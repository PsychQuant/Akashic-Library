import Foundation

/// `display-safe-exempt:` 註記的豁免規則——擲出站點守衛（`SanitizationBoundaryTests.testEveryThrowSiteEscapesEachPayloadExactlyOnce`）
/// 與 sink 守衛（`DisplaySinkCoverageTests.scanViolations`）共用這一份（#584）。
///
/// 規則（#554 R31／R32 起）：只看註記標記**之後**的文字；一個運算式被豁免，當且僅當它的**第一個識別字**以完整字詞出現在那段文字裡。
/// 註記具名什麼就免檢什麼——一句講 `idx` 的註記不會讓同一行的 `entry.title` 免檢。
///
/// 為什麼是一份：R31 把擲出站點守衛改成這條規則時，sink 守衛仍是整行豁免（`if l.contains("display-safe-exempt:") { continue }`），
/// 兩支守衛對同一個標記給出兩種粒度，而讀程式碼的人看不出哪一支在看哪一行（#554 R32 verify regression 第 37 列）。
///
/// 「第一個識別字」之前先取運算式的**主詞**，三件事（封閉列舉）：
/// 1. 開頭的 `return`／`try`／`try?`／`try!`／`await` 不算——關鍵字不指認任何值（sink 守衛會從 `case "k": return v` 抽出 `return v`）。
/// 2. 整條是 `displaySafeClipOnly(x, max: …)` 時主詞是 `x`：那個函式**只截不逃**（`Models.swift` 的 doc：「不得拿它接未消毒的 store 字串」），
///    註記要擔保的是載體已經消毒過，所以要具名的是載體，不是函式名。
/// 3. 以字串字面開頭（`"`／`#"`）的運算式逐段對照（R32 對擲出站點守衛的同一條）：串接的每個非字面運算元、字面裡的每個插值都要各自被具名；
///    字面文字本身是程式文字，不帶執行期資料。否則 `"\(label)" + entry.title` 的註記講 `label` 就會讓 `entry.title` 免檢。
enum DisplaySafeExemption {
    static let marker = "display-safe-exempt:"

    /// 各行標記**之後**的文字，沒有標記的行不貢獻。只看標記之後：標記之前是程式碼，運算式的識別字必然出現在那裡（R30 verify 第 4 列的毯式豁免）。
    static func notes<S: StringProtocol>(in lines: [S]) -> String {
        lines.compactMap { line -> String? in
            guard let r = line.range(of: marker) else { return nil }
            return String(line[r.upperBound...])
        }.joined(separator: "\n")
    }

    /// 運算式的主詞：去掉開頭的關鍵字、拆開整條的 `displaySafeClipOnly(…)`（見型別 doc 的 1、2）。
    static func subject(of expr: String) -> String {
        var e = expr.trimmingCharacters(in: .whitespaces)
        while let r = e.range(of: #"^(return|try[?!]?|await)\s+"#, options: .regularExpression) { e = String(e[r.upperBound...]) }
        let clip = "displaySafeClipOnly("
        if e.hasPrefix(clip), let close = matchingClose(in: e, openAt: e.index(e.startIndex, offsetBy: clip.count - 1)),
           e.index(after: close) == e.endIndex,
           let carrier = SanitizationBoundaryTests.topLevelArguments(of: e).first {
            return subject(of: carrier)
        }
        return e
    }

    /// 運算式的第一個識別字。`$` 算識別字元，讓 `$0` 可以被具名。
    static func firstIdentifier(of expr: String) -> String? {
        expr.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" && $0 != "$" }).first.map(String.init)
    }

    /// 註記有沒有具名這個運算式（見型別 doc）。
    static func names(_ expr: String, in notes: String) -> Bool {
        guard !notes.isEmpty else { return false }
        let e = subject(of: expr)
        if e.hasPrefix("\"") || e.hasPrefix("#\"") {
            return SanitizationBoundaryTests.concatenationPieces(of: e).allSatisfy { piece in
                piece.hasPrefix("\"") || piece.hasPrefix("#\"")
                    ? SanitizationBoundaryTests.interpolations(in: piece).allSatisfy { names($0, in: notes) }
                    : names(piece, in: notes)
            }
        }
        guard let ident = firstIdentifier(of: e) else { return false }
        return notes.range(of: "(?<![A-Za-z0-9_$])\(NSRegularExpression.escapedPattern(for: ident))(?![A-Za-z0-9_])",
                           options: .regularExpression) != nil
    }

    /// `openAt` 那個 `(` 的配對 `)`；字串內的括號不算。配不上回 nil。
    private static func matchingClose(in s: String, openAt: String.Index) -> String.Index? {
        var depth = 0; var inString = false; var i = openAt
        while i < s.endIndex {
            let c = s[i]
            if inString {
                if c == "\\" { i = s.index(after: i); if i == s.endIndex { return nil } }
                else if c == "\"" { inString = false }
            } else if c == "\"" { inString = true }
            else if c == "(" { depth += 1 }
            else if c == ")" { depth -= 1; if depth == 0 { return i } }
            i = s.index(after: i)
        }
        return nil
    }
}
