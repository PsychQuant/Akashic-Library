import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// `akashic references nominate --refs <json> --openalex <json>...`（#617）：PDF 參考文獻 ×
/// OpenAlex `referenced_works` 的雙向提名。**只提名、不判定**（D3：字串相似只能提名）——輸出
/// 沒有「接受」這個欄位，判定是模型逐筆做的事。
///
/// fixture 全是手寫的虛構條目與虛構 OpenAlex work；期望值逐欄手寫。
final class ReferencesNominateTests: XCTestCase {

    private struct Candidate: Decodable {
        let openalex: String
        let doi: String?
        let title: String?
        let score: Double
        let basis: [String]
        let inStore: String?
        let inStoreConflict: [String]?
        let storeMatches: [StoreMatch]?
    }
    private struct StoreMatch: Decodable {
        let citekey: String
        let score: Double
    }
    private struct RefNomination: Decodable {
        let index: Int
        let candidates: [Candidate]
        let storeMatches: [StoreMatch]?
    }
    private struct Work: Decodable {
        let openalex: String
        let inStore: String?
    }
    private struct Result: Decodable {
        let refs: [RefNomination]
        let unnominated: [Work]
        let warnings: [String]
        let contract: Int?
    }

    private var root: URL!
    private var scratch: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-nominate-\(UUID().uuidString)")
        try LibraryStore(root: root).ensureLayout()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-nominate-in-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: scratch)
    }

    private func write(_ name: String, _ content: String) throws -> String {
        let url = scratch.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    /// 參考文獻段 → `extract` 的真輸出。nominate 吃的就是這個形狀——兩個子命令之間的
    /// JSON 是契約，用手寫 refs 測會讓兩邊各自綠、接起來卻壞。
    private func extractRefs(_ text: String) throws -> String {
        let path = try write("refs.txt", text)
        let (status, output) = try CLITestHarness.run(["references", "extract", "--text", path], env: [:])
        XCTAssertEqual(status, 0, output)
        return try write("refs.json", output)
    }

    private func work(_ id: String, doi: String?, title: String, year: Int, authors: [String]) -> String {
        let doiJSON = doi.map { "\"https://doi.org/\($0)\"" } ?? "null"
        let authorships = authors.map { "{\"author\":{\"display_name\":\"\($0)\"}}" }.joined(separator: ",")
        return """
        {"id":"https://openalex.org/\(id)","doi":\(doiJSON),"title":"\(title)",\
        "publication_year":\(year),"authorships":[\(authorships)]}
        """
    }

    private func openalex(_ works: [String]) throws -> String {
        try write("oa-\(UUID().uuidString).json", "{\"results\":[\(works.joined(separator: ","))]}")
    }

    private func nominate(_ refs: String, _ openalexFiles: [String]) throws -> (status: Int32, output: String) {
        var args = ["references", "nominate", "--refs", refs]
        for f in openalexFiles { args += ["--openalex", f] }
        return try CLITestHarness.run(args + ["--library", root.path], env: [:])
    }

    private func decode(_ output: String) throws -> Result {
        try JSONDecoder().decode(Result.self, from: Data(output.utf8))
    }

    /// T6：姓＋年＋標題皆符的 work 排第 1；同作者同年的誘餌 work 可以在候選裡，但排在後面。
    /// DOI 兩邊都有且相同 → 依據列出 `doi`。
    func testExactMatchRanksFirst() throws {
        let refs = try extractRefs("""
        References

        Adams, J. K., & Baker, L. M. (2010). Modeling change in repeated measures: A tutorial.
            Journal of Imaginary Methods, 12(3), 45–67.
        Baker, L. (2012). Second title about growth curves. Journal B, 2, 3–4.
            https://doi.org/10.9999/b.2012
        """)
        let oa = try openalex([
            work("W3", doi: "10.9999/decoy", title: "An unrelated topic entirely", year: 2010,
                 authors: ["Jane K. Adams"]),
            work("W1", doi: "10.9999/a.2010", title: "Modeling change in repeated measures: a tutorial",
                 year: 2010, authors: ["Jane K. Adams", "Lee M. Baker"]),
            work("W2", doi: "10.9999/B.2012", title: "Second title about growth curves", year: 2012,
                 authors: ["Lee Baker"]),
        ])
        let (status, output) = try nominate(refs, [oa])
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.refs.map(\.index), [1, 2])
        XCTAssertEqual(r.refs[0].candidates.first?.openalex, "W1")
        XCTAssertEqual(r.refs[0].candidates.map(\.openalex), ["W1", "W3"],
                       "同作者同年的誘餌仍被提名（交給判定），但排在標題相符者之後")
        XCTAssertEqual(r.refs[1].candidates.first?.openalex, "W2")
        XCTAssertTrue(r.refs[1].candidates.first?.basis.contains("doi") ?? false, output)
        XCTAssertGreaterThan(r.refs[0].candidates[0].score, r.refs[0].candidates[1].score)
    }

    /// T7：同作者同年兩篇 → 兩篇都在兩筆條目的候選裡，由標題區分排序；不自動取第一個。
    func testSameAuthorSameYearKeepsBothCandidates() throws {
        let refs = try extractRefs("""
        References

        Hughes, A. (2015a). Cross-lagged panel models revisited. Imaginary Statistics, 3(1), 100–120.
        Hughes, A. (2015b). Random intercepts and stable traits. Imaginary Statistics, 3(2), 121–140.
        """)
        let oa = try openalex([
            work("W10", doi: "10.9999/h.b", title: "Random intercepts and stable traits", year: 2015,
                 authors: ["Anna Hughes"]),
            work("W11", doi: "10.9999/h.a", title: "Cross-lagged panel models revisited", year: 2015,
                 authors: ["Anna Hughes"]),
        ])
        let (status, output) = try nominate(refs, [oa])
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.refs[0].candidates.map(\.openalex), ["W11", "W10"])
        XCTAssertEqual(r.refs[1].candidates.map(\.openalex), ["W10", "W11"])
        XCTAssertTrue(r.unnominated.isEmpty)
    }

    /// T8：沒被任何條目提名的 OpenAlex work 另列；PDF 條目沒有候選時候選為空。
    /// `--openalex` 可重複（OpenAlex 每批至多 50 個，一篇論文的參考文獻常要好幾批）。
    func testUnnominatedWorksAreListedSeparately() throws {
        let refs = try extractRefs("""
        References

        Adams, J. K. (2001). First title about panels. Journal A, 1, 1–2.
        Quill, Z. (1987). A work OpenAlex never linked. Journal Z, 9, 1–9.
        """)
        let batch1 = try openalex([
            work("W1", doi: "10.9999/a", title: "First title about panels", year: 2001, authors: ["J. Adams"]),
        ])
        let batch2 = try openalex([
            work("W20", doi: "10.9999/z", title: "Something the PDF never cites", year: 1999,
                 authors: ["Mary Zed"]),
        ])
        let (status, output) = try nominate(refs, [batch1, batch2])
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.refs[0].candidates.map(\.openalex), ["W1"])
        XCTAssertEqual(r.refs[1].candidates.count, 0)
        XCTAssertEqual(r.unnominated.map(\.openalex), ["W20"])
    }

    /// T9：store 已有該 DOI（大小寫不同）→ 候選標出 citekey；不在庫者為 nil。
    func testWorksAlreadyInStoreCarryTheirCitekey() throws {
        let draft = try write("draft.json", """
        {"type":"periodical-article","title":"Already here","authors":["Jane Adams"],
         "date":"2001","doi":["10.9999/instore.1"]}
        """)
        let (cs, co) = try CLITestHarness.run(["create-entry", "--file", draft, "--library", root.path], env: [:])
        XCTAssertEqual(cs, 0, co)
        let citekey = try XCTUnwrap(try LibraryStore(root: root).load().entries.first?.citekey)

        let refs = try extractRefs("""
        References

        Adams, J. (2001). Already here. Journal A, 1, 1–2.
        Baker, L. (2002). Not here yet. Journal B, 2, 3–4.
        """)
        let oa = try openalex([
            work("W30", doi: "10.9999/INSTORE.1", title: "Already here", year: 2001, authors: ["Jane Adams"]),
            work("W31", doi: "10.9999/new.2", title: "Not here yet", year: 2002, authors: ["Lee Baker"]),
        ])
        let (status, output) = try nominate(refs, [oa])
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.refs[0].candidates.first?.inStore, citekey)
        XCTAssertNil(r.refs[1].candidates.first?.inStore)
    }

    private func createEntry(_ json: String) throws {
        let draft = try write("draft-\(UUID().uuidString).json", json)
        let (status, output) = try CLITestHarness.run(["create-entry", "--file", draft, "--library", root.path], env: [:])
        XCTAssertEqual(status, 0, output)
    }

    /// T11：同一個 DOI 在 store 裡對到兩筆（#637 的形狀）→ 不擅選一筆，列出全部並 warning
    /// （#617 verify F6：原本取字串最小者，常常選到 `b` 尾碼那筆重複記錄）
    func testDOIHeldByTwoRecordsIsReportedNotPicked() throws {
        try createEntry(#"{"type":"periodical-article","title":"Twin title","authors":["Jane Adams"],"date":"2001","doi":["10.9999/twin.1"]}"#)
        try createEntry(#"{"type":"periodical-article","title":"Twin title","authors":["Jane Adams"],"date":"2001","doi":["10.9999/twin.1"]}"#)
        let refs = try extractRefs("References\n\nAdams, J. (2001). Twin title. Journal A, 1, 1–2.\n")
        let oa = try openalex([work("W40", doi: "10.9999/twin.1", title: "Twin title", year: 2001, authors: ["Jane Adams"])])
        let (status, output) = try nominate(refs, [oa])
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        let c = try XCTUnwrap(r.refs.first?.candidates.first)
        XCTAssertNil(c.inStore, "同一個 DOI 對到兩筆時不得擅選一筆")
        XCTAssertEqual(c.inStoreConflict?.count, 2)
        XCTAssertTrue(r.warnings.contains { $0.contains("不只一筆") }, "\(r.warnings)")
    }

    /// T12：被隔離（quarantined）的檔案要計數回報——那些記錄的 DOI 看不到，不得看起來像
    /// 「掃過且不在庫」（#617 verify F7；#497）
    func testQuarantinedFilesAreCounted() throws {
        let broken = root.appendingPathComponent("entities/00000000-0000-0000-0000-000000000617.yaml")
        try "type: [unclosed\n".write(to: broken, atomically: true, encoding: .utf8)
        let refs = try extractRefs("References\n\nAdams, J. (2001). A title. Journal A, 1, 1–2.\n")
        let oa = try openalex([work("W41", doi: "10.9999/q.1", title: "A title", year: 2001, authors: ["Jane Adams"])])
        let (status, output) = try nominate(refs, [oa])
        XCTAssertEqual(status, 0, output)
        XCTAssertTrue(try decode(output).warnings.contains { $0.contains("隔離") }, output)
    }

    /// T13：store 裡沒有 DOI（或 DOI 不同）的同一篇，以標題＋年份提名（#617 verify F2／F3：
    /// 原本寫入前這道比對要模型每次手寫，而且命中後沒有去處）
    func testStoreTitleYearMatchesAreNominated() throws {
        try createEntry(#"{"type":"book","title":"An old book without a DOI","authors":["Jane Adams"],"date":"1995"}"#)
        let citekey = try XCTUnwrap(try LibraryStore(root: root).load().entries.first?.citekey)
        let refs = try extractRefs("References\n\nAdams, J. (1995). An old book without a DOI. Imaginary Press.\n")
        let oa = try openalex([work("W42", doi: "10.9999/book.1", title: "An old book without a DOI", year: 1995, authors: ["Jane Adams"])])
        let (status, output) = try nominate(refs, [oa])
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.refs.first?.storeMatches?.map(\.citekey), [citekey])
        XCTAssertNil(r.refs.first?.candidates.first?.inStore, "DOI 不同，inStore 仍是空的——兩條線索分開給")
    }

    /// T14：第三方 publication_year 的極端值不得讓 nominate trap（#617 verify F15）
    func testExtremePublicationYearDoesNotTrap() throws {
        let refs = try extractRefs("References\n\nAdams, J. (2001). A title. Journal A, 1, 1–2.\n")
        let oa = try write("oa-extreme.json", #"{"results":[{"id":"https://openalex.org/W43","doi":null,"title":"A title","publication_year":-9223372036854775808,"authorships":[]}]}"#)
        let (status, output) = try nominate(refs, [oa])
        XCTAssertEqual(status, 0, output)
    }

    /// 手寫一份 extract 形狀的 refs JSON（構造 extract 產不出的輸入：切壞的標題、極端年份）
    private func manualRefs(title: String, year: Int, firstAuthor: String = "Adams") throws -> String {
        try write("refs-manual-\(UUID().uuidString).json", """
        {"count":1,"contract":2,"warnings":[],"entries":[{"index":1,"raw":"manual","firstAuthor":"\(firstAuthor)",\
        "authors":["\(firstAuthor)"],"groupAuthor":false,"year":\(year),"title":"\(title)"}]}
        """)
    }

    /// T15：DOI 衝突 warning 只計入**這次**涉及的 DOI（R2 G2：原本是全 store 計數，使用者的
    /// store 本來就有 16 組同 DOI 重複，SKILL 又規定一出現就停——每次 run 都會被擋）
    func testConflictWarningCountsOnlyDOIsInThisRun() throws {
        try createEntry(#"{"type":"periodical-article","title":"Unrelated twin","authors":["Zed Q"],"date":"1999","doi":["10.9999/unrelated.1"]}"#)
        try createEntry(#"{"type":"periodical-article","title":"Unrelated twin","authors":["Zed Q"],"date":"1999","doi":["10.9999/unrelated.1"]}"#)
        let refs = try extractRefs("References\n\nAdams, J. (2001). A title. Journal A, 1, 1–2.\n")
        let oa = try openalex([work("W50", doi: "10.9999/other.1", title: "A title", year: 2001, authors: ["Jane Adams"])])
        let (status, output) = try nominate(refs, [oa])
        XCTAssertEqual(status, 0, output)
        XCTAssertFalse(try decode(output).warnings.contains { $0.contains("不只一筆") }, output)
    }

    /// T16：storeMatches 列出門檻以上的**全部**記錄（R2 G3：原本只取前 3，真正那筆排第 4 就漏）。
    ///
    /// **不**發「同分」warning（R3 M3 推翻 R2 G8）：這四筆是不同作者、同標題的書——分數只看標題，
    /// 同分不代表重複，那則 warning 會讓整個 run 停下、把使用者送去 merge-twins 判出「不是攣生」，
    /// 下一次又停；副標不同的真攣生反而不同分、不會警告。是不是同一篇交給逐筆判定（SKILL 第 4 步）。
    func testStoreMatchesListsEveryHitWithoutTieWarning() throws {
        for who in ["Ann One", "Bob Two", "Cat Three", "Dan Four"] {
            try createEntry("{\"type\":\"book\",\"title\":\"Same imaginary title\",\"authors\":[\"\(who)\"],\"date\":\"2001\"}")
        }
        let refs = try extractRefs("References\n\nFour, D. (2001). Same imaginary title. Imaginary Press.\n")
        let oa = try openalex([work("W51", doi: nil, title: "Same imaginary title", year: 2001, authors: ["Dan Four"])])
        let (status, output) = try nominate(refs, [oa])
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.refs.first?.storeMatches?.count, 4)
        XCTAssertFalse(r.warnings.contains { $0.contains("同分") }, "\(r.warnings)")
    }

    /// T17：候選的 OpenAlex 標題也要比對 store（R2 G4：PDF 標題切壞時，只比 PDF 標題會漏網，
    /// 而真正要寫入的是候選那一筆）
    func testCandidateTitleIsAlsoMatchedAgainstStore() throws {
        try createEntry(#"{"type":"book","title":"An imaginary theory of measurement","authors":["Jane Adams"],"date":"1994"}"#)
        let citekey = try XCTUnwrap(try LibraryStore(root: root).load().entries.first?.citekey)
        let refs = try manualRefs(title: "Imaginary thy", year: 1994)
        let oa = try openalex([work("W52", doi: "10.9999/book.9", title: "An imaginary theory of measurement",
                                    year: 1994, authors: ["Jane Adams"])])
        let (status, output) = try nominate(refs, [oa])
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.refs.first?.candidates.first?.storeMatches?.map(\.citekey), [citekey])
    }

    /// T18：`--refs` 的極端年份不得 trap（R2 G7：R1 只擋了 OpenAlex 那側）
    func testExtremeRefYearDoesNotTrap() throws {
        try createEntry(#"{"type":"book","title":"Any title","authors":["Jane Adams"],"date":"1994"}"#)
        let refs = try manualRefs(title: "Any title", year: Int.min)
        let oa = try openalex([work("W53", doi: nil, title: "Any title", year: 1994, authors: ["Jane Adams"])])
        let (status, output) = try nominate(refs, [oa])
        XCTAssertEqual(status, 0, output)
    }

    /// T19：輸出帶 `contract`（R2 G5）
    func testNominateOutputCarriesContract() throws {
        let refs = try extractRefs("References\n\nAdams, J. (2001). A title. Journal A, 1, 1–2.\n")
        let (status, output) = try nominate(refs, [try openalex([])])
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).contract, 2)
    }

    /// T10：輸入 JSON 壞掉 → 非零結束並指名是哪一個輸入。
    func testMalformedInputFailsLoudly() throws {
        let goodRefs = try extractRefs("References\n\nAdams, J. (2001). T. J, 1, 1.\n")
        let badOA = try write("bad-oa.json", "this is not json")
        let (s1, o1) = try nominate(goodRefs, [badOA])
        XCTAssertNotEqual(s1, 0)
        XCTAssertTrue(o1.contains("--openalex"), o1)

        let badRefs = try write("bad-refs.json", "{\"nope\": 1}")
        let goodOA = try openalex([])
        let (s2, o2) = try nominate(badRefs, [goodOA])
        XCTAssertNotEqual(s2, 0)
        XCTAssertTrue(o2.contains("--refs"), o2)
    }
}
