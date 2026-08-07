import XCTest
import Foundation
@testable import AkashicCore

/// #28：**sink coverage 的機械守衛**。
///
/// 為什麼是掃原始碼而不是跑功能：`displaySafe` 的問題從來不是它本身有 bug，而是
/// **有人新增了一條沒接上它的輸出路徑**。#23 的 R11 → R12 → R13 三輪都在憑記憶補
/// sink、三輪都漏——漏的還一次比一次常用（第三輪漏的是 `akashic query`）。記憶枚舉
/// 贏不了「每次改動都可能新增一條路徑」，所以判準必須機械化。
///
/// 判準：CLI / MCP 的原始碼裡，任何把 **store 衍生字串**插值進輸出的位置，該表達式
/// 必須含 `displaySafe(`。要例外就在同一行寫 `// display-safe-exempt: <理由>`——
/// 逼人講出理由，而不是安靜跳過。
///
/// ## 守衛的涵蓋邊界（#141——誠實記錄「行級文字掃描」照不到的形狀）
///
/// 這是**行級的文字啟發式**，不是型別感知的資料流分析。以下形狀結構性地在它的
/// 視野外，靠人工 + 功能測試釘住，不是它的失效：
///
/// - **bare-`$0` 的 `.map { }`**（最大宗）：`load.residue.map { $0 }` 的 `$0` 不含
///   任何 tainted token，token 判準對它結構性失效。#149 verify 席 strip-all 實測
///   `AkashicService` 一檔 55 個消毒站點守衛只認 21——差額多是這一類。補它需要
///   element-type 或 receiver 上下文（`.map` 的來源是誰），不是另一條行級 regex。
/// - **key-family accessor**（`$0.key`/`p.key`/`lib.key`/`$0.path`）：`key` 不在
///   `taintedTokens`（只有 `citekey`/`personKey`/`libraryKey`）——因為 `key` 也是
///   大量 registry/config 常量 key 的名字，無腦入清單會誤中一片。
/// - **跨行 throw**：`throw StoreYAMLError.invalidField(` 在 N 行、payload 內插在
///   N+1 行——行級掃描看不到 N+1 行的 sink。約 50 個 StoreYAMLError 站點屬此，
///   靠輸出端 sink 兜底（#149 verify F5）。
/// - **switch `case` 短變數值**：`case .literal(let s): return ["literal": s]` 的
///   `s` 是短名、不含 token——那類站點靠人工消毒 + 功能測試。
///
/// **`testGuardCatchesStrippedSanitisation`（#141）是對這個侷限的補償**：它不宣稱
/// 守衛涵蓋每條路徑，而是量測「守衛確實在看真實的消毒站點」——拔光 displaySafe
/// 後守衛必須報大量違規（實測 78）。守衛退化成空洞會讓那個下限失守。完整的
/// 型別感知覆蓋屬另案（需要 SwiftSyntax 級的分析，非本測試的體量）。
final class DisplaySinkCoverageTests: XCTestCase {

    /// store 衍生（＝可能來自別的 binary / 別人 / Zotero 匯入的第三方內容）的識別字。
    /// `authors` 在列：entries 來自 `import-zotero`，而 Zotero 的資料來自出版商與網頁
    /// ——那不是使用者自撰內容。
    private let taintedTokens = [
        "citekey", ".title", ".name", ".reason", ".file",
        ".literal", "personKey", "libraryKey", "authors",
        // #76：divergence 的未信任內容（#133 起可由 LLM 經 MCP 寫入——來源面擴大）
        ".question", ".judgement", ".statement", "restsOn",
    ]

    /// 掃描範圍：使用者看得到輸出的兩層。App 層走型別投影（`displayFile` 等），
    /// 由 `AkashicAppKit` 的 `public extension` 保證，不在本掃描內。
    private var scannedFiles: [URL] {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AkashicKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let fm = FileManager.default
        var out: [URL] = []
        let cliDir = repoRoot.appendingPathComponent("Sources/akashic")
        if let files = try? fm.contentsOfDirectory(at: cliDir, includingPropertiesForKeys: nil) {
            out += files.filter { $0.pathExtension == "swift" }
        }
        out.append(repoRoot.appendingPathComponent("Sources/AkashicMCPKit/AkashicService.swift"))
        // #78-7：AkashicCore 的 decode 錯誤訊息會內插未信任的 YAML 值（#23 的前提：
        // 檔案內容未信任）——#127 verify M2 的 StoreVersion 案例正是這一類，當時
        // 手工修；機械守衛掃到之後這類洞在測試就會亮。akashic-mcp/ 同（#135 F5）。
        // #149 verify F1：QueryError/GraphError 的 errorDescription 同 #142 的病
        //（lookup miss 把 caller citekey 原樣回吐），但這兩個模組不在掃描面——
        // 一次 MCP 呼叫就能把 raw ESC 打進 LLM context。StoreIOError/ConfigError
        // 住 AkashicStoreIO 同理（#142 加的 throw StoreIOError 規則先前是死碼——
        // F4：該檔根本沒被讀）。
        for dir in ["Sources/AkashicCore", "Sources/akashic-mcp",
                    "Sources/AkashicQuery", "Sources/AkashicGraph",
                    "Sources/AkashicStoreIO"] {
            let d = repoRoot.appendingPathComponent(dir)
            if let files = try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil) {
                out += files.filter { $0.pathExtension == "swift" }
            }
        }
        return out
    }

    /// 抓出一行裡所有 `\( … )` 插值的內容（括號配對，處理巢狀）。
    private func interpolations(in line: String) -> [String] {
        var out: [String] = []
        let chars = Array(line)
        var i = 0
        while i < chars.count - 1 {
            if chars[i] == "\\" && chars[i + 1] == "(" {
                var depth = 0
                var j = i + 1
                var buf = ""
                while j < chars.count {
                    if chars[j] == "(" { depth += 1; if depth == 1 { j += 1; continue } }
                    if chars[j] == ")" { depth -= 1; if depth == 0 { break } }
                    buf.append(chars[j])
                    j += 1
                }
                out.append(buf)
                i = j
            }
            i += 1
        }
        return out
    }

    /// 抓出一行裡所有 `"key": <value>` 字典值表達式（#138 verify F2）。
    ///
    /// **插值不是唯一的 sink 形狀。** MCP 面的輸出走 JSON dict——值是裸表達式、
    /// 不經 `\( … )`，只掃插值的守衛對它整面全盲（mutation 實測：拔掉
    /// `displaySafe` 後 U+202E 逐字回流 LLM）。值的邊界用括號深度感知的逗號
    /// 切分——`displaySafe($0.file, max: 300)` 內部的逗號不是邊界。
    private func dictValues(in line: String) -> [String] {
        var out: [String] = []
        let chars = Array(line)
        var i = 0
        while i < chars.count - 2 {
            if chars[i] == "\"" && chars[i + 1] == ":" {
                var j = i + 2
                while j < chars.count && chars[j] == " " { j += 1 }
                var depth = 0
                var buf = ""
                while j < chars.count {
                    let c = chars[j]
                    if c == "(" || c == "[" || c == "{" { depth += 1 }
                    if c == ")" || c == "]" || c == "}" {
                        if depth == 0 { break }
                        depth -= 1
                    }
                    if c == "," && depth == 0 { break }
                    buf.append(c)
                    j += 1
                }
                out.append(buf)
                i = j
            }
            i += 1
        }
        return out
    }

    /// 對單一檔案的原始碼文字掃描違規（#141：抽成純函式，讓正常掃描與 strip-all
    /// 量測自測共用同一判準——meta-test 要能對「拔光 displaySafe 的 source」重跑）。
    func scanViolations(name: String, text: String) -> [String] {
        var violations: [String] = []
        do {
            let allLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (idx, line) in allLines.enumerated() {
                let l = String(line)
                // 前一行是否為 `case …:` 結尾（ConfigError 的 case/return 跨兩行——
                // #149 verify F2）。**往回跳過註解與空行**（#149 R2 F4：case 與
                // return 之間常夾說明註解——愈認真解釋為什麼要消毒，愈把守衛的
                // 回看擋掉；StoreIOError.invalidKey 正是這樣漏掉的）。
                var prevIsCase = false
                var k = idx - 1
                while k >= 0 {
                    let prev = allLines[k].trimmingCharacters(in: .whitespaces)
                    if prev.isEmpty || prev.hasPrefix("//") { k -= 1; continue }
                    prevIsCase = prev.hasPrefix("case ") && prev.hasSuffix(":")
                    break
                }
                // 註解行不算輸出
                if l.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                if l.contains("display-safe-exempt:") { continue }
                // 只看真正的輸出面：print(…) 與 JSON dict 的字串值
                let isSink = l.contains("print(") || l.contains("jsonString(")
                    || l.contains("d[\"") || l.contains("result[\"") || l.contains("\": ")
                    || l.contains("return \"") || l.contains("FileHandle.standard")
                // #78-7：error 構造點是**無條件** sink——payload 最終進 errorDescription
                // →使用者可見輸出，插值的任何內容（YAML 未知 key、原始值）都可疑，
                // 不看 token 清單（局部變數名抓不到）。安全的插值加 exempt 注記
                // #142：ServiceError/StoreIOError 的 throw 行同屬 error sink（caller
                // 輸入經 errorDescription 直達輸出）；errorDescription 的
                // `case … return "…"` 形狀也是——那正是 #142 的雙重盲區（不含
                // throw、又被 case 豁免跳過）。
                let caseReturn = (l.trimmingCharacters(in: .whitespaces).hasPrefix("case ")
                        && l.contains("return \""))
                    || (prevIsCase && l.trimmingCharacters(in: .whitespaces).hasPrefix("return \""))
                let isErrorSink = l.contains("throw StoreYAMLError")
                    || l.contains("throw StoreVersionError")
                    || l.contains("throw ServiceError")
                    || l.contains("throw StoreIOError")
                    || caseReturn
                guard isSink || isErrorSink else { continue }
                // switch 的 `case "x": stmt` 不是 dict 值——冒號後是語句（#138 F2）。
                // **誠實邊界**：這也豁免了 case 行內的真 dict（如
                // `case .literal(let s): return ["literal": s]`），且短變數名值
                // 本就不含可比對 token——那類站點靠人工 + 功能測試釘住。
                // error-sink 行不豁免——throw 行的插值無條件檢查優先於 case 形狀。
                if !isErrorSink,
                   l.trimmingCharacters(in: .whitespaces).hasPrefix("case ") { continue }

                for expr in interpolations(in: l) + dictValues(in: l) {
                    guard isErrorSink
                        || taintedTokens.contains(where: { expr.contains($0) }) else { continue }
                    if expr.contains("displaySafe(") { continue }
                    // `.count` / `.isEmpty` 是數量不是內容；`!= nil` / `== nil` 是
                    // Bool 存在測試（如 hasJudgement）——都到不了內容本身
                    if expr.contains(".count") || expr.contains(".isEmpty") { continue }
                    if expr.contains("!= nil") || expr.contains("== nil") { continue }
                    // MCP tool schema 的描述文字（`str("citekey")` 等）：schema
                    // builder 的引數是程式字面量、不是 store 衍生內容——合併掃描面
                    //（#78-7 akashic-mcp）與 dict 值抽取（#138 F2）後的交叉誤中
                    if expr.hasPrefix("str(\"") || expr.hasPrefix("strArray(\"")
                        || expr.hasPrefix(".string(\"") { continue }
                    // 多行 closure 的開頭行（`… { author -> T in`）：實際輸出在
                    // 後續行——closure 體若是 `case` 行則落入上方 case 豁免的
                    // 誠實邊界，否則仍會被逐行掃到
                    if expr.hasSuffix(" in") || expr.hasSuffix("{") { continue }
                    violations.append("\(name):\(idx + 1)  \(expr)")
                }
            }
        }
        return violations
    }

    func testNoUnsanitisedStoreStringReachesUserVisibleOutput() throws {
        var violations: [String] = []
        for url in scannedFiles {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                XCTFail("讀不到 \(url.lastPathComponent)——掃描範圍若失效，這個測試會變成空跑")
                continue
            }
            violations += scanViolations(name: url.lastPathComponent, text: text)
        }

        XCTAssertTrue(violations.isEmpty, """
            有 \(violations.count) 條把 store 衍生字串未消毒送進使用者可見輸出的路徑：

            \(violations.joined(separator: "\n            "))

            修法二選一：
              1. 包上 displaySafe(…)——資料面用 max: 800，識別字用 max: 200
              2. 確定安全 → 同一行加 `// display-safe-exempt: <理由>`，把理由寫出來
            """)
    }

    /// #141：**量測式自測**——守衛非空洞不能靠「有一條壞樣式抓得到」單點證明
    /// （那被 verify 席多次質疑：拔一個真實站點守衛卻全綠）。這裡把 verify 席手動
    /// 做的 strip-all 量測內建：拔光全部 `displaySafe(`，重掃 shipped source，
    /// 守衛**必須**報大量違規。若守衛的判準退化成永遠不報（token 清單被清空、
    /// isSink 判斷失效…），strip-all 也不會報 → 這個測試紅。
    ///
    /// 下限 20：verify 席實測單一 `AkashicService.swift` strip-all 就 21 站點
    /// （#149 F1 sweep），六模組全掃遠超此數。用保守下限釘住「守衛確實在看真實
    /// 消毒站點」，而非精確計數（精確數隨消毒站點增減、會變脆）。
    func testGuardCatchesStrippedSanitisation() throws {
        var stripped: [String] = []
        for url in scannedFiles {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // 移除 `displaySafe(` ＝ 模擬「拔掉全部消毒」：`displaySafe(citekey, max:200)`
            // → `citekey, max:200)`，掃描抽出的 `citekey` 是 tainted 且不含 displaySafe
            let mutated = text.replacingOccurrences(of: "displaySafe(", with: "")
            stripped += scanViolations(name: url.lastPathComponent, text: mutated)
        }
        XCTAssertGreaterThanOrEqual(stripped.count, 20, """
            拔光 displaySafe 後守衛只報 \(stripped.count) 條——守衛判準可能已退化成
            接近空洞（token 清單、isSink 判斷或抽取器失效）。shipped code 有遠超 20
            個消毒站點，strip-all 應報大量違規。
            """)
    }

    /// 守衛自身要可證偽：掃描範圍不得為空，判準不得永遠成立。
    func testGuardItselfIsNotVacuous() throws {
        XCTAssertGreaterThanOrEqual(scannedFiles.count, 4, "掃描範圍萎縮＝守衛失效")
        // 判準對已知的壞樣式必須成立
        let bad = #"print("\(summary.citekey)\t\(summary.title)")"#
        let exprs = interpolations(in: bad)
        XCTAssertEqual(exprs.count, 2)
        XCTAssertTrue(exprs.allSatisfy { e in
            taintedTokens.contains { e.contains($0) } && !e.contains("displaySafe(")
        }, "判準抓不到已知的壞樣式")
        // dict-value 形狀（#138 verify F2 的 mutation 靶）：值是裸表達式、無插值
        let badDict = #""question": d.question,"#
        let vals = dictValues(in: badDict)
        XCTAssertEqual(vals, ["d.question"], "dict 值抽取失效：\(vals)")
        // 消毒後同形狀必須通過；內部逗號不得被當成值邊界
        let goodDict = #""question": displaySafe(d.question, max: 400),"#
        XCTAssertEqual(dictValues(in: goodDict), ["displaySafe(d.question, max: 400)"])
    }
}

/// #139 verify F2 的行為面 regression：contacts 的 mapping key 來自檔案，
/// 它進 errorDescription 前必須被消毒——掃描守衛管的是原始碼形狀，這條管行為。
extension DisplaySinkCoverageTests {
    func testContactsDirtyKeyDoesNotLeakRawBytesIntoError() {
        // 裸控制字元進不了 YAML（libyaml reader 先擋）——真正的注入路徑是
        // 雙引號的 \u escape，parser 在 reader 檢查**之後**解碼（#144 verify 同發現）
        let yaml = """
        person:
        id: 33333333-4444-5555-6666-777777777777
        key: dirty-contact
        names:
        - D
        profile:
          contacts:
            "email\\u001B[31mEVIL":
              value: not-a-sequence
        """
        XCTAssertThrowsError(try PersonYAML.decode(yaml)) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertFalse(msg.contains("\u{1B}"),
                           "原始 ESC 不得進 errorDescription：\(msg.debugDescription)")
            XCTAssertTrue(msg.contains("u{001B}") || msg.contains("EVIL"),
                          "消毒後仍要可辨認：\(msg)")
        }
    }
}
