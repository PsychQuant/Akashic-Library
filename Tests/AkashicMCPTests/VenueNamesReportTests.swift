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

    /// R29（R28 verify Codex 第 12 列、logic 第 30 列）：全空白項的 canonical 都是空字串，R28 的順序先做同批去重、第二個空白項被判成 folded——
    /// 而它根本沒進 store。先問「有沒有存進去」，再問「同批已見」。
    func testAllWhitespaceItemsAreDroppedNotFolded() {
        let r = AkashicService.namesReport(requested: ["  ", "\t", "Journal"], before: [], after: ["Journal"])
        XCTAssertEqual(r.dropped, ["  ", "\t"])
        XCTAssertEqual(r.folded, [])
    }

    func testFirstOccurrenceIsNotReportedAsFolded() {
        let r = AkashicService.namesReport(requested: ["Journal", "Review"], before: ["Review"], after: ["Review", "Journal"])
        XCTAssertEqual(r.folded, [])
        XCTAssertEqual(r.alreadyPresent, ["Review"])
    }
}
