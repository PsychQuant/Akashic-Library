import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #499（裁決：候選 3）：第 13 條邊在 venue 側維持序列化位置，但 O(catalog) 的增長要有一道**工具自己會看**的
/// 訊號——任一 venue 檔的 resolution verdict 數達 decode 預算的一半即 warning、指名該 venue。散文觸發條件沒有
/// 機制會叫醒任何人（`blocked-issues-must-be-scannable` 的誠實邊界），所以門檻住在 `StoreHealth`。
final class VenueVerdictBudgetWarningTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-vvb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func venue(withVerdicts n: Int) throws -> Venue {
        var v = Venue(key: "big-journal", type: .periodical,
                      names: TimelineOf([TemporalValue(value: "Big Journal")]))
        v.references = (0..<n).map { i in
            ProvenanceReference(
                field: "resolution-confirmed",
                value: ProvenanceReference.VerdictPairingValue(
                    holderKind: .work, holder: "w\(i)a", literal: "Big Journal").encoded,
                kind: .judgement(statement: "測試用判定", restsOn: []))
        }
        return v
    }

    /// 門檻＝讀取上限（檔案位元組）的一半。#499 原本以節點換算（11,111 筆），但節點軸只在檔案含 alias 時生效、store 檔
    /// 不含 alias——#645 R2 verify DA 以真 binary 量過：65,000 筆 verdict 的檔照常載入，8.7 MB 的檔才被 quarantine。
    func testThresholdIsHalfTheReadLimitInFileBytes() {
        XCTAssertEqual(AliasEventBudget.recordFileWarningBytes, AliasEventBudget.maxBytes / 2)
        XCTAssertGreaterThan(AliasEventBudget.recordFileWarningBytes, 268_627,
                             "live 最大刊（2026-09-26，268,627 bytes）不得已在門檻內——那會讓 warning 一上線就常態為真")
    }

    /// 達門檻 → 一筆 warning、owner 是那本 venue、訊息說出數字與處置；差一筆 → 零。
    func testVenueAtThresholdIsAWarningAndBelowIsNot() throws {
        let url = try store.writeVenue(try venue(withVerdicts: 40))
        let bytes = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        let load = try store.load()
        let issues = store.venueVerdictBudgetIssues(in: load, threshold: bytes)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.owner, "big-journal")
        XCTAssertEqual(issues.first?.kind, "venue")
        XCTAssertEqual(issues.first?.issue.severity, .warning)
        XCTAssertTrue(issues.first?.issue.message.hasPrefix(StoreHealth.venueVerdictBudgetPrefix) == true)
        XCTAssertTrue(issues.first?.issue.message.contains("resolution verdict 40 筆") == true, "\(issues.first!.issue.message)")
        XCTAssertTrue(store.venueVerdictBudgetIssues(in: load, threshold: bytes + 1).isEmpty)
    }

    /// 經 `health(from:)`（預設門檻）：一本 40 筆的刊不會出聲；`venueVerdictBudgetWarnings` 計算屬性存在且為空。
    func testHealthUsesTheDefaultThreshold() throws {
        try store.writeVenue(try venue(withVerdicts: 40))
        let health = store.health(from: try store.load())
        XCTAssertTrue(health.venueVerdictBudgetWarnings.isEmpty)
    }

    /// 兩面都要提到（源碼掃描，#453 的同一形）。
    func testBothFacesMentionVenueVerdictBudgetWarnings() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let service = try String(contentsOf: repo.appendingPathComponent("Sources/AkashicMCPKit/AkashicService.swift"), encoding: .utf8)
        let cli = try String(contentsOf: repo.appendingPathComponent("Sources/akashic/Commands.swift"), encoding: .utf8)
        XCTAssertTrue(service.contains("health.venueVerdictBudgetWarnings"))
        XCTAssertTrue(cli.contains("health.venueVerdictBudgetWarnings"))
    }
}
