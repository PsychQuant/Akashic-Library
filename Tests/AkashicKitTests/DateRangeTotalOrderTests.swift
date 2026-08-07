import XCTest
@testable import AkashicCore

/// #100 系列（#131 verify F5）：`DateRange.<` 必須是全序。
///
/// 病：`<` 只比 `start`，而 `==`（synthesized）看整個 range——「同 start 不同
/// end」的兩段互不相等且互不可比（`<` 兩方向皆 false）。`sorted` 因此不是它
/// 自稱的全序，`TimelineOf.==`（`a.sorted == b.sorted`）在這類段上變回順序敏感
/// ——與型別 header「相等性不看儲存順序」的宣稱矛盾。main 上曾靠 Swift sort 對
/// incomparable 元素的**未文件化**穩定性掩蓋——正是 #69 拒絕依賴的那個性質。
final class DateRangeTotalOrderTests: XCTestCase {

    /// 全序公理的機械檢查：incomparable ⟹ equal。
    func testIncomparableImpliesEqual() {
        let ranges: [DateRange] = [
            DateRange(),
            DateRange(start: "2003"),
            DateRange(start: "2003", end: "2010"),
            DateRange(start: "2003", end: "2020"),
            DateRange(start: "2003", endedUnknown: true),
            DateRange(start: "2003-01"),
            DateRange(end: "2010"),
            DateRange(endedUnknown: true),
            // 矛盾組合（encode/decode 兩端拒收，但 struct 公開可寫——#143 verify F1：
            // 全序必須在**型別的整個定義域**上成立，不是只在序列化允許的子集上）
            DateRange(start: "2003", end: "2010", endedUnknown: true),
            DateRange(end: "2010", endedUnknown: true),
        ]
        for a in ranges {
            for b in ranges {
                if !(a < b) && !(b < a) {
                    XCTAssertEqual(a, b,
                        "incomparable 必須代表相等，否則不是全序：\(a) vs \(b)")
                }
            }
        }
    }

    /// #131 F5 的原始重現：同 start 不同 end。
    func testSameStartDifferentEndIsComparable() {
        let a = DateRange(start: "2003", end: "2010")
        let b = DateRange(start: "2003", end: "2020")
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a < b || b < a, "同 start 不同 end 不得 incomparable")
        XCTAssertTrue(a < b, "end 字典序：先結束的在前")
    }

    /// end 三態的順位：具體日期 < 已結束未知（#63）< 進行中（延伸無限遠）。
    /// 這是全序的技術決定，不是時間語意的斷言——但選的順位要可解釋：
    /// 進行中的 end 對應 +∞，理應最後；endedUnknown 已結束、只是不知何時。
    func testEndStateOrdering() {
        let concrete = DateRange(start: "2003", end: "2010")
        let unknown = DateRange(start: "2003", endedUnknown: true)
        let open = DateRange(start: "2003")
        XCTAssertTrue(concrete < unknown)
        XCTAssertTrue(unknown < open)
        XCTAssertTrue(concrete < open)
    }

    /// 型別宣稱的恢復：同內容不同順序的 timeline 必須相等——含「同 start
    /// 不同 end」的段（main 上此案例比出 `!=`）。
    func testTimelineEqualityIsOrderInsensitiveWithSameStartSegments() {
        let s1 = TemporalValue(value: "研究員", range: DateRange(start: "2003", end: "2010"))
        let s2 = TemporalValue(value: "研究員", range: DateRange(start: "2003", end: "2020"))
        let s3 = TemporalValue(value: "所長", range: DateRange(start: "2003", endedUnknown: true))
        let forward = TimelineOf([s1, s2, s3])
        let backward = TimelineOf([s3, s2, s1])
        XCTAssertEqual(forward, backward,
                       "相等性不看儲存順序——這正是型別 header 的宣稱")
    }

    /// #143 verify F1 的原始重現：同 start 同 end、不同 endedUnknown 必須可比。
    func testSameStartSameEndDifferentEndedUnknownIsComparable() {
        let a = DateRange(start: "2003", end: "2010")
        let b = DateRange(start: "2003", end: "2010", endedUnknown: true)
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a < b, "矛盾組合排在正常組合後（rank 0 < 1）")
        let forward = TimelineOf([TemporalValue(value: "x", range: a),
                                  TemporalValue(value: "x", range: b)])
        let backward = TimelineOf([TemporalValue(value: "x", range: b),
                                   TemporalValue(value: "x", range: a)])
        XCTAssertEqual(forward, backward, "順序敏感不得回來")
    }

    /// 既有語意不倒退：nil start 仍排最後。
    func testNilStartStillSortsLast() {
        XCTAssertTrue(DateRange(start: "2003") < DateRange())
        XCTAssertFalse(DateRange() < DateRange(start: "2003"))
    }
}
