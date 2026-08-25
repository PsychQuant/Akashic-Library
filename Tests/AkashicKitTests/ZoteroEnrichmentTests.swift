import XCTest
@testable import AkashicZoteroImport
import AkashicCore

/// 逐筆補值（#340）的語意守衛。
///
/// 這組測試守的核心是**「只加不覆寫」不是一句註解**：`import-zotero` 就在隔壁，
/// 它的 `applyBiblatexFields` 整份替換 `fields`，而兩者共用同一份對映。任何一次
/// 「順手改成直接呼叫 applyBiblatexFields」的重構，都會把補值悄悄變成 pull。
final class ZoteroEnrichmentTests: XCTestCase {

    private func item(key: String, lib: Int = 1, type: String = "journalArticle",
                      fields: [String: String]) -> ZoteroItem {
        ZoteroItem(key: key, version: 1, libraryID: lib, typeName: type,
                   fields: fields, authors: [], tags: [], attachmentPaths: [])
    }

    private func entry(_ citekey: String, type: WorkType = .periodicalArticle,
                       title: String = "T", date: String? = nil,
                       fields: [String: String] = [:],
                       zoteroKey: String? = "ZK1", libraryID: Int? = 1) -> Entry {
        var e = Entry(id: UUID(), citekey: citekey, type: type, title: title)
        e.date = date
        e.fields = fields
        if let zoteroKey {
            e.provenance = Provenance(zoteroKey: zoteroKey, zoteroVersion: 1, libraryID: libraryID)
        }
        return e
    }

    // MARK: - 核心語意

    func testOnlyAbsentKeysAreAdded() {
        let e = entry("a", fields: ["journaltitle": "人工修過的刊名"])
        let i = item(key: "ZK1", fields: ["publicationTitle": "Zotero 的刊名",
                                          "volume": "12", "title": "T"])
        let plan = ZoteroEnrichment.plan(entries: [e], items: [i], citekeys: ["a"])
        XCTAssertEqual(plan.additions.count, 1)
        let add = plan.additions[0]
        XCTAssertEqual(add.addedFields, ["volume": "12"],
                       "既有的 journaltitle 不得出現在補值清單裡——那是覆寫不是補值")

        let after = ZoteroEnrichment.applied(add, to: e)
        XCTAssertEqual(after.fields["journaltitle"], "人工修過的刊名",
                       "**這一條是本命令存在的理由**：pull 會把它換成 Zotero 的值")
        XCTAssertEqual(after.fields["volume"], "12")
    }

    func testTypeTitleAuthorsAndVenuesAreNeverTouched() {
        var e = entry("a", type: .referenceWorkEntry, title: "store 的標題")
        e.authors = [.literal("已在 store 的作者")]
        e.venues = [.literal("已在 store 的載體")]
        // Zotero 說它是 journalArticle、標題不同、有自己的作者
        var i = item(key: "ZK1", type: "journalArticle",
                     fields: ["title": "Zotero 的標題", "publicationTitle": "J"])
        i.authors = [(display: "Zotero Author", family: "Author")]

        let plan = ZoteroEnrichment.plan(entries: [e], items: [i], citekeys: ["a"])
        let after = ZoteroEnrichment.applied(plan.additions[0], to: e)
        XCTAssertEqual(after.type, .referenceWorkEntry, "type 不得被 pull 語意改掉")
        XCTAssertEqual(after.title, "store 的標題")
        XCTAssertEqual(after.authors, [.literal("已在 store 的作者")])
        XCTAssertEqual(after.venues, [.literal("已在 store 的載體")])
        XCTAssertEqual(after.fields["journaltitle"], "J", "該補的還是要補")
    }

    func testExistingDateIsNotOverwrittenButAbsentDateIsFilled() {
        let kept = entry("kept", date: "1999")
        let empty = entry("empty", zoteroKey: "ZK2")
        let i1 = item(key: "ZK1", fields: ["date": "2020-01-01 2020"])
        let i2 = item(key: "ZK2", fields: ["date": "2020-01-01 2020"])
        let plan = ZoteroEnrichment.plan(entries: [kept, empty],
                                         items: [i1, i2], citekeys: ["kept", "empty"])
        XCTAssertEqual(plan.unchanged, ["kept"], "已有 date 且無其他可補 → unchanged")
        XCTAssertEqual(plan.additions.count, 1)
        XCTAssertEqual(plan.additions[0].citekey, "empty")
        XCTAssertNotNil(plan.additions[0].addedDate)
    }

    func testEmptyZoteroValuesAreNotAdded() {
        let e = entry("a")
        let i = item(key: "ZK1", fields: ["publicationTitle": "", "volume": "3"])
        let plan = ZoteroEnrichment.plan(entries: [e], items: [i], citekeys: ["a"])
        XCTAssertEqual(plan.additions[0].addedFields, ["volume": "3"],
                       "空字串補進去會讓「有這個欄位」與「有值」分岔")
    }

    // MARK: - 封閉分類的後置條件

    /// **每一筆指名的 citekey 必落在恰好一類。** 少一類＝那筆安靜消失，
    /// 而「查了沒補到」與「沒查」在輸出上會變成同一件事。
    func testEveryNamedCitekeyIsAccountedForExactlyOnce() {
        let entries = [entry("hasZotero"),
                       entry("noProv", zoteroKey: nil),
                       entry("zGone", zoteroKey: "MISSING")]
        let items = [item(key: "ZK1", fields: ["volume": "1"])]
        let named = ["hasZotero", "noProv", "zGone", "notThere"]
        let plan = ZoteroEnrichment.plan(entries: entries, items: items, citekeys: named)

        XCTAssertEqual(plan.accountedCitekeys.sorted(), named.sorted(),
                       "指名的每一筆都要出現，且只出現一次")
        XCTAssertEqual(plan.noProvenance, ["noProv"])
        XCTAssertEqual(plan.zoteroMissing, ["zGone"])
        XCTAssertEqual(plan.notInStore, ["notThere"])
    }

    func testLegacyEntryWithoutLibraryIDStillMatchesByBareKey() {
        let e = entry("a", libraryID: nil)
        let i = item(key: "ZK1", lib: 7, fields: ["volume": "9"])
        let plan = ZoteroEnrichment.plan(entries: [e], items: [i], citekeys: ["a"])
        XCTAssertEqual(plan.additions.first?.addedFields, ["volume": "9"],
                       "legacy 記錄（無 library_id）退回裸 key 比對，同 ZoteroImporter")
    }

    /// `applied` 的防呆：計畫算出來之後 store 若被改過（那個鍵已有值），
    /// **保守側是不動**，不是照計畫覆寫。
    func testAppliedSkipsKeysThatGainedAValueSincePlanning() {
        let planned = ZoteroEnrichment.Addition(
            citekey: "a", addedFields: ["journaltitle": "計畫時算出的"], addedDate: nil)
        let now = entry("a", fields: ["journaltitle": "計畫之後有人填了這個"])
        XCTAssertEqual(ZoteroEnrichment.applied(planned, to: now).fields["journaltitle"],
                       "計畫之後有人填了這個")
    }

    // MARK: - 空 authors 的顯式補值（#340）

    /// 旗標**預設關閉**——不傳就完全不碰 `authors`（原契約不變）。
    func testAuthorsAreUntouchedWithoutTheFlag() {
        let e = entry("a", fields: ["journaltitle": "J"])
        var i = item(key: "ZK1", fields: ["volume": "3", "title": "T"])
        i.authors = [(display: "Zotero, A.", family: "Zotero")]
        let plan = ZoteroEnrichment.plan(entries: [e], items: [i], citekeys: ["a"])
        XCTAssertEqual(plan.additions.first?.addedAuthors, [],
                       "未開旗標時 authors 一律不進計畫")
    }

    /// 開旗標且 `authors` **完全為空** → 補 `.literal`（不是 `.key`）。
    ///
    /// `literal-first-then-key`：進庫不猜 key。補 literal 是**啟用** `resolve-people`
    /// 那條消歧路徑，不是繞過它——不補的話那條路徑永遠看不到這些作者。
    func testAbsentAuthorsAreFilledAsLiteralsWithTheFlag() {
        var e = entry("a")
        e.authors = []
        var i = item(key: "ZK1", fields: ["title": "T"])
        i.authors = [(display: "Steer, Robert A.", family: "Steer"),
                     (display: "Beck, Aaron T.", family: "Beck")]
        let plan = ZoteroEnrichment.plan(entries: [e], items: [i], citekeys: ["a"],
                                         includeAbsentAuthors: true)
        XCTAssertEqual(plan.additions.first?.addedAuthors,
                       [.literal("Steer, Robert A."), .literal("Beck, Aaron T.")])
        let after = ZoteroEnrichment.applied(plan.additions[0], to: e)
        XCTAssertEqual(after.authors, [.literal("Steer, Robert A."), .literal("Beck, Aaron T.")])
    }

    /// **反面斷言（本例外的全部安全性都在這裡）**：`authors` 只要非空——哪怕只有一個
    /// `.literal`——一律不動。已歸戶的 `.key` 更不可能被碰到。
    func testNonEmptyAuthorsAreNeverTouchedEvenWithTheFlag() {
        for existing in [[Author.literal("人工填的")], [Author.key("che-cheng")]] {
            var e = entry("a")
            e.authors = existing
            var i = item(key: "ZK1", fields: ["title": "T"])
            i.authors = [(display: "Zotero, A.", family: "Zotero")]
            let plan = ZoteroEnrichment.plan(entries: [e], items: [i], citekeys: ["a"],
                                             includeAbsentAuthors: true)
            XCTAssertEqual(plan.additions.first?.addedAuthors ?? [], [],
                           "authors 非空（\(existing)）時不得進補值計畫")
            if let a = plan.additions.first {
                XCTAssertEqual(ZoteroEnrichment.applied(a, to: e).authors, existing,
                               "套用也不得改動既有作者")
            }
        }
    }

    /// `applied` 的保守側防呆：計畫算出來之後 store 若已長出作者，一律不動。
    func testAppliedSkipsAuthorsThatAppearedSincePlanning() {
        let planned = ZoteroEnrichment.Addition(
            citekey: "a", addedFields: [:], addedDate: nil,
            addedAuthors: [.literal("計畫時算出的")])
        var now = entry("a")
        now.authors = [.literal("計畫之後有人填了這個")]
        XCTAssertEqual(ZoteroEnrichment.applied(planned, to: now).authors,
                       [.literal("計畫之後有人填了這個")])
    }

    /// 空白名字不入庫（同 `testEmptyZoteroValuesAreNotAdded` 的紀律）。
    func testBlankZoteroAuthorNamesAreNotAdded() {
        var e = entry("a")
        e.authors = []
        var i = item(key: "ZK1", fields: ["title": "T"])
        i.authors = [(display: "  ", family: ""), (display: "Real, Name", family: "Real")]
        let plan = ZoteroEnrichment.plan(entries: [e], items: [i], citekeys: ["a"],
                                         includeAbsentAuthors: true)
        XCTAssertEqual(plan.additions.first?.addedAuthors, [.literal("Real, Name")])
    }

    // MARK: - #340 的兩個對映修正

    /// `encyclopediaArticle` 先前不在 `typeMap`，fallback 到 `.webpage`（10.16）。
    /// 那是**落錯節**：百科條目是 10.3，而 10.3 的 source element 在 10.16 沒有位置。
    ///
    /// 附帶擋住一個潛伏回歸：#325 已把那 14 筆訂為 `wikipedia-entry`（#409 起改名為
    /// `reference-work-entry`），而 pull 每次
    /// 都重設 `entry.type`——沒有這一列，一次 `import-zotero` 就把它們降回 webpage。
    func testEncyclopediaArticleMapsToTheReferenceWorkEntryType() {
        XCTAssertEqual(ZoteroMapping.workType(for: "encyclopediaArticle"), .referenceWorkEntry)
        XCTAssertEqual(WorkType.referenceWorkEntry.apa7Section, "10.3",
                       "落點必須是 10.3——若這條紅了，代表節的歸屬變了，"
                       + "上面那個對映要重新裁決")
    }

    /// `encyclopediaTitle` 是 10.3 的 source element（「In *Title of reference work*」），
    /// 在 `@INREFERENCE` 就是 `BOOKTITLE`。
    ///
    /// 沒有這一列時它會以殘餘名 `encyclopediatitle` 入庫——**資料在、但 APA7 仍報缺**。
    func testEncyclopediaTitleBecomesBooktitleNotAResidualField() {
        var probe = Entry(id: UUID(), citekey: "p", type: .webpage, title: "")
        let i = item(key: "ZK1", type: "encyclopediaArticle",
                     fields: ["title": "Attachment theory",
                              "encyclopediaTitle": "Wikipedia, the free encyclopedia"])
        ZoteroMapping.applyBiblatexFields(from: i, to: &probe)
        XCTAssertEqual(probe.fields["booktitle"], "Wikipedia, the free encyclopedia")
        XCTAssertNil(probe.fields["encyclopediatitle"],
                     "走了對映就不該同時留一份殘餘——同一個來源欄位兩個鍵會分岔")
        XCTAssertEqual(probe.type, .referenceWorkEntry)
    }
}

/// 識別碼不得以 `fields` 殘留的形式被種回去（#394 verify）。
///
/// ## 這組測試防的是什麼
///
/// §8 的遷移把 664 筆 work 的 `fields.doi` 一族移進結構化欄位。而本命令是 **add-only**
/// （`entry.fields[k] == nil` 才補）——遷移之後那些鍵**恰好都是 nil**，於是它會把殘留
/// 一筆一筆種回去。
///
/// 那不只是「多一份副本」。`BibExport` 的 venue-ISSN 拉取條件是 `if fields["issn"] == nil`
/// ——殘留一旦回來，那條拉取**被遮蔽**，`.bib` 改用 work 上的原始字串。而 spec
/// （entity-identifier）逐字說 work 帶 ISSN 是 **misplacement**。
extension ZoteroEnrichmentTests {

    /// work 一律不收 ISSN——spec 明文指為錯置。
    func testISSNIsNeverAddedToAWork() {
        let e = entry("a", fields: [:])
        let i = item(key: "ZK1", fields: ["ISSN": "1082-989X", "title": "T"])
        let plan = ZoteroEnrichment.plan(entries: [e], items: [i], citekeys: ["a"])

        let all = plan.additions + plan.refusedOnly
        XCTAssertEqual(all.count, 1, "必須有一筆記錄，不可靜默消失")
        XCTAssertNil(all[0].addedFields["issn"],
                     "ISSN 識別的是期刊不是文章；補到 work 上是 spec 明文的 misplacement，"
                     + "而且會遮蔽 BibExport 的 venue-ISSN 拉取")
        XCTAssertTrue(all[0].refusedIdentifiers.contains { $0.contains("issn") },
                      "拒絕必須具名（lossless-intake 執行細節 3：丟棄必須可見）")
    }

    /// 只有被拒的識別碼、沒有別的可補 → 落在 `refusedOnly`，**不是** `unchanged`。
    func testRefusedOnlyIsDistinctFromUnchanged() {
        let e = entry("a", fields: [:])
        let i = item(key: "ZK1", fields: ["ISSN": "1082-989X"])
        let plan = ZoteroEnrichment.plan(entries: [e], items: [i], citekeys: ["a"])

        XCTAssertTrue(plan.unchanged.isEmpty,
                      "「上游也沒有」與「上游有而我們不收」是兩件事，混在一起就看不出區別")
        XCTAssertEqual(plan.refusedOnly.count, 1)
        XCTAssertEqual(plan.accountedCitekeys.sorted(), ["a"], "每個 citekey 恰好被歸類一次")
    }

    /// DOI 走**結構化欄位**，不進 `fields`。
    func testDOIGoesToTheStructuredFieldNotTheResidue() {
        let e = entry("a", fields: [:])
        let i = item(key: "ZK1", fields: ["DOI": "10.1037/met0000144", "title": "T"])
        let plan = ZoteroEnrichment.plan(entries: [e], items: [i], citekeys: ["a"])

        XCTAssertEqual(plan.additions.count, 1)
        let add = plan.additions[0]
        XCTAssertNil(add.addedFields["doi"], "不得種回 fields 殘留")
        XCTAssertEqual(add.addedDOIs.map(\.normalized), ["10.1037/met0000144"])

        let applied = ZoteroEnrichment.applied(add, to: e)
        XCTAssertEqual(applied.doi.map(\.normalized), ["10.1037/met0000144"])
        XCTAssertNil(applied.fields["doi"])
    }

    /// 已有結構化 DOI 時不動它——保守側紀律與既有的 `fields` 一致。
    func testExistingStructuredDOIIsNotOverwritten() {
        var e = entry("a", fields: [:])
        e.doi = [XCTUnwrap0(DOI("10.1037/aaa"))]
        let i = item(key: "ZK1", fields: ["DOI": "10.1037/bbb", "title": "T"])
        let plan = ZoteroEnrichment.plan(entries: [e], items: [i], citekeys: ["a"])

        let add = plan.additions.first
        XCTAssertTrue(add?.addedDOIs.isEmpty ?? true, "既有結構化值不得被覆寫")
        XCTAssertNil(add?.addedFields["doi"], "也不得繞道 fields 寫回去")
    }

    /// 形狀不合法的識別碼**不猜**，但要具名。
    func testUnparseableIdentifierIsRefusedByName() {
        let e = entry("a", fields: [:])
        let i = item(key: "ZK1", fields: ["DOI": "not-a-doi", "title": "T"])
        let plan = ZoteroEnrichment.plan(entries: [e], items: [i], citekeys: ["a"])

        let all = plan.additions + plan.refusedOnly
        XCTAssertEqual(all.count, 1)
        XCTAssertTrue(all[0].addedDOIs.isEmpty)
        XCTAssertNil(all[0].addedFields["doi"])
        XCTAssertTrue(all[0].refusedIdentifiers.contains { $0.contains("doi") })
    }
}

/// XCTUnwrap 在非 throwing 上下文的小輔助。
private func XCTUnwrap0<T>(_ v: T?) -> T {
    guard let v else { preconditionFailure("預期非 nil") }
    return v
}
