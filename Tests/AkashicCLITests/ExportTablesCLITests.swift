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

    /// #657：真的 binary 寫出 publication_doi.csv——三個 DOI 的 work 三列、依序；publication.csv 的 doi 欄只放第一個；
    /// 結尾說出有幾筆 work 帶多個 DOI（publication.doi 只放第一個，要全部得 join 新表——不說的話讀 publication.csv 的人會以為那是全部）。
    func testMultipleDOIsLandInPublicationDOICSV() throws {
        var e = Entry(id: UUID(), citekey: "tryon2001", type: .periodicalArticle, title: "T",
                      authors: [.literal("Tryon, W. W.")], date: "2001")
        e.doi = ["10.1037/1082-989x.6.4.371", "10.1037//1082-989x.6.4.371",
                 "10.1037//1082-989x.6.4.371-386"].compactMap(DOI.init)
        try store.writeEntry(e)
        let home = root.appendingPathComponent("home")
        let r = try CLITestHarness.run(["export-tables", "--output", out.path, "--library", root.path],
                                       env: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("publication_doi: 3 列"), r.output)
        XCTAssertTrue(r.output.contains("（1 筆 work 帶多個 DOI"), r.output)
        let csv = try String(contentsOf: out.appendingPathComponent("publication_doi.csv"), encoding: .utf8)
        XCTAssertEqual(csv, "publication_id,doi_seq,doi\n"
                       + "\(e.id.uuidString),0,10.1037/1082-989x.6.4.371\n"
                       + "\(e.id.uuidString),1,10.1037//1082-989x.6.4.371\n"
                       + "\(e.id.uuidString),2,10.1037//1082-989x.6.4.371-386\n")
        let pub = try String(contentsOf: out.appendingPathComponent("publication.csv"), encoding: .utf8)
        XCTAssertTrue(pub.contains(",10.1037/1082-989x.6.4.371,"), pub)
        XCTAssertFalse(pub.contains("371-386"), "publication.doi 只放第一個")
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
