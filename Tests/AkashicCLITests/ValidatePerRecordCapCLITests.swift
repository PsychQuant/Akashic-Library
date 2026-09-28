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

    /// 25 個配對各持兩筆重複的判定記錄 → CLI 印恰好 `perRecordWarningCap` 則家族訊息 ＋ 一句「另有 5 個配對未列出」；被截的 5 個在
    /// 不帶 `--owner` 的 validate 裡拿不到定位資訊。這是契約不是缺陷（上限在讀取路徑上對未信任的 store 內容跑）——#581 起出口是
    /// `validate --owner`（下一條測試），不帶它時最後一行指路。
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
        // 被截的 5 個配對在這一族裡看不到——這正是本測試要釘住的契約。**不綁走訪順序**（R24 verify logic 第 34 列：哪五個被截取決於
        // references 的序列順序，那不是本測試要釘的東西）：25 個配對裡恰好 20 個具名、5 個不在。
        let named = Set((1...25).filter { i in family.contains { $0.contains("work:w\(i)，") } })
        XCTAssertEqual(named.count, Entry.perRecordWarningCap, "具名的配對數＝上限：\(named.sorted())")
        XCTAssertEqual(r.status, 0, "warning 級不改 exit")
        // #581：被截的記錄數與出口
        XCTAssertTrue(lines.contains { $0.hasPrefix("被截的記錄: 1") && $0.contains("validate --owner <kind>:<key>") }, r.output)
    }

    /// #581：`--owner organization:acme` 對那一筆不套列出上限——25 個配對全部具名、沒有概括句、最後一行說這是完整明細。
    func testOwnerPrintsEveryPairingOfThatRecord() throws {
        var o = Organization(key: "acme", names: TimelineOf([TemporalValue(value: "Acme")]))
        o.references = (1...25).flatMap { [verdict("w\($0)"), verdict("w\($0)")] }
        _ = try LibraryStore(root: root).writeOrganization(o)
        let r = try CLITestHarness.run(["validate", "--library", root.path, "--owner", "organization:acme"],
                                       env: ["AKASHIC_HOME": fakeHome.path])
        let lines = r.output.split(separator: "\n").map(String.init)
        let family = lines.filter { $0.contains("acme: \(StoreHealth.duplicateVerdictRecordPrefix)：") }
        XCTAssertEqual(family.count, 25, r.output)
        XCTAssertEqual(Set((1...25).filter { i in family.contains { $0.contains("work:w\(i)，") } }).count, 25)
        XCTAssertFalse(lines.contains { $0.contains(Entry.perRecordCapSummaryPrefix) }, r.output)
        XCTAssertTrue(lines.contains { $0.contains("organization 'acme' 的完整 per-record 明細") }, r.output)
        XCTAssertTrue(lines.contains { $0.contains("不在 --owner 的範圍") }, "範圍要說出來：\(r.output)")
        XCTAssertEqual(r.status, 0, "warning 級不改 exit")
    }

    /// kind 必填、不猜：只看字串就判得出來的錯是用法錯誤（exit 64）；store 裡找不到是執行期失敗（exit 1）。
    func testOwnerRefusesMissingKindAsUsageErrorAndUnknownRecordAsRuntimeFailure() throws {
        let bare = try CLITestHarness.run(["validate", "--library", root.path, "--owner", "acme"], env: ["AKASHIC_HOME": fakeHome.path])
        XCTAssertEqual(bare.status, 64, bare.output)
        XCTAssertTrue(bare.output.contains("沒有 kind"), bare.output)
        let missing = try CLITestHarness.run(["validate", "--library", root.path, "--owner", "venue:nobody"], env: ["AKASHIC_HOME": fakeHome.path])
        XCTAssertEqual(missing.status, 1, missing.output)
        XCTAssertTrue(missing.output.contains("找不到已載入的 venue 記錄"), missing.output)
    }
}
