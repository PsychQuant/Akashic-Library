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
        let unicode = WebRead.origin(of: "https://bücher.example.org/x")
        XCTAssertEqual(unicode, "https://xn--bcher-kva.example.org")
        XCTAssertEqual(unicode, WebRead.origin(of: "https://XN--BCHER-KVA.example.org/x"))
        XCTAssertTrue(WebRead.hostIsAcceptable(unicode))
        XCTAssertTrue(WebRead.hostIsAcceptable(WebRead.origin(of: "https://例え。テスト/")), "IDN 頂層名稱（xn--）也收")
    }

    // MARK: - 形狀檢查

    func testHostShape() {
        for ok in ["https://journal.example.org", "https://www.sciencedirect.com", "https://xn--bcher-kva.example.org", "https://a.co"] {
            XCTAssertTrue(WebRead.hostIsAcceptable(ok), ok)
        }
        for bad in ["http://journal.example.org", "https://journal.example.org:443", "https://localhost", "https://printer.local",
                    "https://intranet.corp", "https://10.0.0.1", "https://127.0.0.1.nip.io", "https://example.com.", "https://",
                    "invalid://", "https://a_b.example.com", "https://example.1",
                    // b33 verify X2 第 16 列：特殊用途的頂層名稱（RFC 6761、7686、9476）
                    "https://foo.test", "https://foo.example", "https://foo.invalid", "https://foo.onion", "https://foo.alt",
                    "https://nas.box", "https://router.home", "https://x.private", "https://foo.localdomain"] {
            XCTAssertFalse(WebRead.hostIsAcceptable(bad), bad)
        }
    }

    /// 主機裡還有 `:`（埠號已拆掉之後）：ASCII 與非 ASCII 兩個分支同一個答案（b33 verify X2 第 9 列：非 ASCII 分支曾交給 `URL(string:)`、
    /// 把內嵌的 `:80` 當埠號讀掉）。
    func testAnEmbeddedColonIsRefusedOnBothBranches() {
        XCTAssertEqual(WebRead.origin(of: "https://example.com:80:/"), "invalid://")
        XCTAssertEqual(WebRead.origin(of: "https://日本.jp:80:/"), "invalid://")
        XCTAssertEqual(WebRead.origin(of: "https://日本:80:/"), "invalid://")
        XCTAssertEqual(WebRead.origin(of: "https://日本.jp:443/"), "https://xn--wgv71a.jp:443", "一般的埠號照舊")
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
            else if UnsafeToEmitScalar.contains(u) || u.properties.isNoncharacterCodePoint { expected = "" }
            else { expected = String(u) }
            let got = WebRead.clean("a" + String(u) + "b", limit: 10).text
            if got != "a" + expected + "b" { mismatches.append(String(format: "U+%04X", v)) }
            if mismatches.count >= 20 { break }
        }
        XCTAssertEqual(mismatches, [], "前 20 個不一致")
        // b33 verify X2 第 15 列：noncharacter（`escapesInLLMDocument` 的加項）也刪
        for v: UInt32 in [0xFFFF, 0xFFFE, 0xFDD0, 0xFDEF, 0x1FFFE, 0x10FFFF] {
            XCTAssertEqual(WebRead.clean("x" + String(Unicode.Scalar(v)!) + "y", limit: 10).text, "xy", String(format: "U+%04X", v))
        }
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
        XCTAssertEqual(ok.stdout, ["READ-OK host='https://journal.example.org' truncated=yes raw_length=1000000000 kept=1"],
                       "頁面回報的原文長度超過上限＝被截（b33 verify X2 第 11 列）")
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

    /// 頁面說沒截、原文長度卻超過上限：`truncated=yes`（b33 verify X2 第 11 列——先前印 `truncated=no raw_length=999999`，
    /// SKILL 要模型以 `truncated` 為準）。
    func testARawLengthOverTheLimitIsTruncatedWhateverThePageSays() throws {
        let o = try check(raw: #"{"truncated": false, "rawLength": 999999, "text": "hello"}"#)
        XCTAssertEqual(o.code, 0, "\(o.stdout)")
        XCTAssertTrue(o.stdout[0].contains("truncated=yes"), "\(o.stdout)")
        let exact = try check(raw: #"{"truncated": false, "rawLength": 100, "text": "hello"}"#)
        XCTAssertTrue(exact.stdout[0].contains("truncated=no"), "剛好上限不算被截：\(exact.stdout)")
    }

    /// 原文長度比交回的文字還短：不可能出自誠實的頁面，READ-FAIL（b33 verify X2 第 6 列：先前印 `raw_length=2 kept=5`）。
    func testARawLengthShorterThanTheTextIsRefused() throws {
        let o = try check(raw: #"{"truncated": true, "rawLength": 2, "text": "hello"}"#)
        XCTAssertEqual(o.code, 1, "\(o.stdout)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path("out.txt")))
    }

    /// 剔除之後沒有看得見的字（整段零寬或控制字元、或頁面還沒渲染的空白首屏）：READ-FAIL，不當成「沒有訊號」（b33 verify X2 第 17 列）。
    func testNothingVisibleAfterTheStripIsAReadFailure() throws {
        for raw in [#"{"truncated": false, "rawLength": 6, "text": "\u200b\u200b\u0001\ufe0f\u2060\u00ad"}"#,
                    #"{"truncated": false, "rawLength": 1, "text": "\n"}"#,
                    #"{"truncated": false, "rawLength": 0, "text": ""}"#] {
            let o = try check(raw: raw)
            XCTAssertEqual(o.code, 1, "\(raw)：\(o.stdout)")
            XCTAssertTrue(o.stdout[0].contains("沒有看得見的字"), "\(o.stdout)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: path("out.txt")))
            XCTAssertFalse(FileManager.default.fileExists(atPath: path("raw.json")))
        }
    }

    /// 讀回的 JSON 刪不掉（它所在的目錄不可寫）：不再 `try?` 吞掉——READ-OK 改成 READ-FAIL、寫出的文字收回、stderr 說原文還在
    /// （b33 verify X2 第 0／1 列「清理失敗要回報」）。
    func testARawFileThatCannotBeRemovedTurnsReadOkIntoAFailure() throws {
        try XCTSkipIf(geteuid() == 0, "root 刪得掉唯讀目錄裡的檔")
        let locked = dir.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let raw = locked.appendingPathComponent("raw.json").path
        try #"{"truncated": false, "rawLength": 1, "text": "t"}"#.write(toFile: raw, atomically: true, encoding: .utf8)
        try put("b.txt", "https://journal.example.org\n"); try put("a.txt", "https://journal.example.org\n")
        chmod(locked.path, 0o555)
        defer { chmod(locked.path, 0o755) }
        let o = WebRead.checkMode(.init(rawFile: raw, outFile: path("out.txt"), limit: 100, landingFile: nil,
                                        beforeFile: path("b.txt"), afterFile: path("a.txt")))
        XCTAssertEqual(o.code, 1, "\(o)")
        XCTAssertTrue(o.stdout[0].hasPrefix("READ-FAIL 讀回的 JSON 刪不掉"), "\(o.stdout)")
        XCTAssertTrue(o.stderr.contains { $0.hasPrefix("RAW-NOT-REMOVED") }, "\(o.stderr)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path("out.txt")), "READ-FAIL 之後不留文字")
    }

    /// `url`：開分頁之前的檢查，主機與落地主機同一個形狀檢查（b33 verify X2 第 16／39 列：先前是文件裡的正則，`.home`、`.box`、
    /// `127.0.0.1.nip.io` 這類都過得了）。
    func testUrlModeSharesTheHostCheckWithLanding() throws {
        func run(_ u: String) throws -> WebRead.Outcome {
            try put("url.txt", u + "\n")
            return WebRead.urlMode(urlFile: path("url.txt"))
        }
        let ok = try run("https://Journal.Example.org/about/history?x=1&y=(2)")
        XCTAssertEqual(ok, .init(code: 0, stdout: ["URL-OK 'https://journal.example.org'"]))
        for host in ["https://192.168.1.1.nip.io/admin", "https://10-0-0-1.sslip.io/", "https://127.0.0.1.nip.io/x", "https://router.home/",
                     "https://nas.box/", "https://x.private/", "https://foo.localdomain/", "https://foo.test/", "https://foo.onion/"] {
            XCTAssertEqual(try run(host).code, 4, host)
        }
        for shape in ["http://journal.example.org/", "https://journal.example.org:8443/", "https://journal.example.org/#x",
                      "https://journal.example.org/a'b", "https://journal.example.org/a b", "https://journal.example.org/$(id)",
                      "https://journal.example.org/a/%2e%2e/b", "https://journal.example.org/a/../b", "https://bücher.example.org/",
                      "https://user@journal.example.org/", "https://10.0.0.1/", "https://localhost/", "https://journal.example.org/x\nhttps://evil.example.net/"] {
            XCTAssertEqual(try run(shape).code, 1, shape)
        }
        XCTAssertEqual(WebRead.urlMode(urlFile: path("missing.txt")).code, 1)
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

    // MARK: - 已知的驗證服務：一律交給頁面文字（#692，使用者 2026-10-05 裁決第 2 項）

    private let service = "https://challenges.cloudflare.com"
    private let journal = "https://journal.example.org"

    /// 頁面那一側回傳的 JSON：誠實的頁面（原文長度照實報、沒有截）
    private func honest(_ text: String) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["truncated": false, "rawLength": text.utf16.count, "text": text]), as: UTF8.self)
    }

    private var outExists: Bool { FileManager.default.fileExists(atPath: path("out.txt")) }

    /// 落地主機是已知的驗證服務：不論有沒有預期主機（`--expect` 是網址檔或 `-`），都寫下它、印 OK，交給區塊二的文字比對——
    /// 先前「換到」驗證服務（`--expect` 與它不同）一律 2、直接落在上面則照一般主機 OK，同一個終態兩種處置。
    func testLandingOnAVerificationServiceGoesToTheTextComparison() throws {
        try put("o.txt", service + "\n"); try put("url.txt", "https://journal.example.org/about\n")
        for expect in [path("url.txt"), nil] as [String?] {
            try put("land.txt", "OLD\n")
            let o = WebRead.landingMode(originFile: path("o.txt"), landingFile: path("land.txt"), expectFile: expect)
            XCTAssertEqual(o.code, 0, "\(expect ?? "-")：\(o.stdout)")
            XCTAssertTrue(o.stdout.first?.hasPrefix("OK '\(service)'") == true && o.stdout.first?.contains("已知的驗證服務") == true, "\(o.stdout)")
            XCTAssertEqual(try String(contentsOfFile: path("land.txt"), encoding: .utf8), service + "\n")
        }
    }

    /// 讀取前後分頁都在已知的驗證服務上：不論有沒有比對落地主機、落地主機是不是它，都以頁面文字分——等人驗證的標籤 → 3，
    /// 其他（整批暫停的標籤、沒有訊號）→ 2。**沒有 READ-OK**（驗證服務的頁面不當證據），文字不寫出、讀回的 JSON 刪掉。
    func testAPageOnAVerificationServiceIsJudgedByItsTextAndNeverRead() throws {
        let cases: [(text: String, code: Int32, label: String)] = [
            ("Just a moment...", 3, "cloudflare-challenge"), ("Please complete the CAPTCHA", 3, "captcha"), ("Are you a robot?", 3, "human-check"),
            ("Access denied", 2, "access-denied"), ("Welcome to our journal", 2, "沒有訊號"),
        ]
        for landing in [nil, journal, service] as [String?] {
            for c in cases {
                if let landing { try put("land.txt", landing + "\n") }
                let o = try check(raw: try honest(c.text), before: service, after: service, landing: landing.map { _ in path("land.txt") })
                let tag = "\(landing ?? "-")／\(c.text)"
                XCTAssertEqual(o.code, c.code, "\(tag)：\(o.stdout)")
                XCTAssertTrue(o.stdout.first?.hasPrefix(c.code == 3 ? "READ-VERIFY " : "READ-PAUSE ") == true, "\(tag)：\(o.stdout)")
                XCTAssertTrue(o.stdout.first?.contains("'\(service)'") == true && o.stdout.first?.contains(c.label) == true, "\(tag)：\(o.stdout)")
                XCTAssertFalse(outExists, "\(tag)：驗證服務上的文字不寫出")
                XCTAssertFalse(FileManager.default.fileExists(atPath: path("raw.json")), tag)
            }
        }
    }

    /// 讀取當中分頁換了主機、其中一個是已知的驗證服務：文字出自哪一頁分不出來，仍拿它比對——等人驗證還要求讀完時分頁停在驗證服務上
    /// （使用者要驗證的是那個分頁）；讀完時已經離開驗證服務，不論文字都是 2。
    func testAHostChangeDuringTheReadInvolvingAVerificationServiceIsJudgedByTheText() throws {
        for landing in [nil, journal] as [String?] {
            if let landing { try put("land.txt", landing + "\n") }
            let land = landing.map { _ in path("land.txt") }
            let toService = try check(raw: try honest("Just a moment..."), before: journal, after: service, landing: land)
            XCTAssertEqual(toService.code, 3, "\(toService.stdout)")
            XCTAssertEqual(try check(raw: try honest("Welcome to our journal"), before: journal, after: service, landing: land).code, 2)
            let left = try check(raw: try honest("Just a moment..."), before: service, after: journal, landing: land)
            XCTAssertEqual(left.code, 2, "讀完時分頁已經不在驗證服務上：\(left.stdout)")
            XCTAssertFalse(outExists)
        }
    }

    /// 分頁在已知的驗證服務上、讀回的文字不能用（不是 JSON、太大、原文長度比交回的短、剔除之後沒有看得見的字）：拿不準是哪一種就當
    /// 整批暫停（2），不是 READ-FAIL（1）。不在驗證服務上的同一批輸入仍是 1（上面的測試）。
    func testUnusableTextOnAVerificationServiceIsAPauseNotAReadFailure() throws {
        for raw in ["not json", #"{"truncated": false, "rawLength": 2, "text": "​​"}"#,
                    #"{"truncated": true, "rawLength": 2, "text": "hello"}"#,
                    #"{"truncated": false, "rawLength": 5000, "text": "\#(String(repeating: "a", count: 5000))"}"#] {
            let o = try check(raw: raw, before: service, after: service)
            XCTAssertEqual(o.code, 2, "\(raw.prefix(60))：\(o.stdout)")
            XCTAssertTrue(o.stdout.first?.hasPrefix("READ-PAUSE ") == true, "\(o.stdout)")
            XCTAssertFalse(outExists)
            XCTAssertFalse(FileManager.default.fileExists(atPath: path("raw.json")))
        }
        XCTAssertEqual(try check(raw: "not json").code, 1, "不在驗證服務上仍是 READ-FAIL")
    }

    /// 只看主機：`www.google.com` 只在 `/recaptcha/` 才是驗證服務，而 Safari 那一側的主機沒有路徑，所以落在 `www.google.com` 的頁面也交給
    /// 文字比對、不當證據（保守的一邊）。
    func testWwwGoogleComIsJudgedByTheTextToo() throws {
        let google = "https://www.google.com"
        XCTAssertEqual(try check(raw: try honest("I'm not a robot"), before: google, after: google).code, 3)
        XCTAssertEqual(try check(raw: try honest("Search results"), before: google, after: google).code, 2)
        XCTAssertEqual(try check(raw: try honest("Search results")).code, 0, "一般主機照舊 READ-OK")
    }
}
