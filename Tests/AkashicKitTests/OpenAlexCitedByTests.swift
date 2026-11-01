import XCTest
import Foundation
@testable import AkashicSkillTools

final class OpenAlexCitedByTests: XCTestCase {
    typealias OA = OpenAlexCitedBy
    let time = "2026-11-01T03:00:00Z"
    func read(query: OA.Query, data: Data, observedAt: String, previous: OA.Report? = nil) throws -> OA.Report {
        try OA.read(query: query, requestedURL: previous?.nextURL ?? query.url(), data: data, observedAt: observedAt, previous: previous)
    }
    func page(_ ids: [Int], count: Int = 20, cursor: String? = "next", refs: [String] = ["W1", "W2"], date: String = "2024-01-01") throws -> Data {
        let works: [[String: Any]] = ids.map { id in
            ["id": "https://openalex.org/W\(id)", "title": "A critique and extension of a model",
             "doi": "https://doi.org/10.1234/\(id)", "publication_date": date, "publication_year": 2024,
             "cited_by_count": 5, "referenced_works": refs.map { "https://openalex.org/" + $0 },
             "primary_location": ["source": ["id": "https://openalex.org/S1", "display_name": "Methods"]]]
        }
        return try JSONSerialization.data(withJSONObject: ["meta": ["count": count, "next_cursor": cursor as Any? ?? NSNull()], "results": works])
    }
    func testNoFilterOnlyCountsAndDoesNotOfferSelection() throws {
        let q = try OA.Query(seeds: ["W1"])
        XCTAssertTrue(q.countOnly)
        XCTAssertTrue(try q.url().contains("per_page=1"))
        let r = try read(query: q, data: page([10], count: 37), observedAt: time)
        XCTAssertEqual(r.observations[0].count, 37)
        XCTAssertTrue(r.candidates.isEmpty)
        XCTAssertEqual(r.stopReason, "count-only")
        XCTAssertNil(r.nextURL)
        XCTAssertThrowsError(try OA.select(report: r, ids: ["W10"]))
    }
    func testIntersectionUnionYearAndEncodedSearch() throws {
        let q = try OA.Query(seeds: ["W1", "https://openalex.org/W2", "W1"], fromYear: 2023, toYear: 2025, search: "bias & power, cites:W9")
        let parts = URLComponents(string: try q.url())!
        let params = Dictionary(uniqueKeysWithValues: parts.queryItems!.map { ($0.name, $0.value!) })
        XCTAssertEqual(params["filter"], "cites:W1,cites:W2,from_publication_date:2023-01-01,to_publication_date:2025-12-31")
        XCTAssertEqual(params["search"], "bias & power, cites:W9")
        let u = try OA.Query(seeds: ["W1", "W2"], mode: "union", sort: "publication_date:desc")
        XCTAssertTrue(try u.url().removingPercentEncoding!.contains("filter=cites:W1|W2"))
    }
    func testInvalidInputsFailClosed() throws {
        XCTAssertThrowsError(try OA.Query(seeds: []))
        XCTAssertThrowsError(try OA.Query(seeds: ["W1,cites:W2"]))
        XCTAssertThrowsError(try OA.Query(seeds: ["W1"], fromYear: 2025, toYear: 2023))
        XCTAssertThrowsError(try OA.Query(seeds: ["W1"], pageSize: 101))
        XCTAssertThrowsError(try OA.Query(seeds: ["W1"], sourceIDs: ["S1|S2"]))
        XCTAssertThrowsError(try OA.Query(seeds: ["W1"], minCitations: -1))
        XCTAssertThrowsError(try OA.Query(seeds: ["W1"], maxPages: 0))
    }
    func testCursorProgressDeduplicatesAndRecordsChangingCounts() throws {
        let q = try OA.Query(seeds: ["W1", "W2"], fromYear: 2023, pageSize: 2, paging: "cursor")
        let a = try read(query: q, data: page([10, 11]), observedAt: time)
        XCTAssertNotNil(a.nextURL)
        let b = try read(query: q, data: page([11, 12], count: 21, cursor: "third"), observedAt: "2026-11-01T03:01:00Z", previous: a)
        XCTAssertEqual(b.candidates.map(\.id), ["W10", "W11", "W12"])
        XCTAssertEqual(b.observations.map(\.count), [20, 21])
        XCTAssertEqual(b.duplicateCount, 1)
        XCTAssertTrue(b.warnings.contains("count-changed"))
        XCTAssertFalse(b.complete)
    }
    func testStalePageAndRepeatedCursorAreRejected() throws {
        let q = try OA.Query(seeds: ["W1"], fromYear: 2023, paging: "cursor")
        let a = try read(query: q, data: page([10]), observedAt: time)
        XCTAssertThrowsError(try read(query: q, data: page([10], cursor: "different"), observedAt: time, previous: a))
        XCTAssertThrowsError(try read(query: q, data: page([11]), observedAt: time, previous: a))
    }
    func testResponseMustBelongToQuery() throws {
        let q = try OA.Query(seeds: ["W1", "W2"], fromYear: 2023, toYear: 2025)
        XCTAssertThrowsError(try read(query: q, data: page([10], refs: ["W1"]), observedAt: time))
        XCTAssertThrowsError(try read(query: q, data: page([10], date: "2022-12-31"), observedAt: time))
        XCTAssertThrowsError(try read(query: q, data: page([10]), observedAt: "yesterday"))
        XCTAssertThrowsError(try read(query: q, data: Data("{\"error\":\"rate limited\"}".utf8), observedAt: time))
        XCTAssertThrowsError(try read(query: q, data: Data("<html>challenge</html>".utf8), observedAt: time))
        XCTAssertThrowsError(try read(query: q, data: page([10], count: 0), observedAt: time))
    }
    func testBudgetAndExhaustionAreDifferent() throws {
        let q = try OA.Query(seeds: ["W1"], fromYear: 2023, maxCandidates: 1, paging: "cursor")
        let r = try read(query: q, data: page([10, 11]), observedAt: time)
        XCTAssertEqual(r.candidates.count, 1)
        XCTAssertEqual(r.stopReason, "candidate-budget")
        XCTAssertEqual(r.omittedCount, 1)
        XCTAssertFalse(r.complete)
        XCTAssertNil(r.nextURL)
        let p = try OA.Query(seeds: ["W1"], fromYear: 2023, maxPages: 1, paging: "cursor")
        XCTAssertEqual(try read(query: p, data: page([10]), observedAt: time).stopReason, "page-budget")
        let e = try read(query: p, data: page([10], count: 1, cursor: nil), observedAt: time)
        XCTAssertTrue(e.complete)
        XCTAssertEqual(e.stopReason, "exhausted")
        let inconsistent = try read(query: p, data: page([], count: 20, cursor: nil), observedAt: time)
        XCTAssertFalse(inconsistent.complete)
        XCTAssertEqual(inconsistent.stopReason, "inconsistent-end")
    }
    func testSignalsAreEvidenceAndSelectionIsAnExplicitSubset() throws {
        let q = try OA.Query(seeds: ["W1"], fromYear: 2023, paging: "cursor")
        let r = try read(query: q, data: page([10, 11]), observedAt: time)
        XCTAssertTrue(r.candidates[0].signals.contains { $0.category == "critique" && $0.field == "title" })
        XCTAssertFalse(r.candidates[0].hasAbstract)
        XCTAssertThrowsError(try OA.select(report: r, ids: []))
        XCTAssertThrowsError(try OA.select(report: r, ids: ["W999"]))
        XCTAssertEqual(try OA.select(report: r, ids: ["W11"]).map(\.id), ["W11"])
    }
    func testBasicPagingContinuesWithPageNumberAndNoKey() throws {
        let q = try OA.Query(seeds: ["W1"], fromYear: 2023, pageSize: 2)
        XCTAssertEqual(q.paging, "page")
        let a = try read(query: q, data: page([10, 11], count: 3, cursor: nil), observedAt: time)
        XCTAssertTrue(a.nextURL!.contains("page=2"))
        XCTAssertFalse(a.nextURL!.contains("cursor="))
        let b = try read(query: q, data: page([12], count: 3, cursor: nil), observedAt: time, previous: a)
        XCTAssertTrue(b.complete)
        XCTAssertEqual(b.candidates.count, 3)
    }
    func testTruncatedLastPageReportsBudgetNotIndexError() throws {
        for paging in ["page", "cursor"] {
            let q = try OA.Query(seeds: ["W1"], fromYear: 2023, maxCandidates: 1, paging: paging)
            let r = try read(query: q, data: page([10, 11], count: 2, cursor: nil), observedAt: time)
            XCTAssertEqual(r.stopReason, "candidate-budget")
            XCTAssertFalse(r.complete)
        }
    }
    func testRequestBindingAndQueryMismatch() throws {
        let q = try OA.Query(seeds: ["W1"], fromYear: 2023, pageSize: 1)
        XCTAssertThrowsError(try OA.read(query: q, requestedURL: "https://api.openalex.org/works", data: page([10]), observedAt: time))
        let a = try read(query: q, data: page([10]), observedAt: time)
        let other = try OA.Query(seeds: ["W1"], fromYear: 2024, pageSize: 1)
        XCTAssertThrowsError(try read(query: other, data: page([11]), observedAt: time, previous: a))
        XCTAssertThrowsError(try read(query: q, data: page([11]), observedAt: "2026-10-01T00:00:00Z", previous: a))
    }
    func testSourceCitationThresholdAndSparseAbstract() throws {
        let q = try OA.Query(seeds: ["W1"], sourceIDs: ["S1"], minCitations: 5)
        XCTAssertEqual(try read(query: q, data: page([10]), observedAt: time).candidates.count, 1)
        let wrong = try OA.Query(seeds: ["W1"], sourceIDs: ["S2"])
        XCTAssertThrowsError(try read(query: wrong, data: page([10]), observedAt: time))
        let high = try OA.Query(seeds: ["W1"], minCitations: 6)
        XCTAssertThrowsError(try read(query: high, data: page([10]), observedAt: time))
        var obj = try JSONSerialization.jsonObject(with: page([10])) as! [String: Any]
        var works = obj["results"] as! [[String: Any]]
        works[0]["title"] = "Application"
        works[0]["abstract_inverted_index"] = ["power": [0], "analysis": [2]]
        obj["results"] = works
        let result = try read(query: q, data: JSONSerialization.data(withJSONObject: obj), observedAt: time)
        XCTAssertFalse(result.candidates[0].signals.contains { $0.evidence.contains("power analysis") })
    }
    func testUnionOnlyLinksMatchedSeedsAndURLIsShellSafe() throws {
        let q = try OA.Query(seeds: ["W1", "W2"], mode: "union", search: "a'b + c&d")
        let r = try read(query: q, data: page([10], refs: ["W2"]), observedAt: time)
        XCTAssertEqual(r.candidates[0].citedSeeds, ["W2"])
        let url = try q.url()
        XCTAssertFalse(url.contains("'"))
        let components = URLComponents(string: url)!
        XCTAssertEqual(components.queryItems!.first { $0.name == "search" }?.value, "a'b + c&d")
    }

}
