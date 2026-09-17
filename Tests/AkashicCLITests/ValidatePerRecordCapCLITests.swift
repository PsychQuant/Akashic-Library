import XCTest
import Foundation
import AkashicCore
import AkashicEntity
import AkashicStoreIO

/// #554 R24（D66；R23 verify Codex 第 2 列）：釘住 CLI `validate` 的**實際**契約——它不加面級的 20 則截斷（MCP `akashic_doctor`
/// 才截），但 **per-record 的上限住在 `validate()`／`StoreHealth` 產生訊息的那一步**（`Entry.perRecordWarningCap`），三個面共有。
/// 一筆記錄超過上限時，CLI 也只印前 20 則加一句概括——「完整逐行看 CLI validate」這句話在 R14–R23 引入 per-record cap 之後為假，
/// 本測試走真 binary 把那個事實釘住，讓宣稱不能再漂回去。
final class ValidatePerRecordCapCLITests: XCTestCase {
    var root: URL!
    var fakeHome: URL!

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-validate-cap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        try LibraryStore(root: root).ensureLayout()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    private func verdict(_ holder: String) -> ProvenanceReference {
        ProvenanceReference(field: "resolution-rejected",
                            value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: holder, literal: "Vee").encoded,
                            kind: .judgement(statement: "測試用判定", restsOn: []))
    }

    /// 25 個配對各持兩筆重複的判定記錄 → CLI 印恰好 `perRecordWarningCap` 則家族訊息 ＋ 一句「另有 5 個配對未列出」；被截的 5 個在 CLI
    /// 也拿不到定位資訊。這是契約不是缺陷（求值上限在讀取路徑上對未信任的 store 內容跑）——要全部只能讀 YAML。
    func testValidatePrintsAtMostTheCapPerRecordAndOneSummaryLine() throws {
        var o = Organization(key: "acme", names: TimelineOf([TemporalValue(value: "Acme")]))
        o.references = (1...25).flatMap { [verdict("w\($0)"), verdict("w\($0)")] }
        _ = try LibraryStore(root: root).writeOrganization(o)
        let r = try CLITestHarness.run(["validate", "--library", root.path], env: ["AKASHIC_HOME": fakeHome.path])
        let lines = r.output.split(separator: "\n").map(String.init)
        // 家族以**前綴**認（概括句的正文也提到「重複的判定記錄」，但它不帶家族前綴——與 `StoreHealth` 的家族存取子同一條判準）
        let family = lines.filter { $0.contains("acme: \(StoreHealth.duplicateVerdictRecordPrefix)：") }
        XCTAssertEqual(family.count, Entry.perRecordWarningCap, "CLI 不加面級截斷，但 per-record 上限在 validate() 裡、CLI 同樣受它：\n\(r.output)")
        let summary = lines.filter { $0.contains(Entry.perRecordCapSummaryPrefix) && $0.contains("acme") }
        XCTAssertEqual(summary.count, 1, r.output)
        XCTAssertTrue(summary.first?.contains("另有 5 個配對未列出") == true, summary.first ?? "")
        // 被截的配對在這一族裡看不到——這正是本測試要釘住的契約（`w25` 仍會出現在死 verdict 那一族，因為本 fixture 沒建 work；那是另一族的話）
        XCTAssertFalse(family.contains { $0.contains("work:w25") }, family.description)
        XCTAssertEqual(r.status, 0, "warning 級不改 exit")
    }
}
