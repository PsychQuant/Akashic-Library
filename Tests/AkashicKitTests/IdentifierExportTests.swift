import XCTest
@testable import AkashicCore
@testable import AkashicExport

/// #394 §7：匯出面——結構化識別碼勝過 `fields` 裡的同名殘留。
///
/// **這一節防的是一個安靜的失敗。** 遷移把 `doi` 從 `Entry.fields` 搬進結構化欄位之後，
/// `BibExport` 對自由字典的逐鍵轉出就不再輸出它——而 `.bib` 少一個欄位**不會報錯**：
/// LaTeX 照樣編得過，只是參考文獻少了 DOI。這正是 `apa7-is-the-work-floor` 記過的
/// 「語法正確性與書目正確性是兩件事」。
///
/// 形狀比照 #335 的學位論文欄位：在 `fields` 迴圈**之後**寫，所以後者覆蓋前者。
final class IdentifierExportTests: XCTestCase {

    private func entry(doi: [DOI] = [], pmid: [PMID] = [], isbn: [ISBN] = [],
                       fields: [String: String] = [:]) -> Entry {
        var e = Entry(id: UUID(), citekey: "smith2020", type: .periodicalArticle,
                      title: "A title", fields: fields)
        e.doi = doi; e.pmid = pmid; e.isbn = isbn
        return e
    }

    func testStructuredDOIWinsOverTheResidueInFields() throws {
        let e = entry(doi: [try XCTUnwrap(DOI("10.1037/0003-066X.59.1.29"))],
                      fields: ["doi": "10.0000/stale"])
        let bib = BibExport.bibEntry(for: e, people: [:])
        XCTAssertEqual(bib.fields["doi"], "10.1037/0003-066x.59.1.29",
                       "結構化值是正典——殘留不得勝出。**值是正規形**：DOI 依規格是"
                       + "case-insensitive，`DOI.normalized` 整串轉小寫")
    }

    func testAllThreeWorkIdentifiersAreEmitted() throws {
        let e = entry(doi: [try XCTUnwrap(DOI("10.1037/0003-066X.59.1.29"))],
                      pmid: [try XCTUnwrap(PMID("12345678"))],
                      isbn: [try XCTUnwrap(ISBN("978-0-306-40615-7"))])
        let bib = BibExport.bibEntry(for: e, people: [:])
        XCTAssertEqual(bib.fields["doi"], "10.1037/0003-066x.59.1.29")
        XCTAssertEqual(bib.fields["pmid"], "12345678")
        XCTAssertNotNil(bib.fields["isbn"])
    }

    /// **寫出的是正規形**——磁碟上可能是非正規形，但 `.bib` 是給下游排版用的。
    func testEmittedValueIsTheNormalForm() throws {
        let e = entry(isbn: [try XCTUnwrap(ISBN("978-0-306-40615-7"))])
        XCTAssertEqual(BibExport.bibEntry(for: e, people: [:]).fields["isbn"],
                       try XCTUnwrap(ISBN("978-0-306-40615-7")).normalized)
    }

    /// 多值時以**逗號分隔**——一筆 work 真的可以有多個 DOI（實測 37 組同題同年而 DOI
    /// 不同）。丟掉其餘的等於丟掉一次身分判定。
    func testMultipleIdentifiersAreAllEmitted() throws {
        let e = entry(doi: [try XCTUnwrap(DOI("10.1111/aaa")),
                            try XCTUnwrap(DOI("10.2222/bbb"))])
        let out = try XCTUnwrap(BibExport.bibEntry(for: e, people: [:]).fields["doi"])
        XCTAssertTrue(out.contains("10.1111/aaa") && out.contains("10.2222/bbb"),
                      "多值不得只留一個：\(out)")
    }

    /// **沒有結構化值時不得覆蓋殘留**——遷移前的記錄只有 `fields.doi`，
    /// 而那時 export 必須照舊輸出它，否則升級 binary 就會讓所有 DOI 從 .bib 消失。
    func testResidueSurvivesWhenThereIsNoStructuredValue() {
        let e = entry(fields: ["doi": "10.0000/only-residue"])
        XCTAssertEqual(BibExport.bibEntry(for: e, people: [:]).fields["doi"], "10.0000/only-residue")
    }

    // MARK: - ISSN 搬到 venue 之後，.bib 仍須輸出它（遷移後實測抓到的回歸）

    /// **design.md 的 Risks 段預言過這件事，而 §7 的 mitigation 漏掉了 issn。**
    ///
    /// > [export 靜默少欄位] 把 `doi` 搬出 `Entry.fields` 後，`BibExport` 對自由字典的
    /// > 逐鍵轉出不再輸出它，而 `.bib` 少一個欄位**不會報錯**
    ///
    /// §7 對 `doi`／`pmid`／`isbn` 做了 mitigation（迴圈後寫結構化值），但那三個仍在
    /// work 上；`issn` **換了實體**（搬到 venue），所以同一個形狀套不上去。遷移後實測
    /// `.bib` 的 ISSN 欄位自 64 掉到 **0**——資料沒丟（在 venue 上），但匯出看不到。
    ///
    /// 驗收條件也沒抓到：它只列 `DOI`／`ISBN`／`PMID` 要比對，**沒列 ISSN**——寫驗收的
    /// 人在同一個盲點裡。是逐位元比對本身把它翻出來的。
    func testISSNComesFromTheVenueAfterMigration() throws {
        var v = Venue(key: "jrss-c", type: .periodical)
        v.issn = [try XCTUnwrap(ISSN("0035-9254"))]
        var e = Entry(id: UUID(), citekey: "agresti1992analysis",
                      type: .periodicalArticle, title: "T")
        e.venues = [.key("jrss-c")]
        let bib = BibExport.bibEntry(for: e, people: [:], venues: ["jrss-c": v])
        XCTAssertEqual(bib.fields["issn"], "0035-9254",
                       "ISSN 搬到 venue 之後，work 的 .bib 仍須輸出它")
    }

    /// venue 有多個 ISSN 時全部輸出——print 與 electronic 都是這份期刊的號。
    func testMultipleVenueISSNsAreEmitted() throws {
        var v = Venue(key: "ap", type: .periodical)
        v.issn = [try XCTUnwrap(ISSN("0003-066X")), try XCTUnwrap(ISSN("1935-990X"))]
        var e = Entry(id: UUID(), citekey: "x2020", type: .periodicalArticle, title: "T")
        e.venues = [.key("ap")]
        let out = try XCTUnwrap(
            BibExport.bibEntry(for: e, people: [:], venues: ["ap": v]).fields["issn"])
        XCTAssertTrue(out.contains("0003-066X") && out.contains("1935-990X"), out)
    }

    /// **venue 未歸戶（literal）時不得憑空生出 ISSN**——沒有 venue 記錄就沒有號。
    func testNoISSNWhenTheVenueEdgeIsStillLiteral() throws {
        var e = Entry(id: UUID(), citekey: "x2020", type: .periodicalArticle, title: "T")
        e.venues = [.literal("Some Journal")]
        XCTAssertNil(BibExport.bibEntry(for: e, people: [:], venues: [:]).fields["issn"])
    }

    /// `fields` 裡若還有 issn 殘留（遷移略過的那些），照舊輸出——不得被 venue 覆蓋成空。
    func testResidualISSNInFieldsStillEmitted() {
        var e = Entry(id: UUID(), citekey: "x2020", type: .periodicalArticle, title: "T",
                      fields: ["issn": "0000-0000"])
        e.venues = [.literal("Some Journal")]
        XCTAssertEqual(BibExport.bibEntry(for: e, people: [:], venues: [:]).fields["issn"],
                       "0000-0000")
    }
}
