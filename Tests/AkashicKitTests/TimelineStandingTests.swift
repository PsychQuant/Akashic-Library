import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicExport

/// #663：一條隸屬時間軸「現況怎麼說」只有一個推導（`TimelineOf.standing`）。
///
/// 在此之前匯出端有 `researcherStatus`（#661：只被觀測到的隸屬是 `undetermined`），而 CLI、MCP、App 三個讀取面各自寫
/// `current ?? latestPastSegment`——`latestPastSegment` 的分層規則讓有 end 的段勝過觀測段，於是三個面把只被觀測到的隸屬說成
/// 「曾隸屬」（一個離開的斷言），混合情形（NTU 2000–2010 加 2015 年在 ISS 的觀測）觀測段整個不見，而匯出對同一人說
/// `undetermined`。`entity-backlink-completeness` 執行細節 2：一個讀取面只能有一條實作路徑。
///
/// 四種形狀是 issue 的驗收矩陣：只被觀測到、只有 end（含 ended-unknown）、混合、現職。
final class TimelineStandingTests: XCTestCase {

    typealias Seg = TemporalValue<String>

    private func tl(_ segs: [Seg]) -> TimelineOf<String> { TimelineOf(segs) }

    private var attestedOnly: TimelineOf<String> {
        tl([Seg(value: "ISS", range: DateRange(attested: ["2019-05", "2021"]))])
    }
    private var onlyEnded: TimelineOf<String> {
        tl([Seg(value: "ISS", range: DateRange(start: "2010", end: "2018")),
            Seg(value: "NTU", range: DateRange(endedUnknown: true))])
    }
    /// issue 的例子：NTU 2000–2010 加 2015 年在 ISS 的觀測
    private var mixed: TimelineOf<String> {
        tl([Seg(value: "NTU", range: DateRange(start: "2000", end: "2010")),
            Seg(value: "ISS", range: DateRange(attested: ["2015"]))])
    }
    private var current: TimelineOf<String> {
        tl([Seg(value: "NTU", range: DateRange(start: "2000", end: "2010")),
            Seg(value: "ISS", range: DateRange(start: "2020"))])
    }
    /// 有現職、又有一段只被觀測到的：現職說了算
    private var currentWithObservation: TimelineOf<String> {
        tl([Seg(value: "ISS", range: DateRange(start: "2020")),
            Seg(value: "NTU", range: DateRange(attested: ["2012"]))])
    }

    func testEmptyTimelineHasNoStanding() {
        XCTAssertNil(TimelineOf<String>().standing, "沒有資料就沒有現況——不猜成 current，也不猜成 retired")
    }

    func testAttestedOnlyIsUndeterminedAndCarriesTheObservationNotAnEnd() throws {
        let s = try XCTUnwrap(attestedOnly.standing)
        XCTAssertEqual(s.status, .undetermined, "被看到過不等於離開了（#661）")
        XCTAssertNil(s.current)
        XCTAssertNil(s.lastEnded, "沒有任何一段宣稱結束——不得有「曾隸屬」可說")
        XCTAssertEqual(s.lastObserved?.value, "ISS")
        XCTAssertEqual(s.lastObserved?.range.attested.max(), "2021")
    }

    func testOnlyEndedIsRetired() throws {
        let s = try XCTUnwrap(onlyEnded.standing)
        XCTAssertEqual(s.status, .retired)
        XCTAssertNil(s.current)
        XCTAssertNil(s.lastObserved)
        XCTAssertEqual(s.lastEnded?.value, "ISS", "有已知 end 的層勝過 ended-unknown 的層")
        XCTAssertEqual(s.lastEnded?.range.end, "2018")
    }

    func testEndedUnknownAloneIsStillRetiredWithALastEndedSegment() throws {
        let s = try XCTUnwrap(tl([Seg(value: "NTU", range: DateRange(endedUnknown: true))]).standing)
        XCTAssertEqual(s.status, .retired)
        XCTAssertEqual(s.lastEnded?.value, "NTU", "ended-unknown 是已結束（#63），不是觀測")
        XCTAssertNil(s.lastObserved)
    }

    /// **混合情形兩者都要看得到**——`latestPastSegment` 單獨用會讓有 end 的段勝過觀測段，觀測段整個不見。
    func testMixedCarriesBothTheEndedAndTheObservedSegment() throws {
        let s = try XCTUnwrap(mixed.standing)
        XCTAssertEqual(s.status, .undetermined, "混合一律 undetermined（#661 刻意的保守裁決）")
        XCTAssertEqual(s.lastEnded?.value, "NTU")
        XCTAssertEqual(s.lastEnded?.range.end, "2010")
        XCTAssertEqual(s.lastObserved?.value, "ISS")
        XCTAssertEqual(s.lastObserved?.range.attested, ["2015"])
        XCTAssertEqual(mixed.latestPastSegment?.value, "NTU",
                       "對照：舊的單一挑選在混合情形只看得到 NTU——這正是三個面漏掉觀測段的原因")
    }

    func testCurrentWinsAndTheOtherFieldsStayAvailableToTheCaller() throws {
        let s = try XCTUnwrap(current.standing)
        XCTAssertEqual(s.status, .current)
        XCTAssertEqual(s.current?.value, "ISS")
        XCTAssertEqual(s.lastEnded?.value, "NTU")
        let w = try XCTUnwrap(currentWithObservation.standing)
        XCTAssertEqual(w.status, .current, "有開放的段就是現職，觀測段不改變這一點")
        XCTAssertEqual(w.current?.value, "ISS")
        XCTAssertEqual(w.lastObserved?.value, "NTU")
    }

    /// 兩個入口不得分岔：`latestPastSegment` 就是「已結束的層」優先、其次「只被觀測到的層」。
    func testLatestPastSegmentIsTheEndedLayerThenTheObservedLayer() {
        for t in [attestedOnly, onlyEnded, mixed, current, currentWithObservation] {
            let s = t.standing
            XCTAssertEqual(t.latestPastSegment, s?.lastEnded ?? s?.lastObserved)
        }
    }

    /// 匯出端說的與 `standing` 說的是同一件事——四種形狀逐一對。
    func testExportStatusIsTheStandingStatus() throws {
        let shapes: [(String, TimelineOf<String>, String?)] = [
            ("attested-only", attestedOnly, "undetermined"),
            ("only-ended", onlyEnded, "retired"),
            ("mixed", mixed, "undetermined"),
            ("current", current, "current"),
            ("current-with-observation", currentWithObservation, "current"),
            ("empty", TimelineOf<String>(), nil),
        ]
        for (label, t, want) in shapes {
            var p = Person(key: "p-\(label)", names: ["P"])
            p.profile.affiliations = TimelineOf(t.entries.map {
                TemporalValue(value: OrgRef.literal($0.value), range: $0.range)
            })
            let tables = RelationalExport.tables(entries: [], people: [p])
            let col = try XCTUnwrap(tables.researcher.columns.firstIndex(of: "status"))
            XCTAssertEqual(tables.researcher.rows[0][col], want, label)
            XCTAssertEqual(p.profile.affiliations.standing?.status.rawValue, want, label)
        }
    }

    // MARK: - 單一路徑守衛

    /// 讀取面不得自己再推導一次。`latestPastSegment` 是 Core 內部的挑選規則，讀取面要的是 `standing`——
    /// 直接用它就是回到「`current ?? latestPastSegment`」那條會漏掉觀測段的路。
    static func offendingFiles(_ sources: [String: String]) -> [String] {
        // 定義它的兩個檔，加上欄位棘輪的資料檔（只是把成員名寫成字串，`Temporal.latestPastSegment`）
        let allowed: Set<String> = ["Sources/AkashicCore/Temporal.swift", "Sources/AkashicCore/TimelineStanding.swift",
                                    "Sources/akashic-guards/BacklinkRatchetData.swift"]
        return sources.filter { !allowed.contains($0.key) && $0.value.contains("latestPastSegment") }.keys.sorted()
    }

    /// 負控：掃描函式真的認得違規（沒有它，「0 個違規」與「掃描壞了」在輸出上一樣）
    func testTheScanRecognisesAViolationAndAllowsTheCoreFiles() {
        XCTAssertEqual(Self.offendingFiles(["Sources/akashic/X.swift": "let a = t.current ?? t.latestPastSegment"]),
                       ["Sources/akashic/X.swift"])
        XCTAssertEqual(Self.offendingFiles(["Sources/AkashicCore/Temporal.swift": "public var latestPastSegment"]), [])
        XCTAssertEqual(Self.offendingFiles(["Sources/akashic/X.swift": "let a = t.standing"]), [])
    }

    func testNoReadSurfaceCallsLatestPastSegmentDirectly() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sourcesDir = root.appendingPathComponent("Sources")
        var sources: [String: String] = [:]
        let en = try XCTUnwrap(FileManager.default.enumerator(at: sourcesDir, includingPropertiesForKeys: nil))
        for case let url as URL in en where url.pathExtension == "swift" {
            let rel = String(url.path.dropFirst(root.path.count + 1))
            sources[rel] = try String(contentsOf: url, encoding: .utf8)
        }
        XCTAssertGreaterThan(sources.count, 100, "前提：真的掃到了原始碼（\(sources.count) 個檔）")
        XCTAssertNotNil(sources["Sources/AkashicCore/Temporal.swift"], "前提：允許清單裡的檔真的在")
        XCTAssertEqual(Self.offendingFiles(sources), [],
                       "讀取面要用 `standing`，不要直接用 `latestPastSegment`（#663：三個面各自推導曾與匯出分岔）")
    }
}
