import XCTest
@testable import AkashicSkillTools
@testable import AkashicStoreIO

/// #613 b37：b36 verify（Y2）的三則 MEDIUM 與使用者 2026-10-09 的裁決。與 `FulltextFetchPathTests` 同一個記憶體內的假瀏覽器——不碰 Safari、
/// 不連網。
final class FulltextB37Tests: XCTestCase {
    typealias Scenario = FulltextFetchPathTests.Scenario
    typealias FakeBrowser = FulltextFetchPathTests.FakeBrowser

    private var root: URL!
    private var stdout: [String] = []
    private var stderr: [String] = []
    private var browser: FakeBrowser!
    static let now = FulltextFetchPathTests.now
    static let landing = FulltextFetchPathTests.landing

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fetch-b37-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private var ledger: String { root.appendingPathComponent("state/attempts.jsonl").path }

    @discardableResult
    private func run(_ scenario: Scenario, hook: ((_ args: [String], _ fake: FakeBrowser) -> SafariRun?)? = nil) -> Int32 {
        browser = FakeBrowser(scenario)
        browser.hook = hook
        stdout = []; stderr = []
        let fetcher = FulltextFetch(browser: browser, sleeper: { _ in }, now: { Self.now },
                                    out: { self.stdout.append($0) }, err: { self.stderr.append($0) })
        return fetcher.run(.init(window: 5, landing: Self.landing, ledger: ledger))
    }

    private func runResume(_ s: Scenario, tab: (String, String), hook: ((_ args: [String], _ fake: FakeBrowser) -> SafariRun?)? = nil) -> Int32 {
        browser = FakeBrowser(s)
        browser.tabs.append(tab)
        browser.hook = hook
        stdout = []; stderr = []
        let fetcher = FulltextFetch(browser: browser, sleeper: { _ in }, now: { Self.now }, out: { self.stdout.append($0) }, err: { self.stderr.append($0) })
        return fetcher.run(.init(window: 5, landing: Self.landing, ledger: ledger, resumeTab: 2, resumeOrigin: "https://pub.example", resumeStage: .article))
    }

    private var errText: String { stderr.joined(separator: "\n") }
    private var outText: String { stdout.joined(separator: "\n") }
    private var navigations: [String] { browser.calls.filter { $0.hasPrefix("navigate ") } }
    private var ledgerText: String { (try? String(contentsOfFile: ledger, encoding: .utf8)) ?? "" }

    /// 整批暫停：結束碼 6、不印 resume、沒有導航到 PDF、沒有記嘗試。
    private func assertLoginStop(_ code: Int32, _ note: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(code, 6, "\(note)\n\(errText)\n\(outText)", file: file, line: line)
        XCTAssertTrue(errText.contains("STOP THE WHOLE RUN"), "\(note)\n\(errText)", file: file, line: line)
        XCTAssertTrue(errText.contains("(login page)"), "\(note)\n\(errText)", file: file, line: line)
        XCTAssertFalse(errText.contains("WAITING FOR HUMAN VERIFICATION"), "\(note)\n\(errText)", file: file, line: line)
        XCTAssertFalse(outText.contains("resume:"), "整批暫停不印 resume 參數：\(note)\n\(outText)", file: file, line: line)
        XCTAssertTrue(navigations.isEmpty, "\(note)\n\(browser.calls)", file: file, line: line)
        XCTAssertFalse(ledgerText.contains("\"site\""), "沒有記嘗試：\(note)\n\(ledgerText)", file: file, line: line)
    }

    /// 頁面文字的那一段 JS：第 `nth` 次讀時把我們的分頁換到 `to`（同站的登入頁），回含 CAPTCHA 的文字。
    private static func movesToALoginPageWhileReading(onRead nth: Int, to url: String) -> (_ args: [String], _ fake: FakeBrowser) -> SafariRun? {
        var reads = 0
        return { args, fake in
            guard args[0] == "js", !fake.navigated, args.last!.contains("innerText.slice") else { return nil }
            reads += 1
            if reads == nth { fake.tabs[1] = (url, "Sign in") }
            return SafariRun(status: 0, stdout: reads >= nth ? "\nSign in\nPlease complete the CAPTCHA below\n" : "\nArticle\nAbstract text\n")
        }
    }

    // MARK: MEDIUM 0：讀頁中途換到同站的登入頁，登入的長相先於起疑訊號

    /// 落地頁通過網址檢查之後，讀頁面文字的當中分頁轉到同站的 `/login`，那一頁的文字有 CAPTCHA。先前 `botCheckPage` 對重讀得到的穩定快照
    /// 直接判起疑訊號：同站的 CAPTCHA 是等人驗證（8），印出以文章站為目標的 `resume:`。登入頁的網址是比頁面文字更強的證據（R3 已把落地頁的
    /// 這個順序定下來），重讀得到的那一頁也要同一個順序：整批暫停（6）。
    func testALandingThatTurnsIntoASameSiteLoginPageWhileBeingReadPauses() {
        let code = run(Scenario(), hook: Self.movesToALoginPageWhileReading(onRead: 1, to: "https://pub.example/login?next=x"))
        assertLoginStop(code)
    }

    /// 同一件事在讀 PDF 連結之前的那一次檢查（`followThePagesOwnLink` 的 `botCheckPage`）：先前那裡連登入檢查都沒有。
    func testTheCheckBeforeReadingTheLinkAlsoPutsTheLoginLookFirst() {
        let code = run(Scenario(), hook: Self.movesToALoginPageWhileReading(onRead: 2, to: "https://pub.example/sso-login"))
        assertLoginStop(code)
    }

    /// 導航之前的接續（`--resume-stage article`）：使用者驗證完，讀頁面的當中分頁轉到同站的登入頁。
    func testResumingBeforeNavigationIntoASameSiteLoginPageWhileBeingReadPauses() {
        let code = runResume(Scenario(), tab: ("https://pub.example/doi/10.1/x", "Article"),
                             hook: Self.movesToALoginPageWhileReading(onRead: 1, to: "https://pub.example/signin"))
        assertLoginStop(code)
    }

    /// 對照（刻意不動）：導航**之後**分頁沒離開文章頁、檢查的當中轉到同站的登入頁——那是頁面自己的 PDF 連結的結果（沒有權限時常見），
    /// 與 `decideShown` 同一套：同站的 HTML 頁只看文字訊號，交給人 `html-page`，不看網址的登入長相（b36 Y2 第 16 則記下的既有行為）。
    func testAfterNavigationASameSiteLoginPageIsStillHandedOverAsAnHTMLPage() {
        var s = Scenario(); s.afterNavURL = ""; s.afterNavContentType = "text/html"
        var swapped = false
        let code = run(s) { args, fake in
            guard args[0] == "js", fake.navigated, args.last!.contains("innerText.slice"), !swapped else { return nil }
            swapped = true
            fake.tabs[1] = ("https://pub.example/login", "Sign in")
            return SafariRun(status: 0, stdout: "\nSign in\nUsername\n")
        }
        XCTAssertEqual(code, 7, errText)
        XCTAssertTrue(outText.contains("handover: html-page window 5 tab 2 https://pub.example/login"), outText)
    }

    // MARK: MEDIUM 1：safari-browser 的 stderr 只轉印第一行

    /// safari-browser 的 `documentNotFound` 從第三行起列出所有視窗的目前分頁——含使用者其他 profile 的 session。這個命令沒帶 `--profile`，
    /// 那份清單不過濾；網址去掉查詢字串之後，主機與路徑（含路徑裡的帳號）仍在。
    static let documentNotFound = """
    Error: No Safari document matches "window 5 tab 2".
    (The flag is supported and did run — this is a targeting miss, not an unknown option.)
    Available documents:
      [1] window 1: https://mail.other-profile.example/u/0/?ik=MAILSECRET
      [2] window 2 (Safari window 3): https://bank.example/accounts/4417-1234-5678/statement
    Hint: run `safari-browser documents` to list targets.

    """

    private func assertOnlyTheFirstLine(_ code: Int32, _ note: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(code, 1, "\(note)\n\(errText)", file: file, line: line)
        XCTAssertTrue(errText.contains("No Safari document matches \"window 5 tab 2\"."), "\(note)\n\(errText)", file: file, line: line)
        for leak in ["mail.other-profile", "MAILSECRET", "bank.example", "4417-1234-5678", "Available documents"] {
            XCTAssertFalse(errText.contains(leak), "\(note)：\(leak)\n\(errText)", file: file, line: line)
        }
        XCTAssertTrue(errText.contains("5 more lines from safari-browser not shown"), "\(note)\n\(errText)", file: file, line: line)
    }

    func testOpeningTheTabRelaysOnlyTheFirstLineOfSafariBrowsersError() {
        let code = run(Scenario()) { args, _ in
            args[0] == "open" && args.contains("--new-tab") ? SafariRun(status: 1, stderr: Self.documentNotFound) : nil
        }
        assertOnlyTheFirstLine(code, "open")
    }

    func testReadingTheLinkRelaysOnlyTheFirstLineOfSafariBrowsersError() {
        let code = run(Scenario()) { args, _ in
            args[0] == "js" && args.last!.contains("citation_pdf_url") ? SafariRun(status: 1, stderr: Self.documentNotFound) : nil
        }
        assertOnlyTheFirstLine(code, "link")
    }

    func testNavigatingRelaysOnlyTheFirstLineOfSafariBrowsersError() {
        let code = run(Scenario()) { args, _ in
            args[0] == "open" && !args.contains("--new-tab") ? SafariRun(status: 1, stderr: Self.documentNotFound) : nil
        }
        assertOnlyTheFirstLine(code, "navigation")
    }

    /// 第一行的網址照樣去憑證；CRLF 的輸出也只取第一行（Swift 的 `\r\n` 是一個 `Character`）；沒有訊息時說沒有。
    func testTheRelayedLineIsRedactedAndCRLFIsALineBreak() {
        XCTAssertEqual(FulltextFetch.safariFailure("Target tab changed mid-command: https://pub.example/x?sig=S1 moved\r\nTarget position now shows: https://bank.example/acct\r\n"),
                       "Target tab changed mid-command: https://pub.example/x moved (1 more line from safari-browser not shown: it can list other tabs and profiles)")
        XCTAssertEqual(FulltextFetch.safariFailure("\n\n  boom  \n"), "boom")
        XCTAssertEqual(FulltextFetch.safariFailure(""), "(safari-browser printed no message)")
    }

    // MARK: LOW 11、INFO 20、21：印出的主機就是站的比對用的主機

    /// `plainURL` 與 `URLSplit.hostPort`（`sameSite`、`siteOrigin`、`linkTargetOrigin` 都用它）先前各切各的：authority 裡的反斜線、`://` 出現在
    /// 路徑裡的沒有 scheme 的網址，兩邊說的主機不同，帳密也可能原樣印出。
    func testPlainURLNamesTheHostTheSiteComparisonUses() {
        for url in ["https://evil.example\\@pub.example/x", "https://u:p@\u{301}pub.example/x", "//u:p@h.example/x", "//u:SECRET@h.example/a/https://z/q",
                    "https://u:SECRET@pub.example/a://b", "https://pub.example:8443/x;jsessionid=1", "https://user:SECRET@pub.example\\x/y"] {
            let printed = FulltextFetch.plainURL(url)
            XCTAssertEqual(URLSplit(printed).hostPort, URLSplit(url).hostPort, "\(url) → \(printed)")
            XCTAssertFalse(printed.contains("SECRET"), "\(url) → \(printed)")
        }
        XCTAssertEqual(FulltextFetch.plainURL("https://evil.example\\@pub.example/x"), "https://evil.example/x")
        XCTAssertEqual(FulltextFetch.plainURL("//u:SECRET@h.example/a/https://z/q?x=1"), "//h.example/a/https://z/q")
        XCTAssertEqual(FulltextFetch.plainURL("https:no-authority;jsessionid=1"), "https:no-authority")
    }

    // MARK: MEDIUM 2、3：複合路徑段只認明確的登入字（使用者 2026-10-09）

    /// 裁決：複合段裡只有明確的登入字才算（`login`、`logon`、`signin`，與 `sign-in`、`log-in` 這種連字號寫法）；`cas`、`auth`、`idp`、`sso`
    /// 只有整個路徑段就是這個字時才算。`/sso-login`、`/login-required` 仍算。
    func testCompoundSegmentsCountOnlyExplicitLoginWords() {
        for url in ["https://pub.example/sso-login", "https://pub.example/login-required", "https://pub.example/user_login.php",
                    "https://pub.example/sign-in-required", "https://pub.example/please-log-in", "https://pub.example/logon-page",
                    "https://pub.example/signin-help", "https://pub.example/shibboleth-ds", "https://pub.example/saml-redirect",
                    "https://pub.example/openathens-redirect.do", "https://pub.example/wayf-select",
                    // 整段：歧義的四個字整段就是那個字時仍算；整段可省連字號與底線（明確的登入字）
                    "https://pub.example/cas", "https://pub.example/auth/realms/x", "https://pub.example/idp/profile", "https://pub.example/sso.php",
                    "https://pub.example/cas;jsessionid=AB", "https://pub.example/sign-in", "https://pub.example/log_in", "https://pub.example/log-on",
                    // 代價（裁決保留 sign-in、log-in 的連字號寫法）：標題 slug 裡相鄰的 sign、in 也算
                    "https://pub.example/article/psychopathy-and-sign-in-language", "https://pub.example/article/how-to-log-in-to-research",
                    "https://pub.example/article/login-behaviour-in-online-games"] {
            XCTAssertEqual(BotSignals.urlGateLook(url), "login", url)
        }
        // verify（b36 Y2 第 2、3、8 則）量到的誤停：歧義的字在 slug 裡、相鄰兩字接起來湊成的字、整段去掉連字號才湊成的字
        for url in ["https://www.cambridge.org/core/journals/psychological-medicine/article/the-cognitive-assessment-system-cas-in-children/AB12CD",
                    "https://www.erudit.org/fr/revues/x/2020-v-n/un-cas-de-diplomatie/",
                    "https://pub.example/blog/sso-and-research", "https://pub.example/article/idp-and-the-role-of-sso-in-universities/AB12CD",
                    "https://www.cambridge.org/core/journals/psychological-medicine/article/hepatitis-c-as-a-public-health-problem/ABCDEF",
                    "https://pub.example/vitamin-c-as-an-antioxidant", "https://pub.example/cluster-c-as-a-diagnostic-category",
                    "https://pub.example/the_role_of_c_as_a_moderator", "https://pub.example/the-role-of-ss-o-in-x",
                    "https://pub.example/de-novo-au-th-assembly", "https://pub.example/ca-s-9-systems", "https://pub.example/what-is-log-on-log-scale",
                    "https://www.cambridge.org/core/journals/psychometrika/article/crispr-cas-systems-and-learning/ABC123",
                    "https://pub.example/article/how-to-authenticate-participants/ABC", "https://example.org/news/idp-update",
                    "https://pub.example/two-factor-auth-usability", "https://pub.example/x/auth-callback.jsf",
                    "https://pub.example/c-as", "https://pub.example/au_th", "https://pub.example/s-s-o",
                    // 既有的負例
                    "https://cdn.example/files/how-to-login-guide.pdf", "https://pub.example/loginhelp-faq", "https://pub.example/catalog-in-print",
                    "https://pub.example/10.1111/cas.12345"] {
            XCTAssertNil(BotSignals.urlGateLook(url), url)
        }
    }

    /// 兩份封閉清單的關係：複合段算的字都是登入字詞；IdP 服務的名稱（使用者 2026-10-05 第 4 則已認定為不歧義）在複合段也算；歧義的四個字不在。
    func testTheCompoundListIsTheExplicitPartOfTheLoginWords() {
        XCTAssertTrue(BotSignals.compoundLoginWords.isSubset(of: BotSignals.loginTokens))
        XCTAssertTrue(BotSignals.identityProviderNames.isSubset(of: BotSignals.compoundLoginWords))
        XCTAssertTrue(BotSignals.compoundLoginWords.isDisjoint(with: ["cas", "auth", "idp", "sso", "authenticate"]))
        XCTAssertEqual(BotSignals.compoundLoginJoins.map { $0.first + $0.second }, ["signin", "login"])
    }

    /// 完整流程：Cambridge Core 的文章網址帶著標題 slug。b34 起「hepatitis-c-as-…」在落地頁就整批暫停（`c`＋`as`＝`cas`）；照裁決照常走到 PDF。
    func testALandingWhoseSlugJoinsIntoAnAmbiguousWordGoesOn() {
        var s = Scenario()
        s.landingFinal = "https://www.cambridge.org/core/journals/psychological-medicine/article/hepatitis-c-as-a-public-health-problem/ABCDEF"
        s.link = "GET https://www.cambridge.org/core/services/aop-cambridge-core/content/view/ABCDEF"
        let code = run(s)
        XCTAssertEqual(code, 7, errText)
        XCTAssertTrue(outText.contains("handover: pdf-shown"), outText)
    }

    /// SKILL〈整批暫停〉的複合段清單就是程式的兩份清單（對帳）。
    func testTheSkillsCompoundListsAreTheCodesLists() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let skill = try String(contentsOf: repo.appendingPathComponent("plugin/skills/akashic-fetch-fulltext/SKILL.md"), encoding: .utf8)
        func ticks(_ s: Substring) -> [String] {
            var out: [String] = []; var rest = s
            while let open = rest.firstIndex(of: "`") {
                let after = rest.index(after: open)
                guard let close = rest[after...].firstIndex(of: "`") else { break }
                out.append(String(rest[after..<close])); rest = rest[rest.index(after: close)...]
            }
            return out
        }
        func between(_ start: String, _ end: String) -> Substring {
            guard let a = skill.range(of: start), let b = skill.range(of: end, range: a.upperBound..<skill.endIndex) else {
                XCTFail("SKILL 找不到「\(start)」…「\(end)」"); return ""
            }
            return skill[a.upperBound..<b.lowerBound]
        }
        XCTAssertEqual(Set(ticks(between("複合段的登入字（`BotSignals.compoundLoginWords`）：", "；"))), BotSignals.compoundLoginWords)
        XCTAssertEqual(ticks(between("相鄰兩字接起來（`BotSignals.compoundLoginJoins`）：", "；")),
                       BotSignals.compoundLoginJoins.map { "\($0.first)-\($0.second)" })
    }
}
