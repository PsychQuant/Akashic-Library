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
        for run in [{ try self.store.previewResolveDivergence(id: d.id, survivor: "f2020", overrideReason: nil) },
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

    /// date 的**精度差異**不算衝突——`2020` vs `2020-03-15` 是重複記錄的正常形狀
    /// （#71 R2 DA 的同型誤拒教訓）。
    ///
    /// **舊契約「只比在場與否」已被 157-8 推翻**（那個說法過度矯正，`2019` vs
    /// `2021` 會靜默通過）。本測試的兩條斷言在新的前綴相容語意下仍成立，但 doc
    /// 曾把舊契約留在檔案裡、就在 157-8 的回歸測試上方——下一個讀者會照 doc 把
    /// 行為「改回去」。#157 verify 157-20。
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

    // MARK: - #157 R2 的三個回歸（席位真 binary 實測皆會靜默丟資料）

    /// **157-6**：keeper 的空字串日期不得遮蔽被併者的真實日期。
    ///
    /// YAML `date: ""` decode 成 `Optional("")` 且不 quarantine，於是 `keeper.date == nil`
    /// 為假 → 閘不報 → 席位真 binary 實測 `2020-03-15` 永久消失。專案內明文慣例：
    /// 「空值視同缺席……同一個概念不該有兩套判準」（`LibraryStore.swift:997`）。
    func testEmptyKeeperDateDoesNotMaskDoomedDate() {
        var keeper = Entry(id: UUID(), citekey: "k2020", type: "article", title: "T")
        keeper.date = ""
        var doomed = Entry(id: UUID(), citekey: "d2020", type: "article", title: "T")
        doomed.date = "2020-03-15"
        let losses = LibraryStore.fieldsLostByMerging(doomed, into: keeper)
        XCTAssertTrue(losses.contains { $0.contains("2020-03-15") },
                      "空字串要視同缺席，否則日期靜默消失：\(losses)")
        // **訊息也要對**：空值＝缺席，不是「互斥」。少了 isEmpty 折疊時這條仍會
        // 回報（空字串落進不相容分支），但會說「與倖存者的  互斥」——把「倖存者
        // 沒有這個欄位」講成「兩邊的值衝突」，人會去找一個不存在的衝突。
        // 沒有這條斷言，`isEmpty` 的處理就是可被靜默移除的死碼（mutation 實測）。
        XCTAssertFalse(losses.contains { $0.contains("無法機械判定") },
                       "空值是缺席不是衝突，訊息不得說判不出關係：\(losses)")

        // **對稱的另一半**（#157 verify 157-13）：先前只釘住 keeper 側，doomed 側的
        // 折疊 mutation 是**存活**的（966 全綠）。doomed 空、keeper 有真值時不得
        // 報任何 date 遺失——那是「被併者沒帶」，不是衝突。
        var k2 = Entry(id: UUID(), citekey: "k2", type: "article", title: "T")
        k2.date = "2020"
        var d2 = Entry(id: UUID(), citekey: "d2", type: "article", title: "T")
        d2.date = ""
        XCTAssertFalse(LibraryStore.fieldsLostByMerging(d2, into: k2)
            .contains { $0.hasPrefix("date") },
            "doomed 側空值同樣視同缺席")
    }

    /// **157-8**：互斥年份是衝突，不是精度差異。
    ///
    /// 「只比在場與否」是對「`2020` vs `2020-03-15` 會誤拒」的**過度**矯正——那只
    /// 證成前綴相容的放行。person 側結構相同的 `died` 對同一組輸入會報，理由是
    /// 不同日期「是對『這兩筆是不是同一個』的反證，或至少是必須有人裁決的來源衝突」。
    func testMutuallyExclusiveDatesAreReportedButPrecisionIsNot() {
        func losses(keeper k: String, doomed d: String) -> [String] {
            var keeper = Entry(id: UUID(), citekey: "k", type: "article", title: "T")
            keeper.date = k
            var doomed = Entry(id: UUID(), citekey: "d", type: "article", title: "T")
            doomed.date = d
            return LibraryStore.fieldsLostByMerging(doomed, into: keeper)
        }
        XCTAssertFalse(losses(keeper: "2020", doomed: "2020-03-15").contains { $0.hasPrefix("date") },
                       "精度差異是重複記錄的正常形狀，不得誤拒")
        XCTAssertFalse(losses(keeper: "2020-03-15", doomed: "2020").contains { $0.hasPrefix("date") },
                       "反向同理")
        XCTAssertTrue(losses(keeper: "2019", doomed: "2021").contains { $0.hasPrefix("date") },
                      "互斥年份必須報")
        XCTAssertTrue(losses(keeper: "2020-03", doomed: "2020-07").contains { $0.hasPrefix("date") },
                      "同年不同月同樣互斥")
        // 前綴必須落在分隔點上——202 與 2020 是不同年份，不得當成精度差異
        XCTAssertTrue(losses(keeper: "202", doomed: "2020").contains { $0.hasPrefix("date") },
                      "202 不是 2020 的精度較低版本")
    }

    /// **157-7**：同名未知欄位但內容不同＝衝突（三分不是二分）。
    ///
    /// 第一版只比 key 在不在，於是「兩邊都有 `peer_review_status` 但值不同」整條
    /// 漏掉——席位真 binary 實測 doomed 的值被 keeper 靜默覆蓋，而 `validate` 兩行
    /// 都印過「未知欄位（已保留）」。系統已經知道兩邊都有，合併閘卻不看值。
    /// person 版（`:816-826`）早就是三分的，這是「宣稱對稱但沒真的對稱」。
    func testSameUnknownFieldKeyWithDifferentValueIsAConflict() {
        func make(_ raw: String) -> Entry {
            var e = Entry(id: UUID(), citekey: "x", type: "article", title: "T")
            e.unknownFields = [UnknownField(key: "peer_review_status", raw: raw)]
            e.akashic.unknownFields = [UnknownField(key: "cohort", raw: raw)]
            return e
        }
        let same = LibraryStore.fieldsLostByMerging(
            make("peer_review_status: pending\n"), into: make("peer_review_status: pending\n"))
        XCTAssertTrue(same.isEmpty, "兩邊同值＝不會失去：\(same)")

        let diff = LibraryStore.fieldsLostByMerging(
            make("peer_review_status: accepted\n"), into: make("peer_review_status: pending\n"))
        XCTAssertEqual(diff.count, 2, "頂層與 akashic 兩處都要報：\(diff)")
        XCTAssertTrue(diff.allSatisfy { $0.contains("內容不同") },
                      "訊息要說出是衝突而非缺席：\(diff)")
    }

    // MARK: - #157 R3 的四個回歸

    /// **157-12**：「空值＝缺席」是**規則**不是 date 的特例。席位實測 `fields` 兩個
    /// 方向都錯，而且真 binary 在一則訊息裡吐兩句假話。
    func testEmptyValuesAreAbsentForFieldsToo() {
        func losses(keeper kv: String?, doomed dv: String?) -> [String] {
            var keeper = Entry(id: UUID(), citekey: "k", type: "article", title: "T")
            if let kv { keeper.fields["doi"] = kv }
            var doomed = Entry(id: UUID(), citekey: "d", type: "article", title: "T")
            if let dv { doomed.fields["doi"] = dv }
            return LibraryStore.fieldsLostByMerging(doomed, into: keeper)
        }
        XCTAssertTrue(losses(keeper: nil, doomed: "").isEmpty,
                      "doomed 的空值＝缺席，不該報成遺失（spurious refusal）")
        let masked = losses(keeper: "", doomed: "10.1234/real")
        XCTAssertTrue(masked.contains { $0.contains("10.1234/real") },
                      "keeper 的空值不得遮蔽 doomed 的真值：\(masked)")
        XCTAssertFalse(masked.contains { $0.contains("兩邊都有") },
                       "keeper 那邊是缺席——「兩邊都有」是假話：\(masked)")
        XCTAssertTrue(losses(keeper: "10.1/x", doomed: "10.1/x").isEmpty, "同值不算失去")
        XCTAssertTrue(losses(keeper: "10.1/x", doomed: "10.2/y")
            .contains { $0.contains("兩邊都有") }, "真的兩邊都有且不同 → 衝突")
    }

    /// **157-12(c)**：`provenance.libraryID` 的 `nil` 是「pre-Phase-2 未記錄」不是
    /// 「不同 library」——`Provenance` 自己的 doc 就這麼寫。而且那個方向什麼都不會
    /// 失去（倖存者已有較完整的值），卻擋下合併且「搬到倖存者身上」無物可搬。
    func testAbsentLibraryIDIsNotAConflict() {
        func losses(keeperLib: Int?, doomedLib: Int?) -> [String] {
            var keeper = Entry(id: UUID(), citekey: "k", type: "article", title: "T")
            keeper.provenance = Provenance(zoteroKey: "ABCD", zoteroVersion: 1,
                                           libraryID: keeperLib)
            var doomed = Entry(id: UUID(), citekey: "d", type: "article", title: "T")
            doomed.provenance = Provenance(zoteroKey: "ABCD", zoteroVersion: 1,
                                           libraryID: doomedLib)
            return LibraryStore.fieldsLostByMerging(doomed, into: keeper)
        }
        XCTAssertTrue(losses(keeperLib: 1, doomedLib: nil).isEmpty,
                      "被併者未記錄 → 什麼都不會失去，不得擋")
        XCTAssertTrue(losses(keeperLib: nil, doomedLib: 1)
            .contains { $0.contains("library") }, "反方向照報（被併者有、倖存者無）")
        XCTAssertTrue(losses(keeperLib: 1, doomedLib: 2)
            .contains { $0.contains("library") }, "兩邊都有且不同 → 衝突")
    }

    /// **157-18**：attachments 要指名。「先把要保留的搬到倖存者身上」對「1 筆」
    /// 不可執行。
    func testAttachmentLossNamesTheFile() {
        let keeper = Entry(id: UUID(), citekey: "k", type: "article", title: "T")
        var doomed = Entry(id: UUID(), citekey: "d", type: "article", title: "T")
        doomed.attachments = [AttachmentRef(kind: .pool, path: "supplementary-appendix.pdf")]
        let losses = LibraryStore.fieldsLostByMerging(doomed, into: keeper)
        XCTAssertTrue(losses.contains { $0.contains("supplementary-appendix.pdf") },
                      "要說出是哪個檔，否則指示不可執行：\(losses)")
    }

    /// **157-19**：同一組作者但順序不同 → 需人裁決。work 的作者順序帶語意
    /// （`Person.names` 的 doc 明寫順序不帶語意，`Entry.authors` 沒有對應聲明）。
    func testAuthorOrderDifferenceIsReported() {
        var keeper = Entry(id: UUID(), citekey: "k", type: "article", title: "T")
        keeper.authors = [.literal("A"), .literal("B")]
        var doomed = Entry(id: UUID(), citekey: "d", type: "article", title: "T")
        doomed.authors = [.literal("B"), .literal("A")]
        XCTAssertTrue(LibraryStore.fieldsLostByMerging(doomed, into: keeper)
            .contains { $0.contains("順序") }, "同集合不同序要報")
        // 完全相同 → 不報
        doomed.authors = [.literal("A"), .literal("B")]
        XCTAssertTrue(LibraryStore.fieldsLostByMerging(doomed, into: keeper).isEmpty)
    }

    // MARK: - #157 最終裁決的兩項

    /// **157-21**：157-19 的修法自己帶進來的誤拒。`Set(…) == keeperAuthors` 擋得住
    /// 集合差異，擋不住**重數**差異——keeper 帶既存重複時，doomed 的真子集會被報成
    /// 「順序不同」，而順序沒有不同、且什麼都不會失去。
    ///
    /// 可達性不是理論的：keeper 帶既存重複是本 repo **明文保護**的狀態
    ///（`testUnrelatedRecordWithDuplicateAuthorsLeftAlone`：「消歧不是清理工具」）。
    func testDuplicateAuthorsInKeeperAreNotReportedAsOrderDifference() {
        func l(keeper ka: [Author], doomed da: [Author]) -> [String] {
            var keeper = Entry(id: UUID(), citekey: "k", type: "article", title: "T")
            keeper.authors = ka
            var doomed = Entry(id: UUID(), citekey: "d", type: "article", title: "T")
            doomed.authors = da
            return LibraryStore.fieldsLostByMerging(doomed, into: keeper)
        }
        XCTAssertTrue(l(keeper: [.key("a"), .key("a")], doomed: [.key("a")]).isEmpty,
                      "keeper 既存重複、doomed 是子集——什麼都不會失去")
        XCTAssertFalse(l(keeper: [.key("a"), .key("b")], doomed: [.key("b"), .key("a")]).isEmpty,
                       "同集合反序仍要報——不得為了修上一條把 157-19 關掉")
    }

    /// **157-22**：本函式唯一的 **fail-open**——keeper 空標題靜默吞掉被併者的唯一標題。
    ///
    /// 排除 `type`/`title` 的理由是「keeper 的寫法就是人選的 canonical form」，
    /// 而 `""` 不是任何人選的 form、它是缺席。`validate` 已經印過「⚠ title 為空」，
    /// 系統早就知道，合併閘卻不看——與 157-7 的結構同構。
    func testEmptyKeeperTitleDoesNotSwallowDoomedTitle() {
        func losses(keeperTitle kt: String, doomedTitle dt: String) -> [String] {
            let keeper = Entry(id: UUID(), citekey: "k", type: "article", title: kt)
            let doomed = Entry(id: UUID(), citekey: "d", type: "article", title: dt)
            return LibraryStore.fieldsLostByMerging(doomed, into: keeper)
        }
        XCTAssertTrue(losses(keeperTitle: "", doomedTitle: "The Only Real Title")
            .contains { $0.contains("The Only Real Title") },
            "keeper 空標題不得吞掉被併者的唯一標題")
        XCTAssertTrue(losses(keeperTitle: "Short", doomedTitle: "Short: A Longer Subtitle").isEmpty,
                      "兩邊都非空的 title 差異仍**刻意不擋**（#71 R2 DA 的誤拒教訓）")
        // type 同一格
        var k = Entry(id: UUID(), citekey: "k", type: "", title: "T")
        k.type = ""
        let d = Entry(id: UUID(), citekey: "d", type: "article", title: "T")
        XCTAssertTrue(LibraryStore.fieldsLostByMerging(d, into: k)
            .contains { $0.hasPrefix("type:") }, "type 的空值同理")
    }
}
