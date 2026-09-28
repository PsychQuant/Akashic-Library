// plugin 根的 `rules/` 底下的每一條規則，是否被每一個 skill 掛到？
//
// （原為 `plugin/tests/rule-coverage.sh`，#629 移植成 Swift。呼叫形狀不變：
// `akashic-guards rule-coverage [plugin-root]`，root 是 repo 相對路徑，省略時為 `plugin`；
// `run-guards.sh` 逐根呼叫——根的清單只有 `akashic-guards plugin-roots` 那一份，#625。）
//
// ## 為什麼存在
//
// CHANGELOG 與規則檔都寫過「**全部 6 個 skill** 引用它」。那是一個**硬編的計數**：
// 第 7 個 skill 長出來時沒有任何東西會提醒它漏掛，而那句「全部」會安靜地變成假的。
// 跨模型審查點名了這一格（#407 R5 finding 34）。
//
// 這支把那句話從「作者數過」變成「跑一下就知道」。它不解決掛載面比適用面窄的
// 問題（規則檔的誠實邊界有記：see-also 只碰得到 skill 檔），只保證**在它碰得到的
// 範圍內沒有漏格**。
//
// ## 驗的是什麼
//
// **「有一條解析得到的相對路徑指向這條規則」**，不是「這個字串在某處出現過」。前一版用整目錄
// 子字串比對，於是任何一處純文字提及都算「已掛載」——包括一句「本規則不適用於此」。規則檔與
// CHANGELOG 卻把它描述成「引用存在且路徑解析得到」，那個描述經實測為假（#407 R6 findings 14／15／17）。
//
// 擷取樣式的結尾用 `[^)`" ]*` 一路吃到分隔符，**不是**吃到 .md 就停。前一版會從
// `…assertions-must-be-measured.md.bak` 擷取出一個合法前綴、驗證通過，而那個連結是壞的。
// 擷取到的整個 token 必須就是規則檔本身（不是它的前綴）。
//
// **只認 SKILL.md**。掛載點是 skill 的進入點，不是它目錄裡的任一份筆記。前一版掃整個子樹，
// 於是把連結從 SKILL.md 拿掉、在旁邊的 note.md 寫一句「不要載入這條規則」，守衛照樣 ✓
// （#407 R7 verify）。加位置條件才是真的修掉。
//
// ## 與 shell 版的行為差異（#629，判定不變）
//
// - 輸出裡的 SKILL.md 路徑印成 `skills/<name>/SKILL.md`（shell 版因為 glob 的尾斜線印成
//   `skills/<name>//SKILL.md`，那是意外不是設計）。
// - 規則檔與 skill 目錄按位元組序排序（shell 版依 locale 排序；目前的規則名第一個字母就不同，
//   兩者結果一致）。
// - skill 計數只算真目錄（與 `find -type d` 同：symlink 不算）。
// - `rules/` 裡一條 `.md` 都沒有時，兩版都紅，但原因不同：shell 版是 glob 沒命中、字面的 `*.md`
//   被當成一條叫 `*` 的規則（意外）；Swift 版顯式報「沒有東西可檢查」（rc=1）。空集合不得冒充通過。
//
// trigger-coverage: reads plugin/rules/*.md

import Foundation

func ruleCoverage(argv: [String]) -> Int32 {
    let err = { (s: String) in FileHandle.standardError.write(Data((s + "\n").utf8)) }
    let fm = FileManager.default

    // 找不到就停，**不退回檢查 `plugin/`**：退回的話打錯的根會拿到一個與它無關的綠燈
    let rootRel = argv.first ?? "plugin"
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: "\(repoRoot)/\(rootRel)", isDirectory: &isDir), isDir.boolValue else {
        err("✗ 找不到 plugin 根：\(rootRel)")
        return 2
    }
    let plugin = "\(repoRoot)/\(rootRel)"
    let rulesDir = "\(plugin)/rules"
    let skillsDir = "\(plugin)/skills"

    guard fm.fileExists(atPath: rulesDir, isDirectory: &isDir), isDir.boolValue else {
        err("✗ 找不到 \(rulesDir)")
        return 2
    }

    /// 非隱藏的直接子項，依位元組序。
    func children(_ dir: String) -> [String] {
        ((try? fm.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
    }

    // 真目錄的數量（不含 symlink）；0 個是 vacuous 通過，**印出來**——讀的人要分得出
    // 「沒有 skill」與「沒檢查」。新 plugin 在第一個 skill 住進來之前就是這個狀態
    // （akashic-discovery 先於 #617 上線）。
    let nSkills = ((try? fm.contentsOfDirectory(atPath: skillsDir)) ?? []).filter {
        (try? fm.attributesOfItem(atPath: "\(skillsDir)/\($0)")[.type] as? FileAttributeType) == .typeDirectory
    }.count
    if nSkills == 0 {
        print("═══ rule coverage：\(rootRel) 有 0 個 skill（vacuous）═══")
        return 0
    }
    print("═══ rule coverage：\(nSkills) 個 skill ═══")
    print("")

    // `rules/*.md`（glob：不含隱藏檔；不要求是 regular file，與 shell 的 glob 同）
    let rules = children(rulesDir).filter { $0.hasSuffix(".md") }
    // `skills/*/`（glob：目錄或指向目錄的 symlink）
    let skills = children(skillsDir).filter {
        var d: ObjCBool = false
        return fm.fileExists(atPath: "\(skillsDir)/\($0)", isDirectory: &d) && d.boolValue
    }

    // **零條規則不是「全部掛上」。** shell 版在這裡是意外變紅（glob 沒命中時字面的 `*.md` 被當成
    // 一條名叫 `*` 的規則，於是每個 skill 都缺）；Swift 版的空迴圈會直接印綠燈——「沒有東西可檢查」
    // 與「檢查過且乾淨」在輸出上無法區分。所以顯式報紅，並說出是哪一種。
    guard !rules.isEmpty else {
        print("✗ \(rootRel)/rules/ 底下沒有任何 .md 規則檔——不是「全部掛上」，是沒有東西可檢查")
        print("═══ 1 個缺口 ═══")
        return 1
    }

    var fail = 0
    for ruleFile in rules {
        let name = String(ruleFile.dropLast(".md".count))
        print("── \(name) ──")
        // `[^)`" \n]`：與 grep 逐行掃描同——token 不跨行。ICU 的否定字元類會吃換行，要明寫。
        let pattern = #"\.\./[^)`" \n]*"# + NSRegularExpression.escapedPattern(for: name) + #"[^)`" \n]*"#
        for skill in skills {
            let skillDir = "\(skillsDir)/\(skill)"
            let skillFile = "\(skillDir)/SKILL.md"
            let shown = "skills/\(skill)/SKILL.md"
            var found = false
            // 讀不到 SKILL.md ＝ 沒有任何 hit（下方判為沒掛），不是守衛自己失敗
            let text = fm.contents(atPath: skillFile).map { String(decoding: $0, as: UTF8.self) } ?? ""
            let ns = text as NSString
            for m in matches(text, pattern) {
                let rel = ns.substring(with: m.range)
                // 擷取到的整個 token 必須就是規則檔本身（不是它的前綴）
                guard base(rel) == ruleFile else {
                    print("  ✗ \(shown) 的引用不是這條規則本身：\(rel)")
                    fail += 1
                    continue
                }
                var f: ObjCBool = false
                if fm.fileExists(atPath: "\(skillDir)/\(rel)", isDirectory: &f), !f.boolValue {
                    found = true
                } else {
                    print("  ✗ \(shown) 的相對路徑解析不到：\(rel)")
                    fail += 1
                }
            }
            if found {
                print("  ✓ \(skill)")
            } else {
                print("  ✗ \(skill) ← 沒有指向這條規則的可解析相對路徑")
                fail += 1
            }
        }
    }

    print("")
    print(fail == 0 ? "═══ 全部掛上，相對路徑全部解析得到 ═══" : "═══ \(fail) 個缺口 ═══")
    return fail > 0 ? 1 : 0
}
