import XCTest
@testable import AkashicSkillTools
@testable import AkashicStoreIO

/// #768：`fetch` 只讀它自己開的分頁，而且不關任何分頁。與 `FulltextFetchPathTests` 同一個記憶體內的假瀏覽器——不碰 Safari、不連網。
/// 分頁以網址上的記號認（`keepsMark`），記號不在時以視窗 id 與位置追蹤（這個檔多數測試測的是後者，像 Elsevier）。
///
/// 事故的形狀：使用者正在用 Safari，開分頁與讀「目前的分頁」之間目前的分頁換了，`ownTab` 就成了使用者的分頁；站名也取自那個分頁，
/// 所以「分頁還在同一個站才關」一定成立，頁面文字被讀、分頁被關（修好之後 `fetch` 不再關分頁）。這裡每一支測試都記下每個動作當時打到的分頁（`touched`），
/// 核心斷言只有兩條：使用者的分頁沒有被送 JS、沒有被導航；任何路徑都不關分頁（`tearDown` 檢查）。
final class FulltextOwnTabTests: XCTestCase {
    typealias Scenario = FulltextFetchPathTests.Scenario
    typealias FakeBrowser = FulltextFetchPathTests.FakeBrowser

    static let now = FulltextFetchPathTests.now
    static let landing = FulltextFetchPathTests.landing
    static let finalURL = FulltextFetchPathTests.finalURL
    static let mine = "https://user.example/mine"
    static let other = "https://user.example/other"

    private var root: URL!
    private var stdout: [String] = []
    private var stderr: [String] = []
    private var browser: FakeBrowser!
    /// 每個動作打到的分頁，當下顯示什麼：`js <網址>`、`wait <網址>`、`navigate <網址>`、`close <網址>`。
    private var touched: [String] = []
    /// 每個動作用的是哪一種鎖：`mark`（`--url-endswith`）或 `position`（`--window`／`--tab-in-window`）。
    private var locks: [String] = []

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fetch-own-tab-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        if browser != nil { XCTAssertEqual(closes, [], "這個命令不關分頁") }
    }

    private var errText: String { stderr.joined(separator: "\n") }
    private var outText: String { stdout.joined(separator: "\n") }
    private var closes: [String] { browser.calls.filter { $0.hasPrefix("close") } }

    /// `tabs`：開分頁之前視窗裡的分頁。`insertAt`：新分頁插在哪（nil＝最後）。`keepCurrent`：開完之後目前的分頁還是使用者的。
    /// `onDocuments`：第 n 次 `documents` 之前改動分頁（第 1 次是檢查 profile，第 2 次是認新分頁，第 3 次起是輪詢）。
    /// `documentsAnswer`：回非 nil 就用它當 `documents` 的答案（多個視窗）。
    @discardableResult
    private func run(_ s: Scenario = Scenario(), tabs: [String] = [FulltextOwnTabTests.mine], insertAt: Int? = nil, keepCurrent: Bool = false,
                     resumeTab: Int? = nil, resumeOrigin: String? = nil, resumeStage: FulltextFetch.ResumeStage = .article,
                     keepsMark: Bool = false,
                     onJSArgs: (([String]) -> Void)? = nil,
                     onOpenArgs: (([String]) -> Void)? = nil,
                     onDocuments: ((Int, FakeBrowser) -> Void)? = nil,
                     onJS: ((String, FakeBrowser) -> Void)? = nil,
                     documentsFailsAt: Int? = nil,
                     onWait: (() -> Void)? = nil,
                     waitTimeouts: Int = 0,
                     documentsAnswer: ((FakeBrowser) -> String?)? = nil) -> Int32 {
        var scenario = s
        scenario.keepsMark = keepsMark   // 預設像 Elsevier：轉址丟掉記號，之後靠位置追蹤（這個檔多數測試測的就是它）
        browser = FakeBrowser(scenario)
        browser.tabs = tabs.map { ($0, "the user's tab") }
        browser.current = max(tabs.count, 1)
        stdout = []; stderr = []; touched = []; locks = []
        var n = 0
        var timeouts = waitTimeouts
        browser.hook = { [unowned self] args, fake in
            switch args[0] {
            case "documents":
                n += 1
                onDocuments?(n, fake)
                if n == documentsFailsAt { return SafariRun(status: 1, stderr: "Error: AppleScript timed out\n") }
                if let json = documentsAnswer?(fake) { return SafariRun(status: 0, stdout: json) }
                return nil
            case "open" where args.contains("--new-tab"):
                fake.openedNewTab(args.last!, at: insertAt)
                fake.current = keepCurrent ? 1 : (insertAt ?? fake.tabs.count - 1) + 1
                return SafariRun(status: 0)
            case "js", "wait", "open", "close":
                if args[0] == "open" { onOpenArgs?(args) }
                let verb = args[0] == "open" ? "navigate" : args[0]
                // 沒有指定分頁的 `open` 不導航任何分頁（safari-browser#233）：假瀏覽器照真的開新分頁，這裡不記成「打到」那個分頁
                if let k = fake.target(args), args[0] != "open" || FakeBrowser.openTargetFlags.contains(where: args.contains) {
                    self.touched.append("\(verb) \(FakeBrowser.unmarked(fake.tabs[k - 1].url))")
                    self.locks.append(args.contains("--url-endswith") ? "mark" : "position")
                }
                if args[0] == "js" { onJS?(args.last!, fake) }
                if args[0] == "wait" { onWait?() }
                if args[0] == "wait", timeouts > 0 { timeouts -= 1; return SafariRun(status: 1, stderr: "Error: timed out\n") }
                return nil
            default:
                return nil
            }
        }
        let fetcher = FulltextFetch(browser: browser, sleeper: { _ in }, now: { Self.now },
                                    out: { self.stdout.append($0) }, err: { self.stderr.append($0) })
        let ledger = root.appendingPathComponent("state/\(UUID().uuidString).jsonl").path
        return fetcher.run(.init(window: 5, landing: Self.landing, ledger: ledger, resumeTab: resumeTab, resumeOrigin: resumeOrigin, resumeStage: resumeStage))
    }

    private func assertNeverTouched(_ url: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(touched.contains { $0.hasSuffix(" " + url) }, "打到了不是我們開的分頁：\(touched)", file: file, line: line)
    }

    /// 兩個視窗的 `documents` 答案；與假瀏覽器的 `documents` 同一個形狀。
    private func documents(_ windows: [(Int, [String])]) -> String {
        var items: [PyJSON] = []
        for (window, urls) in windows {
            for (i, url) in urls.enumerated() {
                items.append(PyJSON.object([("window", .int(window)), ("index", .int(i + 1)), ("tab_in_window", .int(i + 1)), ("url", .string(url)),
                                            ("title", .string("t")), ("profile", .string("own")), ("is_current", .bool(i == 0)),
                                            ("blocking_dialog", PyJSON.object([("state", .string("unknown")), ("window_id", .int(window == 5 ? 9005 : 9000 + window))]))]))
            }
        }
        return PyJSON.array(items).dumps() + "\n"
    }

    // MARK: 認新分頁

    /// 事故本身：開完之後目前的分頁是使用者的。先前 `ownTab` 成了使用者的分頁、讀它的頁面、找不到連結就關它。
    func testTheCurrentTabBeingTheUsersDoesNotMakeItOurs() {
        var s = Scenario(); s.link = ""
        XCTAssertEqual(run(s, keepCurrent: true), 3, errText)
        assertNeverTouched(Self.mine)
        XCTAssertEqual(browser.tabs.map(\.url), [Self.mine, Self.finalURL], "兩個分頁都留著")
        XCTAssertTrue(errText.contains("no PDF link on https://pub.example/doi/10.1/x"), errText)
    }

    /// 新分頁不在最後一個位置時也認得出來：靠網址上的記號，不靠位置的慣例。
    func testTheNewTabIsFoundWhereverItWasInserted() {
        var s = Scenario(); s.link = ""
        XCTAssertEqual(run(s, tabs: [Self.mine, Self.other], insertAt: 1, keepCurrent: true), 3, errText)
        assertNeverTouched(Self.mine)
        assertNeverTouched(Self.other)
        XCTAssertTrue(touched.allSatisfy { $0.hasSuffix(" " + Self.finalURL) }, "\(touched)")
    }

    /// 開的當中使用者也開了一個分頁：記號認得出哪個是我們的（第二版比對清單，這裡會停）。
    func testAnotherNewTabWhileOpeningDoesNotConfuseIt() {
        let code = run(onDocuments: { n, fake in
            if n == 2 { fake.tabs.insert((Self.other, "the user's new tab"), at: 1) }
        })
        XCTAssertEqual(code, 7, errText)
        assertNeverTouched(Self.other)
        assertNeverTouched(Self.mine)
    }

    /// 開的當中使用者換了頁：不影響（第二版會停）。
    func testAnotherTabChangingWhileOpeningDoesNotMatter() {
        let code = run(tabs: [Self.mine, Self.other], onDocuments: { n, fake in
            if n == 2 { fake.tabs[0].url = "https://user.example/moved-on" }
        })
        XCTAssertEqual(code, 7, errText)
        assertNeverTouched("https://user.example/moved-on")
    }

    /// 新分頁開在最後、同時最後一個分頁換頁（第二輪 verify HIGH 1）：清單的差會把使用者的分頁當成新分頁，記號不會。
    func testTheLastTabChangingWhileOpeningIsNotMistakenForTheNewTab() {
        let blank = "https://user.example/start"
        let bank = "https://bank.example/account"
        let code = run(tabs: [Self.mine, blank], onDocuments: { n, fake in
            if n == 2 { fake.tabs[1].url = bank }
        })
        XCTAssertEqual(code, 7, errText)
        assertNeverTouched(bank)
        XCTAssertTrue(outText.contains("handover: pdf-shown window 5 tab 3"), outText)
    }

    /// 上一次留下的同一頁在最後，這次的新分頁開在它後面：認得出來。
    func testARerunNextToTheTabALastRunLeftIsFound() {
        XCTAssertEqual(run(tabs: [Self.mine, Self.finalURL]), 7, errText)
        XCTAssertTrue(outText.contains("handover: pdf-shown window 5 tab 3"), outText)
    }

    /// 新分頁與旁邊的分頁同一頁、而且不在最後：記號認得出來（第二版會停）。
    func testANewTabIdenticalToItsNeighbourIsFoundByTheMark() {
        XCTAssertEqual(run(tabs: [Self.finalURL, Self.mine], insertAt: 1), 7, errText)
        XCTAssertTrue(outText.contains("handover: pdf-shown window 5 tab 2"), outText)
        assertNeverTouched(Self.mine)
    }

    /// 使用者開著同一篇、但不相鄰，或我們的分頁還在 doi.org：認得出來，照常走。
    func testTheSamePageOpenElsewhereIsNotConfused() {
        XCTAssertEqual(run(tabs: [Self.finalURL, Self.mine]), 7, errText)
        assertNeverTouched(Self.mine)
        XCTAssertTrue(outText.contains("handover: pdf-shown window 5 tab 3"), outText)
    }

    // MARK: 認出來之後，分頁移動

    /// 左邊的分頁被關掉：同一個位置現在是使用者的另一個分頁。先前照讀。
    func testAClosedLeftTabStopsTheRunBeforeTheShiftedTabIsRead() {
        let code = run(tabs: [Self.mine, Self.other], insertAt: 1, onDocuments: { n, fake in
            if n == 3 { fake.tabs.remove(at: 0) }
        })
        XCTAssertEqual(code, 1, errText)
        assertNeverTouched(Self.other)
        XCTAssertTrue(errText.contains("tabs in window 5 changed"), errText)
    }

    /// 我們的分頁在最後（這是常態）而左邊的分頁被關掉：位置超出範圍，但我們的網址還在，那是移動，不是分頁不見了（不是起疑訊號）。
    func testAClosedLeftTabWhenOursIsLastIsAMoveNotAGoneTab() {
        let code = run(tabs: [Self.mine, Self.other], onDocuments: { n, fake in
            if n == 3 { fake.tabs.remove(at: 0) }
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertFalse(errText.contains("STOP THE WHOLE RUN"), errText)
        assertNeverTouched(Self.other)
    }

    /// 停下時只說我們自己的分頁，那個位置現在顯示什麼不印：那是使用者的分頁（可能帶憑證與隱私）。
    func testTheStopNamesOnlyOurOwnTab() {
        let code = run(tabs: [Self.mine, Self.other], insertAt: 1, onDocuments: { n, fake in
            if n == 4 { fake.tabs.remove(at: 0) }
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("pub.example/doi/10.1/x"), errText)
        XCTAssertFalse(errText.contains("user.example"), errText)
        XCTAssertFalse(outText.contains("user.example"), outText)
    }

    /// 別的視窗關了或使用者切換視窗，編號變了：視窗以 id 找回，跟著走，不停（第二版會停）。
    func testOurWindowChangingItsNumberIsFollowedByItsID() {
        let code = run(onDocuments: { n, fake in
            if n == 3 { fake.windowNumber = 4 }
        })
        XCTAssertEqual(code, 7, errText)
        XCTAssertTrue(outText.contains("handover: pdf-shown window 4 tab 2"), outText)
    }

    /// 同上，但導航之後的頁面也沒有記號（例如 PDF 經 Elsevier 的轉址）：只靠視窗 id 找回編號。
    func testOurWindowChangingItsNumberIsFollowedWithoutTheMark() {
        var s = Scenario(); s.afterNavURL = FulltextFetchPathTests.pdfLink
        let code = run(s, onDocuments: { n, fake in
            if n == 3 { fake.windowNumber = 4 }
        })
        XCTAssertEqual(code, 7, errText)
        XCTAssertTrue(outText.contains("handover: pdf-shown window 4 tab 2"), outText)
    }

    /// 頁面文字第一次讀不到、等了之後要再讀：等的時候分頁移動了就不讀。移動發生在兩次讀之間，中間沒有別的 `documents`。
    func testARetryOfThePageTextChecksTheTabAgain() {
        var s = Scenario(); s.pageJSFails = true
        var moved = false
        let code = run(s, tabs: [Self.mine, Self.other], insertAt: 1, onJS: { js, fake in
            guard !moved, js.contains("innerText.slice") else { return }
            moved = true
            fake.tabs.remove(at: 0)
        })
        XCTAssertEqual(code, 1, errText)
        assertNeverTouched(Self.other)
    }

    /// 比對的是上一眼，不是開分頁時的那一眼：我們的分頁換頁之後，右邊開分頁仍然不影響。
    func testARightTabOpeningAfterOurTabNavigatedDoesNotStop() {
        var looksAfterNavigation = 0
        let code = run(onDocuments: { _, fake in
            guard fake.navigated else { return }
            looksAfterNavigation += 1
            if looksAfterNavigation == 2 { fake.tabs.append((Self.other, "the user's new tab")) }
        })
        XCTAssertEqual(code, 7, errText)
        XCTAssertTrue(outText.contains("handover: pdf-shown window 5 tab 2"), outText)
        assertNeverTouched(Self.other)
    }

    /// 我們的分頁被關掉，之後又有分頁補上這個位置：不見了就停，不是「還沒落地」繼續等，否則補上來的分頁會被當成我們的（第一輪 verify 實際跑出來的形狀）。
    func testAClosedTabIsNotReplacedByWhateverTakesItsPosition() {
        let bank = "https://bank.example/account"
        let code = run(onDocuments: { n, fake in
            if n == 3 { fake.tabs.removeLast() }
            if n == 5 { fake.tabs.append((bank, "the user's new tab")) }
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertFalse(errText.contains("STOP THE WHOLE RUN"), "使用者關分頁不是網站起疑：\(errText)")
        assertNeverTouched(bank)
        assertNeverTouched(Self.mine)
    }

    /// 清單讀不到：不知道分頁在不在，不是可以繼續。第一輪 verify 跑出來的是沒有確認就導航。
    func testAListThatCannotBeReadStopsBeforeNavigating() {
        var lookAfterLink = 0
        for failAt in 3...9 {
            lookAfterLink = failAt
            XCTAssertEqual(run(documentsFailsAt: lookAfterLink), 1, "第 \(failAt) 次讀清單失敗：\(errText)")
            XCTAssertFalse(errText.contains("STOP THE WHOLE RUN"), errText)
            XCTAssertTrue(errText.contains("could not read Safari's tab list"), errText)
            XCTAssertEqual(browser.calls.filter { $0.hasPrefix("navigate") }, [], "沒有確認就不導航（第 \(failAt) 次）")
        }
    }

    /// 左邊多開一個分頁：同一個位置現在是使用者的新分頁。
    func testANewLeftTabStopsTheRunBeforeItIsRead() {
        let code = run(onDocuments: { n, fake in
            if n == 3 { fake.tabs.insert((Self.other, "the user's new tab"), at: 1) }
        })
        XCTAssertEqual(code, 1, errText)
        assertNeverTouched(Self.other)
    }

    /// 拖動分頁：位置上換成了另一個已經開著的分頁。
    func testDraggingTabsStopsTheRun() {
        let code = run(onDocuments: { n, fake in
            if n == 3 { fake.tabs.swapAt(0, 1) }
        })
        XCTAssertEqual(code, 1, errText)
        assertNeverTouched(Self.mine)
    }

    /// 使用者切到別的視窗：視窗編號是前後順序，同一個編號現在是另一個視窗。
    func testAnotherWindowTakingTheNumberStopsTheRun() {
        let code = run(onDocuments: { n, fake in
            if n == 3 {
                fake.windowID = 9006
                fake.tabs = [(Self.other, "another window"), ("https://user.example/other2", "another window")]
            }
        })
        XCTAssertEqual(code, 1, errText)
        assertNeverTouched(Self.other)
        assertNeverTouched("https://user.example/other2")
    }

    /// 同上，而且那個視窗在同一個位置開著同一頁（Codex 第一輪）：只看網址認不出來，id 認得出來。
    func testAnotherWindowShowingTheSamePageAtOurPositionStopsTheRun() {
        let code = run(onDocuments: { n, fake in
            if n == 3 {
                fake.windowID = 9006
                fake.tabs = [(Self.other, "another window"), (Self.finalURL, "the user's copy")]
            }
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertEqual(touched.filter { $0.hasPrefix("navigate") }, [])
        XCTAssertEqual(browser.navigated, false, "沒有導航使用者的分頁")
    }

    /// 開分頁的當下視窗就換了：新分頁開到別的視窗去，什麼都不讀。
    func testAnotherWindowTakingTheNumberWhileOpeningStopsTheRun() {
        let code = run(onDocuments: { n, fake in
            if n == 2 { fake.windowID = 9006 }
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertEqual(touched, [])
        XCTAssertTrue(errText.contains("went to another Safari window"), errText)
        XCTAssertFalse(errText.contains("may be left open"), "那個分頁不在我們的視窗：不說它留在這裡")
    }

    /// 新分頁剛出現時還回報不出網址：多看幾眼，看到記號就認得。
    func testTheMarkIsLookedForMoreThanOnce() {
        var opened = ""
        let code = run(keepsMark: true, onDocuments: { n, fake in
            if n == 2 { opened = fake.tabs[1].url; fake.tabs[1].url = "" }
            if n == 3 { fake.tabs[1].url = opened }
        })
        XCTAssertEqual(code, 7, errText)
    }

    /// 記號一直沒出現：什麼都不讀，訊息提醒有一個分頁可能留著。
    func testAMarkThatNeverShowsStopsAndMentionsTheTab() {
        let code = run(keepsMark: true, onDocuments: { n, fake in
            if n >= 2 { fake.pendingRedirect = nil; fake.tabs[fake.tabs.count - 1].url = "" }
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertEqual(touched, [])
        XCTAssertTrue(errText.contains("cannot find the tab just opened"), errText)
        XCTAssertTrue(errText.contains("may be left open"), errText)
    }

    /// 開分頁時就有兩個分頁帶著記號：分不開，什麼都不讀。
    func testTwoMarkedTabsAtOpeningStopTheRun() {
        let code = run(keepsMark: true, onDocuments: { n, fake in
            if n == 2 { fake.tabs.append(fake.tabs[1]) }
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertEqual(touched, [])
        XCTAssertTrue(errText.contains("more than one Safari tab shows this run's mark"), errText)
    }

    // MARK: 記號還在的時候

    /// 記號還在：指令都用記號鎖分頁（safari-browser 在同一段 AppleScript 裡重驗），導航也帶著記號。
    func testWhileTheMarkLastsTheCommandsUseIt() {
        var navigatedTo = ""
        let code = run(keepsMark: true, onJSArgs: nil, onOpenArgs: { args in navigatedTo = args.last! })
        XCTAssertEqual(code, 7, errText)
        XCTAssertFalse(locks.isEmpty)
        XCTAssertTrue(locks.allSatisfy { $0 == "mark" }, "\(locks)")
        XCTAssertTrue(navigatedTo.hasPrefix(FulltextFetchPathTests.pdfLink + "#akashic-"), navigatedTo)
    }

    /// 記號還在：左邊的分頁被關掉、我們的分頁移位，跟著走（位置追蹤會停）。
    func testWhileTheMarkLastsAMovedTabIsFollowed() {
        let code = run(tabs: [Self.mine, Self.other], keepsMark: true, onDocuments: { n, fake in
            if n == 4 { fake.tabs.remove(at: 0) }
        })
        XCTAssertEqual(code, 7, errText)
        XCTAssertTrue(outText.contains("handover: pdf-shown window 5 tab 2"), outText)
        assertNeverTouched(Self.mine)
        assertNeverTouched(Self.other)
    }

    /// **已知限制**（使用者 2026-11-04 接受的代價），**任何出版商都一樣**：有人在我們的分頁裡開了別的網頁（⌘L），記號就不見了，與頁面自己
    /// 換頁分不出來（這個測試的出版商保留記號，是 ⌘L 把它弄掉的；第四輪 verify 第 10 則）。
    /// fetch 改用位置追蹤，把那一頁當成「分頁到了別的主機」：讀它的長相、交給人（7 `left-site`）。**不導航**到 PDF 連結、不關分頁——
    /// 讀到的是那一頁的網址、標題與文字，這個測試把它釘住，日後若改成停下要一起改。
    func testTypingInOurTabIsAKnownLimitForEveryPublisher() {
        let bank = "https://bank.example/account"
        let code = run(keepsMark: true, onDocuments: { n, fake in
            if n == 5 { fake.tabs[1].url = bank }
        })
        XCTAssertEqual(code, 7, errText)
        XCTAssertTrue(outText.contains("handover: left-site"), outText)
        XCTAssertFalse(browser.navigated, "到了別的主機就不導航")
        XCTAssertTrue(closes.isEmpty)
    }

    /// 兩個分頁帶著記號（使用者複製了分頁）：分不開，停。
    func testADuplicatedTabStopsTheRun() {
        let code = run(keepsMark: true, onDocuments: { n, fake in
            if n == 4 { fake.tabs.append(fake.tabs[1]) }
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertFalse(browser.navigated)
    }

    /// 帶著記號的分頁被拖到別的視窗：不是我們的視窗，停。
    func testTheMarkedTabInAnotherWindowStopsTheRun() {
        let code = run(keepsMark: true, onDocuments: { n, fake in
            if n == 4 { fake.windowID = 9006 }
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertFalse(browser.navigated)
    }

    // MARK: 記號不見之後（Elsevier）

    /// ⌘W 關掉我們的分頁再 ⌘T（第二輪 verify HIGH 2）：同一個位置先變空白，就算對不上，不等它「落地」。
    func testCloseAndNewTabAtOurPositionStopsAtTheBlank() {
        let bank = "https://bank.example/account"
        let code = run(onDocuments: { n, fake in
            if n == 4 { fake.tabs[1].url = "" }
            if n == 5 { fake.tabs[1].url = bank }
        })
        XCTAssertEqual(code, 1, errText)
        assertNeverTouched(bank)
        XCTAssertFalse(errText.contains("STOP THE WHOLE RUN"), errText)
    }


    /// 回報的位置有缺號：陣列的第 2 個不是第 2 個分頁，不能照位置讀。
    func testAGapInTheReportedPositionsStopsTheRun() {
        var looks = 0
        let row = { (position: Int, url: String) in
            PyJSON.object([("window", .int(5)), ("index", .int(position)), ("tab_in_window", .int(position)), ("url", .string(url)), ("title", .string("t")),
                           ("profile", .string("own")), ("blocking_dialog", PyJSON.object([("window_id", .int(9005))]))])
        }
        let code = run(documentsAnswer: { _ in
            looks += 1
            return looks >= 3 ? PyJSON.array([row(1, Self.mine), row(3, Self.finalURL)]).dumps() + "\n" : nil
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertEqual(touched, [], "\(touched)")
    }

    /// safari-browser 沒有回報視窗 id：無從知道視窗換了沒，在開分頁之前就停。
    func testNoWindowIDStopsBeforeOpeningAnything() {
        let plain = PyJSON.array([PyJSON.object([("window", .int(5)), ("index", .int(1)), ("tab_in_window", .int(1)), ("url", .string(Self.mine)),
                                                 ("title", .string("t")), ("profile", .string("own"))])]).dumps() + "\n"
        let code = run(documentsAnswer: { _ in plain })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("window id"), errText)
        XCTAssertEqual(browser.calls, [], "沒有開分頁")
    }

    /// 同一個視窗裡整份清單換了（例如切換分頁群組）：同一個 id，但沒有一個分頁還在原來的網址。
    func testTheWholeListBeingReplacedStopsTheRun() {
        let code = run(tabs: [Self.mine, Self.other], onDocuments: { n, fake in
            if n == 3 { fake.tabs = [("https://g.example/1", "t"), ("https://g.example/2", "t"), ("https://g.example/3", "t")] }
        })
        XCTAssertEqual(code, 1, errText)
        assertNeverTouched("https://g.example/3")
    }

    /// 只有我們的分頁換頁，使用者在別的分頁工作：這是常態，不能停。
    func testTheUserWorkingInOtherTabsDoesNotStopTheRun() {
        let code = run(tabs: [Self.mine, Self.other], onDocuments: { n, fake in
            if n >= 3 { fake.tabs[0].url = "https://user.example/page-\(n)" }
        })
        XCTAssertEqual(code, 7, errText)
        assertNeverTouched(Self.mine)
        XCTAssertTrue(outText.contains("handover: pdf-shown window 5 tab 3"), outText)
    }

    /// 我們的分頁右邊開關分頁不影響位置：不能停。
    func testTabsOpeningAndClosingToTheRightDoNotStopTheRun() {
        var s = Scenario(); s.link = ""
        let code = run(s, insertAt: 0, onDocuments: { n, fake in
            if n == 4 { fake.tabs.append((Self.other, "the user's new tab")) }
            if n == 5 { fake.tabs.removeLast() }
        })
        XCTAssertEqual(code, 3, errText)
    }

    /// 我們的分頁從 doi.org 轉到使用者也開著的那一頁：那是轉址，不是移動。
    func testRedirectingToAPageTheUserAlsoHasOpenIsNotAMove() {
        var s = Scenario()
        s.landingFinal = Self.landing
        let code = run(s, tabs: [Self.finalURL, Self.mine], onDocuments: { n, fake in
            if n == 3 { fake.tabs[2].url = Self.finalURL }
        })
        XCTAssertEqual(code, 7, errText)
        XCTAssertTrue(outText.contains("handover: pdf-shown window 5 tab 3"), outText)
    }

    // MARK: 讀到答案的前後

    /// 讀完連結的下一眼分頁移動了：那個答案不用，不說「沒有連結」，也不照它導航。
    func testAMoveRightAfterReadingTheLinkDiscardsTheAnswer() {
        for link in ["", Scenario().link] {
            var s = Scenario(); s.link = link
            let code = run(s, tabs: [Self.mine, Self.other], insertAt: 1, onJS: { js, fake in
                if js.contains("'POST '") { fake.tabs.remove(at: 0) }
            })
            XCTAssertEqual(code, 1, errText)
            XCTAssertFalse(errText.contains("no PDF link"), errText)
            XCTAssertFalse(browser.navigated, "不照那個答案導航")
        }
    }

    /// 導航之前那一眼是最後一道：導航會蓋掉那個分頁的頁面。
    func testAMoveJustBeforeNavigatingStopsTheNavigation() {
        var looksAfterLink = 0
        let code = run(tabs: [Self.mine, Self.other], insertAt: 1, onDocuments: { _, fake in
            guard fake.injectedLinkScript else { return }
            looksAfterLink += 1
            if looksAfterLink == 2 { fake.tabs.remove(at: 0) }
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertFalse(browser.navigated, "沒有導航")
        assertNeverTouched(Self.other)
        XCTAssertTrue(errText.contains("attempt for today is already counted"), "帳本已經記了：\(errText)")
    }

    /// 等連結的 45 秒切成小段，段與段之間看分頁：等的當中分頁移動了就不再往那個位置送。
    func testAMoveWhileWaitingForTheLinkIsSeenBetweenSlices() {
        var waits = 0
        let code = run(tabs: [Self.mine, Self.other], insertAt: 1, onDocuments: { n, fake in
            if waits == 1, fake.tabs.count == 3 { fake.tabs.remove(at: 0) }
        }, onWait: { waits += 1 }, waitTimeouts: 2)
        XCTAssertEqual(code, 1, errText)
        XCTAssertEqual(waits, 1, "移動之後沒有再等")
        assertNeverTouched(Self.other)
    }

    /// 連結出現了就不再等。
    func testAWaitThatSucceedsEndsTheWait() {
        var waits = 0
        XCTAssertEqual(run(onWait: { waits += 1 }), 7, errText)
        XCTAssertEqual(waits, 1)
    }

    /// 連結一直沒出現：等滿所有的段就往下走（結束碼 3），不是卡住。
    func testALinkThatNeverAppearsEndsAfterAllTheSlices() {
        var s = Scenario(); s.link = ""
        var waits = 0
        let code = run(s, onWait: { waits += 1 }, waitTimeouts: 1000)
        XCTAssertEqual(code, 3, errText)
        XCTAssertEqual(waits, FulltextFetch.linkWaitSlices)
    }

    // MARK: 接續

    /// 接續的分頁讀它是人確認過的；找不到連結時同樣留著。
    func testAResumedTabIsLeftOpen() {
        var s = Scenario(); s.link = ""
        let code = run(s, tabs: [Self.mine, Self.finalURL], resumeTab: 2, resumeOrigin: "https://pub.example")
        XCTAssertEqual(code, 3, errText)
        XCTAssertEqual(browser.tabs.count, 2)
        XCTAssertTrue(errText.contains("left open"), errText)
    }

    /// 接續之後分頁移動也要停：接續的那一眼是追蹤的起點。
    func testAMoveAfterResumingStopsTheRun() {
        let code = run(tabs: [Self.mine, Self.finalURL, Self.other], resumeTab: 2, resumeOrigin: "https://pub.example", onDocuments: { n, fake in
            if n == 3 { fake.tabs.remove(at: 0) }
        })
        XCTAssertEqual(code, 1, errText)
        assertNeverTouched(Self.other)
    }

    // MARK: 兩個比較本身

    func testStillOurTab() {
        let a = "https://a.example/", b = "https://b.example/", c = "https://c.example/", o = "https://pub.example/x", p = "https://pub.example/x.pdf"
        func still(_ last: [String], _ pos: Int, _ now: [String]) -> Bool {
            FulltextFetch.stillOurTab(last: last, position: pos, now: now)
        }
        // 常態
        XCTAssertTrue(still([a, o], 2, [a, o]), "什麼都沒變")
        XCTAssertTrue(still([a, o], 2, [a, p]), "我們的分頁換頁")
        XCTAssertTrue(still([a, o], 2, ["https://a.example/next", o]), "使用者在別的分頁換頁")
        XCTAssertTrue(still([a, b, o], 3, ["https://a.example/1", "https://b.example/2", o]), "換了很多頁，我們的沒變")
        XCTAssertTrue(still([a, o], 2, [a, o, c]), "右邊開分頁")
        XCTAssertTrue(still([a, o, c], 2, [a, o]), "右邊關分頁")
        XCTAssertTrue(still([o, p], 2, [o, o]), "轉址到使用者也開著的那一頁：他的分頁還在原位")
        XCTAssertTrue(still([a, o], 2, [o, o]), "使用者在別的分頁打開同一頁：我們的位置沒變")
        XCTAssertTrue(still([o], 1, [p]), "視窗裡只有我們的分頁：只能當成換頁")
        XCTAssertTrue(still(["", o], 2, ["", p]), "視窗裡另一個是空白起始頁、我們換頁（Elsevier 丟掉記號的那一刻）：不停")
        // 移動
        XCTAssertFalse(still([a, o, c], 2, [o, c]), "左邊關分頁，位置上是右邊的分頁")
        XCTAssertFalse(still([a, o], 2, [a, b, o]), "左邊開分頁")
        XCTAssertFalse(still([a, b, o], 3, ["https://a.example/next", o, c]), "分頁數沒變，但別的分頁占了我們的網址的位置")
        XCTAssertFalse(still([a, o], 2, [o, a]), "拖動：互換")
        XCTAssertFalse(still([a, o, c], 2, [a, c, o]), "拖動：往右")
        XCTAssertFalse(still([a, b, o], 3, [o, a, b]), "拖動：移到最左")
        XCTAssertFalse(still([a, o], 2, [o, c]), "關左邊又開右邊：分頁數沒變，我們的網址在別的位置")
        XCTAssertFalse(still([a, b, o], 3, [a, o, c]), "同上，另一個分頁還在原位：我們的網址移走了就不是我們")
        XCTAssertFalse(still([a, o, c], 2, [a, c, b]), "我們的分頁關了、右邊的補上來、最後又開一個：分頁數沒變，我們的網址也不在了")
        XCTAssertFalse(still([a, o, c], 2, [b, o]), "分頁數變了而左邊也變了")
        XCTAssertFalse(still([a, o], 2, [a, p, c]), "分頁數變了而這個位置也變了")
        XCTAssertFalse(still([a, o], 2, [b, c]), "整份清單換了，沒有一個分頁留在原來的網址")
        XCTAssertFalse(still([a, b, o], 3, [c, "https://d.example/", p]), "同上，三個分頁")
        XCTAssertFalse(still([a, o], 3, [a, o]), "位置不存在")
        XCTAssertFalse(still([a, o], 2, [a, ""]), "顯示過網址的位置變成空白（⌘W 再 ⌘T）")
        XCTAssertFalse(still([o], 1, [""]), "同上，只有一個分頁")
        XCTAssertTrue(still(["", a, o], 3, ["", c, p]), "分頁群組切換、只有空白分頁相同：擋不住（已知限制；記號還在時以記號認，不會走到這一條）")
    }
}

extension FulltextFetchPathTests.FakeBrowser {
    /// 讀連結的那一段 JS 已經送過。
    var injectedLinkScript: Bool { injected.contains { $0.contains("'POST '") } }
}
