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

    /// T16：輸出帶 `contract`，讓 skill 分辨得出太舊的 CLI（G5）。R4 A4：warning 的語意在 R3 改了
    /// （多段 warning 列各段數目、頁首與接續 warning、頁碼、拿掉「同分」），契約加一到 3。R6：新增「過長」
    /// 與「最後一筆還沒結束」、多段 warning 改列最多的 5 段，加一到 4。R7：「還沒結束」擴及文字結尾與另一個
    /// 參考文獻標題，新增「下一行以小寫開頭」，加一到 5
    func testOutputCarriesContractVersion() throws {
        let (status, output) = try extract("References\n\nAdams, J. (2001). A title. Journal A.\n")
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).contract, 5)
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
        XCTAssertTrue(r.warnings.contains { $0.contains("接續") && $0.contains("第 5 行") && $0.contains("第 2 筆之後") },
                      "\(r.warnings)")
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
        // R4 B6：補回原 T2 的斷言（R3 改寫 T2 時保留了 fixture，卻拿掉了對 raw 與筆數的斷言）
        XCTAssertEqual(r.count, 3)
        XCTAssertEqual(r.entries.map(\.title), ["First title", "Second title", "Third title spanning two lines"])
        for e in r.entries {
            XCTAssertFalse(e.raw.contains("RUNNING HEAD"), e.raw)
            XCTAssertFalse(e.raw.contains("copyrighted"), e.raw)
        }
        // 沒有正文可對照時，warning 要說實話：是以段內重複判定的，不是「在段外也出現」
        XCTAssertTrue(r.warnings.contains { $0.contains("段內重複") }, "\(r.warnings)")
        XCTAssertFalse(r.warnings.contains { $0.contains("段外也出現") }, "\(r.warnings)")
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

    // MARK: - #617 verify R4

    /// T33：頁首合併時，跨頁條目的後半（標題其餘、出處、DOI）要留在那一筆裡（R4 A1——R3 直接跳到
    /// 下一筆，中間的行無聲丟掉）
    func testRunningHeadKeepsTheTailOfAPageSpanningEntry() throws {
        let text = "References\n\nAdams, J. (2001). A title continued\n\u{0C}References\n"
            + "across pages. Journal A, 1, 1–2.\nhttps://doi.org/10.1234/example\n"
            + "Baker, L. (2002). Another title. Journal B, 2, 3–4.\n"
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.count, 2)
        guard r.count == 2 else { return }
        XCTAssertEqual(r.entries[0].title, "A title continued across pages")
        XCTAssertEqual(r.entries[0].doi, "10.1234/example")
        XCTAssertFalse(r.entries[0].raw.contains("References"), r.entries[0].raw)
    }

    /// T34：作者清單換行的那一行（`Zimmerman, P.`）不得變成排序鍵——排序比的是每一筆的第一作者
    /// （R4 A2：原本拿共同作者去比，排序正確的清單在頁首處被切開）
    func testCoAuthorWrapLineDoesNotResetTheSortKey() throws {
        let text = "References\n\nAdams, J. (2001). First title. Journal A, 1, 1–2.\nBaker, L., &\n"
            + "Zimmerman, P. (2002). Second title. Journal B, 2, 3–4.\n\u{0C}References\n"
            + "Carter, M. (2003). Third title. Journal C, 3, 5–6.\n"
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.entries.map(\.firstAuthor), ["Adams", "Baker", "Carter"])
        XCTAssertFalse(r.warnings.contains { $0.contains("標題候選") }, "\(r.warnings)")
    }

    /// T35：雙欄讀反只會發生一次——之後不再接受「排在清單開頭之前」（R4 A3-1：原本
    /// `[≥ last] ∪ [< first]` 從此涵蓋整個字母表）。
    ///
    /// R5 D4 修正了 R4 的做法：R4 另設上界 `upper`，只接受讀反那一欄的範圍；本機僅有的兩份真實雙欄
    /// 讀反，讀反之後都一路排過了 `upper`，上界會在下一個斷點截斷真實清單。所以這裡改成：讀反之後
    /// 照一般規則（不排在最後一筆之前）接續，只是不能再讀反一次。原 fixture 的 `Zed` 排在 Baker 之後，
    /// 依一般規則本來就接得上，換成排在 Baker 之前的 `Aaa`
    func testColumnSwapHappensOnlyOnce() throws {
        let text = """
        References

        Carter, M. (2003). Third title. Journal C, 3, 5–6.
        Dunn, P. (2004). Fourth title. Journal D, 4, 7–8.
        ACKNOWLEDGMENTS
        We thank the imaginary participants.
        Adams, J. K. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        Author Note
        Aaa, Q. (2019). Not part of the list. Journal Q, 9, 1–2.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.entries.map(\.firstAuthor), ["Carter", "Dunn", "Adams", "Baker"])
        XCTAssertTrue(r.warnings.contains { $0.contains("清單停在") }, "\(r.warnings)")
    }

    /// T36：雙欄讀反的接續條件只用在結束標題，不用在圖表（R4 A3-2）
    func testColumnSwapDoesNotApplyAfterAFloat() throws {
        let text = """
        References

        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        Dunn, P. (2004). Fourth title. Journal D, 4, 7–8.
        Table 1
        Abbott, R. (2003). A row that looks like an entry. Journal R, 1, 1–2.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.map(\.firstAuthor), ["Baker", "Dunn"])
    }

    /// T37：圖表之後緊接著穿插的結束標題（補充資料），清單仍要接續（R4 A3-3：原本在結束標題處
    /// 就停，清單在圖表處截斷且沒有 warning）
    func testFloatFollowedByInterleavedEndHeadingContinues() throws {
        let text = """
        References

        Adams, J. K. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        Table 2
        Table body text
        SUPPLEMENTARY MATERIAL
        The Supplementary Material for this article can be found online.
        Carter, M. (2003). Third title. Journal C, 3, 5–6.
        Dunn, P. (2004). Fourth title. Journal D, 4, 7–8.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.map(\.firstAuthor), ["Adams", "Baker", "Carter", "Dunn"])
    }

    /// T38：圖表出現在第一筆之前（標題孤立在頁尾、下一頁先是圖），清單不得變空，也不得改選後面的
    /// 表格欄名 `Reference`（R4 A3-4：R1 的失敗模式）
    func testFloatBeforeTheFirstEntryDoesNotEmptyTheList() throws {
        let text = """
        References
        Figure 1
        Caption text for the figure.
        Adams, J. K. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        Carter, M. (2003). Third title. Journal C, 3, 5–6.
        Reference
        Smith, Q. (2001). A table cell. n = 40
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.map(\.firstAuthor), ["Adams", "Baker", "Carter"])
    }

    /// T39：參考文獻標題之前、同一頁就有完整條目——雙欄版面把清單的一部分讀到標題之前了，要說出來
    /// （R4 A7：本機一份真實論文有約 20 筆這樣無聲漏掉）
    func testEntriesBeforeTheHeadingOnTheSamePageAreWarned() throws {
        let text = "Body text on page one.\n\u{0C}Body text on page two.\n"
            + "Adams, J. (2001). First title. Journal A, 1, 1–2.\n"
            + "Baker, L. (2002). Second title. Journal B, 2, 3–4.\nReferences\n"
            + "Carter, M. (2003). Third title. Journal C, 3, 5–6.\n"
            + "Dunn, P. (2004). Fourth title. Journal D, 4, 7–8.\n"
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertTrue(r.warnings.contains { $0.contains("標題之前") && $0.contains("2 個完整條目") }, "\(r.warnings)")
    }

    /// T40：年份括號的排版錯字 `(1996}` 與 `{1997)` 都認得，而且標題照樣取得到（R4 B1）
    func testBraceYearTyposKeepYearsAndTitles() throws {
        let text = """
        References

        Adams, J. (1996}. First title. Journal A, 1, 1–2.
        Baker, L. {1997). Second title. Journal B, 2, 3–4.
        Carter, M. (1998). Third title. Journal C, 3, 5–6.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.entries.map(\.year), [1996, 1997, 1998])
        XCTAssertEqual(r.entries.map(\.title), ["First title", "Second title", "Third title"])
    }

    /// T41：年份後面接一個字再接數字的表格列（`(2003) RCT 120`）不是完整條目（R4 B2）
    func testTableRowWithAWordAfterTheYearIsNotAnEntry() throws {
        let text = """
        References

        Adams, J. K. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        Table 1
        Carter, M. (2003) RCT 120 .35
        Dunn, P. (2004) Cohort 88 .41
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.map(\.firstAuthor), ["Adams", "Baker"])
    }

    /// T42：目錄裡同文字的 `References`，加上正文裡一行長得像條目的句子，不得讓目錄那一段吞掉正文
    /// （R4 B3）——頁首合併要求清單在跨過的頁上每頁都有條目
    func testTableOfContentsHeadingDoesNotSwallowTheBody() throws {
        let text = "Contents\nIntroduction\nReferences\n\u{0C}Body text.\n"
            + "Aaron, B. (1990) showed that effects vary across studies.\n\u{0C}More body text.\n"
            + "\u{0C}Even more body text.\n\u{0C}References\n"
            + "Adams, J. K. (2001). First title. Journal A, 1, 1–2.\n"
            + "Baker, L. (2002). Second title. Journal B, 2, 3–4.\n"
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.map(\.firstAuthor), ["Adams", "Baker"])
    }

    /// T43：冊次括號的其他寫法——羅馬數字、帶頁碼、在括號內被截斷——都不留在標題裡（R4 B4）
    func testVolumeParentheticalVariantsAreStripped() throws {
        let text = """
        References

        Adams, J. (2001). Handbook of things (Vol. II). Imaginary Press.
        Baker, L. (2002). Big book (Vol. 3, pp. 10–20). Imaginary Press.
        Carter, M. (2003). Title three (Vol. II. Part A). Imaginary Press.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.map(\.title), ["Handbook of things", "Big book", "Title three"])
    }

    /// T44：行尾軟連字號是斷字，接回時不得變成真的連字號——標題與 DOI 都不能多一個 `-`（R4 B5）
    func testSoftHyphenDoesNotBecomeAHardHyphen() throws {
        let text = "References\n\nAdams, J. (2001). Develop\u{AD}\nment of things. Journal A, 1, 1–2. "
            + "https://doi.org/10.1234/ab\u{AD}\ncd\nBaker, L. (2002). Second title. Journal B, 2, 3–4.\n"
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.entries.first?.title, "Development of things")
        XCTAssertEqual(r.entries.first?.doi, "10.1234/abcd")
    }

    /// T45：標題裡大量句點與括號、或長空白串，不得讓 `title()` 變成二次方（R4 B8）
    func testLongPunctuatedTitleIsFast() throws {
        let noise = String(repeating: "(a. b. ", count: 4000) + String(repeating: " ", count: 20000)
        let text = "References\n\nAdams, J. (2001). \(noise)end. Journal A, 1, 1–2.\n"
        let start = Date()
        let (status, output) = try extract(text)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3, "title 花了太久")
        XCTAssertEqual(status, 0, output)
    }

    /// T46：長書的頁首一出現幾十次，warning 仍要短到不被 500 字上限截掉——只列前幾個位置（R4 B10）
    func testRunningHeadNoteStaysShortInLongBooks() throws {
        var text = "References\n\n"
        for i in 0..<40 {
            text += "Au\(String(UnicodeScalar(65 + i / 26)!))\(String(UnicodeScalar(97 + i % 26)!)), J. (2001). Title \(i). Journal, 1, 1–2.\n"
            text += "\u{0C}References\n"
        }
        text += "Zz, J. (2001). Last. Journal, 1, 1–2.\n"
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.count, 41)
        let note = r.warnings.first { $0.contains("頁首") } ?? ""
        XCTAssertTrue(note.contains("40 次"), note)
        XCTAssertLessThan(note.count, 400, note)
    }

    // MARK: - #617 verify R5

    /// T47：羅馬數字規則要看整個字——`say no. International Journal` 的 `I` 不是羅馬數字（R5 D2）；
    /// 括號外的 `Vol. II`、`pp.` 不讓標題延伸到出版地與頁碼
    func testRomanNumeralRuleNeedsAWholeNumeralInsideParentheses() throws {
        let text = """
        References

        Adams, J. (2001). Learning to say no. International Journal of Testing, 1, 1–2.
        Baker, L. (2002). Handbook of things (Vol. II). Imaginary Press.
        Carter, M. (2003). Collected papers, Vol. II. Imaginary Press, pp. 1–20.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.map(\.title),
                       ["Learning to say no", "Handbook of things", "Collected papers"])
    }

    /// T48：年份括號後直接接引號標題（Harvard）、單字標題、數字開頭的標題，都是完整條目——斷點之後
    /// 全是這種條目時清單不得被無聲截斷（R5 D3）
    func testQuotedSingleWordAndDigitTitlesCountAsFullEntries() throws {
        let text = """
        References

        Adams, J. (2001) ‘First article’, Journal A, 1, 1–2.
        Baker, L. (2002) ‘Second article’, Journal B, 2, 3–4.
        SUPPLEMENTARY MATERIAL
        Supplementary text.
        Carter, M. (2003) ‘Third article’, Journal C, 3, 5–6.
        Dunn, P. (2004) Emotions. London: Imaginary Press.
        Evans, Q. (2005). 25 years of things. Journal E, 5, 1–2.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.map(\.firstAuthor), ["Adams", "Baker", "Carter", "Dunn", "Evans"])
    }

    /// T49：雙欄讀反之後，清單照一般規則接續到後面的斷點之後（R5 D4：R4 的上界把它截斷）
    func testListContinuesPastABreakAfterAColumnSwap() throws {
        let text = """
        References

        Fisher, M. (2003). Third title. Journal C, 3, 5–6.
        Green, P. (2004). Fourth title. Journal D, 4, 7–8.
        ACKNOWLEDGMENTS
        We thank the imaginary participants.
        Adams, J. K. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        Table 2
        Quinn, R. (2005). Fifth title. Journal Q, 5, 9–10.
        Ross, S. (2006). Sixth title. Journal R, 6, 1–2.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.map(\.firstAuthor), ["Fisher", "Green", "Adams", "Baker", "Quinn", "Ross"])
    }

    /// T50：作者清單跨頁、中間夾著頁碼行時，共同作者仍不是新的一筆（R5 D5）
    func testPageNumberBetweenAuthorLinesDoesNotBreakTheAuthorList() throws {
        let text = "References\n\nAdams, J. (2001). First title. Journal A, 1, 1–2.\nBaker, L., &\n246\n"
            + "\u{0C}Zimmerman, P. (2002). Second title. Journal B, 2, 3–4.\n247\n\u{0C}References\n"
            + "Carter, M. (2003). Third title. Journal C, 3, 5–6.\nDunn, P. (2004). Fourth title. Journal D, 4, 7–8.\n"
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.entries.map(\.firstAuthor), ["Adams", "Baker", "Carter", "Dunn"])
        XCTAssertFalse(r.warnings.contains { $0.contains("標題候選") }, "\(r.warnings)")
    }

    /// T51：斷點前一行正在列作者時，斷點之後那一行是同一筆的共同作者，不拿來比字母順序（R5 D5）
    func testAuthorListRunningAcrossABreakIsTheSameEntry() throws {
        let text = "References\n\nAdams, J. (2001). First title. Journal A, 1, 1–2.\n"
            + "Carter, M., &\n\u{0C}References\nAbbott, R. (2003). Third title. Journal C, 3, 5–6.\n"
            + "Dunn, P. (2004). Fourth title. Journal D, 4, 7–8.\n"
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.entries.map(\.firstAuthor), ["Adams", "Carter", "Dunn"])
        XCTAssertFalse(r.warnings.contains { $0.contains("標題候選") }, "\(r.warnings)")
    }

    /// T52：「第 k 筆之後」的 k 由最後的切分決定，與輸出的 index 一致（R5 D6）
    func testBreakNoteNamesTheEntryBySplitNumbering() throws {
        let text = "References\n\nAdams, J. (2001). First title. Journal A, 1, 1–2.\nBaker, L., &\n246\n"
            + "\u{0C}Zimmerman, P. (2002). Second title. Journal B, 2, 3–4.\n"
            + "Evans, M. (2003). Third title continues\nTable 1\nTable body\n"
            + "across the float. Journal C, 3, 5–6.\nFisher, Q. (2004). Fourth title. Journal F, 4, 7–8.\n"
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.entries.map(\.firstAuthor), ["Adams", "Baker", "Evans", "Fisher"])
        XCTAssertTrue(r.warnings.contains { $0.contains("圖表標題") && $0.contains("第 3 筆之後") }, "\(r.warnings)")
    }

    /// T53：第一筆之前的長表格（一格一行，超過 60 行）不得讓清單變空、改選後面的表格欄名；
    /// 真的找不到時，要把這件事說出來（R5 D7）
    func testLongFloatBeforeTheFirstEntryKeepsTheList() throws {
        var text = "Body text.\n\u{0C}References\nTable 4\n"
        for i in 0..<70 { text += "cell \(i)\n" }
        text += "Adams, J. K. (2001). First title. Journal A, 1, 1–2.\n"
            + "Baker, L. (2002). Second title. Journal B, 2, 3–4.\n"
            + "Carter, M. (2003). Third title. Journal C, 3, 5–6.\n"
            + "\u{0C}Reference\nSmith, J. (2003). Row. Journal S, 2, 1.\n"
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.map(\.firstAuthor), ["Adams", "Baker", "Carter"])
    }

    /// T53b：圖表之後找不到接續、主清單因此是空的而改選了別段時，warning 要說出來（R5 D7）。
    /// 至少要有 3 個沒被認成清單的條目開頭——一兩行多半是正文裡長得像條目的句子（本機語料量到的誤報）
    func testEmptyMainListAtABreakIsWarnedEvenIfAnotherSectionIsChosen() throws {
        let text = "Body text.\n\u{0C}References\nFigure 1\nCaption.\n"
            + "Aarts, H. (2001) 3D worlds and more. Journal A, 1, 1–2.\n"
            + "Brandt, K. (2002) 4D worlds and more. Journal B, 2, 3–4.\n"
            + "Cole, M. (2003) 5D worlds and more. Journal C, 3, 5–6.\n"
            + "\u{0C}Reference\nSmith, J. (2003). Row. Journal S, 2, 1.\n"
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertTrue(r.warnings.contains { $0.contains("第 2 行") && $0.contains("沒有被認成清單") }, "\(r.warnings)")
    }

    /// T54：跨頁的是最後一筆時，頁首之後沒有下一筆，後半仍要留在那一筆裡（R5 D8）
    func testRunningHeadKeepsTheTailOfTheLastEntry() throws {
        let text = "References\n\nAdams, J. (2001). First title. Journal A, 1, 1–2.\n"
            + "Carter, M. (2003). A title continued\n\u{0C}References\n"
            + "across pages. Journal C, 3, 5–6.\nhttps://doi.org/10.1234/tail\n"
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.count, 2)
        guard r.count == 2 else { return }
        XCTAssertEqual(r.entries[1].title, "A title continued across pages")
        XCTAssertEqual(r.entries[1].doi, "10.1234/tail")
    }

    /// T55：「略過 N 行…落在第 x 筆」要完整列出每一筆（R5 D9：R4 只列前 15 筆）
    func testSkippedEntryListIsComplete() throws {
        var text = "Body.\nRUNNING HEAD\nBody.\n\nReferences\n\n"
        for i in 0..<20 {
            text += "Au\(String(UnicodeScalar(97 + i)!)), J. (2001). Title \(i) continued\nRUNNING HEAD\non the next page. Journal, 1, 1–2.\n"
        }
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        let joined = r.warnings.filter { $0.contains("略過") || $0.contains("落在") }.joined(separator: " ")
        for n in [1, 15, 16, 20] { XCTAssertTrue(joined.contains("\(n)"), "\(n) 沒被列出：\(joined)") }
        XCTAssertTrue(r.warnings.allSatisfy { $0.count <= 500 }, "\(r.warnings.map(\.count))")
    }

    /// T56：標題停在括號內的 `?` 時，括號裡的字不得被刪掉——只有冊次、版次這類括號殘片才去掉（R5 E1）
    func testUnclosedParenthesisCutOnlyDropsVolumeFragments() throws {
        let text = """
        References

        Adams, J. (2001). Why it matters (does it really?) for things. Journal A, 1, 1–2.
        Baker, L. (2002). Title three (Vol. II. Part A). Imaginary Press.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let titles = try decode(output).entries.map(\.title)
        XCTAssertTrue(titles.first??.contains("does it really") == true, "\(titles)")
        XCTAssertEqual(titles.last, "Title three")
    }

    /// T57：PDF 本身輸出的私用區字元（U+E000）不是軟連字號的記號——不得因此把兩行接成一個字（R5 E2）
    func testPrivateUseCharacterIsNotTreatedAsASoftHyphen() throws {
        let text = "References\n\nAdams, J. (2001). Title with glyph\u{E000}\nnext words. Journal A, 1, 1–2.\n"
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertTrue(try decode(output).entries.first?.raw.contains("\u{E000} next") == true, output)
    }

    /// T58：標題裡一長串 `[` 不得讓 `title()` 變成二次方（R5 E3）
    func testLongRunOfBracketsIsFast() throws {
        let text = "References\n\nAdams, J. (2001). " + String(repeating: "[", count: 30000) + " end. Journal A, 1, 1–2.\n"
        let start = Date()
        let (status, output) = try extract(text)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3, "title 花了太久")
        XCTAssertEqual(status, 0, output)
    }

    /// T59：圖表之後緊接著附錄時，附錄裡的條目不得被算進「清單停在…之後還有 N 個」（R5 E4）
    func testHardEndRightAfterABreakStopsTheCount() throws {
        let text = """
        References

        Adams, J. K. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        Table 1
        Appendix A
        Aaron, Z. (2009). Appendix study. Journal Z, 9, 1–2.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.count, 2)
        XCTAssertFalse(r.warnings.contains { $0.contains("清單停在") }, "\(r.warnings)")
    }

    /// T61：多段 warning 在候選很多時也不超過 500 字（R5 E4）
    func testMultiCandidateWarningStaysShort() throws {
        var text = ""
        for i in 0..<30 {
            let letter = String(UnicodeScalar(122 - i % 26)!)
            text += "References\nZ\(letter)\(i), J. (2001). Title. Journal, 1, 1–2.\nAppendix \(i)\n"
        }
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        let w = r.warnings.first { $0.contains("標題候選") } ?? ""
        XCTAssertFalse(w.isEmpty, "\(r.warnings)")
        XCTAssertLessThanOrEqual(w.count, 500, w)
    }

    // MARK: - #617 verify R6

    /// T64：最後一筆的標題換行換出一行以小寫 appendix／index 開頭的字時，那不是終點——標題的後半
    /// 與 DOI 要留在那一筆裡（R6 E5：原本清單在那裡結束，沒有任何 warning）
    func testLowercaseAppendixLineInsideTheLastEntryIsNotAnEnd() throws {
        let text = """
        References

        Adams, J. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). Inflammation of the
        appendix in children. Journal B, 2, 3–4. https://doi.org/10.1234/app
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.count, 2)
        guard r.count == 2 else { return }
        XCTAssertEqual(r.entries[1].title, "Inflammation of the appendix in children")
        XCTAssertEqual(r.entries[1].doi, "10.1234/app")
    }

    /// T64a：大寫、單獨一行的 `Index` 分不出是標題還是換行（本機語料幾乎都是真標題），照終點處理
    /// ——但最後一筆在那之前還沒結束，要說出來，不得無聲截斷（R6 E5）
    func testCapitalizedIndexLineAfterAnUnfinishedEntryIsWarned() throws {
        let text = """
        References

        Adams, J. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). The citation
        Index
        as a research tool. Journal B, 2, 3–4. https://doi.org/10.1234/idx
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        // 下一行以小寫開頭：R7 起發更具體的那一則（這個 Index 可能是換行換出來的字）
        XCTAssertTrue(r.warnings.contains { $0.contains("小寫開頭") && $0.contains("第 2 筆") }, "\(r.warnings)")

        // 下一行以大寫開頭時，靠「還沒結束」那一則
        let upper = text.replacingOccurrences(of: "as a research tool.", with: "Scientometric Methods, a tool.")
        let (s2, o2) = try extract(upper)
        XCTAssertEqual(s2, 0, o2)
        let r2 = try decode(o2)
        XCTAssertTrue(r2.warnings.contains { $0.contains("還沒結束") && $0.contains("第 2 筆") }, "\(r2.warnings)")
    }

    /// T64b：一筆完整結束之後的 `Index`、緊接在圖表標題之後的附錄，仍是終點
    func testRealIndexAfterACompleteEntryStillEndsTheList() throws {
        let text = """
        References

        Adams, J. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        Index
        Smith, J., 12, 45
        Taylor, K., 88
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.count, 2)
        XCTAssertFalse(r.warnings.contains { $0.contains("還沒結束") }, "\(r.warnings)")
    }

    /// T65：清單停在結束標題或圖表標題、而最後一筆在那之前還沒結束時，要說出來（R6：跨過圖表的
    /// 最後一筆，後半無聲丟掉）
    func testListEndingInsideTheLastEntryIsWarned() throws {
        let text = """
        References

        Adams, J. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). A title that continues
        Table 1
        Cell text
        after the table. Journal B, 2, 3–4.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertTrue(r.warnings.contains { $0.contains("還沒結束") && $0.contains("第 2 筆") }, "\(r.warnings)")
    }

    /// T66：斷點前一行只是以逗號結尾（期刊名後的逗號）、不是在列作者時，照常比字母順序——
    /// 接不上就停下並說出來，不得當成「同一筆的共同作者」併進來（R6 D5）
    func testCommaBeforeABreakIsNotAnAuthorListUnlessItLooksLikeOne() throws {
        let text = """
        References

        Adams, J. (2001). First title. Journal A, 1, 1–2.
        Moore, K. (2002). Second title. Journal of Things,
        Table 1
        Baker, L. (2003). Third title. Journal C, 3, 5–6.
        Carter, M. (2004). Fourth title. Journal D, 4, 7–8.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertEqual(r.entries.map(\.firstAuthor), ["Adams", "Moore"])
        XCTAssertTrue(r.warnings.contains { $0.contains("清單停在") }, "\(r.warnings)")
        XCTAssertFalse(r.warnings.contains { $0.contains("正在列作者") }, "\(r.warnings)")
    }

    /// T67：主清單只有一兩筆、卻因為第一筆之前的圖表而是空的，改選了條目更少的別段時，也要說出來
    /// （R6 D7：門檻 3 讓短清單的這種情形沒有 warning）
    func testTinyOrphanedMainListIsWarnedWhenTheChosenSectionIsSmaller() throws {
        let text = "Body text.\n\u{0C}References\nFigure 1\nCaption.\n"
            + "Aarts, H. (2001) 3D worlds and more. Journal A, 1, 1–2.\n"
            + "Brandt, K. (2002) 4D worlds and more. Journal B, 2, 3–4.\n"
            + "\u{0C}Reference\nSmith, J. (2003). Row. Journal S, 2, 1.\n"
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertTrue(r.warnings.contains { $0.contains("沒有被認成清單") }, "\(r.warnings)")
    }

    /// T68：年份之後以數字為主的表格列（`(2003) USA, 120, .35`、`(2003). 150 .40`）不是完整條目，
    /// 清單不得接續到表格裡（R6 D3）
    func testNumericTableRowsAfterTheYearAreNotFullEntries() throws {
        let text = """
        References

        Adams, J. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        Table 1
        Carter, M. (2003) USA, 120, .35
        Davis, N. (2004). 150 .40
        Evans, P. (2005) UK, 98, .22
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.map(\.firstAuthor), ["Adams", "Baker"])
    }

    /// T69：多段 warning 只列 5 段時，列的是條目開頭最多的 5 段，不是文件裡最前面的 5 段（R6 E4）
    func testMultiCandidateWarningListsTheLargestSegments() throws {
        var text = ""
        for i in 0..<6 { text += "References\nZz\(i), J. (2001). Title. Journal, 1, 1–2.\nAppendix \(i)\n" }
        text += "References\nYa, J. (2001). Title. Journal, 1, 1–2.\nYb, J. (2001). Title. Journal, 1, 1–2.\n"
            + "Yc, J. (2001). Title. Journal, 1, 1–2.\nAppendix 6\n"
        text += "References\n"
        for c in "abcdefgh" { text += "X\(c), J. (2001). Title. Journal, 1, 1–2.\n" }
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let w = try decode(output).warnings.first { $0.contains("標題候選") } ?? ""
        XCTAssertTrue(w.contains("3 個"), w)
        XCTAssertTrue(w.contains("7 段"), w)
    }

    /// T70：最後一筆吸進清單之後的長段文字（作者簡介、引用本文的 DOI）時，要說出來，而且說它的 DOI
    /// 可能不是它自己的（R6：原本只有一份語料被點名，機制沒有揭露）
    func testOverlongEntryIsWarned() throws {
        var text = "References\n\nAdams, J. (2001). First title. Journal A, 1, 1–2.\n"
            + "Baker, L. (2002). Second title. Journal B, 2, 3–4.\n"
        for i in 0..<30 { text += "The second author studies things number \(i) and writes about them at length.\n" }
        text += "Cite this article: https://doi.org/10.9999/stray\n"
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertTrue(r.warnings.contains { $0.contains("第 2 筆") && $0.contains("DOI") }, "\(r.warnings)")
        XCTAssertFalse(r.warnings.contains { $0.contains("第 1 筆") && $0.contains("DOI") }, "\(r.warnings)")
    }

    /// T71：逗號式書目的標題不留下 `, Vol`、`, pp` 殘片；尾端的 `(No. IV)` 也去掉（R6 INFO）
    func testCommaFormVolumeAndNumberFragmentsAreDropped() throws {
        let text = """
        References

        Carter, M. (2003). Collected papers, Vol. II. Imaginary Press, pp. 1–20.
        Dunn, P. (2004). Working report (No. IV). Imaginary Institute.
        Evans, Q. (2005). Selected essays, pp. 1–20. Imaginary Press.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.map(\.title),
                       ["Collected papers", "Working report", "Selected essays"])
    }

    // MARK: - #617 verify R7

    /// T72：標題短、卷期頁多的真條目在斷點之後仍是完整條目——數字多寡只看年份到標題結束那一段，
    /// 不把卷期頁算進去（R7 #0／#3／#8：R6 的規則連卷期頁一起算，這一筆連同之後的清單無聲丟掉）
    func testShortTitleWithManyNumbersAfterABreakIsStillAnEntry() throws {
        for breakLine in ["Table 1\nSome table caption text", "Author Note"] {
            let text = """
            References

            Adams, J. K. (2001). First title. Journal A, 1, 1–2.
            Baker, L. (2002). Second title. Journal B, 2, 3–4.
            \(breakLine)
            Carter, M. (2003). Trust. J Psychol, 12(3), 245–267, 300–320, 400–420.
            Dunn, P. (2004). Flow. Nature, 300 (1), 2–3.
            """
            let (status, output) = try extract(text)
            XCTAssertEqual(status, 0, output)
            XCTAssertEqual(try decode(output).entries.map(\.firstAuthor), ["Adams", "Baker", "Carter", "Dunn"], breakLine)
        }
        let running = "References\n\nAdams, J. K. (2001). First title. Journal A, 1, 1–2.\n"
            + "Baker, L. (2002). Second title. Journal B, 2, 3–4.\n\u{0C}References\n"
            + "Carter, M. (2003). Flow. Nature, 300 (1), 2–3.\n"
        let (status, output) = try extract(running)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.map(\.firstAuthor), ["Adams", "Baker", "Carter"])
    }

    /// T73：最後一筆吸進一長串數字、之後有圖表標題時不得變成二次方（R7 #1：`closesEntry` 的正則在
    /// 長度檢查之前就對整段跑，20 萬字元跑了 7 分鐘）
    func testLongDigitRunInTheLastEntryIsFast() throws {
        let text = "References\n\nAdams, J. (2001). First title. Journal A, 1, 1–2.\n"
            + "Baker, L. (2002). A title that continues " + String(repeating: "1", count: 200_000) + "\nTable 1\n"
        let start = Date()
        let (status, output) = try extract(text)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3, "extract 花了太久")
        XCTAssertEqual(status, 0, output)
    }

    /// T74：清單一路到文字結尾、最後一筆沒有結束時，也要說出來——PDF 可能缺頁（R7 #2）
    func testUnfinishedLastEntryAtTheEndOfTheTextIsWarned() throws {
        let text = "References\n\nAdams, J. (2001). First title. Journal A, 1, 1–2.\nBaker, L. (2002). A title that is cut\n"
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertTrue(r.warnings.contains { $0.contains("第 2 筆") && $0.contains("文字結尾") }, "\(r.warnings)")
    }

    /// T75：清單停在另一個參考文獻標題、最後一筆在那之前還沒結束時，也要說出來（R7 #2）
    func testUnfinishedLastEntryBeforeAnotherHeadingIsWarned() throws {
        let text = """
        References

        Adams, J. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        Carter, M. (2003). A title that
        Bibliography
        Zed, Q. (2009). Other list. Journal Z, 9, 1–2.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertTrue(r.warnings.contains { $0.contains("還沒結束") && $0.contains("第 3 筆") }, "\(r.warnings)")
    }

    /// T76：最後一筆恰好在句點處換行、下一行是大寫的 `Index`、再下一行以小寫開頭時，要說那可能是換行
    /// 換出來的字（R7 #5：原本這種沒有任何 warning）
    func testCapitalizedIndexFollowedByALowercaseLineIsWarned() throws {
        let text = """
        References

        Adams, J. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). The citation index.
        Index
        as a research tool. Journal B, 2, 3–4. https://doi.org/10.1234/idx
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        let r = try decode(output)
        XCTAssertTrue(r.warnings.contains { $0.contains("小寫開頭") && $0.contains("第 2 筆") }, "\(r.warnings)")
    }

    // MARK: - #617 verify R8

    /// T77：標題段不在縮寫（`Vol.`、`No.`）或首字母縮寫（`U.S.A.`）處結束——表格列的數字仍要數到
    /// （R8 #0／#2：R7 的標題段一遇到句點結尾的字就停，這三種表格列又被收成條目，沒有 warning）
    func testAbbreviationsDoNotEndTheTitleSegmentOfATableRow() throws {
        let text = """
        References

        Adams, J. K. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        Table 1
        Smith, J. (2003). Vol. 12, 45-67, .35
        Taylor, K. (2004). No. 8, 90-120, .40
        Upton, M. (2005) U.S.A. 120 .35
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.map(\.firstAuthor), ["Adams", "Baker"])
    }

    // MARK: - #617 verify R9

    /// T78：標題含縮寫或首字母縮寫的真條目，在斷點之後仍是完整條目——包括標題以首字母縮寫結尾、後面
    /// 一串數字的（R9 #0：R8 的標題段在 `U.K.` 不結束，一路數進卷期頁，真條目被當成表格列丟掉）
    func testRealEntriesWithAbbreviationsAfterABreakAreKept() throws {
        let text = """
        References

        Adams, J. K. (2001). First title. Journal A, 1, 1–2.
        Baker, L. (2002). Second title. Journal B, 2, 3–4.
        Table 1
        Carter, M. (2003). Crisis in U.K. 12, 34, 56, 78, 90, 102.
        Dunn, P. (2004). St. Augustine and the city. Journal D, 4, 7–8.
        Evans, Q. (2005). U.S. policy. J Pol, 12, 34–56.
        Fisher, R. (2006). Ph.D. students. Educ Res, 1, 2–3.
        """
        let (status, output) = try extract(text)
        XCTAssertEqual(status, 0, output)
        XCTAssertEqual(try decode(output).entries.map(\.firstAuthor), ["Adams", "Baker", "Carter", "Dunn", "Evans", "Fisher"])
    }
}
