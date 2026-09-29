// 每支**實際在跑**的 Swift 守衛，都有 negative control 在驗它嗎？
//
// **為什麼有這支**（#433）：`run-guards.sh` 把一支守衛從 `plugin/tests/X.py` 換成
// `akashic-guards X` 之後，如果它的負控 harness 仍只跑 `.py`，那個負控驗的就是一個
// **不再被執行的實作**——負控全綠、runner 全綠，而實際在跑的那一版會不會紅，**沒有
// 任何東西在保證**。缺口在兩者中間，兩邊都看不到。
//
// **這不是零實例守衛，它有四個實例**：
//   1. `measured-numbers-audit` 等四支（`MIGRATED` 表，修完當次就抓到兩個真的翻譯遺漏）
//   2. `trigger-coverage` 與 `rule-prose-guards`（各自的獨立 harness）
//   3. **`decision-matrix-drift`——修完前兩個之後我仍然漏了它**：它是 A 批第一支遷的
//      （在第 4 步紀律建立之前），負控是獨立 harness 而不在 `MIGRATED` 表裡，於是
//      前兩處修正都沒有涵蓋到它
//   4. **`official-validate`**（#625）：從寫成那天就沒有負控，而 #689 之前的判準因為 `main.swift`
//      的分派把它算成「有」。#689 同輪補上 `official-validate-mutations`
//
// 第 3 個是這支守衛存在的直接理由：**我修了同一個形狀兩次，然後又漏了第三次**。
// 一條記在散文裡的紀律擋不住這個——它要求人每次遷移都想起來，而我沒有。
//
// **判準**（#689 起）：`run-guards.sh` 裡每個 `akashic-guards <sub>`，必須被某支**負控 harness**
// 提到，而「是不是負控 harness」看的是它的實體，三件事都要成立：
//   1. source 檔 `Sources/akashic-guards/<PascalCase>.swift` 存在（`swift-is-the-implementation-language`
//      的命名對應，`swiftGuards()` 用的同一條）；
//   2. `main.swift` 有 `case "<sub>":` 分派它——沒有的話跑它只會得到「未知的守衛」；
//   3. 它自己也在 `run-guards.sh` 裡跑——一個沒人跑的負控，就是 #433 那個形狀；
// 再加上結構判準：source 裡建一個 `Process` 且指向 `.build/debug/akashic-guards`（它**執行**別的守衛，那是負控的定義）。
// 「提到」只在 harness 自己的 source 與它的 `<PascalCase>Data.swift` 裡找（`"<sub>"` 字面或
// `akashic-guards <sub>`；生成的資料檔只認 `guardRel:`，理由見下）。
//
// **#689 修掉的東西**：上一版把 `Sources/akashic-guards/` 底下**每個檔**都當 harness 掃，並把
// 「`"<sub>"` 字面出現」算成涵蓋。`main.swift` 的分派表寫的正是 `case "<sub>":`，所以每支已註冊的
// 守衛都「有負控」——實測在副本裡刪掉 `NetworkConfinementMutations.swift`，這支仍印「無缺口」。
// 上一版的註解寫著「`main.swift` 寫的是 `case "X":` 而非 `akashic-guards X`，抓不到」——
// 那句話對兩個 regex 為真，對第三種形式（獨立字串字面）為假，而第三種正是讓它恆真的那一個。
//
// **一併移除的**（#689）：Python harness 的兩條 glob（`plugin/tests/*mutations*.py` 等）與 `MIGRATED`
// 表。#433 Step 5 之後樹裡沒有 Python harness，而新判準要求負控在 `run-guards.sh` 裡以
// `akashic-guards <sub>` 跑，Python 檔結構上不可能滿足——留著只是一條永遠空的分支。
//
// **誠實邊界**：它驗的是「有一支會跑的負控提到它」，不是「那個負控真的有效」。一個提到守衛名
// 卻不比對結果的 harness 照樣通過——本守衛擋的是**整個忘記**，不是**做錯**。後者由 harness
// 自己的 negative control 管（那是它們的職責，不是這支的）。「提到」也只是字面：
// `rule-prose-guards-mutations` 為了取根目錄清單而執行 `plugin-roots`，那也被算成提到它。
//
// **刻意不寫 `trigger-coverage: reads` 宣告**（#433 Step 5）：宣告存在的理由是補啟發式
// 的漏（守衛用 glob 組路徑、basename 不逐字出現）。這支讀的是同目錄的 harness source，
// 啟發式看得到——而指向自己所在目錄的宣告會被守衛判成「多半多餘」的警告。

import Foundation

func migratedGuardControl() -> Int32 {
    let runner = ".githooks/run-guards.sh"
    let dir = "Sources/akashic-guards/"
    let dispatcher = dir + "main.swift"
    guard fileExists(runner) else {
        print("✗ 找不到 \(runner)——守衛清單的唯一來源不見了")
        return 1
    }
    guard fileExists(dispatcher) else {
        print("✗ 找不到 \(dispatcher)——子命令的分派表不見了，無法判定哪支負控會被執行")
        return 1
    }
    // 只認**實際的呼叫**，不認註解裡提到的（`codeOnly` 剝掉整行註解，而 run-guards.sh
    // 的註解密度很高——不剝的話一句「`akashic-guards X` 的映射」就會被算成執行了它）。
    let rg = codeOnly(runner)
    // **允許縮排**（#629）：`rule-coverage` 在 `run-guards.sh` 裡是 `for root in $plugin_roots` 迴圈內逐根呼叫，
    // 行首有縮排；只認行首的版本會讓它「實際在跑、卻不在被檢查的名單裡」——這支守衛要防的正是那個形狀。
    // **也認命令替換**（#689）：`plugin_roots=$(… plugin-roots)` 同樣是實際執行，只認行首時它不在名單裡。
    // 同一支守衛可以在多處被呼叫（`rule-prose-guards` 先跑一次完整版、再逐根跑 `--prose-only`），要去重再數。
    var seenSubs = Set<String>()
    let executed = matches(rg, #"(?m)(?:^\s*|\$\()\.build/debug/akashic-guards ([a-z][a-z0-9-]*)"#).map {
        (rg as NSString).substring(with: $0.range(at: 1))
    }.filter { seenSubs.insert($0).inserted }
    guard !executed.isEmpty else {
        print("✗ \(runner) 裡一個 `akashic-guards <子命令>` 都抽不到——抽取式與寫法脫節了")
        return 1
    }

    let dispatch = codeOnly(dispatcher)
    func sourceOf(_ sub: String) -> String { dir + pascal(sub) + ".swift" }
    func isDispatched(_ sub: String) -> Bool { dispatch.contains("case \"\(sub)\":") }
    // **harness ＝ 它執行別的守衛**：source 裡建一個 `Process`（`= Process()`）、而且指向守衛的
    // binary（`.build/debug/akashic-guards`）。用結構而不是檔名：`migrated-guard-control` 的名字帶
    // `control` 卻不是 harness（它讀 `run-guards.sh` 抽字串，不執行任何守衛）。兩個條件缺一不可——
    // `measured-claims-audit` 有 `Process` 但跑的不是守衛（它的 `akashic-guards` 只出現在目錄路徑裡），
    // 本檔有那段 binary 路徑（抽取式裡）但不建 `Process`。這是啟發式——用別的方式 spawn 的
    // harness 會被判成非 harness，方向是**誤報**（它會被要求負控，那是看得見的）。
    func isHarness(_ sub: String) -> Bool {
        guard fileExists(sourceOf(sub)), isDispatched(sub) else { return false }
        let code = codeOnly(sourceOf(sub))
        return !matches(code, #"=\s*Process\(\)"#).isEmpty && code.contains(".build/debug/akashic-guards")
    }
    let harnesses = executed.filter(isHarness)

    /// harness `h` 提到的守衛。只看 `h` 自己的 source 與它的 `<PascalCase>Data.swift`。
    func named(by h: String) -> Set<String> {
        var files = [sourceOf(h)]
        let data = dir + pascal(h) + "Data.swift"
        if fileExists(data) { files.append(data) }
        var out = Set<String>()
        for f in files {
            let code = codeOnly(f)
            // **生成的資料檔只認 `guardRel:` 欄位**（#433 Step 5）：它同時裝著 case 的**受測
            // 對象**（`guardRel`）與**注入內容**（`new:`、`expect:`），而後者可能含守衛名的字面
            // ——那是被注入的資料，不是「有東西驗它」。不分開的話會自指：有一個 case 注入 runner
            // 加一支叫 `fake-guard` 的守衛並斷言「它缺負控」，那個名字若被讀成「已涵蓋」，那一格就失效。
            // **標記要從未剝註解的原文讀**——它自己就是註解，`codeOnly` 會把它剝掉。
            if String(rawFile(f).prefix(600)).contains("本檔由腳本生成") {
                for m in matches(code, #"guardRel: "akashic-guards ([a-z][a-z0-9-]*)""#) {
                    out.insert((code as NSString).substring(with: m.range(at: 1)))
                }
                continue
            }
            for m in matches(code, #"akashic-guards ([a-z][a-z0-9-]*)"#) {
                out.insert((code as NSString).substring(with: m.range(at: 1)))
            }
            // 子命令作為**獨立的字串字面**——`exec([BIN, "decision-matrix-drift", path])`、
            // `p.arguments = ["network-confinement"]` 這種形式裡它不跟 `akashic-guards` 相鄰。
            for s in executed where code.contains("\"\(s)\"") { out.insert(s) }
        }
        out.remove(h)
        return out
    }
    var coverers: [String: [String]] = [:]
    for h in harnesses {
        for g in named(by: h) { coverers[g, default: []].append(h) }
    }

    // **harness 自己就是負控——要求「負控的負控」會無限遞歸。** 但**不靜默豁免**：
    // `oracle-precondition-control` 的存在正是「harness 也可能需要 meta 檢查」的實例（它執行
    // `audit-guards-mutations` 並驗那支 harness 自己的降級機制）。所以沒被任何東西驗的 harness
    // **印出來**，交人裁決要不要 meta-harness，只是不計入缺口。
    let uncovered = executed.filter { coverers[$0] == nil }.sorted()
    let selfControl = uncovered.filter { harnesses.contains($0) }
    let missing = uncovered.filter { !harnesses.contains($0) }
    print("══ 實際在跑的 Swift 守衛：\(executed.count) 支｜會跑的 negative-control harness：\(harnesses.count) 支 ══")
    // **把對應攤開來**：每支守衛被哪些 harness 提到。讓漏掉的那條在人眼前缺席，而不是只印一個總數。
    for s in executed.sorted() where coverers[s] != nil {
        print("  · `\(s)` ← \(coverers[s]!.sorted().joined(separator: "、"))")
    }
    for s in selfControl {
        print("  ℹ `akashic-guards \(s)` 沒有負控，但它**自己就是**負控（source 裡執行別的守衛）"
            + "——不計入缺口。要不要替它寫 meta-harness 是人的裁決"
            + "（`oracle-precondition-control` 就是那樣的一個實例）")
    }
    for s in missing {
        print("  ✗ `akashic-guards \(s)` 在 run-guards.sh 裡跑，"
            + "但沒有任何會跑的 negative-control harness 驗它——")
        // 它若本身長得像負控卻不算數，說出是哪一件實體不在（#689 的三格負控各拆一樣）
        if !fileExists(sourceOf(s)) {
            print("     它的 source 檔不存在（\(sourceOf(s))）——它自己也不能算是別人的負控。")
        } else if !isDispatched(s) {
            print("     main.swift 沒有分派它（沒有 `case \"\(s)\":`，跑它會得到「未知的守衛」）——"
                + "它自己也不能算是別人的負控。")
        }
        print("     修法：寫一支 `<名字>-mutations`（source、main.swift 分派、run-guards.sh 三處都要有），"
            + "或把它的 case 加進會跑的 harness（例如 `AuditGuardsMutationsData.swift`）。")
    }
    if missing.isEmpty {
        // **數字要與上面的 ℹ 對得起來**：說「11 支全部都有」而其中一支剛被印成「沒有負控」
        // ——那是同一份輸出裡的兩句矛盾的話，而本 repo 有一整支守衛在抓這個形狀。
        let need = executed.count - selfControl.count
        print("  \(need) 支需要負控的全部都有會跑的負控"
            + (selfControl.isEmpty ? "" : "（另 \(selfControl.count) 支自己就是負控）"))
    }
    print("\n══ \(missing.isEmpty ? "無缺口" : "**\(missing.count) 支缺負控**") ══")
    return missing.isEmpty ? 0 : 1
}
