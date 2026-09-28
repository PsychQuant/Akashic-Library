import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicEntity
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #670：venue／organization 的 key 有不只一筆記錄時，以 key 定位寫入它們的面不猜寫進哪一筆。
///
/// #669 讓重複 key 成為跨記錄 error（改名與合併因此先停），但 verdict 寫入與 update-venue 不看跨記錄 error，
/// 之前會安靜地寫進第一筆（依列舉順序）。處置比照 #627／#628／#641：呼叫端顯式點名 → 整批拒絕；
/// store 狀態不符的篩選式或逐筆略過的面 → 略過並具名；列表以旗標標出。
final class DuplicateKeyWriteRefusalTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-670-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private var service: AkashicService { AkashicService(root: root, key: nil, environment: [:]) }
    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    /// payload 的 skipped 理由（`"\(array)"` 會把非 ASCII 逃成 `\U…`，不能拿描述字串比對）
    private func skipReasons(_ out: [String: Any]) -> [String] {
        ((out["skipped"] as? [[String: Any]]) ?? []).compactMap { ($0["why"] ?? $0["reason"]) as? String }
    }
    private func assertRefusedAsUnlocatable(_ body: () throws -> String, _ line: UInt = #line) {
        XCTAssertThrowsError(try body(), line: line) { error in
            XCTAssertTrue("\(error)".contains("無法唯一定位"), "\(error)", line: line)
        }
    }

    // MARK: - venue

    /// 兩筆 `psychometrika`（不同 UUID）＋ 一筆指著它的 literal 邊 ＋ 一筆已歸戶到它的 key 邊。
    private func twinVenues() throws {
        for _ in 0..<2 {
            try store.writeVenue(Venue(key: "psychometrika", type: .periodical,
                                       names: Timeline([TemporalValue(value: "Psychometrika")]), authorized: [], id: UUID()))
        }
        try store.writeVenue(Venue(key: "other", type: .periodical, names: Timeline([TemporalValue(value: "Other")]), authorized: []))
        var lit = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        lit.venues = [.literal("PSYCHOMETRIKA")]
        try store.writeEntry(lit)
        var keyed = Entry(id: UUID(), citekey: "y2026", type: .periodicalArticle, title: "U")
        keyed.venues = [.key("psychometrika")]
        try store.writeEntry(keyed)
        XCTAssertEqual(try store.load().venues.filter { $0.key == "psychometrika" }.count, 2, "前提：兩筆同 key")
    }

    func testVenueListingFlagsTheCandidate() throws {
        try twinVenues()
        let listed = try json(try service.resolveVenues(apply: nil))
        let cand = try XCTUnwrap((listed["candidates"] as? [[String: Any]])?.first { ($0["id"] as? String) == "x2025:0" }, "\(listed)")
        XCTAssertEqual(cand["unlocatableVenueKey"] as? Bool, true, "\(cand)")
    }

    /// apply：store 狀態不符＝逐筆略過並具名（D33 的既有契約），entry 不動。
    func testVenueApplySkipsTheCandidateByName() throws {
        try twinVenues()
        let out = try json(try service.resolveVenues(apply: ["x2025:0"]))
        let skipped = try XCTUnwrap(out["skippedUnlocatable"] as? [[String: Any]], "\(out)")
        XCTAssertEqual(skipped.first?["id"] as? String, "x2025:0")
        XCTAssertEqual(try store.load().entries.first { $0.citekey == "x2025" }?.venues, [.literal("PSYCHOMETRIKA")])
    }

    func testVenueRejectRepointDemoteAndUpdateRefuse() throws {
        try twinVenues()
        assertRefusedAsUnlocatable { try self.service.resolveVenues(apply: nil, reject: ["x2025:0"]) }
        assertRefusedAsUnlocatable { try self.service.resolveVenues(apply: nil, repoint: ["y2026:0:other"]) }
        assertRefusedAsUnlocatable { try self.service.resolveVenues(apply: nil, demote: ["y2026:0"]) }
        assertRefusedAsUnlocatable { try self.service.updateVenue(key: "psychometrika", addNames: ["Psychometrika (Print)"], note: nil, type: nil) }
        // 零寫入：兩筆都還是原樣、沒有任何 verdict
        let venues = try store.load().venues.filter { $0.key == "psychometrika" }
        XCTAssertEqual(venues.count, 2)
        XCTAssertTrue(venues.allSatisfy { $0.references.isEmpty && $0.names.entries.count == 1 }, "\(venues)")
    }

    func testVenueUndecidedSkipsByName() throws {
        try twinVenues()
        let out = try json(try service.resolveVenues(apply: nil, undecided: ["x2025:0:psychometrika=查了兩份目錄，判不出來"]))
        XCTAssertTrue(skipReasons(out).contains { $0.contains("無法唯一定位") }, "\(skipReasons(out))")
        XCTAssertTrue(try store.load().venues.allSatisfy { $0.references.isEmpty })
    }

    // MARK: - organization

    /// 兩筆 `iss`（不同 UUID）。名字不同——同名的兩筆會讓那個 literal 成為歧義條目而不是候選，而這裡要測的是候選列；
    /// 一位 person 的隸屬 literal 只對得上第一筆的名字（作者位的團體名要帶 corporate 標記才會被提名，這裡用隸屬比較直接）。
    private func twinOrgs() throws {
        for name in ["Institute of Statistical Science", "Statistics Institute Annex"] {
            var o = Organization(key: "iss", id: UUID())
            o.names = TimelineOf([TemporalValue(value: name, range: DateRange())])
            try store.writeOrganization(o)
        }
        var p = Person(key: "chen-ch", names: ["chen-ch"])
        p.profile.affiliations = TimelineOf([TemporalValue(value: OrgRef.literal("Institute of Statistical Science"), range: DateRange())])
        try store.writePerson(p)
        XCTAssertEqual(try store.load().organizations.filter { $0.key == "iss" }.count, 2, "前提：兩筆同 key")
    }

    func testOrgListingFlagsAndExplicitLegsRefuseOrSkip() throws {
        try twinOrgs()
        let listed = try json(try service.resolveOrganizations(apply: nil))
        let cand = try XCTUnwrap((listed["candidates"] as? [[String: Any]])?.first, "\(listed)")
        XCTAssertEqual(cand["unlocatableOrganizationKey"] as? Bool, true, "\(cand)")
        let id = try XCTUnwrap(cand["id"] as? String)
        // apply 與 reject：顯式點名 → 整批拒絕
        assertRefusedAsUnlocatable { try self.service.resolveOrganizations(apply: [id]) }
        assertRefusedAsUnlocatable { try self.service.resolveOrganizations(apply: nil, reject: [id]) }
        // judge 與 undecided：store 狀態不符 → 該筆略過並具名（這兩條腿的既有契約）
        let judged = try json(try service.resolveOrganizations(apply: nil, judge: ["\(id)@iss=論文機構欄"]))
        XCTAssertTrue(skipReasons(judged).contains { $0.contains("無法唯一定位") }, "\(skipReasons(judged))")
        let undecided = try json(try service.resolveOrganizations(apply: nil, undecided: ["\(id)@iss=查了所方名冊"]))
        XCTAssertTrue(skipReasons(undecided).contains { $0.contains("無法唯一定位") }, "\(skipReasons(undecided))")
        // 零寫入
        XCTAssertEqual(try store.load().people.first?.profile.affiliations.entries.first?.value, .literal("Institute of Statistical Science"))
        XCTAssertTrue(try store.load().organizations.allSatisfy { $0.references.isEmpty })
    }
}
