import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicEntity
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #712：`resolve-venues` 的列表在兩面（CLI 全列、MCP 截並受位元組預算）報出**被正規化配對的否決壓掉的候選**。
///
/// 否決抑制自 #554 R12 起以 `matchingKey` 為鍵，所以對一個拼法的 `--reject`／`--demote` 會壓住同 work 同 venue 的其他拼法——
/// 在此之前列表對那些候選完全沉默。本檔釘的是列表的契約；判準本身（逐字相等不報、其餘報）的純函數測試在
/// `VenueResolverSuppressedTests`，CLI 真 binary 的在 `ResolveVenuesSuppressedCLITests`。
final class VenueSuppressedByNormalizationTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!
    var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-vsupp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
        service = AkashicService(root: root, key: nil, environment: [:])
        _ = try service.addVenue(key: "psychometrika", names: ["Psychometrika"], type: "periodical", note: nil)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }

    private func work(_ citekey: String, _ literals: [String]) throws {
        var e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: "T", date: "2020")
        e.venues = literals.map { .literal($0) }
        _ = try store.writeEntry(e)
    }

    private func rows(_ d: [String: Any], _ key: String = "suppressed") throws -> [[String: Any]] {
        try XCTUnwrap(d[key] as? [[String: Any]], "缺 \(key)：\(d.keys.sorted())")
    }

    func testListingReportsACandidateSuppressedByAnotherSpellingsRejection() throws {
        try work("x2025", ["Psychometrika", "PSYCHOMETRIKA"])
        // 否決之前：兩條邊都是候選、沒有被壓住的
        let before = try json(try service.resolveVenues(apply: nil))
        XCTAssertEqual((before["candidates"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual(try rows(before).count, 0, "沒有候選被壓時 suppressed 是空陣列——「沒有」與「沒給你看」要分得開")
        XCTAssertEqual(before["suppressedTotal"] as? Int, 0)
        XCTAssertEqual(before["truncated"] as? Bool, false)

        _ = try service.resolveVenues(apply: nil, reject: ["x2025:0"])
        let after = try json(try service.resolveVenues(apply: nil))
        XCTAssertEqual((after["candidates"] as? [[String: Any]])?.count, 0, "抑制不變：兩個拼法都不再被提名")
        let suppressed = try rows(after)
        XCTAssertEqual(suppressed.count, 1, "index 0 是被否決的那個拼法本身（普通的已否決），不報；index 1 才是被正規化壓掉的")
        let row = try XCTUnwrap(suppressed.first)
        XCTAssertEqual(row["citekey"] as? String, "x2025")
        XCTAssertEqual(row["venueIndex"] as? Int, 1)
        XCTAssertEqual(row["literal"] as? String, "PSYCHOMETRIKA")
        XCTAssertEqual(row["venueKey"] as? String, "psychometrika")
        XCTAssertEqual(row["rejectedLiterals"] as? [String], ["Psychometrika"], "壓住它的是使用者否決的那個拼法")
        XCTAssertNil(row["id"], "不是可 apply 的候選，不給 id")
        XCTAssertEqual(after["suppressedTotal"] as? Int, 1)
        XCTAssertEqual(after["truncated"] as? Bool, false)
    }

    /// #712 R3（b31 W6 第 1 列）：主路徑的 `reportingSuppressed:` 只在「apply 與 reject 都空」時為真——`nil` 與空陣列都算空。
    /// 這個引數若與 apply＋reject 組合腿的 `false` 對調（或改寫成只認 `nil`），列表腿就不再組 `suppressed`，而唯一看得到的地方是列表的
    /// 輸出：組合腿兩個都非空，對調前後都是 false。源碼掃描（`VenueResolverSuppressedTests.testWriteLegsPassReportingSuppressedFalse`）
    /// 釘住哪個呼叫點傳哪個值，這裡釘住它的行為。
    func testListingWithEmptyApplyAndRejectArraysStillReportsSuppressed() throws {
        try work("x2025", ["Psychometrika", "PSYCHOMETRIKA"])
        _ = try service.resolveVenues(apply: nil, reject: ["x2025:0"])
        for (apply, reject) in [(nil, nil), ([String](), nil), (nil, [String]()), ([String](), [String]())] as [([String]?, [String]?)] {
            let listing = try json(try service.resolveVenues(apply: apply, reject: reject))
            XCTAssertEqual(try rows(listing).map { $0["venueIndex"] as? Int }, [1],
                           "apply=\(String(describing: apply)) reject=\(String(describing: reject))：列表腿要組 suppressed")
            XCTAssertEqual(listing["suppressedTotal"] as? Int, 1)
        }
    }

    func testByteExactRejectionIsNotReported() throws {
        try work("x2025", ["Psychometrika"])
        _ = try service.resolveVenues(apply: nil, reject: ["x2025:0"])
        let after = try json(try service.resolveVenues(apply: nil))
        XCTAssertEqual((after["candidates"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual(try rows(after).count, 0, "普通的已否決列表一向不列，維持原樣")
        XCTAssertEqual(after["suppressedTotal"] as? Int, 0)
    }

    func testRejectionOnAnotherWorkDoesNotSuppressOrReport() throws {
        try work("x2025", ["Psychometrika"])
        try work("y2026", ["PSYCHOMETRIKA"])
        _ = try service.resolveVenues(apply: nil, reject: ["x2025:0"])
        let after = try json(try service.resolveVenues(apply: nil))
        XCTAssertEqual((after["candidates"] as? [[String: Any]])?.map { $0["id"] as? String }, ["y2026:0"],
                       "否決是 per-work：別的 work 的同名拼法照常是候選")
        XCTAssertEqual(try rows(after).count, 0)
    }

    func testDemoteAlsoSuppressesAndIsReportedTheSameWay() throws {
        try work("x2025", ["Psychometrika", "PSYCHOMETRIKA"])
        _ = try service.resolveVenues(apply: ["x2025:0"])
        StoreGitCommit.commitAll(root)   // demote 刪判定記錄之前要求 venue 檔已 commit（#573）
        let demoted = try json(try service.resolveVenues(apply: nil, demote: ["x2025:0"]))
        XCTAssertEqual(demoted["demoted"] as? [String], ["x2025:0"])
        // demote 寫的是 rejected verdict：它的 literal 是 Psychometrika，所以 PSYCHOMETRIKA 邊被正規化壓住
        let after = try json(try service.resolveVenues(apply: nil))
        XCTAssertEqual((after["candidates"] as? [[String: Any]])?.count, 0)
        let suppressed = try rows(after)
        XCTAssertEqual(suppressed.map { $0["literal"] as? String }, ["PSYCHOMETRIKA"])
        XCTAssertEqual(suppressed.first?["rejectedLiterals"] as? [String], ["Psychometrika"])
    }

    func testMCPFaceCapsTheRowsAndDisclosesTheTotalCLIListsAll() throws {
        let n = AkashicService.suppressedItemsCap + 5
        for i in 0..<n { try work(String(format: "w%04d", i), ["Psychometrika", "PSYCHOMETRIKA"]) }
        _ = try service.resolveVenues(apply: nil, reject: (0..<n).map { String(format: "w%04d:0", $0) })

        let mcp = try json(try service.resolveVenues(apply: nil))   // 預設＝MCP 面的上限
        XCTAssertEqual(try rows(mcp).count, AkashicService.suppressedItemsCap)
        XCTAssertEqual(mcp["suppressedTotal"] as? Int, n, "分母永遠完整")
        XCTAssertEqual(mcp["truncated"] as? Bool, true, "被截就要說")
        XCTAssertEqual(try rows(mcp).first?["citekey"] as? String, "w0000", "依 (citekey, venueIndex) 排序")

        let cli = try json(try service.resolveVenues(apply: nil, suppressedLimit: nil))   // CLI 傳 nil＝全列
        XCTAssertEqual(try rows(cli).count, n)
        XCTAssertEqual(cli["suppressedTotal"] as? Int, n)
        XCTAssertEqual(cli["truncated"] as? Bool, false)
    }

    func testNegativeLimitIsRefusedBeforeAnythingElse() throws {
        XCTAssertThrowsError(try service.resolveVenues(apply: nil, suppressedLimit: -1)) { err in
            guard case ServiceError.invalid(let m) = err else { return XCTFail("\(err)") }
            XCTAssertTrue(m.contains("suppressedLimit"), m)
        }
    }

    func testByteBudgetDropsRowsThatDoNotFitAndSaysSo() throws {
        // 每列帶 5 個（resolver 已截，#712 R1）各約 190 個 U+2028 的 rejectedLiterals、總數 6；displaySafe 逃脫之後每個 scalar 遠超一個位元組
        let literals = (0..<VenueResolver.suppressedLiteralsPerRow).map { "L\($0)" + String(repeating: "\u{2028}", count: 190) }
        let suppressed = (0..<30).map { i in
            VenueSuppressedCandidate(citekey: String(format: "w%04d", i), venueIndex: 1, literal: "PSYCHOMETRIKA",
                                     venueKey: "psychometrika", rejectedLiterals: literals, rejectedLiteralsTotal: 6)
        }
        let payload = AkashicService.suppressedPayload(suppressed, limit: 1_000)   // 列數上限不是限制，位元組預算才是
        let shown = try XCTUnwrap(payload["suppressed"] as? [[String: Any]])
        XCTAssertLessThan(shown.count, suppressed.count, "預算吃不下全部——否則這個測試沒有量到預算")
        XCTAssertGreaterThan(shown.count, 0)
        XCTAssertLessThanOrEqual(shown.reduce(0) { $0 + AkashicService.jsonBytes($1) }, AkashicService.candidateByteBudget)
        XCTAssertEqual(payload["suppressedTotal"] as? Int, suppressed.count)
        XCTAssertEqual(payload["truncated"] as? Bool, true)
        let capped = try XCTUnwrap(shown.first)
        XCTAssertEqual((capped["rejectedLiterals"] as? [String])?.count, VenueResolver.suppressedLiteralsPerRow, "每列壓住它的拼法有個數上限")
        XCTAssertEqual(capped["rejectedLiteralsTotal"] as? Int, 6, "超過時說出真實個數")
        // CLI（limit nil）不套位元組預算：全列
        let all = try XCTUnwrap(AkashicService.suppressedPayload(suppressed, limit: nil)["suppressed"] as? [[String: Any]])
        XCTAssertEqual(all.count, suppressed.count)
    }
}
