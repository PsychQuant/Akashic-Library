// `mcp-cli-parity.md` 的封閉列舉 vs 程式碼實際有的東西。
//
// **為什麼有這支**（#407 R50）：那條規則自帶一段「怎麼機械檢查這張表真的封閉」的稽核
// 程序——四個步驟、指令都寫好了——而**從來沒有任何東西執行它**。新增一個 MCP tool 或
// CLI subcommand 而忘了補表，守衛全綠、`swift test` 全綠，封閉列舉的宣稱就安靜變假。
//
// **誠實邊界（四條，逐字取自 Python 版）**：
//
//   · **MCP 面是嚴格集合相等**（表的第一欄 vs `Tool(name:)`），兩個方向都驗。
//   · **CLI 面只驗「命令名出現在規則檔裡」**，不驗它落在**哪一張**表、也不驗那一列的
//     裁決內容對不對。三張表的欄位形狀不同，而把「哪一欄算數」寫死會比它要防的漂移
//     更脆弱。**這比規則要求的弱**——規則要的是「落在某一張表的某一列」，本支只保證
//     「被提到」。
//   · **不驗裁決是否正確**（那要人判斷）。本支只擋「整個沒被提到」。
//   · **②b 把第一欄反引號內容的第一個詞當命令名，這在編輯時可能誤擋**（#407 R54）。
//     **裁決：接受。** 失敗方向是**可見且可逆**的誤擋，而收窄成「只看某一張表的某一欄」
//     會比它要防的漂移更脆弱。與規則檔自己記過的不對稱一致：誤擋可見可逆，漏報安靜。
//
// trigger-coverage: reads .claude/rules/mcp-cli-parity.md

import Foundation

/// 回傳 `struct T` 的本體區段，**大括號配對時跳過字串與註解**。
///
/// 演化（三步，每一步都由實測逼出）：
///
///   R54  `struct T\s*:.*?commandName:` ＋ DOTALL → 沒有 `commandName:` 時走過 T。
///   R54b 到下一個 `struct ` 宣告為止 → 終止在 T **自己巢狀的** struct。
///   R55  大括號配對 → **仍然壞**：字串字面裡的 `"{"`／`"}"` 也被算進去。實測
///        `CreateEntryCmd` 的區段長 **90,902** 字元，而該檔全檔只有 15,061——區段
///        衝出檔案外六倍（#407 R58）。
///   R58  跳過 `"""…"""`／`"…"`（含跳脫）、`//` 到行尾、`/* */`，再數大括號。
///
/// 誠實邊界：**多行字串有處理**（實測 4 處）。原始字串（`#"…"#`）不處理，
/// 實測 0 處，由 `noExoticStrings` 守住。
private func structBody(_ typeName: String, _ srcs: String) -> String? {
    let chars = Array(srcs)
    guard let m = srcs.range(of: "struct\\s+\(NSRegularExpression.escapedPattern(for: typeName))\\b[^{]*\\{",
                             options: .regularExpression) else { return nil }
    var i = srcs.distance(from: srcs.startIndex, to: m.upperBound)
    let start = i
    var depth = 1
    let n = chars.count
    func startsWith(_ s: [Character], _ at: Int) -> Bool {
        at + s.count <= n && Array(chars[at..<(at + s.count)]) == s
    }
    while i < n && depth > 0 {
        let c = chars[i]
        if startsWith(["\"", "\"", "\""], i) {
            var j = i + 3
            while j < n && !startsWith(["\"", "\"", "\""], j) { j += 1 }
            i = j >= n ? n : j + 3
            continue
        }
        if c == "\"" {
            i += 1
            while i < n && chars[i] != "\"" { i += chars[i] == "\\" ? 2 : 1 }
            i += 1
            continue
        }
        if c == "/" && i + 1 < n && chars[i + 1] == "/" {
            while i < n && chars[i] != "\n" { i += 1 }
            continue
        }
        if c == "/" && i + 1 < n && chars[i + 1] == "*" {
            var j = i + 2
            while j + 1 < n && !(chars[j] == "*" && chars[j + 1] == "/") { j += 1 }
            i = j + 1 >= n ? n : j + 2
            continue
        }
        if c == "{" { depth += 1 } else if c == "}" { depth -= 1 }
        i += 1
    }
    return depth == 0 ? String(chars[start..<(i - 1)]) : nil
}

private func commandName(_ typeName: String, _ srcs: String) -> String? {
    guard let body = structBody(typeName, srcs) else { return nil }
    return firstGroup(body, #"commandName:\s*"([^"]+)""#)
}

private func noExoticStrings(_ srcs: String) -> String? {
    let raw = matches(srcs, ##"#""##).count
    guard raw > 0 else { return nil }
    return "原始碼出現原始字串 `#\"…\"#`（\(raw) 處）——`structBody` 的掃描器不認得它們，"
         + "區段可能衝出邊界。加處理或把它們改掉。"
}

func parityTableDrift() -> Int32 {
    let rulePath = ".claude/rules/mcp-cli-parity.md"
    guard let rule = readFile(rulePath),
          let server = readFile("Sources/akashic-mcp/Server.swift"),
          let cli = readFile("Sources/akashic/CLI.swift") else {
        print("✗ 讀不到 \(rulePath)／Server.swift／CLI.swift 之一")
        return 1
    }
    var fails: [String] = []

    // ① MCP 面：嚴格集合相等，兩個方向都驗。
    let real = Set(captures(server, #"Tool\(name: "(akashic_[a-z_]+)""#))
    let listed = Set(captures(rule, #"^\| `(akashic_[a-z_]+)`"#, multiline: true))
    if real.isEmpty {
        fails.append("從 Server.swift 抽不到任何 `Tool(name:)`——抽取式與宣告寫法脫節了")
    }
    for t in real.subtracting(listed).sorted() {
        fails.append("MCP tool `\(t)` 在程式裡但**不在規則的 MCP 表**")
    }
    for t in listed.subtracting(real).sorted() {
        fails.append("MCP 表列了 `\(t)`，但程式裡**沒有這個 tool**")
    }

    // ② CLI 面
    var types: [String] = []
    if let arr = firstGroup(cli, #"subcommands:\s*\[(.*?)\]"#, dotAll: true) {
        types = captures(arr, #"([A-Za-z]+)\.self"#)
    } else {
        fails.append("在 CLI.swift 找不到 subcommands 陣列——抽取式脫節了")
    }
    let cliFiles = (try? FileManager.default.contentsOfDirectory(atPath: "\(repoRoot)/Sources/akashic"))?
        .filter { $0.hasSuffix(".swift") }.sorted() ?? []
    let srcs = cliFiles.compactMap { readFile("Sources/akashic/\($0)") }.joined(separator: "\n")

    var toks = Set<String>()
    for line in rule.components(separatedBy: "\n") where line.hasPrefix("|") {
        let cells = line.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "|")).components(separatedBy: "|")
        for cell in cells.prefix(2) {
            for x in captures(cell, #"`([a-z][a-z0-9 -]*)`"#) {
                if let first = x.split(separator: " ").first { toks.insert(String(first)) }
            }
        }
    }
    var unresolved: [String] = []
    var live = Set<String>()
    for t in types {
        guard let name = commandName(t, srcs) else { unresolved.append(t); continue }
        live.insert(name)
        if !toks.contains(name) {
            fails.append("CLI subcommand `\(name)`（\(t)）**規則檔裡完全沒提到**")
        }
    }
    for t in unresolved {
        fails.append("<未解析> \(t) 抽不到 commandName——稽核程序自己壞了")
    }
    if let exotic = noExoticStrings(srcs) { fails.append(exotic) }

    // ②c 退場列：劃掉的不得仍註冊；沒劃掉的必須仍在
    for m in matches(rule, #"^\|\s*(~~)?`([^`]+)`(?:~~)?"#, multiline: true) {
        let ns = rule as NSString
        let struck = m.range(at: 1).location != NSNotFound
        let raw = ns.substring(with: m.range(at: 2))
        guard let name = raw.split(separator: " ").first.map(String.init) else { continue }
        if name.hasPrefix("-") || name.hasPrefix("akashic_") { continue }
        if struck && live.contains(name) {
            fails.append("表把 `\(name)` 標成退場（劃掉），但它**仍註冊在 CLI.swift**")
        }
        if !struck && !live.contains(name) {
            fails.append("表列了 `\(name)` 而它**已不在 CLI.swift**——退場的列要劃掉"
                         + "並標明理由，不是留著不動")
        }
    }

    // ③ 橫切選項
    var cross = Set<String>()
    for f in cliFiles {
        guard let s = readFile("Sources/akashic/\(f)") else { continue }
        cross.formUnion(captures(s, #"struct ([A-Za-z]+):[^{]*\bParsableArguments\b"#))
    }
    for c in cross.sorted() where !rule.contains(c) {
        fails.append("橫切 ParsableArguments `\(c)` **不在規則的橫切選項表**")
    }

    print("══ parity 表 vs 程式碼：MCP \(real.count)｜CLI \(types.count)｜橫切 \(cross.count) ══")
    for f in fails { print("  ✗ \(f)") }
    print("\n══ \(fails.isEmpty ? "三面皆同步" : "**\(fails.count) 處漂移**") ══")
    return fails.isEmpty ? 0 : 1
}
