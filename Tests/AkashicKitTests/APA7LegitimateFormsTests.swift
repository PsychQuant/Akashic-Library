import XCTest
@testable import AkashicCore
@testable import AkashicExport

/// APA7 的合法形式不得被報成缺漏（#350）。
///
/// 這一組測的是**「滿足」的定義**，不是放寬檢查。缺真的缺的東西照樣要報——每條斷言都
/// 配一條反面斷言確認這一點。
final class APA7LegitimateFormsTests: XCTestCase {

    private func entry(_ citekey: String, type: WorkType, date: String?,
                       fields: [String: String] = [:],
                       authors: [Author] = [.literal("A, A.")]) -> Entry {
        var e = Entry(id: UUID(), citekey: citekey, type: type, title: "T",
                      authors: authors, date: date)
        e.fields = fields
        return e
    }

    private func errors(_ entries: [Entry]) -> [String] {
        BibExport.apa7Report(entries: entries, people: [], venues: [])
            .issues.filter { $0.severity == .error }.map(\.message).sorted()
    }

    // MARK: - 第 2 類：合法的無日期（n.d.）

    /// `date` 的三態必須都可表達，而**中間那一格先前不存在**。
    func testDateHasThreeDistinguishableStates() {
        XCTAssertFalse(entry("a", type: .book, date: "2020").dateIsConfirmedAbsent)
        XCTAssertTrue(entry("b", type: .book, date: Entry.noDateSentinel).dateIsConfirmedAbsent)
        XCTAssertFalse(entry("c", type: .book, date: nil).dateIsConfirmedAbsent,
                       "nil ＝還沒查，不是確認沒有")
    }

    /// **確認無日期不報 error**——APA7 對無日期作品印 `(n.d.)`，那是合法形式。
    func testConfirmedNoDateSatisfiesTheDateRequirement() {
        XCTAssertEqual(errors([entry("anonndentry", type: .book,
                                     date: Entry.noDateSentinel)]), [])
    }

    /// **反面：還沒查照樣報。** 這是兩者唯一被區分開的地方。
    func testUnknownDateStillReportsError() {
        XCTAssertEqual(errors([entry("anon0000entry", type: .book, date: nil)]),
                       ["Missing required field: DATE"],
                       "date: nil ＝還沒查，必須照樣報——否則 sentinel 就只是把檢查關掉")
    }

    /// sentinel **不寫進 `.bib`**：依賴對缺席的 date 印 `(n.d.)`，那正是要的輸出。
    ///
    /// 寫 `date = {n.d.}` 反而會讓 date parser 拿到一個不是日期的字串。
    func testSentinelIsNotEmittedToBib() {
        let bib = BibExport.bibEntry(for: entry("anonndentry", type: .book,
                                                date: Entry.noDateSentinel),
                                     people: [:], venues: [:])
        XCTAssertNil(bib.fields.caseInsensitiveValue(forKey: "date"),
                     "sentinel 不該出現在 .bib；缺席才是 biblatex-apa 印 (n.d.) 的條件")
    }

    /// 真日期照樣寫出去（回歸保護）。
    func testRealDateIsStillEmitted() {
        let bib = BibExport.bibEntry(for: entry("x2020", type: .book, date: "2020"),
                                     people: [:], venues: [:])
        XCTAssertEqual(bib.fields.caseInsensitiveValue(forKey: "date"), "2020")
    }

    // MARK: - 第 1 類：編者填作者位置

    /// 編著書只有 `EDITOR` 是**正確形式**，不是缺作者。
    ///
    /// APA7 §10.2 的 template：`Editor, E. E. (Ed.). (Year). Title. Publisher.`
    func testEditorSatisfiesAuthorPositionForEditedBook() {
        XCTAssertEqual(errors([entry("ed2018book", type: .book, date: "2018",
                                     fields: ["editor": "Evans, F."], authors: [])]),
                       [])
    }

    /// §10.3 整本編著作品被當條目引用時同形。
    func testEditorSatisfiesAuthorPositionForEditedCollection() {
        XCTAssertEqual(errors([entry("ed2001guide", type: .bookChapter, date: "2001",
                                     fields: ["editor": "Macoun, J.",
                                              "booktitle": "A Collaborative"],
                                     authors: [])]),
                       [])
    }

    /// **反面：既無作者也無編者照樣報。**
    func testNeitherAuthorNorEditorStillReportsError() {
        XCTAssertEqual(errors([entry("anon2018book", type: .book, date: "2018",
                                     authors: [])]),
                       ["Missing required field: AUTHOR"])
    }

    /// **替代規則的值域刻意窄**：期刊文章的編者**不**填作者位置。
    ///
    /// 這條防的是「看起來像同一件事就套用」——`ARTICLE` 的作者就是作者，一本期刊的編者
    /// 不是那篇文章的作者。不得依性質相似類推。
    func testEditorDoesNotSatisfyAuthorForJournalArticle() {
        let msgs = errors([entry("ed2020article", type: .periodicalArticle, date: "2020",
                                 fields: ["editor": "Someone, S.",
                                          "journaltitle": "A Journal"],
                                 authors: [])])
        XCTAssertTrue(msgs.contains("Missing required field: AUTHOR"),
                      "期刊文章的編者不填作者位置，應照樣報：\(msgs)")
    }

    /// 會議發表同理——`PRESENTATION` 不在替代表內。
    func testEditorDoesNotSatisfyAuthorForPresentation() {
        let msgs = errors([entry("ed2020talk", type: .conferenceSession, date: "2020",
                                 fields: ["editor": "Someone, S."], authors: [])])
        XCTAssertTrue(msgs.contains("Missing required field: AUTHOR"), "\(msgs)")
    }

    // MARK: - 第 3 類：合法的無個人作者（已由 #353／#354 結構性消除）

    /// 網頁／社群貼文**不要求** `AUTHOR`——`APADataModel` 的 `ONLINE` 表就是這樣寫的
    /// （原始碼註解：`// AUTHOR or EDITOR recommended`）。
    ///
    /// 這條不需要任何替代規則就成立，因為 #353 換表後那個要求本來就不在了。留著它是為了
    /// **釘住第 3 類已經被解掉**：若哪天 `ONLINE` 又開始要求 `AUTHOR`，這條會紅。
    func testOnlineTypesDoNotRequireAuthor() {
        XCTAssertEqual(errors([entry("anon2019page", type: .webpage, date: "2019",
                                     authors: [])]), [])
    }

    /// 參考工具書條目同理——**條目名佔作者位置**（§10.3 例 49 維基百科）。
    func testReferenceWorkEntriesDoNotRequireAuthor() {
        XCTAssertEqual(errors([entry("anon2019wiki", type: .referenceWorkEntry, date: "2019",
                                     fields: ["booktitle": "Wikipedia"],
                                     authors: [])]), [])
    }
}
