import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit
@testable import AkashicIndex

/// venue／org 的 service 面（#304 task 4.1）——CLI 與 MCP 的唯一實作路徑。
final class VenueServiceTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!
    var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-vsvc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
        service = AkashicService(root: root, key: nil, environment: [:])
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }

    func testAddVenueThenViewWithZeroWorks() throws {
        _ = try service.addVenue(key: "psychometrika", names: ["Psychometrika"],
                                 type: "journal", note: nil)
        let d = try json(try service.venue(key: "psychometrika"))
        XCTAssertEqual(d["type"] as? String, "journal")
        XCTAssertEqual(d["workCount"] as? Int, 0, "零篇是答案不是缺席")
        XCTAssertNotNil(d["works"], "空陣列也要出現")
    }

    func testVenueNotFoundVsUndeterminable() throws {
        XCTAssertThrowsError(try service.venue(key: "nope")) { err in
            guard case ServiceError.notFound = err else { return XCTFail("預期 notFound") }
        }
        // quarantined 檔在場 → 無法判定
        try "venue:\nid: \(UUID().uuidString)\nkey: broken\ntype: series\n"
            .write(to: root.appendingPathComponent("entities/\(UUID().uuidString).yaml"),
                   atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try service.venue(key: "nope")) { err in
            guard case ServiceError.undeterminable = err else {
                return XCTFail("quarantine 在場時應 undeterminable，實得 \(err)")
            }
        }
    }

    func testAddVenueRejectsUnknownType() throws {
        XCTAssertThrowsError(try service.addVenue(key: "x", names: ["X"],
                                                  type: "series", note: nil))
    }

    func testChronologicalWorksInVenueView() throws {
        _ = try service.addVenue(key: "psychometrika", names: ["Psychometrika"],
                                 type: "journal", note: nil)
        var e1 = Entry(id: UUID(), citekey: "b2020", type: "article", title: "後")
        e1.venues = [.key("psychometrika")]; e1.date = "2020"
        var e2 = Entry(id: UUID(), citekey: "a2015", type: "article", title: "前")
        e2.venues = [.key("psychometrika")]; e2.date = "2015"
        _ = try store.writeEntry(e1); _ = try store.writeEntry(e2)
        try LibraryIndex(store: store).rebuild()
        let d = try json(try service.venue(key: "psychometrika"))
        let works = try XCTUnwrap(d["works"] as? [[String: Any]])
        XCTAssertEqual(works.map { $0["citekey"] as? String }, ["a2015", "b2020"], "依年升冪")
    }

    func testResolveVenuesFullCycle() throws {
        _ = try service.addVenue(key: "psychometrika", names: ["Psychometrika"],
                                 type: "journal", note: nil)
        var e = Entry(id: UUID(), citekey: "x2025", type: "article", title: "T")
        e.venues = [.literal("PSYCHOMETRIKA")]   // WoS 大寫形——正規化命中
        _ = try store.writeEntry(e)
        // 候選列舉
        let list = try json(try service.resolveVenues(apply: nil))
        let cands = try XCTUnwrap(list["candidates"] as? [[String: Any]])
        XCTAssertEqual(cands.count, 1)
        let id = try XCTUnwrap(cands[0]["id"] as? String)
        XCTAssertEqual(id, "x2025:0")
        // apply：literal 升格 key＋confirmed verdict
        let applied = try json(try service.resolveVenues(apply: [id]))
        XCTAssertEqual(applied["entriesRewritten"] as? Int, 1)
        let after = try store.load()
        XCTAssertEqual(after.entries[0].venues, [.key("psychometrika")])
        let venue = try XCTUnwrap(after.venues.first)
        XCTAssertTrue(venue.references.contains { $0.field == "resolution-confirmed" },
                      "confirmed verdict 落被判定的 venue 記錄")
        // idempotent：再解析零候選
        let again = try json(try service.resolveVenues(apply: nil))
        XCTAssertEqual((again["candidates"] as? [[String: Any]])?.count, 0)
    }

    func testResolveVenuesRejectSuppressesCandidate() throws {
        _ = try service.addVenue(key: "psychometrika", names: ["Psychometrika"],
                                 type: "journal", note: nil)
        var e = Entry(id: UUID(), citekey: "x2025", type: "article", title: "T")
        e.venues = [.literal("Psychometrika")]
        _ = try store.writeEntry(e)
        _ = try service.resolveVenues(apply: nil, reject: ["x2025:0"])
        let after = try json(try service.resolveVenues(apply: nil))
        XCTAssertEqual((after["candidates"] as? [[String: Any]])?.count, 0,
                       "已否決配對不再被提名")
        // entry 的 literal 原樣（reject 不動 entry）
        XCTAssertEqual(try store.load().entries[0].venues, [.literal("Psychometrika")])
    }

    // MARK: - org MCP 面（#304 移轉）

    func testAddOrganizationWithParent() throws {
        _ = try service.addOrganization(key: "academia-sinica", names: ["中央研究院"],
                                        parentKey: nil, note: nil)
        _ = try service.addOrganization(key: "institute-of-statistical-science",
                                        names: ["統計科學研究所"],
                                        parentKey: "academia-sinica", note: nil)
        let load = try store.load()
        XCTAssertEqual(load.organizations.count, 2)
        let iss = try XCTUnwrap(load.organizations.first {
            $0.key == "institute-of-statistical-science" })
        XCTAssertEqual(iss.parents.entries.first?.value, .key("academia-sinica"))
        // 未知 parent 拒絕
        XCTAssertThrowsError(try service.addOrganization(
            key: "x", names: ["X"], parentKey: "nope", note: nil))
    }

    func testResolveOrganizationsCandidatesAndApply() throws {
        _ = try service.addOrganization(key: "institute-of-statistical-science",
                                        names: ["Institute of Statistical Science"],
                                        parentKey: nil, note: nil)
        var p = Person(key: "some-one", names: PersonNames(variant: ["Some One"]))
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: .literal("Institute of Statistical Science"))])
        try store.writePerson(p)
        let list = try json(try service.resolveOrganizations(apply: nil))
        let cands = try XCTUnwrap(list["candidates"] as? [[String: Any]])
        XCTAssertEqual(cands.count, 1)
        let id = try XCTUnwrap(cands[0]["id"] as? String)
        _ = try json(try service.resolveOrganizations(apply: [id]))
        let after = try store.load()
        let person = try XCTUnwrap(after.people.first { $0.key == "some-one" })
        XCTAssertEqual(person.profile.affiliations.entries.first?.value,
                       .key("institute-of-statistical-science"), "literal 升格 key")
    }
}
