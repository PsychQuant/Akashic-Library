// 規則檔裡的 `實測 <數字>` 必須有時間錨，或旁邊有可重跑的指令。
//
// **為什麼有這支**（#407 R36）：某條規則裡的 `實測 N` 隨語料變動而安靜過期。量到 15 個
// 這種數字，其中一個是 `entity-backlink-completeness.md` 的「實測 6 筆」——**重跑得 31 筆，
// 該規則自己寫的兩個「重新裁決」觸發條件都早已成立而沒有人發現**。所以這不是零實例。
//
// **判準（三選一即算有背書）**：
//   1. 同一行有時間錨（`2026-08-23`／`當日`／`立案當時`／`#NNN`）
//   2. 所在**小節的標題到該行之間**有時間錨——**標題本身的 `#NNN` 不算**（#711 b37，b36 verify 第 17 列）：量測文件的歷輪補記
//      小節標題都是「### 第 N 列（#NNN）」，那個編號說的是這一節講哪一列，不是這段數字何時量的；算進去的話，那些小節（2026-10-15：
//      `grep -c '^### 第 [0-9]* 列（#' docs/zero-instance-measurements.md` 得 82 節；先前寫的「87」是 b36 評審的敘述，b38 verify 第 8 列）下的任何
//      「實測 N」都被標題自動背書，守衛對它們等於沒在看。標題裡的日期照樣算。標題是 CommonMark 的 ATX 標題（行首至多三個空白，#711 b39）；
//      標題那一行自己的數字照判準 1 看同一行。
//   3. 前 4 行至後 8 行內有**可重跑的指令**——不只是工具名：還要含路徑分隔／管線／
//      旗標／命令替換其中之一（#407 R39 收緊）
//
// **判讀是線性的、有上限**（#711 b39，b38 verify 第 0、2、4、5、7 列）：讀的檔 PR 改得到；見 `measuredNumbersScan`。
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
// trigger-coverage: reads docs/zero-instance-measurements.md
// trigger-coverage: reads docs/rulings/*.md

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
private let toolRegex = try! NSRegularExpression(pattern: toolRe)
private let runnableChars = CharacterSet(charactersIn: "|/$-")
private let numRegex = try! NSRegularExpression(pattern: numRe)
private let markRegex = try! NSRegularExpression(pattern: markRe)
/// 合法的 ATX 標題（CommonMark：行首至多三個空白、一到六個 `#`、之後是空白或行尾）。小節的錨與 `rowsAfter` 跨過的標題用同一個判準
/// （#711 b39，b38 verify 第 15、24 列：先前小節的錨用 `hasPrefix("#")`——行首的 `#NNN` 散文被當成標題、縮排一個空白的標題又不算）。
private let atxHeadingRegex = try! NSRegularExpression(pattern: #"^ {0,3}#{1,6}(?:\s|$)"#)
func measuredNumbersIsHeading(_ line: String) -> Bool {
    atxHeadingRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
}
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
        if measuredNumbersIsHeading(l) { crossed.append(l.trimmingCharacters(in: .whitespaces)) }
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

/// 一行裡有沒有 inline code 形式的可重跑指令：同一行**相鄰兩個反引號之間**的一段含工具名，而工具名之後還有 runnable 字元。
///
/// 與先前的正規式 `` `[^`\n]*TOOL[^`\n]*RUNNABLE[^`\n]*` `` 答案相同：那三段 `[^`\n]*` 都不跨反引號與換行，所以一個命中恰好是
/// 同一行相鄰兩個反引號之間的一段（含兩段 inline code 之間的那段文字——先前就是如此）；工具名彼此不互為子字串、同一個起點至多一個
/// 命中，所以最左邊的工具名也是最早結束的那個，「它之後有沒有 runnable 字元」就是「有沒有任何一個工具名之後有」。
/// **線性**（#711 b39，b38 verify 第 0、4、7 列）：正規式對一個沒收尾的反引號後接一長串「工具名＋runnable 字元」回溯成約 n^2.4
/// ——800 個「grep | 」（一行 5.6 KB）9 秒、2,000 個超過兩分鐘。這裡每一段只找一次工具名、再找一次 runnable 字元。
func measuredNumbersInlineCmd(_ line: String) -> Bool {
    let parts = line.components(separatedBy: "`")
    guard parts.count >= 3 else { return false }
    for seg in parts[1..<(parts.count - 1)] {
        let ns = seg as NSString
        guard let t = toolRegex.firstMatch(in: seg, range: NSRange(location: 0, length: ns.length)) else { continue }
        let after = t.range.location + t.range.length
        if ns.rangeOfCharacter(from: runnableChars, options: [], range: NSRange(location: after, length: ns.length - after)).location
            != NSNotFound { return true }
    }
    return false
}

/// fence 裡的一行算不算可重跑的指令：同一行有工具名、也有 runnable 字元（不論先後——與先前相同）。
private func fencedCmdLine(_ line: String) -> Bool {
    let ns = line as NSString
    let all = NSRange(location: 0, length: ns.length)
    return toolRegex.firstMatch(in: line, range: all) != nil
        && ns.rangeOfCharacter(from: runnableChars, options: [], range: all).location != NSNotFound
}

/// 一份檔的判讀結果：數到幾個 `實測 N`、哪些是裸的、哪幾行超過行的上限（那幾行不判讀）、到檔尾都沒收尾的 fence 從第幾行開。
struct MeasuredNumbersScan {
    var total = 0
    var bare: [(line: Int, number: String, shown: String)] = []
    var oversizeLines: [(line: Int, bytes: Int)] = []
    var unclosedFence: Int? = nil
}

/// 判讀一份檔的 `實測 N`（檔頭的三條判準）。
///
/// **線性**（#711 b39，b38 verify 第 2、4、5、7 列）：b37 把小節的錨改成逐行累積，但每個數字仍各做兩件與行長成正比的事——
/// 對同一個 12 行視窗重跑一次判準 3（`hasCmd`）、重新 trim 一次整行。一行 N 個沒有時間錨的數字因此是 N 乘上行長：一行兩萬個 51 秒。
/// 現在每一行的事實（有沒有 inline 指令、是不是 fence 的分隔、fence 裡算不算指令）各算一次，每一行的判準 3 也只算一次，
/// 要用到時才算；顯示用的那一段 trim 每行至多一次。
/// **行的上限**：`lineByteCap` 位元組以上的行不判讀、記在 `oversizeLines`（呼叫端具名紅）——fence 裡的行、fence 的分隔行也一樣，判準 3 的
/// 視窗也不讀它（#711 b41，b40 verify 第 0 列：b39 的兩個 fence 分支在上限之前就 `continue`，視窗又經快取讀到超長行）；超長的分隔行照樣
/// 開合 fence，其餘不看。**沒收尾的 fence**：到檔尾還在 fence 裡時記下開頭那一行（呼叫端具名紅），之後的數字沒被判讀（b40 verify 第 5、24 列）。
/// 這裡的單位是一行，所以沿用 `selfProofMaxBlockBytes`；`selfProofMaxBlockLines` 對一行沒有意義（一個單位恆為一行）。後設檢查（`measuredNumbersLinearityIssues`）
/// 傳 `Int.max` 繞過它——那裡量的是判讀本身。
func measuredNumbersScan(_ lines: [String], lineByteCap: Int = selfProofMaxBlockBytes) -> MeasuredNumbersScan {
    var scan = MeasuredNumbersScan()
    let n = lines.count
    let big = lines.map { $0.utf8.count > lineByteCap }
    // 逐行的事實，要用到時才算（0 未算、1 否、2 是）
    var inlineAt = [UInt8](repeating: 0, count: n)
    var fenceAt = [UInt8](repeating: 0, count: n)
    var fencedCmdAt = [UInt8](repeating: 0, count: n)
    var windowAt = [UInt8](repeating: 0, count: n)
    func fact(_ memo: inout [UInt8], _ j: Int, _ compute: (String) -> Bool) -> Bool {
        if memo[j] == 0 { memo[j] = compute(lines[j]) ? 2 : 1 }
        return memo[j] == 2
    }
    /// 判準 3：前 4 行至後 8 行內有可重跑的指令。fence 的開合從視窗頂端起算（與先前把視窗接成一段再逐行讀相同）。
    func hasCmd(around i: Int) -> Bool {
        if windowAt[i] != 0 { return windowAt[i] == 2 }
        let lo = max(0, i - 4), hi = min(n, i + 8)
        var found = false
        for j in lo..<hi where !big[j] && fact(&inlineAt, j, measuredNumbersInlineCmd) { found = true; break }
        if !found {
            var fenced = false
            for j in lo..<hi {
                if fact(&fenceAt, j, { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }) { fenced.toggle(); continue }
                if fenced && !big[j] && fact(&fencedCmdAt, j, fencedCmdLine) { found = true; break }
            }
        }
        windowAt[i] = found ? 2 : 1
        return found
    }
    // secAnchored：從小節標題到目前這一行之間有沒有時間錨——逐行累積（#711 b37）。標題那一行去掉 `#NNN` 再算（見檔頭判準 2）；
    // 第一個標題之前，從檔頭起算
    var secAnchored = false, inFence = false, fenceOpen = 0
    for (i, line) in lines.enumerated() {
        if big[i] {
            scan.oversizeLines.append((i + 1, line.utf8.count))
            if unquote(line).hasPrefix("```") { inFence.toggle(); fenceOpen = i + 1 }
            continue
        }
        let ns = line as NSString
        let lineMarked = markRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil
        // fence 裡的行不判讀數字、也不是標題，但照樣算進小節的時間錨（先前的寫法把整節原文接起來，fence 也在裡面）
        if unquote(line).hasPrefix("```") { inFence.toggle(); fenceOpen = i + 1; secAnchored = secAnchored || lineMarked; continue }
        if inFence { secAnchored = secAnchored || lineMarked; continue }
        if measuredNumbersIsHeading(line) {
            // 標題的 `#NNN` 不替這一節的其他行背書（判準 2）。標題那一行自己的數字照判準 1 看同一行——`mcp-cli-parity` 的
            // 「（#422 verify R1 實測表頭的「12 命令…」）」那個編號就是那個數字的出處（#711 b39，b38 verify 第 15 列考慮過把它也去掉，
            // 那會把這種寫法判成裸數字）
            let stripped = line.replacingOccurrences(of: #"#\d{2,4}"#, with: "", options: .regularExpression)
            secAnchored = markRegex.firstMatch(in: stripped, range: NSRange(location: 0, length: (stripped as NSString).length)) != nil
        } else {
            secAnchored = secAnchored || lineMarked
        }
        var shown: String? = nil
        for m in numRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            let num = ns.substring(with: m.range(at: 1))
            if num.hasPrefix("20"), num.count >= 4, num.prefix(4).allSatisfy(\.isNumber) { continue }   // 日期，不是計數
            scan.total += 1
            if lineMarked || secAnchored || hasCmd(around: i) { continue }
            if shown == nil { shown = String(line.trimmingCharacters(in: .whitespaces).prefix(60)) }
            scan.bare.append((i + 1, num, shown!))
        }
    }
    if inFence { scan.unclosedFence = fenceOpen }
    return scan
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
        // #711（使用者 2026-10-05 裁決）：零實例裁決表的量測與歷輪補記從規則檔搬到 docs/zero-instance-measurements.md（不自動載入）——那些「實測 N」
        // 原本在 `.claude/rules/` 裡受這支守衛檢查，搬走之後要跟著讀，否則搬一次就等於拿掉檢查。
        (zeroInstanceMeasurementsPath, fileExists(zeroInstanceMeasurementsPath) ? [zeroInstanceMeasurementsPath] : []),
        // 2026-10-15：三份規則的裁決表搬到 docs/rulings/（不自動載入），表格裡的「實測 N」原本在 `.claude/rules/` 裡受檢查——
        // 理由同上一列：搬一次不得等於拿掉檢查。逐來源，所以整個目錄不見也會出聲。
        ("docs/rulings/*.md", globFiles("docs/rulings/*.md")),
    ]
    let empty = sources.filter { $0.1.isEmpty }
    if !empty.isEmpty {
        for (k, _) in empty {
            print("✗ 在 \(repoRoot) 底下 `\(k)` 一個檔都沒找到——路徑錯了還是被搬走了？")
        }
        return 1
    }
    // **排序跨全部來源做一次，不是各自排完再串**：`.claude` < `CLAUDE.md` < `docs` < `plugin`
    // （ASCII `.`=46 < `C`=67 < `d`=100 < `p`=112），而先前的寫法把 CLAUDE.md 排在最前面。
    // 單檔注入的 mutation 看不出差別——要兩個不同來源同時有 finding 才會現形。
    let files = sources.flatMap { $0.1 }.sorted()
    var total = 0
    var bare: [(String, Int, String, String)] = []
    // **上限**（#711 b39，b38 verify 第 2、4、5、7 列）：這幾份檔 PR 改得到（`census-parity.yml` 以 `pull_request` 觸發），b37 只在
    // `zero-instance-rows-audit` 設了上限。每份檔沿用 `selfProofMaxFileBytes`、每一行沿用 `selfProofMaxBlockBytes`（這支的單位是一行）——
    // 同一組值，改一處兩支一起動。超過即具名紅、不判讀那一塊，不截斷。
    var oversizeFiles: [(String, Int)] = []
    var oversizeLines: [(String, Int, Int)] = []
    // 讀不到的檔、沒收尾的 fence 也具名紅（#711 b41，b40 verify 第 5、24 列：先前靜默略過，非 UTF-8 的一個位元組就讓整份檔不被讀而照樣綠——
    // 第 3 列「未涵蓋不得冒充通過」；`zero-instance-rows-audit` 對兩者都具名紅）
    var unreadable: [String] = []
    var unclosed: [(String, Int)] = []
    var texts: [String: String] = [:]

    for f in files {
        guard let raw = readFile(f) else { unreadable.append(f); continue }
        if raw.utf8.count > selfProofMaxFileBytes { oversizeFiles.append((f, raw.utf8.count)); continue }
        texts[f] = raw
        let scan = measuredNumbersScan(raw.components(separatedBy: "\n"))
        total += scan.total
        bare += scan.bare.map { (f, $0.line, $0.number, $0.shown) }
        oversizeLines += scan.oversizeLines.map { (f, $0.line, $0.bytes) }
        if let open = scan.unclosedFence { unclosed.append((f, open)) }
    }

    // 標題列說出判準 2 的收窄（#711 b37）：「全部都有時間錨」是在小節標題的編號不背書之下說的——量測文件第 101 列的自證閘也用這一段
    print("══ 規則檔的 `實測 <數字>`：共 \(total) 個（\(files.count) 個檔；小節標題的編號不背書）══")
    for (rel, i, n, s) in bare {
        print("  ✗ \(rel):\(i) 「\(n)」——沒有時間錨也沒有可重跑的指令\n     \(s)")
    }
    if bare.isEmpty { print("  全部都有時間錨或可重跑的指令") }
    for (rel, bytes) in oversizeFiles {
        print("  ✗ \(rel) 有 \(bytes) 位元組，超過上限 \(selfProofMaxFileBytes)——這支守衛不掃它（被掃的檔 PR 改得到，"
              + "上限讓判讀的工作量有界）。拆檔，或提高 `selfProofMaxFileBytes` 並寫理由")
    }
    for (rel, i, bytes) in oversizeLines {
        print("  ✗ \(rel):\(i) 這一行有 \(bytes) 位元組，超過上限 \(selfProofMaxBlockBytes)——不判讀這一行的數字"
              + "（被掃的檔 PR 改得到，上限讓判讀的工作量有界）。拆行，或提高 `selfProofMaxBlockBytes` 並寫理由")
    }
    for rel in unreadable {
        print("  ✗ \(rel) 讀不到（不存在、不是檔，或不是合法的 UTF-8）——這支守衛沒有判讀它。修好編碼或拿掉那個檔")
    }
    for (rel, open) in unclosed {
        print("  ✗ \(rel):\(open) 開的 fence 到檔尾都沒有收尾——之後的 `實測 N` 都被當成 fence 內、沒有判讀。補上收尾的一行")
    }
    let oversize = oversizeFiles.count + oversizeLines.count
    let unjudged = unreadable.count + unclosed.count

    // 標題宣稱的列數 vs 下方的表
    var drift: [(String, Int, String, Int)] = []
    var noflag: [(String, Int, String)] = []
    var borrowed: [(String, Int, String, [String])] = []
    var unparsed: [(String, Int, String)] = []
    var counts = 0
    for f in files {
        guard let raw = texts[f] else { continue }   // 讀不到的、超過檔案上限的不判讀（兩者上面都已具名）
        let lines = raw.components(separatedBy: "\n")
        // 標題用 CommonMark 的 ATX 判準，與小節的錨、`rowsAfter` 同一個（#711 b41，b40 verify 第 19 列：b39 只換了那兩處，這裡仍是
        // `hasPrefix("#")`，行首 `#NNN` 的散文被當成標題）
        for (i, line) in lines.enumerated()
        where line.utf8.count <= selfProofMaxBlockBytes && measuredNumbersIsHeading(line) {
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
          + "｜\(bad == 0 ? "列數宣稱皆相符" : "**\(bad) 處列數不符**")"
          + (oversize == 0 ? "" : "｜**\(oversize) 處超過上限**")
          + (unjudged == 0 ? "" : "｜**\(unjudged) 處沒有判讀**") + " ══")
    return (bare.isEmpty && bad == 0 && oversize == 0 && unjudged == 0) ? 0 : 1
}

// MARK: - 判讀是線性的：輸入放大 10 倍要在固定秒數內（#711 b39）

/// `audit-guards-mutations` 的一項後設檢查：b38 verify 量到的三條超線性路徑（第 0、2、4、5、7 列），各以 n 與 10n 的輸入直接呼叫
/// `measuredNumbersScan`（繞過行的上限——量的是判讀本身），10n 那一次要在 `selfProofLinearityBoundSeconds` 秒內。
/// 先前的版本在這幾個 10n 上要十幾秒到幾分鐘，線性的在一秒內。回 (問題, 一行報告)。
func measuredNumbersLinearityIssues() -> (issues: [String], report: String) {
    func seconds(_ body: () -> Void) -> Double {
        let t0 = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
    }
    let vectors: [(name: String, size: Int, line: (Int) -> String)] = [
        // 第 0 列：一個沒收尾的反引號後接一長串「工具名＋runnable 字元」，同一行一個沒有時間錨的數字（正規式回溯，約 n^2.4）
        ("沒收尾的反引號後接一長串「grep | 」", 100, { k in "實測 3 筆 `" + String(repeating: "grep | ", count: k) }),
        // 第 4 列：一行很多個數字、旁邊有 inline 指令——每個數字各把同一個視窗重掃一次
        ("一行很多個「實測 N」、同一行有 inline 指令", 1_500, { k in "`grep -c x` " + String(repeating: "實測 7 筆，", count: k) }),
        // 第 2、5 列：一行很多個沒有時間錨的數字——每個數字各重掃一次視窗、各 trim 一次整行
        ("一行很多個沒有時間錨的「實測 N」", 1_500, { k in String(repeating: "實測 7 筆，", count: k) }),
    ]
    var issues: [String] = []
    var parts: [String] = []
    for v in vectors {
        let small = seconds { _ = measuredNumbersScan(["## 補充", "", v.line(v.size)], lineByteCap: .max) }
        let large = seconds { _ = measuredNumbersScan(["## 補充", "", v.line(v.size * 10)], lineByteCap: .max) }
        parts.append("\(v.name) \(String(format: "%.2f", small))→\(String(format: "%.2f", large)) 秒")
        if large > selfProofLinearityBoundSeconds {
            issues.append("「\(v.name)」輸入放大 10 倍（\(v.size * 10)）要 \(String(format: "%.1f", large)) 秒，上限 "
                          + "\(String(format: "%.0f", selfProofLinearityBoundSeconds)) 秒——超線性的判讀回來了（#711 b38 verify 量到的形狀）")
        }
    }
    // 換掉正規式之後答案要相同：與正規式 `` `[^`\n]*TOOL[^`\n]*RUNNABLE[^`\n]*` `` 逐一比對（短輸入，回溯無妨）
    let regex = try! NSRegularExpression(pattern: "`[^`\n]*" + toolRe + "[^`\n]*" + runnableRe + "[^`\n]*`")
    let samples = ["`grep -c x`", "`grep x`", "`a | grep`", "`grep` 與 `x|y`", "`grep ` | `", "x `grep -c", "`sed s/a/b/`",
                   "``grep -c x``", "`git log` 之後 `/`", "`validate`-", "`python3 -`", "`gh pr` `x`", "`find .` `wc -l`"]
    for s in samples {
        let expected = regex.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
        if measuredNumbersInlineCmd(s) != expected {
            issues.append("`measuredNumbersInlineCmd` 對「\(s)」的答案與先前的正規式不同（應為 \(expected)）——它換掉的是那個正規式，答案要相同")
        }
    }
    // 小節錨的標題判準（#711 b39，b38 verify 第 15、24 列）：縮排一到三個空白的 ATX 標題也是標題、它的 `#NNN` 不背書；行首 `#NNN` 的散文
    // 不是標題、不重設小節的錨；標題那一行自己的數字照判準 1 看同一行
    let headingSamples: [(name: String, lines: [String], bare: Int)] = [
        ("縮排一個空白的標題，其下的數字", [" ### 第 200 列（#711）", "", "這一節的補記：實測 777 筆。"], 1),
        ("行首 `#NNN` 的散文不重設小節的錨", ["### 小節（2026-10-09）", "#711 的說明：", "實測 777 筆。"], 0),
        ("標題那一行自己的數字照判準 1", ["### 第 5 列（#711）實測 777 筆"], 0),
        ("無縮排的標題，其下的數字", ["### 第 200 列（#711）", "", "這一節的補記：實測 777 筆。"], 1),
    ]
    for s in headingSamples {
        let got = measuredNumbersScan(s.lines).bare.count
        if got != s.bare {
            issues.append("標題判準的樣例「\(s.name)」報了 \(got) 個裸數字，應為 \(s.bare)")
        }
    }
    return (issues, parts.joined(separator: "、"))
}
