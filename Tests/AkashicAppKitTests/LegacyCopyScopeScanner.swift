import Foundation

/// #708 的源碼守衛掃描器：App 的每一個 store 寫入點都要在某個 `recordingLegacyCopies { … }` 的大括號裡。
///
/// R1 verify（第 13／20 列）指出初版的兩個靜默的洞，這裡一起補上：
/// - **掃描範圍**：初版只讀兩個目錄的第一層，日後 App 源碼開子目錄就整批不在掃描內，而下限（6 個寫入點）擋不住——其餘的檔仍湊得滿。
///   現在遞迴（`swiftFiles(under:)`）。
/// - **註解與字串**：初版以每行第一個 `//` 砍掉後半，字串字面值裡的 URL 會把同一行後面的 `}` 一起砍掉，字串裡的裸 `{`／`}` 讓深度失衡；
///   區塊註解還算程式碼。現在先把註解與字串字面值的內容換成空白（換行保留，行號不變），再數大括號、找寫入點。
/// - **函式值與跨行**：初版只認 `.writeEntry(` 這一個字面；`let w = store.writeEntry`（取函式值）與 `store\n    .writeEntry(e)`（跨行）看不到。
///   現在認 `.<方法名>` 後面不是識別字元的每一處。
///
/// **誠實邊界**（守衛仍看不到的）：
/// 1. 方法名單是封閉的四個（`writeMethods`）：App 長出別的 store 寫入方法（例如 `writeVenue`），要加進名單才會被掃。
/// 2. 範圍只認字面的 `recordingLegacyCopies { … }`（或 `({ … })`）：把閉包放在變數裡再傳進去認不出（會被當成範圍外，保守方向）。
/// 3. 「在範圍裡」是文字上的包含，不是呼叫圖：範圍裡呼叫、定義在範圍外的輔助函式，其中的寫入點被判成範圍外（保守）；範圍內的**逃逸閉包**
///    之後才執行的寫入被判成範圍內（漏報）——後者初版就記過；執行期由帳本在範圍結束後拒收晚到的寫入（#708 R2 verify 第 39 列），所以那種寫入會擲錯、不會安靜。
/// 4. 字串內插 `\( … )` 裡的程式碼整段當字串內容空白掉：寫在內插裡的寫入看不到（沒有人這樣寫）。
/// 5. `#if` 等編譯條件不展開：兩個分支都掃。
enum LegacyCopyScopeScanner {
    static let writeMethods = ["writeEntry", "writePerson", "renameEntry", "renamePerson"]

    // MARK: - 註解與字串字面值換成空白

    /// 註解與字串字面值的**內容**換成空白（含分隔符；換行保留，所以行號不變）。處理：`//`、可巢狀的 `/* */`、`"…"`、`"""…"""`、
    /// 帶 `#` 的 raw 字串（`#"…"#`、`##"…"##`），以及字串內插 `\( … )`（內插裡的字串字面值遞迴處理、括號配對）。
    static func blanked(_ source: String) -> String {
        let s = Array(source.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        blank(s, &i, &out, inInterpolation: false)
        return String(out)
    }

    private static let nl: Unicode.Scalar = "\n"
    private static let sp: Unicode.Scalar = " "

    private static func emit(_ c: Unicode.Scalar, _ out: inout String.UnicodeScalarView) {
        out.append(c == nl ? nl : sp)
    }

    /// 掃到 `i == s.count`，或（`inInterpolation` 時）碰到未配對的 `)` 為止；碰到時把 `i` 停在那個 `)` 上、不消耗它。
    /// `inInterpolation` 只在字串內插裡用：數巢狀的小括號，讓內插的結束位置正確。
    private static func blank(_ s: [Unicode.Scalar], _ i: inout Int, _ out: inout String.UnicodeScalarView, inInterpolation: Bool) {
        var depth = 0
        while i < s.count {
            let c = s[i]
            let next: Unicode.Scalar? = i + 1 < s.count ? s[i + 1] : nil
            if c == "/", next == "/" {
                while i < s.count, s[i] != nl { emit(s[i], &out); i += 1 }
            } else if c == "/", next == "*" {
                var d = 1
                emit(c, &out); emit(next!, &out); i += 2
                while i < s.count, d > 0 {
                    if s[i] == "/", i + 1 < s.count, s[i + 1] == "*" { d += 1; emit(s[i], &out); emit(s[i + 1], &out); i += 2 }
                    else if s[i] == "*", i + 1 < s.count, s[i + 1] == "/" { d -= 1; emit(s[i], &out); emit(s[i + 1], &out); i += 2 }
                    else { emit(s[i], &out); i += 1 }
                }
            } else if c == "\"" || c == "#" {
                var hashes = 0
                var j = i
                while j < s.count, s[j] == "#" { hashes += 1; j += 1 }
                if j < s.count, s[j] == "\"" {
                    blankString(s, &i, &out, hashes: hashes)
                } else {
                    out.append(c); i += 1   // 不是字串的開頭（`#if`、`#selector`……）
                }
            } else if inInterpolation, c == "(" {
                depth += 1; out.append(c); i += 1
            } else if inInterpolation, c == ")" {
                if depth == 0 { return }
                depth -= 1; out.append(c); i += 1
            } else {
                out.append(c); i += 1
            }
        }
    }

    /// `i` 在字串開頭的 `#…#"`。把整個字串（含分隔符）換成空白，`i` 停在結尾分隔符之後。
    private static func blankString(_ s: [Unicode.Scalar], _ i: inout Int, _ out: inout String.UnicodeScalarView, hashes: Int) {
        for _ in 0..<hashes { emit("#", &out); i += 1 }
        let multi = i + 2 < s.count && s[i] == "\"" && s[i + 1] == "\"" && s[i + 2] == "\""
        let quotes = multi ? 3 : 1
        for _ in 0..<quotes { emit("\"", &out); i += 1 }
        func closes(at k: Int) -> Bool {
            guard k + quotes + hashes <= s.count else { return false }
            for q in 0..<quotes where s[k + q] != "\"" { return false }
            for h in 0..<hashes where s[k + quotes + h] != "#" { return false }
            return true
        }
        func escapes(at k: Int) -> Bool {
            guard s[k] == "\\", k + hashes < s.count else { return false }
            for h in 0..<hashes where s[k + 1 + h] != "#" { return false }
            return true
        }
        while i < s.count {
            if closes(at: i) {
                for _ in 0..<(quotes + hashes) { emit(" ", &out); i += 1 }
                return
            }
            if !multi, s[i] == nl { return }   // 沒有結尾的單行字串：停在換行，不吃掉後面的程式碼
            if escapes(at: i) {
                // 反斜線加 `hashes` 個 `#`，接著是被跳脫的字元；`(` 開一個內插——裡面是程式碼，遞迴處理（裡面可以有字串）
                let afterEscape = i + 1 + hashes
                for _ in 0..<(1 + hashes) { emit(" ", &out); i += 1 }
                if afterEscape < s.count, s[afterEscape] == "(" {
                    emit("(", &out); i += 1
                    var inner = String.UnicodeScalarView()
                    blank(s, &i, &inner, inInterpolation: true)
                    for c in inner { emit(c, &out) }   // 內插裡的程式碼也整段空白掉（誠實邊界 4）
                    if i < s.count, s[i] == ")" { emit(")", &out); i += 1 }
                } else if i < s.count {
                    emit(s[i], &out); i += 1
                }
                continue
            }
            emit(s[i], &out); i += 1
        }
    }

    // MARK: - 範圍與寫入點

    /// `marker`（正規式，結尾是 `{`）之後那個 `{` 到它配對的 `}`（含）。`code` 必須是 `blanked` 的輸出：字串與註解裡的大括號已不在。
    static func braceRanges(in code: String, matching marker: String) -> [Range<String.Index>] {
        guard let re = try? NSRegularExpression(pattern: marker) else { return [] }
        var out: [Range<String.Index>] = []
        let ns = NSRange(code.startIndex..., in: code)
        for m in re.matches(in: code, range: ns) {
            guard let r = Range(m.range, in: code) else { continue }
            let open = code.index(before: r.upperBound)   // marker 以 `{` 結尾
            var depth = 0
            var i = open
            while i < code.endIndex {
                if code[i] == "{" { depth += 1 }
                if code[i] == "}" { depth -= 1; if depth == 0 { break } }
                i = code.index(after: i)
            }
            if i < code.endIndex { out.append(open..<code.index(after: i)) }
        }
        return out
    }

    static let scopeMarker = #"recordingLegacyCopies\s*\(?\s*\{"#

    struct Scan: Equatable {
        /// 找到的寫入點總數（含範圍內的）。
        var found: Int
        /// 不在任何範圍裡的寫入點：行號（1 起算）與方法名。
        var offenders: [String]
    }

    /// 一份源碼的掃描結果。`name` 只用來標示違規的位置。
    static func scan(_ source: String, name: String) -> Scan {
        let code = blanked(source)
        let scopes = braceRanges(in: code, matching: scopeMarker)
        let alternatives = writeMethods.joined(separator: "|")
        guard let re = try? NSRegularExpression(pattern: #"\.("# + alternatives + #")\b"#) else { return Scan(found: 0, offenders: []) }
        var found = 0
        var offenders: [String] = []
        for m in re.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
            guard let r = Range(m.range, in: code), let method = Range(m.range(at: 1), in: code) else { continue }
            found += 1
            if !scopes.contains(where: { $0.contains(r.lowerBound) }) {
                let line = code[..<r.lowerBound].filter { $0 == "\n" }.count + 1
                offenders.append("\(name):\(line) .\(code[method])")
            }
        }
        return Scan(found: found, offenders: offenders)
    }

    // MARK: - 遞迴列出檔案

    /// `dir` 底下所有 `.swift` 檔，**遞迴**，相對 `dir` 的路徑、排序。目錄不存在回空陣列（呼叫端的下限會擋下空掃描）。
    static func swiftFiles(under dir: URL) -> [String] {
        guard let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var out: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let base = dir.standardizedFileURL.path
            let path = url.standardizedFileURL.path
            out.append(path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : path)
        }
        return out.sorted()
    }
}
