import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #564 b36 Y1 的兩則合併修正（b37 N1）：
///
/// - 第 12 列：同樣兩份歷史，只換被併者的 key 拼法，結論就從放行翻成拒絕——被併者依 key 排序後最後接上的那一筆決定尾端。被併者自己就
///   不一致時現在一律拒絕，結論與 key 拼法無關。
/// - 第 11 列：venue variant「不在 variant 卻以指定結尾」的出口「要它是異寫就 --add-variant 它」只在被併者上做走不通（兩邊分類不同，合併改以
///   「分類不同」拒絕）；出口改成兩邊都做——照出口做完，合併通過。
final class NameClassificationMergeB37Tests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-ncm37-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        GitFixture.initRepo(root)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func record(_ field: String, _ name: String, _ action: NameClassificationRecord.Action, _ reason: String) -> ProvenanceReference {
        NameClassificationRecord.make(field: field, name: name, action: action, reason: reason, restsOn: [])
    }
    private func person(_ key: String, authorized: [String], refs: [ProvenanceReference] = []) -> Person {
        var p = Person(key: key, names: PersonNames(authorized: authorized, variant: []))
        p.references = refs
        return p
    }
    private func venue(_ key: String, names: [String], authorized: [String] = [], variant: [String] = [],
                       refs: [ProvenanceReference] = []) -> Venue {
        var v = Venue(key: key, type: .periodical, names: Timeline(names.map { TemporalValue(value: $0) }), authorized: authorized)
        v.variant = variant
        v.references = refs
        return v
    }
    private func message(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? "\(e)" }

    // MARK: - 第 12 列

    /// DA 的重現：倖存者「指定 R」；一筆被併者自己不一致（「撤回：手改」卻仍是對外形），另一筆「確認：C」。不一致那一筆叫 d1 或 d9，
    /// 結論都是拒絕、說出它的 key——b34 叫 d1 時放行（d2 的確認最後接上、蓋住矛盾），叫 d9 時拒絕。
    func testTheVerdictDoesNotDependOnHowTheInconsistentDoomedIsSpelled() {
        let keeper = person("k", authorized: ["Lin, Mei"], refs: [record("authorized", "Lin, Mei", .designate, "R")])
        let ok = person("d2", authorized: ["Lin, Mei"], refs: [record("authorized", "Lin, Mei", .confirm, "C")])
        for bad in ["d1", "d9"] {
            let inconsistent = person(bad, authorized: ["Lin, Mei"], refs: [record("authorized", "Lin, Mei", .withdraw, "手改")])
            let merged = LibraryStore.mergedPersonKeeper(keeper, absorbing: [inconsistent, ok])
            XCTAssertEqual(merged.classificationTailConflicts.compactMap(\.broughtBy), [bad], "叫 \(bad) 時也要拒絕並具名")
        }
        // venue 同一條規則
        let vk = venue("k", names: ["Journal L"], authorized: ["Journal L"], refs: [record("authorized", "Journal L", .designate, "R")])
        let vok = venue("d2", names: ["Journal L"], authorized: ["Journal L"], refs: [record("authorized", "Journal L", .confirm, "C")])
        for bad in ["d1", "d9"] {
            let vbad = venue(bad, names: ["Journal L"], authorized: ["Journal L"], refs: [record("authorized", "Journal L", .withdraw, "手改")])
            XCTAssertEqual(LibraryStore.mergedVenueKeeper(vk, absorbing: [vbad, vok]).classificationTailConflicts.compactMap(\.broughtBy), [bad])
        }
    }

    /// 被併者自己一致時不受影響：倖存者有、被併者也有同一段一致的歷史（攣生），照舊放行、不重搬。
    func testConsistentDoomedHistoriesStillMerge() {
        let history = [record("authorized", "Lin, Mei", .designate, "R"), record("authorized", "Lin, Mei", .confirm, "S")]
        let merged = LibraryStore.mergedPersonKeeper(person("k", authorized: ["Lin, Mei"], refs: history),
                                                     absorbing: [person("d", authorized: ["Lin, Mei"], refs: history)])
        XCTAssertEqual(merged.classificationTailConflicts, [])
        XCTAssertEqual(merged.referencesCarried, [])
    }

    // MARK: - 第 11 列

    /// 被併者 dv 手改出「variant|Some Jrnl|指定」而名字不在 variant：出口要兩邊都 --add-variant。只在被併者上做 → 「分類不同」拒絕；
    /// 兩邊都做 → 合併通過。
    func testTheVariantExitWorksOnlyWhenBothSidesAddTheVariant() throws {
        let keeper = venue("kv", names: ["Some Journal", "Some Jrnl"], authorized: ["Some Journal"])
        let doomed = venue("dv", names: ["Some Journal", "Some Jrnl"], authorized: ["Some Journal"],
                           refs: [record("variant", "Some Jrnl", .designate, "手改")])
        XCTAssertFalse(LibraryStore.mergedVenueKeeper(keeper, absorbing: [doomed]).classificationTailConflicts.isEmpty, "前提：尾端矛盾")
        let exits = LibraryStore.tailConflictExits(LibraryStore.mergedVenueKeeper(keeper, absorbing: [doomed]).classificationTailConflicts,
                                                   kind: "venue")
        XCTAssertTrue(exits.contains { $0.contains("被併者與倖存者兩邊都 --add-variant") }, "\(exits)")

        // 只在被併者上照做（--add-variant 寫 variant 的指定、名字進 variant）
        var doomedOnly = doomed
        doomedOnly.variant = ["Some Jrnl"]
        doomedOnly.references += [record("variant", "Some Jrnl", .designate, "是異寫")]
        try store.writeVenue(keeper)
        try store.writeVenue(doomedOnly)
        let d = Divergence(id: UUID(), question: "同一本刊嗎",
                           candidates: [DivergenceCandidate(key: "kv", shape: .venue), DivergenceCandidate(key: "dv", shape: .venue)])
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "kv", overrideReason: nil)) { e in
            guard case DivergenceResolveError.wouldLoseFields = e else { return XCTFail("只在被併者上做：要是分類不同，實得 \(e)") }
            XCTAssertTrue(message(e).contains("Some Jrnl"), message(e))
        }

        // 倖存者也照做：合併通過，尾端一致
        var keeperToo = keeper   // 同一筆記錄（同一個 id），不是另建一筆同 key 的
        keeperToo.variant = ["Some Jrnl"]
        keeperToo.references = [record("variant", "Some Jrnl", .designate, "是異寫")]
        try store.writeVenue(keeperToo)
        GitFixture.commitAll(root, message: "both sides")
        _ = try store.previewResolveDivergence(id: d.id, survivor: "kv", overrideReason: nil)
        let report = try store.resolveDivergence(id: d.id, survivor: "kv")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        let k = try XCTUnwrap(store.load().venues.first { $0.key == "kv" })
        XCTAssertTrue(LibraryStore.venueTailConflicts(k).isEmpty)
    }
}
