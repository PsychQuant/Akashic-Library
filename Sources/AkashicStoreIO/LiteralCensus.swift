import Foundation
import AkashicCore

/// 四域 literal 普查（#303 design D5）——literal 歸零 campaign 每輪進度量測的唯一來源。
///
/// （原為 `plugin/skills/akashic-promote-literals/scripts/literal-census.sh`，內嵌 573 行 Python；
/// #629 移植成 Swift，並成為 `akashic literal-census` 子命令。）
///
/// ## 口徑（R1-fix I4 統一；兩個都報，只報比率會藏住 pending）
///
/// - **總邊**：該域 ref 邊總數（key ＋ literal）
/// - **literal 邊**：`.literal` ref 的出現次數（**歸零的終局量測就是這個數**）
/// - **distinct**：不同 literal 字串數（查證工作量的估計；以**位元組**區分，NFC／NFD 各算一個——
///   與 Python 版相同，不是 Swift `String` 的 canonical 相等）
///
/// venue 域的「未部署」≠ 0：報 0 會把「還沒部署」與「查完了」折成同一個觀察，而缺席與零必須可區分。
/// 「未部署」只在**兩個條件同時成立**時才印：marker 讀得到且版號 < 11，**而且**這一輪一條 venue 邊都沒
/// 解析到。先前寫的是「format < 11 時 venue 邊不存在於模型中」——一句全稱句，而它會不成立：磁碟上的 YAML
/// 可以帶 `venues:` 而 marker 說版號較低（手改、複製、遷移中途）。那種情形要報的是**不一致**，不是「不存在」。
///
/// ## marker 由讀端自己判，不再有第二份實作（#629）
///
/// shell＋Python 版要用 Python 重寫一份讀端的 marker grammar（`_read_marker`、19 個 scalar 的空白表、
/// 由 Swift 生成的「`#` 後接 grapheme extender」表），再用兩支測試、一支負控 harness、一個生成器去量測
/// 兩份實作有沒有分岔——#407 的 R6～R18 有一半的輪次花在這上面。現在普查與讀端是**同一個 binary**：
/// marker 直接呼叫 `StoreVersion.read(root:)`，支援上限直接讀 `StoreVersion.supported`。分岔不是被守衛
/// 擋住，是**沒有第二份東西可以分岔**。隨之消失的還有三層「支援上限的來源」（探測 binary／讀 checkout
/// 的原始碼／未知）與兩態（`undecidable`：判註解用的表讀不到；`ceiling-unknown`）——普查自己就是那個 binary。
///
/// 仍然只有一件事**不**共用讀端：**計數本身**。普查是對 YAML 原文的結構掃描（與 Python 版逐行同語意），
/// 不經 `LibraryStore.load`——這是刻意的：讀端拒開的 store（版號太新、marker 壞掉）仍要能印出計數，讓使用者
/// 看到「這些數字是掃出來的、不代表任何 binary 讀得到」。掃描與 Python 版的語意差異記在各函式旁。
///
/// 輸出去向：本命令的產出會被貼進 issue。所以路徑一律縮成 ~ 形式，不印使用者名。
public enum LiteralCensus {

    // MARK: - 結果型別

    /// 一個域的計數。
    public struct Domain: Equatable {
        public var key = 0
        public var literal = 0
        /// 解碼後的 literal（以 Unicode scalar 序列區分，見上）。
        public var distinct = Set<[UInt32]>()
        public var total: Int { key + literal }
        public init() {}
    }

    /// marker 的四態。讀端對每一態的裁決寫在各分支。
    public enum MarkerState: Equatable {
        /// 讀到合法 marker，值為 format。
        case read(Int)
        /// 檔案不存在。讀端明訂「**缺檔 ＝ format 1**，不是錯誤」——#24 之前寫的 store 都沒有這個檔，
        /// 它們就是 v1.x。合法 legacy，不是儀器失敗。
        case absent
        /// 檔案在但 grammar 不合。讀端 throw；**任何 binary 都打不開這個 store**。`detail` 已消毒。
        case malformed(detail: String)
        /// 開不了檔（權限／IO／是目錄）。與「不存在」是不同的事，不得折在一起。
        case unreadable(detail: String)
    }

    public struct Report: Equatable {
        public var root: String
        public var marker: MarkerState
        /// 本 binary 支援的最高 format（`StoreVersion.supported`）。
        public var supported: Int
        public var author = Domain()
        public var venue = Domain()
        public var affiliation = Domain()
        public var orgParents = Domain()
    }

    /// 普查跑不起來的四種原因（封閉列舉）；exit code 沿用 shell 版的 2／3。
    public enum Failure: Error, Equatable {
        /// `entities/`、`entries/`、`people/` 皆缺——那不是 Akashic store。exit 2。
        case notAStore(root: String)
        /// `entities/` 非空但匹配不到任何 `.yaml`——路徑或權限異常，拒絕輸出計數。exit 3。
        case entitiesWithoutYAML(root: String)
        /// 某個 `.yaml` 讀不進來（權限、是目錄…）。**不得靜默少算**——少算一個檔的普查與「查完歸零」
        /// 無法區分。exit 3。`detail` 是程式自己的固定說明（「是目錄」「讀不到」），不是 store 內容。
        case unreadableRecord(path: String, detail: String)
        /// 某個要掃的目錄（`entities/`、`entries/`、`people/`）存在但列不出來（權限、I/O）。第一版把列目錄的錯誤轉成空清單，於是
        /// 一個不可列的 `entities/` 讓 `entitiesWithoutYAML` 也不觸發，印出全零的四域普查——那讀起來像「literal 歸零」（campaign 的
        /// 終點），實際是 store 讀不了（R1 verify 第 4 則）。「不存在」「空」「列不出來」是三件事。exit 3。
        case unlistableDirectory(path: String, detail: String)

        public var exitCode: Int32 {
            switch self {
            case .notAStore: return 2
            case .entitiesWithoutYAML, .unreadableRecord, .unlistableDirectory: return 3
            }
        }

        /// 已消毒的訊息（路徑是使用者給的，檔名是 store 內容）。
        public var message: String {
            switch self {
            case .notAStore(let root):
                return "✗ 「\(displaySafeInvisible(LiteralCensus.tilde(root), max: 300))」不是 Akashic store（entities/／entries/／people/ 皆缺）"
            case .entitiesWithoutYAML(let root):
                return "✗ entities/ 非空但匹配不到任何 .yaml——路徑或權限異常，拒絕輸出計數（\(displaySafeInvisible(LiteralCensus.tilde(root), max: 300))）"
            case .unlistableDirectory(let path, let detail):
                return "✗ 列不出 \(displaySafeInvisible(LiteralCensus.tilde(path), max: 300)) 的內容：\(detail)——拒絕輸出計數（少算與「查完歸零」無法區分）"   // display-safe-exempt: detail：程式的固定說明字串
            case .unreadableRecord(let path, let detail):
                return "✗ 讀不進 \(displaySafeInvisible(LiteralCensus.tilde(path), max: 300))：\(detail)——拒絕輸出計數（少算一個檔與「查完歸零」無法區分）"   // display-safe-exempt: detail：程式的固定說明字串（「是目錄」「讀不到」），不是 store 內容
            }
        }
    }

    // MARK: - 執行

    /// 掃 `root` 底下的記錄檔並讀 marker。
    ///
    /// 掃描範圍是**合併掃描**（R5 更正 R4-8 的「切換」誤修）：`entities/`＋`entries/`＋`people/` 並存讀取——
    /// loader 的 `load()` 本來就並存讀取（LibraryStore doc「與 legacy 並存讀取」；中斷遷移的 store 在 loader
    /// 眼中就是兩筆），普查與 loader 同語意才不會在混合佈局報假零（R4 實測：legacy＋1 個 entities 檔 →
    /// 切換版報 0，doctor 報 2）。檔名判準沿用 Python 版的 `glob("*.yaml")`：**大小寫敏感、不含隱藏檔**。
    public static func run(root: String) throws -> Report {
        let fm = FileManager.default
        func isDirectory(_ p: String) -> Bool {
            var d: ObjCBool = false
            return fm.fileExists(atPath: p, isDirectory: &d) && d.boolValue
        }
        guard isDirectory("\(root)/entities") || isDirectory("\(root)/entries") || isDirectory("\(root)/people") else {
            throw Failure.notAStore(root: root)
        }

        var files: [String] = []
        var entitiesListing: [String] = []
        for sub in ["entities", "entries", "people"] {
            let dir = "\(root)/\(sub)"
            guard isDirectory(dir) else { continue }
            // 列不出來 ≠ 空：錯誤具名拒絕，不轉成空清單
            let listing: [String]
            do { listing = try fm.contentsOfDirectory(atPath: dir) } catch {
                throw Failure.unlistableDirectory(path: dir, detail: errnoName(of: error))
            }
            if sub == "entities" { entitiesListing = listing }
            for name in listing.sorted() where name.hasSuffix(".yaml") && !name.hasPrefix(".") {
                files.append("\(dir)/\(name)")
            }
        }
        if files.isEmpty, !entitiesListing.isEmpty {
            throw Failure.entitiesWithoutYAML(root: root)
        }

        var report = Report(root: root, marker: readMarker(root: root), supported: StoreVersion.supported)
        for f in files {
            guard let data = fm.contents(atPath: f), !isDirectory(f) else {
                throw Failure.unreadableRecord(path: f, detail: isDirectory(f) ? "是目錄" : "讀不到")
            }
            let parent = ((f as NSString).deletingLastPathComponent as NSString).lastPathComponent
            scan(text: decodeText(data), parent: parent, into: &report)
        }
        return report
    }

    /// Python `open(f, encoding='utf-8', errors='replace').read()`：壞位元組換成 U+FFFD，
    /// **文字模式的 universal newlines**——`\r\n` 與孤立的 `\r` 都讀成 `\n`。
    /// （後者是 Python 的隱性行為，普查的每個樣式都建立在它上面：CRLF 的檔與 LF 的檔計數相同。）
    static func decodeText(_ data: Data) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        out.reserveCapacity(data.count)
        var prevCR = false
        for s in String(decoding: data, as: UTF8.self).unicodeScalars {
            if s == "\r" { out.append("\n"); prevCR = true; continue }
            if s == "\n" && prevCR { prevCR = false; continue }
            prevCR = false
            out.append(s)
        }
        return out
    }

    // MARK: - marker

    /// 讀端的 marker 裁決，歸到四態。**直接呼叫 `StoreVersion.read`**——不重寫 grammar。
    public static func readMarker(root: String) -> MarkerState {
        let url = StoreVersion.url(in: URL(fileURLWithPath: root))
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return .absent }
        // 讀端對目錄不走 malformed：fileExists 為真、Data(contentsOf:) 對目錄 throw 一個 IO 錯誤。
        // 與 chmod 000 同類——marker 讀不進來，不是 grammar 不合。
        if isDir.boolValue { return .unreadable(detail: "(是目錄)") }
        do {
            return .read(try StoreVersion.read(root: URL(fileURLWithPath: root)))
        } catch StoreVersionError.malformed(_, let line) {
            // `line` 在擲出端已過 displaySafeInvisible；固定說明（「(標記檔不是 UTF-8)」等）以括號開頭。
            return .malformed(detail: line.hasPrefix("(") ? line : "(有問題的那一行：`\(line)`)")
        } catch {
            return .unreadable(detail: "(\(errnoName(of: error)))")
        }
    }

    /// 讀不進來的原因名（`EACCES` 之類）。找不到 POSIX 底層錯誤時退回 Cocoa 的說法。
    static func errnoName(of error: Error) -> String {
        let ns = error as NSError
        let posix: NSError? = ns.domain == NSPOSIXErrorDomain ? ns : ns.userInfo[NSUnderlyingErrorKey] as? NSError
        guard let code = posix.map({ Int32($0.code) }) else { return "\(ns.domain) \(ns.code)" }
        let names: [Int32: String] = [
            EPERM: "EPERM", ENOENT: "ENOENT", EIO: "EIO", EACCES: "EACCES", ENOTDIR: "ENOTDIR",
            EISDIR: "EISDIR", EMFILE: "EMFILE", ELOOP: "ELOOP", ENAMETOOLONG: "ENAMETOOLONG",
        ]
        return names[code] ?? "errno \(code)"
    }

    // MARK: - 掃描（YAML 原文的結構樣式，與 Python 版逐行同語意）

    static func scan(text t: [Unicode.Scalar], parent: String, into report: inout Report) {
        // legacy 佈局檔無形狀前綴——依目錄判 kind（entries/=work、people/=person）
        func starts(_ p: String) -> Bool { t.hasPrefix(p) }
        let isWork = starts("work:") || (parent == "entries" && !(starts("person:") || starts("organization:")))
        let isPerson = starts("person:") || (parent == "people" && !(starts("work:") || starts("organization:")))

        if isWork {
            // authors 區塊：每個項目一行，後面可跟縮排兩格的續行（`- organization:` 等其他項目不計）
            let a = itemBlock(t, header: "\nauthors:\n", allowContinuation: true)
            report.author.key += a.filter { $0.hasPrefix("- key: ") }.count
            for line in a where line.hasPrefix("- literal: ") {
                report.author.literal += 1
                report.author.distinct.insert(decodeScalar(Array(line.dropFirst("- literal: ".unicodeScalars.count))))
            }
            // venues 區塊：只有單行項目
            let v = itemBlock(t, header: "\nvenues:\n", allowContinuation: false)
            report.venue.key += v.filter { $0.hasPrefix("- key: ") }.count
            for line in v where line.hasPrefix("- literal: ") {
                report.venue.literal += 1
                report.venue.distinct.insert(decodeScalar(Array(line.dropFirst("- literal: ".unicodeScalars.count))))
            }
        } else if starts("organization:") {
            // parents 是頂層鍵（非縮排）——與 person affiliations（profile 下縮排）不同形
            if let blk = lazyBlock(t, header: "\nparents:\n", endsAt: { t, e in
                e == t.count || (t[e] == "\n" && e + 1 < t.count && isLowerAlpha(t[e + 1]))
            }) {
                tallyValueBlock(blk, into: &report.orgParents)
            }
        } else if isPerson {
            if let blk = lazyBlock(t, header: "\n  affiliations:\n", endsAt: { t, e in
                if e == t.count { return true }
                guard t[e] == "\n" else { return false }
                if e + 3 < t.count, t[e + 1] == " ", t[e + 2] == " ", isLowerAlpha(t[e + 3]) { return true }
                return t.hasPrefix("profile", at: e + 1)
            }) {
                tallyValueBlock(blk, into: &report.affiliation)
            }
        }
    }

    private static func isLowerAlpha(_ s: Unicode.Scalar) -> Bool { s.value >= 0x61 && s.value <= 0x7A }

    /// `\nauthors:\n((?:- (?:key|literal): .*\n(?:  .*\n)*)*)`（或 venues 的 `((?:- (?:key|literal): .*\n)*)`）
    /// 取第一個 header 之後的項目行。每一行都要以 `\n` 收尾——最後一行沒有換行就不算（樣式如此）。
    /// header 不存在時回空陣列。
    static func itemBlock(_ t: [Unicode.Scalar], header: String, allowContinuation: Bool) -> [[Unicode.Scalar]] {
        guard let p = t.find(header) else { return [] }
        var i = p + header.unicodeScalars.count
        var lines: [[Unicode.Scalar]] = []
        func lineEnd(from i: Int) -> Int? {   // 下一個 `\n` 的位置
            var j = i
            while j < t.count { if t[j] == "\n" { return j }; j += 1 }
            return nil
        }
        while t.hasPrefix("- key: ", at: i) || t.hasPrefix("- literal: ", at: i) {
            guard let e = lineEnd(from: i) else { break }
            lines.append(Array(t[i..<e]))
            i = e + 1
            if allowContinuation {
                while t.hasPrefix("  ", at: i), let ce = lineEnd(from: i) { i = ce + 1 }
            }
        }
        return lines
    }

    /// `header(.*?)(?=<endsAt>)`（re.S）：header 之後、**最短**滿足 `endsAt` 的位置之前的全部文字。
    /// header 不存在時回 nil。**保留樣式的怪癖**：header 那一行的換行已被消耗，所以緊接著的一行本身
    /// 不會被 `\n…` 的前瞻看見（空的 affiliations 會一路吃到下一個兄弟鍵之後）——這是 Python 版的行為，
    /// 忠實移植；emitter 產出的實際檔案不會走到那裡。
    static func lazyBlock(_ t: [Unicode.Scalar], header: String,
                          endsAt: ([Unicode.Scalar], Int) -> Bool) -> [Unicode.Scalar]? {
        guard let p = t.find(header) else { return nil }
        let start = p + header.unicodeScalars.count
        var e = start
        while e <= t.count {
            if endsAt(t, e) { return Array(t[start..<e]) }
            e += 1
        }
        return Array(t[start...])
    }

    /// `value:\n\s+key: ` 的次數，與 `value:\n\s+literal: (.*)$` 的每個群組。
    ///
    /// **兩個樣式各自獨立掃描**（Python 的兩次 `re.findall`，各自不重疊）：合成一趟看起來等價，但一個
    /// literal 的值本身以 `value:` 結尾、下一行又是 `key: ` 時，合成的版本會漏掉後者——樣式各自掃才與原版逐行同語意。
    static func tallyValueBlock(_ blk: [Unicode.Scalar], into d: inout Domain) {
        let head = Array("value:\n".unicodeScalars)
        /// 在 `blk` 中找每個 `value:\n\s+<token>` 的起點（不重疊）；回傳 token 之後的位置。
        func scan(token: String, _ visit: (_ after: Int) -> Int) {
            var i = 0
            while i < blk.count {
                guard blk.hasPrefix(head, at: i) else { i += 1; continue }
                var j = i + head.count
                let wsStart = j
                while j < blk.count, isPythonSpace(blk[j]) { j += 1 }   // `\s+`（貪婪；後面接的是非空白，回溯無用）
                if j > wsStart, blk.hasPrefix(token, at: j) {
                    i = visit(j + token.unicodeScalars.count)
                } else {
                    i += 1
                }
            }
        }
        scan(token: "key: ") { after in d.key += 1; return after }
        scan(token: "literal: ") { after in
            var k = after
            while k < blk.count, blk[k] != "\n" { k += 1 }   // `(.*)$`（re.M）：到行尾
            d.literal += 1
            d.distinct.insert(decodeScalar(Array(blk[after..<k])))
            return k
        }
    }

    // MARK: - YAML 單行純量解碼

    /// Python `str.isspace()`（＝`re` 的 `\s`、`str.strip()` 的預設集合）：Zs 類、或雙向類別為 WS／B／S。
    /// 列舉如下，不從 Unicode 屬性推導——與這支普查的「不要拿一句等式代替量測」同一個紀律。
    static func isPythonSpace(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x09...0x0D, 0x1C...0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A,
             0x2028, 0x2029, 0x202F, 0x205F, 0x3000:
            return true
        default:
            return false
        }
    }

    /// `literal:` 的值要按 YAML 純量語義解碼，不能原樣當字串（#407 R62）。實測 8 種寫法有 **7 種**分岔：
    /// 引號沒剝、尾隨註解吃進去、跳脫沒還原。而 `distinct literal` 是整個 campaign 的分母——分岔直接污染它。
    ///
    /// 涵蓋**單行**純量：雙引號（完整跳脫表，#407 R63／R64／R66）、單引號（`''` 是一個 `'`）、未加引號
    /// （` #` 起是註解）。區塊／摺疊純量（`|`／`>`）不在內。回傳 Unicode scalar 的數值（不建 `String`：
    /// `\uD800` 之類的孤立 surrogate 在 Python 版是合法 str、在 Swift 不是 `Unicode.Scalar`）。
    /// **與 Python 版唯一的行為差異**：`\UXXXXXXXX` 超出 U+10FFFF 時 Python 版整支普查 ValueError 中止，
    /// 這裡解成 U+FFFD——一筆惡意 literal 不該讓量測儀器倒掉。
    static func decodeScalar(_ raw: [Unicode.Scalar]) -> [UInt32] {
        let s = pyStrip(raw)
        if s.first == "\"" {
            let esc: [Unicode.Scalar: UInt32] = [
                "0": 0, "a": 7, "b": 8, "t": 9, "n": 10, "v": 11, "f": 12, "r": 13, "e": 27,
                " ": 0x20, "\"": 0x22, "/": 0x2F, "_": 0xA0, "N": 0x85, "L": 0x2028, "P": 0x2029,
            ]
            func hex(_ from: Int, _ count: Int) -> UInt32? {
                guard from + count <= s.count else { return nil }
                var v: UInt32 = 0
                for k in from..<(from + count) {
                    guard let d = hexDigit(s[k]) else { return nil }
                    v = v &* 16 &+ d
                }
                return v
            }
            var out: [UInt32] = []
            var i = 1
            while i < s.count, s[i] != "\"" {
                if s[i] != "\\" || i + 1 >= s.count { out.append(s[i].value); i += 1; continue }
                let e = s[i + 1]
                // `\U` 是 8 位（非 BMP：CJK 擴充 B、emoji）。只認小寫 `u` 會讓它落到 fallback、輸出字面的 `U`
                // 再把 8 個十六進位當文字（#407 R64）。
                if e == "U", let v = hex(i + 2, 8) { out.append(v > 0x10FFFF ? 0xFFFD : v); i += 10; continue }
                if e == "u", let v = hex(i + 2, 4) { out.append(v); i += 6 }
                else if e == "x", let v = hex(i + 2, 2) { out.append(v); i += 4 }
                else { out.append(esc[e] ?? e.value); i += 2 }
            }
            return out
        }
        if s.first == "'" {
            var out: [UInt32] = []
            var i = 1
            while i < s.count {
                if s[i] == "'" {
                    if i + 1 < s.count, s[i + 1] == "'" { out.append(0x27); i += 2; continue }
                    break
                }
                out.append(s[i].value); i += 1
            }
            return out
        }
        // 未加引號：` #` 起是註解（YAML 要求註解前有空白；tab 不算）
        let body = s.find(" #").map { Array(s[..<$0]) } ?? s
        return pyStrip(body).map(\.value)
    }

    private static func hexDigit(_ s: Unicode.Scalar) -> UInt32? {
        switch s.value {
        case 0x30...0x39: return s.value - 0x30
        case 0x41...0x46: return s.value - 0x41 + 10
        case 0x61...0x66: return s.value - 0x61 + 10
        default: return nil
        }
    }

    private static func pyStrip(_ s: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var a = 0, b = s.count
        while a < b, isPythonSpace(s[a]) { a += 1 }
        while b > a, isPythonSpace(s[b - 1]) { b -= 1 }
        return Array(s[a..<b])
    }

    // MARK: - 呈現

    /// 報告的文字行。**先報量到的，解釋擺後面**——前一版反過來（先套 format 的解釋、再決定要不要印計數），
    /// 於是在 format 未知時印出「下面的計數是實際掃到的」而下面根本沒有計數行；在 format 缺檔時，明明手上握著
    /// 已解析的 venue 邊，卻宣告「venue 邊不存在於模型中」。兩者都是拿推論蓋掉量測。
    public static func render(_ r: Report, displayRoot: String) -> [String] {
        let fmt: Int?
        switch r.marker {
        case .read(let n): fmt = n
        case .absent: fmt = 1          // 讀端約定：缺檔即 format 1
        case .malformed, .unreadable: fmt = nil
        }
        // 版號超過本 binary 上限。**這個「本 binary」就是讀端本身**——不再有「問到的 binary」與「這份
        // checkout 的 source」兩個可能不同版的上限（shell 版的三層來源與其降級措辭在此全部消失）。
        let tooNew: Bool = { if case .read(let n) = r.marker { return n > r.supported }; return false }()
        let storeUnopenable: Bool = {
            switch r.marker {
            case .malformed, .unreadable: return true
            default: return tooNew
            }
        }()

        func label() -> String {
            if tooNew, let f = fmt {
                return "format \(f)——**超過你的 binary 支援上限 \(r.supported)**"
                     + "（就是執行本命令的這個 akashic；讀端與普查是同一個 binary）；它會整體拒開此 store"
            }
            switch r.marker {
            // 標籤自帶「format」一詞：呼叫端直接嵌入句子，不另外前綴。
            case .absent: return "format 1（無 store.yaml；讀端語意：缺檔即 format 1）"
            case .unreadable(let d): return "format **未知**——store.yaml 開不了 \(d)"   // display-safe-exempt: d：readMarker 給的固定說明（errno 名或「是目錄」），不是 store 內容
            case .malformed(let d): return "format **未知**——marker 不合 grammar \(d)；**讀端會整體拒開此 store**"   // display-safe-exempt: d：`StoreVersion.read` 在擲出端已過 displaySafeInvisible 的那一行（或固定的括號說明）
            case .read(let n): return "format \(n)"   // display-safe-exempt: n 是 Int
            }
        }

        func row(_ name: String, _ d: Domain) -> String {
            let pct = d.total > 0 ? String(format: "%.1f%%", Double(d.literal) / Double(d.total) * 100) : "—"
            let padded = name + String(repeating: " ", count: max(0, 14 - name.count))
            let total = String(d.total)
            let totalPadded = String(repeating: " ", count: max(0, 5 - total.count)) + total
            return "\(padded) 總邊 \(totalPadded)｜literal 邊 \(d.literal)（佔 \(pct)）｜key \(d.key)｜distinct literal \(d.distinct.count)"   // display-safe-exempt: d 是 Domain：三個都是整數計數；padded 是本函式的固定域名
        }
        let indent = String(repeating: " ", count: 14)

        var out = ["store: \(displayRoot)（\(label())）"]
        // marker 壞到讀端會整體拒開時，**這一輪的每一個數字都不能拿去定批次範圍**——不只 venue 那一列。
        // author 才是 campaign 的終局量測，而前一版只在 venue 那一列掛但書，author 照常裸印（R6 finding 50）。
        if storeUnopenable {
            out.append("\(indent) ⚠ 讀端會整體拒開此 store，**下面每一列都不能拿去定 campaign 的批次範圍**"
                     + "——它們是直接掃 YAML 得到的，不代表任何 binary 讀得到這些內容")
        }
        out.append(row("author", r.author))

        // venue 的三分支
        if r.venue.total > 0 {
            // 量到就印，不論 format 說什麼。format 與量測不一致時，把不一致本身報出來。
            out.append(row("venue", r.venue))
            switch r.marker {
            case .read(let n) where !tooNew && n < 11:
                // marker **說得出**一個版號，而它與量測不合——這才是「兩者不一致」。
                out.append("\(indent) ↑ 註：marker 說 format \(n)（< 11，該版本沒有 venue 邊），"
                         + "而上列是**實際解析到的**——兩者不一致，請查 store 狀態")
            case .absent:
                // **缺檔時不能說「marker 說」**——根本沒有 marker 說過任何話。`fmt=1` 是讀端的約定
                // （缺檔即 format 1），不是某份文件的陳述（#407 R17）。
                out.append("\(indent) ↑ 註：沒有 store.yaml——讀端把這種 store 當 format 1，"
                         + "而該版本沒有 venue 邊，上列卻**實際解析到了**。兩者不一致，請查 store 狀態")
            case .malformed, .unreadable:
                // marker 壞掉時它**什麼版本都沒說**，談不上「說不是」（R6 finding 28）。
                out.append("\(indent) ↑ 註：marker 讀不出版號，所以無法判斷上列 venue 邊"
                         + "是否屬於這個 store 的模型——上游的全域警告已說明數字不可用")
            default:
                break
            }
        } else if let f = fmt, f >= 11 {
            out.append(row("venue", r.venue))          // 已部署且真的是 0
        } else if case .absent = r.marker {
            // **缺檔不是壞掉**：讀端明訂缺檔即 format 1。前一版對這個情形也印「先修好 marker」，
            // 而根本沒有東西要修，且那句話指名了一個動作（R6 finding 39）。
            out.append("venue          未部署（無 store.yaml ＝ format 1，而 venue 邊自 format 11 起"
                     + "才存在於模型中；本輪零 venue 邊——非「查完」。"
                     + "部署鏈見 Akashic-Library repo 的 docs/store-format.md format 11 列（不隨 plugin 出貨，plugin 安裝處讀不到））")
        } else if case .read(let n) = r.marker {
            out.append("venue          未部署（marker 說 format \(n)，< 11——該版本沒有 venue 邊；"
                     + "本輪零 venue 邊——非「查完」。"
                     + "部署鏈見 Akashic-Library repo 的 docs/store-format.md format 11 列（不隨 plugin 出貨，plugin 安裝處讀不到））")
        } else {
            out.append("venue          **未知**（\(label())；且未解析到任何 venue 邊——"
                     + "無法區分「未部署」與「已部署但為 0」。先修 store.yaml 再重跑）")
        }
        out.append(row("affiliation", r.affiliation))
        out.append(row("org-parents", r.orgParents))
        return out
    }

    /// 把 `$HOME` 前綴縮成 `~`。輸出會進 issue，不印使用者名。
    ///
    /// 只處理前綴——store root 之外的路徑本命令不印。**比到路徑邊界**，不是裸前綴：裸前綴在 HOME=/home/ann
    /// 時會把 /home/anna/x 改寫成 ~a/x —— 一個不存在的路徑，而這份輸出的去向是 issue。
    public static func tilde(_ path: String, home: String? = nil) -> String {
        var h = home ?? ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        while h.count > 1, h.hasSuffix("/") { h.removeLast() }
        guard !h.isEmpty else { return path }
        if path == h { return "~" }
        if path.hasPrefix(h + "/") { return "~" + String(path.dropFirst(h.count)) }
        return path
    }
}

// MARK: - Unicode scalar 陣列的小工具（普查專用）

extension Array where Element == Unicode.Scalar {
    /// 從 `i` 起是否以 `p` 開頭（逐 scalar 比對——Swift `String.hasPrefix` 是 grapheme 層、且 canonical 相等，
    /// 與 Python 的 code point 比較不同：`work:` 後接組合符號時兩者答案相反）。
    func hasPrefix(_ p: String, at i: Int = 0) -> Bool { hasPrefix(Array(p.unicodeScalars), at: i) }

    func hasPrefix(_ p: [Unicode.Scalar], at i: Int = 0) -> Bool {
        guard i >= 0, i + p.count <= count else { return false }
        for k in 0..<p.count where self[i + k] != p[k] { return false }
        return true
    }

    /// 第一個 `p` 出現的位置。
    func find(_ p: String) -> Int? {
        let needle = Array(p.unicodeScalars)
        guard !needle.isEmpty, needle.count <= count else { return nil }
        for i in 0...(count - needle.count) where hasPrefix(needle, at: i) { return i }
        return nil
    }
}
