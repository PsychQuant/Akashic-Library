import XCTest
@testable import AkashicCore
@testable import AkashicWoSImport
@testable import AkashicZoteroImport

/// #206 / `.claude/rules/lossless-intake.md`：匯入端不得靜默丟欄位。
///
/// 這一組守的是**規則本身**，不是某個 importer 的細節：來源給的欄位，
/// round-trip 之後要還在。
final class LosslessIntakeTests: XCTestCase {

    // MARK: - FieldKey 正規化（三條規則都是必要的，量過）

    /// `BibExport` 把 `fields` 的鍵**直接**當 biblatex 欄位名印出去，所以不合法的
    /// 鍵不是難看，是產出解析不了的 `.bib`。真 `biber --tool` 量到的三種形狀：
    ///
    /// | 欄位名 | biber |
    /// |---|---|
    /// | `RESEARCH_AREAS` | 0 error |
    /// | `RESEARCH AREAS` | syntax error（`found "AREAS", expected "="`）|
    /// | `29_CHARACTER_ABBREV` | syntax error（數字開頭）|
    func testNormalizationProducesLegalBiblatexFieldNames() {
        XCTAssertEqual(FieldKey.normalized("Research Areas"), "research_areas")
        XCTAssertEqual(FieldKey.normalized("WoS Categories"), "wos_categories")
        // 數字開頭要補前綴——WoS 真的有一欄叫 `29 Character Source Abbreviation`
        XCTAssertEqual(FieldKey.normalized("29 Character Source Abbreviation"),
                       "x29_character_source_abbreviation")
        // 連續非英數收斂成一個底線，頭尾不留
        XCTAssertEqual(FieldKey.normalized("  Foo -- Bar!  "), "foo_bar")
        // 已經合法的原樣（小寫化）
        XCTAssertEqual(FieldKey.normalized("doi"), "doi")
    }

    /// 空鍵**不可表達**，回 nil 而不是空字串——壓成 `""` 會讓「無法表達的欄位名」
    /// 與「某個真的值」在 `fields[""]` 裡合流。
    func testUnrepresentableKeyIsNilNotEmpty() {
        XCTAssertNil(FieldKey.normalized(""))
        XCTAssertNil(FieldKey.normalized("   "))
        XCTAssertNil(FieldKey.normalized("---"))
    }

    /// **產出必須是合法 biblatex 欄位名**：字母開頭 + 只有英數與底線。
    /// 這條是性質而非例子——任何輸入都要滿足。
    func testNormalizedOutputIsAlwaysALegalFieldName() {
        for raw in ["Research Areas", "29 Char", "!!!x!!!", "中文欄位 A",
                    "Times Cited, WoS Core", "a.b.c", "UPPER_CASE"] {
            guard let k = FieldKey.normalized(raw) else { continue }
            XCTAssertTrue(k.first?.isLetter == true,
                          "\(raw.debugDescription) → \(k)：必須字母開頭（數字開頭 biber 報 syntax error）")
            XCTAssertTrue(k.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" },
                          "\(raw.debugDescription) → \(k)：只能有英數與底線（空格 biber 報 syntax error）")
            XCTAssertFalse(k.hasSuffix("_"), "\(k) 不得以底線結尾")
        }
    }

    // MARK: - WoS 殘餘收集

    private func wosRow(_ extra: [String: String] = [:]) -> [String: String] {
        var r = ["Authors": "Cheng, Che", "Article Title": "T",
                 "Publication Year": "2025", "DOI": "10.1/x"]
        for (k, v) in extra { r[k] = v }
        return r
    }

    /// 通報的形狀：不在對映表上的欄位不得消失。
    func testWoSKeepsUnmappedColumns() throws {
        let e = try XCTUnwrap(WoSImport.entry(
            from: wosRow(["Research Areas": "Psychology",
                          "Conference Title": "IMPS 2025",
                          "Funding Orgs": "NSTC"]),
            taken: []))
        XCTAssertEqual(e.fields["research_areas"], "Psychology")
        XCTAssertEqual(e.fields["conference_title"], "IMPS 2025")
        XCTAssertEqual(e.fields["funding_orgs"], "NSTC")
        // 對映的欄位照舊
        XCTAssertEqual(e.fields["doi"], "10.1/x")
    }

    /// 空值不佔位——`fields` 裡的空字串在 export 會變成 `FOO = {}`，
    /// 那是雜訊不是資訊。
    func testWoSSkipsEmptyValues() throws {
        let e = try XCTUnwrap(WoSImport.entry(from: wosRow(["Research Areas": ""]), taken: []))
        XCTAssertNil(e.fields["research_areas"])
    }

    /// **殘餘不得覆寫語意對映。** `pages` 是 start--end 合成的，若某個殘餘欄位
    /// 正規化後也叫 `pages`，語意的那份要勝出。
    func testResidualDoesNotOverwriteMappedField() throws {
        let e = try XCTUnwrap(WoSImport.entry(
            from: wosRow(["Start Page": "1", "End Page": "9", "Pages": "SHOULD-NOT-WIN"]),
            taken: []))
        XCTAssertEqual(e.fields["pages"], "1--9", "語意對映必須勝出")
    }

    /// **`consumedColumns` 與實際對映不得分岔。** 這是殘餘收集唯一的維護風險：
    /// 漏宣告一個已對映的欄位 → 它會被收兩次（一次語意、一次原樣殘餘）。
    ///
    /// 檢查方式是行為的，不是讀程式碼：對每個宣告的欄位餵一個**可辨識的**值，
    /// 斷言那個值在 `fields` 裡**最多出現一次**。
    ///
    /// **判準是「不重複」而不是「不以正規化原名出現」**——第一版寫成後者，被自己
    /// 測出來是假陽性：`DOI` 正規化後就是 `doi`，與它的對映目標同名，所以「以
    /// `doi` 為鍵」無法區分它來自對映還是殘餘，且那種情況本來就無害（同鍵、
    /// 同值、`fields[key] != nil` 的守衛讓對映勝出）。
    ///
    /// 真正的危害是**對映目標與原名不同**的那些：`Source Title` → `journaltitle`、
    /// `Issue` → `number`、`Start/End Page` → `pages`。漏宣告的話同一個值會同時
    /// 出現在 `journaltitle` 與 `source_title` 兩個鍵下——那才是分岔的可觀察形狀。
    /// **餵的清單獨立寫死，不枚舉 `WoSImport.consumedColumns`。** 第一版枚舉它，
    /// mutation 實測是**自我指涉**：從 `consumedColumns` 拿掉 `Source Title` 之後，
    /// 迴圈就不再餵那一欄，於是「漏宣告」這件事自己把驗它的測試一起刪掉——兩個
    /// mutation 全綠。本檔所在的 repo 對 `taintedTokens` 已記過同一個坑。
    static let wosMappedColumns = [
        "Authors", "Author Full Names", "Article Title", "Publication Year",
        "Publication Date", "Source Title", "Volume", "Issue", "DOI",
        "Start Page", "End Page", "Group Authors",
    ]

    func testEveryConsumedColumnIsDeclared() throws {
        for column in Self.wosMappedColumns {
            var row = wosRow()
            let sentinel = "SENTINEL-\(column)"
            row[column] = sentinel
            guard let e = WoSImport.entry(from: row, taken: []) else { continue }
            let hits = e.fields.filter { $0.value.contains(sentinel) }.keys.sorted()
            XCTAssertLessThanOrEqual(hits.count, 1,
                "「\(column)」的值同時出現在 \(hits)——consumedColumns 與實際對映分岔了")
        }
    }

    /// 兩份清單的**集合相等**：獨立寫死的那份與 source 的 `consumedColumns`。
    ///
    /// 上一條抓「宣告漏了」，這條抓**反向**——有人加了新的具名對映並宣告，卻沒有
    /// 同步更新測試的餵料清單，於是新對映永遠不被上一條檢查。兩條合起來才把
    /// 補集釘死。
    func testDeclaredSetMatchesTheIndependentList() {
        XCTAssertEqual(WoSImport.consumedColumns, Set(Self.wosMappedColumns),
                       "consumedColumns 與測試的獨立清單分岔——新增對映時兩邊都要改")
    }

    /// 反向：**沒宣告的欄位一定要進殘餘**。這條與上一條合起來把補集釘死。
    func testUndeclaredColumnAlwaysLandsInResidual() throws {
        let novel = "Some Column WoS Adds In 2027"
        let e = try XCTUnwrap(WoSImport.entry(from: wosRow([novel: "v"]), taken: []))
        XCTAssertEqual(e.fields[try XCTUnwrap(FieldKey.normalized(novel))], "v",
                       "未來新增的欄位必須自動被收——這正是本規則的重點")
    }

    // MARK: - Zotero 殘餘收集

    /// Zotero 的 item 依 type 有幾十種欄位，`fieldMap` 涵蓋不到的原本全部消失
    /// （那行 `guard let bibField = fieldMap[zField] else { continue }`）。
    func testZoteroKeepsUnmappedFields() {
        var entry = Entry(id: UUID(), citekey: "z1", type: "misc", title: "")
        let item = ZoteroItem(
            key: "K1", version: 1, libraryID: 1, typeName: "presentation",
            fields: ["title": "T", "date": "2025",
                     "presentationType": "Oral", "meetingName": "IMPS 2025",
                     "place": "Seoul"],
            authors: [], tags: [], attachmentPaths: [])
        ZoteroMapping.applyBiblatexFields(from: item, to: &entry)
        XCTAssertEqual(entry.fields["presentationtype"], "Oral")
        XCTAssertEqual(entry.fields["meetingname"], "IMPS 2025")
        XCTAssertNotNil(entry.fields["place"] ?? entry.fields["location"],
                        "place 不論走 fieldMap 或殘餘，都不得消失")
    }

    /// title／date 已抽成一級欄位，不得同時留在 `fields` 裡重複。
    func testZoteroDoesNotDuplicateTitleAndDate() {
        var entry = Entry(id: UUID(), citekey: "z2", type: "misc", title: "")
        let item = ZoteroItem(key: "K2", version: 1, libraryID: 1, typeName: "journalArticle",
                              fields: ["title": "T", "date": "2025"],
                              authors: [], tags: [], attachmentPaths: [])
        ZoteroMapping.applyBiblatexFields(from: item, to: &entry)
        XCTAssertEqual(entry.title, "T")
        XCTAssertNil(entry.fields["title"])
        XCTAssertNil(entry.fields["date"])
    }
}
