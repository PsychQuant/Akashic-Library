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
        let contract: Int?
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
        // 正文頁也印著同樣的頁首與版權聲明——真實論文的形狀（R2 G10：雜訊的判準改為
        // 「在參考文獻段以外也出現」，只在段內重複的行是正當續行）
        let text = """
        Body text on page eleven.
        RUNNING HEAD IMAGINARY
        This document is copyrighted by the Imaginary Association.

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

    // MARK: - #617 verify 修正輪（F1 F4 F5 F8 F14）

    /// T6：年份括號的其他寫法都要認得——認不得時下一筆會被當成續行無聲併入（F1）
    func testOtherYearFormsAreYearParens() throws {
        let text = """
        References

        Adams, A. (in preparation). A manuscript in preparation. Unpublished.
        Baker, B. (submitted). A submitted manuscript. Unpublished.
        Carter, C. (1890/1950). A reprinted classic. Imaginary Press.
        Dole, D. (1998–99). A two-year span. Journal D, 1, 1–2.
        Evans, E. (2015–). An ongoing series. Journal E.
        Fox, F. (forthcoming). A forthcoming book. Imaginary Press.
        Gray, G. (2004). A plain year. Journal G, 2, 3–4.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.entries.map(\.firstAuthor), ["Adams", "Baker", "Carter", "Dole", "Evans", "Fox", "Gray"])
        guard r.entries.count == 7 else { return }
        XCTAssertEqual(r.entries.map(\.year), [nil, nil, 1890, 1998, 2015, nil, 2004])
        XCTAssertEqual(r.entries.map(\.yearNote), ["in preparation", "submitted", nil, nil, nil, "forthcoming", nil])
        XCTAssertEqual(r.entries[2].title, "A reprinted classic")
    }

    /// T7：仍然認不得的年份寫法 → 併筆無法避免，但一定要有 warning（F1：原本 `year == nil`
    /// 那條永遠不會觸發，因為併入後的條目帶著下一筆的年份）
    func testAbsorbedEntryStartIsWarned() throws {
        let text = """
        References

        Adams, J. (circa 1900). An undated old text. Imaginary Press.
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.count, 1)
        XCTAssertTrue(r.warnings.contains { $0.contains("第 1 筆") && $0.contains("併") }, "\(r.warnings)")
    }

    /// T7b：作者清單換行（上一行以 `&` 或逗號結尾）不是併筆，不得誤報
    func testWrappedAuthorListIsNotWarnedAsMerge() throws {
        let text = """
        References

        Chen, H.-Y., Diaz, R., &
            Garcia, T. (2012). Within-person title. Journal C, 8, 1–20.
        Hughes, A., Ito, K.,
            Jensen, S. (2015). Another wrapped list. Journal H, 3, 1–2.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.count, 2)
        XCTAssertFalse(r.warnings.contains { $0.contains("併") }, "\(r.warnings)")
    }

    /// T8：出版地續行（`Cambridge, U.K.:`）不是新條目開頭
    func testPublisherLocationLineIsNotAnEntryStart() throws {
        let text = """
        References

        Adams, J. (2001). A book title. Cambridge University Press,
        Cambridge, U.K.: Imaginary.
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.entries.map(\.firstAuthor), ["Adams", "Baker"])
    }

    /// T9：機構名裡有句點（`U.S. Department …`）仍是條目開頭
    func testGroupAuthorWithPeriodsStartsAnEntry() throws {
        let text = """
        References

        Adams, J. (2001). First title. Journal A, 1, 1–2.
        U.S. Department of Imaginary Affairs. (2019). A pretend report. Author.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.count, 2)
        guard r.entries.count == 2 else { return }
        XCTAssertEqual(r.entries[1].firstAuthor, "U.S. Department of Imaginary Affairs")
        XCTAssertTrue(r.entries[1].groupAuthor)
        XCTAssertEqual(r.entries[1].year, 2019)
    }

    /// T10：參考文獻段之後的表格欄名 `Reference` 不得奪走標題（F4）——取條目開頭最多的
    /// 那個標題，有多個候選時說出來
    func testLaterReferenceLineDoesNotHijackTheSection() throws {
        let text = """
        References

        Adams, J. K. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). Second title. Journal B, 2, 3–4.

        Table 1

        Studies included
        Reference
        Smith, Q. (2001). A table cell. n = 40
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.entries.map(\.firstAuthor), ["Adams", "Baker"])
        XCTAssertTrue(r.warnings.contains { $0.contains("標題候選") }, "\(r.warnings)")
    }

    /// T11：找到標題、段落裡卻沒有任何條目 → 非零結束，不是空清單（F5）
    func testHeadingWithNoEntriesFailsLoudly() throws {
        let (status, output) = try extract("References\n\nAppendix\n\nSomething else.\n")
        XCTAssertNotEqual(status, 0)
        XCTAssertTrue(output.contains("沒有辨識出任何條目"), output)
    }

    /// T12：短的連字號大寫詞不得造成指數回溯（F8，ReDoS）
    func testPathologicalHyphenatedLineIsFast() throws {
        let bad = String(repeating: "Aa-", count: 21) + "Aa!"   // 修正前約 45 秒（每多一段約 ×2.8）
        let text = "References\n\nAdams, J. (2001). First title. Journal A.\n\(bad)\nBaker, L. (2002). Second. Journal B.\n"
        let start = Date()
        let (status, output) = try extract(text)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "extract 花了太久——正則回溯")
        XCTAssertEqual(status, 0, output)
    }

    /// T13：APA 在標點前斷行的 DOI 要接回來，不得截成看似合法的錯 DOI（F14）
    func testDOIWrappedBeforePunctuationIsRejoined() throws {
        let text = """
        References

        Adams, J. (2001). First title. Journal A, 1, 1–2. https://doi.org/10.9999/0022-3514
        .40.2.226
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.first?.doi, "10.9999/0022-3514.40.2.226")
    }

    /// T14：標題裡的小數點不是句末（F14）
    func testDecimalPointDoesNotEndTheTitle() throws {
        let text = """
        References

        Adams, J. (2001). Version 2.5 of the imaginary model. Journal A, 1, 1–2.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.first?.title, "Version 2.5 of the imaginary model")
    }

    // MARK: - #617 verify R2 修正輪（G1 G4 G5 G10）

    /// T10b：清單**前**的表格欄名 `Reference` 不得奪走標題（G1：R1 修正取「條目開頭最多」，
    /// 但較早候選的段落延伸到真正清單、是它的超集，結構上必勝）
    func testTableBeforeTheListDoesNotHijackTheSection() throws {
        let text = """
        Body text before the table.
        Table 1. Studies included in the imaginary review
        Reference
        Quinn et al. (2011)
        Rivera and Soto (2014)
        Results
        The pooled effect was small, as Quinn et al. (2011) also argued.

        References

        Adams, J. K. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        Carter, M. (2003). Third title. Journal C, 3, 5–6.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.map(\.firstAuthor), ["Adams", "Baker", "Carter"])
    }

    /// T10c：目錄的 `References` 不得奪走標題，也不得讓整篇被誤判成編號制（G1）
    func testTableOfContentsDoesNotHijackTheSection() throws {
        let text = """
        Contents
        1. Introduction
        2. Method
        References
        3. Results
        Hamaker et al. (2015) showed this in the body.

        References

        Adams, J. K. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.map(\.firstAuthor), ["Adams", "Baker"])
    }

    /// T15：標題不在 `vs.`／`ed.` 截斷，尾端的版次括號去掉（G4：無 DOI 的書靠標題比對 store）
    func testTitleSurvivesAbbreviationsAndDropsEdition() throws {
        let text = """
        References

        Adams, J. (1994). Psychometric imaginary theory (3rd ed.). Imaginary Press.
        Baker, L. (2001). Latent vs. manifest change in imaginary panels. Journal B, 2, 3–4.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.map(\.title),
                       ["Psychometric imaginary theory", "Latent vs. manifest change in imaginary panels"])
    }

    /// T16：輸出帶 `contract`，讓 skill 分辨得出太舊的 CLI（G5）
    func testOutputCarriesContractVersion() throws {
        let (status, output) = try extract("References\n\nAdams, J. (2001). A title. Journal A.\n")
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).contract, 2)
    }

    /// T17：APA 7 以刪節號省略作者時，換行不是併筆；小寫接在連字號後的姓、分號結尾的出版地（G10）
    func testEllipsisHyphenatedLowercaseAndSemicolonLocation() throws {
        let text = """
        References

        Adams, A., Baker, B., Carter, C., . . .
            Zed, Z. (2020). A very large collaboration. Journal Z, 1, 1–2.
        Al-khatib, R. (2019). A hyphenated lowercase surname. Journal R, 2, 3–4.
        Moss, T. (2018). A book title. Imaginary Press,
        Oxford, U.K.; New York.
        Nolan, U. (2017). Last title. Journal N, 4, 5–6.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.entries.map(\.firstAuthor), ["Adams", "Al-khatib", "Moss", "Nolan"])
        XCTAssertFalse(r.warnings.contains { $0.contains("併") }, "\(r.warnings)")
        XCTAssertFalse(r.entries[1].groupAuthor)
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

    // MARK: - #617 verify R2 餘項（G6、G10）

    /// T18：清單中間的圖表標題（雙欄期刊的浮動圖表）不得截斷清單（G6）——
    /// 略過那一行、繼續切分，並說出來
    func testFloatCaptionInsideTheListDoesNotTruncateIt() throws {
        let text = """
        References

        Adams, J. K. (2001). First title. Journal A, 1, 1–2.
        Table 3
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        Carter, M. (2003). Third title. Journal C, 3, 5–6.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.entries.map(\.firstAuthor), ["Adams", "Baker", "Carter"])
        XCTAssertTrue(r.warnings.contains { $0.contains("圖表標題") && $0.contains("第 4 行") }, "\(r.warnings)")
    }

    /// T18b：附錄等結束標題之後若還有條目開頭，停在那裡、但要說出被擋在外面的數目（G6）
    func testEndHeadingFollowedByEntriesIsWarned() throws {
        let text = """
        References

        Adams, J. K. (2001). First title. Journal A, 1, 1–2.
        Appendix A
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.count, 1)
        XCTAssertTrue(r.warnings.contains { $0.contains("第 4 行") && $0.contains("1 個條目開頭") }, "\(r.warnings)")
    }

    /// T19：warning 的行號就是檔案的行號——pdftotext 每頁結尾的 `\n\f` 不得多算一行（G10）
    func testLineNumbersDoNotDriftAcrossPageBreaks() throws {
        let text = "Intro text.\n\u{0C}More text.\n\u{0C}References\n\n"
            + "Adams, J. K. (2001). First title. Journal A, 1, 1–2.\n"
            + "Baker, L. (2002). Second title. Journal B, 2, 3–4.\n"
            + "Reference\nSmith, Q. (2001). A table cell. n = 40\n"
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertTrue(r.warnings.contains { $0.contains("標題候選") && $0.contains("第 3 行") }, "\(r.warnings)")
    }

    /// T20：只在參考文獻段裡重複的續行（同一家出版社的兩章）是條目的一部分，不是頁首（G10）；
    /// 被略過的行只以條目序號回報，warning 不帶 PDF 原文
    func testRepeatedLineOnlyInsideTheListIsKept() throws {
        let text = """
        Body text on page one.
        RUNNING HEAD IMAGINARY
        Body text on page two.
        RUNNING HEAD IMAGINARY

        References

        Adams, J. K. (2001). First chapter. In B. Editor (Ed.), Book one (pp. 1–2).
        New York, NY: Imaginary Press.
        Baker, L. (2002). Second chapter. In C. Editor (Ed.), Book two (pp. 3–4).
        RUNNING HEAD IMAGINARY
        New York, NY: Imaginary Press.
        Carter, M. (2003). Third title. Journal C, 3, 5–6.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.count, 3)
        guard r.entries.count == 3 else { return }
        XCTAssertTrue(r.entries[0].raw.hasSuffix("New York, NY: Imaginary Press."), r.entries[0].raw)
        XCTAssertTrue(r.entries[1].raw.hasSuffix("New York, NY: Imaginary Press."), r.entries[1].raw)
        XCTAssertFalse(r.entries[1].raw.contains("RUNNING HEAD"), r.entries[1].raw)
        XCTAssertTrue(r.warnings.contains { $0.contains("略過 1 行") && $0.contains("第 2 筆") }, "\(r.warnings)")
        XCTAssertFalse(r.warnings.contains { $0.contains("RUNNING HEAD") || $0.contains("Imaginary Press") },
                       "warnings 不得帶 PDF 原文：\(r.warnings)")
    }

    /// T21：DOI／URL 在 `(`、`?` 等其他標點前斷行也要接回（G10）；但後面接的是帶空白的
    /// 括號附註（`(Original work published …)`）時不接
    func testDOIWrappedBeforeOtherPunctuationIsRejoined() throws {
        let text = """
        References

        Adams, J. (2001). First title. Journal A, 1, 1–2. https://doi.org/10.9999/(SICI)1097-4679
        (199901)55:1<1::AID-JCLP1>3.0.CO;2-X
        Baker, L. (2002). Second title. Retrieved from https://example.org/page
        ?id=42
        Carter, M. (1950/2003). Third title. Imaginary Press. https://doi.org/10.9999/xyz
        (Original work published 1950)
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        guard r.entries.count == 3 else { return XCTFail("\(r.entries.map(\.raw))") }
        XCTAssertEqual(r.entries[0].doi, "10.9999/(SICI)1097-4679(199901)55:1<1::AID-JCLP1>3.0.CO;2-X")
        XCTAssertTrue(r.entries[1].raw.contains("https://example.org/page?id=42"), r.entries[1].raw)
        XCTAssertEqual(r.entries[2].doi, "10.9999/xyz")
        XCTAssertTrue(r.entries[2].raw.contains("xyz (Original work"), r.entries[2].raw)
    }

    // MARK: - #617 verify R3

    /// T22：書的每一頁都印著 `References` 頁首時，清單不得被切成一頁一段（R3 H1——R2 的 G1 修正
    /// 造成的迴歸）。頁首後的條目按字母順序接得上，就是同一份清單
    func testRepeatedReferencesRunningHeadDoesNotCutTheList() throws {
        let text = "Body text.\n\nReferences\n\n"
            + "Adams, J. K. (2001). First title. Journal A, 1, 1–2.\n"
            + "Baker, L. (2002). Second title. Journal B, 2, 3–4.\n"
            + "\u{0C}123\nReferences\n"
            + "Carter, M. (2003). Third title. Journal C, 3, 5–6.\n"
            + "Dunn, P. (2004). Fourth title. Journal D, 4, 7–8.\n"
            + "\u{0C}124\nReferences\n"
            + "Evans, Q. (2005). Fifth title. Journal E, 5, 9–10.\n"
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.entries.map(\.firstAuthor), ["Adams", "Baker", "Carter", "Dunn", "Evans"])
        XCTAssertFalse(r.warnings.contains { $0.contains("標題候選") }, "\(r.warnings)")
        XCTAssertTrue(r.warnings.contains { $0.contains("頁首") }, "\(r.warnings)")
    }

    /// T23：書末索引（`姓, 名縮寫., 頁碼`）不是清單的一部分（R3 H1：`Index` 不在結束標題裡，
    /// 索引行又長得像條目開頭）
    func testBookIndexIsNotPartOfTheList() throws {
        var text = "References\n\nAdams, J. K. (2001). First title. Journal A, 1, 1–2.\n"
            + "Baker, L. (2002). Second title. Journal B, 2, 3–4.\n\u{0C}Index\n"
        for name in ["Imagin, T. M., 288, 289", "Jover, P., 12", "Kello, A. B., 45, 46", "Lumin, R., 7"] {
            text += name + "\n"
        }
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.map(\.firstAuthor), ["Adams", "Baker"])
    }

    /// T24：雙欄期刊裡，`SUPPLEMENTARY MATERIAL` 之類的結束標題會穿插在清單中間（R3 M1）——
    /// 之後的條目字母順序接得上、又是完整條目，清單就接續，並說出略過了什麼
    func testInterleavedEndHeadingDoesNotTruncateTheList() throws {
        let text = """
        References

        Adams, J. K. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        SUPPLEMENTARY MATERIAL
        The Supplementary Material for this article can be found online.
        Carter, M. (2003). Third title. Journal C, 3, 5–6.
        Dunn, P. (2004). Fourth title. Journal D, 4, 7–8.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.entries.map(\.firstAuthor), ["Adams", "Baker", "Carter", "Dunn"])
        XCTAssertFalse(r.entries[1].raw.contains("Supplementary"), r.entries[1].raw)
        XCTAssertTrue(r.warnings.contains { $0.contains("接續") && $0.contains("第 5 行") }, "\(r.warnings)")
    }

    /// T32：雙欄版面裡 pdftotext 會把兩欄讀反——結束標題之前是清單的後半（C 開頭），之後才是前半
    /// （A 開頭）。之後的條目排在這份清單開頭之前，就是另一欄，不是新清單（R3 M1，本機真實論文實測
    /// 的兩例都是這個形狀）
    func testColumnSwappedListAcrossAnEndHeadingIsKept() throws {
        let text = """
        References

        Carter, M. (2003). Third title. Journal C, 3, 5–6.
        Dunn, P. (2004). Fourth title. Journal D, 4, 7–8.
        ACKNOWLEDGMENTS
        We thank the imaginary participants.
        Adams, J. K. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.entries.map(\.firstAuthor), ["Carter", "Dunn", "Adams", "Baker"])
        XCTAssertTrue(r.warnings.contains { $0.contains("另一欄") && $0.contains("第 5 行") }, "\(r.warnings)")
    }

    /// T25：清單之後的表格與圖（APA 稿件的版面）不得被略過成「夾在清單中間」而產生幻影條目
    /// （R3 M2）——表格列不是完整條目，字母順序也接不上
    func testTrailingTablesAfterTheListStayOut() throws {
        let text = """
        References

        Adams, J. K. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        Table 1
        Descriptive statistics
        Age, M. (SD) 20.1 2.3
        Table 2
        Included studies
        Carter, M. (2003) 120 .35
        Dunn, P. (2004) 88 .41
        Figure 1
        Model diagram
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.entries.map(\.firstAuthor), ["Adams", "Baker"])
        XCTAssertFalse(r.entries[1].raw.contains("Descriptive"), r.entries[1].raw)
        XCTAssertFalse(r.warnings.contains { $0.contains("接續") }, "\(r.warnings)")
    }

    /// T26：清單之後有很多圖表標題時不得變慢（R3 M2：原本 O(圖表數 × 行數)，60 個圖 11 秒）
    func testManyTrailingFiguresStayFast() throws {
        var text = "References\n\n"
        for i in 0..<150 { text += "Author\(String(repeating: "a", count: 1 + i % 5)), J. (2001). Title \(i). Journal, 1, 1–2.\n" }
        for i in 1...60 { text += "Figure \(i)\nCaption text for figure \(i).\n" }
        text += "Zed, A. (2020). Stray line. Journal, 1, 1.\n"
        let start = Date()
        let (status, output) = try extract(text)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3, "extract 花了太久")
        XCTAssertEqual(status, 0, output)
    }

    /// T27：標題真的以 `no.` 結尾時不得吞進期刊名（R3 M9）；`No. 2` 仍不算句末
    func testTitleEndingInAbbreviationWordEndsThere() throws {
        let text = """
        References

        Adams, J. (2001). Learning to say no. Journal of Testing, 2, 1–3.
        Baker, L. (2002). Report No. 2 on things. Journal B, 2, 3–4.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.map(\.title), ["Learning to say no", "Report No. 2 on things"])
    }

    /// T28：書名尾端的冊次、版次、編者括號都不屬於標題；`St.` 不是句末（R3 M8——G4 的部分修正）
    func testBookTitleParentheticalsAreStripped() throws {
        let text = """
        References

        Adams, J. (2001). Handbook of imaginary psychology (6th ed., Vol. 3). Imaginary Press.
        Baker, L. (2002). Imaginary methods (Vol. 2). Imaginary Press.
        Carter, M. (2003). Imaginary handbook (J. Smith, Ed.; 3rd ed.). Imaginary Press.
        Dunn, P. (2004). Travels to St. Imaginary. Imaginary Press.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.map(\.title),
                       ["Handbook of imaginary psychology", "Imaginary methods", "Imaginary handbook", "Travels to St. Imaginary"])
    }

    /// T29：以分號分隔的作者清單不得變成機構作者或併進前一筆（R3 L1——R2 的 `[:;]` 前瞻造成）；
    /// 出版地 `Oxford, U.K.; New York, NY:` 仍不是條目開頭
    func testSemicolonAuthorListsAreNotMisread() throws {
        let text = """
        References

        Adams, J. K. (2001). First title. In B. Editor (Ed.), Book one (pp. 1–2).
        Oxford, U.K.; New York, NY: Imaginary Press.
        Baker, L.; Cole, M.;
        Dean, P. (2002). Second title. Journal B, 2, 3–4.
        Smith, J.; Jones, K. (2003). Third title. Journal C, 3, 5–6.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.entries.map(\.firstAuthor), ["Adams", "Baker", "Smith"])
        XCTAssertEqual(r.entries.map(\.groupAuthor), [false, false, false])
        XCTAssertFalse(r.warnings.contains { $0.contains("吸收") }, "\(r.warnings)")
    }

    /// T30：只有清單、沒有正文頁的輸入（貼上的參考文獻頁、節錄）——頁首仍是雜訊（R3 L2）。
    /// 這是 R2 改寫前 T2 的原 fixture，留作獨立的測試
    func testListOnlyInputStillDropsRepeatedRunningHeads() throws {
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
        XCTAssertEqual(r.entries.map(\.title), ["First title", "Second title", "Third title spanning two lines"])
    }

    /// T31：空白頁（`\f\f`）與行尾軟連字號不得讓 warning 的行號漂移；warning 同時報 PDF 頁碼，
    /// 使用者才對照得到（R3 L3）
    func testLineAndPageNumbersSurviveBlankPagesAndSoftHyphens() throws {
        let text = "Intro.\n\u{0C}\u{0C}More.\nsoft\u{AD}\nhyphen\nReferences\n\n"
            + "Adams, J. K. (2001). First title. Journal A, 1, 1–2.\n"
            + "Baker, L. (2002). Second title. Journal B, 2, 3–4.\n"
            + "Reference\nSmith, Q. (2001). A table cell. n = 40\n"
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertTrue(r.warnings.contains { $0.contains("標題候選") && $0.contains("第 5 行") && $0.contains("PDF 第 3 頁") },
                      "\(r.warnings)")
    }
}
