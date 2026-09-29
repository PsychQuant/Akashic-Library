import XCTest
@testable import AkashicSkillTools
@testable import AkashicStoreIO

/// #629 第二塊 R1 驗證對 `fulltext fetch` 的回歸釘：輸出目的地的處置、git 閘的 fail-closed、頁面連結的來源限制、base64 的容忍、
/// 暫存目錄權限、外部命令的逾時。沿用 `FulltextFetchPathTests` 的記憶體內假瀏覽器。
final class FulltextFetchHardeningTests: XCTestCase {
    private typealias Scenario = FulltextFetchPathTests.Scenario
    private typealias FakeBrowser = FulltextFetchPathTests.FakeBrowser

    private var root: URL!
    private var outDir: URL!
    private var stdout: [String] = []
    private var stderr: [String] = []
    private var browser: FakeBrowser!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fetch-hardening-\(UUID().uuidString)")
        outDir = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // 有些測試把目錄設成唯讀
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: outDir.path)
        try? FileManager.default.removeItem(at: root)
    }

    private var base: Scenario {
        var s = Scenario(); s.body = FulltextFetchPathTests.pdfBody
        s.meta = "{\"s\":200,\"c\":\"application/pdf\",\"l\":\(s.body.count),\"e\":null}"
        return s
    }
    private var errText: String { stderr.joined(separator: "\n") }

    @discardableResult
    private func run(_ scenario: Scenario, out: String? = nil, landing: String = FulltextFetchPathTests.landing,
                     git: FulltextFetch.GitRunner? = nil, onCall: ((String) -> Void)? = nil,
                     configure: (inout FulltextFetch.Options) -> Void = { _ in }) -> Int32 {
        browser = FakeBrowser(scenario)
        browser.onCall = onCall
        stdout = []; stderr = []
        var options = FulltextFetch.Options(window: 5, landing: landing, out: out ?? outDir.appendingPathComponent("w.pdf").path)
        configure(&options)
        let fetcher = git.map { g in
            FulltextFetch(browser: browser, sleeper: { _ in }, out: { self.stdout.append($0) }, err: { self.stderr.append($0) }, git: g)
        } ?? FulltextFetch(browser: browser, sleeper: { _ in }, out: { self.stdout.append($0) }, err: { self.stderr.append($0) })
        return fetcher.run(options)
    }

    private func write(_ text: String, to url: URL) throws { try Data(text.utf8).write(to: url) }

    // MARK: 輸出目的地：目錄、symlink、特殊檔具名拒絕，在碰瀏覽器之前

    /// 第一版對已存在的目的地先 `removeItem` 再 `moveItem`：`--out` 指著非空目錄時遞迴刪掉整個目錄。
    func testANonEmptyDirectoryAtOutIsRefusedAndKept() throws {
        let dir = outDir.appendingPathComponent("w.pdf")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try write("precious", to: dir.appendingPathComponent("keep.txt"))
        XCTAssertEqual(run(base), 1, errText)
        XCTAssertTrue(browser.calls.isEmpty, "一個瀏覽器呼叫都不該有：\(browser.calls)")
        XCTAssertTrue(errText.contains("directory"), errText)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("keep.txt"), encoding: .utf8), "precious", "目錄與裡面的檔原封不動")
    }

    func testADirectoryAtTheUnverifiedOrResponsePathIsRefusedBeforeTheBrowser() throws {
        for name in ["w.unverified.pdf", "w.response.txt"] {
            let dir = outDir.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try write("x", to: dir.appendingPathComponent("keep.txt"))
            XCTAssertEqual(run(base), 1, "\(name)：\(errText)")
            XCTAssertTrue(browser.calls.isEmpty, "\(name)：\(browser.calls)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("keep.txt").path), name)
            try FileManager.default.removeItem(at: dir)
        }
    }

    func testASymlinkAtOutIsRefusedAndItsTargetIsNotTouched() throws {
        let victim = root.appendingPathComponent("victim.txt")
        try write("victim", to: victim)
        try FileManager.default.createSymbolicLink(at: outDir.appendingPathComponent("w.pdf"), withDestinationURL: victim)
        XCTAssertEqual(run(base), 1, errText)
        XCTAssertTrue(browser.calls.isEmpty, "\(browser.calls)")
        XCTAssertTrue(errText.contains("symlink"), errText)
        XCTAssertEqual(try String(contentsOf: victim, encoding: .utf8), "victim")
    }

    // MARK: 覆寫普通檔：原子替換，失敗時原檔還在

    func testAnExistingRegularFileIsReplacedAtomically() throws {
        let target = outDir.appendingPathComponent("w.pdf")
        try write("old", to: target)
        XCTAssertEqual(run(base), 0, errText)
        XCTAssertEqual(try Data(contentsOf: target), FulltextFetchPathTests.pdfBody)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: outDir.path).filter { $0.hasSuffix(".tmp") }
        XCTAssertEqual(leftovers, [], "不留暫存檔")
    }

    /// 替換失敗（流程中途目錄變成唯讀）之後，原本的檔案還在：不是「先刪再搬、搬失敗時已毀」。
    func testAFailedReplaceKeepsTheOriginalFile() throws {
        let target = outDir.appendingPathComponent("w.pdf")
        try write("original", to: target)
        var locked = false
        let code = run(base, onCall: { [self] name in
            if name == "open", !locked {
                locked = true
                try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: outDir.path)
            }
        })
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: outDir.path)
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("cannot write"), errText)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "original", "原檔要還在")
    }

    /// 目的地在檢查之後變成目錄：`rename` 不會遞迴刪它，目錄與裡面的東西都在。
    func testADestinationThatBecomesADirectoryMidRunIsNotDeleted() throws {
        let target = outDir.appendingPathComponent("w.pdf")
        var swapped = false
        let code = run(base, onCall: { [self] name in
            if name == "close", !swapped {   // 分頁關掉、內容驗證完之後才會落地——close 之前改
                swapped = true
                try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                try? write("precious", to: target.appendingPathComponent("keep.txt"))
            }
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("keep.txt"), encoding: .utf8), "precious")
    }

    /// 寫入中途失敗（暫存檔已建立、寫不下去）：原檔還在、不留暫存檔。用 `RLIMIT_FSIZE` 讓 `write(2)` 回 `EFBIG`——
    /// 先前的「先刪再搬」在這種失敗發生時原檔已經被刪。
    func testAWriteFailureAfterTheTempFileWasCreatedKeepsTheOriginalFile() throws {
        let target = outDir.appendingPathComponent("w.pdf")
        try write("original", to: target)
        signal(SIGXFSZ, SIG_IGN)
        var previous = rlimit()
        XCTAssertEqual(getrlimit(RLIMIT_FSIZE, &previous), 0)
        var small = rlimit(rlim_cur: 16, rlim_max: previous.rlim_max)
        XCTAssertEqual(setrlimit(RLIMIT_FSIZE, &small), 0)
        var thrown: Error?
        do { try OutputFile.replace(path: target.path, with: Data(repeating: 0x41, count: 4096)) } catch { thrown = error }
        setrlimit(RLIMIT_FSIZE, &previous)
        signal(SIGXFSZ, SIG_DFL)
        XCTAssertNotNil(thrown, "寫不下去要丟錯，不是靜默成功")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "original")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outDir.path).filter { $0.hasSuffix(".tmp") }, [], "不留暫存檔")
    }

    // MARK: 網址：只收 https

    func testLandingAndPrimeMustBeHTTPS() {
        for bad in ["http://doi.org/10.1/x", "file:///etc/passwd", "javascript:alert(1)", "ftp://x/y"] {
            XCTAssertEqual(run(base, landing: bad), 1, bad)
            XCTAssertTrue(browser.calls.isEmpty, "\(bad)：\(browser.calls)")
            XCTAssertTrue(errText.contains("--landing must be an https"), errText)
        }
        XCTAssertEqual(run(base, configure: { $0.prime = "http://pub.example/x.pdf" }), 1)
        XCTAssertTrue(browser.calls.isEmpty, "\(browser.calls)")
        XCTAssertTrue(errText.contains("--prime must be an https"), errText)
    }

    // MARK: 頁面連結的來源：帶 credentials 的 fetch 不打到頁面選的別的站

    func testAPageLinkThatPointsOffSiteIsRefusedNotFetched() {
        var s = base; s.link = "GET https://evil.example/steal"
        XCTAssertEqual(run(s), 1, errText)
        XCTAssertTrue(errText.contains("off-site"), errText)
        XCTAssertFalse(browser.calls.contains { $0.contains("evil.example") })
        XCTAssertNil(browser.scratchMode, "沒有走到讀回本文那一步（fetch 根本沒發）")
    }

    func testNonHTTPSchemesAndJavascriptLinksAreOffSite() {
        for link in ["GET javascript:fetch('x')", "GET data:text/plain,x", "GET blob:https://pub.example/uuid"] {
            var s = base; s.link = link
            XCTAssertEqual(run(s), 1, link)
            XCTAssertTrue(errText.contains("off-site"), "\(link)：\(errText)")
        }
    }

    func testSameSiteAndRelativeLinksAreAllowed() {
        var s = base; s.link = "GET /doi/pdf/10.1/x"
        XCTAssertEqual(run(s), 0, errText)
        s.link = "GET //pub.example/doi/pdf/10.1/x"
        XCTAssertEqual(run(s), 0, errText)
        s.link = "GET https://PUB.example/doi/pdf/10.1/x"
        XCTAssertEqual(run(s), 0, errText)
    }

    func testFetchTargetOriginResolution() {
        XCTAssertEqual(FulltextFetch.fetchTargetOrigin("/a/b.pdf", page: "https://pub.example/x"), "https://pub.example")
        XCTAssertEqual(FulltextFetch.fetchTargetOrigin("//cdn.example/a.pdf", page: "https://pub.example/x"), "https://cdn.example")
        XCTAssertEqual(FulltextFetch.fetchTargetOrigin("https://cdn.example/a.pdf", page: "https://pub.example/x"), "https://cdn.example")
        XCTAssertNil(FulltextFetch.fetchTargetOrigin("javascript:1", page: "https://pub.example/x"))
        XCTAssertNil(FulltextFetch.fetchTargetOrigin("data:text/plain,x", page: "https://pub.example/x"))
    }

    // MARK: base64、暫存目錄權限

    /// 舊實作的 `base64 -D` 容忍任意位置的換行；`Data(base64Encoded:)` 預設不容忍。
    func testBase64FoldedIntoLinesStillDecodes() {
        var s = base
        s.body = Data("%PDF-1.4\n".utf8) + Data(repeating: 0x41, count: 300)
        s.meta = "{\"s\":200,\"c\":\"application/pdf\",\"l\":\(s.body.count),\"e\":null}"
        s.foldBase64 = true
        XCTAssertEqual(run(s), 0, errText)
        XCTAssertEqual(try? Data(contentsOf: outDir.appendingPathComponent("w.pdf")), s.body)
    }

    /// 只容忍換行；其他非 base64 字元照嚴格解碼失敗（`.ignoreUnknownCharacters` 會把一段錯誤頁文字「解」成垃圾位元組）。
    func testNonBase64GarbageStillFailsToDecode() {
        var s = base
        s.base64Override = "<html>Access to this page is @@ not base64 ##</html>"
        XCTAssertEqual(run(s), 1, errText)
        XCTAssertTrue(errText.contains("base64 decode failed"), errText)
    }

    func testTheScratchDirectoryIsPrivate() {
        XCTAssertEqual(run(base), 0, errText)
        XCTAssertEqual(browser.scratchMode, 0o700, "暫存目錄裡有第三方全文：0700（舊 mktemp -d 同）")
    }

    // MARK: git 閘：git 答不出來時一律拒絕

    private func initRepo(_ name: String) throws -> URL {
        let repo = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        XCTAssertEqual(GitFixture.run(["init", "-q"], in: repo), 0)
        return repo
    }

    private func fetch(into dir: URL, git: FulltextFetch.GitRunner? = nil) -> Int32 {
        run(base, out: dir.appendingPathComponent("w.pdf").path, git: git)
    }

    /// 輸出目錄的祖先有 `.git`，而 git 執行不起來：不能當成「不在工作樹」而放行。
    func testGitThatCannotRunRefusesWhenTheDirectoryIsInsideARepo() throws {
        let repo = try initRepo("repo-nogit")
        XCTAssertEqual(fetch(into: repo, git: { _, _ in nil }), 1, errText)
        XCTAssertTrue(browser.calls.isEmpty, "\(browser.calls)")
        XCTAssertTrue(errText.contains("git cannot be run") && errText.contains("working tree"), errText)
    }

    /// `rev-parse` 非零（safe.directory 的 dubious ownership、`.git` 壞了都是 128）：無從確認，拒絕。
    func testARevParseFailureRefusesWhenTheDirectoryIsInsideARepo() throws {
        let repo = try initRepo("repo-128")
        XCTAssertEqual(fetch(into: repo, git: { _, _ in (128, "") }), 1, errText)
        XCTAssertTrue(browser.calls.isEmpty, "\(browser.calls)")
        XCTAssertTrue(errText.contains("could not confirm") && errText.contains("128"), errText)
    }

    func testARevParseAnswerOtherThanTrueRefuses() throws {
        let repo = try initRepo("repo-false")
        XCTAssertEqual(fetch(into: repo, git: { _, _ in (0, "false\n") }), 1, errText)
        XCTAssertTrue(browser.calls.isEmpty, "\(browser.calls)")
    }

    /// `check-ignore` 只有 0（已忽略）與 1（沒忽略）是答案；128 是「答不出來」。
    func testACheckIgnoreErrorRefuses() throws {
        let repo = try initRepo("repo-checkignore")
        let code = fetch(into: repo, git: { args, _ in args.first == "rev-parse" ? (0, "true\n") : (128, "") })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(browser.calls.isEmpty, "\(browser.calls)")
        XCTAssertTrue(errText.contains("check-ignore exit 128"), errText)
    }

    /// 輸出目錄的祖先都沒有 `.git`：不需要 git 回答，git 起不來也不擋。
    func testNoRepoAboveMeansGitIsNotNeeded() {
        XCTAssertEqual(run(base, git: { _, _ in nil }), 0, errText)
    }

    /// `.git` 是指向不存在 gitdir 的檔案（被清掉主 repo 的 worktree 就是這樣）：真的 git 回 128，閘拒絕。
    func testADanglingGitFileRefuses() throws {
        let repo = root.appendingPathComponent("dangling")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try write("gitdir: /nonexistent/gitdir\n", to: repo.appendingPathComponent(".git"))
        XCTAssertEqual(fetch(into: repo), 1, errText)
        XCTAssertTrue(browser.calls.isEmpty, "\(browser.calls)")
        XCTAssertTrue(errText.contains("working tree"), errText)
    }

    /// PATH 前面的 `git` shim 不能替閘作答（#585）：shim 對什麼都答 0，若閘走 PATH，`check-ignore` 就是「已忽略」而放行。
    func testAGitShimEarlierInPathCannotAnswerForTheGate() throws {
        let shimDir = root.appendingPathComponent("shim")
        try FileManager.default.createDirectory(at: shimDir, withIntermediateDirectories: true)
        let shim = shimDir.appendingPathComponent("git")
        try write("#!/bin/sh\nexit 0\n", to: shim)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
        let saved = ProcessInfo.processInfo.environment["PATH"] ?? ""
        setenv("PATH", shimDir.path + ":" + saved, 1)
        defer { setenv("PATH", saved, 1) }
        let repo = try initRepo("repo-shim")   // 沒有 .gitignore：真的 git 答「沒忽略」
        XCTAssertEqual(fetch(into: repo), 1, errText)
        XCTAssertTrue(browser.calls.isEmpty, "\(browser.calls)")
        XCTAssertTrue(errText.contains("does not ignore it"), errText)
    }

    /// 目標 repo 的 `core.fsmonitor` 在 `check-ignore` 之類的命令裡會被執行（R1 verify 實測）；閘的 git 帶 `-c core.fsmonitor=false`。
    func testTheTargetReposFsmonitorHookIsNotExecutedByTheGate() throws {
        let repo = try initRepo("repo-fsmonitor")
        let marker = root.appendingPathComponent("fsmonitor-ran")
        let hook = repo.appendingPathComponent("hook.sh")
        try write("#!/bin/sh\ntouch '\(marker.path)'\nexit 0\n", to: hook)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        XCTAssertEqual(GitFixture.run(["config", "core.fsmonitor", hook.path], in: repo), 0)
        XCTAssertEqual(fetch(into: repo), 1, "repo 沒忽略輸出檔：\(errText)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "閘不得執行目標 repo 設定的命令")
    }

    // MARK: ToolRunner 的逾時（poppler 對第三方 PDF）

    func testAToolThatNeverFinishesIsKilledAtTheTimeout() {
        let started = Date()
        XCTAssertThrowsError(try ToolRunner.run(["sleep", "30"], timeout: 0.5)) {
            XCTAssertTrue(($0 as? SkillToolError)?.errorDescription?.contains("逾時") == true, "\($0)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 10, "逾時之後要真的結束，不是等它自己跑完")
    }

    func testAFastToolIsUnaffectedByTheTimeout() throws {
        let r = try ToolRunner.run(["echo", "hi"], timeout: 30)
        XCTAssertEqual(r.status, 0)
        XCTAssertEqual(String(decoding: r.stdout, as: UTF8.self), "hi\n")
    }
}
