// CLAUDE.md 的 pre-push 決策矩陣：宣稱值 vs 由兩條語意規則現算的值。
//
// **為什麼有這支**（#407 R27）：那張表錯過一次（R26q 的
// `| 正常 | 恢復 | 任一 | 執行 | 執行 |` —— 涵蓋 3 格而「留」欄是零執行／零執行／執行），
// 而那個錯撐過了好幾輪人＋AI 審查才被發現。表是散文，沒有任何東西在檢查它。
//
// **它驗什麼、不驗什麼**（誠實邊界，寫在最前面免得被當成更強的保證）：
//
//   驗   ——「表宣稱的值」與「由檔案自己敘述的兩條語意規則現算的值」一致，
//          且每一列在它**字面涵蓋的全部格**上成立（笛卡兒積，非只有你檢查過那幾格），
//          且 8 列合起來涵蓋全部 12 格。
//   不驗 —— 那兩條規則本身是否符合**現實**。要驗那個得真的在 12 種組態下各 push 一次。
//          規則取自檔案自己的敘述，所以本支抓的是**轉錄錯誤與合併過度宣稱** —— R26q
//          正是後者。
//
// **兩條規則的出處**（不是我發明的，是檔案自己寫的）：
//
//   A「留在 pre-push」= 執行 ⟺ push 是正常 `git push`（hook 沒被繞過）
//      **且** `core.hooksPath` 指向本樹（那份 hook 才含這些守衛）。
//   B「移出、只留 CI」= 執行 ⟺ CI 跑得起來。出處：該欄的定義即是「只留 CI」。
//
// trigger-coverage: reads CLAUDE.md

import Foundation

private let pushValues = ["正常", "--no-verify"]
private let ciValues = ["不跑", "恢復"]
private let hpValues = ["未設定", "主repo", "本樹"]

private func ruleKeep(_ push: String, _ ci: String, _ hp: String) -> String {
    (push == "正常" && hp == "本樹") ? "執行" : "零執行"
}
private func ruleMove(_ push: String, _ ci: String, _ hp: String) -> String {
    ci == "恢復" ? "執行" : "零執行"
}

/// 剝 markdown 強調與反引號。**不剝括號註記——因為格裡不准有註記。**
///
/// 演化（三步，每一步都是被實測逼出來的）：
///
///   R27 子串比對 → 一個很自然的編輯就被安靜讀反（`不跑（等 macOS 恢復）` 讀成「恢復」）。
///   R28 剝註記 ＋ 嚴格查表 → 讀對了值，但**註記與 token 可以互相矛盾**：只改註記
///       （「未 merge」→「已 merge」）而不動 token，守衛全綠而人會照註記讀成另一個值。
///   R30 **格裡不准有註記**。兩個猜關鍵字的檢查都被實測否掉——「註記含本欄其他值的
///       token」誤傷 0 卻抓不到那個情境；「hooksPath 註記含 `merge`」抓得到形狀卻誤傷
///       2 列。所以不偵測矛盾，改成**讓矛盾寫不出來**：註記回散文，格裡出現 `（` 即
///       `<未解析>`。
///
/// 這是 `entity-backlink-completeness` 引 Tractatus 3.325 的同一個立場：與其檢查錯誤，
/// 不如用一種讓錯誤在文法上寫不出來的記法。
private func stripMD(_ cell: String) -> String {
    var s = cell
    while let r = s.range(of: "`[^`]*`", options: .regularExpression) {
        s.replaceSubrange(r, with: s[r].trimmingCharacters(in: CharacterSet(charactersIn: "`")))
    }
    return s.replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespaces)
}

// 嚴格查表。任何不在表內的字面都落進 `<未解析>`（出聲），不做「猜最像的那個」。
private let pushMap = ["正常 git push": "正常", "--no-verify": "--no-verify"]
private let ciMap = ["不跑": "不跑", "恢復": "恢復"]
private let hpMap: [String: [String]] = ["未設定": ["未設定"], "指向主 repo": ["主repo"],
                                         "指向本樹": ["本樹"], "任一": hpValues]
private func parseOutcome(_ c: String) -> String? {
    (c == "執行" || c == "零執行") ? c : nil
}

/// `mdPath` 可覆寫要讀的 markdown。**唯一的用途是負控**——它必須在 pristine copy 上
/// mutate，不得就地改出貨檔（前一版的 harness 就地改寫版控中的檔案，跨模型審查在審查
/// 期間實際觀察到 tracked 檔出現被注入的狀態，#407 R6）。
func decisionMatrixDrift(_ mdPath: String?) -> Int32 {
    let path = mdPath ?? "\(repoRoot)/CLAUDE.md"
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("✗ 讀不到 \(path)")
        return 1
    }
    let lines = text.components(separatedBy: "\n")
    guard let head = lines.firstIndex(where: {
        $0.hasPrefix("> | push 方式 | CI 狀態 | hooksPath |") }) else {
        print("✗ 找不到決策矩陣的表頭（表被改名或移走了？）")
        return 1
    }

    var rows: [(String, String, [String], String, String)] = []
    for l in lines[(head + 2)...] {
        guard l.hasPrefix("> |") else { break }
        let body = String(l.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        let cells = body.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .components(separatedBy: "|").map(stripMD)
        // 註記一律回散文（見 stripMD 的 R30）。格裡出現全形括號 → 出聲。
        let noted = cells.filter { $0.contains("（") || $0.contains("）") }
        if !noted.isEmpty {
            print("✗ 格裡有註記（註記一律寫在散文，不寫在格裡）：\(pyList(noted))")
            return 1
        }
        guard cells.count == 5 else {
            print("✗ 列的欄數不是 5：\(l.prefix(70))")
            return 1
        }
        // **解析不出來要出聲，不可靜默跳過**——只在 happy path 正確的稽核，會在真正
        // 需要它的時候安靜少報一列（mcp-cli-parity 的 ② 記過同型）。
        guard let p = pushMap[cells[0]], let c = ciMap[cells[1]], let h = hpMap[cells[2]],
              let k = parseOutcome(cells[3]), let m = parseOutcome(cells[4]) else {
            print("✗ <未解析> 列：\(l.prefix(80))")
            print("    push=\(pushMap[cells[0]] ?? "None") ci=\(ciMap[cells[1]] ?? "None") "
                  + "hooksPath=\(hpMap[cells[2]].map(pyList) ?? "None") "
                  + "留=\(parseOutcome(cells[3]) ?? "None") 移出=\(parseOutcome(cells[4]) ?? "None")")
            return 1
        }
        rows.append((p, c, h, k, m))
    }
    guard !rows.isEmpty else { print("✗ 表頭之後一列都沒讀到"); return 1 }

    print("══ 決策矩陣漂移檢查（讀到 \(rows.count) 列）══")
    var bad = 0
    for (i, r) in rows.enumerated() {
        let (p, c, hs, k, m) = r
        let cover = hs.map { (p, c, $0) }
        let keeps = Set(cover.map { ruleKeep($0.0, $0.1, $0.2) })
        let moves = Set(cover.map { ruleMove($0.0, $0.1, $0.2) })
        let ok = keeps == [k] && moves == [m]
        if !ok { bad += 1 }
        let lbl = pad(p, 12) + pad(c, 5) + (hs.count > 1 ? "任一" : hs[0])
        print("  \(ok ? "✓" : "✗") 列\(i + 1) \(pad(lbl, 20)) 涵蓋\(cover.count)格 "
              + "宣稱(\(k),\(m)) 現算(\(keeps.sorted().joined(separator: "/")),"
              + "\(moves.sorted().joined(separator: "/")))")
    }

    var seen = Set<String>()
    for (p, c, hs, _, _) in rows { for h in hs { seen.insert("\(p)|\(c)|\(h)") } }
    var all = Set<String>()
    for p in pushValues { for c in ciValues { for h in hpValues { all.insert("\(p)|\(c)|\(h)") } } }
    let missing = all.subtracting(seen).sorted()
    let dup = rows.reduce(0) { $0 + $1.2.count } - seen.count

    print("\n  涵蓋 \(seen.count)/\(all.count) 格"
          + (missing.isEmpty ? "；無缺口"
             : "；**缺 [" + missing.map { pyTuple($0.components(separatedBy: "|")) }
                                   .joined(separator: ", ") + "]**")
          + (dup != 0 ? "；**\(dup) 格被重複宣稱**" : ""))
    let fail = bad != 0 || !missing.isEmpty || dup != 0
    print("\n══ \(fail ? "**漂移**" : "矩陣與規則一致、無缺口") ══")
    return fail ? 1 : 0
}

/// Python 的 `f'{s:<n}'` 對**全形字元**按碼點數補空白，Swift 沒有內建等價物。
/// 逐字複製那個行為（而不是「看起來對齊」），因為第 3a 步要求**輸出逐字相同**。

// MARK: - Python repr 相容（**遷移期限定**）
//
// 第 3a 步要求兩版在同一批 mutation 上**輸出逐字相同**——那是為了讓 oracle 保持
// **機械**：一個 `diff` 就是判定，不需要人看訊息「實質上像不像」。今天反覆證明
// judgment 會讓錯誤通過（#394 R9 的三個假設全部被自己的量測推翻）。
//
// 代價是這幾個函式讓 Swift 印出 Python 的 repr 形狀（`['x']`／`('a', 'b')`／`None`）。
//
// **退場條件**（`no-compat-fallback` 要求寫下來的那個）：`plugin/tests/
// decision-matrix-drift.py` 被刪除之後，本節連同它的三個呼叫點一併刪，
// 改用 Swift 自然的渲染。量測：
//
//     ls plugin/tests/decision-matrix-drift.py 2>/dev/null | wc -l   # → 0 即可刪
private func pyList(_ xs: [String]) -> String {
    "[" + xs.map { "'\($0)'" }.joined(separator: ", ") + "]"
}
private func pyTuple(_ parts: [String]) -> String {
    "(" + parts.map { "'\($0)'" }.joined(separator: ", ") + ")"
}

private func pad(_ s: String, _ n: Int) -> String {
    s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
}
