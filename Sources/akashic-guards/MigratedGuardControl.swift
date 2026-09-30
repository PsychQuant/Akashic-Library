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
// ## 判準（#707 起：讀執行紀錄，不讀原始碼）
//
// #689 的判準讀原始碼文字：harness 的宣告（命名慣例、`// negative-control-for:`）、argv 陣列字面、資料檔的
// `guardRel:`／`guardArgv:`、`main.swift` 的 `case "…":`、`run-guards.sh` 裡的呼叫寫法。#689 的 R2、R3 verify
// 在真實 harness 上做出十種文字對得上、執行已經不在的寫法（只剩變數宣告、別的 harness 的死碼與宣告、分派改成
// `exit(0)`、守衛本體塞 `Process()` 冒充負控、宣告換行或巢狀、`return 0` 後接 `#if false`、呼叫放進 `"""` 字串、
// runner 裡 `if false`／heredoc 包住那一行、目錄放進變數、`swift run`／`.build/release`）。每補一種寫法，文字比對
// 就多一個可以繞的邊。現在證據是 `run-guards.sh` 這一次執行留下的紀錄（格式與寫入點見 `GuardRunLog.swift`）：
//
//   · **誰要負控**：紀錄裡每一筆 `start` 的子命令——`run-guards.sh` 這次真的啟動了它，不論用什麼路徑、什麼寫法
//     呼叫。另外保留一個文字檢查（見下）。
//   · **誰有負控**：某支 harness 在這次執行裡（1）宣告了它——`<g>-mutations` 的命名慣例，或執行時呼叫
//     `declareNegativeControl`；（2）以 rc=0 跑完（有 `end`、rc=0）；（3）經 `runGuardProcess` 執行了它，
//     而且至少一次**如預期變紅**（`expect=red`、觀察到的 rc≠0）——列舉命令 `plugin-roots` 本來就不會紅，
//     它的是**輸出如預期**（`expect=output`、stdout 逐字相符）；（4）執行的是**這一支 binary**。
//     預期成不成立（`met`）由 `runGuardProcess` 自己比對，harness 只說它預期什麼。
//   · harness 自己沒有負控、但它**確實**替別的守衛作證（出現在對應表的右邊）→「它自己就是負控」，印 ℹ、不計入缺口。
//
// **也算缺口的紀錄形狀**：
//   · 宣告了、跑完了，卻沒有一次讓那支守衛如預期變紅——宣告是空的；
//   · harness 以 rc=0 跑完，但它有執行沒照它自己的預期（預期紅、實際綠）——它沒有比對結果；
//   · harness 沒有以 rc=0 跑完（rc≠0 或沒有 `end`）卻出現在紀錄裡——`run-guards.sh` 是 `set -e`，它的失敗被遮掉了；
//   · 執行的 `akashic-guards` 不是本支這一支 binary；宣告自己、宣告一支這次沒跑的守衛；
//   · 紀錄讀不到、是空的、有一行不是這個格式、或沒有本支自己這一次的 `start`（`AKASHIC_GUARD_RUN_LOG` 沒指向
//     `--log` 那份檔，或 `main.swift` 沒寫 start）——**空掃描不是通過**。
//
// **留下的文字檢查（只在「誰要負控」那一邊）**：剝註解後的 runner 裡每一處 `akashic-guards <子命令>`
// （可以隔一個引號：`"$B/akashic-guards" x`），紀錄裡都要有它的 `start`。它補的是執行期看不到的那一種：
// runner 列了一支守衛、它卻沒有執行，或執行的 binary 不寫紀錄（舊的建置、拿掉了環境變數）——那支守衛不會出現在
// 「誰要負控」裡，只有文字知道它本來該在。**「誰有負控」那一邊不讀任何原始碼。**
//
// **拿掉的文字判準**（#689 的全部）：harness 的四個實體條件（source 檔、`main.swift` 分派、runner 那一行、
// `= Process()` 加 binary 路徑）、`// negative-control-for:` 註解、argv 陣列字面與變數追蹤、資料檔欄位、
// 「抽取認不出的呼叫」偵測。它們的歷史與負控見 `changelog/2026-09-30-migrated-guard-control-artefacts.md`。
//
// **誠實邊界**：
//   · 紀錄是一般檔案。一支 harness 直接打開 `AKASHIC_GUARD_RUN_LOG` 寫一行假的 `invoke`，本支分不出來——
//     它擋的是遺忘與掏空（負控的實體還在、執行已經不在），不是蓄意偽造。
//   · 宣告與預期是 harness 自己說的。它讓守衛變紅的原因可以與注入無關（例如傳一個壞掉的參數）——本支證明
//     「它執行了、它紅了、harness 預期它紅」，紅的原因對不對由 harness 自己的具名比對管（對不上時 harness 回非零，
//     `run-guards.sh` 在這支之前就停了）。
//   · runner 裡**既不以 `akashic-guards <名>` 的文字出現、又不寫紀錄**的呼叫兩邊都看不到（例如
//     `env -u AKASHIC_GUARD_RUN_LOG "$G" x`，其中 `G` 是 binary 的路徑）。
//   · harness 不經 `runGuardProcess` 自己 spawn 的守衛：那些執行不算數（方向是缺負控，看得見）；它若把紀錄的
//     環境變數傳下去，那支守衛會寫 `start`、被當成 runner 跑的而被要求負控（同一個方向）。
//
// **刻意不寫 `trigger-coverage: reads` 宣告**（#433 Step 5）：本支讀的是 `run-guards.sh`（受保護、路徑以字面
// 出現，啟發式看得到）與暫存目錄裡的紀錄。

import Foundation

/// 紀錄的一行（形狀已驗過）。
private struct RunLogLine {
    let line: Int
    let event: String
    let run: String
    let who: String
    let fields: [String: Any]
}

private let runLogEvents: Set<String> = ["start", "declare", "invoke", "end"]
private let runLogExpectations: Set<String> = ["red", "green", "output", "none"]

private func isGuardName(_ s: String) -> Bool { !matches(s, #"^[a-z][a-z0-9-]*$"#).isEmpty }

/// 一行紀錄的形狀（格式見 `GuardRunLog.swift`）。不合時回說明。
private func parseRunLogLine(_ raw: String, line n: Int) -> Result<RunLogLine, RunLogShapeError> {
    func bad(_ why: String) -> Result<RunLogLine, RunLogShapeError> {
        .failure(RunLogShapeError(text: "執行紀錄第 \(n) 行\(why)：\(pyRepr([String(raw.prefix(120))]))"))
    }
    guard let obj = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any] else {
        return bad("不是 JSON 物件")
    }
    guard let v = obj["v"] as? Int, v == GuardRunLog.formatVersion else { return bad("的格式版本不是 \(GuardRunLog.formatVersion)") }
    guard let event = obj["event"] as? String, runLogEvents.contains(event) else { return bad("的 event 不在 start／declare／invoke／end 裡") }
    guard let run = obj["run"] as? String, !run.isEmpty else { return bad("沒有 run") }
    guard let who = obj["self"] as? String, isGuardName(who) else { return bad("的 self 不是子命令名") }
    switch event {
    case "declare":
        guard let list = obj["for"] as? [String], !list.isEmpty, list.allSatisfy(isGuardName) else {
            return bad("的 declare 沒有守衛名的清單（for）")
        }
    case "invoke":
        guard let target = obj["target"] as? String, isGuardName(target),
              let exe = obj["exe"] as? String, !exe.isEmpty,
              let expect = obj["expect"] as? String, runLogExpectations.contains(expect),
              obj["met"] as? Bool != nil, obj["rc"] as? Int != nil,
              obj["case"] as? String != nil, obj["argv"] as? [String] != nil else {
            return bad("的 invoke 缺欄位（target／exe／expect／met／rc／case／argv）或值的型別不對")
        }
    case "end":
        guard obj["rc"] as? Int != nil else { return bad("的 end 沒有 rc") }
    default:
        break
    }
    return .success(RunLogLine(line: n, event: event, run: run, who: who, fields: obj))
}

private struct RunLogShapeError: Error { let text: String }

func migratedGuardControl(argv: [String]) -> Int32 {
    var logPath: String? = nil
    var runner = ".githooks/run-guards.sh"
    var i = 0
    while i < argv.count {
        if argv[i] == "--log", i + 1 < argv.count { logPath = argv[i + 1]; i += 2; continue }
        // `--runner` 的唯一用途是負控（迷你 runner 在暫存目錄）——出貨的呼叫只帶 `--log`
        if argv[i] == "--runner", i + 1 < argv.count { runner = argv[i + 1]; i += 2; continue }
        print("✗ 看不懂的參數 \(pyRepr([argv[i]]))——用法：migrated-guard-control --log <執行紀錄> [--runner <runner 腳本>]")
        return 64
    }
    guard let logPath else {
        print("✗ 需要 --log <執行紀錄>。本支讀的是 run-guards.sh 這一次執行留下的紀錄（#707），單獨跑它沒有東西可讀"
            + "——跑 `bash .githooks/run-guards.sh`")
        return 64
    }

    let runnerFull = runner.hasPrefix("/") ? runner : "\(repoRoot)/\(runner)"
    guard let runnerRaw = try? String(contentsOfFile: runnerFull, encoding: .utf8) else {
        print("✗ 讀不到 \(runner)——守衛清單的唯一來源不見了")
        return 1
    }
    let runnerCode = codeOnlyText(runnerRaw, path: runner)

    // ── 讀紀錄：讀不到、空的、形狀不對，都不判定 ────────────────────────────
    guard let data = FileManager.default.contents(atPath: logPath) else {
        print("✗ 讀不到執行紀錄 \(logPath)——沒有紀錄就不知道這次跑了什麼、哪支負控真的讓它們紅過")
        return 1
    }
    guard let text = String(data: data, encoding: .utf8) else {
        print("✗ 執行紀錄 \(logPath) 不是 UTF-8"); return 1
    }
    var rawLines = text.components(separatedBy: "\n")
    if rawLines.last == "" { rawLines.removeLast() }
    guard !rawLines.isEmpty else {
        print("✗ 執行紀錄是空的（\(logPath)）——空掃描不是通過：一支守衛都沒有留下紀錄，"
            + "表示紀錄的寫入沒有接上（`main.swift` 的 `recordGuardStart`、runner 的 `AKASHIC_GUARD_RUN_LOG`）")
        return 1
    }
    var lines: [RunLogLine] = []
    var shape: [String] = []
    for (idx, raw) in rawLines.enumerated() {
        switch parseRunLogLine(raw, line: idx + 1) {
        case .success(let l): lines.append(l)
        case .failure(let e): shape.append(e.text)
        }
    }
    // 同一個 run 的每一行都要是同一支、恰一筆 start、至多一筆 end
    var byRun: [String: [RunLogLine]] = [:]
    var runOrder: [String] = []
    for l in lines {
        if byRun[l.run] == nil { runOrder.append(l.run) }
        byRun[l.run, default: []].append(l)
    }
    for r in runOrder {
        let ls = byRun[r]!
        let starts = ls.filter { $0.event == "start" }.count
        let ends = ls.filter { $0.event == "end" }.count
        let whos = Set(ls.map { $0.who })
        if starts != 1 {
            shape.append("run \(r) 有 \(starts) 筆 start（第 \(ls.map { String($0.line) }.joined(separator: "、")) 行）——每個行程恰一筆")
        }
        if ends > 1 { shape.append("run \(r) 有 \(ends) 筆 end") }
        if whos.count != 1 { shape.append("run \(r) 的 self 不只一個：\(whos.sorted().joined(separator: "、"))") }
    }
    if !shape.isEmpty {
        for s in shape.prefix(20) { print("  ✗ \(s)") }
        if shape.count > 20 { print("  ✗ ……另有 \(shape.count - 20) 處") }
        print("\n══ **執行紀錄的形狀不對（\(shape.count) 處）——紀錄不可信，不判定** ══")
        return 1
    }
    // 本支自己這一次的 start 必須在：證明 --log 就是本支正在寫的那一份，而且 start 的寫入接上了
    guard byRun[GuardRunLog.runID]?.contains(where: { $0.event == "start" && $0.who == "migrated-guard-control" }) == true else {
        print("✗ 紀錄裡沒有本支這一次執行的 start（run \(GuardRunLog.runID)）——`AKASHIC_GUARD_RUN_LOG` 沒有指向 "
            + "--log 那份檔，或 `main.swift` 沒有寫 start。這份紀錄不是這一次執行留下的，不判定")
        return 1
    }
    // 本支自己的 start 是讀之前寫進去的，所以「空」指的是除了它之外一筆都沒有
    guard runOrder.contains(where: { $0 != GuardRunLog.runID }) else {
        print("✗ 執行紀錄是空的（\(logPath)）：除了本支這一次的 start，一筆都沒有——空掃描不是通過。"
            + "沒有任何守衛留下紀錄，表示紀錄的寫入沒有接上（runner 沒有 export `AKASHIC_GUARD_RUN_LOG`？）")
        return 1
    }

    // ── 誰要負控：這次啟動過的每一支 ─────────────────────────────────────
    let ran = Set(lines.filter { $0.event == "start" }.map { $0.who })
    var problems: [String] = []
    func problem(_ p: String) { if !problems.contains(p) { problems.append(p) } }
    // 文字只用在這一邊：runner 列了、卻沒有 start 的（沒跑，或跑的 binary 不寫紀錄）
    for g in Set(captures(runnerCode, #"akashic-guards['"]?[ \t]+([a-z][a-z0-9-]*)"#)).sorted() where !ran.contains(g) {
        problem("\(runner) 呼叫 `akashic-guards \(g)`，但這次執行的紀錄裡沒有它的 start——它沒有執行"
            + "（在沒跑到的分支或 heredoc 裡？），或執行的 binary 不寫紀錄（舊的建置、拿掉了 `AKASHIC_GUARD_RUN_LOG`）")
    }

    // ── 誰有負控：宣告、跑完、執行了這一支 binary、至少一次如預期 ─────────────
    let ownExe = GuardRunLog.ownExecutable
    var coverers: [String: [String: (red: Int, output: Int)]] = [:]
    var attempts: [String: [String]] = [:]
    var harnessRuns = 0
    for r in runOrder where r != GuardRunLog.runID {
        let ls = byRun[r]!
        let h = ls[0].who
        let invokes = ls.filter { $0.event == "invoke" }
        var declared = Set<String>()
        if h.hasSuffix("-mutations") {
            let g = String(h.dropLast("-mutations".count))
            if ran.contains(g) { declared.insert(g) }
        }
        for d in ls where d.event == "declare" {
            for g in d.fields["for"] as! [String] {
                if g == h { problem("`\(h)` 宣告它是自己的負控——負控的負控要另一支 harness"); continue }
                if !ran.contains(g) {
                    problem("`\(h)` 宣告它是 `\(g)` 的負控，但 `\(g)` 這次沒有跑——拼錯，或那支守衛已退場（宣告跟著拿掉）")
                    continue
                }
                declared.insert(g)
            }
        }
        if invokes.isEmpty && declared.isEmpty { continue }
        if !invokes.isEmpty { harnessRuns += 1 }
        let endRC = ls.first(where: { $0.event == "end" })?.fields["rc"] as? Int
        let completed = endRC == 0
        if !completed {
            let why = endRC.map { "以 rc=\($0) 結束" } ?? "沒有結束紀錄（沒經過 `finishGuard` 就結束，或中途被殺）"
            problem("`\(h)` \(why)——它的 \(invokes.count) 次執行都不算數"
                + "（run-guards.sh 是 `set -e`：沒跑完的 harness 出現在紀錄裡，表示它的失敗被遮掉了）")
        }
        var unmet: [String] = []
        var detected = Set<String>()
        for inv in invokes {
            let target = inv.fields["target"] as! String
            let exe = inv.fields["exe"] as! String
            let expect = inv.fields["expect"] as! String
            let met = inv.fields["met"] as! Bool
            let rc = inv.fields["rc"] as! Int
            let label = inv.fields["case"] as! String
            let foreign = exe != ownExe
            if foreign {
                problem("`\(h)` 執行的 `akashic-guards \(target)` 不是這一支 binary（\(exe)；本支是 \(ownExe)）——那些執行不算數")
            }
            if completed && !met { unmet.append("「\(label)」預期 \(expect)、rc=\(rc)") }
            guard met, expect == "red" || expect == "output", !foreign, target != h else { continue }
            let how = expect == "red" ? "變紅" : "輸出如預期"
            if !completed {
                attempts[target, default: []].append("`\(h)` 讓它\(how)過，但那支 harness 沒有以 rc=0 跑完")
                continue
            }
            if !declared.contains(target) {
                attempts[target, default: []].append("`\(h)` 讓它\(how)過，但 `\(h)` 沒有宣告它——順帶跑不算（#689 R1）")
                continue
            }
            var c = coverers[target, default: [:]][h] ?? (0, 0)
            if expect == "red" { c.red += 1 } else { c.output += 1 }
            coverers[target, default: [:]][h] = c
            detected.insert(target)
        }
        if !unmet.isEmpty {
            problem("`\(h)` 以 rc=0 跑完，但它有 \(unmet.count) 次執行沒有照它自己的預期——它沒有比對結果："
                + unmet.prefix(3).joined(separator: "；") + (unmet.count > 3 ? "……" : ""))
        }
        if completed {
            for g in declared.sorted() where !detected.contains(g) {
                problem("`\(h)` 宣告它是 `\(g)` 的負控，但這次執行裡它沒有一次讓 `\(g)` 如預期變紅（或輸出如預期）——宣告是空的")
            }
        }
    }

    // **harness 自己就是負控——要求「負控的負控」會無限遞歸。** 但**不靜默豁免**：`oracle-precondition-control`
    // 的存在正是「harness 也可能需要 meta 檢查」的實例。豁免只給這次**確實**替別的守衛作證的 harness（出現在
    // 對應表右邊的）——一支從沒讓任何守衛紅過的程式，不論它的原始碼長什麼樣，都不是負控（#689 的第 4 種形狀）。
    let credited = Set(coverers.values.flatMap { $0.keys })
    let uncovered = ran.filter { coverers[$0] == nil }
    let selfControl = uncovered.filter { credited.contains($0) }.sorted()
    let missing = uncovered.filter { !credited.contains($0) }.sorted()

    print("══ 執行紀錄 \(rawLines.count) 行｜這次跑了 \(ran.count) 支守衛｜留下執行紀錄的 harness \(harnessRuns) 次 ══")
    for g in ran.sorted() {
        guard let cs = coverers[g] else { continue }
        let who = cs.keys.sorted().map { h -> String in
            let c = cs[h]!
            return "\(h)（" + [c.red > 0 ? "紅 \(c.red) 次" : nil, c.output > 0 ? "輸出比對 \(c.output) 次" : nil]
                .compactMap { $0 }.joined(separator: "、") + "）"
        }
        print("  · `\(g)` ← \(who.joined(separator: "、"))")
    }
    for s in selfControl {
        print("  ℹ `akashic-guards \(s)` 沒有負控，但它**自己就是**負控（這次確實讓別的守衛如預期變紅過）"
            + "——不計入缺口。要不要替它寫 meta-harness 是人的裁決（`oracle-precondition-control` 就是那樣的一個實例）")
    }
    for s in missing {
        print("  ✗ `akashic-guards \(s)` 這次執行跑了，但沒有任何 harness 在執行時宣告它、以 rc=0 跑完、"
            + "並讓它如預期變紅過——")
        for a in (attempts[s] ?? []).prefix(5) { print("     · \(a)") }
        print("     修法：寫一支 `\(s)-mutations`（經 `runGuardProcess` 執行它、至少一格預期 `.red`），"
            + "或在會跑的 harness 加執行它的格子，並在那支 harness 開頭呼叫 `declareNegativeControl(for: [\"\(s)\"])`；"
            + "harness 要在 run-guards.sh 裡、排在本支之前")
    }
    for p in problems { print("  ✗ \(p)") }
    if missing.isEmpty && problems.isEmpty {
        // **數字要與上面的 ℹ 對得起來**：說「N 支全部都有」而其中一支剛被印成「沒有負控」是同一份輸出裡的兩句矛盾的話
        print("  \(ran.count - selfControl.count) 支需要負控的全部都有，而且這次真的讓它們紅過"
            + (selfControl.isEmpty ? "" : "（另 \(selfControl.count) 支自己就是負控）"))
    }
    let bad = missing.count + problems.count
    print("\n══ \(bad == 0 ? "無缺口" : "**\(missing.count) 支缺負控、\(problems.count) 條紀錄的問題**") ══")
    return bad == 0 ? 0 : 1
}
