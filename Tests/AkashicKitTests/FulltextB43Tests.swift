import XCTest
@testable import AkashicSkillTools
@testable import AkashicStoreIO

/// #613 b43：b42 verify 對 b41 `redactingPageText` 的 finding——帳密那一條正規表示式對斜線串與重複的 `https:` 是平方的（頁面可以讓 CLI
/// 卡住幾分鐘）、帳密含普通空白（與引號、角括號、NBSP、VT）原樣印出、查詢在空白之後的那一段原樣印出。與 `FulltextFetchPathTests` 同一個
/// 記憶體內的假瀏覽器，不碰 Safari、不連網。
final class FulltextB43Tests: XCTestCase {
    typealias Scenario = FulltextFetchPathTests.Scenario
    typealias FakeBrowser = FulltextFetchPathTests.FakeBrowser

    private var root: URL!
    private var stderr: [String] = []

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fetch-b43-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    private func run(_ scenario: Scenario) -> Int32 {
        let browser = FakeBrowser(scenario)
        stderr = []
        let fetcher = FulltextFetch(browser: browser, sleeper: { _ in }, now: { FulltextFetchPathTests.now },
                                    out: { _ in }, err: { self.stderr.append($0) })
        return fetcher.run(.init(window: 5, landing: FulltextFetchPathTests.landing,
                                 ledger: root.appendingPathComponent("state/attempts.jsonl").path))
    }

    private var errText: String { stderr.joined(separator: "\n") }

    private func seconds(_ body: () -> Void) -> Double {
        let t0 = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
    }

    // MARK: MEDIUM 4、5、7：頁面給的字的長度不得讓去憑證變成平方

    /// 每一個形狀都是頁面寫得出來的：`citation_pdf_url` 是全是斜線的字串時 `new URL()` 丟例外、`linkJS` 原樣回傳（b42 的 logic、security、
    /// devil's advocate 三席各自量到：20,000 個斜線在 b41 要 25 秒以上，`'GET ' + '/' × 40000` 要 94 秒）。上限給得寬（debug 建置、
    /// 機器忙的時候），平方的寫法在這個大小遠遠超過它。
    static let hostilePageTexts: [(name: String, text: String)] = [
        ("20,000 個斜線", "GET " + String(repeating: "/", count: 20_000)),
        ("20,000 個反斜線", "GET " + String(repeating: "\\", count: 20_000)),
        ("20,000 個斜線與反斜線交錯", "GET " + String(repeating: "/\\", count: 10_000)),
        ("20,000 次 https:", String(repeating: "https:", count: 20_000)),
        ("20,000 次 https://", String(repeating: "https://", count: 20_000)),
        ("別站之後接 20,000 個斜線", "https://other.example/" + String(repeating: "/", count: 20_000) + "x.pdf"),
        ("20,000 次 //a", String(repeating: "//a", count: 20_000)),
        ("20,000 次 a@", "https://" + String(repeating: "a@", count: 20_000)),
        ("網址之前 400,000 個空白", String(repeating: " ", count: 400_000) + "https://u:p@h/x"),
    ]

    func testRedactingPageTextIsLinearOnHostileInput() {
        for (name, text) in Self.hostilePageTexts {
            let both = seconds { _ = FulltextFetch.redactingPageText(text); _ = FulltextFetch.redactingPageText(FulltextFetch.plainURL(text)) }
            XCTAssertLessThan(both, 3, "\(name)：\(String(format: "%.2f", both)) 秒")
        }
    }

    /// 完整流程：頁面給的連結是一長串斜線（`points off-site` 那一行），與連結那一段 JS 的回答本身就是一長串斜線（`unexpected answer` 那一行）。
    /// 前面的字原樣交給 `plainURL`：`GET` 之後先接 400,000 個空白（`URLSplit` 去掉前導空白先前是一個一個從陣列頭刪，平方：b42 沒有量到這一處，
    /// 同一個判斷掃過時找到——2026-10-20 量：200,000 個 1.8 秒；400,000 個在這支 debug 建置的測試裡 8.3 秒，改成一次切掉之後 0.1 秒）。
    func testTheOffSiteAndUnexpectedAnswerLinesReturnPromptlyOnHostileLinks() {
        var s = Scenario()
        for link in ["GET " + String(repeating: "/", count: 20_000),
                     "GET " + String(repeating: " ", count: 400_000) + "https://other.example/x.pdf",
                     "FOO " + String(repeating: "\\", count: 20_000)] {
            s.link = link
            var rc: Int32 = 0
            let t = seconds { rc = run(s) }
            XCTAssertEqual(rc, 1, errText)
            XCTAssertLessThan(t, 3, "\(String(format: "%.2f", t)) 秒：\(String(errText.prefix(200)))")
        }
    }

    /// 同一個判斷的另一處（b43 掃過時找到）：`normDOI` 去掉 `doi:` 之後的空白也是一個一個 `removeFirst`。PDF 的中繼資料是出版商寫的字。
    func testNormDOIIsLinearOnLeadingSpacesAfterThePrefix() {
        var out = ""
        let t = seconds { out = FulltextVerify.normDOI("doi:" + String(repeating: " ", count: 400_000) + "10.1/X") }
        XCTAssertEqual(out, "10.1/x")
        XCTAssertLessThan(t, 3, "\(String(format: "%.2f", t)) 秒")
    }

    // MARK: MEDIUM 0、LOW 12、13：帳密裡的空白、引號、角括號；空白之後的查詢與路徑參數

    /// WHATWG 讀網址時，authority 只在 `/`、`\`、`?`、`#` 結束——空白、`"`、`<`、`>` 在帳密裡會被百分比編碼，不結束它。頁面給的原始字串
    /// （`new URL()` 失敗時原樣回傳的 `citation_pdf_url`，或遮蔽了 API 的頁面寫的任何字）照同一個讀法剝。
    static let spacedCredentials = [
        "FOO https:u:SEC RET@h.example/x",
        "FOO https://u:SEC RET@h.example/x",
        "GET https://u:SEC RET@h/x?sig=1",
        "FOO https://u:SEC\u{00A0}RET@h/x",
        "FOO https://u:SEC\u{000B}RET@h/x",
        "FOO https://u:SEC\"RET@h/x",
        "FOO https://u:SEC<RET>@h/x",
        "FOO //u:SEC RET@h/x",
        "FOO https:/\\u:SEC RET@h/x",
        "FOO https://a.example/x https://v:SEC RET@b.example/y",
    ]

    func testCredentialsWithWhitespaceQuotesOrAngleBracketsAreRemoved() {
        for text in Self.spacedCredentials {
            let out = FulltextFetch.redactingPageText(text)
            XCTAssertFalse(out.contains("SEC"), "\(text.debugDescription) → \(out.debugDescription)")
            XCTAssertFalse(out.contains("RET"), "\(text.debugDescription) → \(out.debugDescription)")
        }
        XCTAssertEqual(FulltextFetch.redactingPageText("FOO https:u:SEC RET@h.example/x"), "FOO https:h.example/x")
        XCTAssertEqual(FulltextFetch.redactingPageText("FOO https://u:SEC RET@h.example/x"), "FOO https://h.example/x")
    }

    /// 查詢與片段一直到字串結尾（WHATWG：查詢在 `#` 結束、片段在字串結尾結束，空白不結束它們）；路徑參數同理。b41 的網址在空白處結束，
    /// `?title=a b&sig=SECRET` 的 ` b&sig=SECRET` 原樣留下。
    func testQueryAndPathParametersAfterASpaceAreRemoved() {
        let texts = [
            "FOO https://h/doc.pdf?title=a b&sig=SECRET",
            "FOO https://h/x?a=<b>&sig=SECRET",
            "FOO https://h/x#frag ment&sig=SECRET",
            "FOO https://h/x y;jsessionid=SECRET",
            "FOO //h/x?a b&sig=SECRET",
        ]
        for text in texts {
            let out = FulltextFetch.redactingPageText(text)
            XCTAssertFalse(out.contains("SECRET"), "\(text.debugDescription) → \(out.debugDescription)")
            XCTAssertFalse(out.contains("sig="), "\(text.debugDescription) → \(out.debugDescription)")
        }
        XCTAssertEqual(FulltextFetch.redactingPageText("FOO https://h/doc.pdf?title=a b&sig=SECRET"), "FOO https://h/doc.pdf")
    }

    /// 不帶網址的字、網址之前的字照樣；b41 已有的形狀照樣（`FulltextB41Tests.pageTexts` 另有一份）。
    func testTextWithoutAURLAndTheTextBeforeTheURLAreKept() {
        XCTAssertEqual(FulltextFetch.redactingPageText("missing value"), "missing value")
        XCTAssertEqual(FulltextFetch.redactingPageText("what? no link here, mail a@b"), "what? no link here, mail a@b")
        XCTAssertEqual(FulltextFetch.redactingPageText("FOO https://pub.example/x.pdf?sig=Q"), "FOO https://pub.example/x.pdf")
        XCTAssertEqual(FulltextFetch.redactingPageText("FOO https://a.example/x https://u:SECRET@b.example/y?sig=Q"),
                       "FOO https://a.example/x https://b.example/y")
        XCTAssertEqual(FulltextFetch.redactingPageText("https://<ambiguous-host>/x.pdf"), "https://<ambiguous-host>/x.pdf")
    }

    /// 完整流程：連結那一段 JS 的回答與頁面給的連結，帳密帶空白（後者埠號無效，`new URL()` 失敗、原樣回傳）。
    func testTheLinkScriptsAnswerAndTheOffSiteLinkLoseSpacedCredentials() {
        var s = Scenario()
        s.link = "FOO https:u:SEC RET@h.example/x"
        XCTAssertEqual(run(s), 1, errText)
        XCTAssertTrue(errText.contains("unexpected answer from the link script: FOO https:h.example/x"), errText)
        XCTAssertFalse(errText.contains("SEC"), errText)

        s.link = "FOO https://h/doc.pdf?title=a b&sig=SECRET"
        XCTAssertEqual(run(s), 1, errText)
        XCTAssertFalse(errText.contains("SECRET"), errText)

        s.link = "GET https:u:SEC RET@pub.example:99999/x.pdf?sig=Q"
        XCTAssertEqual(run(s), 1, errText)
        XCTAssertTrue(errText.contains("points off-site"), errText)
        XCTAssertFalse(errText.contains("SEC"), errText)
        XCTAssertFalse(errText.contains("sig="), errText)
    }
}
