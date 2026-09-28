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

    /// R1 verify Codex HIGH：預驗只涵蓋收到 verdict 的目標 org，holder org（上級機構被改寫的那一筆）違反寫入期不變式時，
    /// person 已經落盤才被拒。現在整個寫入集合先驗，任一筆不過就零寫入。
    func testInvalidHolderOrganizationRefusesTheWholeBatchBeforeAnyWrite() throws {
        try org("b", "B Org")
        var a = Organization(key: "a")
        a.names = TimelineOf([TemporalValue(value: "A Org", range: DateRange())])
        a.authorized = ["A Org"]
        a.parents = TimelineOf([TemporalValue(value: OrgRef.literal("B Org"), range: DateRange())])
        let url = try store.writeOrganization(a)
        // 手改成違反不變式（authorized 不在 names 裡）——decode 不驗，載得進來，寫入閘會拒
        let text = try String(contentsOf: url, encoding: .utf8)
        let broken = text.replacingOccurrences(of: "authorized:\n- A Org", with: "authorized:\n- Not A Name")
        XCTAssertNotEqual(text, broken, "fixture 沒改到：\(text)")
        try broken.write(to: url, atomically: true, encoding: .utf8)
        try person("p", affiliation: "B Org")
        XCTAssertThrowsError(try service.resolveOrganizations(apply: nil, judge: ["p::B Org@b=x", "a::B Org@b=y"]))
        XCTAssertEqual(try affiliation("p"), .literal("B Org"), "person 不得先落盤")
        XCTAssertTrue(try judgedVerdicts("b").isEmpty, "目標 org 的 verdict 也不得落盤")
    }

    /// R1 verify logic：verdict 以 (holder, literal) 配對、不帶作者位索引。同一筆 work 兩個作者位是同一個 literal 時，
    /// 兩個位置都歸戶，但第二句理由被去重吃掉——要說出來，不能列成已判定而不標。
    func testSecondReasonForTheSamePairingIsReportedAsNotRecorded() throws {
        try org("apa", "APA")
        var e = Entry(id: UUID(), citekey: "ck2020", type: .periodicalArticle, title: "T",
                      authors: [.literal("{APA}"), .literal("{APA}")], date: "2020")   // 團體作者要大括號標記（CorporateName.isMarked）
        e.fields = [:]
        try store.writeEntry(e)
        let out = json(try service.resolveOrganizations(apply: nil, judge: ["ck2020[0]::APA@apa=reason ONE",
                                                                              "ck2020[1]::APA@apa=reason TWO"]))
        let rows = try XCTUnwrap(out["judged"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 2, "\(out)")
        XCTAssertNil(rows[0]["verdictNotRecorded"])
        XCTAssertNotNil(rows[1]["verdictNotRecorded"], "第二句理由沒寫進去，要標出來：\(rows)")
        XCTAssertEqual(try judgedVerdicts("apa").count, 1)
        XCTAssertEqual(try store.load().entries.first?.authors, [.organization("apa"), .organization("apa")])
    }

    /// R2 verify DA：歧義條目的 orgKeys 不過濾否決，id 驗得過而那個 org 已否決過這個配對——照寫會留下 confirmed＋rejected 的
    /// 矛盾對。該筆略過並具名，不寫任何東西。
    func testJudgingToAnOrganizationThatRejectedThePairingIsSkipped() throws {
        try org("as", "Sinica")
        try person("wang-x", affiliation: "Sinica")
        _ = try service.resolveOrganizations(apply: nil, reject: ["wang-x::Sinica"])
        try org("iss", "Sinica")
        let out = json(try service.resolveOrganizations(apply: nil, judge: ["wang-x::Sinica@as=論文署名"]))
        XCTAssertEqual((out["judged"] as? [[String: Any]])?.count ?? 0, 0, "\(out)")
        let why = ((out["skipped"] as? [[String: Any]])?.first?["why"] as? String) ?? ""
        XCTAssertTrue(why.contains("已否決過"), why)
        XCTAssertEqual(try affiliation("wang-x"), .literal("Sinica"))
        XCTAssertTrue(try judgedVerdicts("as").isEmpty)
        XCTAssertEqual(StoreHealthProbe.contradictions(store), 0)
    }

    /// R2 verify DA：內容閘之外還有 #631 的目的檔檢查。legacy 佈局的 entry 未被 git 追蹤時，entry 的寫入會被拒——
    /// 那要在任何一筆落盤之前發生，person 不得先寫。
    func testDestinationChecksRunBeforeAnyWrite() throws {
        try org("apa", "APA")
        try person("pp", affiliation: "APA")
        // 只放在 legacy 的 entries/ 下、未 commit：`entryWritePlan` 會拒（legacyCopyUnmovable）
        let legacyDir = root.appendingPathComponent("entries")
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        var e = Entry(id: UUID(), citekey: "ck2020", type: .periodicalArticle, title: "T",
                      authors: [.literal("{APA}")], date: "2020")
        e.fields = [:]
        try store.writeEntry(e)
        let modern = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("entities"), includingPropertiesForKeys: nil)
            .first { (try? String(contentsOf: $0, encoding: .utf8))?.contains("ck2020") == true }
        try FileManager.default.moveItem(at: try XCTUnwrap(modern), to: legacyDir.appendingPathComponent("ck2020.yaml"))
        XCTAssertThrowsError(try service.resolveOrganizations(apply: nil, judge: ["pp::APA@apa=x", "ck2020[0]::APA@apa=y"]))
        XCTAssertEqual(try affiliation("pp"), .literal("APA"), "person 不得先落盤")
        XCTAssertTrue(try judgedVerdicts("apa").isEmpty)
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

/// 矛盾對計數的最小探針（避免測試依賴 StoreHealth 的完整建構）。
enum StoreHealthProbe {
    static func contradictions(_ store: LibraryStore) -> Int {
        (try? store.health(from: store.load()).contradictoryVerdicts.count) ?? -1
    }
}
