import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// 用真的 `ServiceError`（AkashicMCPKit）當自帶消毒的樣本——它正是 R28 verify 第 1／7 列被 MCP 出口二次逃脫的那個型別。
enum ServiceErrorProbe { static func make(_ why: String) -> Error { ServiceError.invalid(why) } }

/// #554 R28（D80）→ R29（D81）→ R30（D82）：**store 字串在最靠近它的地方逃脫一次，之後每一層只截**。
/// R28 的守衛掃四條手寫 needle、自帶消毒的集合只看描述 body、`"\(error)"` 是結構盲區、裸引數不看——R29 verify 40 列（9 HIGH）全是這幾個
/// 盲區的位置（`StoreVersionError` 在擲出端逃卻沒 conform、`AuthorshipCompletenessValidationError` 在 init 逃、`StoreIncarnationError` 兩端各逃、
/// 11 個 `"\(error)"`、`displaySafeAssembled` 沒退讓）。R30 起這裡**全部由原始碼現算**：型別集合＝「宣告內任一處消毒 ∪ 擲出站點帶消毒」，
/// needle＝conform 集合，描述端對每個 payload 的處置（逃／截／原樣／不用）逐 case 解析，擲出站點逐引數對照——每個 payload 恰逃一次。
final class SanitizationBoundaryTests: XCTestCase {
    static let repoRoot: URL = {
        var u = URL(fileURLWithPath: #filePath)
        while u.lastPathComponent != "Tests" { u.deleteLastPathComponent() }
        return u.deletingLastPathComponent()
    }()

    static func swiftFiles(under dirs: [String]) throws -> [(path: String, text: String)] {
        var out: [(String, String)] = []
        for d in dirs {
            let e = try XCTUnwrap(FileManager.default.enumerator(at: repoRoot.appendingPathComponent(d), includingPropertiesForKeys: nil))
            for case let url as URL in e where url.pathExtension == "swift" {
                out.append((String(url.path.dropFirst(repoRoot.path.count + 1)), try String(contentsOf: url, encoding: .utf8)))
            }
        }
        return out.sorted { $0.0 < $1.0 }
    }

    /// 去掉每行的 `//` 註解（引號內的 `//` 不算——`"https://…"`；`\"` 不算引號，R30）：doc comment 裡提到 `throw ServiceError.` 不是擲出站點。
    /// 已知邊界：多行字串字面值（`"""`）內容行的 `//` 會被當註解（R29 verify 第 36 列，今天零實例）；`/* */` 不剝。
    static func strippingLineComments(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { raw -> String in
            let line = String(raw)
            var quotes = 0; var i = line.startIndex
            while i < line.endIndex {
                if line[i] == "\\" { i = line.index(after: i); if i < line.endIndex { i = line.index(after: i) }; continue }
                if line[i] == "\"" { quotes += 1 }
                if line[i] == "/", line.index(after: i) < line.endIndex, line[line.index(after: i)] == "/", quotes % 2 == 0 {
                    return String(line[..<i]) + String(repeating: " ", count: line.distance(from: i, to: line.endIndex))   // 保留行長，行號不變
                }
                i = line.index(after: i)
            }
            return line
        }.joined(separator: "\n")
    }

    /// 從 `needle` 起、括號配平為止的一段（`throw X.y(…)`／`QuarantinedFile(…)`）。needle 後面（跳過識別字）必須緊接 `(`；needle 自帶 `(` 時
    /// 那個括號就是起點（R29 NC4：第一版對這種 needle 一律跳過，三支守衛變成空掃描）。
    static func statements(in raw: String, needle: String) -> [(line: Int, body: String)] {
        let text = strippingLineComments(raw)
        var out: [(Int, String)] = []
        var search = text.startIndex
        while let r = text.range(of: needle, range: search..<text.endIndex) {
            var open = r.upperBound
            if needle.hasSuffix("(") {
                open = text.index(before: r.upperBound)
            } else {
                while open < text.endIndex, text[open].isLetter || text[open].isNumber || text[open] == "_" || text[open] == "." { open = text.index(after: open) }
            }
            guard open < text.endIndex, text[open] == "(" else { search = r.upperBound; continue }
            var depth = 0; var i = open; var inString = false
            while i < text.endIndex {
                let c = text[i]
                if inString {
                    if c == "\\" { i = text.index(after: i) } else if c == "\"" { inString = false }
                } else if c == "\"" { inString = true }
                else if c == "(" { depth += 1 } else if c == ")" { depth -= 1; if depth == 0 { break } }
                i = text.index(after: i)
            }
            let end = i < text.endIndex ? text.index(after: i) : text.endIndex
            out.append((text[..<r.lowerBound].filter { $0 == "\n" }.count + 1, String(text[r.lowerBound..<end])))
            search = end
        }
        return out
    }

    /// 一段裡的每個 `\(…)` 插值表達式（括號配平；插值裡的字串字面值不切斷配平）。**raw string 的 `\#(…)` 也是插值**（R33；R32 verify DA 第 13 列：
    /// R32 只找 `\(`，`#"…\#(x)…"#` 的插值永遠不命中、逐插值檢查對它是空掃描——零檢查、綠）。
    static func interpolations(in s: String) -> [String] {
        var out: [String] = []
        var i = s.startIndex
        while i < s.endIndex {
            let rest = s[i...]
            let start: String.Index
            if rest.hasPrefix("\\(") { start = s.index(i, offsetBy: 2) }
            else if rest.hasPrefix("\\#(") { start = s.index(i, offsetBy: 3) }
            else { i = s.index(after: i); continue }
            var depth = 1; var j = start; var inString = false
            while j < s.endIndex, depth > 0 {
                let c = s[j]
                if inString { if c == "\\" { j = s.index(after: j) } else if c == "\"" { inString = false } }
                else if c == "\"" { inString = true }
                else if c == "(" { depth += 1 } else if c == ")" { depth -= 1 }
                if depth > 0 { j = s.index(after: j) }
            }
            out.append(String(s[start..<j]))
            i = j < s.endIndex ? s.index(after: j) : s.endIndex
        }
        return out
    }

    /// 一段 `f(a, b: c, …)` 的頂層引數（逗號在深度 0 才切；字串內的逗號不算；**字串裡的 `\(…)` 插值以巢狀模式追蹤**——R29 的版本把插值裡的
    /// `joined(separator: ", ")` 那個引號當成字串結尾，三個站點被切成兩段、裸引數層整段跳過，R29 verify 第 26 列）。
    static func topLevelArguments(of body: String) -> [String] {
        guard let open = body.firstIndex(of: "("), let close = body.lastIndex(of: ")"), open < close else { return [] }
        var out: [String] = []; var cur = ""
        // 模式堆疊：.code(depth) 與 .string；插值 `\(` 在字串裡推一層 code，配平時彈回字串
        enum Mode { case code, string }
        var stack: [Mode] = [.code]; var depths: [Int] = [0]
        var i = body.index(after: open)
        while i < close {
            let c = body[i]
            switch stack.last! {
            case .string:
                cur.append(c)
                if c == "\\" {
                    let n = body.index(after: i)
                    if n < close, body[n] == "(" { cur.append("("); stack.append(.code); depths.append(1); i = n }
                    else if n < close { cur.append(body[n]); i = n }
                } else if c == "\"" { stack.removeLast() }
            case .code:
                if c == "\"" { stack.append(.string); cur.append(c) }
                else if "([{".contains(c) { depths[depths.count - 1] += 1; cur.append(c) }
                else if ")]}".contains(c) {
                    depths[depths.count - 1] -= 1; cur.append(c)
                    if depths.last == 0, stack.count > 1 { stack.removeLast(); depths.removeLast() }   // 插值閉合，回到字串
                } else if c == ",", stack.count == 1, depths[0] == 0 { out.append(cur); cur = "" }
                else { cur.append(c) }
            }
            i = body.index(after: i)
        }
        if !cur.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(cur) }
        return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// 一個引數在深度 0、字串外以 `+` 串接的各段（`"字面" + expr + "字面"`）——R31 對以 `"` 開頭的引數只掃 `\(…)` 插值，串接的 `expr` 整段不看
    /// （R31 verify 第 8 列：17 個站點，其中一個藏著列舉式 `displaySafe`）。**字串以模式堆疊追蹤**（R33；R32 verify 第 8／34 列：R32 的單一 `inString`
    /// 旗標在 `\(` 之後仍是 true，插值裡的巢狀字串把它翻成 false，`"…\(xs.joined(separator: ")"))" + rawVar` 被併成一段、`rawVar` 一個檢查都不經過
    /// ——與 `topLevelArguments` R29 付過的同一筆學費）。raw string（`#"…"#`，插值 `\#(`）也認得（DA 第 13 列）。
    static func concatenationPieces(of arg: String) -> [String] {
        var out: [String] = []; var cur = ""
        enum Mode { case code, string, raw }
        var stack: [Mode] = [.code]; var depths: [Int] = [0]
        var i = arg.startIndex
        func next(_ k: Int) -> String.Index? { arg.index(i, offsetBy: k, limitedBy: arg.index(before: arg.endIndex)) }
        while i < arg.endIndex {
            let c = arg[i]
            switch stack.last! {
            case .string:
                cur.append(c)
                if c == "\\" {
                    if let n = next(1), arg[n] == "(" { cur.append("("); stack.append(.code); depths.append(1); i = n }
                    else if let n = next(1) { cur.append(arg[n]); i = n }
                } else if c == "\"" { stack.removeLast() }
            case .raw:
                cur.append(c)
                if c == "\"", let n = next(1), arg[n] == "#" { cur.append("#"); i = n; stack.removeLast() }
                else if c == "\\", let n = next(1), arg[n] == "#", let m = next(2), arg[m] == "(" { cur.append("#("); stack.append(.code); depths.append(1); i = m }
            case .code:
                if c == "\"" { stack.append(.string); cur.append(c) }
                else if c == "#", let n = next(1), arg[n] == "\"" { stack.append(.raw); cur.append("#\""); i = n }
                else if "([{".contains(c) { depths[depths.count - 1] += 1; cur.append(c) }
                else if ")]}".contains(c) {
                    depths[depths.count - 1] -= 1; cur.append(c)
                    if depths.last == 0, stack.count > 1 { stack.removeLast(); depths.removeLast() }   // 插值閉合，回到字串
                } else if c == "+", stack.count == 1, depths[0] == 0 { out.append(cur); cur = "" }
                else { cur.append(c) }
            }
            i = arg.index(after: i)
        }
        out.append(cur)
        return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// 一段是不是**字面**（`"…"`／`#"…"#`／`[…]`）——一份謂詞（R33；R32 verify DA 第 13 列：R32 在同一個 hunk 寫了兩份不一致的判準，
    /// `:572` 不認 `#"`、`:595` 認，raw string 引數於是走整段豁免）。
    static func isLiteralPiece(_ s: String) -> Bool { s.hasPrefix("\"") || s.hasPrefix("#\"") || s.hasPrefix("[") }

    /// 把字串字面值的**文字**遮成空白、保留 `\(…)` 插值裡的程式碼——用來數一個 binding 在描述裡「以程式碼」出現幾次（R32；中文描述裡的
    /// 「找不到 id 為」讓 `id` 的 `.typed` 判定誤以為它另有原樣用法）。
    static func codeOnly(_ s: String) -> String {
        var out = ""; var inString = false; var depth = 0; var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if inString {
                if c == "\\" {
                    let n = s.index(after: i)
                    if n < s.endIndex, s[n] == "(" { out += "\\("; depth = 1; i = n; inString = false
                        // 插值內的程式碼原樣複製到配平
                        var j = s.index(after: i)
                        while j < s.endIndex, depth > 0 { let d = s[j]; if d == "(" { depth += 1 } else if d == ")" { depth -= 1 }; out.append(d); j = s.index(after: j) }
                        i = j; inString = true; continue
                    }
                    out += "  "; if n < s.endIndex { i = n }
                } else if c == "\"" { inString = false; out.append(c) } else { out.append(" ") }
            } else { if c == "\"" { inString = true }; out.append(c) }
            i = s.index(after: i)
        }
        return out
    }

    static let sanitizers = ["displaySafeInvisible(", "displaySafeError(", "displaySafeErrorText(", "displaySafeErrorMultiline("]
    static func isSanitized(_ e: String) -> Bool { sanitizers.contains { e.hasPrefix($0) } }
    static func isProgramBuilt(_ e: String) -> Bool { programBuilt.contains(where: { e.range(of: $0.pattern, options: .regularExpression) != nil }) }
    static func isPlainValue(_ v: String) -> Bool {
        v.range(of: #"^([0-9_]+|true|false|nil|\.[A-Za-z]\w*(\(.*\))?)$"#, options: .regularExpression) != nil
    }

    private static let programBuilt: [(pattern: String, why: String)] = [
        ("^context$", "呼叫端字面量或由已消毒片段組成的路徑"),
        ("^field$", "呼叫端字面欄位名"),
        ("^label$", "本檔字面常量"),
        ("^what$", "呼叫端字面量（assertNoErrors 的 person／venue…）"),
        ("^safeField$", "已 displaySafeInvisible 的欄位名（Provenance）"),
        ("^expect$", "呼叫端字面形狀名（mapping／sequence）"),
        ("^face$", "本函式的兩個字面常量"),
        ("^detail$", "由欄位名常量 joined 而成"),
        ("^i$", "索引 Int"),
        ("^errno$", "Int"),
        ("^format$", "store format Int"),
        ("^consequence$", "本函式的兩句字面常量"),
        ("^canaryMismatchDetail\\(ca, cb\\)$", "由欄位名常量 joined 而成"),
        ("^T\\.self$", "型別名"),
        ("^T\\.shapeDescription$", "型別的字面描述"),
        ("^(WorkType|VenueType)\\.domainDescription$", "封閉值域現算的字面描述"),
        ("^ProvenanceReference\\.workFieldPrefix$", "常量"),
        ("^[A-Za-z_.]*id\\.uuidString$", "UUID 文法固定（d.id／witness 等）"),
        ("^[A-Za-z_.!]+\\.count$", "Int"),
        ("^[A-Za-z_.!]+\\.rawValue$", "封閉列舉的 rawValue"),
        ("^scan\\.malformedLines\\.map\\(String\\.init\\)\\.joined\\(separator: \", \"\\)$", "行號 Int 清單"),
        // R29：ServiceError／ValidationError 的擲出站點納入掃描後多出的程式構造值
        ("^(idx|written|a\\.index|b\\.index|parts\\.count|report\\.\\w+\\.count)$", "Int"),
        ("^StoreKey\\.pattern$", "常量正則"),
        ("^field\\.uppercased\\(\\)$", "三個呼叫端字面欄位名之一（doi／pmid／isbn）"),
        ("^\\$0\\.value$", "writeFailed 的 value 由 displaySafeError 產出（唯一命中：index rebuild 失敗那一句）"),
        ("^(writeFailedList|confirmFailedList)$", "#562：listCapped 過的清單——writeFailed 的 key 逐項 displaySafeInvisible、value 由 displaySafeError 產出；confirmWriteFailed 的鍵在插入時已 displaySafeInvisible"),
        ("^(WorkType|VenueType|EntityKind)\\.allCases[^\\n]*$", "封閉列舉現算"),
        ("^known\\.isEmpty \\? \"[^\"]*\" : displaySafeInvisible\\(known, max: \\d+\\)$", "三元：字面或已消毒"),
        ("^[A-Za-z_][\\w.!= \\n]*\\?\\s*\"(?:[^\"\\\\]|\\\\.)*\"\\s*:\\s*\"(?:[^\"\\\\]|\\\\.)*\"$", "三元：兩支都是字面（字面裡的插值由上一層檢查）"),
        ("^errors\\.map\\(\\\\\\.message\\)\\.joined\\(separator: \"；\"\\)$", "validate() 的訊息由八個生產者檔消毒——那條守衛（InvisibleEscapeCoverageTests）只禁止用錯的逃脫器、不要求每個插值都逃（R29 verify 第 34 列）；插值層今天零實例，這一列放行的是全庫最寬的一條通道，缺口記在 changelog R30"),
        ("^(rows|AmbiguityDisplayLimit\\.bytes / 1024|startLine\\.map\\(String\\.init\\) \\?\\? \"\\?\")$", "Int"),
        ("^breakdown$", "封閉 enum ResolutionTier 的 rawValue 與計數"),
        ("^(command|f\\.0)$", "本檔字面命令名／旗標名"),
        ("^(invocation|previewHint)$", "DestructiveTargetGate 的組字：命令名＋字面旗標、或兩支字面的預覽提示（#580 R2）"),
        ("^flag$", "DestructiveTargetGate 的旗標名：預設 --apply，唯一的另一個呼叫端傳字面三元 apply ? \"--apply\" : \"--reject\"（#580）"),
        ("^Self\\.shapeName\\(\\w+\\)$", "JSON 值的型別名（封閉的幾個字面）"),
        ("^\\[\\]$", "空陣列字面"),
        ("^safeNames$", "export 缺欄位名的 join，已逐項 displaySafeInvisible"),
        ("^((out\\.utf8\\.count|Self\\.maxExportBytes) / 1024|grouped\\.count - rejectWriteFailed\\.count|entry\\.authors\\.count - 1|others\\.count \\+ 1|i \\+ 1|storeFormat)$", "Int 算術"),
        ("^need$", "封閉 tier enum 的 rawValue join"),
        ("^parameter$", "呼叫端字面參數名（names／add_names）"),
        ("^spelled$", "由 displaySafeInvisible 組成（confirmedLiteral 的拼法揭露）"),
        ("^operation$", "呼叫端字面（apply／repoint）"),
        ("^ORCID\\.shapeDescription$", "常量"),
        ("^type\\(of: v\\)$", "型別名"),
        ("^IndexList\\.render\\(.*\\)$", "Int 序列的字面渲染"),
        ("^Self\\.listCapped\\(\\w+\\) \\{ displaySafeInvisible\\(\\$0, max: [0-9_]+\\) \\}$", "逐項消毒（R32 起串接運算元也掃，both／bad 兩個呼叫端同一列）"),
        // R32：串接運算元（`"字面" + expr`）納入掃描後多出的程式構造值（R31 verify 第 8 列）
        ("^[\\w.]+(\\.prefix\\([^)]*\\))?\\.map \\{ displaySafeInvisible\\(\\$0[\\w.]*, max: [0-9_]+\\) \\}[\\s\\S]*$", "逐項 displaySafeInvisible 的 map；之後的 sorted／joined 不改內容"),
        ("^\\(report\\.writeFailures\\.first\\?\\.error \\?\\? \"[^\"]*\"\\)$", "writeFailures[].error 由 displaySafeError 產出（AkashicService 的 index rebuild 路徑）"),
        ("^conflict\\.describe\\(candidate: [\\w.]+, operation: \"[^\"]*\"\\)$", "ConfirmedLiteralConflict.describe 內部逐項 displaySafeInvisible（cand／list）"),
        ("^described$", "updateVenue 的同書寫系統衝突清單：WritingSystem.rawValue 常數＋listCapped { displaySafeInvisible }（R32 起性質式）"),
        ("^[\\w.]+\\.allCases\\.map\\(\\\\\\.rawValue\\)\\.joined\\(separator: \"[^\"]*\"\\)$", "封閉列舉的 rawValue 清單"),
        ("^\\(timelineKeys\\.map\\(\\\\\\.0\\) \\+ \\[[^\\]]*\\]\\)[\\s\\S]*$", "YAML.timelineKeys 的常量鍵名（之後的 sorted／joined 不改內容）"),
        ("^\\([\\w.]+( [<>=!]+ [0-9_]+)? \\? \"(?:[^\"\\\\]|\\\\.)*\"(?:\\s*\\+\\s*\"(?:[^\"\\\\]|\\\\.)*\")*\\s*:\\s*\"(?:[^\"\\\\]|\\\\.)*\"(?:\\s*\\+\\s*\"(?:[^\"\\\\]|\\\\.)*\")*\\)$", "括號三元：兩支都是字面（可再以 + 串接字面）、且沒有插值（有插值的走逐插值檢查）"),
        ("^validationErrors\\.prefix\\([0-9_]+\\)\\.map \\{ \"- \" \\+ displaySafeClipOnly\\(\\$0\\.message, max: [0-9_]+\\) \\}[\\s\\S]*$", "ValidationIssue.message 由 validate() 生產端消毒、這裡只截（updatePerson）"),
        ("^(knownKeys|updatable)\\.sorted\\(\\)\\.joined\\(separator: \"[^\"]*\"\\)$", "Provenance.knownKeys／PersonYAML.updatableKeys 的常量鍵名"),
        ("^labels\\.sorted\\(\\)$", "knownLabels 的子集（EntityKind 的常量標籤）"),
        // R30
        // R31 拿掉 R30 的 `displaySafe(resolved.path, max: 800)` 列（R30 verify 第 24 列）：那是全 diff 唯一從性質式退回列舉式的站點，而它要的
        // 「貼回去就是那個目錄」列舉式也給不了（反斜線、C0、bidi 照逃）；D75 說生產者一律性質式、守衛無允許清單——這一列正是一個允許清單
        ("^(found|supported|index|count|group\\.count|line|position|column|offset|expected|actual)$", "Int 綁定——描述端以 \\(x) 插值的整數 payload（tooNew、索引、行號）；R32 拿掉 `n`：它也是 DivergenceResolve 迴圈裡 store 名字的變數名，R31 verify 第 1 列的 mutation 曾靠這一列綠（NC2）"),
        ("^shown\\.prefix\\(40\\)\\.map \\{ displaySafeInvisible\\(\\$0, max: 120\\) \\}\\.joined\\(separator: \", \"\\)$", "逐項消毒的 citekey 清單（export-bib，R29 verify 第 30 列）"),
        ("^shown\\.count - 40$", "Int"),
        ("^(maximum|maximumBytes|maximumCount|current|StoreVersion\\.supported)( \\+ 1)?$", "Int（resourceLimit／alreadyAtFormat／tooNew 的上限與版號）"),
        ("^action$", "呼叫端字面（rename／merge 的動作名，與 what 同型）"),
        ("^(errs|cross)\\.map\\(\\\\\\.message\\)$", "validate()／crossRecordIssues 的訊息由生產者消毒（同 errors.map 那一列，同一個缺口）"),
        ("^losses$", "fieldsLostByMerging 三份回傳前逐條 displaySafeInvisible（R28 D80）"),
        ("^capped$", "describeVerdictSource 逐筆性質式逃脫、渲染前截（R27 D78）"),
        ("^first\\.(brought|existing)\\.prefix\\(5\\)\\.map\\(describeVerdictSource\\)$", "describeVerdictSource 逐筆性質式逃脫"),
        ("^affectedMigration\\.collisions$", "collisions 由 describe(m)（性質式）與 uuidString 組成"),
        ("^lines$", "verdictsAlreadyAtTarget 的 lines：hits 的每一行在 assertNoVerdictAlreadyAt 逐項 displaySafeInvisible，計數行是 Int"),
        // R31：payloadModes 認得成員鏈與 helper 之後多出的程式構造值
        // R32 拿掉 R31 的 `^id$` 列（R31 verify 第 10 列）：型別由描述端的 `.uuidString` 成員鏈釘（payloadModes 的 `.typed`），不靠名字
        ("^scalar\\.value$", "UInt32（PropositionError.unsupportedUnicodeScalar：描述端 String(value, radix: 16)）"),
    ]

    // MARK: - 型別集合、payload 模型（R30 D82：全部由原始碼現算）

    struct ErrorTypeDecl { let qualified: String; let simple: String; let path: String; let header: String; let body: String; let conforms: Bool; let isEnum: Bool }

    /// 全樹的 Error 型別（enum／struct／class）：宣告可跨行、巢狀型別以 `外.內` 具名；body 已剝行註解。
    static func errorTypeDecls() throws -> [ErrorTypeDecl] {
        let declRe = try NSRegularExpression(pattern: #"^(\s*)(?:public |internal |fileprivate |private )?(?:indirect )?(enum|struct|class) (\w+)\b"#)
        var out: [ErrorTypeDecl] = []
        for (path, raw) in try swiftFiles(under: ["Sources"]) {
            let text = strippingLineComments(raw)
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            var offsets: [Int] = [0]; for l in lines { offsets.append(offsets.last! + l.count + 1) }
            func indent(_ s: String) -> Int { s.prefix { $0 == " " }.count }
            var decls: [(line: Int, indent: Int, kind: String, name: String)] = []
            for (n, l) in lines.enumerated() {
                if let r = declRe.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)) {
                    decls.append((n, indent(l), String(l[Range(r.range(at: 2), in: l)!]), String(l[Range(r.range(at: 3), in: l)!])))
                }
            }
            for d in decls {
                var h = ""; var m = d.line
                while m < lines.count { h += lines[m] + "\n"; if lines[m].contains("{") { break }; m += 1 }
                let header = String(h[..<(h.firstIndex(of: "{") ?? h.endIndex)])
                let isError = d.name.hasSuffix("Error") || header.range(of: #"\bError\b|\bLocalizedError\b"#, options: .regularExpression) != nil
                guard isError else { continue }
                // body：從第一個 `{` 起括號配平
                let start = text.index(text.startIndex, offsetBy: offsets[d.line]) 
                guard let open = text[start...].firstIndex(of: "{") else { continue }
                var depth = 0; var i = open; var inString = false
                while i < text.endIndex {
                    let c = text[i]
                    if inString { if c == "\\" { i = text.index(after: i) } else if c == "\"" { inString = false } }
                    else if c == "\"" { inString = true }
                    else if c == "{" { depth += 1 } else if c == "}" { depth -= 1; if depth == 0 { break } }
                    i = text.index(after: i)
                }
                let body = String(text[open...i])
                var qualified = d.name
                if d.indent > 0, let parent = decls.last(where: { $0.line < d.line && $0.indent == d.indent - 4 }) { qualified = parent.name + "." + d.name }
                out.append(ErrorTypeDecl(qualified: qualified, simple: d.name, path: path, header: header, body: body,
                                         conforms: header.contains("SanitizedErrorDescription"), isEnum: d.kind == "enum"))
            }
        }
        return out
    }

    enum PayloadMode { case escaped, clipped, raw, unused, unclassified, typed }

    /// 描述端經 helper 用到 payload 時，helper 對那個 payload 做了什麼——**封閉表**，每一列的 helper body 由 `helperSanitizes` 機械驗證含消毒
    /// （不是信任表）。R30 的 `payloadModes` 只認 `displaySafeInvisible(x`／`\(x)`，`\(Self.whoWouldHold(record, …))` 落進 `.unused`、擲出站點永不比對
    /// （R30 verify 第 5／11／14 列）。
    static let descriptionHelpers: [(owner: String, name: String, mode: PayloadMode, why: String)] = [
        ("DivergenceResolveError", "whoWouldHold", .escaped, "兩個引數各 displaySafeInvisible（record／survivor）"),
        ("CorpusDiagnostic", "formatted", .escaped, "TractatusValidationFailure 的 errorDescription 走 `diagnostics.map(\\.formatted)`；formatted 經 singleLine 逐欄位 displaySafeInvisible"),
        ("RenameReportSummary", "lines", .escaped, "AppStateError.renamedButReloadFailed：report 的每一列在 lines 裡逐項逃脫（verdict 列性質式、key 列列舉式——D40）"),
    ]

    /// `owner` 型別宣告 body 裡 `func <name>(`／`var <name>: String {` 的 body 有沒有消毒——直接含、或呼叫同一個 owner body 裡含消毒的 func
    /// （展開一層：`CorpusDiagnostic.formatted` 經 `singleLine` 才消毒）。owner 找不到、成員找不到，都算沒有。
    static func helperSanitizes(owner: String, name: String, files: [(path: String, text: String)]) -> Bool {
        func balanced(from open: String.Index, in text: String) -> String {
            var depth = 0; var i = open
            while i < text.endIndex { let c = text[i]; if c == "{" { depth += 1 } else if c == "}" { depth -= 1; if depth == 0 { break } }; i = text.index(after: i) }
            return String(text[open...(i < text.endIndex ? i : text.index(before: text.endIndex))])
        }
        func member(_ marker: String, in body: String) -> String? {
            guard let r = body.range(of: marker, options: .regularExpression), let open = body[r.upperBound...].firstIndex(of: "{") else { return nil }
            return balanced(from: open, in: body)
        }
        let sanitizerNames = ["displaySafeInvisible(", "escapingInvisibleScalars(", "displaySafe("]
        for (_, raw) in files {
            let text = strippingLineComments(raw)
            guard let r = text.range(of: #"(?:enum|struct|class|extension) "# + NSRegularExpression.escapedPattern(for: owner) + #"\b"#, options: .regularExpression),
                  let open = text[r.upperBound...].firstIndex(of: "{") else { continue }
            let body = balanced(from: open, in: text)
            guard let m = member(#"func "# + NSRegularExpression.escapedPattern(for: name) + #"\("#, in: body) ?? member(#"var "# + NSRegularExpression.escapedPattern(for: name) + #": String \{"#, in: body) else { continue }
            if sanitizerNames.contains(where: m.contains) { return true }
            let callRe = try! NSRegularExpression(pattern: #"(?<![\w.])(\w+)\("#)
            for c in callRe.matches(in: m, range: NSRange(m.startIndex..., in: m)) {
                let callee = String(m[Range(c.range(at: 1), in: m)!])
                if callee != name, let cb = member(#"func "# + NSRegularExpression.escapedPattern(for: callee) + #"\("#, in: body), sanitizerNames.contains(where: cb.contains) { return true }
            }
            return false
        }
        return false
    }

    /// 描述端對每個 case 的每個 payload 做了什麼：`displaySafeInvisible(x`／`x.map { displaySafeInvisible` → escaped；`displaySafeClipOnly(x` → clipped
    /// （擲出端已逃）；`\(x)`／`x.joined` 原樣 → raw（擲出端必須逃）；沒用到 → unused。
    static func payloadModes(of t: ErrorTypeDecl) -> [String: [PayloadMode]] {
        var out: [String: [PayloadMode]] = [:]
        for marker in ["var errorDescription: String? {", "var description: String {"] {
            guard let r = t.body.range(of: marker) else { continue }
            var depth = 0; var i = t.body.index(before: r.upperBound); var block = ""
            while i < t.body.endIndex { let c = t.body[i]; block.append(c); if c == "{" { depth += 1 } else if c == "}" { depth -= 1; if depth == 0 { break } }; i = t.body.index(after: i) }
            let caseRe = try! NSRegularExpression(pattern: #"case (?:let )?\.(\w+)(?:\(([^)]*)\))?"#)
            let matches = caseRe.matches(in: block, range: NSRange(block.startIndex..., in: block))
            for (k, m) in matches.enumerated() {
                let name = String(block[Range(m.range(at: 1), in: block)!])
                let chunkEnd = k + 1 < matches.count ? Range(matches[k + 1].range, in: block)!.lowerBound : block.endIndex
                let chunk = String(block[Range(m.range, in: block)!.upperBound..<chunkEnd])
                var bindings: [String?] = []
                if m.range(at: 2).location != NSNotFound {
                    for piece in String(block[Range(m.range(at: 2), in: block)!]).split(separator: ",") {
                        let w = piece.split(whereSeparator: { $0 == " " || $0 == ":" }).last.map(String.init) ?? "_"
                        bindings.append(w == "_" ? nil : w)
                    }
                }
                out[name] = bindings.map { b in
                    guard let b else { return .unused }
                    let esc = #"displaySafeInvisible\(\s*"# + b + #"\b|\b"# + b + #"\.(prefix\([^)]*\)\.)?map \{ (\"[^"]*)?displaySafeInvisible\("#
                    let clip = #"displaySafeClipOnly\(\s*"# + b + #"\b|\b"# + b + #"\.(prefix\([^)]*\)\.)?map \{ (\"[^"]*)?displaySafeClipOnly\("#
                    // 原樣抵達 sink 的三種寫法（R31；R30 verify 第 5／7／11 列）：`\(x)`／`\(x.任意成員鏈)`（`.joined(`／`.uuidString`／`.count`…——R30 是
                    // 四個尾綴的白名單，新尾綴靜默落進 unused）、`x.map { "`／`x.joined(`、以及**裸回傳** `return x`（`ServiceError.invalid` 的 149 個站點）。
                    let rawUse = #"\\\("# + b + #"(\.\w+(\([^()]*\))?)*\)|\b"# + b + #"\.(prefix\([^)]*\)\.)?map \{ \"|\b"# + b + #"\.joined\(|\breturn\s+"# + b + #"(?![\w.(])"#
                    // helper 路徑：`helper(x`／`Self.helper(x`／`Owner.helper(x`（插值內或字串串接裡都算）——查封閉表，helper body 另由 helperSanitizes 驗；
                    // **不在表裡的 helper 判 raw**（fail-closed：擲出端必須自己逃或具名 programBuilt——`String(value, radix:)` 這種對整數的格式化就落在這裡）
                    let viaHelper = #"(?<![\w.])((?:\w+\.)*\w+)\(\s*"# + b + #"\b"#
                    // 描述端只以 `.uuidString` 用它 → 型別由成員鏈釘住是 UUID，擲出端傳什麼都是 hex+dash（R32；R31 verify 第 10 列：R30/R31 的
                    // `programBuilt ^id$` 是型別盲的——同一個 codebase 裡 `id` 也是呼叫端可控的 String）
                    let uuidOnly = try! NSRegularExpression(pattern: #"\\\("# + b + #"\.uuidString\)"#)
                    let anyUse = try! NSRegularExpression(pattern: #"(?<![\w.$])"# + b + #"(?![\w])"#)
                    let code = codeOnly(chunk)
                    let uses = anyUse.numberOfMatches(in: code, range: NSRange(code.startIndex..., in: code))
                    if uses > 0, uuidOnly.numberOfMatches(in: code, range: NSRange(code.startIndex..., in: code)) == uses { return .typed }
                    // 同一個 chunk 既逃又原樣插值同一個 payload（`.count` 這種 Int 成員鏈不算）→ 分不出類，不得取先命中的那個（R31 verify 第 23 列）
                    let rawChain = try! NSRegularExpression(pattern: #"\\\("# + b + #"((?:\.\w+(?:\([^()]*\))?)*)\)"#)
                    let nonIntRaw = rawChain.matches(in: chunk, range: NSRange(chunk.startIndex..., in: chunk))
                        .filter { String(chunk[Range($0.range(at: 1), in: chunk)!]) != ".count" }
                    if chunk.range(of: esc, options: .regularExpression) != nil { return nonIntRaw.isEmpty ? .escaped : .unclassified }
                    if chunk.range(of: clip, options: .regularExpression) != nil { return .clipped }
                    if let r = chunk.range(of: viaHelper, options: .regularExpression) {
                        let call = String(chunk[r]).split(separator: "(").first.map(String.init) ?? ""
                        let last = call.split(separator: ".").last.map(String.init) ?? call
                        // 查表要連 owner 一起比（R31 verify 第 9 列：R31 只比最後一段，任何型別上的同名 helper 都拿到那一列的 mode，碰撞時 fail-open）
                        // `Self.name(`／裸 `name(` 指的是**被掃描的型別自己**，owner 必須就是它（R32 NC4：R32 第一版對 `Self.` 不比 owner，表列 owner 改錯仍綠）
                        if let h = descriptionHelpers.first(where: { $0.name == last && ((call == last || call == "Self.\(last)") ? $0.owner == t.simple : call == "\($0.owner).\(last)") }) { return h.mode }
                        return .raw
                    }
                    if chunk.range(of: rawUse, options: .regularExpression) != nil { return .raw }
                    // binding 出現在描述裡卻不是上面任何一種形狀：不得靜默當成沒用到（R30 把這一格當 unused 跳過）
                    if uses > 0 { return .unclassified }
                    return .unused
                }
            }
        }
        return out
    }

    /// 擲出站點（`throw <型別>.<case>(…)`）：巢狀型別只在宣告檔內以簡名找、另外全樹以全名找。
    static func throwStatements(of t: ErrorTypeDecl, files: [(path: String, text: String)]) -> [(path: String, line: Int, body: String, caseName: String)] {
        var out: [(String, Int, String, String)] = []
        let nested = t.qualified.contains(".")
        for (path, text) in files {
            var needles = ["throw \(t.qualified)."]
            if !nested || path == t.path { needles.append("throw \(t.simple).") }
            for needle in Set(needles) {
                for (line, body) in statements(in: text, needle: needle) {
                    let caseName = String(body.dropFirst(needle.count).prefix { $0.isLetter || $0.isNumber || $0 == "_" })
                    out.append((path, line, body, caseName))
                }
            }
        }
        return out
    }

    /// 擲出站點的引數帶消毒的型別。每檔剝一次註解、從命中的 `(` 就地配平——R30 第一版對每個命中重跑 `statements(in:)`（整檔再剝一次），
    /// O(n²)、47 秒（R30 verify 前自量）。
    static func typesThrownWithSanitizer(files: [(path: String, text: String)], decls: [ErrorTypeDecl] = []) -> Set<String> {
        var out: Set<String> = []
        let re = try! NSRegularExpression(pattern: #"throw ([A-Z]\w+(?:\.[A-Z]\w+)?)\.\w+\s*\("#)
        // 巢狀型別在宣告檔內以簡名擲出（`throw MigrationError.`）：四個同名的 `MigrationError` 住在四個檔，簡名要就地解成全名——
        // R30 以簡名入集合，一個消毒就替四個背書（R30 verify 第 28／38 列）
        var nestedByFile: [String: [String: String]] = [:]
        for d in decls where d.qualified.contains(".") { nestedByFile[d.path, default: [:]][d.simple] = d.qualified }
        for (path, raw) in files {
            let text = strippingLineComments(raw)
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                var name = String(text[Range(m.range(at: 1), in: text)!])
                if !name.contains("."), let q = nestedByFile[path]?[name] { name = q }
                let open = text.index(before: Range(m.range, in: text)!.upperBound)
                var depth = 0; var i = open; var inString = false
                while i < text.endIndex {
                    let c = text[i]
                    if inString { if c == "\\" { i = text.index(after: i) } else if c == "\"" { inString = false } }
                    else if c == "\"" { inString = true }
                    else if c == "(" { depth += 1 } else if c == ")" { depth -= 1; if depth == 0 { break } }
                    i = text.index(after: i)
                }
                if text[open..<i].contains("displaySafe") { out.insert(name) }
            }
        }
        return out
    }

    /// conform 的型別必須有自己的 Error → 文字描述：`errorDescription`／`description`（計算或儲存）。
    static func hasDescriptionMember(_ t: ErrorTypeDecl) -> Bool {
        t.body.contains("var errorDescription: String? {") || t.body.contains("var description: String {") || t.body.contains("let description: String")
    }

    /// 描述成員（`errorDescription`／`description`／每個 `init`）的 body，加上它們呼叫的型別內 `func`／`static func` 的 body（展開一層）、
    /// 以及封閉表 `descriptionHelpers` 裡被呼叫的跨型別 accessor——其中任一處含消毒即為真。
    static func descriptionMembersSanitize(_ t: ErrorTypeDecl, files: [(path: String, text: String)]) -> Bool {
        func blocks(after marker: String) -> [String] {
            var out: [String] = []; var search = t.body.startIndex
            while let r = t.body.range(of: marker, options: .regularExpression, range: search..<t.body.endIndex) {
                guard let open = t.body[r.lowerBound...].firstIndex(of: "{") else { break }   // 從 marker 起點找：描述的 marker 自己就含 `{`，init 的在參數表之後
                var depth = 0; var i = open
                while i < t.body.endIndex { let c = t.body[i]; if c == "{" { depth += 1 } else if c == "}" { depth -= 1; if depth == 0 { break } }; i = t.body.index(after: i) }
                out.append(String(t.body[open...i])); search = i < t.body.endIndex ? t.body.index(after: i) : t.body.endIndex
            }
            return out
        }
        let text = (blocks(after: #"var errorDescription: String\? \{"#) + blocks(after: #"var description: String \{"#) + blocks(after: #"\binit\??\("#)).joined(separator: "\n")
        let sanitizerNames = ["displaySafeInvisible(", "escapingInvisibleScalars(", "displaySafeErrorText(", "displaySafeError(", "displaySafe("]
        if sanitizerNames.contains(where: text.contains) { return true }
        let callRe = try! NSRegularExpression(pattern: #"(?<![\w.])(?:Self\.)?(\w+)\("#)
        var names: Set<String> = []
        for m in callRe.matches(in: text, range: NSRange(text.startIndex..., in: text)) { names.insert(String(text[Range(m.range(at: 1), in: text)!])) }
        for n in names where t.body.contains("func \(n)(") && helperSanitizes(owner: t.simple, name: n, files: files) { return true }
        for h in descriptionHelpers where text.contains("\\.\(h.name)") || text.contains("\(h.owner).\(h.name)(") || text.contains("Self.\(h.name)(") {
            if helperSanitizes(owner: h.owner, name: h.name, files: files) { return true }
        }
        return false
    }

    // MARK: - 守衛

    /// 自帶消毒的型別集合由原始碼現算，兩個方向都要對上：**宣告內任一處**消毒 payload 的（描述、init、helper）或**擲出站點**帶消毒的，
    /// 必須 conform；conform 的必須是其中之一。R29 只看描述 body，`AuthorshipCompletenessValidationError`（init）與 `StoreVersionError`
    /// （擲出端）都在集合外、被 sink 再逃一次（R29 verify 第 3／4／6／14 列）；`escapeAtThrow` 手寫表自此不存在。
    func testSelfSanitizingErrorTypesAreAClosedList() throws {
        let files = try Self.swiftFiles(under: ["Sources"])
        let decls = try Self.errorTypeDecls()
        let thrown = Self.typesThrownWithSanitizer(files: files, decls: decls)
        var found: Set<String> = [], conforming: Set<String> = [], enumerated: [String] = [], withoutDescription: [String] = []
        for t in decls {
            // 「型別在某條路徑上消毒」不等於「型別在 Error → 文字那條路徑上消毒」（R31；R30 verify 第 8／18／34 列：`CorpusDiagnostic` 的 body 含
            // `displaySafe`——住在 `formatted`，而 Error → 文字走 `String(describing:)`——R30 把它逼成 conform，反射 dump 從此免逃）。判準改成：
            // **描述成員**（`errorDescription`／`description`／`init`，加上它們呼叫的型別內 helper 與封閉表裡的跨型別 accessor）含消毒。
            let bodySanitizes = Self.descriptionMembersSanitize(t, files: files)
            let throwSanitizes = thrown.contains(t.qualified)
            if bodySanitizes || throwSanitizes { found.insert(t.qualified) }
            if t.conforms { conforming.insert(t.qualified) }
            if t.conforms, !Self.hasDescriptionMember(t) { withoutDescription.append("\(t.path) \(t.qualified)") }
            if t.conforms, t.body.range(of: #"(?<!escapingInvisibleScalars\()(?<![A-Za-z])displaySafe\("#, options: .regularExpression) != nil {   // `escapingInvisibleScalars(displaySafe(` 是性質式的組合，不是列舉式
                enumerated.append("\(t.path) \(t.qualified) 仍有列舉式 displaySafe(")
            }
        }
        XCTAssertEqual(found.subtracting(conforming), [], "消毒了 payload 卻沒有宣告 SanitizedErrorDescription：\(found.subtracting(conforming).sorted())")
        XCTAssertEqual(conforming.subtracting(found), [], "宣告了 SanitizedErrorDescription 卻沒有任何一處消毒：\(conforming.subtracting(found).sorted())")
        XCTAssertEqual(enumerated, [], enumerated.joined(separator: "\n"))
        XCTAssertEqual(withoutDescription, [], "宣告了 SanitizedErrorDescription 卻沒有自己的 Error → 文字描述（會走 String(describing:) 反射）：" + withoutDescription.joined(separator: "\n"))
        // struct 的 conformer 不經擲出站點的逐 payload 比對（它們沒有 case），而 `descriptionMembersSanitize` 是存在量詞（描述成員裡**有一處**消毒即為真）
        // ——所以 struct 的 conform 是**封閉清單**，每列要寫出「為什麼整個描述都消毒了」（R31 verify 第 11 列：`TractatusValidationFailure` 的
        // `incompleteness` 曾原樣拼接，守衛因 `formatted` 那一半就綠）
        let structConformers: [String: String] = [
            "ErrorDisplay.EscapedOnce": "唯一的 payload 在 init 經 displaySafeErrorText 逃一次",
            "AuthorshipCompletenessValidationError": "唯一的 store payload（detail）在 init 經 boundedDisplaySafe 逃一次；其餘是 Int 索引",
            "TractatusValidationFailure": "errorDescription 的兩個來源各自逐項 displaySafeInvisible（incompleteness 直接、diagnostics 經 formatted→singleLine）",
            "PropositionModelValidationError": "描述由 safeDescription／boundedKey 組成——每個 store 字串性質式逃一次、退讓截（R30 對 AkashicProposition 兩個型別的獨立稽核）",
        ]
        let actualStructs = Set(decls.filter { $0.conforms && !$0.isEnum }.map(\.qualified))
        XCTAssertEqual(actualStructs, Set(structConformers.keys), "struct 的 SanitizedErrorDescription conformer 是封閉清單——新的要在這裡寫理由：\(actualStructs.sorted())")
        XCTAssertGreaterThanOrEqual(conforming.count, 21, "全樹的自帶消毒型別：\(conforming.sorted())")
        for h in Self.descriptionHelpers {
            XCTAssertTrue(Self.helperSanitizes(owner: h.owner, name: h.name, files: files), "descriptionHelpers 表裡的 `\(h.owner).\(h.name)` 找不到含消毒的宣告——表不是信任的，是被驗的")
        }
        let helper = try String(contentsOf: Self.repoRoot.appendingPathComponent("Sources/AkashicCore/ErrorDisplay.swift"), encoding: .utf8)
        XCTAssertTrue(helper.contains("error is SanitizedErrorDescription"), "isSelfSanitizing 要以 protocol 判，不是 is 鏈")
        XCTAssertFalse(FileManager.default.fileExists(atPath: Self.repoRoot.appendingPathComponent("Sources/AkashicStoreIO/ErrorDisplay.swift").path))
    }

    /// 每個 payload 恰逃一次——描述端逃的，擲出端傳原值；描述端只截或原樣的，擲出端逃（或是字面／程式構造值）。對**每一個** conform 的 enum
    /// 的**每一個**擲出站點逐引數對照（R30；R29 只掃四條手寫 needle、case 粒度，R29 verify 第 17／22 列）。
    func testEveryThrowSiteEscapesEachPayloadExactlyOnce() throws {
        let files = try Self.swiftFiles(under: ["Sources"])
        var offenders: [String] = []; var scanned = 0; var checkedArgs = 0; var unusedSites: [String: Int] = [:]
        for t in try Self.errorTypeDecls() where t.conforms && t.isEnum {
            let modes = Self.payloadModes(of: t)
            for site in Self.throwStatements(of: t, files: files) {
                scanned += 1
                let args = Self.topLevelArguments(of: site.body)
                guard let m = modes[site.caseName] else {
                    if !args.isEmpty { offenders.append("\(site.path):\(site.line) \(t.qualified).\(site.caseName) 描述端沒有這個 case 的 payload 模型") }
                    continue
                }
                guard m.count == args.count else { offenders.append("\(site.path):\(site.line) \(t.qualified).\(site.caseName) 引數 \(args.count) 個、描述綁定 \(m.count) 個，對不上"); continue }
                let rawLines = files.first { $0.path == site.path }!.text.split(separator: "\n", omittingEmptySubsequences: false)
                let span = site.body.filter { $0 == "\n" }.count
                // 只看 `display-safe-exempt:` **之後**的註記文字（R31；R30 verify 第 4／19／25 列：R30 拿整個語句的原始行比對，而引數的識別字必然
                // 出現在那幾行——它就是引數本身——於是一句不相干的註記讓該語句全部引數免檢，74/540 站點、87/834 引數處在毯式豁免下，
                // mutation 拿掉兩個 sanitizer 兩套守衛都綠）
                let notes = rawLines[(site.line - 1)...min(rawLines.count - 1, site.line - 1 + span)].compactMap { line -> String? in
                    guard let r = line.range(of: "display-safe-exempt:") else { return nil }
                    return String(line[r.upperBound...])
                }.joined(separator: "\n")
                func exempted(_ expr: String) -> Bool {
                    // 同一個語句的註記以 `display-safe-exempt:` 具名這個引數（例如 `why 是 NameIdentity 的固定訊息`）即放行——與 sink 守衛同一種豁免形狀
                    guard !notes.isEmpty, let ident = expr.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" && $0 != "$" }).first else { return false }
                    return notes.range(of: "(?<![A-Za-z0-9_$])\(NSRegularExpression.escapedPattern(for: String(ident)))(?![A-Za-z0-9_])", options: .regularExpression) != nil
                }
                if m.allSatisfy({ $0 == .unused }) && !args.isEmpty { unusedSites["\(t.qualified).\(site.caseName)", default: 0] += 1 }
                for (arg, mode) in zip(args, m) {
                    var value = arg
                    if let r = value.range(of: #"^[A-Za-z_]\w*:\s*"#, options: .regularExpression) { value = String(value[r.upperBound...]) }
                    // 豁免的粒度（R32；R31 verify 第 1 列 HIGH）：**只有非字面的裸引數**可以整段豁免；字面（含串接）逐插值、逐運算元各自對照註記——
                    // R31 拿字面的第一個識別字去比註記，`"\(label)「\(displaySafeInvisible(n…))」"` 的註記說 `label` 就讓 store 名字 `n` 的消毒免檢（mutation 綠）
                    let literal = Self.isLiteralPiece(value)
                    if !literal && exempted(value) { continue }
                    if mode != .unused && mode != .typed { checkedArgs += 1 }
                    let site_ = "\(site.path):\(site.line) \(t.qualified).\(site.caseName)"
                    switch mode {
                    case .unused, .typed: continue
                    case .unclassified:
                        offenders.append("\(site_) 描述端用到這個 payload，但守衛分不出逃／截／原樣（helper 不在 descriptionHelpers 表、既逃又原樣、或新形狀）：\(value.prefix(60))")
                    case .escaped:
                        if !literal, Self.isSanitized(value) { offenders.append("\(site_) 的描述已逃脫這個 payload，擲出端不得再逃：\(value.prefix(60))") }
                        if literal {
                            for piece in Self.concatenationPieces(of: value) {
                                let interps = Self.interpolations(in: piece)   // 與 .clipped／.raw 同一個入口條件（R33；R32 verify 第 20／28 列）
                                if Self.isLiteralPiece(piece) || !interps.isEmpty {
                                    for e in interps where Self.isSanitized(e) { offenders.append("\(site_) 的描述已逃脫這個 payload，字面裡的插值不得再逃：\\(\(e.prefix(60)))") }
                                } else if Self.isSanitized(piece) { offenders.append("\(site_) 的描述已逃脫這個 payload，串接的運算元不得再逃：\(piece.prefix(60))") }
                            }
                        }
                    case .clipped, .raw:
                        if literal {
                            for piece in Self.concatenationPieces(of: value) {
                                // 字面（`"`／`#"`／`[`）與**含字面插值的表達式**（`xs.map { "「\(displaySafeInvisible($0…))」" }`）逐插值檢查；其餘表達式整段要是
                                // 消毒／字面值／程式構造值／具名豁免
                                let interps = Self.interpolations(in: piece)
                                if Self.isLiteralPiece(piece) || !interps.isEmpty {
                                    for e in interps where !Self.isSanitized(e) && !Self.isProgramBuilt(e) && !exempted(e) {
                                        offenders.append("\(site_) \\(\(e.prefix(60)))")
                                    }
                                } else if !Self.isSanitized(piece) && !Self.isPlainValue(piece) && !Self.isProgramBuilt(piece) && !exempted(piece) {
                                    offenders.append("\(site_) 串接的運算元：\(piece.prefix(80))")
                                }
                            }
                        } else if !Self.isSanitized(value) && !Self.isPlainValue(value) && !Self.isProgramBuilt(value) {
                            offenders.append("\(site_) 裸引數：\(value.prefix(80))")
                        }
                    }
                }
            }
        }
        // CLI 的 ValidationError 是 struct init、單一 payload、描述原樣：擲出端全逃
        for (path, text) in files where path.hasPrefix("Sources/akashic/") {
            for (line, body) in Self.statements(in: text, needle: "throw ValidationError(") {
                scanned += 1
                for arg in Self.topLevelArguments(of: body) {
                    if Self.isLiteralPiece(arg) {
                        for piece in Self.concatenationPieces(of: arg) {
                            let interps = Self.interpolations(in: piece)
                            if Self.isLiteralPiece(piece) || !interps.isEmpty {
                                for e in interps where !Self.isSanitized(e) && !Self.isProgramBuilt(e) { offenders.append("\(path):\(line) ValidationError \\(\(e.prefix(60)))") }
                            } else if !Self.isSanitized(piece) && !Self.isPlainValue(piece) && !Self.isProgramBuilt(piece) { offenders.append("\(path):\(line) ValidationError 串接的運算元：\(piece.prefix(80))") }
                        }
                    } else if !Self.isSanitized(arg) && !Self.isProgramBuilt(arg) { offenders.append("\(path):\(line) ValidationError 裸引數：\(arg.prefix(80))") }
                }
            }
        }
        // 下限量的是**檢查過的引數**，不是走訪過的站點（R30 verify 第 11 列：540 個站點裡 151 個一個引數都沒檢查，400 的地板有 28% 是空檢查撐的）
        XCTAssertGreaterThanOrEqual(scanned, 400, "掃到 \(scanned) 個擲出站點——空掃描不是通過")
        XCTAssertGreaterThanOrEqual(checkedArgs, 750, "檢查過 \(checkedArgs) 個引數——空檢查不是通過")
        // 描述端真的沒用到 payload 的 case 是封閉清單（每列要有理由）；新出現的要在這裡具名，不得靜默跳過
        let knownUnused: [String: String] = [:]
        XCTAssertEqual(Set(unusedSites.keys).subtracting(knownUnused.keys), [], "描述端沒用到任何 payload 的擲出站點（守衛對它們是啞的）：\(unusedSites)")
        XCTAssertEqual(offenders, [], offenders.joined(separator: "\n"))
    }

    /// Error → 文字只有一個入口（`ErrorDisplay.describe`）；其餘每個把 `Error` 變成字串的地方都走 `displaySafeError`／`displaySafeErrorText`／
    /// `displaySafeErrorMultiline`。掃描範圍是 store 與其面；`TractatusDocs`／`tractatus-doc`／`AkashicProposition` 的 corpus 管線不在內（它們不碰
    /// store 字串；範圍是 R28 verify 第 24 列的裁決，R30 對 AkashicProposition 兩個型別的 conform 做了獨立稽核——prefix 截與 safeDescription）。
    /// **`"\(error)"` 也是入口**（R30；R29 verify 第 5 列：11 個站點、六個落進只截的 sink）。
    func testErrorToTextEntriesGoThroughTheSingleEntryPoint() throws {
        let entry = try NSRegularExpression(pattern: #"as\?\s+LocalizedError\)\?\.errorDescription|String\(describing:\s*(error|e|err|failure)\)|\b(error|e|err|failure|underlying|schemaError)\.(localizedDescription|errorDescription)\b|\\\((error|err|failure|underlying)\)"#)
        var offenders: [String] = []
        for (path, text) in try Self.swiftFiles(under: ["Sources"]) {
            if path.hasPrefix("Sources/TractatusDocs/") || path.hasPrefix("Sources/tractatus-doc/") || path.hasPrefix("Sources/AkashicProposition/") { continue }
            if path.hasPrefix("Sources/akashic-guards/") { continue }   // 開發用守衛的 stderr，給維護者看、不碰 store 內容
            if path == "Sources/AkashicCore/ErrorDisplay.swift" { continue }
            let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (n, raw) in Self.strippingLineComments(text).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let line = String(raw)
                guard entry.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil else { continue }
                if String(rawLines[n]).contains("display-safe-exempt:") { continue }
                offenders.append("\(path):\(n + 1) \(line.trimmingCharacters(in: .whitespaces).prefix(100))")
            }
        }
        XCTAssertEqual(offenders, [], offenders.joined(separator: "\n"))
        let expected: [(file: String, needle: String, count: Int)] = [
            ("Sources/akashic-mcp/Server.swift", "text: displaySafeErrorMultiline(error, prefix: \"Error: \")", 1),
            ("Sources/akashic-mcp/Main.swift", "displaySafeErrorMultiline(error, prefix: \"akashic-mcp 啟動失敗：\")", 1),
            ("Sources/AkashicAppKit/EntryViews.swift", "errorMessage = displaySafeErrorMultiline(error)", 3),
            ("Sources/AkashicAppKit/AdjudicationViews.swift", "errorMessage = displaySafeErrorMultiline(error)", 3),
            ("Sources/AkashicAppKit/GraphView.swift", "loadError = displaySafeErrorMultiline(error)", 2),
            ("Sources/AkashicAppKit/AppState.swift", "underlying: displaySafeError(error, max: 2_400)", 1),
            ("Sources/akashic/LibraryCommands.swift", "throw ValidationError(displaySafeErrorText(", 2),
            ("Sources/akashic/Commands.swift", "throw ValidationError(displaySafeErrorText(error))", 1),
            ("Sources/akashic/CLI.swift", "throw ValidationError(displaySafeErrorText(error))", 1),
            ("Sources/akashic/EnrichCommand.swift", "throw ValidationError(displaySafeErrorText(e))", 1),
            ("Sources/AkashicZoteroImport/ZoteroImporter.swift", "report.writeFailed[entry.citekey] = displaySafeError(error, max: 4_096)", 1),
            ("Sources/akashic/EnrichFromZoteroCommand.swift", "failed[a.citekey] = displaySafeError(error, max: 4_096)", 1),
            ("Sources/AkashicStoreIO/PersonIdentityMigration.swift", "let reason = displaySafeError(error, max: 4_096)", 4),
            ("Sources/AkashicStoreIO/ProvenanceMigration.swift", "reason: displaySafeError(error, max: 4_096)", 2),
            ("Sources/AkashicStoreIO/StoreIncarnation.swift", "why: displaySafeError(error, max: 2_400)", 1),
            ("Sources/AkashicStoreIO/DivergenceResolve.swift", "+ displaySafeError(error, max: 4_096))", 6),
            ("Sources/AkashicStoreIO/DivergenceResolve.swift", "的 verdict value 遷移寫入失敗：\\(displaySafeError(error, max: 4_096))", 6),
            ("Sources/akashic/Commands.swift", "displaySafeError(error, max: 4_096)", 6),
            ("Sources/AkashicStoreIO/IdentifierMigration.swift", "寫入前提不成立：\\(displaySafeError(error, max: 4_096))", 1),
            ("Sources/AkashicStoreIO/VenueVariantMigration.swift", "\\(displaySafeError(error, max: 4_096))", 2),
            ("Sources/AkashicStoreIO/LibraryStore.swift", "reason: displaySafeError(error, max: 4_096)", 4),
        ]
        for (file, needle, count) in expected {
            let text = try String(contentsOf: Self.repoRoot.appendingPathComponent(file), encoding: .utf8)
            XCTAssertEqual(text.components(separatedBy: needle).count - 1, count, "\(file) 的 Error → 文字入口：\(needle)")
        }
    }

    /// `StoreIOError.invalidInput` 的描述只截（擲出端逃）；上限是輸出 scalar。
    func testInvalidInputDescriptionOnlyClips() throws {
        let desc = try String(contentsOf: Self.repoRoot.appendingPathComponent("Sources/AkashicStoreIO/LibraryStore.swift"), encoding: .utf8)
        XCTAssertTrue(desc.contains("\\(displaySafeClipOnly(what, max: 960)) 無效：\\(displaySafeClipOnly(why, max: 3_200))"), "invalidInput 的描述要只截，且上限是輸出 scalar（輸入的 8 倍；R28 verify 第 23 列）")
    }

    /// 已消毒載體（`ValidationIssue.message`／`QuarantinedFile.reason`／`Failure.reason`／`WriteFailure.error`／migration 報告的 reason／`why`）的 sink 只截：
    /// 對這些表達式再跑 `displaySafe(`／`displaySafeInvisible(` 就是二次逃脫。要例外（原始載體）在同一行寫 `display-safe-exempt: 未消毒`。
    /// 另有一張封閉表：每個具名的 sink 都要真的是 clip-only。migration 報告的 reason 自 R30 起**全部**在建構點消毒（R29 verify 第 2 列：
    /// 混合載體——部分建構點 displaySafeError、部分原始 key，CLI 對整批再逃一次）。
    func testSanitizedCarrierSinksOnlyClip() throws {
        let carrier = try NSRegularExpression(pattern: #"displaySafe(Invisible)?\(\s*(\$0\.message|issue\.message|\$0\.reason|f\.reason|reason|f\.error|\$0\.error|f\.why|why)\b"#)
        var offenders: [String] = []
        for (path, text) in try Self.swiftFiles(under: ["Sources"]) {
            for (n, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let line = String(raw)
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                guard carrier.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil else { continue }
                if line.contains("display-safe-exempt:") && line.contains("未消毒") { continue }
                offenders.append("\(path):\(n + 1) \(line.trimmingCharacters(in: .whitespaces).prefix(100))")
            }
        }
        XCTAssertEqual(offenders, [], offenders.joined(separator: "\n"))
        let expected: [(file: String, needle: String)] = [
            ("Sources/AkashicStoreIO/LibraryStore.swift", "無效：\\(displaySafeClipOnly(why, max: 3_200))"),
            ("Sources/AkashicMCPKit/AkashicService.swift", "\"message\": displaySafeClipOnly($0.message, max: 300)"),
            ("Sources/AkashicMCPKit/AkashicService.swift", "\"reason\": displaySafeClipOnly($0.reason, max: 512)"),
            ("Sources/akashic/CLI.swift", "displaySafeClipOnly($0.reason, max: 4_096)"),
            ("Sources/AkashicAppKit/Adjudication.swift", "displaySafeClipOnly(reason, max: 4_096)"),
            ("Sources/AkashicMCPKit/UpdatePerson.swift", "displaySafeClipOnly($0.message, max: 300)"),
            ("Sources/AkashicStoreIO/StoreMigration.swift", "displaySafeClipOnly($0, max: 2_400)"),
            ("Sources/akashic/FormatCommands.swift", "displaySafeClipOnly(f.reason, max: 2_400)"),
            ("Sources/AkashicStoreIO/DivergenceResolve.swift", "losses.map { displaySafeClipOnly($0, max: 2_400) }"),
            ("Sources/akashic/CreateEntryCommand.swift", "displaySafeClipOnly(f.error, max: 3_200)"),
            ("Sources/akashic/LibraryCommands.swift", "displaySafeClipOnly(f.error, max: 3_200)"),
            ("Sources/AkashicMCPKit/AkashicService.swift", "(displaySafeInvisible($0.key, max: 200), displaySafeClipOnly($0.value, max: 512))"),
            ("Sources/akashic/Commands.swift", "displaySafeClipOnly(report.writeFailed[key]!, max: 4_096)"),
            ("Sources/akashic/DivergenceCommands.swift", "displaySafeClipOnly(f, max: 4_096)"),
            ("Sources/akashic/EnrichFromZoteroCommand.swift", "displaySafeClipOnly(e, max: 1_600)"),
            ("Sources/AkashicAppKit/AppState.swift", "displaySafeClipOnly(underlying, max: 2_400)"),
            ("Sources/AkashicAppKit/EntryViews.swift", "displaySafeClipOnly(failure, max: 2_400)"),
            // R30：migration 報告與 resolve 的 why 全部在建構點消毒之後，sink 只截（R29 verify 第 2／5／28／33 列）
            ("Sources/akashic/Commands.swift", "displaySafeClipOnly(f.reason, max: 4_096)"),
            ("Sources/akashic/Commands.swift", "displaySafeClipOnly(f.why, max: 4_096)"),
            ("Sources/akashic/Commands.swift", "displaySafeClipOnly(why, max: 4_096)"),
            ("Sources/akashic/VenueCommand.swift", "displaySafeClipOnly(f.reason, max: 2_400)"),
            ("Sources/akashic/VenueCommand.swift", "displaySafeClipOnly(f.reason, max: 4_096)"),
            ("Sources/akashic/IdentifierMigrateCommand.swift", "displaySafeClipOnly(f, max: 4_096)"),
            ("Sources/AkashicAppKit/RecordIssuesSummary.swift", "displaySafeClipOnly($0.issue.message, max: 300)"),
            // R31：三面共用的 producer（StoreHealth 2,400）進 MCP payload 前再截 512（R30 verify 第 16／17／21／30 列）
            ("Sources/AkashicMCPKit/AkashicService.swift", "d[\"sourcesAuditError\"] = displaySafeClipOnly(auditError, max: 512)"),
            ("Sources/AkashicStoreIO/StoreIncarnation.swift", "displaySafeClipOnly(path, max: 2_400))」存在但讀不到（\\(displaySafeClipOnly(why, max: 2_400))"),
        ]
        for (file, needle) in expected {
            let text = try String(contentsOf: Self.repoRoot.appendingPathComponent(file), encoding: .utf8)
            XCTAssertTrue(text.contains(needle), "\(file) 少了 clip-only 的 sink：\(needle)")
        }
    }

    /// 原始載體（檔名）的 sink 要逃脫——R27 verify 第 3 列：同一行裡 reason 逃了、file 沒逃，ZWSP／TAG 原樣進 CLI 終端與 MCP payload。
    func testRawFileNameSinksEscapeByProperty() throws {
        let expected: [(file: String, needle: String)] = [
            ("Sources/AkashicMCPKit/AkashicService.swift", "\"file\": displaySafeInvisible($0.file, max: 300)"),
            ("Sources/AkashicMCPKit/AkashicService.swift", "health.unknownFieldFiles.map { displaySafeInvisible($0, max: 200) }"),
            ("Sources/akashic/CLI.swift", "\\(displaySafeInvisible($0.file, max: 200))"),
            ("Sources/akashic/Commands.swift", "print(\"  ⚠ \\(displaySafeInvisible($0, max: 200))\")"),
            ("Sources/akashic/FormatCommands.swift", "\\(displaySafeInvisible(f.file, max: 200))"),
            ("Sources/akashic/FormatCommands.swift", "print(\"  - \\(displaySafeInvisible(f, max: 200))\")"),
            ("Sources/AkashicAppKit/Adjudication.swift", "var displayFile: String { displaySafeInvisible(file, max: 300) }"),
        ]
        for (file, needle) in expected {
            let text = try String(contentsOf: Self.repoRoot.appendingPathComponent(file), encoding: .utf8)
            XCTAssertTrue(text.contains(needle), "\(file) 的檔名 sink 沒有以性質逃脫：\(needle)")
        }
    }

    /// 每個 `QuarantinedFile(`／`Failure(file:` 建構點的 reason 都在建構時消毒——「sink 只截」的正確性完全靠這件事。
    func testQuarantineAndFormatFailureReasonsAreSanitizedAtConstruction() throws {
        var offenders: [String] = []; var scanned = 0
        for (path, text) in try Self.swiftFiles(under: ["Sources"]) {
            for needle in ["QuarantinedFile(", "Failure(file:"] {
                for (line, body) in Self.statements(in: text, needle: needle) {
                    scanned += 1
                    guard let r = body.range(of: "reason:") else { offenders.append("\(path):\(line) 沒有 reason:"); continue }
                    let arg = String(body[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let sanitizers = ["displaySafeInvisible(", "displaySafeError(", "describe(error)"]
                    if arg.hasPrefix("\"") {
                        let bad = Self.interpolations(in: arg).filter { e in !sanitizers.contains { e.hasPrefix($0) } && !e.hasSuffix(".uuidString") && !Self.isProgramBuilt(e) }
                        if !bad.isEmpty { offenders.append("\(path):\(line) reason 有未消毒插值：\(bad)") }
                    } else if !sanitizers.contains(where: { arg.hasPrefix($0) }) {
                        offenders.append("\(path):\(line) reason 不是字面量也不經消毒：\(arg.prefix(80))")
                    }
                }
            }
        }
        XCTAssertEqual(offenders, [], offenders.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(scanned, 5, "建構點守衛掃到 \(scanned) 個站點——空掃描不是通過（R29 NC4）")
        let cf = try String(contentsOf: Self.repoRoot.appendingPathComponent("Sources/AkashicStoreIO/CanonicalFormat.swift"), encoding: .utf8)
        XCTAssertTrue(cf.contains("private static func describe(_ error: Error) -> String { displaySafeError(error, max: 4_096) }"), "CanonicalFormat.describe 要走 displaySafeError")
    }

    // MARK: - helper 行為

    /// 三族各逃一次：自帶消毒的 StoreYAMLError／StoreIOError 只截（`\u{0007}` 一次、無 `\u{005C}`）；Yams 那類原始錯誤在這裡逃一次。
    func testDisplaySafeErrorEscapesOnceForEachFamily() throws {
        struct Raw: Error, CustomStringConvertible { var description: String { "yams: peri\u{7} odical\u{200B}" } }
        let yaml = StoreYAMLError.invalidField("venue.type", "'\(displaySafeInvisible("peri\u{7} odical", max: 120))' 不在封閉列舉")
        let io = StoreIOError.invalidInput(what: "venue 'beta'", why: "variant「\(displaySafeInvisible("Ga\u{200B}mma", max: 80))」含不可見字元")
        for (e, expect) in [(yaml as Error, "'peri\\u{0007} odical'"), (io, "「Ga\\u{200B}mma」"), (Raw(), "peri\\u{0007} odical\\u{200B}")] {
            let s = displaySafeError(e, max: 512)
            XCTAssertTrue(s.contains(expect), s)
            XCTAssertFalse(s.contains("\\u{005C}"), "二次逃脫：\(s)")
            XCTAssertFalse(s.unicodeScalars.contains { $0.value == 0x7 || $0.value == 0x200B }, s)
        }
    }

    /// `displaySafeError` 的 `max` 是**輸出** scalar 上限（兩類都是）——R29 的 ×8 藏在函式內部，MCP 的 `applyDict["error"]` 拿到 4,096
    /// 而 changelog 說 512（R29 verify 第 23／24 列）。
    func testDisplaySafeErrorMaxIsAnOutputBound() {
        let long = ServiceErrorProbe.make(String(repeating: displaySafeInvisible("\u{200B}", max: 8), count: 200))   // 1,600 個輸出 scalar
        let out = displaySafeError(long, max: 512)
        XCTAssertLessThanOrEqual(out.count, 512 + "…（已截斷）".count, out.count.description)
        XCTAssertTrue(out.hasSuffix("}…（已截斷）"), "退讓到完整的逃脫序列：\(out.suffix(16))")
        struct Raw: Error, CustomStringConvertible { var description: String { String(repeating: "\u{200B}", count: 200) } }
        let raw = displaySafeError(Raw(), max: 512)
        XCTAssertLessThanOrEqual(raw.count, 512 + "…（已截斷）".count)
        XCTAssertFalse(raw.contains("\\u{005C}"))
    }

    /// 多行入口：自帶消毒的只截、合法反斜線原樣；其餘逐行逃一次（含不可見 scalar）；前綴接在截之前。
    func testDisplaySafeErrorMultilineEscapesOnceAndKeepsRegexConstants() {
        struct Raw: Error, CustomStringConvertible { var description: String { "line\u{7}1\nline\u{200B}2" } }
        let svc = ServiceErrorProbe.make("key「\(displaySafeInvisible("Ga\u{200B}mma", max: 80))」不符合 \\A[a-z0-9]+\\z\n第二行 \(displaySafeInvisible("\u{7}", max: 8))")
        let s = displaySafeErrorMultiline(svc, prefix: "Error: ")
        XCTAssertTrue(s.hasPrefix("Error: key「Ga\\u{200B}mma」"), s)
        XCTAssertTrue(s.contains("\\A[a-z0-9]+\\z"), "合法反斜線常量要原樣：\(s)")
        XCTAssertTrue(s.contains("第二行 \\u{0007}"), s)
        XCTAssertFalse(s.contains("\\u{005C}"), "二次逃脫：\(s)")
        XCTAssertEqual(displaySafeErrorMultiline(Raw()), "line\\u{0007}1\nline\\u{200B}2")
    }

    /// 兩面對同一個錯誤印出同一個字串——**含被截斷的**：CLI 是 `displaySafeAssembled("Error: " + displaySafeErrorText(e))`，MCP 是
    /// `displaySafeErrorMultiline(e, prefix: "Error: ")`，兩者必須逐字相同（R29 verify 第 9 列：先截再加前綴 vs 先加再截，406 vs 413）。
    func testTwoFacesAgreeEvenWhenTruncated() {
        let e = ServiceErrorProbe.make("names（--names） 的 「AAAAA\(String(repeating: displaySafeInvisible("\u{200B}", max: 8), count: 60))」含不可見字元")
        let cli = displaySafeAssembled("Error: " + displaySafeErrorText(e))
        let mcp = displaySafeErrorMultiline(e, prefix: "Error: ")
        XCTAssertEqual(cli, mcp)
        XCTAssertTrue(cli.hasSuffix("}…（已截斷）"), "截點退讓到完整的逃脫序列：\(cli.suffix(20))")
        XCTAssertLessThanOrEqual(cli.count, 400 + "…（已截斷）".count)
    }

    /// 總量上限量的是**最終**輸出：非自帶消毒的錯誤先逃完（含 8 倍膨脹的不可見 scalar）再由 `displaySafeAssembled` 截 96 KB
    /// （R29 verify 第 10／12／15／18 列：R29 在 96 KB 之後才套 `escapingInvisibleScalars`，實測 720 KB 進 MCP context）。
    func testDisplaySafeErrorMultilineCapsAfterExpansion() {
        struct Raw: Error, CustomStringConvertible { var description: String { Array(repeating: String(repeating: "\u{200B}", count: 400), count: 300).joined(separator: "\n") } }
        let out = displaySafeErrorMultiline(Raw(), prefix: "Error: ")
        XCTAssertLessThanOrEqual(out.utf8.count, 96_000 + 8 * 400 + 64, "總量 \(out.utf8.count) bytes")
        XCTAssertTrue(out.contains("……（截斷：共 300 行）"), out.suffix(40).description)
        XCTAssertFalse(out.unicodeScalars.contains { $0.value == 0x200B })
    }

    /// 截點退讓：`displaySafeClipOnly` 與 `displaySafeAssembled` 都退到完整的逃脫序列，且只認半截逃脫序列——`\A`／`\z` 這種真反斜線常量不動
    /// （R28 verify 第 8／29／36 列：R28 的無條件退讓把 CLI 一行 406 砍到 41；R29 verify 第 7／11／13／16／21 列：R29 只裝在 ClipOnly，
    /// assembled 照樣截在 `\u{…}` 中間——DA 實測窄退讓對 `\A…\z` 零誤傷）。
    func testClipBackoffAppliesToAssembledWithoutEatingTrueBackslashes() {
        let long = "\\A[a-z0-9]+\\z " + String(repeating: "x", count: 500)
        for out in [displaySafeAssembled(long, maxLineLength: 400), displaySafeClipOnly(long, max: 400)] {
            XCTAssertTrue(out.hasPrefix("\\A[a-z0-9]+\\z "), out.prefix(40).description)
            XCTAssertGreaterThan(out.count, 380, "一行要留到上限，不是退到最後一個反斜線：\(out.count)")
        }
        for pad in 0..<12 {
            let s = String(repeating: "A", count: pad) + String(repeating: "\\u{200B}", count: 70) + "\n" + String(repeating: "B", count: pad) + String(repeating: "\\u{E0001}", count: 60)
            for line in displaySafeAssembled(s, maxLineLength: 400).split(separator: "\n") where line.hasSuffix("…（已截斷）") {
                let body = String(line.dropLast("…（已截斷）".count))
                XCTAssertFalse(body.hasSuffix("\\"), "裸反斜線結尾（pad \(pad)）：\(body.suffix(12))")
                if let open = body.range(of: "\\u{", options: .backwards) { XCTAssertTrue(body[open.upperBound...].contains("}"), "截在逃脫序列中間（pad \(pad)）：\(body.suffix(12))") }
            }
        }
        let tailZ = String(repeating: "x", count: 398) + "\\z" + "yyyy"
        XCTAssertTrue(displaySafeClipOnly(tailZ, max: 400).hasPrefix(String(repeating: "x", count: 398) + "\\z"), "`\\z` 不是半截逃脫序列，留著")
        for tail in ["\\u{20", "\\u{E000", "\\u{E0001", "\\u{10FFF"] {
            let s = String(repeating: "x", count: 400 - tail.count) + tail + "F}yy"
            XCTAssertTrue(displaySafeClipOnly(s, max: 400).hasPrefix(String(repeating: "x", count: 400 - tail.count) + "…"), "`\(tail)` 是半截：\(displaySafeClipOnly(s, max: 400).suffix(20))")
        }
    }

    /// 只截不逃的截點不得落在 `\u{…}` 中間（R27 verify DA 第 19 列）。
    func testClipOnlyNeverCutsInsideAnEscape() {
        for pad in 0..<10 {
            let s = String(repeating: "A", count: pad) + String(repeating: "\\u{200B}", count: 70)
            let out = displaySafeClipOnly(s, max: 512)
            XCTAssertTrue(out.hasSuffix("…（已截斷）"), out)
            let body = String(out.dropLast("…（已截斷）".count))
            XCTAssertFalse(body.hasSuffix("\\"), "裸反斜線結尾（pad \(pad)）：\(body.suffix(12))")
            if let open = body.range(of: "\\u{", options: .backwards) { XCTAssertTrue(body[open.upperBound...].contains("}"), "截在逃脫序列中間（pad \(pad)）：\(body.suffix(12))") }
        }
        XCTAssertEqual(displaySafeClipOnly("\\u{200B}AB", max: 100), "\\u{200B}AB", "不截時原樣")
        XCTAssertEqual(displaySafe(String(repeating: "\\", count: 3), max: 2), "\\u{005C}\\u{005C}…（已截斷）", "逃脫自己的路徑照舊")
    }

    /// R29 自己造出的兩個雙重逃脫（R29 verify 第 1／8 列與第 4／6／14 列）：`StoreIncarnationError.unreadable` 擲出端與描述端各逃一次；
    /// `StoreVersionError` 擲出端逃了、型別沒 conform、出口再逃一次。兩者走真的入口驗。
    func testStoreIncarnationAndStoreVersionErrorsEscapeOnce() throws {
        let unreadable = StoreIncarnationError.unreadable(path: displaySafeInvisible("/tmp/st\u{200B}ore/incarnation", max: 300), why: displaySafeInvisible("拒絕存取\u{7}", max: 300))
        let s = displaySafeErrorMultiline(unreadable, prefix: "Error: ")
        XCTAssertTrue(s.contains("st\\u{200B}ore") && s.contains("拒絕存取\\u{0007}"), s)
        XCTAssertFalse(s.contains("\\u{005C}"), s)
        XCTAssertThrowsError(try StoreVersion.read(data: Data("format: 17\n\tbad\u{7}line\u{200B}here\n".utf8), path: "/tmp/sv\u{200B}/store.yaml")) { error in
            XCTAssertTrue(error is SanitizedErrorDescription)
            let t = displaySafeErrorMultiline(error, prefix: "Error: ")
            XCTAssertTrue(t.contains("bad\\u{0007}line\\u{200B}here") && t.contains("/tmp/sv\\u{200B}/store.yaml"), t)
            XCTAssertFalse(t.contains("\\u{005C}"), "二次逃脫：\(t)")
            XCTAssertFalse(t.unicodeScalars.contains { $0.value == 0x200B || $0.value == 0x7 }, t)
        }
    }

    /// 守衛自己的解析器：插值裡的 `joined(separator: ", ")` 不得把引數切成兩段（R29 verify 第 26 列）；`\"` 不算引號。
    func testArgumentSplitterSurvivesInterpolatedStringLiterals() {
        let a = Self.topLevelArguments(of: #"throw ServiceError.invalid("index rebuild 失敗：\(displaySafeError(error, max: 512))（本趟：\(report.created.count)、\(missing.joined(separator: ", "))）")"#)
        XCTAssertEqual(a.count, 1, a.description)
        let b = Self.topLevelArguments(of: #"StoreIOError.invalidInput(what: rawKey, why: "x, y \(displaySafeInvisible(k, max: 1))")"#)
        XCTAssertEqual(b, ["what: rawKey", #"why: "x, y \(displaySafeInvisible(k, max: 1))""#])
        XCTAssertEqual(Self.strippingLineComments(#"let s = "a \" // b" // note"#), #"let s = "a \" // b"        "#)
        // R33（R32 verify 第 8／34 列）：插值裡的巢狀字串含 `)`／`\"`／` + ` 時串接不得誤併／誤切；raw string 的 `\#(` 也是插值（DA 第 13 列）
        XCTAssertEqual(Self.concatenationPieces(of: #""前綴 \(xs.joined(separator: ")"))" + rawVar"#), [#""前綴 \(xs.joined(separator: ")"))""#, "rawVar"])
        XCTAssertEqual(Self.concatenationPieces(of: #""前綴 \(g("q\"r"))" + rawVar"#), [#""前綴 \(g("q\"r"))""#, "rawVar"])
        XCTAssertEqual(Self.concatenationPieces(of: #""a \(xs.joined(separator: " + "))""#).count, 1)
        XCTAssertEqual(Self.concatenationPieces(of: #""a \(x.f(of: "\\\"")) b" + rawStoreString"#), [#""a \(x.f(of: "\\\"")) b""#, "rawStoreString"])
        XCTAssertEqual(Self.concatenationPieces(of: ##""字面" + #"\#(x) + y"# + z"##), [#""字面""#, ##"#"\#(x) + y"#"##, "z"])
        XCTAssertEqual(Self.interpolations(in: ##"#"a \#(store) b"#"##), ["store"])
        XCTAssertTrue(Self.isLiteralPiece(##"#"…"#"##) && Self.isLiteralPiece("[a]") && !Self.isLiteralPiece("x"))
    }

    // MARK: - R31（D83）：輸入側上限、LF 折疊、位元組總量、檔名附加

    /// 每個 `displaySafeError(_, max:)` 與 `maxLineLength:` 都 ≤ `ErrorDisplay.inputScalarCeiling`——ceiling 是「每個輸入 scalar 至少產生一個輸出
    /// scalar」之下 sink 不需要更多輸入的保證；sink 上限若超過它，被 ceiling 截短的行會冒充完整的行。
    func testEverySinkBoundIsWithinTheInputCeiling() throws {
        XCTAssertEqual(ErrorDisplay.inputScalarCeiling, 4_096)
        // 各族各自有地板（R32；R31 verify 第 6／16／30 列：R31 的 `maxLineLength:` 那一半零命中——全樹沒有呼叫端傳字面值、宣告的預設值 `= 400` 也掃不到，
        // 而多行家族的輸出上限正是那個預設值；`displaySafeClipOnly` 完全沒掃）。**族要照它守的東西分，地板照實測訂**（R33；R32 verify 第 5／10／15／16／25 列：
        // R32 的第三族 `(?:maxLineLength|max): Int =` 把 `displaySafe`／`displaySafeInvisible` 的**生產者輸入預算** 200 也掃進來——它們不是 sink、與 ceiling
        // 的前提無關，卻撐著那一族的地板：刪掉三個真的 sink 預設值裡的兩個仍綠；clipOnly 的地板 15 是照一個量錯的 18 打的折，真值 39、允許 62% 站點消失）。
        // 實測 2026-09-18（HEAD 58bab46d）：57／39／3——地板取約七折，第三族等於實測（三個成員、少一個就要出聲）。
        // 第四族是**呼叫端字面**的 `maxLineLength:`（R32 換族時丟掉的那一格）：今天零實例、地板 0——它存在是為了抓新的呼叫端，不是證明掃描非空，
        // 所以不拿它撐任何地板。具名常量（`refusalLineMax`）與 `maximum:` 預設值住在自帶消毒型別自己的描述裡、與 ceiling 無關，不在任何一族（第 19 列）。
        let families: [(name: String, pattern: String, floor: Int)] = [
            ("displaySafeError(max:)", #"displaySafeError\([^,)]+,\s*max:\s*([0-9_]+)\)"#, 50),
            ("displaySafeClipOnly(max:)", #"displaySafeClipOnly\((?:[^()]|\([^()]*\))*,\s*max:\s*([0-9_]+)\)"#, 35),
            ("sink 宣告的預設值（maxLineLength: Int =）", #"maxLineLength:\s*Int\s*=\s*([0-9_]+)"#, 3),
            ("呼叫端字面的 maxLineLength:", #"maxLineLength:\s*([0-9_]+)\b"#, 0),
        ]
        var over: [String] = []
        for fam in families {
            let re = try NSRegularExpression(pattern: fam.pattern)
            var sites = 0
            for (path, text) in try Self.swiftFiles(under: ["Sources"]) {
                let stripped = Self.strippingLineComments(text)
                for m in re.matches(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)) {
                    let n = Int(String(stripped[Range(m.range(at: 1), in: stripped)!]).replacingOccurrences(of: "_", with: ""))!
                    sites += 1
                    if n > ErrorDisplay.inputScalarCeiling { over.append("\(path): \(String(stripped[Range(m.range, in: stripped)!]).prefix(80))") }
                }
            }
            if fam.floor > 0 { XCTAssertGreaterThanOrEqual(sites, fam.floor, "\(fam.name)：掃到 \(sites) 個——空掃描不是通過") }
        }
        XCTAssertEqual(over, [], over.joined(separator: "\n"))
    }

    /// 輸入上限不改變截出來的字串：有界版本與無界版本（就地重算）對同一行逐字相同——含混合 ASCII／ZWSP／BEL、含截點退讓。
    func testInputCeilingDoesNotChangeClippedOutput() {
        struct Raw: Error, CustomStringConvertible { let description: String }
        let line = String(repeating: "ab\u{200B}c\u{7}", count: 2_000)   // 10,000 scalar，超過 ceiling
        for max in [512, 4_096] {
            let bounded = displaySafeError(Raw(description: line), max: max)
            let unbounded = displaySafeClipOnly(escapingInvisibleScalars(displaySafe(line, max: .max)), max: max)
            XCTAssertEqual(bounded, unbounded, "max \(max)")
            XCTAssertLessThanOrEqual(bounded.unicodeScalars.count, max + "…（已截斷）".count)
        }
        XCTAssertEqual(displaySafeErrorMultiline(Raw(description: line), prefix: "Error: "),
                       displaySafeAssembled("Error: " + escapingInvisibleScalars(displaySafe(line, max: .max))))
        // 剛好在 ceiling 邊界：4,096 個 scalar 不加標記，4,097 個加一次
        XCTAssertFalse(displaySafeErrorText(Raw(description: String(repeating: "x", count: 4_096))).contains("…（已截斷）"))
        let over = displaySafeErrorText(Raw(description: String(repeating: "x", count: 4_097)))
        XCTAssertEqual(over.components(separatedBy: "…（已截斷）").count - 1, 1)
        XCTAssertEqual(displaySafeError(Raw(description: String(repeating: "x", count: 4_097)), max: 4_096).components(separatedBy: "…（已截斷）").count - 1, 1, "sink 再截時標記仍只有一個")
    }

    /// 工作量與輸入長度同階（R30 verify 第 1／3／6／9 列：R30 對 400,000 個 ZWSP 的單行跑 20 秒、1 MB 96 秒——接近二次）。
    /// 量的是**縮放比**，不是絕對牆鐘（R32；R31 verify 第 5／14／20／42 列：R31 用 1.0 秒絕對上限並宣稱「寬十倍以上」，而實測 debug build
    /// 2 MB 單行 0.10–0.13 s、200,000 行 0.36–0.39 s，兩格都不到十倍，且絕對牆鐘在併發負載下會偶發變紅——偶發的紅比漏報更貴）：
    /// 輸入四倍，耗時不得超過八倍（線性 ≈ 4 倍、二次 ≈ 16 倍）；另留一個寬鬆的絕對上限（10 秒）擋住整個路徑失控。
    func testErrorTextWorkIsLinearInTheInput() {
        struct Raw: Error, CustomStringConvertible { let description: String }
        func seconds(_ body: () -> Void) -> TimeInterval { let t = Date(); body(); return Date().timeIntervalSince(t) }
        let small = Raw(description: String(repeating: "\u{200B}", count: 500_000))
        let big = Raw(description: String(repeating: "\u{200B}", count: 2_000_000))
        _ = displaySafeError(small, max: 512)   // 暖機：第一次跑含一次性配置
        let tSmall = seconds { _ = displaySafeError(small, max: 512) }
        var out = ""
        let tBig = seconds { out = displaySafeError(big, max: 512) }
        XCTAssertLessThanOrEqual(out.unicodeScalars.count, 512 + "…（已截斷）".count)
        XCTAssertLessThan(tBig, 10.0, "2 MB 單行：\(tBig) s")
        XCTAssertLessThan(tBig / Swift.max(tSmall, 0.001), 8.0, "單行：輸入 ×4 耗時 ×\(tBig / Swift.max(tSmall, 0.001))（\(tSmall) → \(tBig) s）——超線性")
        let fewLines = Raw(description: Array(repeating: "\u{200B}", count: 50_000).joined(separator: "\n"))
        let manyLines = Raw(description: Array(repeating: "\u{200B}", count: 200_000).joined(separator: "\n"))
        _ = displaySafeErrorMultiline(fewLines, prefix: "Error: ")
        let tFew = seconds { _ = displaySafeErrorMultiline(fewLines, prefix: "Error: ") }
        var b = ""
        let tMany = seconds { b = displaySafeErrorMultiline(manyLines, prefix: "Error: ") }
        XCTAssertTrue(b.contains("……（截斷：共 200000 行）"), b.suffix(40).description)
        XCTAssertLessThan(tMany, 10.0, "200,000 行：\(tMany) s")
        XCTAssertLessThan(tMany / Swift.max(tFew, 0.001), 8.0, "多行：輸入 ×4 耗時 ×\(tMany / Swift.max(tFew, 0.001))（\(tFew) → \(tMany) s）——超線性")
    }

    /// 單行家族：`max` 是輸出 scalar 上限——對**整個** `UnsafeToEmitScalar` 類別成立（R32 D84；R30 verify 第 12 列對 LF、R31 verify 第 7 列對
    /// TAB／CR／LS：R31 只折了 LF，`displaySafeClipOnly` 對其餘控制字元仍逃成八個字元只算一格）。自帶消毒與非自帶消毒兩類都測。
    func testDisplaySafeErrorMaxIsAnOutputBoundForEveryUnsafeScalar() {
        struct Raw: Error, CustomStringConvertible { var description: String { String(repeating: "\n", count: 600) } }
        let out = displaySafeError(Raw(), max: 512)
        XCTAssertLessThanOrEqual(out.unicodeScalars.count, 512 + "…（已截斷）".count, "\(out.unicodeScalars.count)")
        XCTAssertTrue(out.hasPrefix("\\u{000A}\\u{000A}"), out.prefix(20).description)
        XCTAssertFalse(out.contains("\n"))
        XCTAssertFalse(out.contains("\\u{005C}"), "反斜線不得再逃：\(out.prefix(30))")
        for scalar in ["\t", "\r", "\u{2028}", "\u{0085}", "\u{202E}"] {
            let selfSanitizing = ServiceErrorProbe.make(String(repeating: scalar, count: 600))
            let o = displaySafeError(selfSanitizing, max: 512)
            XCTAssertLessThanOrEqual(o.unicodeScalars.count, 512 + "…（已截斷）".count, "U+\(String(scalar.unicodeScalars.first!.value, radix: 16))：\(o.unicodeScalars.count)")
            XCTAssertFalse(o.unicodeScalars.contains { UnsafeToEmitScalar.contains($0.value) }, "裸控制字元落到輸出")
        }
        XCTAssertEqual(displaySafeClipOnly(String(repeating: "\t", count: 100), max: 16), String(repeating: "\\u{0009}", count: 2) + "…（已截斷）", "只截支數輸出 scalar")
        // 多行家族保留 LF（它的 sink 逐行截）
        XCTAssertEqual(displaySafeErrorMultiline(ServiceErrorProbe.make("a\nb")), "a\nb")
    }

    /// D84 的 `cost` 常數有守衛（R33；R32 verify 第 7／11／17／35 列）：`UnsafeToEmitScalar` 的**每個**成員都在 BMP、只截支對每個成員以
    /// `escapedScalarCount` 為預算恰好不截、少一格就截。`jsonEscape` 對同一前提有 surrogate 分支＋doc，這裡是 display 面的那一半——
    /// 加一個非 BMP 成員（`\u{%04X}` 印五位、每次逃脫少算一格）自此紅（NC）。
    func testEveryUnsafeScalarEscapesToExactlyEscapedScalarCount() {
        var members = 0
        for v in UInt32(0)...0x10FFFF where UnsafeToEmitScalar.contains(v) {
            members += 1
            XCTAssertLessThanOrEqual(v, 0xFFFF, "非 BMP 成員 U+\(String(v, radix: 16))：`%04X` 會印五位、預算少算一格")
            guard let u = Unicode.Scalar(v) else { XCTFail("U+\(String(v, radix: 16)) 不是 scalar"); continue }
            let s = String(Character(u))
            XCTAssertEqual(String(format: "\\u{%04X}", v).unicodeScalars.count, UnsafeToEmitScalar.escapedScalarCount, "U+\(String(v, radix: 16))：逃脫序列長度")
            XCTAssertEqual(displaySafeClipOnly(s, max: UnsafeToEmitScalar.escapedScalarCount), String(format: "\\u{%04X}", v), "U+\(String(v, radix: 16))")
            XCTAssertTrue(displaySafeClipOnly(s, max: UnsafeToEmitScalar.escapedScalarCount - 1).hasSuffix("…（已截斷）"), "U+\(String(v, radix: 16))：少一格要截")
        }
        XCTAssertGreaterThanOrEqual(members, 32 + 1 + 32 + 2 + 5 + 4 + 3 + 1, "成員數 \(members)——空掃描不是通過")
    }

    /// 96 KB 總量以 UTF-8 位元組計（R30 verify 第 13 列：`String.count` 對 300 行 × 400 個 CJK 字放行 288 KB）。
    func testDisplaySafeErrorMultilineTotalCapIsBytes() {
        struct Raw: Error, CustomStringConvertible { var description: String { Array(repeating: String(repeating: "測", count: 400), count: 300).joined(separator: "\n") } }
        let out = displaySafeErrorMultiline(Raw(), prefix: "Error: ")
        XCTAssertLessThanOrEqual(out.utf8.count, 96_000 + 3 * 400 + 64, "總量 \(out.utf8.count) bytes")
        XCTAssertTrue(out.contains("……（截斷：共 300 行）"), out.suffix(40).description)
    }

    /// `describe` 對 NSError 只附**檔名**、暫存檔不附（R30 verify 第 20 列：R30 附絕對路徑——使用者名稱與家目錄進 MCP payload；
    /// `moveItem` 失敗時 `NSFilePathErrorKey` 帶的是 atomicWrite 的暫存檔，附了就把 #146 G3 從另一把鑰匙打開）。
    func testDescribeAppendsFileNameNotPathAndSkipsAtomicWriteTemps() throws {
        let path = "/Users/someone/.akashic/entities/aa\u{200B}bb.yaml"
        let e = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError, userInfo: [NSFilePathErrorKey: path, NSLocalizedDescriptionKey: "拒絕存取。"])
        let d = ErrorDisplay.describe(e)
        XCTAssertEqual(d, "拒絕存取。（檔案：aa\u{200B}bb.yaml）")
        XCTAssertFalse(d.contains("/Users/"), d)
        XCTAssertEqual(displaySafeErrorText(e), "拒絕存取。（檔案：aa\\u{200B}bb.yaml）", "呼叫端逃一次")
        let quoted = NSError(domain: NSCocoaErrorDomain, code: 257, userInfo: [NSFilePathErrorKey: path, NSLocalizedDescriptionKey: "“aa\u{200B}bb.yaml” 無法開啟。"])
        XCTAssertEqual(ErrorDisplay.describe(quoted), "“aa\u{200B}bb.yaml” 無法開啟。", "描述已含檔名時不重複附")
        let tmp = NSError(domain: NSCocoaErrorDomain, code: 516, userInfo: [NSFilePathErrorKey: "/tmp/x/.entity.yaml.tmp-DEADBEEF", NSLocalizedDescriptionKey: "移動失敗。"])
        XCTAssertEqual(ErrorDisplay.describe(tmp), "移動失敗。", "atomicWrite 暫存檔名不附")
        // **真的** Foundation 錯誤（R32；R31 verify 第 13 列：R31 的 fixture 是人工合成的 localizedDescription，而 Foundation 對 moveItem 失敗
        // 自己就把暫存檔名引在本地化文字裡——`isAtomicWriteTemp` 在它具名的那個情境零作用）
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-r32-\(UUID().uuidString)")
        // setup 用 `try` 不用 `try?`、失敗用 `XCTUnwrap` 不用 `real!`（R33；R32 verify 第 23／27 列：setup 靜默失敗時 moveItem 以**別的**錯誤失敗、
        // 兩個斷言照樣過；Foundation 對既存目的檔改成覆蓋時 `real!` 是整個 xctest 程序崩潰，不是一個測試紅）。斷言 code 516 釘住「真的是那個情境」。
        // **本地化依賴**：遮罩靠 Foundation 的本地化文字逐字引用檔名（macOS 27 英文／中文都引）；換一個不引檔名的 locale 這條斷言會紅——那是產品的
        // 邊界不是測試的：`describe` 只在 `NSFilePathErrorKey` 的檔名出現在文字裡時才遮得到。
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let temp = dir.appendingPathComponent(".entity.yaml.tmp-DEADBEEF"); let dest = dir.appendingPathComponent("entity.yaml")
        try "x".write(to: temp, atomically: false, encoding: .utf8); try "y".write(to: dest, atomically: false, encoding: .utf8)
        var caught: Error?
        do { try FileManager.default.moveItem(at: temp, to: dest) } catch { caught = error }
        let real = try XCTUnwrap(caught, "moveItem 對既存目的檔應失敗（516）——Foundation 行為變了就紅，不是 crash")
        XCTAssertEqual((real as NSError).code, 516, "\(real)")
        let described = ErrorDisplay.describe(real)
        XCTAssertFalse(described.contains("DEADBEEF"), "暫存檔名從 localizedDescription 漏出：\(described)")
        XCTAssertTrue(described.contains("（atomicWrite 暫存檔）"), described)
        XCTAssertTrue(ErrorDisplay.isAtomicWriteTemp(".a.yaml.tmp-1"))
        XCTAssertFalse(ErrorDisplay.isAtomicWriteTemp("a.tmp-1"))
    }

    /// CLI 頂層對非 ArgumentParser 錯誤的載體：文字＝`displaySafeErrorText`（逃一次、有界），型別自帶消毒（頂層 sink 只截）。
    func testTopLevelCarrierEscapesOnce() {
        struct Raw: Error, CustomStringConvertible { var description: String { "line\u{200B}1\nline\u{7}2" } }
        let c = ErrorDisplay.EscapedOnce(Raw())
        XCTAssertEqual(c.description, "line\\u{200B}1\nline\\u{0007}2")
        XCTAssertTrue((c as Error) is SanitizedErrorDescription)
        XCTAssertEqual(displaySafeErrorMultiline(c, prefix: "Error: "), displaySafeErrorMultiline(Raw(), prefix: "Error: "), "包一層不改變輸出、不二次逃")
        XCTAssertEqual(ErrorDisplay.EscapedOnce(ServiceErrorProbe.make("x\\u{200B}")).description, "x\\u{200B}", "自帶消毒的原樣")
    }
}
