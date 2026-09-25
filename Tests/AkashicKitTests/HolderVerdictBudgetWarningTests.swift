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
