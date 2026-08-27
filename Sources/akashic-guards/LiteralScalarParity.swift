// `literal-census.sh` 抽 `literal:` 值的 regex vs YAML 純量語義。
//
// **為什麼有這支**（#407 R62）：census 用**裸 regex** 抽 `literal:` 的值，而
// `distinct literal` 正是整個 literal 歸零 campaign 的**分母**。同一支腳本裡兩個**更窄**的
// 文字解析風險（`#` 註解判定、`format:` 標記）都已有完整 oracle ＋ mutation；最寬的那個
// 反而沒有（跨模型審查列為 HIGH）。
//
// **分岔是量過的，不是假設**（R61）：從真實 entity 複製兩筆、只改 `literal` 的**寫法**，
// 值不變——真正的解碼器兩者都得到 `Jacob Cohen`（1 個 distinct）；census 報 **2**。
//
// **誠實邊界（三條，這支比它的兩個姊妹弱）**：
//   · **oracle 不是真的 Swift 解碼器**。姊妹守衛拿真 `akashic` 當 oracle；這裡辦不到——
//     CLI 讀 store 需要 registry key（index 住 store 之外），fixture store 沒有 key 就沒有
//     index。所以 oracle 是本檔內的**參考解碼**，只涵蓋下方列舉的寫法。
//   · **`_scalar` 從 census 原始碼抽出並執行**，不在這裡重打一份——一份規格的兩個副本
//     必然分岔。抽不到、或抽到不只一份，都紅。
//   · **只驗單行純量**。區塊／摺疊純量（`|`／`>`）不在列舉內。
//
// **為什麼 Swift 版仍然 spawn `python3`**（#433）：被測的東西**就是** census.sh 裡內嵌的
// Python 函數（該檔 598 行裡有 573 行是內嵌 Python）。用 Python 執行它不是遷移沒做完，
// 是這支守衛的職責本來就是「驗那段 Python 的行為」——換成 Swift 重寫一份等價解碼，
// 驗的就變成我寫的那份，而不是實際在跑的那份。
//
// trigger-coverage: reads plugin/skills/*/scripts/literal-census.sh

import Foundation

func literalScalarParity() -> Int32 {
    let CENSUS = "plugin/skills/akashic-promote-literals/scripts/literal-census.sh"
    // 「這一行 YAML」→「正確解碼後的值」。封閉列舉：每一列都是一個 YAML 純量寫法。
    let CASES: [(String, String)] = [
        (#"- literal: Jacob Cohen"#,            "Jacob Cohen"),
        (#"- literal: "Jacob Cohen""#,          "Jacob Cohen"),
        (#"- literal: 'Jacob Cohen'"#,          "Jacob Cohen"),
        (#"- literal: Jacob Cohen  # 尾註"#,     "Jacob Cohen"),
        (#"- literal: "Jacob Cohen"  # 尾註"#,   "Jacob Cohen"),
        (#"- literal: "Cohen, J.""#,            "Cohen, J."),
        (#"- literal: "a \"quoted\" name""#,    "a \"quoted\" name"),
        (#"- literal: 'it''s'"#,                "it's"),
        // #407 R63：帶變音符的人名在這個 store 很常見，而 ASCII-safe 的 YAML emitter 會把
        // 它們寫成 `\uXXXX`。照抄下一個字元會得到字面的 `u00e9`。
        (#"- literal: "André Weil""#,      "André Weil"),
        (#"- literal: "caf\xe9""#,              "café"),
        (#"- literal: "a\tb""#,                 "a\tb"),
        // #407 R64：`\U` 是 8 位，非 BMP（CJK 擴充 B、emoji）。
        (#"- literal: "\U00020000""#,           String(UnicodeScalar(0x20000)!)),
        // #407 R66：YAML 雙引號純量還有這些跳脫，漏掉會輸出字面的字母。
        (#"- literal: "a\_b""#,                 "a\u{A0}b"),
        (#"- literal: "a\Nb""#,                 "a\u{85}b"),
        (#"- literal: "a\eb""#,                 "a\u{1B}b"),
        (#"- literal: "a\vb""#,                 "a\u{0B}b"),
    ]

    // ── 把 census 的 `_scalar` 抽出來執行——不在這裡重打一份 ────────────────
    //
    // **用縮排界定函式本體，不靠空行**（#407 R63）：上一版的非貪婪樣式在**第一個空行**就停
    // ——在 `_scalar` 裡插一行純排版的空行，切出來的仍是**語法有效**的片段，`exec` 不會拋，
    // 兩道既有檢查也不會紅，而那個被截斷的 `_scalar` 對單引號／未加引號的值一律回 None。
    // **靜默切錯比切不到危險。**
    let src = rawFile(CENSUS)
    let lines = src.components(separatedBy: "\n")
    func fail(_ m: String) -> Int32 { print("✗ \(m)"); return 1 }

    guard let a = lines.firstIndex(where: { $0.hasPrefix("    def _scalar(s):") }) else {
        return fail("從 census 抽不到 `_scalar`——抽取式與宣告寫法脫節了")
    }
    // 空行與**任意縮排的註解行**都不終止切片（#407 R64）：一行縮排不足的註解——維護者加
    // 一句範圍說明時很自然會左對齊——會讓切片提前結束，而截斷後的本體**仍然語法有效**。
    var b = a + 1
    while b < lines.count {
        let l = lines[b]
        let t = l.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.hasPrefix("#") || l.hasPrefix("        ") { b += 1 } else { break }
    }
    // **切完要驗結構完整**：本體的最後一個非空、非註解行必須是 `return`。只驗「exec 沒拋」
    // 擋不住截斷——那正是上一版的漏洞。
    let tail = lines[a..<b].filter {
        let t = $0.trimmingCharacters(in: .whitespaces)
        return !t.isEmpty && !t.hasPrefix("#")
    }
    guard let last = tail.last,
          last.trimmingCharacters(in: .whitespaces).hasPrefix("return") else {
        let shown = tail.last.map { String($0.trimmingCharacters(in: .whitespaces).prefix(40)) } ?? "（空）"
        return fail("切出的 `_scalar` 本體最後一行不是 `return`——切片可能被截斷了（最後一行：\(shown)）")
    }
    let occurrences = src.components(separatedBy: "def _scalar(s):").count - 1
    guard occurrences == 1 else {
        return fail("census 裡有 \(occurrences) 份 `_scalar`（須恰好 1）")
    }
    // **縮排不足的註解行不進切片**：它們不終止切片（見上），但若原樣納入，dedent 的共同
    // 前綴會塌成空字串（#407 R64 當場踩到）。
    let body = lines[a..<b].filter {
        !($0.trimmingCharacters(in: .whitespaces).hasPrefix("#") && !$0.hasPrefix("        "))
    }
    // `textwrap.dedent`：剝掉全部非空行的共同前綴空白。
    let indents = body.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        .map { $0.prefix(while: { $0 == " " }).count }
    let common = indents.min() ?? 0
    let dedented = body.map { String($0.dropFirst(min(common, $0.prefix(while: { $0 == " " }).count))) }
        .joined(separator: "\n")

    // 一次 spawn 跑完全部 case：JSON 進、JSON 出，避免每個 case 一次 process。
    let prog = dedented + """

    import sys, json, re
    print(json.dumps([_scalar(x) for x in json.loads(sys.argv[1])]))
    """
    let rx = #"^- literal: (.*)$"#
    let args: [String] = CASES.map { (line, _) in
        matches(line, rx).first.map { (line as NSString).substring(with: $0.range(at: 1)) } ?? ""
    }
    guard let argJSON = try? JSONSerialization.data(withJSONObject: args),
          let argStr = String(data: argJSON, encoding: .utf8) else {
        return fail("無法序列化 case——這是本守衛自己的缺陷，不是 census 的")
    }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = ["python3", "-c", prog, argStr]
    p.currentDirectoryURL = URL(fileURLWithPath: repoRoot)
    let out = Pipe(), err = Pipe(); p.standardOutput = out; p.standardError = err
    guard (try? p.run()) != nil else { return fail("spawn python3 失敗") }
    let od = out.fileHandleForReading.readDataToEndOfFile()
    let ed = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard p.terminationStatus == 0,
          let got = try? JSONSerialization.jsonObject(with: od) as? [Any] else {
        let e = String(data: ed, encoding: .utf8) ?? ""
        return fail("執行抽出的 `_scalar` 失敗（exit \(p.terminationStatus)）：\(e.prefix(200))")
    }

    var bad: [(String, String, String)] = []
    for (i, (line, want)) in CASES.enumerated() {
        let g = i < got.count ? got[i] : NSNull()
        let gotStr = g is NSNull ? "None" : "'\(g)'"
        if !(g is NSNull), let s = g as? String, s == want { continue }
        bad.append((line, want, gotStr))
    }
    print("══ `literal:` 純量解碼 parity：\(CASES.count) 種寫法 ══")
    for (line, want, got) in bad {
        print("  ✗ \(line)\n      正確 '\(want)'｜census 得到 \(got)")
    }
    print("\n══ \(bad.isEmpty ? "全部一致" : "**\(bad.count) 種寫法分岔**") ══")
    return bad.isEmpty ? 0 : 1
}
