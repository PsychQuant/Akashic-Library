import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #605：work 合併時的 Zotero 來源。不同來源（不同 library 或不同 key）不再是反證——
/// 同一性由 divergence 記錄上的人工判定決定，Zotero key 只是來源紀錄。合併後倖存者
/// 帶著兩邊的來源：主來源保留（缺則升格），其餘併入附加來源、同來源去重。
final class WorkMergeProvenanceTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-wmp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        GitFixture.initRepo(root)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func work(_ citekey: String, _ prov: Provenance?) -> Entry {
        var e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: "T")
        e.provenance = prov
        return e
    }

    private func merge(_ entries: [Entry], survivor: String) throws -> Entry {
        for e in entries { try store.writeEntry(e) }
        let d = Divergence(id: UUID(), question: "是否同一篇",
                           candidates: entries.map { DivergenceCandidate(key: $0.citekey, shape: .work) })
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        _ = try store.resolveDivergence(id: d.id, survivor: survivor)
        return try XCTUnwrap(store.load().entries.first { $0.citekey == survivor })
    }

    func testDifferentLibrarySourcesMergeAndDoomedBecomesAdditional() throws {
        let keeper = work("cheng2021likert", Provenance(zoteroKey: "WDDP9QMR", zoteroVersion: 1, libraryID: 1))
        let doomed = work("cheng2021blikert", Provenance(zoteroKey: "QFAFGFW5", zoteroVersion: 2, libraryID: 2))
        let after = try merge([keeper, doomed], survivor: "cheng2021likert")
        XCTAssertEqual(after.provenance?.zoteroKey, "WDDP9QMR", "倖存者主來源保留")
        XCTAssertEqual(after.additionalProvenance.map(\.zoteroKey), ["QFAFGFW5"])
        XCTAssertEqual(after.additionalProvenance.first?.libraryID, 2)
    }

    func testDoomedPrimaryPromotedWhenKeeperHasNone() throws {
        let keeper = work("a2020", nil)
        let doomed = work("a2020dup", Provenance(zoteroKey: "K2", zoteroVersion: 1, libraryID: 2))
        let after = try merge([keeper, doomed], survivor: "a2020")
        XCTAssertEqual(after.provenance?.zoteroKey, "K2", "倖存者無主來源 → 被併者主來源升格")
        XCTAssertTrue(after.additionalProvenance.isEmpty)
    }

    func testSameSourceIsDeduplicated() throws {
        let src = Provenance(zoteroKey: "K1", zoteroVersion: 1, libraryID: 1)
        let keeper = work("b2020", src)
        var doomed = work("b2020dup", src)
        doomed.additionalProvenance = [Provenance(zoteroKey: "K2", zoteroVersion: 1, libraryID: 2)]
        let after = try merge([keeper, doomed], survivor: "b2020")
        XCTAssertEqual(after.provenance?.zoteroKey, "K1")
        XCTAssertEqual(after.additionalProvenance.map(\.zoteroKey), ["K2"], "同來源不重複、被併者的附加來源一併帶過來")
    }

    func testDoomedPrimaryMatchingKeeperAdditionalIsNotDuplicated() throws {
        var keeper = work("c2020", Provenance(zoteroKey: "K1", zoteroVersion: 1, libraryID: 1))
        keeper.additionalProvenance = [Provenance(zoteroKey: "K2", zoteroVersion: 1, libraryID: 2)]
        let doomed = work("c2020dup", Provenance(zoteroKey: "K2", zoteroVersion: 1, libraryID: 2))
        let after = try merge([keeper, doomed], survivor: "c2020")
        XCTAssertEqual(after.additionalProvenance.map(\.zoteroKey), ["K2"])
    }

    func testThreeWayMergeKeepsEverySourceOnce() throws {
        let keeper = work("d2020", Provenance(zoteroKey: "K1", zoteroVersion: 1, libraryID: 1))
        let d1 = work("d2020b", Provenance(zoteroKey: "K2", zoteroVersion: 1, libraryID: 2))
        let d2 = work("d2020c", Provenance(zoteroKey: "K3", zoteroVersion: 1, libraryID: 5))
        let after = try merge([keeper, d1, d2], survivor: "d2020")
        XCTAssertEqual(Set(after.additionalProvenance.map(\.zoteroKey)), ["K2", "K3"])
        XCTAssertEqual(after.additionalProvenance.count, 2)
    }

    func testSameSourceOrphanedOnDoomedStillBlocks() throws {
        let keeper = work("e2020", Provenance(zoteroKey: "K1", zoteroVersion: 1, libraryID: 1))
        let doomed = work("e2020dup", Provenance(zoteroKey: "K1", zoteroVersion: 1, libraryID: 1,
                                                  orphanedAt: Date(timeIntervalSince1970: 1_790_000_000)))
        for e in [keeper, doomed] { try store.writeEntry(e) }
        let d = Divergence(id: UUID(), question: "?", candidates: [
            DivergenceCandidate(key: "e2020", shape: .work), DivergenceCandidate(key: "e2020dup", shape: .work)])
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "e2020")) { error in
            guard case DivergenceResolveError.wouldLoseFields(_, _, let losses) = error else {
                return XCTFail("預期 wouldLoseFields，實得 \(error)")
            }
            XCTAssertTrue(losses.contains { $0.contains("orphaned") }, "\(losses)")
        }
    }
}
