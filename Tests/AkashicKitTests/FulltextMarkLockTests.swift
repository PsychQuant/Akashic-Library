import XCTest
@testable import AkashicSkillTools
@testable import AkashicStoreIO

/// #768 第四版（第三輪 verify 之後，使用者 2026-11-04 的兩個裁決）：
///
/// - 記號鎖一定帶 `--profile`：safari-browser 的 `open` 不把 `--url-endswith` 當成指定了分頁（safari-browser#233），只帶它會在前景視窗
///   開新分頁，我們的分頁沒有被導航。假瀏覽器照真的 safari-browser 的判斷（`FakeBrowser.openTargetFlags`）。
/// - 記號不見就改用位置追蹤，不論何時：頁面用腳本轉到的登入、驗證頁照常分類（6／8）。
///
/// 另外：記進帳本之後的每一條失敗都印「已計次」；有別的 profile 的視窗開著就在開分頁之前停（safari-browser#351）；接續以上一次執行的
/// 記號找分頁（`--resume-mark`），`resume:` 一行帶視窗編號。
final class FulltextMarkLockTests: XCTestCase {
    typealias FakeBrowser = FulltextFetchPathTests.FakeBrowser
    typealias Scenario = FulltextFetchPathTests.Scenario

    static let mark = "akashic-0123456789abcdef"
    static let finalURL = FulltextFetchPathTests.finalURL
    static let pdfLink = FulltextFetchPathTests.pdfLink
    /// 使用者自己的分頁，與文章同一個站（只照位置接續時，這一種最容易被接手）
    static let usersSameSiteTab = "https://pub.example/doi/10.1/other"

    private var root: URL!
    private var stdout: [String] = []
    private var stderr: [String] = []
    private var browser: FakeBrowser!
    /// 每一次沒有 `--new-tab` 的 `open`（導航）的參數
    private var opens: [[String]] = []
    private var errText: String { stderr.joined(separator: "\n") }
    private var outText: String { stdout.joined(separator: "\n") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fetch-mark-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        XCTAssertFalse(browser?.calls.contains { $0.hasPrefix("close") } ?? false, "fetch 不關任何分頁：\(browser?.calls ?? [])")
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func fetch(_ s: Scenario = Scenario(), tabs: [String]? = nil, configure: (inout FulltextFetch.Options) -> Void = { _ in },
                     hook: ((_ args: [String], _ fake: FakeBrowser) -> SafariRun?)? = nil) -> Int32 {
        browser = FakeBrowser(s)
        if let tabs { browser.tabs = tabs.map { ($0, "a tab") }; browser.current = tabs.count }
        stdout = []; stderr = []; opens = []
        browser.hook = { [unowned self] args, fake in
            if args[0] == "open", !args.contains("--new-tab") { self.opens.append(args) }
            return hook?(args, fake)
        }
        var o = FulltextFetch.Options(window: 5, landing: FulltextFetchPathTests.landing, ledger: root.appendingPathComponent("ledger.jsonl").path)
        configure(&o)
        let fetcher = FulltextFetch(browser: browser, sleeper: { _ in }, now: { FulltextFetchPathTests.now },
                                    out: { self.stdout.append($0) }, err: { self.stderr.append($0) }, mark: Self.mark)
        return fetcher.run(o)
    }

    /// 多個視窗的 `documents --json` 答案：（視窗編號，profile，視窗 id，網址）。
    private static func documents(_ windows: [(number: Int, profile: String?, id: Int, urls: [String])]) -> String {
        var items: [PyJSON] = []
        for w in windows {
            for (i, url) in w.urls.enumerated() {
                items.append(PyJSON.object([("window", .int(w.number)), ("index", .int(i + 1)), ("tab_in_window", .int(i + 1)), ("url", .string(url)),
                                            ("title", .string("t")), ("profile", w.profile.map { .string($0) } ?? .null), ("is_current", .bool(i == 0)),
                                            ("blocking_dialog", PyJSON.object([("state", .string("unknown")), ("window_id", .int(w.id))]))]))
            }
        }
        return PyJSON.array(items).dumps() + "\n"
    }

    // MARK: 記號鎖帶 --profile（第三輪 verify 第 1–5 則）

    /// 第三輪的 CRITICAL：記號還在時，導航用 `open --url-endswith` 在前景視窗開了新分頁。現在帶 `--profile`，導航的是我們的分頁。
    func testWhileTheMarkLastsTheNavigationGoesToOurTabNotANewOne() {
        let code = fetch()
        XCTAssertEqual(code, 7, errText)
        XCTAssertTrue(outText.contains("handover: pdf-shown window 5 tab 2"), outText)
        XCTAssertEqual(opens.map { Array($0.dropLast()) }, [["open", "--profile", "own", "--url-endswith", "#" + Self.mark]])
        XCTAssertEqual(opens.first?.last, Self.pdfLink + "#" + Self.mark)
        XCTAssertFalse(browser.calls.contains { $0.hasPrefix("open-new-tab") || $0.hasPrefix("focus") }, "\(browser.calls)")
        XCTAssertEqual(browser.tabs.count, 2, "沒有多開分頁：\(browser.tabs)")
        XCTAssertTrue(browser.navigated)
    }

    /// 假瀏覽器本身：沒有指定分頁的 `open`（只帶 `--url-endswith`）照真的 safari-browser 開新分頁、不導航——第三輪的假瀏覽器把它當成導航，
    /// 所以 19 個 mutant 看不見那個缺陷。
    func testTheFakeOpensANewTabLikeSafariBrowserWhenOpenNamesNoTarget() {
        let fake = FakeBrowser(Scenario())
        fake.tabs = [("https://pub.example/doi/10.1/x#m", "Article")]
        XCTAssertEqual(fake.run(["open", "--url-endswith", "#m", "https://pub.example/pdf#m"]).status, 0)
        XCTAssertFalse(fake.navigated)
        XCTAssertEqual(fake.tabs.map(\.url), ["https://pub.example/doi/10.1/x#m", "https://pub.example/pdf#m"])
        let other = FakeBrowser(Scenario())
        other.tabs = [("https://pub.example/doi/10.1/x#m", "Article")]
        XCTAssertEqual(other.run(["open", "--profile", "own", "--url-endswith", "#m", "https://pub.example/pdf#m"]).status, 0)
        XCTAssertTrue(other.navigated)
        XCTAssertEqual(other.tabs.count, 1)
    }

    // MARK: 記號不見改用位置追蹤（使用者 2026-11-04；第三輪 verify 第 3、4、13 則）

    /// Elsevier 的 linkinghub 插頁帶著記號、回報 complete，之後 meta refresh 到 id.elsevier（記號丟了）再到 ScienceDirect。第三輪在插頁上
    /// 落定就把「記號消失」當成有人動了分頁（結束碼 1）；現在改用位置追蹤，照常往下判。**照常往下判的結果仍是交給人（`left-site`）**：
    /// 落定時站名取了插頁的主機，之後到了 ScienceDirect 就是「到了別的主機」。這是 #768 之前就有的行為（第四輪 verify 第 6、33 則），
    /// 不在這個 issue 修；這裡把它釘住，改了要一起改。
    func testAnInterstitialThatSettlesWithTheMarkAndThenRefreshesIsNotAFalseStop() {
        var s = Scenario(); s.landingFinal = "https://linkinghub.elsevier.example/retrieve/pii/X"
        var settled = false
        var looksAfter = 0
        let code = fetch(s, hook: { args, fake in
            if args[0] == "js", args.last!.contains("document.readyState"), !settled { settled = true }
            if args[0] == "documents", settled {
                looksAfter += 1
                if looksAfter == 1 { fake.tabs[1].url = "https://id.elsevier.example/as/authorization.oauth2?x" }
                if looksAfter == 2 { fake.tabs[1].url = "https://www.sciencedirect.example/science/article/pii/X" }
            }
            return nil
        })
        XCTAssertEqual(code, 7, errText)
        XCTAssertTrue(outText.contains("handover: left-site"), outText)
        XCTAssertFalse(errText.contains("changed while this ran"), errText)
        XCTAssertFalse(browser.calls.contains { $0.hasPrefix("open-new-tab") }, "\(browser.calls)")
    }

    // MARK: 記進帳本之後的失敗都說已計次（第三輪 verify 第 6、20 則）

    func testANavigationFailureAfterTheAttemptIsCountedSaysSo() {
        var s = Scenario(); s.navigationFails = true
        XCTAssertEqual(fetch(s), 1, errText)
        XCTAssertTrue(errText.contains("could not navigate the tab to the PDF link"), errText)
        XCTAssertTrue(errText.contains("attempt for today is already counted"), errText)
    }

    func testAnUnreadableTabListAfterTheAttemptIsCountedSaysSo() {
        let code = fetch(hook: { [unowned self] args, _ in
            guard args[0] == "documents", self.outText.contains("attempt:") else { return nil }
            return SafariRun(status: 1, stderr: "Error: AppleScript timed out\n")
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("could not read Safari's tab list"), errText)
        XCTAssertTrue(errText.contains("attempt for today is already counted"), errText)
    }

    func testAFailureBeforeTheAttemptDoesNotSayItWasCounted() {
        var n = 0
        let code = fetch(hook: { args, _ in
            guard args[0] == "documents" else { return nil }
            n += 1
            return n == 4 ? SafariRun(status: 1, stderr: "Error: AppleScript timed out\n") : nil
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertFalse(outText.contains("attempt:"), outText)
        XCTAssertFalse(errText.contains("already counted"), errText)
    }

    // MARK: 別的 profile 的視窗（safari-browser#351；第三輪 verify 第 12 則）

    /// 別的 profile 的視窗開著：#351 可能把新分頁開到那裡，以那個 profile 的身分載入文章頁。開任何分頁之前就停，訊息不印那個 profile 與它的分頁。
    func testAWindowOfAnotherProfileStopsTheRunBeforeAnythingIsOpened() {
        let code = fetch(hook: { args, fake in
            guard args[0] == "documents" else { return nil }
            return SafariRun(status: 0, stdout: Self.documents([(5, "own", 9005, fake.tabs.map(\.url)),
                                                                (6, "someone-else", 9006, ["https://mail.private.example/inbox"])]))
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("a Safari window of another profile"), errText)
        XCTAssertFalse(errText.contains("someone-else"), errText)
        XCTAssertFalse(errText.contains("mail.private.example"), errText)
        XCTAssertFalse(browser.calls.contains { $0.hasPrefix("open") }, "什麼都沒開：\(browser.calls)")
    }

    /// 同一個 profile 的另一個視窗不擋：新分頁真的開錯視窗時 fetch 認得出來、不讀它（`went to another Safari window`），而那一頁載入在使用者
    /// 自己的 profile 裡。
    func testAnotherWindowOfTheSameProfileDoesNotStopTheRun() {
        let code = fetch(hook: { args, fake in
            guard args[0] == "documents" else { return nil }
            // 這個答案繞過了假瀏覽器自己的轉址：落地頁直接換成文章頁（記號保留）
            if fake.tabs.count > 1, fake.tabs[1].url.hasPrefix("https://doi.org/") { fake.tabs[1].url = Self.finalURL + "#" + Self.mark }
            return SafariRun(status: 0, stdout: Self.documents([(5, "own", 9005, fake.tabs.map(\.url)), (6, "own", 9006, ["https://news.example/"])]))
        })
        XCTAssertEqual(code, 7, errText)
    }

    // MARK: 以記號接續（第三輪 verify 第 7、21 則）

    /// 結束碼 8：記號還在，`resume:` 一行帶 `--resume-mark` 與這次最後看到的視窗編號。
    func testTheResumeLineCarriesTheMarkAndTheWindow() {
        var s = Scenario(); s.pageStatus = "403"; s.pageText = "Just a moment...\nChecking"
        XCTAssertEqual(fetch(s), 8, errText)
        XCTAssertTrue(outText.contains("resume: --resume-tab 2 --resume-origin https://pub.example --window 5 --resume-mark \(Self.mark)"), outText)
        XCTAssertTrue(errText.contains("--resume-mark \(Self.mark)"), errText)
    }

    /// 記號已經不在（Elsevier）：`resume:` 一行不帶 `--resume-mark`（接續時沒有東西可找）。
    func testWithoutTheMarkTheResumeLineHasNoMark() {
        var s = Scenario(); s.pageStatus = "403"; s.pageText = "Just a moment...\nChecking"; s.keepsMark = false
        XCTAssertEqual(fetch(s), 8, errText)
        XCTAssertTrue(outText.contains("resume: --resume-tab 2 --resume-origin https://pub.example --window 5"), outText)
        XCTAssertFalse(outText.contains("--resume-mark"), outText)
    }

    /// 使用者驗證時分頁移了位置，`--resume-tab` 指到使用者自己同一站的分頁：以記號找到的是停下的那個分頁，使用者的分頁沒被讀、沒被導航。
    func testResumingFindsTheMarkedTabWhereverItMoved() {
        let ours = Self.finalURL + "#" + Self.mark
        let code = fetch(tabs: [ours, Self.usersSameSiteTab], configure: {
            $0.resumeTab = 2; $0.resumeOrigin = "https://pub.example"; $0.resumeMark = Self.mark
        })
        XCTAssertEqual(code, 7, errText)
        XCTAssertTrue(outText.contains("resuming: window 5 tab 1"), outText)
        XCTAssertEqual(browser.tabs[1].url, Self.usersSameSiteTab, "使用者的分頁沒有被導航")
        XCTAssertEqual(opens.map { Array($0.dropLast()) }, [["open", "--profile", "own", "--url-endswith", "#" + Self.mark]])
    }

    /// 導航之後的接續（`followed`）：PDF 在別的主機上、分頁還帶著記號。接續時第一個送進分頁的 JS（讀 `document.contentType`）就以記號鎖，
    /// 不是位置（找到記號之後才算接到那個分頁；mutation 檢查找出這一條先前沒有測試）。
    func testResumingAfterTheLinkWasFollowedLocksOnTheMarkFromTheFirstScript() {
        var s = Scenario(); s.currentContentType = "application/pdf"
        var jsLocks: [String] = []
        let code = fetch(s, tabs: ["https://user.example/mine", "https://cdn.pub.example/x.pdf#" + Self.mark], configure: {
            $0.resumeTab = 2; $0.resumeOrigin = "https://pub.example"; $0.resumeStage = .followed; $0.resumeMark = Self.mark
        }, hook: { args, _ in
            if args[0] == "js" { jsLocks.append(args.contains("--url-endswith") ? "mark" : "position") }
            return nil
        })
        XCTAssertEqual(code, 7, errText)
        XCTAssertTrue(outText.contains("handover: pdf-shown"), outText)
        XCTAssertEqual(jsLocks.first, "mark", "\(jsLocks)")
        XCTAssertTrue(jsLocks.allSatisfy { $0 == "mark" }, "\(jsLocks)")
    }

    /// 記號已經不在：照 `--resume-tab` 的位置接續（使用者 2026-11-04：記號不見時改用位置）。
    func testResumingWithoutTheMarkOnAnyTabUsesThePosition() {
        let code = fetch(tabs: ["https://user.example/mine", Self.finalURL], configure: {
            $0.resumeTab = 2; $0.resumeOrigin = "https://pub.example"; $0.resumeMark = Self.mark
        })
        XCTAssertEqual(code, 7, errText)
        XCTAssertTrue(outText.contains("resuming: window 5 tab 2"), outText)
        XCTAssertEqual(opens.map { Array($0.dropLast()) }, [["open", "--window", "5", "--tab-in-window", "2"]])
    }

    /// 帶著記號的分頁在別的視窗：不接續，請人找出它所在的視窗。
    func testResumingWhenTheMarkedTabIsInAnotherWindowStops() {
        let code = fetch(configure: { $0.resumeTab = 1; $0.resumeOrigin = "https://pub.example"; $0.resumeMark = Self.mark }, hook: { args, fake in
            guard args[0] == "documents" else { return nil }
            return SafariRun(status: 0, stdout: Self.documents([(5, "own", 9005, [Self.usersSameSiteTab]),
                                                                (6, "own", 9006, [Self.finalURL + "#" + Self.mark])]))
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("is not exactly one tab of window 5"), errText)
        XCTAssertTrue(opens.isEmpty)
    }

    func testAResumeMarkOfTheWrongShapeOrWithoutAResumeTabIsRefused() {
        XCTAssertEqual(fetch(configure: { $0.resumeTab = 2; $0.resumeOrigin = "https://pub.example"; $0.resumeMark = "akashic-XYZ" }), 1)
        XCTAssertTrue(errText.contains("--resume-mark"), errText)
        XCTAssertEqual(fetch(configure: { $0.resumeMark = Self.mark }), 1)
        XCTAssertTrue(errText.contains("--resume-mark goes with --resume-tab"), errText)
        XCTAssertNil(FulltextFetch.markShapeProblem(FulltextFetch.newMark()))
        XCTAssertNotNil(FulltextFetch.markShapeProblem("akashic-0123456789ABCDEF"))
        XCTAssertNotNil(FulltextFetch.markShapeProblem("akashic-0123456789abcde"))
    }

    // MARK: 訊息印的是我們的分頁（第三輪 verify 第 27 則）

    /// 清單的位置有缺號：先前依位置從清單取「我們的分頁最後的網址」，取到旁邊的分頁（或什麼都沒有）。現在記的是確認的那個分頁本身的網址。
    func testAGapInThePositionsDoesNotPutAnotherTabsURLInTheMessage() {
        var s = Scenario(); s.link = ""
        let code = fetch(s, hook: { args, fake in
            guard args[0] == "documents" else { return nil }
            // 這個答案繞過了假瀏覽器自己的轉址：落地頁直接換成文章頁（記號保留）
            if fake.tabs.count > 1, fake.tabs[1].url.hasPrefix("https://doi.org/") { fake.tabs[1].url = Self.finalURL + "#" + Self.mark }
            // 位置 1 與 3（2 沒有回報）
            let items = fake.tabs.enumerated().map { i, t in
                PyJSON.object([("window", .int(5)), ("index", .int(i + 1)), ("tab_in_window", .int(i == 0 ? 1 : i + 2)), ("url", .string(t.url)),
                               ("title", .string(t.title)), ("profile", .string("own")), ("is_current", .bool(false)),
                               ("blocking_dialog", PyJSON.object([("state", .string("unknown")), ("window_id", .int(9005))]))])
            }
            return SafariRun(status: 0, stdout: PyJSON.array(items).dumps() + "\n")
        })
        XCTAssertEqual(code, 3, errText)
        XCTAssertTrue(errText.contains("no PDF link on \(FulltextFetch.plainURL(browser.tabs[1].url))"), errText)
        XCTAssertFalse(errText.contains("user.example"), errText)
    }

    // MARK: 第五版（第四輪 verify 之後，使用者 2026-11-04：靠 safari-browser#351 根本解決、照位置接續）


    /// 接續也一樣：別的 profile 的視窗開著，接續在讀、導航任何東西之前就停（第六輪 verify 第 1、4 則：先前判斷放在 resume 之後）。
    func testAResumeStopsWhenAnotherProfilesWindowIsOpen() {
        var sent: [String] = []
        let code = fetch(tabs: ["https://user.example/mine", Self.finalURL], configure: {
            $0.resumeTab = 2; $0.resumeOrigin = "https://pub.example"
        }, hook: { args, fake in
            if args[0] != "documents" { sent.append(args[0]) }
            guard args[0] == "documents" else { return nil }
            return SafariRun(status: 0, stdout: Self.documents([(5, "own", 9005, fake.tabs.map(\.url)),
                                                                (6, "someone-else", 9006, ["https://mail.private.example/inbox"])]))
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("a Safari window of another profile"), errText)
        XCTAssertEqual(sent, [], "沒有送任何 js、wait、open：\(sent)")
    }

    /// 執行當中才開了別的 profile 的視窗：下一眼就停，不再讀、不再導航（第六輪 verify 第 8 則）。
    func testAnotherProfilesWindowOpenedMidRunStopsTheRun() {
        var looks = 0
        let code = fetch(hook: { args, fake in
            guard args[0] == "documents" else { return nil }
            looks += 1
            if fake.tabs.count > 1, fake.tabs[1].url.hasPrefix("https://doi.org/") { fake.tabs[1].url = Self.finalURL + "#" + Self.mark }
            var windows: [(number: Int, profile: String?, id: Int, urls: [String])] = [(5, "own", 9005, fake.tabs.map(\.url))]
            if looks >= 5 { windows.append((6, "someone-else", 9006, ["https://mail.private.example/inbox"])) }
            return SafariRun(status: 0, stdout: Self.documents(windows))
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("was opened while this ran"), errText)
        XCTAssertFalse(browser.navigated)
        XCTAssertFalse(errText.contains("mail.private.example"), errText)
    }

    /// 讀 PDF 連結不重跑：記號剛好在讀連結之前不見（頁面可能剛換成同站的登入或驗證頁），讀連結失敗就停，不讀新頁面的連結再導航過去
    /// （第六輪 verify 第 2、32 則）。
    func testTheLinkReadIsNotRetried() {
        var linkReads = 0
        let code = fetch(hook: { args, fake in
            guard args[0] == "js", args.last!.contains("citation_pdf_url") else { return nil }
            linkReads += 1
            if let r = fake.tabs[1].url.range(of: "#akashic-") { fake.tabs[1].url = String(fake.tabs[1].url[..<r.lowerBound]) }
            return nil
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertEqual(linkReads, 1)
        XCTAssertFalse(browser.navigated)
    }

    /// 新分頁以全域的 `--window N` 開（不帶 `--profile`：safari-browser#351 的修正不能把它釘在那個 profile 的視窗，見那個 issue 的更正）。
    func testTheTabIsOpenedByTheGlobalWindowNumber() {
        var newTabArgs: [String] = []
        XCTAssertEqual(fetch(hook: { args, _ in
            if args[0] == "open", args.contains("--new-tab") { newTabArgs = Array(args.dropLast()) }
            return nil
        }), 7, errText)
        XCTAssertEqual(newTabArgs, ["open", "--new-tab", "--window", "5"])
    }

    /// 認不出 profile 的別的視窗（`profile: null`）也當成可能是別人的：沒有修正時停（第四輪 verify 第 6 則）。
    func testAnotherWindowWhoseProfileCannotBeReadAlsoStopsTheRun() {
        let code = fetch(hook: { args, fake in
            guard args[0] == "documents" else { return nil }
            var items: [PyJSON] = []
            for (i, t) in fake.tabs.enumerated() {
                items.append(PyJSON.object([("window", .int(5)), ("index", .int(i + 1)), ("tab_in_window", .int(i + 1)), ("url", .string(t.url)),
                                            ("title", .string("t")), ("profile", .string("own")), ("is_current", .bool(false)),
                                            ("blocking_dialog", PyJSON.object([("state", .string("unknown")), ("window_id", .int(9005))]))]))
            }
            items.append(PyJSON.object([("window", .int(6)), ("index", .int(9)), ("tab_in_window", .int(1)), ("url", .string("https://x.example/")),
                                        ("title", .string("")), ("profile", .null), ("is_current", .bool(true)),
                                        ("blocking_dialog", PyJSON.object([("state", .string("unknown")), ("window_id", .int(9006))]))]))
            return SafariRun(status: 0, stdout: PyJSON.array(items).dumps() + "\n")
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("cannot be read"), errText)
        XCTAssertFalse(browser.calls.contains { $0.hasPrefix("open") }, "\(browser.calls)")
    }

    /// 記號剛好在確認與命令之間不見（讀頁面文字之前頁面用腳本換了網址）：記號鎖找不到分頁，再確認一次、改用位置鎖重跑一次，照常往下走
    /// （第四輪 verify 第 8 則：先前結束碼 1）。讀頁面文字的結果之後還會跟前後兩次的網址與標題比對，所以可以重跑；讀連結不行（見下一個測試）。
    func testAMarkLostRightBeforeACommandIsRetriedOnceByPosition() {
        var textLocks: [String] = []
        let code = fetch(hook: { args, fake in
            guard args[0] == "js", args.last!.contains("innerText.slice") else { return nil }
            textLocks.append(args.contains("--url-endswith") ? "mark" : "position")
            if textLocks.count == 1, let r = fake.tabs[1].url.range(of: "#akashic-") { fake.tabs[1].url = String(fake.tabs[1].url[..<r.lowerBound]) }
            return nil
        })
        XCTAssertEqual(code, 7, errText)
        XCTAssertEqual(Array(textLocks.prefix(2)), ["mark", "position"])
        XCTAssertTrue(browser.navigated)
    }

    /// 讀連結失敗之後的確認讓鎖變了（記號剛好不見）：訊息印的是實際用的鎖，不是重算的（第四輪 verify 第 21 則）。
    func testAFailedCommandIsReportedWithTheLockItActuallyUsed() {
        let code = fetch(hook: { args, fake in
            guard args[0] == "js", args.last!.contains("citation_pdf_url") else { return nil }
            if let r = fake.tabs[1].url.range(of: "#akashic-") { fake.tabs[1].url = String(fake.tabs[1].url[..<r.lowerBound]) }
            return SafariRun(status: 1, stderr: "Error: AppleScript error: JavaScript error: boom\nAvailable documents:\n")
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("`js --profile own --url-endswith #\(Self.mark) <the link script>`"), errText)
    }

    /// 導航不重跑：記號剛好在導航之前不見（頁面剛換了網址，可能是驗證頁或登入頁），導航找不到分頁就失敗、說已計次，不以位置鎖再送一次
    /// （第五輪 verify 第 2 則）。
    func testANavigationThatFindsNoTabIsNotRetried() {
        let code = fetch(hook: { args, fake in
            guard args[0] == "open", !args.contains("--new-tab") else { return nil }
            if let r = fake.tabs[1].url.range(of: "#akashic-") { fake.tabs[1].url = String(fake.tabs[1].url[..<r.lowerBound]) }
            return nil
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertEqual(opens.count, 1, "\(opens)")
        XCTAssertFalse(browser.navigated)
        XCTAssertTrue(errText.contains("could not navigate the tab to the PDF link"), errText)
        XCTAssertTrue(errText.contains("attempt for today is already counted"), errText)
    }

    /// 重跑只認 safari-browser 自己那一行的 `No Safari document matches`；頁面寫得進去的 JavaScript 錯誤不算。
    func testOnlySafariBrowsersOwnNoMatchLineCountsAsNoTab() {
        XCTAssertTrue(FulltextFetch.noTabMatched("Error: No Safari document matches \"(target)\".\n\nAvailable documents:\n"))
        XCTAssertFalse(FulltextFetch.noTabMatched("Error: no document matches the target\n"))
        XCTAssertFalse(FulltextFetch.noTabMatched("Error: AppleScript error: JavaScript error: Error: No Safari document matches x\n"))
        XCTAssertFalse(FulltextFetch.noTabMatched("Error: AppleScript error: JavaScript error: boom\n"))
        XCTAssertFalse(FulltextFetch.noTabMatched("Error: AppleScript error: JavaScript error: x\nError: No Safari document matches y\n"), "只看第一行")
    }

    /// 只重跑「沒有分頁符合」：命令自己的失敗不重跑。
    func testOtherFailuresOfAMarkLockedCommandAreNotRetried() {
        var linkCalls = 0
        let code = fetch(hook: { args, _ in
            guard args[0] == "js", args.last!.contains("citation_pdf_url") else { return nil }
            linkCalls += 1
            return SafariRun(status: 1, stderr: "Error: AppleScript error: JavaScript error: boom\n")
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertEqual(linkCalls, 1)
    }

    /// 導航之後的接續：嘗試在上一次執行就記過了，接續在一開始就失敗也要說（第四輪 verify 第 4 則）。
    func testAResumedRunAfterTheLinkWasFollowedSaysTheAttemptWasCountedEvenWhenItFailsAtOnce() {
        let code = fetch(configure: { $0.resumeTab = 2; $0.resumeOrigin = "https://pub.example"; $0.resumeStage = .followed },
                         hook: { args, _ in args[0] == "documents" ? SafariRun(status: 1, stderr: "Error: AppleScript timed out\n") : nil })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("attempt for today is already counted"), errText)
    }

    func testAResumeRefusalAfterTheLinkWasFollowedSaysTheAttemptWasCounted() {
        let code = fetch(tabs: ["https://user.example/mine"], configure: {
            $0.resumeTab = 4; $0.resumeOrigin = "https://pub.example"; $0.resumeStage = .followed
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("has no tab 4"), errText)
        XCTAssertTrue(errText.contains("attempt for today is already counted"), errText)
    }

    /// 導航之後的接續也一樣：那個位置是別的主機上的一般網頁，不接、不印它的網址。
    func testAResumeRefusalAfterTheLinkWasFollowedDoesNotPrintTheOtherTabsURL() {
        let code = fetch(tabs: ["https://user.example/private?token=x", Self.finalURL], configure: {
            $0.resumeTab = 1; $0.resumeOrigin = "https://pub.example"; $0.resumeStage = .followed
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("shows another page"), errText)
        XCTAssertFalse(errText.contains("user.example"), errText)
    }

    /// 接續拒絕的那個分頁不是我們的：不印它的網址（第四輪 verify 第 25 則）。
    func testAResumeRefusalDoesNotPrintTheOtherTabsURL() {
        let code = fetch(tabs: ["https://user.example/private?token=x", Self.finalURL], configure: {
            $0.resumeTab = 1; $0.resumeOrigin = "https://pub.example"
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("shows another page"), errText)
        XCTAssertFalse(errText.contains("user.example"), errText)
    }

    // MARK: 第八版（第七輪 verify）：連結的答案綁在判過的那一頁上

    /// 讀完連結之後的第一眼，分頁已經換了頁（`change` 改它）：這個答案不用。
    private func afterTheLinkRead(_ s: Scenario = Scenario(), change: @escaping (FakeBrowser) -> Void) -> Int32 {
        var linkRead = false, changed = false
        return fetch(s, hook: { args, fake in
            if args[0] == "js", args.last!.contains("citation_pdf_url") { linkRead = true }
            if args[0] == "documents", linkRead, !changed { changed = true; change(fake) }
            return nil
        })
    }

    /// 第七輪 verify 第 1 則（Codex）：讀完連結之後分頁到了同站的登入頁、記號不見。先前位置追蹤當成我們的分頁在換頁、`siteGuard` 只看主機，
    /// 就拿舊頁面的連結把那一頁蓋掉。現在判新的那一頁：登入頁整批暫停，沒有導航，也沒有記嘗試。
    func testASameSiteLoginPageAfterTheLinkReadStopsTheRunAndNothingIsNavigated() {
        let code = afterTheLinkRead { $0.tabs[1].url = "https://pub.example/login" }
        XCTAssertEqual(code, 6, errText)
        XCTAssertFalse(browser.navigated)
        XCTAssertTrue(opens.isEmpty, "\(opens)")
        XCTAssertFalse(outText.contains("attempt:"), outText)
    }

    func testASameSiteVerificationPageAfterTheLinkReadWaitsForTheUserAndNothingIsNavigated() {
        let code = afterTheLinkRead {
            $0.tabs[1].url = "https://pub.example/challenge-page"
            $0.scenario.pageStatus = "403"; $0.scenario.pageText = "Just a moment...\nChecking"
        }
        XCTAssertEqual(code, 8, errText)
        XCTAssertFalse(browser.navigated)
        XCTAssertFalse(outText.contains("attempt:"), outText)
    }

    /// 新的那一頁沒有任何訊號：連結還是舊頁面的，不跟（結束碼 1，沒有記嘗試）。
    func testASameSiteOrdinaryPageAfterTheLinkReadIsNotNavigatedEither() {
        let code = afterTheLinkRead { $0.tabs[1].url = "https://pub.example/doi/10.1/another" }
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("changed after it was checked"), errText)
        XCTAssertFalse(browser.navigated)
        XCTAssertFalse(outText.contains("attempt:"), outText)
        XCTAssertFalse(errText.contains("already counted"), errText)
    }

    /// 判過之後、讀連結之前就換了頁（記號還在的同站轉址也一樣）：讀到的是新頁面的連結，同樣不用（第七輪 verify 第 3 則）。
    func testAPageChangeBetweenTheCheckAndTheLinkReadIsCaught() {
        let code = fetch(hook: { args, fake in
            if args[0] == "js", args.last!.contains("citation_pdf_url") { fake.tabs[1].url = "https://pub.example/doi/10.1/another#" + Self.mark }
            return nil
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("changed after it was checked"), errText)
        XCTAssertFalse(browser.navigated)
    }

    /// 導航之前的最後一眼：記了嘗試之後才換頁，也不導航；訊息說已計次。
    func testAPageChangeRightBeforeTheNavigationIsCaughtAndSaysTheAttemptWasCounted() {
        for (url, expected) in [("https://pub.example/login", Int32(6)), ("https://pub.example/doi/10.1/another", 1)] {
            var changed = false
            let code = fetch(hook: { [unowned self] args, fake in
                if args[0] == "documents", !changed, self.outText.contains("attempt:") { changed = true; fake.tabs[1].url = url }
                return nil
            })
            XCTAssertEqual(code, expected, errText)
            XCTAssertFalse(browser.navigated, url)
            XCTAssertTrue(errText.contains("attempt for today is already counted"), errText)
            XCTAssertEqual(errText.components(separatedBy: "already counted").count - 1, 1, errText)
            try? FileManager.default.removeItem(at: root.appendingPathComponent("ledger.jsonl"))
        }
    }

    /// 頁面用腳本拿掉 fragment 不是換頁：網址除了我們的記號都一樣，照常導航（以位置鎖）。
    func testLosingOnlyTheMarkAfterTheLinkReadIsNotAPageChange() {
        let code = afterTheLinkRead { fake in
            if let r = fake.tabs[1].url.range(of: "#akashic-") { fake.tabs[1].url = String(fake.tabs[1].url[..<r.lowerBound]) }
        }
        XCTAssertEqual(code, 7, errText)
        XCTAssertTrue(browser.navigated)
        XCTAssertEqual(opens.map { Array($0.dropLast()) }, [["open", "--window", "5", "--tab-in-window", "2"]])
    }

    // MARK: 第八版：每一眼的別的 profile 檢查只看開頭沒有的視窗（第七輪 verify 第 4、15 則）

    /// 同一個 profile 的第二個視窗開頭就在、檢查過：它載入新頁、標題一時空白而讀不出 profile，不是有人開了別的 profile 的視窗。
    func testAWindowCheckedAtTheStartWhoseProfileGoesUnreadableDoesNotStopTheRun() {
        var looks = 0
        let code = fetch(hook: { args, fake in
            guard args[0] == "documents" else { return nil }
            looks += 1
            if fake.tabs.count > 1, fake.tabs[1].url.hasPrefix("https://doi.org/") { fake.tabs[1].url = Self.finalURL + "#" + Self.mark }
            return SafariRun(status: 0, stdout: Self.documents([(5, "own", 9005, fake.tabs.map(\.url)),
                                                                (6, looks >= 5 ? nil : "own", 9006, ["https://news.example/"])]))
        })
        XCTAssertEqual(code, 7, errText)
        XCTAssertTrue(browser.navigated)
    }

    /// 接續也一樣：開頭檢查過的視窗要在 `resume` 之前記下，否則接續的 run 每一眼都把它當成新開的視窗。
    func testOnAResumedRunAWindowCheckedAtTheStartWhoseProfileGoesUnreadableDoesNotStopTheRun() {
        var looks = 0
        let code = fetch(tabs: ["https://user.example/mine", Self.finalURL], configure: {
            $0.resumeTab = 2; $0.resumeOrigin = "https://pub.example"
        }, hook: { args, fake in
            guard args[0] == "documents" else { return nil }
            looks += 1
            return SafariRun(status: 0, stdout: Self.documents([(5, "own", 9005, fake.tabs.map(\.url)),
                                                                (6, looks >= 2 ? nil : "own", 9006, ["https://news.example/"])]))
        })
        XCTAssertEqual(code, 7, errText)
        XCTAssertTrue(browser.navigated)
    }

    /// 開頭沒有的視窗讀不出 profile：可能是別人的，停。
    func testAWindowOpenedMidRunWhoseProfileCannotBeReadStopsTheRun() {
        var looks = 0
        let code = fetch(hook: { args, fake in
            guard args[0] == "documents" else { return nil }
            looks += 1
            if fake.tabs.count > 1, fake.tabs[1].url.hasPrefix("https://doi.org/") { fake.tabs[1].url = Self.finalURL + "#" + Self.mark }
            var windows: [(number: Int, profile: String?, id: Int, urls: [String])] = [(5, "own", 9005, fake.tabs.map(\.url))]
            if looks >= 5 { windows.append((6, nil, 9006, ["https://x.example/"])) }
            return SafariRun(status: 0, stdout: Self.documents(windows))
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("was opened while this ran"), errText)
        XCTAssertFalse(browser.navigated)
    }

    /// 開頭沒有、而屬於同一個 profile 的視窗不擋。
    func testAWindowOfTheSameProfileOpenedMidRunDoesNotStopTheRun() {
        var looks = 0
        let code = fetch(hook: { args, fake in
            guard args[0] == "documents" else { return nil }
            looks += 1
            if fake.tabs.count > 1, fake.tabs[1].url.hasPrefix("https://doi.org/") { fake.tabs[1].url = Self.finalURL + "#" + Self.mark }
            var windows: [(number: Int, profile: String?, id: Int, urls: [String])] = [(5, "own", 9005, fake.tabs.map(\.url))]
            if looks >= 5 { windows.append((6, "own", 9006, ["https://news.example/"])) }
            return SafariRun(status: 0, stdout: Self.documents(windows))
        })
        XCTAssertEqual(code, 7, errText)
    }

    // MARK: 第八版：記號在沒有記號的一段之後回來（第六輪 verify 第 6 則、第七輪 verify 第 2 則）

    /// 位置鎖導航的那一刻左邊多了一個分頁：`--tab-in-window T` 指到使用者的分頁，它被導航、帶著我們的記號。先前記號的分支不比對上一眼，
    /// 把它當成我們的分頁、印 `handover`，真正的文章頁留在旁邊。現在分頁數變了，對不上就停。
    func testAPositionLockedNavigationThatLandsOnTheUsersTabIsNotTakenForOurs() {
        var s = Scenario(); s.keepsMark = false
        let code = fetch(s, hook: { args, fake in
            if args[0] == "open", !args.contains("--new-tab") { fake.tabs.insert(("https://left.example/", "a tab"), at: 0) }
            return nil
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("changed while this ran"), errText)
        XCTAssertTrue(errText.contains("attempt for today is already counted"), errText)
        XCTAssertFalse(outText.contains("handover:"), outText)
    }

    /// 記號回來時在別的位置：不是我們導航的那個位置，停。
    func testTheMarkComingBackAtAnotherPositionStopsTheRun() {
        var s = Scenario(); s.keepsMark = false
        var navigated = false
        let code = fetch(s, hook: { args, fake in
            if args[0] == "open", !args.contains("--new-tab") { navigated = true; return nil }
            if args[0] == "documents", navigated { navigated = false; fake.tabs.swapAt(0, 1) }
            return nil
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("changed while this ran"), errText)
        XCTAssertFalse(outText.contains("handover:"), outText)
    }

    /// 我們的位置沒有變，記號卻出現在別的分頁上：位置追蹤本身成立，所以要另外看記號在不在我們的位置。
    func testTheMarkOnAnotherTabWhileOurPositionIsUnchangedStopsTheRun() {
        var s = Scenario(); s.keepsMark = false
        let code = fetch(s, hook: { args, fake in
            guard args[0] == "open", !args.contains("--new-tab") else { return nil }
            fake.tabs[0].url = args.last!
            return SafariRun(status: 0)
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("changed while this ran"), errText)
        XCTAssertFalse(outText.contains("handover:"), outText)
    }

    /// Elsevier 的正常流程：記號丟了之後位置鎖導航，`withMark` 把記號帶回我們的位置。不是誤停。
    func testTheMarkComingBackOnOurOwnPositionGoesOn() {
        var s = Scenario(); s.keepsMark = false
        XCTAssertEqual(fetch(s), 7, errText)
        XCTAssertTrue(outText.contains("handover: pdf-shown window 5 tab 2"), outText)
    }

    // MARK: 第八版：把停止的位置釘住（第七輪 verify 第 9、21 則）

    /// 只有這條路上順序才有差：導航之後的接續、分頁在 PDF 主機上、記號不在。`resume` 在任何 `ownTabNow` 之前就送 `js`，所以停止要排在 `resume`
    /// 之前。沒有送任何東西到那個位置。
    func testAFollowedResumeStopsBeforeItsFirstScriptWhenAnotherProfilesWindowIsOpen() {
        var s = Scenario(); s.currentContentType = "application/pdf"
        var sent: [String] = []
        let code = fetch(s, tabs: ["https://user.example/mine", "https://cdn.pub.example/x.pdf"], configure: {
            $0.resumeTab = 2; $0.resumeOrigin = "https://pub.example"; $0.resumeStage = .followed
        }, hook: { args, fake in
            guard args[0] == "documents" else { sent.append(args[0]); return nil }
            return SafariRun(status: 0, stdout: Self.documents([(5, "own", 9005, fake.tabs.map(\.url)),
                                                                (6, "someone-else", 9006, ["https://mail.private.example/inbox"])]))
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("a Safari window of another profile"), errText)
        XCTAssertEqual(sent, [], "\(sent)")
    }

    /// 無條件：`safari-browser --version` 回多新都一樣。第五版的版本閘是第五輪 verify 的 HIGH，維護者裁決不要；假瀏覽器沒有 `--version`
    /// 時，版本閘回來測試也不會紅。
    func testTheStopDoesNotDependOnTheSafariBrowserVersion() {
        let code = fetch(hook: { args, fake in
            if args.contains("--version") { return SafariRun(status: 0, stdout: "v9.9.9\n") }
            guard args[0] == "documents" else { return nil }
            return SafariRun(status: 0, stdout: Self.documents([(5, "own", 9005, fake.tabs.map(\.url)),
                                                                (6, "someone-else", 9006, ["https://mail.private.example/inbox"])]))
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("a Safari window of another profile"), errText)
        XCTAssertFalse(browser.calls.contains { $0.hasPrefix("open") }, "\(browser.calls)")
    }

    // MARK: 第九版：頁面標題偽造的列（第八輪 verify 第 1 則，safari-browser#355）

    /// `documents --json` 的答案，逐列給：（視窗編號，分頁位置，視窗 id，網址）。
    private static func rows(_ list: [(window: Int, tab: Int, id: Int, url: String)]) -> String {
        PyJSON.array(list.map { r in
            PyJSON.object([("window", .int(r.window)), ("index", .int(r.tab)), ("tab_in_window", .int(r.tab)), ("url", .string(r.url)),
                           ("title", .string("t")), ("profile", .string("own")), ("is_current", .bool(false)),
                           ("blocking_dialog", PyJSON.object([("state", .string("unknown")), ("window_id", .int(r.id))]))])
        }).dumps() + "\n"
    }

    /// 頁面讀了 `location.hash`，拿掉自己的記號，把標題寫成一列帶記號的假列。讀完連結之後的清單裡，使用者的第 1 個分頁多了一列帶記號的。
    /// 先前 `ownTabNow` 認任何一列帶記號的分頁，導航就打到使用者的分頁。假列不能刪掉別的分頁的列，所以它一定與真的列同位置：第二列就停。
    private func forgedAfterTheLinkRead(_ forged: (window: Int, tab: Int, id: Int, url: String)) -> Int32 {
        var linkRead = false
        return fetch(hook: { args, fake in
            if args[0] == "js", args.last!.contains("citation_pdf_url") { linkRead = true }
            guard args[0] == "documents", linkRead else { return nil }
            return SafariRun(status: 0, stdout: Self.rows([(5, 1, 9005, fake.tabs[0].url), (5, 2, 9005, Self.finalURL), forged]))
        })
    }

    func testARowForgedOntoARealPositionStopsTheRunAndNothingIsNavigated() {
        let code = forgedAfterTheLinkRead((5, 1, 9005, Self.finalURL + "#" + Self.mark))
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("cannot be trusted"), errText)
        // 同一個視窗被讀兩次（列舉途中視窗被拉到前面）也長這樣，訊息兩種都要說（第九輪 verify 第 1、7 則）
        XCTAssertTrue(errText.contains("a window raised while the list was read"), errText)
        XCTAssertTrue(errText.contains("a page title forging an entry"), errText)
        XCTAssertFalse(browser.navigated)
        XCTAssertTrue(opens.isEmpty, "\(opens)")
    }

    /// 視窗編號可以寫成別的，id 是頁面讀不到卻也不必讀對的欄位：safari-browser 以 id 解析分頁，所以 id 與位置相同的列一樣是假列。
    func testARowForgedUnderAnotherWindowNumberWithOurWindowIDStopsTheRunToo() {
        let code = forgedAfterTheLinkRead((99, 1, 9005, Self.finalURL + "#" + Self.mark))
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("cannot be trusted"), errText)
        XCTAssertFalse(browser.navigated)
    }

    func testADuplicatedPositionIsFoundByNumberOrByWindowID() {
        typealias Row = (window: Int, id: Int?, tab: Int)
        let same: [Row] = [(5, 9005, 1), (5, 7777, 1)]
        XCTAssertTrue(FulltextFetch.hasDuplicatedPosition(same), "同一個編號、同一個位置")
        let sameID: [Row] = [(5, 9005, 1), (99, 9005, 1)]
        XCTAssertTrue(FulltextFetch.hasDuplicatedPosition(sameID), "同一個 id、同一個位置")
        let noID: [Row] = [(5, nil, 1), (6, nil, 1)]
        XCTAssertFalse(FulltextFetch.hasDuplicatedPosition(noID), "讀不到 id 的列不互相比")
        let clean: [Row] = [(5, 9005, 1), (5, 9005, 2), (6, 9006, 1)]
        XCTAssertFalse(FulltextFetch.hasDuplicatedPosition(clean))
    }

    /// 兩個視窗都有第 1 個分頁不是假列（誤停會讓開著兩個視窗的人完全不能用）。
    func testTheSamePositionInTwoWindowsIsNotAForgedRow() {
        let code = fetch(hook: { args, fake in
            guard args[0] == "documents" else { return nil }
            if fake.tabs.count > 1, fake.tabs[1].url.hasPrefix("https://doi.org/") { fake.tabs[1].url = Self.finalURL + "#" + Self.mark }
            return SafariRun(status: 0, stdout: Self.documents([(5, "own", 9005, fake.tabs.map(\.url)), (6, "own", 9006, ["https://own.example/a"])]))
        })
        XCTAssertEqual(code, 7, errText)
    }

    // MARK: 第九版：接續的兩個提早結束（第八輪 verify 第 3 則）

    func testAFollowedResumeWhoseWindowIsGoneSaysTheAttemptWasCounted() {
        let code = fetch(configure: { $0.window = 7; $0.resumeTab = 2; $0.resumeOrigin = "https://pub.example"; $0.resumeStage = .followed })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("Safari window 7 not found"), errText)
        XCTAssertTrue(errText.contains("attempt for today is already counted"), errText)
    }

    func testAFollowedResumeWithTheWrongProfileSaysTheAttemptWasCounted() {
        let code = fetch(configure: { $0.expectProfile = "other"; $0.resumeTab = 2; $0.resumeOrigin = "https://pub.example"; $0.resumeStage = .followed })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("refusing to touch it"), errText)
        XCTAssertTrue(errText.contains("attempt for today is already counted"), errText)
    }

    /// `fail()` 自己會跳脫整則訊息，名字先跳脫一次就成了兩次：反斜線被跳脫了又跳脫（第九輪 verify 第 3 則）。
    func testTheProfileRefusalEscapesANameOnce() {
        let code = fetch(configure: { $0.expectProfile = "a\\b\u{FE0F}" })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("a\\u{005C}b\\u{FE0F}"), errText)
        XCTAssertFalse(errText.contains("u{005C}u{"), errText)
    }

    /// 沒有接續時沒有記過嘗試：不印。
    func testTheSameExitsWithoutAResumeSayNothingAboutAnAttempt() {
        for configure in [{ (o: inout FulltextFetch.Options) in o.window = 7 }, { (o: inout FulltextFetch.Options) in o.expectProfile = "other" }] {
            XCTAssertEqual(fetch(configure: configure), 1, errText)
            XCTAssertFalse(errText.contains("already counted"), errText)
        }
    }

    // MARK: 第九版：換了頁之後要判到底（第八輪 verify 第 5、8、10 則）

    /// 同站的驗證頁網址、頁面還沒寫出訊號：落地時是 6，讀完連結之後到了同一頁也要是 6，不是 1。
    func testASameSiteVerificationURLAfterTheLinkReadStopsTheRun() {
        let code = afterTheLinkRead { $0.tabs[1].url = "https://pub.example/captcha/abc" }
        XCTAssertEqual(code, 6, errText)
        XCTAssertFalse(browser.navigated)
        XCTAssertFalse(outText.contains("attempt:"), outText)
    }

    /// 換頁的當下頁面還在載入：等它落定再判，訊號在第二次讀才出現。先前只讀一次，判成沒有訊號（結束碼 1）。
    func testAPageStillLoadingWhenTheChangeIsSeenIsJudgedAfterItSettles() {
        var changed = false, reads = 0
        let code = fetch(hook: { args, fake in
            if args[0] == "js", args.last!.contains("citation_pdf_url") {
                changed = true
                fake.tabs[1].url = "https://pub.example/check"
                fake.scenario.readyState = "loading"
                return nil
            }
            if changed, args[0] == "js", args.last!.contains("document.contentType") {
                reads += 1
                if reads == 2 {
                    fake.scenario.readyState = "complete"
                    fake.scenario.pageStatus = "403"; fake.scenario.pageText = "Just a moment...\nChecking"
                }
            }
            return nil
        })
        XCTAssertEqual(code, 8, errText)
        XCTAssertFalse(browser.navigated)
    }

    /// 判過的那一頁本身：等連結的時候到了同站的驗證頁網址、頁面還沒寫出訊號，先前照樣讀連結（找不到就是結束碼 3，整批繼續；找到就記嘗試、導航）。
    func testAVerificationURLReachedWhileWaitingForTheLinkStopsTheRun() {
        var waited = false
        let code = fetch(hook: { args, fake in
            if args[0] == "wait", !waited { waited = true; fake.tabs[1].url = "https://pub.example/captcha/abc#" + Self.mark }
            return nil
        })
        XCTAssertEqual(code, 6, errText)
        XCTAssertFalse(browser.navigated)
        XCTAssertFalse(outText.contains("attempt:"), outText)
    }

    /// 頁面自己換到同站的 PDF：那是分頁顯示的東西，照常交給人，不是起疑也不是失敗。
    func testASameSitePDFReachedAfterTheLinkReadIsHandedOver() {
        let code = afterTheLinkRead {
            $0.tabs[1].url = "https://pub.example/doi/pdf/10.1/x"
            $0.scenario.currentContentType = "application/pdf"
        }
        XCTAssertEqual(code, 7, errText)
        XCTAssertTrue(outText.contains("handover: pdf-shown"), outText)
        XCTAssertFalse(browser.navigated)
    }

    /// 換頁之後讀不到的頁面：`watchOnSite` 走 `judgeUnreadable`，交給人。落地頁同樣的頁面是 6，這裡與導航之前的接續同一套（第九輪 verify 第 2、6 則）。
    func testAChangedPageThatCannotBeReadIsHandedOverAsUnverifiable() {
        var linkRead = false, changed = false
        let code = fetch(hook: { args, fake in
            if args[0] == "js", args.last!.contains("citation_pdf_url") { linkRead = true; return nil }
            if args[0] == "documents", linkRead, !changed { changed = true; fake.tabs[1].url = "https://pub.example/other" }
            return args[0] == "js" && changed ? SafariRun(status: 1, stdout: "", stderr: "Error: no answer") : nil
        })
        XCTAssertEqual(code, 7, errText)
        XCTAssertTrue(outText.contains("handover: unverifiable"), outText)
        XCTAssertFalse(browser.navigated)
    }

    /// 只有印出來看不到的部分變了（query、fragment；`plainURL` 也去掉路徑參數與帳密）：網址印出來兩邊一樣，訊息不能說成某一處變了
    /// （第九輪 verify 第 12 則：`;jsessionid` 變了、或 A → B → A，先前印「只有 query 或 fragment 變了」）。
    func testAFragmentOnlyChangeSaysWhatChanged() {
        let code = afterTheLinkRead { $0.tabs[1].url = Self.finalURL + "#abstract" }
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("not printed here"), errText)
        XCTAssertFalse(errText.contains("\(Self.finalURL) → \(Self.finalURL)"), errText)
        XCTAssertFalse(browser.navigated)
    }

    // MARK: 第九版：留下的分頁（第八輪 verify 第 6 則）

    /// SKILL 叫 agent 照 `fetch` 印的位置找留下的分頁，所以結束碼 3、9 都要印。
    func testNoPDFLinkPrintsWhereTheTabIs() {
        var s = Scenario(); s.link = "none"
        XCTAssertEqual(fetch(s), 3, errText)
        XCTAssertTrue(errText.contains("window 5, tab 2"), errText)
    }

    func testTheDailyCapPrintsWhereTheTabIs() throws {
        let ledger = root.appendingPathComponent("capped.jsonl").path
        let attempts = FulltextAttemptLedger(path: ledger)
        for _ in 0..<FulltextAttemptLedger.dailyCap {
            _ = try attempts.reserve(site: "pub.example", landing: "x", at: FulltextFetchPathTests.now)
        }
        XCTAssertEqual(fetch(configure: { $0.ledger = ledger }), FulltextFetch.Code.dailyCapReached, errText)
        XCTAssertTrue(errText.contains("window 5, tab 2"), errText)
        XCTAssertTrue(errText.contains("left open"), errText)
    }
}
