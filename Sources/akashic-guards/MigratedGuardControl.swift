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
// **刻意不寫 `trigger-coverage: reads` 宣告**（#433 Step 5）：宣告存在的理由是補啟發式
// 的漏（守衛用 glob 組路徑、basename 不逐字出現）。這支讀的是同目錄的 harness source，
// 啟發式看得到——而指向自己所在目錄的宣告會被守衛判成「多半多餘」的警告。

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
    // **harness 清單同時涵蓋兩種語言**（#433 Step 5）：遷移期間 Python 版還在，遷完之後
    // 只剩 Swift。判準對兩者相同——它們都是「執行別的守衛」的東西，而那正是負控的定義。
    var harnesses = globFiles("plugin/tests/*mutations*.py")
        + globFiles("plugin/skills/*/scripts/tests/*mutations*.py")
    if fileExists("plugin/tests/oracle-precondition-control.py") {
        harnesses.append("plugin/tests/oracle-precondition-control.py")
    }
    // **Swift 側掃整個目錄，不只「有 Process() 的」**（#433 Step 5）：harness 的 case 資料
    // 被抽進 `*Data.swift`（沒有 `Process()`，不會被判成 harness），而受測守衛的子命令名
    // 正是寫在那裡。只掃執行面會漏掉它們——實測 5 支守衛因此被誤報「缺負控」。
    //
    // 掃全目錄不會誤判：`main.swift` 的 dispatch 表寫的是 `case "X":` 而非
    // `akashic-guards X`，抓不到；下方的 `isHarness` 仍用執行面判準區分「它自己就是負控」。
    harnesses += globFiles("Sources/akashic-guards/*.swift")
    var covered = Set<String>()
    for h in harnesses {
        let code = codeOnly(h)
        // **生成的資料檔只認 `guardRel:` 欄位**（#433 Step 5）：它同時裝著 case 的**受測
        // 對象**（`guardRel`）與**注入內容**（`new:`），而後者可能含 `akashic-guards <名字>`
        // 的字面——那是被注入的資料，不是「有東西驗它」。
        //
        // 不分開的話會自指：有一個 case 注入 runner 加一支叫 `fake-guard` 的守衛並斷言
        // 「它缺負控」，而那個名字在資料檔裡被讀成「已涵蓋」→ 守衛不紅 → 那一格失效。
        // 與 `zero-instance-rows-audit` 撞到的那個假編號是同一個形狀：**把測試資料放進被掃描
        // （那個編號的字面刻意不寫在這裡——寫了就會被那支守衛掃到，而那正是這段在講的事。
        //   這句話本身是第三次踩到同一個形狀：我在說明自指問題的註解裡製造了自指問題。）
        // 的範圍，它就會被當成事實**。
        // **標記要從未剝註解的原文讀**——它自己就是註解，`codeOnly` 會把它剝掉。
        // 這個小地方讓整段豁免靜默失效：資料檔走了通用分支，於是 case 的 `expect` 欄位
        // （裡面有被斷言「應該缺負控」的那個名字）被讀成「已涵蓋」。
        if String(rawFile(h).prefix(600)).contains("本檔由腳本生成") {
            for m in matches(code, #"guardRel: "akashic-guards ([a-z][a-z0-9-]*)""#) {
                covered.insert((code as NSString).substring(with: m.range(at: 1)))
            }
            continue
        }
        // ① 直接呼叫
        for m in matches(code, #"akashic-guards['"]?\s*,?\s*['"]([a-z][a-z0-9-]*)['"]"#) {
            covered.insert((code as NSString).substring(with: m.range(at: 1)))
        }
        for m in matches(code, #"akashic-guards ([a-z][a-z0-9-]*)"#) {
            covered.insert((code as NSString).substring(with: m.range(at: 1)))
        }
        // ③ **子命令作為獨立的字串字面**——`exec([BIN, "decision-matrix-drift", path])` 這種
        //    形式裡它不跟 `akashic-guards` 相鄰。`codeOnly` 已剝註解，所以「只在註解裡提到」
        //    不算數。
        for s in executed where code.contains("\"\(s)\"") { covered.insert(s) }
        // ② `MIGRATED` 表的值（遷移期的兩版並驗清單）
        if let mm = matches(code, #"(?s)MIGRATED\s*=\s*\{(.*?)\n\}"#).first {
            let blk = (code as NSString).substring(with: mm.range(at: 1))
            for m in matches(blk, #"'([a-z][a-z0-9-]*)'"#) {
                covered.insert((blk as NSString).substring(with: m.range(at: 1)))
            }
        }
    }

    // **harness 自己就是負控——要求「負控的負控」會無限遞歸。**
    //
    // 但**不靜默豁免**：`oracle-precondition-control` 的存在正是「harness 也可能需要
    // meta 檢查」的實例（它 import `audit-guards-mutations` 並驗那支 harness 自己的降級
    // 機制）。所以 harness 類**印出來**，交人裁決要不要 meta-harness，只是不計入缺口。
    //
    // **判準是結構的**：harness ＝ 它**執行**別的守衛（那就是負控的定義）。用「source 裡
    // 有 `Process()` 且提到守衛」而不是檔名——`migrated-guard-control` 的名字帶 `control`
    // 卻不是 harness（它讀 `run-guards.sh` 抽字串，不執行任何守衛），檔名判準會誤判它。
    //
    // **這是啟發式**：一個用別的方式 spawn 的 harness 會被判成非 harness（方向是**誤報**
    // ——它會被要求負控，而那是可見可裁決的，不是靜默漏放）。
    // **不列舉路徑前綴。** 上一版寫 `plugin/tests/`，而 `marker-parity-mutations` 執行的是
    // `plugin/skills/.../store-marker-parity.sh`——判準比它要描述的東西窄，於是一支真的
    // harness 被要求負控。改成拿 `run-guards.sh` 裡**實際跑的每一支守衛的檔名**去比對：
    // 那份清單本來就是唯一來源，不需要另外維護一組前綴。
    let guardNames = Set(matches(rg, #"(?m)^(?:python3|bash|swift) (\S+)"#).map {
        base((rg as NSString).substring(with: $0.range(at: 1)))
    })
    func isHarness(_ sub: String) -> Bool {
        let p = "Sources/akashic-guards/" + pascal(sub) + ".swift"
        guard fileExists(p) else { return false }
        let code = codeOnly(p)
        guard code.contains("Process()") else { return false }
        return code.contains("akashic-guards") || guardNames.contains(where: { code.contains($0) })
    }
    let uncovered = executed.filter { !covered.contains($0) }.sorted()
    let selfControl = uncovered.filter(isHarness)
    let missing = uncovered.filter { !isHarness($0) }
    print("══ 實際在跑的 Swift 守衛：\(executed.count) 支｜negative-control harness：\(harnesses.count) 支 ══")
    for s in selfControl {
        print("  ℹ `akashic-guards \(s)` 沒有負控，但它**自己就是**負控（source 裡執行別的守衛）"
            + "——不計入缺口。要不要替它寫 meta-harness 是人的裁決"
            + "（`oracle-precondition-control` 就是那樣的一個實例）")
    }
    for s in missing {
        print("  ✗ `akashic-guards \(s)` 在 run-guards.sh 裡跑，"
            + "但沒有任何 negative-control harness 驗它——")
        print("     那支守衛的負控（若有）驗的是**已經不再執行**的 Python 版。")
        print("     修法：讓它的 harness 兩版都跑並要求輸出逐字相同（見 #433 的第 4 步）。")
    }
    if missing.isEmpty {
        // **數字要與上面的 ℹ 對得起來**：說「11 支全部都有」而其中一支剛被印成「沒有負控」
        // ——那是同一份輸出裡的兩句矛盾的話，而本 repo 有一整支守衛在抓這個形狀。
        let need = executed.count - selfControl.count
        print("  \(need) 支需要負控的全部都有在驗實際執行的那一版"
            + (selfControl.isEmpty ? "" : "（另 \(selfControl.count) 支自己就是負控）"))
    }
    print("\n══ \(missing.isEmpty ? "無缺口" : "**\(missing.count) 支缺負控**") ══")
    return missing.isEmpty ? 0 : 1
}
