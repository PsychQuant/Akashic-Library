import Foundation

/// Python `json.loads` 語意的 JSON 解析（#629 R1 verify 第 23、41 則）。
///
/// 舊腳本（`ndjson-abstracts-to-proposals.py`、`crossref_match.py`）用 `json.loads`；第一版移植改用 Foundation 的 `JSONSerialization`，
/// 而兩者在邊界上不同，且有一半的差異是**靜默**的：
///
/// | 輸入 | `json.loads` | `JSONSerialization` |
/// |---|---|---|
/// | 重複的鍵 | **最後一個**勝 | 第一個勝——同一列進 store 的摘要不同，沒有任何警告 |
/// | 字串值開頭的 U+FEFF | 原樣保留（`str.strip()` 不把它當空白） | 被吃掉——`﻿This DOI is not currently attached…` 從「收為提案」變成「略過」 |
/// | 尾隨逗號 `[1,]` | 拒絕 | 接受——壞輸入被當成好輸入 |
/// | `NaN`、`Infinity`、`-Infinity` | 接受（`parse_constant`） | 拒絕 |
///
/// 這個解析器只做 `json.loads` 的文法（RFC 8259 加上那三個常數），回傳 Foundation 相容的值（`[String: Any]`、`[Any]`、`String`、
/// `Bool`、`Int`、`Double`、`NSNull`），所以呼叫端原本的 `as?` 轉型不用動。
///
/// **與 Python 仍有的差異（寫出來，不藏）**：
/// - 巢狀深度上限 `maxDepth`（512，與 Foundation 相同）：更深的拒絕。Python 的 C 掃描器對更深的巢狀仍接受；Crossref 回應與 NDJSON 的列不會有；
/// - 孤立的代理對（`"\ud800"`）：Python 接受並產生孤立代理字元（之後 `print` 才會炸），這裡預設拒絕——Swift `String` 表示不了它。讀 Crossref
///   回應（`DirectoryResponseSource`、`calibrate`）時換成 U+FFFD：合法的 200 回應被判成「不是 JSON」會觸發中止條款、整批停（R2 verify 第 27 則）；
///   摘要進 store 的路徑（`abstracts-to-proposals`）維持拒絕，不把一個不是來源給的字元寫進 store；讀頁面的回傳（`web-read check`，#692 R4）
///   刪掉它——那是 `slice` 截在代理對中間的產物，Python 版之後也會把它當 Cs 剔除；
/// - 超出 `Int` 的整數：Python 是任意精度，這裡退成 `Double`。書目資料裡的整數（年、卷、頁數）不會到那個量級。
enum PyJSONParser {
    struct ParseError: Error, CustomStringConvertible {
        let message: String
        let offset: Int
        var description: String { "\(message) (byte \(offset))" }
    }

    /// 與 Foundation 的 `JSONSerialization` 同一個上限（512）：不比第一版更嚴。
    static let maxDepth = 512

    /// 孤立代理對的處置（見型別 doc 的差異清單）。`drop` 給 `web-read check`（#692 R4）：讀頁面的運算式以 `slice` 截到上限，
    /// 截在一個 emoji 中間時 `JSON.stringify` 產出孤立的 `\ud83d`——誠實的頁面也會；Python 版保留它、再由剔除步驟當 Cs 刪掉，
    /// 這裡在解析時就刪（換成 U+FFFD 會讓一個不是頁面寫的字元進輸出）。
    enum LoneSurrogates { case reject, replacementCharacter, drop }

    static func parse(_ data: Data, loneSurrogates: LoneSurrogates = .reject) throws -> Any {
        // `json.load(open(path, encoding="utf-8"))` 對非 UTF-8 的位元組拋 `UnicodeDecodeError`：這裡也拒絕，不悄悄換成 U+FFFD
        guard String(data: data, encoding: .utf8) != nil else { throw ParseError(message: "Invalid UTF-8", offset: 0) }
        var parser = Parser(bytes: Array(data), loneSurrogates: loneSurrogates)
        parser.skipWhitespace()
        let value = try parser.parseValue(depth: 0)
        parser.skipWhitespace()
        if parser.index < parser.bytes.count { throw ParseError(message: "Extra data", offset: parser.index) }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        let loneSurrogates: LoneSurrogates
        var index = 0

        init(bytes: [UInt8], loneSurrogates: LoneSurrogates) { self.bytes = bytes; self.loneSurrogates = loneSurrogates }

        func fail(_ message: String) -> ParseError { ParseError(message: message, offset: index) }

        mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
        }

        mutating func expect(_ literal: String) -> Bool {
            let lit = Array(literal.utf8)
            guard index + lit.count <= bytes.count, Array(bytes[index..<(index + lit.count)]) == lit else { return false }
            index += lit.count
            return true
        }

        mutating func parseValue(depth: Int) throws -> Any {
            guard depth <= PyJSONParser.maxDepth else { throw fail("nesting too deep") }
            guard index < bytes.count else { throw fail("Expecting value") }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try parseObject(depth: depth)
            case UInt8(ascii: "["): return try parseArray(depth: depth)
            case UInt8(ascii: "\""): return try parseString()
            case UInt8(ascii: "t"): if expect("true") { return true }
            case UInt8(ascii: "f"): if expect("false") { return false }
            case UInt8(ascii: "n"): if expect("null") { return NSNull() }
            case UInt8(ascii: "N"): if expect("NaN") { return Double.nan }
            case UInt8(ascii: "I"): if expect("Infinity") { return Double.infinity }
            case UInt8(ascii: "-"): if expect("-Infinity") { return -Double.infinity }
                return try parseNumber()
            case UInt8(ascii: "0")...UInt8(ascii: "9"): return try parseNumber()
            default: break
            }
            throw fail("Expecting value")
        }

        mutating func parseNumber() throws -> Any {
            let start = index
            if bytes[index] == UInt8(ascii: "-") { index += 1 }
            guard index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 else { index = start; throw fail("Expecting value") }
            if bytes[index] == 0x30 { index += 1 } else { while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 { index += 1 } }
            var isFloat = false
            if index + 1 < bytes.count, bytes[index] == UInt8(ascii: "."), bytes[index + 1] >= 0x30, bytes[index + 1] <= 0x39 {
                isFloat = true
                index += 1
                while index < bytes.count, bytes[index] >= 0x30, bytes[index] <= 0x39 { index += 1 }
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
                var j = index + 1
                if j < bytes.count, bytes[j] == UInt8(ascii: "+") || bytes[j] == UInt8(ascii: "-") { j += 1 }
                if j < bytes.count, bytes[j] >= 0x30, bytes[j] <= 0x39 {
                    isFloat = true
                    while j < bytes.count, bytes[j] >= 0x30, bytes[j] <= 0x39 { j += 1 }
                    index = j
                }
            }
            let text = String(decoding: bytes[start..<index], as: UTF8.self)
            if !isFloat, let i = Int(text) { return i }
            return Double(text) ?? Double.nan   // 超出 Int 的整數與浮點數；文法已驗過，Double(text) 不會是 nil
        }

        mutating func parseString() throws -> String {
            index += 1   // 開頭的 "
            var out = [UInt8]()
            while true {
                guard index < bytes.count else { throw fail("Unterminated string") }
                let b = bytes[index]
                if b == UInt8(ascii: "\"") { index += 1; break }
                if b < 0x20 { throw fail("Invalid control character") }
                if b != UInt8(ascii: "\\") { out.append(b); index += 1; continue }
                index += 1
                guard index < bytes.count else { throw fail("Unterminated string") }
                let e = bytes[index]
                index += 1
                switch e {
                case UInt8(ascii: "\""): out.append(0x22)
                case UInt8(ascii: "\\"): out.append(0x5C)
                case UInt8(ascii: "/"): out.append(0x2F)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    var unit = try hex4()
                    if (0xD800...0xDBFF).contains(unit) {
                        // 高代理：後面要接 \uDC00–\uDFFF
                        if index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") {
                            let resume = index
                            index += 2
                            let low = try hex4()   // 壞的 \u 跳脫一律拒絕（Python 同）
                            if (0xDC00...0xDFFF).contains(low) {
                                unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
                            } else if loneSurrogates != .reject {
                                index = resume   // 那個跳脫不是低代理：退回去，讓下一輪照常解它
                                if loneSurrogates == .drop { continue }
                                unit = 0xFFFD
                            } else {
                                throw fail("Unpaired surrogate")
                            }
                        } else if loneSurrogates != .reject {
                            if loneSurrogates == .drop { continue }
                            unit = 0xFFFD
                        } else {
                            throw fail("Unpaired surrogate")
                        }
                    } else if (0xDC00...0xDFFF).contains(unit) {
                        guard loneSurrogates != .reject else { throw fail("Unpaired surrogate") }
                        if loneSurrogates == .drop { continue }
                        unit = 0xFFFD
                    }
                    guard let scalar = Unicode.Scalar(unit) else { throw fail("Invalid \\u escape") }
                    out.append(contentsOf: Array(String(Character(scalar)).utf8))
                default: throw fail("Invalid \\escape")
                }
            }
            // 位元組原樣（含開頭的 U+FEFF）：`String(decoding:)` 不剝 BOM；輸入已由呼叫端驗過是合法 UTF-8
            return String(decoding: out, as: UTF8.self)
        }

        mutating func hex4() throws -> UInt32 {
            guard index + 4 <= bytes.count else { throw fail("Invalid \\uXXXX escape") }
            var v: UInt32 = 0
            for k in 0..<4 {
                let c = bytes[index + k]
                let d: UInt32
                switch c {
                case 0x30...0x39: d = UInt32(c) - 0x30
                case 0x41...0x46: d = UInt32(c) - 0x41 + 10
                case 0x61...0x66: d = UInt32(c) - 0x61 + 10
                default: throw fail("Invalid \\uXXXX escape")
                }
                v = v * 16 + d
            }
            index += 4
            return v
        }

        mutating func parseArray(depth: Int) throws -> Any {
            index += 1
            var items: [Any] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return items }
            while true {
                skipWhitespace()
                items.append(try parseValue(depth: depth + 1))
                skipWhitespace()
                guard index < bytes.count else { throw fail("Expecting ',' delimiter") }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return items }
                throw fail("Expecting ',' delimiter")
            }
        }

        mutating func parseObject(depth: Int) throws -> Any {
            index += 1
            var object: [String: Any] = [:]
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return object }
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else {
                    throw fail("Expecting property name enclosed in double quotes")
                }
                let key = try parseString()
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw fail("Expecting ':' delimiter") }
                index += 1
                skipWhitespace()
                object[key] = try parseValue(depth: depth + 1)   // 重複的鍵：最後一個勝（`json.loads` 同）
                skipWhitespace()
                guard index < bytes.count else { throw fail("Expecting ',' delimiter") }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return object }
                throw fail("Expecting ',' delimiter")
            }
        }
    }
}
