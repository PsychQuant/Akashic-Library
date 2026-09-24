import XCTest
@testable import AkashicCore
@testable import AkashicEntity
@testable import AkashicStoreIO
@testable import AkashicZoteroImport
@testable import AkashicMCPKit

/// #628：resolve-people 以外的寫入面，在 citekey 無法唯一定位（重複，或與另一筆共用 id）時不猜是哪一筆。
///
/// 原則同 #627：「無法唯一定位」只有一個定義（`unlocatableCitekeys`），每一條腿沿用自己既有的失敗語意——
/// library add／remove、venue apply／reject／repoint／demote、org apply／reject 整批拒絕；enrich 該筆歸 `ambiguous`；
/// enrichFromZotero 歸 `unlocatable`；`VenueResolver.apply`／`OrgResolver.apply` 以陣列位置就地改寫。
final class DuplicateCitekeyOtherWritersTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!
    var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-dupck628-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        service = AkashicService(root: root, key: nil, environment: [:])
        try store.writeVenue(Venue(key: "alpha", type: .periodical,
                                   names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: []))
        // c2020 重複：A 的 venue 邊是 literal、B 已歸戶到 alpha。d2021 是正常的一筆。
        var a = Entry(id: UUID(), citekey: "c2020", type: .periodicalArticle, title: "A", date: "2020")
        a.venues = [.literal("Alpha Journal")]
        var b = Entry(id: UUID(), citekey: "c2020", type: .periodicalArticle, title: "B", date: "2020")
        b.venues = [.key("alpha")]
        var d = Entry(id: UUID(), citekey: "d2021", type: .periodicalArticle, title: "D", date: "2021")
        d.venues = [.literal("Alpha Journal")]
        for e in [a, b, d] { try store.writeEntry(e) }
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func dups() throws -> [Entry] {
        try store.load().entries.filter { $0.citekey == "c2020" }.sorted { $0.title < $1.title }
    }

    private func assertRefused(_ body: () throws -> Any, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { err in
            let text = (err as? LocalizedError)?.errorDescription ?? "\(err)"
            XCTAssertTrue(text.contains("#628"), text, file: file, line: line)
        }
    }

    func testLibraryAddRefusesADuplicatedCitekeyWholeBatch() throws {
        try store.writeLibrary(Library(key: "lab", name: "Lab"))
        let before = try dups()
        assertRefused { try self.service.setMembership(action: "add", key: "lab", citekeys: ["d2021", "c2020"]) }
        XCTAssertEqual(try dups(), before)
        XCTAssertEqual(try store.load().entries.first { $0.citekey == "d2021" }!.akashic.libraries, [], "整批拒絕——正常那筆也不寫")
    }

    func testEnrichMarksADuplicatedCitekeyAmbiguousAndFillsTheRest() throws {
        let before = try dups()
        let plan = try AddOnlyEnrichment.plan(entries: try store.load().entries, proposals: [
            .init(citekey: "c2020", fields: ["note": "x"]), .init(citekey: "d2021", fields: ["note": "y"])])
        XCTAssertEqual(plan.items.map(\.category), [.ambiguous, .added])
        XCTAssertTrue((plan.items[0].reason ?? "").contains("#628"), plan.items[0].reason ?? "")
        // 寫入後 index 重建會因重複 citekey 失敗（既有損壞態）——不看結束方式，只看兩筆重複有沒有被動
        _ = try? service.enrich(proposals: [.init(citekey: "c2020", fields: ["note": "x"]),
                                           .init(citekey: "d2021", fields: ["note": "y"])],
                               dryRun: false, includeAbsentAuthors: false)
        XCTAssertEqual(try dups(), before, "重複的兩筆都不動")
    }

    func testZoteroEnrichmentRoutesADuplicatedCitekeyToUnlocatable() throws {
        let plan = ZoteroEnrichment.plan(entries: try store.load().entries, items: [], citekeys: ["c2020", "d2021"])
        XCTAssertEqual(plan.unlocatable, ["c2020"])
        XCTAssertFalse(plan.accountedCitekeys.filter { $0 == "c2020" }.count > 1, "每個 citekey 恰落一類")
    }

    func testVenueApplyRejectRepointDemoteRefuseADuplicatedCitekey() throws {
        let before = try dups()
        assertRefused { try self.service.resolveVenues(apply: ["c2020:0"]) }
        assertRefused { try self.service.resolveVenues(apply: nil, reject: ["c2020:0"]) }
        assertRefused { try self.service.resolveVenues(apply: nil, demote: ["c2020:0"]) }
        assertRefused { try self.service.resolveVenues(apply: nil, repoint: ["c2020:0:alpha"]) }
        XCTAssertEqual(try dups(), before)
        let list = try JSONSerialization.jsonObject(with: Data(try service.resolveVenues(apply: nil).utf8)) as! [String: Any]
        let rows = list["candidates"] as? [[String: Any]] ?? []
        XCTAssertEqual(rows.first { $0["citekey"] as? String == "c2020" }?["unlocatableCitekey"] as? Bool, true, "\(rows)")
        XCTAssertNil(rows.first { $0["citekey"] as? String == "d2021" }?["unlocatableCitekey"])
    }

    /// 最後一道防線：兩個 resolver 的 apply 以陣列位置就地改寫——重複 citekey 的兩筆既不被改、也不被換成同一份。
    func testResolverAppliesDoNotGuessOrCollapseDuplicates() throws {
        let entries = try store.load().entries
        let venueOut = VenueResolver.apply([
            VenueResolutionCandidate(citekey: "c2020", venueIndex: 0, literal: "Alpha Journal", venueKey: "alpha", reason: "r"),
            VenueResolutionCandidate(citekey: "d2021", venueIndex: 0, literal: "Alpha Journal", venueKey: "alpha", reason: "r")],
            to: entries)
        XCTAssertEqual(venueOut.map(\.id), entries.map(\.id), "順序與身分不變")
        for (b, a) in zip(entries, venueOut) where b.citekey == "c2020" { XCTAssertEqual(a, b) }
        XCTAssertEqual(venueOut.first { $0.citekey == "d2021" }!.venues, [.key("alpha")])

        var withAuthors = entries
        for i in withAuthors.indices { withAuthors[i].authors = [.literal("Ministry of Education")] }
        let orgOut = OrgResolver.apply([
            OrgResolutionCandidate(holder: .work(citekey: "c2020", authorIndex: 0), literal: "Ministry of Education", orgKey: "moe", reason: "r"),
            OrgResolutionCandidate(holder: .work(citekey: "d2021", authorIndex: 0), literal: "Ministry of Education", orgKey: "moe", reason: "r")],
            to: [], organizations: [], entries: withAuthors).entries
        for (b, a) in zip(withAuthors, orgOut) where b.citekey == "c2020" { XCTAssertEqual(a, b) }
        XCTAssertEqual(orgOut.first { $0.citekey == "d2021" }!.authors, [.organization("moe")])
    }
}
