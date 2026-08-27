// 規則檔裡的 `實測 <數字>` 必須有時間錨，或旁邊有可重跑的指令。
//
// **為什麼有這支**（#407 R36）：某條規則裡的 `實測 N` 隨語料變動而安靜過期。量到 15 個
// 這種數字，其中一個是 `entity-backlink-completeness.md` 的「實測 6 筆」——**重跑得 31 筆，
// 該規則自己寫的兩個「重新裁決」觸發條件都早已成立而沒有人發現**。所以這不是零實例。
//
// **判準（三選一即算有背書）**：
//   1. 同一行有時間錨（`2026-08-23`／`當日`／`立案當時`／`#NNN`）
//   2. 所在**小節的標題到該行之間**有時間錨
//   3. 前 4 行至後 8 行內有**可重跑的指令**——不只是工具名：還要含路徑分隔／管線／
//      旗標／命令替換其中之一（#407 R39 收緊）
//
// **誠實邊界（三條，都量過）**：
//   · **觸發詞只認「實測」。** 換個寫法就逃掉。這是 heuristic 不是覆蓋保證。
//   · **它驗「有沒有時間錨」，不驗「數字對不對」。** entity-backlink 那個 31 筆是**人**
//     重跑發現的，本支抓不到它。
//   · **四位數年份不算數字**（`2026-08-12 的實測` 裡的 2026 是日期）。
//
// trigger-coverage: reads plugin/rules/*.md
// trigger-coverage: reads .claude/rules/*.md
// trigger-coverage: reads CLAUDE.md

import Foundation

private let numRe = #"實測[^。\n]{0,24}?(\d[\d,./]*)"#
private let markRe = #"20\d\d-\d\d-\d\d|20\d\d 年|當日|立案當時|#\d{2,4}"#
// **工具名不算配方**（#407 R39）：前一版只要 backtick 裡出現關鍵字就算有指令，於是
// `akashic validate`——一個貼進 shell 也重現不出那個數字的**工具名**——把一個會漂移的
// 計數判成有背書。現在另外要求它長得像**可貼進 shell 的一行**。
//
// **反引號要在同一行內配對**（#407 R40）：`[^`]*` 不排除換行，於是一個 inline code 的
// **收尾**反引號會被當成新的開頭，一路吃過表格好幾列。加 `\n` 到排除集合即修好。
private let toolRe = #"(?:grep|awk|sed|git |gh |python3|swift|bash|jq|wc |find |validate)"#
private let runnableRe = #"[|/$-]"#
private let cmdInline = "`[^`\n]*" + toolRe + "[^`\n]*" + runnableRe + "[^`\n]*`"
// 字元類**刻意比 `digits` 認得的略寬**（#407 R67i）：只收認得的字，「解析不出要報」
// 那條路徑就永遠不可達——一段沒有輸入到得了的程式碼，讀起來卻像一道防線。收進
// `廿`／`卅`／`萬` 這些真實會出現但不處理的字，讓那條路徑有東西走得到。
private let countRe = #"(現有|恰|共)\s*([0-9０-９零一二兩三四五六七八九十百千廿卅萬]+)\s*(列|項|條|格)"#

private let digits: [Character: Int] = ["零": 0, "一": 1, "二": 2, "兩": 2, "三": 3,
                                        "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]

/// 把中文或阿拉伯數字轉成 Int；解析不出回 nil
///
/// **用算的，不要用查表**（#407 R67i）：上一版是一張手寫的對照表，而它**缺了十五、
/// 且十六以上完全沒有**——`現有十五列` 會回 nil 然後被靜默略過。手寫表的問題不是
/// 這次漏了哪幾個，是它每次都會漏，而漏掉的形式是沉默。（**呼叫端必須報出來，不得略過**）。
private func parseNum(_ raw: String) -> Int? {
    var s = ""
    for ch in raw.trimmingCharacters(in: .whitespaces) {
        if let a = "０１２３４５６７８９".firstIndex(of: ch) {
            s.append(Character(String("０１２３４５６７８９".distance(from: "０１２３４５６７８９".startIndex, to: a))))
        } else { s.append(ch) }
    }
    if !s.isEmpty && s.allSatisfy({ $0.isNumber && $0.isASCII }) { return Int(s) }
    var total = 0, section = 0, seen = false
    for ch in s {
        if let d = digits[ch] { section = d; seen = true }
        else if ch == "十" { section = (section == 0 ? 1 : section) * 10; total += section; section = 0; seen = true }
        else if ch == "百" { section = (section == 0 ? 1 : section) * 100; total += section; section = 0; seen = true }
        else { return nil }
    }
    return seen ? total + section : nil
}

/// `i` 之後最近的 markdown 表有幾個資料列。
///
/// **找不到回 `.none`，不是 0**：「標題後沒有表」與「表有 0 列」是兩件事，折成同一個值
/// 會讓前者被當成不符（`lossless-intake` 的「靜默是最糟的形式」）。
///
/// **fence 內的示範表不是表**（#407 R67j）：規則檔常用 ``` 包一段 markdown 語法示範。
/// **標題要是合法的 ATX 標題**（#407 R67l）：CommonMark 要求 `#` 後接空白或行尾，
/// 而本 repo 的規則檔滿是行首的 `#NNN` issue 編號——上一版把 `#407 R33 的量測：`
/// 當成標題，於是它後面那張**本來就屬於當前標題**的表被誤判成 borrowed。
private enum RowsAfter { case rows(Int), borrowed([String]), none }

private func rowsAfter(_ lines: [String], _ i: Int) -> RowsAfter {
    var crossed: [String] = []
    var fenced = false
    let sep = #"^\|[-\s|:]+\|\s*$"#
    for j in (i + 1)..<min(i + 40, lines.count) {
        let l = lines[j]
        if l.trimmingCharacters(in: .whitespaces).hasPrefix("```") { fenced.toggle(); continue }
        if fenced { continue }
        if !matches(l, #"^#{1,6}(\s|$)"#).isEmpty { crossed.append(l.trimmingCharacters(in: .whitespaces)) }
        if !matches(l, sep).isEmpty {
            if !crossed.isEmpty { return .borrowed(crossed) }
            var k = j + 1, rows = 0
            while k < lines.count && lines[k].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                if !matches(lines[k], sep).isEmpty { rows -= 1; break }
                rows += 1; k += 1
            }
            return .rows(max(rows, 0))
        }
    }
    return .none
}

private func hasCmd(_ chunk: String) -> Bool {
    if !matches(chunk, cmdInline).isEmpty { return true }
    // ② 圍籬區塊。**必須支援**：兩個真的可重跑的配方就寫在 ```bash 裡，而 inline 那條
    //    看不到它們——先前它們「通過」靠的是①跨行誤配對出來的假 match（#407 R40）。
    var fenced = false
    for line in chunk.components(separatedBy: "\n") {
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { fenced.toggle(); continue }
        if fenced && !matches(line, toolRe).isEmpty && !matches(line, runnableRe).isEmpty { return true }
    }
    return false
}

private func unquote(_ l: String) -> String {
    l.replacingOccurrences(of: #"^\s*>\s?"#, with: "", options: .regularExpression)
}

func measuredNumbersAudit() -> Int32 {
    // **逐來源檢查，不看聯集**（#407 R67g）：加入 CLAUDE.md 之後，「一個都沒找到就報錯」
    // 會被它撐著——兩個 rules 目錄整個消失時聯集仍非空，於是路徑打錯或規則被搬走**不會有
    // 任何跡象**。這與 `trigger-coverage` 從「聯集」改成「逐對」是同一個修正。
    let sources: [(String, [String])] = [
        (".claude/rules/*.md", globFiles(".claude/rules/*.md")),
        ("plugin/rules/*.md", globFiles("plugin/rules/*.md")),
        ("CLAUDE.md", fileExists("CLAUDE.md") ? ["CLAUDE.md"] : []),
    ]
    let empty = sources.filter { $0.1.isEmpty }
    if !empty.isEmpty {
        for (k, _) in empty {
            print("✗ 在 \(repoRoot) 底下 `\(k)` 一個檔都沒找到——路徑錯了還是被搬走了？")
        }
        return 1
    }
    // **排序跨三個來源做一次，不是各自排完再串**：`.claude` < `CLAUDE.md` < `plugin`
    // （ASCII `.`=46 < `C`=67 < `p`=112），而先前的寫法把 CLAUDE.md 排在最前面。
    // 單檔注入的 mutation 看不出差別——要兩個不同來源同時有 finding 才會現形。
    let files = sources.flatMap { $0.1 }.sorted()
    var total = 0
    var bare: [(String, Int, String, String)] = []

    for f in files {
        guard let raw = readFile(f) else { continue }
        let lines = raw.components(separatedBy: "\n")
        var sec = 0, inFence = false
        for (i, line) in lines.enumerated() {
            if unquote(line).hasPrefix("```") { inFence.toggle(); continue }
            if inFence { continue }
            if line.hasPrefix("#") { sec = i }
            let ns = line as NSString
            for m in matches(line, numRe) {
                let n = ns.substring(with: m.range(at: 1))
                if !matches(n, #"^20\d\d"#).isEmpty { continue }   // 日期，不是計數
                total += 1
                let secText = lines[sec...i].joined(separator: "\n")
                let around = lines[max(0, i - 4)..<min(lines.count, i + 8)].joined(separator: "\n")
                let anchored = !matches(line, markRe).isEmpty
                    || !matches(secText, markRe).isEmpty || hasCmd(around)
                if !anchored {
                    bare.append((f, i + 1, n, String(line.trimmingCharacters(in: .whitespaces).prefix(60))))
                }
            }
        }
    }

    print("══ 規則檔的 `實測 <數字>`：共 \(total) 個（\(files.count) 個檔）══")
    for (rel, i, n, s) in bare {
        print("  ✗ \(rel):\(i) 「\(n)」——沒有時間錨也沒有可重跑的指令\n     \(s)")
    }
    if bare.isEmpty { print("  全部都有時間錨或可重跑的指令") }

    // 標題宣稱的列數 vs 下方的表
    var drift: [(String, Int, String, Int)] = []
    var noflag: [(String, Int, String)] = []
    var borrowed: [(String, Int, String, [String])] = []
    var unparsed: [(String, Int, String)] = []
    var counts = 0
    for f in files {
        guard let raw = readFile(f) else { continue }
        let lines = raw.components(separatedBy: "\n")
        for (i, line) in lines.enumerated()
        where line.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
            let ns = line as NSString
            for m in matches(line, countRe) {
                counts += 1
                let whole = ns.substring(with: m.range(at: 0))
                guard let n = parseNum(ns.substring(with: m.range(at: 2))) else {
                    unparsed.append((f, i + 1, whole)); continue
                }
                switch rowsAfter(lines, i) {
                case .rows(let r): if r != n { drift.append((f, i + 1, whole, r)) }
                case .borrowed(let h): borrowed.append((f, i + 1, whole, h))
                case .none: noflag.append((f, i + 1, whole))
                }
            }
        }
    }

    print("\n══ 標題宣稱的列數：共 \(counts) 處 ══")
    for (rel, i, txt, rows) in drift { print("  ✗ \(rel):\(i) 標題說「\(txt)」而下方的表有 \(rows) 列") }
    for (rel, i, txt) in noflag { print("  ✗ \(rel):\(i) 標題說「\(txt)」但在下一個標題之前找不到表——錨不存在") }
    for (rel, i, txt, heads) in borrowed {
        let whereS = heads.count == 1 ? "在「\(heads[0])」之後"
                                      : "隔了 \(heads.count) 個標題（\(heads[0]) … \(heads[heads.count-1])）"
        let which = heads.count == 1 ? "那個" : "正確的那個"
        print("  ✗ \(rel):\(i) 標題說「\(txt)」而它自己沒有表——最近的表\(whereS)，"
              + "不屬於它。把宣稱搬到\(which)標題上，或補回本節的表")
    }
    for (rel, i, txt) in unparsed { print("  ✗ \(rel):\(i) 標題說「\(txt)」而那個數字解析不出來——請改寫或擴充 _num") }
    let bad = drift.count + noflag.count + borrowed.count + unparsed.count
    if bad == 0 { print("  \(counts) 處全部與其下方的表相符") }

    print("\n══ \(bare.isEmpty ? "無裸數字" : "**\(bare.count) 個裸數字**")"
          + "｜\(bad == 0 ? "列數宣稱皆相符" : "**\(bad) 處列數不符**") ══")
    return (bare.isEmpty && bad == 0) ? 0 : 1
}
