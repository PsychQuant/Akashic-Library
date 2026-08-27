// 每支**實際在跑**的 Swift 守衛，都有 negative control 在驗它嗎？
//
// **為什麼有這支**（#433）：`run-guards.sh` 把一支守衛從 `plugin/tests/X.py` 換成
// `akashic-guards X` 之後，如果它的負控 harness 仍只跑 `.py`，那個負控驗的就是一個
// **不再被執行的實作**——負控全綠、runner 全綠，而實際在跑的那一版會不會紅，**沒有
// 任何東西在保證**。缺口在兩者中間，兩邊都看不到。
//
// **這不是零實例守衛，它有三個實例**：
//   1. `measured-numbers-audit` 等四支（`MIGRATED` 表，修完當次就抓到兩個真的翻譯遺漏）
//   2. `trigger-coverage` 與 `rule-prose-guards`（各自的獨立 harness）
//   3. **`decision-matrix-drift`——修完前兩個之後我仍然漏了它**：它是 A 批第一支遷的
//      （在第 4 步紀律建立之前），負控是獨立 harness 而不在 `MIGRATED` 表裡，於是
//      前兩處修正都沒有涵蓋到它
//
// 第 3 個是這支守衛存在的直接理由：**我修了同一個形狀兩次，然後又漏了第三次**。
// 一條記在散文裡的紀律擋不住這個——它要求人每次遷移都想起來，而我沒有。
//
// **判準**：`run-guards.sh` 裡每個 `akashic-guards <sub>`，必須在某個 negative-control
// harness 裡也出現（直接呼叫 `akashic-guards <sub>`，或列在 `MIGRATED` 表裡）。
//
// **誠實邊界**：它驗的是「有東西提到它」，不是「那個負控真的有效」。一個把 `MIGRATED`
// 表填滿卻不比對的 harness 照樣通過——本守衛擋的是**整個忘記**，不是**做錯**。
// 後者由 harness 自己的 negative control 管（那是它們的職責，不是這支的）。
//
// trigger-coverage: reads plugin/tests/*.py

import Foundation

func migratedGuardControl() -> Int32 {
    let runner = ".githooks/run-guards.sh"
    guard fileExists(runner) else {
        print("✗ 找不到 \(runner)——守衛清單的唯一來源不見了")
        return 1
    }
    // 只認**行首**的實際呼叫，不認註解裡提到的（`codeOnly` 剝掉整行註解，而 run-guards.sh
    // 的註解密度很高——不剝的話一句「`akashic-guards X` 的映射」就會被算成執行了它）。
    let rg = codeOnly(runner)
    let executed = matches(rg, #"(?m)^\.build/debug/akashic-guards ([a-z][a-z0-9-]*)"#).map {
        (rg as NSString).substring(with: $0.range(at: 1))
    }
    guard !executed.isEmpty else {
        print("✗ \(runner) 裡一個 `akashic-guards <子命令>` 都抽不到——抽取式與寫法脫節了")
        return 1
    }

    // negative-control harness：檔名帶 `mutations` 的，加上 `oracle-precondition-control`
    // （它 import 前者的模組、驗 harness 自己的降級機制）。
    var harnesses = globFiles("plugin/tests/*mutations*.py")
        + globFiles("plugin/skills/*/scripts/tests/*mutations*.py")
    if fileExists("plugin/tests/oracle-precondition-control.py") {
        harnesses.append("plugin/tests/oracle-precondition-control.py")
    }
    var covered = Set<String>()
    for h in harnesses {
        let code = codeOnly(h)
        // ① 直接呼叫
        for m in matches(code, #"akashic-guards['"]?\s*,?\s*['"]([a-z][a-z0-9-]*)['"]"#) {
            covered.insert((code as NSString).substring(with: m.range(at: 1)))
        }
        for m in matches(code, #"akashic-guards ([a-z][a-z0-9-]*)"#) {
            covered.insert((code as NSString).substring(with: m.range(at: 1)))
        }
        // ② `MIGRATED` 表的值（遷移期的兩版並驗清單）
        if let mm = matches(code, #"(?s)MIGRATED\s*=\s*\{(.*?)\n\}"#).first {
            let blk = (code as NSString).substring(with: mm.range(at: 1))
            for m in matches(blk, #"'([a-z][a-z0-9-]*)'"#) {
                covered.insert((blk as NSString).substring(with: m.range(at: 1)))
            }
        }
    }

    let missing = executed.filter { !covered.contains($0) }.sorted()
    print("══ 實際在跑的 Swift 守衛：\(executed.count) 支｜negative-control harness：\(harnesses.count) 支 ══")
    for s in missing {
        print("  ✗ `akashic-guards \(s)` 在 run-guards.sh 裡跑，"
            + "但沒有任何 negative-control harness 驗它——")
        print("     那支守衛的負控（若有）驗的是**已經不再執行**的 Python 版。")
        print("     修法：讓它的 harness 兩版都跑並要求輸出逐字相同（見 #433 的第 4 步）。")
    }
    if missing.isEmpty {
        print("  \(executed.count) 支全部都有負控在驗實際執行的那一版")
    }
    print("\n══ \(missing.isEmpty ? "無缺口" : "**\(missing.count) 支缺負控**") ══")
    return missing.isEmpty ? 0 : 1
}
