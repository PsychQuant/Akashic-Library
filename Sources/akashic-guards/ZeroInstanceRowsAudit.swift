// `zero-instance-guards.md` 的裁決表：每一列裁決「寫」的守衛，程式裡真的有嗎？
//
// **契約（逐字取自 Python 版的 docstring，#433 第 3b 步）**：
//
//   表裡每一列都引一個 issue 編號。裁決是 ✅「寫」的列，那個編號必須出現在
//   `Sources/` 底下——也就是那個守衛真的被實作了。
//
// **另一條義務（#711）**：量測區塊裡每一條「對 binary 的輸出計數」的指令，必須帶自證——
// 前面以 `&&` 接 `LC_ALL=C grep -a -q '<這條檢查獨有的訊息片段>' "$(command -v <同一支 binary>)"`，或同一個區塊
// 較早一條量測的行尾寫 `# 正對照`（期望值不是 0 的那條）。沒有的話，舊 binary 沒有那條檢查時印的是 `0`，與「檢查過且
// 乾淨」在輸出上分不開（第 13 列的自證就是為了防這件事）。#710 R1 verify 一次抓到二十多條沒有閘的，
// 說明卻都寫「同第 13 列的自證」——文字與指令分岔，而且是安靜的。R1（#711 R1 verify）起閘要以 `&&` 接上、查同一支
// binary，片段要在 release 版找得到、不能是負控自己種進 binary 的——細節見 `selfProofIssues` 與 `selfProofNeedleIssues`。
//
// **誠實邊界（三條，與 Python 版同）**：
//
//   · 只驗編號在場，**不驗守衛做的事對不對**（那要人判斷，正是該規則保留給人的部分）。
//   · 編號可能因別的理由出現在 Sources（例如某個註解提到它）。這是**弱檢查**——它擋的是
//     「加了一列卻沒實作」與「實作被刪了而列還在」，不是「實作偏離了裁決」。
//   · 裁決不是 ✅ 的列**不要求編號在場**——那正是它的意思。
//
// **為什麼有這支**（#407 R55）：那份規則的表是一列一列裁決出來的封閉列舉，而沒有任何
// 東西在確認「裁決寫了守衛的那些列，守衛真的存在」。與 `mcp-cli-parity`（由
// `parity-table-drift` 守）和 `entity-backlink-completeness`（由 `backlink-field-ratchet`
// 守）**同一個形狀**。
//
// trigger-coverage: reads Sources/*/*.swift

import Foundation

func zeroInstanceRowsAudit() -> Int32 {
    let rulePath = ".claude/rules/zero-instance-guards.md"
    guard let rule = readFile(rulePath) else {
        FileHandle.standardError.write(Data("✗ 找不到 \(rulePath)\n".utf8))
        return 1
    }
    // **排除由腳本生成的測試資料檔**（#433）：`AuditGuardsMutationsData.swift` 等把
    // negative-control 的 mutation 字串資料化，住在 `Sources/` 只因為 SwiftPM 要它在那裡
    // 才編得到——它們**不是實作**。
    //
    // 不排除的話這支必然誤判：其中一個 mutation 的內容正是「一個刻意不存在於 Sources 的
    // 編號」，資料化之後那個編號就真的出現了，於是守衛說「找得到實作」而它其實只找到自己
    // 的測試資料。這在資料化的當天就讓那一格從綠變紅。
    //
    // **判準是結構的**（檔頭的生成標記），不是列舉檔名——列舉會與下一個生成檔分岔。
    let src = swiftSources().compactMap(readFile)
        .filter { !String($0.prefix(600)).contains("本檔由腳本生成") }
        .joined(separator: "\n")

    // `| <列號> | <情形> | <裁決> | <理由> |` —— 讀前三欄，第四欄刻意不讀。
    //
    // **抽取式不得要求 ` | `**（#365，2026-08-28）。先前的 pattern 是
    // `^\| (\d+) \| (.*?) \| (.*?) \|`，它要求分隔符**前面有空格**——而 markdown
    // 不要求，本表既有的每一列都寫成 `…）| ✅ **寫** | …`（`）` 與 `|` 之間沒有空格）。
    //
    // 後果不是「讀不到」，是**每一欄往後挪一格**：裁決欄讀到的是理由欄。於是
    // `verdict.contains("✅")` 對每一列都是 false，每一列都 `continue`——
    // **這個守衛從來沒有真的檢查過任何一列的實作是否在場**，而它十一列全綠。
    //
    // 那正是本檔第 5、6 兩列講的形狀（守衛對自己的覆蓋率說謊／從沒紅過的檢查與不存在
    // 的檢查長得一樣），發生在守衛**自己**身上。
    //
    // 改成整行切欄：`|` 兩側的空白一律 trim，與 markdown 的實際語意一致。
    let rowRe = try! NSRegularExpression(pattern: #"^\|\s*(\d+)\s*\|(.*)$"#,
                                         options: [.anchorsMatchLines])
    let ns = rule as NSString
    let rows = rowRe.matches(in: rule, range: NSRange(location: 0, length: ns.length))
    guard !rows.isEmpty else {
        FileHandle.standardError.write(
            Data("✗ 裁決表一列都沒讀到——抽取式與表的寫法脫節了\n".utf8))
        return 1
    }

    // **列號必須連續**（#365，2026-08-28）。
    //
    // 抽取式要求 ` |`（空格＋豎線），而 markdown **不要求**——一列寫成 `…）| ❌` 時
    // 它整列匹配不到，而守衛**照樣綠**，只是 `rows.count` 少一。實測：加了兩列之後
    // 表有 11 列而守衛報 10，沒有任何訊息說少了一列。
    //
    // 那是本檔第 5 列（「重複看起來像多一份覆蓋」）的鏡像：那一列講的是**多印**一個 ✓，
    // 這裡是**少印**一列而沒人知道。兩者都是「守衛對自己的覆蓋率說謊」。
    //
    // 檢查列號連續是最便宜的兜底：它不需要知道表該有幾列（那個數字會隨裁決成長），
    // 只需要知道**編號不該跳號**。
    let nums: [Int] = rows.compactMap { Int(ns.substring(with: $0.range(at: 1))) }
    if let bad = nums.enumerated().first(where: { $0.element != $0.offset + 1 }) {
        // `.utf8` 只綁到最後一個字串——整個運算式要先括起來（實測踩過）
        let msg = "✗ 裁決表的列號跳號：讀到第 \(bad.offset + 1) 個是「\(bad.element)」——"
            + "很可能有一列的分隔符缺了空格（抽取式要 ` |`，markdown 不要）"
            + "而它**整列被跳過**，守衛照樣綠只是少數一列\n"
        FileHandle.standardError.write(Data(msg.utf8))
        return 1
    }

    let issueRe = try! NSRegularExpression(pattern: #"#(\d{2,4})"#)
    var fails: [String] = []

    for m in rows {
        let num = ns.substring(with: m.range(at: 1))
        // 第二個捕獲組是「列號之後的整行」——切成欄，兩側 trim。
        let cells = ns.substring(with: m.range(at: 2))
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard cells.count >= 2 else {
            fails.append("第 \(num) 列切不出情形與裁決兩欄——表格格式壞了")
            continue
        }
        let body = cells[0]
        let verdict = cells[1]

        let bodyNS = body as NSString
        let issues = issueRe.matches(in: body, range: NSRange(location: 0, length: bodyNS.length))
            .map { bodyNS.substring(with: $0.range(at: 1)) }
        if issues.isEmpty {
            fails.append("第 \(num) 列沒有引用任何 issue 編號——無從查證它是否被實作")
            continue
        }
        // **裁決欄必須是裁決**（#365，2026-08-28）。
        //
        // 抽取式的 `(.*?) \|` 只要求**三個** ` | `，而一列有四個。少了中間那個空格時
        // 它仍然匹配，只是**每一欄往後挪一格**——裁決欄讀到的是**理由欄**。
        //
        // 那比「少數一列」更糟：守衛照樣數到它、照樣印 ✓，而它判斷的是錯的欄位。
        // 理由裡碰巧出現一個 `✅`，一個裁決「不寫」的列就會被要求實作在場；反過來
        // 一個「寫」的列會被靜默跳過檢查。
        //
        // 實測（三種分隔符狀態）：兩處都缺 → 不匹配（列號檢查抓）；只有中間有 → 正確；
        // **只有行尾有 → 匹配但裁決欄讀成理由欄**。本檢查抓第三種。
        let marks = ["✅", "⚠", "❌"]
        guard marks.contains(where: { verdict.contains($0) }) else {
            fails.append("第 \(num) 列的裁決欄讀到「\(verdict.prefix(30))」——"
                         + "那不像裁決（要有 ✅／⚠／❌ 之一）。"
                         + "很可能是某個分隔符缺了空格，導致每一欄往後挪了一格")
            continue
        }
        guard verdict.contains("✅") else { continue }   // 裁決不是「寫」→ 不要求實作在場

        let absent = issues.filter { !src.contains("#\($0)") }
        if absent.count == issues.count {
            let named = issues.map { "#\($0)" }.joined(separator: "／")
            fails.append("第 \(num) 列裁決「寫」，但它引用的編號 \(named) "
                         + "**在 Sources/ 裡都找不到**——守衛實作了嗎，還是被刪了而列還在？")
        }
    }

    // **每一列都要在「各列共通的東西」有一條 bullet 講它自己的理由**（#479）。
    //
    // 前面幾條檢查守的都是可判定的性質（欄位在不在、編號對不對、裁決欄讀到什麼）。
    // 這一條守的是**辯護**：這張表的價值全在「理由欄與裁決同列所以不會分岔」，而共通段
    // 是那些理由的第二層——它說明每一列的理由**彼此不同**，那正是本檔不寫總括判準的依據。
    //
    // 少一條 bullet 不會讓任何檢查變錯，只會讓下一個人拿判準去類推——而那是本檔開宗明義
    // 禁止的動作。漂移真的發生過：第 12 列的裁決 2026-08-28 就下了，2026-09-02 才補進表。
    //
    // 一條 bullet 可以涵蓋多列（「第 10、11、12 列的理由是三個**不同的**…」），所以判準是
    // **每個列號至少被引用一次**，不是「bullet 數等於列數」。
    //
    // **錨在行首**（`\n## `）——同一個字面也出現在本檔下方的量測腳本裡（那段
    // Python 用 `t.index('## 各列共通的東西')` 找同一個標題）。`range(of:)` 取第一個，
    // 於是擷取到的會是**量測區塊的尾巴**而不是真的段落，結果是 16 列被誤報成沒有 bullet。
    // 實地踩到——加完量測腳本的下一次執行就紅了。同型的坑本 repo 記過：
    // `parity-table-drift` 的表格第一欄不得用反引號，因為守衛會把那些 token 當成宣稱。
    if let ci = rule.range(of: "\n## 各列共通的東西") {
        let after = rule[ci.upperBound...]
        let common = after.range(of: "\n## ").map { String(after[..<$0.lowerBound]) } ?? String(after)
        // **只認「以 `- 第 N 列的理由是` 開頭的 bullet」，不是段落裡任何一次提到 N**
        // （#479，第一版就是後者而它太弱）。那一段裡到處都是跨列比較——「第 4 列與
        // 第 1 列的差別值得看一眼」、「它與第 1 列（缺跡象）、第 8 列…最像」——所以
        // 一列即使**沒有自己的 bullet**，也會因為被別列拿去比較而算成「有講到」。
        // 實測：拿掉第 1 列的 bullet，鬆的判準 rc=0（負控不紅）。
        let refRe = try! NSRegularExpression(pattern: #"(?m)^- 第 ([0-9、]+) 列的理由是"#)
        let cns = common as NSString
        var cited = Set<Int>()
        for m in refRe.matches(in: common, range: NSRange(location: 0, length: cns.length)) {
            for part in cns.substring(with: m.range(at: 1)).components(separatedBy: "、") {
                if let v = Int(part) { cited.insert(v) }
            }
        }
        let uncited = nums.filter { !cited.contains($0) }
        if !uncited.isEmpty {
            fails.append("第 \(uncited.map(String.init).joined(separator: "／")) 列在「各列共通的東西」"
                         + "沒有任何 bullet 講它——那一段是每列理由**彼此不同**的說明，"
                         + "而那正是本檔不寫總括判準的依據。加一條 bullet 說出這一列的理由"
                         + "為什麼不能沿用既有任何一列")
        }
    } else {
        fails.append("找不到「## 各列共通的東西」——這一段是理由欄的第二層，不得消失")
    }

    // **量測指令的自證閘**（#711）。空掃描不是通過：一條都沒掃到，代表抽取式與檔的寫法脫節了。
    let proof = selfProofIssues(in: rule)
    if proof.checked == 0 {
        fails.append("量測區塊裡對 binary 輸出計數的指令一條都沒掃到——"
                     + "抽取式與檔的寫法脫節了，自證閘的檢查等於沒跑")
    }
    fails += proof.issues
    // #711 R1：閘的片段要在 release 版找得到、而且不是負控自己種進 `akashic-guards` 的
    fails += selfProofNeedleIssues(gates: proof.gates)

    var out = "══ zero-instance 裁決表：\(rows.count) 列；量測指令 \(proof.checked) 條數 binary 輸出 ══\n"
    for f in fails { out += "  ✗ \(f)\n" }
    out += "\n══ " + (fails.isEmpty ? "每一列裁決「寫」的都找得到實作"
                                    : "**\(fails.count) 列有問題**") + " ══\n"
    FileHandle.standardOutput.write(Data(out.utf8))
    return fails.isEmpty ? 0 : 1
}


// MARK: - 量測指令的自證閘（#711；R1 起閘要以 `&&` 接到被量的指令、查同一支 binary）

/// 被量的指令的來源：`akashic <子命令>`、`akashic-guards <子命令>`（含路徑，如 `.build/debug/akashic-guards`）、
/// `"$(command -v akashic)" <子命令>`、`swift run akashic <子命令>`，或存了它們輸出的 `"$out"`。只看管線的**第一個**命令。
/// 第 1 組＝binary 名（`"$out"` 時為空：它的 binary 在別一行，閘綁不上，只能靠正對照）。
/// R1 起子命令前可以有 `-`／`--` 開頭的選項（`akashic --library X validate`，#711 R1 verify 第 13 列）。
private let selfProofSourceRe =
    #"^\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:swift\s+run\s+(?:-\S+\s+)*)?(?:"?\$\(command -v (akashic(?:-guards)?)\)"?|(?:[\w.~-]*/)*(akashic(?:-guards)?))\s+-{0,2}[a-z]|"\$out""#
/// 自證閘：一整個命令恰為 `LC_ALL=C grep -a -q '<片段>' <binary>`。`LC_ALL=C` 不能省——macOS 的 `/usr/bin/grep` 在 UTF-8
/// locale 下對 binary 比不到中文（#710 R1：同一個 binary 印 0 與 3）。
private let selfProofLooseGateRe = #"^\s*(?:LC_ALL=C\s+)?grep\s+-a\s+-q\b"#
/// 正對照：期望值不是 0 的那條。舊 binary 印 0 與它的期望值分得開，所以同一個區塊裡跟在它後面的 0 有了對照。
/// **R1 起只認行尾 shell 註解的開頭**（`# 正對照…`），而且那一行本身要是一條被量的指令——
/// `# 這裡沒有正對照` 這種否定句不算（#711 R1 verify 第 21、24、27 列：先前是任意子字串）。
private let selfProofControlRe = #"^#\s*正對照"#

/// 一個量測單位切成頂層的命令串：`pipelines[i]` 是一條管線（以 `|` 分開的命令），`joins[i]` 是接在
/// `pipelines[i]` 與 `pipelines[i+1]` 之間的運算子（`&&`／`||`／`;`／`&`）。引號內與 `$( … )`／`( … )` 內的運算子不算；
/// `2>&1`、`&>` 這類重導向裡的 `&` 不算。
struct SelfProofShellList { var pipelines: [[String]]; var joins: [String] }

func selfProofShellList(_ s: String) -> SelfProofShellList {
    let c = Array(s.unicodeScalars)
    var pipelines: [[String]] = [[]]
    var joins: [String] = []
    var cur = ""
    var inSingle = false, inDouble = false
    var depth = 0
    var i = 0
    func endCommand() { pipelines[pipelines.count - 1].append(cur.trimmingCharacters(in: .whitespaces)); cur = "" }
    while i < c.count {
        let ch = c[i]
        if inSingle {
            cur.unicodeScalars.append(ch); if ch == "'" { inSingle = false }; i += 1; continue
        }
        if ch == "\\", i + 1 < c.count { cur.unicodeScalars.append(ch); cur.unicodeScalars.append(c[i + 1]); i += 2; continue }
        if ch == "\"" { inDouble.toggle(); cur.unicodeScalars.append(ch); i += 1; continue }
        if !inDouble, ch == "'" { inSingle = true; cur.unicodeScalars.append(ch); i += 1; continue }
        if ch == "(" { depth += 1; cur.unicodeScalars.append(ch); i += 1; continue }
        if ch == ")" { depth = max(0, depth - 1); cur.unicodeScalars.append(ch); i += 1; continue }
        if inDouble || depth > 0 { cur.unicodeScalars.append(ch); i += 1; continue }
        let next: Unicode.Scalar? = i + 1 < c.count ? c[i + 1] : nil
        let prev: Unicode.Scalar? = cur.unicodeScalars.last
        if ch == "|" {
            if next == "|" { endCommand(); joins.append("||"); pipelines.append([]); i += 2; continue }
            endCommand(); i += 1; continue
        }
        if ch == ";" { endCommand(); joins.append(";"); pipelines.append([]); i += 1; continue }
        if ch == "&" {
            if next == "&" { endCommand(); joins.append("&&"); pipelines.append([]); i += 2; continue }
            if prev == ">" || next == ">" { cur.unicodeScalars.append(ch); i += 1; continue }   // 2>&1、&> 是重導向
            endCommand(); joins.append("&"); pipelines.append([]); i += 1; continue
        }
        cur.unicodeScalars.append(ch); i += 1
    }
    endCommand()
    return SelfProofShellList(pipelines: pipelines, joins: joins)
}

/// 去掉行尾的 shell 註解（引號外、位在字首的 `#` 起到行尾），回 (指令, 註解)。註解不含開頭的 `#`。
func selfProofSplitComment(_ s: String) -> (code: String, comment: String?) {
    let c = Array(s.unicodeScalars)
    var inSingle = false, inDouble = false
    var i = 0
    while i < c.count {
        let ch = c[i]
        if inSingle { if ch == "'" { inSingle = false }; i += 1; continue }
        if ch == "\\" { i += 2; continue }
        if ch == "\"" { inDouble.toggle(); i += 1; continue }
        if !inDouble, ch == "'" { inSingle = true; i += 1; continue }
        if !inDouble, ch == "#", i == 0 || c[i - 1] == " " || c[i - 1] == "\t" {
            var code = String.UnicodeScalarView(), comment = String.UnicodeScalarView()
            code.append(contentsOf: c[..<i]); comment.append(contentsOf: c[i...])
            return (String(code), String(comment))
        }
        i += 1
    }
    return (s, nil)
}

/// 一個命令的 token（`shellLex`；未閉合引號退回空白切分——那時這個命令也不會被認成閘）。
private func selfProofTokens(_ cmd: String) -> [String] {
    (try? shellLex(cmd)) ?? cmd.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
}

/// 計數出口：`grep` 帶 `-c`（選項串任何位置，如 `-cE`、`-vc`、分開寫的 `-E -c`）或 `--count`；`wc -l`。
/// R1 起認這些寫法（#711 R1 verify 第 18、24、27 列：先前只認 `| grep -c…` 一種排列）。
private func selfProofIsCount(_ cmd: String) -> Bool {
    let t = selfProofTokens(cmd)
    guard let head = t.first.map({ ($0 as NSString).lastPathComponent }) else { return false }
    if head == "wc" { return t.dropFirst().contains { $0.hasPrefix("-") && !$0.hasPrefix("--") && $0.contains("l") } || t.contains("--lines") }
    guard ["grep", "egrep", "fgrep"].contains(head) else { return false }
    var i = 1
    while i < t.count {
        let a = t[i]
        if a == "--" { break }
        if a == "--count" { return true }
        if a == "-e" || a == "-f" || a == "--regexp" || a == "--file" { i += 2; continue }   // 下一個 token 是樣式，不是選項
        if a.hasPrefix("-"), !a.hasPrefix("--"), a.count > 1 {
            for ch in a.dropFirst() {
                if ch == "c" { return true }
                if ch == "e" || ch == "f" { break }   // `-ve 'x'` 這類：後面是樣式
            }
        }
        i += 1
    }
    return false
}

/// 一個命令若恰是自證閘，回 (片段, binary 名, 有沒有 `LC_ALL=C`)。binary 名取 `"$(command -v X)"` 的 X，或路徑的最後一段。
func selfProofGate(_ cmd: String) -> (needle: String, binary: String, strict: Bool)? {
    var t = selfProofTokens(cmd)
    var strict = false
    if t.first == "LC_ALL=C" { strict = true; t.removeFirst() }
    guard t.count == 5, t[0] == "grep", t[1] == "-a", t[2] == "-q" else { return nil }
    let target = t[4]
    let binary: String
    if target.hasPrefix("$(command -v "), target.hasSuffix(")") {
        binary = String(target.dropFirst("$(command -v ".count).dropLast())
    } else {
        binary = (target as NSString).lastPathComponent
    }
    return (t[3], binary, strict)
}

/// 被量的指令的來源 binary：`nil`＝不是 binary 的輸出（不在此列）；`.some("")`＝`"$out"`（binary 在別一行）。
private func selfProofSource(_ firstCommand: String) -> String? {
    guard let m = matches(firstCommand, selfProofSourceRe).first else { return nil }
    let ns = firstCommand as NSString
    for g in 1...2 where m.range(at: g).location != NSNotFound { return ns.substring(with: m.range(at: g)) }
    return ""
}

/// 回 (問題, 掃到幾條數 binary 輸出的指令, 掃到的閘)。
///
/// **單位**：fence 外是一行裡的每一段 inline code；fence 內是一行（先去掉行尾的 `#` 註解）。語言標記是 `text` 的 fence
/// 是**紀錄、不是可執行的量測**，不掃（第 71 列已退場的那個區塊就是這樣標的）。
///
/// **閘的判準（R1 起，#711 R1 verify 第 2、13、27 列）**：一條被量的管線前面那一個命令必須恰是自證閘，**以 `&&` 接過來**，
/// 而且閘查的 binary 與管線的來源是同一支。`;`／`||`／`&` 接的閘不算——閘失敗時被量的指令照跑、印 `0`，正是自證要防的事；
/// 較早一行的閘也不算（它擋不住下一行）。**不支援其他 fail-stop 寫法**（`set -e`、`if … then`、`|| exit`）：量測區塊沒有用到，
/// 加進來只會讓判準變寬——要用它們，先改這支。
///
/// **正對照**是另一種自證，只在 fence 內：一條被量的指令行尾寫 `# 正對照…`（它的期望值不是 0），同一個區塊裡它之後的計數都有了
/// 對照——讀的人看正對照是不是 0，就知道後面的 0 算不算數。它不靠控制流，所以不要求 `&&`。
///
/// **誠實邊界**：
/// · 只驗閘「在、接得上、查同一支 binary」，不驗片段是不是那條檢查**獨有**的（那要人判斷：片段選得太通用時，舊 binary 照樣通過）；
///   片段在不在 binary 裡由 `selfProofNeedleIssues` 另外查。
/// · 來源只認上面那幾種寫法；`"$res"`、不加引號的 `$out`、`cat f | grep -c` 這類以變數或檔案當來源的不算被量的指令——
///   不掃到就不會紅，這是漏報的方向。
/// · 正對照只驗「寫了」，不驗那一行的期望值真的不是 0。
func selfProofIssues(in rule: String) -> (issues: [String], checked: Int, gates: [(needle: String, binary: String, line: Int)]) {
    var issues: [String] = []
    var checked = 0
    var gates: [(needle: String, binary: String, line: Int)] = []
    var inFence = false, fenceIsRecord = false
    var blockProven = false   // 本 fence 區塊裡，較早的一行是正對照
    /// 一個單位：記下閘、判每一條被量的管線。回這個單位裡有沒有被量的管線。
    func judge(_ unit: String, line: Int, inherited: Bool) -> Bool {
        let list = selfProofShellList(unit)
        var counted = false
        for (i, pipe) in list.pipelines.enumerated() {
            if pipe.count == 1, let g = selfProofGate(pipe[0]), g.strict { gates.append((g.needle, g.binary, line)) }
            guard pipe.count >= 2, let source = selfProofSource(pipe[0]),
                  pipe.dropFirst().contains(where: selfProofIsCount) else { continue }
            checked += 1
            counted = true
            if inherited { continue }
            let head = String(unit.prefix(70))
            let before: (cmd: String, join: String)? = i > 0 && list.pipelines[i - 1].count == 1
                ? (list.pipelines[i - 1][0], list.joins[i - 1]) : nil
            if let b = before, let g = selfProofGate(b.cmd) {
                if !g.strict {
                    issues.append("第 \(line) 行的量測指令有 `grep -a -q` 閘卻沒有 `LC_ALL=C`——macOS 的 `/usr/bin/grep` 在 UTF-8 locale 下"
                                  + "對 binary 比不到中文，閘會誤判成「沒有這條檢查」：`\(head)…`")
                } else if b.join != "&&" {
                    issues.append("第 \(line) 行的量測指令與自證閘之間是 `\(b.join)` 不是 `&&`——閘失敗時被量的指令照跑、印 `0`，"
                                  + "與「檢查過且乾淨」分不開：`\(head)…`")
                } else if source.isEmpty || g.binary != source {
                    let what = source.isEmpty ? "`\"$out\"`（它的 binary 在別一行，閘綁不上）" : "`\(source)`"
                    issues.append("第 \(line) 行的自證閘查的是 `\(g.binary)`，被量的卻是 \(what)——閘證明不了被量的那支 binary "
                                  + "有這條檢查：`\(head)…`")
                }
                continue
            }
            if let b = before, !matches(b.cmd, selfProofLooseGateRe).isEmpty {
                issues.append("第 \(line) 行的量測指令有 `grep -a -q` 閘卻沒有 `LC_ALL=C`——macOS 的 `/usr/bin/grep` 在 UTF-8 locale 下"
                              + "對 binary 比不到中文，閘會誤判成「沒有這條檢查」：`\(head)…`")
                continue
            }
            issues.append("第 \(line) 行的量測指令數 binary 的輸出，卻沒有自證閘：`\(head)…`——舊 binary 沒有這條檢查時它印 `0`，"
                          + "與「檢查過且乾淨」分不開。前面以 `&&` 接 `LC_ALL=C grep -a -q '<這條檢查獨有的訊息片段>' \"$(command -v akashic)\"`"
                          + "（查同一支 binary），或在同一個區塊較早的一條量測行尾寫 `# 正對照`（期望值不是 0 的那條）")
        }
        return counted
    }
    for (i, l) in rule.components(separatedBy: "\n").enumerated() {
        let line = i + 1
        let trimmed = l.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") {
            if inFence { inFence = false; fenceIsRecord = false }
            else { inFence = true; fenceIsRecord = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces) == "text" }
            blockProven = false
            continue
        }
        if inFence {
            if fenceIsRecord { continue }
            let (code, comment) = selfProofSplitComment(l)
            let isControl = comment.map { !matches($0, selfProofControlRe).isEmpty } ?? false
            let counted = judge(code, line: line, inherited: blockProven || isControl)
            if counted && isControl { blockProven = true }
        } else {
            for m in matches(l, #"`([^`\n]+)`"#) {
                let (code, comment) = selfProofSplitComment((l as NSString).substring(with: m.range(at: 1)))
                let isControl = comment.map { !matches($0, selfProofControlRe).isEmpty } ?? false
                _ = judge(code, line: line, inherited: isControl)
            }
        }
    }
    return (issues, checked, gates)
}

// MARK: - 閘的片段要在 binary 裡、而且不能是負控自己種進去的（#711 R1）

/// **最短的字面段**：Swift 對 15 位元組以內的字串字面段在最佳化建置裡當成 small string 的 immediate 嵌進指令，
/// 位元組不連續地出現在 binary 裡——`LC_ALL=C grep -a -q` 在 release 版找不到它（#711 R1 verify 第 3、5、10 列實測：
/// 第 34 列的 `隸屬 key「`、第 36 列的 `個 venue 上` 各 13 位元組，debug 版找得到、release 版找不到）。
/// 判準是「片段是某個 ≥16 位元組的字面段的子字串」，不是片段本身的長度：`死 verdict`（11 位元組）在較長的字面段裡，release 版找得到。
let selfProofMinLiteralSegmentBytes = 16

/// 負控的 harness 檔：`*Mutations.swift`、`*MutationsData.swift`（`swift-is-the-implementation-language`：守衛的負對照寫成
/// `*-mutations` 子命令）。它們與守衛編進同一支 `akashic-guards`，所以它們的字面段裡出現的片段會讓對 `akashic-guards` 的閘成立，
/// 即使真正的檢查已經不在（#711 R1 verify 第 6、11 列：第 71 列的閘被 `audit-guards-mutations` 的錨字串滿足）。
func selfProofIsHarness(_ rel: String) -> Bool {
    rel.hasSuffix("Mutations.swift") || rel.hasSuffix("MutationsData.swift")
}

/// Swift 原始碼裡每個字串字面段（UTF-8 位元組；插值 `\( … )` 是段的邊界；常見的逃脫已解碼；註解不算）。
/// 支援一般、多行（`"""`）與 raw（`#"…"#`）字串。正規式字面（`/…/`）不處理——這個 repo 的 Sources 沒有用到。
func swiftStringLiteralSegments(_ src: String) -> [[UInt8]] {
    let b = Array(src.utf8)
    let n = b.count
    var out: [[UInt8]] = []
    var i = 0
    func at(_ k: Int, _ s: [UInt8]) -> Bool {
        guard k + s.count <= n else { return false }
        for j in 0..<s.count where b[k + j] != s[j] { return false }
        return true
    }
    let q: UInt8 = 0x22, bs: UInt8 = 0x5C, hash: UInt8 = 0x23, slash: UInt8 = 0x2F, star: UInt8 = 0x2A, nl: UInt8 = 0x0A
    while i < n {
        if b[i] == slash, i + 1 < n, b[i + 1] == slash { while i < n, b[i] != nl { i += 1 }; continue }
        if b[i] == slash, i + 1 < n, b[i + 1] == star {
            i += 2
            while i + 1 < n, !(b[i] == star && b[i + 1] == slash) { i += 1 }
            i += 2; continue
        }
        var k = i, hashes = 0
        while k < n, b[k] == hash { hashes += 1; k += 1 }
        guard k < n, b[k] == q else { i = hashes > 0 ? k : i + 1; continue }
        let multi = at(k, [q, q, q])
        i = k + (multi ? 3 : 1)
        let close = (multi ? [q, q, q] : [q]) + Array(repeating: hash, count: hashes)
        let esc = [bs] + Array(repeating: hash, count: hashes)
        var seg: [UInt8] = []
        while i < n {
            if at(i, close) { i += close.count; break }
            if !multi, b[i] == nl { break }
            if at(i, esc) {
                var e = i + esc.count
                guard e < n else { i = n; break }
                switch b[e] {
                case 0x28:   // `(`：插值，段的邊界
                    out.append(seg); seg = []
                    var depth = 1
                    e += 1
                    while e < n, depth > 0 { if b[e] == 0x28 { depth += 1 } else if b[e] == 0x29 { depth -= 1 }; e += 1 }
                    i = e; continue
                case 0x75 where e + 1 < n && b[e + 1] == 0x7B:   // `\u{…}`
                    var j = e + 2, hex = ""
                    while j < n, b[j] != 0x7D { hex.unicodeScalars.append(Unicode.Scalar(b[j])); j += 1 }
                    if let v = UInt32(hex, radix: 16), let s = Unicode.Scalar(v) { seg += Array(String(s).utf8) }
                    i = j + 1; continue
                case 0x6E: seg.append(0x0A)   // n
                case 0x74: seg.append(0x09)   // t
                case 0x72: seg.append(0x0D)   // r
                case 0x30: seg.append(0x00)   // 0
                default:   seg.append(b[e])   // \" \' \\
                }
                i = e + 1; continue
            }
            seg.append(b[i]); i += 1
        }
        out.append(seg)
    }
    return out
}

/// `haystack` 的 UTF-8 位元組裡有沒有 `needle`（`memmem`，不經 String 的比較語意）。
private func bytesContain(_ haystack: String, _ needle: [UInt8]) -> Bool {
    var h = haystack
    return h.withUTF8 { hb in
        needle.withUnsafeBytes { nb in
            guard let hp = hb.baseAddress, let np = nb.baseAddress, !needle.isEmpty else { return false }
            return memmem(hp, hb.count, np, nb.count) != nil
        }
    }
}

/// 閘的片段兩個條件（#711 R1）：
/// 1. **在那支 binary 的原始碼裡、而且在一個 ≥ `selfProofMinLiteralSegmentBytes` 位元組的字面段裡**——否則 release 版找不到它，
///    閘把有這條檢查的 binary 讀成舊的（自證的反向誤判）。`akashic` 的原始碼＝`Sources/` 除了 `akashic-guards` 與 `akashic-mcp`
///    （沒有逐 target 解析依賴：一個只在 App 模組裡的字面段會讓這條誤過，release 版的實際 grep 才是終判）；`akashic-guards` 的原始碼＝
///    它自己的目錄、不含 harness 檔。
/// 2. 對 `akashic-guards` 的閘：**片段不得出現在 harness 檔的任何字面段裡**（見 `selfProofIsHarness`）。harness 要比對那段訊息時，
///    改用同一則訊息裡的另一段文字。
/// 只查 binary 是 `akashic`／`akashic-guards` 的閘（範本裡的 `<…>` 與 `…` 不在此列）。
func selfProofNeedleIssues(gates: [(needle: String, binary: String, line: Int)]) -> [String] {
    let relevant = gates.filter { $0.binary == "akashic" || $0.binary == "akashic-guards" }
    guard !relevant.isEmpty else { return [] }
    let needleBytes = Set(relevant.map(\.needle)).map { Array($0.utf8) }
    let sep = "\u{0}"
    var long: [String: String] = ["akashic": "", "akashic-guards": ""]
    var harness = ""
    for rel in swiftSources() {
        let module = rel.split(separator: "/").dropFirst().first.map(String.init) ?? ""
        let isGuards = module == "akashic-guards"
        guard !(module == "akashic-mcp"), let text = readFile(rel) else { continue }
        let isHarness = isGuards && selfProofIsHarness(rel)
        // 非 harness 檔先以原文篩：原文裡連片段都沒有，就不會有含它的字面段（片段跨逃脫寫法時這裡會漏，那是誤報的方向——第 1 條會紅）。
        // 用 `memmem`：5 MB 的 Sources × 三十個片段，Swift 的 `String.contains` 在 debug 版要好幾秒，而 audit-guards-mutations 跑這支十幾次
        guard isHarness || needleBytes.contains(where: { bytesContain(text, $0) }) else { continue }
        for seg in swiftStringLiteralSegments(text) {
            let s = String(decoding: seg, as: UTF8.self)
            if isHarness { harness += s + sep }
            else if seg.count >= selfProofMinLiteralSegmentBytes { long[isGuards ? "akashic-guards" : "akashic", default: ""] += s + sep }
        }
    }
    var out: [String] = []
    var seen = Set<String>()
    for g in relevant where seen.insert(g.binary + sep + g.needle).inserted {
        if long[g.binary]?.range(of: g.needle, options: .literal) == nil {
            out.append("第 \(g.line) 行的自證閘片段「\(g.needle)」不在 `\(g.binary)` 原始碼任何 ≥\(selfProofMinLiteralSegmentBytes) 位元組的字串字面段裡"
                       + "——最佳化建置會把 15 位元組以內的字面段當 immediate 嵌進指令，release 版的 binary 裡找不到它，"
                       + "閘會把有這條檢查的 binary 讀成舊的。改用同一則訊息裡較長字面段的一段")
        }
        if g.binary == "akashic-guards", harness.range(of: g.needle, options: .literal) != nil {
            out.append("第 \(g.line) 行的自證閘片段「\(g.needle)」出現在負控 harness（`*Mutations.swift`／`*MutationsData.swift`）的字串裡"
                       + "——它們編進同一支 `akashic-guards`，真的檢查不在時閘照樣成立。harness 改用那則訊息的另一段文字")
        }
    }
    return out
}
