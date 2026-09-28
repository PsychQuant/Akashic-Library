import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #581：`akashic_doctor` 的 `owner`——單筆記錄的完整 per-record 明細（`AkashicService.recordIssueDetail(owner:)`）。
///
/// MCP 面與 CLI `validate --owner` 走同一個 `perRecordIssues(from:owner:)`；差別只在呈現：這一面的輸出進 LLM context，
/// 所以逐則受 `candidateByteBudget` 約束、以 `total`／`truncated` 揭露（與不帶 owner 時的 `recordIssues.first` 同一個威脅模型）。
final class RecordIssueDetailTests: XCTestCase {
    var root: URL!
    var fakeHome: URL!
    var service: AkashicService!

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-owner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        try LibraryStore(root: root).ensureLayout()
        service = AkashicService(root: root, environment: ["AKASHIC_HOME": fakeHome.path])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    private func pairs(_ n: Int, literal: String) -> [ProvenanceReference] {
        (1...n).flatMap { i -> [ProvenanceReference] in
            let v = ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "w\(i)", literal: literal).encoded
            let r = ProvenanceReference(field: "resolution-rejected", value: v, kind: .judgement(statement: "測試用判定", restsOn: []))
            return [r, r]
        }
    }

    private func object(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }

    /// 25 個配對：不帶 owner 時 `duplicateVerdictRecords` 是 20（下限）；帶 owner 時 25 則全列、沒有概括句、沒被預算截。
    func testOwnerListsEveryIssueOfThatRecord() throws {
        var o = Organization(key: "acme", names: TimelineOf([TemporalValue(value: "Acme")]))
        o.references = pairs(25, literal: "Vee")
        _ = try LibraryStore(root: root).writeOrganization(o)
        let doctor = try object(try service.doctor())
        let recordIssues = try XCTUnwrap(doctor["recordIssues"] as? [String: Any])
        XCTAssertEqual(recordIssues["duplicateVerdictRecords"] as? Int, Entry.perRecordWarningCap, "對照：不帶 owner 時照舊是下限")
        let detail = try object(try service.recordIssueDetail(owner: "organization:acme"))
        let issues = try XCTUnwrap(detail["issues"] as? [[String: Any]])
        let family = issues.compactMap { $0["message"] as? String }.filter { $0.hasPrefix(StoreHealth.duplicateVerdictRecordPrefix) }
        XCTAssertEqual(family.count, 25, "\(family.count)")
        XCTAssertFalse(issues.contains { ($0["message"] as? String)?.hasPrefix(Entry.perRecordCapSummaryPrefix) == true })
        XCTAssertEqual(detail["total"] as? Int, issues.count)
        XCTAssertEqual(detail["truncated"] as? Bool, false)
        XCTAssertEqual(detail["listing"] as? String, "full")
        let owner = try XCTUnwrap(detail["owner"] as? [String: Any])
        XCTAssertEqual(owner["kind"] as? String, "organization")
        XCTAssertEqual(owner["key"] as? String, "acme")
        XCTAssertNil(detail["indexRebuilt"], "owner 模式唯讀、不重建 index")
    }

    /// 面的位元組預算仍在：數百則、每則近千字元時 `issues` 被截、`truncated` 為 true、`total` 是完整則數。
    func testOwnerDetailStaysUnderTheByteBudgetAndDisclosesTruncation() throws {
        var o = Organization(key: "acme", names: TimelineOf([TemporalValue(value: "Acme")]))
        o.references = pairs(300, literal: String(repeating: "Long literal ", count: 9))
        _ = try LibraryStore(root: root).writeOrganization(o)
        let detail = try object(try service.recordIssueDetail(owner: "organization:acme"))
        let issues = try XCTUnwrap(detail["issues"] as? [[String: Any]])
        let total = try XCTUnwrap(detail["total"] as? Int)
        XCTAssertEqual(detail["truncated"] as? Bool, true)
        XCTAssertLessThan(issues.count, total, "預算截掉的要揭露：listed \(issues.count) / total \(total)")
        XCTAssertGreaterThanOrEqual(total, 300, "total 數的是截之前的全部則數")
        let bytes = try JSONSerialization.data(withJSONObject: issues).count
        XCTAssertLessThanOrEqual(bytes, AkashicService.candidateByteBudget + 2_048, "issues 受 48 KiB 預算約束：\(bytes)")
    }

    /// 定址錯誤、找不到都拒絕（不猜），訊息說出 kind 的值域。
    func testOwnerRefusesMissingKindAndUnknownRecords() throws {
        XCTAssertThrowsError(try service.recordIssueDetail(owner: "acme")) { error in
            XCTAssertTrue(displaySafeErrorText(error).contains("沒有 kind"), displaySafeErrorText(error))
        }
        XCTAssertThrowsError(try service.recordIssueDetail(owner: "venue:nobody")) { error in
            XCTAssertTrue(displaySafeErrorText(error).contains("找不到"), displaySafeErrorText(error))
        }
    }
}
