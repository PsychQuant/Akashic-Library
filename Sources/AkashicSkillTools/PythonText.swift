import Foundation

/// Python `str` 語意的小工具（#629）。
///
/// 這個模組的前身是 Python 腳本（`verify_pdf.py`、`crossref_match.py`……），它們的判定建在 Python 字串方法與 `re`
/// 的 Unicode 語意上：`str.isspace()`／`isalnum()`／`lower()`／`splitlines()`／`strip()`、`\w`、`\d`。Swift 的
/// `Character` 與 ICU 正則在邊界上不一樣（`\w` 含組合標記與連接標點、`splitlines` 沒有對應物、`Character.isWhitespace`
/// 不含 U+001C–001F……），而**判定的門檻是拿 Python 的行為量出來的**（`FulltextVerify` 的校準表）。所以這裡逐個
/// 重寫 Python 的定義，在 **Unicode scalar** 上運作（Python 的 `str` 是 code point 序列，不是 grapheme cluster）。
///
/// 已知差異（都只發生在極端字元，實務上的書目文字碰不到）：
/// - Unicode 版本：Python 3.13 是 15.1.0，這裡用執行環境的 Swift 標準函式庫；新指派的碼位可能不同；
/// - `nfkc` 是 Foundation 的 NFKD 接 NFC（見 `nfkc` 的說明；一步的 `precomposedStringWithCompatibilityMapping` 對相容分解後的組合序列
///   與 Python 不同，已換掉）——**新指派的碼位**仍取決於執行環境的 Unicode 版本；
/// - `\b`／`re.I` 的 Unicode 等價（如 `ſ`↔`s`、Kelvin sign↔`k`）不重現。
typealias Scalars = [Unicode.Scalar]

enum PyText {
    /// Python `str.isspace()`：Unicode bidi 類為 WS／B／S，或一般類別 Zs。列舉取自 Python 3.13 對全部 code point 的實測
    /// （29 個）。
    static func isSpace(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x09...0x0D, 0x1C...0x1F, 0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
            return true
        default:
            return false
        }
    }

    /// Python `str.isalnum()` 對單一字元：`isalpha()`（Lu／Ll／Lt／Lm／Lo）、`isdecimal()`、`isdigit()`、`isnumeric()`
    /// 任一。後三者合起來就是 Numeric_Type 非 None。它也是 Python `\w` 減去底線。
    static func isAlnum(_ s: Unicode.Scalar) -> Bool {
        switch s.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return true
        default:
            return s.properties.numericType != nil
        }
    }

    /// Python `\w`（str 樣式）：`isalnum()` 或底線。
    static func isWord(_ s: Unicode.Scalar) -> Bool { s == "_" || isAlnum(s) }

    /// Python `\d`（str 樣式）：十進位數字（Nd）。
    static func isDecimal(_ s: Unicode.Scalar) -> Bool { s.properties.generalCategory == .decimalNumber }

    /// Python `str.lower()`：逐 code point 取完整小寫對映（含 `İ` → `i̇` 這種一對多），並重現 Python 的 Final_Sigma
    /// 規則（`Σ` 在詞尾變 `ς`，其餘變 `σ`）。
    static func lower(_ s: Scalars) -> Scalars {
        var out = Scalars()
        out.reserveCapacity(s.count)
        for (i, c) in s.enumerated() {
            if c.value == 0x03A3 {
                out.append(isFinalSigma(s, i) ? "\u{03C2}" : "\u{03C3}")
            } else {
                out.append(contentsOf: c.properties.lowercaseMapping.unicodeScalars)
            }
        }
        return out
    }

    private static func isFinalSigma(_ s: Scalars, _ i: Int) -> Bool {
        var j = i - 1
        while j >= 0, s[j].properties.isCaseIgnorable { j -= 1 }
        guard j >= 0, s[j].properties.isCased else { return false }
        j = i + 1
        while j < s.count, s[j].properties.isCaseIgnorable { j += 1 }
        return j == s.count || !s[j].properties.isCased
    }

    static func lower(_ s: String) -> Scalars { lower(Scalars(s.unicodeScalars)) }

    /// `unicodedata.normalize("NFKC", …)`。
    ///
    /// **不用 `precomposedStringWithCompatibilityMapping`**（#629 R1 verify 第 42、47 則）：Foundation 的 NFKC 對「相容分解之後」的組合序列
    /// 不做 canonical reordering、也不重組——`ｶﾞ`（U+FF76 U+FF9E）得 `カ`＋U+3099 而 Python 是 `ガ`（U+30AC）；U+01C5 ＋ U+0323 的順序不同。
    /// 後果是標題比對在這些輸入上與舊實作分岔（fail-closed：拒收、交人看，但不是「逐條照舊」）。改成定義本身：**NFKC ＝ NFC(NFKD(s))**，
    /// 兩步都用 Foundation。對 Python 3.13 實跑的 53 萬個輸入（全部已指派 scalar、相容字元加 1–2 個組合標記的排列、半形假名加濁點、
    /// Hangul／Devanagari／假名／CJK 相容區／阿拉伯連字的隨機序列）0 個不一致；原本的一步版在同一批有 800 個不一致。
    static func nfkc(_ s: Scalars) -> Scalars {
        Scalars(String(String.UnicodeScalarView(s)).decomposedStringWithCompatibilityMapping.precomposedStringWithCanonicalMapping.unicodeScalars)
    }

    /// Python `str.strip()`（不帶引數）：去掉頭尾的 `isspace()` 字元。
    static func strip(_ s: Scalars) -> Scalars {
        var lo = 0, hi = s.count
        while lo < hi, isSpace(s[lo]) { lo += 1 }
        while hi > lo, isSpace(s[hi - 1]) { hi -= 1 }
        return Scalars(s[lo..<hi])
    }

    /// Python `str.splitlines()`（`keepends=False`）：邊界是 `\n`、`\r`、`\r\n`、`\v`、`\f`、`\x1c`–`\x1e`、`\x85`、
    /// U+2028、U+2029。注意 pdftotext 用 `\f` 分頁——分頁符**也是**行界。
    static func splitLines(_ s: Scalars) -> [Scalars] {
        var lines: [Scalars] = []
        var cur = Scalars()
        var i = 0
        while i < s.count {
            let c = s[i]
            switch c.value {
            case 0x0A, 0x0B, 0x0C, 0x1C, 0x1D, 0x1E, 0x85, 0x2028, 0x2029:
                lines.append(cur); cur = []
            case 0x0D:
                lines.append(cur); cur = []
                if i + 1 < s.count, s[i + 1].value == 0x0A { i += 1 }
            default:
                cur.append(c)
            }
            i += 1
        }
        if !cur.isEmpty { lines.append(cur) }
        return lines
    }

    /// `urllib.parse.unquote`：`%XX` 序列的位元組以 UTF-8 解碼（無效位元組取代為 U+FFFD），非 `%XX` 的 `%` 原樣保留。
    static func unquote(_ s: Scalars) -> Scalars {
        guard s.contains("%") else { return s }
        var out = Scalars()
        var pending = [UInt8]()
        func flush() {
            if pending.isEmpty { return }
            out.append(contentsOf: String(decoding: pending, as: UTF8.self).unicodeScalars)
            pending = []
        }
        var i = 0
        while i < s.count {
            if s[i] == "%", let hi = hexValue(s, i + 1), let lo = hexValue(s, i + 2) {
                pending.append(UInt8(hi * 16 + lo))
                i += 3
            } else {
                flush()
                out.append(s[i])
                i += 1
            }
        }
        flush()
        return out
    }

    private static func hexValue(_ s: Scalars, _ i: Int) -> Int? {
        guard i < s.count else { return nil }
        switch s[i].value {
        case 0x30...0x39: return Int(s[i].value) - 0x30
        case 0x41...0x46: return Int(s[i].value) - 0x41 + 10
        case 0x61...0x66: return Int(s[i].value) - 0x61 + 10
        default: return nil
        }
    }

    /// 去掉尾端屬於 `chars` 的字元（Python `str.rstrip(chars)`）。
    static func rstrip(_ s: Scalars, _ chars: Set<Unicode.Scalar>) -> Scalars {
        var hi = s.count
        while hi > 0, chars.contains(s[hi - 1]) { hi -= 1 }
        return Scalars(s[0..<hi])
    }

    static func hasPrefix(_ s: Scalars, _ p: Scalars, at i: Int = 0) -> Bool {
        guard i >= 0, i + p.count <= s.count else { return false }
        for k in 0..<p.count where s[i + k] != p[k] { return false }
        return true
    }

    static func hasSuffix(_ s: Scalars, _ p: Scalars) -> Bool {
        s.count >= p.count && hasPrefix(s, p, at: s.count - p.count)
    }

    /// `s.find(p, from)`；找不到回 nil。
    static func firstIndex(of p: Scalars, in s: Scalars, from: Int = 0) -> Int? {
        guard !p.isEmpty else { return from <= s.count ? from : nil }
        guard s.count >= p.count else { return nil }
        var i = from
        while i + p.count <= s.count {
            if hasPrefix(s, p, at: i) { return i }
            i += 1
        }
        return nil
    }

    /// Python `str.replace(old, new)`（全部、非重疊、由左而右）。
    static func replacing(_ s: Scalars, _ old: Scalars, with new: Scalars) -> Scalars {
        guard !old.isEmpty else { return s }
        var out = Scalars()
        var i = 0
        while i < s.count {
            if hasPrefix(s, old, at: i) {
                out.append(contentsOf: new)
                i += old.count
            } else {
                out.append(s[i])
                i += 1
            }
        }
        return out
    }

    static func string(_ s: Scalars) -> String { String(String.UnicodeScalarView(s)) }
}
