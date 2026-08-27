// `trigger-coverage` 的 negative control——它真的會在觸發點被拆掉時變紅嗎？
//
// **32 個 mutation 的字串在 `TriggerCoverageMutationsData.swift`，機械抽出不手抄**（#433）。
//
// **遷移期兩版都跑並要求逐字一致**——刪掉 Python 守衛時把 `run` 裡那一半拿掉。
//
// **刻意不寫 `trigger-coverage: reads` 宣告**：宣告存在的理由是補啟發式的漏（守衛用 glob
// 組路徑、basename 不逐字出現）。這支的依賴 `plugin/tests/trigger-coverage.py` 在 source
// 裡逐字出現，啟發式看得到。第一版寫了 `reads .githooks/run-guards.sh` 而**那不在
// PROTECTED 裡**（它不是守衛也不在 DATA），於是守衛報「宣告解析不到任何受保護檔——
// 它等於沒寫」——那條檢查在它被寫下的當天就抓到了我。

import Foundation

func triggerCoverageMutations() -> Int32 {
    // **守衛要跑 copy 裡的那份，不是原始路徑**——兩個 case 注入的正是守衛自己的原始碼，
    // 跑原始路徑等於那兩格完全沒生效（而輸出看起來只是「守衛沒指名」）。差分測試抓到
    // 這個：Python 版用 `os.path.join(root, GUARD_REL)`，我第一版寫成 repoRoot。
    let GUARD_REL = "plugin/tests/trigger-coverage.py"
    let BIN = "\(repoRoot)/.build/debug/akashic-guards"
    var sourceInjected: [String] = []

    func exec(_ argv: [String], cwd: String) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let o = Pipe(), e = Pipe(); p.standardOutput = o; p.standardError = e
        guard (try? p.run()) != nil else { return (127, "spawn 失敗") }
        let od = o.fileHandleForReading.readDataToEndOfFile()
        _ = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: od, encoding: .utf8) ?? "")
    }
    func run(_ root: String, sourceInjection: Bool = false) -> (Int32, String) {
        let py = exec(["/usr/bin/python3", root + "/" + GUARD_REL, "--root", root], cwd: root)
        // **注入守衛自己的原始碼時不比對**：Swift 的等價程式碼在 compiled binary 裡，改
        // `.py` 對它**結構上**無效——比對必然分岔，而分岔與守衛的正確性無關。代價在總結
        // 彙總印出，不靜默。
        if sourceInjection {
            sourceInjected.append(GUARD_REL)
            return py
        }
        if FileManager.default.isExecutableFile(atPath: BIN) {
            let sw = exec([BIN, "trigger-coverage"], cwd: root)
            if sw != py {
                print("✗ 遷移期兩版分岔：trigger-coverage.py vs `akashic-guards trigger-coverage`")
                print("  ── python rc=\(py.0)\n\(py.1)")
                print("  ── swift  rc=\(sw.0)\n\(sw.1)")
                exit(1)
            }
            return sw
        }
        return py
    }

    /// 複製相關子樹、套用 edits、跑守衛。
    ///
    /// **`.claude` 只複製 `rules/`**（#433）：整個 `.claude` 是 2.0 GB／25,519 個檔，其中
    /// `.claude/worktrees/` 佔 2.0 GB（IDD 的隔離工作樹）；守衛要的只有規則檔（144 KB；
    /// private repo，外部讀者取不到）。**但那個目錄非複製不可**——
    /// `measured-numbers-audit` 宣告它讀 `.claude/rules/*.md` 而那些檔在 PROTECTED 裡，
    /// 沒複製的話 temp 樹裡那條宣告解析不到，**每一個 case 都多報一條與注入無關的缺口**。
    func withCopy(_ edits: [(path: String, old: String, new: String)]) -> (Int32, String)? {
        let tmp = NSTemporaryDirectory() + "trig-mut-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        for sub in ["plugin", ".github", ".githooks", "Sources"] {
            let s = "\(repoRoot)/\(sub)"
            if FileManager.default.fileExists(atPath: s) {
                try? FileManager.default.copyItem(atPath: s, toPath: tmp + "/" + sub)
            }
        }
        let rulesSrc = "\(repoRoot)/.claude/rules"
        if FileManager.default.fileExists(atPath: rulesSrc) {
            try? FileManager.default.createDirectory(atPath: tmp + "/.claude", withIntermediateDirectories: true)
            try? FileManager.default.copyItem(atPath: rulesSrc, toPath: tmp + "/.claude/rules")
        }
        // **根目錄的受保護檔也要複製。** 它們不是子樹，上面那個迴圈看不到——漏掉時守衛在
        // temp 樹裡找不到 DATA 的成員，於是**每一個** case 都因為同一個與注入無關的理由
        // 變紅（#407 R27 當場踩到：加了 `CLAUDE.md` 進 DATA 之後 14/14 全紅）。
        for f in ["CLAUDE.md"] {
            let s = "\(repoRoot)/\(f)"
            if FileManager.default.fileExists(atPath: s) {
                try? FileManager.default.copyItem(atPath: s, toPath: tmp + "/" + f)
            }
        }
        for e in edits {
            let p = tmp + "/" + e.path
            guard let t = try? String(contentsOfFile: p, encoding: .utf8) else { return nil }
            guard let r = t.range(of: e.old) else { return nil }   // 注入沒改到 → case 無效
            try? t.replacingCharacters(in: r, with: e.new).write(toFile: p, atomically: true, encoding: .utf8)
        }
        return run(tmp, sourceInjection: edits.contains { $0.path == GUARD_REL })
    }

    let (baseRC, baseOut) = run(repoRoot)
    if baseRC != 0 {
        print("✗ baseline 不是全綠（rc=\(baseRC)）——負控在紅的 baseline 上沒有意義\n\(baseOut)")
        return 1
    }
    print("baseline：無缺口 ✓\n")

    var results: [Bool] = []
    for c in triggerCoverageMutationCases {
        guard let (rc, out) = withCopy(c.edits) else {
            print("✗ \(c.desc) → **注入沒改到東西**，這個 case 無效"); results.append(false); continue
        }
        let gaps = matches(out, #"(?m)^  · (.+)$"#).map { (out as NSString).substring(with: $0.range(at: 1)) }
        if c.isWarn {
            // **綁定到被 mutate 的那個守衛**（#407 R24e）：上一版只問「輸出裡有沒有
            // expect」——那與「哪一個守衛觸發的」無關。警告訊息的模板對每個守衛都一樣。
            //
            // **單檔才綁得住**（#407 R24h）：多個 key 時「某個被 edit 的檔名」會變成聯集，
            // A 的警告消失而 B 恰好有一條文字相符的既有警告時仍會綠。資料檔實測全是單檔。
            if c.edits.count != 1 {
                print("✗ warn_case 目前只支援單檔 edits（收到 \(c.edits.count) 個）——綁定會退化成聯集")
                return 1
            }
            let warns = matches(out, #"(?m)^  \? (.+)$"#).map { (out as NSString).substring(with: $0.range(at: 1)) }
            let targets = c.edits.map { base($0.path) }
            let named = warns.filter { w in w.contains(c.expect) && targets.contains(where: { w.contains($0) }) }
            let stray = warns.filter { !named.contains($0) }
            // 三段判準，與 case 對齊（#407 R24b）：(1) rc **必須是 0**——警告不改變 exit
            // code，那正是「降為 warning」的意思；(2) 指名的警告出現；(3) 鑑別力：不得有
            // 無關的警告，也不得有任何缺口（有缺口就不是純警告情境）。
            let ok = rc == 0 && !named.isEmpty && stray.isEmpty && gaps.isEmpty
            if ok { print("✓ \(c.desc) → 警告出現（rc=0，警告 \(warns.count) 條全屬同類）") }
            else if rc != 0 { print("✗ \(c.desc) → rc=\(rc) ← 警告不該改變 exit code；缺口：\(pyRepr(Array(gaps.prefix(2))))") }
            else if named.isEmpty { print("✗ \(c.desc) → 警告沒出現 ← 檢查對它是盲的") }
            else { print("✗ \(c.desc) → 另有 \(stray.count) 條無關警告 ← 注入不是外科手術式的") }
            results.append(ok)
        } else {
            // 三段判準，第三段是 #407 R20d 補的：前兩段（守衛變紅、訊息指名了它）不足以說
            // 這格**鑑別**了它具名的缺陷——一個注入若順帶打壞別的東西，紅的原因就分不出來。
            // 姊妹 harness 在 R18b 已經吃過這個虧（四格宣告「第 1 項」的注入實際紅 [1, 2]）。
            let hit = out.contains(c.expect)
            let stray = gaps.filter { !$0.contains(c.expect) }
            let ok = rc != 0 && hit && stray.isEmpty
            if ok {
                print("✓ \(c.desc) → rc=\(rc)，指名了它"
                    + (gaps.isEmpty ? "" : "（缺口 \(gaps.count) 條全屬同類）"))
            } else if !hit {
                print("✗ \(c.desc) → rc=\(rc)，但沒指名 ← 訊息對它是盲的")
            } else if !stray.isEmpty {
                print("✗ \(c.desc) → rc=\(rc)，但另有 \(stray.count) 條無關缺口 "
                    + "← 注入不是外科手術式的：\(pyRepr(Array(stray.prefix(2))))")
            } else {
                print("✗ \(c.desc) → rc=\(rc)")
            }
            results.append(ok)
        }
    }
    if !sourceInjected.isEmpty {
        // **不靜默**（`lossless-intake` 執行細節 3）：這些 case 的 Swift 側沒有負控，
        // 而輸出若不說，它與「兩版都驗過了」長得一模一樣。
        print("ℹ \(sourceInjected.count) 個 case 注入的是守衛**自己的原始碼**——Swift 版的"
            + "等價程式碼在 compiled binary 裡，改 .py 對它無效，所以這些 case "
            + "**只驗了 Python 版**。")
    }
    print("\n=== negative control \(results.filter { $0 }.count)/\(results.count) ===")
    print("出貨檔未被開啟以寫入：\(GUARD_REL)")
    return results.allSatisfy { $0 } ? 0 : 1
}
