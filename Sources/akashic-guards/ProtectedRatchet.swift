// 受保護清單的棘輪（#522）：清單少了什麼、多了什麼，都要出聲。
//
// ## 為什麼需要它
//
// `trigger-coverage` 的 `missing` 檢查問的是「清單裡列的路徑還在不在磁碟上」——而
// **glob 產生的成員永遠不會「列了卻不存在」**，它只會變少。2026-09-09 實測三組：
//
//   A 刪一整支守衛（`plugin/tests/review-claim-audit.sh`）  → 守衛 24→23、受保護 56→55、rc=0
//   B 刪一條 glob 規則檔（`.claude/rules/no-compat-fallback.md`）→ 受保護 56→55、rc=0
//   C 拿掉一條顯式 `DATA` 條目（重編 binary 後）             → 受保護 56→55、rc=0
//
// 三組全部印「無缺口」。失效方向與 #516／#518 相同：**安靜的綠**。
//
// ## 為什麼是棘輪，不是「把 glob 換成顯式清單」
//
// 顯式清單今天 19/19 由 `missing` 逐條具名——看起來更好。但把 11 條 glob 規則檔換成顯式
// 之後，**忘記把新規則檔加進去是靜默的**：同一個失效換一步，而規則檔正是這個 repo 用來
// 承載裁決的地方。棘輪相反：它對「少了什麼」與「多了什麼」都出聲。
//
// ## 為什麼它不是 #518 記過的那個缺陷
//
// #518 的教訓是「複製清單與 `DATA` 之間沒有任何東西在對帳」。棘輪**整個存在理由就是被
// 對帳**——這支守衛自己就是對帳機制。同形先例：`hash-table-drift.sh` 對一張生成的表做的
// 是同一件事（「表有它自己的失效模式：版本一動它就過期，而過期是安靜的」）。
//
// 清單來自 `protectedInventory()`，與 `trigger-coverage` **同一份**——一個自己算一遍的
// 棘輪只會證明它自己與自己一致。
//
// trigger-coverage: reads .githooks/protected-ratchet.txt

import Foundation

let ratchetPath = ".githooks/protected-ratchet.txt"

func protectedRatchet(argv: [String]) -> Int32 {
    let inv = protectedInventory()
    let current = Array(Set(inv.guards + inv.data)).sorted()
    let body = current.joined(separator: "\n") + "\n"

    if argv.contains("--accept") {
        do {
            try body.write(toFile: "\(repoRoot)/\(ratchetPath)", atomically: true, encoding: .utf8)
            print("══ 棘輪已更新：\(current.count) 條 ══")
            print("  改動會出現在 commit diff 裡——那就是它被 review 的地方")
            return 0
        } catch {
            print("✗ 寫不進 \(ratchetPath)：\(error)")
            return 2
        }
    }

    guard fileExists(ratchetPath) else {
        print("✗ 棘輪檔 \(ratchetPath) 不存在——建立它：")
        print("    .build/debug/akashic-guards protected-ratchet --accept")
        return 2
    }
    let recorded = rawFile(ratchetPath)
        .components(separatedBy: "\n").filter { !$0.isEmpty }
    // **空集合不得冒充通過**：一個空的棘輪對任何清單都「沒有少」。
    guard !recorded.isEmpty else {
        print("✗ 棘輪檔是空的——那不是「沒有少」，是棘輪壞了")
        return 1
    }
    let rec = Set(recorded), cur = Set(current)
    let removed = recorded.filter { !cur.contains($0) }
    let added = current.filter { !rec.contains($0) }
    guard removed.isEmpty && added.isEmpty else {
        var out = "══ 受保護清單與棘輪不符 ══\n"
        for p in removed {
            out += "  ✗ 少了：\(p)——它從清單裡消失了。"
                 + "刪檔是合法的，但要在這裡被看見（glob 成員消失時沒有別的東西會說話）\n"
        }
        for p in added {
            out += "  ✗ 多了：\(p)——新成員也要被 review："
                 + "往已在 CI paths 的路徑根加一個零讀者的檔，可以零成本灌水（#522 半二 3）\n"
        }
        out += "  確認之後接受它：.build/debug/akashic-guards protected-ratchet --accept\n"
        FileHandle.standardError.write(Data(out.utf8))
        return 1
    }
    print("══ 受保護清單與棘輪相符：\(current.count) 條 ══")
    return 0
}
