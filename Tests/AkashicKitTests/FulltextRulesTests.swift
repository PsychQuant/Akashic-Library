import XCTest
@testable import AkashicSkillTools

/// `plugin/skills/akashic-fetch-fulltext/scripts/tests/test_rules_and_verify.py` 的逐案移植（#629，54 個測試）。
///
/// 離線：不連網、不開 Safari、不需要 PDF——案例是 2026-09-23／24 抓一批真實 PDF 時觀察到的，凍結成文字，出版商的網站
/// 之後漂移也不會讓它們失敗。它們釘的是**這段程式碼的行為**，不是出版商的。
///
/// **這一份的期望值不是新實作說的話**：每個斷言逐字取自舊的 Python 測試（同一個輸入、同一個期望）；舊測試在移植前對舊實作
/// 全綠（54 個），移植後對新實作也全綠。除了移植的 54 個，另有「新舊逐案差分」的證據（changelog 記載），不在這個檔裡。
final class PdfUrlRulesTests: XCTestCase {
    func testSageReaderLinkIsReplacedByDownloadURL() {
        XCTAssertEqual(
            PdfUrlRules.pdfURL(finalURL: "https://journals.sagepub.com/doi/10.1177/0265407517718387",
                               pageLink: "https://journals.sagepub.com/doi/reader/10.1177/0265407517718387"),
            "https://journals.sagepub.com/doi/pdf/10.1177/0265407517718387?download=true")
    }

    func testWileyUsesPdfdirect() {
        XCTAssertEqual(PdfUrlRules.pdfURL(finalURL: "https://onlinelibrary.wiley.com/doi/10.1111/jopy.12964"),
                       "https://onlinelibrary.wiley.com/doi/pdfdirect/10.1111/jopy.12964")
    }

    func testWileySiciDOIIsKeptVerbatim() {
        let doi = "10.1002/(SICI)1099-0984(199909/10)13:5%3C389::AID-PER361%3E3.0.CO;2-A"
        XCTAssertEqual(PdfUrlRules.pdfURL(finalURL: "https://onlinelibrary.wiley.com/doi/\(doi)"),
                       "https://onlinelibrary.wiley.com/doi/pdfdirect/\(doi)")
    }

    func testPsycnetFulltextHtmlMapsToPdf() {
        XCTAssertEqual(PdfUrlRules.pdfURL(finalURL: "https://psycnet.apa.org/fulltext/2020-54836-001.html"),
                       "https://psycnet.apa.org/fulltext/2020-54836-001.pdf")
    }

    func testPsycnetDoilandingTakesIdFromRecordLink() {
        XCTAssertEqual(
            PdfUrlRules.pdfURL(finalURL: "https://psycnet.apa.org/doiLanding?doi=10.1037%2Fmet0000285",
                               pageLink: "/record/2022-13893-001?doi=1"),
            "https://psycnet.apa.org/fulltext/2022-13893-001.pdf")
    }

    func testPsycnetDoilandingWithoutRecordLinkGivesNothing() {
        XCTAssertNil(PdfUrlRules.pdfURL(finalURL: "https://psycnet.apa.org/doiLanding?doi=10.1037%2Fmet0000285"))
    }

    func testViewSuffixAfterDOIIsPeeledOff() {
        XCTAssertEqual(PdfUrlRules.doiFromPath("/doi/10.1111/jopy.12964/abstract"), "10.1111/jopy.12964")
        XCTAssertEqual(PdfUrlRules.doiFromPath("/doi/full/10.1111/jopy.12964/"), "10.1111/jopy.12964")
        XCTAssertEqual(PdfUrlRules.pdfURL(finalURL: "https://onlinelibrary.wiley.com/doi/10.1111/jopy.12964/references"),
                       "https://onlinelibrary.wiley.com/doi/pdfdirect/10.1111/jopy.12964")
    }

    func testSiciDOISlashesSurviveSuffixPeeling() {
        let doi = "10.1002/(SICI)1099-0984(199909/10)13:5%3C389::AID-PER361%3E3.0.CO;2-A"
        XCTAssertEqual(PdfUrlRules.doiFromPath("/doi/abs/\(doi)/full"), doi)
    }

    func testUnknownPublisherDefersToPageLink() {
        XCTAssertNil(PdfUrlRules.pdfURL(finalURL: "https://www.tandfonline.com/doi/full/10.1080/10705511.2024.2379495"))
    }
}

final class FulltextVerifyTests: XCTestCase {
    static let title = "A Theory of States and Traits—Revised"
    static let doi = "10.1146/annurev-clinpsy-032813-153719"

    private func assess(_ page: String, _ count: Int, _ title: String, _ pages: String?, doi: String? = nil, meta: String? = nil) -> FulltextVerify.Assessment {
        FulltextVerify.assess(firstPage: page, pageCount: count, title: title, pages: pages, doi: doi, metaDOI: meta)
    }

    /// `**OWN`：檔案自己的中繼資料指名這篇。
    private func assessOwn(_ page: String, _ count: Int, _ title: String, _ pages: String?) -> FulltextVerify.Assessment {
        assess(page, count, title, pages, doi: Self.doi, meta: Self.doi)
    }

    func testPageRangeArithmetic() {
        XCTAssertEqual(FulltextVerify.expectedPageCount("71--98"), 28)
        XCTAssertEqual(FulltextVerify.expectedPageCount("1013–1034"), 22)
        XCTAssertNil(FulltextVerify.expectedPageCount("e81105"))
        XCTAssertNil(FulltextVerify.expectedPageCount(nil))
    }

    func testVersionOfRecordPasses() {
        let r = assessOwn("Downloaded from ... CP11CH04-Steyer\nA Theory of States and Traits—Revised", 28, Self.title, "71--98")
        XCTAssertEqual(r.doiState, "metadata-match")
        XCTAssertTrue(r.isArticle)
        XCTAssertTrue(r.versionOfRecord)
    }

    func testSupplementIsNotTheArticle() {
        let r = assess("Supplemental Material: Annu. Rev. Clin. Psychol. 2015. 11:71–98\n"
                       + "A Theory of States and Traits—Revised\nA SUPPLEMENTAL TEXT TO CTT", 10, Self.title, "71--98")
        XCTAssertFalse(r.isArticle)
        XCTAssertTrue(r.flags.contains("supplement"))
    }

    static let msTitle = "A General Panel Model with Random and Fixed Effects: A Structural Equations Approach"
    static let msPage = "NIH Public Access\nAuthor Manuscript\nSoc Forces. doi:10.1353/sof.2010.0072.\n"
        + "A General Panel Model with Random and Fixed Effects: A Structural Equations Approach"

    func testAuthorManuscriptIsTheWorkButNotVersionOfRecord() {
        // 帶檔案自己的中繼資料 DOI 時被收——作為這篇作品，不是正式版。
        let r = assess(Self.msPage, 36, Self.msTitle, "1--34", doi: "10.1353/sof.2010.0072", meta: "10.1353/sof.2010.0072")
        XCTAssertTrue(r.isArticle)
        XCTAssertFalse(r.versionOfRecord)
    }

    func testAuthorManuscriptWithOnlyAPrintedDOIGetsAHumanLook() {
        // PMC 作者稿沒有中繼資料 DOI（2026-09-24 量過），頁數也不比，所以印出來的 DOI 單獨站著：不自動收。
        let r = assess(Self.msPage, 36, Self.msTitle, "1--34", doi: "10.1353/sof.2010.0072")
        XCTAssertEqual(r.doiState, "page-match")
        XCTAssertFalse(r.isArticle)
    }

    func testTitleLineAloneIsNotEnough() {
        // 沒有 DOI 可比、沒有頁碼範圍：只有一個訊號，所以人看一眼。
        XCTAssertFalse(assess(Self.msPage, 36, Self.msTitle, nil, doi: nil).isArticle)
    }

    static let wrongTitle = "The rank-order consistency of personality traits from childhood to old age"

    func testSameTopicWrongPaperAtTheMeasuredBoundary() {
        // 2026-09-24 對真實 pdftotext 輸出量到：這組配對得 0.8，因為別篇的摘要用了錯誤標題大部分的字。
        // 合成文字（我們自己的用字）重現：10 個內容字詞裡 8 個。
        let firstPage = "Personality Development Across the Life Course\n"
            + "We review the rank-order consistency of personality traits from childhood onward."
        XCTAssertEqual(FulltextVerify.titleScore(Self.wrongTitle, firstPage: firstPage), 0.8, accuracy: 1e-9)
        XCTAssertFalse(assess(firstPage, 19, Self.wrongTitle, nil).isArticle)
    }

    func testUnrelatedTitleScoresFarBelow() {
        let firstPage = "Personality Development Across the Life Course: The Argument for Change and Continuity"
        XCTAssertLessThan(FulltextVerify.titleScore(Self.wrongTitle, firstPage: firstPage), 0.5)
    }

    static let cjkTitle = "大學生自我認定的發展軌跡"

    func testCJKTitleSurvivesALineWrap() {
        let page = "大學生自我認定\n的發展軌跡\n摘要\nDOI: 10.6251/BEP.2020.0001"
        XCTAssertNotNil(FulltextVerify.titleMatch(Self.cjkTitle, firstPages: page))
        XCTAssertTrue(assess(page, 20, Self.cjkTitle, nil, doi: "10.6251/bep.2020.0001", meta: "10.6251/BEP.2020.0001").isArticle)
    }

    func testCJKSameTopicPaperDifferingAtTheEndIsRejected() {
        // 審查 2026-09-24：二連詞重疊給它 0.91 而收下。
        let wrong = "自我概念與生涯輔導：大學生自我認定的發展軌道分析\n摘要\n本研究分析大學生自我概念形成歷程。"
        XCTAssertNil(FulltextVerify.titleMatch(Self.cjkTitle, firstPages: wrong))
        XCTAssertFalse(assess(wrong, 19, Self.cjkTitle, nil).isArticle)
    }

    func testMixedScriptTitleNeedsBothPartsInOrder() {
        let title = "RI-CLPM 在大學生自我認定研究中的應用"
        XCTAssertNotNil(FulltextVerify.titleMatch(title, firstPages: "RI-CLPM 在大學生自我\n認定研究中的應用\nAbstract"))
        XCTAssertNil(FulltextVerify.titleMatch(title, firstPages: "RI-CLPM 在青少年情緒研究中的應用\n大學生自我認定"))
    }

    func testTitleNestedInALongerCJKTitleIsRejected() {
        // 審查 R3，2026-09-24：單純包含關係兩個都收。
        let title = "大學生自我認定的發展"
        XCTAssertNil(FulltextVerify.titleMatch(title, firstPages: "台灣大學生自我認定的發展與相關因素之研究\n王小明\n摘要"))
        XCTAssertNil(FulltextVerify.titleMatch(title, firstPages: "對「大學生自我認定的發展」一文之商榷\n李四\n摘要"))
    }

    func testLatinTitleExtendedWithoutASeparatorIsRejected() {
        let page = "A critique of the cross-lagged panel model in developmental research\nAuthor\nAbstract"
        XCTAssertNil(FulltextVerify.titleMatch("A critique of the cross-lagged panel model", firstPages: page))
    }

    func testAbstractContainingEveryTitleWordIsNotTheTitle() {
        // 字詞重疊實測的失敗（14/808 收錯）：同領域論文的摘要用了另一篇標題的每一個字。
        let page = "The within-between dispute in panel research\nJane Doe\nAbstract\n"
            + "We revisit a critique of the cross-lagged panel model and its random intercept extension."
        XCTAssertEqual(FulltextVerify.titleScore("A critique of the cross-lagged panel model", firstPage: page), 1.0)
        XCTAssertNil(FulltextVerify.titleMatch("A critique of the cross-lagged panel model", firstPages: page))
        XCTAssertFalse(assess(page, 20, "A critique of the cross-lagged panel model", nil).isArticle)
    }

    func testRecordWithMainTitleOnlyMatchesAPDFWithSubtitle() {
        // 副標題在**同一行**：只有分隔符規則能對上主標題。
        let page = "Journal\nThe separation of between-person and within-person components: A latent curve model\nAbstract"
        XCTAssertEqual(FulltextVerify.titleMatch("The separation of between-person and within-person components", firstPages: page), "main-title")
        // 副標題自己一行：主標題那一行本身就等於記錄。
        let wrapped = "Journal\nThe separation of between-person and within-person components:\nA latent curve model"
        XCTAssertEqual(FulltextVerify.titleMatch("The separation of between-person and within-person components", firstPages: wrapped), "exact")
        XCTAssertEqual(FulltextVerify.titleMatch("The separation of between-person and within-person components: A latent curve model", firstPages: page), "exact")
    }

    func testGenericTitleNeedsThePageCount() {
        // 審查 R4：「Introduction」是任何一篇論文某一節的標題。
        let page = "Some Other Paper\nJohn Smith\nAbstract\nText.\nIntroduction\nMore text."
        XCTAssertEqual(FulltextVerify.titleMatch("Introduction", firstPages: page), "exact")
        // 沒有 DOI，標題行加頁數永遠不夠。
        XCTAssertFalse(assess(page, 12, "Introduction", "1--12").isArticle)
        // 這一頁先印了別篇的 DOI：拒收。
        let other = page + "\ndoi:10.1037/other0001"
        XCTAssertFalse(assess(other, 12, "Introduction", "1--12", doi: "10.1037/intro0001").isArticle)
    }

    static let critique = "A critique of the cross-lagged panel model"
    static let critiqueDOI = "10.1037/a0038889"

    func testReplyAfterTheSeparatorIsADifferentWork() {
        let page = "A critique of the cross-lagged panel model: A reply to Orth et al.\nJane Doe\nAbstract"
        XCTAssertEqual(FulltextVerify.titleMatch(Self.critique, firstPages: page), "main-title-response")
        XCTAssertEqual(FulltextVerify.titleMatch("大學生自我認定的發展軌跡", firstPages: "大學生自我認定的發展軌跡：回應王氏\n摘要"),
                       "main-title-response")
        // 頁面上沒有 DOI：頁數剛好吻合也救不了它。
        XCTAssertFalse(assess(page, 16, Self.critique, "102--116").isArticle)
    }

    // 審查 R5，2026-09-24：以下每一個都是標題行規則會收下的別篇。每個都印著自己的 DOI，那就是拒收它的東西。
    func testReplyMarkerOnTheLineBeforeTheTitleIsRejectedByItsDOI() {
        let page = "Erratum to:\nA critique of the cross-lagged panel model\nhttps://doi.org/10.1037/a0099999\nText"
        XCTAssertEqual(FulltextVerify.titleMatch(Self.critique, firstPages: page), "exact")
        let r = assess(page, 16, Self.critique, "102--116", doi: Self.critiqueDOI)
        XCTAssertEqual(r.doiState, "page-mismatch")
        XCTAssertFalse(r.isArticle)
    }

    func testReplyInAnotherLanguageIsRejectedByItsDOI() {
        let page = "A critique of the cross-lagged panel model: Eine Erwiderung auf Müller\ndoi:10.1026/0012-1924/a000001"
        XCTAssertEqual(FulltextVerify.titleMatch(Self.critique, firstPages: page), "main-title")
        XCTAssertFalse(assess(page, 16, Self.critique, "102--116", doi: Self.critiqueDOI).isArticle)
    }

    func testSequelWithANumberIsRejectedByItsDOI() {
        let page = "A Theory of States and Traits Revised 2\nhttps://doi.org/10.1146/annurev-other-000000\nJane Doe"
        XCTAssertEqual(FulltextVerify.titleMatch("A Theory of States and Traits Revised", firstPages: page), "exact")
        XCTAssertFalse(assess(page, 28, "A Theory of States and Traits Revised", nil, doi: "10.1146/annurev-clinpsy-032813-153719").isArticle)
    }

    func testOrdinarySubtitleWordLikeCorrectionIsAcceptedWithTheDOI() {
        let page = "Range restriction revisited: Correction for attenuation in panel data\ndoi:10.1037/met0000123\nAbstract"
        let r = assess(page, 20, "Range restriction revisited", nil, doi: "10.1037/met0000123", meta: "10.1037/met0000123")
        XCTAssertEqual(r.doiState, "metadata-match")
        XCTAssertTrue(r.isArticle)
        // 沒有中繼資料時，印出來的 DOI 可能是引用；回應字樣的守衛於是拒收——文件記載的代價（人看一眼）。
        XCTAssertFalse(assess(page, 20, "Range restriction revisited", "1--20", doi: "10.1037/met0000123").isArticle)
    }

    func testOnlyPageOneDOICounts() {
        // 第 2 頁參考文獻裡的 DOI 不是檔案自己的；第 1 頁沒有 DOI ＝ absent。
        let page = "A critique of the cross-lagged panel model\nAbstract\n\u{0C}References\ndoi:10.1037/other"
        let r = assess(page, 16, Self.critique, "102--116", doi: Self.critiqueDOI)
        XCTAssertEqual(r.doiState, "absent")
        XCTAssertFalse(r.isArticle)   // 沒有 DOI 訊號：人看一眼
    }

    // 審查 R6，2026-09-24：首頁的第一個 DOI 可以是**引用**原文。
    func testErratumCitingTheOriginalsDOIFirstIsCaughtByPages() {
        let page = "Erratum to: A critique of the cross-lagged panel model\nhttps://doi.org/10.1037/a0038889\nIn the article..."
        let r = assess(page, 1, Self.critique, "102--116", doi: Self.critiqueDOI)
        XCTAssertEqual(r.doiState, "page-match")
        XCTAssertFalse(r.isArticle)   // 1 頁對 15 頁
    }

    func testMetadataDOIOverridesWhatThePagePrints() {
        let page = "A critique of the cross-lagged panel model\nhttps://doi.org/10.1037/a0038889\nText"
        // 檔案自己說它是別篇（勘誤先引用原文）
        var r = assess(page, 16, Self.critique, "102--116", doi: Self.critiqueDOI, meta: "10.1037/met0099999")
        XCTAssertEqual(r.doiState, "metadata-mismatch")
        XCTAssertFalse(r.isArticle)
        // 檔案自己說它是這篇，即使首頁先印了一個被引用的 DOI
        let cited = "A critique of the cross-lagged panel model\nsee doi:10.1037/cited0001\nText"
        r = assess(cited, 16, Self.critique, nil, doi: Self.critiqueDOI, meta: Self.critiqueDOI)
        XCTAssertEqual(r.doiState, "metadata-match")
        XCTAssertTrue(r.isArticle)
    }

    func testXMPDOIStopsAtTheClosingTag() {
        // 語料裡的形狀（T&F、SAGE）：標籤緊接在 DOI 後面。
        XCTAssertEqual(FulltextVerify.doiFromXMP("<dc:identifier>doi:10.1080/10705511.2020.1784738</dc:identifier>"),
                       "10.1080/10705511.2020.1784738")
        XCTAssertEqual(FulltextVerify.doiFromXMP("<prism:doi>10.1177/0265407517718387</prism:doi></rdf:Description>"),
                       "10.1177/0265407517718387")
    }

    func testXMPSiciDOIIsUnescaped() {
        XCTAssertEqual(
            FulltextVerify.doiFromXMP("<prism:doi>10.1002/(SICI)1099-0984(199909/10)13:5&lt;389::AID-PER361&gt;3.0.CO;2-A</prism:doi>"),
            "10.1002/(sici)1099-0984(199909/10)13:5<389::aid-per361>3.0.co;2-a")
    }

    func testDOIFromAURLDropsQueryAndFragment() {
        XCTAssertEqual(FulltextVerify.normDOI("https://doi.org/10.1111/jopy.12964?utm_source=x#abstract"), "10.1111/jopy.12964")
    }

    func testMainTitleMatchNeedsThePageCount() {
        let title = "The separation of between-person and within-person components"
        let page = "Journal\nThe separation of between-person and within-person components: A latent curve model\nAbstract"
        let printed = page + "\ndoi:10.1037/a0035297"
        XCTAssertFalse(assess(printed, 16, title, nil, doi: "10.1037/a0035297").isArticle)
        XCTAssertTrue(assess(printed, 16, title, "879--894", doi: "10.1037/a0035297").isArticle)
    }

    func testAmpersandAndAndAreTheSameTitle() {
        let page = "Structure & Dynamics of Self-Concept\nDevelopment\nAuthor"
        XCTAssertEqual(FulltextVerify.titleMatch("Structure and Dynamics of Self-Concept Development", firstPages: page), "exact")
        XCTAssertEqual(FulltextVerify.titleMatch("Structure & Dynamics of Self-Concept Development",
                                                 firstPages: "Structure and Dynamics of\nSelf-Concept Development"), "exact")
    }

    func testTitleWrappedOverSevenLinesStillMatches() {
        let title = "One two three four five six seven eight nine ten eleven twelve thirteen fourteen"
        let words = title.split(separator: " ").map(String.init)
        let page = stride(from: 0, to: words.count, by: 2).map { words[$0..<min($0 + 2, words.count)].joined(separator: " ") }.joined(separator: "\n")
        XCTAssertEqual(FulltextVerify.titleMatch(title, firstPages: page), "exact")
    }

    func testFootnoteMarkerAfterTheTitleIsTolerated() {
        XCTAssertEqual(FulltextVerify.titleMatch("Residual Structural Equation Models", firstPages: "Residual Structural Equation Models1\nX"), "exact")
    }

    func testTitleOfShortWordsUsesContainment() {
        // 每個字都 ≤ 2 個字母，所以 normalize() 是空的，由包含關係決定。
        XCTAssertNotNil(FulltextVerify.titleMatch("Is It Ok", firstPages: "is it ok\nabstract"))
        XCTAssertNil(FulltextVerify.titleMatch("Is It Ok", firstPages: "something else entirely"))
    }

    func testStandaloneSupportingInformationHeadingInsideAnArticleIsNotFlagged() {
        // ACS／Wiley 的文章在前面幾頁自己帶「Supporting Information」標題；只有前 3 行能標記補充檔。
        let page = ["Journal of Things", "A Theory of States and Traits—Revised", "Jane Doe",
                    "Abstract", "We study states.", "Supporting Information", "Details online."].joined(separator: "\n")
        let r = assess(page, 28, Self.title, "71--98")
        XCTAssertFalse(r.flags.contains("supplement"))
    }

    func testSupportingInformationFileIsASupplement() {
        let r = assess("Supporting Information\n" + Self.title, 6, Self.title, "71--98")
        XCTAssertTrue(r.flags.contains("supplement"))
        XCTAssertFalse(r.isArticle)
    }

    func testTandFCoverPageLinkIsNotASupplement() {
        // 2026-09-24 量到：T&F 文章的封面長這樣，任何位置都算的規則把文章本身標成補充資料。
        let cover = "Structural Equation Modeling: A Multidisciplinary Journal\n"
            + "A Theory of States and Traits—Revised\n"
            + "To link to this article: https://doi.org/10.1080/x\n"
            + "View supplementary material\nPublished online: 06 Oct 2025."
        let r = assessOwn(cover, 30, Self.title, "71--98")
        XCTAssertFalse(r.flags.contains("supplement"))
        XCTAssertTrue(r.isArticle)
    }

    func testArticleMentioningItsSupplementBelowTheHeadIsNotFlagged() {
        let body = (["A Theory of States and Traits—Revised"] + (0..<20).map { "line \($0)" }
                    + ["Supporting Information is available online."]).joined(separator: "\n")
        let r = assessOwn(body, 28, Self.title, "71--98")
        XCTAssertFalse(r.flags.contains("supplement"))
        XCTAssertTrue(r.isArticle)
    }

    func testPageCountFarFromRangeIsRejected() {
        let r = assess(Self.title, 10, Self.title, "71--98")
        XCTAssertEqual(r.pagesOK, false)
        XCTAssertFalse(r.isArticle)
    }
}

final class BotSignalsTests: XCTestCase {
    func testCloudflareInterstitialStops() {
        XCTAssertEqual(BotSignals.detect("<title>Just a moment...</title><div id=cf-chl-widget>"), "cloudflare-challenge")
    }

    func test403AloneStops() { XCTAssertEqual(BotSignals.detect("<html></html>", status: 403), "http-403") }

    func test429AloneStops() { XCTAssertEqual(BotSignals.detect("", status: 429), "http-429") }

    func testCaptchaPageStops() { XCTAssertNotNil(BotSignals.detect("Please complete the CAPTCHA to continue")) }

    func testVendorBlockPagesStop() {
        XCTAssertEqual(BotSignals.detect("Pardon Our Interruption"), "akamai-block")
        XCTAssertEqual(BotSignals.detect("Press & Hold to confirm you are a human"), "perimeterx-block")
        XCTAssertEqual(BotSignals.detect("<script src=https://ct.captcha-delivery.com/c.js>"), "datadome-block")
    }

    func testOrdinaryHCIWordingIsNotAVendorBlock() {
        // 審查 2026-09-24：這些單獨的片語在一般摘要上讓 run 停下。
        XCTAssertNil(BotSignals.detect("Participants were asked to press and hold the target icon for 500 ms."))
        XCTAssertNil(BotSignals.detect("Teams using automation tools shipped releases faster."))
    }

    func testPaywallLoadingShellIsNotSuspicion() {
        // 沒有權限的 PsycNet，2026-09-23：200 加約 8 KB 的「Loading...」外殼。那是「沒有權限」（結束碼 4），不是網站起疑。
        XCTAssertNil(BotSignals.detect("<html><body><div>Loading...</div></body></html>", status: 200))
    }

    func testOrdinaryArticlePageIsNotSuspicion() {
        XCTAssertNil(BotSignals.detect("The Separation of Between-person and Within-person Components "
                                       + "of Individual Change Over Time\nAbstract\nLongitudinal data...", status: 200))
    }
}

/// 移植之外新增的邊界案例（期望值取自舊 Python 實作的實際輸出，逐條實測）：Python 語意在邊界上與 Swift 不同的地方，以及移植時
/// 新出現的東西（`PDFReader`、`HTMLEntities`、`URLSplit`）。上面三個 class 是 54 個逐案移植，這裡不混進去，免得「54」變成一句沒有對照的數字。
final class FulltextVerifyBoundaryTests: XCTestCase {
    /// `^(https?://(dx\.)?doi\.org/|doi:\s*)` 是**一個**交替式：至多剝一個前綴。
    func testOnlyOneDOIPrefixIsStripped() {
        XCTAssertEqual(FulltextVerify.normDOI("https://doi.org/doi:10.1234/x"), "doi:10.1234/x")
        XCTAssertEqual(FulltextVerify.normDOI("doi:  10.1234/x"), "10.1234/x")
        XCTAssertEqual(FulltextVerify.normDOI("10.1/x,.;:)]}/"), "10.1/x")
        XCTAssertEqual(FulltextVerify.normDOI("10.1234/x%2Fy%E4%B8%AD"), "10.1234/x/y中")
    }

    /// XMP 裡的 DOI：`\d{4,9}` 恰在範圍內才算、`\b` 前一個字元不能是字詞字元、`&amp;`／數字參照被還原。
    func testXMPDOIShapeMatchesPython() {
        XCTAssertEqual(FulltextVerify.doiFromXMP("<a>10.1234/x&amp;y</a>"), "10.1234/x&y")
        XCTAssertEqual(FulltextVerify.doiFromXMP("<a>10.1234/x&#60;y&#x3e;z</a>"), "10.1234/x<y>z")
        XCTAssertEqual(FulltextVerify.doiFromXMP("<a>10.12345678/x</a>"), "10.12345678/x")
        XCTAssertEqual(FulltextVerify.doiFromXMP("<a>10.1234/&lt;a&gt;</a>"), "10.1234/<a>")
        XCTAssertEqual(FulltextVerify.doiFromXMP("doi 10.1234/a\"b"), "10.1234/a")
        for none in ["<a>10.123/x</a>", "<a>x10.1234/y</a>", "<a>10.1234/</a>", "<a>10.1234567890/x</a>"] {
            XCTAssertNil(FulltextVerify.doiFromXMP(none), none)
        }
    }

    /// 頁面文字的 DOI 允許 `<` `>`（SICI 式），XMP 的不允許（它以標籤結尾）。
    func testPageTextDOIKeepsAngleBracketsWhileXMPStopsAtThem() {
        XCTAssertEqual(FulltextVerify.pageOneDOI("doi:10.1002/(SICI)1099-0984(199909/10)13:5<389::AID-PER361>3.0.CO;2-A\n"),
                       "10.1002/(sici)1099-0984(199909/10)13:5<389::aid-per361>3.0.co;2-a")
        XCTAssertEqual(FulltextVerify.doiFromXMP("<a>10.1002/x<b>y</b></a>"), "10.1002/x")
    }

    func testExpectedPageCountBoundaries() {
        XCTAssertEqual(FulltextVerify.expectedPageCount("71-98"), 28)
        XCTAssertEqual(FulltextVerify.expectedPageCount(" 71 – 98 "), 28)
        XCTAssertEqual(FulltextVerify.expectedPageCount("٣٤--٤٥"), 12)   // Python 的 `\d` 與 `int()` 認 Unicode 十進位數字
        XCTAssertEqual(FulltextVerify.expectedPageCount("12—15"), 4)
        XCTAssertEqual(FulltextVerify.expectedPageCount("10---20"), 11)
        for none in ["5", "98--71", "1--", "--5", "", "12 - 15 x"] { XCTAssertNil(FulltextVerify.expectedPageCount(none), none) }
    }

    func testPdfinfoPageCountParsing() {
        XCTAssertEqual(PDFReader.pageCount(fromPdfinfo: "Title:  x\nPages:          28\nEncrypted: no\n"), 28)
        XCTAssertNil(PDFReader.pageCount(fromPdfinfo: "Title: Pages: 5\n"), "必須是行首（`^Pages:`）")
        XCTAssertNil(PDFReader.pageCount(fromPdfinfo: "Pages:\n"))
        XCTAssertNil(PDFReader.pageCount(fromPdfinfo: ""))
    }

    /// `urlsplit` 的子集：主機是 `netloc.lower()`，帶埠號不符合規則（舊實作同）；前導控制字元與換行被吃掉。
    func testURLSplitFollowsPythonUrlsplit() {
        XCTAssertNil(PdfUrlRules.pdfURL(finalURL: "https://journals.sagepub.com:443/doi/10.1177/x"))
        XCTAssertEqual(PdfUrlRules.pdfURL(finalURL: "HTTPS://Onlinelibrary.Wiley.com/doi/10.1/z"), "https://onlinelibrary.wiley.com/doi/pdfdirect/10.1/z")
        XCTAssertEqual(PdfUrlRules.pdfURL(finalURL: "  https://onlinelibrary.wiley.com/doi/10.1/z"), "https://onlinelibrary.wiley.com/doi/pdfdirect/10.1/z")
        XCTAssertEqual(PdfUrlRules.pdfURL(finalURL: "https://onlinelibrary.wiley.com\t/doi/10.1/z"), "https://onlinelibrary.wiley.com/doi/pdfdirect/10.1/z")
        XCTAssertEqual(PdfUrlRules.pdfURL(finalURL: "//onlinelibrary.wiley.com/doi/10.1/z"), "https://onlinelibrary.wiley.com/doi/pdfdirect/10.1/z")   // 省略 scheme 的 `//host` 也有 netloc——規則只看主機
        XCTAssertEqual(URLSplit("https://pub.example/doi/10.1/x?a=b#f").origin, "https://pub.example")
        XCTAssertEqual(URLSplit("HTTPS://Pub.Example/x").origin, "https://Pub.Example", "scheme 小寫、netloc 原樣（`origin()` 用來比對分頁還在不在同一個站）")
    }

    func testPageCountTitleAndNonPDFAreNamedNotCrashed() throws {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-pdf-\(UUID().uuidString).pdf")
        try Data("<html>hello</html>".utf8).write(to: f)
        defer { try? FileManager.default.removeItem(at: f) }
        XCTAssertThrowsError(try PDFReader.read(path: f.path)) { XCTAssertEqual(($0 as? SkillToolError)?.errorDescription, "not a PDF (no %PDF- header)") }
        XCTAssertThrowsError(try PDFReader.read(path: f.path + ".missing"))
        let (json, ok) = FulltextFetch.verdictJSON(path: f.path, title: "T", pages: nil, doi: "")
        XCTAssertFalse(ok)
        XCTAssertEqual(json, "{\"error\": \"not a PDF (no %PDF- header)\", \"is_article\": false}")
    }
}
