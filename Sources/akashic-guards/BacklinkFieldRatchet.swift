// `entity-backlink-completeness.md` 的封閉列舉：**新欄位必須先被裁決**。
//
// **為什麼有這支**（#407 R51）：那張表**錯過三次**（宣稱窮盡卻漏三條、補了形狀沒窮舉
// 欄位、新增一條邊卻沒改表）。它因此附了一段可執行的稽核程序，第 ③ 步是「逐欄位問：
// 它會被序列化嗎？它的值指涉另一個實體嗎？」——**那一步是人的判斷**，不能由腳本代做。
//
// 所以本支**不裁決**，只做**棘輪**：把當下六個型別檔的 `public var` ＋ `public let`
// 全部釘住。新出現一個就紅，訊息要求人跑第 ③ 步、再加進清單。
//
// **誠實邊界（五條，逐字取自 Python 版）**：
//
//   · **釘的是全部欄位，不是「看起來像 reference 的」**。上一版用型別排除純量當候選
//     偵測，而 `public var seeAlso: [String]` 這種直接掛頂層的 key 陣列會被判成純量
//     而漏掉。謂詞比它要管的東西窄，所以整個拿掉（#407 R52）。
//   · 宣告**跨行**時逐行 regex 看不到；先摺平空白再抓。
//   · **`public let` 也算**（#407 R53）：第 13 條邊的 `VerdictPairingValue` 的
//     `holderKind`／`holder` 正是 `public let`——一條真的 entity 指標整個在棘輪之外。
//   · **不驗那些列的裁決內容對不對**（那要人判斷），但兩件事有守：**葉欄位必須存在於
//     Swift**（R57）以及**它的宣告型別不得改變**（R59）。
//   · 欄位被**刪掉**也會紅（清單與現況不等），那是刻意的——刪一條邊同樣要改表。
//
// trigger-coverage: reads .claude/rules/entity-backlink-completeness.md

import Foundation

/// 從那張表抽出各條邊的**葉欄位名**。
///
/// **為什麼要讀表**（#407 R57，跨模型審查指名為 HIGH）：上一版只比對自己的清單字面，
/// **完全不打開那份規則**——於是同一個 commit 裡加一個欄位、再把它追加進清單，棘輪就
/// 綠了，而表一列都沒動。**守衛可以被編輯它自己的 fixture 來消音。**
///
/// 現在多一道：表裡每一列的 `Type.field` 路徑，其**葉欄位**必須真的存在於六個型別檔。
///
/// 誠實邊界：只比**葉名**（`Person.profile.affiliations` → `affiliations`），不驗它掛在
/// 哪個型別上——巢狀路徑的中間段不在那六個檔的頂層宣告裡，逐段驗證需要型別解析。
private func tableEdges() -> (rows: [(String, String, String)]?, err: String?) {
    let rulePath = ".claude/rules/entity-backlink-completeness.md"
    guard let rule = readFile(rulePath) else { return (nil, "找不到規則檔") }
    let ns = rule as NSString
    let rows = matches(rule, #"^\| (\d+) \| (.*?) \| (.*?) \|"#, multiline: true)
    guard !rows.isEmpty else { return (nil, "表一列都沒讀到——抽取式與表的寫法脫節了") }
    var out: [(String, String, String)] = []
    for m in rows {
        let num = ns.substring(with: m.range(at: 1))
        let whereCol = ns.substring(with: m.range(at: 2))
        guard let path = firstGroup(whereCol, #"`([A-Z][A-Za-z]*\.[A-Za-z.]+)`"#) else {
            return (nil, "第 \(num) 列抽不到 `Type.field` 路徑")
        }
        out.append((num, path, String(path.split(separator: ".").last!)))
    }
    return (out, nil)
}

func backlinkFieldRatchet() -> Int32 {
    var seen = Set<String>()
    var declared: [String: String] = [:]
    for f in ratchetFiles {
        let p = "Sources/AkashicCore/\(f).swift"
        guard let raw = readFile(p) else {
            print("✗ 找不到 \(p)——規則指定的六個型別檔之一不在了，稽核程序脫節")
            return 1
        }
        // 宣告可能跨行：先摺平空白再抓（誠實邊界第 2 條）。
        let flat = raw.replacingOccurrences(of: #"\s+"#, with: " ",
                                            options: .regularExpression)
        for name in captures(flat, #"public (?:var|let) (\w+)\s*:"#) {
            seen.insert("\(f).\(name)")
        }
        // 型別要逐行抓（摺平後分不出宣告在哪結束）。
        for line in raw.components(separatedBy: "\n") {
            let m = matches(line, #"^\s*public (?:var|let) (\w+)\s*:\s*([^={\n]+)"#)
            guard let first = m.first else { continue }
            let lns = line as NSString
            let key = "\(f).\(lns.substring(with: first.range(at: 1)))"
            if declared[key] == nil {
                declared[key] = lns.substring(with: first.range(at: 2))
                    .trimmingCharacters(in: .whitespaces)
            }
        }
    }

    let typeFails = edgeTypes.sorted { $0.key < $1.key }.compactMap { k, v -> String? in
        declared[k] == v ? nil
            : "邊欄位 `\(k)` 的宣告型別變了：釘住 `\(v)`，現在是 "
              + "`\(declared[k] ?? "（抽不到）")`——名字沒動而語意可能已經不同"
    }

    let (edges, err) = tableEdges()
    var tableFails: [String] = []
    if let err { tableFails.append(err) }
    if let edges {
        let leaves = Set(seen.map { String($0.split(separator: ".").last!) })
        for (num, path, leaf) in edges where !leaves.contains(leaf) {
            tableFails.append("表第 \(num) 列的 `\(path)`——葉欄位 `\(leaf)` "
                              + "**在六個型別檔裡找不到**（列被改名了，還是 Swift 改名了？）")
        }
    }

    let new = seen.subtracting(adjudicated).sorted()
    let gone = adjudicated.subtracting(seen).sorted()
    print("══ 欄位棘輪：現況 \(seen.count)｜已裁決 \(adjudicated.count) ══")
    for n in new {
        print("  ✗ **新欄位未經裁決**：\(n)——請跑 entity-backlink-completeness.md 的"
              + "第 ③ 步（它會被序列化嗎？值指涉另一個實體嗎？），再加進 ADJUDICATED")
    }
    for n in gone { print("  ✗ 欄位消失：\(n)——若它是一條邊，表也要改") }
    for f in typeFails { print("  ✗ \(f)") }
    for f in tableFails { print("  ✗ \(f)") }
    // Python 版是 `print(A if not table_fails else '')` —— 有 table_fails 時**印一個空行**。
    // 逐字複製那個行為:第 3a 步要求輸出逐字相同,而「跳過不印」與「印空行」在 diff 裡不同。
    // （這一格正是逐字比對抓到的——實質判定兩版一致,差的只有這一個空行。）
    if edges != nil {
        print(tableFails.isEmpty ? "  （表 \(edges!.count) 列，葉欄位全部對得上 Swift）" : "")
    }
    let n = new.count + gone.count
    print("\n══ \(n == 0 ? "無未裁決欄位" : "**\(n) 處") ══")
    return (new.isEmpty && gone.isEmpty && tableFails.isEmpty && typeFails.isEmpty) ? 0 : 1
}
