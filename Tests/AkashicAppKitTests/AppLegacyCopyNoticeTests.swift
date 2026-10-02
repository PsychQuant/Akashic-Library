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
/// ~~**work 的拷貝讓 index 重建撞重複**（兩份共用 citekey 或 id，#705 的誠實邊界），那是 index 的事（另案）。~~ → **#709 起不成立**：index 重建
/// 以 `entities/` 那份為準、略過 legacy 拷貝，work 與 person 一樣動作成功（`testAWorkEditThatLeavesTheLegacyCopySucceedsWithANotice`，#709 R3 verify）。
/// 「留下拷貝之後才失敗」的各格仍用「index 目錄唯讀」造出一個與重複無關、確定會發生的重建失敗——不論 index 怎麼處理兩份並存，那些測試都成立。
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
        XCTAssertTrue(notice.headline.contains(LegacyCopyLeft.explanation), "這件事是什麼的說明與 CLI／MCP 報告同一份（標題本身是一般說明文字，R1 verify）")

        XCTAssertTrue(try onDisk(p.id).contains("resolution-confirmed"), "verdict 寫進 entities/")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.personURL(key: p.key).path), "legacy 那份還在——所以才要列")
        let promoted = try XCTUnwrap(try store.load().entries.first { $0.citekey == e.citekey })
        XCTAssertEqual(promoted.authors, [.key(p.key)], "作者位歸戶了")
    }

    /// 範圍本身（work 那一半）：寫入回傳、提示列出——動作的成敗只看 `body` 之後的步驟。端到端見下一個測試。
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

    /// #709 R3 verify（requirements 席）：work 的端到端成功。`AppState.mutate` 寫了、legacy 拷貝刪不掉，之後的 index 重建以 `entities/` 那份為準、
    /// 略過 legacy 拷貝——動作成功，提示列出要清的檔，清單只看到 entities/ 那一份（App 的讀取視圖）。#709 之前這一格擲錯（兩份共用 citekey 撞 UNIQUE）。
    func testAWorkEditThatLeavesTheLegacyCopySucceedsWithANotice() throws {
        let e = try writeLegacyWork(work())
        commitAll()
        try lock(store.entriesDir)
        let state = try makeState()

        XCTAssertNoThrow(try state.addTag(citekey: e.citekey, tag: "x"), "寫了、index 重建成功——不是失敗")

        XCTAssertEqual(state.legacyCopyNotice?.items.map(\.key), [e.citekey], "要清的 legacy 檔列在提示裡")
        XCTAssertEqual(state.legacyCopyNotice?.items.map(\.legacyFile), ["entries/\(e.citekey).yaml"])
        XCTAssertTrue(try onDisk(e.id).contains("- x"), "它寫了")
        XCTAssertEqual(state.entries.filter { $0.citekey == e.citekey }.count, 1, "App 清單只列 entities/ 那一份")
        XCTAssertEqual(state.entries.first { $0.citekey == e.citekey }?.akashic.tags, ["x"])
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

    /// 寫進去的那份（`entities/<id>.yaml`）不見了——git 還原、手動清理、別的工具：legacy 檔成了唯一一份，這一列的指示「刪掉 legacy 那份」
    /// 會刪掉唯一的拷貝，所以兩個檔都在才保留（#708 R1 verify 第 11 列）。
    func testARowIsDroppedWhenTheWrittenCopyIsGoneSoTheInstructionNeverDeletesTheOnlyCopy() throws {
        var e = try writeLegacyWork(work())
        commitAll()
        try lock(store.entriesDir)
        let state = try makeState()
        e.akashic.tags = ["x"]
        _ = try state.recordingLegacyCopies { try state.store.writeEntry(e) }
        XCTAssertNotNil(state.legacyCopyNotice)
        try state.load()
        XCTAssertNotNil(state.legacyCopyNotice, "兩個檔都在：load 不拿掉")

        try FileManager.default.removeItem(at: store.entityURL(id: e.id))   // 寫進去的那份不見了
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.entriesDir.appendingPathComponent("\(e.citekey).yaml").path), "前提：legacy 那份還在")
        try state.load()
        XCTAssertNil(state.legacyCopyNotice, "legacy 檔是唯一的一份了，不得再叫使用者刪它")
    }

    /// 切到目前已經是的那個 store：legacy 檔還在磁碟上，提示是使用者知道要清哪個檔的唯一線索，不清（#708 R1 verify 第 19 列）。
    /// 切到另一個 store 才清（`testSwitchingFilesClearsTheNotice`）。
    func testSwitchingToTheStoreThatIsAlreadyActiveKeepsTheNotice() throws {
        var e = try writeLegacyWork(work())
        commitAll()
        try lock(store.entriesDir)
        let home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        // 同一個目錄，以不同寫法登記（尾端斜線、`.` 路段）：標準化之後仍是同一個 store
        try AkashicConfig(files: ["self": root.path + "/./"]).write(to: home.appendingPathComponent("config.yaml"))
        let state = try makeState()
        e.akashic.tags = ["x"]
        _ = try state.recordingLegacyCopies { try state.store.writeEntry(e) }
        let before = try XCTUnwrap(state.legacyCopyNotice)

        try state.switchFile(key: "self")

        XCTAssertEqual(state.legacyCopyNotice, before, "同一個 store：提示原樣保留")
    }

    /// 標題是一般說明文字，不是 CLI／MCP 的鍵名；這件事是什麼的一句說明與 CLI／MCP 同一份（#708 R1 verify 第 12／32 列）。
    /// 同一個動作另有錯誤時，標題只說「請依那個錯誤的訊息處理」，**不**說那是別的原因、與這份拷貝無關——後續寫入被 #631 拒絕的原因
    /// 正是這份拷貝（`laterWriteRefused`，#708 R2 verify 第 1／34 列；R3 verify 第 25 列指出這段註解仍寫著 R2 拿掉的那句）。
    func testTheHeadlineIsPlainWordingNotTheJsonKeyName() {
        let left = LegacyCopyLeft(kind: .person, key: "cheng-che", id: UUID(), legacyFile: "people/cheng-che.yaml", detail: "d")
        let notice = LegacyCopyNotice(items: [left], root: URL(fileURLWithPath: "/tmp/store"))
        XCTAssertFalse(notice.headline.contains("writtenWithLegacyCopy"), "GUI 使用者不該看到 API 的鍵名：\(notice.headline)")
        XCTAssertTrue(notice.headline.contains(LegacyCopyLeft.explanation), "這件事是什麼的說明與 CLI／MCP 同一份")
        XCTAssertTrue(notice.headline.contains("1 筆"), notice.headline)
        XCTAssertTrue(notice.headline.contains("同一個動作若另有錯誤，請依那個錯誤的訊息處理"), notice.headline)
        XCTAssertFalse(notice.headline.contains("與這份拷貝無關") || notice.headline.contains("別的原因"),
                       "後續的寫入被拒絕的原因正是這份拷貝（laterWriteRefused）——標題不得否認它：\(notice.headline)")
        XCTAssertTrue(LegacyCopyLeft.reportLines([left]).first?.contains(LegacyCopyLeft.explanation) == true, "CLI／MCP 的標題仍帶同一句")
    }

    /// #708 R2 verify 第 1／34 列：`laterWriteRefused`（同一個操作之後對同一筆的寫入被 #631 拒絕、**原因就是這份拷貝**）時，標題與那一列都要說這件事，
    /// 而且與 CLI／MCP 同一句（`laterWriteRefusedNote`）；沒有標的列、以及全部沒標時的標題不得出現它。
    func testALaterWriteRefusedLeftoverIsSaidInTheHeadlineAndTheRowNotDeniedAsUnrelated() {
        var refused = LegacyCopyLeft(kind: .person, key: "cheng-che", id: UUID(), legacyFile: "people/cheng-che.yaml", detail: "d")
        refused.laterWriteRefused = true
        let plain = LegacyCopyLeft(kind: .person, key: "someone", id: UUID(), legacyFile: "people/someone.yaml", detail: "d")
        let notice = LegacyCopyNotice(items: [refused, plain], root: URL(fileURLWithPath: "/tmp/store"))

        XCTAssertTrue(notice.headline.contains("其中 1 筆：\(LegacyCopyLeft.laterWriteRefusedNote)"), "標題說出後續寫入沒套用：\(notice.headline)")
        XCTAssertFalse(notice.headline.contains("與這份拷貝無關") || notice.headline.contains("別的原因"), notice.headline)
        let details = notice.rows.map(\.displayDetail)
        XCTAssertEqual(details[0], refused.message + "；" + LegacyCopyLeft.laterWriteRefusedNote, "標了的那一列帶附句，與 reportLines 同一句")
        XCTAssertEqual(details[1], plain.message, "沒標的列不帶")
        XCTAssertTrue(LegacyCopyLeft.reportLines([refused]).joined().contains(LegacyCopyLeft.laterWriteRefusedNote), "CLI／MCP 的附句是同一份")

        let none = LegacyCopyNotice(items: [plain], root: URL(fileURLWithPath: "/tmp/store"))
        XCTAssertFalse(none.headline.contains(LegacyCopyLeft.laterWriteRefusedNote), "全部沒標時標題不提：\(none.headline)")
    }

    /// 每一列顯示 legacy 檔的完整路徑（store root ＋ 相對路徑），使用者不必自己知道 store 在哪裡才刪得掉（#708 R1 verify 第 12／32 列）。
    func testEachRowShowsTheFullPathOfTheLegacyFile() {
        let left = LegacyCopyLeft(kind: .person, key: "cheng-che", id: UUID(), legacyFile: "people/cheng-che.yaml", detail: "d")
        let notice = LegacyCopyNotice(items: [left], root: URL(fileURLWithPath: "/Volumes/Data/my store"))
        XCTAssertEqual(notice.rows.map(\.displayLegacyPath), ["/Volumes/Data/my store/people/cheng-che.yaml"])
        XCTAssertEqual(notice.rows.map(\.displayLegacyFile), ["people/cheng-che.yaml"], "相對路徑仍在")
    }

    /// 同一個 legacy 檔再次留下：留最新的那一筆（key 與說明），原位置不動。
    func testAddingTheSameLeftoverAgainKeepsTheNewestAndItsPosition() {
        let id = UUID()
        let other = LegacyCopyLeft(kind: .person, key: "other", id: UUID(), legacyFile: "people/other.yaml", detail: "o")
        let first = LegacyCopyLeft(kind: .work, key: "old2025key", id: id, legacyFile: "entries/old2025key.yaml", detail: "第一次")
        let again = LegacyCopyLeft(kind: .work, key: "new2025key", id: id, legacyFile: "entries/old2025key.yaml", detail: "第二次")
        let notice = LegacyCopyNotice(items: [first, other], root: URL(fileURLWithPath: "/tmp/s")).adding([again])
        XCTAssertEqual(notice.items, [again, other], "同一筆（kind、id、legacy 檔）只留一次、留最新的，位置不變")
    }

    // MARK: - 源碼守衛：App 的每一個寫入者都在範圍裡

    /// App 沒有 CLI 進入點或 MCP 分派那樣的單一出口，範圍開在各寫入點——新的寫入點忘了開，同一件事就回到「操作失敗」。
    /// 掃 `AkashicAppKit` 與 `AkashicApp/Sources` **遞迴**底下的每個 `.swift`：每一處 `.writeEntry`／`.writePerson`／`.renameEntry`／
    /// `.renamePerson`（含取函式值、跨行）都要在某個 `recordingLegacyCopies {` 的大括號裡。掃描器的細節與誠實邊界見
    /// `LegacyCopyScopeScanner`（#708 R1 verify 第 13／20 列補上遞迴、字串與註解、函式值）。
    func testEveryAppStoreWriteIsInsideTheScope() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var offenders: [String] = []
        var found = 0
        var files = 0
        for dir in ["Sources/AkashicAppKit", "AkashicApp/Sources"] {
            let base = repo.appendingPathComponent(dir)
            for rel in LegacyCopyScopeScanner.swiftFiles(under: base) {
                files += 1
                let source = try String(contentsOf: base.appendingPathComponent(rel), encoding: .utf8)
                let scan = LegacyCopyScopeScanner.scan(source, name: "\(dir)/\(rel)")
                found += scan.found
                offenders += scan.offenders
            }
        }
        XCTAssertGreaterThanOrEqual(files, 10, "空掃描不是通過：掃到的檔太少（\(files)）")
        XCTAssertGreaterThanOrEqual(found, 6, "空掃描不是通過：mutate、rename、accept 兩處、脫鉤、拿掉已刪除的來源")
        XCTAssertEqual(offenders, [], "App 的寫入點不在 recordingLegacyCopies 的範圍裡（#708）：\n" + offenders.joined(separator: "\n"))
    }

    // MARK: - 掃描器本身（#708 R1 verify 第 13／20 列）

    private func scan(_ code: String) -> LegacyCopyScopeScanner.Scan { LegacyCopyScopeScanner.scan(code, name: "T") }

    /// 範圍內的寫入算範圍內，範圍外的算違規；括號配對正確，巢狀不打亂它。
    func testTheScannerFindsTheMatchingBraceAndSeparatesInsideFromOutside() {
        let r = scan("""
            func a() { try recordingLegacyCopies { x { y } ; _ = try store.writeEntry(e) } }
            func b() { _ = try store.writePerson(p) }
            """)
        XCTAssertEqual(r.found, 2)
        XCTAssertEqual(r.offenders, ["T:2 .writePerson"])
    }

    /// 字串字面值裡的 `//`（URL）曾把同一行後面的 `}` 一起砍掉，讓範圍多延伸一段、把範圍外的寫入判成範圍內（漏報）。
    func testAUrlInAStringDoesNotCutTheRestOfTheLine() {
        let r = scan("""
            func a() { try recordingLegacyCopies { let u = "https://example.test/a"; _ = try store.writeEntry(e) } ; store.writePerson(p) }
            """)
        XCTAssertEqual(r.found, 2)
        XCTAssertEqual(r.offenders, ["T:1 .writePerson"], "範圍在 `}` 就結束了，後面的寫入在範圍外")
    }

    /// 字串裡的裸 `{`／`}` 曾讓深度失衡：範圍裡的字串含 `}` 會讓範圍提早結束（範圍裡的寫入被判成範圍外），範圍外的字串含 `{` 會讓之後的範圍延伸。
    func testBracesInsideStringsDoNotUnbalanceTheScope() {
        let r = scan("""
            func a() { try recordingLegacyCopies { let s = "}"; _ = try store.writeEntry(e) } }
            func b() { let t = "{"; _ = try store.writePerson(p) }
            func c() { try recordingLegacyCopies { _ = try store.renameEntry(a, b) } }
            """)
        XCTAssertEqual(r.found, 3)
        XCTAssertEqual(r.offenders, ["T:2 .writePerson"], "字串裡的大括號不算：第一行的範圍到最後一個 `}` 才結束")
    }

    /// 區塊註解不是程式碼：裡面的寫入不算、裡面的 `recordingLegacyCopies {` 不開範圍；巢狀的區塊註解整段略過。
    func testBlockCommentsAreNotCode() {
        let r = scan("""
            /* store.writeEntry(e) /* nested */ store.writePerson(p) */
            /* recordingLegacyCopies { */ func c() { _ = try store.renameEntry(a, b) }
            """)
        XCTAssertEqual(r.found, 1, "只剩註解外的 renameEntry")
        XCTAssertEqual(r.offenders, ["T:2 .renameEntry"], "註解裡的 recordingLegacyCopies { 不開範圍")
    }

    /// 行註解不是程式碼：整行註解與行尾註解裡的寫入不算。
    func testLineCommentsAreNotCode() {
        let r = scan("// store.writeEntry(e)\nfunc a() {} // store.writePerson(p)\n/// 文件註解 store.renameEntry(a, b)\n")
        XCTAssertEqual(r.found, 0)
    }

    /// 取函式值、跨行寫法：只認 `.writeEntry(` 時看不到。
    func testAFunctionValueAndALineBreakBeforeTheDotAreSeen() {
        let r = scan("""
            func a() { let w = store.writeEntry; try w(e) }
            func b() {
                try store
                    .writePerson(p)
            }
            func c() { try recordingLegacyCopies { let w = store.writeEntry; try w(e) } }
            """)
        XCTAssertEqual(r.found, 3)
        XCTAssertEqual(r.offenders, ["T:1 .writeEntry", "T:4 .writePerson"])
    }

    /// 名字只是前綴的方法不是寫入點（`writeEntryX`）；沒有點的定義（`func writeEntry`）也不是。
    func testOnlyTheExactMethodNamesCount() {
        let r = scan("func writeEntry() {}\nstore.writeEntryX(e)\nstore.rewriteEntry(e)\n")
        XCTAssertEqual(r.found, 0)
    }

    /// 多行字串、raw 字串、字串內插（內插裡可以有字串與括號）：內容全部空白掉，不影響範圍判定；字串之後的程式碼照常掃。
    func testMultiLineRawAndInterpolatedStringsAreBlanked() {
        let r = scan(##"""
            func a() { try recordingLegacyCopies {
                let m = """
                  store.writePerson(p) { "
                  """
                let r = #"raw "quoted" { store.writePerson(p)"#
                let i = "x \(foo("a)b", 1) { store.writePerson(p) \(nested)) y"
                _ = try store.writeEntry(e)
            } }
            func b() { _ = try store.renamePerson(a, b) }
            """##)
        XCTAssertEqual(r.found, 2, "字串裡的 writePerson 都不算")
        XCTAssertEqual(r.offenders, ["T:9 .renamePerson"])
    }

    /// 遞迴列出：子目錄裡的檔也在。初版 `contentsOfDirectory` 只讀第一層，日後 App 源碼開子目錄就整批不在掃描內。
    func testSwiftFilesAreListedRecursively() throws {
        let dir = root.appendingPathComponent("scan-fixture")
        let sub = dir.appendingPathComponent("Views/Deep")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "// a".write(to: dir.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        try "// b".write(to: sub.appendingPathComponent("B.swift"), atomically: true, encoding: .utf8)
        try "x".write(to: sub.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(LegacyCopyScopeScanner.swiftFiles(under: dir), ["A.swift", "Views/Deep/B.swift"])
        XCTAssertEqual(LegacyCopyScopeScanner.swiftFiles(under: dir.appendingPathComponent("missing")), [], "目錄不存在回空陣列，由呼叫端的下限擋下")
    }
}
