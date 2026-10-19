import XCTest
@testable import AkashicSkillTools
@testable import AkashicStoreIO

/// #613 b45：b44 verify 對 b43 `redactingPageText` 的 finding——前一個 authority 吞掉後面的 special scheme 時，它緊接一個斜線的那組帳密原樣
/// 印出（第 2、5、6、11 則，b41 有剝）；第一個網址沒有 `//`、後面又有 `scheme://` 或說明文字時，它的路徑參數與 ASP.NET 群組原樣印出（第 3、11、
/// 16、19 則，b41 有剝）；帳密之後兩個反斜線再接 `@` 時印出反斜線之前的帳密（第 10、20 則，b41 同形）；帳密含反斜線而沒有 `//`（INFO 28）。
/// 與 `FulltextFetchPathTests` 同一個記憶體內的假瀏覽器，不碰 Safari、不連網。
final class FulltextB45Tests: XCTestCase {
    typealias Scenario = FulltextFetchPathTests.Scenario
    typealias FakeBrowser = FulltextFetchPathTests.FakeBrowser

    private var root: URL!
    private var stderr: [String] = []

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fetch-b45-\(UUID().uuidString)")
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

    private func pyRepr(_ s: String) -> String { s.debugDescription }

    // MARK: 第 2、5、6、11 則：前一個 authority 吞掉的 special scheme 之後只有一個斜線

    /// 每一組都取自 b44 的重現（logic、regression、devil's advocate、requirements 四席）。帳密的記號是 `SEC`。
    static let nestedAuthorities = [
        "https://u:p@h https:/v:SECRET@x/y",
        "https://u:p@h https:\\v:SECRET@x/y",
        "https://u:p@h https:/v:SEC%40RET@x/y",
        "https://u:p@h https:/v:SEC;RET@x/y",
        "GET https://a.example https:/v:SECRET@x/y",
        "GET https://a.example ftp:/v:SECRET@x/y",
        "GET https://a.example ws:/v:SECRET@x/y",
        "https://a https:/u:SECRET@h/x",
        "//https:/u:SECRET@h/x",
        "GET //cdn.example https:/user:SECRET@host/x.pdf",
        "FOO https://http:/u:SECRET@h/x",
        "FOO //http:/u:SECRET@h/x",
        "FOO https:https:/u:SECRET@h/x",
        "FOO \\\\ws:/u:SECRET@h/x",
        "FOO ssh://a b https:/u:SECRET@h/x",
        "FOO //x https:/u:SECRET@h/x",
        "FOO //x HTTPS:/u:SECRET@h/x",
        "//https:/https:/u:SECRET@h/x",   // 兩層
    ]

    func testCredentialsAfterASwallowedSpecialSchemeAreRemoved() {
        for text in Self.nestedAuthorities {
            let out = FulltextFetch.redactingPageText(text)
            XCTAssertFalse(out.contains("SEC"), "\(pyRepr(text)) → \(pyRepr(out))")
            // 去一次就乾淨：再過一次不再變（b44 第 11 則：b43 對這個形狀不冪等）
            XCTAssertEqual(FulltextFetch.redactingPageText(out), out, "\(pyRepr(text))")
        }
        // 與 b41 逐字相同（b44 的差分實測取的那幾組）
        XCTAssertEqual(FulltextFetch.redactingPageText("https://u:p@h https:/v:SECRET@x/y"), "https://h https:/x/y")
        XCTAssertEqual(FulltextFetch.redactingPageText("//https:/u:SECRET@h/x"), "//https:/h/x")
        XCTAssertEqual(FulltextFetch.redactingPageText("GET //cdn.example https:/user:SECRET@host/x.pdf"), "GET //cdn.example https:/host/x.pdf")
        // b41 印 `\\HTTPS:\`；照 RFC 3986 讀，`HTTPS:\ax@` 整段是帳密（反斜線之後還有 `@`），兩種讀法說法不同
        XCTAssertEqual(PyText.string(FulltextFetch.withoutPageUserinfo(Scalars("\\\\HTTPS:\\ax@".unicodeScalars))), "\\\\<ambiguous-host>")
    }

    /// b44 的 devil's advocate 與 regression 兩席對 b41 的正規表示式做了差分，找到 98 個 b43 剝得比 b41 少的字串、0 個多的。這裡把 b41 的那一條
    /// 放進測試當 oracle：**沒有空白、引號、角括號、反斜線的字**（兩者對 authority 的結束一致的範圍）上，`withoutPageUserinfo` 與它逐字相同。
    /// 有反斜線時 b45 多一件事（兩種讀法對帳密說法不同時印 `<ambiguous-host>`），所以只要求：沒印 `<ambiguous-host>` 時逐字相同，而且留下的
    /// `@` 不比 b41 多。決定性的偽隨機，每次跑同一批。
    static let b41Userinfo = try! NSRegularExpression(pattern: #"(?i)((?:https?|wss?|ftp|file):[/\\]*|[/\\]{2,})[^/\\?#\s"<>]*@"#)

    static func b41(_ s: String) -> String {
        b41Userinfo.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "$1")
    }

    private func fuzz(alphabet: [String], cases: Int, seed: UInt64, check: (String, String, String) -> Void) {
        var state = seed
        func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state >> 33 }
        for _ in 0..<cases {
            let n = Int(next() % 14) + 1
            let s = (0..<n).map { _ in alphabet[Int(next() % UInt64(alphabet.count))] }.joined()
            check(s, PyText.string(FulltextFetch.withoutPageUserinfo(Scalars(s.unicodeScalars))), Self.b41(s))
        }
    }

    func testUserinfoStepMatchesB41OnTextWithoutWhitespaceOrBackslashes() {
        let alphabet = ["h", "t", "p", "s", ":", "/", "@", "u", "x", "?", "#", "https:", "http:", "HTTPS:", "ws:", "ftp:", "file:", "//", ".", ";", "%40"]
        var diverged: [String] = []
        fuzz(alphabet: alphabet, cases: 60_000, seed: 0x613B45) { s, mine, oracle in
            if mine != oracle, diverged.count < 5 { diverged.append("\(pyRepr(s)) → b45 \(pyRepr(mine))，b41 \(pyRepr(oracle))") }
        }
        XCTAssertEqual(diverged, [], "與 b41 不同")
    }

    func testUserinfoStepNeverKeepsMoreThanB41WithBackslashes() {
        let alphabet = ["h", "p", ":", "/", "\\", "@", "u", "x", "?", "#", "https:", "HTTP:", "ws:", "//", "\\\\", "S"]
        var diverged: [String] = []
        fuzz(alphabet: alphabet, cases: 60_000, seed: 0xB45613) { s, mine, oracle in
            let ats = { (t: String) in t.unicodeScalars.filter { $0 == "@" }.count }
            let ok = mine.contains(FulltextFetch.ambiguousHost) ? ats(mine) <= ats(oracle) : mine == oracle
            if !ok, diverged.count < 5 { diverged.append("\(pyRepr(s)) → b45 \(pyRepr(mine))，b41 \(pyRepr(oracle))") }
        }
        XCTAssertEqual(diverged, [], "比 b41 留得多、或沒有兩種讀法卻與 b41 不同")
    }

    // MARK: 第 3、11、16、19 則：第一個網址沒有 `//` 時的路徑參數與 ASP.NET 群組

    func testPathParametersOfAFirstURLWithoutTwoSlashesAreRemoved() {
        // 與 b41 逐字相同
        XCTAssertEqual(FulltextFetch.redactingPageText("FOO https:/h.example/x;jsessionid=SECRET then http://other/y"),
                       "FOO https:/h.example/x then http://other/y")
        XCTAssertEqual(FulltextFetch.redactingPageText("FOO https:h.example/x;jsessionid=SECRET see http://o/y"),
                       "FOO https:h.example/x see http://o/y")
        XCTAssertEqual(FulltextFetch.redactingPageText("FOO //h.example/a/(X(SECRET)) more"), "FOO //h.example/a more")
        XCTAssertEqual(FulltextFetch.redactingPageText("x https:h/x;a=SECRET y https://h3/y"), "x https:h/x y https://h3/y")
        let texts = [
            "FOO https:h.example/a/(X(SECRET)) more",
            "FOO https:/h.example/a/(X(SECRET)) more",
            "GET https:/\\h/x;jsessionid=SECRET more://x",
            "GET \\\\h/(S(SECRET))/x https://z.example/y",
            "FOO https:/h/(S(SECRET))/x see https://h2/y",
            "FOO https:h/x%3Bjsessionid%3DSECRET see https://h2/y",
            "FOO https:/h/x;jsessionid=SECRET;http://other/y",   // 沒有空白、黏在後面的網址上
            // b43 已經剝的，照舊剝
            "FOO https://h/x y;jsessionid=SECRET",
            "FOO https://h/x;jsession id=SECRET",
            "FOO https://h/a/(S(SEC RET))/x",
            "FOO //h.example/a/(X(SECRET)) more https://h2/y?sig=SECRET",
        ]
        for text in texts {
            let out = FulltextFetch.redactingPageText(text)
            XCTAssertFalse(out.contains("SEC"), "\(pyRepr(text)) → \(pyRepr(out))")
            XCTAssertFalse(out.contains("sig="), "\(pyRepr(text)) → \(pyRepr(out))")
        }
    }

    /// `plainURL` 本身（同一個判斷的另一條路徑：`redactingURLs` 與 safari-browser 的錯誤那一行都經過它）：沒有 authority 的網址後面接 `scheme://`
    /// 時，`://` 之前的那一段也去路徑參數。
    func testPlainURLRemovesPathParametersBeforeALaterSeparator() {
        XCTAssertEqual(FulltextFetch.plainURL("https:/h/x;jsessionid=SECRET;http://other/y"), "https:/h/x;http://other/y")
        XCTAssertFalse(FulltextFetch.plainURL("\\\\h/(S(SECRET))/x;b://z").contains("SECRET"))
        XCTAssertEqual(FulltextFetch.plainURL("GET https:/\t/u:SECRET@h/x"), "GET https://h/x")   // b41 那一格照舊
    }

    // MARK: 第 10、20 則、INFO 28：反斜線之後還有 `@`

    func testABackslashThenAtPrintsTheAmbiguousHostInEveryShape() {
        XCTAssertEqual(FulltextFetch.redactingPageText("GET https://user:SECRET\\\\@pub.example/x"), "GET https://<ambiguous-host>/x")
        XCTAssertEqual(FulltextFetch.redactingPageText("GET https://user:SECRET\\\\\\@pub.example/x"), "GET https://<ambiguous-host>/x")
        XCTAssertEqual(FulltextFetch.redactingPageText("//user:SECRET\\\\@pub.example/x"), "//<ambiguous-host>/x")
        XCTAssertEqual(FulltextFetch.redactingPageText("GET https://user:SECRET\\@pub.example/x.pdf"), "GET https://<ambiguous-host>/x.pdf")   // 一個反斜線（b39）照舊
        let texts = [
            "ssh://u:SEC\\\\RET@h/x",
            "GET https:u:SEC\\RET@h/x",
            "see https://a/b //u:SEC\\RET@h/x",
            "GET https://a:SECRET@c\\\\d@e.example/x",
        ]
        for text in texts {
            let out = FulltextFetch.redactingPageText(text)
            XCTAssertFalse(out.contains("SEC"), "\(pyRepr(text)) → \(pyRepr(out))")
            XCTAssertTrue(out.contains(FulltextFetch.ambiguousHost), "\(pyRepr(text)) → \(pyRepr(out))")
        }
    }

    // MARK: 完整流程

    func testTheLinkScriptsAnswerLosesTheNestedCredentialAndThePathParameters() {
        var s = Scenario()
        s.link = "https://u:p@h https:/v:SECRET@x/y"
        XCTAssertEqual(run(s), 1, errText)
        XCTAssertTrue(errText.contains("unexpected answer from the link script: https://h https:/x/y"), errText)
        XCTAssertFalse(errText.contains("SECRET"), errText)

        s.link = "FOO https:/h.example/x;jsessionid=SECRET then http://other/y"
        XCTAssertEqual(run(s), 1, errText)
        XCTAssertFalse(errText.contains("SECRET"), errText)

        s.link = "GET https://user:SECRET\\\\@pub.example/x.pdf"
        XCTAssertEqual(run(s), 1, errText)
        XCTAssertTrue(errText.contains("<ambiguous-host>"), errText)
        XCTAssertFalse(errText.contains("SECRET"), errText)
    }

    // MARK: LOW 13：網址很多時

    /// 每一個網址都經過 `plainURL`（第 3 步逐段一次、`redactingURLs` 收尾一次）。b44 量到 b43 的 `'https://h/x '` × 100,000 在 debug 建置要
    /// 5.2 秒（每次呼叫重編兩條正規表示式）；兩條改成只編一次。這裡用 20,000 個、上限 3 秒（與 `FulltextB43Tests` 同一個上限）。
    func testManyURLsStayWithinTheBound() {
        for (name, text) in [("'https://h/x ' × 20,000", String(repeating: "https://h/x ", count: 20_000)),
                             ("'a://b ' × 20,000", String(repeating: "a://b ", count: 20_000)),
                             ("'https:/h/x;j=1 ' × 20,000", String(repeating: "https:/h/x;j=1 ", count: 20_000))] {
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = FulltextFetch.redactingPageText(text)
            let t = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
            XCTAssertLessThan(t, 3, "\(name)：\(String(format: "%.2f", t)) 秒")
        }
    }
}
