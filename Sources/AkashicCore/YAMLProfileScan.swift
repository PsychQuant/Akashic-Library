import CYaml
import Foundation

/// 掃描 library 內的 YAML 檔，統計 store YAML profile 外的語法用了多少（開發用）。
///
/// （原為 `scripts/scan-yaml-profile.py`，#629 移植成 `akashic scan-yaml-profile`。）
///
/// 用途：#33（store YAML 輸入 profile）的證據來源。宣稱「真實 corpus 遷移成本為零」的那張表就是這支掃描
/// 產出的——放進 repo 是為了讓結論可重跑、可核對，而不是只能相信 issue 上的數字
/// （`docs/specs/2026-08-01-akashic-yaml-input-profile-design.md` §0：「保留，供日後 corpus 變化時重測」）。
///
/// 兩層輸出：
/// 1. **regex 層的粗掃**（含已知的 false positive，見 `--inspect`）——與 Python 版逐樣式同語意（`\s` 用 Python 的
///    空白集合明寫，不用 ICU 的；`^`／`$` 只認 `\n`，與 `re.M` 同）。
/// 2. **parser 層的 ground truth**——現在是 **libyaml 的 event 流**，也就是 store 讀端（Yams）用的那個 parser；
///    Python 版用的是 PyYAML，兩者對 anchor 與顯式 tag 的判定同義，但「這個 parser 就是讀端的 parser」讓
///    ground truth 不再需要假設。**不需要另外安裝任何東西**（Python 版沒裝 PyYAML 就只出第 1 段）。
///
/// 2026-08-01 的實測（Python 版）：13 個 anchor/alias regex 命中全部是期刊名裡的 `&amp;` 與引號內的
/// `*keyword*` 標記，parser 層 0 命中。
public enum YAMLProfileScan {

    /// profile 外的語法（顯示順序即輸出順序）。
    public static let features = [
        "BOM", "NEL/LS/PS", "tab", "CR", "comment line", "inline comment",
        "multi-doc ---", "anchor/alias", "explicit tag", "merge key",
        "block scalar |>", "flow seq [..]", "flow map {..}", "complex key ? k",
    ]

    public struct Result {
        public var root: String
        /// 掃到的 `.yaml` 檔（相對路徑排序不保證；只用名字與計數）。
        public var files: [String] = []
        /// feature → 命中的檔名（掃描順序）
        public var buckets: [String: [String]] = [:]
        /// max 縮排／2 → 檔數
        public var depth: [Int: Int] = [:]
        /// parser 層：真 anchor、非標準 tag、顯式 core tag、parse 失敗
        public var anchored: [String] = []
        public var tagged: [String] = []
        public var taggedCore: [String] = []
        public var failed: [(name: String, reason: String)] = []
        /// `--inspect`：regex 命中的實際文字（`檔名: 行`，前 110 字元）
        public var inspected: [String] = []
    }

    // MARK: - Python 的 `\s`

    /// Python `re` 的 `\s`（＝`str.isspace()`）：`[ \t\n\r\f\v]`、U+001C–001F、U+0085、U+00A0、U+1680、
    /// U+2000–200A、U+2028、U+2029、U+202F、U+205F、U+3000。ICU 的 `\s` 少了 `\v`、U+001C–001F、U+0085，
    /// 所以明寫。
    private static let pySpaceClass = #"\t-\r\x{1C}-\x{20}\x{85}\x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}"#
    private static let S = "[\(pySpaceClass)]"       // \s
    private static let N = "[^\(pySpaceClass)]"       // \S

    private static func regex(_ p: String, multiline: Bool = false) -> NSRegularExpression {
        var o: NSRegularExpression.Options = []
        // Python 的 `^`／`$`（re.M）與 `.` 只認 `\n`——ICU 預設也認 `\r`、U+0085、U+2028、U+2029
        if multiline { o.insert(.anchorsMatchLines) }
        o.insert(.useUnixLineSeparators)
        // 樣式都是編譯期常數；壞了是程式缺陷，不是輸入問題
        return try! NSRegularExpression(pattern: p, options: o)
    }

    private static let anchorAlias = regex("(^|[\(pySpaceClass)\\[{,])[&*][A-Za-z0-9_-]+")
    private static let tagRE = regex("(^|\(S))!!?[A-Za-z0-9_/-]*")
    private static let mergeKey = regex("^\(S)*<<\(S)*:", multiline: true)
    private static let blockScalar = regex(":\(S)*[|>][0-9+-]*\(S)*$", multiline: true)
    private static let exoticLineSeps = regex("[\u{85}\u{2028}\u{2029}]")
    /// 顯式 complex key（`? key`）——**這個統計是不完整的**（R12）。alias 落在 key 位置會在 compose 內部指數展開，
    /// 但 YAML 的 mapping key 根本不需要 `?`：`*a12: 1`（block 隱式）、`{*a12: 1}`（flow）都繞過本判準。
    /// 保留此欄僅供參考，**不可**用來論證「corpus 對該 DoS 免疫」——真正相關的是上面的 anchor/alias 統計。
    private static let complexKey = regex("^[ ]*\\?(?=[ \\t]|$)", multiline: true)
    private static let commentLine = regex("^\(S)*#", multiline: true)
    private static let inlineComment = regex("\(N)\(S)+#")
    private static let multiDoc = regex("^---", multiline: true)
    private static let flowSeq = regex(":\(S)*\\[")
    private static let flowMap = regex(":\(S)*\\{")

    private static func hits(_ re: NSRegularExpression, _ text: String) -> Bool {
        re.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    // MARK: - 掃描

    public static func scan(root: String, inspect: Bool = false) throws -> Result {
        var result = Result(root: root)
        for f in features { result.buckets[f] = [] }
        let fm = FileManager.default
        guard let e = fm.enumerator(atPath: root) else { return result }
        // `Path.rglob('*.yaml')`：遞迴、大小寫敏感；排序讓輸出可重現
        let rels = e.compactMap { $0 as? String }.filter { $0.hasSuffix(".yaml") }.sorted()
        for rel in rels {
            let name = (rel as NSString).lastPathComponent
            guard let data = fm.contents(atPath: "\(root)/\(rel)") else { continue }
            result.files.append(name)
            func mark(_ feature: String) { result.buckets[feature]!.append(name) }

            if data.starts(with: [0xEF, 0xBB, 0xBF]) { mark("BOM") }
            if data.contains(0x0D) { mark("CR") }
            let text = String(decoding: data, as: UTF8.self)
            if hits(exoticLineSeps, text) { mark("NEL/LS/PS") }
            if text.contains("\t") { mark("tab") }
            if hits(commentLine, text) { mark("comment line") }
            if hits(inlineComment, text) { mark("inline comment") }
            if hits(multiDoc, text) { mark("multi-doc ---") }
            if hits(anchorAlias, text) { mark("anchor/alias") }
            if hits(tagRE, text) { mark("explicit tag") }
            if hits(mergeKey, text) { mark("merge key") }
            if hits(blockScalar, text) { mark("block scalar |>") }
            if hits(flowSeq, text) { mark("flow seq [..]") }
            if hits(flowMap, text) { mark("flow map {..}") }
            if hits(complexKey, text) { mark("complex key ? k") }

            let lines = pySplitlines(text).filter { $0.unicodeScalars.contains { !isPySpace($0) } }
            let d = lines.map { $0.prefix { $0 == " " }.count }.max() ?? 0
            result.depth[d / 2, default: 0] += 1

            // parser 層
            switch events(of: data) {
            case .failure(let e): result.failed.append((name, e.reason))
            case .success(let found):
                if found.anchored {
                    result.anchored.append(name)
                } else if let t = found.tag {
                    if t.hasPrefix("tag:yaml.org,2002:") { result.taggedCore.append(name) } else { result.tagged.append(name) }
                }
            }
            if inspect, hits(anchorAlias, text) || hits(inlineComment, text) {
                for line in pySplitlines(text) where hits(anchorAlias, line) || hits(inlineComment, line) {
                    let stripped = String(String.UnicodeScalarView(pyStrip(Array(line.unicodeScalars))))
                    result.inspected.append("  \(name): \(String(stripped.prefix(110)))")
                }
            }
        }
        return result
    }

    private struct EventFindings { var anchored = false; var tag: String? }

    /// libyaml 的 event 流；**第一個帶 anchor 的事件停止**（Python 版：先看 anchor、再看 tag，找到就 break）。
    private static func events(of data: Data) -> Swift.Result<EventFindings, ScanError> {
        var parser = yaml_parser_t()
        guard yaml_parser_initialize(&parser) == 1 else { return .failure(ScanError("parser 初始化失敗")) }
        defer { yaml_parser_delete(&parser) }
        let bytes = [UInt8](data)
        var found = EventFindings()
        var failure: ScanError?
        bytes.withUnsafeBufferPointer { buf in
            yaml_parser_set_input_string(&parser, buf.baseAddress, buf.count)
            loop: while true {
                var event = yaml_event_t()
                guard yaml_parser_parse(&parser, &event) == 1 else {
                    failure = ScanError(parser.problem.map { String(cString: $0) } ?? "parse error")
                    break loop
                }
                defer { yaml_event_delete(&event) }
                var anchor: UnsafePointer<UInt8>?, tag: UnsafePointer<UInt8>?
                switch event.type {
                case YAML_STREAM_END_EVENT: break loop
                case YAML_SCALAR_EVENT: anchor = event.data.scalar.anchor.map { UnsafePointer($0) }; tag = event.data.scalar.tag.map { UnsafePointer($0) }
                case YAML_SEQUENCE_START_EVENT: anchor = event.data.sequence_start.anchor.map { UnsafePointer($0) }; tag = event.data.sequence_start.tag.map { UnsafePointer($0) }
                case YAML_MAPPING_START_EVENT: anchor = event.data.mapping_start.anchor.map { UnsafePointer($0) }; tag = event.data.mapping_start.tag.map { UnsafePointer($0) }
                default: continue
                }
                if anchor != nil { found.anchored = true; break loop }
                if let tag, found.tag == nil {
                    found.tag = String(cString: tag)
                    break loop
                }
            }
        }
        if let failure { return .failure(failure) }
        return .success(found)
    }

    private struct ScanError: Error {
        let reason: String
        init(_ r: String) { reason = r }
    }

    // MARK: - Python `str` 的小工具

    private static func isPySpace(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x09...0x0D, 0x1C...0x20, 0x85, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000: return true
        default: return false
        }
    }

    private static func pyStrip(_ s: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var a = 0, b = s.count
        while a < b, isPySpace(s[a]) { a += 1 }
        while b > a, isPySpace(s[b - 1]) { b -= 1 }
        return Array(s[a..<b])
    }

    /// Python `str.splitlines()`：`\n`、`\r`、`\r\n`、`\v`、`\f`、`\x1c`–`\x1e`、`\x85`、U+2028、U+2029。
    private static func pySplitlines(_ text: String) -> [String] {
        var out: [String] = [], cur = String.UnicodeScalarView()
        var prevCR = false
        for s in text.unicodeScalars {
            if prevCR { prevCR = false; if s == "\n" { continue } }
            switch s.value {
            case 0x0A, 0x0B, 0x0C, 0x1C, 0x1D, 0x1E, 0x85, 0x2028, 0x2029:
                out.append(String(cur)); cur = .init()
            case 0x0D:
                out.append(String(cur)); cur = .init(); prevCR = true
            default:
                cur.append(s)
            }
        }
        if !cur.isEmpty { out.append(String(cur)) }
        return out
    }

    // MARK: - 呈現

    /// 報告文字行。檔名與行內容是 store 衍生字串，一律消毒。
    public static func render(_ r: Result, inspect: Bool) -> [String] {
        func name(_ s: String) -> String { displaySafeInvisible(s, max: 120) }
        func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }
        func lpad(_ s: String, _ n: Int) -> String { s.count >= n ? s : String(repeating: " ", count: n - s.count) + s }
        func pyList(_ xs: [String]) -> String { "[" + xs.prefix(3).map { "'\(name($0))'" }.joined(separator: ", ") + "]" }

        var out = ["library root : \(displaySafeInvisible(r.root, max: 300))",
                   "total files  : \(r.files.count)", "",
                   "\(pad("FEATURE (regex 粗掃)", 22)) \(lpad("FILES", 6))   examples"]
        for f in features {
            let hit = r.buckets[f] ?? []
            let ex = hit.prefix(2).map(name).joined(separator: ", ")
            out.append("\(pad(f, 22)) \(lpad(String(hit.count), 6))   \(ex)\(hit.isEmpty ? "" : "  <-- 命中，需人工核對")")
        }
        out.append("")
        out.append("nesting depth (max indent / 2): {"
            + r.depth.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ") + "}")   // display-safe-exempt: $0.key 是縮排深度的整數，$0.value 是檔數
        out.append("")
        out.append("--- YAML parser ground truth（權威；libyaml event 流，與讀端同一個 parser）---")
        out.append("真 anchor      : \(r.anchored.count)  \(pyList(r.anchored))")
        out.append("非標準 tag     : \(r.tagged.count)  \(pyList(r.tagged))")
        // profile §4 同樣禁止顯式 core tag——與「非標準 tag」分欄是為了讓報告看得出差別，而不是像 R11 之前那樣
        // 被 startswith 濾掉後靜默歸零。
        out.append("顯式 core tag  : \(r.taggedCore.count)  \(pyList(r.taggedCore))")
        if !r.failed.isEmpty {
            out.append("parse 失敗     : \(r.failed.count)  "
                + "[" + r.failed.prefix(3).map { "('\(name($0.name))', '\(displaySafeInvisible(String($0.reason.prefix(60)), max: 80))')" }.joined(separator: ", ") + "]")   // display-safe-exempt: name($0.name) 內的 name() 就是 displaySafeInvisible；$0.reason 在同一個運算式裡逃脫
        }
        if inspect {
            out.append("")
            out.append("--- regex 命中的實際文字（人工判斷 false positive）---")
            out.append(contentsOf: r.inspected.map { displaySafeInvisible($0, max: 200) })
        }
        return out
    }
}
