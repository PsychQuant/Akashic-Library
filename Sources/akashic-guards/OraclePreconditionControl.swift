// `audit-guards-mutations` 兩個**自檢**機制的負控（#407 R67h／R67j）。
//
// **檢查一：ROBUST oracle 的前提**。R67 讓 ROBUST 負控拿「守衛在未注入 copy 上的輸出」當
// oracle、要求逐字相同；R67e 又加了「跑兩次比對以驗決定性」。那個前提檢查是 harness 裡唯一
// 一個**失敗會外溢**的機制（假紅會讓人開始不相信所有紅燈），所以它自己要被檢查：要求 harness
// 乾淨降級而不是 crash 或假裝通過——前提不成立時具名報出是哪一支守衛，且那一支的 ROBUST
// case **全部不計入**通過數（不是只少一格）。
//
// **檢查二：逐守衛的 baseline**（R67j）。harness 上一版只驗兩支守衛的 baseline，於是其餘
// 守衛若在注入**之前**就已經紅，它們的控制組會平白通過。
//
// ## 注入機制：環境變數 ＋ subprocess，不是 monkey-patch（#433）
//
// Python 版 `import` harness 模組並改寫 `mod.with_copy`。Swift 沒有那個機制。用「可注入的
// withCopy 參數」是更直接的對應，但 `main()` 的輸出要被捕捉，那就得把 harness 裡所有 `print`
// 改成可注入的 sink——一次波及整支的重構，換到的東西與 subprocess 相同。
//
// subprocess 另有一個好處：**它跑的是真的出貨路徑**，與使用者跑
// `akashic-guards audit-guards-mutations` 完全一樣。
//
// 代價：出貨的 binary 多三個只有本支會設的環境變數。它們必須 (a) 帶 `AKASHIC_` 前綴、
// (b) 在被注入處具名、(c) **未設定時完全沒有行為**——否則就是藏在出貨路徑裡的後門。
// 第三點有實測：未設定時輸出與 Python 版逐位元相同。
//
// trigger-coverage: reads plugin/tests/*.py

import Foundation

func oraclePreconditionControl() -> Int32 {
    let BIN = "\(repoRoot)/.build/debug/akashic-guards"

    /// 跑 harness 自己（真的出貨路徑），帶指定的注入環境變數。
    func runHarness(_ extraEnv: [String: String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: BIN)
        p.arguments = ["audit-guards-mutations"]
        p.currentDirectoryURL = URL(fileURLWithPath: repoRoot)
        var env = ProcessInfo.processInfo.environment
        env["AKASHIC_SKIP_CASES"] = "1"          // 只跑 ROBUST——CASES 與本控制組無關
        for (k, v) in extraEnv { env[k] = v }
        p.environment = env
        let o = Pipe(), e = Pipe(); p.standardOutput = o; p.standardError = e
        guard (try? p.run()) != nil else { return (127, "spawn 失敗") }
        let od = o.fileHandleForReading.readDataToEndOfFile()
        _ = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: od, encoding: .utf8) ?? "")
    }
    func passCount(_ out: String) -> (Int, Int)? {
        guard let m = matches(out, #"negative control (\d+)/(\d+)"#).first else { return nil }
        let ns = out as NSString
        return (Int(ns.substring(with: m.range(at: 1))) ?? -1, Int(ns.substring(with: m.range(at: 2))) ?? -1)
    }

    let hasSwift = FileManager.default.isExecutableFile(atPath: "/usr/bin/swift")
        || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/swift")
    let DRIFT = "plugin/skills/akashic-literal-campaign/scripts/tests/hash-table-drift.sh"
    var counts: [String: Int] = [:]
    for c in agmRobust {
        if !hasSwift && (c.guardRel.hasSuffix(".swift") || c.guardRel == DRIFT) { continue }
        counts[c.guardRel, default: 0] += 1
    }
    guard !counts.isEmpty else {
        print("✗ 過濾後沒有任何可毒化的 ROBUST 守衛——本控制組在此環境退化成空的。"
            + "（全部 ROBUST 守衛都需要 Swift 而此環境沒有？）")
        return 1
    }
    // 挑 ROBUST case 最多的那一支——**這支控制組要測的是「那一支的 case 全部不計入」**，
    // 只有一格的守衛測不到「第二格」那條路徑（R67e 的 scratch probe 正是栽在這裡：它挑的
    // 守衛只有一個 ROBUST case，第一輪就 continue 了）。
    let target = counts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })!.key
    let nCases = counts[target]!
    print("══ 毒化 \(target)（\(nCases) 個 ROBUST case，全樹最多）══")
    if nCases < 2 {
        print("✗ 全樹沒有任何守衛有 2 個以上 ROBUST case——這支控制組退化成測不到"
            + "「第二格」那條路徑。加一個 ROBUST case，或刪掉這支並說明為什麼。")
        return 1
    }

    // 先量未毒化的通過數。
    let clean = runHarness([:])
    guard let (cleanOK, _) = passCount(clean.1) else {
        print("✗ 讀不到未毒化時的通過數——harness 的輸出格式變了")
        return 1
    }

    // ── 檢查一 ────────────────────────────────────────────────────────────
    let (rc1, out1) = runHarness(["AKASHIC_POISON_GUARD": target])
    var fails: [String] = []
    if !out1.contains("oracle 前提不成立") || !out1.contains(target) {
        fails.append("沒有具名報出是哪一支守衛的前提不成立")
    }
    if let (got, _) = passCount(out1) {
        let want = cleanOK - nCases
        if got != want {
            fails.append("通過數應從 \(cleanOK) 掉到 \(want)（少掉那 \(nCases) 格），實際 \(got)")
        }
    } else {
        fails.append("毒化後讀不到通過數")
    }
    if rc1 == 0 { fails.append("前提不成立時 harness 仍回 0") }
    for f in fails { print("  ✗ \(f)") }
    if fails.isEmpty {
        print("  ✓ 具名報出、\(nCases) 格全部不計入（\(cleanOK) → \(cleanOK - nCases)）、rc≠0")
    }

    // ── 檢查二 ────────────────────────────────────────────────────────────
    print("")
    print("══ 檢查二：逐守衛的 baseline 驗證 ══")
    let (rc2, out2) = runHarness(["AKASHIC_POISON_BASELINE": "1"])
    var bFails: [String] = []
    // **子命令形式**（#433 Step 5）：harness 的 `guardRel` 已從 `.py` 路徑換成
    // `akashic-guards <sub>`，訊息裡印的也是那個。比對舊路徑會讓這一格靜默失敗。
    let NUMBERS = "akashic-guards measured-numbers-audit"
    if !out2.contains("在**注入之前**就已經紅") || !out2.contains(NUMBERS) {
        bFails.append("沒有具名報出是哪一支守衛的 baseline 就紅了")
    }
    if out2.contains("negative control") {
        bFails.append("髒 baseline 下仍跑完全部 case 並印出通過數——控制組在空轉")
    }
    if rc2 == 0 { bFails.append("baseline 髒掉時 harness 仍回 0") }
    for f in bFails { print("  ✗ \(f)") }
    if bFails.isEmpty { print("  ✓ 髒 baseline 被在跑任何 case 之前攔下、具名、rc≠0") }

    let total = fails.count + bFails.count
    print("")
    print("══ \(total == 0 ? "兩個自檢都會乾淨降級" : "**\(total) 項不符**") ══")
    return total == 0 ? 0 : 1
}
