import XCTest
@testable import AkashicSkillTools
@testable import AkashicStoreIO

/// #613 b34：R3 修正輪的 verify（b33 X3）提出的九則 MEDIUM 與幾則 LOW，以及使用者 2026-10-05 的四則裁決。與 `FulltextFetchPathTests`
/// 同一個記憶體內的假瀏覽器——不碰 Safari、不連網。
///
/// MEDIUM 的共同形狀：R3 只修了「別的主機」那一條路，文章站上的同一個判斷（`decideShown`、`unscriptable`、`--resume-stage article`）還留著
/// 原本的問題。這裡每一支測試都在文章站那一條路上重現一則，並對照別的主機上的同一個形狀。
final class FulltextB34Tests: XCTestCase {
    typealias Scenario = FulltextFetchPathTests.Scenario
    typealias FakeBrowser = FulltextFetchPathTests.FakeBrowser

    private var root: URL!
    private var lastLedger = ""
    private var stdout: [String] = []
    private var stderr: [String] = []
    private var browser: FakeBrowser!
    static let now = FulltextFetchPathTests.now
    static let landing = FulltextFetchPathTests.landing

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fetch-b34-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func newLedger() -> String {
        lastLedger = root.appendingPathComponent("state/\(UUID().uuidString).jsonl").path
        return lastLedger
    }

    @discardableResult
    private func run(_ scenario: Scenario, landing: String = FulltextB34Tests.landing,
                     hook: ((_ args: [String], _ fake: FakeBrowser) -> SafariRun?)? = nil) -> Int32 {
        browser = FakeBrowser(scenario)
        browser.hook = hook
        stdout = []; stderr = []
        let fetcher = FulltextFetch(browser: browser, sleeper: { _ in }, now: { Self.now },
                                    out: { self.stdout.append($0) }, err: { self.stderr.append($0) })
        return fetcher.run(.init(window: 5, landing: landing, ledger: newLedger()))
    }

    private func runResume(_ s: Scenario, tab: (String, String), origin: String = "https://pub.example", stage: FulltextFetch.ResumeStage,
                           hook: ((_ args: [String], _ fake: FakeBrowser) -> SafariRun?)? = nil) -> Int32 {
        browser = FakeBrowser(s)
        browser.tabs.append(tab)
        browser.hook = hook
        stdout = []; stderr = []
        let fetcher = FulltextFetch(browser: browser, sleeper: { _ in }, now: { Self.now }, out: { self.stdout.append($0) }, err: { self.stderr.append($0) })
        return fetcher.run(.init(window: 5, landing: Self.landing, ledger: newLedger(), resumeTab: 2, resumeOrigin: origin, resumeStage: stage))
    }

    private var errText: String { stderr.joined(separator: "\n") }
    private var outText: String { stdout.joined(separator: "\n") }

    private func assertStop(_ code: Int32, _ note: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(code, 6, "\(note)\n\(errText)\n\(outText)", file: file, line: line)
        XCTAssertTrue(errText.contains("STOP THE WHOLE RUN"), "\(note)\n\(errText)", file: file, line: line)
        XCTAssertFalse(outText.contains("resume:"), "整批暫停不印 resume 參數：\(note)\n\(outText)", file: file, line: line)
        XCTAssertFalse(outText.contains("handover:"), "\(note)\n\(outText)", file: file, line: line)
    }

    private func assertHandover(_ code: Int32, _ reason: FulltextFetch.Handover, _ note: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(code, 7, "\(note)\n\(errText)\n\(outText)", file: file, line: line)
        XCTAssertTrue(outText.contains("handover: \(reason.rawValue) window 5 tab 2"), "\(note)\n\(outText)", file: file, line: line)
        XCTAssertFalse(errText.contains("STOP THE WHOLE RUN"), "\(note)\n\(errText)", file: file, line: line)
        XCTAssertFalse(errText.contains("WAITING FOR HUMAN VERIFICATION"), "\(note)\n\(errText)", file: file, line: line)
    }

    /// 導航之後讀分頁顯示什麼的那一段 JS 一律失敗（Safari 的 PDF 檢視器可能不跑頁面 JS）。
    private static func shownJSFails(_ args: [String], _ fake: FakeBrowser) -> SafariRun? {
        guard args[0] == "js", args.last!.contains("document.contentType") else { return nil }
        return SafariRun(status: 1)
    }

    // MARK: 第 1、5、7 則：文章站上讀不到的分頁與別的主機同一套——不因標題或網址的一般字樣停

    /// 頁面自己的 PDF 連結多半在文章站本身（SAGE `/doi/pdf/`、Wiley pdfdirect）。讀不到的那一頁可能是 Safari 的 PDF 檢視器，標題是文章標題：
    /// 先前文章站上仍以標題與網址判，`A Survey of CAPTCHA Design` 得 8（請使用者完成一個不存在的驗證）、`Analysis of unusual traffic patterns` 得 6。
    func testAnUnreadableTabOnTheArticleSiteIsHandedOverWhateverItsTitleSays() {
        for title in ["A Survey of CAPTCHA Design", "Analysis of unusual traffic patterns", "Access denied: refusal in therapy",
                      "Rate limited learning", "Verify you are human: a study", "Login behaviour in online games"] {
            var s = Scenario(); s.afterNavTitle = title; s.afterNavJSFails = true
            assertHandover(run(s), .unverifiable, title)
            XCTAssertTrue(outText.contains("https://pub.example/doi/pdf/10.1/x"), outText)
            XCTAssertFalse(outText.contains("resume:"), title)
        }
        // 文章站上的路徑字樣也不算（PDF 的路徑常有 `auth`、`validate`）
        var path = Scenario(); path.link = "GET https://pub.example/auth/12345.pdf"; path.afterNavJSFails = true
        assertHandover(run(path), .unverifiable)
    }

    /// 導航之後的接續（`followed`）落在同一個分頁：先前同一個標題再得 8，這一篇永遠走不完。
    func testResumingAfterNavigationOnAnUnreadableArticleSiteTabDoesNotLoopOnVerification() {
        let code = runResume(Scenario(), tab: ("https://pub.example/doi/pdf/10.1/x", "A Survey of CAPTCHA Design"), stage: .followed,
                             hook: Self.shownJSFails)
        assertHandover(code, .unverifiable)
    }

    /// 文章站上讀不到、而標題是驗證服務自己的標記（`Just a moment...`）：仍是等人驗證——封閉的六個標籤照訊號處理，與別的主機同一份清單。
    func testAnUnreadableArticleSiteTabWithAServiceMarkerStillWaits() {
        var s = Scenario(); s.afterNavTitle = "Just a moment..."; s.afterNavJSFails = true
        XCTAssertEqual(run(s), 8, errText)
        XCTAssertTrue(outText.contains("--resume-stage followed"), outText)
    }

    // MARK: 第 3 則（與 LOW 15、17）：讀不到的分頁停在登入主機 → 整批暫停（只看主機）

    /// 登入頁維持整批暫停（使用者 2026-10-02）。PDF 不從 IdP 主機出來，所以讀不到的分頁在登入主機上時整批暫停——只看主機，路徑與標題不看
    /// （`/auth/12345.pdf`、`Login behaviour in …` 是檔案與文章）。先前 R3 讀不到的分頁一律交給人（7、批次繼續）。
    func testAnUnreadableTabOnALoginHostPausesTheBatch() {
        for url in ["https://idp.uni.example/saml/login?SAMLRequest=SECRETSAML", "https://sso.uni.example/x", "https://idp-prod.uni.example/profile",
                    "https://login.uni.example/u", "https://my.openathens.example/redirector", "https://wayf.federation.example/ds",
                    "https://shib.shibboleth.uni.example/x"] {
            var s = Scenario(); s.afterNavURL = url; s.afterNavTitle = "University Sign in"; s.afterNavJSFails = true
            assertStop(run(s), url)
            XCTAssertTrue(errText.contains("(login page)"), errText)
            XCTAssertFalse(errText.contains("SECRETSAML"), errText)
        }
    }

    /// 主機的登入字詞不在最左邊的標籤（使用者 2026-10-05 第 4 則：`journals.auth.gr` 的 `auth` 是大學名稱）：讀不到的分頁照常交給人。
    func testAnUnreadableTabOnAHostWhoseLoginWordIsNotLeftmostIsHandedOver() {
        for url in ["https://journals.auth.gr/x.pdf", "https://files.sso-cdn.example.org/x.pdf", "https://www.cas.cn/x.pdf"] {
            var s = Scenario(); s.afterNavURL = url; s.afterNavTitle = "x.pdf"; s.afterNavJSFails = true
            assertHandover(run(s), .unverifiable, url)
        }
    }

    // MARK: 第 2、8 則：文章站上同一份快照

    /// 導航之後分頁先在文章站讀到 `text/html`、`complete`，讀頁面文字的那一下換到別的主機的 IdP 登入頁：先前以文章站的標題配登入頁的文字判、
    /// 交給人時再讀網址，得 7 `html-page`、批次繼續。讀完之後網址變了＝這一份不是同一頁的，回去等；新的一頁照別的主機判——登入頁，整批暫停。
    func testAPageChangeWhileReadingAnArticleSitePageIsNotMixedIntoOneJudgement() {
        var s = Scenario(); s.afterNavContentType = "text/html"; s.afterNavTitle = "Reader"
        var swapped = false
        let code = run(s) { args, fake in
            guard args[0] == "js", fake.navigated, args.last!.contains("innerText.slice"), !swapped else { return nil }
            swapped = true
            fake.tabs[1] = ("https://idp.uni.example/saml/login?x=SECRETX", "University Sign in")
            return SafariRun(status: 0, stdout: "\nUsername\nPassword\n")
        }
        assertStop(code)
        XCTAssertTrue(errText.contains("(login page)"), errText)
        XCTAssertFalse(outText.contains("html-page"), outText)
        XCTAssertFalse(errText.contains("SECRETX"), errText)
    }

    /// 文章站上的 HTML 頁交給人時，印的是判斷的那一頁的網址（快照），不是判完之後再讀一次的。
    func testTheHTMLPageHandoverPrintsTheJudgedURL() {
        var s = Scenario(); s.afterNavContentType = "text/html"; s.afterNavTitle = "Reader"; s.afterNavText = "Reader\nDownload PDF"
        assertHandover(run(s), .htmlPage)
        XCTAssertTrue(outText.contains("handover: html-page window 5 tab 2 https://pub.example/doi/pdf/10.1/x"), outText)
    }

    /// 導航之後分頁沒有離開文章頁：檢查的那一下換了頁就不是 `tab-unchanged`（先前交給人時才讀網址，印的是換過去的那一頁）。
    func testATabThatMovesDuringTheUnchangedCheckIsNotCalledUnchanged() {
        var s = Scenario(); s.afterNavURL = ""; s.afterNavContentType = "text/html"
        var swapped = false
        let code = run(s) { args, fake in
            guard args[0] == "js", fake.navigated, args.last!.contains("innerText.slice"), !swapped else { return nil }
            swapped = true
            fake.tabs[1] = ("https://idp.uni.example/login", "Sign in")
            return SafariRun(status: 0, stdout: "\nUsername\nPassword\n")
        }
        assertStop(code)
        XCTAssertFalse(outText.contains("tab-unchanged"), outText)
    }

    // MARK: 第 4 則：文章站上讀不到也要連續、同一個網址、從沒讀到過一般網頁

    /// 失敗、還在載入、失敗、失敗……：讀到過「還在載入」的網址是一般網頁，不是 PDF 檢視器。先前文章站上累積計數，得 7 `unverifiable`、
    /// 批次繼續（訊息還說「Safari 的 PDF 檢視器可能不跑頁面 JS」）；別的主機上同一串回答是 6 卡住。
    func testScatteredUnreadableAnswersOnTheArticleSiteAreAStall() {
        var polls = 0
        let code = run(Scenario()) { args, fake in
            guard args[0] == "js", fake.navigated, args.last!.contains("document.contentType") else { return nil }
            polls += 1
            return polls == 2 ? SafariRun(status: 0, stdout: "text/html\nloading\n") : SafariRun(status: 1)
        }
        assertStop(code)
        XCTAssertTrue(errText.contains("did not settle"), errText)
    }

    // MARK: 第 0 則：導航之前的接續，PDF 先於路徑的登入長相

    /// 舊的呼叫端沒帶 `--resume-stage`、驗證在導航之後、分頁已經顯示文章站上的 PDF：路徑有登入字詞（`/auth/12345.pdf`）也先交給人。
    /// 先前路徑的登入長相排在 PDF 之前，得 6。
    func testResumingBeforeNavigationOnASameSitePDFWithALoginWordInItsPathHandsItOver() {
        var s = Scenario(); s.currentContentType = "application/pdf"
        let code = runResume(s, tab: ("https://pub.example/auth/12345.pdf", "12345.pdf"), stage: .article)
        assertHandover(code, .pdfShown)
        XCTAssertTrue(outText.contains("https://pub.example/auth/12345.pdf"), outText)
    }

    /// 同一條路上不是 PDF 的頁面：路徑的登入長相照舊整批暫停。主機的登入長相仍在送任何 JS 之前就停（`FulltextR3Tests`）。
    func testResumingBeforeNavigationOnASameSiteLoginPathThatIsNotAPDFPauses() {
        let code = runResume(Scenario(), tab: ("https://pub.example/auth/realms/x", "Sign in"), stage: .article)
        assertStop(code)
        XCTAssertTrue(errText.contains("(login page)"), errText)
        XCTAssertFalse(browser.calls.contains { $0.hasPrefix("navigate") || $0.hasPrefix("close") }, "\(browser.calls)")
    }

    // MARK: LOW 21：導航之前的接續讀分頁此刻的網址，驗證頁的網址而沒有訊號就等它轉走

    /// 使用者說驗證完了，分頁還在 `/captcha/`、文字是 `Thank you. Redirecting.`：先前以接續開始時讀的舊網址套驗證頁的長相，得 6。
    /// 現在等它轉走（只讀分頁網址，不送 JS），轉到文章頁之後照常往下走。
    func testResumingWhileTheVerificationPageRedirectsWaitsForIt() {
        var s = Scenario(); s.link = "GET https://opg.optica.example/x.pdf"
        var documents = 0
        let captcha = "https://opg.optica.example/captcha/?url=x"
        let code = runResume(s, tab: (captcha, "Please wait"), origin: "https://opg.optica.example", stage: .article) { args, fake in
            if args[0] == "documents", !fake.navigated {
                documents += 1
                if documents == 12 { fake.tabs[1] = ("https://opg.optica.example/abstract.cfm?URI=x", "Article") }
                return nil
            }
            if args[0] == "js", args.last!.contains("innerText.slice"), !fake.navigated {
                return SafariRun(status: 0, stdout: fake.tabs[1].url == captcha ? "\nThank you. Redirecting.\n" : "\nArticle page\n")
            }
            return nil
        }
        assertHandover(code, .pdfShown)
        let textReadsOnCaptcha = browser.injected.filter { $0.contains("innerText.slice") }.count
        XCTAssertLessThanOrEqual(textReadsOnCaptcha, 4, "等它轉走的時候不讀頁面文字：\(textReadsOnCaptcha)")
    }

    /// 一直沒轉走：整批暫停，訊息說分頁停在驗證頁的網址上。
    func testResumingOnAVerificationURLThatNeverMovesPauses() {
        var s = Scenario(); s.pageText = "Thank you. Redirecting."
        let code = runResume(s, tab: ("https://pub.example/captcha/?url=x", "Please wait"), stage: .article)
        assertStop(code)
        XCTAssertTrue(errText.contains("(verification page)"), errText)
    }

    // MARK: 第 6 則（與 LOW 9、23）：頁面連結的帳密

    /// 帶帳密的落地頁上，同一組帳密的同站連結（相對連結經 WHATWG 解析沿用 base 的帳密）：先前站的 origin 去了帳密、連結的沒去，兩邊永遠
    /// 不等，得 1 `points off-site` 並把帳密印到 stderr。站的比對看主機與埠號。
    func testALinkCarryingTheSameCredentialsAsThePageIsFollowed() {
        var s = Scenario(); s.landingFinal = "https://alice:s3cretpw@pub.example/doi/10.1/x"; s.link = "GET https://alice:s3cretpw@pub.example/doi/pdf/10.1/x"
        assertHandover(run(s), .pdfShown)
        XCTAssertFalse((outText + errText).lowercased().contains("s3cretpw"), outText + errText)
        let ledger = (try? String(contentsOfFile: lastLedger, encoding: .utf8)) ?? ""
        XCTAssertTrue(ledger.contains("\"site\":\"pub.example\""), ledger)
        XCTAssertFalse(ledger.lowercased().contains("s3cretpw"), ledger)
    }

    /// 連到別的主機、連結帶帳密：照舊拒絕（1），訊息印的 origin 不帶帳密。
    func testAnOffSiteLinkIsRefusedWithoutPrintingItsCredentials() {
        var s = Scenario(); s.link = "GET https://bob:LINKSECRET@cdn.example/x.pdf"
        XCTAssertEqual(run(s), 1, errText)
        XCTAssertTrue(errText.contains("points off-site (https://cdn.example, page origin https://pub.example)"), errText)
        XCTAssertFalse(errText.lowercased().contains("linksecret"), errText)
    }

    func testLinkTargetOriginComparesHostAndPortOnly() {
        XCTAssertEqual(FulltextFetch.linkTargetOrigin("https://u:p@Pub.Example/x"), "https://pub.example")
        XCTAssertEqual(FulltextFetch.linkTargetOrigin("https://pub.example:8443/x"), "https://pub.example:8443")
        XCTAssertNil(FulltextFetch.linkTargetOrigin("https://u:p@/x"), "主機是空的")
    }

    // MARK: LOW 9、19：主機前的帳密以 scalar 切；反斜線結束 authority（WHATWG）

    func testHostPortStripsCredentialsEvenBeforeACombiningMark() {
        let u = URLSplit("https://user:SECRETPW@\u{0301}pub.example/x")
        XCTAssertFalse(u.hostPort.contains("SECRETPW"), u.hostPort)
        XCTAssertFalse(u.siteOrigin.contains("SECRETPW"), u.siteOrigin)
    }

    /// `https://evil.example\@pub.example/x`：WHATWG 把 `\` 當 `/`，主機是 `evil.example`。先前去帳密時切最後一個 `@`，把它當成文章站（fail open）。
    func testABackslashEndsTheAuthorityForTheSiteComparison() {
        XCTAssertEqual(URLSplit("https://evil.example\\@pub.example/x").siteOrigin, "https://evil.example")
        var s = Scenario(); s.afterNavURL = "https://idp.evil.example\\@pub.example/doi/pdf/x"; s.afterNavTitle = "Sign in"
        s.afterNavContentType = "text/html"; s.afterNavText = "Username\nPassword"
        assertStop(run(s))
        XCTAssertTrue(errText.contains("(login page)"), errText)
    }

    // MARK: LOW 11、18：讀的當中一直在變的頁面，停止訊息照實說

    /// 落定了、網址不變、標題每讀一次都變（倒數計時的「Redirecting in N s」）：一份快照都拿不到。仍是整批暫停（往停的那一邊），但訊息說
    /// 頁面在讀的當中一直變，不是只說沒落定。
    func testAPageWhoseTitleKeepsChangingSaysSoWhenItStalls() {
        var s = Scenario(); s.afterNavURL = "https://hub.other.example/retrieve/x"; s.afterNavTitle = "Redirecting"; s.afterNavContentType = "text/html"
        var n = 0
        let code = run(s) { args, fake in
            if args[0] == "documents", fake.navigated { n += 1; fake.tabs[1].title = "Redirecting in \(n) s" }
            return nil
        }
        assertStop(code)
        XCTAssertTrue(errText.contains("changed while it was being read"), errText)
    }

    // MARK: LOW 12、13、20、24：網址去憑證

    func testPlainURLDropsMoreSessionForms() {
        XCTAssertEqual(FulltextFetch.plainURL("https://host/(A(abc)F(def))/x.aspx"), "https://host/x.aspx")
        XCTAssertEqual(FulltextFetch.plainURL("https://host/(S(zzzz))(F(yyyy))/x.aspx"), "https://host/x.aspx")
        XCTAssertEqual(FulltextFetch.plainURL("https://host/(X(1)S(abc))/x.aspx"), "https://host/x.aspx")
        XCTAssertEqual(FulltextFetch.plainURL("https://host/x%3Bjsessionid%3DLEAK/y"), "https://host/x/y")
        XCTAssertEqual(FulltextFetch.plainURL("https://host/x%3bjsessionid=LEAK"), "https://host/x")
        XCTAssertEqual(FulltextFetch.plainURL("//u:p@h.example/x"), "//h.example/x")
        // SICI 式 DOI 與一般的括號不動
        let sici = "https://onlinelibrary.wiley.com/doi/10.1002/(SICI)1097-4571(199806)49:8%3C693::AID-ASI4%3E3.0.CO;2-0"
        XCTAssertEqual(FulltextFetch.plainURL(sici), sici)
        XCTAssertEqual(FulltextFetch.plainURL("https://pub.example/doi/10.1016/S0022-2496(05)80001-1"), "https://pub.example/doi/10.1016/S0022-2496(05)80001-1")
    }

    /// safari-browser 自己的 stderr 原樣轉印之前，裡面的網址先去憑證（先前 `open:`、導航失敗、讀連結失敗三處原樣印）。
    func testSafariBrowsersOwnErrorsDoNotCarrySignedURLs() {
        let code = run(Scenario()) { args, fake in
            guard args[0] == "open", !args.contains("--new-tab") else { return nil }
            return SafariRun(status: 1, stderr: "error: could not open https://pub.example/doi/pdf/10.1/x?X-Amz-Signature=NAVSECRET in the tab\n")
        }
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("https://pub.example/doi/pdf/10.1/x in the tab"), errText)
        XCTAssertFalse(errText.contains("NAVSECRET"), errText)

        var linkFails = Scenario(); linkFails.linkJSFails = true
        let code2 = run(linkFails) { args, _ in
            guard args[0] == "js", args.last!.contains("citation_pdf_url") else { return nil }
            return SafariRun(status: 1, stderr: "TypeError at https://pub.example/x;jsessionid=LINKSESSION\n")
        }
        XCTAssertEqual(code2, 1, errText)
        XCTAssertFalse(errText.contains("LINKSESSION"), errText)
    }

    // MARK: LOW 14：帳本的 landing 也去憑證

    func testTheLedgerLandingCarriesNoQueryOrPathParameters() throws {
        _ = run(Scenario(), landing: "https://doi.org/10.1/x?ticket=ST-1-LANDSECRET")
        let ledger = try String(contentsOfFile: lastLedger, encoding: .utf8)
        XCTAssertFalse(ledger.contains("LANDSECRET"), ledger)
        XCTAssertTrue(ledger.contains("\"landing\":\"https://doi.org/10.1/x\""), ledger)
    }

    // MARK: 使用者 2026-10-05 第 2、3、4 則：網頁副檔名、複合路徑段、主機標籤

    /// 第 4 則：主機名稱裡帶 auth 一類字樣的期刊平台不再因此整批暫停。登入字詞只認最左邊的標籤；IdP 服務的名稱在任何一個標籤都算。
    func testHostLoginWordsCountOnlyInTheLeftmostLabelOrAsIdentityProviderNames() {
        for url in ["https://journals.auth.gr/index.php/x", "https://www.cas.cn/x", "https://files.sso-cdn.example.org/x", "https://user:login@pub.example/x",
                    "https://pub.example:443/x"] {
            XCTAssertFalse(BotSignals.hostLoginLook(url), url)
            XCTAssertNil(BotSignals.urlGateLook(url), url)
        }
        for url in ["https://sso.uni.example/x", "https://idp-prod.uni.example/x", "https://sign-in.example/x", "https://login.microsoftonline.example/x",
                    "https://auth.uni.example/x", "https://cas.uni.example/x", "https://my.openathens.example/x", "https://wayf.federation.example/x",
                    "https://idp.shibboleth.uni.example/x", "https://saml.uni.example/x", "https://uni-saml.example/x"] {
            XCTAssertTrue(BotSignals.hostLoginLook(url), url)
            XCTAssertEqual(BotSignals.urlGateLook(url), "login", url)
        }
        XCTAssertTrue(BotSignals.identityProviderNames.isSubset(of: BotSignals.loginTokens))
        // 驗證字詞在主機的任何一個字都算（沒有被裁決收窄）
        XCTAssertEqual(BotSignals.urlGateLook("https://verify.other.example/c"), "verification")
        XCTAssertEqual(BotSignals.urlGateLook("https://x.captcha-host.example/c"), "verification")
    }

    /// DOI 落地在 `journals.auth.gr` 這種平台：先前每一篇都停在落地頁（6）；現在照常走到 PDF。
    func testALandingOnAJournalPlatformWithAuthInItsHostGoesOn() {
        var s = Scenario(); s.landingFinal = "https://journals.auth.gr/index.php/x/article/view/1"
        s.link = "GET https://journals.auth.gr/index.php/x/article/download/1/2"
        assertHandover(run(s), .pdfShown)
    }

    /// 第 2 則：網頁副檔名加 `cfm`、`xhtml`、`jsf` 等。
    func testMoreDynamicPageExtensionsCount() {
        for ext in ["cfm", "cfml", "xhtml", "jsf", "jspx", "faces", "shtml", "phtml"] {
            XCTAssertEqual(BotSignals.urlGateLook("https://pub.example/login.\(ext)"), "login", ext)
            XCTAssertEqual(BotSignals.urlGateLook("https://pub.example/captcha.\(ext)"), "verification", ext)
            XCTAssertTrue(BotSignals.pageExtensions.contains(ext), ext)
        }
        XCTAssertNil(BotSignals.urlGateLook("https://cdn.example/login.pdf"), "PDF 不是網頁副檔名")
        var s = Scenario(); s.landingFinal = "https://pub.example/login.cfm?url=x"
        assertStop(run(s))
    }

    /// 第 3 則：`/sso-login`、`/login-required` 這類複合段算登入頁。只拆網頁名稱（沒有副檔名、或副檔名是網頁副檔名）——檔名（`.pdf`）與
    /// DOI 片段不拆；驗證字詞不拆（沒有被裁決放寬）。使用者 2026-10-09 收窄成只認明確的登入字（`FulltextB37Tests`）：`auth-callback` 不再算。
    func testCompoundPathSegmentsWithALoginWordAreLoginPages() {
        for url in ["https://pub.example/sso-login", "https://pub.example/login-required", "https://pub.example/user_login.php",
                    "https://pub.example/sign-in-required", "https://pub.example/shibboleth-ds"] {
            XCTAssertEqual(BotSignals.urlGateLook(url), "login", url)
        }
        for url in ["https://pub.example/x/auth-callback.jsf",
                    "https://cdn.example/files/how-to-login-guide.pdf", "https://pub.example/loginhelp-faq", "https://pub.example/the-challenge-of-replication",
                    "https://pub.example/doi/10.1016/S0022-2496(05)80001-1", "https://pub.example/doi/10.3758/s13428-019-01234-5",
                    "https://pub.example/catalog-in-print", "https://pub.example/10.1111/cas.12345"] {
            XCTAssertNil(BotSignals.urlGateLook(url), url)
        }
        var s = Scenario(); s.landingFinal = "https://pub.example/sso-login?target=x"
        assertStop(run(s))
        XCTAssertTrue(errText.contains("(login page)"), errText)
    }

    // MARK: LOW 10：SKILL 稱為封閉的清單與程式對帳

    private func skillText() throws -> String {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repo.appendingPathComponent("plugin/skills/akashic-fetch-fulltext/SKILL.md"), encoding: .utf8)
    }

    private func ticks(_ s: Substring) -> [String] {
        var out: [String] = []; var rest = s
        while let open = rest.firstIndex(of: "`") {
            let after = rest.index(after: open)
            guard let close = rest[after...].firstIndex(of: "`") else { break }
            out.append(String(rest[after..<close])); rest = rest[rest.index(after: close)...]
        }
        return out
    }

    private func between(_ text: String, _ start: String, _ end: String, file: StaticString = #filePath, line: UInt = #line) -> Substring {
        guard let a = text.range(of: start), let b = text.range(of: end, range: a.upperBound..<text.endIndex) else {
            XCTFail("SKILL 找不到「\(start)」…「\(end)」", file: file, line: line); return ""
        }
        return text[a.upperBound..<b.lowerBound]
    }

    /// 讀不到的分頁只看的六個驗證服務標籤：SKILL 先前只以散文描述（Akamai、PerimeterX…），兩邊各改各的不會有任何東西紅（b33 X3 第 10 則）。
    func testTheSkillsServiceMarkerListIsTheCodesList() throws {
        let list = between(try skillText(), "封閉的六個標籤（`BotSignals.serviceMarkerLabels`）：", "（Akamai")
        XCTAssertEqual(Set(ticks(list)), BotSignals.serviceMarkerLabels)
        XCTAssertEqual(ticks(list).count, BotSignals.serviceMarkerLabels.count, "沒有重複")
    }

    /// IdP 服務名（主機任何一個標籤都算）：SKILL 的清單就是程式的集合。
    func testTheSkillsIdentityProviderListIsTheCodesList() throws {
        let list = between(try skillText(), "封閉清單（`BotSignals.identityProviderNames`）：", "；")
        XCTAssertEqual(Set(ticks(list)), BotSignals.identityProviderNames)
    }

    /// 〈交給人之後〉的表逐一列交給人的原因：表的原因就是 `Handover` 的全部 `rawValue`（先前 SKILL 說「只有這四種」而程式有七種，
    /// 範圍只是隱含的——b33 X3 第 10 則，與 b31 W4 第 5 則同形）。另外，「分頁到了別的主機時只有這四種」的四種要在表裡。
    func testTheSkillsHandoverTableIsTheHandoverEnum() throws {
        let skill = try skillText()
        let table = between(skill, "| 原因 | 請使用者做什麼 |", "`pdf-shown` 也包含")
        let reasons = table.split(separator: "\n").filter { $0.hasPrefix("| `") }.compactMap { ticks($0).first }
        XCTAssertEqual(Set(reasons), Set(FulltextFetch.Handover.allCases.map(\.rawValue)))
        XCTAssertEqual(reasons.count, FulltextFetch.Handover.allCases.count, "\(reasons)")
        let offSite = between(skill, "交給人的原因**只有這四種**", "沒有命中封閉清單**不代表不是登入頁**")
        let named = Set(ticks(offSite)).intersection(Set(FulltextFetch.Handover.allCases.map(\.rawValue)))
        XCTAssertEqual(named, ["pdf-shown", "left-site", "unverifiable", "doi-not-resolved", "html-page", "tab-unchanged", "button"],
                       "四種在別的主機上、三種只在文章站上，兩組合起來是全部")
    }
}
