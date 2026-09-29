import XCTest
@testable import AkashicCore

/// #675：名字段時間欄位的輸入檢查（`Venue.nameSegmentRangeIssue`）與它共用的兩份判準——
/// 矛盾組合（`DateRange.contradictionDescription`，YAML 邊界用的同一份）與區間有效性（`Venue.endpointIssue`，沿革豁免的放行條件用的同一份）。
final class VenueNameSegmentRangeTests: XCTestCase {

    // MARK: - 矛盾組合：一份判準，兩個使用者

    func testContradictionDescriptionNamesBothContradictionsAndIsNilOtherwise() {
        XCTAssertNil(DateRange().contradictionDescription)
        XCTAssertNil(DateRange(start: "1933", end: "1960").contradictionDescription)
        XCTAssertNil(DateRange(start: "1933", endedUnknown: true).contradictionDescription)
        XCTAssertNil(DateRange(attested: ["1950", "2005"]).contradictionDescription)
        XCTAssertTrue(DateRange(end: "1960", endedUnknown: true).contradictionDescription?.contains("end 與 endedUnknown 並存是矛盾") == true)
        for r in [DateRange(start: "1933", attested: ["1950"]), DateRange(end: "1960", attested: ["1950"]), DateRange(endedUnknown: true, attested: ["1950"])] {
            XCTAssertTrue(r.contradictionDescription?.contains("attested 與 start/end/ended 並存是矛盾") == true, "\(r)")
        }
    }

    /// YAML 的 encode 對同一個矛盾丟同一句話——寫入面說「可以」而 store 邊界說「不行」的組合不存在。
    func testTheYAMLBoundaryRefusesWithTheSameSentence() throws {
        for r in [DateRange(end: "1960", endedUnknown: true), DateRange(start: "1933", attested: ["1950"])] {
            let venue = Venue(key: "v", type: .periodical, names: Timeline([TemporalValue(value: "V", range: r)]))
            XCTAssertThrowsError(try VenueYAML.encode(venue)) { err in
                let s = (err as? LocalizedError)?.errorDescription ?? String(describing: err)
                XCTAssertTrue(s.contains(r.contradictionDescription ?? "（沒有矛盾？）"), "\(r)：\(s)")
            }
        }
    }

    // MARK: - nameSegmentRangeIssue

    func testNameSegmentRangeIssueAcceptsValidIntervalsOfAnyGranularity() {
        let ok: [DateRange] = [
            DateRange(), DateRange(start: "1933"), DateRange(end: "1960"), DateRange(start: "1933", end: "1960"),
            DateRange(start: "1960", end: "1960-06"),            // 同年內的細粒度 end 合法
            DateRange(start: "1960-06-15", end: "1960-06-15"),
            DateRange(start: "1933", endedUnknown: true), DateRange(endedUnknown: true),
            DateRange(attested: ["1950", "2005-03", "2005-03-01"]),
        ]
        for r in ok { XCTAssertNil(Venue.nameSegmentRangeIssue(r), "\(r)") }
    }

    func testNameSegmentRangeIssueRefusesWithASpecificSentence() {
        let bad: [(DateRange, String)] = [
            (DateRange(start: "民國49"), "start「民國49」不是 ISO 8601 前綴"),
            (DateRange(end: "1960-13"), "end「1960-13」不是 ISO 8601 前綴"),
            (DateRange(start: "1960-1"), "不是 ISO 8601 前綴"),
            (DateRange(start: "１９３３"), "不是 ISO 8601 前綴"),            // 全形數字
            (DateRange(start: ""), "不是 ISO 8601 前綴"),
            (DateRange(start: "2000", end: "1999"), "start「2000」晚於 end「1999」"),
            (DateRange(start: "2000-06", end: "2000-05"), "晚於"),
            (DateRange(end: "1960", endedUnknown: true), "end 與 endedUnknown 並存是矛盾"),
            (DateRange(attested: ["1950", "abc"]), "attested 的觀測點「abc」"),
            (DateRange(attested: [""]), "attested 的觀測點"),
        ]
        for (r, needle) in bad {
            let why = Venue.nameSegmentRangeIssue(r)
            XCTAssertTrue(why?.contains(needle) == true, "\(r) 應說出「\(needle)」：\(why ?? "nil")")
        }
    }

    /// 區間有效性只有一份：`segmentIsWellFormed`（沿革豁免的放行條件）與 `nameSegmentRangeIssue` 的端點檢查對同一組輸入答案一致——
    /// 寫入面放行的區間，沿革豁免也認得；不會出現「工具寫得進去、卻永遠解鎖不了同名沿革」的區間。
    func testEndpointJudgementIsTheSameForTheExemptionAndTheWriteFace() {
        let points: [String?] = [nil, "1933", "1960", "1960-06", "2003-1", "民國49", "2003-13", "2000", "1999"]
        for s in points {
            for e in points {
                let r = DateRange(start: s, end: e)
                XCTAssertEqual(Venue.segmentIsWellFormed(r), Venue.nameSegmentRangeIssue(r) == nil, "\(r)")
            }
        }
    }
}
