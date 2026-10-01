import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #712 的 CLI 面：`akashic resolve-venues`（不帶旗標）列出被正規化配對的否決壓掉的候選。
///
/// 走真 binary——CLI 面把 `suppressedLimit: nil` 傳給服務（全列、沒有 MCP 的列數與位元組上限），服務層的測試測不到那一行轉送。
/// venue 的 CLI 列表就是服務的 JSON 原樣印出（沒有另一套人可讀排版），所以「計數行」是 `suppressedTotal` 與 `truncated`。
final class ResolveVenuesSuppressedCLITests: XCTestCase {
    private var tmp: URL!
    private var root: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-rvsupp-\(UUID().uuidString)")
        root = tmp.appendingPathComponent("store")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        try store.writeVenue(Venue(key: "psychometrika", type: .periodical,
                                   names: Timeline([TemporalValue(value: "Psychometrika")]), authorized: []))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func run(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: ["HOME": tmp.path, "AKASHIC_HOME": tmp.path])
    }

    private func seed(_ count: Int) throws {
        let store = LibraryStore(root: root)
        for i in 0..<count {
            var e = Entry(id: UUID(), citekey: String(format: "w%04d", i), type: .periodicalArticle, title: "T", date: "2020")
            e.venues = [.literal("Psychometrika"), .literal("PSYCHOMETRIKA")]
            _ = try store.writeEntry(e)
        }
    }

    private func listing() throws -> [String: Any] {
        let r = try run(["resolve-venues"])
        XCTAssertEqual(r.status, 0, r.output)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(r.output.utf8)) as? [String: Any], r.output)
    }

    func testListingNamesTheCandidatesAnotherSpellingsRejectionSuppressed() throws {
        try seed(1)
        let reject = try run(["resolve-venues", "--reject", "w0000:0"])
        XCTAssertEqual(reject.status, 0, reject.output)

        let d = try listing()
        XCTAssertEqual((d["candidates"] as? [Any])?.count, 0, "抑制不變")
        XCTAssertEqual(d["suppressedTotal"] as? Int, 1)
        XCTAssertEqual(d["truncated"] as? Bool, false)
        let row = try XCTUnwrap((d["suppressed"] as? [[String: Any]])?.first)
        XCTAssertEqual(row["citekey"] as? String, "w0000")
        XCTAssertEqual(row["venueIndex"] as? Int, 1)
        XCTAssertEqual(row["literal"] as? String, "PSYCHOMETRIKA")
        XCTAssertEqual(row["venueKey"] as? String, "psychometrika")
        XCTAssertEqual(row["rejectedLiterals"] as? [String], ["Psychometrika"])
    }

    func testListingWithNothingSuppressedSaysZero() throws {
        try seed(1)
        let d = try listing()
        XCTAssertEqual(d["suppressedTotal"] as? Int, 0, "沒有候選被壓住也要說出來")
        XCTAssertEqual((d["suppressed"] as? [Any])?.count, 0)
    }

    func testCLIListsEveryRowWhileTheServiceDefaultIsCapped() throws {
        let n = AkashicService.suppressedItemsCap + 5
        try seed(n)
        let ids = (0..<n).map { String(format: "w%04d:0", $0) }
        XCTAssertEqual(try run(["resolve-venues", "--reject"] + ids).status, 0)

        let d = try listing()
        XCTAssertEqual((d["suppressed"] as? [Any])?.count, n, "CLI 全列（操作者要能列舉每一筆）")
        XCTAssertEqual(d["suppressedTotal"] as? Int, n)
        XCTAssertEqual(d["truncated"] as? Bool, false)

        // 對照：同一份 store 走服務的預設（MCP 面）被截
        let service = AkashicService(root: root, key: nil, environment: [:])
        let mcp = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try service.resolveVenues(apply: nil).utf8)) as? [String: Any])
        XCTAssertEqual((mcp["suppressed"] as? [Any])?.count, AkashicService.suppressedItemsCap)
        XCTAssertEqual(mcp["truncated"] as? Bool, true)
    }

    func testHelpDescribesTheSuppressedSection() throws {
        let r = try CLITestHarness.run(["resolve-venues", "--help"], env: ["HOME": tmp.path, "AKASHIC_HOME": tmp.path])
        XCTAssertTrue(r.output.contains("suppressed") && r.output.contains("suppressedTotal") && r.output.contains("#712"),
                      "契約細節住在 --help：\(r.output)")
    }
}
