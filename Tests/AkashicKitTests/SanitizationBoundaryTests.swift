import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #554 R28（Claude 代裁 D80；R27 verify 第 1／2／3／4／5／11／12／14／15／16／17／19／27／28／29 列——十五列是同一個缺陷的十五個位置）：
/// **store 字串在最靠近它的地方逃脫一次，之後每一層只截**。R27 的守衛只掃八個生產者檔、以手寫清單為 scope、完全不掃 sink，於是
/// `invalidInput` 對已消毒的 what／why 再逃一次、quarantine 的 decode-error 支把 `StoreYAMLError` 已逃脫的片段再逃一次、`fmt` 疊到第三層、
/// MCP doctor／App／`update_person` 各自對已消毒的訊息再逃一次、而 `file` 欄位與 `unknownFieldFiles` 完全沒逃——四席與 DA 用真 binary
/// 逐一重現。這裡的守衛不靠檔案清單：擲出站點掃全樹、sink 以載體表達式掃全樹、建構點掃全樹、自帶消毒的錯誤型別由原始碼現算。
/// 用真的 `ServiceError`（AkashicMCPKit）當自帶消毒的樣本——它正是 R28 verify 第 1／7 列被 MCP 出口二次逃脫的那個型別。
enum ServiceErrorProbe { static func make(_ why: String) -> Error { ServiceError.invalid(why) } }

final class SanitizationBoundaryTests: XCTestCase {
    private static let repoRoot: URL = {
        var u = URL(fileURLWithPath: #filePath)
        while u.lastPathComponent != "Tests" { u.deleteLastPathComponent() }
        return u.deletingLastPathComponent()
    }()

    private static func swiftFiles(under dirs: [String]) throws -> [(path: String, text: String)] {
        var out: [(String, String)] = []
        for d in dirs {
            let e = try XCTUnwrap(FileManager.default.enumerator(at: repoRoot.appendingPathComponent(d), includingPropertiesForKeys: nil))
            for case let url as URL in e where url.pathExtension == "swift" {
                out.append((String(url.path.dropFirst(repoRoot.path.count + 1)), try String(contentsOf: url, encoding: .utf8)))
            }
        }
        return out.sorted { $0.0 < $1.0 }
    }

    /// 去掉每行的 `//` 註解（引號內的 `//` 不算——`"https://…"`）：doc comment 裡提到 `throw ServiceError.` 不是擲出站點（R29）。
    static func strippingLineComments(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { raw -> String in
            let line = String(raw)
            var quotes = 0; var i = line.startIndex
            while i < line.endIndex {
                if line[i] == "\"" { quotes += 1 }
                if line[i] == "/", line.index(after: i) < line.endIndex, line[line.index(after: i)] == "/", quotes % 2 == 0 {
                    return String(line[..<i]) + String(repeating: " ", count: line.distance(from: i, to: line.endIndex))   // 保留行長，行號不變
                }
                i = line.index(after: i)
            }
            return line
        }.joined(separator: "\n")
    }

    /// 從 `needle` 起、括號配平為止的一段（`throw X.y(…)`／`QuarantinedFile(…)`）。**needle 後面緊接的必須是 `(`**（R29；R28 的版本
    /// 對沒有括號的命中往後找到下一個 `(`，把兩個站點吞成一段）。
    private static func statements(in raw: String, needle: String) -> [(line: Int, body: String)] {
        let text = strippingLineComments(raw)
        var out: [(Int, String)] = []
        var search = text.startIndex
        while let r = text.range(of: needle, range: search..<text.endIndex) {
            var open = r.upperBound
            if needle.hasSuffix("(") {
                open = text.index(before: r.upperBound)   // needle 自己帶 `(`（`invalidInput(`／`ValidationError(`／`QuarantinedFile(`）——R29 NC4 抓到：第一版對這種 needle 一律跳過，三支守衛變成空掃描
            } else {
                while open < text.endIndex, text[open].isLetter || text[open].isNumber || text[open] == "_" || text[open] == "." { open = text.index(after: open) }
            }
            guard open < text.endIndex, text[open] == "(" else { search = r.upperBound; continue }
            var depth = 0; var i = open
            while i < text.endIndex {
                if text[i] == "(" { depth += 1 } else if text[i] == ")" { depth -= 1; if depth == 0 { break } }
                i = text.index(after: i)
            }
            let end = i < text.endIndex ? text.index(after: i) : text.endIndex
            out.append((text[..<r.lowerBound].filter { $0 == "\n" }.count + 1, String(text[r.lowerBound..<end])))
            search = end
        }
        return out
    }

    /// 一段裡的每個 `\(…)` 插值表達式（括號配平）。
    private static func interpolations(in s: String) -> [String] {
        var out: [String] = []
        var search = s.startIndex
        while let r = s.range(of: "\\(", range: search..<s.endIndex) {
            var depth = 1; var i = r.upperBound
            while i < s.endIndex, depth > 0 {
                if s[i] == "(" { depth += 1 } else if s[i] == ")" { depth -= 1 }
                if depth > 0 { i = s.index(after: i) }
            }
            out.append(String(s[r.upperBound..<i]))
            search = i < s.endIndex ? s.index(after: i) : s.endIndex
        }
        return out
    }

    /// 擲出端的插值要嘛 `displaySafeInvisible(`，要嘛是這張封閉表裡的程式構造值——**每一列都有理由**，不得依性質相似類推。
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
        ("^id\\.uuidString$", "UUID 文法固定"),
        ("^[A-Za-z_.!]+\\.count$", "Int"),
        ("^[A-Za-z_.!]+\\.rawValue$", "封閉列舉的 rawValue"),
        ("^scan\\.malformedLines\\.map\\(String\\.init\\)\\.joined\\(separator: \", \"\\)$", "行號 Int 清單"),
        // R29：ServiceError／ValidationError 的擲出站點納入掃描後多出的程式構造值
        ("^(idx|written|a\\.index|b\\.index|parts\\.count|report\\.\\w+\\.count)$", "Int"),
        ("^StoreKey\\.pattern$", "常量正則"),
        ("^field\\.uppercased\\(\\)$", "三個呼叫端字面欄位名之一（doi／pmid／isbn）"),
        ("^\\$0\\.value$", "writeFailed 的 value 由 displaySafeError 產出（唯一命中：index rebuild 失敗那一句）"),
        ("^confirmWriteFailed\\.keys\\.sorted\\(\\)\\.joined\\(separator: \"、\"\\)$", "鍵在插入時已 displaySafe"),
        ("^(WorkType|VenueType|EntityKind)\\.allCases[^\\n]*$", "封閉列舉現算"),
        ("^known\\.isEmpty \\? \"[^\"]*\" : displaySafeInvisible\\(known, max: \\d+\\)$", "三元：字面或已消毒"),
        ("^[A-Za-z_][\\w.!= \\n]*\\?\\s*\"(?:[^\"\\\\]|\\\\.)*\"\\s*:\\s*\"(?:[^\"\\\\]|\\\\.)*\"$", "三元：兩支都是字面（字面裡的插值由上一層檢查）"),
        ("^errors\\.map\\(\\\\\\.message\\)\\.joined\\(separator: \"；\"\\)$", "validate() 的訊息已由生產者消毒（D75 的守衛 InvisibleEscapeCoverageTests）"),
        ("^(rows|AmbiguityDisplayLimit\\.bytes / 1024|startLine\\.map\\(String\\.init\\) \\?\\? \"\\?\")$", "Int"),
        ("^breakdown$", "封閉 enum ResolutionTier 的 rawValue 與計數"),
        ("^(command|f\\.0)$", "本檔字面命令名／旗標名"),
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
        ("^Self\\.listCapped\\(both\\) \\{ displaySafeInvisible\\(\\$0, max: 120\\) \\}$", "逐項消毒"),
        ("^(report\\.writeFailed\\.keys|written)\\.sorted\\(\\)\\.map \\{ displaySafeInvisible\\(\\$0, max: 200\\) \\}\\.joined\\(separator: \", \"\\)$", "逐項消毒的 citekey 清單"),
        ("^writeFailed\\.map \\{ \"\\\\\\(displaySafeInvisible\\(\\$0\\.key, max: 200\\)\\)（\\\\\\(\\$0\\.value\\)）\" \\}\\.sorted\\(\\)\\.joined\\(separator: \"; \"\\)$", "key 逐項消毒、value 由 displaySafeError 產出（index rebuild 失敗那一句）"),
        ("^labels\\.sorted\\(\\)$", "knownLabels 的子集（EntityKind 的常量標籤）"),
    ]

    /// 一段 `f(a, b: c, …)` 的頂層引數（逗號在深度 0 才切；字串內的逗號不算）。
    static func topLevelArguments(of body: String) -> [String] {
        guard let open = body.firstIndex(of: "("), let close = body.lastIndex(of: ")") , open < close else { return [] }
        var out: [String] = []; var cur = ""; var depth = 0; var inString = false; var i = body.index(after: open)
        while i < close {
            let c = body[i]
            if inString {
                cur.append(c)
                if c == "\\" { i = body.index(after: i); if i < close { cur.append(body[i]) } }
                else if c == "\"" { inString = false }
            } else if c == "\"" { inString = true; cur.append(c) }
            else if "([{".contains(c) { depth += 1; cur.append(c) }
            else if ")]}".contains(c) { depth -= 1; cur.append(c) }
            else if c == ",", depth == 0 { out.append(cur); cur = "" }
            else { cur.append(c) }
            i = body.index(after: i)
        }
        if !cur.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(cur) }
        return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// 一個錯誤 enum 裡「描述端自己逃脫 payload」的 case（`unknownShapeLabel`／`shapeLabelHasValue`…：描述裡對 associated value
    /// `displaySafeInvisible`）。不變式是**每個 payload 恰逃一次**——住在擲出端或描述端由原始碼決定，守衛從描述現算、不寫清單。
    private static func descriptionEscapedCases(ofType type: String) throws -> Set<String> {
        var out: Set<String> = []
        for (_, text) in try swiftFiles(under: ["Sources"]) {
            guard let d = text.range(of: "enum \(type)") ?? text.range(of: "enum \(type):"), let e = text.range(of: "var errorDescription: String? {", range: d.upperBound..<text.endIndex) else { continue }
            var depth = 0; var i = text.index(before: e.upperBound); var body = ""
            while i < text.endIndex { let c = text[i]; body.append(c); if c == "{" { depth += 1 } else if c == "}" { depth -= 1; if depth == 0 { break } }; i = text.index(after: i) }
            for chunk in strippingLineComments(body).replacingOccurrences(of: "case let .", with: "case .").components(separatedBy: "case .").dropFirst() {   // `case let .x(a, b)` 也算
                guard let paren = chunk.firstIndex(where: { !$0.isLetter && !$0.isNumber && $0 != "_" }) else { continue }
                if chunk.contains("displaySafeInvisible(") { out.insert(String(chunk[..<paren])) }
            }
        }
        return out
    }

    private static func isProgramBuilt(_ e: String) -> Bool {
        programBuilt.contains(where: { e.range(of: $0.pattern, options: .regularExpression) != nil })
    }

    /// 擲出站點的兩層檢查：(1) 字串字面裡的每個插值要嘛 `displaySafeInvisible(`、要嘛程式構造值；(2) **不是字面的頂層引數**
    /// 要嘛 `displaySafeInvisible(`／`displaySafeError(`／`displaySafeErrorMultiline(`、要嘛 Int／Bool／enum case／程式構造值
    /// ——R28 只做 (1)，`what: relativePath`／`ValidationError(key)` 這種裸引數整個站點不含 `\(` 就掃不到（R28 verify 第 3／6／19／22 列）。
    private static func offenders(needle: String, dirs: [String], atLeast: Int) throws -> [String] {
        var out: [String] = []
        var scanned = 0
        let sanitizers = ["displaySafeInvisible(", "displaySafeError(", "displaySafeErrorMultiline("]
        let typeName = needle.replacingOccurrences(of: "throw ", with: "").split(separator: ".").first.map(String.init) ?? ""
        let escapedInDescription = try descriptionEscapedCases(ofType: typeName)
        for (path, text) in try swiftFiles(under: dirs) {
            for (line, body) in statements(in: text, needle: needle) {
                scanned += 1
                let caseName = String(body.dropFirst(needle.count).prefix { $0.isLetter || $0.isNumber || $0 == "_" })
                if escapedInDescription.contains(caseName) {
                    for arg in topLevelArguments(of: body) where sanitizers.contains(where: { arg.hasPrefix($0) }) {
                        out.append("\(path):\(line) \(caseName) 的描述已逃脫 payload，擲出端不得再逃：\(arg.prefix(60))")
                    }
                    continue
                }
                for e in interpolations(in: body) where !e.hasPrefix("displaySafeInvisible(") && !e.hasPrefix("displaySafeError(") {
                    if isProgramBuilt(e) { continue }
                    out.append("\(path):\(line) \\(\(e))")
                }
                for arg in topLevelArguments(of: body) {
                    var value = arg
                    if let r = value.range(of: #"^[A-Za-z_]\w*:\s*"#, options: .regularExpression) { value = String(value[r.upperBound...]) }
                    if value.hasPrefix("\"") { continue }                                   // 字面（插值由上一層檢查）
                    if sanitizers.contains(where: { value.hasPrefix($0) }) { continue }
                    if value.range(of: #"^([0-9_]+|true|false|nil|\.[A-Za-z]\w*(\(.*\))?)$"#, options: .regularExpression) != nil { continue }
                    if isProgramBuilt(value) { continue }
                    out.append("\(path):\(line) 裸引數：\(value.prefix(80))")
                }
            }
        }
        if scanned < atLeast { out.append("守衛只掃到 \(scanned) 個 `\(needle)` 站點（下限 \(atLeast)）——空掃描不是通過（R29 NC4）") }
        return out
    }

    /// StoreYAMLError 的描述自 R28 起在**擲出端**逐項消毒（YAML.swift 127 個站點、Provenance／AuthorshipCompleteness／PersonIdentityMigration）——
    /// R27 之前 YAML.swift 的檔頭自己寫著「約 50 個跨行 throw 站點未消毒，靠 sink 兜底」，而 sink 兜底就是第 1／27 列的二次逃脫。
    func testStoreYAMLErrorThrowSitesSanitizeStoreStrings() throws {
        let bad = try Self.offenders(needle: "throw StoreYAMLError.", dirs: ["Sources"], atLeast: 100)
        XCTAssertEqual(bad, [], bad.joined(separator: "\n"))
    }

    /// `ServiceError`（AkashicMCPKit）與 CLI 的 `ValidationError` 是 R28 verify 第 10／13／17／19／32 列的兩個洞：前者 140 個站點列舉式
    /// `displaySafe(`、描述「不再消毒」而 MCP 出口再逃一次；後者的 key／title／path 裸字串直接進 ArgumentParser 的終端輸出。
    /// 兩者自 R29 起與 StoreYAMLError 同一條規則：擲出端 `displaySafeInvisible`，描述只截，出口只截。
    func testServiceErrorAndValidationErrorThrowSitesSanitizeStoreStrings() throws {
        let bad = try Self.offenders(needle: "throw ServiceError.", dirs: ["Sources/AkashicMCPKit", "Sources/akashic-mcp"], atLeast: 100)
            + Self.offenders(needle: "throw ValidationError(", dirs: ["Sources/akashic"], atLeast: 30)
        XCTAssertEqual(bad, [], bad.joined(separator: "\n"))
    }

    /// Error → 文字只有一個入口（`ErrorDisplay.describe`）；其餘每個把 `Error` 變成字串的地方都走 `displaySafeError`／`displaySafeErrorMultiline`
    /// （R28 verify 第 1／5／7／15／26／30 列：MCP Server、Main、App 六個 errorMessage、CLI 五個 ValidationError 包裝、PersonIdentityMigration、
    /// ProvenanceMigration、StoreIncarnation、ZoteroImporter、EnrichFromZotero 各自 `errorDescription ?? "\(error)"` 再逃一次或不逃）。
    /// 掃描範圍是 store 與其面；`TractatusDocs`／`tractatus-doc`／`AkashicProposition` 不在內——它們處理的是文件 corpus 與命題，
    /// 不碰 store 字串（範圍記在 R28 verify 第 24 列的裁決）。
    func testErrorToTextEntriesGoThroughTheSingleEntryPoint() throws {
        let entry = try NSRegularExpression(pattern: #"as\?\s+LocalizedError\)\?\.errorDescription|String\(describing:\s*(error|e|err|failure)\)|\b(error|e|err|failure|underlying|schemaError)\.(localizedDescription|errorDescription)\b"#)
        var offenders: [String] = []
        for (path, text) in try Self.swiftFiles(under: ["Sources"]) {
            if path.hasPrefix("Sources/TractatusDocs/") || path.hasPrefix("Sources/tractatus-doc/") || path.hasPrefix("Sources/AkashicProposition/") { continue }
            if path == "Sources/AkashicCore/ErrorDisplay.swift" { continue }
            for (n, raw) in Self.strippingLineComments(text).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let line = String(raw)
                guard entry.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil else { continue }
                if String(text.split(separator: "\n", omittingEmptySubsequences: false)[n]).contains("display-safe-exempt:") { continue }
                offenders.append("\(path):\(n + 1) \(line.trimmingCharacters(in: .whitespaces).prefix(100))")
            }
        }
        XCTAssertEqual(offenders, [], offenders.joined(separator: "\n"))
        let expected: [(file: String, needle: String, count: Int)] = [
            ("Sources/akashic-mcp/Server.swift", "text: \"Error: \\(displaySafeErrorMultiline(error))\"", 1),
            ("Sources/akashic-mcp/Main.swift", "displaySafeErrorMultiline(error)", 1),
            ("Sources/AkashicAppKit/EntryViews.swift", "errorMessage = displaySafeErrorMultiline(error)", 3),
            ("Sources/AkashicAppKit/AdjudicationViews.swift", "errorMessage = displaySafeErrorMultiline(error)", 3),
            ("Sources/AkashicAppKit/GraphView.swift", "loadError = displaySafeErrorMultiline(error)", 2),
            ("Sources/AkashicAppKit/AppState.swift", "underlying: displaySafeError(error, max: 300)", 1),
            ("Sources/akashic/LibraryCommands.swift", "throw ValidationError(displaySafeErrorMultiline(", 2),
            ("Sources/akashic/Commands.swift", "throw ValidationError(displaySafeErrorMultiline(error))", 1),
            ("Sources/akashic/CLI.swift", "throw ValidationError(displaySafeErrorMultiline(error))", 1),
            ("Sources/akashic/EnrichCommand.swift", "throw ValidationError(displaySafeErrorMultiline(e))", 1),
            ("Sources/AkashicZoteroImport/ZoteroImporter.swift", "report.writeFailed[entry.citekey] = displaySafeError(error, max: 512)", 1),
            ("Sources/akashic/EnrichFromZoteroCommand.swift", "failed[a.citekey] = displaySafeError(error, max: 512)", 1),
            ("Sources/AkashicStoreIO/PersonIdentityMigration.swift", "let reason = displaySafeError(error, max: 512)", 4),
            ("Sources/AkashicStoreIO/ProvenanceMigration.swift", "reason: displaySafeError(error, max: 512)", 2),
            ("Sources/AkashicStoreIO/StoreIncarnation.swift", "why: displaySafeError(error, max: 300)", 1),
            ("Sources/AkashicStoreIO/DivergenceResolve.swift", "+ displaySafeError(error, max: 512))", 6),
        ]
        for (file, needle, count) in expected {
            let text = try String(contentsOf: Self.repoRoot.appendingPathComponent(file), encoding: .utf8)
            XCTAssertEqual(text.components(separatedBy: needle).count - 1, count, "\(file) 的 Error → 文字入口：\(needle)")
        }
    }

    /// `StoreIOError.invalidInput` 的 what／why 在擲出端消毒、描述只截（R27 verify 第 5／12／14 列：R27 把描述換成 displaySafeInvisible，
    /// 與同一個 enum 另外兩格相反，`fmt` 疊到第三層）。`assertNoErrors` 的 why 是 validate() 的訊息——不含 `\(`，本掃描看不到，由 D75 的守衛管。
    func testInvalidInputThrowSitesSanitizeStoreStrings() throws {
        let bad = try Self.offenders(needle: "StoreIOError.invalidInput(", dirs: ["Sources"], atLeast: 5)
        XCTAssertEqual(bad, [], bad.joined(separator: "\n"))
        let desc = try String(contentsOf: Self.repoRoot.appendingPathComponent("Sources/AkashicStoreIO/LibraryStore.swift"), encoding: .utf8)
        XCTAssertTrue(desc.contains("\\(displaySafeClipOnly(what, max: 960)) 無效：\\(displaySafeClipOnly(why, max: 3_200))"), "invalidInput 的描述要只截，且上限是輸出 scalar（輸入的 8 倍；R28 verify 第 23 列）")
    }

    /// 已消毒載體（`ValidationIssue.message`／`QuarantinedFile.reason`／`Failure.reason`／`WriteFailure.error`）的 sink 只截：
    /// 對這些表達式再跑 `displaySafe(`／`displaySafeInvisible(` 就是二次逃脫（R27 verify 第 2／4／11／16／17 列）。要例外（原始載體，
    /// 例如 BibExport 的 message 只含欄位名常量）在同一行寫 `display-safe-exempt: 未消毒`。另有一張封閉表：R27 verify 具名的每個 sink 都要真的是 clip-only。
    func testSanitizedCarrierSinksOnlyClip() throws {
        let carrier = try NSRegularExpression(pattern: #"displaySafe(Invisible)?\(\s*(\$0\.message|issue\.message|\$0\.reason|f\.reason|reason|f\.error|\$0\.error)\b"#)
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
            // R29：writeFailed／failures／App 的 underlying 由 displaySafeError 產出，sink 只截（R28 verify 第 9／18／34 列）
            ("Sources/AkashicMCPKit/AkashicService.swift", "(displaySafe($0.key, max: 200), displaySafeClipOnly($0.value, max: 512))"),
            ("Sources/akashic/Commands.swift", "displaySafeClipOnly(report.writeFailed[key]!, max: 4_096)"),
            ("Sources/akashic/DivergenceCommands.swift", "displaySafeClipOnly(f, max: 4_096)"),
            ("Sources/akashic/EnrichFromZoteroCommand.swift", "displaySafeClipOnly(e, max: 1_600)"),
            ("Sources/AkashicAppKit/AppState.swift", "displaySafeClipOnly(underlying, max: 2_400)"),
            ("Sources/AkashicAppKit/EntryViews.swift", "displaySafeClipOnly(failure, max: 2_400)"),
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

    /// 每個 `QuarantinedFile(`／`Failure(file:` 建構點的 reason 都在建構時消毒——「sink 只截」的正確性完全靠這件事（R27 verify 第 15 列的鄰接不變式）。
    func testQuarantineAndFormatFailureReasonsAreSanitizedAtConstruction() throws {
        var offenders: [String] = []
        var scanned = 0
        for (path, text) in try Self.swiftFiles(under: ["Sources"]) {
            for needle in ["QuarantinedFile(", "Failure(file:"] {
                for (line, body) in Self.statements(in: text, needle: needle) {
                    scanned += 1
                    guard let r = body.range(of: "reason:") else { offenders.append("\(path):\(line) 沒有 reason:"); continue }
                    let arg = String(body[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let sanitizers = ["displaySafeInvisible(", "displaySafeError(", "describe(error)"]
                    if arg.hasPrefix("\"") {
                        // 字串字面量：每個插值要嘛消毒、要嘛是 UUID（文法固定）、要嘛是封閉表裡的程式構造值（`StoreKey.pattern`）
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
        XCTAssertTrue(cf.contains("private static func describe(_ error: Error) -> String { displaySafeError(error, max: 512) }"), "CanonicalFormat.describe 要走 displaySafeError")
    }

    /// 自帶消毒的錯誤型別由 **protocol conformance** 宣告、由原始碼全樹現算（R29 D81；R28 verify 第 5／14／37／40 列：R28 的 `is` 鏈住在
    /// AkashicStoreIO、掃兩個目錄，`ServiceError`／`IndexError`／`QueryError`／`GraphError`／App 與 TractatusDocs 的錯誤都在鏈外）。
    /// 三件事一起釘：描述裡有逃脫的型別**必須** conform；conform 而描述不逃脫的只有一張封閉表（`ServiceError`：140 個擲出站點消毒，
    /// 描述原樣回傳）；conform 的型別描述裡不得再有列舉式 `displaySafe(`。
    func testSelfSanitizingErrorTypesAreAClosedList() throws {
        var found: Set<String> = []
        var conforming: Set<String> = []
        var enumerated: [String] = []
        // 宣告的繼承列可以跨行（`PropositionError:\n    Error,\n    Equatable,…`）——header 從宣告行收到第一個 `{` 為止
        let declRe = try NSRegularExpression(pattern: #"^(\s*)(?:public |internal |fileprivate |private )?(?:indirect )?(enum|struct|class|extension) (\w+)\b"#)
        for (path, text) in try Self.swiftFiles(under: ["Sources"]) {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            func indent(_ s: String) -> Int { s.prefix { $0 == " " }.count }
            func header(from k: Int) -> String {
                var h = ""; var m = k
                while m < lines.count { h += lines[m]; if lines[m].contains("{") { break }; m += 1 }
                return String(h[..<(h.firstIndex(of: "{") ?? h.endIndex)])
            }
            func isErrorType(_ name: String, _ h: String) -> Bool {
                name.hasSuffix("Error") || h.range(of: #"\bError\b|\bLocalizedError\b"#, options: .regularExpression) != nil
            }
            func decl(above k: Int, indent target: Int) -> (name: String, line: Int, header: String)? {
                var m = k
                while m >= 0 {
                    let l = lines[m]
                    if indent(l) == target, let r = declRe.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)) {
                        return (String(l[Range(r.range(at: 3), in: l)!]), m, header(from: m))
                    }
                    m -= 1
                }
                return nil
            }
            func qualified(_ i: Int, indent mine: Int) throws -> (name: String, isError: Bool) {
                let d1 = try XCTUnwrap(decl(above: i, indent: mine - 4), "\(path):\(i + 1) 找不到型別宣告")
                let isErr = isErrorType(d1.name, d1.header)
                if mine - 4 > 0, let d0 = decl(above: d1.line, indent: mine - 8) { return (d0.name + "." + d1.name, isErr) }
                return (d1.name, isErr)
            }
            for (i, line) in lines.enumerated() {
                if let r = declRe.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)), header(from: i).contains("SanitizedErrorDescription") {
                    let name = String(line[Range(r.range(at: 3), in: line)!])
                    let mine = indent(line)
                    if mine > 0, let d0 = decl(above: i - 1, indent: mine - 4) { conforming.insert(d0.name + "." + name) } else { conforming.insert(name) }
                }
                guard line.contains("var errorDescription: String? {") || line.contains("var description: String {") else { continue }
                var depth = 0; var j = i; var body = ""
                loop: while j < lines.count {
                    for c in lines[j] { if c == "{" { depth += 1 } else if c == "}" { depth -= 1; if depth == 0 { break loop } } }
                    body += (lines[j].components(separatedBy: "//").first ?? "") + "\n"; j += 1
                }
                guard body.contains("displaySafe") else { continue }
                let (name, isError) = try qualified(i, indent: indent(line))
                guard isError else { continue }   // 值型別的 description（UnprojectableReason 那類）不是錯誤，protocol 對它無定義
                found.insert(name)
                if body.contains("displaySafe(") { enumerated.append("\(path) \(name) 的描述仍有列舉式 displaySafe(") }
            }
        }
        let escapeAtThrow: Set<String> = ["ServiceError"]   // 封閉表：描述原樣回傳、消毒在 140 個擲出站點（testServiceErrorAndValidationErrorThrowSitesSanitizeStoreStrings）
        XCTAssertEqual(found.subtracting(conforming), [], "描述自帶消毒但沒有宣告 SanitizedErrorDescription：\(found.subtracting(conforming).sorted())")
        XCTAssertEqual(conforming.subtracting(found), escapeAtThrow, "宣告了 SanitizedErrorDescription 但描述不逃脫、又不在擲出端消毒的封閉表裡：\(conforming.subtracting(found).subtracting(escapeAtThrow).sorted())；封閉表裡的型別必須 conform")
        XCTAssertEqual(enumerated, [], enumerated.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(conforming.count, 17, "全樹的自帶消毒型別：\(conforming.sorted())")
        let helper = try String(contentsOf: Self.repoRoot.appendingPathComponent("Sources/AkashicCore/ErrorDisplay.swift"), encoding: .utf8)
        XCTAssertTrue(helper.contains("error is SanitizedErrorDescription"), "isSelfSanitizing 要以 protocol 判，不是 is 鏈")
        XCTAssertFalse(FileManager.default.fileExists(atPath: Self.repoRoot.appendingPathComponent("Sources/AkashicStoreIO/ErrorDisplay.swift").path), "R28 的 StoreIO 副本要刪掉——兩份會分岔")
    }

    /// 多行入口（MCP Server／Main／App／CLI）：自帶消毒的走 `displaySafeAssembled`（只截、合法反斜線原樣），其餘逐行逃一次。
    func testDisplaySafeErrorMultilineEscapesOnceAndKeepsRegexConstants() {
        struct Raw: Error, CustomStringConvertible { var description: String { "line\u{7}1\nline\u{200B}2" } }
        let svc = ServiceErrorProbe.make("key「\(displaySafeInvisible("Ga\u{200B}mma", max: 80))」不符合 \\A[a-z0-9]+\\z\n第二行 \(displaySafeInvisible("\u{7}", max: 8))")
        let s = displaySafeErrorMultiline(svc)
        XCTAssertTrue(s.contains("Ga\\u{200B}mma"), s)
        XCTAssertTrue(s.contains("\\A[a-z0-9]+\\z"), "合法反斜線常量要原樣：\(s)")
        XCTAssertTrue(s.contains("第二行 \\u{0007}"), s)
        XCTAssertFalse(s.contains("\\u{005C}"), "二次逃脫：\(s)")
        let r = displaySafeErrorMultiline(Raw())
        XCTAssertEqual(r, "line\\u{0007}1\nline\\u{200B}2", r)
    }

    /// 截點退讓只認半截逃脫序列，真反斜線常量不動；`displaySafeAssembled` 完全不受影響（R28 verify 第 8／29／36 列：R28 把退讓寫在
    /// `displaySafe` 裡、以 `!escapingBackslash` 當前件，CLI 全域出口的一行 406 scalar 被砍到 41、`\A…\z` 被吃掉）。
    func testClipBackoffKeepsTrueBackslashConstantsAndLeavesAssembledAlone() {
        let long = "\\A[a-z0-9]+\\z " + String(repeating: "x", count: 500)
        let assembled = displaySafeAssembled(long, maxLineLength: 400)
        XCTAssertTrue(assembled.hasPrefix("\\A[a-z0-9]+\\z "), assembled.prefix(40).description)
        XCTAssertGreaterThan(assembled.count, 380, "一行要留到上限，不是退到最後一個反斜線：\(assembled.count)")
        let clipped = displaySafeClipOnly(long, max: 400)
        XCTAssertTrue(clipped.hasPrefix("\\A[a-z0-9]+\\z "), clipped.prefix(40).description)
        XCTAssertGreaterThan(clipped.count, 380, clipped.count.description)
        let tailZ = String(repeating: "x", count: 398) + "\\z" + "yyyy"
        XCTAssertTrue(displaySafeClipOnly(tailZ, max: 400).hasPrefix(String(repeating: "x", count: 398) + "\\z"), "`\\z` 不是半截逃脫序列，留著")
        let tailU = String(repeating: "x", count: 397) + "\\u{20" + "0B}yy"
        XCTAssertTrue(displaySafeClipOnly(tailU, max: 400).hasPrefix(String(repeating: "x", count: 397) + "…"), "`\\u{20` 是半截，退到反斜線之前")
    }

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

    /// 只截不逃的截點不得落在 `\u{…}` 中間（R27 verify DA 第 19 列：pad 7 時輸出以裸反斜線結尾）。
    func testClipOnlyNeverCutsInsideAnEscape() {
        for pad in 0..<10 {
            let s = String(repeating: "A", count: pad) + String(repeating: "\\u{200B}", count: 70)   // pad 在前才會把截點推進逃脫序列（NC1 第一版 pad 在後、70×8 對齊 512、永遠切在邊界）
            let out = displaySafeClipOnly(s, max: 512)
            XCTAssertTrue(out.hasSuffix("…（已截斷）"), out)
            let body = String(out.dropLast("…（已截斷）".count))
            XCTAssertFalse(body.hasSuffix("\\"), "裸反斜線結尾（pad \(pad)）：\(body.suffix(12))")
            if let open = body.range(of: "\\u{", options: .backwards) {
                XCTAssertTrue(body[open.upperBound...].contains("}"), "截在逃脫序列中間（pad \(pad)）：\(body.suffix(12))")
            }
        }
        XCTAssertEqual(displaySafeClipOnly("\\u{200B}AB", max: 100), "\\u{200B}AB", "不截時原樣")
        XCTAssertEqual(displaySafe(String(repeating: "\\", count: 3), max: 2), "\\u{005C}\\u{005C}…（已截斷）", "逃脫自己的路徑照舊")
    }
}
