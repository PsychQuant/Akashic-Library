import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicEntity
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// change `resolution-verdict-states`（#636）：同一配對的提名層（apply／reject）與逐篇判定兩筆並存，
/// 以及未決記錄（#619）與判定並存時不構成矛盾。釘住「使用點指派」那一批：合併、rename、D64、#486。
final class JudgedCoexistenceTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-coexist-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try "sources/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func v(_ kind: ResolutionLedger.VerdictKind, holder: String, literal: String = "C-H Chen",
                   rule: String = ResolutionLedger.personRule, statement: String = "s") -> ProvenanceReference {
        kind == .undecided
            ? ResolutionLedger.record(undecided: .work, holder: holder, literal: literal, statement: statement, restsOn: [])
            : ResolutionLedger.record(kind, holderKind: .work, holder: holder, literal: literal, rule: rule, statement: statement)
    }
    private func person(_ key: String, _ refs: [ProvenanceReference]) throws {
        var p = Person(key: key, names: ["Person \(key)"])
        p.references = refs
        try store.writePerson(p)
    }
    private func entry(_ citekey: String, author: Author = .literal("C-H Chen")) throws {
        try store.writeEntry(Entry(id: UUID(), citekey: citekey, type: .periodicalArticle,
                                   title: "T \(citekey)", authors: [author], date: "2020"))
    }
    private func divergence(keeper: String, doomed: String, shape: EntityKind) throws -> Divergence {
        let d = Divergence(id: UUID(), question: "\(keeper) 與 \(doomed) 是同一個嗎",
                           candidates: [DivergenceCandidate(key: keeper, shape: shape),
                                        DivergenceCandidate(key: doomed, shape: shape)])
        _ = try store.writeDivergence(d)
        return d
    }
    private func refs(_ key: String) throws -> [ProvenanceReference] {
        try XCTUnwrap(try store.load().people.first { $0.key == key }).references
    }
    private let judged = ResolutionLedger.judgedRule

    // MARK: - health

    func testBothClassesAreNotADuplicateRecord() throws {
        try entry("w1")
        try person("p", [v(.confirmed, holder: "w1"), v(.confirmed, holder: "w1", rule: judged, statement: "機構一致")])
        XCTAssertTrue(store.health(from: try store.load()).duplicateVerdictRecords.isEmpty, "兩個層級是兩筆記錄，不是重複（#636）")
    }

    func testNominatedConfirmedAndJudgedRejectedIsAContradiction() throws {
        try entry("w1")
        try person("p", [v(.confirmed, holder: "w1"), v(.rejected, holder: "w1", rule: judged)])
        XCTAssertEqual(store.health(from: try store.load()).contradictoryVerdicts.count, 1, "矛盾不分層級")
    }

    func testUndecidedBesideADecisionIsNotAContradiction() throws {
        try entry("w1")
        try person("p", [v(.undecided, holder: "w1"), v(.confirmed, holder: "w1")])
        let h = store.health(from: try store.load())
        XCTAssertTrue(h.contradictoryVerdicts.isEmpty, "未決是查證歷史，不是矛盾")
        XCTAssertTrue(h.duplicateVerdictRecords.isEmpty)
    }

    // MARK: - merge

    func testPersonMergeKeepsBothClasses() throws {
        try entry("w1", author: .key("keep"))
        try person("keep", [v(.confirmed, holder: "w1")])
        try person("doom", [v(.confirmed, holder: "w1", rule: judged, statement: "機構一致")])
        let d = try divergence(keeper: "keep", doomed: "doom", shape: .person)
        GitFixture.commitAll(root)
        _ = try store.resolveDivergence(id: d.id, survivor: "keep")
        let kept = try refs("keep")
        XCTAssertEqual(Set(kept.compactMap(\.verdictClass)), [.nominated, .judged], "\(kept)")
    }

    func testWorkMergeKeepsBothClassesOnTheHolder() throws {
        try entry("keep2020a")
        try entry("doom2020a")
        try person("p", [v(.confirmed, holder: "doom2020a"), v(.confirmed, holder: "keep2020a", rule: judged, statement: "機構一致")])
        let d = try divergence(keeper: "keep2020a", doomed: "doom2020a", shape: .work)
        GitFixture.commitAll(root)
        _ = try store.resolveDivergence(id: d.id, survivor: "keep2020a")
        let vs = ResolutionLedger.verdicts(references: try refs("p")).verdicts
        XCTAssertEqual(vs.count, 2, "\(vs)")
        XCTAssertTrue(vs.allSatisfy { $0.holder == "keep2020a" })
    }

    func testMergeDoesNotRefuseUndecidedBesideADecision() throws {
        try entry("w1", author: .key("keep"))
        try person("keep", [v(.confirmed, holder: "w1")])
        try person("doom", [v(.undecided, holder: "w1")])
        let d = try divergence(keeper: "keep", doomed: "doom", shape: .person)
        GitFixture.commitAll(root)
        XCTAssertNoThrow(try store.resolveDivergence(id: d.id, survivor: "keep"))
        XCTAssertEqual(try refs("keep").count, 2)
    }

    // MARK: - rename

    func testRenameKeepsBothClassesAndDistinctUndecidedChecks() throws {
        try entry("w1")
        try person("p", [v(.confirmed, holder: "w1"), v(.confirmed, holder: "w1", rule: judged, statement: "機構一致"),
                         v(.undecided, holder: "w1", statement: "查了機構"), v(.undecided, holder: "w1", statement: "查了共同作者")])
        GitFixture.commitAll(root)
        _ = try store.renameEntry(from: "w1", to: "w2")
        let vs = ResolutionLedger.verdicts(references: try refs("p")).verdicts
        XCTAssertEqual(vs.count, 4, "\(vs)")
        XCTAssertTrue(vs.allSatisfy { $0.holder == "w2" })
    }

    // MARK: - service：judge／refute 並存（spec「Per-work judgement SHALL coexist with an earlier nominated verdict」）

    private func service() -> AkashicService { AkashicService(root: root) }
    private func json(_ s: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any]) ?? [:]
    }

    func testJudgeAfterApplyWritesACoexistingJudgedVerdict() throws {
        try entry("w1", author: .key("p"))
        try person("p", [v(.confirmed, holder: "w1")])
        GitFixture.commitAll(root)
        let out = json(try service().resolvePeople(apply: nil, judge: ["w1:0:p=論文登記中研院統計所"]))
        let row = try XCTUnwrap((out["judged"] as? [[String: Any]])?.first, "\(out)")
        XCTAssertEqual(row["coexistsWith"] as? String, "nominated")
        XCTAssertEqual(Set(try refs("p").compactMap(\.verdictClass)), [.nominated, .judged])
        XCTAssertEqual(try store.load().entries.first?.authors, [.key("p")], "作者位不動")
    }

    func testRefuteAfterRejectWritesACoexistingJudgedVerdict() throws {
        try entry("w1")
        try person("p", [v(.rejected, holder: "w1")])
        GitFixture.commitAll(root)
        let out = json(try service().resolvePeople(apply: nil, refute: ["w1:0:p=機構不同"]))
        XCTAssertEqual((out["refuted"] as? [[String: Any]])?.first?["coexistsWith"] as? String, "nominated", "\(out)")
        XCTAssertEqual(try refs("p").filter { $0.field == "resolution-rejected" }.count, 2)
    }

    func testCoexistenceNeedsFormat19() throws {
        try entry("w1", author: .key("p"))
        try person("p", [v(.confirmed, holder: "w1")])
        try StoreVersion.write(root: root, format: 18)
        GitFixture.commitAll(root)
        let out = json(try service().resolvePeople(apply: nil, judge: ["w1:0:p=理由"]))
        let why = ((out["skipped"] as? [[String: Any]])?.first?["why"] as? String) ?? ""
        XCTAssertTrue(why.contains("19"), "\(out)")
        XCTAssertEqual(try refs("p").count, 1, "零寫入")
    }
}
