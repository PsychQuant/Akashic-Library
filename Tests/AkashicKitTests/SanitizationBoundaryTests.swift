import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #554 R28（Claude 代裁 D80；R27 verify 第 1／2／3／4／5／11／12／14／15／16／17／19／27／28／29 列——十五列是同一個缺陷的十五個位置）：
/// **store 字串在最靠近它的地方逃脫一次，之後每一層只截**。R27 的守衛只掃八個生產者檔、以手寫清單為 scope、完全不掃 sink，於是
/// `invalidInput` 對已消毒的 what／why 再逃一次、quarantine 的 decode-error 支把 `StoreYAMLError` 已逃脫的片段再逃一次、`fmt` 疊到第三層、
/// MCP doctor／App／`update_person` 各自對已消毒的訊息再逃一次、而 `file` 欄位與 `unknownFieldFiles` 完全沒逃——四席與 DA 用真 binary
/// 逐一重現。這裡的守衛不靠檔案清單：擲出站點掃全樹、sink 以載體表達式掃全樹、建構點掃全樹、自帶消毒的錯誤型別由原始碼現算。
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

    /// 從 `needle` 起、括號配平為止的一段（`throw X.y(…)`／`QuarantinedFile(…)`）。
    private static func statements(in text: String, needle: String) -> [(line: Int, body: String)] {
        var out: [(Int, String)] = []
        var search = text.startIndex
        while let r = text.range(of: needle, range: search..<text.endIndex) {
            guard let open = text[r.upperBound...].firstIndex(of: "(") else { break }
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
    ]

    private static func offenders(needle: String, dirs: [String]) throws -> [String] {
        var out: [String] = []
        for (path, text) in try swiftFiles(under: dirs) {
            for (line, body) in statements(in: text, needle: needle) {
                for e in interpolations(in: body) where !e.hasPrefix("displaySafeInvisible(") {
                    if programBuilt.contains(where: { e.range(of: $0.pattern, options: .regularExpression) != nil }) { continue }
                    out.append("\(path):\(line) \\(\(e))")
                }
            }
        }
        return out
    }

    /// StoreYAMLError 的描述自 R28 起在**擲出端**逐項消毒（YAML.swift 127 個站點、Provenance／AuthorshipCompleteness／PersonIdentityMigration）——
    /// R27 之前 YAML.swift 的檔頭自己寫著「約 50 個跨行 throw 站點未消毒，靠 sink 兜底」，而 sink 兜底就是第 1／27 列的二次逃脫。
    func testStoreYAMLErrorThrowSitesSanitizeStoreStrings() throws {
        let bad = try Self.offenders(needle: "throw StoreYAMLError.", dirs: ["Sources"])
        XCTAssertEqual(bad, [], bad.joined(separator: "\n"))
    }

    /// `StoreIOError.invalidInput` 的 what／why 在擲出端消毒、描述只截（R27 verify 第 5／12／14 列：R27 把描述換成 displaySafeInvisible，
    /// 與同一個 enum 另外兩格相反，`fmt` 疊到第三層）。`assertNoErrors` 的 why 是 validate() 的訊息——不含 `\(`，本掃描看不到，由 D75 的守衛管。
    func testInvalidInputThrowSitesSanitizeStoreStrings() throws {
        let bad = try Self.offenders(needle: "StoreIOError.invalidInput(", dirs: ["Sources"])
        XCTAssertEqual(bad, [], bad.joined(separator: "\n"))
        let desc = try String(contentsOf: Self.repoRoot.appendingPathComponent("Sources/AkashicStoreIO/LibraryStore.swift"), encoding: .utf8)
        XCTAssertTrue(desc.contains("\\(displaySafeClipOnly(what, max: 120)) 無效：\\(displaySafeClipOnly(why, max: 400))"), "invalidInput 的描述要只截")
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
            ("Sources/AkashicStoreIO/LibraryStore.swift", "無效：\\(displaySafeClipOnly(why, max: 400))"),
            ("Sources/AkashicMCPKit/AkashicService.swift", "\"message\": displaySafeClipOnly($0.message, max: 300)"),
            ("Sources/AkashicMCPKit/AkashicService.swift", "\"reason\": displaySafeClipOnly($0.reason, max: 512)"),
            ("Sources/akashic/CLI.swift", "displaySafeClipOnly($0.reason, max: 512)"),
            ("Sources/AkashicAppKit/Adjudication.swift", "displaySafeClipOnly(reason, max: 512)"),
            ("Sources/AkashicMCPKit/UpdatePerson.swift", "displaySafeClipOnly($0.message, max: 300)"),
            ("Sources/AkashicStoreIO/StoreMigration.swift", "displaySafeClipOnly($0, max: 300)"),
            ("Sources/akashic/FormatCommands.swift", "displaySafeClipOnly(f.reason, max: 300)"),
            ("Sources/AkashicStoreIO/DivergenceResolve.swift", "losses.map { displaySafeClipOnly($0, max: 300) }"),
            ("Sources/akashic/CreateEntryCommand.swift", "displaySafeClipOnly(f.error, max: 400)"),
            ("Sources/akashic/LibraryCommands.swift", "displaySafeClipOnly(f.error, max: 400)"),
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
        for (path, text) in try Self.swiftFiles(under: ["Sources"]) {
            for needle in ["QuarantinedFile(", "Failure(file:"] {
                for (line, body) in Self.statements(in: text, needle: needle) {
                    guard let r = body.range(of: "reason:") else { offenders.append("\(path):\(line) 沒有 reason:"); continue }
                    let arg = String(body[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let sanitizers = ["displaySafeInvisible(", "displaySafeError(", "describe(error)"]
                    if arg.hasPrefix("\"") {
                        // 字串字面量：每個插值要嘛消毒、要嘛是 UUID（文法固定）
                        let bad = Self.interpolations(in: arg).filter { e in !sanitizers.contains { e.hasPrefix($0) } && !e.hasSuffix(".uuidString") }
                        if !bad.isEmpty { offenders.append("\(path):\(line) reason 有未消毒插值：\(bad)") }
                    } else if !sanitizers.contains(where: { arg.hasPrefix($0) }) {
                        offenders.append("\(path):\(line) reason 不是字面量也不經消毒：\(arg.prefix(80))")
                    }
                }
            }
        }
        XCTAssertEqual(offenders, [], offenders.joined(separator: "\n"))
        let cf = try String(contentsOf: Self.repoRoot.appendingPathComponent("Sources/AkashicStoreIO/CanonicalFormat.swift"), encoding: .utf8)
        XCTAssertTrue(cf.contains("private static func describe(_ error: Error) -> String { displaySafeError(error, max: 512) }"), "CanonicalFormat.describe 要走 displaySafeError")
    }

    /// 自帶消毒的錯誤型別是封閉列舉，且由原始碼現算：AkashicCore／AkashicStoreIO 內 `errorDescription` 含 `displaySafe` 的型別集合＝
    /// `ErrorDisplay.isSelfSanitizing` 的 `is` 鏈；而那些描述裡不得有列舉式 `displaySafe(`（要嘛性質式、要嘛只截）。
    func testSelfSanitizingErrorTypesAreAClosedList() throws {
        var found: Set<String> = []
        var enumerated: [String] = []
        for (path, text) in try Self.swiftFiles(under: ["Sources/AkashicCore", "Sources/AkashicStoreIO"]) {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (i, line) in lines.enumerated() where line.contains("var errorDescription: String? {") {
                // 區塊：從這一行起括號配平
                var depth = 0; var j = i; var body = ""
                loop: while j < lines.count {
                    for c in lines[j] { if c == "{" { depth += 1 } else if c == "}" { depth -= 1; if depth == 0 { break loop } } }
                    body += (lines[j].components(separatedBy: "//").first ?? "") + "\n"; j += 1   // 去掉註解——AliasBudgetError 的註解提到 displaySafe
                }
                guard body.contains("displaySafe") else { continue }
                // 型別名：往上找縮排剛好少一層的宣告；它自己若非頂層，再往上找一層
                func indent(_ s: String) -> Int { s.prefix { $0 == " " }.count }
                func decl(above k: Int, indent target: Int) -> (name: String, line: Int)? {
                    var m = k
                    while m >= 0 {
                        let l = lines[m]
                        if indent(l) == target, let r = l.range(of: #"(enum|struct|class|extension) (\w+)"#, options: .regularExpression) {
                            return (String(l[r]).split(separator: " ")[1].description, m)
                        }
                        m -= 1
                    }
                    return nil
                }
                let mine = indent(line)
                let d1 = try XCTUnwrap(decl(above: i, indent: mine - 4), "\(path):\(i + 1) 找不到型別宣告")
                var name = d1.name
                if mine - 4 > 0, let d0 = decl(above: d1.line, indent: mine - 8) { name = d0.name + "." + name }
                found.insert(name)
                if body.contains("displaySafe(") { enumerated.append("\(path) \(name) 的描述仍有列舉式 displaySafe(") }
            }
        }
        let helper = try String(contentsOf: Self.repoRoot.appendingPathComponent("Sources/AkashicStoreIO/ErrorDisplay.swift"), encoding: .utf8)
        let re = try NSRegularExpression(pattern: #"error is ([A-Za-z_.]+)"#)
        let listed = Set(re.matches(in: helper, range: NSRange(helper.startIndex..., in: helper)).map { String(helper[Range($0.range(at: 1), in: helper)!]) })
        XCTAssertEqual(found, listed, "多了（描述自帶消毒但 helper 沒列）：\(found.subtracting(listed))；少了（helper 列了但描述不消毒）：\(listed.subtracting(found))")
        XCTAssertEqual(enumerated, [], enumerated.joined(separator: "\n"))
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
