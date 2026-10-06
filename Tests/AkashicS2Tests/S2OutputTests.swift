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

    private func result(_ raw: [[String: Any]], total: Int?, hasMore: Bool? = false, endpoint: String = "references") -> S2Result {
        let data = S2JSON.array(raw.map { .object(["paperId": .string($0["paperId"] as! String),
                                                   "title": .string($0["title"] as! String)]) })
        return S2Result(endpoint: endpoint, request: [:], total: total, offset: 0, data: data, hasMore: hasMore)
    }

    /// spec Scenario「The same paper through MCP」：只放得下 120 筆 → returned 120、nextOffset 120。
    func testOnlyWholeRecordsThatFitAreReturned() throws {
        let all = records(1000)
        let budget = envelopeBytes(Array(all.prefix(120)), total: 1000, offset: 0, nextOffset: 120, truncated: true)
        let page = S2Output.mcpPage(result(all, total: 1000, hasMore: true), budget: budget)
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

    // MARK: 續查訊號（#664 verify R1 第 5、6、7 列）

    /// `batch`／`recommend`／`paper`／`match` 不接 `offset`：被位元組上限截斷時，給一個會被忽略的 `nextOffset`
    /// 只會讓呼叫者拿到同一頁、無限迴圈地耗用全機額度。這幾個端點沒有續查，`nextOffset` 一律 null。
    func testAnEndpointThatDoesNotPageNeverOffersAContinuationCursor() {
        let all = records(400)
        let page = S2Output.mcpPage(result(all, total: 400, hasMore: nil, endpoint: "batch"), budget: 20_000)
        XCTAssertTrue(page.truncated)
        XCTAssertLessThan(page.returned, 400)
        XCTAssertNil(page.nextOffset)
    }

    /// 有沒有下一頁看 S2 自己回的 `next`，不看另一個端點的計數（計數可以比實際筆數大，也可以查不到）。
    func testTheContinuationCursorFollowsS2sOwnNextAndNotTheCount() {
        // 計數 1000、但 S2 說沒有了（例如出版商沒有提供的參考文獻）：沒有下一頁。
        XCTAssertNil(S2Output.mcpPage(result(records(3), total: 1000, hasMore: false)).nextOffset)
        // 計數查不到（null）、但 S2 說還有：有下一頁。
        XCTAssertEqual(S2Output.mcpPage(result(records(3), total: nil, hasMore: true)).nextOffset, 3)
    }

    /// 空的一頁不指回自己：`nextOffset == offset` 是定點，照它續查會永遠原地踏步。
    func testAnEmptyPageNeverPointsBackAtItself() {
        let page = S2Output.mcpPage(result([], total: 40, hasMore: true))
        XCTAssertEqual(page.returned, 0)
        XCTAssertNil(page.nextOffset)
    }

    // MARK: JSON 面的清理要無損（#664 verify R1 第 8 列）

    /// 書目標題裡的反斜線（LaTeX）、不換行空格、軟連字號是正當內容。JSON 面不能用終端機用的 `displaySafe`——
    /// 它把反斜線改成字面的 `\u{005C}`，解不回來。
    func testJSONFacesKeepLegitimateBibliographicCharactersLosslessly() throws {
        let title = "The $\\beta$\u{00A0}model\u{00AD}ling"
        let result = S2Result(endpoint: "paper", request: ["id": .string("DOI:10.1/x")], total: nil, offset: 0,
                              data: .object(["title": .string(title)]))
        let mcp = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(S2Output.mcpPage(result).text.utf8)) as? [String: Any])
        XCTAssertEqual(((mcp["data"] as? [[String: Any]])?.first)?["title"] as? String, title)
        let cli = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(S2Output.cliJSON(result, fetchedAt: Date(timeIntervalSince1970: 0)).utf8)) as? [String: Any])
        XCTAssertEqual((cli["data"] as? [String: Any])?["title"] as? String, title)
    }

    /// 方向覆寫與控制字元仍然不會以原樣出現在輸出文字裡（改寫成 JSON 的 `\uXXXX`，解碼後還是原字元）。
    func testJSONFacesStillEscapeDirectionOverridesAndControlCharactersInTheText() throws {
        let evil = "Evil\u{202E}txt.exe\u{0007}"
        let result = S2Result(endpoint: "paper", request: [:], total: nil, offset: 0, data: .object(["title": .string(evil)]))
        for text in [S2Output.mcpPage(result).text, S2Output.cliJSON(result, fetchedAt: Date(timeIntervalSince1970: 0))] {
            XCTAssertFalse(text.unicodeScalars.contains { $0.value == 0x202E || $0.value == 0x07 }, text)
            XCTAssertTrue(text.contains("\\u202e") || text.contains("\\u202E"), text)
        }
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(S2Output.mcpPage(result).text.utf8)) as? [String: Any])
        XCTAssertEqual(((decoded["data"] as? [[String: Any]])?.first)?["title"] as? String, evil)
    }

    /// 位元組上限量的是**實際輸出**的大小：被改寫成 `\uXXXX` 之後變長，不能拿改寫前的大小去算。
    func testTheByteBudgetCountsTheEscapedText() {
        let many = (0..<50).map { _ in S2JSON.object(["t": .string(String(repeating: "\u{202E}", count: 40))]) }
        let result = S2Result(endpoint: "recommend", request: [:], total: nil, offset: 0, data: .array(many))
        let page = S2Output.mcpPage(result, budget: 4_000)
        XCTAssertLessThanOrEqual(page.text.utf8.count, 4_000)
        XCTAssertTrue(page.truncated)
    }
}
