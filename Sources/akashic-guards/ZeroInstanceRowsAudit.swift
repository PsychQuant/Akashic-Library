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
// 而不合這個模板，就是錯誤。R1 是一個 shell 剖析器，每一輪 verify 都在它對 shell 的理解裡找到新的旁路。R3（#711 R3 verify）：模板封閉，
// 「哪些文字是一個單位」原本不是——拆在兩行、寫在 fence 與 inline code 以外、計數寫法沒被認出的量測不成單位；R3 補寬辨識，另加一個不靠
// 辨識的條數地板（棘輪標記）。R4（#711 R4 verify）：R3 仍在列舉寫法，R4 反過來——認不出時偏向「是量測」與「同一個單位」，模板加上
// 前置條件（`: "${V:?…}" && test -f …`），退場標記拿掉。細節見 `selfProofIssues`、`selfProofRatchetIssues` 與 `selfProofNeedleIssues`。
//
// **兩份檔**（#711，使用者 2026-10-05 裁決）：裁決表住在規則檔，各列的量測、歷輪補記與棘輪標記住在不自動載入的
// `docs/zero-instance-measurements.md`。表格、列號與共通段的檢查只讀規則檔；自證閘兩份都掃（表格裡仍可能有量測）。
// 量測寫法的通則抽成規則 `measurement-commands-self-prove`，它引用的模板是 `selfProofTemplate` 的第二份描述，所以另查兩者逐字相同。
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

/// 裁決表的規則檔。
let zeroInstanceRulePath = ".claude/rules/zero-instance-guards.md"
/// 各列的量測與歷輪補記（#711，使用者 2026-10-05 裁決）：規則檔每個 session 自動載入，量測腳本與逐輪補記搬到這份不自動載入的文件。
/// 自證閘兩份都掃；棘輪標記住在這裡。
let zeroInstanceMeasurementsPath = "docs/zero-instance-measurements.md"
/// 量測寫法的通則從規則檔抽成的獨立規則（#711）。它引用 `selfProofTemplate`——那是第二份描述，所以守衛查兩者逐字相同。
let selfProofTemplateRulePath = ".claude/rules/measurement-commands-self-prove.md"

func zeroInstanceRowsAudit() -> Int32 {
    let rulePath = zeroInstanceRulePath
    guard let rule = readFile(rulePath) else {
        FileHandle.standardError.write(Data("✗ 找不到 \(rulePath)\n".utf8))
        return 1
    }
    // 量測文件不在不是「沒有量測」：兩者在輸出上要分得開（第 3 列）
    guard let measurements = readFile(zeroInstanceMeasurementsPath) else {
        FileHandle.standardError.write(Data(("✗ 找不到 \(zeroInstanceMeasurementsPath)——各列的量測與棘輪標記住在那裡（#711），"
            + "它不在時自證閘與棘輪都沒有輸入\n").utf8))
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

    // **量測指令的自證閘**（#711）。規則檔與量測文件各掃一次——表格裡仍可能有量測（第 56 列），量測文件是它們主要住的地方。
    // 空掃描不是通過：量測文件裡一條都沒掃到，代表抽取式與檔的寫法脫節了。規則檔裡零條是正常的（量測本來就該住在量測文件）。
    let ruleProof = selfProofIssues(in: rule, file: rulePath)
    let docProof = selfProofIssues(in: measurements, file: zeroInstanceMeasurementsPath)
    if docProof.checked == 0 {
        fails.append("\(zeroInstanceMeasurementsPath) 裡對 binary 輸出計數的指令一條都沒掃到——"
                     + "抽取式與檔的寫法脫節了，自證閘的檢查等於沒跑")
    }
    fails += ruleProof.issues + docProof.issues
    let gates = ruleProof.gates + docProof.gates
    // 閘的片段的條件見 `selfProofNeedleIssues`（條數不寫在這裡——寫死的計數會與那份清單分岔，#711 R4 verify 第 18、34 列）
    fails += selfProofNeedleIssues(gates: gates)
    // #711 R3：條數的地板不靠辨識；R4 起依閘去重（`selfProofRatchetIssues`）；標記住在量測文件
    let ratchet = selfProofRatchetIssues(rule: rule, measurements: measurements, gates: gates)
    fails += ratchet.issues
    fails += selfProofTemplateCopyIssues(readFile(selfProofTemplateRulePath))
    let checked = ruleProof.checked + docProof.checked

    // 標題列印出條數與棘輪下限（R3 verify 第 7 列：條數掉了，審閱的人在輸出裡要看得到）
    var out = "══ zero-instance 裁決表：\(rows.count) 列；量測指令 \(checked) 條數 binary 輸出"
        + "（合模板 \(gates.count) 條、依閘去重 \(selfProofDistinctGates(gates)) 條，"
        + "棘輪下限 \(ratchet.floor.map(String.init) ?? "—")） ══\n"
    for f in fails { out += "  ✗ \(f)\n" }
    out += "\n══ " + (fails.isEmpty ? "每一列裁決「寫」的都找得到實作"
                                    : "**\(fails.count) 列有問題**") + " ══\n"
    FileHandle.standardOutput.write(Data(out.utf8))
    return fails.isEmpty ? 0 : 1
}


// MARK: - 量測指令的自證閘（#711；R2 起只收一種寫法；R4 起辨識偏向「是量測」、單位偏向合併）

/// **一條對 binary 輸出計數的量測只有一種合法寫法**（#711 R2；R4 加前置條件）：
///
///     [: "${V:?訊息}" && [test -f "$V/store.yaml" && ]]LC_ALL=C grep -a -q '<片段>' <BIN> && <BIN> <參數> 2>&1 | grep -c '<樣式>'
///
/// - `<BIN>` 兩處**逐字相同**，而且是路徑（`.build/debug/akashic`、`~/bin/akashic`）或 `"$(command -v akashic)"`
///   （`akashic-guards` 同）。裸名不收：`grep -a -q '…' akashic` 讀的是工作目錄裡叫 `akashic` 的檔，不是那支 binary。
/// - `<參數>` 以子命令或選項開頭，不含 `|`、`&`、`;`、`#`、單引號、反引號、反斜線、括號、`<`、`>`，雙引號成對——所以沒有第二條
///   管線、`$( … )`、子 shell、here-doc、別的重導向（`2>&1` 是模板自己的），也沒有讓 `2>&1 | grep -c` 落進註解或引號裡的寫法。
/// - **前置條件**（R4，#711 R4 verify 第 1、3、5 列）：`<參數>` 與 `test -f` 的路徑用到的每個變數都要列在最前面的
///   `: "${V:?…}"`（可以多個，空白隔開）；`<參數>` 有 `--library "$V"` 時另要 `test -f "$V/store.yaml"`。理由：`${V:?…}` 寫在管線裡
///   只結束那一段的子 shell，錯誤訊息走 stderr、右邊的 `grep -c` 照樣印 `0`——與「檢查過且乾淨」分不開；寫在 `&&` 串的最前面，整條不跑。
///   V 打錯成一個不是 store 的目錄時 `validate` 報錯、`grep -c` 一樣印 `0`，`doctor` 還會在那裡建出一個 store——`test -f` 擋這一半。
/// - 整個單位就是這一條指令、**寫在一行**——fence 裡的一行，或不跨行的一段 inline code；行尾至多一段 `#` 註解。
/// - `<片段>` 與 `<樣式>` 以單引號包、不含單引號；片段另有條件（`selfProofNeedleIssues`）。
///
/// **為什麼收縮而不是擴充剖析器**：R1 的判準是一個 shell 剖析器（閘以 `&&` 接上、查同一支 binary），R1 verify 的每一席都在它對 shell
/// 的理解裡找到新的旁路（#711 R2 verify 第 0、1、7、11–14、16、20、22、23 列）。剖析任意 shell 是一場軍備競賽；模板只有一種寫法，
/// 合不合只看逐字。模板以外的那一半——「哪些文字是一個單位、哪些單位是量測」——見 `selfProofIssues`。
let selfProofTemplate = "[: \"${V:?…}\" && [test -f \"$V/store.yaml\" && ]]LC_ALL=C grep -a -q '<片段>' <BIN> && <BIN> <參數> 2>&1 | grep -c '<樣式>'"

/// `<BIN>`：`"$(command -v akashic)"`、`"$(command -v akashic-guards)"`，或結尾是這兩個名字的路徑（至少一個 `/`）。
private let selfProofBinPattern = #"(?:"\$\(command -v (?:akashic|akashic-guards)\)"|(?:[\w.~-]*/)+(?:akashic|akashic-guards))"#
/// `<參數>` 的字元：不含 `#`（`… validate # x 2>&1 | grep -c 'y'` 的計數整段在註解裡）與單引號（引號能跨過 `2>&1 | grep -c`）。
private let selfProofArgsPattern = #"[a-z-][^|&;`'#\\()<>\n]*?"#
/// 前置條件裡的一個 `"${V:?訊息}"`。
private let selfProofGuardWord = #""\$\{[A-Za-z_][A-Za-z0-9_]*:\?[^"}\n]*\}""#
/// 前置條件：`: "${V:?…}"[ "${W:?…}"…] && ` 加上可有可無的 `test -f "<路徑>" && `。
private let selfProofPreconditionPattern = #"(?:: (?<guards>"# + selfProofGuardWord + #"(?: "# + selfProofGuardWord
    + #")*) && (?:test -f "(?<test>[^"\n]*)" && )?)?"#
/// 模板本身，行尾至多一段 `#` 註解。BIN 的第二處以 `\k<bin>` 要求逐字相同。
private let selfProofTemplateRe = try! NSRegularExpression(pattern:
    "^" + selfProofPreconditionPattern + #"LC_ALL=C grep -a -q '(?<needle>[^']+)' (?<bin>"# + selfProofBinPattern
    + #") && \k<bin> (?<args>"# + selfProofArgsPattern + #") 2>&1 \| grep -c '[^']+'(?:[ \t]+#.*)?$"#)
/// 同上而兩處 BIN 各自獨立——只用來在錯誤訊息裡說出「兩處不是同一個」，判準是上面那一條。
private let selfProofLooseTemplateRe = try! NSRegularExpression(pattern:
    "^" + selfProofPreconditionPattern + #"LC_ALL=C grep -a -q '[^']+' (?<gate>"# + selfProofBinPattern + #") && (?<measured>"#
    + selfProofBinPattern + #") "# + selfProofArgsPattern + #" 2>&1 \| grep -c '[^']+'(?:[ \t]+#.*)?$"#)
/// 單位開頭的前置條件（只有 `: "${V:?…}" && ` 那一段）——它裡面的 `${V:?…}` 不在管線裡。
private let selfProofLeadingGuardsRe = try! NSRegularExpression(pattern:
    #"^: "# + selfProofGuardWord + #"(?: "# + selfProofGuardWord + #")* && "#)
/// `${V:?…}`、`${V?…}`：沒設就讓 shell 停下的展開——只有不在管線裡時才停得下來。
private let selfProofRequiredExpansionRe = try! NSRegularExpression(pattern: #"\$\{[A-Za-z_][A-Za-z0-9_]*:?\?"#)
/// 一根管線：不是 `||` 的一部分的 `|`（`|&` 算）。
private let selfProofPipeRe = try! NSRegularExpression(pattern: #"(?<!\|)\|(?!\|)"#)

/// 單位裡**提到**這兩支 binary 的任何寫法（R4：不分大小寫——macOS 的檔案系統不分，`~/bin/Akashic` 跑得起來，#711 R4 verify 第 20 列）：
/// 裸名、路徑、`$(command -v …)`、參數展開的預設值——`swift run akashic`、`n=$(akashic …)`、`time akashic`、`{ akashic …; }`、
/// `${AKASHIC_BIN:-akashic}`、`${X-akashic}`、`${X:=akashic}`、`"$AKASHIC"` 都算。判準是 shell 的字邊界：名字前面不是字、`.`、`~`、`/`，
/// 也不是「字－連字號」（`che-akashic` 是另一個名字）——**參數展開的運算子是字邊界**，所以 `${X-akashic}` 的 `-` 前面雖然是字，
/// 照樣算（R4 verify 第 4 列：R3 的 lookbehind 把它與 `che-akashic` 一起排除）。後面不是字、`.`、`/`、`-`：
/// `~/.akashic`、`akashic-mcp`、`akashic.sources`、`Sources/akashic/…`、`akashic_doctor`、`Akashic-Library` 不是執行它的寫法。
private let selfProofBinaryMentionRe = try! NSRegularExpression(pattern:
    #"(?i)(?<![\w.~/])(?:(?<![\w.~/-]-)|(?<=\$\{[A-Za-z_][A-Za-z0-9_]{0,63}-))(?:[\w.~-]*/)*(?:akashic-guards|akashic)(?![\w./-])"#)
/// 計數的選項：`-c`（併在選項串裡也算，例如 `-Ec`）、以 `--cou` 開頭的長選項（`--count`、它的縮寫、`--count-matches`、`--count=…`），
/// 前後可以有引號（`grep '-c' …`）。
private let selfProofCountOption = #"(?<![\w-])['"]?(?:-[A-Za-z]*c[A-Za-z]*|--cou[\w-]*)(?:=[^\s'"]*)?['"]?(?![\w-])"#
private let selfProofCountOptionRe = try! NSRegularExpression(pattern: selfProofCountOption)
/// 會因計數選項而計數的命令：名字以 `grep` 結尾的任何命令（`grep`、`egrep`、`zgrep`、`ggrep`、`pcregrep`、`ugrep`…——R4 verify 第 4、7、12 列：
/// R3 只認 `[ef]?grep`）與 `rg`／`ag`／`ack`／`uniq`。
private let selfProofCountToolRe = try! NSRegularExpression(pattern: #"(?<![\w.-])(?:\w*grep|rg|ag|ack|uniq)(?![\w.-])"#)
private let selfProofWcRe = try! NSRegularExpression(pattern: #"(?<![\w.-])wc(?![\w.-])"#)
private let selfProofJqRe = try! NSRegularExpression(pattern: #"(?<![\w.-])jq(?![\w.-])"#)
private let selfProofLengthRe = try! NSRegularExpression(pattern: #"\blength\b"#)
/// grep 家族：管線裡這個命令沒有計數選項時是過濾、有就是計數。
private let selfProofGrepFamilyRe = try! NSRegularExpression(pattern: #"^(?:\w*grep|rg|ag|ack)$"#)
/// **已知不計數的顯示命令**（封閉列舉，R4）：binary 的輸出經管線送進它，不算計數。清單外的命令一律當成計數——認不出來的方向是判成量測
/// （紅、具名那一行，作者改成模板或把命令加進這裡並寫理由），不是放行。
/// · `head`：只截前幾行，不產生數字（第 19 列的 `… zero-instance-rows-audit 2>&1 | head -1`）。
/// · 沒有計數選項的 grep 家族（`selfProofGrepFamilyRe`）：只挑行（第 49 列的 `… doctor … | grep -E '^orphaned…'`）。
/// `tail`、`sort`、`sed`、`awk`、`nl`、`python3`、`while read` 都不在清單裡：`grep -n … | tail -n 1`、`nl | tail -1`、`awk 'END{print NR}'`、
/// `sed -n '$='` 都數得出行數（R4 verify 第 12、20 列）。
let selfProofDisplayFilters: Set<String> = ["head"]

private func selfProofFirstMatch(_ re: NSRegularExpression, _ s: String) -> NSTextCheckingResult? {
    re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length))
}
private func selfProofLastMatch(_ re: NSRegularExpression, _ s: String) -> NSTextCheckingResult? {
    re.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length)).last
}

/// 單位裡**有計數**：計數命令之後任何位置出現計數選項；任何 `wc`；`jq` 之後出現 `length`。
/// **線性**（R4 verify 第 16 列：R3 的 `[\s\S]*?` 讓每個工具名各往行尾惰性掃一次，一行數萬個 `grep` 要幾十秒）：只比「第一個計數命令」與
/// 「最後一個計數選項」的位置。寬是故意的：一個單位裡 `grep` 之後出現在**別的命令**的 `-c`（`grep x f; python3 -c …`）也算——誤認的方向。
func selfProofHasCount(_ s: String) -> Bool {
    if selfProofFirstMatch(selfProofWcRe, s) != nil { return true }
    if let t = selfProofFirstMatch(selfProofCountToolRe, s), let o = selfProofLastMatch(selfProofCountOptionRe, s),
       o.range.location > t.range.location { return true }
    if let j = selfProofFirstMatch(selfProofJqRe, s), let l = selfProofLastMatch(selfProofLengthRe, s),
       l.range.location > j.range.location { return true }
    return false
}

/// 管線的一段（`|` 之後到下一個 `|` 之前）的命令會不會把輸入變成數字：前面的 `NAME=值` 環境設定跳過、前導的 `\` 與路徑去掉之後，
/// 是 grep 家族就看這一段有沒有計數選項，是 `selfProofDisplayFilters` 就不算，其餘一律算（包括這一段沒有命令）。
func selfProofStageCounts(_ stage: String) -> Bool {
    var words = stage.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
    while let w = words.first, w.range(of: #"^[A-Za-z_][A-Za-z0-9_]*="#, options: .regularExpression) != nil { words.removeFirst() }
    guard var cmd = words.first else { return true }
    cmd = String(cmd.drop { "\\\"'`({".contains($0) })
    if let slash = cmd.lastIndex(of: "/") { cmd = String(cmd[cmd.index(after: slash)...]) }
    if selfProofFirstMatch(selfProofGrepFamilyRe, cmd) != nil { return selfProofFirstMatch(selfProofCountOptionRe, stage) != nil }
    return !selfProofDisplayFilters.contains(cmd)
}

/// binary 的輸出經管線送進一個會計數的命令：從第一次提到 binary 之後，每一根管線（`selfProofPipeRe`）的那一段各問一次
/// `selfProofStageCounts`。管線不剖析引號——樣式裡的 `|`（`grep -E 'a|b'`）會被當成一根管線，切出的那一段多半不是已知的顯示命令、
/// 被判成計數：誤認的方向。
func selfProofPipesIntoCounter(_ s: String) -> Bool {
    guard let b = selfProofFirstMatch(selfProofBinaryMentionRe, s) else { return false }
    let ns = s as NSString
    let after = b.range.location + b.range.length
    let bars = selfProofPipeRe.matches(in: s, range: NSRange(location: after, length: ns.length - after)).map(\.range.location)
    for bar in bars {
        var start = bar + 1
        if start < ns.length, ns.character(at: start) == 0x26 { start += 1 }   // `|&`
        // 這一段到下一個 `|`（含 `||` 的第一個）為止
        let rest = NSRange(location: start, length: ns.length - start)
        let next = ns.range(of: "|", options: [], range: rest).location
        let end = next == NSNotFound ? ns.length : max(next, start)
        if selfProofStageCounts(ns.substring(with: NSRange(location: start, length: end - start))) { return true }
    }
    return false
}

/// 一個單位是不是一條量測：**提到 binary**，而且**有計數**——計數選項或計數命令（`selfProofHasCount`），或 binary 的輸出經管線送進一個
/// 不在已知顯示命令清單裡的命令（`selfProofPipesIntoCounter`；`pipes` 為 false 時不看——表格列裡的 `|` 是欄的分隔，不是管線）。
/// 兩者都看含註解的原文（R3 起不切註解）。
func selfProofIsMeasurement(_ s: String, pipes: Bool = true) -> Bool {
    guard selfProofFirstMatch(selfProofBinaryMentionRe, s) != nil else { return false }
    return selfProofHasCount(s) || (pipes && selfProofPipesIntoCounter(s))
}

/// `${V:?…}` 寫在管線裡（R4 verify 第 1、3、5 列）：回第一個那樣的展開，沒有回 nil。開頭的前置條件（`: "${V:?…}" && `）裡的不算；
/// 單位裡沒有管線時也不算（簡單指令裡的 `${V:?…}` 讓 shell 停下——第 49、77 列的 `python3 - "${STORE:?…}" <<'PY'` 就是）。
/// 有管線而它在別處——左邊、右邊、`$( … )` 裡——一律算：管線的每一段都在自己的子 shell 裡，那一段結束、其餘照跑。
func selfProofRequiredExpansionInPipeline(_ s: String) -> String? {
    let ns = s as NSString
    guard selfProofFirstMatch(selfProofPipeRe, s) != nil else { return nil }
    let start = selfProofFirstMatch(selfProofLeadingGuardsRe, s)?.range.length ?? 0
    return selfProofRequiredExpansionRe.firstMatch(in: s, range: NSRange(location: start, length: ns.length - start))
        .map { ns.substring(with: $0.range) }
}

/// 一行（已 trim）若是 fence 的分隔線，回 (字元, 長度, info)。反引號 fence 的 info 不得含反引號（CommonMark：那是 inline code）。
private func selfProofFenceDelimiter(_ trimmed: String) -> (char: Character, count: Int, info: String)? {
    guard let c = trimmed.first, c == "`" || c == "~" else { return nil }
    let run = trimmed.prefix { $0 == c }.count
    guard run >= 3 else { return nil }
    let info = String(trimmed.dropFirst(run)).trimmingCharacters(in: .whitespaces)
    if c == "`", info.contains("`") { return nil }
    return (c, run, info)
}

/// 剝掉引用區塊的前綴（`>`，前面至多三個空白、後面至多一個空白，可以多層），回 (內容, 層數)。R2 的 fence 判斷看的是 trim 過的行，
/// 引用區塊裡的 ```` ```bash ```` 首字是 `>`，整個 fence 不被認出（R3 verify 第 2、4、5、11 列）。
func selfProofStripBlockquote(_ line: String) -> (content: String, depth: Int) {
    var s = Substring(line), depth = 0
    while true {
        let spaces = s.prefix { $0 == " " }.count
        guard spaces <= 3, s.dropFirst(spaces).first == ">" else { break }
        s = s.dropFirst(spaces + 1)
        if s.first == " " { s = s.dropFirst() }
        depth += 1
    }
    return (String(s), depth)
}

/// 一個實體行是否接到下一行（shell 的接續）：去掉行尾空白後以奇數個 `\` 結尾；或以 `|`、`||`、`&&`、`|&` 結尾——行尾若有 `#` 註解，
/// 註解前那一段以它們結尾也算（`cmd |   # 計數` 在 shell 裡照樣接到下一行）。哪個 `#` 是註解的開頭不判斷：每一個前面是空白（或在行首）的
/// `#` 都試，任一個成立就接——接錯的方向是多判讀一個單位（誤報），不是放行。
/// **線性**（R4 verify 第 16 列：R3 對每個 `#` 各切一次前綴、各跑一次正規式）：一趟掃過，記住每個 `#` 之前最後一個非空白字元。
func selfProofContinues(_ s: String) -> Bool {
    let chars = Array(s)
    var end = chars.count
    while end > 0, chars[end - 1] == " " || chars[end - 1] == "\t" { end -= 1 }
    var backslashes = 0
    while backslashes < end, chars[end - 1 - backslashes] == "\\" { backslashes += 1 }
    if backslashes % 2 == 1 { return true }
    func endsWithOperator(_ i: Int) -> Bool {
        guard i >= 0 else { return false }
        if chars[i] == "|" { return true }   // `|`、`||`
        return chars[i] == "&" && i > 0 && (chars[i - 1] == "&" || chars[i - 1] == "|")   // `&&`、`|&`
    }
    if endsWithOperator(end - 1) { return true }
    var lastNonSpace = -1
    for k in 0..<end {
        let c = chars[k]
        if c == "#", k == 0 || chars[k - 1] == " " || chars[k - 1] == "\t", endsWithOperator(lastNonSpace) { return true }
        if c != " " && c != "\t" { lastNonSpace = k }
    }
    return false
}

/// 下一行以 `|`、`&&`、`||` 開頭——shell 不收，但讀的人會把它當成上一行的接續，照接。
func selfProofIsContinuation(_ s: String) -> Bool {
    let t = s.drop { $0 == " " || $0 == "\t" }
    return t.hasPrefix("|") || t.hasPrefix("&&")
}

/// 空白行或只有 `#` 註解的行：管線還沒接完時跳過它們（R4 verify 第 0 列：shell 允許 `|` 之後空幾行再接下一個命令）。
private func selfProofIsBlankOrComment(_ s: String) -> Bool {
    let t = s.trimmingCharacters(in: .whitespaces)
    return t.isEmpty || t.hasPrefix("#")
}

/// 去掉接續用的行尾反斜線（只有奇數個時才是接續）。
private func selfProofDropContinuationBackslash(_ s: String) -> String {
    let r = s.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression)
    guard r.reversed().prefix(while: { $0 == "\\" }).count % 2 == 1 else { return s }
    return String(r.dropLast())
}

/// 把實體行接成邏輯行：(起始行號, 接起來的文字, 跨了幾個實體行)。**認不出邊界時偏向合併**（R4）：一行以接續運算子結尾、或下一個
/// 有內容的行以 `|`／`&&` 開頭時，中間的空白行與純註解行跳過、接上那一行（R3 遇到空白行就停：`akashic validate |`、空白行、`grep -c x`
/// 被切成兩個單位，兩個都不成量測——R4 verify 第 0 列）。跳過的行算進實體行數，所以那個單位一定是「跨行」。
func selfProofLogicalLines(_ lines: [(line: Int, text: String)]) -> [(line: Int, text: String, physical: Int)] {
    var out: [(line: Int, text: String, physical: Int)] = []
    var i = 0
    while i < lines.count {
        var joined = [i]
        var j = i
        while true {
            var m = j + 1
            while m < lines.count, selfProofIsBlankOrComment(lines[m].text) { m += 1 }
            guard m < lines.count, selfProofContinues(lines[j].text) || selfProofIsContinuation(lines[m].text) else { break }
            joined.append(m)
            j = m
        }
        let text = joined.map { k in k < j ? selfProofDropContinuationBackslash(lines[k].text) : lines[k].text }
            .joined(separator: " ")
        out.append((lines[i].line, text, j - i + 1))
        i = j + 1
    }
    return out
}

/// CommonMark 的 inline code 配對（R3 verify 第 2、5、19 列：R2 用 `` `([^`\n]+)` `` 逐行配對，同一行較前面一個孤立的反引號或一段雙反引號
/// span 會讓後面的配對整個錯位，跨行的 span 兩半都不成單位）。一串 n 個反引號開頭，到下一串**恰好** n 個反引號收尾；找不到收尾的那一串是
/// 字面上的反引號，從它後面繼續找。前面是反斜線的反引號是字面（只吃一個字元）。內容的換行換成空白；兩端各有一個空白、而且不全是空白時
/// 各去掉一個。回 (開頭位置, 收尾之後的位置, 內容, 是否跨行)，位置是 `chars` 的索引。
/// **線性**（#711 R4，b33 X6 第 16 列的同一類）：收尾的那一串只會是一串**完整的**反引號（前後都不是反引號），先把它們依長度建索引，
/// 每個長度一個只往前走的指標——逐串往後找的寫法對長短不一、找不到收尾的反引號串是 O(n^1.5)。
func selfProofInlineSpans(_ chars: [Character]) -> [(start: Int, end: Int, content: String, multiline: Bool)] {
    var out: [(start: Int, end: Int, content: String, multiline: Bool)] = []
    let n = chars.count
    var runsByLength: [Int: [Int]] = [:]   // 長度 → 每一串完整反引號的開頭（遞增）
    var r = 0
    while r < n {
        guard chars[r] == "`" else { r += 1; continue }
        var e = r
        while e < n, chars[e] == "`" { e += 1 }
        runsByLength[e - r, default: []].append(r)
        r = e
    }
    var cursor: [Int: Int] = [:]           // 長度 → runsByLength 裡下一個還沒越過的位置
    var i = 0
    while i < n {
        if chars[i] == "\\", i + 1 < n, chars[i + 1] == "`" { i += 2; continue }
        guard chars[i] == "`" else { i += 1; continue }
        var j = i
        while j < n, chars[j] == "`" { j += 1 }
        let run = j - i
        // 開頭這一串之後的第一串同長的完整反引號（開頭這一串已延伸到底，所以 j 之後的每一串都是完整的）
        var close: (Int, Int)? = nil
        if let starts = runsByLength[run] {
            var c = cursor[run] ?? 0
            while c < starts.count, starts[c] < j { c += 1 }
            cursor[run] = c
            if c < starts.count { close = (starts[c], starts[c] + run) }
        }
        guard let c = close else { i = j; continue }
        let (cs, ce) = c
        let raw = chars[j..<cs]
        var content = String(raw).replacingOccurrences(of: "\n", with: " ")
        if content.count >= 2, content.first == " ", content.last == " ", content.contains(where: { $0 != " " }) {
            content = String(content.dropFirst().dropLast())
        }
        out.append((i, ce, content, raw.contains("\n")))
        i = ce
    }
    return out
}

/// fence 與 inline code 以外的文字：去掉 HTML 標記（`<pre>`、`<code>` 等）、解碼常見的實體。標記只認 `<` 後面接英文字母或 `/`，
/// 所以 `2>&1`、`<BIN>` 以外的散文不受影響；`<BIN>` 這種佔位符被當成標記去掉，那不改變任何判定（它不是 binary 也不是計數）。
/// 標記的內文不跨過下一個 `<`：`[^>\n]*` 讓每個 `<a` 各往行尾掃一次，一行三萬個 `<a` 要十秒（#711 R4，b33 X6 第 16 列的同一類）。
private func selfProofProseText(_ s: String) -> String {
    var t = s.replacingOccurrences(of: #"</?[A-Za-z][^<>\n]*>"#, with: " ", options: .regularExpression)
    for (e, v) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#124;", "|"), ("&amp;", "&")] {
        t = t.replacingOccurrences(of: e, with: v)
    }
    return t
}

/// GFM 表格的分隔列（`|---|:--:|`）：只有 `|`、`-`、`:`、空白，至少一個 `|` 與一個 `-`。
private func selfProofIsTableDelimiter(_ t: String) -> Bool {
    t.contains("|") && t.contains("-") && t.allSatisfy { "|-: \t".contains($0) }
}

/// 量測住在哪裡——合不合法不只看文字，也看位置。
private enum SelfProofPlace {
    case fence              // fence 裡（含引用區塊裡的 fence）
    case textFence(Int)     // `text` fence（值＝開頭的行號）
    case inline             // fence 外的一段 inline code
    case prose              // fence 與 inline code 以外：縮排區塊、`<pre>`、散文
}

/// 一條合模板的量測的閘：片段、binary 名、所在的檔與行號（#711：量測住在兩份檔，訊息要說是哪一份）。
typealias SelfProofGate = (needle: String, binary: String, line: Int, file: String)

/// 自證閘的掃描結果。`gates`：合模板的量測各一個閘。
struct SelfProofScan {
    var issues: [String] = []
    var checked = 0
    var gates: [SelfProofGate] = []
}

/// 回 (問題, 掃到幾條數 binary 輸出的指令, 掃到的閘)。
///
/// **辨識寬、判定窄**：一個單位裡**提到** binary 又**有計數**（`selfProofIsMeasurement`），就是一條量測；量測只有一種合法形——fence 裡的
/// 一行、或不跨行的一段 inline code，逐字是 `selfProofTemplate`——其餘一律是錯誤、具名那一行。
///
/// **總原則（R4）——認不出來時偏向「是量測」、偏向「同一個單位」**。R1–R3 每一輪都列舉幾種寫法、下一輪 verify 在列舉之外找到新的
/// （R4 verify 第 0、2、4、7、12、20 列：跨空白行的管線、`|` 開頭而不是表格列的續行、`${X-akashic}`、`zgrep`／`ggrep`／`pcregrep`、
/// `rg --count-matches`、`awk`／`nl | tail` 的計數）。所以判讀不再列舉「什麼算」，而是反過來：
/// · **計數**：binary 的輸出經管線送進任何命令都算計數，除了一張封閉的「已知不計數」清單（`selfProofDisplayFilters` 與不帶計數選項的
///   grep 家族）；另外不經管線的計數選項、`wc`、`jq … length` 照舊算（`<( … )`、here-string）。
/// · **binary**：不分大小寫；參數展開的運算子是字邊界。
/// · **單位**：接續運算子之後的空白行與純註解行跳過、照接；`|` 開頭的行只有在 GFM 表格裡（前一行是表格列、或下一行是分隔列）才是
///   表格列，否則是段落的續行；兩段 inline code 之間只隔空白與一個接續運算子（`|`、`||`、`&&`、`|&`）時接成一個；段落最後一段 inline code
///   以接續運算子結尾、下一個段落以 inline code 開頭（中間只有空白行）時接成一個；散文（縮排區塊、`<pre>`）同一把——上一個段落最後一個
///   邏輯行與下一個段落第一個邏輯行以接續運算子相連時接成一個；引用層數變淺不切段（CommonMark 的 lazy continuation），加深才切。
/// 每一種都是誤認的方向：多判一個單位、紅、具名那一行，作者改成模板或改寫；漏認的方向是放行。
///
/// **單位**（R3 起）：
/// · 每一行先剝掉引用區塊的 `>` 前綴（`selfProofStripBlockquote`），之後才判 fence。
/// · fence 裡：實體行先接成邏輯行（`selfProofLogicalLines`）。跨行的量測一律紅，即使接起來逐字是模板——「一行」是模板的一部分。
/// · fence 外：以段落為單位（空行、標題、表格列、清單項目開頭、HTML 註解行、引用層數加深都是邊界——變淺是 lazy continuation、不是；表格一列一段），段落裡用 CommonMark 的
///   配對找 inline code（`selfProofInlineSpans`）。
/// · fence 與 inline code 以外的文字（縮排區塊、`<pre>`、散文——`selfProofProseText` 去掉 HTML 標記與實體之後）照樣接成邏輯行判讀；
///   那裡的量測一律紅：要寫在 fence 或 inline code 裡。表格列的散文不看管線（`|` 是欄的分隔）。
/// · **不切註解**（R3 verify 第 15 列）：辨識看含註解的原文（註解裡提到 binary 與計數也算一條量測——誤報的方向），模板自己收行尾註解。
///
/// **fence**：```` ``` ```` 與 `~~~` 都認；收尾是同一個字元、長度不短於開頭、沒有 info 的一行。fence 裡出現一行長得像**新** fence 開頭的
/// （同字元、夠長、帶 info，例如 ```` ```bash ````），那是前一個 fence 沒有收尾——報錯並指名開頭那一行；檔尾還在 fence 裡也報錯。
///
/// **`text` fence 照掃**，裡面的量測一律是錯誤（紀錄改寫成不提 binary 的形式，還在用的改成 `bash` fence）。**R4 拿掉了退場標記**：R2 起
/// 前一行是退場標記的 `text` fence 不掃（第 71 列的紀錄），R3 釘住它的**個數**——它仍是一個全域的「不掃」開關，區塊裡加一行、或把一行換成
/// 沒有閘的量測，守衛照樣綠（R4 verify 第 6、11、13、21 列）。那個區塊在 R4 的辨識下沒有任何一行是量測，開關不再需要。
///
/// **管線裡的 `${V:?…}`**（R4 verify 第 1、3、5 列）：fence 與 inline code 的每一個單位都查（不只量測）——`selfProofRequiredExpansionInPipeline`。
///
/// **正對照不讓別行繼承**（#711 R2 verify 第 14 列）——每一條量測各自符合模板。
///
/// **誠實邊界（認不出來、所以不紅的寫法——開放的，不是封閉列舉；條數的地板兜底，見 `selfProofRatchetIssues`）**：
/// · **binary 的輸出先存進變數或檔案、在另一個單位計數**（`out=$(akashic …)` 一行、`printf '%s' "$out" | grep -c` 另一行；`… > f` 一行、
///   `grep -c x f` 另一行）：binary 名與計數不在同一個單位。同一個單位裡兩者都有就算，而那樣寫不會是模板，所以是錯誤。
/// · **以別名、複本或變數執行 binary**（`ak validate`、`/tmp/x validate`、變數名不含 akashic 的 `"$B" validate`）：名字認不出來。
/// · **散文裡 binary 名與計數不在同一個邏輯行**：辨識以邏輯行（與 inline code 段）為單位，不以整個 fence 或段落為單位——後者會把
///   「一行跑 binary、下一行數別的檔」（第 51 列）這種合法的寫法也判成量測。
/// · **兩段 inline code 之間隔著文字**（不只空白與一個接續運算子）：不接。
func selfProofIssues(in rule: String, file: String) -> SelfProofScan {
    var scan = SelfProofScan()

    func judge(_ raw: String, line: Int, physical: Int, place: SelfProofPlace, pipes: Bool = true) {
        let code = raw.trimmingCharacters(in: .whitespaces)
        let head = String(code.prefix(200))
        switch place {
        case .fence, .textFence, .inline:
            if let e = selfProofRequiredExpansionInPipeline(code) {
                if selfProofIsMeasurement(code, pipes: pipes) { scan.checked += 1 }
                scan.issues.append("第 \(line) 行的 `\(e)…}` 寫在管線裡：`\(head)`——沒設時只結束那一段的子 shell，錯誤訊息走 stderr、"
                                   + "管線的其餘照跑，計數印 `0`，與「檢查過且乾淨」分不開。移到整條指令最前面：`: \"\(e)…}\" && …`，"
                                   + "其餘地方寫 `\"$V\"`")
                return
            }
        case .prose:
            break
        }
        guard selfProofIsMeasurement(code, pipes: pipes) else { return }
        scan.checked += 1
        switch place {
        case .textFence(let open):
            scan.issues.append("第 \(line) 行在第 \(open) 行開的 `text` fence 裡對 binary 的輸出計數：`\(head)`——`text` fence 照掃；"
                               + "紀錄改寫成不提 binary 的形式，還在用的量測改成 `bash` fence、寫成 `\(selfProofTemplate)`")
            return
        case .prose:
            scan.issues.append("第 \(line) 行在 fence 與 inline code 以外（縮排區塊、`<pre>`、散文）對 binary 的輸出計數：`\(head)`"
                               + "——量測只收 fence 裡的一行或一段 inline code，逐字是 `\(selfProofTemplate)`")
            return
        case .fence, .inline:
            break
        }
        if physical > 1 {
            scan.issues.append("第 \(line) 行起跨 \(physical) 行的單位對 binary 的輸出計數（以 `\\`、行尾 `|`／`&&`、下一行開頭的 `|` 接續——"
                               + "中間可以隔著空白行或註解行——或 inline code 跨行、跨段落、兩段之間只隔一個接續運算子）——跨行不是唯一合法的寫法 `\(selfProofTemplate)`，"
                               + "接起來逐字是它也一樣：`\(head)`。寫成一行；binary 與計數拆在兩行時，舊 binary 印 `0` 而守衛先前一行都看不到")
            return
        }
        let ns = code as NSString
        if let m = selfProofFirstMatch(selfProofTemplateRe, code),
           ns.substring(with: m.range(withName: "args")).filter({ $0 == "\"" }).count % 2 == 0 {
            if let why = selfProofPreconditionIssue(m, in: ns) {
                scan.issues.append("第 \(line) 行的量測\(why)：`\(head)`")
                return
            }
            scan.gates.append((ns.substring(with: m.range(withName: "needle")),
                               selfProofBinaryName(ns.substring(with: m.range(withName: "bin"))), line, file))
            return
        }
        var hint = ""
        if let m = selfProofFirstMatch(selfProofLooseTemplateRe, code) {
            let gate = ns.substring(with: m.range(withName: "gate")), measured = ns.substring(with: m.range(withName: "measured"))
            hint = gate == measured ? "——<參數> 裡的雙引號要成對"
                : "——閘查的是 `\(gate)`，被量的是 `\(measured)`：兩處要逐字相同（只比檔名時，閘證明的可能是另一個檔）"
        }
        scan.issues.append("第 \(line) 行對 binary 的輸出計數，卻不是唯一合法的寫法 `\(selfProofTemplate)`：`\(head)`\(hint)。"
                           + "<BIN> 兩處逐字相同、是路徑或 `\"$(command -v …)\"`；<參數> 不含 `#`、單引號；整個單位只有這一條指令——"
                           + "前後不接 `;`／`||`／`|`、不包在 `if`／`$( … )`／`{ }` 裡、寫在一行——行尾至多一段 `#` 註解。不合模板的寫法在"
                           + "沒有那條檢查的舊 binary 上照樣印 `0`，與「檢查過且乾淨」分不開")
    }

    // ── fence 外的段落：inline code 與其餘文字 ──
    let raws = rule.components(separatedBy: "\n")
    let stripped = raws.map { selfProofStripBlockquote($0) }
    var block: [(line: Int, text: String)] = []
    /// 上一個段落最後一段 inline code（後面只剩空白）——下一個段落以 inline code 開頭、中間只有空白行、兩者以接續運算子相連時接成一個
    /// （R4：偏向合併）。沒接上就在下一個段落處理時判讀。
    var pending: (line: Int, content: String, lastLine: Int)? = nil
    func judgePending() {
        if let p = pending { judge(p.content, line: p.line, physical: 1, place: .inline) }
        pending = nil
    }
    /// 散文（含縮排區塊、`<pre>`）的同一件事：上一個段落最後一個邏輯行，與下一個段落的第一個邏輯行之間只有空白行、兩者以接續運算子相連時
    /// 接成一個（縮排區塊裡 `akashic validate |`、空白行、`grep -c x`——shell 照接，fence 裡的同一種寫法 R4 起接上了）。
    var pendingProse: (line: Int, text: String, lastLine: Int)? = nil
    func judgePendingProse() {
        if let p = pendingProse { judge(p.text, line: p.line, physical: 1, place: .prose) }
        pendingProse = nil
    }
    /// `from` 之後到 `to` 之前（行號，1 起算）都是空白行（引用區塊的 `>` 已剝掉）。
    func onlyBlankBetween(_ from: Int, _ to: Int) -> Bool {
        to > from && (from + 1..<to).allSatisfy { stripped[$0 - 1].content.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    func flushBlock(table: Bool = false) {
        defer { block = [] }
        guard !block.isEmpty else { return }   // 連續的空白行：上一個段落留下的那一段繼續等
        let chars = Array(block.map(\.text).joined(separator: "\n"))
        var lineAt: [Int] = []          // chars 的每個索引在第幾行
        lineAt.reserveCapacity(chars.count)
        var k = 0
        for c in chars { lineAt.append(block[k].line); if c == "\n" { k += 1 } }
        let spans = selfProofInlineSpans(chars)
        var merged: [(line: Int, start: Int, end: Int, content: String, physical: Int)] = []
        for s in spans {
            if let last = merged.last {
                let between = String(chars[last.end..<s.start]).trimmingCharacters(in: .whitespacesAndNewlines)
                let operatorBetween = !table && ["|", "||", "&&", "|&"].contains(between)
                if (between.isEmpty && (selfProofContinues(last.content) || selfProofIsContinuation(s.content))) || operatorBetween {
                    let glue = operatorBetween ? " " + between + " " : " "
                    merged[merged.count - 1] = (last.line, last.start, s.end, last.content + glue + s.content, 2)
                    continue
                }
            }
            merged.append((lineAt[s.start], s.start, s.end, s.content, s.multiline ? 2 : 1))
        }
        // 上一個段落留下的那一段接到這個段落的第一段
        if let p = pending {
            if !table, onlyBlankBetween(p.lastLine, block[0].line), let first = merged.first, chars[0..<first.start].allSatisfy(\.isWhitespace),
               selfProofContinues(p.content) || selfProofIsContinuation(first.content) {
                merged[0] = (p.line, first.start, first.end, p.content + " " + first.content, 2)
                pending = nil
            } else {
                judgePending()
            }
        }
        for (i, s) in merged.enumerated() {
            if i == merged.count - 1, !table, s.physical == 1, chars[s.end...].allSatisfy(\.isWhitespace) {
                pending = (s.line, s.content, block[block.count - 1].line)
                continue
            }
            judge(s.content, line: s.line, physical: s.physical, place: .inline)
        }
        var prose = chars
        for s in spans { for q in s.start..<s.end where prose[q] != "\n" { prose[q] = " " } }
        let proseLines = String(prose).components(separatedBy: "\n").enumerated()
            .map { (line: block[$0.offset].line, text: selfProofProseText($0.element)) }
        var logical = selfProofLogicalLines(proseLines)
        if let p = pendingProse {
            if !table, onlyBlankBetween(p.lastLine, block[0].line), let first = logical.first,
               selfProofContinues(p.text) || selfProofIsContinuation(first.text) {
                logical[0] = (p.line, p.text + " " + first.text, 2)
                pendingProse = nil
            } else {
                judgePendingProse()
            }
        }
        for (i, l) in logical.enumerated() {
            if i == logical.count - 1, !table {
                pendingProse = (l.line, l.text, block[block.count - 1].line)
                continue
            }
            judge(l.text, line: l.line, physical: l.physical, place: .prose, pipes: !table)
        }
    }

    var fence: (char: Character, count: Int, info: String, line: Int)? = nil
    var fenceLines: [(line: Int, text: String)] = []
    func flushFence(_ f: (char: Character, count: Int, info: String, line: Int)) {
        defer { fenceLines = [] }
        let place: SelfProofPlace = f.info.split(separator: " ").first == "text" ? .textFence(f.line) : .fence
        for l in selfProofLogicalLines(fenceLines) { judge(l.text, line: l.line, physical: l.physical, place: place) }
    }
    var previousDepth = 0
    var inTable = false
    let listItem = try! NSRegularExpression(pattern: #"^\s*(?:[-*+]|\d+[.)])\s+"#)
    let heading = try! NSRegularExpression(pattern: #"^#{1,6}(?:\s|$)"#)
    for (i, (l, depth)) in stripped.enumerated() {
        let line = i + 1
        let trimmed = l.trimmingCharacters(in: .whitespaces)
        defer { previousDepth = depth }
        if let f = fence {
            if let d = selfProofFenceDelimiter(trimmed), d.char == f.char, d.count >= f.count {
                if d.info.isEmpty { flushFence(f); fence = nil; continue }
                scan.issues.append("第 \(line) 行「\(String(trimmed.prefix(20)))」是新 fence 的開頭，卻落在第 \(f.line) 行開的 fence 裡"
                                   + "——第 \(f.line) 行的 fence 沒有收尾，之後整份檔的 fence 內外會顛倒、量測區塊不被掃。在它前面補上收尾的一行")
                flushFence(f)
                fence = (d.char, d.count, d.info, line)   // 依作者的意圖從這一行重新開始，後面的錯誤才指得準
                continue
            }
            fenceLines.append((line, l))
            continue
        }
        if let d = selfProofFenceDelimiter(trimmed) {
            flushBlock()
            judgePending()
            judgePendingProse()
            inTable = false
            fence = (d.char, d.count, d.info, line)
            continue
        }
        // GFM 表格列（R4 verify 第 2 列：R3 把每一個以 `|` 開頭的行都當成表格列、切段，多行 inline code 裡以 `|` 開頭的續行把 span 切成兩半）：
        // 含 `|` 而且前一行是同一層的表格列，或下一行是分隔列（表頭）。其餘以 `|` 開頭的行是段落的續行。
        let nextIsDelimiter = i + 1 < stripped.count && stripped[i + 1].depth == depth
            && selfProofIsTableDelimiter(stripped[i + 1].content.trimmingCharacters(in: .whitespaces))
        let tableRow = trimmed.contains("|") && ((inTable && depth == previousDepth) || nextIsDelimiter)
        inTable = tableRow
        let ns = l as NSString
        let whole = NSRange(location: 0, length: ns.length)
        let standalone = tableRow || trimmed.hasPrefix("<!--")
            || heading.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) != nil
        // 引用層數**加深**是邊界（引用區塊可以打斷段落）；**變淺**不是——CommonMark 的 lazy continuation：引用區塊裡一段沒收尾的
        // inline code，下一行沒有 `>` 時仍是同一個段落、同一段 inline code（R4 的偏向合併；R3 兩個方向都切）
        if trimmed.isEmpty || standalone || depth > previousDepth || listItem.firstMatch(in: l, range: whole) != nil {
            flushBlock()
        }
        guard !trimmed.isEmpty else { continue }
        block.append((line, l))
        if standalone { flushBlock(table: tableRow) }
    }
    flushBlock()
    judgePending()
    judgePendingProse()
    if let f = fence {
        flushFence(f)
        scan.issues.append("第 \(f.line) 行開的 fence 到檔尾都沒有收尾——之後整份檔被當成 fence 內，量測的判讀會錯。補上收尾的一行")
    }
    // 兩份檔各掃一次（#711：量測搬到量測文件，表格裡仍可能有）——每則訊息以檔名開頭，行號是那份檔的行號
    scan.issues = scan.issues.map { "\(file) " + $0 }
    return scan
}

/// 合模板的量測，前置條件夠不夠（R4）：`<參數>` 與 `test -f` 用到的變數都在 `: "${V:?…}"` 裡；`--library "$V"` 有 `test -f "$V/store.yaml"`。
/// 回一句說明哪裡不夠的話，夠就回 nil。
private func selfProofPreconditionIssue(_ m: NSTextCheckingResult, in ns: NSString) -> String? {
    func group(_ name: String) -> String? {
        let r = m.range(withName: name)
        return r.location == NSNotFound ? nil : ns.substring(with: r)
    }
    let args = group("args") ?? ""
    let test = group("test")
    let guarded = Set(captures(group("guards") ?? "", #"\$\{([A-Za-z_][A-Za-z0-9_]*):\?"#))
    let used = Set(captures(args + " " + (test ?? ""), #"\$\{?([A-Za-z_][A-Za-z0-9_]*)"#))
    let unguarded = used.subtracting(guarded).sorted()
    if !unguarded.isEmpty {
        let list = unguarded.map { "`$\($0)`" }.joined(separator: "、")
        return "用到 \(list)，前面卻沒有 `: \"${\(unguarded[0]):?…}\" && `——沒設時 `--library \"\"` 等同沒傳、落到預設解析到的 store"
            + "（在這台機器上那是活的一份），`--from \"\"` 之類讀不到東西、計數印 `0`"
    }
    for v in captures(args, #"--library[ =]"?\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?"?"#) {
        guard test != "$\(v)/store.yaml", test != "${\(v)}/store.yaml" else { continue }
        return "以 `--library \"$\(v)\"` 指名 store，前面卻沒有 `test -f \"$\(v)/store.yaml\" && `——\(v) 打錯成一個不是 store 的目錄時，"
            + "`validate` 報錯而 `grep -c` 照印 `0`，`doctor` 還會在那裡建出一個 store"
    }
    return nil
}

/// `<BIN>` 的 binary 名：`"$(command -v X)"` 取 X，路徑取最後一段。只用來決定片段該在哪支 binary 的原始碼裡找——判準是兩處逐字相同。
private func selfProofBinaryName(_ bin: String) -> String {
    let prefix = "\"$(command -v "
    if bin.hasPrefix(prefix), bin.hasSuffix(")\"") { return String(bin.dropFirst(prefix.count).dropLast(2)) }
    return (bin as NSString).lastPathComponent
}

// MARK: - 棘輪：合模板的量測條數（#711 R3；R4 依閘去重、拿掉退場區塊）

/// **棘輪標記**：規則檔裡恰好一行，記合模板的量測**依 (binary, 閘的片段) 去重後**至少幾條。
///
/// R3 verify 第 7 列：把量測改寫成守衛認不出的寫法，閘全部消失而守衛 rc=0——唯一的地板是「一條都沒掃到」。辨識在 R4 改成偏向「是量測」，
/// 但認不出來的寫法仍有（`selfProofIssues` 的誠實邊界），所以條數要有一個不靠辨識的地板：少於下限即紅。新增量測之後把下限調高是人的事；
/// 下限過期只會讓它擋不住**少量**的流失，擋得住整批。**它不是新增量測的守衛**：新增一條沒有閘的量測不改變合模板的條數，抓到它的只能是辨識。
/// **去重**（R4 verify 第 21 列）：逐字相同的量測貼兩次、或同一道閘配不同的樣式，各算一條的話，拿掉三道閘再貼三份複本，地板照樣滿足。
/// 地板數的是**閘**——同一道閘（同一支 binary、同一個片段）只算一次。
/// **住在被稽核的同一個檔裡**（R4 verify 第 13 列）：一次編輯可以同時改下限與內容——這類檔內棘輪的固有限制（`protected-ratchet.txt`
/// 把清單放在另一個檔）；它防的是安靜的流失，不是有意的改寫，改下限的那一行在 diff 裡看得到。
let selfProofRatchetPattern = #"<!-- zero-instance-rows-audit 棘輪：合模板的量測（依 binary 與閘的片段去重）至少 (\d+) 條 -->"#

/// 去重後的閘數。
func selfProofDistinctGates(_ gates: [SelfProofGate]) -> Int {
    Set(gates.map { $0.binary + "\u{0}" + $0.needle }).count
}

func selfProofRatchetIssues(rule: String, measurements: String, gates: [SelfProofGate]) -> (issues: [String], floor: Int?) {
    // 標記住在量測文件（#711）：規則檔裡出現一個是搬錯了地方——兩份各一個時地板有兩個數，哪個算數沒有答案
    let inRule = matches(rule, selfProofRatchetPattern).count
    guard inRule == 0 else {
        return (["棘輪標記住在 \(zeroInstanceMeasurementsPath)，\(zeroInstanceRulePath) 裡不得有（找到 \(inRule) 個）"
                 + "——量測搬到量測文件之後，地板跟著量測住"], nil)
    }
    let found = captures(measurements, selfProofRatchetPattern, multiline: true)
    let marks = matches(measurements, selfProofRatchetPattern)
    guard marks.count == 1, let floorText = found.first, let floor = Int(floorText) else {
        return (["棘輪標記要恰好一個（找到 \(marks.count) 個）：`<!-- zero-instance-rows-audit 棘輪：合模板的量測（依 binary 與閘的片段去重）至少 N 條 -->`"
                 + "，住在 \(zeroInstanceMeasurementsPath)——它是量測條數不靠辨識的地板"], nil)
    }
    let distinct = selfProofDistinctGates(gates)
    guard distinct < floor else { return ([], floor) }
    return (["合模板的量測依閘去重後只有 \(distinct) 條，棘輪標記的下限是 \(floor) 條——量測被拿掉、改成守衛不判讀的寫法（以變數或檔案當來源、"
             + "別名執行），或只是同一道閘的複本。真的是有意的，把棘輪標記的下限改成 \(distinct)"], floor)
}

/// 規則 `measurement-commands-self-prove` 引用的模板與 `selfProofTemplate` 逐字相同（#711：通則抽成獨立規則之後，那份規則裡的模板是
/// 第二份描述——它與守衛分岔時，照規則寫的人寫出的量測會被守衛判紅，或規則放行的寫法守衛不收）。檔不在也紅：規則被刪或搬走時，
/// 「沒有東西可比」不得冒充「一致」。
func selfProofTemplateCopyIssues(_ text: String?) -> [String] {
    guard let text else {
        return ["找不到 \(selfProofTemplateRulePath)——量測寫法的規則住在那裡，守衛要拿它的模板與 `selfProofTemplate` 對照"]
    }
    guard text.contains("`" + selfProofTemplate + "`") else {
        return ["\(selfProofTemplateRulePath) 裡找不到與守衛逐字相同的模板 `\(selfProofTemplate)`——規則與守衛分岔了："
                + "改了守衛就同批改規則那一行，反之亦然"]
    }
    return []
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

/// 閘的片段的條件（#711 R1、R2、R3；條數不寫——寫死的計數與清單分岔過，R4 verify 第 18、34 列）：
/// 1. **不含基本正規式的特殊字元**（`selfProofNeedleMetacharacters`）、**不以 `-` 開頭**（R3：`grep` 會把它當選項）、
///    **不短於 `selfProofMinNeedleBytes`**（R2）。
/// 2. **在那支 binary 的原始碼裡**——任何字串字面段都沒有的片段，是訊息改了字、或那條檢查已移除（R2 verify 第 21 列：R1 對這種情形
///    與下一條印同一句話，把維護者導向字面段長度）。
/// 3. **在一個 ≥ `selfProofMinLiteralSegmentBytes` 位元組的字面段裡**——否則 release 版找不到它，閘把有這條檢查的 binary 讀成舊的
///    （自證的反向誤判）。`akashic` 的原始碼＝`Sources/` 除了 `akashic-guards` 與 `akashic-mcp`（沒有逐 target 解析依賴：一個只在 App
///    模組裡的字面段會讓這條誤過，release 版的實際 grep 才是終判）；`akashic-guards` 的原始碼＝它自己的目錄、不含 harness 檔。
/// 4. 對 `akashic-guards` 的閘：**片段不得出現在 harness 檔的任何字面段裡**（見 `selfProofIsHarness`）。harness 要比對那段訊息時，
///    改用同一則訊息裡的另一段文字。
/// 只查 binary 是 `akashic`／`akashic-guards` 的閘（模板只收這兩支）。
func selfProofNeedleIssues(gates: [SelfProofGate]) -> [String] {
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
            out.append("\(g.file) 第 \(g.line) 行的自證閘片段「\(g.needle)」含基本正規式的特殊字元（\(meta.sorted().map { "`\($0)`" }.joined(separator: "、"))）"   // display-safe-exempt: g.file 是 rulePath 或 zeroInstanceMeasurementsPath 兩個程式常量（repo 內的檔案路徑，不是 store 內容）；g 的其餘欄位取自同一份 repo 文件
                       + "——`grep -a -q` 把片段當正規式：`.`、`*` 讓閘對任何非空檔成立，`[` 讓 grep 出錯、閘恆失敗。"
                       + "改用同一則訊息裡不含 `.[]*^$\\` 的一段")
        }
        // R3 verify 第 12 列：`grep -a -q '--include-absent-authors' f` 把片段當選項、結束碼 2，閘恆失敗——新 binary 被讀成舊的
        if g.needle.hasPrefix("-") {
            out.append("\(g.file) 第 \(g.line) 行的自證閘片段「\(g.needle)」以 `-` 開頭——`grep -a -q` 把它當成選項（認不得時結束碼 2），"
                       + "閘恆失敗、把有這條檢查的 binary 讀成舊的。改用同一則訊息裡不以 `-` 開頭的一段")
        }
        if g.needle.utf8.count < selfProofMinNeedleBytes {
            out.append("\(g.file) 第 \(g.line) 行的自證閘片段「\(g.needle)」只有 \(g.needle.utf8.count) 位元組（下限 \(selfProofMinNeedleBytes)）"
                       + "——太短的片段在任何版本的 binary 裡都找得到，閘恆真。改用同一則訊息裡較長的一段")
        }
        if anyLength[g.binary]?.range(of: g.needle, options: .literal) == nil {
            out.append("\(g.file) 第 \(g.line) 行的自證閘片段「\(g.needle)」在 `\(g.binary)` 的原始碼裡找不到（任何字串字面段都沒有）"
                       + "——訊息改了字、或那條檢查已移除。更新這一列的閘與量測，讓它們對著現在的訊息")
        } else if long[g.binary]?.range(of: g.needle, options: .literal) == nil {
            out.append("\(g.file) 第 \(g.line) 行的自證閘片段「\(g.needle)」只在 `\(g.binary)` 原始碼裡短於 \(selfProofMinLiteralSegmentBytes) 位元組的字串字面段裡"
                       + "——最佳化建置會把 15 位元組以內的字面段當 immediate 嵌進指令，release 版的 binary 裡找不到它，"
                       + "閘會把有這條檢查的 binary 讀成舊的。改用同一則訊息裡較長字面段的一段")
        }
        if g.binary == "akashic-guards", harness.range(of: g.needle, options: .literal) != nil {
            out.append("\(g.file) 第 \(g.line) 行的自證閘片段「\(g.needle)」出現在負控 harness（`*Mutations.swift`／`*MutationsData.swift`）的字串裡"
                       + "——它們編進同一支 `akashic-guards`，真的檢查不在時閘照樣成立。harness 改用那則訊息的另一段文字")
        }
    }
    return out
}
