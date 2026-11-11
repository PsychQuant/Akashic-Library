import XCTest
@testable import AkashicSkillTools
@testable import AkashicStoreIO

/// #777：使用者 2026-11-11 對取全文四件待裁事項的裁決（第 1、2 件改行為，第 3、4 件維持）。與 `FulltextFetchPathTests` 同一個記憶體內的
/// 假瀏覽器——不碰 Safari、不連網。規格：`openspec/specs/fulltext-gate-look`。
final class FulltextLoginLookRulingsTests: XCTestCase {
    typealias Scenario = FulltextFetchPathTests.Scenario
    typealias FakeBrowser = FulltextFetchPathTests.FakeBrowser

    private var root: URL!
    private var stdout: [String] = []
    private var stderr: [String] = []
    private var browser: FakeBrowser!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fetch-777-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private var ledger: String { root.appendingPathComponent("state/attempts.jsonl").path }
    private var errText: String { stderr.joined(separator: "\n") }
    private var outText: String { stdout.joined(separator: "\n") }

    private func run(_ scenario: Scenario) -> Int32 {
        browser = FakeBrowser(scenario)
        stdout = []; stderr = []
        let fetcher = FulltextFetch(browser: browser, sleeper: { _ in }, now: { FulltextFetchPathTests.now },
                                    out: { self.stdout.append($0) }, err: { self.stderr.append($0) })
        return fetcher.run(.init(window: 5, landing: FulltextFetchPathTests.landing, ledger: ledger))
    }

    /// 整批暫停、停的是登入長相那一支、不印 resume。
    private func assertLoginPause(_ code: Int32, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(code, 6, "\(errText)\n\(outText)", file: file, line: line)
        XCTAssertTrue(errText.contains("STOP THE WHOLE RUN"), errText, file: file, line: line)
        XCTAssertTrue(errText.contains("(login page)"), errText, file: file, line: line)
        XCTAssertFalse(errText.contains("WAITING FOR HUMAN VERIFICATION"), errText, file: file, line: line)
        XCTAssertFalse(outText.contains("resume:"), outText, file: file, line: line)
    }

    // MARK: 第 1 件：`/action/showLogin` 算登入頁（只看路徑）

    // spec-example: fulltext-gate-look / showLogin path is a login look
    func testTheAtyponShowLoginPathHasTheLookOfALoginPage() {
        for u in ["https://onlinelibrary.example/action/showLogin",
                  "https://onlinelibrary.example/action/showLogin?redirectUri=%2Fdoi%2Fx",
                  "https://pub.example/action/showlogin;jsessionid=AB",
                  "https://pub.example/showLogin.action"] {
            XCTAssertEqual(BotSignals.urlGateLook(u), "login", u)
        }
    }

    // spec-example: fulltext-gate-look / showlogin host label is not a login host
    func testAShowLoginHostLabelIsNotALoginHost() {
        XCTAssertNil(BotSignals.urlGateLook("https://showlogin.uni.example/x"))
        XCTAssertFalse(BotSignals.hostLoginLook("https://showlogin.uni.example/x"))
        // 裁決只講路徑：主機與路徑共用的兩份清單不收它
        XCTAssertFalse(BotSignals.loginTokens.contains("showlogin"))
        XCTAssertFalse(BotSignals.compoundLoginWords.contains("showlogin"))
    }

    // spec-example: fulltext-gate-look / showlogin inside a longer slug does not count
    func testShowLoginInsideALongerSlugDoesNotCount() {
        for u in ["https://pub.example/doi/how-to-showlogin-errors", "https://pub.example/showlogins", "https://pub.example/doi/10.1/showlogin.pdf"] {
            XCTAssertNil(BotSignals.urlGateLook(u), u)
        }
    }

    // spec-example: fulltext-gate-look / A CAPTCHA on the showLogin page after navigation pauses the run
    func testACaptchaOnTheShowLoginPageAfterNavigationPausesTheRun() {
        var s = Scenario(); s.afterNavURL = "https://pub.example/action/showLogin?redirectUri=%2Fdoi%2Fx"; s.afterNavTitle = "Log in"
        s.afterNavContentType = "text/html"; s.afterNavText = "Please complete the CAPTCHA below"
        assertLoginPause(run(s))
    }

    // spec-example: fulltext-gate-look / A showLogin page on another host pauses the run
    func testAShowLoginPageOnAnotherHostPausesTheRun() {
        var s = Scenario(); s.afterNavURL = "https://other.example/action/showLogin"; s.afterNavTitle = "Welcome"
        s.afterNavContentType = "text/html"; s.afterNavText = "Welcome back"
        let code = run(s)
        XCTAssertEqual(code, 6, errText)
        XCTAssertTrue(errText.contains("(login page)"), errText)
        XCTAssertFalse(outText.contains("handover: left-site"), outText)
    }

    // MARK: 第 2 件的負控：沒有驗證服務標記的讀不到分頁照舊不看路徑（使用者 2026-10-02）

    // spec-example: fulltext-gate-look / Unreadable same-site login path without a marker is handed over
    func testAnUnreadableSameSiteLoginPathWithoutAMarkerIsHandedOver() {
        var s = Scenario(); s.afterNavURL = "https://pub.example/login"; s.afterNavTitle = "Sign in"; s.afterNavJSFails = true
        XCTAssertEqual(run(s), 7, errText)
        XCTAssertTrue(outText.contains("handover: unverifiable"), outText)
    }

    // spec-example: fulltext-gate-look / Unreadable same-site PDF path with an auth segment is handed over
    func testAnUnreadableSameSitePDFPathWithAnAuthSegmentIsHandedOver() {
        var s = Scenario(); s.afterNavURL = "https://pub.example/auth/12345.pdf"; s.afterNavTitle = "A Survey of Login Behaviour"
        s.afterNavJSFails = true
        XCTAssertEqual(run(s), 7, errText)
        XCTAssertTrue(outText.contains("handover: unverifiable"), outText)
    }

    // MARK: 第 2 件：那一支只收文章站上、等人驗證的兩個標記

    /// 裁決點名的第二個標記：按住驗證（`perimeterx-press-and-hold`）。讀不到的同站分頁在登入路徑上、標題是按住驗證的頁面用語時整批暫停。
    /// Cloudflare 挑戰那一個標記的測試在 `FulltextB37Tests.testAnUnreadableSameSiteTabAtALoginPathWithAServiceMarkerPauses`。
    func testAnUnreadableSameSiteLoginPathWithAPressAndHoldMarkerPauses() {
        var s = Scenario(); s.afterNavURL = "https://pub.example/login"; s.afterNavTitle = "Press & Hold to confirm you are a human (and not a bot)"
        s.afterNavJSFails = true
        assertLoginPause(run(s))
        XCTAssertTrue(errText.contains("perimeterx-press-and-hold"), errText)
    }

    /// 別的主機上讀不到的分頁：登入路徑加上 Cloudflare 挑戰的標記，本來就整批暫停（服務標記在文章站與已知驗證服務之外）。停止的理由要照實說是
    /// 別的主機，不說成「文章站上的登入頁」——第 2 件那一支有 `sameSite` 這個條件，結束碼不靠它，訊息靠它。
    func testAnUnreadableLoginPathOnAnotherHostIsNotCalledTheArticleSite() {
        var s = Scenario(); s.afterNavURL = "https://other.example/login"; s.afterNavTitle = "Just a moment..."; s.afterNavJSFails = true
        XCTAssertEqual(run(s), 6, errText)
        XCTAssertTrue(errText.contains("STOP THE WHOLE RUN"), errText)
        XCTAssertTrue(errText.contains("neither the article site nor a known verification service"), errText)
        XCTAssertFalse(errText.contains("on the article site"), errText)
        XCTAssertFalse(outText.contains("resume:"), outText)
    }

    /// 整批暫停的標記（等人驗證的兩個以外的四個）在同站的登入路徑上照舊以自己的標籤停：第 2 件那一支只收等人驗證的標記（裁決的範圍），
    /// 封鎖頁的理由是「被封鎖」，不改說成登入頁。結束碼兩邊都是 6，這一支釘的是訊息。
    func testAnUnreadableSameSiteLoginPathWithABlockMarkerKeepsItsOwnReason() {
        var s = Scenario(); s.afterNavURL = "https://pub.example/login"; s.afterNavTitle = "Pardon Our Interruption"; s.afterNavJSFails = true
        XCTAssertEqual(run(s), 6, errText)
        XCTAssertTrue(errText.contains("STOP THE WHOLE RUN"), errText)
        XCTAssertTrue(errText.contains("akamai-block"), errText)
        XCTAssertFalse(errText.contains("(login page)"), errText)
        XCTAssertFalse(outText.contains("resume:"), outText)
    }

    // MARK: 契約版本

    // spec-example: fulltext-gate-look / Skill and CLI agree on contract 10
    func testTheContractVersionIsTen() throws {
        XCTAssertEqual(FulltextFetch.contractVersion, 10)
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let skill = try String(contentsOf: repo.appendingPathComponent("plugin/skills/akashic-fetch-fulltext/SKILL.md"), encoding: .utf8)
        XCTAssertTrue(skill.contains("[ \"${v#fulltext-contract }\" -ge 10 ]"), "SKILL 第 0 步要求 10")
    }

    /// SKILL〈中止條款〉的只給路徑用的登入段就是程式的那一份（對帳；同 `FulltextB37Tests.testTheSkillsCompoundListsAreTheCodesLists`）。
    func testTheSkillsPathOnlyListIsTheCodesList() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let skill = try String(contentsOf: repo.appendingPathComponent("plugin/skills/akashic-fetch-fulltext/SKILL.md"), encoding: .utf8)
        let start = "**只給路徑用的登入段**（`BotSignals.pathOnlyLoginSegments`）："
        guard let a = skill.range(of: start), let b = skill.range(of: "——", range: a.upperBound..<skill.endIndex) else {
            return XCTFail("SKILL 找不到只給路徑用的登入段")
        }
        let listed = skill[a.upperBound..<b.lowerBound].split(separator: "`", omittingEmptySubsequences: false).enumerated().filter { $0.offset % 2 == 1 }.map { String($0.element) }
        XCTAssertEqual(Set(listed), BotSignals.pathOnlyLoginSegments)
    }
}
