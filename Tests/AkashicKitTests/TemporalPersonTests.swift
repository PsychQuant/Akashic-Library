import XCTest
import Foundation
@testable import AkashicCore

/// #20：Person 成為 valid-time temporal 實體。
final class TemporalPersonTests: XCTestCase {

    // MARK: - 這個 issue 的動機：一筆真實的錯誤資料

    /// 使用者拍板做完整版的直接理由：`.dedup_researchers` 把多段任期壓成
    /// `min(start)` / `max(end)`，於是聲稱鄭清水 2003-01 至 2017-06 **連續**在職 14 年，
    /// 實際 2006-08 至 2013-07 有 7 年不在。可多段的結構直接修掉它。
    func testMultipleTenureSegmentsAreNotCollapsed() {
        let t = Timeline([
            TemporalValue(value: "ISS", range: DateRange(start: "2013-07", end: "2017-06")),
            TemporalValue(value: "ISS", range: DateRange(start: "2003-01", end: "2006-08")),
        ])
        XCTAssertEqual(t.sorted.map(\.range.start), ["2003-01", "2013-07"],
                       "兩段必須各自保留，不得被壓成一段")
        XCTAssertEqual(t.sorted.map(\.range.end), ["2006-08", "2017-06"])
        XCTAssertFalse(t.sorted[0].range.overlaps(t.sorted[1].range),
                       "中間的 7 年空檔必須看得出來")
    }

    // MARK: - 開放區間

    /// `nil` end ＝ **仍在進行中**，不是「未知」。用哨兵日期（`9999-12`）會讓兩者
    /// 無法區分，而且任何忘記處理哨兵的計算都會得到荒謬的區間長度。
    func testOpenRangeMeansOngoing() {
        let open = DateRange(start: "2020-01")
        XCTAssertTrue(open.isOpen)
        // 開放區間延伸到無限遠——與任何之後的區間重疊
        XCTAssertTrue(open.overlaps(DateRange(start: "2030-01", end: "2031-01")))
        XCTAssertFalse(open.overlaps(DateRange(start: "2010-01", end: "2019-12")))
    }

    func testCurrentPicksLatestOpenEntry() {
        let t = Timeline([
            TemporalValue(value: "助研究員", range: DateRange(start: "2010", end: "2015")),
            TemporalValue(value: "副研究員", range: DateRange(start: "2015", end: "2021")),
            TemporalValue(value: "研究員", range: DateRange(start: "2021")),
        ])
        XCTAssertEqual(t.current?.value, "研究員")
    }

    func testCurrentIsNilWhenAllClosed() {
        let t = Timeline([TemporalValue(value: "x", range: DateRange(start: "2010", end: "2015"))])
        XCTAssertNil(t.current, "全部結束時沒有現況——不得回傳最後一段當現況")
    }

    /// 重疊**回報而非拒絕**：一人同時兼兩個行政職是真的，爬取重複也是真的。
    /// 判斷屬於使用端，這裡只給事實。
    func testOverlapIsReportedNotRejected() {
        let t = Timeline([
            TemporalValue(value: "所長", range: DateRange(start: "2020", end: "2023")),
            TemporalValue(value: "代理副所長", range: DateRange(start: "2022", end: "2024")),
        ])
        XCTAssertEqual(t.overlappingPairs().count, 1)
        XCTAssertEqual(t.sorted.count, 2, "重疊不得使任何一段消失")
    }

    // MARK: - rank 混三種語意的拆解（#20 scope 變更 3）

    /// 來源的 `rank` 欄混了職級、行政職、聘任類型。不拆的話，「歷任所長」要對字串
    /// 做子字串比對，而「兼任研究員」會被算成一種職級。
    func testThreeSemanticsAreSeparateTimelines() {
        var p = PersonProfile()
        p.ranks = Timeline([TemporalValue(value: "研究員", range: DateRange(start: "2015"))])
        p.administrative = Timeline([
            TemporalValue(value: "所長", range: DateRange(start: "2020", end: "2023"))])
        p.appointments = Timeline([TemporalValue(value: "兼任", range: DateRange(start: "2024"))])
        XCTAssertEqual(p.ranks.current?.value, "研究員")
        XCTAssertNil(p.administrative.current, "所長任期已結束")
        XCTAssertEqual(p.appointments.current?.value, "兼任")
    }

    // MARK: - YAML round-trip（#23 說的「結構顯著變深」）

    func testProfileRoundTrips() throws {
        var p = Person(key: "cheng-ching-shui", names: ["鄭清水", "Cheng, Ching-Shui"])
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: .literal("ISS"), range: DateRange(start: "2003-01", end: "2006-08"),
                          source: "https://example.org/iss"),
            TemporalValue(value: .literal("ISS"), range: DateRange(start: "2013-07", end: "2017-06")),
        ])
        p.profile.ranks = Timeline([
            TemporalValue(value: "研究員", range: DateRange(start: "2013-07"))])
        p.profile.contacts = ["email": Timeline([
            TemporalValue(value: "a@example.org", range: DateRange(start: "2013"))])]

        let yaml = try PersonYAML.encode(p)
        XCTAssertEqual(try PersonYAML.decode(yaml), p)
    }

    /// 空 profile 不序列化——否則每個 person 檔都多一個空 map。
    func testEmptyProfileIsNotSerialised() throws {
        let yaml = try PersonYAML.encode(Person(key: "p-one", names: ["A"]))
        XCTAssertFalse(yaml.contains("profile"), yaml)
    }

    /// **輸出必須決定性**——同一份資料每次 encode 的順序相同，否則產生假 diff。
    func testEncodingIsDeterministicRegardlessOfInputOrder() throws {
        func make(_ order: [Int]) -> Person {
            // #241：id 是隨機 v4——determinism 斷言必須釘同一個顯式 id
            var p = Person(key: "p-one", names: ["A"],
                           id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
            let vs = [
                TemporalValue(value: "A", range: DateRange(start: "2010")),
                TemporalValue(value: "B", range: DateRange(start: "2005", end: "2010")),
                TemporalValue(value: "C", range: DateRange(start: "2000", end: "2005")),
            ]
            p.profile.ranks = Timeline(order.map { vs[$0] })
            p.profile.contacts = ["email": Timeline([TemporalValue(value: "e")]),
                                  "phone": Timeline([TemporalValue(value: "p")])]
            return p
        }
        XCTAssertEqual(try PersonYAML.encode(make([0, 1, 2])),
                       try PersonYAML.encode(make([2, 0, 1])))
    }

    /// known 欄位的**形狀**不符 fail-closed（§5：形狀演化不入 tolerant 範圍）。
    func testMalformedProfileIsRejected() {
        for bad in ["profile: \"字串\"\n",
                    "profile:\n  ranks: \"不是 sequence\"\n",
                    "profile:\n  ranks:\n    - novalue: x\n",
                    "profile:\n  unknownDimension: []\n"] {
            XCTAssertThrowsError(try PersonYAML.decode("id: 11111111-1111-4111-8111-111111111111\nkey: p\nnames: {variant: [A]}\n" + bad),
                                 bad.debugDescription)
        }
    }

    /// **舊 binary 的相容性**：profile 是 person 頂層的**新 known 欄位**。舊 binary
    /// 把它當未知欄位 tolerant 保留（#23），所以不需要 bump format——這是 additive。
    func testProfileIsAdditiveForOlderBinaries() throws {
        var p = Person(key: "p-one", names: ["A"])
        p.profile.ranks = Timeline([TemporalValue(value: "研究員")])
        let yaml = try PersonYAML.encode(p)
        // 模擬舊 binary：profile 不在 known 集合裡 → 應被 captureUnknownBlocks 收下
        XCTAssertTrue(yaml.contains("profile:"), yaml)
        XCTAssertTrue(yaml.contains("value: 研究員"), yaml)
    }
}
