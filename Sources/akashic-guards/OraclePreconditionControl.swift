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
// 它是 `audit-guards-mutations` 這支 harness 的負控：函式開頭在執行時宣告（`declareNegativeControl`，#707），
// `migrated-guard-control` 讀執行紀錄裡的那一筆與下面兩個檢查讓 harness 變紅的那兩次執行。
//
// **刻意不寫 `trigger-coverage: reads` 宣告**（#433 Step 5）：宣告存在的理由是補啟發式
// 的漏（守衛用 glob 組路徑、basename 不逐字出現）。這支讀的是同目錄的 harness source，
// 啟發式看得到——而指向自己所在目錄的宣告會被守衛判成「多半多餘」的警告。

import Foundation

func oraclePreconditionControl() -> Int32 {
    declareNegativeControl(for: ["audit-guards-mutations"])
    let BIN = "\(repoRoot)/.build/debug/akashic-guards"

    /// 跑 harness 自己（真的出貨路徑），帶指定的注入環境變數。
    /// 經 `runGuardProcess` 執行（#707）：它留下執行紀錄。被執行的 harness 拿不到紀錄的環境變數，所以它自己
    /// 在毒化下跑的那些守衛不會進紀錄——只有「本支讓它變紅」這一次會。
    func runHarness(_ extraEnv: [String: String], _ label: String, _ expect: GuardExpectation) -> (Int32, String) {
        var env = extraEnv
        env["AKASHIC_SKIP_CASES"] = "1"          // 只跑 ROBUST——CASES 與本控制組無關
        let r = runGuardProcess([BIN, "audit-guards-mutations"], cwd: repoRoot, env: env,
                                label: label, expect: expect)
        return (r.status, r.stdout)
    }
    func passCount(_ out: String) -> (Int, Int)? {
        guard let m = matches(out, #"negative control (\d+)/(\d+)"#).first else { return nil }
        let ns = out as NSString
        return (Int(ns.substring(with: m.range(at: 1))) ?? -1, Int(ns.substring(with: m.range(at: 2))) ?? -1)
    }

    // （#629：先前這裡依「有沒有 swift toolchain」過濾掉 `.swift` 腳本與 `hash-table-drift.sh` 的 ROBUST case。
    //  那兩類守衛都已退場，所有 ROBUST 守衛都是編譯好的子命令，不需要過濾。）
    var counts: [String: Int] = [:]
    for c in agmRobust { counts[c.guardRel, default: 0] += 1 }
    guard !counts.isEmpty else {
        print("✗ 沒有任何可毒化的 ROBUST 守衛——本控制組退化成空的。")
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
    // 預期寫 `.none` 而不是 `.green`：這一次只讀通過數。`AKASHIC_SKIP_CASES` 下 harness 的後設檢查收不到那一對
    // 刻意相同的 case，rc 本來就是 1——#707 的執行紀錄第一次跑就把「預期綠、實際 rc=1」報了出來。
    let clean = runHarness([:], "未毒化（只讀通過數）", .none)
    guard let (cleanOK, _) = passCount(clean.1) else {
        print("✗ 讀不到未毒化時的通過數——harness 的輸出格式變了")
        return 1
    }

    // ── 檢查一 ────────────────────────────────────────────────────────────
    let (rc1, out1) = runHarness(["AKASHIC_POISON_GUARD": target], "檢查一：毒化 \(target) 的 oracle 前提", .red)
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
    let (rc2, out2) = runHarness(["AKASHIC_POISON_BASELINE": "1"], "檢查二：弄髒 baseline", .red)
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
