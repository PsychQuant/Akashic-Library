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
        XCTAssertTrue(AkashicService.splitOrgUndecided("p::A@iss=x", knownRowIDs: Set<String>()).accepted.isEmpty, "無已知 rowID")
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
        // R1 verify：undecidedTotal 與 CLI 四態計數行、resolve-people 同一個定義（只數候選配對）；歧義條目另數
        XCTAssertEqual(list["undecidedTotal"] as? Int, 1)
        XCTAssertEqual(list["ambiguityUndecidedTotal"] as? Int, 1)
    }

    /// 沒有未決記錄時：候選列 0、歧義條目空物件、總數 0。
    func testListingWithoutUndecidedRecords() throws {
        try org("iss", "Sinica")
        try person("p", affiliation: "Sinica")
        let list = json(try service.resolveOrganizations(apply: nil))
        XCTAssertEqual((list["candidates"] as? [[String: Any]])?.first?["undecidedChecks"] as? Int, 0)
        XCTAssertEqual(list["undecidedTotal"] as? Int, 0)
        XCTAssertEqual(list["ambiguityUndecidedTotal"] as? Int, 0)
    }

    // MARK: - R1 verify 的修正

    /// person 與 organization 同 key、同 literal 時兩列的 id 相同：整批拒絕，不把記錄寫到先解析到的那一種 holder 下。
    func testPersonAndOrganizationWithTheSameKeyAreRefused() throws {
        try org("lab", "Lab")
        try org("x", "X Institute", parents: [.literal("Lab")])
        try person("x", affiliation: "Lab")
        XCTAssertThrowsError(try service.resolveOrganizations(apply: nil, undecided: ["x::Lab@lab=查過"])) { error in
            XCTAssertTrue("\(error)".contains("同時是 person 與 organization 兩列"), "\(error)")
        }
        XCTAssertTrue(try orgRefs("lab").isEmpty)
    }

    /// 列表帶否決過濾、未決腿若只用不帶否決的那次 resolve，parents 的循環守衛會擋掉列表上看得到的列。
    /// a→b 已否決；b 的 parents literal 指向 a。列表上有 `b::A Org`，未決腿必須認得它。
    func testRowShownOnlyByTheRejectFilteredRunIsKnown() throws {
        try org("a", "A Org", parents: [.literal("B Org")])
        try org("b", "B Org", parents: [.literal("A Org")])
        _ = try service.resolveOrganizations(apply: nil, reject: ["a::B Org"])
        let list = json(try service.resolveOrganizations(apply: nil))
        let ids = ((list["candidates"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
        XCTAssertTrue(ids.contains("b::A Org"), "前提：列表看得到這一列：\(list)")
        let out = json(try service.resolveOrganizations(apply: nil, undecided: ["b::A Org@a=查過院組織規程"]))
        XCTAssertEqual(recorded(out).count, 1, "\(out)")
    }

    /// rowID 以位元組比對：列表的 literal 是 NFD 時，送 NFC 拼法不算同一個 id。
    func testRowIDMatchIsByteExact() throws {
        let nfd = "Cafe\u{0301} Lab"
        try org("cafe", nfd)
        try person("p", affiliation: nfd)
        XCTAssertThrowsError(try service.resolveOrganizations(apply: nil, undecided: ["p::Café Lab@cafe=查過"]), "NFC 拼法")
        XCTAssertTrue(try orgRefs("cafe").isEmpty)
        let out = json(try service.resolveOrganizations(apply: nil, undecided: ["p::\(nfd)@cafe=查過"]))
        XCTAssertEqual(recorded(out).count, 1, "逐字的 NFD 拼法：\(out)")
    }

    /// 超過任何合法 id 長度的輸入在試切之前就整批拒絕；試切本身對長輸入是線性的。
    func testOverlongSpecIsRefusedBeforeSplittingAndSplitIsLinear() throws {
        try org("iss", "Sinica")
        try person("p", affiliation: "Sinica")
        let long = "p::Sinica@iss=" + String(repeating: "x", count: 5_000)
        XCTAssertThrowsError(try service.resolveOrganizations(apply: nil, undecided: [long])) { error in
            XCTAssertTrue("\(error)".contains("超過任何合法 id 的上限"), "\(error)")
        }
        let adversarial = String(repeating: "@a=", count: 20_000)   // 60 KB，每個 @ 都是可切的位置
        let start = Date()
        let r = AkashicService.splitOrgUndecided(adversarial, knownRowIDs: ["p::Sinica"])
        XCTAssertEqual(r.tried, 20_000)
        XCTAssertTrue(r.accepted.isEmpty)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0, "R1 verify 實測先前 60 KB 跑 14 秒")
    }

    /// R2 verify DA 重現一：person 那一列已否決、列表上只剩 org 那一列時，逐字複製的 id 要收下，不當成撞號。
    func testRejectedPersonRowDoesNotCollideWithTheListedOrgRow() throws {
        try org("lab", "Lab")
        try org("x", "X Institute", parents: [.literal("Lab")])
        try person("x", affiliation: "Lab")
        _ = try service.resolveOrganizations(apply: nil, reject: ["x::Lab"])   // byID 取第一列（person）
        let ids = ((json(try service.resolveOrganizations(apply: nil))["candidates"] as? [[String: Any]]) ?? [])
            .compactMap { $0["id"] as? String }
        XCTAssertEqual(ids, ["x::Lab"], "前提：列表只剩 org 那一列")
        let out = json(try service.resolveOrganizations(apply: nil, undecided: ["x::Lab@lab=查過院組織規程"]))
        XCTAssertEqual(recorded(out).count, 1, "\(out)")
        XCTAssertTrue(try orgRefs("lab").contains { $0.value == "org:x :: Lab" && $0.field == "resolution-undecided" })
    }

    /// R2 verify DA 重現二：否決另一個配對後離開列表、沒有人判定過的列，其舊 id 要整批拒絕，不寫出一筆看不到的記錄。
    func testRowThatLeftTheListingWithoutBeingDecidedIsRefused() throws {
        try org("a", "A Org", parents: [.key("c"), .literal("B Org")])
        try org("b", "B Org", parents: [.literal("A Org")])
        try org("c", "C Org", parents: [.literal("B Org")])
        _ = try service.resolveOrganizations(apply: nil, reject: ["a::B Org"])
        let ids = ((json(try service.resolveOrganizations(apply: nil))["candidates"] as? [[String: Any]]) ?? [])
            .compactMap { $0["id"] as? String }
        XCTAssertFalse(ids.contains("c::B Org"), "前提：c::B Org 已離開列表：\(ids)")
        XCTAssertThrowsError(try service.resolveOrganizations(apply: nil, undecided: ["c::B Org@b=查過"]))
        XCTAssertFalse(try orgRefs("b").contains { $0.field == "resolution-undecided" })
    }

    /// 已否決的配對（不在列表上）仍走逐筆略過，不整批拒絕。
    func testRejectedPairingOffTheListingIsSkipped() throws {
        try org("iss", "Sinica")
        try person("p", affiliation: "Sinica")
        _ = try service.resolveOrganizations(apply: nil, reject: ["p::Sinica"])
        let out = json(try service.resolveOrganizations(apply: nil, undecided: ["p::Sinica@iss=查過"]))
        XCTAssertEqual((out["skipped"] as? [Any])?.count, 1, "\(out)")
    }

    /// 巢狀的已知前綴：第二個切法成立即停，說明不組（R2 verify：每個切法各複製一次尾段）。
    func testNestedKnownPrefixesStopAtTheSecondSplit() {
        let known: Set<String> = ["p::A", "p::A@a=x", "p::A@a=x@a=x"]
        let r = AkashicService.splitOrgUndecided("p::A@a=x@a=x@a=" + String(repeating: "y", count: 10_000), knownRowIDs: known)
        XCTAssertEqual(r.accepted.count, 2)
        XCTAssertTrue(r.accepted.allSatisfy { $0.statement.isEmpty })
    }

    /// 結果裡的 id 不截斷：同一歧義條目的兩個 org，literal 很長時仍分得開。
    func testLongLiteralIDsStayDistinguishableInTheResult() throws {
        let long = "Institute " + String(repeating: "of Very Long Names ", count: 20)
        let name = long.trimmingCharacters(in: .whitespaces)
        try org("as", name)
        try org("iss", name)
        try person("p", affiliation: name)
        let out = json(try service.resolveOrganizations(apply: nil, undecided: ["p::\(name)@as=查過", "p::\(name)@iss=查過"]))
        let ids = Set(recorded(out).compactMap { $0["id"] as? String })
        XCTAssertEqual(ids.count, 2, "\(ids)")
    }

    /// 切得開但前綴不是已知 id（例如那一列已歸戶而離開列表）時，訊息要與格式錯分得開。
    func testStaleIDMessageDiffersFromFormatError() throws {
        try org("iss", "Sinica")
        try person("p", affiliation: "Sinica")
        XCTAssertThrowsError(try service.resolveOrganizations(apply: nil, undecided: ["q::Gone@iss=x"])) { error in
            XCTAssertTrue("\(error)".contains("離開列表"), "\(error)")
        }
        XCTAssertThrowsError(try service.resolveOrganizations(apply: nil, undecided: ["p::Sinica=x"])) { error in
            XCTAssertTrue("\(error)".contains("不是 <列表的 id>@<orgKey>=<說明> 的格式"), "\(error)")
        }
    }
}

