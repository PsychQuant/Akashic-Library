import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicZoteroImport
@testable import AkashicMCPKit

/// #705 R2 verify：MCP 面的 `writtenWithLegacyCopy` 有上限（第 13 列），以及同一個操作稍早留下 legacy 拷貝之後，其他寫入者的拒絕也說出
/// 前一步寫了（第 5 列）。
final class WrittenWithLegacyCopyR2Tests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!
    private var service: AkashicService { AkashicService(root: root, key: nil, environment: [:]) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-705r2-mcp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "sources/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
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

    private func items(_ n: Int) -> [LegacyCopyLeft] {
        (1...n).map { LegacyCopyLeft(kind: .work, key: String(format: "k%02d", $0), id: UUID(), legacyFile: "entries/k.yaml", detail: "d") }
    }

    private func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
    }

    /// 第 13 列：成功的 JSON 至多列 20 筆（依 (kind, key) 排序留前面的），`…Total` 是完整筆數、`…Truncated` 說有沒有截——三個鍵同進同出。
    /// CLI 傳 nil＝全列。已帶這個鍵的回應（import 的 payload 已截）併進去時，總數是它的總數加上這次的筆數。
    func testTheMCPResponseCapsTheRowsAndGivesTheTotal() throws {
        let obj = try object(AkashicService.reportingWrittenWithLegacyCopy("{}", items(25), isError: false))
        let rows = try XCTUnwrap(obj["writtenWithLegacyCopy"] as? [[String: String]])
        XCTAssertEqual(rows.count, AkashicService.writtenWithLegacyCopyLimit)
        XCTAssertEqual(rows.first?["key"], "k01")
        XCTAssertEqual(obj["writtenWithLegacyCopyTotal"] as? Int, 25)
        XCTAssertEqual(obj["writtenWithLegacyCopyTruncated"] as? Bool, true)

        let full = try object(AkashicService.reportingWrittenWithLegacyCopy("{}", items(25), isError: false, limit: nil))
        XCTAssertEqual((full["writtenWithLegacyCopy"] as? [Any])?.count, 25, "CLI 全列")
        XCTAssertEqual(full["writtenWithLegacyCopyTruncated"] as? Bool, false)

        let small = try object(AkashicService.reportingWrittenWithLegacyCopy("{}", items(2), isError: false))
        XCTAssertEqual(small["writtenWithLegacyCopyTotal"] as? Int, 2)
        XCTAssertEqual(small["writtenWithLegacyCopyTruncated"] as? Bool, false, "上限之內：照給兩個揭露鍵")

        let base = AkashicService.reportingWrittenWithLegacyCopy("{}", items(25), isError: false)
        let merged = try object(AkashicService.reportingWrittenWithLegacyCopy(base, items(2), isError: false))
        XCTAssertEqual(merged["writtenWithLegacyCopyTotal"] as? Int, 27, "併進去：已截的總數加上這次的筆數")
        XCTAssertEqual((merged["writtenWithLegacyCopy"] as? [Any])?.count, 20)
    }

    /// 錯誤回應的人可讀報告同一個上限：標題是完整筆數，多出的一行說去哪裡找。
    func testTheErrorTextIsCappedWithADisclosure() {
        let out = AkashicService.reportingWrittenWithLegacyCopy("Error: index rebuild 失敗", items(25), isError: true)
        let lines = out.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertTrue(lines.first?.hasSuffix(": 25") == true, String(lines.first ?? ""))
        XCTAssertEqual(lines.filter { $0.hasPrefix("  ⚠ ") }.count, 20)
        XCTAssertTrue(out.contains("另有 5 筆未列出") && out.contains("akashic validate"), out)
        XCTAssertTrue(out.hasSuffix("\n\nError: index rebuild 失敗"), out)
    }

    /// import 的 payload：給了 listLimit（MCP）才截，沒給（直接呼叫、嵌進錯誤而沒有外層）全列；兩種都帶揭露鍵。
    func testTheImportPayloadCapsOnlyWithAListLimit() throws {
        var report = ImportReport()
        report.writtenWithLegacyCopy = items(25)
        let capped = AkashicService.importReportPayload(report, listLimit: 20)
        XCTAssertEqual((capped["writtenWithLegacyCopy"] as? [Any])?.count, 20)
        XCTAssertEqual(capped["writtenWithLegacyCopyTotal"] as? Int, 25)
        XCTAssertEqual(capped["writtenWithLegacyCopyTruncated"] as? Bool, true)
        let full = AkashicService.importReportPayload(report)
        XCTAssertEqual((full["writtenWithLegacyCopy"] as? [Any])?.count, 25)
        XCTAssertEqual(full["writtenWithLegacyCopyTruncated"] as? Bool, false)
    }

    /// 之後的寫入沒有套用的那一筆：列帶 `laterWriteNotApplied`（與人可讀報告同一句）。
    func testARowFlagsALaterWriteThatWasNotApplied() throws {
        var left = items(1)[0]
        left.laterWriteRefused = true
        let obj = try object(AkashicService.reportingWrittenWithLegacyCopy("{}", [left], isError: false))
        let row = try XCTUnwrap((obj["writtenWithLegacyCopy"] as? [[String: String]])?.first)
        XCTAssertEqual(row["laterWriteNotApplied"], LegacyCopyLeft.laterWriteRefusedNote)
        let plain = try object(AkashicService.reportingWrittenWithLegacyCopy("{}", items(1), isError: false))
        XCTAssertNil((plain["writtenWithLegacyCopy"] as? [[String: String]])?.first?["laterWriteNotApplied"], "沒有之後就不出現")
    }

    /// #705 R3 verify（codex，MEDIUM）：成功清單截到 20 筆時，「之後的寫入沒有套用」只標在被截掉的那一列上——唯一的回報跟著消失。
    /// 完整的筆數在截斷之外（`writtenWithLegacyCopyNotApplied`，> 0 才出現）。
    func testTheNotAppliedCountSurvivesTruncationOfTheRows() throws {
        var all = items(25)
        all[24].laterWriteRefused = true   // 排序第 25 位：不在前 20 列裡
        let obj = try object(AkashicService.reportingWrittenWithLegacyCopy("{}", all, isError: false))
        let rows = try XCTUnwrap(obj["writtenWithLegacyCopy"] as? [[String: String]])
        XCTAssertEqual(rows.count, 20)
        XCTAssertFalse(rows.contains { $0["laterWriteNotApplied"] != nil }, "前提：可見的 20 列都沒有這個標記")
        XCTAssertEqual(obj["writtenWithLegacyCopyTruncated"] as? Bool, true)
        XCTAssertEqual(obj["writtenWithLegacyCopyNotApplied"] as? Int, 1, "完整筆數不被截")

        // 沒有任何一筆之後被拒時鍵不出現——既有回應的位元組不變
        let none = try object(AkashicService.reportingWrittenWithLegacyCopy("{}", items(25), isError: false))
        XCTAssertNil(none["writtenWithLegacyCopyNotApplied"])

        // CLI 全列：列自己帶標記，數也一致
        let full = try object(AkashicService.reportingWrittenWithLegacyCopy("{}", all, isError: false, limit: nil))
        XCTAssertEqual(full["writtenWithLegacyCopyNotApplied"] as? Int, 1)
        XCTAssertEqual((full["writtenWithLegacyCopy"] as? [[String: String]])?.filter { $0["laterWriteNotApplied"] != nil }.count, 1)

        // 併進已截的回應：已截的那份自己帶完整的數，這次再有一筆就是兩筆
        var more = items(2)
        more[0].laterWriteRefused = true
        let base = AkashicService.reportingWrittenWithLegacyCopy("{}", all, isError: false)
        let merged = try object(AkashicService.reportingWrittenWithLegacyCopy(base, more, isError: false))
        XCTAssertEqual(merged["writtenWithLegacyCopyNotApplied"] as? Int, 2)
    }

    /// 錯誤回應（人可讀報告）同一件事：被截掉的列裡有沒套用的，「另有 N 筆未列出」那一行要說。
    func testTheErrorTextSaysWhenAHiddenRowHasANotAppliedWrite() {
        var all = items(25)
        all[24].laterWriteRefused = true
        let out = AkashicService.reportingWrittenWithLegacyCopy("Error: index rebuild 失敗", all, isError: true)
        let tail = out.split(separator: "\n").first { $0.contains("另有 5 筆未列出") }.map(String.init) ?? ""
        XCTAssertTrue(tail.contains("其中 1 筆") && tail.contains(LegacyCopyLeft.laterWriteRefusedNote), out)
        // 可見的 20 列都沒標記、也沒有隱藏的標記時，這一行維持原樣
        let plain = AkashicService.reportingWrittenWithLegacyCopy("Error: x", items(25), isError: true)
        XCTAssertFalse(plain.contains("其中"), plain)
    }

    /// import 的 payload：給了 listLimit（MCP）截列、完整的沒套用筆數照給。
    func testTheImportPayloadCarriesTheFullNotAppliedCount() throws {
        var report = ImportReport()
        report.writtenWithLegacyCopy = items(25)
        report.writtenWithLegacyCopy[24].laterWriteRefused = true
        let capped = AkashicService.importReportPayload(report, listLimit: 20)
        XCTAssertEqual((capped["writtenWithLegacyCopy"] as? [Any])?.count, 20)
        XCTAssertEqual(capped["writtenWithLegacyCopyNotApplied"] as? Int, 1)
    }

    /// 第 5 列：不只 `ZoteroImporter`——同一個範圍（分派）裡的第二個寫入者撞上稍早留下的拷貝，拒絕說出前一步寫了，
    /// 而且那一筆標上 `laterWriteRefused`。這裡是 update_person 對同一個 person 寫兩次（person 的兩份不擋 index 重建，#670）。
    func testASecondWriterInTheSameScopeSaysTheEarlierStepWrote() throws {
        let p = Person(key: "yang-hau-hung", names: PersonNames(variant: ["Hau-Hung Yang"]))
        try PersonYAML.encode(p).write(to: store.personURL(key: p.key), atomically: true, encoding: .utf8)
        StoreGitCommit.commitAll(root)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: store.peopleDir.path)
        let probe = store.peopleDir.appendingPathComponent("probe-\(UUID().uuidString)")
        if FileManager.default.createFile(atPath: probe.path, contents: Data()) {
            try? FileManager.default.removeItem(at: probe)
            throw XCTSkip("這個環境的權限擋不住刪檔（以 root 執行？）")
        }
        let (_, written) = LegacyCopyLedger.collecting { () throws -> Void in
            _ = try service.updatePerson(key: p.key, fields: ["note": "第一步"], dryRun: false)
            XCTAssertThrowsError(try service.updatePerson(key: p.key, fields: ["note": "第二步"], dryRun: false)) { error in
                let text = displaySafeErrorMultiline(error, prefix: "Error: ")
                XCTAssertTrue(text.contains("同一個操作稍早已寫入這一筆（見 writtenWithLegacyCopy）"), text)
            }
        }
        XCTAssertEqual(written.map(\.key), [p.key])
        XCTAssertEqual(written.map(\.laterWriteRefused), [true])
    }
}
