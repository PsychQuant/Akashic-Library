import XCTest
@testable import AkashicSkillTools

/// `PySequenceMatcher`、`PyJSON`、`PyText`、`CauchyJitter`（#629）：Python 語意的移植底層。
///
/// **期望值全部取自 Python 3.13 的實際輸出**（`difflib.SequenceMatcher`、`json.dumps`、`str` 方法），不是新實作自己說的話。
/// 這些底層一旦與 Python 差一個位元，`crossref_match` 的門檻與 `verify_pdf` 的回報分數就跟著漂——門檻是拿 Python 的行為量出來的。
final class PySequenceMatcherTests: XCTestCase {
    private func ratio(_ a: String, _ b: String, autojunk: Bool = true) -> Double {
        PySequenceMatcher(Scalars(a.unicodeScalars), Scalars(b.unicodeScalars), autojunk: autojunk).ratio()
    }

    func testRatiosMatchPython() {
        XCTAssertEqual(ratio("a", "a"), 1.0)
        XCTAssertEqual(ratio("", ""), 1.0)
        XCTAssertEqual(ratio("abc", ""), 0.0)
        XCTAssertEqual(ratio("", "abc"), 0.0)
        XCTAssertEqual(ratio("abcd", "bcde"), 0.75)
        XCTAssertEqual(ratio("the quick brown fox", "the quick brown fax"), 0.9473684210526315)
        XCTAssertEqual(ratio("psychological methods", "psychological method"), 0.975609756097561)
        XCTAssertEqual(ratio("journal of personality and social psychology", "j personality social psychology"), 0.8266666666666667)
        XCTAssertEqual(ratio("xyz", "zyx"), 0.3333333333333333)
        XCTAssertEqual(ratio("心理 測驗 大學生", "心理 測驗 大學"), 0.9411764705882353)
    }

    /// `len(b) >= 200` 時 autojunk 把出現次數超過 `len(b)//100 + 1` 的元素從 `b2j` 拿掉：`"a"*10` 對 `"a"*300` 得 0.0645，
    /// 而不是不 autojunk 時的 ≈ 0.06452（兩者在這組恰好都會被「熱門」影響——用 `autojunk: false` 對照，證明旗標真的有作用）。
    func testAutojunkChangesTheResultForPopularElements() {
        let a = String(repeating: "a", count: 10), b = String(repeating: "a", count: 300)
        XCTAssertEqual(ratio(a, b), 0.06451612903225806)      // Python：SequenceMatcher(None, a, b).ratio()
        XCTAssertEqual(ratio(String(repeating: "ab", count: 150), String(repeating: "ba", count: 150)), 0.0)   // Python：0.0（autojunk 讓 a、b 全成熱門）
        XCTAssertGreaterThan(ratio(String(repeating: "ab", count: 150), String(repeating: "ba", count: 150), autojunk: false), 0.9)
    }

    func testLongestMatchTiesTakeTheEarliestBlock() {
        let m = PySequenceMatcher(Scalars("xabyab".unicodeScalars), Scalars("zabab".unicodeScalars), autojunk: false)
            .findLongestMatch(alo: 0, ahi: 6, blo: 0, bhi: 5)
        XCTAssertEqual(m, PySequenceMatcher.Match(a: 1, b: 1, size: 2))   // Python：Match(a=1, b=1, size=2)
    }
}

final class PyJSONTests: XCTestCase {
    private var sample: PyJSON {
        .object([
            ("a", .double(1.0)),
            ("b", .array([.int(1), .double(2.5), .null, .bool(true), .double(-0.0), .double(1e-05), .double(1e16), .double(0.1 + 0.2)])),
            ("c", .string("é\u{2028}\u{7F}\u{1F}\"\\\n/\t\r\u{08}\u{0C}\u{00}")),
            ("d", .object([])),
            ("e", .array([])),
            ("f", .object([("x", .array([.array([]), .object([])])), ("y", .string("中"))])),
        ])
    }

    /// 期望值取自 `json.dumps(v, ensure_ascii=False)`（無縮排）。
    func testCompactMatchesPython() {
        let expected = "{\"a\": 1.0, \"b\": [1, 2.5, null, true, -0.0, 1e-05, 1e+16, 0.30000000000000004], "
            + "\"c\": \"é\u{2028}\u{7F}\\u001f\\\"\\\\\\n/\\t\\r\\b\\f\\u0000\", \"d\": {}, \"e\": [], \"f\": {\"x\": [[], {}], \"y\": \"中\"}}"
        XCTAssertEqual(sample.dumps(), expected)
    }

    /// 期望值取自 `json.dumps(v, ensure_ascii=False, indent=1)` 與 `indent=2`。
    func testIndentedMatchesPython() {
        let tail = "\"c\": \"é\u{2028}\u{7F}\\u001f\\\"\\\\\\n/\\t\\r\\b\\f\\u0000\""
        let one = "{\n \"a\": 1.0,\n \"b\": [\n  1,\n  2.5,\n  null,\n  true,\n  -0.0,\n  1e-05,\n  1e+16,\n  0.30000000000000004\n ],\n "
            + tail + ",\n \"d\": {},\n \"e\": [],\n \"f\": {\n  \"x\": [\n   [],\n   {}\n  ],\n  \"y\": \"中\"\n }\n}"
        XCTAssertEqual(sample.dumps(indent: 1), one)
        let two = "{\n  \"a\": 1.0,\n  \"b\": [\n    1,\n    2.5,\n    null,\n    true,\n    -0.0,\n    1e-05,\n    1e+16,\n    0.30000000000000004\n  ],\n  "
            + tail + ",\n  \"d\": {},\n  \"e\": [],\n  \"f\": {\n    \"x\": [\n      [],\n      {}\n    ],\n    \"y\": \"中\"\n  }\n}"
        XCTAssertEqual(sample.dumps(indent: 2), two)
    }

    /// `json.dumps("aé😀\x7f")`（預設 ensure_ascii=True）＝ JS 字串字面值的 ASCII 逃脫。
    func testJavaScriptLiteralMatchesPythonEnsureAscii() {
        XCTAssertEqual(PyJSON.javaScriptLiteral("a\u{E9}\u{1F600}\u{7F}"), "\"a\\u00e9\\ud83d\\ude00\\u007f\"")
    }

    func testRoundingUsesTheExactBinaryValue() {
        XCTAssertEqual(PyJSON.rounded(0.8, digits: 2), 0.8)
        XCTAssertEqual(PyJSON.rounded(2.675, digits: 2), 2.67)     // Python：round(2.675, 2) == 2.67（2.675 的二進位值略小於 2.675）
        XCTAssertEqual(PyJSON.rounded(0.9235, digits: 3), 0.923)   // Python：round(0.9235, 3) == 0.923
    }
}

final class PyTextTests: XCTestCase {
    private func s(_ x: String) -> Scalars { Scalars(x.unicodeScalars) }

    /// Python `str.splitlines()`：`\f` 與 `\x1c`–`\x1e`、U+2028 都是行界，尾端的分隔符不產生空行，連續分隔符產生空行。
    func testSplitLinesMatchesPython() {
        func lines(_ x: String) -> [String] { PyText.splitLines(s(x)).map { PyText.string($0) } }
        XCTAssertEqual(lines("a\nb"), ["a", "b"])
        XCTAssertEqual(lines("a\n"), ["a"])
        XCTAssertEqual(lines("a\n\n"), ["a", ""])
        XCTAssertEqual(lines("a\r\nb\rc"), ["a", "b", "c"])
        XCTAssertEqual(lines("p1\u{0C}p2"), ["p1", "p2"])
        XCTAssertEqual(lines("x\u{2028}y\u{85}z\u{1C}w"), ["x", "y", "z", "w"])
        XCTAssertEqual(lines(""), [])
        XCTAssertEqual(lines("\n"), [""])
    }

    /// Python：`"a　".isspace()` 等（29 個空白碼位）；U+180E、U+200B 不是。
    func testIsSpaceMatchesPythonsTable() {
        for v in [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x85, 0xA0, 0x1680, 0x2000, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000] {
            XCTAssertTrue(PyText.isSpace(Unicode.Scalar(UInt32(v))!), String(v, radix: 16))
        }
        for v in [0x180E, 0x200B, 0x200C, 0xFEFF, 0x00AD, 0x41] { XCTAssertFalse(PyText.isSpace(Unicode.Scalar(UInt32(v))!), String(v, radix: 16)) }
    }

    /// Python 的 `isalnum()` 認數字型的 Nl／No（`Ⅳ`、`①`、`½`），不認組合標記。
    func testIsAlnumMatchesPython() {
        for c in "aZ中٣Ⅳ①½ǅ" { XCTAssertTrue(PyText.isAlnum(c.unicodeScalars.first!), String(c)) }
        for c in "_ -\u{0301}\u{200D}—" { XCTAssertFalse(PyText.isAlnum(c.unicodeScalars.first!), String(c)) }
    }

    /// Python `"ΑΣ".lower()` 是 `"ας"`（詞尾 sigma），`"ΑΣΑ".lower()` 是 `"ασα"`，單獨的 `"Σ"` 是 `"σ"`。
    func testLowerRestoresFinalSigma() {
        XCTAssertEqual(PyText.string(PyText.lower(s("ΑΣ"))), "ας")
        XCTAssertEqual(PyText.string(PyText.lower(s("ΑΣΑ"))), "ασα")
        XCTAssertEqual(PyText.string(PyText.lower(s("Σ"))), "σ")
        XCTAssertEqual(PyText.string(PyText.lower(s("İ"))), "i\u{307}")   // 一對多對映
    }

    func testUnquoteMatchesPython() {
        XCTAssertEqual(PyText.string(PyText.unquote(s("10.1234/x%2Fy%E4%B8%AD"))), "10.1234/x/y中")
        XCTAssertEqual(PyText.string(PyText.unquote(s("10.1234/x%E4"))), "10.1234/x\u{FFFD}")   // 無效 UTF-8 → U+FFFD
        XCTAssertEqual(PyText.string(PyText.unquote(s("100%"))), "100%")
        XCTAssertEqual(PyText.string(PyText.unquote(s("%zz%4"))), "%zz%4")
    }
}

final class CauchyJitterTests: XCTestCase {
    func testDefaultsCalibrateToTheStatedMedian() throws {
        let p = CauchyJitter.Parameters()
        guard case .success(let c) = CauchyJitter.calibrate(p) else { return XCTFail("預設參數應該可校準") }
        XCTAssertEqual(CauchyJitter.truncatedMedian(c.mu, p.scale, p.min, p.max), 3.0, accuracy: 1e-9)
    }

    /// 舊 SKILL.md 的一行公式用 `max(2, …)` 夾住，10⁶ 次模擬有 22.3% 剛好是 2.0 秒（safari-browser#182）。截斷後重新正規化
    /// 不得有任何質量堆在下界：在 20 萬次抽樣裡，等於 2.0 的一個都不該有、中位數應貼近 3。
    func testTruncationDiscardsInsteadOfClamping() throws {
        let p = CauchyJitter.Parameters()
        guard case .success(let c) = CauchyJitter.calibrate(p) else { return XCTFail() }
        var g = SystemRandomNumberGenerator()
        var draws = (0..<200_000).map { _ in CauchyJitter.draw(p, c, unit: { Double.random(in: 0..<1, using: &g) }) }
        XCTAssertFalse(draws.contains(2.0), "有質量堆在下界＝被夾住")
        XCTAssertTrue(draws.allSatisfy { $0 > 2.0 && $0 < 60.0 })
        draws.sort()
        XCTAssertEqual(draws[draws.count / 2], 3.0, accuracy: 0.05)
    }

    func testInvalidParametersAreRefusedWithTheOldMessages() {
        XCTAssertEqual(CauchyJitter.calibrate(.init(min: 5, max: 4, median: 3, scale: 0.8)),
                       .failure(.init("need 0 <= min < median < max and 0 < scale <= 100*(max-min)")))
        XCTAssertEqual(CauchyJitter.calibrate(.init(min: 2, max: 60, median: 3, scale: 0)),
                       .failure(.init("need 0 <= min < median < max and 0 < scale <= 100*(max-min)")))
        guard case .failure(let e) = CauchyJitter.calibrate(.init(min: 2, max: 60, median: 59.999, scale: 0.01)) else { return XCTFail("median 59.999 在 scale 0.01 下應該不可達") }
        XCTAssertTrue(e.message.hasPrefix("median 59.999 unreachable with scale 0.01; achievable "), e.message)
    }

    /// 極端的均勻亂數值（0、貼近 0、貼近 1）也不得抽出區間外的間隔：抽到區間外就重抽，64 次都落空才退回中位數。
    func testDrawStaysInsideTheIntervalAtTheExtremes() throws {
        let p = CauchyJitter.Parameters()
        guard case .success(let c) = CauchyJitter.calibrate(p) else { return XCTFail() }
        for u in [0.0, 1e-12, 1e-6, 0.5, 1 - 1e-6, 1 - 1e-12] {
            let x = CauchyJitter.draw(p, c, unit: { u })
            XCTAssertTrue(p.min <= x && x <= p.max, "unit=\(u) → \(x)")
        }
    }
}
