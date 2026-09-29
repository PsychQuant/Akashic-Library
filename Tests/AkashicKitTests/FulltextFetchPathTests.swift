import XCTest
@testable import AkashicSkillTools

/// `FulltextFetch` 的路徑測試（#629，由 `tests/fetch-fulltext-paths.sh` 移植）——對一個**記憶體內的假瀏覽器**跑，不碰 Safari、
/// 不連網。
///
/// 結束碼是它對 agent 的契約：6 是「整批停」（中止條款），1 是「看一眼、也許重試」。落錯碼就是把中止條款悄悄變成重試——
/// 2026-09-24 審查在三處找到這個缺陷。每個案例把一條路徑釘在它的碼上，並檢查契約承諾的副作用：6 時我們的分頁**不**被關、
/// 請求的檔名下什麼都沒寫；0 時只關自己開的分頁、使用者的分頁不動。
///
/// 舊測試對一個 Python stub 跑 19 條路徑；這裡逐條移植（案例名、輸入、期望都照舊）。**假瀏覽器逐行對應舊 stub 的分派**
/// （`documents`／`open`／`close`／`js`／`wait`，`js` 依腳本內容分派），所以「這支程式對瀏覽器說了什麼」可以在測試裡逐條斷言，
/// 而不只是最後的結束碼。
final class FulltextFetchPathTests: XCTestCase {

    // MARK: 假瀏覽器

    struct Scenario {
        var profile = "own"
        var prime: String?
        var primeLandsOn: String?
        var landingFinal = "https://pub.example/doi/10.1/x"
        var tabTitle = "Article"
        var readyState = "complete"
        var pageJSFails = false
        var pageText = "Article\nAbstract text"
        var redirectAfterCheck: String?
        var link = "GET https://pub.example/doi/pdf/10.1/x"
        var meta: String?
        var body = Data()
        var fetchWaitRC: Int32 = 0
    }

    final class FakeBrowser: SafariBrowser {
        var scenario: Scenario
        var tabs: [(url: String, title: String)] = [("https://user.example/mine", "the user's own tab")]
        var current = 1
        var checked = false
        var calls: [String] = []
        init(_ s: Scenario) { scenario = s }

        private func opt(_ args: [String], _ name: String) -> String? { args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }

        func run(_ args: [String]) -> SafariRun {
            switch args[0] {
            case "documents":
                let items = tabs.enumerated().map { i, t in
                    PyJSON.object([("window", .int(5)), ("index", .int(i + 1)), ("tab_in_window", .int(i + 1)), ("url", .string(t.url)),
                                   ("title", .string(t.title)), ("profile", .string(scenario.profile)), ("is_current", .bool(i + 1 == current))])
                }
                return SafariRun(status: 0, stdout: PyJSON.array(items).dumps() + "\n")
            case "open":
                let url = args.last!
                calls.append("open \(url)")
                if url == scenario.prime { tabs.append((scenario.primeLandsOn ?? url, "x.pdf")) } else { tabs.append((scenario.landingFinal, scenario.tabTitle)) }
                current = tabs.count
                return SafariRun(status: 0)
            case "close":
                let k = Int(opt(args, "--tab-in-window")!)!
                calls.append("close \(k) \(tabs[k - 1].url)")
                tabs.remove(at: k - 1)
                current = min(current, tabs.count)
                return SafariRun(status: 0)
            case "js":
                let k = Int(opt(args, "--tab-in-window")!)!
                let file = opt(args, "--file")
                let src = file.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? args.last!
                if src.contains("document.readyState") { return SafariRun(status: 0, stdout: scenario.readyState + "\n") }
                if src.contains("innerText.slice") {
                    if scenario.pageJSFails { return SafariRun(status: 1) }
                    if let redirect = scenario.redirectAfterCheck, !checked { tabs[k - 1].url = redirect; checked = true }
                    return SafariRun(status: 0, stdout: scenario.pageText + "\n")
                }
                if src.contains("window.__aff = ") { return SafariRun(status: 0, stdout: "started\n") }
                if file != nil { return SafariRun(status: 0, stdout: scenario.link + "\n") }
                if src.contains("JSON.stringify({s:") { return SafariRun(status: 0, stdout: (scenario.meta ?? "") + "\n") }
                if let output = opt(args, "--output") {
                    try? Data(scenario.body.base64EncodedString().utf8).write(to: URL(fileURLWithPath: output))
                    return SafariRun(status: 0)
                }
                if src.contains("delete window.__aff") { return SafariRun(status: 0, stdout: "ok\n") }
                return SafariRun(status: 0)
            case "wait":
                return SafariRun(status: (opt(args, "--js") ?? "").contains("__aff") ? scenario.fetchWaitRC : 0)
            default:
                return SafariRun(status: 2)
            }
        }
    }

    // MARK: 場地

    private var root: URL!
    private var outDir: URL!
    private var outFile: String { outDir.appendingPathComponent("w.pdf").path }
    private var stdout: [String] = []
    private var stderr: [String] = []
    private var browser: FakeBrowser!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fetch-paths-\(UUID().uuidString)")
        outDir = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    static let landing = "https://doi.org/10.1/x"
    static let finalURL = "https://pub.example/doi/10.1/x"
    static let pdfBody = Data("%PDF-1.4\n% stub body\n".utf8)

    private func okMeta(_ length: Int) -> String { "{\"s\":200,\"c\":\"application/pdf\",\"l\":\(length),\"e\":null}" }

    /// 跑一個場景，回結束碼。
    @discardableResult
    private func run(_ scenario: Scenario, landing: String = FulltextFetchPathTests.landing, _ configure: (inout FulltextFetch.Options) -> Void = { _ in }) -> Int32 {
        browser = FakeBrowser(scenario)
        stdout = []; stderr = []
        var options = FulltextFetch.Options(window: 5, landing: landing, out: outFile)
        configure(&options)
        let fetcher = FulltextFetch(browser: browser, sleeper: { _ in }, out: { self.stdout.append($0) }, err: { self.stderr.append($0) })
        return fetcher.run(options)
    }

    private var base: Scenario { var s = Scenario(); s.meta = okMeta(Self.pdfBody.count); s.body = Self.pdfBody; return s }
    private var errText: String { stderr.joined(separator: "\n") }
    private var outText: String { stdout.joined(separator: "\n") }
    private func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: outDir.appendingPathComponent(name).path) }

    private func assertStop(_ code: Int32, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(code, 6, errText, file: file, line: line)
        XCTAssertTrue(errText.contains("STOP THE WHOLE RUN"), file: file, line: line)
        XCTAssertFalse(browser.calls.contains { $0.hasPrefix("close") }, "分頁必須留著給使用者看：\(browser.calls)", file: file, line: line)
        XCTAssertFalse(exists("w.pdf"), "中止時請求的檔名下不得有任何東西", file: file, line: line)
    }

    // MARK: 19 條路徑

    func testHappyPath() {
        XCTAssertEqual(run(base), 0, errText)
        XCTAssertGreaterThan(try! Data(contentsOf: URL(fileURLWithPath: outFile)).count, 0)
        XCTAssertTrue(browser.calls.contains("close 2 \(Self.finalURL)"), "\(browser.calls)")
        XCTAssertFalse(browser.calls.contains { $0.contains("close") && $0.contains("user.example") }, "使用者的分頁不得動")
    }

    func testPrimedHappyPath() {
        var s = base; s.prime = "https://pub.example/x.pdf"
        XCTAssertEqual(run(s) { $0.prime = "https://pub.example/x.pdf" }, 0, errText)
        XCTAssertTrue(browser.calls.contains("close 2 https://pub.example/x.pdf"), "\(browser.calls)")
        XCTAssertTrue(browser.calls.contains("close 2 \(Self.finalURL)"), "\(browser.calls)")
        XCTAssertFalse(browser.calls.contains { $0.contains("user.example") && $0.hasPrefix("close") })
    }

    func testChallengeOnLanding() {
        var s = base; s.pageText = "Just a moment...\nChecking"
        assertStop(run(s))
    }

    func testTabMovesToAnotherSite() {
        var s = base; s.redirectAfterCheck = "https://verify.other.example/c"
        assertStop(run(s))
    }

    func testPageUnreadable() {
        var s = base; s.pageJSFails = true
        assertStop(run(s))
    }

    /// 本文讀不到，但**分頁標題**（不經 JS 讀）顯示挑戰頁：中止要點名那個訊號。用標籤比對，因為「頁面讀不到」的退路同樣是 6——
    /// 只有標籤說明標題檢查真的跑了。
    func testChallengeInTitleWhenBodyUnreadable() {
        var s = base; s.pageJSFails = true; s.tabTitle = "Just a moment..."
        assertStop(run(s))
        XCTAssertTrue(errText.contains("cloudflare-challenge"), errText)
    }

    func testFetchStalls() {
        var s = base; s.fetchWaitRC = 1
        assertStop(run(s))
    }

    func testHTTP403Response() {
        var s = base; s.meta = "{\"s\":403,\"c\":\"text/html\",\"l\":40,\"e\":null}"; s.body = Data("<html><body>Forbidden</body></html>".utf8)
        assertStop(run(s))
    }

    func testEmptyResponse() {
        var s = base; s.meta = "{\"s\":200,\"c\":\"application/pdf\",\"l\":0,\"e\":null}"
        assertStop(run(s))
    }

    func testFetchThrows() {
        var s = base; s.meta = "{\"s\":null,\"c\":null,\"l\":null,\"e\":\"TypeError: Load failed\"}"
        assertStop(run(s))
    }

    func testPageNeverSettles() {
        var s = base; s.readyState = "loading"
        assertStop(run(s))
    }

    func testResponseMetadataUnreadable() {
        var s = base; s.meta = "not json"
        assertStop(run(s))
    }

    func testPrimedTabSentElsewhere() {
        var s = base; s.prime = "https://pub.example/x.pdf"; s.primeLandsOn = "https://verify.other.example/c"
        assertStop(run(s) { $0.prime = "https://pub.example/x.pdf" })
        XCTAssertFalse(browser.calls.contains("open \(Self.landing)"), "被送走之後不得繼續去文章頁")
    }

    /// 無權限（PsycNet 沒有 entitlement 時回 200 與 ~8 KB 的 Loading 殼）不是起疑：結束碼 4、本文存給人看、我們的分頁關掉。
    func testPaywallShellIsNoAccess() {
        var s = base; let shell = Data("<html><body><div>Loading...</div></body></html>".utf8)
        s.meta = "{\"s\":200,\"c\":\"text/html\",\"l\":\(shell.count),\"e\":null}"; s.body = shell
        XCTAssertEqual(run(s), 4, errText)
        XCTAssertFalse(errText.contains("STOP THE WHOLE RUN"))
        XCTAssertTrue(exists("w.response.txt"))
        XCTAssertTrue(browser.calls.contains("close 2 \(Self.finalURL)"), "\(browser.calls)")
    }

    func testNoPDFLink() {
        var s = base; s.link = ""
        XCTAssertEqual(run(s), 3, errText)
        XCTAssertTrue(browser.calls.contains("close 2 \(Self.finalURL)"), "\(browser.calls)")
    }

    func testWrongProfileRefusedBeforeOpeningAnything() {
        var s = base; s.profile = "someone-else"
        XCTAssertEqual(run(s) { $0.expectProfile = "own" }, 1, errText)
        XCTAssertFalse(browser.calls.contains { $0.hasPrefix("open") }, "不得開任何分頁")
    }

    func testOutInsideAGitTreeThatDoesNotIgnoreItIsRefusedBeforeAnyBrowserCall() throws {
        let repo = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let git = try ToolRunner.git(["-C", repo.path, "init", "-q"])
        XCTAssertEqual(git.status, 0)
        browser = FakeBrowser(base); stdout = []; stderr = []
        let fetcher = FulltextFetch(browser: browser, sleeper: { _ in }, out: { self.stdout.append($0) }, err: { self.stderr.append($0) })
        let code = fetcher.run(.init(window: 5, landing: Self.landing, out: repo.appendingPathComponent("w.pdf").path))
        XCTAssertEqual(code, 1)
        XCTAssertTrue(browser.calls.isEmpty, "一個瀏覽器呼叫都不該有：\(browser.calls)")
        XCTAssertTrue(errText.contains("working tree"), errText)
    }

    /// 被該樹 ignore 的位置放行。
    func testOutInsideAGitTreeThatIgnoresItIsAllowed() throws {
        let repo = root.appendingPathComponent("repo2")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        _ = try ToolRunner.git(["-C", repo.path, "init", "-q"])
        try Data("*.pdf\n*.response.txt\n".utf8).write(to: repo.appendingPathComponent(".gitignore"))
        browser = FakeBrowser(base); stdout = []; stderr = []
        let fetcher = FulltextFetch(browser: browser, sleeper: { _ in }, out: { self.stdout.append($0) }, err: { self.stderr.append($0) })
        XCTAssertEqual(fetcher.run(.init(window: 5, landing: Self.landing, out: repo.appendingPathComponent("w.pdf").path)), 0, errText)
    }

    /// `git -C` 擋不住 `GIT_DIR`（#234／#239）：從 git hook 裡執行時它指向呼叫 hook 的 repo。這裡造一個「什麼都忽略」的誘餌 repo，
    /// 把 `GIT_DIR` 指過去；閘若沒剝除環境，`check-ignore` 問的是誘餌、答「已忽略」而放行——第三方全文寫進沒忽略它的工作樹。
    func testGitDirInTheCallersEnvironmentCannotMakeTheGateFailOpen() throws {
        let target = root.appendingPathComponent("gate-target")
        let decoy = root.appendingPathComponent("gate-decoy")
        for d in [target, decoy] {
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            XCTAssertEqual(try ToolRunner.git(["-C", d.path, "init", "-q"]).status, 0)
        }
        try Data("*\n".utf8).write(to: decoy.appendingPathComponent(".git/info/exclude"))
        setenv("GIT_DIR", decoy.appendingPathComponent(".git").path, 1)
        defer { unsetenv("GIT_DIR") }
        XCTAssertFalse(ToolRunner.scrubbedGitEnvironment.keys.contains { $0.hasPrefix("GIT_") }, "剝除後不得留下任何 GIT_*")
        browser = FakeBrowser(base); stdout = []; stderr = []
        let fetcher = FulltextFetch(browser: browser, sleeper: { _ in }, out: { self.stdout.append($0) }, err: { self.stderr.append($0) })
        let code = fetcher.run(.init(window: 5, landing: Self.landing, out: target.appendingPathComponent("w.pdf").path))
        XCTAssertEqual(code, 1, "GIT_DIR 指向誘餌時，閘仍要照 -C 指的那個 repo 判斷：\(errText)")
        XCTAssertTrue(browser.calls.isEmpty, "\(browser.calls)")
    }

    // MARK: 驗證步驟，端到端（DOI 從 doi.org 落地網址取）

    private func makePDF(lines: [String]) -> Data {
        let text = "BT /F1 12 Tf 72 720 Td 14 TL " + lines.map { "(\($0)) Tj T*" }.joined(separator: " ") + " ET"
        let objs = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
                    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>", "<< /Length \(text.utf8.count) >>\nstream\n\(text)\nendstream"]
        var out = Data("%PDF-1.4\n".utf8)
        var offsets: [Int] = []
        for (i, o) in objs.enumerated() { offsets.append(out.count); out.append(Data("\(i + 1) 0 obj\n\(o)\nendobj\n".utf8)) }
        let xref = out.count
        out.append(Data("xref\n0 \(objs.count + 1)\n0000000000 65535 f \n".utf8))
        for o in offsets { out.append(Data(String(format: "%010d 00000 n \n", o).utf8)) }
        out.append(Data("trailer\n<< /Size \(objs.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
        return out
    }

    func testVerifiedByTitleAndTheLandingURLsDOI() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/pdftotext") || (try? ToolRunner.run(["pdftotext", "-v"])) != nil, "需要 poppler")
        let own = makePDF(lines: ["A Stub Title For Path Tests", "doi:10.1234/x", "Abstract"])
        var s = base; s.body = own; s.meta = okMeta(own.count)
        XCTAssertEqual(run(s, landing: "https://doi.org/10.1234/x") { $0.title = "A Stub Title For Path Tests"; $0.pages = "1--1" }, 0, errText)
        XCTAssertTrue(exists("w.pdf"), "以要求的檔名存")
        XCTAssertTrue(outText.contains("\"doi_state\": \"page-match\""), outText)
    }

    func testAnotherWorksDOIIsNotVerified() throws {
        try XCTSkipUnless((try? ToolRunner.run(["pdftotext", "-v"])) != nil, "需要 poppler")
        let other = makePDF(lines: ["A Stub Title For Path Tests", "doi:10.1234/someone-else", "Abstract"])
        var s = base; s.body = other; s.meta = okMeta(other.count)
        XCTAssertEqual(run(s, landing: "https://doi.org/10.1234/x") { $0.title = "A Stub Title For Path Tests"; $0.pages = "1--1" }, 5, errText)
        XCTAssertTrue(exists("w.unverified.pdf"))
        XCTAssertFalse(exists("w.pdf"))
    }

    // MARK: 純函式

    func testDOIFromTheLandingURL() {
        XCTAssertEqual(FulltextFetch.doiFromLanding("https://doi.org/10.1037/a0038889?x=1#f"), "10.1037/a0038889")
        XCTAssertEqual(FulltextFetch.doiFromLanding("http://doi.org/10.1/x"), "10.1/x")
        XCTAssertEqual(FulltextFetch.doiFromLanding("https://dx.doi.org/10.1/x"), "10.1/x")
        XCTAssertNil(FulltextFetch.doiFromLanding("http://dx.doi.org/10.1/x"), "舊實作只認這三個前綴（bash 的 case）")
        XCTAssertNil(FulltextFetch.doiFromLanding("HTTPS://doi.org/10.1/x"), "區分大小寫")
        XCTAssertNil(FulltextFetch.doiFromLanding("https://pub.example/doi/10.1/x"))
    }

    func testMetaParsing() {
        XCTAssertEqual(FulltextFetch.parseMeta("{\"s\":200,\"c\":\"application/pdf\",\"l\":123,\"e\":null}")?.length, 123)
        XCTAssertEqual(FulltextFetch.parseMeta("{\"s\":200,\"l\":5,\"e\":\"boom\"}")?.hadError, true)
        XCTAssertEqual(FulltextFetch.parseMeta("{\"e\":null}")?.status, 0)
        XCTAssertNil(FulltextFetch.parseMeta("not json"))
        XCTAssertNil(FulltextFetch.parseMeta(""))
        XCTAssertNil(FulltextFetch.parseMeta("[1,2]"))
    }

    func testContainsLoadingIsCaseInsensitiveOverBytes() {
        XCTAssertTrue(FulltextFetch.containsLoading(Data("<div>LoAdInG...</div>".utf8)))
        XCTAssertTrue(FulltextFetch.containsLoading(Data([0xFF, 0x00] + Array("loading".utf8))))
        XCTAssertFalse(FulltextFetch.containsLoading(Data("load ing".utf8)))
    }

    /// 頁內取 PDF 的 JS 與 Python 舊腳本產生的逐字相同（`json.dumps(url)` 的 ASCII 逃脫、GET／POST 兩種本文）。
    func testFetchJSMatchesTheOldGeneratorByteForByte() {
        let get = "\nwindow.__aff = {done:false};\nfetch(\"https://pub.example/doi/pdf/10.1/x?a=b&c=\\u00e9\", {method:\"GET\", credentials:'include', body:undefined})\n"
            + " .then(r => { window.__aff.status = r.status; window.__aff.ctype = r.headers.get('content-type'); return r.arrayBuffer(); })\n"
            + " .then(b => { const u = new Uint8Array(b); let s = '';\n"
            + "   for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode.apply(null, u.subarray(i, i + 0x8000));\n"
            + "   window.__aff.b64 = btoa(s); window.__aff.len = u.length; window.__aff.done = true; })\n"
            + " .catch(e => { window.__aff.err = String(e); window.__aff.done = true; });\nreturn 'started';\n"
        XCTAssertEqual(FulltextFetch.fetchJS(url: "https://pub.example/doi/pdf/10.1/x?a=b&c=é", method: "GET"), get)
        let post = get.replacingOccurrences(of: "https://pub.example/doi/pdf/10.1/x?a=b&c=\\u00e9", with: "https://pub.example/dl")
            .replacingOccurrences(of: "method:\"GET\"", with: "method:\"POST\"")
            .replacingOccurrences(of: "body:undefined", with: "body:new FormData(document.querySelector('form.ft-download-content__form--pdf'))")
        XCTAssertEqual(FulltextFetch.fetchJS(url: "https://pub.example/dl", method: "POST"), post)
    }

    /// 頁面連結的兩段 JS（`--file`／`wait --js`）與舊腳本的 heredoc 逐字相同。
    func testLinkScriptsMatchTheOldHeredocs() {
        XCTAssertEqual(FulltextFetch.hasLinkJS, """
        !!(document.querySelector('meta[name=citation_pdf_url]')
          || document.querySelector('a[href*="/doi/pdf/"],a[href*="pdfdirect"],a[href$=".pdf"],a[href*=".pdf?"],a[href^="/record/"]')
          || document.querySelector('form.ft-download-content__form--pdf'))

        """)
        XCTAssertTrue(FulltextFetch.linkJS.hasPrefix("const f = document.querySelector('form.ft-download-content__form--pdf');\nif (f) return 'POST ' + f.action;\n"))
        XCTAssertTrue(FulltextFetch.linkJS.hasSuffix("  const a = document.querySelector(s); if (a) return 'GET ' + a.href;\n}\nreturn '';\n"))
    }
}
