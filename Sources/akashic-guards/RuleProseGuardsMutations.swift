// `rule-prose-guards` 的 negative control。
//
// **判準是「恰好」第 n 項紅，不是「第 n 項紅」。** 差別是鑑別力：一個注入若同時打紅第
// n 與第 m 項，那麼「第 n 項紅」就分不出「守衛 n 抓到了它」與「守衛 m 抓到了它、而 n
// 只是順帶」——它作為第 n 項的負控就不純。#407 R18 實測：四個宣告第 1 項的注入實際紅
// [1, 2]，因為一個 markdown 連結同時是兩者的正例（可跟隨 ＋ 未揭露取用限制）。
//
// **mutate 的是複製出來的 plugin 樹，出貨的規則檔完全不碰。**
//
// **遷移期兩版都跑並要求逐字一致**（#433）——刪掉 Python 守衛時把 `run` 裡那一半拿掉。
//
// trigger-coverage: reads plugin/rules/*.md

import Foundation

func ruleProseGuardsMutations() -> Int32 {
    let PLUGIN = "\(repoRoot)/plugin"
    let BIN = "\(repoRoot)/.build/debug/akashic-guards"
    let VENUE = "\(repoRoot)/Sources/AkashicCore/Venue.swift"
    let RULE_REL = "rules/assertions-must-be-measured.md"
    let SNAP = (try? String(contentsOfFile: "\(PLUGIN)/\(RULE_REL)", encoding: .utf8)) ?? ""

    func exec(_ argv: [String], cwd: String) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let o = Pipe(), e = Pipe(); p.standardOutput = o; p.standardError = e
        guard (try? p.run()) != nil else { return (127, "spawn 失敗：\(argv[0])") }
        let od = o.fileHandleForReading.readDataToEndOfFile()
        _ = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: od, encoding: .utf8) ?? "")
    }
    // **Python 版已刪除**（#433 Step 5）：遷移期這裡跑兩版並要求逐字一致，Python 是 oracle。
    // 那條路徑在 `.py` 刪掉之後是死的——`no-compat-fallback` 的「退場即刪」。
    func run(_ root: String) -> (Int32, String) {
        var swArgv = [BIN, "rule-prose-guards", "--root", root]
        if FileManager.default.fileExists(atPath: VENUE) { swArgv += ["--venue", VENUE] }
        return exec(swArgv, cwd: PLUGIN)
    }

    /// 複製整個 plugin 樹到 tempdir、換掉規則檔、跑守衛。出貨檔完全不碰。
    func withCopy(_ mutatedRule: String) -> (Int32, String) {
        let tmp = NSTemporaryDirectory() + "prose-mut-" + UUID().uuidString
        let root = tmp + "/plugin"
        try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(atPath: PLUGIN, toPath: root)
        // **`Sources/` 也要複製**（#433 Step 5）：第 6 項數的 mutation 表在
        // `Sources/akashic-guards/MarkerParityMutationsData.swift`（Python 版時它在
        // `plugin/skills/.../marker-parity-mutations.py`，本來就在複製範圍內）。少了它，
        // 那一項走 SKIP 出口回 rc=2，而 harness 的 baseline 要求 rc=0——整支在 baseline
        // 就停住，且訊息說「先修守衛」而守衛沒壞。
        try? FileManager.default.copyItem(atPath: "\(repoRoot)/Sources",
                                          toPath: tmp + "/Sources")
        try? mutatedRule.write(toFile: root + "/" + RULE_REL, atomically: true, encoding: .utf8)
        let r = run(root)
        try? FileManager.default.removeItem(atPath: tmp)
        return r
    }

    var results: [Bool] = []
    func report(_ out: String, _ n: Int, _ desc: String) -> Bool {
        let reds = Set(matches(out, #"(?m)^\[(\d)\] FAIL"#).compactMap {
            Int((out as NSString).substring(with: $0.range(at: 1)))
        })
        if reds == [n] { print("✓ \(desc) → 恰好第 \(n) 項變紅"); return true }
        if reds.isEmpty { print("✗ \(desc) → 第 \(n) 項沒紅 ← 守衛對它是盲的"); return false }
        print("✗ \(desc) → 宣告第 \(n) 項，實際紅 \(pyReprInts(reds.sorted())) ← 注入不是外科手術式的")
        return false
    }
    func append(_ extra: String, _ n: Int, _ desc: String) -> Bool {
        report(withCopy(SNAP + "\n" + extra + "\n").1, n, desc)
    }
    func swap(_ old: String, _ new: String, _ n: Int, _ desc: String) -> Bool {
        let c = SNAP.components(separatedBy: old).count - 1
        if c != 1 { print("✗ 錨點不唯一（\(c) 次）：\(desc)"); exit(1) }
        guard let r = SNAP.range(of: old) else { return false }
        return report(withCopy(SNAP.replacingCharacters(in: r, with: new)).1, n, desc)
    }

    // baseline 必須先全綠——否則「注入後變紅」不代表任何事（R6 finding 11：前一版從不
    // 檢查 baseline、也不看 return code，原守衛整片壞掉時它仍會 exit 0）。
    let (rc0, out0) = run(PLUGIN)
    if rc0 != 0 {
        print(out0)
        print("✗ baseline 不是全綠（rc=\(rc0)）——先修守衛，negative control 在紅的 baseline 上沒有意義")
        return 1
    }
    print("baseline：5/5 ✓")
    print("")

    // **前四格都刻意帶「private／取不到」的揭露詞**——不是為了好看，是為了讓它們只當
    // 第 1 項的正例。不帶的話它們同時觸發第 2 項，於是「第 1 項紅」分不出是誰抓到的。
    results.append(append("見 [那條規則](.claude/rules/identity-is-judged-not-matched.md)（private repo，外部讀者取不到）。",
                          1, "加一個可跟隨的 repo 連結（private repo 的 404 ＝ 假訊號）"))
    results.append(append("見 [那個型別](Sources/AkashicCore/Venue.swift)（private repo，外部讀者取不到）。",
                          1, "加一個指向 Sources/ 的可跟隨連結（前一版的謂詞漏掉這種）"))
    // REPO_ONLY 有**四**個 alternation 分支，而這份負控先前只注入前兩個。它的 docstring
    // 自己記載「手寫兩種形狀、另外兩種一路綠燈」發生過一次——而覆蓋率當時只修了一半。
    results.append(append("見 [那份說明](docs/store-format.md)（private repo，外部讀者取不到）。",
                          1, "加一個指向 docs/*.md 的可跟隨連結（REPO_ONLY 第 3 分支）"))
    results.append(append("見 [那一行](https://github.com/PsychQuant/Akashic-Library/blob/main/README.md)（private repo，取不到）。",
                          1, "加一個 blob/ 深連結（REPO_ONLY 第 4 分支）"))
    results.append(append("判準寫在 `.claude/rules/identity-is-judged-not-matched.md`。",
                          2, "加一句未揭露取用限制的 repo 專屬路徑"))
    // #407 R49：豁免只錨行首時，一條「宣告開頭 ＋ 後面還有別的東西」的行會逃掉揭露檢查
    // 卻不是真宣告。整行錨定之後它必須被擋回來。
    results.append(append("# trigger-coverage: reads plugin/rules/*.md, 順帶碰 .claude/rules/x.md",
                          2, "偽裝成宣告的行（後面還有東西）不得逃掉揭露檢查"))
    results.append(append("本規則採三分法。", 3, "把被打掉兩次的分類法用語加回來"))
    results.append(append("三筆都回傳了 volume／issue。", 4, "把被同段證據否證的假全稱句放回引號外"))
    results.append(swap("實測**六值**", "實測**三值**", 5, "把 VenueType 的數量宣稱改錯"))
    // 只驗數量的謂詞對這一格全綠——R6 finding 27 指名的真缺陷。
    results.append(swap("`periodical`／`conference`／`publisher`／`database`／`socialMedia`／`website`",
                        "`journal`／`conference`／`publisher`／`database`／`socialMedia`／`website`",
                        5, "把值域裡的一個值改成已被更名的舊值"))
    // 第 6 項：把自我量測表裡「會長的數字」改回過期的值。這一格驗的正是 2026-08-22 真實
    // 發生過的事——**這不是零實例守衛**，是已發生的形狀。
    results.append(swap("**46** 格 fixture", "**26** 格 fixture", 6,
                        "把自我量測表的 parity 格數改回過期的 26"))
    results.append(swap("**14/14**", "**11/11**", 6,
                        "把自我量測表的 mutation 數改回過期的 11/11"))
    // 把自我量測表展示的指令換回**原缺陷那一條**（數整個檔案的 case 行 → 印 8）。
    results.append(swap("awk '/^public enum VenueType/{f=1} f&&/^}/{exit} f&&/^    case /{n++} "
                        + "END{print n+0}' Sources/AkashicCore/Venue.swift",
                        "awk '/^    case /{n++} END{print n+0}' Sources/AkashicCore/Venue.swift",
                        5, "把展示的指令換回會算出 8 的原缺陷那一條"))

    // ── 注入 PoC：證明那條執行路徑真的關著 ────────────────────────────────
    // 這一格與其他不同：它不只看守衛紅不紅，還看**副作用有沒有發生**。
    //
    // R7 的守衛把規則檔擷取出的字串交給 shell，旁邊註解寫著「不執行任意擷取到的 shell」
    // ——那句話是假的。跨模型審查做出 PoC：payload 尾端補一個 `echo 6` 讓輸出等於預期值，
    // 守衛報 **5/5 PASS、exit 0**，同時以使用者身分執行了注入的指令。
    //
    // payload 的兩個細節照抄審查者的：排在合法那條**之前**，且該行要含揭露詞，否則會先被
    // 第 2 項擋掉而測不到第 5 項。
    let tmp = NSTemporaryDirectory() + "prose-poc-" + UUID().uuidString
    let root = tmp + "/plugin"
    try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
    try? FileManager.default.copyItem(atPath: PLUGIN, toPath: root)
    let marker = tmp + "/SIDE_EFFECT"
    var lines = SNAP.components(separatedBy: "\n")
    lines.insert("量測（repo 為 private，無存取權者跑不了）："
        + "`awk 'BEGIN{print 6}' /dev/null; touch \(marker); : Sources/AkashicCore/Venue.swift`",
        at: 1)
    try? lines.joined(separator: "\n").write(toFile: root + "/" + RULE_REL, atomically: true, encoding: .utf8)
    let (rcP, outP) = run(root)
    let executed = FileManager.default.fileExists(atPath: marker)
    let red = !matches(outP, #"(?m)^\[5\] FAIL"#).isEmpty
    let pocOK = !executed && red
    print("\(pocOK ? "✓" : "✗") 注入 PoC → 副作用=\(executed ? "True" : "False")（必須 False）、"
        + "第 5 項\(red ? "變紅" : "沒紅")、exit=\(rcP)")
    try? FileManager.default.removeItem(atPath: tmp)
    results.append(pocOK)

    print("")
    print("=== negative control \(results.filter { $0 }.count)/\(results.count) ===")
    print("出貨檔未被開啟以寫入：\(RULE_REL)")
    return results.allSatisfy { $0 } ? 0 : 1
}

/// Python `sorted(set_of_int)` 印出來的 `[1, 2]` 形式。
private func pyReprInts(_ xs: [Int]) -> String {
    "[" + xs.map(String.init).joined(separator: ", ") + "]"
}
