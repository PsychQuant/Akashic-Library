// `store-marker-parity.sh` 的 negative control。
//
// 逐一把 census 的 marker 解析規則注入缺陷，要求 parity 測試 (1) fail>0、(2) 宣告的那一格
// 變紅。**mutate 的是 census 的 copy，出貨檔完全不碰。**
//
// **判準是「宣告的那一格紅了」，刻意不是「只有那一格紅」。** 姊妹 harness
// （`rule-prose-guards-mutations`）用的是「恰好第 n 項紅」，因為那邊的 5 個 check 是
// **不同性質**的檢查。這裡不跟進，而且不是還沒做：46 個 fixture 是**同一個性質**
// （census 與讀端一致）的不同輸入，一個打壞 census 某條規則的注入天然會讓所有依賴該
// 規則的 fixture 一起紅——那是正確行為，不是雜訊。要求 exact 會逼每個 mutation 手寫一份
// 預期的 fixture 集合，而那份集合會在新增 fixture 時安靜過期。
//
// **14 個 mutation 的字串在 `MarkerParityMutationsData.swift`，機械抽出不手抄**（#433）。
//
// trigger-coverage: reads plugin/skills/*/scripts/literal-census.sh

import Foundation

func markerParityMutations() -> Int32 {
    let HERE = "\(repoRoot)/plugin/skills/akashic-promote-literals/scripts/tests"
    let CENSUS = "\(repoRoot)/plugin/skills/akashic-promote-literals/scripts/literal-census.sh"
    let TEST = "\(HERE)/store-marker-parity.sh"
    let TABLE = "\(repoRoot)/plugin/skills/akashic-promote-literals/scripts/hash-merging-ranges.txt"
    let ORIGINAL = (try? String(contentsOfFile: CENSUS, encoding: .utf8)) ?? ""

    func runTest(_ censusPath: String) -> (Int, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [TEST, "--census", censusPath]
        p.currentDirectoryURL = URL(fileURLWithPath: repoRoot)
        let o = Pipe(); p.standardOutput = o; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return (-1, "spawn 失敗") }
        let d = o.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(data: d, encoding: .utf8) ?? ""
        let n = matches(out, #"fail=(\d+)"#).first.map {
            Int((out as NSString).substring(with: $0.range(at: 1))) ?? -1
        } ?? -1
        return (n, out)
    }

    // baseline 必須先全綠——否則「注入後變紅」不代表任何事（R6 finding 11：前一版從不
    // 檢查 baseline，原守衛整片壞掉時它仍會 exit 0）。
    let (baseFails, baseOut) = runTest(CENSUS)
    if baseFails != 0 {
        print(baseOut)
        print("✗ baseline 不是全綠（fail=\(baseFails)）——先修 parity 測試，"
            + "negative control 在紅的 baseline 上沒有意義")
        return 1
    }
    print("baseline：fail=0 ✓（\(markerParityMutations_count) 個 mutation 待跑）")
    print("")

    let work = NSTemporaryDirectory() + "marker-mut-" + UUID().uuidString
    try? FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: work) }

    var results: [Bool] = []
    for m in markerParityMutationsTable {
        // 注入點不唯一即中止——那表示抽出的片段與 census 的寫法脫節了。
        let c = ORIGINAL.components(separatedBy: m.old).count - 1
        if c != 1 { print("✗ 注入點不唯一（\(c) 次）：\(m.desc)"); return 1 }
        let copy = work + "/literal-census.sh"
        guard let r = ORIGINAL.range(of: m.old) else { return 1 }
        try? ORIGINAL.replacingCharacters(in: r, with: m.new)
            .write(toFile: copy, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: copy)
        // **相鄰的資料檔也要一起複製。** census 從自己的所在目錄讀
        // `hash-merging-ranges.txt`（判 `#` 註解用的 grapheme 表）。只複製腳本的話，copy
        // 找不到表 → 所有「# + 非 ASCII」的 fixture 一律變 undecidable，**與被測的
        // mutation 無關**。實測：單一 mutation 的 fail 從 1–3 變成 11–12，而 harness 仍報
        // 14/14——它在一個降級的環境裡量，數字看起來是綠的（#407 R10 verify）。
        let tableDst = work + "/" + (TABLE as NSString).lastPathComponent
        try? FileManager.default.removeItem(atPath: tableDst)
        try? FileManager.default.copyItem(atPath: TABLE, toPath: tableDst)
        let (fails, out) = runTest(copy)
        let hit = out.contains("✗ " + m.expectCase)
        let ok = fails > 0 && hit
        print("\(ok ? "✓" : "✗") 注入「\(m.desc)」→ fail=\(fails)"
            + (hit ? "，且該格變紅" : "，但該格沒紅 ← 測試對它是盲的"))
        results.append(ok)
    }

    print("")
    print("=== negative control \(results.filter { $0 }.count)/\(results.count) ===")
    print("出貨檔未被開啟以寫入：plugin/skills/akashic-promote-literals/scripts/literal-census.sh")
    return results.allSatisfy { $0 } ? 0 : 1
}
