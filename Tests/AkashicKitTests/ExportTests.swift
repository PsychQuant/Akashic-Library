import XCTest
@testable import AkashicCore
@testable import AkashicExport

final class ExportTests: XCTestCase {
    private func makeEntry() -> Entry {
        var entry = Entry(
            id: UUID(uuidString: "7C1F6C2E-0000-0000-0000-000000000001")!,
            citekey: "cheng2025identifiability", type: "article",
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

    // MARK: - APA7 完整性報告（#326）

    /// 缺 APA7 必要欄位要**報出來**——語法完美但書目殘缺的 entry 先前會通過所有檢查。
    func testExportReportsMissingAPA7RequiredField() throws {
        var entry = makeEntry()
        entry.fields.removeValue(forKey: "journaltitle")   // ARTICLE 的必要欄位
        let report = BibExport.apa7Report(entries: [entry], people: people)
        XCTAssertTrue(report.issues.contains {
            $0.citekey == "cheng2025identifiability" && $0.message.contains("JOURNALTITLE")
        }, "缺 JOURNALTITLE 必須被報出，實際：\(report.issues)")
    }

    /// 欄位齊全者不得被誤報。
    func testExportReportsNothingWhenAPA7FieldsComplete() throws {
        let report = BibExport.apa7Report(entries: [makeEntry()], people: people)
        XCTAssertTrue(report.issues.filter { $0.severity == .error }.isEmpty,
                      "完整 entry 不該有 error，實際：\(report.issues)")
    }

    /// **「沒被檢查」不得長得像「通過」**：validator 的必要欄位表只涵蓋 7 個 type，
    /// store 另有 online／unpublished／misc 等值不在表內。那些必須明確列為未涵蓋，
    /// 否則使用者會把「零 issue」讀成「已驗過」。
    func testExportSurfacesTypesNotCoveredByValidator() throws {
        var entry = makeEntry()
        entry = Entry(id: entry.id, citekey: "anon2018wiki", type: "misc",
                      title: "Wiki", authors: [], date: "2018")
        let report = BibExport.apa7Report(entries: [entry], people: people)
        XCTAssertTrue(report.uncheckedCitekeys.contains("anon2018wiki"),
                      "type=misc 不在 validator 的必要欄位表內，必須列為未涵蓋")
        XCTAssertTrue(report.issues.isEmpty, "未涵蓋者不該產生 issue（那會是假陽性）")
    }

    func testBibExportRendersBiblatex() throws {
        let bib = BibExport.bibFile(entries: [makeEntry()], people: people)
        XCTAssertTrue(bib.contains("@ARTICLE{cheng2025identifiability,"))
        // key 作者經 people 還原顯示名，姓在前
        XCTAssertTrue(bib.contains("AUTHOR = {Cheng, Che and Yang, Hau-Hung}"))
        XCTAssertTrue(bib.contains("TITLE = {Identifiability of polychoric models}"))
        XCTAssertTrue(bib.contains("JOURNALTITLE = {Psychometrika}"))
        XCTAssertTrue(bib.contains("DATE = {2025-04-01}"))
        XCTAssertTrue(bib.contains("DOI = {10.1017/psy.2025.1}"))
    }

    func testBibExportCJKAuthorPassesThrough() throws {
        var entry = Entry(id: UUID(), citekey: "chen2004matrix", type: "book",
                          title: "矩陣視覺化", authors: [.literal("陳君厚")], date: "2004")
        entry.fields["publisher"] = "Academia Sinica"
        let bib = BibExport.bibFile(entries: [entry], people: [])
        XCTAssertTrue(bib.contains("@BOOK{chen2004matrix,"))
        XCTAssertTrue(bib.contains("AUTHOR = {陳君厚}"))   // 無空格姓名整體視為 family
    }

    func testBibExportIsDeterministic() throws {
        let a = BibExport.bibFile(entries: [makeEntry()], people: people)
        let b = BibExport.bibFile(entries: [makeEntry()], people: people)
        XCTAssertEqual(a, b)
    }

    func testCSLJSONExport() throws {
        let json = try CSLExport.cslJSON(entries: [makeEntry()], people: people)
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
