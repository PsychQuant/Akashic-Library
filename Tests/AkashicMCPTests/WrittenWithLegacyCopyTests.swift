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

    /// 錯誤回應是文字：同一份人可讀的報告附在後面。寫進去的那一筆不能因為之後的步驟失敗就從回應裡消失。
    func testAnErrorResponseGetsTheSameReportAppended() {
        let left = item()
        let out = AkashicService.reportingWrittenWithLegacyCopy("Error: index rebuild 失敗", [left], isError: true)
        XCTAssertTrue(out.hasPrefix("Error: index rebuild 失敗"), out)
        for line in LegacyCopyLeft.reportLines([left]) { XCTAssertTrue(out.contains(line), "\(line)\n—\n\(out)") }
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

    /// resolve-people 的 apply 逐筆收容寫入失敗（`writeFailed`）。這一筆寫了，不進 `writeFailed`；work 的兩份共用 citekey，
    /// 之後的 index rebuild 撞重複——錯誤訊息照實說 rebuild 失敗、`writeFailed 0 筆`，而寫進去的那一筆在收集到的清單裡。
    func testResolvePeopleApplyDoesNotListItAsAWriteFailure() throws {
        let e = try legacyWork()
        let id = "\(e.citekey):0:cheng-che"
        let (result, written) = LegacyCopyLedger.collecting { try service.resolvePeople(apply: [id]) }
        XCTAssertEqual(written.map(\.key), [e.citekey], "寫了，記在成功那一側")
        guard case .failure(let error) = result else { return XCTFail("前提：兩份並存時 index rebuild 撞重複的 citekey") }
        let text = AkashicService.reportingWrittenWithLegacyCopy(displaySafeErrorMultiline(error, prefix: "Error: "),
                                                                written, isError: true)
        XCTAssertTrue(text.contains("writeFailed 0 筆"), "不算寫入失敗：\(text)")
        XCTAssertTrue(text.contains("writtenWithLegacyCopy"), text)
        let onDisk = try String(contentsOf: store.entityURL(id: e.id), encoding: .utf8)
        XCTAssertTrue(onDisk.contains("key: cheng-che"), "作者位已歸戶：\(onDisk)")
    }

    /// enrich 逐筆收容寫入失敗（`writeFailed`）。同上：寫了、不進 `writeFailed`，rebuild 的錯誤訊息把它列在「已落地」。
    func testEnrichDoesNotListItAsAWriteFailure() throws {
        let e = try legacyWork()
        let (result, written) = LegacyCopyLedger.collecting {
            try service.enrich(proposals: [.init(citekey: e.citekey, fields: ["abstract": "摘要"])],
                               dryRun: false, includeAbsentAuthors: false)
        }
        XCTAssertEqual(written.map(\.key), [e.citekey])
        guard case .failure(let error) = result else { return XCTFail("前提：兩份並存時 index rebuild 撞重複的 citekey") }
        let text = displaySafeErrorMultiline(error, prefix: "Error: ")
        XCTAssertTrue(text.contains("本趟已落地 1 筆"), text)
        XCTAssertFalse(text.contains("writeFailed"), text)
    }
}
