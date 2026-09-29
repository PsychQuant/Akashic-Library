import Foundation

/// 保留鍵順序、輸出與 Python `json.dumps(…, ensure_ascii=False)` 逐位元相同的 JSON 值（#629）。
///
/// 為什麼不用 `JSONEncoder`：它只能字典序（`.sortedKeys`）或不保證順序，而舊腳本的輸出（`verify_pdf.py` 的判定 JSON、
/// `crossref_match.py` 的結果檔、`ndjson-abstracts-to-proposals.py` 的提案檔）是 skill 與測試依賴的**文字形狀**——
/// `"doi_state": "page-match"` 是路徑測試 grep 的字串，`indent=1` 的結果檔是人與 agent 讀的。保留同一個形狀，才能把
/// 「移植後輸出不變」用逐位元比對證明，而不是用「語意相同」帶過。
///
/// Python 的規則（`json.dumps` 預設）：
/// - 無縮排時分隔符是 `, ` 與 `: `；有縮排時項目分隔符是 `,`＋換行、鍵分隔符仍是 `: `；空陣列／物件是 `[]`／`{}`；
/// - 字串只跳脫 `"`、`\`、`\b \f \n \r \t` 與其餘 U+0000–U+001F（`\u00xx`，小寫十六進位）；DEL 與非 ASCII 原樣輸出；
/// - 浮點數用 `float.__repr__`（最短來回表示，`1.0` 不縮成 `1`）——Swift 的 `Double.description` 同一規則。
public enum PyJSON: Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([PyJSON])
    /// 鍵順序就是陣列順序（Python 3.7+ 的 dict 插入序）。
    case object([(String, PyJSON)])

    public static func == (l: PyJSON, r: PyJSON) -> Bool { l.dumps() == r.dumps() }

    public func dumps(indent: Int? = nil) -> String {
        var out = ""
        write(&out, indent: indent, level: 0)
        return out
    }

    private func write(_ out: inout String, indent: Int?, level: Int) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .double(let d): out += PyJSON.repr(d)
        case .string(let s): PyJSON.writeString(s, into: &out)
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "["
            for (n, item) in items.enumerated() {
                if n > 0 { out += indent == nil ? ", " : "," }
                if let ind = indent { out += "\n" + String(repeating: " ", count: ind * (level + 1)) }
                item.write(&out, indent: indent, level: level + 1)
            }
            if let ind = indent { out += "\n" + String(repeating: " ", count: ind * level) }
            out += "]"
        case .object(let pairs):
            if pairs.isEmpty { out += "{}"; return }
            out += "{"
            for (n, pair) in pairs.enumerated() {
                if n > 0 { out += indent == nil ? ", " : "," }
                if let ind = indent { out += "\n" + String(repeating: " ", count: ind * (level + 1)) }
                PyJSON.writeString(pair.0, into: &out)
                out += ": "
                pair.1.write(&out, indent: indent, level: level + 1)
            }
            if let ind = indent { out += "\n" + String(repeating: " ", count: ind * level) }
            out += "}"
        }
    }

    /// Python `float.__repr__`。有限值直接用 Swift 的最短來回表示；不會出現在輸出裡的 inf／nan 照 Python 寫成 JSON 的
    /// `Infinity`／`NaN`。
    static func repr(_ d: Double) -> String {
        if d.isNaN { return "NaN" }
        if d.isInfinite { return d < 0 ? "-Infinity" : "Infinity" }
        return d.description
    }

    static func writeString(_ s: String, into out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u.value {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x08: out += "\\b"
            case 0x0C: out += "\\f"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0x00...0x1F: out += String(format: "\\u%04x", u.value)
            default: out.unicodeScalars.append(u)
            }
        }
        out += "\""
    }

    /// Python `round(x, digits)`：對**確切的二進位值**做四捨五入再取最近的 double。`String(format:)` 的 `%.nf` 是同一個
    /// 語意（C 的 printf 對確切二進位值做 round-half-even）；乘以 10ⁿ 再 `rounded()` 會在接近平手的值上引入誤差。
    static func rounded(_ x: Double, digits: Int) -> Double {
        Double(String(format: "%.\(digits)f", x)) ?? x
    }

    /// JavaScript 字串字面值（`json.dumps(url)` 的預設：ASCII 逃脫，非 ASCII 寫成 `\uXXXX`，補充平面用 surrogate pair）。
    static func javaScriptLiteral(_ s: String) -> String {
        var out = "\""
        for u in s.utf16 {
            switch u {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x08: out += "\\b"
            case 0x0C: out += "\\f"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0x20...0x7E: out.unicodeScalars.append(Unicode.Scalar(u)!)
            default: out += String(format: "\\u%04x", u)
            }
        }
        return out + "\""
    }
}
