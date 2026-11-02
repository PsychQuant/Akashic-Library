import XCTest
@testable import AkashicSkillTools
@testable import AkashicStoreIO

/// #613 b47：b46 verify 對 b45 `redactingPageText` 的 finding——路徑參數的**值**跨過空白、`"`、`<`、`>` 時，b45 的逐段處理只去到界線，
/// 界線之後的尾巴（值以引號或角括號開頭時是整個值）原樣印出，b43 整段讀、值是 `[^;/]*`，整個去掉（第 0、1、4 則）；`plainURL` 的無
/// authority 分支對第一個 `://` 之前的整段去路徑參數，吃掉說明文字與 scheme（INFO 22）；authority 在反斜線之後的 `;名 字=值`（INFO 19）；
/// 以反斜線分開的 ASP.NET 群組（INFO 16）。
/// 與 `FulltextFetchPathTests` 同一個記憶體內的假瀏覽器，不碰 Safari、不連網。
final class FulltextB47Tests: XCTestCase {
    typealias Scenario = FulltextFetchPathTests.Scenario
    typealias FakeBrowser = FulltextFetchPathTests.FakeBrowser

    private var root: URL!
    private var stderr: [String] = []

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fetch-b47-\(UUID().uuidString)")
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

    // MARK: 第 0、1、4 則：值跨過界線

    /// 每一組都取自 b46 的重現（regression、devil's advocate、logic 三席），右邊是 b43 印的（b47 要逐字相同）。
    static let crossingValues: [(text: String, b43: String)] = [
        ("https://h/x;jsessionid=SEC RET", "https://h/x"),
        ("https://h/x;jsessionid=SEC<RET", "https://h/x"),
        ("https://h/x;jsessionid=SEC\"RET", "https://h/x"),
        ("GET https://h/x;jsessionid=\"SECRET\" more", "GET https://h/x"),
        ("https://h/x;sig=<SECRET>", "https://h/x"),
        ("ftp://h/x;PHPSESSID=abc def ghi", "ftp://h/x"),
        ("https://h/x%3Bsid%3Dab cd", "https://h/x"),
        ("https://h/(S(AB CD))/x;sid=ZZ YY/z", "https://h/x/z"),
        ("x https://h/x;k=a b;j=SECRET more", "x https://h/x"),
        ("https://h/;jsid=a SECRET\"", "https://h"),
        ("https://h/;a=b c=SECRET", "https://h"),
        // 同形：值在第二段路徑、接著還有路徑；名字也跨過界線；NBSP
        ("GET https://h/a;sid=SEC RET/b more", "GET https://h/a/b more"),
        ("GET https://h/a;j id=SEC RET", "GET https://h/a"),
        ("GET https://h/a;sid=SEC\u{00A0}RET", "GET https://h/a"),
    ]

    func testPathParameterValuesThatCrossABoundaryAreRemovedLikeB43() {
        for (text, expected) in Self.crossingValues {
            let out = FulltextFetch.redactingPageText(text)
            XCTAssertEqual(out, expected, "\(pyRepr(text))")
            XCTAssertEqual(B43.redactingPageText(text), expected, "oracle：\(pyRepr(text))")
            for marker in ["SEC", "RET", "abc", "def", "ghi", "ab cd", "ZZ", "YY", "AB CD"] where !expected.contains(marker) {
                XCTAssertFalse(out.contains(marker), "\(pyRepr(text)) → \(pyRepr(out))")
            }
        }
    }

    /// INFO 19：authority 在反斜線之後的那一段（`hostPort` 不印）裡有名字夾空白的 `;名 字=值`——b45 逐段時那一段先被丟掉、`;` 跟著不見，
    /// 空白之後的 `id=SEC` 原樣印出。整段讀時，authority 從反斜線到第一個 `/` 整段不印（與 b43 相同）。
    func testAParameterInTheAuthorityTailAfterABackslashIsNotPrinted() {
        XCTAssertEqual(FulltextFetch.redactingPageText("FOO https://h\\x;j id=SEC"), "FOO https://h")
        XCTAssertEqual(FulltextFetch.redactingPageText("//h\\x;j id=SEC/x"), "//h/x")
        XCTAssertEqual(FulltextFetch.redactingPageText("FOO https://h\\x more SEC/y"), "FOO https://h/y")
    }

    /// b45 為了 b43 的兩個洞加的逐段處理照舊：沒有 `//` 的第一個網址後面接著 `scheme://` 時，`://` 之前那一段 b43 原樣印出（連同路徑參數），
    /// 那一段仍由逐段處理去掉（與 b41 逐字相同）；ASP.NET 群組後面接著空白與字。
    func testTheB45ShapesStillComeOutTheSame() {
        XCTAssertEqual(FulltextFetch.redactingPageText("FOO https:/h.example/x;jsessionid=SECRET then http://other/y"),
                       "FOO https:/h.example/x then http://other/y")
        XCTAssertEqual(FulltextFetch.redactingPageText("FOO https:h.example/x;jsessionid=SECRET see http://o/y"),
                       "FOO https:h.example/x see http://o/y")
        XCTAssertEqual(FulltextFetch.redactingPageText("FOO //h.example/a/(X(SECRET)) more"), "FOO //h.example/a more")
        XCTAssertEqual(FulltextFetch.redactingPageText("x https:h/x;a=SECRET y https://h3/y"), "x https:h/x y https://h3/y")
    }

    // MARK: 與 b43 的差分

    /// 值、名字、群組各種形狀，夾空白、引號、角括號、NBSP、`%3B`／`%3D`，放在帶 `//` 的網址、沒有 `//` 的網址、反斜線開頭的網址後面，
    /// 後面再接說明文字、路徑、別的網址。b43 印出的字裡沒有 `SECRET` 時，b47 也不得有（b47 不比 b43 漏）。決定性的偽隨機，每次跑同一批。
    func testNeverLeaksWhereB43WasClean() {
        let prefixes = ["", "GET ", "x ", "see: \"", "FOO <"]
        let urls = ["https://h/x", "ftp://h/a/b", "//h/x", "https:h/x", "https:/h/x", "HTTPS://H/x", "\\\\h/x", "https://h\\q/x", "ws://h"]
        let names = ["jsessionid", "sid", "PHPSESSID", "k", "j id", "a\"b", "x<y"]
        let seps = [(";", "="), ("%3B", "%3D"), (";", "%3d"), ("%3b", "=")]
        let chunks = ["SECRET", "SEC", "RET", "a", "b c", "\"SECRET\"", "<SECRET>", "SEC RET", "SE\u{00A0}CRET"]
        let glue = [" ", "\"", "<", ">", "  ", "\u{00A0}", "", "\u{2003}"]
        let tails = ["", " more", "/z", "/z more", " more https://o/y", "\"", ">", ";b", "/(S(AB CD))/q", " then http://o/y", " /q", "\" x"]
        var state: UInt64 = 0x613B47
        func next(_ n: Int) -> Int { state = state &* 6364136223846793005 &+ 1442695040888963407; return Int((state >> 33) % UInt64(n)) }
        var leaks: [String] = [], printedMore: [String] = [], cleanInB43 = 0
        for _ in 0..<40_000 {
            var text = prefixes[next(prefixes.count)] + urls[next(urls.count)]
            for _ in 0...next(3) {
                let (semi, eq) = seps[next(seps.count)]
                var value = chunks[next(chunks.count)]
                for _ in 0..<next(3) { value += glue[next(glue.count)] + chunks[next(chunks.count)] }
                text += semi + names[next(names.count)] + eq + value
                if next(3) == 0 { text += "/p" }
            }
            text += tails[next(tails.count)]
            let mine = FulltextFetch.redactingPageText(text), oracle = B43.redactingPageText(text)
            // 不比 b43 印得多：b47 印的是 b43 印的子序列（兩邊都沒有 `<ambiguous-host>` 時——那是第 2 步的事，與這一輪無關）
            if !mine.contains(FulltextFetch.ambiguousHost), !oracle.contains(FulltextFetch.ambiguousHost),
               !Self.isSubsequence(Array(mine.unicodeScalars), of: Array(oracle.unicodeScalars)), printedMore.count < 5 {
                printedMore.append("\(pyRepr(text)) → b47 \(pyRepr(mine))，b43 \(pyRepr(oracle))")
            }
            guard !oracle.contains("SECRET") else { continue }
            cleanInB43 += 1
            if mine.contains("SECRET"), leaks.count < 5 { leaks.append("\(pyRepr(text)) → b47 \(pyRepr(mine))，b43 \(pyRepr(oracle))") }
        }
        XCTAssertGreaterThan(cleanInB43, 10_000, "產生的字大多要是 b43 乾淨的，差分才有意義")
        XCTAssertEqual(leaks, [], "b43 乾淨、b47 漏")
        XCTAssertEqual(printedMore, [], "b47 印了 b43 沒印的字")
    }

    static func isSubsequence(_ a: [Unicode.Scalar], of b: [Unicode.Scalar]) -> Bool {
        var j = 0
        for c in a {
            while j < b.count, b[j] != c { j += 1 }
            guard j < b.count else { return false }
            j += 1
        }
        return true
    }

    /// 網址帶 `//` 的時候，b43 對整段的去法這裡一字不差地做（scheme 與主機段已是正規的寫法時，印出的字與 b43 逐字相同）。
    func testURLsWithAnAuthorityComeOutExactlyAsInB43() {
        let urls = ["https://h/x", "ftp://h/a/b", "//h/x", "https://h\\q/x"]
        let values = ["SECRET", "SEC RET", "\"SECRET\" more", "<SECRET> more", "a b c", "x\u{00A0}y", "SEC\"RET"]
        let tails = ["", " more words", "/z", "/z more", " more https://o/y", " then http://o/y?sig=1", "/(S(AB CD))/q", ";b=c d/e"]
        var diverged: [String] = []
        for u in urls {
            for v in values {
                for t in tails {
                    for p in ["", "GET "] {
                        let text = p + u + ";jsessionid=" + v + t
                        let mine = FulltextFetch.redactingPageText(text), oracle = B43.redactingPageText(text)
                        if mine != oracle, diverged.count < 5 { diverged.append("\(pyRepr(text)) → b47 \(pyRepr(mine))，b43 \(pyRepr(oracle))") }
                    }
                }
            }
        }
        XCTAssertEqual(diverged, [], "與 b43 不同")
    }

    // MARK: INFO 22：`plainURL` 只對網址本身去路徑參數

    func testPlainURLLeavesTheTextBeforeTheURLAsIs() {
        for text in ["Error: navigation failed; code=5 for https://h/x", "document 3; of=4/5 https://h/x",
                     "a; b=c https://h/x;sid=SECRET", "see; x=y //h/x"] {
            XCTAssertEqual(FulltextFetch.plainURL(text), B43.plainURL(text), "\(pyRepr(text))")
        }
        XCTAssertEqual(FulltextFetch.plainURL("Error: navigation failed; code=5 for https://h/x"), "Error: navigation failed; code=5 for https://h/x")
        XCTAssertEqual(FulltextFetch.plainURL("document 3; of=4/5 https://h/x"), "document 3; of=4/5 https://h/x")
        // b45 的那幾格照舊：`://` 之前那一段本身是網址（從它的起點去）
        XCTAssertEqual(FulltextFetch.plainURL("https:/h/x;jsessionid=SECRET;http://other/y"), "https:/h/x;http://other/y")
        XCTAssertFalse(FulltextFetch.plainURL("\\\\h/(S(SECRET))/x;b://z").contains("SECRET"))
        XCTAssertEqual(FulltextFetch.plainURL("GET https:/h/x;jsessionid=SECRET;http://other/y"), "GET https:/h/x;http://other/y")
        // 只去那個網址本身——到第一個空白、`"`、`<`、`>` 為止；之後到 `://` 的字原樣（與 b43 相同），後面那個網址的 scheme 留著（b45 吃掉它）
        XCTAssertEqual(FulltextFetch.plainURL("https:h/x;k=SECRET more https://z/q"), "https:h/x more https://z/q")
        XCTAssertEqual(FulltextFetch.plainURL("x https:h/y;k=SECRET extra; code=5 for https://z"), "x https:h/y extra; code=5 for https://z")
        XCTAssertEqual(FulltextFetch.plainURL("see https:h/x;k=SECRET\"and\" https://z"), "see https:h/x\"and\" https://z")
        for text in ["https:h/x;k=SECRET more https://z/q", "x https:h/y;k=SECRET extra; code=5 for https://z"] {
            // b43 那一段整段原樣：印的是它的子序列，少的只有那個網址自己的路徑參數
            XCTAssertTrue(Self.isSubsequence(Array(FulltextFetch.plainURL(text).unicodeScalars), of: Array(B43.plainURL(text).unicodeScalars)), text)
        }
        // 不在保證裡的（說明那一句）：值跨過界線時，界線之後的部分原樣（b43 整段原樣、b45 連同之後的字與 scheme 去掉）
        XCTAssertEqual(FulltextFetch.plainURL("https:h/x;k=SEC RET https://z"), "https:h/x RET https://z")
        XCTAssertEqual(B43.plainURL("https:h/x;k=SEC RET https://z"), "https:h/x;k=SEC RET https://z")
    }

    // MARK: INFO 16：反斜線分開的 ASP.NET 群組；第 2 步吞掉唯一的網址起點

    func testAnASPNetGroupBeforeABackslashIsRemoved() {
        XCTAssertEqual(FulltextFetch.plainURL("https://h/(S(SECRET))\\x"), "https://h/x")
        XCTAssertEqual(FulltextFetch.plainURL("https://h/a\\(S(SECRET))(F(SEC))\\b/c"), "https://h/a\\b/c")
        XCTAssertEqual(FulltextFetch.plainURL("https://h/(S(SECRET))\\"), "https://h")
        XCTAssertEqual(FulltextFetch.redactingPageText("FOO https://h/(S(SECRET))\\x more"), "FOO https://h/x more")
        XCTAssertEqual(FulltextFetch.redactingPageText("FOO \\\\h/(S(SECRET))\\x"), "FOO \\\\h/x")
        // 只丟群組；路徑參數的值照舊跨過反斜線（b43 同）
        XCTAssertEqual(FulltextFetch.plainURL("https://h/x;k=SEC\\RET/y"), "https://h/x/y")
        XCTAssertEqual(B43.plainURL("https://h/x;k=SEC\\RET/y"), "https://h/x/y")
    }

    /// 說明裡「不在保證裡的」那一項釘住現況：第 2 步把 `ws:` 那一段印成 `<ambiguous-host>`，`\\` 前一個字是 scheme 字元、不是起點，第 3 步沒有網址
    /// 可處理（b41、b43 同）。這一格變了，說明要跟著改。
    func testWhenStepTwoSwallowsTheOnlyURLStartTheRestIsAsIs() {
        XCTAssertEqual(FulltextFetch.redactingPageText("GET\\\\ws:\\\\%3Bk%3DSECRET@/;a=SECRET"), "GET\\\\<ambiguous-host>/;a=SECRET")
    }

    // MARK: 完整流程

    /// `unexpected answer from the link script` 那一行（method 不是 GET／POST 的回答原樣進 `redactingPageText`）；GET 的回答走 `points off-site`
    /// 那一行（先過 `plainURL`，b45 也不漏）。
    func testTheLinkScriptsAnswerLosesAValueThatCrossesAQuote() {
        var s = Scenario()
        s.link = "FOO https://h/x;jsessionid=\"SECRET\" more"
        XCTAssertEqual(run(s), 1, errText)
        XCTAssertTrue(errText.contains("unexpected answer from the link script: FOO https://h/x"), errText)
        XCTAssertFalse(errText.contains("SECRET"), errText)

        s.link = "GET https://h/x;jsessionid=\"SECRET\" more"
        XCTAssertEqual(run(s), 1, errText)
        XCTAssertTrue(errText.contains("points off-site"), errText)
        XCTAssertFalse(errText.contains("SECRET"), errText)

        s.link = "FOO https://h/x;sig=<SEC RET> tail"
        XCTAssertEqual(run(s), 1, errText)
        XCTAssertFalse(errText.contains("SEC"), errText)
        XCTAssertFalse(errText.contains("RET"), errText)
    }
}

/// b43（6bc979f7）的 `redactingPageText` 第 1–3 步與它用到的 `plainURL`、`withoutPathParameters`、`withoutPageUserinfo`——差分的 oracle。
/// 逐字抄自那個 commit（`URLSplit`、`firstPageURLStart`、`redactingURLs` 的正規表示式之後沒有改，直接用現在的）。
enum B43 {
    static func plainURL(_ url: String) -> String {
        var s = url
        if let cut = s.unicodeScalars.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            s = String(String.UnicodeScalarView(s.unicodeScalars[..<cut]))
        }
        let parts = URLSplit(s)
        if parts.hasAuthority {
            let head = parts.scheme.isEmpty ? "//" : PyText.string(parts.scheme) + "://"
            return head + printedHostPort(parts) + withoutPathParameters(parts.path)
        }
        let scalars = Array(s.unicodeScalars.filter { $0 != "\t" && $0 != "\n" && $0 != "\r" })
        guard let sep = scalars.indices.first(where: { PyText.hasPrefix(scalars, [":", "/", "/"], at: $0) }) else {
            return withoutPathParameters(s)
        }
        let inner = URLSplit("//" + PyText.string(Array(scalars[(sep + 3)...])))
        return PyText.string(Array(scalars[..<sep])) + "://" + printedHostPort(inner) + withoutPathParameters(inner.path)
    }

    static func printedHostPort(_ parts: URLSplit) -> String {
        let n = parts.netloc
        if let backslash = n.firstIndex(of: "\\"), let at = n.lastIndex(of: "@"), backslash < at { return FulltextFetch.ambiguousHost }
        return parts.hostPort
    }

    static let param = try! NSRegularExpression(pattern: #"(?:;|%3[Bb])(?:(?!%3[BbDd])[^;=/])+(?:=|%3[Dd])(?:(?!%3[Bb])[^;/])*"#)
    static let aspNetSession = try! NSRegularExpression(pattern: #"^(?:\((?:[A-Za-z]\([^()/]*\))+\))+$"#)

    static func withoutPathParameters(_ path: String) -> String {
        var kept: [String] = []
        for segment in path.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            let range = NSRange(segment.startIndex..., in: segment)
            if aspNetSession.firstMatch(in: segment, range: range) != nil { continue }
            let stripped = param.stringByReplacingMatches(in: segment, range: range, withTemplate: "")
            if stripped.isEmpty, !segment.isEmpty { continue }
            kept.append(stripped)
        }
        return kept.joined(separator: "/")
    }

    static let urlPattern = try! NSRegularExpression(pattern: #"(?i)(?<![A-Za-z0-9+.-])[a-z][a-z0-9+.-]*://[^\s"<>]+"#)

    static func redactingURLs(_ text: String) -> String {
        let ns = text as NSString
        var out = "", last = 0
        for m in urlPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last)) + plainURL(ns.substring(with: m.range))
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }

    static let specialSchemes: [Scalars] = ["https:", "http:", "wss:", "ws:", "ftp:", "file:"].map { Scalars($0.unicodeScalars) }

    static func specialSchemeEnd(_ s: Scalars, at i: Int) -> Int? {
        for p in specialSchemes {
            guard i + p.count <= s.count else { continue }
            if (0..<p.count).allSatisfy({ k in
                let c = s[i + k]
                return c == p[k] || (c.isASCII && c.properties.isUppercase && Unicode.Scalar(c.value + 0x20) == p[k])
            }) { return i + p.count }
        }
        return nil
    }

    static func isSlash(_ c: Unicode.Scalar) -> Bool { c == "/" || c == "\\" }

    static func withoutPageUserinfo(_ s: Scalars) -> Scalars {
        var out = Scalars()
        var i = 0
        while i < s.count {
            var start: Int? = nil
            if let k = specialSchemeEnd(s, at: i) {
                var m = k
                while m < s.count, isSlash(s[m]) { m += 1 }
                start = m
            } else if isSlash(s[i]) {
                var m = i
                while m < s.count, isSlash(s[m]) { m += 1 }
                if m - i >= 2 { start = m } else { out.append(s[i]); i += 1; continue }
            }
            guard let from = start else { out.append(s[i]); i += 1; continue }
            out.append(contentsOf: s[i..<from])
            var end = from, lastAt: Int? = nil
            while end < s.count, !isSlash(s[end]), s[end] != "?", s[end] != "#" {
                if s[end] == "@" { lastAt = end }
                end += 1
            }
            out.append(contentsOf: s[(lastAt.map { $0 + 1 } ?? from)..<end])
            i = end
        }
        return out
    }

    static func redactingPageText(_ text: String) -> String {
        let stripped = Scalars(text.unicodeScalars.filter { $0 != "\t" && $0 != "\n" && $0 != "\r" })
        let withoutUserinfo = withoutPageUserinfo(stripped)
        guard let start = FulltextFetch.firstPageURLStart(withoutUserinfo) else { return redactingURLs(PyText.string(withoutUserinfo)) }
        return redactingURLs(PyText.string(Scalars(withoutUserinfo[..<start])) + plainURL(PyText.string(Scalars(withoutUserinfo[start...]))))
    }
}
