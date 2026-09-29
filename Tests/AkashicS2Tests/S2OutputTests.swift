import XCTest
@testable import AkashicS2

/// #664 任務 4.2：外部字串清理與 MCP 位元組上限（Requirement「Text from Semantic Scholar is
/// sanitized before display」「The MCP tool bounds its result by bytes」）。
final class S2OutputTests: XCTestCase {
    func testControlAndDirectionCharactersAreNeutralised() {
        let raw = S2JSON.object([
            "title": .string("Evil\u{202E}txt.exe"),
            "note\u{202E}": .string("k"),
            "year": .int(2015),
            "abstract": .string(String(repeating: "a", count: 5000)),
        ])
        guard case .object(let o) = S2Output.sanitized(raw) else { return XCTFail("object expected") }
        guard case .string(let title)? = o["title"] else { return XCTFail("title expected") }
        XCTAssertFalse(title.unicodeScalars.contains { $0.value == 0x202E }, title)
        XCTAssertFalse(o.keys.contains { $0.unicodeScalars.contains { $0.value == 0x202E } })
        XCTAssertEqual(o["year"], .int(2015))
        guard case .string(let abstract)? = o["abstract"] else { return XCTFail("abstract expected") }
        XCTAssertEqual(abstract.count, 5000)                     // 長文不被截
    }

    /// 以獨立的編碼器（JSONSerialization）算出「恰好 120 筆時整份輸出」的位元組數當上限。
    private func envelopeBytes(_ records: [[String: Any]], total: Int, offset: Int, nextOffset: Int?, truncated: Bool) -> Int {
        let envelope: [String: Any] = [
            "endpoint": "references", "total": total, "returned": records.count, "truncated": truncated,
            "offset": offset, "nextOffset": nextOffset ?? NSNull(), "data": records,
        ]
        return try! JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys, .withoutEscapingSlashes]).count
    }

    private func records(_ n: Int) -> [[String: Any]] {
        (0..<n).map { ["paperId": "p\($0)", "title": String(repeating: "t", count: 380)] }
    }

    private func result(_ raw: [[String: Any]], total: Int) -> S2Result {
        let data = S2JSON.array(raw.map { .object(["paperId": .string($0["paperId"] as! String),
                                                   "title": .string($0["title"] as! String)]) })
        return S2Result(endpoint: "references", request: [:], total: total, offset: 0, data: data)
    }

    /// spec Scenario「The same paper through MCP」：只放得下 120 筆 → returned 120、nextOffset 120。
    func testOnlyWholeRecordsThatFitAreReturned() throws {
        let all = records(1000)
        let budget = envelopeBytes(Array(all.prefix(120)), total: 1000, offset: 0, nextOffset: 120, truncated: true)
        let page = S2Output.mcpPage(result(all, total: 1000), budget: budget)
        XCTAssertEqual(page.returned, 120)
        XCTAssertTrue(page.truncated)
        XCTAssertEqual(page.nextOffset, 120)
        XCTAssertLessThanOrEqual(page.text.utf8.count, budget)
        let decoded = try JSONSerialization.jsonObject(with: Data(page.text.utf8)) as! [String: Any]
        let data = decoded["data"] as! [[String: Any]]
        XCTAssertEqual(data.count, 120)
        XCTAssertEqual(data.last?["paperId"] as? String, "p119")
        XCTAssertEqual((data.last?["title"] as? String)?.count, 380)   // 沒有半筆
        XCTAssertEqual(decoded["total"] as? Int, 1000)
    }

    func testEverythingFitsMeansNotTruncated() throws {
        let page = S2Output.mcpPage(result(records(3), total: 3))
        XCTAssertEqual(page.returned, 3)
        XCTAssertFalse(page.truncated)
        XCTAssertNil(page.nextOffset)
        XCTAssertEqual(S2Output.mcpByteBudget, 49_152)
    }
}
