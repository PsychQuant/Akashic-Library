// `zero-instance-guards.md` 的裁決表：每一列裁決「寫」的守衛，程式裡真的有嗎？
//
// **契約（逐字取自 Python 版的 docstring，#433 第 3b 步）**：
//
//   表裡每一列都引一個 issue 編號。裁決是 ✅「寫」的列，那個編號必須出現在
//   `Sources/` 底下——也就是那個守衛真的被實作了。
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

    var out = "══ zero-instance 裁決表：\(rows.count) 列 ══\n"
    for f in fails { out += "  ✗ \(f)\n" }
    out += "\n══ " + (fails.isEmpty ? "每一列裁決「寫」的都找得到實作"
                                    : "**\(fails.count) 列有問題**") + " ══\n"
    FileHandle.standardOutput.write(Data(out.utf8))
    return fails.isEmpty ? 0 : 1
}
