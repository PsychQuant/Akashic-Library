import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicSkillTools

/// `WebRead`（`akashic web-read`，#692 R4 verify）的單元層：主機萃取、形狀檢查、剔除、`check` 的清理。
/// 讀頁面的 bash 區塊整條（假的 safari-browser 接真的 binary）在 `AkashicCLITests/WebAccessReadContractTests`。
final class WebReadTests: XCTestCase {

    // MARK: - 主機萃取（R4 verify 第 11／14 列）

    /// 解析器會分岔的形狀一律 `invalid://`，不模擬任何一個解析器。
    func testShapesWhereParsersDisagreeAreRefused() {
        for url in ["https://evil.example\\@trusted.example/#akashic-aa",      // WebKit：evil.example；urlsplit／Foundation：trusted.example
                    "https:\\\\evil.example/",                                 // WebKit：evil.example；urlsplit：沒有主機
                    "https://user:pw@example.com/",                           // 帳密：先前 urlsplit 靜默丟掉
                    "https://doi.org@evil.example/",
                    "https://evil%2Eexample.com/",                            // 百分比編碼的主機
                    "https://[::1]/",                                         // IPv6 字面值
                    "https://example.com:99999/", "https://example.com:8x/",  // 埠號
                    "https://exa mple.com/", "https://example.com/\u{0}x", " https://example.com/",
                    "https://exam\u{200B}ple.com/"] {
            XCTAssertEqual(WebRead.origin(of: url), "invalid://", url)
        }
    }

    func testOrdinaryUrlsKeepSchemeHostAndPort() {
        XCTAssertEqual(WebRead.origin(of: "https://Journal.Example.ORG/a/b?c=1#akashic-deadbeef"), "https://journal.example.org")
        XCTAssertEqual(WebRead.origin(of: "https://example.com:443/x"), "https://example.com:443")
        XCTAssertEqual(WebRead.origin(of: "http://example.com/x"), "http://example.com")
        XCTAssertEqual(WebRead.origin(of: "about:blank#akashic-deadbeef"), "about://")
        // 反斜線在 fragment 之後不影響主機（fragment 是我們的碼，不送伺服器）
        XCTAssertEqual(WebRead.origin(of: "https://example.com/x#a\\b"), "https://example.com")
    }

    /// 國際化網域名稱：Safari 回報 Unicode 或 punycode，比起來都相同（R3 的限制 5：先前 Unicode 形一律被拒）。
    func testUnicodeAndPunycodeHostsCompareEqual() {
        let unicode = WebRead.origin(of: "https://bücher.example/x")
        XCTAssertEqual(unicode, "https://xn--bcher-kva.example")
        XCTAssertEqual(unicode, WebRead.origin(of: "https://XN--BCHER-KVA.example/x"))
        XCTAssertTrue(WebRead.hostIsAcceptable(unicode))
        XCTAssertTrue(WebRead.hostIsAcceptable(WebRead.origin(of: "https://例え。テスト/")), "IDN 頂層名稱（xn--）也收")
    }

    // MARK: - 形狀檢查

    func testHostShape() {
        for ok in ["https://journal.example.org", "https://www.sciencedirect.com", "https://xn--bcher-kva.example", "https://a.co"] {
            XCTAssertTrue(WebRead.hostIsAcceptable(ok), ok)
        }
        for bad in ["http://journal.example.org", "https://journal.example.org:443", "https://localhost", "https://printer.local",
                    "https://intranet.corp", "https://10.0.0.1", "https://127.0.0.1.nip.io", "https://example.com.", "https://",
                    "invalid://", "https://a_b.example.com", "https://example.1"] {
            XCTAssertFalse(WebRead.hostIsAcceptable(bad), bad)
        }
    }

    func testShownPrintsOnlyHostShapedStrings() {
        XCTAssertEqual(WebRead.shown("https://journal.example.org"), "'https://journal.example.org'")
        XCTAssertEqual(WebRead.shown("https://a.example:443"), "'https://a.example:443'")
        XCTAssertEqual(WebRead.shown("https://a.example/'; rm -rf"), "'<不像主機，未印>'")
    }

    func testVerificationServiceHosts() {
        XCTAssertTrue(WebRead.isVerificationServiceHost("https://challenges.cloudflare.com"))
        XCTAssertTrue(WebRead.isVerificationServiceHost("https://newassets.hcaptcha.com"))
        XCTAssertTrue(WebRead.isVerificationServiceHost("https://www.google.com"), "只看主機時 reCAPTCHA 的主機算進來（保守的一邊）")
        XCTAssertFalse(WebRead.isVerificationServiceHost("https://journal.example.org"))
        XCTAssertFalse(WebRead.isVerificationServiceHost("http://challenges.cloudflare.com"))
    }

    // MARK: - 剔除就是 UnsafeToEmitScalar（R4 verify 第 3／5 列）

    /// 每一個 scalar 過一次 `clean`：被刪的恰好是 `UnsafeToEmitScalar.contains` 扣掉映射成換行或空白的那幾類；其餘原樣。
    /// R3 的 Python 版另寫一份集合、在 macOS 的 Python 3.9 上留下九個之後才指派的格式字元，這支測試把兩份收成一份。
    func testTheStripIsExactlyUnsafeToEmitScalarPlusTheMappings() {
        var mismatches: [String] = []
        for v in UInt32(0)...0x10FFFF {
            guard let u = Unicode.Scalar(v) else { continue }
            let cat = u.properties.generalCategory
            let expected: String
            if u == "\n" || u == "\t" { expected = String(u) }
            else if u == "\r" || v == 0x0B || v == 0x0C || v == 0x85 || cat == .lineSeparator || cat == .paragraphSeparator { expected = "\n" }
            else if cat == .spaceSeparator { expected = " " }
            else if UnsafeToEmitScalar.contains(u) { expected = "" }
            else { expected = String(u) }
            let got = WebRead.clean("a" + String(u) + "b", limit: 10).text
            if got != "a" + expected + "b" { mismatches.append(String(format: "U+%04X", v)) }
            if mismatches.count >= 20 { break }
        }
        XCTAssertEqual(mismatches, [], "前 20 個不一致")
        for v: UInt32 in [0x0890, 0x0891, 0x13439, 0x1343F] {
            XCTAssertEqual(WebRead.clean("x" + String(Unicode.Scalar(v)!), limit: 10).text, "x", String(format: "U+%04X", v))
        }
    }

    func testCRLFIsOneNewlineAndTheCapIsInUTF16Units() {
        XCTAssertEqual(WebRead.clean("a\r\nb\rc", limit: 100).text, "a\nb\nc")
        // 截在 emoji 的代理對中間：孤立的高代理刪掉，不換成 U+FFFD
        let r = WebRead.clean("ab😀cd", limit: 3)
        XCTAssertEqual(r.text, "ab")
        XCTAssertTrue(r.cut)
        let exact = WebRead.clean("abc", limit: 3)
        XCTAssertFalse(exact.cut, "剛好上限不算被截")
    }

    // MARK: - check 的清理與欄位

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("webread-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func path(_ name: String) -> String { dir.appendingPathComponent(name).path }
    private func put(_ name: String, _ text: String) throws { try text.write(toFile: path(name), atomically: true, encoding: .utf8) }

    private func check(raw: String, before: String = "https://journal.example.org", after: String = "https://journal.example.org",
                       landing: String? = nil) throws -> WebRead.Outcome {
        try put("raw.json", raw); try put("out.txt", "OLD"); try put("b.txt", before + "\n"); try put("a.txt", after + "\n")
        return WebRead.checkMode(.init(rawFile: path("raw.json"), outFile: path("out.txt"), limit: 100, landingFile: landing,
                                       beforeFile: path("b.txt"), afterFile: path("a.txt")))
    }

    /// 不論結果，讀回的 JSON 都刪掉；輸出檔只有 READ-OK 才有（上一次的不留）。
    func testTheRawFileIsRemovedOnEveryOutcome() throws {
        let cases: [(String, String, Int32)] = [
            (#"{"truncated": false, "rawLength": 1, "text": "t"}"#, "https://journal.example.org", 0),
            (#"{"truncated": false, "rawLength": 1, "text": "t"}"#, "https://evil.example.net", 4),
            (#"not json"#, "https://journal.example.org", 1),
            (#"{"truncated": false, "rawLength": 1, "text": "t"}"#, "https://challenges.cloudflare.com", 2),
        ]
        for (raw, after, code) in cases {
            let o = try check(raw: raw, after: after)
            XCTAssertEqual(o.code, code, "\(after)：\(o.stdout)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: path("raw.json")), "\(after)：讀回的 JSON 要刪掉")
            XCTAssertEqual(FileManager.default.fileExists(atPath: path("out.txt")), code == 0, "\(after)：輸出檔只在 READ-OK 才有")
        }
    }

    func testRawLengthMustBeAnIntegerInRange() throws {
        for raw in [#"{"truncated": false, "rawLength": 1000000001, "text": "t"}"#,
                    #"{"truncated": false, "rawLength": -1, "text": "t"}"#,
                    #"{"truncated": false, "rawLength": 4.0, "text": "t"}"#,
                    #"{"truncated": false, "rawLength": true, "text": "t"}"#,
                    #"{"truncated": 0, "rawLength": 1, "text": "t"}"#,
                    #"{"truncated": false, "rawLength": 1, "text": 5}"#] {
            XCTAssertEqual(try check(raw: raw).code, 1, raw)
        }
        let ok = try check(raw: #"{"truncated": false, "rawLength": 1000000000, "text": "t"}"#)
        XCTAssertEqual(ok.code, 0)
        XCTAssertEqual(ok.stdout, ["READ-OK host='https://journal.example.org' truncated=no raw_length=1000000000 kept=1"])
    }

    /// 誠實的頁面截在 emoji 中間時 `JSON.stringify` 產出孤立的 `\ud83d`：不是 READ-FAIL，孤立代理字元刪掉。
    func testALoneSurrogateEscapeFromAnHonestSliceIsDropped() throws {
        let o = try check(raw: #"{"truncated": true, "rawLength": 9, "text": "ab\ud83d"}"#)
        XCTAssertEqual(o.code, 0, "\(o.stdout)")
        XCTAssertEqual(try String(contentsOfFile: path("out.txt"), encoding: .utf8), "ab")
    }

    /// 沒有比對落地主機時，主機仍要形狀合格（R4 verify 第 15 列）。
    func testWithoutALandingFileTheHostShapeStillCounts() throws {
        let raw = #"{"truncated": false, "rawLength": 1, "text": "t"}"#
        XCTAssertEqual(try check(raw: raw, before: "http://journal.example.org", after: "http://journal.example.org").code, 4)
        XCTAssertEqual(try check(raw: raw, before: "https://printer.local", after: "https://printer.local").code, 4)
        XCTAssertEqual(try check(raw: raw).code, 0)
    }

    func testLandingModeDeletesFirstAndWritesOnlyOnOK() throws {
        try put("o.txt", "https://printer.local\n"); try put("land.txt", "https://journal.example.org\n")
        XCTAssertEqual(WebRead.landingMode(originFile: path("o.txt"), landingFile: path("land.txt"), expectFile: nil).code, 4)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path("land.txt")))
        try put("o.txt", "https://www.example.org\n"); try put("url.txt", "https://example.org/about\n")
        let apex = WebRead.landingMode(originFile: path("o.txt"), landingFile: path("land.txt"), expectFile: path("url.txt"))
        XCTAssertEqual(apex.code, 4, "同站轉址也是不合——由使用者確認落地主機後改 EXPECT 重跑")
        XCTAssertTrue(apex.stdout[0].contains("'https://www.example.org'") && apex.stdout[0].contains("'https://example.org'"), "\(apex.stdout)")
        try put("url.txt", "https://www.example.org/\n")
        XCTAssertEqual(WebRead.landingMode(originFile: path("o.txt"), landingFile: path("land.txt"), expectFile: path("url.txt")).code, 0)
        XCTAssertEqual(try String(contentsOfFile: path("land.txt"), encoding: .utf8), "https://www.example.org\n")
    }

    func testOriginModeNeedsExactlyOneTab() {
        let one = Data(#"[{"url": "https://a.example.org/x#akashic-deadbeef"}, {"url": "https://b.example.org/"}]"#.utf8)
        XCTAssertEqual(WebRead.originMode(documents: one, tag: "deadbeef"), .init(code: 0, stdout: ["https://a.example.org"]))
        let two = Data(#"[{"url": "https://a.example.org/#akashic-deadbeef"}, {"url": "https://b.example.org/#akashic-deadbeef"}]"#.utf8)
        XCTAssertEqual(WebRead.originMode(documents: two, tag: "deadbeef").code, 1)
        XCTAssertEqual(WebRead.originMode(documents: Data("nope".utf8), tag: "deadbeef").code, 1)
        // 別的分頁的標題帶孤立代理字元：不讓整份輸出解析失敗
        let lone = Data(#"[{"url": "https://a.example.org/#akashic-deadbeef", "title": "x\ud800"}]"#.utf8)
        XCTAssertEqual(WebRead.originMode(documents: lone, tag: "deadbeef").code, 0)
    }
}
