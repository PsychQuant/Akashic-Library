import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicExport

/// #6：機構名不得被切成 "Organization, World Health"。
///
/// **範圍（誠實記）**：本 issue 只交付「**標記存在時** export 端尊重它」。
/// **不做**自動偵測——Zotero 的 `fieldMode == 1` 同時用於機構與「不想被拆的人名」，
/// 沒有訊號能分開兩者，自動標記會把人名保護壞。真正的修法（family / given /
/// corporate 三態各自成欄）屬 #35。
final class CorporateNameTests: XCTestCase {

    // MARK: - 標記本身

    func testMarkAndUnmarkRoundTrip() {
        let s = "World Health Organization"
        XCTAssertEqual(CorporateName.mark(s), "{World Health Organization}")
        XCTAssertEqual(CorporateName.unmark(CorporateName.mark(s)), s)
        XCTAssertTrue(CorporateName.isMarked(CorporateName.mark(s)))
    }

    func testMarkIsIdempotent() {
        let once = CorporateName.mark("WHO")
        XCTAssertEqual(CorporateName.mark(once), once, "重複標記會產生 {{WHO}}")
    }

    /// **不平衡的括號不算標記**——`{a} b {c}` 是一般字串裡剛好有括號，
    /// 把它當機構名會讓一個人名被原樣輸出而不切分。
    func testUnbalancedBracesAreNotMarks() {
        for s in ["{a} b {c}", "{a} b", "a {b}", "{", "}", "{}{}", "no braces"] {
            XCTAssertFalse(CorporateName.isMarked(s), s.debugDescription)
        }
    }

    func testNestedBracesStillCountAsSingleMark() {
        XCTAssertTrue(CorporateName.isMarked("{Institute of {Statistical} Science}"))
        XCTAssertEqual(CorporateName.unmark("{Institute of {Statistical} Science}"),
                       "Institute of {Statistical} Science")
    }

    func testUnmarkOnPlainStringIsIdentity() {
        XCTAssertEqual(CorporateName.unmark("Che Cheng"), "Che Cheng")
    }

    // MARK: - biblatex 輸出（原始 bug）

    /// 這就是 issue 報的那一個。
    func testCorporateNameIsNotSplitInBibExport() {
        let marked = CorporateName.mark("World Health Organization")
        XCTAssertEqual(BibExport.bibName(for: .literal(marked), people: [:]),
                       "{World Health Organization}",
                       "機構名被切成 Family, Given")
    }

    /// 一般人名不受影響——修法不得改變既有正確行為。
    func testPersonNameStillSplitInBibExport() {
        XCTAssertEqual(BibExport.bibName(for: .literal("Che Cheng"), people: [:]),
                       "Cheng, Che")
        XCTAssertEqual(BibExport.bibName(for: .literal("R. Darrell Bock"), people: [:]),
                       "Bock, R. Darrell")
    }

    /// CJK 全名無空白——既有行為是整體當 family，不得被本次修改影響。
    func testCJKNameUnchanged() {
        XCTAssertEqual(BibExport.bibName(for: .literal("鄭澈"), people: [:]), "鄭澈")
    }

    // MARK: - CSL 輸出

    /// CSL 有 `literal` name variant，正好對應機構名。輸出時**去掉標記**——
    /// 大括號是 biblatex 的慣例，CSL-JSON 的消費端不認得它。
    func testCorporateNameUsesCSLLiteralVariantWithoutBraces() throws {
        var e = Entry(id: UUID(), citekey: "who2020a", type: .report, title: "T",
                      authors: [.literal(CorporateName.mark("World Health Organization"))],
                      date: "2020")
        e.fields["journaltitle"] = "J"
        let json = try CSLExport.cslJSON(entries: [e], people: [])
        let arr = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [[String: Any]]
        let authors = arr[0]["author"] as! [[String: Any]]
        XCTAssertEqual(authors[0]["literal"] as? String, "World Health Organization")
        XCTAssertNil(authors[0]["family"], "機構名不得有 family")
    }

    func testPersonNameUsesFamilyGivenInCSL() throws {
        var e = Entry(id: UUID(), citekey: "cheng2025a", type: .periodicalArticle, title: "T",
                      authors: [.literal("Che Cheng")], date: "2025")
        e.fields["journaltitle"] = "J"
        let json = try CSLExport.cslJSON(entries: [e], people: [])
        let arr = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [[String: Any]]
        let authors = arr[0]["author"] as! [[String: Any]]
        XCTAssertEqual(authors[0]["family"] as? String, "Cheng")
        XCTAssertEqual(authors[0]["given"] as? String, "Che")
    }

    // MARK: - 姓名順序（#377）

    /// **已是 `Family, Given` 形的名字不得被重排。**
    ///
    /// 實測 730 筆 person 的 authorized 名字是這個形（WoS 的 `Author Full Names` 格式，
    /// `import-wos` 依 `lossless-intake` 原樣收下——入庫是對的）。原本 `familyGiven`
    /// 一律取最後一個空格分隔 token 當姓，於是 `Chang, Ya-Hsuan` 變成
    /// family=`Ya-Hsuan`、given=`Chang,`，biblatex 印成「Ya-Hsuan, C.」。
    ///
    /// **逗號是顯式記號不是啟發式**：biblatex 與 WoS 共用「姓, 名」這個慣例。
    func testCommaFormNamesAreNotReordered() {
        let cases: [(String, family: String, given: String)] = [
            ("Chang, Ya-Hsuan", family: "Chang", given: "Ya-Hsuan"),
            // 三個 token、逗號在第一個之後——先前輸出 `K., Reeves, Gillian`
            ("Reeves, Gillian K.", family: "Reeves", given: "Gillian K."),
            // 多 token 的姓：空格法做不到，逗號法自動正確
            ("van der Berg, Jan", family: "van der Berg", given: "Jan"),
            ("Chen, Yan Si", family: "Chen", given: "Yan Si"),
        ]
        for (input, family, given) in cases {
            let got = BibExport.familyGiven(input)
            XCTAssertEqual(got?.family, family, "\(input) 的姓")
            XCTAssertEqual(got?.given, given, "\(input) 的名")
        }
    }

    /// 無逗號的形照舊：最後一個 token 當姓。
    func testSpaceFormStillSplitsOnTheLastToken() {
        let got = BibExport.familyGiven("Che Cheng")
        XCTAssertEqual(got?.family, "Cheng")
        XCTAssertEqual(got?.given, "Che")
    }

    /// **`.bib` 的實際輸出**——這條才是使用者看得到的東西。
    func testBibOutputKeepsFamilyGivenOrderForCommaFormNames() {
        var p = Person(key: "chang-ya-hsuan",
                       names: PersonNames(authorized: ["Chang, Ya-Hsuan"]))
        p.id = UUID()
        var e = Entry(id: UUID(), citekey: "chang2026a", type: .periodicalArticle,
                      title: "T", authors: [.key("chang-ya-hsuan")], date: "2026")
        e.fields["journaltitle"] = "J"
        let bib = BibExport.bibEntry(for: e, people: ["chang-ya-hsuan": p])
        XCTAssertEqual(bib.fields["author"], "Chang, Ya-Hsuan",
                       "先前是「Ya-Hsuan, Chang,」——姓名顛倒且多一個逗號")
    }

    /// given 為空時不留尾隨逗號（來源只寫了姓，或字串本身以逗號結尾）。
    func testEmptyGivenDoesNotLeaveATrailingComma() {
        var p = Person(key: "chang", names: PersonNames(authorized: ["Chang,"]))
        p.id = UUID()
        var e = Entry(id: UUID(), citekey: "chang2026b", type: .periodicalArticle,
                      title: "T", authors: [.key("chang")], date: "2026")
        e.fields["journaltitle"] = "J"
        let bib = BibExport.bibEntry(for: e, people: ["chang": p])
        XCTAssertEqual(bib.fields["author"], "Chang")
    }

    /// 標記只是普通字串——**strict 的 authors 層完全不受影響**，
    /// 舊 binary 照常讀（只是它們的 export 仍會切錯，可用性退化非資料毀損）。
    func testMarkedNameIsJustAStringInStore() throws {
        let e = Entry(id: UUID(), citekey: "who2020a", type: .report, title: "T",
                      authors: [.literal("{World Health Organization}")], date: "2020")
        let yaml = try EntryYAML.encode(e)
        XCTAssertEqual(try EntryYAML.decode(yaml).authors, e.authors)
    }
}
