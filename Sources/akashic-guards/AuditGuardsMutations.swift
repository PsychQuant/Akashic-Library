// 守衛群的 negative control——每一支真的會在它宣稱的缺陷出現時變紅嗎？
//
// **判準三段**：(1) rc≠0、(2) 訊息指名了它、(3) `ROBUST` 那一組反過來——注入純重排時
// **維持綠且輸出與未注入逐字相同**。
//
// **52 個 case 的字串在 `AuditGuardsMutationsData.swift`，機械抽出不手抄**（#433）。
//
// trigger-coverage: reads plugin/rules/*.md

import Foundation

// ── 八個特殊 edit（資料化不了的那些）────────────────────────────────────
// 其餘 44 個是 `replace`、2 個是 `delete`，都在資料檔裡。

/// 第一個非註解非空行：把首 token 的末字元換成 `F`（尾隨空白改不了語意，所以不用它）。
private func perturbTable(_ t: String) -> String {
    var lines = t.components(separatedBy: "\n")
    for (i, l) in lines.enumerated() {
        let s = l.trimmingCharacters(in: .whitespaces)
        if s.isEmpty || l.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("#") { continue }
        guard let first = l.split(separator: " ", omittingEmptySubsequences: true).first else { break }
        let repl = String(first.dropLast()) + "F"
        if let r = l.range(of: String(first)) { lines[i] = l.replacingCharacters(in: r, with: repl) }
        break
    }
    return lines.joined(separator: "\n")
}

/// 第一個 `0x` 起算 6 個字元換成 `0xFFFE`。
private func perturbRanges(_ t: String) -> String {
    guard let r = t.range(of: "0x") else { return t }
    let start = t.distance(from: t.startIndex, to: r.lowerBound)
    let end = t.index(t.startIndex, offsetBy: min(start + 6, t.count))
    return String(t[t.startIndex..<r.lowerBound]) + "0xFFFE" + String(t[end...])
}

/// **刻意不寫死列數**（#414）：先前三個 case 各自寫死 `現有 6 列` 當字面錨，而那是規則檔
/// 那個數字的**第二份副本**——規則檔加一列（6 → 7）時三個 case 同時失效，且失效的方式是
/// 「注入沒有造成任何改動」。綁**標題的結構**而非它此刻的內容。
private func ziVerdictHeading(_ new: String, _ text: String) -> String {
    let pat = #"(?m)^## 裁決史（封閉列舉——現有 \S+ 列，一列不多一列不少）$"#
    guard let m = matches(text, pat).first else { return text }
    return (text as NSString).replacingCharacters(in: m.range, with: new)
}

/// 把 `CreateEntryCmd` 裡巢狀的 `EntryDraft` 搬到 `configuration` **之前**——一次**純重排**
/// （Swift 語意不變），測稽核程序的抽取邊界。上一版的邊界（到下一個 `struct ` 為止）在這個
/// 排列下會抽不到 `commandName` 而回 nil——訊息會去怪稽核程序自己。
private func moveNestedStruct(_ src: String) -> String {
    guard let m = matches(src, #"(?s)    struct EntryDraft \{.*?\n    \}\n"#).first else { return src }
    let block = (src as NSString).substring(with: m.range)
    var out = src.replacingOccurrences(of: block, with: "")
    if let r = out.range(of: "struct CreateEntryCmd: ParsableCommand {") {
        out = out.replacingCharacters(in: r, with: "struct CreateEntryCmd: ParsableCommand {\n" + block)
    }
    return out
}

private func applyEdit(_ e: AGMEdit, _ text: String) -> String? {
    switch e.kind {
    // **兩種 replace 的範圍不同**：Python 的 `str.replace(old, new)` 換掉全部，帶 `count=1`
    // 才換第一個。混為一談會讓 5 個 case 靜默換錯範圍（實測其中一個直接讓守衛不紅）。
    // **找不到就回原文，不是 nil**——Python 的 `str.replace` 找不到時回原字串，而整體
    // 「有沒有改到東西」由呼叫端在**所有 edit 套完之後**判斷。回 nil 會讓鏈式裡的 no-op
    // 環節誤報「這個 case 無效」。
    case "replaceAll":
        return text.replacingOccurrences(of: e.a, with: e.b)
    case "replaceFirst":
        guard let r = text.range(of: e.a) else { return text }
        return text.replacingCharacters(in: r, with: e.b)
    case "perturbTable":         return perturbTable(text)
    case "perturbRanges":        return perturbRanges(text)
    case "prependAsciiRange":    return "41 41\n" + text  // display-safe-exempt: 這是 edit 的回傳值（寫進 temp copy 的檔案），不是使用者可見輸出
    case "removeTableSeparator":
        return text.replacingOccurrences(of: #"(?m)^\|[-\s|:]+\|\s*$"#,
                                         with: "（表分隔線已移除）", options: .regularExpression)
    case "ziVerdictHeading":     return ziVerdictHeading(e.a, text)
    case "moveNestedStruct":     return moveNestedStruct(text)
    default: return nil
    }
}

func auditGuardsMutations() -> Int32 {
    let BIN = "\(repoRoot)/.build/debug/akashic-guards"
    let fm = FileManager.default
    var sourceInjected: [String] = []
    var poisonCounter = 0          // 見 `AKASHIC_POISON_GUARD`
    var abort: String? = nil          // 取代 Python 的 SystemExit（case 無效時具名並跳過）

    func exec(_ argv: [String], cwd: String) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let o = Pipe(), e = Pipe(); p.standardOutput = o; p.standardError = e
        guard (try? p.run()) != nil else { return (127, "spawn 失敗：\(argv[0])") }
        let od = o.fileHandleForReading.readDataToEndOfFile()
        let ed = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus,
                (String(data: od, encoding: .utf8) ?? "") + (String(data: ed, encoding: .utf8) ?? ""))
    }

    /// 複製相關子樹、套用 edits、跑 copy 裡的那支守衛。
    ///
    /// **`.claude` 只複製 `rules/`**：整個 `.claude` 是 2.0 GB／25,519 個檔（`worktrees/`
    /// 佔 2.0 GB），而守衛讀的只有規則檔（144 KB；private repo，外部讀者取不到）。全樹複製
    /// 16.5 秒一次 × 每個 case，讓這支 harness 曾漲到 13 分鐘以上。
    func withCopy(_ guardRel: String, _ edits: [AGMEdit]) -> (Int32, String) {
        let tmp = NSTemporaryDirectory() + "audit-mut-" + UUID().uuidString
        try? fm.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmp) }
        for sub in ["plugin", ".github", "Sources", ".githooks"] {
            try? fm.copyItem(atPath: "\(repoRoot)/\(sub)", toPath: tmp + "/" + sub)
        }
        try? fm.createDirectory(atPath: tmp + "/.claude", withIntermediateDirectories: true)
        try? fm.copyItem(atPath: "\(repoRoot)/.claude/rules", toPath: tmp + "/.claude/rules")
        // **CLAUDE.md 是檔案不是目錄**，不在上面那個迴圈裡（#407 R67g）——少了它，針對
        // `measured-numbers-audit` 的注入會以「檔案不存在」失敗，那是與注入無關的紅。
        try? fm.copyItem(atPath: "\(repoRoot)/CLAUDE.md", toPath: tmp + "/CLAUDE.md")

        // **同一個 path 的多個 edit 依序套用，套完才檢查「有沒有改到東西」。**
        //
        // Python 的 `edits` 是 `{path: fn}`，而 `fn` 可以是鏈式的
        // `t.replace(A,B).replace(C,D)`——它只檢查 `fn(before) != before`，也就是**整體**的
        // 結果。抽取時鏈式被展開成多個 `AGMEdit`，若逐步檢查，一個 no-op 的環節（實際存在：
        // 有一格的 `a == b`）就會誤報「這個 case 無效」而整格消失。
        var byPath: [String: [AGMEdit]] = [:]
        var order: [String] = []
        for e in edits {
            if byPath[e.path] == nil { order.append(e.path) }
            byPath[e.path, default: []].append(e)
        }
        for path in order {
            let group = byPath[path]!
            let p = tmp + "/" + path
            // **`delete` ＝ 把它整個搬走**：用來測「輸入來源歸零」，而不是改守衛**自己的
            // 原始碼**去指向錯的路徑——後者只對直譯語言有效，改 `.py` 對 binary 結構上無效。
            if group.contains(where: { $0.kind == "delete" }) {
                guard fm.fileExists(atPath: p) else {
                    abort = "✗ 注入要搬走 \(path) 但它不存在——這個 case 無效"; return (0, "")
                }
                try? fm.removeItem(atPath: p); continue
            }
            guard let before = try? String(contentsOfFile: p, encoding: .utf8) else {
                abort = "✗ 注入讀不到 \(path)——這個 case 無效"; return (0, "")
            }
            var after = before
            for e in group {
                guard let next = applyEdit(e, after) else {
                    abort = "✗ 注入對 \(path) 沒有造成任何改動——這個 case 無效"; return (0, "")
                }
                after = next
            }
            guard after != before else {
                abort = "✗ 注入對 \(path) 沒有造成任何改動——這個 case 無效"; return (0, "")
            }
            try? after.write(toFile: p, atomically: true, encoding: .utf8)
        }
        // 守衛只讀 git **歷史**，所以把 `.git` symlink 回真 repo 是安全的；沒有它，
        // `measured-claims-audit` 會因為「這裡不是 repo」而紅——與注入無關的紅等於沒有負控。
        try? fm.createSymbolicLink(atPath: tmp + "/.git", withDestinationPath: "\(repoRoot)/.git")

        // **Swift-only 守衛**：`migrated-guard-control` 沒有 Python 原版，`guardRel` 直接
        // 寫成 `akashic-guards <子命令>`，不走 interpreter 那條路。
        if guardRel.hasPrefix("akashic-guards ") {
            let sub = guardRel.split(separator: " ")[1]
            guard fm.isExecutableFile(atPath: BIN) else { return (2, "（\(BIN) 不存在——本 case 未執行）") }
            return exec([BIN, String(sub)], cwd: tmp)
        }
        let interp: String
        switch (guardRel as NSString).pathExtension {
        case "py": interp = "/usr/bin/python3"
        case "sh": interp = "/bin/bash"
        default:   interp = "/usr/bin/env"        // swift
        }
        let argv = interp == "/usr/bin/env" ? ["/usr/bin/env", "swift", tmp + "/" + guardRel]
                                            : [interp, tmp + "/" + guardRel]
        let r = exec(argv, cwd: tmp)
        var sub = agmMigrated.first(where: { $0.py == guardRel })?.sub
        // **注入守衛自己的原始碼時不做兩版比對**：Swift 的等價程式碼在 compiled binary 裡，
        // 改 `.py` 結構上無效——比對必然分岔而分岔與正確性無關。判準是結構的（edits 動到
        // `guardRel` 自己），不是名單。代價在總結彙總印出，不靜默。
        if sub != nil && edits.contains(where: { $0.path == guardRel }) {
            sourceInjected.append(guardRel); sub = nil
        }
        if let s = sub, fm.isExecutableFile(atPath: BIN) {
            let rs = exec([BIN, s], cwd: tmp)
            if rs != r {
                print("✗ 遷移期兩版分岔：\(guardRel) vs `akashic-guards \(s)`")
                print("  ── python rc=\(r.0)\n\(r.1)")
                print("  ── swift  rc=\(rs.0)\n\(rs.1)")
                exit(1)
            }
            return rs        // 回傳**實際在跑的**那一版
        }
        return r
    }
    /// **`AKASHIC_POISON_GUARD` — oracle-precondition-control 的注入點**（#433）。
    ///
    /// Python 版靠 monkey-patch `mod.with_copy`；Swift 沒有那個機制。用「可注入的 withCopy
    /// 參數」是更直接的對應，但 `main()` 的輸出要被捕捉，那就得把所有 `print` 改成可注入的
    /// sink——一次波及整支的重構，換到的東西與 subprocess 相同。而 subprocess 另有一個好處：
    /// **它跑的是真的出貨路徑**，與使用者跑 `akashic-guards audit-guards-mutations` 完全一樣。
    ///
    /// **它必須在未設定時完全沒有行為**——否則就是一個藏在出貨路徑裡的後門。
    func poisonedIfRequested(_ guardRel: String, _ edits: [AGMEdit]) -> (Int32, String) {
        let env = ProcessInfo.processInfo.environment
        // **檢查二的注入**：把 `measured-numbers-audit` 的 baseline 弄髒（規則檔多一個裸
        // 數字），harness 必須在跑任何 case **之前**攔下並具名。
        if env["AKASHIC_POISON_BASELINE"] != nil,
           guardRel == "akashic-guards measured-numbers-audit" {
            var e = edits
            e.append(AGMEdit(path: ".claude/rules/lossless-intake.md", kind: "replaceFirst",
                             a: "## 規則", b: "## 破壞 baseline\n\n實測 42 筆。\n\n## 規則"))
            return withCopy(guardRel, e)
        }
        if let poison = env["AKASHIC_POISON_GUARD"],
           poison == guardRel, edits.isEmpty {
            // **非決定性注入在 harness 層，不在守衛裡**（#433 Step 5）。
            //
            // Python 版把 `print(os.getpid())` 注進守衛的 `.py`——遷移之後守衛是 compiled
            // binary，那條路**結構上不通**。而 oracle 要測的性質是「harness 對**非決定性
            // 輸出**的降級」，輸出從哪來不影響那個性質，所以改在這裡附加一個每次都不同的
            // 值。遞增計數器而非 pid：pid 是 harness 自己的，同一個 process 內每次相同。
            poisonCounter += 1
            let r = withCopy(guardRel, [])
            return (r.0, r.1 + "\n\(poisonCounter)")
        }
        return withCopy(guardRel, edits)
    }
    let run = poisonedIfRequested

    // ── 主流程 ───────────────────────────────────────────────────────────
    var paired: [String: String] = [:]
    var byOutput: [String: [String]] = [:]          // key = guard + "\u{1F}" + out
    func mtimes() -> [String: Double] {
        var m: [String: Double] = [:]
        for r in agmWatched {
            let a = (try? fm.attributesOfItem(atPath: "\(repoRoot)/\(r)")) ?? [:]
            m[r] = (a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
        }
        return m
    }
    let before = mtimes()
    let hasSwift = exec(["/usr/bin/which", "swift"], cwd: repoRoot).0 == 0
    if !fm.isExecutableFile(atPath: BIN) {
        print("ℹ \(BIN) 不存在——`MIGRATED` 的 \(agmMigrated.count) 支只驗 Python 版，"
            + "實際在 run-guards.sh 跑的 Swift 版**在這台機器上沒有負控**。"
            + "先跑 `swift build --product akashic-guards`。")
    }
    let COVERAGE = "plugin/tests/rule-coverage.sh"
    let DRIFT = "plugin/skills/akashic-promote-literals/scripts/tests/hash-table-drift.sh"
    for rel in [COVERAGE] + (hasSwift ? [DRIFT] : []) {
        let r = exec(["/bin/bash", "\(repoRoot)/\(rel)"], cwd: repoRoot)
        if r.0 != 0 { print("✗ baseline 就紅了：\(rel)\n\(r.1)"); return 1 }
    }
    // **每一支被當成受測對象的守衛都要驗 baseline**（#407 R67j）：上一版只驗這兩支，於是
    // 其餘守衛若在注入**之前**就已經紅，它們的控制組會平白通過——控制組宣稱「注入造成了
    // 紅」，而紅早就在那裡。
    // **`AKASHIC_SKIP_CASES`**：只跑 ROBUST（對應 Python 版的 `mod.CASES = []`）——
    // oracle 要驗的是 ROBUST oracle 的降級，跑 45 個 CASES 只是浪費。
    let cases = ProcessInfo.processInfo.environment["AKASHIC_SKIP_CASES"] != nil ? [] : agmCases
    var tested = Array(Set((cases + agmRobust).map { $0.guardRel })).sorted()
    if !hasSwift { tested = tested.filter { !$0.hasSuffix(".swift") && $0 != DRIFT } }
    var dirty: [(String, String)] = []
    for rel in tested {
        abort = nil
        let (rc, out) = run(rel, [])
        if rc != 0 { dirty.append((rel, out)) }
    }
    if !dirty.isEmpty {
        print("✗ \(dirty.count) 支守衛在**注入之前**就已經紅——它們的控制組會平白通過：")
        for (rel, out) in dirty {
            let s = (out.isEmpty ? "（無輸出）" : out).trimmingCharacters(in: .whitespacesAndNewlines)
            print("  · \(rel)\n    " + String(s.replacingOccurrences(of: "\n", with: "\n    ").prefix(300)))
        }
        return 1
    }
    print("baseline：\(tested.count) 支皆綠 ✓（\(cases.count) 個 mutation 待跑）\n")
    sourceInjected.removeAll()      // baseline 階段的計數不算——那裡 edits 是空的

    // **缺 swift 時大聲跳過，不假裝乾淨**（#407 R42）：`lossless-intake` 的「靜默是最糟的形式」。
    var skipped: [String] = []
    if !hasSwift {
        skipped = cases.filter { $0.guardRel.hasSuffix(".swift") || $0.guardRel == DRIFT }.map { $0.desc }
        print("⚠ 此環境沒有 swift——跳過 \(skipped.count) 個需要 Swift toolchain 的 case：")
        for n in skipped { print("    · \(n)") }
        print("  （其餘 case 照跑。「跳過」不等於「檢查過且乾淨」。）\n")
    }

    let pairedFlat = Set(agmPairedIdentical.flatMap { $0 })
    var ok = 0
    for c in cases {
        if skipped.contains(c.desc) { continue }
        abort = nil
        let (rc, out) = run(c.guardRel, c.edits)
        if let a = abort { print(a); continue }
        let miss = c.expect.filter { !out.contains($0) }
        if pairedFlat.contains(c.desc) { paired[c.desc] = out }
        byOutput[c.guardRel + "\u{1F}" + out, default: []].append(c.desc)
        if rc != 0 && miss.isEmpty {
            print("✓ 注入「\(c.desc)」→ rc=\(rc)，具名"); ok += 1
        } else {
            print("✗ 注入「\(c.desc)」→ rc=\(rc)" + (miss.isEmpty ? "" : "，缺 \(pyRepr(miss))"))
            print("   " + String((out.isEmpty ? "（無輸出）" : out)
                .replacingOccurrences(of: "\n", with: "\n   ").prefix(500)))
        }
    }

    // **輸出逐字相同的 case 互相不可區分**（#407 R67c）：重複**看起來像多一份覆蓋**——
    // 計數多一個 ✓，維護者讀成「又多檢查了一件事」，其實是同一件事查了兩次。
    let declared = agmPairedIdentical.map { Set($0) }
    let undeclared = byOutput.values.filter { $0.count > 1 && !declared.contains(Set($0)) }
    if !undeclared.isEmpty {
        print("✗ \(undeclared.count) 組 case 的輸出逐字相同卻未具名為刻意的一對：")
        for names in undeclared {
            for x in names { print("      · \(x)") }
            print("    （若是刻意的，加進 PAIRED_IDENTICAL 並寫下為什麼相同）")
        }
    } else {
        print("✓ 無未具名的重複 case（輸出逐字相同者只有已具名的那一對）"); ok += 1
    }

    // **理由欄的提及不得改變任何事**：每一組的輸出必須逐字相同，而那個相同本身就是被斷言
    // 的性質——字串斷言做不到這件事。
    var invOK = true
    for pair in agmPairedIdentical {
        let (a, b) = (pair[0], pair[1])
        if paired[a] == nil || paired[b] == nil {
            print("✗ 不變式：這一組只收到部分輸出（case 被改名或跳過？）\n   \(a)\n   \(b)")
            invOK = false
        } else if paired[a] != paired[b] {
            print("✗ 不變式：這一組的輸出分岔了——被斷言為「不得改變任何事」"
                + "的那個加法改變了守衛輸出\n   \(a)\n   \(b)")
            invOK = false
        }
    }
    if invOK { print("✓ 不變式：\(agmPairedIdentical.count) 組刻意相同的 case 輸出各自逐字一致"); ok += 1 }

    // ── ROBUST：注入純重排，必須**維持綠且輸出與未注入逐字相同** ──────────
    // 這個 oracle 的前提是**輸出決定性**——假紅會讓人開始不相信所有紅燈，所以前提自己要被檢查。
    var pristine: [String: String] = [:]
    var nondeterministic = Set<String>()
    for c in agmRobust {
        if pristine[c.guardRel] == nil && !nondeterministic.contains(c.guardRel) {
            abort = nil
            let first = run(c.guardRel, []).1
            abort = nil
            let second = run(c.guardRel, []).1
            if first != second {
                let fl = Set(first.components(separatedBy: "\n"))
                let diff = second.components(separatedBy: "\n").filter { !fl.contains($0) }
                print("✗ oracle 前提不成立：\(c.guardRel) 的未注入輸出兩次不同"
                    + "——逐字比對會偶發假紅\n   第二次獨有：\(pyRepr(Array(diff.prefix(3))))")
                nondeterministic.insert(c.guardRel); continue
            }
            pristine[c.guardRel] = first
        }
        abort = nil
        let (rc, out) = run(c.guardRel, c.edits)
        if let a = abort { print(a); continue }
        guard let pri = pristine[c.guardRel] else { continue }   // 前提不成立時不假裝通過
        let miss = c.expect.filter { !out.contains($0) }
        let drift = out != pri
        if rc == 0 && miss.isEmpty && !drift {
            print("✓ 重排注入「\(c.desc)」→ 維持綠，且輸出與未注入逐字相同"); ok += 1
        } else {
            print("✗ 重排注入「\(c.desc)」→ rc=\(rc)"
                + (miss.isEmpty ? "" : "，缺 \(pyRepr(miss))")
                + (drift ? "，輸出與未注入不同" : ""))
        }
    }

    let same = before == mtimes()
    let expected = cases.count - skipped.count + agmRobust.count + 2   // +2 = 不變式、重複掃描
    if !sourceInjected.isEmpty {
        let uniq = Array(Set(sourceInjected.map { base($0) })).sorted()
        print("ℹ \(sourceInjected.count) 個 case 注入的是守衛**自己的原始碼**"
            + "（\(uniq.joined(separator: "、"))）——Swift 版的等價程式碼在 compiled binary 裡，"
            + "改 .py 對它無效，所以這些 case **只驗了 Python 版**。"
            + "能改成環境注入的就該改（見注入處的說明）。")
    }
    print("\n=== negative control \(ok)/\(expected) "
        + "（\(cases.count - skipped.count) 須紅 ＋ \(agmRobust.count) 須綠 ＋ 2 後設檢查）==="
        + (skipped.isEmpty ? "" : "（另有 \(skipped.count) 個因缺 swift 跳過）"))
    print("\(same ? "出貨檔未被開啟以寫入" : "**出貨檔被動到了**")：\(agmWatched.count) 個受監看檔")
    if ok != expected || !same { return 1 }
    return skipped.isEmpty ? 0 : 2
}
