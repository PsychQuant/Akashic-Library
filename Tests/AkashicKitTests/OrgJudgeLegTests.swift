import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicEntity
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #647：resolve-organizations 的逐篇判定腿（`<列表的 id>@<orgKey>=理由`）。
final class OrgJudgeLegTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-org-judge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try "sources/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private var service: AkashicService { AkashicService(root: root) }
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
    private func affiliation(_ key: String) throws -> OrgRef? {
        try XCTUnwrap(try store.load().people.first { $0.key == key }).profile.affiliations.entries.first?.value
    }
    private func judgedVerdicts(_ orgKey: String) throws -> [ProvenanceReference] {
        try XCTUnwrap(try store.load().organizations.first { $0.key == orgKey }).references
            .filter { $0.field == ProvenanceReference.resolutionConfirmedField }
    }

    /// 候選列：歸戶並寫 org-judged 層級的 confirmed，理由進記錄。
    func testCandidateRowIsJudgedWithReason() throws {
        try org("iss", "ISS Academia Sinica")
        try person("chen-ch", affiliation: "ISS Academia Sinica")
        let out = json(try service.resolveOrganizations(apply: nil, judge: ["chen-ch::ISS Academia Sinica@iss=所方名冊列名"]))
        XCTAssertEqual((out["judged"] as? [[String: Any]])?.count, 1, "\(out)")
        XCTAssertEqual(try affiliation("chen-ch"), .key("iss"))
        let v = try XCTUnwrap(try judgedVerdicts("iss").first)
        XCTAssertEqual(v.verdictClass, .judged, "逐篇判定是 judged 層級")
        guard case let .judgement(statement, _) = v.kind else { return XCTFail("\(v)") }
        XCTAssertTrue(statement.contains("所方名冊列名"), statement)
        XCTAssertTrue(statement.contains("[rule: org-judged]"), statement)
    }

    /// 歧義條目也收——歧義的意思是提名器分不出來，不是人分不出來。
    func testAmbiguityEntryCanBeJudgedToOneOfItsOrganizations() throws {
        try org("as", "Sinica")
        try org("iss", "Sinica")
        try person("wang-x", affiliation: "Sinica")
        let listed = json(try service.resolveOrganizations(apply: nil))
        XCTAssertEqual((listed["ambiguities"] as? [[String: Any]])?.count, 1, "\(listed)")
        _ = try service.resolveOrganizations(apply: nil, judge: ["wang-x::Sinica@iss=論文署名的所址是統計所"])
        XCTAssertEqual(try affiliation("wang-x"), .key("iss"))
        XCTAssertThrowsError(try service.resolveOrganizations(apply: nil, judge: ["wang-x::Sinica@ntu=x"]),
                             "那一列已歸戶、離開列表——id 不再是列表的 id")
    }

    /// 查過未決的候選：#647 的起因——篩選式 --apply 排除它，逐篇判定可以歸戶它。
    func testUndecidedCandidateCanBeJudged() throws {
        try org("iss", "ISS")
        try person("lin-y", affiliation: "ISS")
        _ = try service.resolveOrganizations(apply: nil, undecided: ["lin-y::ISS@iss=縮寫與兩個機構都相容"])
        _ = try service.resolveOrganizations(apply: nil, judge: ["lin-y::ISS@iss=找到論文的完整署名"])
        XCTAssertEqual(try affiliation("lin-y"), .key("iss"))
    }

    /// 上級機構：判給會成環的那一個是 store 狀態不符——該筆略過並具名；另一個照常落地。
    func testParentThatWouldCloseACycleIsSkipped() throws {
        try org("b", "B Org", parents: [.key("a")])
        try org("c", "B Org")
        try org("a", "A Org", parents: [.literal("B Org")])
        let out = json(try service.resolveOrganizations(apply: nil, judge: ["a::B Org@b=x"]))
        XCTAssertEqual((out["judged"] as? [[String: Any]])?.count ?? 0, 0, "\(out)")
        let why = ((out["skipped"] as? [[String: Any]])?.first?["why"] as? String) ?? ""
        XCTAssertTrue(why.contains("成環"), why)
        XCTAssertEqual(try store.load().organizations.first { $0.key == "a" }?.parents.entries.first?.value, .literal("B Org"),
                       "略過的那一筆零寫入")
        _ = try service.resolveOrganizations(apply: nil, judge: ["a::B Org@c=x"])
        XCTAssertEqual(try store.load().organizations.first { $0.key == "a" }?.parents.entries.first?.value, .key("c"))
    }

    /// 輸入錯整批拒絕、零寫入：理由空白、同一列判兩次、與其他腿組合。
    func testInputErrorsRefuseTheWholeBatch() throws {
        try org("as", "Sinica")
        try org("iss", "Sinica")
        try person("wang-x", affiliation: "Sinica")
        try org("ntu", "NTU")
        try person("lee-z", affiliation: "NTU")
        XCTAssertThrowsError(try service.resolveOrganizations(apply: nil, judge: ["lee-z::NTU@ntu=  "]), "理由空白")
        XCTAssertThrowsError(try service.resolveOrganizations(apply: nil, judge: ["wang-x::Sinica@as=a", "wang-x::Sinica@iss=b"]),
                             "同一列判給兩個 org")
        XCTAssertThrowsError(try service.resolveOrganizations(apply: ["lee-z::NTU"], judge: ["lee-z::NTU@ntu=x"]), "與 apply 組合")
        XCTAssertThrowsError(try service.resolveOrganizations(apply: nil, judge: ["lee-z::NTU@ntu=ok", "lee-z::NTU@iss=x"]),
                             "一筆 orgKey 不是那一列提名的——整批拒絕")
        XCTAssertEqual(try affiliation("lee-z"), .literal("NTU"), "整批拒絕零寫入")
        XCTAssertEqual(try affiliation("wang-x"), .literal("Sinica"))
    }
}
