import XCTest
@testable import AkashicSkillTools
@testable import AkashicStoreIO

/// #629 R1–R3 驗證對 `fulltext fetch` 的回歸釘，#613 之後分成兩半：
///
/// - `fetch`（導航）：`--landing` 的形狀、頁面連結的來源限制——導航到頁面選的別的站，同樣是在使用者已登入的 profile 裡開那個站。
/// - `take`（收檔，原本 `fetch` 的輸出與 git 閘搬過來）：輸出目的地的處置、原子替換、git 閘的 fail-closed、暫存目錄權限、`--from` 的限制。
final class FulltextFetchHardeningTests: XCTestCase {
    private typealias Scenario = FulltextFetchPathTests.Scenario
    private typealias FakeBrowser = FulltextFetchPathTests.FakeBrowser

    private var root: URL!
    private var outDir: URL!
    private var source: URL!
    private var stdout: [String] = []
    private var stderr: [String] = []
    private var browser: FakeBrowser!
    private var scratchMode: Int?

    static let pdfBody = Data("%PDF-1.4\n% stub body\n".utf8)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fetch-hardening-\(UUID().uuidString)")
        outDir = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        source = root.appendingPathComponent("saved-by-the-user.pdf")
        try Self.pdfBody.write(to: source)
    }

    override func tearDownWithError() throws {
        // 有些測試把目錄設成唯讀
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: outDir.path)
        try? FileManager.default.removeItem(at: root)
    }

    private var errText: String { stderr.joined(separator: "\n") }

    // MARK: fetch

    @discardableResult
    private func fetch(_ scenario: Scenario, landing: String = FulltextFetchPathTests.landing) -> Int32 {
        browser = FakeBrowser(scenario)
        stdout = []; stderr = []
        let fetcher = FulltextFetch(browser: browser, sleeper: { _ in }, out: { self.stdout.append($0) }, err: { self.stderr.append($0) })
        return fetcher.run(.init(window: 5, landing: landing, ledger: root.appendingPathComponent("ledger.jsonl").path))
    }

    func testLandingMustBeHTTPS() {
        for bad in ["http://doi.org/10.1/x", "file:///etc/passwd", "javascript:alert(1)", "ftp://x/y"] {
            XCTAssertEqual(fetch(Scenario(), landing: bad), 1, bad)
            XCTAssertTrue(browser.calls.isEmpty, "\(bad)：\(browser.calls)")
            XCTAssertTrue(errText.contains("--landing must be an https"), errText)
        }
    }

    /// `--landing` 在使用者已登入的 profile 裡開：主機要是公開的網域名稱——web-access.md〈插值前先驗形狀〉「完整網址」一列的主機部分與禁用字元
    /// （#629 R2 verify 第 34 則）。路徑的字元集不套那一列：SICI 式 DOI 的 `<`、`>` 在 doi.org 網址裡是合法的。
    func testLandingMustHaveAPublicHostName() {
        let bad = ["https://localhost/x", "https://127.0.0.1/x", "https://[::1]/x", "https://router.local/x", "https://svc.corp/x", "https://intranet/x",
                   "https://user@doi.org/10.1/x", "https://doi.org:8443/10.1/x", "https://doi.org./10.1/x", "https://doi.org/10.1/../x",
                   "https://doi.org/10.1/%2e%2E/x", "https://doi.org/10.1/x#frag", "https://doi.org/10.1/x\"y", "https://doi.org/10.1/x y",
                   "https://doi.org/10.1/x$(id)", #"https://doi.org/10.1/x\y"#, "https://1.2.3.4/x"]
        for url in bad {
            XCTAssertEqual(fetch(Scenario(), landing: url), 1, url)
            XCTAssertTrue(browser.calls.isEmpty, "\(url)：\(browser.calls)")
            XCTAssertTrue(errText.contains("--landing must be an https"), "\(url)：\(errText)")
        }
        for url in ["https://doi.org/10.1002/(sici)1097-0258(19980430)17:8<873::aid-sim777>3.0.co;2-B", "https://dx.doi.org/10.1/x", "https://DOI.org/10.1/a?b=c"] {
            XCTAssertEqual(fetch(Scenario(), landing: url), 7, "\(url)：\(errText)")
        }
    }

    // MARK: 頁面連結的來源：不把使用者已登入的分頁導到頁面選的別的站

    func testAPageLinkThatPointsOffSiteIsRefusedNotFollowed() {
        var s = Scenario(); s.link = "GET https://evil.example/steal"
        XCTAssertEqual(fetch(s), 1, errText)
        XCTAssertTrue(errText.contains("off-site"), errText)
        XCTAssertFalse(browser.calls.contains { $0.contains("evil.example") })
    }

    func testNonHTTPSchemesAndJavascriptLinksAreOffSite() {
        for link in ["GET javascript:alert(1)", "GET data:text/plain,x", "GET blob:https://pub.example/uuid", "POST javascript:x"] {
            var s = Scenario(); s.link = link
            XCTAssertEqual(fetch(s), 1, link)
            XCTAssertTrue(errText.contains("off-site"), "\(link)：\(errText)")
            XCTAssertFalse(browser.calls.contains { $0.hasPrefix("navigate") }, link)
        }
    }

    /// 同站的絕對網址放行，而且**導過去的就是驗過的那一串**。
    func testSameSiteAbsoluteLinksAreFollowedVerbatim() {
        for link in ["https://pub.example/doi/pdf/10.1/x", "https://PUB.example/doi/pdf/10.1/x", "https://pub.example/a.pdf?x=1#frag"] {
            var s = Scenario(); s.link = "GET " + link
            XCTAssertEqual(fetch(s), 7, "\(link)：\(errText)")
            XCTAssertEqual(browser.calls.filter { $0.hasPrefix("navigate") }, ["navigate \(link)"], link)
        }
    }

    /// #629 R2 verify 第 0／9／12／20 則：瀏覽器用 WHATWG 解析——反斜線當斜線、`https:` 後面多出來的斜線當主機分隔。下面每一串在
    /// urlsplit 式的檢查裡都判成「同站」，瀏覽器卻開到 `evil.example`。`linkJS` 在頁面裡把連結解析成絕對網址，Swift 只收「`https://` 開頭、
    /// 沒有反斜線、空白或控制字元」的字串再比 origin。
    func testBackslashSlashRunAndRelativeLinksAreRefused() {
        let bad = [
            #"\\evil.example/x.pdf"#, #"\evil.example/x.pdf"#, #"/\evil.example/x.pdf"#, #"\/evil.example/x.pdf"#,
            "///evil.example/x.pdf", "////evil.example/x.pdf", "  //evil.example/x.pdf", "//pub.example/doi/pdf/10.1/x", "/doi/pdf/10.1/x",
            "https:///evil.example/x.pdf", #"https:\\evil.example/x.pdf"#, #"https://\evil.example/x.pdf"#, #"https:/\evil.example/x.pdf"#,
            #"https://pub.example\@evil.example/x.pdf"#, "https://pub.example@evil.example/x.pdf", "https://pub.example:443@evil.example/x.pdf",
            "https://pub.example/x\t.pdf", "https://pub.example/x .pdf", "http://pub.example/x.pdf",
        ]
        for link in bad {
            var s = Scenario(); s.link = "GET " + link
            XCTAssertEqual(fetch(s), 1, "\(link)：\(errText)")
            XCTAssertTrue(errText.contains("not following a link the page chose"), "\(link)：\(errText)")
            XCTAssertFalse(browser.calls.contains { $0.hasPrefix("navigate") }, link)
        }
    }

    /// `citation_pdf_url` 的 `content` 是原始字串：要在頁面裡用 WHATWG 解析成絕對網址再交回。
    func testTheMetaLinkIsResolvedInThePage() {
        XCTAssertTrue(FulltextFetch.linkJS.contains("if (m && m.content) { try { return 'GET ' + new URL(m.content, document.baseURI).href; } catch (e) { return 'GET ' + m.content; } }"), FulltextFetch.linkJS)
    }

    func testLinkTargetOrigin() {
        XCTAssertEqual(FulltextFetch.linkTargetOrigin("https://pub.example/a/b.pdf"), "https://pub.example")
        XCTAssertEqual(FulltextFetch.linkTargetOrigin("HTTPS://Pub.Example/a.pdf"), "https://pub.example")
        for u in ["/a/b.pdf", "//cdn.example/a.pdf", "javascript:1", "data:text/plain,x", "blob:https://pub.example/u", "http://pub.example/a.pdf",
                  #"\\evil.example/a"#, "///evil.example/a", "https:///evil.example/a", #"https://pub.example\x"#, "https://pub.example/a b", "https://"] {
            XCTAssertNil(FulltextFetch.linkTargetOrigin(u), u)
        }
    }

    // MARK: take

    @discardableResult
    private func take(from: String? = nil, out: String? = nil, git: FulltextTake.GitRunner? = nil, sizeLimit: Int = LibraryStore.maxSourceBytes,
                      realVerifier: Bool = false, afterInspect: ((String) -> Void)? = nil,
                      configure: (inout FulltextTake.Options) -> Void = { _ in }) -> Int32 {
        stdout = []; stderr = []
        scratchMode = nil
        // `--title` 必填（#613 修正輪）：預設給一個標題；驗證步驟預設用替身（輸出目的地與 git 閘的測試不需要 poppler 與真的 PDF）
        var options = FulltextTake.Options(from: from ?? source.path, out: out ?? outDir.appendingPathComponent("w.pdf").path, title: "A Stub Title For Take Tests")
        configure(&options)
        let taker = realVerifier
            ? FulltextTake(out: { self.stdout.append($0) }, err: { self.stderr.append($0) }, git: git, sizeLimit: sizeLimit)
            : FulltextTake(out: { self.stdout.append($0) }, err: { self.stderr.append($0) }, git: git, sizeLimit: sizeLimit,
                           verifier: { _, _, _, _ in ("{\"stub\": true}", true, false) })
        taker.afterInspect = afterInspect
        taker.onScratch = { [weak self] url in
            self?.scratchMode = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber)?.intValue
        }
        return taker.run(options)
    }

    private func write(_ text: String, to url: URL) throws { try Data(text.utf8).write(to: url) }

    func testTakeCopiesTheSourceWithoutTouchingIt() throws {
        let before = try FileManager.default.attributesOfItem(atPath: source.path)
        XCTAssertEqual(take(), 0, errText)
        XCTAssertEqual(try Data(contentsOf: outDir.appendingPathComponent("w.pdf")), Self.pdfBody)
        XCTAssertEqual(try Data(contentsOf: source), Self.pdfBody, "--from 只讀")
        let after = try FileManager.default.attributesOfItem(atPath: source.path)
        XCTAssertEqual(before[.modificationDate] as? Date, after[.modificationDate] as? Date)
    }

    func testANonPDFSourceWritesNothing() throws {
        try write("<html>Access Denied</html>", to: source)
        XCTAssertEqual(take(), 2, errText)
        XCTAssertTrue(errText.contains("not a PDF"), errText)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outDir.path), [], "什麼都沒寫")
    }

    func testTheSourceMustBeARegularFile() throws {
        let link = root.appendingPathComponent("link.pdf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        XCTAssertEqual(take(from: link.path), 1, errText)
        XCTAssertTrue(errText.contains("symlink"), errText)
        XCTAssertEqual(take(from: root.path), 1, errText)
        XCTAssertTrue(errText.contains("directory"), errText)
        XCTAssertEqual(take(from: root.appendingPathComponent("missing.pdf").path), 1, errText)
        XCTAssertTrue(errText.contains("does not exist"), errText)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outDir.path), [])
    }

    /// FIFO 在 `lstat` 就被拒絕：不開、不阻塞、什麼都沒寫（row 76 的「lstat 拒 FIFO」一句）。
    func testAFIFOSourceIsRefusedWithoutHanging() throws {
        let fifo = root.appendingPathComponent("pipe.pdf")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertEqual(take(from: fifo.path), 1, errText)
        XCTAssertTrue(errText.contains("FIFO"), errText)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outDir.path), [])
    }

    /// `lstat` 通過之後、`open` 之前，普通檔被換成 FIFO：沒有 `O_NONBLOCK` 的 `open` 會一直等到有寫入端，`fstat` 永遠到不了。
    /// 在背景執行緒跑、限時 10 秒——被卡住時失敗，不是整個測試掛住。
    func testAFileSwappedForAFIFOAfterTheLstatCheckDoesNotHang() throws {
        let swapped = expectation(description: "take returned")
        var code: Int32 = -1
        DispatchQueue.global().async {
            code = self.take(afterInspect: { path in
                try? FileManager.default.removeItem(atPath: path)
                mkfifo(path, 0o600)
            })
            swapped.fulfill()
        }
        wait(for: [swapped], timeout: 10)
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("not a regular file"), errText)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outDir.path), [])
    }

    /// `lstat` 之後被換成 symlink：`O_NOFOLLOW` 擋下，不跟隨。
    func testAFileSwappedForASymlinkAfterTheLstatCheckIsNotFollowed() throws {
        let other = root.appendingPathComponent("other.pdf")
        try Self.pdfBody.write(to: other)
        let code = take(afterInspect: { path in
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: other.path)
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("cannot read --from"), errText)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outDir.path), [])
    }

    /// `lstat` 之後被換成目錄：`open` 讀得開目錄，靠 `fstat` 的再確認擋下（訊息是 `not a regular file`，不是讀取失敗）。
    func testAFileSwappedForADirectoryAfterTheLstatCheckIsRefusedByTheFstatRecheck() throws {
        let code = take(afterInspect: { path in
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
        })
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("--from is not a regular file"), errText)
    }

    /// 使用者 2026-10-02：`--title` 必填。沒給或給空字串先前整個跳過驗證、結束碼 0 照樣說存好了，而 SKILL 把 0 讀成「驗證過」。
    func testATitleIsRequiredAndAnEmptyOneIsRefusedBeforeAnythingIsRead() throws {
        for title in [nil, "", "   "] as [String?] {
            let code = take(configure: { $0.title = title })
            XCTAssertEqual(code, 64, "\(String(describing: title))：\(errText)")
            XCTAssertTrue(errText.contains("--title is required"), errText)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outDir.path), [], "什麼都沒寫")
        }
        // --doi／--pages 不再能讓沒有標題的呼叫變成「免驗證」
        XCTAssertEqual(take(configure: { $0.title = nil; $0.doi = "10.1234/x"; $0.pages = "1--1" }), 64)
    }

    /// 驗證本身跑不起來（截斷的下載、缺 poppler）與「讀完了、不是這篇」是兩件事：前者結束碼 1、什麼都不寫；後者才是 5。
    func testAVerificationThatCouldNotRunIsNotReportedAsAnotherPaper() throws {
        let taker = FulltextTake(out: { self.stdout.append($0) }, err: { self.stderr.append($0) }, git: nil,
                                 verifier: { _, _, _, _ in ("{\"error\": \"pdfinfo failed (exit 1)\", \"is_article\": false}", false, true) })
        stdout = []; stderr = []
        let code = taker.run(.init(from: source.path, out: outDir.appendingPathComponent("w.pdf").path, title: "T"))
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("verification could not run"), errText)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outDir.path), [], "不存 *.unverified.pdf：那是「別篇」的處置")
    }

    func testARealTruncatedPDFIsAVerificationErrorNotExit5() throws {
        try XCTSkipUnless((try? ToolRunner.run(["pdftotext", "-v"])) != nil, "需要 poppler")
        XCTAssertEqual(take(realVerifier: true), 1, errText)
        XCTAssertTrue(errText.contains("verification could not run"), errText)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outDir.path), [])
    }

    /// 不是 PDF 的檔案：不印內容（`--from` 是 agent 可被引導指定的路徑，印前 80 個字元等於讀任意檔頭的出口）。
    func testANonPDFSourceDoesNotEchoItsContent() throws {
        try write("AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", to: source)
        XCTAssertEqual(take(), 2, errText)
        XCTAssertFalse(errText.contains("wJalr"), errText)
        XCTAssertFalse(errText.contains("AWS_SECRET"), errText)
        XCTAssertTrue(errText.contains("first bytes 41 57 53"), errText)
        try write("<!DOCTYPE html><html><body>Access Denied</body></html>", to: source)
        XCTAssertEqual(take(), 2, errText)
        XCTAssertTrue(errText.contains("looks like an HTML page"), errText)
        XCTAssertFalse(errText.contains("Access Denied"), errText)
    }

    /// 存不進 store 的檔收進來也沒有用：上限與 `store-source` 同一個常數（測試接縫調小）。
    func testASourceOverTheStoreLimitIsRefused() {
        XCTAssertEqual(take(sizeLimit: 8), 1, errText)
        XCTAssertTrue(errText.contains("over the store-source limit"), errText)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outDir.path), [])
    }

    // MARK: take 的輸出目的地：目錄、symlink、特殊檔具名拒絕，在讀 --from 之前

    /// 第一版對已存在的目的地先 `removeItem` 再 `moveItem`：`--out` 指著非空目錄時遞迴刪掉整個目錄。
    func testANonEmptyDirectoryAtOutIsRefusedAndKept() throws {
        let dir = outDir.appendingPathComponent("w.pdf")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try write("precious", to: dir.appendingPathComponent("keep.txt"))
        XCTAssertEqual(take(), 1, errText)
        XCTAssertTrue(errText.contains("directory"), errText)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("keep.txt"), encoding: .utf8), "precious", "目錄與裡面的檔原封不動")
    }

    func testADirectoryAtTheUnverifiedPathIsRefused() throws {
        let dir = outDir.appendingPathComponent("w.unverified.pdf")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try write("x", to: dir.appendingPathComponent("keep.txt"))
        XCTAssertEqual(take(), 1, errText)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("keep.txt").path))
    }

    func testASymlinkAtOutIsRefusedAndItsTargetIsNotTouched() throws {
        let victim = root.appendingPathComponent("victim.txt")
        try write("victim", to: victim)
        try FileManager.default.createSymbolicLink(at: outDir.appendingPathComponent("w.pdf"), withDestinationURL: victim)
        XCTAssertEqual(take(), 1, errText)
        XCTAssertTrue(errText.contains("symlink"), errText)
        XCTAssertEqual(try String(contentsOf: victim, encoding: .utf8), "victim")
    }

    func testAnExistingRegularFileIsReplacedAtomically() throws {
        let target = outDir.appendingPathComponent("w.pdf")
        try write("old", to: target)
        XCTAssertEqual(take(), 0, errText)
        XCTAssertEqual(try Data(contentsOf: target), Self.pdfBody)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outDir.path).filter { $0.hasPrefix(".") }, [], "不留暫存檔")
    }

    /// 替換失敗（目錄唯讀）之後，原本的檔案還在：不是「先刪再搬、搬失敗時已毀」。
    func testAFailedReplaceKeepsTheOriginalFile() throws {
        let target = outDir.appendingPathComponent("w.pdf")
        try write("original", to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: outDir.path)
        let code = take()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: outDir.path)
        XCTAssertEqual(code, 1, errText)
        XCTAssertTrue(errText.contains("cannot write"), errText)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "original", "原檔要還在")
    }

    /// 寫入中途失敗（暫存檔已建立、寫不下去）：原檔還在、不留暫存檔。用 `RLIMIT_FSIZE` 讓 `write(2)` 回 `EFBIG`。
    func testAWriteFailureAfterTheTempFileWasCreatedKeepsTheOriginalFile() throws {
        let target = outDir.appendingPathComponent("w.pdf")
        try write("original", to: target)
        // 行程層級的狀態：只在這幾行之間改，結束時還原成**原本的**處置與上限。這支測試不適合平行跑。
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

    func testTheScratchDirectoryIsPrivate() throws {
        _ = take(configure: { $0.title = "Some Title" })
        XCTAssertEqual(scratchMode, 0o700, "暫存目錄裡有第三方全文：0700（舊 mktemp -d 同）")
    }

    // MARK: take 的驗證（端到端，需要 poppler）

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

    func testVerifiedByTitleAndDOI() throws {
        try XCTSkipUnless((try? ToolRunner.run(["pdftotext", "-v"])) != nil, "需要 poppler")
        try makePDF(lines: ["A Stub Title For Path Tests", "doi:10.1234/x", "Abstract"]).write(to: source)
        XCTAssertEqual(take(realVerifier: true, configure: { $0.title = "A Stub Title For Path Tests"; $0.pages = "1--1"; $0.doi = "10.1234/x" }), 0, errText)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outDir.appendingPathComponent("w.pdf").path), "以要求的檔名存")
        XCTAssertTrue(stdout.joined().contains("\"doi_state\": \"page-match\""), stdout.joined())
    }

    func testAnotherWorksDOIIsKeptAsUnverified() throws {
        try XCTSkipUnless((try? ToolRunner.run(["pdftotext", "-v"])) != nil, "需要 poppler")
        try makePDF(lines: ["A Stub Title For Path Tests", "doi:10.1234/someone-else", "Abstract"]).write(to: source)
        XCTAssertEqual(take(realVerifier: true, configure: { $0.title = "A Stub Title For Path Tests"; $0.pages = "1--1"; $0.doi = "10.1234/x" }), 5, errText)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outDir.appendingPathComponent("w.unverified.pdf").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outDir.appendingPathComponent("w.pdf").path))
    }

    // MARK: take 的 git 閘：git 答不出來時一律拒絕

    private func initRepo(_ name: String) throws -> URL {
        let repo = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        XCTAssertEqual(GitFixture.run(["init", "-q"], in: repo), 0)
        return repo
    }

    private func take(into dir: URL, git: FulltextTake.GitRunner? = nil) -> Int32 {
        take(out: dir.appendingPathComponent("w.pdf").path, git: git)
    }

    func testOutInsideAGitTreeThatDoesNotIgnoreItIsRefused() throws {
        let repo = try initRepo("repo")
        XCTAssertEqual(take(into: repo), 1)
        XCTAssertTrue(errText.contains("working tree"), errText)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.appendingPathComponent("w.pdf").path))
    }

    func testOutInsideAGitTreeThatIgnoresItIsAllowed() throws {
        let repo = try initRepo("repo2")
        try write("*.pdf\n", to: repo.appendingPathComponent(".gitignore"))
        XCTAssertEqual(take(into: repo), 0, errText)
    }

    /// `git -C` 擋不住 `GIT_DIR`：從 git hook 裡執行時它指向呼叫 hook 的 repo。誘餌 repo 什麼都忽略；閘若沒剝除環境就會放行。
    func testGitDirInTheCallersEnvironmentCannotMakeTheGateFailOpen() throws {
        let target = try initRepo("gate-target")
        let decoy = try initRepo("gate-decoy")
        try write("*\n", to: decoy.appendingPathComponent(".git/info/exclude"))
        setenv("GIT_DIR", decoy.appendingPathComponent(".git").path, 1)
        defer { unsetenv("GIT_DIR") }
        XCTAssertNil(LibraryStore.scrubbedGitEnvironment["GIT_DIR"], "呼叫端的 GIT_DIR 不得留到閘的 git 裡")
        XCTAssertEqual(take(into: target), 1, "GIT_DIR 指向誘餌時，閘仍要照 -C 指的那個 repo 判斷：\(errText)")
    }

    func testGitThatCannotRunRefusesWhenTheDirectoryIsInsideARepo() throws {
        let repo = try initRepo("repo-nogit")
        XCTAssertEqual(take(into: repo, git: { _, _ in nil }), 1, errText)
        XCTAssertTrue(errText.contains("git cannot be run") && errText.contains("working tree"), errText)
    }

    func testARevParseFailureRefusesWhenTheDirectoryIsInsideARepo() throws {
        let repo = try initRepo("repo-128")
        XCTAssertEqual(take(into: repo, git: { _, _ in (128, "") }), 1, errText)
        XCTAssertTrue(errText.contains("could not confirm") && errText.contains("128"), errText)
    }

    func testARevParseAnswerOtherThanTrueRefuses() throws {
        let repo = try initRepo("repo-false")
        XCTAssertEqual(take(into: repo, git: { _, _ in (0, "false\n") }), 1, errText)
    }

    func testACheckIgnoreErrorRefuses() throws {
        let repo = try initRepo("repo-checkignore")
        XCTAssertEqual(take(into: repo, git: { args, _ in args.first == "rev-parse" ? (0, "true\n") : (128, "") }), 1, errText)
        XCTAssertTrue(errText.contains("check-ignore exit 128"), errText)
    }

    func testNoRepoAboveMeansGitIsNotNeeded() {
        XCTAssertEqual(take(git: { _, _ in nil }), 0, errText)
    }

    func testADanglingGitFileRefuses() throws {
        let repo = root.appendingPathComponent("dangling")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try write("gitdir: /nonexistent/gitdir\n", to: repo.appendingPathComponent(".git"))
        XCTAssertEqual(take(into: repo), 1, errText)
        XCTAssertTrue(errText.contains("working tree"), errText)
    }

    func testAGitShimEarlierInPathCannotAnswerForTheGate() throws {
        let shimDir = root.appendingPathComponent("shim")
        try FileManager.default.createDirectory(at: shimDir, withIntermediateDirectories: true)
        let shim = shimDir.appendingPathComponent("git")
        try write("#!/bin/sh\nexit 0\n", to: shim)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
        let saved = ProcessInfo.processInfo.environment["PATH"] ?? ""
        setenv("PATH", shimDir.path + ":" + saved, 1)
        defer { setenv("PATH", saved, 1) }
        let repo = try initRepo("repo-shim")
        XCTAssertEqual(take(into: repo), 1, errText)
        XCTAssertTrue(errText.contains("does not ignore it"), errText)
    }

    func testTheTargetReposFsmonitorHookIsNotExecutedByTheGate() throws {
        let repo = try initRepo("repo-fsmonitor")
        let marker = root.appendingPathComponent("fsmonitor-ran")
        let hook = repo.appendingPathComponent("hook.sh")
        try write("#!/bin/sh\ntouch '\(marker.path)'\nexit 0\n", to: hook)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        XCTAssertEqual(GitFixture.run(["config", "core.fsmonitor", hook.path], in: repo), 0)
        XCTAssertEqual(take(into: repo), 1, "repo 沒忽略輸出檔：\(errText)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "閘不得執行目標 repo 設定的命令")
    }

    func testTheTempNameKeepsTheDestinationNameAsItsSuffix() {
        XCTAssertEqual(OutputFile.tempPath(for: "/a/b/w.pdf", token: "T0K"), "/a/b/.T0K.w.pdf")
        XCTAssertEqual(OutputFile.tempPath(for: "w.pdf", token: "T0K"), "./.T0K.w.pdf")
    }

    func testSuffixIgnoreRulesAlsoCoverTheTempNames() throws {
        let repo = try initRepo("repo-suffix")
        try write("*.pdf\n", to: repo.appendingPathComponent(".gitignore"))
        for name in ["w.pdf", "w.unverified.pdf"] {
            let temp = OutputFile.tempPath(for: repo.appendingPathComponent(name).path, token: UUID().uuidString)
            XCTAssertEqual(GitFixture.run(["check-ignore", "-q", "--", temp], in: repo), 0, temp)
        }
        XCTAssertEqual(take(into: repo), 0, errText)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: repo.path).filter { $0.hasPrefix(".") && $0 != ".git" && $0 != ".gitignore" }, [], "不留暫存檔")
    }

    /// 只忽略最終檔名（逐字）的樹：暫存檔名沒被忽略，閘拒絕、說出是暫存檔。
    func testATreeThatIgnoresOnlyTheFinalNamesIsRefusedBecauseOfTheTempName() throws {
        let repo = try initRepo("repo-exact")
        try write("/w.pdf\n/w.unverified.pdf\n", to: repo.appendingPathComponent(".gitignore"))
        XCTAssertEqual(take(into: repo), 1, errText)
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
