import XCTest
@testable import AkashicCore
@testable import AkashicExport
@testable import AkashicStoreIO

/// #63：「已結束，但結束日期未知」的一等表達。
///
/// 具體案例：43 位退休 PI 只有「已退休」的事實、沒有退休年份——`end: nil` 語意是
/// 進行中（整批被算成現職）、捏造年份是偽造資料、塞 `note` 不參與計算。
/// 依 issue 選項 3（additive）：`ended: true` + `end` 缺席 = 已結束、時點未知。
final class EndedUnknownTests: XCTestCase {

    // MARK: - DateRange 語意

    func testEndedUnknownRangeIsNotOpen() {
        let r = DateRange(start: "2003", endedUnknown: true)
        XCTAssertFalse(r.isOpen, "已結束（時點未知）不是進行中——isOpen 是 current 推導的根")
    }

    func testPlainOpenRangeSemanticsUnchanged() {
        XCTAssertTrue(DateRange(start: "2003").isOpen, "既有語意不變：end 缺席且未標 ended ＝ 進行中")
        XCTAssertFalse(DateRange(start: "2003", end: "2010").isOpen)
    }

    func testCurrentExcludesEndedUnknownSegments() {
        let t = Timeline([
            TemporalValue(value: "ISS", range: DateRange(start: "1990", endedUnknown: true)),
        ])
        XCTAssertNil(t.current, "退休（時點未知）的段不是 current——43 位退休 PI 不得被算成現職")
    }

    func testCurrentStillPicksTrulyOpenSegment() {
        let t = Timeline([
            TemporalValue(value: "舊單位", range: DateRange(start: "1990", endedUnknown: true)),
            TemporalValue(value: "現單位", range: DateRange(start: "2010")),
        ])
        XCTAssertEqual(t.current?.value, "現單位")
    }

    /// overlaps 的誠實選擇：無端點無從排除重疊——保守視為開放（多報不漏報）。
    func testEndedUnknownOverlapsConservatively() {
        let unknown = DateRange(start: "1990", endedUnknown: true)
        let later = DateRange(start: "2020")
        XCTAssertTrue(unknown.overlaps(later),
                      "不知何時結束＝無從排除重疊——保守判重疊，交由人工裁決")
    }

    // MARK: - YAML round-trip

    func testPersonProfileEndedRoundTrips() throws {
        var p = Person(key: "wang-old", names: ["Wang Old"])
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: .literal("中研院統計所"),
                          range: DateRange(start: "1985", endedUnknown: true),
                          source: "所方網頁退休名單"),
        ])
        let yaml = try PersonYAML.encode(p)
        XCTAssertTrue(yaml.contains("ended: true"), "已結束（時點未知）必須落檔：\n\(yaml)")
        let back = try PersonYAML.decode(yaml)
        XCTAssertEqual(back.profile.affiliations.entries.first?.range.endedUnknown, true)
        XCTAssertNil(back.profile.affiliations.current, "round-trip 後仍不是 current")
    }

    func testEndedAbsentIsNotEmitted() throws {
        var p = Person(key: "wang-now", names: ["Wang Now"])
        p.profile.ranks = Timeline([
            TemporalValue(value: "研究員", range: DateRange(start: "2010")),
        ])
        let yaml = try PersonYAML.encode(p)
        XCTAssertFalse(yaml.contains("ended"), "預設值不落檔——diff 噪音與 schema 汙染")
    }

    /// `end` 有值時 `ended: true` 是矛盾——end 本身就是「已結束於此」，兩者並存
    /// 無法判斷哪個是真話。拒絕，不猜。
    func testEndWithEndedTrueIsRejected() throws {
        let yaml = """
            key: bad-person
            names: [Bad]
            profile:
              ranks:
              - value: 研究員
                start: "2010"
                end: "2020"
                ended: true
            """
        XCTAssertThrowsError(try PersonYAML.decode(yaml),
                             "end 有值 + ended: true 是矛盾組合——拒絕，不猜哪個是真話")
    }

    func testEndedFalseIsTolerated() throws {
        // `ended: false` 冗餘但無矛盾（等同缺席）——寬容讀入、不寫出
        let yaml = """
            key: ok-person
            names: [Ok]
            profile:
              ranks:
              - value: 研究員
                start: "2010"
                ended: false
            """
        let p = try PersonYAML.decode(yaml)
        XCTAssertEqual(p.profile.ranks.entries.first?.range.endedUnknown, false)
        XCTAssertNotNil(p.profile.ranks.current, "ended: false ＝ 照常進行中")
    }

    // MARK: - format bump（#63 是 non-additive）

    /// 「看似 additive 其實不是」：tolerant-preserve 的開放層只涵蓋記錄頂層與
    /// akashic namespace——時間軸**段內**的鍵是 strict（rejectUnknownKeys），
    /// 舊 binary 讀到 `ended:` 是**整檔 quarantine**（人檔消失），不是保留。
    /// refuse-if-newer 的「請升級」遠比 per-file quarantine 誠實 → MUST bump。
    func testEndedRequiresFormatBump() {
        XCTAssertGreaterThanOrEqual(StoreVersion.supported, 6,
                                    "#63 的 ended 是段內新鍵——舊 binary quarantine 整檔，non-additive")
    }

    // MARK: - status 推導（#63 的實際案例）

    func testRetiredPIWithUnknownEndIsExportedAsRetired() throws {
        var p = Person(key: "retired-pi", names: ["Retired PI"])
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: .literal("中研院統計所"),
                          range: DateRange(start: "1985", endedUnknown: true)),
        ])
        let table = RelationalExport.tables(entries: [], people: [p]).researcher
        let statusIdx = try XCTUnwrap(table.columns.firstIndex(of: "status"))
        XCTAssertEqual(table.rows.first?[statusIdx], "retired",
                       "退休（時點未知）→ status=retired——#63 的 43 位 PI 場景")
    }
}
