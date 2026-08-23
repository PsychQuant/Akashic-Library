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
                                 type: "periodical", note: nil)
        let d = try json(try service.venue(key: "psychometrika"))
        XCTAssertEqual(d["type"] as? String, "periodical")
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
                                 type: "periodical", note: nil)
        var e1 = Entry(id: UUID(), citekey: "b2020", type: .periodicalArticle, title: "後")
        e1.venues = [.key("psychometrika")]; e1.date = "2020"
        var e2 = Entry(id: UUID(), citekey: "a2015", type: .periodicalArticle, title: "前")
        e2.venues = [.key("psychometrika")]; e2.date = "2015"
        _ = try store.writeEntry(e1); _ = try store.writeEntry(e2)
        try LibraryIndex(store: store).rebuild()
        let d = try json(try service.venue(key: "psychometrika"))
        let works = try XCTUnwrap(d["works"] as? [[String: Any]])
        XCTAssertEqual(works.map { $0["citekey"] as? String }, ["a2015", "b2020"], "依年升冪")
    }

    func testResolveVenuesFullCycle() throws {
        _ = try service.addVenue(key: "psychometrika", names: ["Psychometrika"],
                                 type: "periodical", note: nil)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
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
                                 type: "periodical", note: nil)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.literal("Psychometrika")]
        _ = try store.writeEntry(e)
        _ = try service.resolveVenues(apply: nil, reject: ["x2025:0"])
        let after = try json(try service.resolveVenues(apply: nil))
        XCTAssertEqual((after["candidates"] as? [[String: Any]])?.count, 0,
                       "已否決配對不再被提名")
        // entry 的 literal 原樣（reject 不動 entry）
        XCTAssertEqual(try store.load().entries[0].venues, [.literal("Psychometrika")])
    }

    // MARK: - #306：update-venue（異名補寫——append 語意）

    func testUpdateVenueAppendsNamesWithoutClobbering() throws {
        _ = try service.addVenue(key: "psychometrika", names: ["Psychometrika"],
                                 type: "periodical", note: nil)
        let out = try json(try service.updateVenue(
            key: "psychometrika", addNames: ["PSYCHOMETRIKA", "Psychometrika"],
            note: nil, type: nil))
        XCTAssertEqual(out["namesAdded"] as? [String], ["PSYCHOMETRIKA"],
                       "重複異名不重加：\(out)")
        let v = try XCTUnwrap(try store.load().venues.first)
        XCTAssertEqual(Set(v.names.entries.map(\.value)),
                       ["Psychometrika", "PSYCHOMETRIKA"], "既有名字不得被洗掉")
        // 沿革補全後 resolver 立即受益：WoS 大寫形 exact 命中
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.literal("PSYCHOMETRIKA")]
        _ = try store.writeEntry(e)
        let list = try json(try service.resolveVenues(apply: nil))
        XCTAssertEqual((list["candidates"] as? [[String: Any]])?.count, 1)
    }

    func testUpdateVenueRejectsUnknownKeyAndBadType() throws {
        XCTAssertThrowsError(try service.updateVenue(
            key: "nope", addNames: ["X"], note: nil, type: nil))
        _ = try service.addVenue(key: "v1", names: ["V"], type: "periodical", note: nil)
        XCTAssertThrowsError(try service.updateVenue(
            key: "v1", addNames: nil, note: nil, type: "series"))
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

    // MARK: - 歸錯戶的退路（#418）

    private func twoVenuesAndAnEntry() throws -> Entry {
        _ = try service.addVenue(key: "wikipedia", names: ["Wikipedia"], type: "website", note: nil)
        _ = try service.addVenue(key: "wikipedia-zh", names: ["維基百科"], type: "website", note: nil)
        var e = Entry(id: UUID(), citekey: "w2020", type: .referenceWorkEntry, title: "條目")
        e.venues = [.key("wikipedia")]
        _ = try store.writeEntry(e)
        return e
    }

    /// **`--repoint` 把一條已經是 key 的邊改指到另一個 venue**（#418）。
    ///
    /// `resolve-venues --apply` 只做 literal → key 的升格。歸錯戶之後**沒有任何命令**
    /// 改得回來——person 域有 `resolve-divergence` 當退路，venue 域沒有。而
    /// `literal-first-then-key` 的整套論證建立在「漏可逆、誤不可逆」的不對稱上，
    /// 並為 person 域提供了退路；venue 域缺這一格。
    func testRepointMovesAKeyedEdgeToAnotherVenue() throws {
        _ = try twoVenuesAndAnEntry()
        let d = try json(try service.resolveVenues(apply: nil, reject: nil,
                                                   repoint: ["w2020:0:wikipedia-zh"]))
        XCTAssertEqual(d["entriesRewritten"] as? Int, 1)
        let after = try store.load().entries.first { $0.citekey == "w2020" }
        XCTAssertEqual(after?.venues, [.key("wikipedia-zh")])
    }

    /// **兩側都要留 verdict**——改指是一個身分判定，而判定會錯、錯了要能回溯
    /// （`identity-is-judged-not-matched`：判定要留 verdict、要可回溯與逆轉）。
    func testRepointWritesVerdictsOnBothVenues() throws {
        _ = try twoVenuesAndAnEntry()
        _ = try service.resolveVenues(apply: nil, reject: nil, repoint: ["w2020:0:wikipedia-zh"])
        let venues = try store.load().venues
        let old = try XCTUnwrap(venues.first { $0.key == "wikipedia" })
        let new = try XCTUnwrap(venues.first { $0.key == "wikipedia-zh" })
        XCTAssertTrue(old.references.contains { $0.field == "resolution-rejected" },
                      "舊 venue 要留 rejected——否則下次提名會再把它提出來：\(old.references)")
        XCTAssertTrue(new.references.contains { $0.field == "resolution-confirmed" },
                      "新 venue 要留 confirmed：\(new.references)")
    }

    /// **前提不符要具名略過，不得靜默**：那一格不是 key、index 越界、新 key 不存在。
    func testRepointRefusesWhenThePreconditionDoesNotHold() throws {
        _ = try twoVenuesAndAnEntry()
        // 新 key 不存在 → 整批拒絕（同 apply 的 notFound 語意）
        XCTAssertThrowsError(try service.resolveVenues(apply: nil, reject: nil,
                                                       repoint: ["w2020:0:nope"]))
        // index 越界 → 拒絕
        XCTAssertThrowsError(try service.resolveVenues(apply: nil, reject: nil,
                                                       repoint: ["w2020:9:wikipedia-zh"]))
        // 語法錯 → 拒絕
        XCTAssertThrowsError(try service.resolveVenues(apply: nil, reject: nil,
                                                       repoint: ["w2020:0"]))
        // 全部拒絕後，資料不得被動過
        XCTAssertEqual(try store.load().entries.first { $0.citekey == "w2020" }?.venues,
                       [.key("wikipedia")], "整批拒絕即零寫入")
    }

    /// **改指到自己是 no-op，不是錯誤**——冪等，重跑同一個 id 不會累積 verdict。
    func testRepointToTheSameVenueIsANoOp() throws {
        _ = try twoVenuesAndAnEntry()
        let d = try json(try service.resolveVenues(apply: nil, reject: nil,
                                                   repoint: ["w2020:0:wikipedia"]))
        XCTAssertEqual(d["entriesRewritten"] as? Int, 0)
        XCTAssertEqual(try store.load().entries.first { $0.citekey == "w2020" }?.venues,
                       [.key("wikipedia")])
    }
}
