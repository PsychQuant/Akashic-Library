import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #75 對二：work 消歧的欄位遺失比對——與 person 側 fieldsLostByMerging 對齊。
///
/// 病：work 消歧只搬「別人指向被併者」的參照，被併者**自己**帶的 fields／
/// attachments／tags／libraries／出向 relations／provenance 隨檔案消失而使用者
/// 只看到「✓ 併入」。同 person 鐵律：被併者帶有倖存者沒有的內容 → **拒絕並指名**
/// 將失去什麼（搬欄位是人的判斷，不自動合併）。
final class WorkMergeFieldsTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-wmf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        GitFixture.initRepo(root)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// 兩筆 work（同一篇的兩種匯入）+ 一筆 work 歧異記錄。
    private func seed(keeper: Entry, doomed: Entry) throws -> Divergence {
        try store.writeEntry(keeper)
        try store.writeEntry(doomed)
        let d = Divergence(
            id: UUID(), question: "是否同一篇",
            candidates: [DivergenceCandidate(key: keeper.citekey, shape: .work),
                         DivergenceCandidate(key: doomed.citekey, shape: .work)])
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        return d
    }

    private func work(_ citekey: String) -> Entry {
        Entry(id: UUID(), citekey: citekey, type: "article", title: "T")
    }

    func testRefusesWhenDoomedHasFieldKeeperLacks() throws {
        var keeper = work("a2020")
        var doomed = work("a2020dup")
        doomed.fields["doi"] = "10.1/xyz"   // keeper 沒有
        let d = try seed(keeper: keeper, doomed: doomed)
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "a2020")) { error in
            guard case DivergenceResolveError.wouldLoseFields(_, _, let losses) = error else {
                return XCTFail("預期 wouldLoseFields，實得 \(error)")
            }
            XCTAssertTrue(losses.contains { $0.contains("doi") }, "\(losses)")
        }
    }

    func testRefusesWhenDoomedHasAttachmentsTagsLibraries() throws {
        for (label, mutate) in [
            ("attachments", { (e: inout Entry) in
                e.attachments = [AttachmentRef(kind: .pool, path: "x.pdf")] }),
            ("tags", { (e: inout Entry) in e.akashic.tags = ["unread"] }),
            ("libraries", { (e: inout Entry) in e.akashic.libraries = ["sinica"] }),
        ] {
            let r = FileManager.default.temporaryDirectory
                .appendingPathComponent("akashic-wmf2-\(UUID().uuidString)")
            try FileManager.default.createDirectory(
                at: r.appendingPathComponent("entities"), withIntermediateDirectories: true)
            try StoreVersion.write(root: r, format: StoreVersion.supported)
            GitFixture.initRepo(r)
            defer { try? FileManager.default.removeItem(at: r) }
            let s = LibraryStore(root: r)
            let keeper = work("b2020")
            var doomed = work("b2020dup")
            mutate(&doomed)
            try s.writeEntry(keeper); try s.writeEntry(doomed)
            let d = Divergence(id: UUID(), question: "?",
                candidates: [DivergenceCandidate(key: "b2020", shape: .work),
                             DivergenceCandidate(key: "b2020dup", shape: .work)])
            try s.writeDivergence(d)
            GitFixture.commitAll(r, message: "seed")
            XCTAssertThrowsError(try s.resolveDivergence(id: d.id, survivor: "b2020"),
                                 "\(label) 遺失必須拒絕") { error in
                guard case DivergenceResolveError.wouldLoseFields(_, _, let losses) = error else {
                    return XCTFail("\(label): 預期 wouldLoseFields，實得 \(error)")
                }
                XCTAssertTrue(losses.contains { $0.contains(label) }, "\(label): \(losses)")
            }
        }
    }

    /// **出向 relations**：被併者自己 cites 的東西，keeper 沒 cite → 遺失。
    /// （resolveWorkDivergence 的遷移迴圈跳過 doomed，所以 doomed 的出向不會搬。）
    func testRefusesWhenDoomedCitesSomethingKeeperDoesNot() throws {
        var keeper = work("c2020")
        var doomed = work("c2020dup")
        doomed.akashic.relations.cites = ["olsson1979"]   // keeper 沒 cite
        let d = try seed(keeper: keeper, doomed: doomed)
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "c2020")) { error in
            guard case DivergenceResolveError.wouldLoseFields(_, _, let losses) = error else {
                return XCTFail("預期 wouldLoseFields，實得 \(error)")
            }
            XCTAssertTrue(losses.contains { $0.contains("cites") || $0.contains("olsson1979") },
                          "出向 relations 遺失必須指名：\(losses)")
        }
    }

    /// 子集放行：doomed 的欄位是 keeper 的子集（或相同）→ 正常消歧。
    func testAllowsWhenDoomedIsSubset() throws {
        var keeper = work("d2020")
        keeper.fields["doi"] = "10.1/xyz"
        keeper.akashic.tags = ["a", "b"]
        var doomed = work("d2020dup")
        doomed.fields["doi"] = "10.1/xyz"   // 相同
        doomed.akashic.tags = ["a"]          // 子集
        let d = try seed(keeper: keeper, doomed: doomed)
        let report = try store.resolveDivergence(id: d.id, survivor: "d2020")
        XCTAssertEqual(report.failures, [])
        XCTAssertEqual(report.merged, ["d2020dup"])
    }

    /// provenance.zoteroKey 不同 → 衝突，拒絕（兩個不同的 Zotero 來源是反證）。
    func testRefusesWhenDoomedHasDifferentZoteroKey() throws {
        var keeper = work("e2020")
        keeper.provenance = Provenance(zoteroKey: "AAA", zoteroVersion: 1)
        var doomed = work("e2020dup")
        doomed.provenance = Provenance(zoteroKey: "BBB", zoteroVersion: 1)
        let d = try seed(keeper: keeper, doomed: doomed)
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "e2020")) { error in
            guard case DivergenceResolveError.wouldLoseFields(_, _, let losses) = error else {
                return XCTFail("預期 wouldLoseFields，實得 \(error)")
            }
            XCTAssertTrue(losses.contains { $0.contains("zotero") }, "\(losses)")
        }
    }

    /// #139 F1 的教訓：preview 與實跑擲同樣的 wouldLoseFields（dry-run 不得沉默）。
    func testPreviewRejectsWorkFieldLossSameAsActual() throws {
        let keeper = work("f2020")
        var doomed = work("f2020dup")
        doomed.fields["doi"] = "10.1/xyz"
        let d = try seed(keeper: keeper, doomed: doomed)
        for run in [{ try self.store.previewResolveDivergence(id: d.id, survivor: "f2020") },
                    { try self.store.resolveDivergence(id: d.id, survivor: "f2020") }] {
            XCTAssertThrowsError(try run()) { error in
                guard case DivergenceResolveError.wouldLoseFields = error else {
                    return XCTFail("preview 與實跑須同拒絕，實得 \(error)")
                }
            }
        }
    }
}
