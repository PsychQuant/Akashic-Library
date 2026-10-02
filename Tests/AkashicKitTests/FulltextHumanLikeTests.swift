import XCTest
import JavaScriptCore
@testable import AkashicSkillTools

/// #613「跟真人一樣」的幾個純函式面：起疑訊號分兩種處置、每日嘗試帳本、注入頁面的 JS 能當運算式解析。
final class BotSignalsResponseTests: XCTestCase {
    /// 等人驗證只有四種（使用者 2026-10-01 的封閉列舉）。
    func testTheFourVerificationKinds() {
        let cases: [(String, String)] = [
            ("Please complete the CAPTCHA to continue", "captcha"),
            // ScienceDirect 2026-09-28 的 CAPTCHA 頁：captcha 與 human-check 都命中，照清單順序取前者，兩者都是等人驗證
            ("Are you a robot? Please confirm you are a human by completing the captcha challenge below.", "captcha"),
            ("Are you a robot?", "human-check"),
            ("<title>Just a moment...</title>", "cloudflare-challenge"),
            ("Press & Hold to confirm you are a human (and not a bot).", "perimeterx-press-and-hold"),
        ]
        for (text, label) in cases {
            XCTAssertEqual(BotSignals.classify(text), BotSignals.Hit(label: label, response: .humanVerification), text)
        }
    }

    /// 其他一律整批暫停：封鎖頁、異常流量、請求過多、PMC 的下載前驗證頁、ScienceDirect 的中介頁、403／429。
    func testEverythingElsePausesTheBatch() {
        let cases: [(String, Int?, String)] = [
            ("Pardon Our Interruption", nil, "akamai-block"),
            ("Access to this page has been denied.", nil, "perimeterx-block"),
            ("<script src=https://ct.captcha-delivery.com/c.js>", nil, "datadome-block"),
            ("Access Denied", nil, "access-denied"),
            ("We have detected unusual traffic from your network", nil, "unusual-traffic"),
            ("Too many requests", nil, "rate-limit"),
            ("Preparing to download ...", nil, "pmc-pow-challenge"),
            ("Preparing your download\nPlease check your downloads folder shortly", nil, "sciencedirect-download-challenge"),
            ("<script>window.cra_js_challenge = 1</script>", nil, "sciencedirect-download-challenge"),
            ("<html></html>", 403, "http-403"),
            ("", 429, "http-429"),
            ("Forbidden", 403, "http-403"),
            ("Access Denied", 403, "access-denied"),
        ]
        for (text, status, label) in cases {
            XCTAssertEqual(BotSignals.classify(text, status: status), BotSignals.Hit(label: label, response: .pauseBatch), text)
        }
    }

    /// 同一頁同時命中兩種時，整批暫停優先——不論兩者在清單裡的順序。
    func testAPauseSignalWinsWhereverItIsInTheList() {
        XCTAssertEqual(BotSignals.classify("captcha\nToo many requests")?.response, .pauseBatch, "rate-limit 在 captcha 之後")
        XCTAssertEqual(BotSignals.classify("captcha\nToo many requests")?.label, "rate-limit")
        XCTAssertEqual(BotSignals.classify("Access to this page has been denied. Press & Hold to confirm")?.label, "perimeterx-block")
        XCTAssertEqual(BotSignals.classify("captcha-delivery.com")?.label, "datadome-block", "DataDome 的網址含 captcha，仍是封鎖頁")
        XCTAssertEqual(BotSignals.detect("captcha\nToo many requests"), "rate-limit", "detect 用同一套優先順序")
    }

    /// 挑戰頁常以 403 回應：文字是等人驗證的訊號時，狀態碼不把它改成整批暫停（否則使用者列的 Cloudflare「Just a moment」永遠走不到等人驗證）。
    func testAVerificationPageServedWithA403StillWaitsForTheHuman() {
        XCTAssertEqual(BotSignals.classify("<title>Just a moment...</title>", status: 403), BotSignals.Hit(label: "cloudflare-challenge", response: .humanVerification))
        XCTAssertEqual(BotSignals.classify("Are you a robot? Please complete the captcha", status: 403)?.response, .humanVerification)
        XCTAssertEqual(BotSignals.classify("You are being rate limited. Just a moment...", status: 429)?.label, "rate-limit", "文字裡的整批暫停標籤仍然優先")
    }

    /// 使用者 2026-10-02：HTTP 429 一律整批暫停，不論頁面文字。403 的驗證頁文字仍可優先（Cloudflare 的挑戰頁常以 403 回應）。
    func testA429IsAlwaysPauseWhateverTheTextSays() {
        for text in ["Please complete the captcha challenge", "Too many... Protected by reCAPTCHA", "Are you a robot?", "<title>Just a moment...</title>", ""] {
            XCTAssertEqual(BotSignals.classify(text, status: 429)?.response, .pauseBatch, text)
        }
        XCTAssertEqual(BotSignals.classify("Please complete the captcha challenge", status: 429)?.label, "http-429")
        XCTAssertEqual(BotSignals.classify("Please complete the captcha challenge", status: 403)?.response, .humanVerification, "403 的例外仍在")
    }

    /// Cloudflare 的經典挑戰頁也寫「Checking your browser before accessing…」：與 `cloudflare-challenge` 同頁時不被 PMC 的通用字樣吃成整批暫停；
    /// PMC 專屬的「preparing to download」同頁時仍是整批暫停。
    func testACloudflareChallengePageIsNotSwallowedByThePMCGenericWording() {
        XCTAssertEqual(BotSignals.classify("Just a moment...\nChecking your browser before accessing pub.example."),
                       BotSignals.Hit(label: "cloudflare-challenge", response: .humanVerification))
        XCTAssertEqual(BotSignals.classify("Checking your browser before accessing pub.example.")?.label, "pmc-pow-challenge", "沒有 Cloudflare 標記：仍是 PMC 那一條")
        XCTAssertEqual(BotSignals.classify("Just a moment...\nPreparing to download ...")?.response, .pauseBatch)
    }

    /// 等人驗證能成立的第二種主機：已知的驗證服務，封閉清單。
    func testKnownVerificationServices() {
        for url in ["https://challenges.cloudflare.com/cdn-cgi/challenge-platform/x", "https://hcaptcha.com/x", "https://newassets.hcaptcha.com/captcha/v1/x",
                    "https://www.recaptcha.net/recaptcha/api2/x", "https://www.google.com/recaptcha/api2/anchor"] {
            XCTAssertTrue(BotSignals.isKnownVerificationService(url: url), url)
        }
        for url in ["https://evil.example/captcha", "https://www.google.com/search?q=recaptcha", "http://challenges.cloudflare.com/x", "https://challenges.cloudflare.com.evil.example/x",
                    "https://notcloudflare.com/x", "https://hcaptcha.com.evil.example/", "https://pub.example/captcha/"] {
            XCTAssertFalse(BotSignals.isKnownVerificationService(url: url), url)
        }
    }

    /// 分頁離開文章站之後的第二道檢查：登入／驗證頁的長相（網址的主機與路徑、標題）；簽章網址的查詢字串不算。
    func testTheGateLookOfAPage() {
        XCTAssertEqual(BotSignals.gateLook(url: "https://sso.other.example/login", title: "Sign in"), "login")
        XCTAssertEqual(BotSignals.gateLook(url: "https://idp.uni.example/idp/profile/SAML2/Redirect/SSO", title: "x"), "login")
        XCTAssertEqual(BotSignals.gateLook(url: "https://files.example/a", title: "Please log in to continue"), "login")
        XCTAssertEqual(BotSignals.gateLook(url: "https://verify.other.example/c", title: "Article"), "verification")
        XCTAssertEqual(BotSignals.gateLook(url: "https://files.example/a", title: "Verify your identity"), "verification")
        XCTAssertNil(BotSignals.gateLook(url: "https://files.cdn.example/signed/x.pdf?X-Amz-Signature=auth&challenge=1&login=1", title: "x.pdf"), "查詢字串不算")
        XCTAssertNil(BotSignals.gateLook(url: "https://pdf.sciencedirectassets.com/1-s2.0/main.pdf", title: "main.pdf"))
        XCTAssertNil(BotSignals.gateLook(url: "https://hub.other.example/retrieve/x", title: "Retrieving"))
    }

    func testTheVerificationSetIsExactlyTheFourDecided() {
        XCTAssertEqual(BotSignals.humanVerificationLabels, ["captcha", "human-check", "cloudflare-challenge", "perimeterx-press-and-hold"])
        let labels = Set(BotSignals.signals.map(\.label))
        XCTAssertTrue(BotSignals.humanVerificationLabels.isSubset(of: labels), "每個等人驗證的標籤都有樣式")
    }

    func testAnOrdinaryArticleStillPasses() {
        XCTAssertNil(BotSignals.classify("Preparing your manuscript for download is described in the author guide"))
        XCTAssertNil(BotSignals.classify("An ordinary article about panel models"))
    }
}

final class FulltextAttemptLedgerTests: XCTestCase {
    private var root: URL!
    private var ledger: FulltextAttemptLedger!
    /// 2026-10-01 10:00 +08:00
    private let now = Date(timeIntervalSince1970: 1_790_820_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString)")
        ledger = FulltextAttemptLedger(path: root.appendingPathComponent("a/b/attempts.jsonl").path)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testTimestampsCarryTheTaipeiOffset() {
        XCTAssertEqual(FulltextAttemptLedger.timestamp(now), "2026-10-01T10:00:00+08:00")
        XCTAssertEqual(FulltextAttemptLedger.timestamp(Date(timeIntervalSince1970: 1_790_784_000)), "2026-10-01T00:00:00+08:00")
        XCTAssertEqual(FulltextAttemptLedger.taipeiDay(Date(timeIntervalSince1970: 1_790_783_999)), "2026-09-30", "臺北午夜前一秒")
        XCTAssertEqual(FulltextAttemptLedger.taipeiDay(Date(timeIntervalSince1970: 1_790_784_000)), "2026-10-01")
    }

    func testAppendCreatesAPrivateFileAndCounts() throws {
        XCTAssertEqual(try ledger.count(site: "pub.example", on: now), 0, "沒有檔＝空")
        try ledger.append(site: "pub.example", landing: "https://doi.org/10.1/x", at: now)
        try ledger.append(site: "pub.example", landing: "https://doi.org/10.1/y", at: now)
        try ledger.append(site: "other.example", landing: "https://doi.org/10.1/z", at: now)
        XCTAssertEqual(try ledger.count(site: "pub.example", on: now), 2)
        XCTAssertEqual(try ledger.count(site: "other.example", on: now), 1)
        let text = try String(contentsOfFile: ledger.path, encoding: .utf8)
        XCTAssertEqual(text.split(separator: "\n").first, #"{"at":"2026-10-01T10:00:00+08:00","landing":"https://doi.org/10.1/x","site":"pub.example"}"#)
        let attrs = try FileManager.default.attributesOfItem(atPath: ledger.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let dirAttrs = try FileManager.default.attributesOfItem(atPath: (ledger.path as NSString).deletingLastPathComponent)
        XCTAssertEqual((dirAttrs[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testATimeWithoutAnOffsetIsRejected() {
        XCTAssertNil(FulltextAttemptLedger.parse(#"{"at":"2026-10-01T10:00:00","site":"x"}"#))
        XCTAssertNil(FulltextAttemptLedger.parse(#"{"at":"2026-10-01","site":"x"}"#))
        XCTAssertNotNil(FulltextAttemptLedger.parse(#"{"at":"2026-10-01T02:00:00Z","site":"x"}"#))
        XCTAssertNotNil(FulltextAttemptLedger.parse(#"{"at":"2026-10-01T10:00:00+08:00","site":"x"}"#))
    }

    func testAppendRefusesASymlink() throws {
        try FileManager.default.createDirectory(atPath: (ledger.path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let victim = root.appendingPathComponent("victim.txt")
        try Data("victim".utf8).write(to: victim)
        try FileManager.default.createSymbolicLink(atPath: ledger.path, withDestinationPath: victim.path)
        XCTAssertThrowsError(try ledger.append(site: "pub.example", landing: "x", at: now))
        XCTAssertEqual(try String(contentsOf: victim, encoding: .utf8), "victim")
    }

    // MARK: #613 修正輪：檔尾換行、查數與記錄是一步、站名大小寫、CRLF

    /// 手改過帳本、編輯器沒補檔尾換行：新的一筆不得黏在舊的一筆後面（黏在一起下一次 `load` 整個拒絕，而訊息叫人「刪掉那一行」會刪掉兩筆）。
    func testAppendAfterAFinalRecordWithoutANewlineKeepsBothRecordsOnTheirOwnLines() throws {
        try FileManager.default.createDirectory(atPath: (ledger.path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(#"{"at":"2026-10-01T09:00:00+08:00","landing":"x","site":"pub.example"}"#.utf8).write(to: URL(fileURLWithPath: ledger.path))   // 沒有檔尾換行
        try ledger.append(site: "pub.example", landing: "y", at: now)
        let text = try String(contentsOfFile: ledger.path, encoding: .utf8)
        XCTAssertEqual(text.split(separator: "\n").count, 2, text)
        XCTAssertTrue(text.hasSuffix("\n"))
        XCTAssertEqual(try ledger.load().count, 2, "重讀得回來")
        XCTAssertEqual(try ledger.count(site: "pub.example", on: now), 2)
    }

    func testReserveAlsoRepairsAMissingFinalNewline() throws {
        try FileManager.default.createDirectory(atPath: (ledger.path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(#"{"at":"2026-10-01T09:00:00+08:00","landing":"x","site":"pub.example"}"#.utf8).write(to: URL(fileURLWithPath: ledger.path))
        XCTAssertEqual(try ledger.reserve(site: "pub.example", landing: "y", at: now), .granted(used: 2))
        XCTAssertEqual(try ledger.load().count, 2)
    }

    func testReserveGrantsUpToTheCapAndThenWritesNothing() throws {
        for i in 1...FulltextAttemptLedger.dailyCap {
            XCTAssertEqual(try ledger.reserve(site: "pub.example", landing: "x", at: now), .granted(used: i))
        }
        let before = try Data(contentsOf: URL(fileURLWithPath: ledger.path))
        XCTAssertEqual(try ledger.reserve(site: "pub.example", landing: "x", at: now), .capReached(used: FulltextAttemptLedger.dailyCap))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: ledger.path)), before, "到上限時什麼都不寫")
        XCTAssertEqual(try ledger.reserve(site: "other.example", landing: "x", at: now), .granted(used: 1), "別的站不算")
    }

    /// 兩條執行緒（各自開自己的檔案描述，`flock` 對它們就是兩個行程）搶最後一格：只有一個拿到。`afterRead` 把「讀完、決定要不要記」之間的
    /// 視窗拉寬——沒有鎖的實作兩邊都讀到 9、各自記成第 10 次。
    func testTwoReservationsRacingForTheLastSlotGrantExactlyOne() throws {
        for _ in 1..<FulltextAttemptLedger.dailyCap { try ledger.append(site: "pub.example", landing: "x", at: now) }
        let results = ResultBox()
        let group = DispatchGroup()
        for _ in 0..<2 {
            group.enter()
            DispatchQueue.global().async {
                var racer = FulltextAttemptLedger(path: self.ledger.path)
                racer.afterRead = { Thread.sleep(forTimeInterval: 0.3) }
                let r = try? racer.reserve(site: "pub.example", landing: "x", at: self.now)
                results.add(r)
                group.leave()
            }
        }
        group.wait()
        let all = results.all
        XCTAssertEqual(all.filter { if case .granted = $0 { return true } else { return false } }.count, 1, "\(all)")
        XCTAssertEqual(all.filter { if case .capReached = $0 { return true } else { return false } }.count, 1, "\(all)")
        XCTAssertEqual(try ledger.count(site: "pub.example", on: now), FulltextAttemptLedger.dailyCap, "帳本剛好 10 筆，不是 11")
    }

    final class ResultBox {
        private let lock = NSLock()
        private var items: [FulltextAttemptLedger.Reservation?] = []
        func add(_ r: FulltextAttemptLedger.Reservation?) { lock.lock(); items.append(r); lock.unlock() }
        var all: [FulltextAttemptLedger.Reservation?] { lock.lock(); defer { lock.unlock() }; return items }
    }

    /// 手改的帳本把站名寫成大寫：寫入端一律小寫，讀回來也要算進同一個站（少算正是上限要防的方向）。
    func testAMisCasedSiteInAHandEditedLedgerStillCounts() throws {
        try FileManager.default.createDirectory(atPath: (ledger.path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let line = #"{"at":"2026-10-01T09:00:00+08:00","landing":"x","site":"PUB.example"}"# + "\n"
        try Data(String(repeating: line, count: 10).utf8).write(to: URL(fileURLWithPath: ledger.path))
        XCTAssertEqual(try ledger.count(site: "pub.example", on: now), 10)
        XCTAssertEqual(try ledger.reserve(site: "pub.example", landing: "x", at: now), .capReached(used: 10))
    }

    /// Swift 的 `"\r\n"` 是一個 `Character`：切 `"\n"` 的實作對 CRLF 的檔完全不切行，整檔被當成「第 1 行讀不懂」。
    func testACRLFLedgerIsRead() throws {
        try FileManager.default.createDirectory(atPath: (ledger.path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let line = #"{"at":"2026-10-01T09:00:00+08:00","landing":"x","site":"pub.example"}"#
        try Data((line + "\r\n" + line + "\r\n").utf8).write(to: URL(fileURLWithPath: ledger.path))
        XCTAssertEqual(try ledger.load().count, 2)
        XCTAssertEqual(try ledger.reserve(site: "pub.example", landing: "y", at: now), .granted(used: 3))
    }

    /// 預設位置在 store 之外：`~/.akashic` 是 `main` store 的 root，它的 `.gitignore` 不排除 `state/` 之類的新目錄。
    func testTheDefaultPathIsOutsideTheStore() {
        let path = FulltextAttemptLedger.defaultPath(environment: ["HOME": "/Users/someone", "AKASHIC_HOME": "/Users/someone/.akashic"])
        XCTAssertEqual(path, "/Users/someone/Library/Application Support/akashic/fulltext-attempts.jsonl")
        XCTAssertFalse(path.hasPrefix("/Users/someone/.akashic"))
    }
}

/// 注入頁面的每一段 JS 都要能當**運算式**解析：`safari-browser js` 先把程式碼包成 `'' + (\n<code>\n)` 試一次，失敗才退回函式本體
/// （`JSWrapper.expressionWrapper`）——寫成 `return …` 的敘述，第一次嘗試在頁面裡就是一個 SyntaxError。網站的分析工具看得到頁面的
/// JS 錯誤（2026-09-28 NVA 的 Matomo 記錄了 agent 的 SyntaxError）。這裡用 JavaScriptCore 照那個包法解析（只定義函式、不呼叫）。
final class FulltextJavaScriptTests: XCTestCase {
    /// 回 nil＝解析成功；否則是 JavaScriptCore 的錯誤訊息。
    static func expressionParseError(_ code: String) -> String? {
        guard let context = JSContext() else { return "no JSContext" }
        var error: String?
        context.exceptionHandler = { _, exception in error = exception?.toString() ?? "exception" }
        _ = context.evaluateScript("(function(){ try { var r = '' + (\n\(code)\n); } catch(e) {} })")
        return error
    }

    func testEveryInjectedSnippetParsesAsAnExpression() {
        XCTAssertEqual(FulltextFetch.injectedExpressions.count, 5)
        for code in FulltextFetch.injectedExpressions {
            XCTAssertNil(Self.expressionParseError(code), code)
        }
    }

    /// 負對照：解析器真的會抓到敘述形——否則上面那支永遠綠。
    func testTheParserRejectsTheStatementForm() {
        XCTAssertNotNil(Self.expressionParseError("return document.title"))
        XCTAssertNotNil(Self.expressionParseError("const f = 1; if (f) return 'x';"))
        XCTAssertNotNil(Self.expressionParseError("(function () { return 1; )()"))
    }

    /// 能解析之外，也要**跑得出期待的形狀**：在一個假的 document 上執行（JavaScriptCore 沒有 DOM）。
    func testTheSnippetsEvaluateOnAStubDocument() throws {
        let context = try XCTUnwrap(JSContext())
        var thrown: String?
        context.exceptionHandler = { _, e in thrown = e?.toString() }
        context.evaluateScript("""
        var performance = { getEntriesByType: function (t) { return [{ responseStatus: 403 }]; } };
        var document = { readyState: 'complete', contentType: 'application/pdf', title: 'T', baseURI: 'https://pub.example/a',
          body: { innerText: 'Body text' },
          querySelector: function (s) {
            if (s === 'meta[name=citation_pdf_url]') { return { content: '/doi/pdf/10.1/x' }; }
            return null;
          } };
        function URL(u, base) { this.href = u.indexOf('https://') === 0 ? u : 'https://pub.example' + u; }
        """)
        func evaluate(_ code: String) -> String? { context.evaluateScript("'' + (\n\(code)\n)")?.toString() }
        XCTAssertEqual(evaluate(FulltextFetch.readyStateJS), "complete")
        XCTAssertEqual(evaluate(FulltextFetch.pageTextJS), "403\nT\nBody text")
        XCTAssertEqual(evaluate(FulltextFetch.hasLinkJS), "true")
        XCTAssertEqual(evaluate(FulltextFetch.linkJS), "GET https://pub.example/doi/pdf/10.1/x")
        XCTAssertEqual(evaluate(FulltextFetch.shownJS), "application/pdf\ncomplete")
        XCTAssertNil(thrown)
        // 沒有 navigation timing 的瀏覽器：狀態碼那一行是空的，不拋錯
        context.evaluateScript("performance = { getEntriesByType: function (t) { return []; } };")
        XCTAssertEqual(evaluate(FulltextFetch.pageTextJS), "\nT\nBody text")
        context.evaluateScript("performance = undefined;")
        XCTAssertEqual(evaluate(FulltextFetch.pageTextJS), "\nT\nBody text")
        XCTAssertNil(thrown)
    }
}
