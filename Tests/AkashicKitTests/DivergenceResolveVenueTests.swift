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
                                                 && $0.contains("variant") },
                      "降級沒有被說出來：\(report.warnings)")
    }

    /// **dry-run 不得對降級沉默。**
    ///
    /// 降級是單向的（venue 沒有改回 authorized 的面），而 dry-run 正是「還能反悔的
    /// 時點」。這個檔案為同一形狀付過兩次代價（#139 F1：拒絕條件只在實跑算，
    /// dry-run 對最高頻的 `wouldLoseFields` 完全沉默）——提醒與拒絕同一條紀律。
    func testDryRunAnnouncesTheDemotionToo() throws {
        let d = try seed()
        let preview = try store.previewResolveDivergence(
            id: d.id, survivor: "the-american-statistician", overrideReason: nil)
        XCTAssertTrue(preview.warnings.contains { $0.contains("AMERICAN STATISTICIAN")
                                                  && $0.contains("variant") },
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
}
