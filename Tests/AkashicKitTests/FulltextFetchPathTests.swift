import XCTest
@testable import AkashicSkillTools
@testable import AkashicStoreIO

/// `FulltextFetch` 的路徑測試（#613 導航版；#629 由 `tests/fetch-fulltext-paths.sh` 移植）——對一個**記憶體內的假瀏覽器**跑，不碰 Safari、
/// 不連網。
///
/// 結束碼是它對 agent 的契約：7 交給人、8 等人驗證、9 這個站今天到上限、6 整批暫停、3 找不到連結、1 看一眼。落錯碼就是把中止條款悄悄
/// 變成重試。每個案例把一條路徑釘在它的碼上，並檢查契約承諾的副作用：7／8／6 時我們的分頁**不**被關；3／9 時關掉的只有我們的分頁；
/// **任何路徑都沒有頁內取檔的 JS**，也沒有導航到頁面連結以外的網址。
final class FulltextFetchPathTests: XCTestCase {

    // MARK: 假瀏覽器

    struct Scenario {
        var profile = "own"
        var landingFinal = "https://pub.example/doi/10.1/x"
        var tabTitle = "Article"
        var readyState = "complete"
        var pageJSFails = false
        var pageText = "Article\nAbstract text"
        /// 頁面 navigation timing 的狀態碼（`pageTextJS` 的第一行）；空＝瀏覽器沒有這個值
        var pageStatus = ""
        var redirectAfterCheck: String?
        var link = "GET https://pub.example/doi/pdf/10.1/x"
        var linkJSFails = false
        // 導航到 PDF 連結之後
        /// 分頁落在哪個網址；nil＝就是導航的目標；"" 表示分頁沒有離開文章頁
        var afterNavURL: String?
        var afterNavTitle = "x.pdf"
        var afterNavContentType = "application/pdf"
        var afterNavReadyState = "complete"
        var afterNavJSFails = false
        var afterNavText = "A PDF"
        var afterNavStatus = ""
        var navigationFails = false
    }

    final class FakeBrowser: SafariBrowser {
        var scenario: Scenario
        var tabs: [(url: String, title: String)] = [("https://user.example/mine", "the user's own tab")]
        var current = 1
        var checked = false
        var navigated = false
        var calls: [String] = []
        /// 送進頁面的每一段 JS（`js` 與 `wait --js`）。
        var injected: [String] = []
        init(_ s: Scenario) { scenario = s }

        private func opt(_ args: [String], _ name: String) -> String? { args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }

        func run(_ args: [String]) -> SafariRun {
            switch args[0] {
            case "documents":
                let items = tabs.enumerated().map { i, t in
                    PyJSON.object([("window", .int(5)), ("index", .int(i + 1)), ("tab_in_window", .int(i + 1)), ("url", .string(t.url)),
                                   ("title", .string(t.title)), ("profile", .string(scenario.profile)), ("is_current", .bool(i + 1 == current))])
                }
                return SafariRun(status: 0, stdout: PyJSON.array(items).dumps() + "\n")
            case "open":
                let url = args.last!
                if args.contains("--new-tab") {
                    calls.append("open \(url)")
                    tabs.append((scenario.landingFinal, scenario.tabTitle))
                    current = tabs.count
                } else {
                    calls.append("navigate \(url)")
                    if scenario.navigationFails { return SafariRun(status: 1, stderr: "no\n") }
                    let k = Int(opt(args, "--tab-in-window")!)!
                    navigated = true
                    let landed = scenario.afterNavURL ?? url
                    if !landed.isEmpty { tabs[k - 1] = (landed, scenario.afterNavTitle) }
                }
                return SafariRun(status: 0)
            case "close":
                let k = Int(opt(args, "--tab-in-window")!)!
                calls.append("close \(k) \(tabs[k - 1].url)")
                tabs.remove(at: k - 1)
                current = min(current, tabs.count)
                return SafariRun(status: 0)
            case "js":
                let k = Int(opt(args, "--tab-in-window")!)!
                let src = args.last!
                injected.append(src)
                if src.contains("document.contentType") {
                    if navigated {
                        if scenario.afterNavJSFails { return SafariRun(status: 1) }
                        return SafariRun(status: 0, stdout: scenario.afterNavContentType + "\n" + scenario.afterNavReadyState + "\n")
                    }
                    return SafariRun(status: 0, stdout: "text/html\n" + scenario.readyState + "\n")
                }
                if src.contains("innerText.slice") {
                    if navigated {
                        if scenario.afterNavJSFails { return SafariRun(status: 1) }
                        return SafariRun(status: 0, stdout: scenario.afterNavStatus + "\n" + scenario.afterNavText + "\n")
                    }
                    if scenario.pageJSFails { return SafariRun(status: 1) }
                    if let redirect = scenario.redirectAfterCheck, !checked { tabs[k - 1].url = redirect; checked = true }
                    return SafariRun(status: 0, stdout: scenario.pageStatus + "\n" + scenario.pageText + "\n")
                }
                if src.contains("citation_pdf_url") {
                    if scenario.linkJSFails { return SafariRun(status: 1, stderr: "boom\n") }
                    return SafariRun(status: 0, stdout: scenario.link + "\n")
                }
                if src.contains("document.readyState") { return SafariRun(status: 0, stdout: scenario.readyState + "\n") }
                return SafariRun(status: 0)
            case "wait":
                if let js = opt(args, "--js") { injected.append(js) }
                return SafariRun(status: 0)
            default:
                return SafariRun(status: 2)
            }
        }
    }

    // MARK: 場地

    private var root: URL!
    var ledgerPath: String { root.appendingPathComponent("state/attempts.jsonl").path }
    private var stdout: [String] = []
    private var stderr: [String] = []
    private var browser: FakeBrowser!
    /// 2026-10-01 10:00 +08:00
    static let now = Date(timeIntervalSince1970: 1_790_820_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fetch-paths-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    static let landing = "https://doi.org/10.1/x"
    static let finalURL = "https://pub.example/doi/10.1/x"
    static let pdfLink = "https://pub.example/doi/pdf/10.1/x"

    /// 跑一個場景，回結束碼。
    @discardableResult
    private func run(_ scenario: Scenario, landing: String = FulltextFetchPathTests.landing, now: Date = FulltextFetchPathTests.now,
                     _ configure: (inout FulltextFetch.Options) -> Void = { _ in }) -> Int32 {
        browser = FakeBrowser(scenario)
        stdout = []; stderr = []
        var options = FulltextFetch.Options(window: 5, landing: landing, ledger: ledgerPath)
        configure(&options)
        let fetcher = FulltextFetch(browser: browser, sleeper: { _ in }, now: { now }, out: { self.stdout.append($0) }, err: { self.stderr.append($0) })
        return fetcher.run(options)
    }

    private var errText: String { stderr.joined(separator: "\n") }
    private var outText: String { stdout.joined(separator: "\n") }
    private var ledgerLines: [String] {
        (try? String(contentsOfFile: ledgerPath, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
    }
    private var navigations: [String] { browser.calls.filter { $0.hasPrefix("navigate ") } }

    /// 整批暫停：結束碼 6、分頁留著、沒有導航到 PDF。
    private func assertStop(_ code: Int32, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(code, 6, errText, file: file, line: line)
        XCTAssertTrue(errText.contains("STOP THE WHOLE RUN"), file: file, line: line)
        XCTAssertFalse(browser.calls.contains { $0.hasPrefix("close") }, "分頁必須留著給使用者看：\(browser.calls)", file: file, line: line)
    }

    /// 等人驗證：結束碼 8、分頁留著、印出在同一個分頁接著走的參數。
    private func assertVerification(_ code: Int32, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(code, 8, errText, file: file, line: line)
        XCTAssertTrue(errText.contains("WAITING FOR HUMAN VERIFICATION"), errText, file: file, line: line)
        XCTAssertFalse(errText.contains("STOP THE WHOLE RUN"), file: file, line: line)
        XCTAssertFalse(browser.calls.contains { $0.hasPrefix("close") }, "\(browser.calls)", file: file, line: line)
        XCTAssertTrue(outText.contains("resume: --resume-tab 2 --resume-origin https://pub.example"), outText, file: file, line: line)
    }

    private func assertHandover(_ code: Int32, _ reason: FulltextFetch.Handover, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(code, 7, errText, file: file, line: line)
        XCTAssertTrue(outText.contains("handover: \(reason.rawValue) window 5 tab 2"), outText, file: file, line: line)
        XCTAssertFalse(browser.calls.contains { $0.hasPrefix("close") }, "交給人時分頁留著：\(browser.calls)", file: file, line: line)
    }

    // MARK: 主路徑：導航到頁面自己的連結、交給人

    func testNavigatesToThePagesOwnPDFLinkAndHandsOver() {
        assertHandover(run(Scenario()), .pdfShown)
        XCTAssertEqual(browser.calls, ["open \(Self.landing)", "navigate \(Self.pdfLink)"], "只開文章頁、再導到頁面自己的連結")
        XCTAssertEqual(ledgerLines.count, 1, "準備導航到 PDF 的那一刻記一次")
        XCTAssertTrue(ledgerLines[0].contains("\"at\":\"2026-10-01T10:00:00+08:00\""), ledgerLines[0])
        XCTAssertTrue(ledgerLines[0].contains("\"site\":\"pub.example\""), ledgerLines[0])
        XCTAssertTrue(outText.contains("attempt: pub.example 1/10 2026-10-01"), outText)
        XCTAssertFalse(browser.calls.contains { $0.contains("user.example") }, "使用者的分頁不得動")
    }

    /// 最高原則的第一條：送進頁面的 JS 沒有任何取檔的東西（2026-09-28 的第一、二次 CAPTCHA 都緊跟在頁內 fetch 之後）。
    func testNothingInjectedIntoThePageRequestsAnything() {
        var scenarios = [Scenario()]
        var html = Scenario(); html.afterNavContentType = "text/html"; scenarios.append(html)
        var form = Scenario(); form.link = "POST https://pub.example/dl"; scenarios.append(form)
        for s in scenarios {
            run(s)
            XCTAssertFalse(browser.injected.isEmpty)
            for js in browser.injected {
                for banned in ["fetch(", "XMLHttpRequest", "credentials", "sendBeacon", ".submit(", ".click(", "location.href", "location.assign", "atob", "btoa"] {
                    XCTAssertFalse(js.contains(banned), "注入的 JS 含 \(banned)：\(js)")
                }
            }
            XCTAssertTrue(browser.injected.allSatisfy { FulltextFetch.injectedExpressions.contains($0) }, "只送固定的幾段：\(browser.injected)")
        }
    }

    /// #613 裁決 2：不再拼出版商的 PDF 網址——SAGE 的 reader、Wiley 的 `/doi/pdf/`、PsycNet 都照頁面自己的連結走。
    func testThePublisherURLRulesAreGone() {
        var sage = Scenario()
        sage.landingFinal = "https://journals.sagepub.com/doi/10.1177/0265407517718387"
        sage.link = "GET https://journals.sagepub.com/doi/reader/10.1177/0265407517718387"
        sage.afterNavContentType = "text/html"
        assertHandover(run(sage), .htmlPage)
        XCTAssertEqual(navigations, ["navigate https://journals.sagepub.com/doi/reader/10.1177/0265407517718387"], "不是 ?download=true")

        var wiley = Scenario()
        wiley.landingFinal = "https://onlinelibrary.wiley.com/doi/10.1111/jopy.12964"
        wiley.link = "GET https://onlinelibrary.wiley.com/doi/pdf/10.1111/jopy.12964"
        assertHandover(run(wiley), .pdfShown)
        XCTAssertEqual(navigations, ["navigate https://onlinelibrary.wiley.com/doi/pdf/10.1111/jopy.12964"], "不是 pdfdirect")

        // PsycNet 停在 doiLanding、頁面只有 /record/ 連結：linkJS 不再把它當 PDF 連結，找不到 → 3（先前會拼 /fulltext/<id>.pdf）
        var psycnet = Scenario()
        psycnet.landingFinal = "https://psycnet.apa.org/doiLanding?doi=10.1037%2Fmet0000285"
        psycnet.link = ""
        XCTAssertEqual(run(psycnet), 3, errText)
        XCTAssertEqual(navigations, [])
        XCTAssertFalse(FulltextFetch.linkJS.contains("/record/") || FulltextFetch.hasLinkJS.contains("/record/"))
    }

    // MARK: 導航之後

    func testAnHTMLPageAfterNavigationIsHandedOver() {
        var s = Scenario(); s.afterNavContentType = "text/html; charset=utf-8"; s.afterNavText = "Reader\nDownload PDF"
        assertHandover(run(s), .htmlPage)
    }

    /// Safari 的 PDF 檢視器可能不能跑頁面 JS：標題乾淨就交給人看，不當成「頁面乾淨、驗證過」。
    func testAnUnscriptableTabIsHandedOverUnverified() {
        var s = Scenario(); s.afterNavJSFails = true
        assertHandover(run(s), .unverifiable)
        XCTAssertTrue(errText.contains("could not read the tab"), errText)
    }

    /// 讀不到分頁、而標題是驗證頁：等人驗證，不交給人存檔。
    func testAnUnscriptableTabWithAChallengeTitleWaitsForVerification() {
        var s = Scenario(); s.afterNavJSFails = true; s.afterNavTitle = "Just a moment..."
        assertVerification(run(s))
    }

    func testATabThatDoesNotMoveIsHandedOver() {
        var s = Scenario(); s.afterNavURL = ""
        assertHandover(run(s), .tabUnchanged)
        XCTAssertTrue(errText.contains("may have started a download"), errText)
    }

    func testRedirectedOffSiteAfterNavigationStops() {
        var s = Scenario(); s.afterNavURL = "https://sso.other.example/login"; s.afterNavTitle = "Sign in"
        assertStop(run(s))
    }

    func testRedirectedToAVerificationPageAfterNavigationWaits() {
        var s = Scenario(); s.afterNavURL = "https://pub.example/captcha/?next=x"; s.afterNavContentType = "text/html"
        s.afterNavText = "Please complete the captcha challenge below"
        assertVerification(run(s))
    }

    /// 使用者 2026-10-01：ScienceDirect 的「Preparing your download」是起疑訊號、整批暫停，不當成一般讀者流程等它自己過。
    func testTheScienceDirectDownloadInterstitialPausesTheBatch() {
        var s = Scenario(); s.afterNavContentType = "text/html"
        s.afterNavText = "Preparing your download\nPlease check your downloads folder shortly"
        assertStop(run(s))
        XCTAssertTrue(errText.contains("sciencedirect-download-challenge"), errText)
    }

    func testAnHTTP403AfterNavigationPausesTheBatch() {
        var s = Scenario(); s.afterNavContentType = "text/html"; s.afterNavStatus = "403"; s.afterNavText = "Forbidden"
        assertStop(run(s))
        XCTAssertTrue(errText.contains("http-403"), errText)
    }

    func testATabThatNeverSettlesAfterNavigationStops() {
        var s = Scenario(); s.afterNavContentType = "text/html"; s.afterNavReadyState = "loading"
        assertStop(run(s))
    }

    func testAFailedNavigationIsAnAutomationFailure() {
        var s = Scenario(); s.navigationFails = true
        XCTAssertEqual(run(s), 1, errText)
        XCTAssertTrue(errText.contains("could not navigate"), errText)
        XCTAssertEqual(ledgerLines.count, 1, "導航之前已經記了一次——失敗也算")
    }

    // MARK: 表單按鈕交給人

    func testAFormButtonIsHandedOverWithoutPressingIt() {
        var s = Scenario(); s.link = "POST https://pub.example/dl"
        assertHandover(run(s), .button)
        XCTAssertEqual(navigations, [], "不代按、不代送")
        XCTAssertEqual(ledgerLines.count, 1, "按鈕交給人也算一次嘗試")
    }

    // MARK: 文章頁上的訊號

    func testChallengeOnLandingWaitsForVerification() {
        var s = Scenario(); s.pageText = "Just a moment...\nChecking"
        assertVerification(run(s))
        XCTAssertEqual(navigations, [])
        XCTAssertEqual(ledgerLines.count, 0, "還沒準備取 PDF，不記")
    }

    func testABlockPageOnLandingPausesTheBatch() {
        for text in ["Access Denied\nReference #18", "Pardon Our Interruption", "Too many requests", "Preparing to download ..."] {
            var s = Scenario(); s.pageText = text
            assertStop(run(s))
        }
    }

    /// 同一頁同時有等人驗證與整批暫停的訊號時，往停的那一邊倒。
    func testAPauseSignalWinsOverAVerificationSignalOnTheSamePage() {
        var s = Scenario(); s.pageText = "Access to this page has been denied.\nPress & Hold to confirm you are a human"
        assertStop(run(s))
        XCTAssertTrue(errText.contains("perimeterx-block"), errText)
    }

    func testAnHTTP429OnLandingPausesTheBatch() {
        var s = Scenario(); s.pageStatus = "429"
        assertStop(run(s))
    }

    func testTabMovesToAnotherSite() {
        var s = Scenario(); s.redirectAfterCheck = "https://verify.other.example/c"
        assertStop(run(s))
    }

    func testPageUnreadable() {
        var s = Scenario(); s.pageJSFails = true
        assertStop(run(s))
    }

    /// 本文讀不到，但**分頁標題**（不經 JS 讀）顯示驗證頁：等人驗證，而不是「頁面讀不到」的整批暫停。
    func testChallengeInTitleWhenBodyUnreadable() {
        var s = Scenario(); s.pageJSFails = true; s.tabTitle = "Just a moment..."
        assertVerification(run(s))
        XCTAssertTrue(errText.contains("cloudflare-challenge"), errText)
    }

    func testPageNeverSettles() {
        var s = Scenario(); s.readyState = "loading"
        assertStop(run(s))
    }

    func testNoPDFLink() {
        var s = Scenario(); s.link = ""
        XCTAssertEqual(run(s), 3, errText)
        XCTAssertTrue(browser.calls.contains("close 2 \(Self.finalURL)"), "\(browser.calls)")
        XCTAssertEqual(ledgerLines.count, 0)
    }

    func testTheLinkScriptFailingIsAnAutomationFailure() {
        var s = Scenario(); s.linkJSFails = true
        XCTAssertEqual(run(s), 1, errText)
        XCTAssertEqual(navigations, [])
    }

    func testWrongProfileRefusedBeforeOpeningAnything() {
        var s = Scenario(); s.profile = "someone-else"
        XCTAssertEqual(run(s) { $0.expectProfile = "own" }, 1, errText)
        XCTAssertFalse(browser.calls.contains { $0.hasPrefix("open") }, "不得開任何分頁")
    }

    // MARK: 每站每天 10 次

    private func writeLedger(_ lines: [String]) throws {
        try FileManager.default.createDirectory(atPath: (ledgerPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: URL(fileURLWithPath: ledgerPath))
    }

    private func entry(_ at: String, _ site: String = "pub.example") -> String { "{\"at\":\"\(at)\",\"landing\":\"https://doi.org/10.1/y\",\"site\":\"\(site)\"}" }

    func testTheTenthAttemptProceedsAndTheEleventhStops() throws {
        try writeLedger((0..<9).map { entry(String(format: "2026-10-01T0%d:00:00+08:00", $0)) })
        assertHandover(run(Scenario()), .pdfShown)
        XCTAssertEqual(ledgerLines.count, 10)
        XCTAssertTrue(outText.contains("attempt: pub.example 10/10"), outText)

        XCTAssertEqual(run(Scenario()), 9, errText)
        XCTAssertTrue(errText.contains("DAILY CAP"), errText)
        XCTAssertEqual(navigations, [], "到上限就不導航到 PDF")
        XCTAssertEqual(ledgerLines.count, 10, "被擋下的不記")
        XCTAssertTrue(browser.calls.contains("close 2 \(Self.finalURL)"), "關的是我們自己的分頁：\(browser.calls)")
        XCTAssertFalse(browser.calls.contains { $0.contains("user.example") && $0.hasPrefix("close") })
    }

    /// 日界是 Asia/Taipei：`2026-09-30T16:30:00Z` 是臺北 10/1 00:30（算今天），`2026-09-30T23:59:59+08:00` 是昨天；別的站不算。
    func testTheDayIsTaipeisAndOtherSitesDoNotCount() throws {
        var lines = (0..<9).map { _ in entry("2026-09-30T16:30:00Z") }
        lines += (0..<5).map { _ in entry("2026-09-30T23:59:59+08:00") }
        lines += (0..<5).map { _ in entry("2026-10-01T09:00:00+08:00", "other.example") }
        try writeLedger(lines)
        assertHandover(run(Scenario()), .pdfShown)
        XCTAssertTrue(outText.contains("attempt: pub.example 10/10 2026-10-01"), outText)
        XCTAssertEqual(run(Scenario()), 9, errText)
        // 臺北的隔天（10/2 00:00:01）又可以
        let tomorrow = Self.now.addingTimeInterval(14 * 3600 + 1)
        assertHandover(run(Scenario(), now: tomorrow), .pdfShown)
        XCTAssertTrue(outText.contains("attempt: pub.example 1/10 2026-10-02"), outText)
    }

    /// 帳本讀不懂就在碰瀏覽器之前停：數不出今天的次數，就不能保證沒超過上限。
    func testAnUnreadableLedgerStopsBeforeAnyBrowserCall() throws {
        for bad in ["not json", "{\"at\":\"2026-10-01T10:00:00\",\"site\":\"pub.example\"}", "{\"site\":\"pub.example\"}", "{\"at\":\"2026-10-01T10:00:00+08:00\",\"site\":\"\"}"] {
            try writeLedger([entry("2026-10-01T09:00:00+08:00"), bad])
            XCTAssertEqual(run(Scenario()), 1, bad)
            XCTAssertTrue(browser.calls.isEmpty, "\(bad)：\(browser.calls)")
            XCTAssertTrue(errText.contains("line 2"), "\(bad)：\(errText)")
        }
        try FileManager.default.removeItem(atPath: ledgerPath)
        try FileManager.default.createSymbolicLink(atPath: ledgerPath, withDestinationPath: root.appendingPathComponent("elsewhere").path)
        XCTAssertEqual(run(Scenario()), 1, errText)
        XCTAssertTrue(browser.calls.isEmpty)
        XCTAssertTrue(errText.contains("symlink"), errText)
    }

    // MARK: 等人驗證之後在同一個分頁接著走

    private func runResume(_ s: Scenario, tabs: [(String, String)], origin: String = "https://pub.example") -> Int32 {
        browser = FakeBrowser(s)
        browser.tabs += tabs
        stdout = []; stderr = []
        let fetcher = FulltextFetch(browser: browser, sleeper: { _ in }, now: { Self.now }, out: { self.stdout.append($0) }, err: { self.stderr.append($0) })
        return fetcher.run(.init(window: 5, landing: Self.landing, ledger: ledgerPath, resumeTab: 2, resumeOrigin: origin))
    }

    /// 使用者驗證完，分頁回到文章頁：不開新分頁、不重新載入，讀同一頁的連結、導過去、交給人。
    func testResumingContinuesInTheSameTabWithoutReloading() {
        let code = runResume(Scenario(), tabs: [(Self.finalURL, "Article")])
        XCTAssertEqual(code, 7, errText)
        XCTAssertEqual(browser.calls, ["navigate \(Self.pdfLink)"], "沒有 open --new-tab、沒有重新載入")
        XCTAssertEqual(ledgerLines.count, 1)
    }

    func testResumingWhileTheChallengeIsStillThereWaitsAgain() {
        var s = Scenario(); s.pageText = "Are you a robot? Please complete the captcha"
        XCTAssertEqual(runResume(s, tabs: [(Self.finalURL, "請稍候...")]), 8, errText)
        XCTAssertEqual(browser.calls, [])
    }

    /// 驗證發生在導航到 PDF 之後、分頁現在顯示 PDF：嘗試已經記過，不再導航、不再記，直接交給人。
    func testResumingOnAShownPDFHandsOverWithoutAnotherAttempt() {
        final class PDFTab: SafariBrowser {
            let inner: FakeBrowser
            init(_ inner: FakeBrowser) { self.inner = inner }
            func run(_ args: [String]) -> SafariRun {
                if args[0] == "js", args.last!.contains("document.contentType") { return SafariRun(status: 0, stdout: "application/pdf\ncomplete\n") }
                return inner.run(args)
            }
        }
        let fake = FakeBrowser(Scenario())
        fake.tabs.append(("https://pub.example/doi/pdf/10.1/x", "x.pdf"))
        stdout = []; stderr = []
        let fetcher = FulltextFetch(browser: PDFTab(fake), sleeper: { _ in }, now: { Self.now }, out: { self.stdout.append($0) }, err: { self.stderr.append($0) })
        let code = fetcher.run(.init(window: 5, landing: Self.landing, ledger: ledgerPath, resumeTab: 2, resumeOrigin: "https://pub.example"))
        XCTAssertEqual(code, 7, errText)
        XCTAssertTrue(stdout.joined(separator: "\n").contains("handover: pdf-shown"), stdout.joined())
        XCTAssertEqual(fake.calls, [])
        XCTAssertEqual(ledgerLines.count, 0)
    }

    /// 那個位置的分頁不是驗證時的那個站（使用者把視窗拉到前面、編號變了）：不在那裡動作。
    func testResumingOnATabShowingAnotherSiteRefuses() {
        XCTAssertEqual(runResume(Scenario(), tabs: [("https://elsewhere.example/p", "Other")]), 1, errText)
        XCTAssertEqual(browser.calls, [])
        XCTAssertTrue(errText.contains("not resuming there"), errText)
    }

    func testResumingOnAMissingTabRefuses() {
        XCTAssertEqual(runResume(Scenario(), tabs: []), 1, errText)
        XCTAssertEqual(browser.calls, [])
    }

    // MARK: 純函式

    func testSiteKeyAndContentType() {
        XCTAssertEqual(FulltextFetch.siteKey("https://Pub.Example"), "pub.example")
        XCTAssertEqual(FulltextFetch.siteKey("https://www.sciencedirect.com"), "www.sciencedirect.com")
        XCTAssertTrue(FulltextFetch.contentTypeIsPDF("application/pdf\ncomplete"))
        XCTAssertTrue(FulltextFetch.contentTypeIsPDF("Application/PDF"))
        XCTAssertFalse(FulltextFetch.contentTypeIsPDF("text/html\ncomplete"))
        XCTAssertFalse(FulltextFetch.contentTypeIsPDF("text/html\npdf"), "只看第一行")
    }

    func testResumeOriginShape() {
        XCTAssertNil(FulltextFetch.resumeOriginProblem("https://www.sciencedirect.com"))
        for bad in ["http://pub.example", "https://pub.example/", "https://pub.example/x", "https://pub.example?x", "https://localhost", "https://1.2.3.4", "pub.example"] {
            XCTAssertNotNil(FulltextFetch.resumeOriginProblem(bad), bad)
        }
    }
}
