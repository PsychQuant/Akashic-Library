import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #645：person 與 organization 的記錄檔逼近讀取上限時出聲——venue 側（#499）的同形擴充，同一個門檻、同一個量法。
/// 增長來源是一個人的著作數與不退役的 `resolution-undecided` 記錄（#619、#643）。量的是**檔案位元組**：store 檔不含
/// alias，讀取路徑上唯一會觸發的是 `maxBytes`（#645 R2 verify DA）。
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

    private func verdicts(_ n: Int, field: String = "resolution-confirmed", statement: String = "測試用判定") -> [ProvenanceReference] {
        (0..<n).map { i in
            ProvenanceReference(
                field: field,
                value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "w\(i)a", literal: "Chen, C.").encoded,
                kind: .judgement(statement: statement, restsOn: []))
        }
    }

    private func size(_ url: URL) throws -> Int {
        try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
    }

    /// 門檻是檔案本身的位元組數：恰好等於檔案大小 → 一筆 warning；大一 byte → 零。
    func testPersonFileAtThresholdIsAWarningAndBelowIsNot() throws {
        var p = Person(key: "chen-c", names: ["Chen, C."])
        p.references = verdicts(40)
        let url = try store.writePerson(p)
        let bytes = try size(url)
        let load = try store.load()
        let issues = store.holderVerdictBudgetIssues(in: load, threshold: bytes)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.owner, "chen-c")
        XCTAssertEqual(issues.first?.kind, "person")
        XCTAssertEqual(issues.first?.issue.severity, .warning)
        XCTAssertTrue(issues.first?.issue.message.hasPrefix(StoreHealth.holderVerdictBudgetPrefix) == true)
        XCTAssertTrue(issues.first?.issue.message.contains("\(bytes) 位元組") == true, "\(issues.first!.issue.message)")
        XCTAssertTrue(issues.first?.issue.message.contains("resolution verdict 40 筆") == true)
        XCTAssertTrue(store.holderVerdictBudgetIssues(in: load, threshold: bytes + 1).isEmpty)
    }

    func testOrganizationFileAtThresholdIsAWarning() throws {
        var o = Organization(key: "iss")
        o.names = TimelineOf([TemporalValue(value: "ISS", range: DateRange())])
        o.references = verdicts(12)
        let url = try store.writeOrganization(o)
        let issues = store.holderVerdictBudgetIssues(in: try store.load(), threshold: try size(url))
        XCTAssertEqual(issues.map(\.owner), ["iss"])
        XCTAssertEqual(issues.first?.kind, "organization")
    }

    /// 經 `health(from:)`（預設門檻 4 MiB）：以未決記錄把 person 檔推過門檻，warning 經 perRecord 出現；venue 族不重複報。
    /// 這也是 R1 verify 指出缺的那支——沒有它，拿掉 `perRecord += holderVerdictBudgetIssues` 不會有任何測試變紅。
    func testUndecidedRecordsPushAPersonFileOverTheDefaultThroughHealth() throws {
        var p = Person(key: "chen-c", names: ["Chen, C."])
        p.references = verdicts(1_000, field: "resolution-undecided", statement: String(repeating: "查", count: 1_400))
        let url = try store.writePerson(p)
        XCTAssertGreaterThanOrEqual(try size(url), AliasEventBudget.recordFileWarningBytes, "前提：檔案確實過了門檻")
        XCTAssertLessThan(try size(url), AliasEventBudget.maxBytes, "前提：仍讀得回來（否則會被 quarantine、根本不在 load 裡）")
        let health = store.health(from: try store.load())
        XCTAssertEqual(health.holderVerdictBudgetWarnings.map(\.owner), ["chen-c"])
        XCTAssertTrue(health.venueVerdictBudgetWarnings.isEmpty, "venue 族不掃 person")
    }

    /// 門檻＝讀取上限的一半；live 最大檔（268,627 bytes，2026-09-26）不得已在門檻內。
    func testThresholdIsHalfTheReadLimit() {
        XCTAssertEqual(AliasEventBudget.recordFileWarningBytes, AliasEventBudget.maxBytes / 2)
        XCTAssertGreaterThan(AliasEventBudget.recordFileWarningBytes, 268_627)
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
