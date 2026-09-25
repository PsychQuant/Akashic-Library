import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicEntity
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// change `org-undecided-leg`（#643）：resolve-organizations 的未決腿。
final class OrgUndecidedLegTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-org-undecided-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try "sources/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private var service: AkashicService { AkashicService(root: root) }

    // MARK: - 1.2 解析（spec「An undecided id SHALL be split only where the prefix is a known row id」）

    /// spec 的 split 表，一列一個斷言。
    func testSplitTable() {
        let ok = AkashicService.splitOrgUndecided("p::A@iss=x", knownRowIDs: ["p::A"])
        XCTAssertEqual(ok.accepted.map { [$0.rowID, $0.orgKey, $0.statement] }, [["p::A", "iss", "x"]])
        XCTAssertTrue(AkashicService.splitOrgUndecided("p::A@iss=x", knownRowIDs: []).accepted.isEmpty, "無已知 rowID")
        XCTAssertEqual(AkashicService.splitOrgUndecided("p::A@b=c@iss=x", knownRowIDs: ["p::A", "p::A@b=c"]).accepted.count, 2,
                       "兩個切法都成立")
    }

    /// spec 的 Scenario：literal 含 `@` 與 `=`。
    func testLiteralWithAtAndEquals() {
        let r = AkashicService.splitOrgUndecided("chen-ch::Lab@Sinica=Dept@iss=查過",
                                                  knownRowIDs: ["chen-ch::Lab@Sinica=Dept"])
        XCTAssertEqual(r.accepted.map { [$0.rowID, $0.orgKey, $0.statement] }, [["chen-ch::Lab@Sinica=Dept", "iss", "查過"]])
    }

    /// `@` 與 `=` 之間不是 StoreKey（大寫、空白）就不是可切的位置。
    func testNonStoreKeyBetweenAtAndEqualsIsNotASplit() {
        XCTAssertTrue(AkashicService.splitOrgUndecided("p::A@ISS=x", knownRowIDs: ["p::A"]).accepted.isEmpty)
        XCTAssertTrue(AkashicService.splitOrgUndecided("p::A@i s=x", knownRowIDs: ["p::A"]).accepted.isEmpty)
        XCTAssertTrue(AkashicService.splitOrgUndecided("p::A@-iss=x", knownRowIDs: ["p::A"]).accepted.isEmpty, "StoreKey 不以 - 開頭")
    }

    /// 整批：零個或多個切法、orgKey 不在那一列、說明空白、id 重複都整批拒絕。
    func testParseRefusals() throws {
        let rows: [String: Set<String>] = ["p::Sinica": ["iss"], "q::Lab": ["as", "iss"]]
        XCTAssertNoThrow(try service.parseOrgUndecidedSpecs(["p::Sinica@iss=查過", "q::Lab@as=查過"], restsOn: [], rows: rows))
        XCTAssertThrowsError(try service.parseOrgUndecidedSpecs(["p::Sinica@ntu=x"], restsOn: [], rows: rows), "orgKey 不在那一列")
        XCTAssertThrowsError(try service.parseOrgUndecidedSpecs(["r::X@iss=x"], restsOn: [], rows: rows), "不是已知 rowID")
        XCTAssertThrowsError(try service.parseOrgUndecidedSpecs(["p::Sinica@iss=  "], restsOn: [], rows: rows), "說明空白")
        XCTAssertThrowsError(try service.parseOrgUndecidedSpecs(["p::Sinica@iss=a", "p::Sinica@iss=b"], restsOn: [], rows: rows),
                             "同一個 rowID＋org 重複")
    }
    // MARK: - 2.1 寫入面（spec「resolve-organizations SHALL provide an explicit undecided leg on both faces」）

    private func json(_ s: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any]) ?? [:]
    }
    private func org(_ key: String, _ name: String, parents: [OrgRef] = []) throws {
        var o = Organization(key: key)
        o.names = TimelineOf([TemporalValue(value: name, range: DateRange())])
        o.parents = TimelineOf(parents.map { TemporalValue(value: $0, range: DateRange()) })
        try store.writeOrganization(o)
    }
    private func person(_ key: String, affiliation: String) throws {
        var p = Person(key: key, names: [key])
        p.profile.affiliations = TimelineOf([TemporalValue(value: OrgRef.literal(affiliation), range: DateRange())])
        try store.writePerson(p)
    }
    private func orgRefs(_ key: String) throws -> [ProvenanceReference] {
        try XCTUnwrap(try store.load().organizations.first { $0.key == key }).references
    }
    private func recorded(_ out: [String: Any]) -> [[String: Any]] { (out["undecided"] as? [[String: Any]]) ?? [] }

    /// spec 的 Scenario「Recording an undecided affiliation pairing」。
    func testAffiliationHolder() throws {
        try org("iss", "ISS Academia Sinica")
        try person("chen-ch", affiliation: "ISS Academia Sinica")
        let out = json(try service.resolveOrganizations(apply: nil, undecided: ["chen-ch::ISS Academia Sinica@iss=研究所名稱縮寫與兩個機構都相容"]))
        XCTAssertEqual(recorded(out).count, 1, "\(out)")
        let r = try orgRefs("iss")
        XCTAssertEqual(r.map(\.field), ["resolution-undecided"])
        XCTAssertEqual(r.first?.value, "person:chen-ch :: ISS Academia Sinica")
        let p = try XCTUnwrap(try store.load().people.first { $0.key == "chen-ch" })
        XCTAssertEqual(p.profile.affiliations.entries.first?.value, .literal("ISS Academia Sinica"), "affiliation 仍是 literal")
    }

    func testParentsHolder() throws {
        try org("as", "Academia Sinica")
        try org("iss", "ISS", parents: [.literal("Academia Sinica")])
        _ = json(try service.resolveOrganizations(apply: nil, undecided: ["iss::Academia Sinica@as=查過院本部組織規程"]))
        XCTAssertEqual(try orgRefs("as").first?.value, "org:iss :: Academia Sinica")
    }

    func testWorkHolder() throws {
        try org("apa", "American Psychological Association")
        try store.writeEntry(Entry(id: UUID(), citekey: "apa2020", type: .book, title: "T",
                                   authors: [.literal("{American Psychological Association}")], date: "2020"))
        let out = json(try service.resolveOrganizations(apply: nil, undecided: ["apa2020[0]::American Psychological Association@apa=查過"]))
        XCTAssertEqual(recorded(out).count, 1, "\(out)")
        XCTAssertEqual(try orgRefs("apa").first?.value, "work:apa2020 :: American Psychological Association")
    }

    /// spec 的 Scenario「Recording against each organization of an ambiguity」。
    func testAmbiguityRecordsEachOrganization() throws {
        try org("as", "Sinica")
        try org("iss", "Sinica")
        try person("p", affiliation: "Sinica")
        let out = json(try service.resolveOrganizations(apply: nil, undecided: ["p::Sinica@as=查過院本部名冊", "p::Sinica@iss=查過所名冊"]))
        XCTAssertEqual(recorded(out).count, 2, "\(out)")
        XCTAssertEqual(try orgRefs("as").count, 1)
        XCTAssertEqual(try orgRefs("iss").count, 1)
    }

    /// spec 的 Scenario「An organization outside the row」。
    func testOrganizationOutsideTheRowIsRefused() throws {
        try org("iss", "Sinica")
        try org("ntu", "National Taiwan University")
        try person("p", affiliation: "Sinica")
        XCTAssertThrowsError(try service.resolveOrganizations(apply: nil, undecided: ["p::Sinica@ntu=x"]))
        XCTAssertTrue(try orgRefs("ntu").isEmpty)
    }

    func testDecidedPairingIsSkipped() throws {
        try org("iss", "Sinica")
        try person("p", affiliation: "Sinica")
        _ = try service.resolveOrganizations(apply: nil, reject: ["p::Sinica"])
        let out = json(try service.resolveOrganizations(apply: nil, undecided: ["p::Sinica@iss=查過"]))
        XCTAssertEqual((out["skipped"] as? [Any])?.count, 1, "\(out)")
        XCTAssertEqual(try orgRefs("iss").map(\.field), ["resolution-rejected"])
    }

    func testAlreadyRecordedAndSameCallDuplicate() throws {
        try org("apa", "APA")
        try store.writeEntry(Entry(id: UUID(), citekey: "w", type: .book, title: "T",
                                   authors: [.literal("{APA}"), .literal("{APA}")], date: "2020"))
        let first = json(try service.resolveOrganizations(apply: nil, undecided: ["w[0]::APA@apa=查過", "w[1]::APA@apa=查過"]))
        XCTAssertEqual(recorded(first).count, 2, "同一次呼叫的第二個相同記錄報成本次寫入：\(first)")
        XCTAssertEqual(try orgRefs("apa").count, 1)
        let again = json(try service.resolveOrganizations(apply: nil, undecided: ["w[0]::APA@apa=查過"]))
        XCTAssertEqual((again["alreadyRecorded"] as? [Any])?.count, 1, "\(again)")
    }

    /// spec 的 Scenario「Undecided write on a format-18 store」與「Combining the leg with apply」。
    func testFormat18AndCombinationsAreRefused() throws {
        try org("iss", "Sinica")
        try person("p", affiliation: "Sinica")
        XCTAssertThrowsError(try service.resolveOrganizations(apply: ["p::Sinica"], undecided: ["p::Sinica@iss=x"]))
        XCTAssertThrowsError(try service.resolveOrganizations(apply: nil, reject: ["p::Sinica"], undecided: ["p::Sinica@iss=x"]))
        XCTAssertThrowsError(try service.resolveOrganizations(apply: nil, restsOn: ["sha256:" + String(repeating: "a", count: 64)]))
        try StoreVersion.write(root: root, format: 18)
        XCTAssertThrowsError(try service.resolveOrganizations(apply: nil, undecided: ["p::Sinica@iss=x"]))
        XCTAssertTrue(try orgRefs("iss").isEmpty)
    }
    // MARK: - 2.2 列表揭露（spec「The listing SHALL disclose undecided checks and give every row an id」）

    /// spec 的 Scenario「A checked candidate in the listing」＋ 歧義條目的 id 與物件形。
    func testListingDisclosesUndecidedChecks() throws {
        try org("iss", "ISS Academia Sinica")
        try person("chen-ch", affiliation: "ISS Academia Sinica")
        try org("as", "Sinica")
        try org("sinica-2", "Sinica")
        try person("p", affiliation: "Sinica")
        _ = try service.resolveOrganizations(apply: nil, undecided: ["chen-ch::ISS Academia Sinica@iss=查過", "p::Sinica@as=查過"])
        let list = json(try service.resolveOrganizations(apply: nil))
        let cand = try XCTUnwrap((list["candidates"] as? [[String: Any]])?.first { ($0["id"] as? String) == "chen-ch::ISS Academia Sinica" })
        XCTAssertEqual(cand["undecidedChecks"] as? Int, 1, "\(list)")
        let amb = try XCTUnwrap((list["ambiguities"] as? [[String: Any]])?.first)
        XCTAssertEqual(amb["id"] as? String, "p::Sinica", "歧義條目帶 id")
        XCTAssertEqual(amb["undecidedChecks"] as? [String: Int], ["as": 1], "只列非零的 org")
        XCTAssertEqual(list["undecidedTotal"] as? Int, 2)
    }

    /// 沒有未決記錄時：候選列 0、歧義條目空物件、總數 0。
    func testListingWithoutUndecidedRecords() throws {
        try org("iss", "Sinica")
        try person("p", affiliation: "Sinica")
        let list = json(try service.resolveOrganizations(apply: nil))
        XCTAssertEqual((list["candidates"] as? [[String: Any]])?.first?["undecidedChecks"] as? Int, 0)
        XCTAssertEqual(list["undecidedTotal"] as? Int, 0)
    }
}

