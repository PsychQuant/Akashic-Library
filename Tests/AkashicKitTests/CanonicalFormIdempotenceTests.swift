import XCTest
import Foundation
@testable import AkashicCore

/// #69：正規化必須**一次到達不動點**。
///
/// canonical form 的定義住在 encoder 裡，正規化即 `encode(decode(x))`。若那不是冪等的，
/// `akashic fmt` 每跑一次就產生一次 diff——工具與版控互相對抗，最後沒人敢跑它。
///
/// 冪等性的論證：序列化是 `entries` 陣列的**純函式**，而 decode 保留陣列順序。
/// 所以 `f(f(x)) == f(x)`。這個測試把論證釘成可執行的斷言。
final class CanonicalFormIdempotenceTests: XCTestCase {

    private func normalize(_ yaml: String) throws -> String {
        try PersonYAML.encode(try PersonYAML.decode(yaml))
    }

    /// requirement **Normalization SHALL reach a fixed point in one pass**。
    ///
    /// 輸入刻意是**反時間序**的 affiliations——那是外部 pipeline 真實會產生的形狀
    /// （寫入者按自己的迴圈順序寫，不按時間）。
    func testNormalizingTwiceIsStable() throws {
        let input = """
        person:
        id: 11111111-1111-4111-8111-111111111111
        key: cheng-ching-shui
        names:
        - Cheng, Ching-Shui
        authorized:
        - Cheng, Ching-Shui
        profile:
          affiliations:
          - value:
              literal: ISS
            start: 2013-07
            end: 2017-06
          - value:
              literal: ISS
            start: 2003-01
            end: 2006-08
        """ + "\n"

        let x = try normalize(input)
        let y = try normalize(x)

        XCTAssertNotEqual(x, input, "輸入是反時間序的，正規化必須改變它——否則這個測試沒測到東西")
        XCTAssertEqual(y, x, "第二次正規化必須是 no-op；不是的話 1.2 的排序不是不動點")
    }

    /// 不動點性質對**已經 canonical** 的輸入同樣成立（f(x) == x）。
    /// 與上一個測試互補：那個測「會收斂」，這個測「收斂後不再動」。
    func testAlreadyCanonicalInputIsUnchanged() throws {
        var p = Person(key: "cheng", names: ["C"], authorized: ["C"])
        p.profile.ranks = Timeline([
            TemporalValue(value: "助研究員", range: DateRange(start: "2003", end: "2013")),
            TemporalValue(value: "研究員", range: DateRange(start: "2013")),
        ])
        let canonical = try PersonYAML.encode(p)
        XCTAssertEqual(try normalize(canonical), canonical)
    }

    // MARK: - organization-entity delta 的兩個 Scenario

    /// Scenario「An organization's names keep their authored order」。
    ///
    /// 三筆全無 `range` → 全部 `range` 相等 → 由寫入順序決定。這正是本 change 的動機：
    /// 改之前由 `value` 決勝，中文正式名被英文名擠到後面。
    func testOrganizationAliasesKeepAuthoredOrder() throws {
        let authored = ["統計科學研究所", "Institute of Statistical Science", "中研院統計所"]
        let org = Organization(key: "institute-of-statistical-science",
                               names: Timeline(authored.map { TemporalValue(value: $0) }))
        let yaml = try OrganizationYAML.encode(org)
        let decoded = try OrganizationYAML.decode(yaml)
        XCTAssertEqual(decoded.names.entries.map(\.value), authored,
                       "無日期的別名必須保留寫入順序：\n\(yaml)")
    }

    /// Scenario「An organization's historical names order by time」。
    ///
    /// 有 `range` 時時間仍然說話——本 change 只在時間**沒話說**時才退回寫入順序。
    func testOrganizationHistoricalNamesOrderByTime() throws {
        let org = Organization(
            key: "institute-of-statistical-science",
            names: Timeline([
                TemporalValue(value: "統計科學研究所", range: DateRange(start: "1993-08")),
                TemporalValue(value: "統計學研究所籌備處", range: DateRange(start: "1982-07",
                                                                        end: "1993-07")),
            ]))
        let decoded = try OrganizationYAML.decode(try OrganizationYAML.encode(org))
        XCTAssertEqual(decoded.names.entries.map(\.value),
                       ["統計學研究所籌備處", "統計科學研究所"],
                       "有日期時必須照時間，早的在前")
    }
}
