import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicAppKit

/// #708：App 的寫入寫進 `entities/`、而 #631 搬移後的 legacy 拷貝刪不掉時，動作算**成功**，另以非阻斷的提示
/// （`AppState.legacyCopyNotice`，側欄的一個 Section）列出要清的 legacy 檔——與 CLI／MCP／import-zotero 的 `writtenWithLegacyCopy`
/// （#705）同一個說法。之後的步驟才真的失敗時，兩樣都給：提示照樣列出拷貝，擲出的是帶著它們的 `LegacyCopyLeftBeforeFailure`。
///
/// 刪不掉的造法同 `LegacyCopyLedgerTests`：legacy 檔受 git 追蹤、乾淨（寫入時會搬移它），然後讓它所在的目錄唯讀。
///
/// **work 的拷貝讓 index 重建撞重複**（兩份共用 citekey 或 id，#705 的誠實邊界），那是 index 的事（另案）。所以「動作成功」的端到端情境
/// 用 person 的拷貝（people 表對重複 key 留第一筆，重建照常）；work 的各寫入點用「index 目錄唯讀」造出一個與重複無關、確定會發生的
/// 重建失敗——不論 index 日後怎麼處理兩份並存，這些測試都成立。
final class AppLegacyCopyNoticeTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-708-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        git(["init", "-q"])
        try "sources/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        XCTAssertTrue(store.usesEntitiesLayout, "前提：entities 佈局——legacy 目錄在這裡是殘留")
        for dir in [store.entriesDir, store.peopleDir, indexDir!] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        for dir in [store.entriesDir, store.peopleDir, indexDir!] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        }
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - 夾具

    /// keyless store 的 index 住在 store root 內（`.akashic/`）。
    private var indexDir: URL? { store?.indexURL.deletingLastPathComponent() }

    /// `AKASHIC_HOME` 指進 fixture：registry 與 index 都不碰使用者的家目錄。
    private func makeState() throws -> AppState {
        let state = AppState(root: root, key: nil,
                             environment: ["AKASHIC_HOME": root.appendingPathComponent("home").path])
        try state.load()
        return state
    }

    /// 剝除 GIT_*（#234）：從 git hook 裡跑測試時，hook 環境帶著 GIT_DIR，`-C` 擋不住它。
    private static var scrubbedGitEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    }

    @discardableResult
    private func git(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root.path, "-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false"] + args
        p.environment = Self.scrubbedGitEnvironment
        p.standardOutput = Pipe(); p.standardError = Pipe()
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    private func commitAll(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(git(["add", "-A"]), 0, "git add", file: file, line: line)
        XCTAssertEqual(git(["commit", "-q", "--allow-empty", "-m", "fixture"]), 0, "git commit", file: file, line: line)
    }

    /// 讓 `dir` 唯讀：裡面的檔刪不掉、也建不了新檔。以 root 執行時權限擋不住，那時造不出這個狀態——skip，不假綠。
    private func lock(_ dir: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        let probe = dir.appendingPathComponent("probe-\(UUID().uuidString)")
        if FileManager.default.createFile(atPath: probe.path, contents: Data()) {
            try? FileManager.default.removeItem(at: probe)
            throw XCTSkip("這個環境的權限擋不住刪檔（以 root 執行？），造不出「寫完之後刪 legacy 失敗」")
        }
    }

    /// legacy 佈局的一筆 work：只有 `entries/<citekey>.yaml` 一份（寫入時會搬移它）。commit 與上鎖由呼叫端做。
    @discardableResult
    private func writeLegacyWork(_ e: Entry) throws -> Entry {
        try EntryYAML.encode(e).write(to: store.entriesDir.appendingPathComponent("\(e.citekey).yaml"),
                                      atomically: true, encoding: .utf8)
        return e
    }

    private func work(_ citekey: String = "cheng2025identifiability") -> Entry {
        Entry(id: UUID(), citekey: citekey, type: .periodicalArticle,
              title: "Identifiability of polychoric models", authors: [.literal("Che Cheng")], date: "2025")
    }

    private func onDisk(_ id: UUID) throws -> String {
        try String(contentsOf: store.entityURL(id: id), encoding: .utf8)
    }

    // MARK: - 成功：動作算成功，提示列出要清的檔

    /// 裁決台的 accept：entry 寫進 entities/，person 的 verdict 寫進 entities/、而 legacy 的 `people/<key>.yaml` 刪不掉。
    /// person 的兩份不擋 index 重建——這是端到端「動作成功」的那一格。
    func testAnAcceptThatLeavesTheLegacyPersonCopySucceedsWithANotice() throws {
        let e = work()
        try store.writeEntry(e)   // entities 佈局：沒有 legacy 可搬
        let p = Person(key: "cheng-che", names: PersonNames(variant: ["Che Cheng"]))
        try PersonYAML.encode(p).write(to: store.personURL(key: p.key), atomically: true, encoding: .utf8)
        commitAll()
        try lock(store.peopleDir)
        let state = try makeState()
        let model = PeopleResolveModel(state: state)
        let candidate = try XCTUnwrap(model.candidates.first { $0.citekey == e.citekey && $0.personKey == p.key },
                                      "前提：提名出這個配對：\(model.candidates.map(\.pinnedID))")

        XCTAssertNoThrow(try model.accept(candidate), "寫了——不是失敗")

        let notice = try XCTUnwrap(state.legacyCopyNotice, "留下的拷貝要列在提示裡")
        XCTAssertEqual(notice.items.count, 1, "\(notice.items)")
        let left = try XCTUnwrap(notice.items.first)
        XCTAssertEqual(left.kind, .person)
        XCTAssertEqual(left.key, p.key)
        XCTAssertEqual(left.id, p.id)
        XCTAssertEqual(left.legacyFile, "people/cheng-che.yaml")
        XCTAssertEqual(notice.rows.map(\.displayRecord), ["person「cheng-che」"])
        XCTAssertEqual(notice.rows.map(\.displayLegacyFile), ["people/cheng-che.yaml"])
        XCTAssertEqual(notice.rows.map(\.writtenFile), ["entities/\(p.id.uuidString).yaml"])
        XCTAssertEqual(notice.rows.map(\.displayDetail), [left.message], "每一列的說明與 CLI／MCP 同一句")
        XCTAssertEqual(notice.headline, LegacyCopyLeft.reportLines([left]).first, "說明與 CLI／MCP 報告的第一行同一句")

        XCTAssertTrue(try onDisk(p.id).contains("resolution-confirmed"), "verdict 寫進 entities/")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.personURL(key: p.key).path), "legacy 那份還在——所以才要列")
        let promoted = try XCTUnwrap(try store.load().entries.first { $0.citekey == e.citekey })
        XCTAssertEqual(promoted.authors, [.key(p.key)], "作者位歸戶了")
    }

    /// 範圍本身（work 那一半）：寫入回傳、提示列出——動作的成敗只看 `body` 之後的步驟。work 的端到端成功要等 index 容忍兩份並存（另案）。
    func testTheScopeTurnsAWorkLeftoverIntoANoticeInsteadOfAnError() throws {
        var e = try writeLegacyWork(work())
        commitAll()
        try lock(store.entriesDir)
        let state = try makeState()
        e.akashic.tags = ["x"]

        XCTAssertNoThrow(try state.recordingLegacyCopies { try state.store.writeEntry(e) })

        let left = try XCTUnwrap(state.legacyCopyNotice?.items.first)
        XCTAssertEqual(left.kind, .work)
        XCTAssertEqual(left.key, e.citekey)
        XCTAssertEqual(left.legacyFile, "entries/\(e.citekey).yaml")
        XCTAssertTrue(try onDisk(e.id).contains("- x"))
    }

    // MARK: - 留下拷貝之後才真的失敗：兩樣都給

    /// 衍生層編輯（`AppState.mutate`）：寫了、legacy 拷貝刪不掉，之後 index 重建失敗。
    func testATagEditWhoseReindexFailsAfterALeftoverShowsBoth() throws {
        let e = try writeLegacyWork(work())
        commitAll()
        try lock(store.entriesDir)
        let state = try makeState()
        try lock(try XCTUnwrap(indexDir))   // 與兩份並存無關、確定會發生的重建失敗

        XCTAssertThrowsError(try state.addTag(citekey: e.citekey, tag: "x")) { error in
            assertCarriesTheLeftover(error, kind: .work, key: e.citekey)
        }
        XCTAssertEqual(state.legacyCopyNotice?.items.map(\.key), [e.citekey], "失敗之後提示照樣列出要清的檔")
        XCTAssertTrue(try onDisk(e.id).contains("- x"), "它寫了")
    }

    /// 改名：範圍只包 `renameEntry`；之後的重建失敗照舊是 `renamedButReloadFailed`（它本身就說改名已寫入、帶著報告——view 靠它顯示回執），
    /// 留下的舊 citekey 那份 legacy 拷貝在提示裡。
    func testARenameThatLeavesTheOldLegacyCopyKeepsItsReceiptAndListsTheCopy() throws {
        let e = try writeLegacyWork(work())
        commitAll()
        try lock(store.entriesDir)
        let state = try makeState()
        try lock(try XCTUnwrap(indexDir))

        XCTAssertThrowsError(try state.rename(from: e.citekey, to: "cheng2025renamed")) { error in
            guard case AppStateError.renamedButReloadFailed = error else {
                return XCTFail("部分成功的回執不得被包掉：\(error)")
            }
        }
        let left = try XCTUnwrap(state.legacyCopyNotice?.items.first)
        XCTAssertEqual(left.key, "cheng2025renamed", "報告具名的是現在的鍵")
        XCTAssertEqual(left.legacyFile, "entries/\(e.citekey).yaml", "legacy 那份是改名前的 citekey")
        XCTAssertTrue(try onDisk(e.id).contains("cheng2025renamed"), "改名寫了")
    }

    /// 裁決台的「轉純 Akashic」：同上。
    func testDetachingAnOrphanWhoseReindexFailsAfterALeftoverShowsBoth() throws {
        var e = work()
        e.provenance = Provenance(zoteroKey: "K", zoteroVersion: 1, orphanedAt: Date(timeIntervalSince1970: 1))
        try writeLegacyWork(e)
        commitAll()
        try lock(store.entriesDir)
        let state = try makeState()
        try lock(try XCTUnwrap(indexDir))

        XCTAssertThrowsError(try OrphanModel(state: state).resolve(citekey: e.citekey, action: .detachFromZotero)) { error in
            assertCarriesTheLeftover(error, kind: .work, key: e.citekey)
        }
        XCTAssertEqual(state.legacyCopyNotice?.items.map(\.key), [e.citekey])
        XCTAssertFalse(try onDisk(e.id).contains("zotero"), "脫鉤寫了")
    }

    private func assertCarriesTheLeftover(_ error: Error, kind: LegacyCopyLeft.Kind, key: String,
                                          file: StaticString = #filePath, line: UInt = #line) {
        guard let carried = error as? LegacyCopyLeftBeforeFailure else {
            return XCTFail("應帶著寫了的那一筆：\(error)", file: file, line: line)
        }
        XCTAssertEqual(carried.written.map(\.kind), [kind], file: file, line: line)
        XCTAssertEqual(carried.written.map(\.key), [key], file: file, line: line)
        if case StoreIOError.legacyCopyNotRemoved = carried.underlying {
            XCTFail("失敗的原因不是留下的拷貝：\(carried.underlying)", file: file, line: line)
        }
        // 失敗提示先說寫了什麼、再說錯誤（與 CLI／MCP 同一個順序）
        let shown = displaySafeErrorMultiline(error)
        XCTAssertTrue(shown.hasPrefix("writtenWithLegacyCopy（"), shown, file: file, line: line)
    }

    // MARK: - 提示的生命週期

    func testTheNoticeDropsCopiesThatAreGoneAndCanBeDismissed() throws {
        var e = try writeLegacyWork(work())
        commitAll()
        try lock(store.entriesDir)
        let state = try makeState()
        e.akashic.tags = ["x"]
        _ = try state.recordingLegacyCopies { try state.store.writeEntry(e) }
        try state.load()
        XCTAssertNotNil(state.legacyCopyNotice, "legacy 檔還在：load 不拿掉")

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.entriesDir.path)
        try FileManager.default.removeItem(at: store.entriesDir.appendingPathComponent("\(e.citekey).yaml"))
        try state.load()
        XCTAssertNil(state.legacyCopyNotice, "使用者刪掉 legacy 那份之後，提示不再叫他去清")

        // 收起：只動提示
        try writeLegacyWork(work("olsson1979maximum"))
        commitAll()
        try lock(store.entriesDir)
        try state.load()
        var other = try XCTUnwrap(state.entries.first { $0.citekey == "olsson1979maximum" })
        other.akashic.tags = ["y"]
        _ = try state.recordingLegacyCopies { try state.store.writeEntry(other) }
        XCTAssertNotNil(state.legacyCopyNotice)
        state.dismissLegacyCopyNotice()
        XCTAssertNil(state.legacyCopyNotice)
    }

    /// 切換檔案：提示列的是舊 universe 的路徑，一律清空。另一個 store 在**同一個相對路徑**也有檔時，load 的「拿掉已經不在的」救不了它——
    /// 那一列會在新 universe 裡指著一個不相干的檔。
    func testSwitchingFilesClearsTheNotice() throws {
        var e = try writeLegacyWork(work())
        commitAll()
        try lock(store.entriesDir)
        let home = root.appendingPathComponent("home")
        let other = root.appendingPathComponent("other")
        try LibraryStore(root: other, key: nil, environment: [:]).ensureLayout()
        try FileManager.default.createDirectory(at: other.appendingPathComponent("entries"), withIntermediateDirectories: true)
        try EntryYAML.encode(work()).write(to: other.appendingPathComponent("entries/\(e.citekey).yaml"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try AkashicConfig(files: ["other": other.path]).write(to: home.appendingPathComponent("config.yaml"))
        let state = try makeState()
        e.akashic.tags = ["x"]
        _ = try state.recordingLegacyCopies { try state.store.writeEntry(e) }
        XCTAssertNotNil(state.legacyCopyNotice)

        try state.switchFile(key: "other")
        XCTAssertNil(state.legacyCopyNotice)
    }

    // MARK: - 源碼守衛：App 的每一個寫入者都在範圍裡

    /// App 沒有 CLI 進入點或 MCP 分派那樣的單一出口，範圍開在各寫入點——新的寫入點忘了開，同一件事就回到「操作失敗」。
    /// 掃 `AkashicAppKit` 與 `AkashicApp/Sources`：每一個 `writeEntry(`／`writePerson(`／`renameEntry(`／`renamePerson(` 呼叫都要在某個
    /// `recordingLegacyCopies {` 的大括號裡（字面上的包含——寫入搬進另一個函式時要在那個函式裡開範圍）。
    func testEveryAppStoreWriteIsInsideTheScope() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let writes = [".writeEntry(", ".writePerson(", ".renameEntry(", ".renamePerson("]
        var offenders: [String] = []
        var found = 0
        for dir in ["Sources/AkashicAppKit", "AkashicApp/Sources"] {
            let names = try FileManager.default.contentsOfDirectory(atPath: repo.appendingPathComponent(dir).path)
            for name in names.sorted() where name.hasSuffix(".swift") {
                let rel = "\(dir)/\(name)"
                let code = try String(contentsOf: repo.appendingPathComponent(rel), encoding: .utf8)
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { line -> String in
                        guard let r = line.range(of: "//") else { return String(line) }
                        return String(line[..<r.lowerBound])
                    }.joined(separator: "\n")
                let scopes = Self.braceRanges(in: code, after: "recordingLegacyCopies {")
                for needle in writes {
                    var from = code.startIndex
                    while let hit = code.range(of: needle, range: from..<code.endIndex) {
                        found += 1
                        if !scopes.contains(where: { $0.contains(hit.lowerBound) }) {
                            let line = code[..<hit.lowerBound].filter { $0 == "\n" }.count + 1
                            offenders.append("\(rel):\(line) \(needle)")
                        }
                        from = hit.upperBound
                    }
                }
            }
        }
        XCTAssertGreaterThanOrEqual(found, 6, "空掃描不是通過：mutate、rename、accept 兩處、脫鉤、拿掉已刪除的來源")
        XCTAssertEqual(offenders, [], "App 的寫入點不在 recordingLegacyCopies 的範圍裡（#708）：\n" + offenders.joined(separator: "\n"))
    }

    /// `marker` 之後那個 `{` 到它配對的 `}`（含）。字串字面裡的大括號在 App 源碼裡都成對（`\u{…}`、閉包），不另處理。
    static func braceRanges(in code: String, after marker: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var from = code.startIndex
        while let hit = code.range(of: marker, range: from..<code.endIndex) {
            let open = code.index(before: hit.upperBound)   // marker 以 `{` 結尾
            var depth = 0
            var i = open
            while i < code.endIndex {
                if code[i] == "{" { depth += 1 }
                if code[i] == "}" { depth -= 1; if depth == 0 { break } }
                i = code.index(after: i)
            }
            if i < code.endIndex { out.append(open..<code.index(after: i)) }
            from = hit.upperBound
        }
        return out
    }

    /// 守衛的掃描器本身：配對到正確的右括號，巢狀與字串裡的 `\u{…}` 不打亂它。
    func testTheBraceScannerFindsTheMatchingBrace() {
        let code = "a { b { \"\\u{200B}\" } } c recordingLegacyCopies { x { y } z } w .writeEntry("
        let ranges = Self.braceRanges(in: code, after: "recordingLegacyCopies {")
        XCTAssertEqual(ranges.map { String(code[$0]) }, ["{ x { y } z }"])
        XCTAssertFalse(ranges[0].contains(code.range(of: ".writeEntry(")!.lowerBound))
    }
}
