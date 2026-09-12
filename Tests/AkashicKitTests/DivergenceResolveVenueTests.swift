import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// venue 的攣生合併（#553）。
///
/// 在此之前 `resolveDivergence` 的 `byShape` 白名單不收 venue，於是**已經發生過的**
/// 重複（實測 live store 5 組／11 筆，見 `LooseTitleKey` 檔頭）沒有任何合併路徑——
/// person 有 `resolve-divergence`、work 有，venue 沒有。
///
/// fixture 用 **American Statistician 那組的真實形狀**：`ISSN 0003-1305` 只在
/// `the-american-statistician` 那一筆，而另一筆的 `authorized` 是 WoS 全大寫形。
/// 這一組同時逼出兩個相反的裁決——ISSN 不對稱**要擋**、authorized 不對稱**只要說**
/// ——所以它是本檔的主 fixture 而不是隨手挑的例子。
final class DivergenceResolveVenueTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-divv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        GitFixture.initRepo(root)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// 倖存者帶 ISSN、被併者不帶；被併者的 `authorized` 是倖存者沒有的全大寫形。
    @discardableResult
    private func seed(keeperType: VenueType = .periodical,
                      doomedType: VenueType = .periodical) throws -> Divergence {
        var keeper = Venue(key: "the-american-statistician", type: keeperType,
                           names: Timeline([TemporalValue(value: "The American Statistician")]),
                           authorized: ["The American Statistician"],
                           issn: [XCTUnwrap_ISSN("0003-1305")])
        keeper.references = [verdict(holder: "casella1985introduction",
                                     literal: "The American Statistician")]
        try store.writeVenue(keeper)

        var doomed = Venue(key: "american-statistician", type: doomedType,
                           names: Timeline([TemporalValue(value: "AMERICAN STATISTICIAN")]),
                           authorized: ["AMERICAN STATISTICIAN"])
        doomed.references = [verdict(holder: "shih2025a", literal: "AMERICAN STATISTICIAN")]
        try store.writeVenue(doomed)

        var work = Entry(id: UUID(), citekey: "shih2025a", type: .periodicalArticle,
                         title: "A note", authors: [.literal("Shih, J.")], date: "2025")
        work.venues = [.key("american-statistician")]
        try store.writeEntry(work)

        let d = Divergence(
            id: UUID(), question: "同一本刊嗎",
            candidates: [DivergenceCandidate(key: "the-american-statistician", shape: .venue),
                         DivergenceCandidate(key: "american-statistician", shape: .venue)])
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        return d
    }

    /// venue 側的 verdict：holder 是**持有刊名 literal 的 work**（`VerdictHolderKind`
    /// 沒有 venue——實測 live store 8,670 條全部是 `work:` 前綴）。
    private func verdict(holder: String, literal: String) -> ProvenanceReference {
        ProvenanceReference(
            field: "resolution-confirmed",
            value: ProvenanceReference.VerdictPairingValue(
                holderKind: .work, holder: holder, literal: literal).encoded,
            kind: .judgement(statement: "resolve apply：alias 完全命中", restsOn: []))
    }

    private func XCTUnwrap_ISSN(_ s: String) -> ISSN {
        guard let i = ISSN(s) else { preconditionFailure("fixture 的 ISSN 寫錯了：\(s)") }
        return i
    }

    // MARK: - 合併本身

    /// 被併者的寫法要**保留成 variant**，`Entry.venues` 要改指倖存者，被併檔要消失。
    ///
    /// 名字不保留的話，下次 `resolve-venues` 遇到 `AMERICAN STATISTICIAN` 會再分割
    /// 一次——`OrgBootstrap`／`PersonBootstrap` 的同一教訓。
    func testMergesNamesIntoVariantAndRepointsEntryVenues() throws {
        let d = try seed()
        let report = try store.resolveDivergence(id: d.id, survivor: "the-american-statistician")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))

        let load = try store.load()
        let keys = load.venues.map(\.key)
        XCTAssertEqual(keys, ["the-american-statistician"], "被併的 venue 檔沒有被刪：\(keys)")

        let v = try XCTUnwrap(load.venues.first)
        XCTAssertTrue(v.names.entries.map(\.value).contains("AMERICAN STATISTICIAN"),
                      "被併者的寫法沒有保留進 names：\(v.names.entries.map(\.value))")
        XCTAssertEqual(v.variant, ["AMERICAN STATISTICIAN"],
                       "被併者的寫法要落在 variant（不是 authorized）：\(v.variant)")
        XCTAssertEqual(v.authorized, ["The American Statistician"],
                       "倖存者的對外形不得被聯集改變：\(v.authorized)")
        XCTAssertEqual(v.issn.map(\.raw), ["0003-1305"], "ISSN 不得在合併中消失")

        let e = try XCTUnwrap(load.entries.first { $0.citekey == "shih2025a" })
        XCTAssertEqual(e.venues, [.key("the-american-statistician")],
                       "work 的 venue 邊沒有改指倖存者：\(e.venues)")
    }

    /// 被併者的 verdict 要搬到倖存者身上——判定史不隨檔案消失（#271 同型）。
    func testVerdictReferencesMigrateToTheKeeper() throws {
        let d = try seed()
        let report = try store.resolveDivergence(id: d.id, survivor: "the-american-statistician")
        XCTAssertEqual(report.verdictReferencesMigrated,
                       ["work:shih2025a :: AMERICAN STATISTICIAN"])
        let v = try XCTUnwrap(try store.load().venues.first)
        let values = Set(v.references.compactMap(\.value))
        XCTAssertTrue(values.contains("work:shih2025a :: AMERICAN STATISTICIAN"),
                      "被併者的 verdict 沒有搬過來：\(values)")
        XCTAssertTrue(values.contains("work:casella1985introduction :: The American Statistician"),
                      "倖存者原有的 verdict 不得被覆蓋：\(values)")
    }

    // MARK: - 拒絕條件

    /// **挑錯倖存者要被擋**：ISSN 只在其中一筆，合併會讓它隨檔案消失。
    /// 識別碼是 `identity-is-judged-not-matched` 的明文例外，丟掉它是實質損失。
    func testRefusesWhenTheDoomedVenueCarriesAnISSNTheKeeperLacks() throws {
        let d = try seed()
        XCTAssertThrowsError(
            try store.resolveDivergence(id: d.id, survivor: "american-statistician")
        ) { err in
            guard case DivergenceResolveError.wouldLoseFields(_, _, let losses) = err else {
                return XCTFail("預期 wouldLoseFields，實際：\(err)")
            }
            XCTAssertTrue(losses.contains { $0.contains("0003-1305") },
                          "拒絕訊息沒有指名將失去的 ISSN：\(losses)")
        }
    }

    /// `type` 不一致要擋（#324）：`VenueType` 決定哪些欄位存在，跨 type 合併不是
    /// 丟一個欄位，是把整組欄位需求換掉——那必須有人裁決。
    func testRefusesWhenTypesDiffer() throws {
        let d = try seed(keeperType: .periodical, doomedType: .database)
        XCTAssertThrowsError(
            try store.resolveDivergence(id: d.id, survivor: "the-american-statistician")
        ) { err in
            guard case DivergenceResolveError.wouldLoseFields(_, _, let losses) = err else {
                return XCTFail("預期 wouldLoseFields，實際：\(err)")
            }
            XCTAssertTrue(losses.contains { $0.contains("type") }, "沒有指名 type：\(losses)")
        }
    }

    // MARK: - 記錄面（#553 的另一半）

    /// **`record-divergence` 收得下 venue 候選。**
    ///
    /// 這條是負控逼出來的：其餘測試用 `writeDivergence` 直接落檔，繞過了
    /// `recordDivergence` 的 `byShape` 白名單——把 `.venue` 從那張表拿掉，
    /// 它們**全部維持綠**。而 `byShape` 正是 #553 的另一半：記不下來的話，
    /// 合併管線再完整也沒有記錄可以餵給它。
    func testRecordDivergenceAcceptsVenueCandidates() throws {
        try seed()
        let d = try store.recordDivergence(
            question: "同一本刊嗎",
            candidates: [(key: "the-american-statistician", shape: .venue),
                         (key: "american-statistician", shape: .venue)],
            judgement: nil, restsOn: [])
        XCTAssertEqual(d.candidates.map(\.key).sorted(),
                       ["american-statistician", "the-american-statistician"])
        XCTAssertTrue(d.candidates.allSatisfy { $0.shape == .venue })
    }

    /// 不存在的 venue key 仍要被擋——白名單放行的是「這個 shape 可以指涉」，
    /// 不是「任何字串都收」。
    func testRecordDivergenceStillRejectsAnUnknownVenueKey() throws {
        try seed()
        XCTAssertThrowsError(try store.recordDivergence(
            question: "同一本刊嗎",
            candidates: [(key: "the-american-statistician", shape: .venue),
                         (key: "no-such-journal", shape: .venue)],
            judgement: nil, restsOn: []))
    }

    // MARK: - 版控可回溯性閘（#558）

    /// **被併的 venue 檔 untracked → 拒絕，且檔案仍在。**
    ///
    /// #553 加了 venue 的合併路徑，但 `doomedRelativePaths` 的 switch 對 `.venue`
    /// 仍是 `continue`（註解寫「上游已擋」——那對 venue 自 #553 起是假的）。實測：
    /// 一個從未進 git 的 venue 記錄被直接刪除、零警告。person／work 的 doomed 檔會過
    /// tracked+clean 檢查，venue 的不會——#73 的紀律在這一格失效。
    ///
    /// 與 `DivergenceResolveTests.testRefusesWhenDoomedFilesAreUncommitted`（person）
    /// 同型，差別是 untracked 的是**被併實體**而非 divergence 記錄——#553 開發時撞到的
    /// 是後者，於是誤以為閘對 venue 是完整的。
    func testRefusesWhenDoomedVenueIsUntracked() throws {
        // keeper 先 commit；doomed **不** commit → untracked
        let keeper = Venue(key: "keeper-journal", type: .periodical,
                           names: Timeline([TemporalValue(value: "Keeper Journal")]),
                           authorized: ["Keeper Journal"])
        try store.writeVenue(keeper)
        GitFixture.commitAll(root, message: "keeper only")

        let doomed = Venue(key: "doomed-journal", type: .periodical,
                           names: Timeline([TemporalValue(value: "Doomed Journal")]),
                           authorized: ["Doomed Journal"])
        try store.writeVenue(doomed)
        let d = Divergence(
            id: UUID(), question: "同一本嗎",
            candidates: [DivergenceCandidate(key: "keeper-journal", shape: .venue),
                         DivergenceCandidate(key: "doomed-journal", shape: .venue)])
        try store.writeDivergence(d)
        // 只 commit divergence 記錄——讓 untracked 的是**被併實體**，不是記錄
        GitFixture.commit(root, paths: ["entities/\(d.id.uuidString).yaml"], message: "div only")

        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "keeper-journal"),
                             "untracked 的 doomed venue 刪掉後 git 取不回，必須拒絕") { err in
            guard case DivergenceResolveError.deletionNotRecoverable(let files) = err else {
                return XCTFail("應為 deletionNotRecoverable，實得 \(err)")
            }
            XCTAssertTrue(files.contains { $0.path.contains(doomed.id.uuidString) },
                          "訊息必須指名被併的 venue 檔：\(files)")
        }
        let after = try store.load()
        XCTAssertEqual(after.venues.count, 2, "拒絕後被併的 venue 檔必須仍在")
        XCTAssertEqual(after.divergences.count, 1)
    }

    // MARK: - unsupportedShape 的訊息不得手寫值域

    /// **這條是 doc-sync sweep 抓出來的**（#553 close 時）。
    ///
    /// `unsupportedShape` 的訊息原本逐字寫「本版的消歧只處理 person 與 work」，
    /// 而 #553 把 venue 加進支援值域之後**沒有任何東西報錯**——那句話今天唯一
    /// 觸發得到的是 organization，所以它是一句對著使用者說的假話。而 README 還
    /// 逐字引用著它。
    ///
    /// 訊息改成從 `mergeableShapes` 生成，本條釘住那份清單與**實際分支**一致：
    /// 清單裡的 shape 不得擲 `unsupportedShape`，清單外的必須擲。
    func testUnsupportedShapeMessageNamesTheRealDomain() throws {
        // venue 在清單裡 → 不得擲 unsupportedShape（它走得完整條管線）
        XCTAssertTrue(DivergenceResolveError.mergeableShapes.contains("venue"),
                      "venue 已經接得住了，清單卻沒有它")
        let d = try seed()
        XCTAssertNoThrow(try store.resolveDivergence(id: d.id, survivor: "the-american-statistician"))

        // organization 不在清單裡 → 必須擲，且訊息要說出**真的**支援哪些
        var a = Organization(key: "org-a")
        a.names = Timeline([TemporalValue(value: "Org A")])
        var b = Organization(key: "org-b")
        b.names = Timeline([TemporalValue(value: "Org B")])
        try store.writeOrganization(a)
        try store.writeOrganization(b)
        let od = Divergence(id: UUID(), question: "同一個機構嗎",
                            candidates: [DivergenceCandidate(key: "org-a", shape: .organization),
                                         DivergenceCandidate(key: "org-b", shape: .organization)])
        try store.writeDivergence(od)
        GitFixture.commitAll(root, message: "orgs")

        XCTAssertThrowsError(try store.resolveDivergence(id: od.id, survivor: "org-a")) { err in
            guard case DivergenceResolveError.unsupportedShape = err else {
                return XCTFail("預期 unsupportedShape，實際：\(err)")
            }
            // `"\(err)"` 給的是 enum 的 debug 形（`unsupportedShape("organization")`），
            // 不是使用者看到的那句話——測試第一版就是這樣寫的，然後它抓到了自己。
            let msg = (err as? LocalizedError)?.errorDescription ?? "\(err)"
            XCTAssertFalse(msg.contains("只處理 person 與 work"),
                           "訊息手寫了值域，而值域已經變了：\(msg)")
            for shape in DivergenceResolveError.mergeableShapes {
                XCTAssertTrue(msg.contains(shape), "訊息沒說出支援的 \(shape)：\(msg)")
            }
        }
    }

    // MARK: - authorized 降級：說，但不擋

    /// **本輪的裁決釘子**：被併者的 `authorized` 不是拒絕條件。
    ///
    /// person 側對同一形狀是**拒絕**（#81：「哪個名字對外」是判定）。venue 不是：
    /// 實測 479/479 筆的 `authorized` 恰好等於 `[names[0]]`，唯一的寫入者是
    /// `VenueBootstrap` 的建檔慣例。把 bootstrap 副產品當承重判定，會讓這個工具
    /// 對它要解決的 5 組重複**全部無用**——而那 5 組正是它的立案理由。
    func testDemotedAuthorizedIsAWarningNotARefusal() throws {
        let d = try seed()
        let report = try store.resolveDivergence(id: d.id, survivor: "the-american-statistician")
        XCTAssertFalse(report.hasFailures, "authorized 不對稱不得擋下合併")
        XCTAssertTrue(report.warnings.contains { $0.contains("AMERICAN STATISTICIAN")
                                                 && $0.contains("成為") && $0.contains("variant") },
                      "降級沒有被說出來（seed 的形狀是 becomesVariant，要說「成為」）：\(report.warnings)")
    }

    /// **dry-run 不得對降級沉默。**
    ///
    /// 降級是單向的（#554 之前沒有改回 authorized 的面；之後有面但不留 judgement，
    /// 合併端仍分不出判定與機械值——#564），而 dry-run 正是「還能反悔的
    /// 時點」。這個檔案為同一形狀付過兩次代價（#139 F1：拒絕條件只在實跑算，
    /// dry-run 對最高頻的 `wouldLoseFields` 完全沉默）——提醒與拒絕同一條紀律。
    func testDryRunAnnouncesTheDemotionToo() throws {
        let d = try seed()
        let preview = try store.previewResolveDivergence(
            id: d.id, survivor: "the-american-statistician", overrideReason: nil)
        XCTAssertTrue(preview.warnings.contains { $0.contains("AMERICAN STATISTICIAN")
                                                  && $0.contains("成為") && $0.contains("variant") },
                      "dry-run 沒有預告降級：\(preview.warnings)")
    }

    /// preview 與實跑對**同一個**降級要說**同一句話**——兩份描述會分岔
    /// （`no-compat-fallback` §「同一件事只能有一份描述」）。這條釘住它們共用
    /// `validateVenuePreconditions` 這個計算點，而不是各自算一次。
    func testPreviewAndActualReportTheSameWarnings() throws {
        let d = try seed()
        let preview = try store.previewResolveDivergence(
            id: d.id, survivor: "the-american-statistician", overrideReason: nil)
        let actual = try store.resolveDivergence(id: d.id, survivor: "the-american-statistician")
        XCTAssertEqual(preview.warnings, actual.warnings,
                       "preview 與實跑的提醒不一致——它們沒有共用同一個計算點")
    }

    /// **D1 之後的常態**（R2 verify 第 2 列，DA 席實測）：被併者的 authorized 若已在倖存者的
    /// `names`（未標——被 `--authorize` 換下來的舊指定），合併路徑的 `known` 濾除會讓它**留在
    /// 未標、不進 variant**。R2 之前提醒句拿被併者 authorized 對 `keeper.authorized` 比、卻對
    /// 合併結果說「成為 variant」——預告了一個沒發生的分類改變；而句尾建議「用 `--authorize`
    /// 改回」照做會把人手工指定的正式刊名移出。提醒要說真的結果，且不給會覆蓋指定的建議。
    func testDemotedNameAlreadyInKeeperNamesIsAnnouncedAsUnclassifiedNotVariant() throws {
        var keeper = Venue(key: "the-american-statistician", type: .periodical,
                           names: Timeline([TemporalValue(value: "The American Statistician"),
                                            TemporalValue(value: "AMERICAN STATISTICIAN")]),
                           authorized: ["The American Statistician"])     // 大寫形：未標
        keeper.references = [verdict(holder: "casella1985introduction",
                                     literal: "The American Statistician")]
        try store.writeVenue(keeper)
        var doomed = Venue(key: "american-statistician", type: .periodical,
                           names: Timeline([TemporalValue(value: "AMERICAN STATISTICIAN")]),
                           authorized: ["AMERICAN STATISTICIAN"])
        doomed.references = [verdict(holder: "shih2025a", literal: "AMERICAN STATISTICIAN")]
        try store.writeVenue(doomed)
        var work = Entry(id: UUID(), citekey: "shih2025a", type: .periodicalArticle,
                         title: "A note", authors: [.literal("Shih, J.")], date: "2025")
        work.venues = [.key("american-statistician")]
        try store.writeEntry(work)
        let d = Divergence(id: UUID(), question: "同一本刊嗎",
                           candidates: [DivergenceCandidate(key: "the-american-statistician", shape: .venue),
                                        DivergenceCandidate(key: "american-statistician", shape: .venue)])
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")

        let report = try store.resolveDivergence(id: d.id, survivor: "the-american-statistician")
        let line = try XCTUnwrap(report.warnings.first { $0.contains("AMERICAN STATISTICIAN") },
                                 "降級沒有被說出來：\(report.warnings)")
        XCTAssertTrue(line.contains("未標"), "要說真的結果（留在 names、未標）：\(line)")
        XCTAssertFalse(line.contains("成為") && line.contains("variant"), "不得預告一個沒發生的分類改變：\(line)")
        XCTAssertFalse(line.contains("改回"), "不得建議一個會覆蓋人工指定的動作：\(line)")
        let v = try XCTUnwrap(LibraryStore(root: root).load().venues.first { $0.key == "the-american-statistician" })
        XCTAssertEqual(v.variant, [], "已在 names 的名字留未標，不進 variant")
        XCTAssertEqual(v.authorized, ["The American Statistician"])
    }

    /// 第三種結果（R3 verify 第 13 列：零測試）：被併者的 authorized 已在倖存者的 **variant**——
    /// 合併不改分類，提醒要說「仍是…variant」而不是「成為」。
    func testDemotedNameAlreadyInKeeperVariantIsAnnouncedAsAlreadyVariant() throws {
        var keeper = Venue(key: "the-american-statistician", type: .periodical,
                           names: Timeline([TemporalValue(value: "The American Statistician"),
                                            TemporalValue(value: "AMERICAN STATISTICIAN")]),
                           authorized: ["The American Statistician"])
        keeper.variant = ["AMERICAN STATISTICIAN"]
        keeper.references = [verdict(holder: "casella1985introduction", literal: "The American Statistician")]
        try store.writeVenue(keeper)
        var doomed = Venue(key: "american-statistician", type: .periodical,
                           names: Timeline([TemporalValue(value: "AMERICAN STATISTICIAN")]),
                           authorized: ["AMERICAN STATISTICIAN"])
        doomed.references = [verdict(holder: "shih2025a", literal: "AMERICAN STATISTICIAN")]
        try store.writeVenue(doomed)
        var work = Entry(id: UUID(), citekey: "shih2025a", type: .periodicalArticle,
                         title: "A note", authors: [.literal("Shih, J.")], date: "2025")
        work.venues = [.key("american-statistician")]
        try store.writeEntry(work)
        let d = Divergence(id: UUID(), question: "同一本刊嗎",
                           candidates: [DivergenceCandidate(key: "the-american-statistician", shape: .venue),
                                        DivergenceCandidate(key: "american-statistician", shape: .venue)])
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")

        let report = try store.resolveDivergence(id: d.id, survivor: "the-american-statistician")
        let line = try XCTUnwrap(report.warnings.first { $0.contains("AMERICAN STATISTICIAN") })
        XCTAssertTrue(line.contains("仍是") && line.contains("variant"), line)
        XCTAssertFalse(line.contains("成為"), line)
        let v = try XCTUnwrap(LibraryStore(root: root).load().venues.first { $0.key == "the-american-statistician" })
        XCTAssertEqual(v.variant, ["AMERICAN STATISTICIAN"])
    }

    /// **被併者的髒名字若 canonical 等於倖存者已有的名字，根本不會搬進倖存者——不必為此拒絕**（R7 verify 第 13 列）：
    /// `mergedVenueKeeper` 先以 canonical 對倖存者 `names` 濾除；`"AMERICAN STATISTICIAN "` 對倖存者已有的
    /// `"AMERICAN STATISTICIAN"` 會被濾掉，合併結果合法，而 R7 仍要求操作者去修一筆下一步就刪掉的檔。
    func testDoomedDirtNameThatWouldBeFilteredOutDoesNotBlockTheMerge() throws {
        var keeper = Venue(key: "the-american-statistician", type: .periodical,
                           names: Timeline([TemporalValue(value: "The American Statistician"),
                                            TemporalValue(value: "AMERICAN STATISTICIAN")]),
                           authorized: ["The American Statistician"])
        keeper.variant = ["AMERICAN STATISTICIAN"]
        try store.writeVenue(keeper)
        let doomed = Venue(key: "american-statistician", type: .periodical,
                           names: Timeline([TemporalValue(value: "AMERICAN STATISTICIAN")]),
                           authorized: ["AMERICAN STATISTICIAN"])
        try store.writeVenue(doomed)
        let file = root.appendingPathComponent("entities/\(doomed.id.uuidString).yaml")
        try String(contentsOf: file, encoding: .utf8)
            .replacingOccurrences(of: "- value: AMERICAN STATISTICIAN\n", with: "- value: 'AMERICAN STATISTICIAN '\n")
            .write(to: file, atomically: true, encoding: .utf8)
        let d = Divergence(id: UUID(), question: "同一本刊嗎",
                           candidates: [DivergenceCandidate(key: "the-american-statistician", shape: .venue),
                                        DivergenceCandidate(key: "american-statistician", shape: .venue)])
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        let report = try store.resolveDivergence(id: d.id, survivor: "the-american-statistician")
        XCTAssertFalse(report.hasFailures, "\(report.failures)")
        let v = try XCTUnwrap(LibraryStore(root: root).load().venues.first { $0.key == "the-american-statistician" })
        XCTAssertEqual(v.names.entries.map(\.value), ["The American Statistician", "AMERICAN STATISTICIAN"])
    }

    /// **dry-run 對預測的 keeper 跑寫入閘**（#554 R5 verify 第 10 列）：被併者若是舊 binary 寫的髒記錄
    /// （尾隨空白的名字——D8 之後是 error），合併會把它併進倖存者的 names／variant，`--apply` 在
    /// `keeperWrite` 才拒（乾淨、無撕裂）——但 `--dry-run` 說 OK。本檔自己的 #139 F1：dry-run 是
    /// 「還能反悔的時點」，拒絕條件只在實跑算就是假的 dry-run。preview 與實跑共用同一個 keeper 計算點。
    func testDryRunRefusesWhenThePredictedKeeperWouldNotBeWritable() throws {
        let d = try seed()
        let doomed = try XCTUnwrap(store.load().venues.first { $0.key == "american-statistician" })
        let file = root.appendingPathComponent("entities/\(doomed.id.uuidString).yaml")
        let dirty = try String(contentsOf: file, encoding: .utf8)
            .replacingOccurrences(of: "- value: AMERICAN STATISTICIAN\n", with: "- value: 'AMERICAN STATISTICIAN '\n")
        try dirty.write(to: file, atomically: true, encoding: .utf8)
        GitFixture.commitAll(root, message: "dirty")
        XCTAssertTrue(try store.load().venues.first { $0.key == "american-statistician" }!
                        .names.entries.contains { $0.value == "AMERICAN STATISTICIAN " }, "fixture")
        // 訊息要指向**被併者**（R6 verify 第 28 列）：那個字串只存在於 doomed 的 YAML，R6 的訊息說
        // 「venue 'the-american-statistician' 的 names…請在 YAML 裡改」——倖存者的檔裡根本沒有這一筆。
        XCTAssertThrowsError(try store.previewResolveDivergence(
            id: d.id, survivor: "the-american-statistician", overrideReason: nil)) { err in
            let s = (err as? LocalizedError)?.errorDescription ?? String(describing: err)
            XCTAssertTrue(s.contains("AMERICAN STATISTICIAN "), s)
            XCTAssertTrue(s.contains("american-statistician") && s.contains("被併"), s)
            XCTAssertFalse(s.contains("'the-american-statistician' 的 names"), s)
        }
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "the-american-statistician"))
        let after = try store.load()
        XCTAssertEqual(after.venues.count, 2, "零寫入：被併者還在")
        XCTAssertEqual(after.entries.first?.venues, [.key("american-statistician")])
    }
}
