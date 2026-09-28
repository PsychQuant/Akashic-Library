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
    private func seed(keeper: Venue, doomed: [Venue], into target: (root: URL, store: LibraryStore)? = nil) throws -> Divergence {
        let store = target?.store ?? self.store!
        let root = target?.root ?? self.root!
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

    /// 另一份獨立的 store（同一個測試裡比兩種被併者順序的結果）。呼叫端負責在測試結束前移除。
    private func freshStore() throws -> (root: URL, store: LibraryStore) {
        let r = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-venue-absorb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: r.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: r, format: StoreVersion.supported)
        GitFixture.initRepo(r)
        return (r, LibraryStore(root: r))
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

    // MARK: - 三方合併：分類與提醒與被併者的順序無關（#565 R1 verify，四席同指）

    /// 倖存者沒有 `Shared Alias`，兩個被併者各帶一份完全相同的段，只有一個把它列在 variant。R1 之前只有**先處理**的那個被併者
    /// 決定分類：標記在鍵較前的被併者身上時 variant 是 `["Shared Alias"]`，在較後的身上時是 `[]`——同一份資料、與語意無關的順序。
    /// 規則：倖存者原本沒有的名字，**任一**被併者把它列在 variant 就標（未標「不作任何宣稱」，不構成反對）。
    func testThreeWayVariantClassificationDoesNotDependOnDoomedOrder() throws {
        let keeper = Venue(key: "k", type: .periodical, names: Timeline([seg("Keeper Journal")]), authorized: ["Keeper Journal"])
        var tagged = Venue(key: "z-var", type: .periodical, names: Timeline([seg("Z Var"), seg("Shared Alias")]), authorized: ["Z Var"])
        tagged.variant = ["Shared Alias"]
        let plain = Venue(key: "a-plain", type: .periodical, names: Timeline([seg("A Plain"), seg("Shared Alias")]), authorized: ["A Plain"])
        for order in [[tagged, plain], [plain, tagged]] {
            let m = LibraryStore.mergedVenueKeeper(keeper, absorbing: order)
            XCTAssertEqual(m.keeper.variant, ["Shared Alias"], "任一被併者標了就標——順序 \(order.map(\.key))")
            XCTAssertEqual(m.keeper.names.entries.filter { $0.value == "Shared Alias" }.count, 1, "完全相同的段只搬一份")
            let absorption = LibraryStore.venueNameAbsorption(keeper: keeper, doomed: order)
            XCTAssertTrue(absorption.uncarriedVariants.isEmpty,
                          "倖存者原本沒有這個名字，沒有既有分類可保護，也就沒有「沒帶過去」的提醒：\(absorption.uncarriedVariants)")
        }
    }

    /// 同上，走真的 store 與兩種鍵的排序（被併者依鍵落盤後的順序處理）：分類與提醒（排序後）逐字相同。
    func testThreeWayEndToEndResultIsTheSameWhicheverDoomedKeyComesFirst() throws {
        func run(taggedKey: String, plainKey: String) throws -> (variant: [String], warnings: [String]) {
            let s = try freshStore()
            defer { try? FileManager.default.removeItem(at: s.root) }
            let keeper = Venue(key: "k", type: .periodical, names: Timeline([seg("Keeper Journal")]), authorized: ["Keeper Journal"])
            var tagged = Venue(key: taggedKey, type: .periodical, names: Timeline([seg("Tagged Main"), seg("Shared Alias")]), authorized: ["Tagged Main"])
            tagged.variant = ["Shared Alias"]
            let plain = Venue(key: plainKey, type: .periodical, names: Timeline([seg("Plain Main"), seg("Shared Alias")]), authorized: ["Plain Main"])
            let d = try seed(keeper: keeper, doomed: [tagged, plain], into: s)
            let preview = try s.store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)
            let report = try s.store.resolveDivergence(id: d.id, survivor: "k")
            XCTAssertEqual(preview.warnings, report.warnings, "dry-run 與實跑同一份")
            let after = try XCTUnwrap(LibraryStore(root: s.root).load().venues.first { $0.key == "k" })
            return (after.variant, report.warnings.sorted())
        }
        let a = try run(taggedKey: "a-var", plainKey: "z-plain")
        let b = try run(taggedKey: "z-var", plainKey: "a-plain")
        XCTAssertEqual(a.variant, ["Shared Alias"])
        XCTAssertEqual(a.variant, b.variant, "被併者的鍵排序不得改變分類")
        // 提醒的內容也不該取決於順序——只差被併者的鍵名，把它們換成同一組再比
        let norm: ([String]) -> [String] = { $0.map { $0.replacingOccurrences(of: "a-var", with: "T").replacingOccurrences(of: "z-var", with: "T")
            .replacingOccurrences(of: "a-plain", with: "P").replacingOccurrences(of: "z-plain", with: "P") }.sorted() }
        XCTAssertEqual(norm(a.warnings), norm(b.warnings), "\(a.warnings) ／ \(b.warnings)")
    }

    /// authorized 降級的提醒要依**最終結果**：d1 把 `Shared X` 當 authorized、d2 把它列為 variant、倖存者沒有它。最終是 variant
    /// （併入 names 並標 variant），R1 之前提醒只對原始倖存者算、預告「成為未標」——與實際相反。兩種順序同一句。
    func testThreeWayAuthorizedReminderFollowsTheFinalOutcome() throws {
        let keeper = Venue(key: "k", type: .periodical, names: Timeline([seg("Keeper Journal")]), authorized: ["Keeper Journal"])
        let asAuthorized = Venue(key: "d1", type: .periodical, names: Timeline([seg("Shared X")]), authorized: ["Shared X"])
        var asVariant = Venue(key: "d2", type: .periodical, names: Timeline([seg("D2 Main"), seg("Shared X")]), authorized: ["D2 Main"])
        asVariant.variant = ["Shared X"]
        var reminders: [[String]] = []
        for order in [[asAuthorized, asVariant], [asVariant, asAuthorized]] {
            let s = try freshStore()
            defer { try? FileManager.default.removeItem(at: s.root) }
            let d = try seed(keeper: keeper, doomed: order, into: s)
            let preview = try s.store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)
            let line = try XCTUnwrap(preview.warnings.first { $0.contains("「Shared X」") && $0.contains("是 authorized") }, "\(preview.warnings)")
            XCTAssertTrue(line.contains("variant") && !line.contains("成為未標"), "最終是 variant，不得預告成為未標：\(line)")
            XCTAssertTrue(line.contains("d2"), "說出是哪個被併者把它列為 variant：\(line)")
            let report = try s.store.resolveDivergence(id: d.id, survivor: "k")
            XCTAssertEqual(preview.warnings, report.warnings)
            XCTAssertEqual(try XCTUnwrap(LibraryStore(root: s.root).load().venues.first { $0.key == "k" }).variant, ["Shared X"], "預告與實際一致")
            reminders.append(preview.warnings.sorted())
        }
        XCTAssertEqual(reminders[0], reminders[1], "兩種順序的提醒逐字相同")
    }

    /// 倖存者「原本」就有的名字，被併者說它是 variant：只提醒、不改倖存者的分類，而且**只**對原本的倖存者做——
    /// 先併入的被併者帶進來的名字不算「倖存者已有」（R1 之前那句「倖存者已有這個名字」在三方合併時是假話）。
    func testUncarriedReminderIsOnlyForNamesTheKeeperOriginallyHad() throws {
        let keeper = Venue(key: "k", type: .periodical,
                           names: Timeline([seg("Keeper Journal"), seg("KEEPER JOURNAL")]), authorized: ["Keeper Journal"])
        var d1 = Venue(key: "d1", type: .periodical, names: Timeline([seg("D1 Main"), seg("KEEPER JOURNAL")]), authorized: ["D1 Main"])
        d1.variant = ["KEEPER JOURNAL"]
        var d2 = Venue(key: "d2", type: .periodical, names: Timeline([seg("D2 Main"), seg("KEEPER JOURNAL"), seg("New Alias")]), authorized: ["D2 Main"])
        d2.variant = ["KEEPER JOURNAL"]
        for order in [[d1, d2], [d2, d1]] {
            let a = LibraryStore.venueNameAbsorption(keeper: keeper, doomed: order)
            XCTAssertEqual(a.uncarriedVariants.count, 1, "每個名字一則，不論幾個被併者說了：\(a.uncarriedVariants)")
            XCTAssertEqual(a.uncarriedVariants.first?.froms, ["d1", "d2"], "兩個被併者都說了——都點名、排序固定")
            XCTAssertFalse(a.incoming.contains { $0.segment.value == "KEEPER JOURNAL" }, "倖存者已有的相同段不搬")
        }
    }

    // MARK: - source／note 的「完全相同」是位元組相同（#565 R1 verify）

    /// Swift `String ==` 是 canonical equivalence：NFC 的 `Café` 與 NFD 的 `Cafe\u{0301}` 相等，於是被併者那一段被當成「完全相同」略過，
    /// 它的 note／source 位元組隨檔案消失，既沒有衝突拒絕也沒有遺失回報。名字的身分仍是 canonical，但「可以整段不搬」的判準是位元組。
    func testSegmentsDifferingOnlyByNormalizationFormInSourceOrNoteAreNotSilentlyDeduplicated() throws {
        let nfc = "Caf\u{00E9}", nfd = "Cafe\u{0301}"
        XCTAssertEqual(nfc, nfd, "fixture：Swift 視為相等")
        XCTAssertNotEqual(Array(nfc.utf8), Array(nfd.utf8), "fixture：位元組不同")
        let keeper = Venue(key: "k", type: .periodical, names: Timeline([seg("Keeper Journal")]), authorized: ["Keeper Journal"])
        for (label, keeperSeg, doomedSeg) in [
            ("note", seg("Shared Title", note: nfc), seg("Shared Title", note: nfd)),
            ("source", seg("Shared Title", source: nfc), seg("Shared Title", source: nfd)),
        ] {
            var k = keeper
            k.names = Timeline(k.names.entries + [keeperSeg])
            let d = Venue(key: "d", type: .periodical, names: Timeline([seg("Doomed Journal"), doomedSeg]), authorized: ["Doomed Journal"])
            let a = LibraryStore.venueNameAbsorption(keeper: k, doomed: [d])
            XCTAssertEqual(a.conflicts.count, 1, "\(label)：位元組不同 → 不是「完全相同」，不能安靜略過；同名又不能並存 → 具名衝突")
            XCTAssertTrue(a.incoming.contains { $0.segment.value == "Shared Title" }, "\(label)：照樣搬（前置具名拒絕，寫入閘是最後一道）")
        }
        // 位元組完全相同的仍然略過
        var k2 = keeper
        k2.names = Timeline(k2.names.entries + [seg("Shared Title", source: nfc, note: nfd)])
        let same = Venue(key: "d", type: .periodical,
                         names: Timeline([seg("Doomed Journal"), seg("Shared Title", source: nfc, note: nfd)]), authorized: ["Doomed Journal"])
        let a2 = LibraryStore.venueNameAbsorption(keeper: k2, doomed: [same])
        XCTAssertTrue(a2.conflicts.isEmpty && !a2.incoming.contains { $0.segment.value == "Shared Title" })
    }

    /// 走真的 store：note 只差 NFC／NFD 的兩筆，合併要以「不能並存」具名拒絕、零寫入（不是默默合併）。
    func testNoteDifferingOnlyByNormalizationFormIsRefusedThroughTheStore() throws {
        let nfc = "Caf\u{00E9}", nfd = "Cafe\u{0301}"
        let keeper = Venue(key: "k", type: .periodical,
                           names: Timeline([seg("Keeper Journal"), seg("Shared Title", note: nfc)]), authorized: ["Keeper Journal"])
        let doomed = Venue(key: "d", type: .periodical,
                           names: Timeline([seg("Doomed Journal"), seg("Shared Title", note: nfd)]), authorized: ["Doomed Journal"])
        let d = try seed(keeper: keeper, doomed: [doomed])
        let stored = try XCTUnwrap(store.load().venues.first { $0.key == "d" }?.names.entries.first { $0.value == "Shared Title" }?.note)
        try XCTSkipUnless(Array(stored.utf8) == Array(nfd.utf8), "store 在寫入時把 note 正規化了，這個 fixture 到不了磁碟——靜態測試已釘住")
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)) { err in
            XCTAssertTrue(String(describing: err).contains("不能並存"), "\(err)")
        }
        XCTAssertEqual(Set(try store.load().venues.map(\.key)), ["k", "d"], "零寫入")
    }

    // MARK: - 效能：名字併入是線性的（#565 R1 verify，四席同指）

    /// 舊實作（`Set` 濾除）是線性的；#565 首版對每個候選重掃「倖存者＋已搬入」的全部段並重算 canonical，是二次方——被併者與倖存者各
    /// 1,000／3,000／6,000 個相異名字，微基準 2.2／20.4／78.2 秒。現在每段的 canonical 鍵只算一次、以鍵建索引，每個候選只查自己的鍵。
    func testAbsorbingThousandsOfDistinctNamesStaysFast() throws {
        let n = 5_000
        let keeper = Venue(key: "k", type: .periodical,
                           names: Timeline((0..<n).map { seg("Keeper Name \($0)") }), authorized: ["Keeper Name 0"])
        let doomed = Venue(key: "d", type: .periodical,
                           names: Timeline((0..<n).map { seg("Doomed Name \($0)") }), authorized: ["Doomed Name 0"])
        let start = Date()
        let a = LibraryStore.venueNameAbsorption(keeper: keeper, doomed: [doomed])
        let merged = LibraryStore.mergedVenueKeeper(keeper, absorbing: [doomed])
        let elapsed = Date().timeIntervalSince(start)
        print("[perf] absorbing \(n)+\(n) distinct names: \(String(format: "%.3f", elapsed)) s")
        XCTAssertEqual(a.incoming.count, n)
        XCTAssertEqual(merged.keeper.names.entries.count, 2 * n)
        XCTAssertTrue(a.conflicts.isEmpty)
        XCTAssertLessThan(elapsed, 2.0, "5,000 個相異名字的併入要在 2 秒內（二次方的寫法在 debug build 實測 118.7 秒，線性的是 0.1 秒上下）")
    }

    // MARK: - 拒絕訊息（#565 R1 verify）

    /// 三方合併：倖存者 `Sankhya` 1933–1960、d1 2002–2007、d2 2005–2010——d2 與**先併入的 d1** 衝突。訊息要點名兩個被併者，
    /// 而且出路要對：把 d2 那段寫進倖存者只會讓倖存者與 d1 那段重疊、下一輪換成 d1 被拒；能解的是改其中一個被併者的 YAML。
    func testThreeWayConflictBetweenTwoDoomedRecordsNamesBothAndPointsAtTheRightFix() throws {
        let keeper = Venue(key: "k", type: .periodical,
                           names: Timeline([seg("Keeper Journal"), seg("Sankhya", start: "1933", end: "1960")]), authorized: ["Keeper Journal"])
        let d1 = Venue(key: "d1", type: .periodical,
                       names: Timeline([seg("D1 Main"), seg("Sankhya", start: "2002", end: "2007")]), authorized: ["D1 Main"])
        let d2 = Venue(key: "d2", type: .periodical,
                       names: Timeline([seg("D2 Main"), seg("Sankhya", start: "2005", end: "2010")]), authorized: ["D2 Main"])
        let d = try seed(keeper: keeper, doomed: [d1, d2])
        func check(_ err: Error) {
            let s = (err as? LocalizedError)?.errorDescription ?? String(describing: err)
            XCTAssertTrue(s.contains("被併的「d2」"), s)
            XCTAssertTrue(s.contains("先併入的被併者「d1」"), "衝突的另一方是先併入的被併者，不是倖存者：\(s)")
            XCTAssertTrue(s.contains("兩個被併者") && s.contains("改其中一筆"), "出路是改其中一個被併者的 YAML：\(s)")
            XCTAssertFalse(s.contains("逐字寫進倖存者"), "對被併者之間的衝突，把那段寫進倖存者不是出路：\(s)")
        }
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil), "dry-run", check)
        XCTAssertThrowsError(try store.resolveDivergence(id: d.id, survivor: "k"), "apply", check)
        XCTAssertEqual(Set(try store.load().venues.map(\.key)), ["k", "d1", "d2"], "零寫入")
    }

    /// 與倖存者自己的段衝突：出路要說完整——倖存者那段若不帶時間、被併者的是沿革段，把被併者的那段寫進倖存者會造出同名近重複，
    /// 被寫入閘擋下；操作者必須連倖存者自己的那段一起換掉。
    func testConflictWithTheKeepersOwnSegmentSaysTheFixIsOnBothSides() throws {
        let keeper = Venue(key: "k", type: .periodical,
                           names: Timeline([seg("Keeper Journal"), seg("Shared Title")]), authorized: ["Keeper Journal"])
        let doomed = Venue(key: "d", type: .periodical,
                           names: Timeline([seg("Doomed Journal"), seg("Shared Title", start: "1933", end: "1960")]), authorized: ["Doomed Journal"])
        let d = try seed(keeper: keeper, doomed: [doomed])
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)) { err in
            let s = (err as? LocalizedError)?.errorDescription ?? String(describing: err)
            XCTAssertTrue(s.contains("倖存者同名的那一段"), s)
            XCTAssertTrue(s.contains("倖存者自己的那一段"), "出路要說到倖存者自己的那一段也得改：\(s)")
        }
    }

    /// 不能並存的同名段清單有上限：至多列 20 組，其餘給總數。被併者帶數千個互相衝突的同名段時，訊息大小不得正比於 store 內容。
    func testConflictListIsCappedAndCarriesTheTotal() throws {
        let n = 30
        let names = (0..<n).map { String(format: "Shared %02d", $0) }
        let keeper = Venue(key: "k", type: .periodical,
                           names: Timeline([seg("Keeper Journal")] + names.map { seg($0) }), authorized: ["Keeper Journal"])
        let doomed = Venue(key: "d", type: .periodical,
                           names: Timeline([seg("Doomed Journal")] + names.map { seg($0, note: "from WoS") }), authorized: ["Doomed Journal"])
        let d = try seed(keeper: keeper, doomed: [doomed])
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)) { err in
            let s = (err as? LocalizedError)?.errorDescription ?? String(describing: err)
            XCTAssertEqual(s.components(separatedBy: "不能並存——").count - 1, 20, "至多逐組列 20 條：\(s.count) 字元")
            XCTAssertTrue(s.contains("共 \(n) 組") && s.contains("另有 \(n - 20) 組"), "其餘給總數：\(s)")
        }
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
