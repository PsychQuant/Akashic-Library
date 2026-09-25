import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicEntity
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// change `resolution-verdict-states` R2 verify 的修正，逐項釘住（標題是 verify 報告的列）。
final class ResolutionVerdictStatesR2Tests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-rvs-r2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try "sources/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
        for key in ["chen-ch", "chen-ch-b"] {
            var p = Person(key: key, names: ["C-H Chen"])
            p.names = PersonNames(authorized: ["C-H Chen"], variant: [])
            try store.writePerson(p)
        }
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private var service: AkashicService { AkashicService(root: root) }
    private func json(_ s: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any]) ?? [:]
    }
    private func work(_ ck: String, _ authors: [Author]) throws {
        try store.writeEntry(Entry(id: UUID(), citekey: ck, type: .periodicalArticle, title: "T \(ck)",
                                   authors: authors, date: "2020"))
    }
    private func refs(_ key: String = "chen-ch") throws -> [ProvenanceReference] {
        try XCTUnwrap(try store.load().people.first { $0.key == key }).references
    }
    private func setRefs(_ r: [ProvenanceReference], key: String = "chen-ch") throws {
        var p = try XCTUnwrap(try store.load().people.first { $0.key == key })
        p.references = r
        try store.writePerson(p)
    }
    private func judgedRow(_ out: [String: Any]) -> [String: Any] {
        (out["judged"] as? [[String: Any]])?.first ?? [:]
    }

    /// 第 1／4／6 列（HIGH）：已有逐篇判定的配對，另一個 literal 作者位送**不同**理由——作者位歸戶，但回應要說理由沒寫入。
    func testJudgeWithDifferentReasonOnLiteralSlotDisclosesTheUnrecordedReason() throws {
        try work("w1", [.literal("C-H Chen"), .literal("C-H Chen")])
        _ = try service.resolvePeople(apply: nil, judge: ["w1:0:chen-ch=機構一致"])
        let out = json(try service.resolvePeople(apply: nil, judge: ["w1:1:chen-ch=共同作者相同"]))
        XCTAssertNotNil(judgedRow(out)["verdictNotRecorded"], "\(out)")
        XCTAssertEqual(out["personsRewritten"] as? Int, 0, "沒有寫入就不算改寫了 person")
        let authors = try XCTUnwrap(try store.load().entries.first { $0.citekey == "w1" }).authors
        XCTAssertEqual(authors, [.key("chen-ch"), .key("chen-ch")])
        XCTAssertEqual(try refs().filter { $0.field == "resolution-confirmed" }.count, 1)
    }

    /// 同一次呼叫：兩個 literal 作者位、同一人、不同理由——第二個的理由存不進去，要標出來。
    func testTwoSlotsInOneCallWithDifferentReasonsDiscloseTheSecond() throws {
        try work("w1", [.literal("C-H Chen"), .literal("C-H Chen")])
        let out = json(try service.resolvePeople(apply: nil, judge: ["w1:0:chen-ch=機構一致", "w1:1:chen-ch=共同作者相同"]))
        let rows = (out["judged"] as? [[String: Any]]) ?? []
        XCTAssertEqual(rows.filter { $0["verdictNotRecorded"] != nil }.count, 1, "\(out)")
    }

    /// 同一句理由不算沒寫：它已經在。
    func testJudgeWithSameReasonOnLiteralSlotIsNotFlagged() throws {
        try work("w1", [.literal("C-H Chen"), .literal("C-H Chen")])
        _ = try service.resolvePeople(apply: nil, judge: ["w1:0:chen-ch=機構一致"])
        let out = json(try service.resolvePeople(apply: nil, judge: ["w1:1:chen-ch=機構一致"]))
        XCTAssertNil(judgedRow(out)["verdictNotRecorded"], "\(out)")
    }

    /// 第 1／4／6 列（format 18 支）：已有提名層判定、作者位仍是 literal——照常歸戶，回應說明理由因 format 沒寫入。
    func testJudgeOnFormat18WithNominatedVerdictDisclosesTheSuppressedReason() throws {
        try work("w1", [.key("chen-ch"), .literal("C-H Chen")])
        try setRefs([ResolutionLedger.record(.confirmed, holderKind: .work, holder: "w1", literal: "C-H Chen",
                                             rule: ResolutionLedger.personRule, statement: "apply")])
        try StoreVersion.write(root: root, format: 18)
        let out = json(try service.resolvePeople(apply: nil, judge: ["w1:1:chen-ch=機構一致"]))
        let why = judgedRow(out)["verdictNotRecorded"] as? String ?? ""
        XCTAssertTrue(why.contains("19"), "\(out)")
        XCTAssertEqual(try refs().count, 1, "format 18 不寫第二個層級")
    }

    /// 第 7 列：attribute-org 在 format 18 已有提名層判定時，judgement 沒寫入要說出來。
    func testAttributeOrgOnFormat18DisclosesTheUnrecordedJudgement() throws {
        _ = try service.addOrganization(key: "moe", names: ["教育部"], parentKey: nil, note: nil)
        var org = try XCTUnwrap(try store.load().organizations.first { $0.key == "moe" })
        org.references = [ResolutionLedger.record(.confirmed, holderKind: .work, holder: "moe2011", literal: "教育部",
                                                  rule: ResolutionLedger.orgRule, statement: "apply")]
        try store.writeOrganization(org)
        try work("moe2011", [.literal("教育部")])
        try StoreVersion.write(root: root, format: 18)
        let out = json(try service.attributeToOrganizations(["moe2011:0:moe=名字是政府機關，不是人"]))
        let row = (out["attributed"] as? [[String: Any]])?.first ?? [:]
        XCTAssertNotNil(row["verdictNotRecorded"], "\(out)")
    }

    /// 第 2 列：兩個實體、reference 內容完全相同——另一個實體的既有記錄不得被報成本次寫入。
    func testWrittenThisCallIsKeyedByTheJudgedEntity() throws {
        try work("w1", [.literal("C-H Chen")])
        _ = try service.resolvePeople(apply: nil, undecided: ["w1:0:chen-ch-b=查了機構"])
        let out = json(try service.resolvePeople(apply: nil, undecided: ["w1:0:chen-ch=查了機構", "w1:0:chen-ch-b=查了機構"]))
        XCTAssertEqual((out["undecided"] as? [[String: Any]])?.count, 1, "\(out)")
        XCTAssertEqual((out["alreadyRecorded"] as? [Any])?.count, 1, "\(out)")
    }

    private func undecidedState() throws -> String? {
        let o = json(try service.person(key: "chen-ch", name: nil, library: nil))
        let vs = ((o["person"] as? [String: Any])?["verdicts"] as? [[String: Any]]) ?? []
        return vs.first { ($0["kind"] as? String) == "resolution-undecided" }?["state"] as? String
    }
    private func setAuthors(_ ck: String, _ authors: [Author]) throws {
        var e = try XCTUnwrap(try store.load().entries.first { $0.citekey == ck })
        e.authors = authors
        try store.writeEntry(e)
    }

    /// 第 3／8／14 列：「查證歷史」看實際的判定，不看觀測。
    func testHistoryStateFollowsTheDecisionNotObservability() throws {
        try work("w1", [.literal("C-H Chen")])
        _ = try service.resolvePeople(apply: nil, undecided: ["w1:0:chen-ch=查了機構"])
        XCTAssertEqual(try undecidedState(), "observed")
        // literal 被改掉、沒有任何判定：觀測不到，但不是查證歷史
        try setAuthors("w1", [.literal("Someone Else")])
        XCTAssertEqual(try undecidedState(), "stale")
        // reject 之後 literal 仍在：觀測得到，而已判定
        try setAuthors("w1", [.literal("C-H Chen")])
        var r = try refs()
        r.append(ResolutionLedger.record(.rejected, holderKind: .work, holder: "w1", literal: "C-H Chen",
                                         rule: ResolutionLedger.personRule, statement: "否決"))
        try setRefs(r)
        XCTAssertEqual(try undecidedState(), "history")
    }

    /// 第 18 列：提名理由的血統排序——exact 與 judged 並存時回 exact（序列化順序無關）。
    func testConfirmedPairingsPrefersExactOverJudgedRegardlessOfOrder() throws {
        let exact = ResolutionLedger.record(.confirmed, holderKind: .work, holder: "w1", literal: "C-H Chen",
                                            rule: ResolutionLedger.personRule, statement: "apply")
        let judged = ResolutionLedger.record(.confirmed, holderKind: .work, holder: "w1", literal: "C-H Chen",
                                             rule: ResolutionLedger.judgedRule, statement: "機構一致")
        for order in [[exact, judged], [judged, exact]] {
            var p = Person(key: "chen-ch", names: ["C-H Chen"])
            p.references = order
            let rules = Array(ResolutionLedger.confirmedPairings(people: [p]).values)
            XCTAssertEqual(rules, [ResolutionLedger.personRule], "\(order.map(\.value))")
        }
    }
    /// R3 verify 第 1／4 列：同一次呼叫、兩個位置、同配對、理由不同的 refute——第二筆具名略過，不列在 refuted。
    func testRefuteCollisionInOneCallIsSkippedAndNamed() throws {
        try work("w1", [.literal("C-H Chen"), .literal("C-H Chen")])
        let out = json(try service.resolvePeople(apply: nil, refute: ["w1:0:chen-ch=機構不同", "w1:1:chen-ch=共同作者不同"]))
        let refuted = (out["refuted"] as? [[String: Any]]) ?? []
        let skipped = (out["skipped"] as? [[String: Any]]) ?? []
        XCTAssertEqual(refuted.count, 1, "\(out)")
        XCTAssertEqual(skipped.count, 1, "\(out)")
        XCTAssertFalse(refuted.contains { $0["verdictNotRecorded"] != nil }, "refute 不動作者位，不該說「作者位已歸戶」")
    }

    /// R3 verify 第 10 列：attribute-org 在 format 18 碰到同層級、理由不同的判定——原因要說是理由不同，不是提名層。
    func testAttributeOrgNamesTheActualCollisionCause() throws {
        _ = try service.addOrganization(key: "moe", names: ["教育部"], parentKey: nil, note: nil)
        try work("moe2011", [.literal("教育部"), .literal("教育部")])
        _ = try service.attributeToOrganizations(["moe2011:0:moe=政府機關"])
        try StoreVersion.write(root: root, format: 18)
        let out = json(try service.attributeToOrganizations(["moe2011:1:moe=出版者欄寫教育部"]))
        let why = ((out["attributed"] as? [[String: Any]])?.first?["verdictNotRecorded"] as? String) ?? ""
        XCTAssertTrue(why.contains("理由不同"), "\(out)")
    }
}

