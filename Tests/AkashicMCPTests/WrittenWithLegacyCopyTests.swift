import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicZoteroImport
@testable import AkashicMCPKit

/// #705：寫進 `entities/`、搬移後的 legacy 拷貝沒刪掉的那一筆，MCP 面記在成功那一側的 `writtenWithLegacyCopy`。
///
/// 工具分派（`Server.swift`）在一個收集範圍裡跑每一次呼叫，結束後用 `AkashicService.reportingWrittenWithLegacyCopy` 把收到的
/// 附進回應。這裡照同一個順序在服務層重演（範圍 → 呼叫 → 附上），釘住兩件事：各寫入者的失敗清單不含這一筆、回應帶著它。
/// 分派本身的接線由 `StdioE2ETests.testLegacyCopyLeftIsReportedOnTheSuccessSide` 走真 binary 釘住。
final class WrittenWithLegacyCopyTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!
    private var service: AkashicService { AkashicService(root: root, key: nil, environment: [:]) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-705-mcp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "sources/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        for dir in [store.entriesDir, store.peopleDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try store.writePerson(Person(key: "cheng-che", names: PersonNames(authorized: ["Che Cheng"])))
    }

    override func tearDownWithError() throws {
        for dir in [store.entriesDir, store.peopleDir] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        }
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - 夾具

    private func lock(_ dir: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        let probe = dir.appendingPathComponent("probe-\(UUID().uuidString)")
        if FileManager.default.createFile(atPath: probe.path, contents: Data()) {
            try? FileManager.default.removeItem(at: probe)
            throw XCTSkip("這個環境的權限擋不住刪檔（以 root 執行？），造不出「寫完之後刪 legacy 失敗」")
        }
    }

    /// legacy 佈局的一筆 work（只有 `entries/<citekey>.yaml`、受 git 追蹤且乾淨），`entries/` 唯讀——寫入會搬移、刪除會失敗。
    @discardableResult
    private func legacyWork() throws -> Entry {
        let e = Entry(id: UUID(), citekey: "cheng2025identifiability", type: .periodicalArticle,
                      title: "Identifiability of polychoric models", authors: [.literal("Che Cheng")], date: "2025")
        try EntryYAML.encode(e).write(to: store.entriesDir.appendingPathComponent("\(e.citekey).yaml"),
                                      atomically: true, encoding: .utf8)
        StoreGitCommit.commitAll(root)
        try lock(store.entriesDir)
        return e
    }

    /// 同上，person：`people/<key>.yaml` 一份、`people/` 唯讀。
    @discardableResult
    private func legacyPerson() throws -> Person {
        let p = Person(key: "yang-hau-hung", names: PersonNames(variant: ["Hau-Hung Yang"]))
        try PersonYAML.encode(p).write(to: store.personURL(key: p.key), atomically: true, encoding: .utf8)
        StoreGitCommit.commitAll(root)
        try lock(store.peopleDir)
        return p
    }

    private func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
    }

    private func item(_ key: String = "cheng2025identifiability") -> LegacyCopyLeft {
        LegacyCopyLeft(kind: .work, key: key, id: UUID(), legacyFile: "entries/\(key).yaml", detail: "權限不足")
    }

    // MARK: - 回應的形狀

    func testASuccessfulJSONObjectGetsTheKeyOnTheSuccessSide() throws {
        let left = item()
        let out = AkashicService.reportingWrittenWithLegacyCopy("{\n  \"written\" : 1\n}", [left], isError: false)
        let obj = try object(out)
        XCTAssertEqual(obj["written"] as? Int, 1, "原本的鍵不動：\(out)")
        let rows = try XCTUnwrap(obj["writtenWithLegacyCopy"] as? [[String: String]], out)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?["kind"], "work")
        XCTAssertEqual(rows.first?["key"], left.key)
        XCTAssertEqual(rows.first?["written"], left.writtenFile)
        XCTAssertEqual(rows.first?["legacyFile"], left.legacyFile)
        XCTAssertEqual(rows.first?["detail"], "權限不足")
    }

    func testNothingCollectedLeavesTheResponseByteIdentical() {
        for (text, isError) in [("{\n  \"a\" : 1\n}", false), ("[1, 2]", false), ("Error: 壞了", true)] {
            XCTAssertEqual(AkashicService.reportingWrittenWithLegacyCopy(text, [], isError: isError), text)
        }
    }

    /// 錯誤回應是文字：同一份人可讀的報告放在**最前面**，接著原本的錯誤（#705 R1 verify 第 5 列）。寫進去的那一筆不能因為之後的步驟失敗
    /// 就從回應裡消失；而且呼叫端要先讀到「寫了」，才讀到 rebuild 失敗——附在末尾時 agent 很可能照 isError 重試，而重試會被 #631 拒絕。
    func testAnErrorResponseLeadsWithTheSameReport() {
        let left = item()
        let lines = LegacyCopyLeft.reportLines([left])
        let out = AkashicService.reportingWrittenWithLegacyCopy("Error: index rebuild 失敗", [left], isError: true)
        XCTAssertTrue(out.hasPrefix(lines.joined(separator: "\n")), out)
        XCTAssertTrue(out.hasSuffix("\n\nError: index rebuild 失敗"), "原本的錯誤原樣接在後面：\(out)")
    }

    /// 成功的回應已經帶著這個鍵（`akashic_import_zotero` 的 payload 自己帶）：併進那個陣列、回應仍是一份 JSON（#705 R1 verify 第 15 列：
    /// 先前落到「附文字」那一格，合法的 JSON 變成 JSON 加文字）。
    func testAnExistingKeyIsMergedAndTheResponseStaysJSON() throws {
        let existing = item("b2020x"), added = item("a2020x")
        let base = AkashicService.reportingWrittenWithLegacyCopy("{\n  \"created\" : [ ]\n}", [existing], isError: false)
        let out = AkashicService.reportingWrittenWithLegacyCopy(base, [added], isError: false)
        let obj = try object(out)
        let rows = try XCTUnwrap(obj["writtenWithLegacyCopy"] as? [[String: String]], out)
        XCTAssertEqual(rows.map { $0["key"] }, ["a2020x", "b2020x"], "兩筆都在、依 (kind, key) 排序")
        XCTAssertNotNil(obj["created"], "原本的鍵不動")
        // 同名鍵卻不是陣列：不是這個函式寫的形狀——不覆寫它，照舊附文字
        let odd = AkashicService.reportingWrittenWithLegacyCopy("{\"writtenWithLegacyCopy\": 1}", [added], isError: false)
        XCTAssertTrue(odd.hasPrefix("{\"writtenWithLegacyCopy\": 1}"), odd)
        XCTAssertTrue(odd.contains(added.message), odd)
    }

    /// 不是 JSON 物件的成功回應（陣列、純文字）沒有地方放鍵——同一份報告附在後面，不改動原本的內容。
    func testANonObjectResponseGetsTheReportAppended() {
        let left = item()
        let out = AkashicService.reportingWrittenWithLegacyCopy("[1, 2]", [left], isError: false)
        XCTAssertTrue(out.hasPrefix("[1, 2]"), out)
        XCTAssertTrue(out.contains(left.message), out)
    }

    /// 回應裡的字串都是消毒過的：legacyFile 帶 key，而 key 是 store 內容。
    func testTheRowsAreSanitized() throws {
        let evil = LegacyCopyLeft(kind: .work, key: "a\u{202E}b", id: UUID(), legacyFile: "entries/a\u{202E}b.yaml", detail: "d")
        let obj = try object(AkashicService.reportingWrittenWithLegacyCopy("{}", [evil], isError: false))
        let row = try XCTUnwrap((obj["writtenWithLegacyCopy"] as? [[String: String]])?.first)
        XCTAssertFalse(row["key"]!.unicodeScalars.contains("\u{202E}"), row["key"]!)
        XCTAssertFalse(row["legacyFile"]!.unicodeScalars.contains("\u{202E}"), row["legacyFile"]!)
    }

    /// `akashic_import_zotero` 的報告自己收（`ZoteroImporter.run` 有自己的範圍），payload 由報告帶出——rebuild 失敗時錯誤訊息
    /// 帶著同一份 payload，所以它也在那裡。
    func testTheImportReportPayloadCarriesIt() throws {
        var report = ImportReport()
        XCTAssertNil(AkashicService.importReportPayload(report)["writtenWithLegacyCopy"], "沒有就不出現")
        report.writtenWithLegacyCopy = [item()]
        let rows = try XCTUnwrap(AkashicService.importReportPayload(report)["writtenWithLegacyCopy"] as? [[String: String]])
        XCTAssertEqual(rows.map { $0["key"] }, ["cheng2025identifiability"])
    }

    // MARK: - 寫入者：範圍內寫了、不進失敗清單

    /// person 的兩份共用 key，而 index 的 people 表對重複 key 留第一筆（#670）——rebuild 照常成功，這是成功回應帶著它的那一格。
    func testUpdatePersonReportsItOnASuccessfulResponse() throws {
        let p = try legacyPerson()
        let (result, written) = LegacyCopyLedger.collecting {
            try service.updatePerson(key: p.key, fields: ["note": "改過"], dryRun: false)
        }
        let payload = try result.get()
        XCTAssertEqual(written.map(\.key), [p.key])
        let obj = try object(AkashicService.reportingWrittenWithLegacyCopy(payload, written, isError: false))
        let rows = try XCTUnwrap(obj["writtenWithLegacyCopy"] as? [[String: String]], "\(obj)")
        XCTAssertEqual(rows.first?["kind"], "person")
        XCTAssertEqual(rows.first?["legacyFile"], "people/\(p.key).yaml")
        let onDisk = try String(contentsOf: store.entityURL(id: p.id), encoding: .utf8)
        XCTAssertTrue(onDisk.contains("改過"), "寫了：\(onDisk)")
    }

    /// resolve-people 的 apply 逐筆收容寫入失敗（`writeFailed`）。這一筆寫了，不進 `writeFailed`、算在 `applied`；#709 起 index 以
    /// entities/ 那份為準、略過 legacy 拷貝，呼叫回成功（#709 之前 work 的兩份讓 rebuild 撞重複、這一筆只能附在錯誤訊息裡）。
    func testResolvePeopleApplyDoesNotListItAsAWriteFailure() throws {
        let e = try legacyWork()
        let id = "\(e.citekey):0:cheng-che"
        let (result, written) = LegacyCopyLedger.collecting { try service.resolvePeople(apply: [id]) }
        XCTAssertEqual(written.map(\.key), [e.citekey], "寫了，記在成功那一側")
        let obj = try object(AkashicService.reportingWrittenWithLegacyCopy(try result.get(), written, isError: false))
        XCTAssertNil(obj["writeFailed"], "不算寫入失敗：\(obj)")
        XCTAssertEqual(obj["applied"] as? [String], [id], "\(obj)")
        XCTAssertEqual((obj["writtenWithLegacyCopy"] as? [[String: String]])?.map { $0["key"] }, [e.citekey], "\(obj)")
        let onDisk = try String(contentsOf: store.entityURL(id: e.id), encoding: .utf8)
        XCTAssertTrue(onDisk.contains("key: cheng-che"), "作者位已歸戶：\(onDisk)")
    }

    /// enrich 逐筆收容寫入失敗（`writeFailed`）。同上：寫了、不進 `writeFailed`、算在 `written`，呼叫回成功（#709）。
    func testEnrichDoesNotListItAsAWriteFailure() throws {
        let e = try legacyWork()
        let (result, written) = LegacyCopyLedger.collecting {
            try service.enrich(proposals: [.init(citekey: e.citekey, fields: ["abstract": "摘要"])],
                               dryRun: false, includeAbsentAuthors: false)
        }
        XCTAssertEqual(written.map(\.key), [e.citekey])
        let obj = try object(try result.get())
        XCTAssertNil(obj["writeFailed"], "\(obj)")
        XCTAssertEqual(obj["written"] as? [String], [e.citekey], "\(obj)")
    }

    /// 寫了之後別的步驟失敗時照舊：store 裡另有兩筆**不同**的記錄共用 citekey（#709 不替真的重複選一筆），index rebuild 撞 UNIQUE——
    /// 錯誤訊息照實說 rebuild 失敗、`writeFailed 0 筆`，寫進去的那一筆在收集到的清單裡、報告放在錯誤最前面。
    func testALaterRebuildFailureStillCarriesIt() throws {
        breakIndexRebuild()
        let e = try legacyWork()
        let id = "\(e.citekey):0:cheng-che"
        let (result, written) = LegacyCopyLedger.collecting { try service.resolvePeople(apply: [id]) }
        XCTAssertEqual(written.map(\.key), [e.citekey], "寫了，記在成功那一側")
        guard case .failure(let error) = result else { return XCTFail("前提：兩筆不同的記錄共用 citekey，index rebuild 撞 UNIQUE") }
        let text = AkashicService.reportingWrittenWithLegacyCopy(displaySafeErrorMultiline(error, prefix: "Error: "),
                                                                written, isError: true)
        XCTAssertTrue(text.hasPrefix("writtenWithLegacyCopy"), text)
        XCTAssertTrue(text.contains("writeFailed 0 筆"), "不算寫入失敗：\(text)")
    }

    // MARK: - import_zotero 的 rebuild 失敗（#705 R1 verify 第 1 列）

    /// 兩筆**不同**的記錄（id 不同）共用一個 citekey——index rebuild 必然撞 UNIQUE。#709 起同一筆記錄的 legacy 拷貝不再讓重建失敗
    /// （index 以 entities/ 那份為準），要測「寫了之後 rebuild 失敗」得用真的重複。
    private func breakIndexRebuild() {
        for title in ["A", "B"] {
            XCTAssertNoThrow(try store.writeEntry(Entry(id: UUID(), citekey: "dup2020x", type: .periodicalArticle, title: title, date: "2020")))
        }
    }

    /// `n` 筆 legacy 佈局的 work，各帶一個 Zotero 來源（`KEYART01`…，版本比 Zotero 舊）——匯入會更新它們、寫進 `entities/`、刪不掉 legacy 檔。
    /// 另有兩筆不同的記錄共用 citekey（`breakIndexRebuild`），之後的 index rebuild 撞 UNIQUE。
    private func legacyZoteroWorks(_ n: Int) throws -> (db: URL, keys: [String]) {
        breakIndexRebuild()
        let dir = root.appendingPathComponent("zotero-fixture")   // 在 store 之內：tearDown 一起清掉
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let zotero = try PayloadZoteroDB(dir: dir, itemCount: n)
        var keys: [String] = []
        for i in 1...n {
            var e = Entry(id: UUID(), citekey: String(format: "legacy2025n%02d", i), type: .periodicalArticle, title: "Old \(i)", date: "2025")
            e.provenance = Provenance(zoteroKey: String(format: "KEYART%02d", i), zoteroVersion: 1, libraryID: 1)
            try EntryYAML.encode(e).write(to: store.entriesDir.appendingPathComponent("\(e.citekey).yaml"), atomically: true, encoding: .utf8)
            keys.append(e.citekey)
        }
        StoreGitCommit.commitAll(root)
        try lock(store.entriesDir)
        return (zotero.url, keys)
    }

    /// 分派的範圍裡（這裡照同一個順序重演）：importer 自己的範圍收下、放進報告；rebuild 失敗時報告裡的那幾筆**交給外層**，
    /// 嵌進錯誤訊息的 payload 不再帶——外層在格式化錯誤之後把它們放在回應最前面、不截。真 binary 的接線與超過錯誤上限的量由
    /// `StdioE2ETests.testImportRebuildFailureReportsTheLegacyCopiesWithACap` 釘住。
    func testAnImportWhoseRebuildFailsHandsItsLeftoversToTheEnclosingScope() throws {
        let (db, keys) = try legacyZoteroWorks(3)
        let (result, outer) = LegacyCopyLedger.collecting { try service.importZotero(zoteroDb: db.path, libraryID: nil) }
        guard case .failure(let error) = result else { return XCTFail("前提：兩筆不同的記錄共用 citekey，index rebuild 撞 UNIQUE") }
        XCTAssertEqual(outer.map(\.key).sorted(), keys, "交給外層（分派）")
        let text = displaySafeErrorMultiline(error, prefix: "Error: ")
        XCTAssertTrue(text.contains("index rebuild 失敗"), text)
        XCTAssertFalse(text.contains("\"writtenWithLegacyCopy\""), "嵌進錯誤的 payload 不再帶——否則同一筆報兩次：\(text)")
    }

    /// 沒有外層範圍的直接呼叫端：沒有人可交，報告照舊帶在嵌進錯誤的 payload 裡。
    func testWithoutAnEnclosingScopeTheImportErrorStillCarriesThem() throws {
        let (db, keys) = try legacyZoteroWorks(2)
        XCTAssertThrowsError(try service.importZotero(zoteroDb: db.path, libraryID: nil)) { error in
            let text = displaySafeErrorMultiline(error, prefix: "Error: ")
            XCTAssertTrue(text.contains("\"writtenWithLegacyCopy\""), text)
            for k in keys { XCTAssertTrue(text.contains(k), "\(k)：\(text)") }
        }
    }
}
