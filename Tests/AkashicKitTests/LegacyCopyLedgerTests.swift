import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #705：內容寫進 `entities/`、但 #631 搬移後的 legacy 拷貝刪不掉的那一筆——**寫了**，記在成功那一側。
///
/// 使用者 2026-09-30 裁決 (a)：各寫入者統一，這一筆列在回報面的 `writtenWithLegacyCopy`，不算失敗、不進任何失敗清單。
/// 機制是一個收集範圍（`LegacyCopyLedger.collecting`）：範圍內 `writeEntry`／`writePerson` 記下這一筆、照常回傳；範圍外照舊擲
/// `legacyCopyNotRemoved`（#702）——沒有人收集的地方不會安靜吞掉它。
///
/// 刪不掉的造法同 #702 R1 verify 的測試：legacy 檔受 git 追蹤、乾淨（寫入時會搬移它），然後讓它所在的目錄唯讀。
final class LegacyCopyLedgerTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-705-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try "sources/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        XCTAssertTrue(store.usesEntitiesLayout, "前提：entities 佈局——legacy 目錄在這裡是殘留")
        for dir in [store.entriesDir, store.peopleDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        for dir in [store.entriesDir, store.peopleDir] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        }
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - 夾具

    /// 讓 `dir` 唯讀：裡面的檔刪不掉。以 root 執行時權限擋不住，那時造不出這個狀態——skip，不假綠。
    private func lock(_ dir: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        let probe = dir.appendingPathComponent("probe-\(UUID().uuidString)")
        if FileManager.default.createFile(atPath: probe.path, contents: Data()) {
            try? FileManager.default.removeItem(at: probe)
            throw XCTSkip("這個環境的權限擋不住刪檔（以 root 執行？），造不出「寫完之後刪 legacy 失敗」")
        }
    }

    /// legacy 佈局的一筆 work：只有 `entries/<citekey>.yaml` 一份，受 git 追蹤、乾淨——寫入時會搬移它（#631），而刪除會失敗。
    private func legacyWork() throws -> Entry {
        let e = Entry(id: UUID(), citekey: "cheng2025identifiability", type: .periodicalArticle,
                      title: "Identifiability of polychoric models", authors: [.literal("Che Cheng")], date: "2025")
        try EntryYAML.encode(e).write(to: store.entriesDir.appendingPathComponent("\(e.citekey).yaml"),
                                      atomically: true, encoding: .utf8)
        GitFixture.commitAll(root)
        try lock(store.entriesDir)
        return e
    }

    /// 同上，person：只有 `people/<key>.yaml` 一份。
    private func legacyPerson() throws -> Person {
        let p = Person(key: "cheng-che", names: PersonNames(variant: ["Che Cheng"]))
        try PersonYAML.encode(p).write(to: store.personURL(key: p.key), atomically: true, encoding: .utf8)
        GitFixture.commitAll(root)
        try lock(store.peopleDir)
        return p
    }

    private struct Boom: Error {}

    // MARK: - 範圍外：照舊擲錯

    func testOutsideAnyScopeTheWriteStillThrows() throws {
        var e = try legacyWork()
        e.akashic.tags = ["x"]
        XCTAssertThrowsError(try store.writeEntry(e)) { error in
            guard case StoreIOError.legacyCopyNotRemoved = error else { return XCTFail("應是 legacyCopyNotRemoved：\(error)") }
            let d = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(d.hasPrefix("已寫入 entities/\(e.id.uuidString).yaml"), d)
            XCTAssertTrue(d.contains("entries/\(e.citekey).yaml"), d)
        }
        XCTAssertTrue(try String(contentsOf: store.entityURL(id: e.id), encoding: .utf8).contains("- x"), "擲錯之前已經寫了")
    }

    /// person 那一半走同一個 `removeMovedLegacy`（#702 R2 verify：先前沒有任何測試走到 `writePerson` 這一條）。
    func testOutsideAnyScopeThePersonWriteStillThrows() throws {
        var p = try legacyPerson()
        p.note = "改過"
        XCTAssertThrowsError(try store.writePerson(p)) { error in
            guard case StoreIOError.legacyCopyNotRemoved = error else { return XCTFail("應是 legacyCopyNotRemoved：\(error)") }
            let d = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(d.hasPrefix("已寫入 entities/\(p.id.uuidString).yaml"), d)
            XCTAssertTrue(d.contains("people/\(p.key).yaml"), d)
        }
        XCTAssertTrue(try String(contentsOf: store.entityURL(id: p.id), encoding: .utf8).contains("改過"), "擲錯之前已經寫了")
    }

    /// 刪除時 legacy 檔**已經不在**（別的程序先刪了）：搬移要的終態達成，不是「兩份並存」——範圍外不擲、範圍內不記（#702 R2 verify）。
    /// 權限擋住的刪除（檔案還在）不屬於這一格。
    func testALegacyFileThatIsAlreadyGoneIsNotALeftover() throws {
        let missing = store.entriesDir.appendingPathComponent("gone2025.yaml")
        var enoent: Error?
        XCTAssertThrowsError(try FileManager.default.removeItem(at: missing)) { enoent = $0 }
        XCTAssertTrue(LibraryStore.isNoSuchFile(try XCTUnwrap(enoent)), "前提：刪一個不存在的檔擲的是「沒有這個檔」：\(String(describing: enoent))")
        XCTAssertNoThrow(try store.removeMovedLegacy(missing, kind: .work, key: "gone2025", id: UUID()), "範圍外不擲")
        let (result, written) = LegacyCopyLedger.collecting {
            try store.removeMovedLegacy(missing, kind: .work, key: "gone2025", id: UUID())
        }
        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(written, [], "範圍內不記")

        _ = try legacyWork()   // entries/ 唯讀：裡面的檔刪不掉，錯誤不是「沒有這個檔」
        let locked = store.entriesDir.appendingPathComponent("cheng2025identifiability.yaml")
        var denied: Error?
        XCTAssertThrowsError(try FileManager.default.removeItem(at: locked)) { denied = $0 }
        XCTAssertFalse(LibraryStore.isNoSuchFile(try XCTUnwrap(denied)), "權限擋住的不是「已經不在」：\(String(describing: denied))")
    }

    /// 範圍結束後不殘留：之後範圍外的寫入照舊擲錯（task-local 的綁定只在 body 期間有效）。
    func testTheScopeEndsWithItsBody() throws {
        var e = try legacyWork()
        e.akashic.tags = ["x"]
        let (first, _) = LegacyCopyLedger.collecting { () }
        XCTAssertNoThrow(try first.get())
        XCTAssertThrowsError(try store.writeEntry(e), "範圍外的寫入不得被一個已經結束的範圍收走")
    }

    // MARK: - 範圍內：記下、照常回傳

    func testInsideAScopeTheWorkIsRecordedAsWritten() throws {
        var e = try legacyWork()
        e.akashic.tags = ["x"]
        let (result, written) = LegacyCopyLedger.collecting { try store.writeEntry(e) }
        XCTAssertNoThrow(try result.get(), "寫了，不是失敗")
        XCTAssertEqual(written.count, 1, "\(written)")
        let left = try XCTUnwrap(written.first)
        XCTAssertEqual(left.kind, .work)
        XCTAssertEqual(left.key, e.citekey)
        XCTAssertEqual(left.id, e.id)
        XCTAssertEqual(left.legacyFile, "entries/\(e.citekey).yaml")
        XCTAssertEqual(left.writtenFile, "entities/\(e.id.uuidString).yaml")
        XCTAssertFalse(left.detail.isEmpty, "刪不掉的原因要留著")
        let onDisk = try String(contentsOf: store.entityURL(id: e.id), encoding: .utf8)
        XCTAssertTrue(onDisk.contains("- x"), "內容已經寫進 entities/：\(onDisk)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.entriesDir.appendingPathComponent("\(e.citekey).yaml").path),
                      "前提：legacy 那份還在")
    }

    func testInsideAScopeThePersonIsRecordedAsWritten() throws {
        var p = try legacyPerson()
        p.note = "改過"
        let (result, written) = LegacyCopyLedger.collecting { try store.writePerson(p) }
        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(written.map(\.kind), [.person])
        XCTAssertEqual(written.map(\.key), [p.key])
        XCTAssertEqual(written.map(\.legacyFile), ["people/\(p.key).yaml"])
        let onDisk = try String(contentsOf: store.entityURL(id: p.id), encoding: .utf8)
        XCTAssertTrue(onDisk.contains("改過"), onDisk)
    }

    /// 人可讀的一句話：具名是哪一筆、兩個檔各在哪、這一筆寫了。CLI 的尾段與 MCP 錯誤的附記都印它。
    func testMessageNamesTheRecordAndBothFiles() throws {
        var e = try legacyWork()
        e.akashic.tags = ["x"]
        let (_, written) = LegacyCopyLedger.collecting { try store.writeEntry(e) }
        let message = try XCTUnwrap(written.first?.message)
        XCTAssertTrue(message.contains("work「\(e.citekey)」"), message)
        XCTAssertTrue(message.contains("已寫入 entities/\(e.id.uuidString).yaml"), message)
        XCTAssertTrue(message.contains("entries/\(e.citekey).yaml"), message)
        let lines = LegacyCopyLeft.reportLines(written)
        XCTAssertEqual(lines.count, 2, "\(lines)")
        XCTAssertTrue(lines[0].hasPrefix("writtenWithLegacyCopy"), lines[0])
        XCTAssertTrue(lines[1].contains(message), lines[1])
        XCTAssertEqual(LegacyCopyLeft.reportLines([]), [], "沒有就不印")
    }

    // MARK: - 巢狀

    /// 最內層收下：它自己的報告（例如 `ImportReport`）列出這一筆，外層不重複。
    func testTheInnermostScopeClaimsWhatItCollected() throws {
        var e = try legacyWork()
        e.akashic.tags = ["x"]
        var inner: [LegacyCopyLeft] = []
        let (outerResult, outer) = LegacyCopyLedger.collecting {
            let (r, w) = LegacyCopyLedger.collecting { try store.writeEntry(e) }
            inner = w
            return try r.get()
        }
        XCTAssertNoThrow(try outerResult.get())
        XCTAssertEqual(inner.map(\.key), [e.citekey])
        XCTAssertEqual(outer, [], "每一筆只在一個地方被報告")
    }

    /// 內層的 body 擲錯時沒有報告可以放——收到的轉交外層，錯誤不帶走它們；回傳空陣列（仍然只報一次）。
    func testAFailedInnerScopeHandsOffToTheOuter() throws {
        var e = try legacyWork()
        e.akashic.tags = ["x"]
        var inner: [LegacyCopyLeft] = [LegacyCopyLeft(kind: .person, key: "sentinel", id: UUID(), legacyFile: "", detail: "")]
        var innerFailed = false
        let (_, outer) = LegacyCopyLedger.collecting {
            let (r, w) = LegacyCopyLedger.collecting { () throws -> Void in
                try store.writeEntry(e)
                throw Boom()
            }
            inner = w
            if case .failure = r { innerFailed = true }
        }
        XCTAssertTrue(innerFailed)
        XCTAssertEqual(inner, [], "已轉交外層")
        XCTAssertEqual(outer.map(\.key), [e.citekey], "寫進去的那一筆不能跟著錯誤一起消失")
    }

    // MARK: - 改名（#705 R1 verify 第 4／11 列）

    /// `renameEntry` 先寫新 citekey 那一份、再刪舊 citekey 的 legacy 檔。先前那一步直接 `removeItem`：`entries/` 唯讀時以 Foundation 的
    /// 原始錯誤中止，引用它的 work、verdict、歧異記錄都還沒改寫（同 id 兩份、引用指著舊鍵）。現在走 `removeMovedLegacy`——範圍內記下、
    /// 繼續改寫其餘引用，改名做完。
    func testRenameInAScopeFinishesAndRewritesEveryReference() throws {
        var citing = Entry(id: UUID(), citekey: "yang2026citing", type: .periodicalArticle, title: "Citing", date: "2026")
        citing.akashic.relations.cites = ["cheng2025identifiability"]
        try store.writeEntry(citing)
        let e = try legacyWork()   // commit 全部、entries/ 唯讀
        let (result, written) = LegacyCopyLedger.collecting { try store.renameEntry(from: e.citekey, to: "cheng2025renamed") }
        let report = try result.get()
        XCTAssertEqual(report.relationsRewritten, [citing.citekey], "改名做完：引用它的 work 改寫了")
        XCTAssertEqual(written.map(\.kind), [.work])
        XCTAssertEqual(written.map(\.key), ["cheng2025renamed"], "具名的是這筆記錄現在的 citekey")
        XCTAssertEqual(written.map(\.legacyFile), ["entries/\(e.citekey).yaml"], "留下的是舊 citekey 那一份")
        XCTAssertTrue(try XCTUnwrap(written.first).message.contains("改名前的 citekey"), "兩份共用的是 id，不是 citekey")
        let renamed = try EntryYAML.decode(try String(contentsOf: store.entityURL(id: e.id), encoding: .utf8))
        XCTAssertEqual(renamed.citekey, "cheng2025renamed")
        let rewritten = try EntryYAML.decode(try String(contentsOf: store.entityURL(id: citing.id), encoding: .utf8))
        XCTAssertEqual(rewritten.akashic.relations.cites, ["cheng2025renamed"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.entriesDir.appendingPathComponent("\(e.citekey).yaml").path),
                      "前提：legacy 那份還在")
    }

    /// 範圍外（App）照舊擲，但擲的是「已寫入……」的 `legacyCopyNotRemoved`，不是 Foundation 的原始錯誤——後者讓呼叫端以為這一筆沒寫。
    func testRenameOutsideAScopeSaysItWroteInsteadOfARawError() throws {
        let e = try legacyWork()
        XCTAssertThrowsError(try store.renameEntry(from: e.citekey, to: "cheng2025renamed")) { error in
            guard case StoreIOError.legacyCopyNotRemoved = error else { return XCTFail("應是 legacyCopyNotRemoved：\(error)") }
        }
    }

    /// `renamePerson` 同形：寫 person 之後刪舊 key 的 legacy 檔。範圍內記下、繼續改寫作品的作者邊。
    func testRenamePersonInAScopeFinishesAndRewritesTheAuthorEdges() throws {
        let work = Entry(id: UUID(), citekey: "cheng2026work", type: .periodicalArticle, title: "W",
                         authors: [.key("cheng-che")], date: "2026")
        try store.writeEntry(work)
        let p = try legacyPerson()   // commit 全部、people/ 唯讀
        let (result, written) = LegacyCopyLedger.collecting { try store.renamePerson(from: p.key, to: "cheng-che-renamed") }
        let report = try result.get()
        XCTAssertEqual(report.authorEdgesRewritten, [work.citekey], "改名做完：作者邊改寫了")
        XCTAssertEqual(written.map(\.kind), [.person])
        XCTAssertEqual(written.map(\.key), ["cheng-che-renamed"])
        XCTAssertEqual(written.map(\.legacyFile), ["people/\(p.key).yaml"])
        let rewritten = try EntryYAML.decode(try String(contentsOf: store.entityURL(id: work.id), encoding: .utf8))
        XCTAssertEqual(rewritten.authors, [.key("cheng-che-renamed")])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.personURL(key: p.key).path), "前提：legacy 那份還在")
    }

    // MARK: - 沒有外層範圍時的失敗（#705 R1 verify 第 17／22／30／36 列）

    /// 沒有外層可轉交、body 在留下 legacy 拷貝之後擲錯：`get` 擲出的錯誤帶著寫了的那幾筆，描述先說寫了什麼。
    /// 先前 `ZoteroImporter.run` 與 `LegacyCopyReport.payload` 的 `try result.get()` 把它們丟掉。
    func testWithoutAnOuterScopeAFailureCarriesWhatWasWritten() throws {
        var e = try legacyWork()
        e.akashic.tags = ["x"]
        let (result, written) = LegacyCopyLedger.collecting { () throws -> Void in
            try store.writeEntry(e)
            throw Boom()
        }
        XCTAssertEqual(written.map(\.key), [e.citekey], "沒有外層：原樣回傳給呼叫端")
        XCTAssertThrowsError(try LegacyCopyLedger.get(result, written: written)) { error in
            guard let carried = error as? LegacyCopyLeftBeforeFailure else { return XCTFail("應帶著寫了的那幾筆：\(error)") }
            XCTAssertEqual(carried.written.map(\.key), [e.citekey])
            XCTAssertTrue(carried.underlying is Boom, "原本的錯誤留著")
            let d = carried.errorDescription ?? ""
            XCTAssertTrue(d.hasPrefix("writtenWithLegacyCopy"), "先說寫了什麼：\(d)")
            XCTAssertTrue(d.contains("work「\(e.citekey)」"), d)
        }
        // 已轉交外層（written 空）或沒有收到任何東西：原樣擲原本的錯誤、成功就回結果
        XCTAssertThrowsError(try LegacyCopyLedger.get(Result<Int, Error>.failure(Boom()), written: [])) { XCTAssertTrue($0 is Boom) }
        XCTAssertEqual(try LegacyCopyLedger.get(Result<Int, Error>.success(7), written: []), 7)
    }

    /// 內層成功、之後的步驟才失敗的呼叫端把報告裡的那幾筆交給外層（第 1 列：`akashic_import_zotero` 的 rebuild 失敗）。沒有範圍時回 false。
    func testHandingToTheEnclosingScope() {
        let item = LegacyCopyLeft(kind: .work, key: "k2020", id: UUID(), legacyFile: "entries/k2020.yaml", detail: "d")
        XCTAssertFalse(LegacyCopyLedger.handToEnclosingScope([item]), "沒有範圍：沒有人可交")
        var handed = false
        let (_, outer) = LegacyCopyLedger.collecting { handed = LegacyCopyLedger.handToEnclosingScope([item]) }
        XCTAssertTrue(handed)
        XCTAssertEqual(outer, [item])
    }

    /// 開收集範圍的每個地方都經 `LegacyCopyLedger.get` 取結果；例外只有兩個最外層（CLI 進入點、MCP 分派），它們自己處理 `written`
    /// ——沒有外層可以轉交。一個新的範圍若照舊寫 `try result.get()`，失敗時收到的就消失（第 17／22／30／36 列）。
    func testEveryScopeTakesItsResultThroughGet() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let outermost: [String: String] = [
            "Sources/akashic/CLI.swift": "LegacyCopyReport.printLines(written)",
            "Sources/akashic-mcp/Server.swift": "reportingWrittenWithLegacyCopy(\"Error: 工具分派失敗\", written, isError: true)",
        ]
        var scopes: [String] = [], offenders: [String] = []
        let enumerator = FileManager.default.enumerator(at: repo.appendingPathComponent("Sources"), includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let rel = String(url.path.dropFirst(repo.path.count + 1))
            if rel == "Sources/AkashicStoreIO/LegacyCopyLedger.swift" { continue }
            let code = try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> String in
                    guard let r = line.range(of: "//") else { return String(line) }
                    return String(line[..<r.lowerBound])
                }.joined(separator: "\n")
            guard code.contains("LegacyCopyLedger.collecting") else { continue }
            scopes.append(rel)
            if let needle = outermost[rel] {
                if !code.contains(needle) { offenders.append("\(rel)：最外層要自己處理 written（找不到 \(needle)）") }
            } else if !code.contains("LegacyCopyLedger.get(") {
                offenders.append("\(rel)：開了收集範圍卻沒有經 LegacyCopyLedger.get 取結果")
            }
        }
        XCTAssertEqual(Set(outermost.keys).subtracting(scopes), [], "例外清單過期：\(scopes.sorted())")
        XCTAssertGreaterThanOrEqual(scopes.count, 4, "空掃描不是通過：\(scopes.sorted())")
        XCTAssertEqual(offenders, [], offenders.joined(separator: "\n"))
    }
}
