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

    /// 掃描範圍是**封閉列舉**（見 `scannedDirs` 與下方兩個個別加入的路徑），不是
    /// 「使用者看得到輸出的各層」——那個說法在 #158 第一版寫過，是**假的**，這裡
    /// 記著避免再寫回去。
    ///
    /// **含 `AkashicAppKit`**（#155）：App 的 error 型別（Adjudication／AppState／
    /// FileWatcher）同樣 echo store 衍生值，威脅模型比 MCP-直達-LLM 弱（顯示在
    /// SwiftUI 而非灌進 context），但同 bug class。
    ///
    /// **不含 `AkashicApp/Sources/`——那才是真正的使用者顯示層，而且有 10 處裸綁**
    /// （#158 verify 158-1 實測）。它是 XcodeGen 專案、不是 SwiftPM target
    /// （`Package.swift` 對它零引用，`swift build` 從不編譯它）。把它加進掃描清單
    /// **也照樣零違規**——因為 `isSink` 只認 `print(` / `jsonString(` / `d["` /
    /// `result["` / `": ` / `return "` / `FileHandle.standard`，SwiftUI 的 `Text(` /
    /// `Label(` / `Button(` / `.alert(` 一個都不在裡面。加目錄不等於加保護。
    ///
    /// 舊註解說 App 層「走型別投影（`displayFile` 等）由 `AkashicAppKit` 的
    /// `public extension` 保證」——**那也是假的**：`ResolutionCandidate` 根本沒有
    /// `displayLiteral` / `displayPersonKey`，`AdjudicationViews.swift:20` 就裸綁著
    /// 這兩個（而 21 行用的是消毒過的 `displayCitekey`）。兩個版本的說法都不成立，
    /// 差別只在錯的方向。真正的處置是 follow-up issue，不是換一句好聽的註解。
    ///
    /// **App target 未編不影響本守衛**——它掃的是原始碼文字，不需要能執行 App。
    /// **掃描面用「枚舉 `Sources/` + 顯式 opt-out」，不是手寫白名單**
    /// （#158 verify 158-3b）。
    ///
    /// 手寫清單有三個靜默失效路徑，實測全部成立：
    ///
    /// | 洞 | 手寫清單 | 枚舉 + opt-out |
    /// |---|---|---|
    /// | 打錯字（`AkashicAppKitTYPO`）| `try?` 貢獻 0 檔、不報錯 | 目錄還在 `Sources/` → 自動掃回來 |
    /// | **刪掉一項** | 清單與斷言讀同一份常數，一起縮，測試無感 | 同上 |
    /// | 新模組沒人加進清單 | 完全開放 | 自動被掃 |
    ///
    /// 第二項是 R2 席位的實測：刪掉 `Sources/AkashicAppKit` **並且**同時放回一條
    /// 真的未消毒輸出 → 全套仍綠。第一版的逐項非空斷言只 pin「宣稱掃的目錄都
    /// 存在」，membership 軸還是 tautology——入口從 typo 換成 deletion。
    ///
    /// 要排除必須寫進 `optOut` **並給理由**，跟 `display-safe-exempt` 同一個哲學：
    /// 逼人講出理由，而不是安靜跳過。
    /// **理由必須是可否證的陳述**（#158 verify R3）——「無使用者可見輸出面」這種
    /// 讀起來合理但沒人能檢查的句子不算。R3 席位實測：第一版 7 條裡 **3 條是假的**，
    /// 而且錯的兩條正是我自己心虛、特地請席位攻擊的那兩條：
    ///
    /// - `AkashicExport`「不是終端輸出；跳脫由 biblatex 層負責」——**兩個子句都假**。
    ///   `akashic export-bib` 預設印到 stdout、MCP `akashic_export` 把 .bib 全文當
    ///   tool result 回 LLM（最強威脅模型）；而 biblatex 跳脫的是 TeX specials
    ///   （`{}`／`\`／`%`／`&`），**不是** C0／bidi／LS-PS。席位探針實測：raw ESC
    ///   與 U+202E 都原樣通過。已移出 opt-out，leak 另開 issue。
    /// - `AkashicIndex`「只寫 SQLite」——假。`IndexError.rootNotALibrary` 是
    ///   `LocalizedError` 且**它自己就包了 `displaySafe`**（寫的人知道那是輸出面）。
    ///   opt-out 把那條的回歸保護整個拆掉（席位 mutation 實測綠）。已移出。
    /// - `AkashicSQLite`「無使用者可見輸出面」——結論對、**理由錯**。它有 4 個
    ///   `SQLiteError` case、6 條 caseReturn。正確理由是 #155 issue 自己寫的那句。
    ///   差別不是措辭：「無輸出面」＝以後沒人需要回來看；「有輸出面但目前不含
    ///   caller payload」＝以後有人往裡面塞 `citekey` 時理由當場失效、會被發現。
    static let optOut: [String: String] = [
        "AkashicSQLite":
            "有輸出面（SQLiteError 4 個 case／6 條 caseReturn），但只帶 sqlite3_errmsg "
            + "與自產 SQL 文字、**不含 caller payload**（SQL 全走 bind 參數，無內插）",
        "AkashicTestGuard": "test-only target，不進 release binary",
        "AkashicTestGuardLoader": "同上",
        "AkashicZoteroImport":
            "全模組零 print(／return \"／throw；唯二的 return \" 是 dedup key 構造",
        "AkashicWoSImport": "同上",
    ]

    /// **不得 opt-out、且必須真的在掃描面裡**的模組。兩個條件用同一份清單
    /// （#158 verify R3-4——分成兩份時差集會靜默漏掉）。
    static let mustScan = ["AkashicCore", "AkashicStoreIO", "AkashicEntity",
                           "akashic", "akashic-mcp", "AkashicMCPKit",
                           "AkashicQuery", "AkashicGraph", "AkashicAppKit",
                           "AkashicExport", "AkashicIndex"]

    /// 實際被掃的模組目錄 = `Sources/` 底下全部，減去 `optOut`。
    ///
    /// **只掃各模組頂層**（#158 verify R3 的 158-5 升級）：`contentsOfDirectory` 非
    /// 遞迴，`Sources/AkashicCore/Sub/Probe.swift` 這種巢狀檔案**掃不到**（席位實測
    /// 放一條未消毒輸出進去 → 全綠）。SwiftPM 完全支援巢狀 source 目錄，所以
    /// 「= `Sources/` 底下全部」這句在**檔案**層級是假的——寫在這裡以免被誤讀。
    /// 改用 `enumerator(at:)` 屬另案（#162 家族）。
    static func scannedDirs(repoRoot: URL) -> [String] {
        let sources = repoRoot.appendingPathComponent("Sources")
        let all = (try? FileManager.default.contentsOfDirectory(
            at: sources, includingPropertiesForKeys: [.isDirectoryKey]))?
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map(\.lastPathComponent).sorted() ?? []
        return all.filter { optOut[$0] == nil }.map { "Sources/\($0)" }
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AkashicKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    private var scannedFiles: [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for dir in Self.scannedDirs(repoRoot: repoRoot) {
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

    func testNoUnsanitisedStoreStringReachesUserVisibleOutput() throws {
        var violations: [String] = []

        for url in scannedFiles {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                XCTFail("讀不到 \(url.lastPathComponent)——掃描範圍若失效，這個測試會變成空跑")
                continue
            }
            let name = url.lastPathComponent
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

        XCTAssertTrue(violations.isEmpty, """
            有 \(violations.count) 條把 store 衍生字串未消毒送進使用者可見輸出的路徑：

            \(violations.joined(separator: "\n            "))

            修法二選一：
              1. 包上 displaySafe(…)——資料面用 max: 800，識別字用 max: 200
              2. 確定安全 → 同一行加 `// display-safe-exempt: <理由>`，把理由寫出來
            """)
    }

    /// **opt-out 必須逐條有理由，且掃描面必須真的涵蓋核心模組**（#158 verify 158-3b）。
    ///
    /// 枚舉 + opt-out 把「刪掉一項」這個洞關掉了（模組還在 `Sources/` 就會被掃回來），
    /// 但留下一個新的入口：**把模組加進 `optOut`**。這條把它擋住——理由不得為空，
    /// 且幾個核心輸出面模組不得出現在 opt-out 裡（要移除必須先改這條測試，那是
    /// 顯式動作而非順手一改）。
    func testOptOutIsJustifiedAndCoreModulesAreScanned() throws {
        for (name, reason) in Self.optOut {
            XCTAssertFalse(reason.trimmingCharacters(in: .whitespaces).isEmpty,
                           "opt-out 的「\(name)」沒有理由——排除必須講出為什麼")
        }
        // **同一份清單**（#158 verify R3-4）：兩處各寫一份時差集是 `AkashicGraph`
        // 與 `AkashicQuery`——它們若目錄被改名／搬走，第一條檢查照過（不在 optOut）、
        // 第二條根本不看它們，只剩 `count >= 30` 兜底。
        let dirs = Self.scannedDirs(repoRoot: repoRoot)
        for core in Self.mustScan {
            XCTAssertNil(Self.optOut[core], "「\(core)」是使用者可見輸出面，不得 opt-out")
            XCTAssertTrue(dirs.contains("Sources/\(core)"),
                          "掃描面不含 Sources/\(core)：\(dirs)")
        }
        // 每個被掃的目錄都要真的有 .swift（目錄空了＝那個模組的覆蓋是假的）
        let fm = FileManager.default
        for dir in dirs {
            let files = (try? fm.contentsOfDirectory(
                at: repoRoot.appendingPathComponent(dir),
                includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "swift" } ?? []
            XCTAssertFalse(files.isEmpty, "掃描目錄「\(dir)」貢獻 0 個 .swift")
        }
    }

    func testGuardItselfIsNotVacuous() throws {
        // 4 太鬆——光 Sources/akashic 一個目錄就有 8 個檔（#156 verify R2）
        XCTAssertGreaterThanOrEqual(scannedFiles.count, 30, "掃描範圍萎縮＝守衛失效")
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
