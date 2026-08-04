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
        [Person(key: "cheng-che", names: ["Che Cheng", "鄭澈"],
                authorized: ["Che Cheng", "鄭澈"])]
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
