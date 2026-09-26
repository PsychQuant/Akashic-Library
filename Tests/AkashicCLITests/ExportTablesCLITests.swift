import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #596：`export-tables` 結尾的兩個計數——未歸戶（`author_kind = literal`）與作者 key 懸空（kind 是
/// person／organization 而 id 為 NULL）分開說。R1 verify：改用 author_kind 計數之後，懸空的團體作者 key
/// 在所有面都不報（validate 也不報，#652），這一行是目前唯一會數到它的地方。
final class ExportTablesCLITests: XCTestCase {
    private var root: URL!
    private var out: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-export-cli-\(UUID().uuidString)")
        out = root.appendingPathComponent("tables-out")
        store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testUnresolvedAndDanglingKeysAreCountedSeparately() throws {
        try store.writePerson(Person(key: "member", names: ["Member, M."]))
        try store.writeEntry(Entry(id: UUID(), citekey: "ghost2021", type: .periodicalArticle, title: "T",
                                   authors: [.key("member"), .organization("ghost-org"),
                                             .key("ghost-person"), .literal("Nobody, N.")],
                                   date: "2021"))
        let r = try CLITestHarness.run(["export-tables", "--output", out.path, "--library", root.path], env: [:])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("（1 筆作者未歸戶"), r.output)
        XCTAssertTrue(r.output.contains("（2 筆作者 key 懸空"), r.output)
    }

    /// 已歸戶的團體作者（org 存在）不算未歸戶、也不算懸空。
    func testResolvedCorporateAuthorIsNeitherUnresolvedNorDangling() throws {
        var org = Organization(key: "moonshot")
        org.names = TimelineOf([TemporalValue(value: "Taiwan Cancer Moonshot", range: DateRange())])
        try store.writeOrganization(org)
        try store.writeEntry(Entry(id: UUID(), citekey: "corp2021", type: .periodicalArticle, title: "T",
                                   authors: [.organization("moonshot")], date: "2021"))
        let r = try CLITestHarness.run(["export-tables", "--output", out.path, "--library", root.path], env: [:])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertFalse(r.output.contains("未歸戶") || r.output.contains("懸空"), r.output)
    }
}
