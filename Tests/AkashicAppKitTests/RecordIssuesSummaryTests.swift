import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicAppKit

/// #487：App 面不渲染 `perRecordIssues`——只有 per-record warning（含死 verdict）的 store 在 App 上什麼都看不到。
/// 本測試在 `AppState` 層與純模型層：注入一筆死 verdict → 摘要非 nil、死 verdict 計 1；乾淨 store → nil（沉默即健康）；
/// 源碼掃描釘住 `SidebarView` 掛了 `RecordIssuesSection` 且它**不在** `hasFindings` 閘內。
final class RecordIssuesSummaryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-ris-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try store.writeEntry(Entry(id: UUID(), citekey: "alive2020a", type: .periodicalArticle,
                                   title: "T", authors: [.literal("A B")], date: "2020"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func verdict(holder: String) -> ProvenanceReference {
        ProvenanceReference(
            field: "resolution-confirmed",
            value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: holder,
                                                           literal: "Some Author").encoded,
            kind: .judgement(statement: "測試用判定", restsOn: []))
    }

    /// 一筆死 verdict → App 的 health 持有它，摘要非 nil、死 verdict 計 1、help 含那筆的 owner 與「akashic validate」。
    func testDeadVerdictReachesTheAppSummary() throws {
        let store = LibraryStore(root: root)
        var p = Person(key: "some-author", names: PersonNames(variant: ["Some Author"]))
        p.references = [verdict(holder: "gone2019z")]
        try store.writePerson(p)
        let state = AppState(root: root)
        try state.load()
        let health = try XCTUnwrap(state.health)
        let summary = try XCTUnwrap(RecordIssuesSummary(health: health))
        XCTAssertEqual(summary.deadVerdicts, 1)
        XCTAssertGreaterThanOrEqual(summary.total, 1)
        XCTAssertEqual(summary.errors, 0, "死 verdict 是 warning——hasFindings 不會亮，這正是本 Section 存在的理由")
        XCTAssertFalse(health.hasFindings)
        XCTAssertTrue(summary.help.contains("some-author"))
        XCTAssertTrue(summary.help.contains("akashic validate"))
    }

    /// #450：拆分後的孤兒 verdict 也要到得了 App 的摘要——三面（CLI／MCP／App）對這一族的計數不得分岔
    /// （#453 對 CLI／MCP 的同一條紀律）。person 持有 `work:alive2020a :: A B` 的 rejected verdict，而 alive2020a
    /// 已把「A B」拆成「A」「B」（拆分記錄在 work 側）→ 孤兒 1、各段全不在 0。
    func testOrphanedSplitVerdictReachesTheAppSummary() throws {
        let store = LibraryStore(root: root)
        var e = try XCTUnwrap(try store.load().entries.first { $0.citekey == "alive2020a" })
        e.authors = [.literal("A"), .literal("B")]
        let record = try XCTUnwrap(SplitRecordValue(parts: ["A", "B"], reason: "測試用拆分"))
        e.references = [ProvenanceReference(field: "authors", value: "A B",
                                            kind: .judgement(statement: record.encoded, restsOn: []))]
        try store.writeEntry(e)
        var p = Person(key: "p-one", names: PersonNames(variant: ["A B"]))
        p.references = [ProvenanceReference(
            field: "resolution-rejected",
            value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "alive2020a", literal: "A B").encoded,
            kind: .judgement(statement: "測試用否決", restsOn: []))]
        try store.writePerson(p)
        let state = AppState(root: root)
        try state.load()
        let summary = try XCTUnwrap(RecordIssuesSummary(health: try XCTUnwrap(state.health)))
        XCTAssertEqual(summary.orphanedSplitVerdicts, 1)
        XCTAssertEqual(summary.staleSplitRecords, 0, "「A」「B」都仍是作者位")
        XCTAssertEqual(summary.errors, 0, "warning，不亮 hasFindings")
        XCTAssertTrue(summary.help.contains("p-one"), summary.help)
    }

    /// 乾淨 store → nil（沉默即健康）。
    func testCleanStoreHasNoSummary() throws {
        let store = LibraryStore(root: root)
        var p = Person(key: "some-author", names: PersonNames(variant: ["Some Author"]))
        p.references = [verdict(holder: "alive2020a")]
        try store.writePerson(p)
        let state = AppState(root: root)
        try state.load()
        XCTAssertNil(RecordIssuesSummary(health: try XCTUnwrap(state.health)))
    }

    /// help 的預覽有上限，超過的筆數以「另 N 則」說出（不靜默截斷——lossless-intake 執行細節 3）。
    func testHelpPreviewIsBoundedAndSaysHowManyMore() throws {
        let store = LibraryStore(root: root)
        var p = Person(key: "some-author", names: PersonNames(variant: ["Some Author"]))
        p.references = (0..<7).map { verdict(holder: "gone\($0)z") }
        try store.writePerson(p)
        let state = AppState(root: root)
        try state.load()
        let summary = try XCTUnwrap(RecordIssuesSummary(health: try XCTUnwrap(state.health), previewLimit: 5))
        XCTAssertEqual(summary.deadVerdicts, 7)
        XCTAssertTrue(summary.help.contains("另 2 則"), summary.help)
    }

    /// `SidebarView` 掛了 `RecordIssuesSection`，且那一行不在 `hasFindings` 的 if 區塊內（獨立的閘）。
    func testSidebarMountsTheSectionOutsideTheHasFindingsGate() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let src = try String(contentsOf: repo.appendingPathComponent("Sources/AkashicAppKit/ContentView.swift"), encoding: .utf8)
        guard let mount = src.range(of: "RecordIssuesSection(") else {
            return XCTFail("SidebarView 沒有掛 RecordIssuesSection——#487 的缺口原樣")
        }
        // 閘的形狀：掛載那一行之前最近的 `if let health = state.health` 不得帶 `health.hasFindings`
        let before = src[..<mount.lowerBound]
        guard let gate = before.range(of: "if let health = state.health", options: .backwards) else {
            return XCTFail("掛載處之前找不到 health 的 if let")
        }
        let gateLine = before[gate.lowerBound...].split(separator: "\n").first.map(String.init) ?? ""
        XCTAssertFalse(gateLine.contains("hasFindings"),
                       "RecordIssuesSection 掛在 hasFindings 閘內——那個閘只計 error，warning 永遠看不到：\(gateLine)")
        XCTAssertTrue(src.contains("RecordIssuesSummary(health:"), "掛載要經過純模型摘要")
    }


    /// 配對唯一性的兩半（#554 R11 D28、R14 D36）也要到得了 App 的摘要——三面對這兩族的計數不得分岔（R14 verify regression
    /// 第 22 列：兩族沒有 StoreHealth 家族，App 預覽 5 則時可能完全看不到）。
    func testPairingUniquenessFamiliesReachTheAppSummary() throws {
        let store = LibraryStore(root: root)
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
        v.references = [ProvenanceReference(field: "resolution-confirmed",
                                            value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "alive2020a", literal: "Alpha Journal").encoded,
                                            kind: .judgement(statement: "測試", restsOn: [])),
                        ProvenanceReference(field: "resolution-confirmed",
                                            value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "alive2020a", literal: "Beta Review").encoded,
                                            kind: .judgement(statement: "測試", restsOn: []))]
        try store.writeVenue(v)
        var e = try XCTUnwrap(try store.load().entries.first { $0.citekey == "alive2020a" })
        e.venues = [.key("alpha"), .key("alpha")]
        try store.writeEntry(e)
        let state = AppState(root: root)
        try state.load()
        let summary = try XCTUnwrap(RecordIssuesSummary(health: try XCTUnwrap(state.health)))
        XCTAssertEqual(summary.confirmedLiteralAmbiguities, 1)
        XCTAssertEqual(summary.duplicateVenueEdges, 1)
        XCTAssertEqual(summary.errors, 0, "兩族都是 warning")
    }
}
