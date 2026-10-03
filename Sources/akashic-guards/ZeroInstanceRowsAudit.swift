// `zero-instance-guards.md` 的裁決表：每一列裁決「寫」的守衛，程式裡真的有嗎？
//
// **契約（逐字取自 Python 版的 docstring，#433 第 3b 步）**：
//
//   表裡每一列都引一個 issue 編號。裁決是 ✅「寫」的列，那個編號必須出現在
//   `Sources/` 底下——也就是那個守衛真的被實作了。
//
// **另一條義務（#711）**：量測區塊裡每一條「對 binary 的輸出計數」的指令，必須帶自證——沒有的話，舊 binary 沒有那條檢查時
// 印的是 `0`，與「檢查過且乾淨」在輸出上分不開（第 13 列的自證就是為了防這件事）。#710 R1 verify 一次抓到二十多條沒有閘的，
// 說明卻都寫「同第 13 列的自證」——文字與指令分岔，而且是安靜的。R2（#711 R2 verify）起只收一種寫法：
// `LC_ALL=C grep -a -q '<片段>' <BIN> && <BIN> <參數> 2>&1 | grep -c '<樣式>'`，`<BIN>` 兩處逐字相同；同一個單位裡提到 binary 又有計數
// 而不合這個模板，就是錯誤。R1 是一個 shell 剖析器，每一輪 verify 都在它對 shell 的理解裡找到新的旁路——細節見 `selfProofIssues`
// 與 `selfProofNeedleIssues`。
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
    // #711 R1／R2：閘的片段四條——不含正規式字元、不太短、release 版找得到、不是負控自己種進 `akashic-guards` 的
    fails += selfProofNeedleIssues(gates: proof.gates)

    var out = "══ zero-instance 裁決表：\(rows.count) 列；量測指令 \(proof.checked) 條數 binary 輸出 ══\n"
    for f in fails { out += "  ✗ \(f)\n" }
    out += "\n══ " + (fails.isEmpty ? "每一列裁決「寫」的都找得到實作"
                                    : "**\(fails.count) 列有問題**") + " ══\n"
    FileHandle.standardOutput.write(Data(out.utf8))
    return fails.isEmpty ? 0 : 1
}


// MARK: - 量測指令的自證閘（#711；R2 起只收一種寫法）

/// **一條對 binary 輸出計數的量測只有一種合法寫法**（#711 R2）：
///
///     LC_ALL=C grep -a -q '<片段>' <BIN> && <BIN> <參數> 2>&1 | grep -c '<樣式>'
///
/// - `<BIN>` 兩處**逐字相同**，而且是路徑（`.build/debug/akashic`、`~/bin/akashic`）或 `"$(command -v akashic)"`
///   （`akashic-guards` 同）。裸名不收：`grep -a -q '…' akashic` 讀的是工作目錄裡叫 `akashic` 的檔，不是那支 binary。
/// - `<參數>` 以子命令或選項開頭，不含 `|`、`&`、`;`、反引號、反斜線、括號、`<`、`>`——所以沒有第二條管線、`$( … )`、子 shell、
///   接續行、here-doc 或別的重導向（`2>&1` 是模板自己的）。
/// - 整個單位（fence 內一行、fence 外一段 inline code）就是這一條指令，行尾至多一段 `#` 註解。
/// - `<片段>` 與 `<樣式>` 以單引號包、不含單引號；片段另有三條（`selfProofNeedleIssues`）。
///
/// **為什麼收縮而不是擴充剖析器**：R1 的判準是一個 shell 剖析器（閘以 `&&` 接上、查同一支 binary），R1 verify 的每一席都在它對 shell
/// 的理解裡找到新的旁路——只比檔名、前導或尾端的 `||`、`if`／`for`／`{ }`、`$( … )`、`time`／`env` 前綴（#711 R2 verify 第 0、1、7、
/// 11–14、16、20、22、23 列）。剖析任意 shell 是一場軍備競賽；封閉的模板沒有旁路可找：**一個單位裡同時出現 binary 與計數，就必須逐字
/// 符合它，否則是錯誤、具名那一行**。R1 的「認不出來就靜默跳過」不再存在。
let selfProofTemplate = "LC_ALL=C grep -a -q '<片段>' <BIN> && <BIN> <參數> 2>&1 | grep -c '<樣式>'"

/// `<BIN>`：`"$(command -v akashic)"`、`"$(command -v akashic-guards)"`，或結尾是這兩個名字的路徑（至少一個 `/`）。
private let selfProofBinPattern = #"(?:"\$\(command -v (?:akashic|akashic-guards)\)"|(?:[\w.~-]*/)+(?:akashic|akashic-guards))"#
/// 模板本身。第 1 組＝片段、第 2 組＝BIN（第二處以 `\2` 要求逐字相同）、第 3 組＝參數、第 4 組＝樣式。
private let selfProofTemplateRe =
    #"^LC_ALL=C grep -a -q '([^']+)' ("# + selfProofBinPattern + #") && \2 ([a-z-][^|&;`\\()<>\n]*?) 2>&1 \| grep -c '([^']+)'$"#
/// 同上而兩處 BIN 各自獨立——只用來在錯誤訊息裡說出「兩處不是同一個」，判準是上面那一條。
private let selfProofLooseTemplateRe =
    #"^LC_ALL=C grep -a -q '[^']+' ("# + selfProofBinPattern + #") && ("# + selfProofBinPattern
    + #") [a-z-][^|&;`\\()<>\n]*? 2>&1 \| grep -c '[^']+'$"#

/// 單位裡**提到**這兩支 binary 的任何寫法：裸名、路徑、`$(command -v …)`——`swift run akashic`、`n=$(akashic …)`、`time akashic`、
/// `{ akashic …; }` 都算。`~/.akashic`、`akashic-mcp`、`akashic.sources`、`Sources/akashic/…`、`akashic_doctor` 不是執行它的寫法，不算。
private let selfProofBinaryMentionRe = #"(?<![\w.~/-])(?:[\w.~-]*/)*(?:akashic-guards|akashic)(?![\w./-])"#
/// 單位裡有計數：`grep`／`egrep`／`fgrep`／`rg` 帶 `-c`（選項串任何位置）或 `--count`；`wc` 帶 `-l` 或 `--lines`。
private let selfProofCountMentionRe =
    #"\b(?:[ef]?grep|rg)\b[^|;&\n]*\s(?:-[A-Za-z]*c[A-Za-z]*|--count)(?![\w-])|\bwc\b[^|;&\n]*\s(?:-[A-Za-z]*l[A-Za-z]*|--lines)(?![\w-])"#

/// **退場標記**：寫在 ```` ```text ```` fence 的**前一行**，那個 fence 是已退場的紀錄、不掃（第 71 列）。只對 `text` fence 有作用。
/// 沒有它的 `text` fence 照掃，裡面有量測就是錯誤——`text` 這個語言標記本身不再是出口（#711 R2 verify 第 9、18 列：R1 對任何
/// `text` fence 一律不掃，換個語言標記就能讓一條沒有閘的量測安靜通過）。
let selfProofRetiredMarker = "<!-- zero-instance-rows-audit: 已退場的量測紀錄，不掃 -->"

/// 一行（已 trim）若是 fence 的分隔線，回 (字元, 長度, info)。反引號 fence 的 info 不得含反引號（CommonMark：那是 inline code）。
private func selfProofFenceDelimiter(_ trimmed: String) -> (char: Character, count: Int, info: String)? {
    guard let c = trimmed.first, c == "`" || c == "~" else { return nil }
    let run = trimmed.prefix { $0 == c }.count
    guard run >= 3 else { return nil }
    let info = String(trimmed.dropFirst(run)).trimmingCharacters(in: .whitespaces)
    if c == "`", info.contains("`") { return nil }
    return (c, run, info)
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

/// `<BIN>` 的 binary 名：`"$(command -v X)"` 取 X，路徑取最後一段。只用來決定片段該在哪支 binary 的原始碼裡找——判準是兩處逐字相同。
private func selfProofBinaryName(_ bin: String) -> String {
    let prefix = "\"$(command -v "
    if bin.hasPrefix(prefix), bin.hasSuffix(")\"") { return String(bin.dropFirst(prefix.count).dropLast(2)) }
    return (bin as NSString).lastPathComponent
}

/// 回 (問題, 掃到幾條數 binary 輸出的指令, 掃到的閘)。
///
/// **單位**：fence 內一行；fence 外一行裡的每一段 inline code。先去掉行尾的 `#` 註解，同時提到 `akashic`／`akashic-guards` 與計數的
/// 單位就是一條量測，必須逐字符合 `selfProofTemplate`。
///
/// **fence**：```` ``` ```` 與 `~~~` 都認；收尾是同一個字元、長度不短於開頭、沒有 info 的一行。fence 裡出現一行長得像**新** fence 開頭的
/// （同字元、夠長、帶 info，例如 ```` ```bash ````），那是前一個 fence 沒有收尾——報錯並指名開頭那一行；檔尾還在 fence 裡也報錯。
/// R1 對任何 ```` ``` ```` 開頭的行都切換內外、檔尾不檢查：第 80／81 列的區塊漏了收尾，之後整份檔內外顛倒，新加的量測區塊
/// 完全不被掃、守衛照樣綠（#711 R2 verify 第 2、4、5、6 列）。
///
/// **`text` fence**：前一行是 `selfProofRetiredMarker` 的不掃；其餘照掃，裡面的量測一律是錯誤（紀錄要標退場，還在用的改成 `bash` fence）。
///
/// **正對照不再讓別行繼承**（#711 R2 verify 第 14 列：一行 `akashic-guards` 的正對照替後面一條 `akashic` 的計數背書）——每一條量測各自
/// 符合模板。
///
/// **誠實邊界**：
/// · 只驗形狀，不驗片段是不是那條檢查**獨有**的（要人判斷）；片段的三條另見 `selfProofNeedleIssues`。
/// · 辨識靠字面的 binary 名：以變數或檔案當來源的計數（`out=$(akashic …)` 一行、`printf '%s' "$out" | grep -c` 另一行、
///   `cat f | grep -c`）不提到 binary，不算量測——掃不到就不會紅（第 71 列的補記區塊就是這一種，它的自證是說明文字）。
///   同一行裡兩者都有就算，而那樣寫不會是模板，所以是錯誤。
/// · 計數只認 `grep`／`egrep`／`fgrep`／`rg` 的 `-c`／`--count` 與 `wc -l`／`--lines`；`awk` 自己加總的寫法認不出來。
/// · 一個單位裡 `-c` 出現在 grep 的樣式字串裡（`grep 'a -c b'`）也會被當成計數——那是誤報的方向，具名那一行。
func selfProofIssues(in rule: String) -> (issues: [String], checked: Int, gates: [(needle: String, binary: String, line: Int)]) {
    var issues: [String] = []
    var checked = 0
    var gates: [(needle: String, binary: String, line: Int)] = []
    /// 一個單位。`textFenceLine`：它在一個沒有退場標記的 `text` fence 裡（值是 fence 開頭的行號）。
    func judge(_ raw: String, line: Int, textFenceLine: Int?) {
        let code = selfProofSplitComment(raw).code.trimmingCharacters(in: .whitespaces)
        guard !matches(code, selfProofBinaryMentionRe).isEmpty, !matches(code, selfProofCountMentionRe).isEmpty else { return }
        checked += 1
        let head = String(code.prefix(200))
        if let open = textFenceLine {
            issues.append("第 \(line) 行在第 \(open) 行開的 `text` fence 裡對 binary 的輸出計數，而那個 fence 的前一行不是退場標記"
                          + "「\(selfProofRetiredMarker)」：`\(head)`——已退場的紀錄在 fence 前一行加上標記；還在用的量測改成 `bash` fence、"
                          + "寫成 `\(selfProofTemplate)`")
            return
        }
        let ns = code as NSString
        if let m = matches(code, selfProofTemplateRe).first {
            gates.append((ns.substring(with: m.range(at: 1)), selfProofBinaryName(ns.substring(with: m.range(at: 2))), line))
            return
        }
        var hint = ""
        if let m = matches(code, selfProofLooseTemplateRe).first {
            hint = "——閘查的是 `\(ns.substring(with: m.range(at: 1)))`，被量的是 `\(ns.substring(with: m.range(at: 2)))`："
                + "兩處要逐字相同（只比檔名時，閘證明的可能是另一個檔）"
        }
        issues.append("第 \(line) 行對 binary 的輸出計數，卻不是唯一合法的寫法 `\(selfProofTemplate)`：`\(head)`\(hint)。"
                      + "<BIN> 兩處逐字相同、是路徑或 `\"$(command -v …)\"`；整個單位只有這一條指令——前後不接 `;`／`||`／`|`、"
                      + "不包在 `if`／`$( … )`／`{ }` 裡、不以 `\\` 接續——行尾至多一段 `#` 註解。不合模板的寫法在沒有那條檢查的"
                      + "舊 binary 上照樣印 `0`，與「檢查過且乾淨」分不開")
    }
    var fence: (char: Character, count: Int, info: String, line: Int, retired: Bool)? = nil
    var previous = ""
    for (i, l) in rule.components(separatedBy: "\n").enumerated() {
        let line = i + 1
        let trimmed = l.trimmingCharacters(in: .whitespaces)
        defer { previous = trimmed }
        if let f = fence {
            if let d = selfProofFenceDelimiter(trimmed), d.char == f.char, d.count >= f.count {
                if d.info.isEmpty { fence = nil; continue }
                issues.append("第 \(line) 行「\(String(trimmed.prefix(20)))」是新 fence 的開頭，卻落在第 \(f.line) 行開的 fence 裡"
                              + "——第 \(f.line) 行的 fence 沒有收尾，之後整份檔的 fence 內外會顛倒、量測區塊不被掃。在它前面補上收尾的一行")
                fence = (d.char, d.count, d.info, line, false)   // 依作者的意圖從這一行重新開始，後面的錯誤才指得準
                continue
            }
            if f.retired { continue }
            judge(l, line: line, textFenceLine: f.info.split(separator: " ").first == "text" ? f.line : nil)
            continue
        }
        if let d = selfProofFenceDelimiter(trimmed) {
            let isText = d.info.split(separator: " ").first == "text"
            fence = (d.char, d.count, d.info, line, isText && previous == selfProofRetiredMarker)
            continue
        }
        for m in matches(l, #"`([^`\n]+)`"#) {
            judge((l as NSString).substring(with: m.range(at: 1)), line: line, textFenceLine: nil)
        }
    }
    if let f = fence {
        issues.append("第 \(f.line) 行開的 fence 到檔尾都沒有收尾——之後整份檔被當成 fence 內，量測的判讀會錯。補上收尾的一行")
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

/// 片段的最短長度（#711 R2 verify 第 17 列）：`a`、`.` 這種片段在任何 binary 裡都找得到，閘恆真。下限 8 位元組＝三個以上的中文字，
/// 或一個比 `venue`（5）、`verdict`（7）長的英文片段——這兩個字在 `akashic` 裡到處都是。這是粗的防線，**不驗**片段是那條檢查獨有的
/// （那要人判斷）。2026-10-02 規則檔裡最短的片段是 `求值總量`（12 位元組）。
let selfProofMinNeedleBytes = 8

/// `grep -a -q` 把片段當**基本正規式**，守衛卻把它當字面比對：`.`、`*` 讓閘對任何非空檔成立，`[` 讓 grep 結束碼是 2（閘恆失敗）。
/// 片段不得含這些字元（#711 R2 verify 第 17 列）——選「拒收」而不是改寫成 `grep -F`：模板只有一種寫法，加一個 `-F` 的變體就是第二種。
let selfProofNeedleMetacharacters: Set<Character> = [".", "[", "]", "*", "^", "$", "\\"]

/// 閘的片段四個條件（#711 R1、R2）：
/// 1. **不含基本正規式的特殊字元**（`selfProofNeedleMetacharacters`）、**不短於 `selfProofMinNeedleBytes`**（R2）。
/// 2. **在那支 binary 的原始碼裡**——任何字串字面段都沒有的片段，是訊息改了字、或那條檢查已移除（R2 verify 第 21 列：R1 對這種情形
///    與下一條印同一句話，把維護者導向字面段長度）。
/// 3. **在一個 ≥ `selfProofMinLiteralSegmentBytes` 位元組的字面段裡**——否則 release 版找不到它，閘把有這條檢查的 binary 讀成舊的
///    （自證的反向誤判）。`akashic` 的原始碼＝`Sources/` 除了 `akashic-guards` 與 `akashic-mcp`（沒有逐 target 解析依賴：一個只在 App
///    模組裡的字面段會讓這條誤過，release 版的實際 grep 才是終判）；`akashic-guards` 的原始碼＝它自己的目錄、不含 harness 檔。
/// 4. 對 `akashic-guards` 的閘：**片段不得出現在 harness 檔的任何字面段裡**（見 `selfProofIsHarness`）。harness 要比對那段訊息時，
///    改用同一則訊息裡的另一段文字。
/// 只查 binary 是 `akashic`／`akashic-guards` 的閘（模板只收這兩支）。
func selfProofNeedleIssues(gates: [(needle: String, binary: String, line: Int)]) -> [String] {
    let relevant = gates.filter { $0.binary == "akashic" || $0.binary == "akashic-guards" }
    guard !relevant.isEmpty else { return [] }
    let needleBytes = Set(relevant.map(\.needle)).map { Array($0.utf8) }
    let sep = "\u{0}"
    var long: [String: String] = ["akashic": "", "akashic-guards": ""]
    var anyLength: [String: String] = ["akashic": "", "akashic-guards": ""]
    var harness = ""
    for rel in swiftSources() {
        let module = rel.split(separator: "/").dropFirst().first.map(String.init) ?? ""
        let isGuards = module == "akashic-guards"
        guard !(module == "akashic-mcp"), let text = readFile(rel) else { continue }
        let isHarness = isGuards && selfProofIsHarness(rel)
        // 非 harness 檔先以原文篩：原文裡連片段都沒有，就不會有含它的字面段（片段跨逃脫寫法時這裡會漏，那是誤報的方向——第 2 條會紅）。
        // 用 `memmem`：5 MB 的 Sources × 三十個片段，Swift 的 `String.contains` 在 debug 版要好幾秒，而 audit-guards-mutations 跑這支十幾次
        guard isHarness || needleBytes.contains(where: { bytesContain(text, $0) }) else { continue }
        let bin = isGuards ? "akashic-guards" : "akashic"
        for seg in swiftStringLiteralSegments(text) {
            let s = String(decoding: seg, as: UTF8.self)
            if isHarness { harness += s + sep; continue }
            anyLength[bin, default: ""] += s + sep
            if seg.count >= selfProofMinLiteralSegmentBytes { long[bin, default: ""] += s + sep }
        }
    }
    var out: [String] = []
    var seen = Set<String>()
    for g in relevant where seen.insert(g.binary + sep + g.needle).inserted {
        let meta = Set(g.needle).intersection(selfProofNeedleMetacharacters)
        if !meta.isEmpty {
            out.append("第 \(g.line) 行的自證閘片段「\(g.needle)」含基本正規式的特殊字元（\(meta.sorted().map { "`\($0)`" }.joined(separator: "、"))）"
                       + "——`grep -a -q` 把片段當正規式：`.`、`*` 讓閘對任何非空檔成立，`[` 讓 grep 出錯、閘恆失敗。"
                       + "改用同一則訊息裡不含 `.[]*^$\\` 的一段")
        }
        if g.needle.utf8.count < selfProofMinNeedleBytes {
            out.append("第 \(g.line) 行的自證閘片段「\(g.needle)」只有 \(g.needle.utf8.count) 位元組（下限 \(selfProofMinNeedleBytes)）"
                       + "——太短的片段在任何版本的 binary 裡都找得到，閘恆真。改用同一則訊息裡較長的一段")
        }
        if anyLength[g.binary]?.range(of: g.needle, options: .literal) == nil {
            out.append("第 \(g.line) 行的自證閘片段「\(g.needle)」在 `\(g.binary)` 的原始碼裡找不到（任何字串字面段都沒有）"
                       + "——訊息改了字、或那條檢查已移除。更新這一列的閘與量測，讓它們對著現在的訊息")
        } else if long[g.binary]?.range(of: g.needle, options: .literal) == nil {
            out.append("第 \(g.line) 行的自證閘片段「\(g.needle)」只在 `\(g.binary)` 原始碼裡短於 \(selfProofMinLiteralSegmentBytes) 位元組的字串字面段裡"
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
