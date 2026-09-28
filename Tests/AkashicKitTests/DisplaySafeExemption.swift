import Foundation

/// `display-safe-exempt:` 註記的豁免規則——擲出站點守衛（`SanitizationBoundaryTests.testEveryThrowSiteEscapesEachPayloadExactlyOnce`）
/// 與 sink 守衛（`DisplaySinkCoverageTests.scanViolations`）共用這一份（#584）。
///
/// 規則（#554 R31／R32 起；#584 R1 verify 收緊）：只看**註解裡**標記**之後**的文字；一個運算式被豁免，當且僅當它拆得開，
/// 而且**每一個帶執行期資料的運算元**的第一個識別字都以完整字詞出現在那段文字裡。
/// 註記具名什麼就免檢什麼——一句講 `idx` 的註記不會讓同一行的 `entry.title` 免檢，也不會讓 `idx + entry.title` 的第二個運算元免檢。
///
/// 為什麼是一份：R31 把擲出站點守衛改成這條規則時，sink 守衛仍是整行豁免（`if l.contains("display-safe-exempt:") { continue }`），
/// 兩支守衛對同一個標記給出兩種粒度，而讀程式碼的人看不出哪一支在看哪一行（#554 R32 verify regression 第 37 列）。
///
/// ## 運算式怎麼拆（封閉列舉；拆不開一律不豁免——fail-closed，不是「拆不開就放行」）
///
/// 1. **開頭的 `return`／`try`／`try?`／`try!`／`await` 與前綴 `!`／`-` 不算**：關鍵字與前綴運算子不指認任何值
///    （sink 守衛會從 `case "k": return v` 抽出 `return v`）。
/// 2. **頂層的二元運算子把運算式切成運算元，每個運算元各自要被具名**：`??`、三元 `? :`（條件與兩個分支都算）、`+ - * / %`、
///    `== != < > <= >=`、`&& ||`、`...`／`..<`。運算子兩側要有空白；沒有空白的（`a+b`）不認得，落到第 7 條。
///    `as`／`as?`／`as!`／`is` 的右邊是型別，不是值。
/// 3. **括號包住的運算式**：拆開括號裡面（逗號分隔的 tuple 每個元素都算），之後可以接成員或呼叫（`(a ?? b).count`）。
/// 4. **字串字面**（`"…"`／`#"…"#`）：字面文字是程式文字、不帶執行期資料；每個插值各自要被具名。字面**後面接尾段**
///    （`"x".appending(raw)`）拆不開——尾段沒有插值、也不被 `+` 切開，不得因此免檢。
/// 5. **常量**：數字、`true`／`false`／`nil`、`[]`／`[:]`、key path 字面（`\.value`：接收者上的投影，不引進新的值），不需要具名。
///    陣列／字典字面逐元素對照。
/// 6. **鏈**：`頭.成員(…)[…] { … }`——頭的識別字要具名，每個呼叫引數（去掉 `label:`）、每個有標籤的下標引數（`default:` 之類會流進結果）、
///    尾隨閉包的 body 各自是運算元。**無標籤的下標引數是查找鍵，不流進結果**，不要求具名。成員名（`.title`）不獨立要求具名——
///    粒度是頭的識別字，不是成員路徑（已知邊界）。頭是前導點（`.string(x)`）時成員名不是值、不要求具名；頭是 `displaySafeClipOnly`
///    時函式名不指認任何值（它**只截不逃**，`Models.swift` 的 doc：「不得拿它接未消毒的 store 字串」），要具名的是載體。
/// 7. **其餘一律不豁免**：if／switch 運算式、沒有空白的運算子、不認得的尾段。
///
/// 「具名」＝那個識別字以**完整字詞**出現在註記裡，且前一個字元不是 `.`——註記寫 `entry.title` 只指認 `entry`，不指認裸的 `title`
///（R1 verify 第 5 列：先前的 lookbehind 沒有排除 `.`，一句講 `entry.citekey` 的註記讓另一個值 `citekey` 免檢）。
/// `$` 算識別字元，讓 `$0` 可以被具名。
enum DisplaySafeExemption {
    static let marker = "display-safe-exempt:"

    /// 各行**註解裡**標記之後的文字，沒有標記的行不貢獻。只看標記之後：標記之前是程式碼，運算式的識別字必然出現在那裡（R30 verify 第 4 列的毯式豁免）。
    /// 只認註解裡的標記（R1 verify 第 24／27 列）：`print("display-safe-exempt: \(entry.title)")` 沒有註解，標記在字串字面裡，
    /// 後面的程式碼不是註記。註解的起點由 `SanitizationBoundaryTests.strippingLineComments` 判定（引號感知），兩支守衛用同一個。
    static func notes<S: StringProtocol>(in lines: [S]) -> String {
        lines.compactMap { line -> String? in
            let chars = Array(String(line))
            let stripped = Array(SanitizationBoundaryTests.strippingLineComments(String(line)))
            guard chars.count == stripped.count,
                  let start = chars.indices.first(where: { chars[$0] != stripped[$0] }) else { return nil }   // 沒有註解
            let comment = String(chars[start...])
            guard let r = comment.range(of: marker) else { return nil }
            return String(comment[r.upperBound...])
        }.joined(separator: "\n")
    }

    /// 註記有沒有具名這個運算式的每一個運算元（見型別 doc）。
    static func names(_ expr: String, in notes: String) -> Bool {
        guard !notes.isEmpty else { return false }
        return covered(expr, notes: notes)
    }

    // MARK: - 運算式的拆解

    private static func covered(_ raw: String, notes: String) -> Bool {
        var e = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let r = e.range(of: #"^(return|try[?!]?|await)\s+"#, options: .regularExpression) {
            e = String(e[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        while e.hasPrefix("!") || e.hasPrefix("-") { e = String(e.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !e.isEmpty else { return false }
        let scanned = scan(e)
        let parts = operands(of: scanned)
        if parts.count > 1 {
            return parts.allSatisfy { part in
                if let op = part.precededBy, ["as", "as?", "as!", "is"].contains(op) { return true }   // 右邊是型別
                return covered(part.text, notes: notes)
            }
        }
        return coveredOperand(e, scanned, notes: notes)
    }

    /// 沒有頂層運算子的單一運算元。
    private static func coveredOperand(_ e: String, _ s: Scanned, notes: String) -> Bool {
        let chars = s.chars
        // 字串字面：後面不得有尾段；插值各自具名
        if e.hasPrefix("\"") || e.hasPrefix("#\"") {
            guard s.literalEnds.first == chars.count else { return false }
            return SanitizationBoundaryTests.interpolations(in: e).allSatisfy { covered($0, notes: notes) }
        }
        if e.range(of: #"^([0-9][0-9_]*(\.[0-9][0-9_]*)?|true|false|nil|\[\]|\[:\])$"#, options: .regularExpression) != nil { return true }
        // key path 字面（`\.value`、`\Type.member`）是接收者上的投影，不引進新的值——資料來自收到它的那個運算式，那個運算式要自己被具名
        if e.range(of: #"^\\[A-Za-z_]*(\.[A-Za-z_]\w*)+$"#, options: .regularExpression) != nil { return true }
        return coveredChain(chars, notes: notes)
    }

    /// `頭.成員(…)[…] { … }`：頭具名（或是前導點／clipOnly），呼叫引數、有標籤的下標引數、尾隨閉包各自是運算元。認不得的尾段回 false。
    private static func coveredChain(_ chars: [Character], notes: String) -> Bool {
        let n = chars.count
        var i = 0
        func isIdent(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" || c == "$" }
        func ident(at start: Int) -> (name: String, end: Int) {
            var j = start
            while j < n, isIdent(chars[j]) { j += 1 }
            return (String(chars[start..<j]), j)
        }
        if chars[0] == "." {
            let m = ident(at: 1)
            guard !m.name.isEmpty else { return false }
            i = m.end   // 前導點：`.foo`／`.foo(x)`——成員名不是值，引數才是
        } else if isIdent(chars[0]) {
            let head = ident(at: 0)
            i = head.end
            let clipOnly = head.name == "displaySafeClipOnly" && i < n && chars[i] == "("
            if !clipOnly && !isNamed(head.name, in: notes) { return false }
        } else if chars[0] == "(" || chars[0] == "[" {
            // 括號包住的運算式／tuple、陣列／字典字面：逐元素（字典的 `k: v` 兩邊都算），之後可以接成員或呼叫
            guard let close = matchingClose(chars, open: 0) else { return false }
            let isParen = chars[0] == "("
            let items = SanitizationBoundaryTests.topLevelArguments(
                of: isParen ? String(chars[0...close]) : "(" + String(chars[1..<close]) + ")")
            for item in items {
                for piece in isParen ? [stripLabel(item)] : splitTopLevelColon(item) {
                    guard covered(piece, notes: notes) else { return false }
                }
            }
            i = close + 1
        } else if chars[0] == "{" {
            i = 0   // 裸閉包：由下面的尾隨閉包分支處理
        } else {
            return false
        }
        while i < n {
            let c = chars[i]
            if c == "." || ((c == "?" || c == "!") && i + 1 < n && chars[i + 1] == ".") {
                if c != "." { i += 1 }
                let m = ident(at: i + 1)
                guard !m.name.isEmpty else { return false }
                i = m.end
            } else if c == "?" || c == "!" {
                i += 1
            } else if c == "(" {
                guard let close = matchingClose(chars, open: i) else { return false }
                let args = SanitizationBoundaryTests.topLevelArguments(of: String(chars[i...close]))
                guard args.allSatisfy({ covered(stripLabel($0), notes: notes) }) else { return false }
                i = close + 1
            } else if c == "[" {
                guard let close = matchingClose(chars, open: i) else { return false }
                // 無標籤的下標引數是查找鍵，不流進結果；有標籤的（`default: x`）會
                for arg in SanitizationBoundaryTests.topLevelArguments(of: "(" + String(chars[(i + 1)..<close]) + ")") where hasLabel(arg) {
                    guard covered(stripLabel(arg), notes: notes) else { return false }
                }
                i = close + 1
            } else if c == "{" || c.isWhitespace {
                var j = i
                var sawNewline = false
                while j < n, chars[j].isWhitespace { if chars[j] == "\n" { sawNewline = true }; j += 1 }
                if j < n, chars[j] == "{" {
                    guard let close = matchingClose(chars, open: j) else { return false }
                    guard covered(closureBody(String(chars[(j + 1)..<close])), notes: notes) else { return false }
                    i = close + 1
                } else if j < n, chars[j] == ".", sawNewline {
                    i = j   // 換行後接 `.member` 的鏈
                } else { return false }
            } else {
                return false
            }
        }
        return true
    }

    /// 閉包字面的 body：去掉 `[capture] params in`。認不得參數形狀時整段當 body（fail-closed：多出來的識別字要具名）。
    private static func closureBody(_ inner: String) -> String {
        let pattern = #"^\s*(\[[^\]]*\]\s*)?(\([^)]*\)|[A-Za-z_$][\w$]*(\s*,\s*[A-Za-z_$][\w$]*)*)\s+in\s+"#
        if let r = inner.range(of: pattern, options: .regularExpression) { return String(inner[r.upperBound...]) }
        return inner
    }

    private static func hasLabel(_ arg: String) -> Bool { arg.range(of: #"^[A-Za-z_]\w*:\s*"#, options: .regularExpression) != nil }
    private static func stripLabel(_ arg: String) -> String {
        if let r = arg.range(of: #"^[A-Za-z_]\w*:\s*"#, options: .regularExpression) { return String(arg[r.upperBound...]) }
        return arg
    }

    /// `k: v`（字典字面的一個元素）在頂層冒號切成兩邊；沒有冒號就是單一運算式。
    private static func splitTopLevelColon(_ item: String) -> [String] {
        let s = scan(item)
        for (i, c) in s.chars.enumerated() where s.top[i] && c == ":" {
            return [String(s.chars[..<i]), String(s.chars[(i + 1)...])].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        return [item]
    }

    /// 這個識別字有沒有以完整字詞出現在註記裡。前一個字元不得是 `.`（成員鏈裡的名字不指認同名的裸識別字）。
    static func isNamed(_ ident: String, in notes: String) -> Bool {
        notes.range(of: "(?<![A-Za-z0-9_$.])\(NSRegularExpression.escapedPattern(for: ident))(?![A-Za-z0-9_])",
                    options: .regularExpression) != nil
    }

    // MARK: - 掃描：字串、括號、插值感知

    private struct Scanned {
        let chars: [Character]
        /// 這個字元位於最外層的程式碼（不在字串、括號、插值裡）。
        let top: [Bool]
        /// 最外層字串字面的結束處（收尾引號之後一格）。
        let literalEnds: [Int]
    }

    private static func scan(_ s: String) -> Scanned {
        let chars = Array(s)
        var top = [Bool](repeating: false, count: chars.count)
        var ends: [Int] = []
        enum Mode { case code, string, raw }
        var stack: [Mode] = [.code]; var depths: [Int] = [0]
        func at(_ k: Int) -> Character? { k < chars.count ? chars[k] : nil }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch stack.last! {
            case .string:
                if c == "\\" {
                    if at(i + 1) == "(" { stack.append(.code); depths.append(1); i += 2; continue }
                    i += 2; continue
                }
                if c == "\"" { stack.removeLast(); if stack.count == 1 { ends.append(i + 1) } }
            case .raw:
                if c == "\"", at(i + 1) == "#" { stack.removeLast(); if stack.count == 1 { ends.append(i + 2) }; i += 2; continue }
                if c == "\\", at(i + 1) == "#", at(i + 2) == "(" { stack.append(.code); depths.append(1); i += 3; continue }
            case .code:
                if stack.count == 1, depths[0] == 0 { top[i] = true }
                if c == "\"" { stack.append(.string) }
                else if c == "#", at(i + 1) == "\"" { stack.append(.raw); i += 2; continue }
                else if "([{".contains(c) { depths[depths.count - 1] += 1 }
                else if ")]}".contains(c) {
                    depths[depths.count - 1] -= 1
                    if depths.last! == 0, stack.count > 1 { stack.removeLast(); depths.removeLast() }   // 插值閉合，回到字串
                }
            }
            i += 1
        }
        return Scanned(chars: chars, top: top, literalEnds: ends)
    }

    /// `open` 那個括號的配對閉括號；字串、插值內的括號不算。配不上回 nil。
    private static func matchingClose(_ chars: [Character], open: Int) -> Int? {
        var depth = 0
        enum Mode { case code, string, raw }
        var stack: [Mode] = [.code]; var depths: [Int] = [0]
        func at(_ k: Int) -> Character? { k < chars.count ? chars[k] : nil }
        var i = open
        while i < chars.count {
            let c = chars[i]
            switch stack.last! {
            case .string:
                if c == "\\" {
                    if at(i + 1) == "(" { stack.append(.code); depths.append(1); i += 2; continue }
                    i += 2; continue
                }
                if c == "\"" { stack.removeLast() }
            case .raw:
                if c == "\"", at(i + 1) == "#" { stack.removeLast(); i += 2; continue }
                if c == "\\", at(i + 1) == "#", at(i + 2) == "(" { stack.append(.code); depths.append(1); i += 3; continue }
            case .code:
                if c == "\"" { stack.append(.string) }
                else if c == "#", at(i + 1) == "\"" { stack.append(.raw); i += 2; continue }
                else if "([{".contains(c) { depths[depths.count - 1] += 1; if stack.count == 1 { depth += 1 } }
                else if ")]}".contains(c) {
                    depths[depths.count - 1] -= 1
                    if stack.count == 1 { depth -= 1; if depth == 0 { return i } }
                    else if depths.last! == 0 { stack.removeLast(); depths.removeLast() }
                }
            }
            i += 1
        }
        return nil
    }

    // MARK: - 頂層運算子

    /// 長的先比：`as?` 在 `as` 之前、`??` 在 `?` 之前、`<=` 在 `<` 之前。
    private static let operatorTokens = ["as?", "as!", "as", "is", "??", "...", "..<", "==", "!=", "<=", ">=", "&&", "||",
                                         "?", "+", "-", "*", "/", "%", "<", ">", ":"]

    /// 在頂層（不在字串、括號、插值裡）、前後都有空白的運算子處切開。回傳每個運算元與它前面的運算子。
    private static func operands(of s: Scanned) -> [(precededBy: String?, text: String)] {
        let chars = s.chars; let n = chars.count
        var out: [(String?, String)] = []
        var start = 0; var op: String? = nil
        var i = 0
        while i < n {
            guard s.top[i], chars[i].isWhitespace else { i += 1; continue }
            var j = i
            while j < n, chars[j].isWhitespace { j += 1 }
            if j < n, s.top[j],
               let token = operatorTokens.first(where: { t in
                   let tc = Array(t)
                   return j + tc.count < n && Array(chars[j..<(j + tc.count)]) == tc && chars[j + tc.count].isWhitespace
               }) {
                out.append((op, String(chars[start..<i])))
                op = token
                start = j + token.count
                i = start
                continue
            }
            i = j
        }
        out.append((op, String(chars[start..<n])))
        return out
    }
}
