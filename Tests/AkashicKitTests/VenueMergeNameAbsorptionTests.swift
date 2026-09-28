import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// venue 合併怎麼把被併者的名字併進倖存者（#565）。
///
/// #553 的合併把被併者的名字**一律標成 variant**、並以 `TemporalValue(value:)` 重建而丟掉時間欄位。
/// 兩件事都錯：
///
/// 1. #554 D1（使用者 2026-09-12）對 `--authorize` 的降級目標選了**未標**——`venue-entity` spec：
///    「A name in neither is unclassified … it makes no claim either way」。「兩筆是同一本刊」蘊含
///    「這些名字都是本刊的名字」（→ `names` 聯集），**不蘊含**「它們都是倖存者對外形的異寫」。
///    所以被併者**原本在 variant** 的才進 variant，其餘（含被併者的 authorized）進 names、未標。
/// 2. 被併者 `names` 裡帶 `start`／`end`／`attested`／`source`／`note` 的段要**整段**搬過去
///    （`lossless-intake`；`zero-instance-guards` 第 22 列保留沿革就是為了讓它有位置可落）。
///
/// 同名的段若與倖存者那一段時間不同而**不能並存**（不是兩段都帶不相交的時間），合併不替人判定
/// 哪一段對——具名拒絕、零寫入。
final class VenueMergeNameAbsorptionTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-venue-absorb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        GitFixture.initRepo(root)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func seg(_ v: String, start: String? = nil, end: String? = nil,
                     attested: [String] = [], source: String? = nil, note: String? = nil) -> TemporalValue<String> {
        TemporalValue(value: v, range: DateRange(start: start, end: end, attested: attested),
                      source: source, note: note)
    }

    /// 寫入倖存者與被併者（依序），一筆指向第一個被併者的 work，一筆列出全部候選的歧異記錄，commit。
    @discardableResult
    private func seed(keeper: Venue, doomed: [Venue]) throws -> Divergence {
        try store.writeVenue(keeper)
        for d in doomed { try store.writeVenue(d) }
        var work = Entry(id: UUID(), citekey: "shih2025a", type: .periodicalArticle,
                         title: "A note", authors: [.literal("Shih, J.")], date: "2025")
        work.venues = [.key(doomed[0].key)]
        try store.writeEntry(work)
        let d = Divergence(id: UUID(), question: "同一本刊嗎",
                           candidates: ([keeper] + doomed).map { DivergenceCandidate(key: $0.key, shape: .venue) })
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        return d
    }

    private func keeperAfter(_ key: String) throws -> Venue {
        try XCTUnwrap(LibraryStore(root: root).load().venues.first { $0.key == key })
    }

    // MARK: - 分類：被併者原本在 variant 的才進 variant

    func testOnlyTheDoomedsVariantsAreTaggedVariant() throws {
        let keeper = Venue(key: "k", type: .periodical,
                           names: Timeline([seg("Keeper Journal")]), authorized: ["Keeper Journal"])
        var doomed = Venue(key: "d", type: .periodical,
                           names: Timeline([seg("Doomed Journal"), seg("DOOMED JOURNAL"), seg("Doomed J")]),
                           authorized: ["Doomed Journal"])
        doomed.variant = ["DOOMED JOURNAL"]
        let d = try seed(keeper: keeper, doomed: [doomed])
        let report = try store.resolveDivergence(id: d.id, survivor: "k")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        let v = try keeperAfter("k")
        XCTAssertEqual(Set(v.names.entries.map(\.value)),
                       ["Keeper Journal", "Doomed Journal", "DOOMED JOURNAL", "Doomed J"])
        XCTAssertEqual(v.variant, ["DOOMED JOURNAL"],
                       "只有被併者原本在 variant 的才進 variant——它的 authorized 與未標的名字留未標：\(v.variant)")
        XCTAssertEqual(v.authorized, ["Keeper Journal"])
    }

    /// 被併者的 authorized 不在倖存者 names：併入後**成為未標**，提醒要說真的結果（#565 Expected 2）。
    func testDemotedAuthorizedIsAnnouncedAsBecomingUnclassified() throws {
        let keeper = Venue(key: "k", type: .periodical,
                           names: Timeline([seg("Keeper Journal")]), authorized: ["Keeper Journal"])
        let doomed = Venue(key: "d", type: .periodical,
                           names: Timeline([seg("Doomed Journal")]), authorized: ["Doomed Journal"])
        let d = try seed(keeper: keeper, doomed: [doomed])
        let preview = try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)
        let line = try XCTUnwrap(preview.warnings.first { $0.contains("Doomed Journal") }, "\(preview.warnings)")
        XCTAssertTrue(line.contains("成為未標"), line)
        XCTAssertFalse(line.contains("的 variant（"), "不得預告一個不會發生的 variant 標記：\(line)")
        let report = try store.resolveDivergence(id: d.id, survivor: "k")
        XCTAssertEqual(preview.warnings, report.warnings)
        XCTAssertEqual(try keeperAfter("k").variant, [])
    }

    // MARK: - 時間欄位：整段搬

    func testDatedSegmentMovesWholeWithSourceAndNote() throws {
        let keeper = Venue(key: "k", type: .periodical,
                           names: Timeline([seg("Keeper Journal")]), authorized: ["Keeper Journal"])
        let old = seg("Old Title", start: "1933", end: "1960",
                      source: "https://example.org/history", note: "masthead")
        let attested = seg("Interim Title", attested: ["1961"])
        let doomed = Venue(key: "d", type: .periodical,
                           names: Timeline([seg("Doomed Journal"), old, attested]), authorized: ["Doomed Journal"])
        let d = try seed(keeper: keeper, doomed: [doomed])
        let report = try store.resolveDivergence(id: d.id, survivor: "k")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        let v = try keeperAfter("k")
        XCTAssertTrue(v.names.entries.contains(old), "沿革段要整段搬（時間、source、note）：\(v.names.entries)")
        XCTAssertTrue(v.names.entries.contains(attested), "attested 也是時間欄位：\(v.names.entries)")
        XCTAssertFalse(v.variant.contains("Old Title"), "沿革段不是異寫")
    }

    /// 沿革改回舊名：倖存者有 `Sankhyā` 1933–1960，被併者有 `Sankhyā` 2002–2007——兩段都帶不相交的時間，並存合法。
    func testSameNameRenamingHistorySegmentCoexistsWithTheKeepers() throws {
        let early = seg("Sankhyā", start: "1933", end: "1960")
        let late = seg("Sankhyā", start: "2002", end: "2007")
        let keeper = Venue(key: "k", type: .periodical,
                           names: Timeline([seg("Sankhya Current"), early]), authorized: ["Sankhya Current"])
        let doomed = Venue(key: "d", type: .periodical,
                           names: Timeline([seg("Sankhya Series A"), late]), authorized: ["Sankhya Series A"])
        let d = try seed(keeper: keeper, doomed: [doomed])
        let report = try store.resolveDivergence(id: d.id, survivor: "k")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        let v = try keeperAfter("k")
        XCTAssertTrue(v.names.entries.contains(early) && v.names.entries.contains(late),
                      "兩段都要在：\(v.names.entries)")
    }

    /// 同名、時間不同而不能並存（倖存者那段不帶時間）：合併不替人判定哪一段對——dry-run 與實跑都拒、訊息指名被併者
    /// 與那段的時間、零寫入。在此之前被併者的時間欄位會被安靜丟掉。
    func testConflictingSameNameSegmentIsRefusedAndNamed() throws {
        let keeper = Venue(key: "k", type: .periodical,
                           names: Timeline([seg("Keeper Journal"), seg("Shared Title")]), authorized: ["Keeper Journal"])
        let doomed = Venue(key: "d", type: .periodical,
                           names: Timeline([seg("Doomed Journal"), seg("Shared Title", start: "1933", end: "1960")]),
                           authorized: ["Doomed Journal"])
        let d = try seed(keeper: keeper, doomed: [doomed])
        func check(_ err: Error) {
            let s = (err as? LocalizedError)?.errorDescription ?? String(describing: err)
            XCTAssertTrue(s.contains("被併的「d」"), s)
            XCTAssertTrue(s.contains("Shared Title") && s.contains("1933") && s.contains("1960"), s)
            XCTAssertTrue(s.contains("不能並存"), s)
        }
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil), "dry-run", check)
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "k"), "apply", check)
        let after = try store.load()
        XCTAssertEqual(Set(after.venues.map(\.key)), ["k", "d"], "零寫入：被併者還在")
        XCTAssertEqual(after.entries.first?.venues, [.key("d")])
        XCTAssertEqual(after.venues.first { $0.key == "k" }?.names.entries.count, 2, "倖存者沒被改")
    }

    /// 同一段只差 note（倖存者沒有）也不能並存——note 會隨被併檔消失，同樣要人決定。
    func testSameSegmentDifferingOnlyInNoteIsRefused() throws {
        let keeper = Venue(key: "k", type: .periodical,
                           names: Timeline([seg("Keeper Journal"), seg("Shared Title")]), authorized: ["Keeper Journal"])
        let doomed = Venue(key: "d", type: .periodical,
                           names: Timeline([seg("Doomed Journal"), seg("Shared Title", note: "from WoS")]),
                           authorized: ["Doomed Journal"])
        let d = try seed(keeper: keeper, doomed: [doomed])
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)) { err in
            let s = (err as? LocalizedError)?.errorDescription ?? String(describing: err)
            XCTAssertTrue(s.contains("from WoS"), s)
        }
    }

    /// 完全相同的段（canonical 相等、時間與 source／note 相同）不重複搬；三方合併時兩個被併者各帶一份也只留一段。
    func testIdenticalSegmentsAreNotDuplicatedAcrossDoomedRecords() throws {
        let keeper = Venue(key: "k", type: .periodical,
                           names: Timeline([seg("Keeper Journal")]), authorized: ["Keeper Journal"])
        let d1 = Venue(key: "d1", type: .periodical,
                       names: Timeline([seg("Doomed One"), seg("Shared Title", start: "1933", end: "1960")]),
                       authorized: ["Doomed One"])
        let d2 = Venue(key: "d2", type: .periodical,
                       names: Timeline([seg("Doomed Two"), seg("Shared Title", start: "1933", end: "1960")]),
                       authorized: ["Doomed Two"])
        let d = try seed(keeper: keeper, doomed: [d1, d2])
        let report = try store.resolveDivergence(id: d.id, survivor: "k")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        let v = try keeperAfter("k")
        XCTAssertEqual(v.names.entries.filter { $0.value == "Shared Title" }.count, 1, "\(v.names.entries)")
    }

    // MARK: - 被併者的 variant 標記碰上倖存者已有的名字

    /// 倖存者的 names 已有這個名字（未標）而被併者把它標成 variant：合併不改倖存者的分類（不替它多標一句），
    /// 但被併者那句話會隨檔案消失——要說出來，dry-run 與實跑同一句。
    func testDoomedVariantTagOnAnExistingKeeperNameIsAnnouncedNotCarried() throws {
        let keeper = Venue(key: "k", type: .periodical,
                           names: Timeline([seg("Keeper Journal"), seg("KEEPER JOURNAL")]), authorized: ["Keeper Journal"])
        var doomed = Venue(key: "d", type: .periodical,
                           names: Timeline([seg("Doomed Journal"), seg("KEEPER JOURNAL")]), authorized: ["Doomed Journal"])
        doomed.variant = ["KEEPER JOURNAL"]
        let d = try seed(keeper: keeper, doomed: [doomed])
        let preview = try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)
        let line = try XCTUnwrap(preview.warnings.first { $0.contains("KEEPER JOURNAL") }, "\(preview.warnings)")
        XCTAssertTrue(line.contains("variant") && line.contains("未標"), line)
        let report = try store.resolveDivergence(id: d.id, survivor: "k")
        XCTAssertEqual(preview.warnings, report.warnings)
        XCTAssertEqual(try keeperAfter("k").variant, [], "倖存者的分類不變")
    }

    /// 倖存者已把它當對外形、被併者說它是異寫：兩邊的分類衝突，倖存者為準，也要說。
    func testDoomedVariantThatIsTheKeepersAuthorizedIsAnnounced() throws {
        let keeper = Venue(key: "k", type: .periodical,
                           names: Timeline([seg("Keeper Journal")]), authorized: ["Keeper Journal"])
        var doomed = Venue(key: "d", type: .periodical,
                           names: Timeline([seg("Doomed Journal"), seg("Keeper Journal")]), authorized: ["Doomed Journal"])
        doomed.variant = ["Keeper Journal"]
        let d = try seed(keeper: keeper, doomed: [doomed])
        let report = try store.resolveDivergence(id: d.id, survivor: "k")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        let line = try XCTUnwrap(report.warnings.first { $0.contains("「Keeper Journal」在被併的") }, "\(report.warnings)")
        XCTAssertTrue(line.contains("authorized"), line)
        let v = try keeperAfter("k")
        XCTAssertEqual(v.authorized, ["Keeper Journal"])
        XCTAssertEqual(v.variant, [])
    }

    /// 被併者的孤兒 variant（不在它自己的 names 裡——#473 起是 error，只有手改或舊 binary 寫得出來）：
    /// 在此之前它照樣併進倖存者的 names 與 variant；#565 保留這個行為（不安靜丟掉）。
    func testDoomedOrphanVariantIsStillCarried() throws {
        let keeper = Venue(key: "k", type: .periodical,
                           names: Timeline([seg("Keeper Journal")]), authorized: ["Keeper Journal"])
        let doomed = Venue(key: "d", type: .periodical,
                           names: Timeline([seg("Doomed Journal")]), authorized: ["Doomed Journal"])
        try store.writeVenue(doomed)
        let file = root.appendingPathComponent("entities/\(doomed.id.uuidString).yaml")
        let text = try String(contentsOf: file, encoding: .utf8)
        try (text + "variant:\n- Orphan Spelling\n").write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.load().venues.first { $0.key == "d" }?.variant, ["Orphan Spelling"], "fixture")
        try store.writeVenue(keeper)
        var work = Entry(id: UUID(), citekey: "shih2025a", type: .periodicalArticle,
                         title: "A note", authors: [.literal("Shih, J.")], date: "2025")
        work.venues = [.key("d")]
        try store.writeEntry(work)
        let dv = Divergence(id: UUID(), question: "同一本刊嗎",
                            candidates: [DivergenceCandidate(key: "k", shape: .venue), DivergenceCandidate(key: "d", shape: .venue)])
        try store.writeDivergence(dv)
        GitFixture.commitAll(root, message: "seed")
        let report = try store.resolveDivergence(id: dv.id, survivor: "k")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        let v = try keeperAfter("k")
        XCTAssertTrue(v.names.entries.map(\.value).contains("Orphan Spelling"), "\(v.names.entries)")
        XCTAssertEqual(v.variant, ["Orphan Spelling"])
    }
}
