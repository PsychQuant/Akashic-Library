import XCTest
import Foundation

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

    func testNoUnsanitisedStoreStringReachesUserVisibleOutput() throws {
        var violations: [String] = []

        for url in scannedFiles {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                XCTFail("讀不到 \(url.lastPathComponent)——掃描範圍若失效，這個測試會變成空跑")
                continue
            }
            let name = url.lastPathComponent
            for (idx, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let l = String(line)
                // 註解行不算輸出
                if l.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                if l.contains("display-safe-exempt:") { continue }
                // 只看真正的輸出面：print(…) 與 JSON dict 的字串值
                let isSink = l.contains("print(") || l.contains("jsonString(")
                    || l.contains("d[\"") || l.contains("result[\"") || l.contains("\": ")
                guard isSink else { continue }
                // switch 的 `case "x": stmt` 不是 dict 值——冒號後是語句。
                // **誠實邊界**：這也豁免了 case 行內的真 dict（如
                // `case .literal(let s): return ["literal": s]`），且短變數名值
                // 本就不含可比對 token——那類站點靠人工 + 功能測試釘住。
                if l.trimmingCharacters(in: .whitespaces).hasPrefix("case ") { continue }

                for expr in interpolations(in: l) + dictValues(in: l) {
                    guard taintedTokens.contains(where: { expr.contains($0) }) else { continue }
                    if expr.contains("displaySafe(") { continue }
                    // `.count` / `.isEmpty` 是數量不是內容；`!= nil` / `== nil` 是
                    // Bool 存在測試（如 hasJudgement）——都到不了內容本身
                    if expr.contains(".count") || expr.contains(".isEmpty") { continue }
                    if expr.contains("!= nil") || expr.contains("== nil") { continue }
                    // 多行 closure 的開頭行（`… { author -> T in`）：實際輸出在
                    // 後續行——closure 體若是 `case` 行則落入上方 case 豁免的
                    // 誠實邊界，否則仍會被逐行掃到
                    if expr.hasSuffix(" in") || expr.hasSuffix("{") { continue }
                    violations.append("\(name):\(idx + 1)  \(expr)")
                }
            }
        }

        XCTAssertTrue(violations.isEmpty, """
            有 \(violations.count) 條把 store 衍生字串未消毒送進使用者可見輸出的路徑：

            \(violations.joined(separator: "\n            "))

            修法二選一：
              1. 包上 displaySafe(…)——資料面用 max: 800，識別字用 max: 200
              2. 確定安全 → 同一行加 `// display-safe-exempt: <理由>`，把理由寫出來
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
