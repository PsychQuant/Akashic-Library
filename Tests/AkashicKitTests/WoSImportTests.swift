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
