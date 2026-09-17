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
        XCTAssertEqual(summary.cappedRecords, 0)
        XCTAssertEqual(summary.lowerBound(summary.duplicateVenueEdges), "1", "沒有記錄被截：計數是精確的，不標下限")
    }

    /// R18（D54；R17 verify Codex 第 2 列）：被截的記錄數要到得了 App——家族計數是下限，三面都要說得出「還有」。
    func testCappedRecordsReachTheAppSummary() throws {
        let store = LibraryStore(root: root)
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
        v.references = (1...25).flatMap { w in ["Alpha Journal", "Beta Review"].map { lit in
            ProvenanceReference(field: "resolution-confirmed",
                                value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "w\(w)", literal: lit).encoded,
                                kind: .judgement(statement: "測試", restsOn: [])) } }
        try store.writeVenue(v)
        for w in 1...25 { try store.writeEntry(Entry(id: UUID(), citekey: "w\(w)", type: .periodicalArticle, title: "T", authors: [.literal("A B")], date: "2020")) }
        let state = AppState(root: root)
        try state.load()
        let summary = try XCTUnwrap(RecordIssuesSummary(health: try XCTUnwrap(state.health)))
        XCTAssertEqual(summary.confirmedLiteralAmbiguities, 20)
        XCTAssertEqual(summary.cappedRecords, 1)
        // R19（D57；R18 verify Codex 第 3 列）：有記錄被截時家族的值要標成下限——20 是「至少 20」
        XCTAssertEqual(summary.lowerBound(summary.confirmedLiteralAmbiguities), "≥ 20")
        XCTAssertEqual(summary.lowerBound(summary.deadVerdicts), "≥ 0")
    }

    /// R18 verify Codex 第 3 列：`cappedRecords` 到得了摘要（R18 D54）卻沒有任何 View 消費它——側欄的家族計數仍是裸數字，使用者看不出
    /// 那是下限。R19（D57）：`RecordIssuesSection` 渲染「被截的記錄」一列，且每個家族的值經 `summary.lowerBound`（有記錄被截時前綴「≥」）。
    /// 源碼掃描（去掉 `//` 註解）釘住兩件事——與 `testSidebarMountsTheSectionOutsideTheHasFindingsGate` 同一種守衛。
    func testSectionRendersCappedRecordsAndMarksFamilyCountsAsLowerBounds() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let raw = try String(contentsOf: repo.appendingPathComponent("Sources/AkashicAppKit/RecordIssuesSection.swift"), encoding: .utf8)
        let code = raw.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let s = String(line)
            if let r = s.range(of: "//") { return String(s[..<r.lowerBound]) }
            return s
        }.joined(separator: "\n")
        // 兩件都要在：閘與值（只查 `summary.cappedRecords` 出現過會被 `.help` 字串裡的插值滿足——R19 負控 NC6 抓到的假綠）
        XCTAssertTrue(code.contains("if summary.cappedRecords > 0 {"), "RecordIssuesSection 沒有以 cappedRecords 閘出一列——doctor 面說得出「還有幾筆被截」而 App 面說不出")
        XCTAssertTrue(code.contains("LabeledContent(\"被截的記錄\", value: \"\\(summary.cappedRecords)\")"), "「被截的記錄」那一列的值要是 cappedRecords 本身")
        // R20（R19 verify requirements 第 5 列、DA 第 13 列）：名冊用反射取自型別本身，不寫死；且釘在 `value:` 的位置上——
        // 只查呼叫出現過會被 `.help` 裡的插值滿足（同一函式裡對同一風險曾有兩種標準）。`total`／`errors` 也是下限（D59），一起釘。
        let store = LibraryStore(root: root)
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
        v.references = [ProvenanceReference(field: "resolution-confirmed",
                                            value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "w1", literal: "Alpha Journal").encoded,
                                            kind: .judgement(statement: "測試", restsOn: [])),
                        ProvenanceReference(field: "resolution-confirmed",
                                            value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "w1", literal: "Beta Review").encoded,
                                            kind: .judgement(statement: "測試", restsOn: []))]
        try store.writeVenue(v)
        try store.writeEntry(Entry(id: UUID(), citekey: "w1", type: .periodicalArticle, title: "T", authors: [.literal("A B")], date: "2020"))
        let summary = try XCTUnwrap(RecordIssuesSummary(health: store.health(from: try store.load())))
        let counters = Mirror(reflecting: summary).children.compactMap { child -> String? in
            guard let label = child.label, child.value is Int, label != "cappedRecords" else { return nil }
            return label
        }
        XCTAssertGreaterThanOrEqual(counters.count, 11, "反射應看到 total、errors 與各家族：\(counters)")
        XCTAssertTrue(counters.contains("contradictoryVerdicts"), "#486 的家族要到得了 App（R19 verify DA 第 12 列）：\(counters)")
        for name in counters {
            XCTAssertTrue(code.contains("value: summary.lowerBound(summary.\(name)))"), "\(name) 的值沒有在 value: 的位置經 lowerBound——被截時它是下限")
        }
    }

    /// R19 verify DA 第 12 列：`StoreHealth.contradictoryVerdicts`（#486）全樹零消費——doctor 與 App 兩面都沒有這一族，而加家族的理由
    /// （截 20 則／預覽 5 則時可能完全看不到）對矛盾 verdict 一字不改地成立；rename 剛製造出來的矛盾對兩面都沒有計數可看。
    func testContradictoryVerdictsReachTheAppSummary() throws {
        let store = LibraryStore(root: root)
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
        v.references = ["resolution-confirmed", "resolution-rejected"].map { field in
            ProvenanceReference(field: field,
                                value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "w1", literal: "Alpha Journal").encoded,
                                kind: .judgement(statement: "測試", restsOn: [])) }
        try store.writeVenue(v)
        try store.writeEntry(Entry(id: UUID(), citekey: "w1", type: .periodicalArticle, title: "T", authors: [.literal("A B")], date: "2020"))
        let summary = try XCTUnwrap(RecordIssuesSummary(health: store.health(from: try store.load())))
        XCTAssertEqual(summary.contradictoryVerdicts, 1)
        XCTAssertEqual(summary.cappedRecords, 0)
        XCTAssertEqual(summary.lowerBound(summary.total), "\(summary.total)", "沒有記錄被截：total 精確")
    }

    /// R15 verify 第 16 列：App 預覽對已消毒的訊息再過一次 `displaySafe(_, max: 160)`——反斜線被逃成 U+005C，且 160 把家族前綴之後的
    /// 正文截光。R16：只截不逃、上限 300。
    func testHelpPreviewDoesNotEscapeMessagesTwice() throws {
        let store = LibraryStore(root: root)
        func confirmed(_ literal: String) -> ProvenanceReference {
            ProvenanceReference(field: "resolution-confirmed",
                                value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: "alive2020a", literal: literal).encoded,
                                kind: .judgement(statement: "測試", restsOn: []))
        }
        var v = Venue(key: "alpha", type: .periodical, names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [])
        v.references = [confirmed("Alpha\u{200B}Journal"), confirmed("Beta Journal")]
        try store.writeVenue(v)
        let summary = try XCTUnwrap(RecordIssuesSummary(health: store.health(from: try store.load())))
        XCTAssertEqual(summary.confirmedLiteralAmbiguities, 1)
        XCTAssertTrue(summary.help.contains("\\u{200B}"), summary.help)
        XCTAssertFalse(summary.help.contains("\\u{005C}"), summary.help)
        XCTAssertTrue(summary.help.contains("D23"), "160 的上限把正文截掉了：\(summary.help)")
    }

    /// #554 R27（R26 verify regression 第 3 列 HIGH、security 第 36 列）：同一個 `LabeledContent` 疊兩個 `.help(` 時 SwiftUI 只顯示一個——R26 為 D71 的
    /// 揭露疊了第二個，既有的處置指引與新的限定詞二擇一消失，而源碼掃描守衛對兩段文字都在的檔案照樣綠。一列恰好一個 `.help(`。
    func testEveryRecordIssuesRowCarriesAtMostOneHelp() throws {
        var u = URL(fileURLWithPath: #filePath)
        while u.lastPathComponent != "Tests" { u.deleteLastPathComponent() }
        let file = u.deletingLastPathComponent().appendingPathComponent("Sources/AkashicAppKit/RecordIssuesSection.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        let rows = text.components(separatedBy: "LabeledContent(").dropFirst()
        XCTAssertGreaterThan(rows.count, 5, "fixture：RecordIssuesSection 的列數")
        for (i, row) in rows.enumerated() {
            let helps = row.components(separatedBy: ".help(").count - 1
            XCTAssertLessThanOrEqual(helps, 1, "第 \(i + 1) 列掛了 \(helps) 個 .help(——只有一個會顯示")
        }
    }

    /// #554 R31（R30 verify 第 22 列）：預覽的每則訊息只截、上限 300 個**輸出** scalar——R16 起就是；R30 抬到 2,400（誤把「輸入上限 ×8」的
    /// 平準套到一個本來就是輸出上限的格）。這裡把數字釘在原始碼：改它要同時改這裡與 `SanitizationBoundaryTests` 的 sink 表。
    func testHelpPreviewClipBoundIsPinnedAtThreeHundred() throws {
        let src = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/AkashicAppKit/RecordIssuesSummary.swift"), encoding: .utf8)
        XCTAssertTrue(src.contains("displaySafeClipOnly($0.issue.message, max: 300)"), "預覽上限不是 300")
        XCTAssertFalse(src.contains("issue.message, max: 2_400"))
    }
}
