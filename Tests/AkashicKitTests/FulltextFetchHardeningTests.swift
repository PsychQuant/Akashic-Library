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
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: outDir.path).filter { $0.hasPrefix(".") }
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
        // 行程層級的狀態：只在這幾行之間改，結束時還原成**原本的**處置與上限（R2 verify 第 41 則：先前還原成 SIG_DFL）。
        // 測試是依序跑的；平行執行（`--parallel`）時同一段時間裡別的寫入會碰到 EFBIG——這支測試因此不適合平行跑。
        let previousHandler = signal(SIGXFSZ, SIG_IGN)
        var previous = rlimit()
        XCTAssertEqual(getrlimit(RLIMIT_FSIZE, &previous), 0)
        var small = rlimit(rlim_cur: 16, rlim_max: previous.rlim_max)
        XCTAssertEqual(setrlimit(RLIMIT_FSIZE, &small), 0)
        var thrown: Error?
        do { try OutputFile.replace(path: target.path, with: Data(repeating: 0x41, count: 4096)) } catch { thrown = error }
        setrlimit(RLIMIT_FSIZE, &previous)
        signal(SIGXFSZ, previousHandler)
        XCTAssertNotNil(thrown, "寫不下去要丟錯，不是靜默成功")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "original")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outDir.path).filter { $0.hasPrefix(".") }, [], "不留暫存檔")
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

    /// 兩個網址都在使用者已登入的 profile 裡開：主機要是公開的網域名稱——web-access.md〈插值前先驗形狀〉「完整網址」一列的主機部分與禁用字元
    /// （R2 verify 第 34 則：先前只查 `https://` 前綴）。路徑的字元集不套那一列：SICI 式 DOI 的 `<`、`>` 在 doi.org 網址裡是合法的。
    func testLandingAndPrimeMustHaveAPublicHostName() {
        let bad = ["https://localhost/x", "https://127.0.0.1/x", "https://[::1]/x", "https://router.local/x", "https://svc.corp/x", "https://intranet/x",
                   "https://user@doi.org/10.1/x", "https://doi.org:8443/10.1/x", "https://doi.org./10.1/x", "https://doi.org/10.1/../x",
                   "https://doi.org/10.1/%2e%2E/x", "https://doi.org/10.1/x#frag", "https://doi.org/10.1/x\"y", "https://doi.org/10.1/x y",
                   "https://doi.org/10.1/x$(id)", #"https://doi.org/10.1/x\y"#, "https://1.2.3.4/x"]
        for url in bad {
            XCTAssertEqual(run(base, landing: url), 1, url)
            XCTAssertTrue(browser.calls.isEmpty, "\(url)：\(browser.calls)")
            XCTAssertTrue(errText.contains("--landing must be an https"), "\(url)：\(errText)")
        }
        XCTAssertEqual(run(base, configure: { $0.prime = "https://127.0.0.1/x.pdf" }), 1)
        XCTAssertTrue(errText.contains("--prime must be an https"), errText)
        for url in ["https://doi.org/10.1002/(sici)1097-0258(19980430)17:8<873::aid-sim777>3.0.co;2-B", "https://dx.doi.org/10.1/x", "https://DOI.org/10.1/a?b=c"] {
            XCTAssertEqual(run(base, landing: url), 0, "\(url)：\(errText)")
        }
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

    /// 同站的絕對網址放行，而且**發出去的就是驗過的那一串**（`fetch.js` 裡的字串字面值）。
    func testSameSiteAbsoluteLinksAreAllowedAndTheValidatedStringIsTheFetchedString() {
        for link in ["https://pub.example/doi/pdf/10.1/x", "https://PUB.example/doi/pdf/10.1/x", "https://pub.example/a.pdf?x=1#frag"] {
            var s = base; s.link = "GET " + link
            XCTAssertEqual(run(s), 0, "\(link)：\(errText)")
            XCTAssertTrue(browser.fetchSource?.contains("fetch(\(PyJSON.javaScriptLiteral(link)),") == true, "\(link)：\(browser.fetchSource ?? "<no fetch>")")
        }
    }

    /// #629 R2 verify 第 0／9／12／20 則：Swift 側的檢查曾用 `urlsplit` 式的解析，瀏覽器的 `fetch` 用 WHATWG——反斜線當斜線、`https:` 後面
    /// 多出來的斜線當主機分隔。下面每一串在舊檢查裡都判成「同站」，瀏覽器卻打到 `evil.example`（驗證席以 Node 的 `new URL(u, 頁面)` 實測）。
    /// 現在 `linkJS` 在頁面裡把連結解析成絕對網址，Swift 只收「`https://` 開頭、沒有反斜線、空白或控制字元」的字串再比 origin；
    /// 相對或協定相對的形狀只會在瀏覽器解析失敗時原樣回來，一律拒絕。
    func testBackslashSlashRunAndRelativeLinksAreRefusedNotFetched() {
        let bad = [
            #"\\evil.example/x.pdf"#, #"\evil.example/x.pdf"#, #"/\evil.example/x.pdf"#, #"\/evil.example/x.pdf"#,
            "///evil.example/x.pdf", "////evil.example/x.pdf", "  //evil.example/x.pdf", "//pub.example/doi/pdf/10.1/x", "/doi/pdf/10.1/x",
            "https:///evil.example/x.pdf", #"https:\\evil.example/x.pdf"#, #"https://\evil.example/x.pdf"#, #"https:/\evil.example/x.pdf"#,
            #"https://pub.example\@evil.example/x.pdf"#, "https://pub.example@evil.example/x.pdf", "https://pub.example:443@evil.example/x.pdf",
            "https://pub.example/x\t.pdf", "https://pub.example/x .pdf", "http://pub.example/x.pdf",
        ]
        for link in bad {
            var s = base; s.link = "GET " + link
            XCTAssertEqual(run(s), 1, "\(link)：\(errText)")
            XCTAssertTrue(errText.contains("refusing a credentialed fetch"), "\(link)：\(errText)")
            XCTAssertNil(browser.fetchSource, "\(link)：fetch 不該發出")
        }
    }

    /// 頁面有惡意的 `<base href>` 時，`linkJS` 以 `document.baseURI` 解析出的是別站的絕對網址——這是它交回來的樣子，要被拒。
    func testALinkResolvedAgainstAHostileBaseIsRefused() {
        var s = base; s.link = "GET https://evil.example/doi/pdf/10.1/x"
        XCTAssertEqual(run(s), 1, errText)
        XCTAssertNil(browser.fetchSource)
    }

    /// `citation_pdf_url` 的 `content` 是原始字串（不像 `a.href`、`form.action` 已被瀏覽器解析）：要在頁面裡用 WHATWG 解析成絕對網址再交回，
    /// 解析失敗才原樣交回（Swift 側一律拒絕非絕對的形狀）。
    func testTheMetaLinkIsResolvedInThePage() {
        XCTAssertTrue(FulltextFetch.linkJS.contains("if (m && m.content) { try { return 'GET ' + new URL(m.content, document.baseURI).href; } catch (e) { return 'GET ' + m.content; } }\n"), FulltextFetch.linkJS)
        XCTAssertFalse(FulltextFetch.linkJS.contains("if (m && m.content) return 'GET ' + m.content;"))
    }

    func testFetchTargetOrigin() {
        XCTAssertEqual(FulltextFetch.fetchTargetOrigin("https://pub.example/a/b.pdf"), "https://pub.example")
        XCTAssertEqual(FulltextFetch.fetchTargetOrigin("https://cdn.example/a.pdf"), "https://cdn.example")
        XCTAssertEqual(FulltextFetch.fetchTargetOrigin("HTTPS://Pub.Example/a.pdf"), "https://pub.example")
        for u in ["/a/b.pdf", "//cdn.example/a.pdf", "javascript:1", "data:text/plain,x", "blob:https://pub.example/u", "http://pub.example/a.pdf",
                  #"\\evil.example/a"#, "///evil.example/a", "https:///evil.example/a", #"https://pub.example\x"#, "https://pub.example/a b", "https://"] {
            XCTAssertNil(FulltextFetch.fetchTargetOrigin(u), u)
        }
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

    // MARK: 原子替換的暫存檔也在 git 閘裡（R2 verify 第 2／33 則）

    /// 暫存檔名保留目的地的整個檔名當尾巴：以副檔名忽略的規則（`*.pdf`、`*.response.txt`）同樣蓋得到它。
    func testTheTempNameKeepsTheDestinationNameAsItsSuffix() {
        XCTAssertEqual(OutputFile.tempPath(for: "/a/b/w.pdf", token: "T0K"), "/a/b/.T0K.w.pdf")
        XCTAssertEqual(OutputFile.tempPath(for: "/a/b/w.response.txt", token: "T0K"), "/a/b/.T0K.w.response.txt")
        XCTAssertEqual(OutputFile.tempPath(for: "w.pdf", token: "T0K"), "./.T0K.w.pdf")
    }

    /// 只以 `*.pdf`、`*.response.txt` 忽略輸出的樹：真的 git 也把三個暫存檔名判成已忽略——寫到一半被中斷，留下的暫存檔也不會被 `git add -A` 收進去。
    func testSuffixIgnoreRulesAlsoCoverTheTempNames() throws {
        let repo = try initRepo("repo-suffix")
        try write("*.pdf\n*.response.txt\n", to: repo.appendingPathComponent(".gitignore"))
        for name in ["w.pdf", "w.unverified.pdf", "w.response.txt"] {
            let temp = OutputFile.tempPath(for: repo.appendingPathComponent(name).path, token: UUID().uuidString)
            XCTAssertEqual(GitFixture.run(["check-ignore", "-q", "--", temp], in: repo), 0, temp)
        }
        XCTAssertEqual(fetch(into: repo), 0, errText)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: repo.path).filter { $0.hasPrefix(".") && $0 != ".git" && $0 != ".gitignore" }, [], "不留暫存檔")
    }

    /// 只忽略三個最終檔名（逐字）的樹：暫存檔名沒被忽略，閘在碰瀏覽器之前就拒絕、說出是暫存檔。
    func testATreeThatIgnoresOnlyTheFinalNamesIsRefusedBecauseOfTheTempName() throws {
        let repo = try initRepo("repo-exact")
        try write("/w.pdf\n/w.unverified.pdf\n/w.response.txt\n", to: repo.appendingPathComponent(".gitignore"))
        XCTAssertEqual(fetch(into: repo), 1, errText)
        XCTAssertTrue(browser.calls.isEmpty, "\(browser.calls)")
        XCTAssertTrue(errText.contains("temporary name"), errText)
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
