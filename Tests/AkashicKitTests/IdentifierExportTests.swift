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
}
