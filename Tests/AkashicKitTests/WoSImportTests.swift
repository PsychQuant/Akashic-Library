import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicWoSImport

/// #21：WoS 匯出 → entries。
final class WoSImportTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    private let header = "Authors\tAuthor Full Names\tArticle Title\tSource Title\tPublication Year\tDOI\n"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-wos-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    // MARK: - 日期（#598）

    /// WoS 的 `Publication Date` 有兩種形：只有月日（`FEB`、`JUL 9`）與已含年（`2026 JUN 1`）。
    /// 前者要前綴 `Publication Year`，後者**不能**再前綴——否則年份出現兩次（實例：
    /// ISS 100 篇裡 4 筆 `2026 2026 JUN 1`）。
    func testPublicationDateAlreadyContainingYearIsNotPrefixedAgain() throws {
        let tsv = "Authors\tAuthor Full Names\tArticle Title\tPublication Year\tPublication Date\tDOI\n"
            + "Lin, A\tLin, Ann\tOne\t2026\t2026 JUN 1\t10.1/one\n"
            + "Lin, B\tLin, Bob\tTwo\t2025\tJUL 9\t10.1/two\n"
            + "Lin, C\tLin, Cat\tThree\t2026\tFEB\t10.1/three\n"
        _ = try WoSImport.run(text: tsv, store: store)
        let dates = Dictionary(uniqueKeysWithValues: try store.load().entries.map { ($0.title, $0.date) })
        XCTAssertEqual(dates["One"], "2026 JUN 1", "Date 已含年就照原樣")
        XCTAssertEqual(dates["Two"], "2025 JUL 9")
        XCTAssertEqual(dates["Three"], "2026 FEB")
    }

    /// #598 Expected 的第二半：Date 自帶的年與 Publication Year 不一致時，date 以 Date 為準，但 Publication Year
    /// 的原值不得靜默消失（它在 `consumedColumns` 裡、不進殘餘收集——`lossless-intake`）。一致時不另存。
    func testDisagreeingPublicationYearIsKeptWhenDateCarriesItsOwnYear() throws {
        let tsv = "Authors\tAuthor Full Names\tArticle Title\tPublication Year\tPublication Date\tDOI\n"
            + "Lin, A\tLin, Ann\tOne\t2025\t2026 JUN 1\t10.1/one\n"
            + "Lin, B\tLin, Bob\tTwo\t2026\t2026 JUN 1\t10.1/two\n"
        _ = try WoSImport.run(text: tsv, store: store)
        let byTitle = Dictionary(uniqueKeysWithValues: try store.load().entries.map { ($0.title, $0) })
        XCTAssertEqual(byTitle["One"]?.date, "2026 JUN 1", "Date 內的年為準")
        XCTAssertEqual(byTitle["One"]?.fields["publication_year"], "2025", "不一致的 Publication Year 原值留下")
        XCTAssertNil(byTitle["Two"]?.fields["publication_year"], "一致時沒有資訊可留，不另存")
    }

    // MARK: - alias 配對（本 importer 的真正價值）

    /// 兩欄**同 index 對齊**，每位作者免費得到兩種寫法。這補掉
    /// `PersonResolver.normalize()` 不重排 `Last, First`、不去連字號的弱點。
    func testAliasPairingFromTwoColumns() {
        let g = WoSImport.aliasGroups(abbreviated: "Su, YH; Chiou, JM",
                                      full: "Su, Ying-Hao; Chiou, Jeng-Min")
        XCTAssertEqual(g, [["Su, YH", "Su, Ying-Hao"], ["Chiou, JM", "Chiou, Jeng-Min"]])
    }

    /// **長度不同時不猜對齊。** 強行對齊會把 A 的縮寫配到 B 的全名上，產生一條錯的
    /// alias——而錯的 alias 會讓 `PersonResolver` 把兩個人合成一個。
    func testMismatchedLengthsDoNotFabricateAliases() {
        let g = WoSImport.aliasGroups(abbreviated: "Su, YH; Chiou, JM; Lin, A",
                                      full: "Su, Ying-Hao")
        XCTAssertEqual(g, [["Su, YH", "Su, Ying-Hao"], ["Chiou, JM"], ["Lin, A"]],
                       "多出來的必須各自成組，不得跨位配對")
    }

    func testIdenticalFormsCollapseToOne() {
        XCTAssertEqual(WoSImport.aliasGroups(abbreviated: "Cheng, Che", full: "Cheng, Che"),
                       [["Cheng, Che"]])
    }

    // MARK: - 冪等（issue 明列的要求 5）

    /// **身分判準必須先於碰撞避讓。** 順序反了就不 idempotent：先避讓的話重跑時
    /// 「基底 citekey 已被自己上次匯入佔用」會生出 `su2015bfunctional`，每跑一次多一份。
    func testRerunProducesNoDuplicates() throws {
        let tsv = header
            + "Su, YH\tSu, Ying-Hao\tFunctional data\tPsychometrika\t2015\t10.1234/abc\n"
            + "Cheng, C\tCheng, Che\tIdentifiability\tPsychometrika\t2025\t\n"
        let first = try WoSImport.run(text: tsv, store: store)
        XCTAssertEqual(first.created.count, 2)
        let second = try WoSImport.run(text: tsv, store: store)
        XCTAssertEqual(second.created.count, 0, "重跑不得新增")
        XCTAssertEqual(second.unchanged.count, 2)
        XCTAssertEqual(try store.load().entries.count, 2)
    }

    /// 身分用 **DOI 優先**——citekey 是衍生的稱呼，拿它當身分正是上面那個 bug 的來源。
    /// 同一個 DOI 即使標題微調也是同一篇。
    func testDOIIsIdentityEvenWhenTitleChanges() throws {
        _ = try WoSImport.run(text: header
            + "Su, YH\tSu, Ying-Hao\tOld title\tPsychometrika\t2015\t10.1234/abc\n", store: store)
        let r = try WoSImport.run(text: header
            + "Su, YH\tSu, Ying-Hao\tRevised title\tPsychometrika\t2015\t10.1234/abc\n", store: store)
        XCTAssertEqual(r.created.count, 0)
        XCTAssertEqual(r.conflicts.count, 1, "同一篇但內容不同 → conflict，不是新增")
    }

    /// **conflict 不覆寫。** citekey 相同、內容不同，可能是使用者手動補過的資料，
    /// 而 WoS 的欄位比 store 的窄——覆寫會把人工資訊洗掉。
    func testConflictDoesNotOverwrite() throws {
        _ = try WoSImport.run(text: header
            + "Su, YH\tSu, Ying-Hao\tT\tPsychometrika\t2015\t10.1234/abc\n", store: store)
        var e = try store.load().entries[0]
        e.akashic.tags = ["人工補的"]
        try store.writeEntry(e)
        _ = try WoSImport.run(text: header
            + "Su, YH\tSu, Ying-Hao\tT\tOther Journal\t2015\t10.1234/abc\n", store: store)
        XCTAssertEqual(try store.load().entries[0].akashic.tags, ["人工補的"], "人工資料被洗掉")
    }

    // MARK: - 不自動歸戶（本 repo 的鐵律）

    func testAuthorsAreAllLiteral() throws {
        _ = try WoSImport.run(text: header
            + "Su, YH\tSu, Ying-Hao\tT\tJ\t2015\t\n", store: store)
        let authors = try store.load().entries[0].authors
        XCTAssertEqual(authors.count, 1)
        guard case .literal = authors[0] else {
            return XCTFail("作者必須全部是 .literal——歸戶交給 PersonResolver + 裁決台")
        }
    }

    /// 團體作者以 #6 的大括號標記，不讓 export 切成 "Organization, World Health"。
    func testGroupAuthorsAreMarkedAsCorporate() throws {
        let tsv = "Authors\tAuthor Full Names\tArticle Title\tPublication Year\tGroup Authors\n"
            + "Su, YH\tSu, Ying-Hao\tT\t2015\tWorld Health Organization\n"
        _ = try WoSImport.run(text: tsv, store: store)
        let authors = try store.load().entries[0].authors
        XCTAssertEqual(authors.count, 2)
        guard case let .literal(g) = authors[1] else { return XCTFail() }
        XCTAssertTrue(CorporateName.isMarked(g), g)
    }

    // MARK: - 解析

    /// 書目 title 常含逗號與引號——CSV 模式必須走 RFC 4180。
    func testCSVQuotedFieldsWithCommas() {
        let rows = WoSImport.rows(
            from: "Authors,Article Title\n\"Su, YH\",\"A title, with comma and \"\"quotes\"\"\"\n",
            separator: ",")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["Authors"], "Su, YH")
        XCTAssertEqual(rows[0]["Article Title"], #"A title, with comma and "quotes""#)
    }

    func testBlankRowsAreSkipped() {
        XCTAssertEqual(WoSImport.rows(from: header + "\t\t\t\t\t\n").count, 0)
    }

    /// #89：**行尾不得改變解析結果**。WoS 從 Windows 匯出的 tab-delimited 檔原生是
    /// CRLF，而 Swift 的 `String` 以 grapheme cluster 迭代——`"\r\n"` 是**單一**
    /// `Character`，既不等於 `"\r"` 也不等於 `"\n"`。逐 `Character` 比對換行的解析器
    /// 會把整份檔案吞成一個 field，回報 created 0 而不報錯。
    ///
    /// 斷言寫成「LF 與 CRLF 必須等價」而非釘住某個 fixture：這條性質比任何單一
    /// 樣本都難被未來的重構繞過。
    func testLineEndingsDoNotChangeParsing() {
        let lf = header + "Chen, CH\tChen-Hsin Chen\tDiagnostic Plots\tBiometrics\t1991\t10.2307/2532643\n"
        let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
        let a = WoSImport.rows(from: lf), b = WoSImport.rows(from: crlf)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(b.count, a.count, "CRLF 解析出 \(b.count) 列、LF 解析出 \(a.count) 列")
        XCTAssertEqual(b.first?["Article Title"], "Diagnostic Plots")
        XCTAssertEqual(b.first?["DOI"], "10.2307/2532643")
        XCTAssertEqual(b.first?["Publication Year"], "1991")
    }

    /// 舊 Mac 的單獨 `\r` 行尾原本就被當成「丟掉」——修 CRLF 不得把它變成分列。
    func testBareCarriageReturnStillDropped() {
        let rows = WoSImport.rows(from: "Authors\tArticle Title\nA, B\tTi\rtle\n")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["Article Title"], "Title")
    }

    /// header 解析成功但一列資料都沒有 → **必須說出來**，不能與「匯入成功但 0 筆」
    /// 在輸出上無法區分（#89 的真正傷害是靜默，不只是解析錯）。
    func testHeaderOnlyFileIsReportedNotSilent() throws {
        let r = try WoSImport.run(text: header, store: store)
        XCTAssertEqual(r.created.count, 0)
        let msg = try XCTUnwrap(r.skippedRows.first, "只有表頭的檔案必須留下訊息")
        XCTAssertTrue(msg.contains("表頭"), msg)
    }

    /// 缺第一作者或年份 → **skip 並說出是哪一列**，不靜默丟掉。
    func testUnusableRowIsReportedNotSilentlyDropped() throws {
        let r = try WoSImport.run(text: header + "\t\tNo author\tJ\t2020\t\n", store: store)
        XCTAssertEqual(r.created.count, 0)
        XCTAssertEqual(r.skippedRows.count, 1)
        XCTAssertTrue(r.skippedRows[0].contains("第 2 列"), r.skippedRows[0])
    }

    func testDryRunWritesNothing() throws {
        let r = try WoSImport.run(text: header
            + "Su, YH\tSu, Ying-Hao\tT\tJ\t2015\t\n", store: store, dryRun: true)
        XCTAssertEqual(r.created.count, 1)
        XCTAssertEqual(try store.load().entries.count, 0)
    }
}

/// 身分判準改讀 `canonicalDOIs` 之後的**行為改變**（#394 verify）——記錄下來，
/// 不假裝沒發生。
///
/// 舊實作比的是 `fields["doi"]` 的**原始字串**，所以任何非空字串都算「有 DOI」；
/// 新實作要求該字串解析得出 `DOI`（`10.<≥4 碼註冊者>/<後綴>`）。實測真實 store 有
/// **3 筆**解析不出的殘留（`DOI 10.1037/h0077149`、`Doi 10.1037//…`、以及一筆把
/// 附錄 DOI 黏在後面的），它們因此退回 (標題, 年份) 判準。
///
/// **這不是回歸**：舊實作對同樣那 3 筆也配不上（庫內鍵是 `doi:doi 10.1037/…`、
/// 從 WoS 列來的 probe 是 `doi:10.1037/…`，兩側一樣對不上）。差別只在**退路**——
/// 舊的沒有退路直接新增，新的還會試一次標題比對。
extension WoSImportTests {
    func testUnparseableDOIResidueFallsBackToTitleYear() throws {
        // 庫內先放一筆殘留形狀不合法的記錄
        var e = Entry(id: UUID(), citekey: "su2015functional",
                      type: .periodicalArticle, title: "Functional data")
        e.date = "2015"
        e.fields["doi"] = "DOI 10.1234/abc"          // 帶標籤前綴 → DOI.init 解析失敗
        _ = try store.writeEntry(e)

        // 同標題同年的一列進來：DOI 對不上（庫內那筆的 canonicalDOIs 是空的），
        // 但 probe 自己帶 DOI，所以**不退回標題比對**——DOI 說「不是同一筆」就不是。
        let r = try WoSImport.run(text: header
            + "Su, YH\tSu, Ying-Hao\tFunctional data\tPsychometrika\t2015\t10.1234/abc\n",
            store: store)
        XCTAssertEqual(r.created.count, 1,
                       "probe 帶得出 DOI 而庫內那筆帶不出——判為不同筆。"
                       + "退回標題比對會讓兩篇同題同年而 DOI 不同的論文被誤判成同一筆")
    }
}

/// 遷移之後重跑同一份 WoS 檔，必須仍是 `unchanged`（#425 verify HIGH）。
///
/// ## 這組測試防的是什麼
///
/// `Entry` 是**合成** Equatable，而 #394 給它加了 `doi`／`pmid`／`isbn`／`references`
/// 四個儲存屬性。`entry(from: row)` 只寫 `fields["doi"]`——probe 的結構化欄位**恆為空**。
///
/// 於是對一筆已遷移的記錄（結構化 `doi` 非空、`fields.doi` 已移除）：
/// `a == b` 為假 → 走回填 → 最終 `mergedCheck == probeCheck` **必然為假** → 落 conflicts。
/// 而 conflict 路徑刻意不覆寫，所以 `enriched` 回填**此後永遠不會再 fire**：
/// WoS 日後新增的任何欄位都補不進去，`lossless-intake` 的「規則要及於已匯入的記錄」
/// 對全庫 664 筆帶 DOI 的 work 失效。
///
/// **這是 #206 verify H1 修過的同一個形狀，被 #394 的結構化欄位原封不動重新裝填。**
///
/// 既有的三支 idempotency 測試對它是盲的：它們都在**同一次 run** 內建檔＋重跑，
/// 結構化欄位全程為空。
extension WoSImportTests {

    /// 把一筆記錄手動改成「遷移後」的形狀：結構化 `doi` 有值、`fields.doi` 移除。
    private func migrateInPlace(_ citekey: String) throws {
        var e = try XCTUnwrap(try store.load().entries.first { $0.citekey == citekey })
        let raw = try XCTUnwrap(e.fields["doi"])
        e.doi = [try XCTUnwrap(DOI(raw))]
        e.fields.removeValue(forKey: "doi")
        _ = try store.writeEntry(e)
    }

    func testReimportAfterMigrationIsStillUnchanged() throws {
        let tsv = header
            + "Su, YH\tSu, Ying-Hao\tFunctional data\tPsychometrika\t2015\t10.1234/abc\n"
        let first = try WoSImport.run(text: tsv, store: store)
        XCTAssertEqual(first.created.count, 1)

        try migrateInPlace("su2015functional")

        let second = try WoSImport.run(text: tsv, store: store)
        XCTAssertEqual(second.conflicts, [],
                       "遷移之後重跑不得變成 conflict——conflict 路徑不覆寫，"
                       + "於是 enriched 回填此後永遠不會再 fire")
        XCTAssertEqual(second.unchanged, ["su2015functional"])
        XCTAssertEqual(second.created.count, 0)
    }

    /// 重跑**不得**把 `fields.doi` 殘留種回去——那是 migrate-identifiers 剛移除的。
    ///
    /// 與 `enrich-from-zotero` 的同一條紀律（#394）：識別碼有結構化的家之後，
    /// 回填路徑不得繞道 `fields` 把它種回來。
    func testReimportDoesNotResurrectTheFieldsResidue() throws {
        let tsv = header
            + "Su, YH\tSu, Ying-Hao\tFunctional data\tPsychometrika\t2015\t10.1234/abc\n"
        _ = try WoSImport.run(text: tsv, store: store)
        try migrateInPlace("su2015functional")

        _ = try WoSImport.run(text: tsv, store: store)

        let after = try XCTUnwrap(try store.load().entries.first { $0.citekey == "su2015functional" })
        XCTAssertNil(after.fields["doi"],
                     "殘留一旦被種回來，同一個值就有兩份副本可各自漂移")
        XCTAssertEqual(after.doi.map(\.normalized), ["10.1234/abc"], "結構化值必須完好")
    }
}
