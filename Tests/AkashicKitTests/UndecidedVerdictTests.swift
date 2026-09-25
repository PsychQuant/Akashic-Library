import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicEntity
@testable import AkashicStoreIO

/// change `resolution-verdict-states`（#619）：未決記錄的 store 層與 ledger 層。
/// 寫入面（resolve-people／resolve-venues 的 undecided 腿）的測試在 `AkashicMCPTests`。
final class UndecidedVerdictTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!
    private let digest = "sha256:" + String(repeating: "b", count: 64)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-undecided-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func undecided(_ literal: String = "C.-H. Chen", statement: String = "查了論文機構欄只寫 Taipei",
                           restsOn: [String] = []) -> ProvenanceReference {
        ResolutionLedger.record(undecided: .work, holder: "chen2020a", literal: literal,
                                statement: statement, restsOn: restsOn)
    }
    private func decision(_ kind: ResolutionLedger.VerdictKind, rule: String = ResolutionLedger.personRule)
        -> ProvenanceReference {
        ResolutionLedger.record(kind, holderKind: .work, holder: "chen2020a", literal: "C.-H. Chen",
                                rule: rule, statement: "s")
    }
    private func person(_ refs: [ProvenanceReference]) -> Person {
        var p = Person(key: "chen-ch", names: ["Chen, C.-H."])
        p.references = refs
        return p
    }

    // MARK: - 封閉三值與產生器

    func testVerdictFieldsAreAClosedTriple() {
        XCTAssertEqual(ProvenanceReference.resolutionVerdictFields,
                       ["resolution-confirmed", "resolution-rejected", "resolution-undecided"])
        XCTAssertEqual(Set(ResolutionLedger.VerdictKind.allCases.map(\.rawValue)),
                       ProvenanceReference.resolutionVerdictFields, "enum 與欄位集合同一份值域")
    }

    func testRecordUndecidedCarriesTailAndRestsOn() {
        let r = undecided(restsOn: [digest])
        XCTAssertEqual(r.field, "resolution-undecided")
        XCTAssertEqual(r.value, "work:chen2020a :: C.-H. Chen")
        guard case .judgement(let s, let restsOn) = r.kind else { return XCTFail() }
        XCTAssertEqual(s, "查了論文機構欄只寫 Taipei [rule: checked-undecided]")
        XCTAssertEqual(restsOn, [digest])
        let parsed = ResolutionLedger.verdicts(references: [r]).verdicts
        XCTAssertEqual(parsed.map(\.kind), [.undecided])
        XCTAssertEqual(parsed.first?.restsOn, [digest])
    }

    // MARK: - store 層

    func testUndecidedOnPersonLoadsWithoutQuarantine() throws {
        try store.writePerson(person([undecided(), undecided(restsOn: [digest])]))
        let load = try store.load()
        XCTAssertTrue(load.quarantined.isEmpty, "\(load.quarantined)")
        XCTAssertEqual(load.people.first?.references.count, 2)
    }

    func testUndecidedWithMalformedValueIsRejected() throws {
        var bad = undecided()
        bad.value = "chen2020a C.-H. Chen"
        XCTAssertThrowsError(try store.writePerson(person([bad])))
    }

    func testFormat18RefusesUndecidedAndCoexistingClasses() throws {
        try StoreVersion.write(root: root, format: 18)
        XCTAssertThrowsError(try store.writePerson(person([undecided()]))) { e in
            XCTAssertTrue("\(e)".contains("19"), "\(e)")
        }
        XCTAssertThrowsError(try store.writePerson(person([
            decision(.confirmed), decision(.confirmed, rule: ResolutionLedger.judgedRule)]))) { e in
            XCTAssertTrue("\(e)".contains("19"), "\(e)")
        }
        XCTAssertNoThrow(try store.writePerson(person([decision(.confirmed)])), "單一層級在 18 照寫")
    }

    // MARK: - ledger 層

    func testAppendIfAbsentAccumulatesChecksButNotIdenticalResends() {
        var refs: [ProvenanceReference] = []
        XCTAssertTrue(ResolutionLedger.appendIfAbsent(undecided(), to: &refs))
        XCTAssertTrue(ResolutionLedger.appendIfAbsent(undecided(statement: "查了共同作者"), to: &refs))
        XCTAssertFalse(ResolutionLedger.appendIfAbsent(undecided(statement: "查了共同作者"), to: &refs))
        XCTAssertEqual(refs.count, 2)
    }

    func testSupersedeNeverRetiresUndecidedAndUndecidedRetiresNothing() {
        var refs = [undecided(), decision(.rejected)]
        let r1 = ResolutionLedger.supersede(decision(.confirmed), in: &refs)
        XCTAssertTrue(r1.appended)
        XCTAssertEqual(r1.retired.map(\.field), ["resolution-rejected"])
        XCTAssertTrue(refs.contains { $0.field == "resolution-undecided" }, "未決是查證歷史，不退役")
        let r2 = ResolutionLedger.supersede(undecided(statement: "再查一次"), in: &refs)
        XCTAssertTrue(r2.retired.isEmpty, "寫未決不退役任何判定")
    }

    func testPairingStateDecidedBeatsUndecided() {
        // 鍵是正規化配對（R1 verify：與寫入端的 verdictPairingKey 同一把正規化）
        let p = ResolutionLedger.statePairing(
            ResolutionPairing(holderKind: .work, holder: "chen2020a", literal: "C.-H. Chen", judgedKey: "chen-ch"))
        XCTAssertEqual(ResolutionLedger.pairingStates(references: [undecided(), undecided(statement: "x")],
                                                      judgedKey: "chen-ch")[p]?.state, .undecided)
        XCTAssertEqual(ResolutionLedger.pairingStates(references: [undecided(), undecided(statement: "x")],
                                                      judgedKey: "chen-ch")[p]?.undecidedChecks, 2)
        XCTAssertEqual(ResolutionLedger.pairingStates(references: [undecided(), decision(.confirmed)],
                                                      judgedKey: "chen-ch")[p]?.state, .decided)
        XCTAssertTrue(ResolutionLedger.undecidedChecks(holders: [("chen-ch", [undecided(), decision(.rejected)])]).isEmpty,
                      "已判定的配對不標查過未決")
    }

    /// spec「A checked pairing leaves pending」
    func testCheckedPairingLeavesPending() {
        let p = ResolutionPairing(holderKind: .work, holder: "chen2020a", literal: "C.-H. Chen", judgedKey: "chen-ch")
        let before = ResolutionLedger.counts(people: [person([])], candidates: [(p, ResolutionLedger.personRule)])
        XCTAssertEqual(before[ResolutionLedger.personRule]?.pending, 1)
        XCTAssertEqual(before[ResolutionLedger.personRule]?.undecided, 0)
        let after = ResolutionLedger.counts(people: [person([undecided()])], candidates: [(p, ResolutionLedger.personRule)])
        XCTAssertEqual(after[ResolutionLedger.personRule]?.pending, 0)
        XCTAssertEqual(after[ResolutionLedger.personRule]?.undecided, 1)
        XCTAssertNil(after[ResolutionLedger.undecidedRule], "未決不開 rule 桶")
    }

    func testConfirmedPairingsPrefersJudgedLineage() {
        let p = person([decision(.confirmed, rule: "author-name-initials"),
                        decision(.confirmed, rule: ResolutionLedger.judgedRule)])
        let pairs = ResolutionLedger.confirmedPairings(people: [p])
        XCTAssertEqual(pairs.values.first, ResolutionLedger.judgedRule)
        let reversed = person([decision(.confirmed, rule: ResolutionLedger.judgedRule),
                               decision(.confirmed, rule: "author-name-initials")])
        XCTAssertEqual(ResolutionLedger.confirmedPairings(people: [reversed]).values.first, ResolutionLedger.judgedRule,
                       "與序列化順序無關")
    }
}
