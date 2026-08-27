// `decision-matrix-drift` 的 negative control。
//
// 一個沒紅過的檢查，與一個不存在的檢查，在輸出上完全一樣。本支逐一注入缺陷，要求守衛
// **(1) rc=1、(2) 具名到那一列或那個症狀、(3) 沒有順帶把別的格報壞**。
//
// **mutate 的是 pristine copy，出貨的 CLAUDE.md 從頭到尾不被開啟以寫入**——結束前以
// mtime 前後比對確認（前一版 harness 就地改寫版控中的檔案，#407 R6）。
//
// **遷移期兩版都跑並要求逐字一致**（#433）：守衛的 Python 版仍在樹裡當 oracle，Swift 版
// 是實際在跑的。刪掉 Python 版時把 `runBoth` 裡那一半拿掉即可。
//
// trigger-coverage: reads CLAUDE.md

import Foundation

func decisionMatrixMutations() -> Int32 {
    let MD = "\(repoRoot)/CLAUDE.md"
    let BIN = "\(repoRoot)/.build/debug/akashic-guards"

    let R6 = "> | 正常 `git push` | 恢復 | 指向本樹 | 執行 | 執行 |"
    let R3 = "> | 正常 `git push` | 不跑 | 指向本樹 | **執行** | **零執行** |"
    let R5 = "> | 正常 `git push` | 恢復 | 指向主 repo | **零執行** | **執行** |"
    let R2 = "> | 正常 `git push` | 不跑 | 指向主 repo | **零執行** | 零執行 |"
    let R1 = "> | 正常 `git push` | 不跑 | 未設定 | 零執行 | 零執行 |"
    let HEAD = "> | push 方式 | CI 狀態 | hooksPath | 留在 pre-push | 移出、只留 CI |"

    func rep(_ s: String, _ a: String, _ b: String) -> String {
        guard let r = s.range(of: a) else { return s }
        return s.replacingCharacters(in: r, with: b)
    }

    typealias Case = (name: String, fn: (String) -> String, must: [String], mustnot: [String])
    let CASES: [Case] = [
        ("把 R26q 那一列放回來（任一 × 留欄不一致）",
         { rep($0, R6, "> | 正常 `git push` | 恢復 | 任一 | 執行 | 執行 |") },
         ["✗ 列6", "被重複宣稱"], []),
        ("翻掉一格的宣稱值（列3 執行→零執行）",
         { rep($0, R3, rep(R3, "| **執行** |", "| **零執行** |")) },
         ["✗ 列3"], ["✗ 列1", "✗ 列2", "✗ 列4"]),
        ("刪掉一列（列5）→ 涵蓋出現缺口",
         { rep($0, R5 + "\n", "") },
         ["缺 ", "'主repo'"], ["✗ 列"]),
        ("讓兩列重疊（列1 的 hooksPath 改成任一）",
         { rep($0, R1, "> | 正常 `git push` | 不跑 | 任一 | 零執行 | 零執行 |") },
         ["✗ 列1", "被重複宣稱"], []),
        ("把一格的 hooksPath 弄成解析不出來的字",
         { rep($0, R2, rep(R2, "指向主 repo", "見上")) },
         ["<未解析>"], ["矩陣與規則一致"]),
        ("改掉表頭 → 找不到表",
         { rep($0, HEAD, "> | 推送方式 | CI | hooks | 留 | 移出 |") },
         ["找不到決策矩陣的表頭"], []),
        ("多塞一欄 → 欄數不是 5",
         { rep($0, R6, R6 + " 備註 |") },
         ["欄數不是 5"], ["矩陣與規則一致"]),
        // 這一個是負控自己抓出來的：上一版的「多塞一欄」切出來仍是 5 欄、mutation 沒生效。
        // 修它時看見結果格的子串比對會把「執行（只在 merge 後）」讀成無條件「執行」——
        // 限定詞被安靜丟掉。#407 R28：三個「人讀是 A、parser 讀成 B 且不出聲」的自然編輯。
        ("push 格不在封閉詞彙裡（`正常 push`，少了 git）→ 不得被猜成正常",
         { rep($0, R6, "> | 正常 push | 恢復 | 指向本樹 | 執行 | 執行 |") },
         ["<未解析>"], ["矩陣與規則一致"]),
        ("hooksPath 格寫成「指向本樹以外」→ 不得只讀到其中一值",
         { rep($0, R6, "> | 正常 `git push` | 恢復 | 指向本樹以外 | 執行 | 執行 |") },
         ["<未解析>"], ["矩陣與規則一致"]),
        // R30：格裡一律不准有註記——不論它會不會造成誤讀。偵測矛盾的兩個近似做法都被
        // 實測否掉（一個抓不到、一個誤傷 2 列），所以改成讓矛盾寫不出來。
        ("key 欄帶註記 → 一律拒（不偵測矛盾，改成寫不出來）",
         { rep($0, R5, rep(R5, "指向主 repo", "指向主 repo（**已 merge**）")) },
         ["格裡有註記"], ["矩陣與規則一致"]),
        ("結果欄帶限定詞 → 一律拒",
         { rep($0, R6, rep(R6, "| 執行 |", "| 執行（只在 merge 後） |")) },
         ["格裡有註記"], ["矩陣與規則一致"]),
    ]
    // **不是每個注入都該讓守衛變紅。** R30 起格裡不准有註記，於是「註記須被忽略」那組
    // 不再存在——`ROBUST` 是空的，但計數仍印出來（`0 個須綠`），因為「這一類目前沒有
    // 實例」與「這一類不存在」是兩件事。
    let ROBUST_COUNT = 0

    /// 跑守衛。**兩版都跑並要求逐字一致**——回傳實際在跑的那一版。
    func runBoth(_ path: String) -> (Int32, String) {
        func exec(_ argv: [String]) -> (Int32, String) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: argv[0])
            p.arguments = Array(argv.dropFirst())
            p.currentDirectoryURL = URL(fileURLWithPath: repoRoot)
            let o = Pipe(), e = Pipe(); p.standardOutput = o; p.standardError = e
            guard (try? p.run()) != nil else { return (127, "spawn 失敗：\(argv[0])") }
            let od = o.fileHandleForReading.readDataToEndOfFile()
            let ed = e.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return (p.terminationStatus,
                    (String(data: od, encoding: .utf8) ?? "") + (String(data: ed, encoding: .utf8) ?? ""))
        }
        // **Python 版已刪除**（#433 Step 5）：遷移期這裡跑兩版並要求逐字一致。
        return exec([BIN, "decision-matrix-drift", path])
    }

    func stat(_ p: String) -> (Int, Int) {
        let a = (try? FileManager.default.attributesOfItem(atPath: p)) ?? [:]
        let m = (a[.modificationDate] as? Date).map { Int($0.timeIntervalSince1970 * 1e9) } ?? -1
        return (m, (a[.size] as? Int) ?? -1)
    }
    let before = stat(MD)
    let src = (try? String(contentsOfFile: MD, encoding: .utf8)) ?? ""

    let (rc0, out0) = runBoth(MD)
    print(rc0 == 0 ? "baseline：rc=\(rc0) ✓" : "✗ baseline 就紅了：\n\(out0)")
    if rc0 != 0 { return 1 }
    print("（\(CASES.count) 個 mutation 待跑）\n")

    var ok = 0
    let tmpRoot = NSTemporaryDirectory()
    for c in CASES {
        let mutated = c.fn(src)
        // 注入沒生效卻報綠，是假 harness 的形狀（#407 R19）——直接擋掉。
        if mutated == src {
            print("✗ 注入「\(c.name)」→ **內容沒變**，這個 case 無效"); continue  // display-safe-exempt: c.name 是本檔 CASES 的字串常數，非 store 衍生
        }
        let d = tmpRoot + "dmm-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        let p = d + "/CLAUDE.md"
        try? mutated.write(toFile: p, atomically: true, encoding: .utf8)
        let (rc, out) = runBoth(p)
        try? FileManager.default.removeItem(atPath: d)
        let miss = c.must.filter { !out.contains($0) }
        let stray = c.mustnot.filter { out.contains($0) }
        if rc == 1 && miss.isEmpty && stray.isEmpty {
            print("✓ 注入「\(c.name)」→ rc=1，具名且無旁及"); ok += 1  // display-safe-exempt: c.name 是本檔 CASES 的字串常數，非 store 衍生
        } else {
            print("✗ 注入「\(c.name)」→ rc=\(rc)"  // display-safe-exempt: c.name 是本檔 CASES 的字串常數，非 store 衍生
                + (miss.isEmpty ? "" : "，缺 \(pyRepr(miss))")
                + (stray.isEmpty ? "" : "，旁及 \(pyRepr(stray))"))
            print("   " + String(out.replacingOccurrences(of: "\n", with: "\n   ").prefix(600)))
        }
    }

    let after = stat(MD)
    let same = before == after
    print("\n=== negative control \(ok)/\(CASES.count + ROBUST_COUNT) "
        + "（\(CASES.count) 個須紅 ＋ \(ROBUST_COUNT) 個須綠）===")
    print("\(same ? "出貨檔未被開啟以寫入" : "**出貨檔被動到了**")：CLAUDE.md")
    return (ok == CASES.count + ROBUST_COUNT && same) ? 0 : 1
}
