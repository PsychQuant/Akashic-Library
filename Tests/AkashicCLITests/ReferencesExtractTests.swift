import XCTest
import Foundation

/// `akashic references extract --text <file>`（#617）：從 `pdftotext` 的輸出切出參考文獻段、
/// 逐筆切分、抽欄位。
///
/// **fixture 全是手寫的虛構條目**——作者、期刊、標題都是編的。第三方論文的參考文獻原文不進
/// repo；真實論文的校準只在使用者本機跑、只記數字（#617 Implementation Plan）。期望值逐欄手寫，
/// 不由實作推出。
final class ReferencesExtractTests: XCTestCase {

    private struct Ref: Decodable {
        let index: Int
        let raw: String
        let firstAuthor: String?
        let authors: [String]
        let groupAuthor: Bool
        let year: Int?
        let yearSuffix: String?
        let yearNote: String?
        let title: String?
        let doi: String?
    }
    private struct Result: Decodable {
        let count: Int
        let entries: [Ref]
        let warnings: [String]
    }

    private func extract(_ text: String) throws -> (status: Int32, output: String) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("refs-\(UUID().uuidString).txt")
        try text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return try CLITestHarness.run(["references", "extract", "--text", url.path], env: [:])
    }

    private func decode(_ output: String) throws -> Result {
        try JSONDecoder().decode(Result.self, from: Data(output.utf8))
    }

    /// T1：標準作者—年份段，含作者清單換行（`&` 結尾的下一行看起來像新條目）與續行
    func testSplitsStandardAuthorYearListAndExtractsFields() throws {
        let text = """
        The body of the paper ends here and mentions nothing else.

        References

        Adams, J. K., & Baker, L. M. (2010). Modeling change in repeated measures:
            A tutorial. Journal of Imaginary Methods, 12(3), 45–67.
        Chen, H.-Y., Diaz, R., Evans, P. Q., Fischer, M., &
            Garcia, T. (2012). Within-person fluctuation and between-person differences.
            Fictional Psychological Review, 8, 1–20. https://doi.org/10.9999/fpr.2012.001
        Hughes, A. (2015a). Cross-lagged panel models revisited. Imaginary Statistics, 3(1), 100–
            120.
        Hughes, A. (2015b). Random intercepts and stable traits. Imaginary Statistics, 3(2),
            121–140.
        Ito, K., Jensen, S., Kim, D., Lopez, M., Moore, N., Novak, O., & Olsen, P. (2018).
            Large collaborations and author lists. Journal of Pretend Science, 5, 9–30.
        van der Berg, W. (2020). A book about longitudinal data. Imaginary Press.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.count, 6)
        XCTAssertEqual(r.entries.map(\.firstAuthor), ["Adams", "Chen", "Hughes", "Hughes", "Ito", "van der Berg"])
        XCTAssertEqual(r.entries[0].authors, ["Adams", "Baker"])
        XCTAssertEqual(r.entries[1].authors, ["Chen", "Diaz", "Evans", "Fischer", "Garcia"])
        XCTAssertEqual(r.entries[4].authors.count, 7)
        XCTAssertEqual(r.entries.map(\.year), [2010, 2012, 2015, 2015, 2018, 2020])
        XCTAssertEqual(r.entries.map(\.yearSuffix), [nil, nil, "a", "b", nil, nil])
        XCTAssertEqual(r.entries.map(\.title), [
            "Modeling change in repeated measures: A tutorial",
            "Within-person fluctuation and between-person differences",
            "Cross-lagged panel models revisited",
            "Random intercepts and stable traits",
            "Large collaborations and author lists",
            "A book about longitudinal data",
        ])
        XCTAssertEqual(r.entries[1].doi, "10.9999/fpr.2012.001")
        XCTAssertNil(r.entries[0].doi)
        XCTAssertEqual(r.entries.map(\.index), [1, 2, 3, 4, 5, 6])
    }

    /// T2：頁碼、重複的頁首與版權聲明夾在段中——不成為條目，也不併進條目
    func testPageNoiseIsNeitherAnEntryNorMergedIntoOne() throws {
        let text = """
        References

        Adams, J. K. (2001). First title. Journal A, 1, 1–2.
        12
        RUNNING HEAD IMAGINARY
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        This document is copyrighted by the Imaginary Association.
        Carter, M. (2003). Third title spanning
        13
        RUNNING HEAD IMAGINARY
        two lines. Journal C, 3, 5–6.
        This document is copyrighted by the Imaginary Association.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.count, 3)
        XCTAssertEqual(r.entries.map(\.title), ["First title", "Second title", "Third title spanning two lines"])
        for e in r.entries {
            XCTAssertFalse(e.raw.contains("RUNNING HEAD"), e.raw)
            XCTAssertFalse(e.raw.contains("copyrighted"), e.raw)
        }
    }

    /// T2b：頁首與版權聲明在參考文獻段只出現一次、但在全文每頁都有——仍是雜訊。
    /// （#617 校準：參考文獻段只跨兩頁時，段內計數抓不到它們，於是併進了條目原文。）
    func testRunningHeadsAreCountedAcrossTheWholeDocument() throws {
        let text = """
        Body text on page one.
        IMAGINARY, AUTHORS, AND OTHERS
        This document is copyrighted by the Imaginary Association.
        Body text on page two.
        IMAGINARY, AUTHORS, AND OTHERS
        This document is copyrighted by the Imaginary Association.

        References

        Adams, J. K. (2001). First title. In B. Editor (Ed.), Book of chapters
        This document is copyrighted by the Imaginary Association.
        IMAGINARY, AUTHORS, AND OTHERS
        (pp. 1–2). Imaginary Press.
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.count, 2)
        XCTAssertFalse(r.entries[0].raw.contains("copyrighted"), r.entries[0].raw)
        XCTAssertFalse(r.entries[0].raw.contains("IMAGINARY, AUTHORS"), r.entries[0].raw)
        XCTAssertTrue(r.entries[0].raw.hasSuffix("(pp. 1–2). Imaginary Press."), r.entries[0].raw)
    }

    /// T4b：年份區間（軟體手冊、多年報告）也是年份括號——否則這筆沒有年份，
    /// 下一筆會被當成續行併進來（#617 校準：一篇 63 筆的清單因此切成 62 筆）。
    func testYearRangeIsAYearParen() throws {
        let text = """
        References

        Quinn, A., & Quinn, B. (1998 –2012). Imaginary software user’s guide. Pretend Press.
        Ross, C. (2001). A title after the range. Journal R, 1, 1–2.
        Stone, D. (2003–2005). Multi-year report. Imaginary Agency.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.entries.map(\.firstAuthor), ["Quinn", "Ross", "Stone"])
        XCTAssertEqual(r.entries.map(\.year), [1998, 2001, 2003])
        XCTAssertEqual(r.entries[0].title, "Imaginary software user’s guide")
        XCTAssertEqual(r.entries[2].title, "Multi-year report")
    }

    /// T3：標題前的正文、Appendix 之後的內容都不進清單
    func testOnlyTheReferencesSectionIsRead() throws {
        let text = """
        As the references below show, this sentence is body text, not a heading.
        Old, A. (1990). A body-text lookalike that precedes the heading. Journal O.

        REFERENCES

        Adams, J. K. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). Second title. Journal B, 2, 3–4.

        Appendix

        Zed, Q. (1999). An appendix lookalike that must be excluded. Journal Z.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.entries.map(\.firstAuthor), ["Adams", "Baker"])
    }

    /// T3b：找不到參考文獻標題 → 非零結束並說明，而不是回一份空清單
    func testMissingHeadingFailsLoudly() throws {
        let (status, output) = try extract("Adams, J. K. (2001). First title. Journal A.\n")
        XCTAssertNotEqual(status, 0)
        XCTAssertTrue(output.contains("找不到參考文獻段"), output)
    }

    /// T4：DOI 兩種寫法、et al.、書的章節、機構作者、in press
    func testVariantShapes() throws {
        let text = """
        Bibliography

        Lee, K. (2011). Chapter title here. In M. Editor & N. Editor (Eds.), Book title (pp. 1–10). Publisher.
        Moss, T., Nolan, U., et al. (2019). Using et al. in a list. Journal M, 2, 1–5. doi:10.1234/abc.5
        Price, V. (2016). Dx resolver form. Journal P, 4, 7–8. https://dx.doi.org/10.5555/XYZ-9.
        Quinn, R. (in press). Forthcoming title. Journal Q.
        World Imaginary Organization. (2019). Guidelines for pretend research. Author.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.count, 5)
        XCTAssertEqual(r.entries[0].title, "Chapter title here")
        XCTAssertEqual(r.entries[1].authors, ["Moss", "Nolan"])
        XCTAssertEqual(r.entries[1].doi, "10.1234/abc.5")
        XCTAssertEqual(r.entries[2].doi, "10.5555/XYZ-9")
        XCTAssertNil(r.entries[3].year)
        XCTAssertEqual(r.entries[3].yearNote, "in press")
        XCTAssertEqual(r.entries[3].title, "Forthcoming title")
        XCTAssertEqual(r.entries[4].firstAuthor, "World Imaginary Organization")
        XCTAssertTrue(r.entries[4].groupAuthor)
        XCTAssertEqual(r.entries[4].year, 2019)
        XCTAssertEqual(r.entries[4].title, "Guidelines for pretend research")
    }

    /// T5：數字編號格式 → 明確回報不支援，不硬切
    func testNumberedStyleIsRejected() throws {
        let text = """
        References

        [1] A. Adams, "First," J. A, 2001.
        [2] B. Baker, "Second," J. B, 2002.
        [3] C. Carter, "Third," J. C, 2003.
        """
        let (status, output) = try extract(text)
        XCTAssertNotEqual(status, 0)
        XCTAssertTrue(output.contains("不支援"), output)
    }
}
