import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #645：person 與 organization 持有的 resolution verdict 數達 decode 預算的一半時出聲——venue 側（#499）的同形擴充。
/// 兩者持有的 verdict 與 venue 同一個 `ProvenanceReference` 形狀、受同一個 decode 硬預算約束；增長來源是一個人的著作數
/// 與不退役的 `resolution-undecided` 記錄（#619、#643）。
final class HolderVerdictBudgetWarningTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-hvb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func verdicts(_ n: Int, restsOn: [String] = []) -> [ProvenanceReference] {
        (0..<n).map { i in
            ProvenanceReference(
                field: "resolution-confirmed",
                value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "w\(i)a", literal: "Chen, C.").encoded,
                kind: .judgement(statement: "測試用判定", restsOn: restsOn))
        }
    }

    func testPersonAtThresholdIsAWarningAndBelowIsNot() throws {
        var p = Person(key: "chen-c", names: ["Chen, C."])
        p.references = verdicts(40)
        try store.writePerson(p)
        let load = try store.load()
        let issues = store.holderVerdictBudgetIssues(in: load, threshold: 40)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.owner, "chen-c")
        XCTAssertEqual(issues.first?.kind, "person")
        XCTAssertEqual(issues.first?.issue.severity, .warning)
        XCTAssertTrue(issues.first?.issue.message.hasPrefix(StoreHealth.holderVerdictBudgetPrefix) == true)
        XCTAssertTrue(issues.first?.issue.message.contains("40") == true, "\(issues.first!.issue.message)")
        XCTAssertTrue(store.holderVerdictBudgetIssues(in: load, threshold: 41).isEmpty)
    }

    func testOrganizationAtThresholdIsAWarning() throws {
        var o = Organization(key: "iss")
        o.names = TimelineOf([TemporalValue(value: "ISS", range: DateRange())])
        o.references = verdicts(12)
        try store.writeOrganization(o)
        let issues = store.holderVerdictBudgetIssues(in: try store.load(), threshold: 12)
        XCTAssertEqual(issues.map(\.owner), ["iss"])
        XCTAssertEqual(issues.first?.kind, "organization")
    }

    /// rests-on 的 digest 每個多一個節點，換算成等效筆數再比（與 venue 側同一份算法）。
    func testRestsOnCountsTowardTheBudget() throws {
        var p = Person(key: "chen-c", names: ["Chen, C."])
        p.references = verdicts(10, restsOn: ["sha256:" + String(repeating: "a", count: 64)])   // 10 個 digest ＝ 等效 2 筆
        try store.writePerson(p)
        let load = try store.load()
        XCTAssertEqual(store.holderVerdictBudgetIssues(in: load, threshold: 12).count, 1)
        XCTAssertTrue(store.holderVerdictBudgetIssues(in: load, threshold: 13).isEmpty)
    }

    /// 經 `health(from:)`（預設門檻）：40 筆不出聲、計算屬性存在且為空；venue 那一族不重複報 person。
    func testHealthUsesTheDefaultThresholdAndKeepsFamiliesApart() throws {
        var p = Person(key: "chen-c", names: ["Chen, C."])
        p.references = verdicts(40)
        try store.writePerson(p)
        let health = store.health(from: try store.load())
        XCTAssertTrue(health.holderVerdictBudgetWarnings.isEmpty)
        XCTAssertTrue(store.venueVerdictBudgetIssues(in: try store.load(), threshold: 1).isEmpty, "venue 族不掃 person")
    }

    /// 位元組軸（#645 verify security）：未決記錄的說明可寫到 4 KB，只看節點會在撞上 8 MiB 讀取上限之後很久才出聲。
    /// 經 `health(from:)`（預設門檻）走一次，同時證明新族真的接進了 perRecord。
    func testByteAxisFiresThroughHealthWithUndecidedRecords() throws {
        var p = Person(key: "chen-c", names: ["Chen, C."])
        let statement = String(repeating: "查", count: 1_400)   // 4,200 位元組
        p.references = (0..<260).map { i in
            ProvenanceReference(
                field: "resolution-undecided",
                value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "w\(i)a", literal: "Chen, C.").encoded,
                kind: .judgement(statement: statement, restsOn: []))
        }
        try store.writePerson(p)
        let health = store.health(from: try store.load())
        XCTAssertEqual(health.holderVerdictBudgetWarnings.map(\.owner), ["chen-c"], "260 筆 × 4.2 KB ≥ 1 MiB，節點數只有門檻的 2%")
        XCTAssertTrue(health.holderVerdictBudgetWarnings.first?.issue.message.contains("位元組") == true)
        XCTAssertTrue(health.venueVerdictBudgetWarnings.isEmpty, "venue 族不重複報 person")
    }

    /// 位元組門檻＝讀取預算的一半 ÷ 最壞的 YAML 跳脫（4.00×，第 18 列量過）；venue 族同一個門檻。
    func testByteThresholdIsDerivedAndSharedWithVenues() throws {
        XCTAssertEqual(AliasEventBudget.verdictByteWarningThreshold, AliasEventBudget.maxBytes / 2 / 4)
        var v = Venue(key: "big-journal", type: .periodical, names: TimelineOf([TemporalValue(value: "Big Journal")]))
        v.references = verdicts(3)
        try store.writeVenue(v)
        let load = try store.load()
        XCTAssertEqual(store.venueVerdictBudgetIssues(in: load, threshold: 1_000, byteThreshold: 10).count, 1, "venue 族也看位元組軸")
        XCTAssertTrue(store.venueVerdictBudgetIssues(in: load, threshold: 1_000, byteThreshold: 1_000_000).isEmpty)
    }

    /// 三個面都要提到（源碼掃描，#453 的同一形）。
    func testAllFacesMentionHolderVerdictBudgetWarnings() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let read = { (p: String) in try String(contentsOf: repo.appendingPathComponent(p), encoding: .utf8) }
        XCTAssertTrue(try read("Sources/AkashicMCPKit/AkashicService.swift").contains("health.holderVerdictBudgetWarnings"))
        XCTAssertTrue(try read("Sources/akashic/Commands.swift").contains("health.holderVerdictBudgetWarnings"))
        XCTAssertTrue(try read("Sources/AkashicAppKit/RecordIssuesSummary.swift").contains("health.holderVerdictBudgetWarnings"))
    }
}
