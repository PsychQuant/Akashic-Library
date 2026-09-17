import XCTest
@testable import AkashicMCPKit

/// #554 R28（R27 verify Codex 第 7 列）：兩面描述承諾回報「同批去重」，而 `namesReport` 對同批**位元組相同**的重複零回報——`afterBytes` 是集合，
/// 分不出第一筆實際存入與後續被去重的。
final class VenueNamesReportTests: XCTestCase {
    func testIdenticalDuplicatesInOneBatchAreReportedAsFolded() {
        let r = AkashicService.namesReport(requested: ["Journal", "Journal", "Journal "], before: [], after: ["Journal"])
        XCTAssertEqual(r.folded, ["Journal", "Journal "])
        XCTAssertEqual(r.alreadyPresent, [])
        XCTAssertEqual(r.dropped, [])
    }

    func testFirstOccurrenceIsNotReportedAsFolded() {
        let r = AkashicService.namesReport(requested: ["Journal", "Review"], before: ["Review"], after: ["Review", "Journal"])
        XCTAssertEqual(r.folded, [])
        XCTAssertEqual(r.alreadyPresent, ["Review"])
    }
}
