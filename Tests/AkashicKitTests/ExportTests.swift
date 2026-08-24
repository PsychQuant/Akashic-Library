import XCTest
@testable import AkashicCore
@testable import AkashicExport

final class ExportTests: XCTestCase {
    private func makeEntry() -> Entry {
        var entry = Entry(
            id: UUID(uuidString: "7C1F6C2E-0000-0000-0000-000000000001")!,
            citekey: "cheng2025identifiability", type: .periodicalArticle,
            title: "Identifiability of polychoric models",
            authors: [.key("cheng-che"), .literal("Hau-Hung Yang")], date: "2025-04-01")
        entry.fields = [
            "journaltitle": "Psychometrika",
            "volume": "90",
            "number": "2",
            "doi": "10.1017/psy.2025.1",
            "pages": "301-322",
        ]
        return entry
    }

    private var people: [Person] {
        // #81：對外顯示名由 `authorized` 指定，不再由 `names` 的第一個元素決定。
        // 本 fixture 兩個書寫系統各指定一個——匯出時 `.bib`／CSL 請求 latn。
        [Person(key: "cheng-che", names: PersonNames(authorized: ["Che Cheng", "鄭澈"]))]
    }

    // MARK: - 團體作者（#323）

    /// `Author` 是三態：已歸戶為人／已歸戶為團體／未歸戶。
    ///
    /// **三態不是「人／團體／字串」** —— `.literal` 仍表示**未歸戶**（不論它最終是人
    /// 或團體）。若把三態讀成「進庫時就分人與團體」，那是 `literal-first-then-key`
    /// 規則第 1 段禁止的「進庫時猜」。
    func testAuthorHasThreeStates() {
        let person: AkashicCore.Author = .key("cheng-che")
        let group: AkashicCore.Author = .organization("taiwan-cancer-moonshot")
        let unresolved: AkashicCore.Author = .literal("{Taiwan Cancer Moonshot Program}")
        XCTAssertEqual(person.displayName, "cheng-che")
        XCTAssertEqual(group.displayName, "taiwan-cancer-moonshot")
        XCTAssertEqual(unresolved.displayName, "{Taiwan Cancer Moonshot Program}")
        XCTAssertNotEqual(person, group)
    }

    /// 團體作者匯出成 biblatex 的**雙大括號**（APA7 §8.13／8.17／8.21 的慣例）。
    ///
    /// 雙大括號讓 BibTeX 不把團體名當成人名拆解「姓, 名」。WoS 匯出的
    /// `{Taiwan Cancer Moonshot Program}` 用的就是同一個慣例——那 3 條 literal 不是
    /// 髒資料，是模型先前接不住的正規表述。
    func testOrganizationAuthorRendersDoubleBraced() throws {
        var e = makeEntry()
        e.authors = [.organization("taiwan-cancer-moonshot")]
        let orgs = [Organization(key: "taiwan-cancer-moonshot",
                                 authorized: ["Taiwan Cancer Moonshot Program"])]
        let bib = BibExport.bibFile(entries: [e], people: people, organizations: orgs, venues: [])
        XCTAssertTrue(bib.contains("AUTHOR = {{Taiwan Cancer Moonshot Program}}"),
                      "團體作者必須雙大括號，實得：\(bib)")
    }

    // MARK: - APA7 完整性報告（#326）

    /// 缺 APA7 必要欄位要**報出來**——語法完美但書目殘缺的 entry 先前會通過所有檢查。
    func testExportReportsMissingAPA7RequiredField() throws {
        var entry = makeEntry()
        entry.fields.removeValue(forKey: "journaltitle")   // ARTICLE 的必要欄位
        let report = BibExport.apa7Report(entries: [entry], people: people, venues: [])
        XCTAssertTrue(report.issues.contains {
            $0.citekey == "cheng2025identifiability" && $0.message.contains("JOURNALTITLE")
        }, "缺 JOURNALTITLE 必須被報出，實際：\(report.issues)")
    }

    /// 欄位齊全者不得被誤報。
    func testExportReportsNothingWhenAPA7FieldsComplete() throws {
        let report = BibExport.apa7Report(entries: [makeEntry()], people: people, venues: [])
        XCTAssertTrue(report.issues.filter { $0.severity == .error }.isEmpty,
                      "完整 entry 不該有 error，實際：\(report.issues)")
    }

    /// **「沒被檢查」不得長得像「通過」**：必要欄位表不涵蓋所有 entry type，未涵蓋者
    /// 必須明確列出，否則使用者會把「零 issue」讀成「已驗過」。
    ///
    /// **探針型別在 #353 換過**。原本用 `.webpage`（→ `ONLINE`），但換用
    /// `APADataModel` 的 15 型表之後 `ONLINE` **有**必要欄位表了，於是這條測試自己
    /// 失去了偵測力——它會通過，只因為斷言的那件事不再成立。改用 `.visualWork`
    /// （→ `IMAGE`），那是目前確實不在表內的三個型別之一
    /// （另兩個是 `INREFERENCE`／#354 與 `UNPUBLISHED`）。
    ///
    /// 這個型別哪天被涵蓋，本測試會紅——那時該換探針、而不是刪掉它。
    /// `APA7GoldenTests.testUncoveredTypesHaveNoFixtures` 是同一件事的矩陣側。
    func testExportSurfacesTypesNotCoveredByValidator() throws {
        let entry = Entry(id: makeEntry().id, citekey: "anon2018image", type: .visualWork,
                          title: "An Image", authors: [], date: "2018")
        let report = BibExport.apa7Report(entries: [entry], people: people, venues: [])
        XCTAssertTrue(report.uncheckedCitekeys.contains("anon2018image"),
                      "IMAGE 不在必要欄位表內，必須列為未涵蓋")
        XCTAssertTrue(report.issues.isEmpty, "未涵蓋者不該產生 issue（那會是假陽性）")
    }

    /// #353 的正面驗收：先前整批未涵蓋的 `ONLINE` 現在**真的被檢查**。
    ///
    /// 沒有這條，換表帶來的覆蓋提升只存在於 commit message 裡。
    func testOnlineTypesAreNowActuallyChecked() throws {
        let complete = Entry(id: UUID(), citekey: "anon2018page", type: .webpage,
                             title: "A Page", authors: [], date: "2018")
        let report = BibExport.apa7Report(entries: [complete], people: people, venues: [])
        XCTAssertTrue(report.uncheckedCitekeys.isEmpty,
                      "ONLINE 現在有必要欄位表（TITLE／DATE），應被檢查")
        XCTAssertTrue(report.issues.filter { $0.severity == .error }.isEmpty,
                      "TITLE 與 DATE 都在，不該有 error：\(report.issues)")

        // 反面：缺 DATE 要被抓到。ONLINE 的必要欄位**不含 AUTHOR**
        // （`APADataModel` 原始碼註解：AUTHOR or EDITOR recommended），所以這筆沒有
        // 作者也不該報 error——那正是 #350 第 3 類假陽性消失的地方。
        let noDate = Entry(id: UUID(), citekey: "anon0000page", type: .webpage,
                           title: "A Page", authors: [], date: nil)
        let errs = BibExport.apa7Report(entries: [noDate], people: people, venues: [])
            .issues.filter { $0.severity == .error }
        XCTAssertEqual(errs.map(\.message), ["Missing required field: DATE"],
                       "應只報缺 DATE；報缺 AUTHOR 就是選錯表的那個假陽性回來了")
    }

    func testBibExportRendersBiblatex() throws {
        let bib = BibExport.bibFile(entries: [makeEntry()], people: people, venues: [])
        XCTAssertTrue(bib.contains("@ARTICLE{cheng2025identifiability,"))
        // key 作者經 people 還原顯示名，姓在前
        XCTAssertTrue(bib.contains("AUTHOR = {Cheng, Che and Yang, Hau-Hung}"))
        XCTAssertTrue(bib.contains("TITLE = {Identifiability of polychoric models}"))
        XCTAssertTrue(bib.contains("JOURNALTITLE = {Psychometrika}"))
        XCTAssertTrue(bib.contains("DATE = {2025-04-01}"))
        XCTAssertTrue(bib.contains("DOI = {10.1017/psy.2025.1}"))
    }

    func testBibExportCJKAuthorPassesThrough() throws {
        var entry = Entry(id: UUID(), citekey: "chen2004matrix", type: .book,
                          title: "矩陣視覺化", authors: [.literal("陳君厚")], date: "2004")
        entry.fields["publisher"] = "Academia Sinica"
        let bib = BibExport.bibFile(entries: [entry], people: [], venues: [])
        XCTAssertTrue(bib.contains("@BOOK{chen2004matrix,"))
        XCTAssertTrue(bib.contains("AUTHOR = {陳君厚}"))   // 無空格姓名整體視為 family
    }

    func testBibExportIsDeterministic() throws {
        let a = BibExport.bibFile(entries: [makeEntry()], people: people, venues: [])
        let b = BibExport.bibFile(entries: [makeEntry()], people: people, venues: [])
        XCTAssertEqual(a, b)
    }

    func testCSLJSONExport() throws {
        let json = try CSLExport.cslJSON(entries: [makeEntry()], people: people, venues: [])
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [[String: Any]]
        XCTAssertEqual(parsed.count, 1)
        let item = parsed[0]
        XCTAssertEqual(item["id"] as? String, "cheng2025identifiability")
        XCTAssertEqual(item["type"] as? String, "article-journal")
        XCTAssertEqual(item["container-title"] as? String, "Psychometrika")
        XCTAssertEqual(item["DOI"] as? String, "10.1017/psy.2025.1")
        let authors = item["author"] as! [[String: Any]]
        XCTAssertEqual(authors[0]["family"] as? String, "Cheng")
        XCTAssertEqual(authors[0]["given"] as? String, "Che")
        XCTAssertEqual(authors[1]["family"] as? String, "Yang")
        let issued = item["issued"] as! [String: Any]
        let dateParts = issued["date-parts"] as! [[Int]]
        XCTAssertEqual(dateParts, [[2025]])
    }
}
