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
        let keeper = work("a2020")
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
        let keeper = work("c2020")
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
    // MARK: - #157 verify 157-1／157-2 的 regression

    /// **最強的一項**：tolerant-preserve 的未知欄位（較新 binary 寫入、本版不認識）
    /// ——本 binary 依定義無法判斷它重不重要，唯一安全的預設是拒絕。
    func testRefusesWhenDoomedHasUnknownFields() throws {
        let keeper = work("g2020")
        var doomed = work("g2020dup")
        doomed.unknownFields = [UnknownField(key: "future_field", raw: "future_field: 42")]
        let d = try seed(keeper: keeper, doomed: doomed)
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "g2020")) { error in
            guard case DivergenceResolveError.wouldLoseFields(_, _, let losses) = error else {
                return XCTFail("預期 wouldLoseFields，實得 \(error)")
            }
            XCTAssertTrue(losses.contains { $0.contains("future_field") }, "\(losses)")
        }
    }

    /// authors：doomed 的 `.key(...)` 是 resolve-people 歸戶的產物——work 合併不搬，
    /// 丟掉的是人做過的判斷。
    func testRefusesWhenDoomedHasResolvedAuthorsKeeperLacks() throws {
        let keeper = work("h2020")
        var doomed = work("h2020dup")
        doomed.authors = [.key("chen-ming")]
        let d = try seed(keeper: keeper, doomed: doomed)
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "h2020")) { error in
            guard case DivergenceResolveError.wouldLoseFields(_, _, let losses) = error else {
                return XCTFail("預期 wouldLoseFields，實得 \(error)")
            }
            XCTAssertTrue(losses.contains { $0.contains("chen-ming") },
                          "已歸戶的作者不得靜默消失：\(losses)")
        }
    }

    /// date **只比在場與否、不比精度**——`2020` vs `2020-03-15` 是重複記錄的正常
    /// 形狀（#71 R2 DA 的同型誤拒教訓）。
    func testDateComparesPresenceNotPrecision() throws {
        // (a) doomed 有、keeper 沒有 → 拒
        var k1 = work("i2020"); k1.date = nil
        var d1 = work("i2020dup"); d1.date = "2020-03-15"
        let div1 = try seed(keeper: k1, doomed: d1)
        XCTAssertThrowsError(try store.resolveDivergence(id: div1.id, survivor: "i2020"))

        // (b) 兩邊都有但精度不同 → **放行**（不是衝突）
        let r2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-wmf-date-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: r2.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: r2, format: StoreVersion.supported)
        GitFixture.initRepo(r2)
        defer { try? FileManager.default.removeItem(at: r2) }
        let s2 = LibraryStore(root: r2)
        var k2 = work("j2020"); k2.date = "2020"
        var d2 = work("j2020dup"); d2.date = "2020-03-15"
        try s2.writeEntry(k2); try s2.writeEntry(d2)
        let div2 = Divergence(id: UUID(), question: "?",
            candidates: [DivergenceCandidate(key: "j2020", shape: .work),
                         DivergenceCandidate(key: "j2020dup", shape: .work)])
        try s2.writeDivergence(div2)
        GitFixture.commitAll(r2, message: "seed")
        let report = try s2.resolveDivergence(id: div2.id, survivor: "j2020")
        XCTAssertEqual(report.failures, [], "精度差異不是衝突——不得誤拒")
    }

    /// #157 verify 157-2：Zotero 記錄的身分是 (libraryID, zoteroKey) 這個**對**。
    func testRefusesWhenSameZoteroKeyDifferentLibrary() throws {
        var keeper = work("k2020")
        keeper.provenance = Provenance(zoteroKey: "ABCD", zoteroVersion: 1, libraryID: 1)
        var doomed = work("k2020dup")
        doomed.provenance = Provenance(zoteroKey: "ABCD", zoteroVersion: 1, libraryID: 77)
        let d = try seed(keeper: keeper, doomed: doomed)
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "k2020")) { error in
            guard case DivergenceResolveError.wouldLoseFields(_, _, let losses) = error else {
                return XCTFail("預期 wouldLoseFields，實得 \(error)")
            }
            XCTAssertTrue(losses.contains { $0.contains("library") }, "\(losses)")
        }
    }

    /// type/title 是**刻意排除**——同一篇的兩筆記錄 title 本來就會不同，keeper 的
    /// 寫法就是人選的 canonical form（要求相等會重演 #71 R2 DA 的誤拒）。
    func testTypeAndTitleDifferencesDoNotBlock() throws {
        var keeper = work("l2020"); keeper.title = "Short"
        var doomed = work("l2020dup")
        doomed.title = "Short: A Much Longer Subtitle"
        doomed.type = "misc"
        let d = try seed(keeper: keeper, doomed: doomed)
        let report = try store.resolveDivergence(id: d.id, survivor: "l2020")
        XCTAssertEqual(report.failures, [], "type/title 差異刻意不擋")
        XCTAssertEqual(report.merged, ["l2020dup"])
    }

}
