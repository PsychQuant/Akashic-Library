import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #663：MCP 的 resolve-people 歧義條目（`people[ref]`）對隸屬的說法。
///
/// 先前只被觀測到的隸屬送 `formerAffiliation` ＋ `formerAffiliationAttested`——「former」是一個離開的斷言，
/// 而匯出端對同一人說 `undetermined`（#661）。現在 `formerAffiliation*` 只給宣稱已結束的段，只被觀測到的段另有
/// `observedAffiliation` ＋ `observedAffiliationAt`；混合情形兩組都送。舊鍵 `formerAffiliationAttested` 退場、
/// 不改語意沿用——讀它的呼叫端得到「缺席」而不是一個換了意思的值。
final class AffiliationStandingPayloadTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!
    private var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-standing-\(UUID().uuidString)")
        store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        service = AkashicService(root: root, key: nil, environment: [:])
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// 帶指定隸屬的人 `stand-x`，加一個同名、帶 ORCID 的 `stand-y`（於是有歧義條目）→ `people[ref]` 的 `stand-x` 條目。
    private func entry(_ segments: [(String, DateRange)]) throws -> [String: Any] {
        var x = Person(key: "stand-x", names: PersonNames(variant: ["Stand Same"]))
        x.profile.affiliations = TimelineOf(segments.map {
            TemporalValue(value: OrgRef.literal($0.0), range: $0.1)
        })
        try store.writePerson(x)
        var y = Person(key: "stand-y", names: PersonNames(variant: ["Stand Same"]))
        y.orcid = try XCTUnwrap(ORCID("0000-0003-4038-9439"))
        try store.writePerson(y)
        try store.writeEntry(Entry(id: UUID(), citekey: "stand2020", type: .periodicalArticle,
                                   title: "X", authors: [.literal("Stand Same")], date: "2020"))
        let out = try JSONSerialization.jsonObject(
            with: Data(try service.resolvePeople(apply: nil).utf8)) as! [String: Any]
        let people = out["people"] as! [String: [String: Any]]
        return try XCTUnwrap(people.values.first { $0["key"] as? String == "stand-x" }, "\(people)")
    }

    private func affiliationKeys(_ e: [String: Any]) -> Set<String> {
        Set(e.keys.filter { $0.contains("Affiliation") })
    }

    func testAttestedOnlyIsObservedNotFormer() throws {
        let e = try entry([("ISS", DateRange(attested: ["2019-05", "2021"]))])
        XCTAssertEqual(e["observedAffiliation"] as? String, "ISS")
        XCTAssertEqual(e["observedAffiliationAt"] as? String, "2021", "只送最近的一個觀測點（與先前同）")
        XCTAssertEqual(affiliationKeys(e), ["observedAffiliation", "observedAffiliationAt"],
                       "沒有任何一段宣稱結束——不得有 formerAffiliation*：\(e)")
    }

    func testOnlyEndedIsStillFormer() throws {
        let e = try entry([("ISS", DateRange(start: "2010", end: "2018"))])
        XCTAssertEqual(e["formerAffiliation"] as? String, "ISS")
        XCTAssertEqual(e["formerAffiliationEnd"] as? String, "2018")
        XCTAssertEqual(affiliationKeys(e), ["formerAffiliation", "formerAffiliationEnd"])
    }

    func testEndedUnknownIsFormerWithUnknownEnd() throws {
        let e = try entry([("Gone Lab", DateRange(endedUnknown: true))])
        XCTAssertEqual(e["formerAffiliation"] as? String, "Gone Lab")
        XCTAssertEqual(e["formerAffiliationEnd"] as? String, "unknown")
        XCTAssertNil(e["observedAffiliation"])
    }

    /// **混合情形兩組都送**：先前只有 `formerAffiliation`（NTU），觀測段整個不見。
    func testMixedSendsBothGroups() throws {
        let e = try entry([("NTU", DateRange(start: "2000", end: "2010")),
                           ("ISS", DateRange(attested: ["2015"]))])
        XCTAssertEqual(e["formerAffiliation"] as? String, "NTU")
        XCTAssertEqual(e["formerAffiliationEnd"] as? String, "2010")
        XCTAssertEqual(e["observedAffiliation"] as? String, "ISS")
        XCTAssertEqual(e["observedAffiliationAt"] as? String, "2015")
    }

    func testCurrentSendsOnlyCurrentAffiliation() throws {
        let e = try entry([("ISS", DateRange(start: "2020")), ("NTU", DateRange(attested: ["2012"]))])
        XCTAssertEqual(e["currentAffiliation"] as? String, "ISS")
        XCTAssertEqual(affiliationKeys(e), ["currentAffiliation"], "有現職就只送現職（與先前同）：\(e)")
    }

    func testTheRetiredKeyIsGoneNotRepurposed() throws {
        for segs in [[("ISS", DateRange(attested: ["2021"]))],
                     [("NTU", DateRange(start: "2000", end: "2010")), ("ISS", DateRange(attested: ["2015"]))]] {
            XCTAssertNil(try entry(segs)["formerAffiliationAttested"],
                         "舊鍵退場：讀它的呼叫端要得到缺席，不是一個換了意思的值")
            try? FileManager.default.removeItem(at: root)
            try setUpWithError()
        }
    }
}
