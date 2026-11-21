import XCTest
@testable import AkashicSkillTools
@testable import AkashicStoreIO

/// #772：`fetch` 把每一個以位置認分頁的動作鎖在開頭選定的視窗（`--window-id`，safari-browser v2.9.0），不再因為別的 profile 的視窗而停
/// （使用者 2026-11-19 09:24「我是覺得在別的是窗沒差，只要鎖定好固定視窗就好」、09:25「也不一定要在個人，只要固定視窗就好了嗎」）。
///
/// 假瀏覽器照真的 safari-browser 解析 `--window-id`：id 不對就沒有分頁符合，不退回前景視窗（`FakeBrowser.target`）。
final class FulltextWindowLockTests: XCTestCase {
    typealias FakeBrowser = FulltextFetchPathTests.FakeBrowser
    typealias Scenario = FulltextFetchPathTests.Scenario

    static let mark = "akashic-0123456789abcdef"

    private var root: URL!
    private var stdout: [String] = []
    private var stderr: [String] = []
    private var browser: FakeBrowser!
    /// 送給 safari-browser 的每一條命令（`documents` 除外）
    private var sent: [[String]] = []
    private var errText: String { stderr.joined(separator: "\n") }
    private var outText: String { stdout.joined(separator: "\n") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fetch-window-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        XCTAssertFalse(browser?.calls.contains { $0.hasPrefix("close") } ?? false, "fetch 不關任何分頁：\(browser?.calls ?? [])")
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func fetch(_ s: Scenario = Scenario(), configure: (inout FulltextFetch.Options) -> Void = { _ in },
                       hook: ((_ args: [String], _ fake: FakeBrowser) -> SafariRun?)? = nil) -> Int32 {
        browser = FakeBrowser(s)
        stdout = []; stderr = []; sent = []
        browser.hook = { [unowned self] args, fake in
            if args[0] != "documents" { self.sent.append(args) }
            return hook?(args, fake)
        }
        var o = FulltextFetch.Options(window: 5, landing: FulltextFetchPathTests.landing, ledger: root.appendingPathComponent("ledger.jsonl").path)
        configure(&o)
        let fetcher = FulltextFetch(browser: browser, sleeper: { _ in }, now: { FulltextFetchPathTests.now },
                                    out: { self.stdout.append($0) }, err: { self.stderr.append($0) }, mark: Self.mark)
        return fetcher.run(o)
    }

    /// 一列 `documents --json`；`windowIDKey: false` 是 v2.9.0 以前的形狀（只有 `blocking_dialog.window_id`）。
    private static func row(window: Int, tab: Int, url: String, profile: String?, id: Int, windowIDKey: Bool = true) -> PyJSON {
        var fields: [(String, PyJSON)] = [("window", .int(window)), ("index", .int(tab)), ("tab_in_window", .int(tab)), ("url", .string(url)),
                                          ("title", .string("t")), ("profile", profile.map { .string($0) } ?? .null), ("is_current", .bool(false))]
        if windowIDKey { fields.append(("window_id", .int(id))) }
        fields.append(("blocking_dialog", PyJSON.object([("state", .string("unknown")), ("window_id", .int(id))])))
        return PyJSON.object(fields)
    }

    // MARK: 每一個以位置認分頁的動作都帶 --window-id

    // spec-example: fulltext-window-lock / Position locks carry the window id
    func testPositionLocksCarryTheWindowID() {
        var s = Scenario(); s.keepsMark = false
        XCTAssertEqual(fetch(s), 7, errText)
        let positional = sent.filter { $0.contains("--tab-in-window") }
        XCTAssertFalse(positional.isEmpty, "記號不在時應該有位置鎖：\(sent)")
        for args in positional {
            XCTAssertEqual(args.firstIndex(of: "--window-id").map { args[$0 + 1] }, "9005", "\(args)")
        }
        XCTAssertFalse(sent.contains { $0.contains("--window") }, "不再送 --window N：\(sent)")
    }

    /// 一眼與命令之間，使用者把另一個視窗拉到前面：我們的視窗從 5 變成 6。先前的 `--window 5` 這一下就指到別的視窗（#735 的形狀）；`--window-id`
    /// 不跟著前後順序變，命令照樣到我們的視窗。
    // spec-example: fulltext-window-lock / A window raised between a look and a command does not change the target
    func testAWindowRaisedBetweenALookAndACommandDoesNotChangeTheTarget() {
        var s = Scenario(); s.keepsMark = false
        var raisedAt: [String]?
        let code = fetch(s, hook: { args, fake in
            if raisedAt == nil, args[0] == "js", args.contains("--tab-in-window") {
                fake.windowNumber = 6
                raisedAt = args
            }
            return nil
        })
        XCTAssertEqual(code, 7, errText)
        let args = raisedAt ?? []
        XCTAssertEqual(args.firstIndex(of: "--window-id").map { args[$0 + 1] }, "9005", "\(args)")
        XCTAssertFalse(args.contains("--window"), "\(args)")
    }

    // MARK: profile 只用來選視窗

    // spec-example: fulltext-window-lock / A window of another profile is refused when a profile is expected
    func testAWindowOfAnotherProfileIsRefusedWhenAProfileIsExpected() {
        XCTAssertEqual(fetch(configure: { $0.expectProfile = "someone-else" }), 1, errText)
        XCTAssertTrue(errText.contains("refusing to touch it"), errText)
        XCTAssertFalse(sent.contains { $0.first == "open" }, "什麼都沒開：\(sent)")
    }

    /// 視窗的列讀不出 profile、也沒有給 `--expect-profile`：照樣用這個視窗。記號鎖要 profile，所以一律用位置鎖。
    // spec-example: fulltext-window-lock / A window whose profile cannot be read is used when no profile is expected
    func testAWindowWhoseProfileCannotBeReadIsUsedWhenNoProfileIsExpected() {
        let code = fetch(hook: { args, fake in
            guard args[0] == "documents" else { return nil }
            if fake.tabs.count > 1, fake.tabs[1].url.hasPrefix("https://doi.org/") {
                fake.tabs[1].url = FulltextFetchPathTests.finalURL + "#" + Self.mark
            }
            let rows = fake.tabs.enumerated().map { i, t in Self.row(window: 5, tab: i + 1, url: t.url, profile: nil, id: 9005) }
            return SafariRun(status: 0, stdout: PyJSON.array(rows).dumps() + "\n")
        })
        XCTAssertEqual(code, 7, errText)
        XCTAssertFalse(sent.contains { $0.contains("--profile") }, "\(sent)")
    }

    // MARK: safari-browser 太舊

    // spec-example: fulltext-window-lock / Rows without window_id stop the run before anything is opened
    func testRowsWithoutWindowIDStopTheRunBeforeAnythingIsOpened() {
        let code = fetch(hook: { args, fake in
            guard args[0] == "documents" else { return nil }
            let rows = fake.tabs.enumerated().map { i, t in Self.row(window: 5, tab: i + 1, url: t.url, profile: "own", id: 9005, windowIDKey: false) }
            return SafariRun(status: 0, stdout: PyJSON.array(rows).dumps() + "\n")
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("2.9.0"), errText)
        XCTAssertFalse(sent.contains { $0.first == "open" }, "什麼都沒開：\(sent)")
    }

    // MARK: own-tab 一行

    // spec-example: fulltext-window-lock / The own-tab line carries the window id and the mark
    func testTheOwnTabLineCarriesTheWindowIDAndTheMark() {
        XCTAssertEqual(fetch(), 7, errText)
        XCTAssertTrue(outText.contains("own-tab: window-id 9005 tab 2 mark \(Self.mark)"), outText)
    }

    /// 接續時分頁被拒（顯示別的網頁）：`own-tab:` 不印——那個位置可能是使用者自己的分頁，skill 不能拿它去鎖。
    func testARefusedResumePrintsNoOwnTabLine() {
        let code = fetch(configure: { $0.resumeTab = 1; $0.resumeOrigin = "https://pub.example" })
        XCTAssertEqual(code, 1, errText)
        XCTAssertFalse(outText.contains("own-tab:"), outText)
    }
}
