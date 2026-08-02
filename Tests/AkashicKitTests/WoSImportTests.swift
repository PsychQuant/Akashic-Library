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
            + "Su, YH\tSu, Ying-Hao\tFunctional data\tPsychometrika\t2015\t10.1/abc\n"
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
            + "Su, YH\tSu, Ying-Hao\tOld title\tPsychometrika\t2015\t10.1/abc\n", store: store)
        let r = try WoSImport.run(text: header
            + "Su, YH\tSu, Ying-Hao\tRevised title\tPsychometrika\t2015\t10.1/abc\n", store: store)
        XCTAssertEqual(r.created.count, 0)
        XCTAssertEqual(r.conflicts.count, 1, "同一篇但內容不同 → conflict，不是新增")
    }

    /// **conflict 不覆寫。** citekey 相同、內容不同，可能是使用者手動補過的資料，
    /// 而 WoS 的欄位比 store 的窄——覆寫會把人工資訊洗掉。
    func testConflictDoesNotOverwrite() throws {
        _ = try WoSImport.run(text: header
            + "Su, YH\tSu, Ying-Hao\tT\tPsychometrika\t2015\t10.1/abc\n", store: store)
        var e = try store.load().entries[0]
        e.akashic.tags = ["人工補的"]
        try store.writeEntry(e)
        _ = try WoSImport.run(text: header
            + "Su, YH\tSu, Ying-Hao\tT\tOther Journal\t2015\t10.1/abc\n", store: store)
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
