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
    }
    private struct RefNomination: Decodable {
        let index: Int
        let candidates: [Candidate]
    }
    private struct Work: Decodable {
        let openalex: String
        let inStore: String?
    }
    private struct Result: Decodable {
        let refs: [RefNomination]
        let unnominated: [Work]
        let warnings: [String]
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
