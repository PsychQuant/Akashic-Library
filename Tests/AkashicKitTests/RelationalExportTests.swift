import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicExport

/// #22：Akashic → 關係式表格（DuckDB 為衍生）。
final class RelationalExportTests: XCTestCase {

    private func entry(_ ck: String, authors: [Author], date: String? = "2020",
                       id: UUID = UUID()) -> Entry {
        var e = Entry(id: id, citekey: ck, type: "article", title: "T",
                      authors: authors, date: date)
        e.fields["journaltitle"] = "J"
        return e
    }

    // MARK: - sum type → nullable FK（本 issue 的核心對應）

    /// `.key(k)` → `researcher_id` 有值；`.literal(s)` → **NULL** + `name_full`。
    /// 不需要「是否已歸戶」的旗標——缺席本身就是資訊，`IS NULL` 就是查詢。
    func testAuthorSumTypeMapsToNullableFK() {
        let p = Person(key: "cheng-che", names: ["Che Cheng"])
        let e = entry("a2020a", authors: [.key("cheng-che"), .literal("Someone Else")])
        let t = RelationalExport.tables(entries: [e], people: [p]).publicationAuthor
        XCTAssertEqual(t.rows.count, 2)
        XCTAssertEqual(t.rows[0][2], p.id.uuidString, "已歸戶必須有 researcher_id")
        XCTAssertEqual(t.rows[0][3], "Che Cheng")
        XCTAssertNil(t.rows[1][2], "未歸戶必須是 NULL")
        XCTAssertEqual(t.rows[1][3], "Someone Else")
    }

    /// `author_seq` 由陣列 index 給——作者順序是書目資料的一部分，不得被排序打亂。
    func testAuthorSequencePreservesOrder() {
        let e = entry("a2020a", authors: [.literal("First"), .literal("Second"), .literal("Third")])
        let rows = RelationalExport.tables(entries: [e], people: []).publicationAuthor.rows
        XCTAssertEqual(rows.map { $0[1] }, ["0", "1", "2"])
        XCTAssertEqual(rows.map { $0[3] }, ["First", "Second", "Third"])
    }

    /// **懸空的 `.key` 不得憑空造 id**——造出來的會在下游變成一筆不存在的 researcher 的 FK。
    func testDanglingAuthorKeyYieldsNullNotFabricatedID() {
        let e = entry("a2020a", authors: [.key("ghost-person")])
        let row = RelationalExport.tables(entries: [e], people: []).publicationAuthor.rows[0]
        XCTAssertNil(row[2], "懸空 key 必須是 NULL")
        XCTAssertEqual(row[3], "ghost-person", "名字仍要出得來，否則下游連查都不知道查什麼")
    }

    // MARK: - year 的邊界（真實 corpus 的實際問題）

    /// `"0000"` 是真實資料（Zotero 對缺日期的佔位，536 筆中有 2 筆）。忠實轉成 `0`
    /// 會讓下游得到「西元 0 年的出版品」——那不是資料，是佔位符被當成值。
    func testPlaceholderYearBecomesNullButRawIsKept() {
        let e = entry("a0000a", authors: [.literal("X")], date: "0000")
        let row = RelationalExport.tables(entries: [e], people: []).publication.rows[0]
        XCTAssertEqual(row[4], "0000", "date_raw 必須保留原字串，資訊不得遺失")
        XCTAssertNil(row[5], "year 不得是 0")
    }

    func testYearExtraction() {
        XCTAssertEqual(RelationalExport.year(of: "2020-05-01"), 2020)
        XCTAssertEqual(RelationalExport.year(of: "May 2020"), 2020)
        XCTAssertEqual(RelationalExport.year(of: "2027"), 2027, "未來年份合法（in press）")
        XCTAssertNil(RelationalExport.year(of: "n.d."))
        XCTAssertNil(RelationalExport.year(of: nil))
        XCTAssertNil(RelationalExport.year(of: "0000"))
    }

    // MARK: - CSV 正確性（下游靠它讀）

    /// 逗號、引號、換行——書目 title 三種都會出現，escape 錯一個就整份 CSV 錯位。
    func testCSVEscapesSpecialCharacters() {
        var e = entry("a2020a", authors: [.literal("X")])
        e.title = #"Title, with "quotes" and"# + "\nnewline"
        let csv = RelationalExport.csv(RelationalExport.tables(entries: [e], people: []).publication)
        XCTAssertTrue(csv.contains(#""Title, with ""quotes"" and"#), csv)
        // 欄位數不得因為內嵌換行而爆掉：header 1 行 + 資料（含內嵌換行）
        XCTAssertEqual(csv.components(separatedBy: "\"").count % 2, 1, "引號未配對")
    }

    func testNilBecomesEmptyField() {
        let e = entry("a2020a", authors: [.literal("X")], date: nil)
        let csv = RelationalExport.csv(RelationalExport.tables(entries: [e], people: []).publication)
        let dataLine = csv.split(separator: "\n")[1]
        XCTAssertTrue(dataLine.contains(",,"), "nil 應為空欄位：\(dataLine)")
    }

    // MARK: - 決定性（下游會 diff 這些檔案）

    /// 同樣的輸入必須產生逐字相同的輸出——否則每次 export 都是一個假 diff。
    func testOutputIsDeterministic() {
        let ids = (0..<3).map { _ in UUID() }
        let es = zip(["c2020c", "a2020a", "b2020b"], ids).map {
            entry($0.0, authors: [.literal("X")], id: $0.1)
        }
        let ps = [Person(key: "z-one", names: ["Z"]), Person(key: "a-two", names: ["A"])]
        let a = RelationalExport.tables(entries: es, people: ps)
        let b = RelationalExport.tables(entries: es.reversed(), people: ps.reversed())
        XCTAssertEqual(a, b, "輸出順序必須與輸入順序無關")
        XCTAssertEqual(a.publication.rows.map { $0[1] }, ["a2020a", "b2020b", "c2020c"])
        XCTAssertEqual(a.researcher.rows.map { $0[1] }, ["a-two", "z-one"])
    }

    // MARK: - temporal 維度（#20 → #22）

    /// long format：維度值域開放，攤平成寬表會讓每個新職稱變成一次 schema 變更。
    func testTimelineExportsAsLongFormat() {
        var p = Person(key: "cheng", names: ["C"])
        p.profile.ranks = Timeline([
            TemporalValue(value: "助研究員", range: DateRange(start: "2010", end: "2015")),
            TemporalValue(value: "研究員", range: DateRange(start: "2015"))])
        p.profile.administrative = Timeline([
            TemporalValue(value: "所長", range: DateRange(start: "2020", end: "2023"),
                          source: "https://example.org")])
        let t = RelationalExport.tables(entries: [], people: [p]).researcherTimeline
        XCTAssertEqual(t.rows.count, 3)
        XCTAssertEqual(t.rows.map { $0[1] }, ["rank", "rank", "administrative"])
        XCTAssertEqual(t.rows[0][2], "助研究員")
        XCTAssertEqual(t.rows[0][4], "2015", "valid_end")
        XCTAssertNil(t.rows[1][4], "開放區間的 valid_end 必須是 NULL")
        XCTAssertEqual(t.rows[2][5], "https://example.org", "source 必須帶出來")
    }

    /// 多段任期（#20 的動機資料）必須各自成列，不得被壓成一段。
    func testMultiSegmentTenureExportsAsSeparateRows() {
        var p = Person(key: "cheng", names: ["C"])
        p.profile.affiliations = Timeline([
            TemporalValue(value: "ISS", range: DateRange(start: "2003-01", end: "2006-08")),
            TemporalValue(value: "ISS", range: DateRange(start: "2013-07", end: "2017-06"))])
        let rows = RelationalExport.tables(entries: [], people: [p]).researcherTimeline.rows
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map { $0[3] }, ["2003-01", "2013-07"])
    }

    /// **沒有隸屬資料時 status 是 NULL，不猜成 current**——猜會讓退休者被算成現職。
    func testStatusIsNullWithoutAffiliationData() {
        let p = Person(key: "unknown-status", names: ["U"])
        XCTAssertNil(RelationalExport.tables(entries: [], people: [p]).researcher.rows[0][9])
    }

    func testStatusDerivedFromOpenAffiliation() {
        var cur = Person(key: "a-current", names: ["A"])
        cur.profile.affiliations = Timeline([
            TemporalValue(value: "ISS", range: DateRange(start: "2020"))])
        var ret = Person(key: "b-retired", names: ["B"])
        ret.profile.affiliations = Timeline([
            TemporalValue(value: "ISS", range: DateRange(start: "2000", end: "2010"))])
        let rows = RelationalExport.tables(entries: [], people: [cur, ret]).researcher.rows
        XCTAssertEqual(rows[0][9], "current")
        XCTAssertEqual(rows[1][9], "retired")
        XCTAssertEqual(rows[0][6], "ISS" == rows[0][5] ? nil : rows[0][6])  // rank 無資料
        XCTAssertEqual(rows[0][5], "ISS", "affiliation_current")
    }

    /// researcher 的主鍵用**UUID 而非 key**——key 是稱呼會改，surrogate id 才適合當 FK。
    func testResearcherUsesStableIDNotKey() {
        let p = Person(key: "cheng-che", names: ["Che Cheng"], orcid: "0000-0001-2345-6789")
        let row = RelationalExport.tables(entries: [], people: [p]).researcher.rows[0]
        XCTAssertEqual(row[0], p.id.uuidString)
        XCTAssertEqual(row[1], "cheng-che")
        XCTAssertEqual(row[3], "0000-0001-2345-6789")
    }
}
