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
// **判準**（#689 起；R1 verify 起改成「宣告＋受測對象」）：`run-guards.sh` 裡每個 `akashic-guards <sub>`，必須有一支
// **負控 harness 宣告自己驗它、而且它的 source 文字裡有執行它的寫法**（受測對象）。**這是文字層的判定**：
// 它認的是 source 裡的寫法，不是 harness 執行時真的跑了什麼（#689 R2 verify；四個掏空的形狀見本段下方〈誠實邊界〉）。
//
// 「是不是負控 harness」看它的實體，四件事都要成立：
//   1. source 檔 `Sources/akashic-guards/<PascalCase>.swift` 存在（`swift-is-the-implementation-language`
//      的命名對應，`swiftGuards()` 用的同一條）；
//   2. `main.swift` 有 `case "<sub>":` 分派它——沒有的話跑它只會得到「未知的守衛」；
//   3. 它自己也在 `run-guards.sh` 裡跑——一個沒人跑的負控，就是 #433 那個形狀；
//   4. source 裡建一個 `Process`（`= Process()`）且指向 `.build/debug/akashic-guards`（它**執行**別的守衛，那是負控的定義）。
//
// **宣告**（harness 自己說它是誰的負控）有兩種來源：
//   · 命名慣例：`<g>-mutations` 宣告 `<g>`（`<g>` 要是實際在跑的守衛；`audit-guards-mutations` 的 `audit-guards` 不是，沒有慣例宣告）；
//   · source 裡一整行、從行首開始的 `// negative-control-for: <g>, <g>`（可以有多行）。宣告的名字不在 `run-guards.sh` 裡跑
//     ——拼錯或守衛已退場——是缺口，不靜默忽略。
//
// **受測對象**（source 裡以什麼寫法執行誰）只認執行它的寫法，不認提到它的寫法：
//   · harness 自己 source 裡的 argv 陣列字面——第一個元素是守衛名（`p.arguments = ["<g>"]`、`guardArgv: ["<g>", …]`），
//     或第一個是 `BIN`、第二個是守衛名（`exec([BIN, "<g>", …])`）。陣列字面若是賦給一個變數（`let x = ["<g>"]`），
//     那個變數要在同一檔出現在執行的位置（`guardArgv: x`、`arguments = x`、`exec(x`）才算（#689 R2 verify：
//     `plugin-roots-mutations` 把七處 `guardArgv: consistency` 全換掉，只剩宣告 `let consistency = [...]`，上一版照樣算數）；
//   · 它的 `<PascalCase>Data.swift` 裡 case 的受測對象欄位：`guardRel: "akashic-guards <g>"`、`guardArgv: ["<g>", …]`。
//     資料檔的其餘欄位（`a:`／`b:`／`old:`／`new:`／`expect:`）是注入內容，不算——那裡的守衛名是被塞進 copy 的字串，不是被執行的程式。
//
// 守衛算有負控＝某支 harness 宣告了它、而且以它為受測對象。只宣告而 source 裡沒有執行它的寫法（宣告是空的）是缺口；
// 只跑不宣告不算數。
//
// **為什麼要宣告，不只看受測對象**（R1 verify 四席）：上一版把「某支 harness 的 source 提到守衛名」算成有負控。
// `plugin-roots-mutations` 為了驗 plugin 根而跑 `trigger-coverage`，於是刪掉 `trigger-coverage` 自己那支 39 格的
// `TriggerCoverageMutations.swift`（連資料、分派、runner 那一行）仍印「無缺口」；`rule-prose-guards-mutations`
// 為了取根目錄清單而跑 `plugin-roots`，刪掉 `PluginRootsMutations.swift` 也一樣。#689 的 Expected 是「刪掉某支守衛的
// mutations 檔時，本守衛要失敗」——順帶跑一下不是負控，要 harness 自己宣告。
// **為什麼資料檔只認受測對象欄位**（R1 verify logic 席）：上一版只對帶「本檔由腳本生成」標記的資料檔這樣做，
// `TriggerCoverageMutationsData.swift` 的標記是「本檔曾由腳本生成」，對不上，於是它注入 runner 的那一行
// `.build/debug/akashic-guards plugin-store-format-parity` 被讀成「`trigger-coverage-mutations` 驗了它」。
//
// **#689 修掉的東西**：更早一版把 `Sources/akashic-guards/` 底下**每個檔**都當 harness 掃，並把「`"<sub>"` 字面出現」
// 算成涵蓋。`main.swift` 的分派表寫的正是 `case "<sub>":`，所以每支已註冊的守衛都「有負控」——實測在副本裡刪掉
// `NetworkConfinementMutations.swift`，這支仍印「無缺口」。
//
// **一併移除的**（#689）：Python harness 的兩條 glob（`plugin/tests/*mutations*.py` 等）與 `MIGRATED`
// 表。#433 Step 5 之後樹裡沒有 Python harness，而新判準要求負控在 `run-guards.sh` 裡以
// `akashic-guards <sub>` 跑，Python 檔結構上不可能滿足——留著只是一條永遠空的分支。
//
// **「實際在跑」的抽取認不出的寫法要出聲**（R1 verify logic／security 席；R2 verify 改成獨立定位）：抽取只認行首（可縮排）與
// 命令替換 `$(`，binary 路徑與子命令之間可以是任意個空白或 TAB。`if ! … ; then`、`a && …`、`timeout 60 …`、引號包住的 binary、
// 變數（`G=.build/debug/akashic-guards; "$G" x`）、迴圈變數、續行這類寫法照樣會執行，卻不在名單裡、也就不被要求負控。
// 所以剝註解後的 `run-guards.sh` 裡**每一處 `.build/debug/akashic-guards`**（只找路徑，不管後面接什麼）都必須落在一個被抽取
// 認得的呼叫裡，否則是缺口（逐行具名）。例外只有兩個具名的形狀：`[ ! -x .build/debug/akashic-guards ]` 存在檢查，與整行只有
// 一個 `echo "…"`、引號裡沒有 `$` 與反引號的訊息。R1 的版本拿同一條（只認單一空格的）regex 去找「漏掉的」，於是雙空格、TAB、
// 變數這些寫法兩邊都看不到——兩個檢查共用一個失敗條件。方向是誤報，看得見；不逐一擴充語法。
//
// **誠實邊界**：它驗的是「有一支會跑的負控宣告了它、而且 source 裡有執行它的寫法」，不是「那支負控執行時真的跑了它」，
// 更不是「那個負控真的有效」。一個執行守衛卻不比對結果的 harness 照樣通過——本守衛擋的是**整個忘記**，不是**做錯**。
// 後者由 harness 自己的 negative control 管。
// 受測對象的判定是文字層的。R2 verify（DA 席）在真實 harness 上做出四個不需要惡意的掏空形狀，現況逐一寫出：
//   1. case 表重構後只剩變數宣告（`let consistency = ["marketplace-consistency"]` 留著、七處 `guardArgv: consistency`
//      全換掉）——**R2 起擋下**：宣告出來的變數要在執行的位置被用到才算；
//   2. 在別的 harness 加 `// negative-control-for: <g>` 與一行死碼——`let _dead = ["<g>"]` 的形狀 **R2 起擋下**（同上），
//      但寫成直接執行的字面（`_ = exec([BIN, "<g>"])`）放在一個沒人呼叫的函式裡**仍然通過**：函式有沒有被呼叫，文字層看不到；
//   3. `main.swift` 把 `case "<g>-mutations": exit(…)` 改成 `exit(0)`——**仍然通過**：`isDispatched` 只找 `case "…":` 字面，
//      不看分派到哪裡；
//   4. 一支一般守衛在自己的 source 加 `let p = Process()` 與一個含 `.build/debug/akashic-guards` 的字串，就被當成
//      「自己就是負控」豁免——**R2 起擋下**：豁免只給以某支它宣告的守衛為受測對象的 harness（同一條宣告＋受測對象的規則）。
// 2 的後半與 3 要的是執行期的證據（harness 印出它實際跑了哪些守衛、由本守衛比對），那是另一個設計，另開 issue。
// source 裡一個第一個元素恰好是守衛名、卻不是 argv 的陣列字面，也仍會被當成受測對象；宣告這道閘在它前面，
// 所以那只會讓一個**已宣告**的守衛被當成有跑。
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
    // binary 路徑與子命令之間是**任意個空白或 TAB**（#689 R2 verify：先前只認一個空格，雙空格與 TAB 的呼叫會執行、卻不在名單裡）。
    let binPath = #"\.build/debug/akashic-guards"#
    let call = binPath + #"[ \t]+([a-z][a-z0-9-]*)"#
    let recognizedCalls = matches(rg, #"(?m)(?:^[ \t]*|\$\()"# + call)
    var seenSubs = Set<String>()
    let executed = recognizedCalls.map { (rg as NSString).substring(with: $0.range(at: 1)) }
        .filter { seenSubs.insert($0).inserted }
    guard !executed.isEmpty else {
        print("✗ \(runner) 裡一個 `akashic-guards <子命令>` 都抽不到——抽取式與寫法脫節了")
        return 1
    }
    // **認不出的寫法要出聲**（R1 verify；R2 verify 起獨立定位）：找的是 binary 路徑本身的每一處出現，不是「長得像呼叫」的那些
    // ——後者與抽取共用同一條 regex，抽取認不出的寫法它也認不出（雙空格、TAB、變數、引號都是這樣漏掉的）。每一處出現都必須
    // 落在一個被抽取認得的呼叫裡，或是下面兩個具名的例外之一。
    let exemptShapes = [
        #"\[[ \t]+(?:![ \t]+)?-x[ \t]+"# + binPath + #"[ \t]+\]"#,   // 存在檢查 `[ ! -x .build/debug/akashic-guards ]`
        #"(?m)^[ \t]*echo[ \t]+"[^"$`\n]*"[ \t]*$"#,                    // 整行只有一個 echo，引號裡沒有 `$` 與反引號（不執行任何東西）
    ]
    let accounted = recognizedCalls.map { $0.range } + exemptShapes.flatMap { matches(rg, $0).map { $0.range } }
    var unrecognized: [String] = []
    for o in matches(rg, binPath) where !accounted.contains(where: { NSLocationInRange(o.range.location, $0) }) {
        let line = (rg as NSString).substring(with: (rg as NSString).lineRange(for: o.range))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !unrecognized.contains(line) { unrecognized.append(line) }
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
    /// 回 nil＝它是 harness；否則是第一件不成立的實體（依判準的順序）。
    func whyNotHarness(_ sub: String) -> String? {
        if !fileExists(sourceOf(sub)) { return "它的 source 檔不存在（\(sourceOf(sub))）" }
        if !isDispatched(sub) { return "main.swift 沒有分派它（沒有 `case \"\(sub)\":`，跑它會得到「未知的守衛」）" }
        if !executed.contains(sub) { return "它不在 run-guards.sh 裡跑" }
        let code = codeOnly(sourceOf(sub))
        if matches(code, #"=\s*Process\(\)"#).isEmpty { return "它的 source 沒有建 `Process`（不執行任何程式）" }
        if !code.contains(".build/debug/akashic-guards") { return "它的 source 沒有指向 `.build/debug/akashic-guards`（不執行守衛）" }
        return nil
    }
    let harnesses = executed.filter { whyNotHarness($0) == nil }

    var problems: [String] = []
    /// harness `h` 宣告它是哪幾支守衛的負控：命名慣例，加上 source 裡從行首開始的 `// negative-control-for:` 行。
    /// **宣告從未剝註解的原文讀**——它自己就是註解，`codeOnly` 會把它剝掉。
    func claims(of h: String) -> Set<String> {
        var out = Set<String>()
        if h.hasSuffix("-mutations") {
            let g = String(h.dropLast("-mutations".count))
            if executed.contains(g) { out.insert(g) }
        }
        for m in matches(rawFile(sourceOf(h)), #"(?m)^// negative-control-for:(.*)$"#) {
            let list = (rawFile(sourceOf(h)) as NSString).substring(with: m.range(at: 1))
            for raw in list.split(separator: ",") {
                let g = raw.trimmingCharacters(in: .whitespaces)
                if matches(g, #"^[a-z][a-z0-9-]*$"#).isEmpty {
                    problems.append("`\(h)` 的 `negative-control-for:` 有一項不是守衛名：「\(g)」"); continue
                }
                if g == h { problems.append("`\(h)` 宣告它是自己的負控——負控的負控要另一支 harness"); continue }
                if !executed.contains(g) {
                    problems.append("`\(h)` 宣告它是 `\(g)` 的負控，但 `\(g)` 不在 run-guards.sh 裡跑"
                        + "——拼錯，或那支守衛已退場（宣告跟著拿掉）")
                    continue
                }
                out.insert(g)
            }
        }
        return out
    }
    /// harness `h` 以哪幾支守衛為受測對象：自己 source 裡的 argv 陣列字面，與資料檔的受測對象欄位（判準見檔頭）。
    func targets(of h: String) -> Set<String> {
        var out = Set<String>()
        let src = codeOnly(sourceOf(h))
        let ns = src as NSString
        // 陣列字面若是 `let x = [...]`／`var x = [...]`，group 1 是 `x`：它要在同一檔出現在執行的位置才算（#689 R2 verify）。
        let literal = #"(?:\b(?:let|var)[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*(?::[^=\n]*)?=[ \t]*)?"#
            + #"\[\s*(?:BIN\s*,\s*)?"([a-z][a-z0-9-]*)""#
        for m in matches(src, literal) {
            if m.range(at: 1).location != NSNotFound {
                let v = NSRegularExpression.escapedPattern(for: ns.substring(with: m.range(at: 1)))
                if matches(src, #"(?:guardArgv:|\barguments[ \t]*=|\bexec\()[ \t]*"# + v + #"\b"#).isEmpty { continue }
            }
            out.insert(ns.substring(with: m.range(at: 2)))
        }
        let data = dir + pascal(h) + "Data.swift"
        for f in [sourceOf(h)] + (fileExists(data) ? [data] : []) {
            let code = codeOnly(f)
            for p in [#"guardRel:\s*"akashic-guards ([a-z][a-z0-9-]*)""#, #"guardArgv:\s*\[\s*"([a-z][a-z0-9-]*)""#] {
                for m in matches(code, p) { out.insert((code as NSString).substring(with: m.range(at: 1))) }
            }
        }
        return out.intersection(executed)
    }
    var coverers: [String: [String]] = [:]
    for h in harnesses {
        let t = targets(of: h)
        for g in claims(of: h).sorted() {
            if t.contains(g) {
                coverers[g, default: []].append(h)
            } else {
                problems.append("`\(h)` 宣告它是 `\(g)` 的負控，卻沒有以 `\(g)` 為受測對象"
                    + "（source 裡沒有執行它的 argv、資料檔也沒有 `guardRel:`／`guardArgv:` 指向它）——宣告是空的，不算數")
            }
        }
    }

    // **harness 自己就是負控——要求「負控的負控」會無限遞歸。** 但**不靜默豁免**：
    // `oracle-precondition-control` 的存在正是「harness 也可能需要 meta 檢查」的實例（它執行
    // `audit-guards-mutations` 並驗那支 harness 自己的降級機制）。所以沒被任何東西驗的 harness
    // **印出來**，交人裁決要不要 meta-harness，只是不計入缺口。
    // **豁免只給真的在當負控的 harness**（#689 R2 verify，security／DA 席）：上一版只看 `whyNotHarness`（四個文字條件），
    // 一支一般守衛在 source 塞 `let p = Process()` 與一個含 binary 路徑的字串就被豁免。現在它要以某支它宣告的守衛為受測對象——
    // 同一條「宣告＋受測對象」的規則，也就是它自己出現在上面的對應表裡。
    let creditedHarnesses = Set(coverers.values.flatMap { $0 })
    let uncovered = executed.filter { coverers[$0] == nil }.sorted()
    let selfControl = uncovered.filter { creditedHarnesses.contains($0) }
    let missing = uncovered.filter { !creditedHarnesses.contains($0) }
    print("══ 實際在跑的 Swift 守衛：\(executed.count) 支｜會跑的 negative-control harness：\(harnesses.count) 支 ══")
    // **把對應攤開來**：每支守衛由哪些 harness 宣告並執行。讓漏掉的那條在人眼前缺席，而不是只印一個總數。
    for s in executed.sorted() where coverers[s] != nil {
        print("  · `\(s)` ← \(coverers[s]!.sorted().joined(separator: "、"))")
    }
    for s in selfControl {
        print("  ℹ `akashic-guards \(s)` 沒有負控，但它**自己就是**負控（宣告並執行別的守衛）"
            + "——不計入缺口。要不要替它寫 meta-harness 是人的裁決"
            + "（`oracle-precondition-control` 就是那樣的一個實例）")
    }
    for s in missing {
        print("  ✗ `akashic-guards \(s)` 在 run-guards.sh 裡跑，"
            + "但沒有任何會跑的 negative-control harness 宣告並執行它——")
        // 慣例的負控只拆掉一部分時，說出不見的是哪一件實體（全部拆掉時它就是不存在，上一行已經說了）
        let conventional = s + "-mutations"
        if fileExists(sourceOf(conventional)) || isDispatched(conventional) || executed.contains(conventional),
           let why = whyNotHarness(conventional) {
            print("     它的慣例負控 `\(conventional)` 不算數：\(why)。")
        }
        // 它若本身長得像負控卻不算數，說出是哪一件實體不在（#689 的負控格各拆一樣）。一般守衛不是 harness 是正常的，
        // 只有缺 source 或分派時才說（那兩件對任何子命令都是必要的）。
        if let why = whyNotHarness(s),
           !fileExists(sourceOf(s)) || !isDispatched(s) || s.hasSuffix("-mutations") || s.hasSuffix("-control") {
            print("     它自己也不能算是別人的負控：\(why)。")
        } else if whyNotHarness(s) == nil {
            print("     它長得像負控（建 `Process` 並指向 `.build/debug/akashic-guards`），但沒有以任何它宣告的守衛為受測對象，"
                + "所以也不算「自己就是負控」。")
        }
        print("     修法：寫一支 `<名字>-mutations`（source、main.swift 分派、run-guards.sh 三處都要有），"
            + "或在會跑的 harness 加執行它的 case，並在那支 harness 的 source 加一行 `// negative-control-for: \(s)`。")
    }
    for u in unrecognized {
        problems.append("run-guards.sh 這一行有 `.build/debug/akashic-guards`，但抽取認不出它是哪一支守衛的呼叫"
            + "（只認行首與 `$(`、路徑後接空白與子命令名）：「\(u)」——改成獨立一行，或擴充抽取並補負控")
    }
    for p in problems { print("  ✗ \(p)") }
    if missing.isEmpty && problems.isEmpty {
        // **數字要與上面的 ℹ 對得起來**：說「11 支全部都有」而其中一支剛被印成「沒有負控」
        // ——那是同一份輸出裡的兩句矛盾的話，而本 repo 有一整支守衛在抓這個形狀。
        let need = executed.count - selfControl.count
        print("  \(need) 支需要負控的全部都有會跑的負控"
            + (selfControl.isEmpty ? "" : "（另 \(selfControl.count) 支自己就是負控）"))
    }
    let bad = missing.count + problems.count
    print("\n══ \(bad == 0 ? "無缺口" : "**\(missing.count) 支缺負控、\(problems.count) 條宣告或抽取的問題**") ══")
    return bad == 0 ? 0 : 1
}
