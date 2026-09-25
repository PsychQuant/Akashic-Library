import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicEntity
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// change `resolution-verdict-states` R1 verify 的修正，逐項釘住（標題是 verify 報告的列）。
final class ResolutionVerdictStatesR1Tests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-rvs-r1-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try "sources/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
        var p = Person(key: "chen-ch", names: ["C-H Chen"])
        p.names = PersonNames(authorized: ["C-H Chen"], variant: [])
        try store.writePerson(p)
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
    private func authors(_ ck: String) throws -> [Author] {
        try XCTUnwrap(try store.load().entries.first { $0.citekey == ck }).authors
    }
    private func setRefs(_ r: [ProvenanceReference], key: String = "chen-ch") throws {
        var p = try XCTUnwrap(try store.load().people.first { $0.key == key })
        p.references = r
        try store.writePerson(p)
    }

    /// 第 1 列（HIGH）：已有逐篇判定的配對，另一個仍是 literal 的作者位送同一句判定——要歸戶，不是 alreadyJudged。
    func testJudgeOnLiteralSlotWithExistingJudgedVerdictStillAssignsTheSlot() throws {
        try work("w1", [.literal("C-H Chen"), .literal("C-H Chen")])
        _ = try service.resolvePeople(apply: nil, judge: ["w1:0:chen-ch=機構一致"])
        let out = json(try service.resolvePeople(apply: nil, judge: ["w1:1:chen-ch=機構一致"]))
        XCTAssertEqual((out["alreadyJudged"] as? [Any])?.count ?? 0, 0, "\(out)")
        XCTAssertEqual(try authors("w1"), [.key("chen-ch"), .key("chen-ch")], "第二個作者位要被歸戶")
        XCTAssertEqual(try refs().filter { $0.field == "resolution-confirmed" }.count, 1, "verdict 以記錄鍵去重")
    }

    /// 第 3 列：同一筆 work 兩個作者位同一 literal 同一人——一個配對，一筆未決只計一次。
    func testUndecidedCountIsPerPairingNotPerRow() throws {
        try work("w1", [.literal("C-H Chen"), .literal("C-H Chen")])
        _ = try service.resolvePeople(apply: nil, undecided: ["w1:0:chen-ch=查了機構"])
        let list = json(try service.resolvePeople(apply: nil))
        XCTAssertEqual(list["undecidedTotal"] as? Int, 1, "\(list)")
        XCTAssertEqual(list["pendingTotal"] as? Int, 0, "\(list)")
    }

    /// 第 5 列：spec「MCP per-id apply writes a checked pairing」。
    func testPerIdApplyWritesACheckedPairingAndKeepsTheUndecidedRecord() throws {
        try work("w1", [.literal("C-H Chen")])
        _ = try service.resolvePeople(apply: nil, undecided: ["w1:0:chen-ch=查了機構"])
        _ = try service.resolvePeople(apply: ["w1:0:chen-ch"])
        XCTAssertEqual(try authors("w1"), [.key("chen-ch")])
        XCTAssertEqual(Set(try refs().map(\.field)), ["resolution-undecided", "resolution-confirmed"])
    }

    /// 第 11 列（DA）：同一人對同一 work 持有只差位元組的兩個 confirmed 拼法（work 攣生合併的產物）——judge 不得「不猜」地卡死。
    func testRecoveredLiteralsDedupeByNormalizedKey() throws {
        try work("w1", [.key("chen-ch")])
        try setRefs([
            ResolutionLedger.record(.confirmed, holderKind: .work, holder: "w1", literal: "C.-H.  Chen",
                                    rule: ResolutionLedger.personRule, statement: "apply"),
            ResolutionLedger.record(.confirmed, holderKind: .work, holder: "w1", literal: "C.-H. Chen",
                                    rule: ResolutionLedger.judgedRule, statement: "機構一致"),
        ])
        let out = json(try service.resolvePeople(apply: nil, judge: ["w1:0:chen-ch=機構一致"]))
        let why = ((out["skipped"] as? [[String: Any]])?.first?["why"] as? String) ?? ""
        XCTAssertFalse(why.contains("不猜"), "只差位元組的拼法是同一個配對：\(out)")
    }

    /// 第 12 列：目的鍵上已有未決記錄時 rename 具名拒絕（D60 涵蓋三值）。
    func testRenameRefusesWhenTheDestinationAlreadyHoldsAnUndecidedRecord() throws {
        try work("w1", [.literal("C-H Chen")])
        try setRefs([ResolutionLedger.record(undecided: .work, holder: "w2", literal: "C-H Chen",
                                             statement: "舊的查證", restsOn: [])])
        GitFixture.commitAll(root)
        XCTAssertThrowsError(try store.renameEntry(from: "w1", to: "w2"))
    }

    /// 第 21 列：同一次呼叫兩個 id 寫下同一筆未決記錄（記錄不帶位置）——第二個是這次寫的，不是「已在」。
    func testSecondIdentialUndecidedInOneCallIsReportedAsRecorded() throws {
        try work("w1", [.literal("C-H Chen"), .literal("C-H Chen")])
        let out = json(try service.resolvePeople(apply: nil, undecided: ["w1:0:chen-ch=查了機構", "w1:1:chen-ch=查了機構"]))
        XCTAssertEqual((out["undecided"] as? [[String: Any]])?.count, 2, "\(out)")
        XCTAssertEqual((out["alreadyRecorded"] as? [Any])?.count ?? 0, 0)
        XCTAssertEqual(try refs().count, 1)
    }

    /// 第 25 列：format 18 上，已有逐篇判定的配對再 apply 另一個作者位——照常歸戶、不造出兩層級並存、不在 entry 寫入後才失敗。
    func testApplyOnFormat18DoesNotCreateCoexistence() throws {
        try work("w1", [.key("chen-ch"), .literal("C-H Chen")])
        try setRefs([ResolutionLedger.record(.confirmed, holderKind: .work, holder: "w1", literal: "C-H Chen",
                                             rule: ResolutionLedger.judgedRule, statement: "機構一致")])
        try StoreVersion.write(root: root, format: 18)
        let out = json(try service.resolvePeople(apply: ["w1:1:chen-ch"]))
        XCTAssertNil(out["confirmWriteFailed"], "\(out)")
        XCTAssertEqual(try authors("w1"), [.key("chen-ch"), .key("chen-ch")])
        XCTAssertEqual(try refs().count, 1, "format 18 不寫第二個層級")
    }

    /// 第 6 列（b）：person 合併的 dry-run 跑與實跑同一道 keeper 閘——format 18 上兩層級並存時 dry-run 就要拒。
    func testPersonMergePreviewRunsTheKeeperGate() throws {
        try work("w1", [.literal("C-H Chen")])
        try setRefs([ResolutionLedger.record(.confirmed, holderKind: .work, holder: "w1", literal: "C-H Chen",
                                             rule: ResolutionLedger.personRule, statement: "apply")])
        var q = Person(key: "chen-ch-2", names: ["Chen C-H"])
        q.references = [ResolutionLedger.record(.confirmed, holderKind: .work, holder: "w1", literal: "C-H Chen",
                                                rule: ResolutionLedger.judgedRule, statement: "機構一致")]
        try store.writePerson(q)
        let d = Divergence(id: UUID(), question: "同一人？",
                           candidates: [DivergenceCandidate(key: "chen-ch", shape: .person),
                                        DivergenceCandidate(key: "chen-ch-2", shape: .person)])
        _ = try store.writeDivergence(d)
        try StoreVersion.write(root: root, format: 18)
        GitFixture.commitAll(root)
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "chen-ch", overrideReason: nil))
    }

    /// 第 7 列：未決腿有界——超過上限整批拒絕、零寫入。
    func testUndecidedLegIsBounded() throws {
        try work("w1", [.literal("C-H Chen")])
        let many = (0..<21).map { "sha256:" + String(format: "%064x", $0) }
        XCTAssertThrowsError(try service.resolvePeople(apply: nil, undecided: ["w1:0:chen-ch=x"], restsOn: many))
        let long = String(repeating: "查", count: 2_000)   // 6,000 位元組
        XCTAssertThrowsError(try service.resolvePeople(apply: nil, undecided: ["w1:0:chen-ch=\(long)"]))
        XCTAssertTrue(try refs().isEmpty)
    }
}
