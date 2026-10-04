import XCTest
@testable import AkashicSkillTools
@testable import AkashicStoreIO

/// #613 R3：R2 修正輪的 verify（b31 W4）提出的六則 MEDIUM 與幾則 LOW。與 `FulltextFetchPathTests` 同一個記憶體內的假瀏覽器——
/// 不碰 Safari、不連網。
///
/// 判準仍是使用者 2026-10-02 的兩則裁決（#613 Decision comment）：別的主機上顯示 PDF → 交給人；其他沒有標記的頁面 → 這一筆交給人、
/// 批次繼續；登入頁、驗證頁、封鎖頁維持整批暫停。
final class FulltextR3Tests: XCTestCase {
    typealias Scenario = FulltextFetchPathTests.Scenario
    typealias FakeBrowser = FulltextFetchPathTests.FakeBrowser

    private var root: URL!
    private var ledgerPath: String { root.appendingPathComponent("state/\(UUID().uuidString).jsonl").path }
    private var lastLedger = ""
    private var stdout: [String] = []
    private var stderr: [String] = []
    private var browser: FakeBrowser!
    static let now = FulltextFetchPathTests.now
    static let landing = FulltextFetchPathTests.landing

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fetch-r3-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// 時鐘與睡眠的接縫（一般的測試用固定時間、不睡）。包成一個型別，尾隨閉包才不會被對到它。
    struct Clock {
        var now: () -> Date
        var sleep: (Double) -> Void
    }

    @discardableResult
    private func run(_ scenario: Scenario, clock: Clock? = nil,
                     hook: ((_ args: [String], _ fake: FakeBrowser) -> SafariRun?)? = nil) -> Int32 {
        browser = FakeBrowser(scenario)
        browser.hook = hook
        stdout = []; stderr = []
        lastLedger = ledgerPath
        let fetcher = FulltextFetch(browser: browser, sleeper: clock?.sleep ?? { _ in }, now: clock?.now ?? { Self.now },
                                    out: { self.stdout.append($0) }, err: { self.stderr.append($0) })
        return fetcher.run(.init(window: 5, landing: Self.landing, ledger: lastLedger))
    }

    private func runResume(_ s: Scenario, tab: (String, String), origin: String = "https://pub.example", stage: FulltextFetch.ResumeStage) -> Int32 {
        browser = FakeBrowser(s)
        browser.tabs.append(tab)
        stdout = []; stderr = []
        let fetcher = FulltextFetch(browser: browser, sleeper: { _ in }, now: { Self.now }, out: { self.stdout.append($0) }, err: { self.stderr.append($0) })
        return fetcher.run(.init(window: 5, landing: Self.landing, ledger: ledgerPath, resumeTab: 2, resumeOrigin: origin, resumeStage: stage))
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
        XCTAssertEqual(code, 7, "\(note)\n\(errText)", file: file, line: line)
        XCTAssertTrue(outText.contains("handover: \(reason.rawValue) window 5 tab 2"), "\(note)\n\(outText)", file: file, line: line)
        XCTAssertFalse(errText.contains("STOP THE WHOLE RUN"), "\(note)\n\(errText)", file: file, line: line)
    }

    // MARK: 第 0 則：分類用的網址、標題與頁面文字是同一頁的

    /// 別的主機上的中繼頁落定了，讀頁面文字的那一下分頁換到登入頁：先前以舊網址、舊標題配新文字判，三樣都沒命中就交給人（7 `left-site`）。
    /// 讀完之後分頁的網址變了＝這一份不是同一頁的，回去等；新的一頁落定之後判它——登入頁，整批暫停。
    func testAPageChangeWhileReadingThePageTextIsNotMixedIntoOneJudgement() {
        var s = Scenario(); s.afterNavURL = "https://hub.other.example/retrieve/x"; s.afterNavTitle = "Retrieving"; s.afterNavContentType = "text/html"
        var swapped = false
        let code = run(s) { args, fake in
            guard args[0] == "js", fake.navigated, args.last!.contains("innerText.slice"), !swapped else { return nil }
            swapped = true
            fake.tabs[1] = ("https://hub.other.example/login?next=SECRETNEXT", "Please wait")
            return SafariRun(status: 0, stdout: "\nUsername\nPassword\n")
        }
        assertStop(code)
        XCTAssertTrue(errText.contains("(login page)"), errText)
        XCTAssertFalse(errText.contains("SECRETNEXT"), errText)
    }

    /// 讀標題與網址那一下之後、讀頁面文字之前，標題換了（同一個網址）：也不是同一份快照，回去等。換回穩定的那一頁之後照常判。
    func testATitleThatChangesUnderTheSnapshotIsReadAgain() {
        var s = Scenario(); s.afterNavURL = "https://hub.other.example/retrieve/x"; s.afterNavTitle = "Retrieving"; s.afterNavContentType = "text/html"
        var reads = 0
        let code = run(s) { args, fake in
            guard args[0] == "js", fake.navigated, args.last!.contains("innerText.slice") else { return nil }
            reads += 1
            if reads == 1 { fake.tabs[1].title = "Sign in" }   // 讀文字的這一下，標題變成登入頁的
            return nil
        }
        assertStop(code)
        XCTAssertTrue(errText.contains("(login page)"), errText)
        XCTAssertGreaterThanOrEqual(reads, 2, "第一份快照不用，第二份才判")
    }

    // MARK: 第 2 則（與 LOW 13）：落地頁網址是登入頁的長相，先於頁面文字的 CAPTCHA 字樣

    /// SSO 登入頁把 DOI 帶在查詢字串裡、頁面寫著 CAPTCHA：登入頁維持整批暫停（使用者 2026-10-02），不降成可以接著走的 8。
    func testALoginLookingLandingThatMentionsACaptchaStillPausesTheBatch() {
        var s = Scenario(); s.landingFinal = "https://sso.uni.example/login?service=https://doi.org/10.1/x"; s.tabTitle = "University Login"
        s.pageText = "Sign in. Please complete the CAPTCHA below."
        assertStop(run(s))
        XCTAssertTrue(errText.contains("(login page)"), errText)
        XCTAssertFalse(errText.contains("WAITING FOR HUMAN VERIFICATION"), errText)
    }

    /// 驗證頁的長相（路徑 `/captcha/`）仍排在訊號之後：文章站自己的 CAPTCHA 頁（Optica 2026-09-28 的形狀）是等人驗證。
    func testAVerificationLookingLandingWithACaptchaStillWaitsForTheHuman() {
        var s = Scenario(); s.landingFinal = "https://opg.optica.example/captcha/?url=x"; s.tabTitle = "Captcha"
        s.pageText = "Please complete the captcha below"
        XCTAssertEqual(run(s), 8, errText)
        XCTAssertTrue(outText.contains("resume: --resume-tab 2 --resume-origin https://opg.optica.example"), outText)
    }

    /// 導航之前的接續（`article`）同一道閘：分頁停在登入頁的長相上 → 整批暫停，不讀連結、不導航、不關使用者的登入分頁。
    func testResumingBeforeNavigationOnALoginLookingPagePausesTheBatch() {
        var s = Scenario(); s.pageText = "Sign in. Please complete the CAPTCHA below."
        let code = runResume(s, tab: ("https://sso.uni.example/login?service=https://doi.org/10.1/x", "University Login"),
                             origin: "https://sso.uni.example", stage: .article)
        assertStop(code)
        XCTAssertTrue(errText.contains("(login page)"), errText)
        XCTAssertFalse(browser.calls.contains { $0.hasPrefix("navigate") || $0.hasPrefix("close") }, "\(browser.calls)")
        XCTAssertEqual(browser.injected, [], "網址已經是登入頁的長相：不往那個分頁送任何 JS")
    }

    // MARK: 第 3、4 則：讀不到的分頁可能是 PDF——不因標題或網址的字樣整批暫停

    /// Safari 的 PDF 檢視器可能不跑頁面 JS。別的主機上的分頁讀不到時，標題常是文章標題、網址常有 `auth`、`validate` 之類的段：
    /// 這些字樣不整批暫停，交給人（`unverifiable`），訊息說讀不到、沒驗證過。標題與網址取自審查者的實測（先前全是結束碼 6）。
    func testAnUnreadableTabOnAnotherHostIsHandedOverWhateverItsTitleOrPathSays() {
        let titles = ["Verification of measurement invariance", "Verify the factor structure", "Login behaviour in online games",
                      "Sign in to the reader", "A Survey of CAPTCHA Design", "Reducing CAPTCHA friction: a usability study",
                      "Analysis of unusual traffic patterns", "Research design in experimental psychology"]
        for title in titles {
            var s = Scenario(); s.afterNavURL = "https://pdf.sciencedirectassets.com/271/1-s2.0-S002-main.pdf?X-Amz-Signature=SECRETSIG"
            s.afterNavTitle = title; s.afterNavJSFails = true
            assertHandover(run(s), .unverifiable, title)
            XCTAssertTrue(errText.contains("could not read the tab"), errText)
            XCTAssertTrue(errText.contains("nothing on it was checked"), errText)
            XCTAssertFalse((outText + errText).contains("SECRETSIG"), title)
        }
        for url in ["https://cdn.example.org/auth/12345.pdf", "https://cdn.example.org/validate/x.pdf", "https://sso-files.example.org/x.pdf"] {
            var s = Scenario(); s.afterNavURL = url; s.afterNavTitle = "main.pdf"; s.afterNavJSFails = true
            assertHandover(run(s), .unverifiable, url)
        }
    }

    /// 讀不到的分頁仍不是乾淨的：網址在已知的驗證服務上、或標題與網址帶著驗證服務自己的標記（封閉清單 `BotSignals.serviceMarkerLabels`），
    /// 照訊號處理——已知驗證服務上的人類檢查等人驗證，其他主機上的服務標記整批暫停。
    func testAnUnreadableTabStillStopsOnAVerificationServiceMarker() {
        var cloudflareTitle = Scenario(); cloudflareTitle.afterNavURL = "https://cdn.example.org/x"; cloudflareTitle.afterNavTitle = "Just a moment..."
        cloudflareTitle.afterNavJSFails = true
        assertStop(run(cloudflareTitle))
        XCTAssertTrue(errText.contains("cloudflare-challenge"), errText)

        var known = Scenario(); known.afterNavURL = "https://challenges.cloudflare.com/cdn-cgi/challenge-platform/h/b/x"; known.afterNavTitle = "Just a moment..."
        known.afterNavJSFails = true
        XCTAssertEqual(run(known), 8, errText)
        XCTAssertTrue(outText.contains("--resume-stage followed"), outText)

        // 已知驗證服務上、標題與網址沒有任何標籤：那是驗證服務的頁面而讀不到——整批暫停，不交給人（先前是 7 `unverifiable`）
        var knownNeutral = Scenario(); knownNeutral.afterNavURL = "https://challenges.cloudflare.com/x"; knownNeutral.afterNavTitle = "x"
        knownNeutral.afterNavJSFails = true
        assertStop(run(knownNeutral))
        XCTAssertTrue(errText.contains("known verification service"), errText)

        var datadome = Scenario(); datadome.afterNavURL = "https://geo.captcha-delivery.com/captcha/?initialCid=x"; datadome.afterNavTitle = "x"
        datadome.afterNavJSFails = true
        assertStop(run(datadome))
        XCTAssertTrue(errText.contains("datadome-block"), errText)
    }

    func testTheServiceMarkersAreAClosedListOfVendorLabels() {
        XCTAssertEqual(BotSignals.serviceMarkerLabels, ["akamai-block", "perimeterx-press-and-hold", "perimeterx-block", "datadome-block",
                                                        "cloudflare-challenge", "sciencedirect-download-challenge"])
        XCTAssertTrue(BotSignals.serviceMarkerLabels.isSubset(of: Set(BotSignals.signals.map(\.label))))
        for article in ["A Survey of CAPTCHA Design", "Verify you are human: a study", "Analysis of unusual traffic patterns",
                        "Access denied: refusal in therapy", "A proof-of-work consensus", "Rate limited learning"] {
            XCTAssertNil(BotSignals.serviceMarker(article), article)
        }
        XCTAssertEqual(BotSignals.serviceMarker("Just a moment...")?.response, .humanVerification)
        XCTAssertEqual(BotSignals.serviceMarker("Pardon Our Interruption")?.response, .pauseBatch)
        XCTAssertEqual(BotSignals.serviceMarker("Access to this page has been denied. Press & Hold to confirm")?.label, "perimeterx-block", "整批暫停優先")
    }

    // MARK: 第 5 則（與 LOW 12）：讀不到要連續、在同一個網址、而且那裡從沒讀到過一般網頁

    /// 讀不到之間夾著「還在載入」的回答：那是一個一般網頁（讀得到 `text/html`），不是 PDF 檢視器。先前讀不到是累積計數，三次散落的失敗
    /// 就把沒載完的頁面交給人（7、批次繼續）；現在等它落定，一直沒落定是卡住（6）。
    func testScatteredUnreadableAnswersOnALoadingPageAreAStallNotAHandover() {
        var s = Scenario(); s.afterNavURL = "https://hub.other.example/retrieve/x"; s.afterNavTitle = "Retrieving"; s.afterNavContentType = "text/html"
        var polls = 0
        let code = run(s) { args, fake in
            guard args[0] == "js", fake.navigated, args.last!.contains("document.contentType") else { return nil }
            polls += 1
            return polls % 2 == 1 ? SafariRun(status: 1) : SafariRun(status: 0, stdout: "text/html\nloading\n")
        }
        assertStop(code)
        XCTAssertTrue(errText.contains("did not settle"), errText)
    }

    /// 讀到過一次「還在載入」，之後一直讀不到：那個網址是一般網頁，讀不到不等於可能是 PDF——等到卡住。
    func testAPageThatAnsweredOnceAndThenWentSilentIsNotTreatedAsAPDFViewer() {
        var s = Scenario(); s.afterNavURL = "https://hub.other.example/retrieve/x"; s.afterNavTitle = "Retrieving"; s.afterNavContentType = "text/html"
        var polls = 0
        let code = run(s) { args, fake in
            guard args[0] == "js", fake.navigated, args.last!.contains("document.contentType") else { return nil }
            polls += 1
            return polls == 1 ? SafariRun(status: 0, stdout: "text/html\nloading\n") : SafariRun(status: 1)
        }
        assertStop(code)
    }

    /// 換了網址就重新數：舊網址上的讀不到不算到新網址上。新網址上連三次讀不到、從沒讀到過一般網頁 → 交給人（`unverifiable`）。
    func testUnreadableAnswersOnTheOldURLDoNotCountForTheNewOne() {
        var s = Scenario(); s.afterNavURL = "https://hop.example/redirecting"; s.afterNavTitle = "Redirecting..."; s.afterNavContentType = "text/html"
        var polls = 0
        let code = run(s) { args, fake in
            guard args[0] == "js", fake.navigated, args.last!.contains("document.contentType") else { return nil }
            polls += 1
            if polls == 3 { fake.tabs[1] = ("https://files.other.example/x.pdf", "x.pdf") }
            return SafariRun(status: 1)
        }
        assertHandover(code, .unverifiable)
        XCTAssertTrue(outText.contains("https://files.other.example/x.pdf"), outText)
        XCTAssertGreaterThanOrEqual(polls, 5, "新網址自己要連三次")
    }

    // MARK: LOW 7：60 秒是時鐘，不是輪詢次數

    /// 每一次輪詢除了睡 2 秒，還有對 safari-browser 的呼叫（真的 `documents --json` 不快）。先前 30 次輪詢的上限在每次呼叫慢的時候
    /// 等上一百多秒；現在以時鐘計，60 秒到了就是卡住。
    func testTheOffSiteWaitIsBoundedByTheClock() {
        var s = Scenario(); s.afterNavURL = "https://hub.other.example/retrieve/x"; s.afterNavTitle = "Retrieving"; s.afterNavContentType = "text/html"
        var t = 0.0
        var polls = 0
        let start = Self.now
        let code = run(s, clock: Clock(now: { t += 1.5; return start.addingTimeInterval(t) }, sleep: { t += $0 })) { args, fake in
            guard args[0] == "js", fake.navigated, args.last!.contains("document.contentType") else { return nil }
            polls += 1
            return SafariRun(status: 0, stdout: polls < 25 ? "text/html\nloading\n" : "text/html\ncomplete\n")
        }
        assertStop(code)
        XCTAssertTrue(errText.contains("did not settle"), errText)
        XCTAssertLessThan(polls, 25, "時鐘到了 60 秒就不再輪詢")
    }

    // MARK: LOW 6、15、16：帳密不經 origin 外洩

    func testCredentialsInTheHostNeverReachTheMessagesOrTheLedger() throws {
        var blocked = Scenario(); blocked.landingFinal = "https://user:SECRETPW@pub.example/doi/10.1/x"; blocked.pageText = "Access Denied"
        assertStop(run(blocked))
        XCTAssertFalse(errText.contains("SECRETPW"), errText)
        XCTAssertTrue(errText.contains("on https://pub.example"), errText)

        var normal = Scenario(); normal.landingFinal = "https://user:SECRETPW@pub.example/doi/10.1/x"
        _ = run(normal)
        XCTAssertFalse((outText + errText).contains("SECRETPW"), outText + errText)
        let ledger = (try? String(contentsOfFile: lastLedger, encoding: .utf8)) ?? ""
        XCTAssertFalse(ledger.lowercased().contains("secretpw"), ledger)
        XCTAssertTrue(ledger.contains("\"site\":\"pub.example\""), ledger)

        var offSite = Scenario(); offSite.afterNavURL = "https://user:SECRETPW@cdn.example/reader/1"; offSite.afterNavTitle = "Reader"
        offSite.afterNavContentType = "text/html"
        assertHandover(run(offSite), .leftSite)
        XCTAssertFalse((outText + errText).contains("SECRETPW"), outText + errText)
        XCTAssertTrue(errText.contains("for https://cdn.example;"), errText)
    }

    // MARK: LOW 17：路徑參數裡的 session id

    func testPlainURLDropsSessionIDsInPathParameters() {
        XCTAssertEqual(FulltextFetch.plainURL("https://cdn.example/dl/;sid=ABC123SECRET/(S(aspnetsession123))/file.pdf;PHPSESSID=zzz;jsessionid=KEEPOUT"),
                       "https://cdn.example/dl/file.pdf")
        XCTAssertEqual(FulltextFetch.plainURL("https://cdn.example/a;type=pdf/b"), "https://cdn.example/a/b")
        // SICI 式 DOI 的 `;2-0` 不是 `名=值` 的路徑參數：留著（它是文件身分的一部分）
        let sici = "https://onlinelibrary.wiley.com/doi/10.1002/(SICI)1097-4571(199806)49:8%3C693::AID-ASI4%3E3.0.CO;2-0"
        XCTAssertEqual(FulltextFetch.plainURL(sici), sici)
        XCTAssertEqual(FulltextFetch.plainURL("https://pub.example/doi/10.1016/S0022-2496(05)80001-1"), "https://pub.example/doi/10.1016/S0022-2496(05)80001-1")
    }

    // MARK: LOW 18：pdf-shown 的依據是頁面讀得到的值

    func testThePDFShownMessageSaysAPageCanClaimToBeAPDF() {
        var s = Scenario(); s.afterNavURL = "https://files.cdn.example/x.pdf"
        assertHandover(run(s), .pdfShown)
        XCTAssertTrue(errText.contains("a page can claim that"), errText)
    }

    // MARK: LOW 9：SKILL〈中止條款〉的封閉清單與程式逐字相同

    private func skillText() throws -> String {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repo.appendingPathComponent("plugin/skills/akashic-fetch-fulltext/SKILL.md"), encoding: .utf8)
    }

    /// 反引號裡的字（`a`、`b`）。
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

    /// 兩份封閉清單（SKILL 的文字、`BotSignals` 的程式）若各改各的，SKILL 說「封閉、逐字」就是假的（b31 W4 第 9、34 則：已知驗證服務那一份
    /// 已經不一樣——程式對三個主機都收子網域、另收裸 `google.com/recaptcha/`）。這裡從 SKILL 的那一段讀出清單，與程式的集合逐一比。
    func testTheSkillsClosedListsAreTheCodesLists() throws {
        let skill = try skillText()
        let gate = between(skill, "封閉清單（`BotSignals.gateLook`）：網址的主機或路徑有 ", "主機以非字母數字")
        let parts = gate.components(separatedBy: "（登入）")
        XCTAssertEqual(parts.count, 3, String(gate))
        guard parts.count == 3 else { return }
        let urlVerification = parts[1].components(separatedBy: "（驗證）")[0]
        let titleVerification = parts[2].components(separatedBy: "（驗證）")[0]
        XCTAssertEqual(Set(ticks(Substring(parts[0]))), BotSignals.loginTokens)
        XCTAssertEqual(Set(ticks(Substring(urlVerification))), BotSignals.verificationTokens)
        let normalise: (String) -> String = { BotSignals.titleWords($0).joined(separator: " ") }
        XCTAssertEqual(Set(ticks(Substring(parts[1].components(separatedBy: "或標題有").last ?? "")).map(normalise)),
                       Set(BotSignals.loginTitlePhrases.map(normalise)))
        XCTAssertEqual(Set(ticks(Substring(titleVerification)).map(normalise)), Set(BotSignals.verificationTitlePhrases.map(normalise)))

        let extensions = between(skill, "一段可以帶一個網頁副檔名（", "）")
        XCTAssertEqual(Set(ticks(extensions).map { String($0.dropFirst()) }), BotSignals.pageExtensions)

        let services = between(skill, "（`BotSignals.isKnownVerificationService`，逐字）：主機是 ", "開頭")
        let hosts = services.components(separatedBy: "或它們的子網域")
        XCTAssertEqual(hosts.count, 2, String(services))
        XCTAssertEqual(Set(ticks(Substring(hosts[0]))), Set(BotSignals.knownVerificationHosts))
        let tail = ticks(Substring(hosts.last ?? ""))
        XCTAssertEqual(Set(tail.dropLast()), Set(BotSignals.knownVerificationPathPrefixes.map(\.host)))
        XCTAssertEqual(Set([tail.last ?? ""]), Set(BotSignals.knownVerificationPathPrefixes.map(\.prefix)))
    }

    // MARK: LOW 21：`followed` 的分頁空白時，那不是我們的分頁

    func testResumingAfterNavigationOnAnEmptyTabDoesNotCallItOurs() {
        let code = runResume(Scenario(), tab: ("", ""), stage: .followed)
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("shows nothing"), errText)
        XCTAssertFalse(errText.contains("our tab"), errText)
    }
}
