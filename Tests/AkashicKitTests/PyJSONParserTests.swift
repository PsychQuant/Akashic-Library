import XCTest
@testable import AkashicSkillTools

/// `PyJSONParser`（#629 R1 verify 第 23、41 則）：Python `json.loads` 的文法。**期望值取自 Python 3.13 的實跑**（`json.loads` 後
/// `json.dumps(sort_keys=True, ensure_ascii=False)`；`nil` 是 `JSONDecodeError`）——不是 Foundation 或新實作說的話。
final class PyJSONParserTests: XCTestCase {
    static let cases: [(String, String?)] = [
        ("{\"doi\":\"10.1/a\",\"doi\":\"10.1/b\"}", "{\"doi\": \"10.1/b\"}"),
        ("{\"a\":1,\"a\":{\"b\":2},\"a\":[3]}", "{\"a\": [3]}"),
        ("{\"abstract\":\"\u{FEFF}An abstract.\"}", "{\"abstract\": \"\u{FEFF}An abstract.\"}"),
        ("{\"abstract\":\"\\ufeffAn abstract.\"}", "{\"abstract\": \"\u{FEFF}An abstract.\"}"),
        ("[1,]", nil),
        ("{\"a\":1,}", nil),
        ("[,1]", nil),
        ("{\"a\":}", nil),
        ("[1 2]", nil),
        ("{\"a\" 1}", nil),
        ("{'a':1}", nil),
        ("[01]", nil),
        ("[1.]", nil),
        ("[.5]", nil),
        ("\"\\ud83d\\ude00\"", "\"\u{1F600}\""),
        ("\"tab\there\"", nil),
        ("\"nl\\n\"", "\"nl\\n\""),
        ("{\"a\":[[[[]]]]}", "{\"a\": [[[[]]]]}"),
        (" \t\n {\"a\": 1} \r\n", "{\"a\": 1}"),
        ("{\"a\":1} x", nil),
        ("", nil),
        ("   ", nil),
        ("nul", nil),
        ("tru", nil),
        ("true", "true"),
        ("false", "false"),
        ("null", "null"),
        ("\"x\"", "\"x\""),
        ("12", "12"),
        ("-1.25e2", "-125.0"),
        ("\"\\u00e9\\u4e2d\"", "\"é中\""),
        ("\"\\/\"", "\"/\""),
        ("\"\\x\"", nil),
        ("\"abc", nil),
        ("{\"a\":\"b\"", nil),
        ("[1", nil),
        ("\u{FEFF}{\"a\":1}", nil),
        ("{\"k\":\"v\u{2028}w\"}", "{\"k\": \"v\u{2028}w\"}"),
    ]

    func testEveryCaseAgreesWithPython() {
        for (input, expected) in Self.cases {
            let parsed = try? PyJSONParser.parse(Data(input.utf8))
            switch (parsed, expected) {
            case (nil, nil): break
            case (let value?, let want?): XCTAssertEqual(PyJSONBridge.convert(value).dumps(), want, "輸入 \(input.debugDescription)")
            case (let value?, nil): XCTFail("Python 拒絕、這裡接受：\(input.debugDescription) → \(PyJSONBridge.convert(value).dumps())")
            case (nil, let want?): XCTFail("Python 接受（\(want)）、這裡拒絕：\(input.debugDescription)")
            }
        }
    }

    /// Foundation 與 Python 不同的四處，逐一釘住（第一版用 `JSONSerialization`，重複鍵取第一個、吃掉字串開頭的 U+FEFF、接受尾隨逗號、拒絕 NaN）。
    func testTheFourPlacesWhereFoundationDiffered() throws {
        let dup = try PyJSONParser.parse(Data(#"{"doi":"10.1/a","doi":"10.1/b"}"#.utf8)) as? [String: Any]
        XCTAssertEqual(dup?["doi"] as? String, "10.1/b", "重複的鍵：最後一個勝")
        let bom = try PyJSONParser.parse(Data("{\"a\":\"\u{FEFF}x\"}".utf8)) as? [String: Any]
        XCTAssertEqual((bom?["a"] as? String)?.unicodeScalars.first?.value, 0xFEFF, "字串開頭的 U+FEFF 保留")
        XCTAssertThrowsError(try PyJSONParser.parse(Data("[1,]".utf8)))
        let nan = try PyJSONParser.parse(Data("[NaN, Infinity, -Infinity]".utf8)) as? [Any]
        XCTAssertEqual((nan?[0] as? Double)?.isNaN, true)
        XCTAssertEqual(nan?[1] as? Double, .infinity)
        XCTAssertEqual(nan?[2] as? Double, -.infinity)
    }

    func testNumbersKeepTheirPythonTypes() throws {
        let values = try PyJSONParser.parse(Data("[1e5, 1E-2, 1.5e+3, -0, 0.0, 7]".utf8)) as! [Any]
        XCTAssertEqual(PyJSONBridge.convert(values).dumps(), "[100000.0, 0.01, 1500.0, 0, 0.0, 7]")
        XCTAssertTrue(values[5] is Int)
        XCTAssertTrue(values[0] is Double)
    }

    /// 已知差異（寫在型別 doc 裡）：超出 `Int` 的整數退成 `Double`（Python 是任意精度）；孤立的代理對拒絕（Python 接受）；
    /// 巢狀超過上限拒絕。
    func testDocumentedDeviationsFromPython() {
        XCTAssertTrue((try? PyJSONParser.parse(Data("12345678901234567890".utf8))) is Double)
        XCTAssertThrowsError(try PyJSONParser.parse(Data(#""\ud800""#.utf8)))
        XCTAssertThrowsError(try PyJSONParser.parse(Data(#""\udc00""#.utf8)))
        let deep = String(repeating: "[", count: PyJSONParser.maxDepth + 2) + String(repeating: "]", count: PyJSONParser.maxDepth + 2)
        XCTAssertThrowsError(try PyJSONParser.parse(Data(deep.utf8)))
        let ok = String(repeating: "[", count: 100) + String(repeating: "]", count: 100)
        XCTAssertNoThrow(try PyJSONParser.parse(Data(ok.utf8)))
    }

    /// `json.load(open(path, encoding="utf-8"))` 對非 UTF-8 拋 `UnicodeDecodeError`：這裡也拒絕，不換成 U+FFFD。
    func testInvalidUTF8IsRejected() {
        XCTAssertThrowsError(try PyJSONParser.parse(Data([0x22, 0xFF, 0x22])))
    }
}
