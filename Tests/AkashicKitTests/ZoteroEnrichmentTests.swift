import XCTest
@testable import AkashicExport
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

    /// 造一筆「entry 無 ISBN、Zotero 有一個部分可解的 ISBN 字串」的計畫（#394 verify R9）。
    func planWithZoteroISBN(_ raw: String) throws -> ZoteroEnrichment.Result {
        let e = entry("a")
        let i = item(key: "ZK1", fields: ["title": "T", "ISBN": raw])
        return ZoteroEnrichment.plan(entries: [e], items: [i], citekeys: ["a"])
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

/// pull 路徑（`applyBiblatexFields`）也不得把識別碼留在 `fields` 殘留（#425 verify HIGH）。
///
/// 我修了 add-only 的 `enrich`，**姊妹路徑 pull 沒修**——而 pull 是預設的 Zotero
/// 匯入面（`ZoteroImporter` 的新建與更新兩條路徑都呼叫它）。
/// spec（entity-identifier）的「WHEN a work record carries an ISSN THEN the store
/// SHALL treat that as a misplacement」在該路徑上 NOT addressed，
/// 而 `BibExport` 的 `if fields["issn"] == nil` venue 拉取會因此被遮蔽。
final class ZoteroPullIdentifierPlacementTests: XCTestCase {
    private func item(_ fields: [String: String]) -> ZoteroItem {
        ZoteroItem(key: "K", version: 1, libraryID: 1, typeName: "journalArticle",
                   fields: fields, authors: [], tags: [], attachmentPaths: [])
    }

    func testDOIAndISBNGoToStructuredFieldsNotResidue() {
        var e = Entry(id: UUID(), citekey: "x", type: .webpage, title: "")
        ZoteroMapping.applyBiblatexFields(
            from: item(["title": "T", "DOI": "10.1234/abc", "ISBN": "9780306406157"]), to: &e)

        XCTAssertEqual(e.doi.map(\.normalized), ["10.1234/abc"], "識別碼有結構化的家")
        XCTAssertEqual(e.isbn.map(\.normalized), ["9780306406157"])
        XCTAssertNil(e.fields["doi"], "不得留在 fields——同一個值兩份副本可各自漂移")
        XCTAssertNil(e.fields["isbn"])
    }

    /// 解析不出來的**不猜**——原值留在 `fields`，交由既有的殘餘路徑處理。
    func testUnparseableIdentifierStaysInFields() {
        var e = Entry(id: UUID(), citekey: "x", type: .webpage, title: "")
        ZoteroMapping.applyBiblatexFields(from: item(["title": "T", "DOI": "not-a-doi"]), to: &e)

        XCTAssertTrue(e.doi.isEmpty, "解析不出就不填結構化欄位")
        XCTAssertEqual(e.fields["doi"], "not-a-doi", "原值不得丟棄（lossless-intake）")
    }
}

/// venue 的 ISSN 勝過 work 的 `fields` 殘留（#425 verify HIGH）。
extension ZoteroPullIdentifierPlacementTests {
    func testVenueISSNWinsOverTheWorkResidue() throws {
        var v = Venue(key: "j", type: .periodical)
        v.issn = [try XCTUnwrap(ISSN("1554-351X"))]
        var e = Entry(id: UUID(), citekey: "a2020", type: .periodicalArticle, title: "T")
        e.venues = [.key("j")]
        // pull 寫回的殘留——寫法未正規化，而且它是**過渡態**
        e.fields["issn"] = "1554351X"

        let bib = BibExport.bibEntry(for: e, people: [:], venues: ["j": v])

        XCTAssertEqual(bib.fields["issn"], "1554-351X",
                       "識別碼住在它所識別的實體上——venue 的那個才是正典；"
                       + "work 的殘留是等 migrate-identifiers 搬走的過渡態")
    }

    /// venue 沒有號時退回殘留——那時它是唯一的來源。
    func testResidueIsUsedWhenTheVenueHasNoISSN() throws {
        let v = Venue(key: "j", type: .periodical)
        var e = Entry(id: UUID(), citekey: "a2020", type: .periodicalArticle, title: "T")
        e.venues = [.key("j")]
        e.fields["issn"] = "1554-351X"

        let bib = BibExport.bibEntry(for: e, people: [:], venues: ["j": v])
        XCTAssertEqual(bib.fields["issn"], "1554-351X", "唯一來源不得被丟掉")
    }
}

/// pull 對識別碼必須**跟隨上游**，而移除要可見（#394 verify R4 ④）。
extension ZoteroPullIdentifierPlacementTests {
    /// Zotero 這次沒給 → 結構化識別碼要清掉。
    ///
    /// 修改**之前** DOI 住 `fields`，整份替換讓它消失，`fieldsRemovedByPull` 記得到；
    /// 把它提升進結構化欄位之後**沒有補 else 分支**，於是它變成「有就跟隨、沒有就保留」
    /// ——既不是 follow 也不是 preserve，而且沒有一行程式碼說這是刻意的。
    ///
    /// 後果是**過期值會安靜留著**：使用者在 Zotero 清掉一個掛錯篇的 DOI，重跑 pull
    /// 之後 store 仍然帶著它，而 `export-bib` 繼續印、`import-wos` 繼續拿它當身分證。
    func testClearingTheDOIUpstreamClearsItLocally() {
        var e = Entry(id: UUID(), citekey: "a", type: .periodicalArticle, title: "T")
        e.doi = [DOI("10.1037/aaa")!]
        ZoteroMapping.applyBiblatexFields(from: item(["title": "T"]), to: &e)

        XCTAssertTrue(e.doi.isEmpty,
                      "pull 是跟隨上游——Zotero 清掉的值不得在本地安靜留著。"
                      + "這正是提升進結構化欄位**之前**的行為（住 fields 時整份替換會清掉它）")
    }

    /// 上游有值時照常覆寫（跟隨語意的另一半）。
    func testUpstreamValueStillOverwrites() {
        var e = Entry(id: UUID(), citekey: "a", type: .periodicalArticle, title: "T")
        e.doi = [DOI("10.1037/old")!]
        ZoteroMapping.applyBiblatexFields(from: item(["title": "T", "DOI": "10.1037/new"]), to: &e)
        XCTAssertEqual(e.doi.map(\.normalized), ["10.1037/new"])
    }
}

/// 上游「給了但讀不懂」不得與「沒給」折成同一件事（#394 verify R5 ①）。
extension ZoteroPullIdentifierPlacementTests {
    /// **Zotero 把多個 ISBN 塞在同一個字串裡**，而 `ISBN.init` 對它必然回 nil
    /// （`idCompact` 後長度既非 10 也非 13）。R4 的翻轉把那個 nil 當成「上游清空了」，
    /// 於是 `migrate-identifiers` 剛拆出來的兩個結構化號被扔掉。
    ///
    /// 實測受害者 2 筆（`dweck2000social` 精裝／平裝、`kelley2023sample`），皆來自 Zotero。
    ///
    /// 正確的狀態有**三個**不是兩個：上游沒給 → 清空；給了且讀得懂 → 取代；
    /// **給了但讀不懂 → 保留既有值**（那是我們的解析能力不足，不是上游的意思）。
    func testAnUnparseableUpstreamStringDoesNotWipeStructuredISBNs() {
        var e = Entry(id: UUID(), citekey: "k", type: .book, title: "T")
        e.isbn = [ISBN("9781433837135")!, ISBN("9781433841323")!]
        // Zotero 的真實形狀：多個號空白分隔在同一個欄位
        ZoteroMapping.applyBiblatexFields(
            from: item(["title": "T", "ISBN": "978-1-4338-3713-5 978-1-4338-4132-3"]), to: &e)

        XCTAssertEqual(e.isbn.count, 2,
                       "上游那個字串**含有**這兩個號——讀不懂它是我們的解析限制，"
                       + "不是上游說「這本書沒有 ISBN」。把兩者折成同一個分支會安靜刪資料")
    }

    /// 上游真的沒給時仍然清空（跟隨語意的那一半不得被本修復弄壞）。
    func testAbsentUpstreamStillClearsISBN() {
        var e = Entry(id: UUID(), citekey: "k", type: .book, title: "T")
        e.isbn = [ISBN("9781433837135")!]
        ZoteroMapping.applyBiblatexFields(from: item(["title": "T"]), to: &e)
        XCTAssertTrue(e.isbn.isEmpty, "沒給就是清空——R4 修的那件事仍然成立")
    }
}

/// 第三態不得把上游那個讀不懂的字串刪掉（#394 verify R6 ③）。
extension ZoteroPullIdentifierPlacementTests {
    /// R5 的註解逐字寫著「原字串仍留在 `fields`,資訊零損失」——**那句話只在
    /// `existing` 為空時為真**。移除迴圈問的是「結構化欄位現在空不空」，而第三態
    /// 剛把 `existing` 填回去了,於是上游那個讀不懂的字串被一併刪除。
    ///
    /// 三件事同時成立:資訊損失（且是相對 main 的**回歸**——遷移前它住 `fields`,
    /// 整份替換之後仍在）、零回報、留下的是**過期識別碼**（而識別碼終結指涉）。
    func testAnUnparseableUpstreamStringSurvivesInFields() {
        var e = Entry(id: UUID(), citekey: "k", type: .periodicalArticle, title: "T")
        e.doi = [DOI("10.1037/old")!]
        ZoteroMapping.applyBiblatexFields(
            from: item(["title": "T", "DOI": "10.1037/new (in press)"]), to: &e)

        XCTAssertEqual(e.doi.map(\.normalized), ["10.1037/old"], "既有值保留（R5 已修的那半）")
        XCTAssertEqual(e.fields["doi"], "10.1037/new (in press)",
                       "**上游那個字串必須留在 fields**——我們讀不懂它不等於它不存在。"
                       + "刪掉它是 lossless-intake 禁止的靜默丟棄,而且留下的是過期識別碼")
    }
}

/// 部分成功不得移除殘留（#394 verify R7 ①）。
extension ZoteroPullIdentifierPlacementTests {
    /// **借了 tokenizer，沒借它的紀律。** `IdentifierMigration` 對同一個形狀有明文裁決：
    ///
    /// > 只要有任何一個 bad，就**不移除殘留**——殘留是那些解不了的值唯一的棲身處。
    ///
    /// 而 `followUpstream` 用 `.values` 把 `unparseable` 整個丟掉，於是「一個 token
    /// 解得出、另一個解不出」時 `parsed` 為 true，呼叫端把**整個原字串**移出 `fields`
    /// ——解不出的那個號從 store 徹底消失，且零回報。
    ///
    /// 兩者的差別還在於**頻率**：`migrate-identifiers` 只跑一次，`import-zotero` 是
    /// 預設的匯入面，新建與更新兩條路徑都走這裡。
    func testPartialParseKeepsTheResidueString() {
        var e = Entry(id: UUID(), citekey: "k", type: .book, title: "T")
        // 精裝可解、平裝漏一碼不可解
        let raw = "978-1-4338-3216-1 (hardcover) 1-4338-3216 (paperback)"
        ZoteroMapping.applyBiblatexFields(from: item(["title": "T", "ISBN": raw]), to: &e)

        XCTAssertFalse(e.isbn.isEmpty, "解得出的那個號要進結構化欄位")
        XCTAssertEqual(e.fields["isbn"], raw,
                       "**有任何一個 token 解不出就不移除殘留**——那是它唯一的棲身處。"
                       + "IdentifierMigration 對同一個形狀已有明文裁決，這裡不得相反")
    }

    /// 全部解得出時照常移除（紀律的另一半，不得被本修復弄壞）。
    func testFullyParsedRemovesTheResidue() {
        var e = Entry(id: UUID(), citekey: "k", type: .book, title: "T")
        ZoteroMapping.applyBiblatexFields(
            from: item(["title": "T", "ISBN": "9781433837135 9781433841323"]), to: &e)
        XCTAssertEqual(e.isbn.count, 2)
        XCTAssertNil(e.fields["isbn"], "全部解得出 → 殘留沒有存在理由")
    }
}

/// 上游結構上不供給的欄位，不得被「跟隨上游」清空（#394 verify R8）。
extension ZoteroPullIdentifierPlacementTests {
    /// **`fieldMap` 沒有任何一列產生 `pmid`** —— Zotero 的 item schema 沒有 PMID 欄位
    /// （它住 `Extra`，經 `FieldKey.normalized` 收成 `extra`）。於是
    /// `followUpstream(fields["pmid"], …)` 的第一個引數**結構上恆為 nil**，
    /// 走第一個 guard 回 `([], false)`，`entry.pmid` 被設成 `[]`。
    ///
    /// 「跟隨上游」對一個上游永遠不給的欄位，退化成**無條件銷毀**——而且不可逆：
    /// PMID 不在 Zotero 裡，永遠不會從 Zotero 回來。
    ///
    /// 實測 0 筆重疊（536 筆 Zotero 來源、65 筆有 pmid），所以這是**地雷不是現行損害**
    /// ——但它不需要任何人犯錯就會引爆，只需要有人在一筆 Zotero 來源的記錄上補一個 PMID
    /// （`import-wos` 會寫、`akashic-person-verify` 查 Europe PMC 後也會）。
    func testPullDoesNotWipeAFieldZoteroCannotSupply() {
        var e = Entry(id: UUID(), citekey: "k", type: .periodicalArticle, title: "T")
        e.pmid = [PMID("12345678")!]
        ZoteroMapping.applyBiblatexFields(from: item(["title": "T"]), to: &e)

        XCTAssertEqual(e.pmid.map(\.normalized), ["12345678"],
                       "Zotero 沒有 PMID 欄位——它的沉默不是「上游說沒有」，"
                       + "是「上游根本不談這件事」。把兩者折成同一個分支會不可逆地刪資料")
    }

    /// 上游**能**供給的欄位，沉默仍然是清空（跟隨語意不得被本修復弄壞）。
    func testPullStillClearsAFieldZoteroCanSupply() {
        var e = Entry(id: UUID(), citekey: "k", type: .periodicalArticle, title: "T")
        e.doi = [DOI("10.1037/old")!]
        ZoteroMapping.applyBiblatexFields(from: item(["title": "T"]), to: &e)
        XCTAssertTrue(e.doi.isEmpty, "DOI 在 fieldMap 裡——上游沉默＝上游說沒有")
    }
}

/// enrich 的部分成功：訊息說保留就要真的保留（#394 verify R9）。
extension ZoteroEnrichmentTests {
    /// R8 的訊息逐字寫「其餘 token 的形狀不認得；**原字串保留在 fields 供人裁**」
    /// ——那句話描述的是 **pull** 的行為。這段程式碼住在 **enrich**（add-only）路徑，
    /// 那裡 `case "doi","pmid","isbn"` **只 append 訊息、從不寫 `added[k]`**，
    /// 所以那個解析不出的 token 在 enrich 之後**不存在於 store 的任何地方**。
    ///
    /// **比沉默更糟**：丟棄被誤述成保留，使用者讀完會判斷「資料還在、之後再處理」。
    ///
    /// 修法讓那句話變真——部分成功時把原字串真的加進 `fields`（那正是殘留欄位的用途，
    /// 與 pull 一致），而不是改成一句「已丟棄」的誠實訃告。
    func testPartialParseActuallyPreservesTheRawString() throws {
        let raw = "9781433832161 1-4338-3216"          // 第二個 token 只有 9 碼
        let plan = try planWithZoteroISBN(raw)
        guard let a = plan.additions.first else { return XCTFail("應該有一筆 addition") }

        XCTAssertEqual(a.addedISBNs.map { $0.normalized }, ["9781433832161"], "解得出的進結構化欄位")
        XCTAssertEqual(a.addedFields["isbn"], raw,
                       "**原字串必須真的被加進去**——訊息說它保留在 fields，"
                       + "而 enrich 是 add-only,不主動加就等於它消失了")
    }

    /// 部分成功**不是**「刻意不採用」——它不該走 refused 通道。
    func testPartialParseIsNotReportedAsRefused() throws {
        let plan = try planWithZoteroISBN("9781433832161 1-4338-3216")
        guard let a = plan.additions.first else { return XCTFail("應該有一筆 addition") }

        XCTAssertTrue(a.refusedIdentifiers.isEmpty,
                      "`refusedIdentifiers` 的契約是「Zotero 給了識別碼但**刻意不採用**」。"
                      + "部分成功既不是刻意（解析不出是我們的限制）也不是不採用"
                      + "（解出的那些已經採用了）")
        XCTAssertEqual(a.partiallyParsedIdentifiers.count, 1, "它有自己的通道")
    }

    /// 全部解不出時仍走 refused（那一格的語意沒變）。
    func testFullyUnparseableStillRefused() throws {
        let plan = try planWithZoteroISBN("not-an-isbn-at-all")
        // 全部解不出且無其他可補值 → 落 `refusedOnly`（那個分類本來就是為它存在的）。
        guard let a = plan.refusedOnly.first else { return XCTFail("應該落 refusedOnly") }
        XCTAssertEqual(a.refusedIdentifiers.count, 1)
        XCTAssertTrue(a.partiallyParsedIdentifiers.isEmpty)
    }
}

/// 上游若**真的給了** PMID，就該跟隨（#394 verify R9 MEDIUM）。
extension ZoteroPullIdentifierPlacementTests {
    /// R8 的條件寫成「`pmid` 不在 `fieldMap` 裡 ⇒ 不跟隨」，而決定 `fields["pmid"]`
    /// 存不存在的是 **`fieldMap[z] ?? FieldKey.normalized(z)` 兩條路徑**。
    /// `FieldKey.normalized("PMID")` → `"pmid"`，而 `ZoteroReader` 的 SQL 是泛型的
    /// ——Zotero 日後加一個 `PMID` 欄位就會讓它出現，**我方零程式碼改動**。
    ///
    /// 那時舊條件仍然「為真」（fieldMap 確實沒有那一列），於是殘留永不被移除、
    /// 結構化的舊值遮蔽上游的新值，兩面都不會印出也不會有 diagnostic。
    ///
    /// 正確的問法不是「這個欄位在不在對映表裡」，是「**上游這次到底有沒有給值**」。
    func testAnUpstreamPMIDIsFollowedWhenActuallySupplied() {
        var e = Entry(id: UUID(), citekey: "k", type: .periodicalArticle, title: "T")
        e.pmid = [PMID("11111111")!]
        // 走殘餘路徑：`PMID` 不在 fieldMap，經 FieldKey.normalized 收成 `pmid`
        ZoteroMapping.applyBiblatexFields(from: item(["title": "T", "PMID": "22222222"]), to: &e)

        XCTAssertEqual(e.pmid.map(\.normalized), ["22222222"],
                       "上游**給了**值就該跟隨——沉默才是「不談這件事」")
        XCTAssertNil(e.fields["pmid"], "解得出就不留殘留（與 doi／isbn 一致）")
    }

    /// 沉默仍然不清空（R8 修的那件事不得被本修復弄壞）。
    func testSilenceStillDoesNotWipePMID() {
        var e = Entry(id: UUID(), citekey: "k", type: .periodicalArticle, title: "T")
        e.pmid = [PMID("11111111")!]
        ZoteroMapping.applyBiblatexFields(from: item(["title": "T"]), to: &e)
        XCTAssertEqual(e.pmid.map(\.normalized), ["11111111"], "Zotero 沒談 PMID ⇒ 不動")
    }
}
