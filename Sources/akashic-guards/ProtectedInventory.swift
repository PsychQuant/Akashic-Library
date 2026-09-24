// 受保護清單（#522）。
//
// **它住在這裡而不是 `TriggerCoverage.swift`，理由是量出來的。** `READS` 判定「這支守衛
// 讀了哪些受保護檔」的方式是「路徑字面出現在它的程式碼裡」——而**持有清單的那個檔，
// 清單裡每一條的字面本來就在它自己的程式碼裡**。於是 `TriggerCoverage.swift` 被判定讀了
// 一堆它根本沒讀的檔。**2026-09-09 實測本輪前後：22 → 2**（#522 半二 3 記的是
// 「被判定讀 15 個」，那是立案當時的數字；清單這中間長大了）。
//
// #522 的 Expected 3 提的解法是「`READS` 的鍵從 basename 換成完整相對路徑」——**量測顯示
// 那不解決這一個**：`DATA` 裡寫的本來就是完整路徑，換過去照樣命中。真正的來源是「持有
// 清單的檔案自己是一支守衛」，而 `swiftGuards()` 只把 `main.swift` 有對應 `case` 的檔算成
// 守衛。清單搬進這個沒有 `case` 的檔之後，它不是守衛，phantom 也就不存在。
//
// 2026-09-09 另量：`READS` 的邊裡完整路徑命中 64 條、**只靠 basename** 17 條。把比對收窄
// 成完整路徑會拿掉那 17 條，而多餘的邊只會產生多餘的**紅**、少掉的邊會產生**綠**——
// 收窄的失敗方向比放寬糟。所以 basename 回退保留。

import Foundation

/// repo 根目錄實際存在的目錄，各帶尾斜線（#522）。
///
/// 取代手維護的白名單。**排除兩個**：`.git`（版控自己的目錄，不是 repo 內容）與
/// `.build`（建置產物，且走訪它很貴）。這是封閉的兩項，不是「凡是隱藏目錄」——
/// `.claude`／`.githooks`／`.github` 都是真的內容且本來就在舊白名單裡。
func repoTopLevelRoots() -> [String] {
    let fm = FileManager.default
    let skip: Set<String> = [".git", ".build"]
    guard let names = try? fm.contentsOfDirectory(atPath: repoRoot) else { return [] }
    return names.filter { name in
        guard !skip.contains(name) else { return false }
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: "\(repoRoot)/\(name)", isDirectory: &isDir) && isDir.boolValue
    }.map { $0 + "/" }.sorted()
}

/// 受保護清單的**單一來源**（#522）：`trigger-coverage` 與 `protected-ratchet` 共用。
///
/// 抽出來的理由不是重用，是**不得有第二份**：棘輪檔要比對的正是這份清單，而一個自己
/// 算一遍的棘輪只會證明它自己與自己一致。
func protectedInventory() -> (guards: [String], data: [String]) {
    // 生成器不是守衛——它由 hash-table-drift.sh 呼叫，自己不做斷言。
    let GENERATORS: Set<String> = ["derive-hash-extenders.swift"]
    // **逐段相加而非一個大表達式**：合成一式時 Swift 的型別檢查逾時（實測），
    // 而那個失敗看起來像「這段程式有問題」而不是「這一式太長」。
    // #625：同一組 pattern 套到**每一個** plugin 根（原本只有 `plugin/`——放在
    // `plugins/<name>/` 的測試被刪或沒接線，沒有一道守衛會出聲）。根目錄來自唯一來源
    // `pluginRoots()`；負對照見 `plugin-roots-mutations`。
    var scripts: [String] = []
    for root in pluginRoots() {
        for pat in ["tests/*.sh", "tests/*.py", "skills/*/scripts/tests/*.sh",
                    "skills/*/scripts/tests/*.py", "skills/*/scripts/tests/*.swift"] {
            scripts += globFiles("\(root)/\(pat)")
        }
    }
    scripts = realRepoRelative(scripts)
    let GUARDS = (scripts.filter { !GENERATORS.contains(base($0)) } + swiftGuards()).sorted()

    // 守衛之外，還被守衛讀的東西。**每一條都必須存在**（坑 1）。
    var DATA = [
        "plugin/skills/akashic-promote-literals/scripts/literal-census.sh",
        "plugin/skills/akashic-promote-literals/scripts/hash-merging-ranges.txt",
        "plugin/skills/akashic-promote-literals/scripts/tests/derive-hash-extenders.swift",
        // ── 以下八條是 #518 補進來的 ─────────────────────────────────────────
        //
        // **為什麼是顯式條目而不是放寬 glob。** 兩個方案各有一個沉默方向：
        //   · 顯式條目 —— 新增（守衛開始讀一個沒被保護的檔）靜默 ← 就是 #518
        //   · 放寬 glob —— 刪除（受保護檔被刪掉）靜默；glob 只是回傳更少的檔，
        //     而 `#433` 的註解已記過同型：「刪檔會讓那支守衛整個離開覆蓋表，
        //     而輸出仍印 ✓ 涵蓋 6/6」
        // 裁決：**顯式條目 ＋ 一道會紅的檢查**（下方「守衛讀的檔必須在受保護集合」）。
        //
        // **但「兩個方向都不沉默」是假的。** 那句話是 #518 的第一版寫在這裡與 changelog
        // 裡的，被 R1 verify 的 Devil's Advocate 用實測推翻、coordinator 獨立重現。三個量測：
        //
        //   1. **刪檔方向只涵蓋顯式字面。** `missing`（下方）檢查的是「清單裡列的路徑還在
        //      不在磁碟上」，而 glob 產生的成員永遠不會「列了卻不存在」——它只會變少。
        //      `PROTECTED` 的 55 條組成（實測，#521 後）：**顯式 20**、`GUARDS` **23**
        //      （**7 個 glob ＋ 16 個由 `swiftGuards()` 解析 `main.swift` 的 `case` 分派**——
        //      不是「整組 glob」，那是本檔上一版寫錯的機制描述）、rules glob **12**
        //      （`.claude/rules/*.md` 11 ＋ `plugin/rules/*.md` 1）。
        //      **這道守衛自己對 32 條刪檔沉默**（35 條 glob 成員裡 3 條會出聲：
        //      `entity-backlink-completeness.md` 與 `mcp-cli-parity.md` 被**具名宣告**指到、
        //      `assertions-must-be-measured.md` 是 `plugin/rules/*.md` 的唯一成員故 glob 解析到零）。
        //      實測刪掉一整支守衛 `plugin/tests/review-claim-audit.sh` → 守衛 23→22、
        //      **rc=0、照印「無缺口」**。
        //
        //      **但「32 條可以無聲消失」對整條 pre-push 是過度悲觀的**（R2 verify 更正）：
        //      那 32 條裡 **23 條在 pre-push 的別的階段是大聲的**——16 支 Swift 守衛的檔一刪，
        //      `main.swift` 的 `case` 分派就找不到符號、`swift build` 直接失敗（pre-push 第一
        //      階段就是它）；7 支腳本守衛一刪，`run-guards.sh` 以路徑呼叫它們、rc=127。
        //      **整條 pre-push 都靜默的只剩 9 個 `.claude/rules/*.md`（9/55，16%）。**
        //
        //   2. **「從 `DATA` 拿掉一條」與「檔案被刪掉」是兩件事**，而前者只有在**某支守衛的
        //      程式碼裡有那條路徑的引號字面**時才會紅。實測 20 條顯式條目裡 **10 條看不見**。
        //      **`MarkerParityMutationsData.swift` 是最尖的一格**：它是本輪自己補進來的、
        //      是真依賴（`RuleProseGuards.swift:285` 真的讀它），而拿掉它一聲不吭——
        //      #518 的標題所描述的形狀，發生在 #518 自己修完之後、在它自己加的條目上。
        //
        //      **10/20 這個比例比修法前更差，而那是本輪自己造成的**：R2 補進來的那 5 條
        //      （下方 `AuditGuardsMutationsData` 那一段）唯一的讀者就是那個**不被掃描的資料
        //      檔**，所以它們一進來就全部落在盲區。修法前是 5/14。把它寫出來而不是只報
        //      「受保護 55」，因為後者看起來像單調的進步。
        //
        //   3. **新增方向只涵蓋「引號緊鄰完整路徑」的寫法。** 見下方檢查處的盲點清單。
        //
        // **裁決仍然成立，而且比上一版寫的更強**（R2 verify 更正——上一版寫「刪除那一軸兩案
        // 同樣沉默」，那是從「兩個方向都不沉默」過度擺盪到另一端，而且同樣沒量過 glob 那一側）：
        //   · **刪除軸**：顯式條目 **20/20 由 `missing` 逐條具名**；glob 成員 **0**
        //     （結構上不可能——glob 不會「列了卻不存在」）。顯式嚴格更優 20 個檔。
        //   · **新增軸**：同形放寬 glob（`plugin/skills/*/scripts/*.{sh,py}`）只涵蓋得到本輪
        //     8 個新檔裡的 **1 個**；要涵蓋 8/8 得同時放寬六條 glob 根、**156 個檔進
        //     `PROTECTED`**（54 → 191）。只放寬 `Sources/*/*.swift` 一條實跑就是
        //     **rc=1、受保護 172、72 條缺口**。
        // 兩軸都是顯式勝，所以裁決不必改；要改的是**別把它說成完整的保證**。
        //
        // 這裡選擇把覆蓋率降級成誠實的散文而不是當場補一道機制，理由**不是**「零實例」——
        // `GUARDS.count` 下降有實測前例，本檔 `#433` 那段就記著「21 支 → 6 支而輸出照印
        // ✓ 涵蓋 6/6」。真正的理由是：根治要先分開「守衛自己讀的路徑」與「注入用的 payload
        // 路徑」（見下方第六個盲點），那是判準問題不是一行改動。追蹤 #522。
        //
        // **量測（逐項，#518 R1 重量）**：這道檢查**自己**找出 **5 支守衛／8 對／7 個檔**；
        // 第 8 個檔 `MarkerParityMutationsData.swift` 是**照報表手補的**——它真正的讀者
        // `RuleProseGuards.swift:285` 把路徑組出來，引號不緊鄰，這道檢查看不到。
        // 合計 **6 支守衛／9 對／8 個相異檔**（`.githooks/run-guards.sh` 被兩支守衛引用，
        // 在對數裡算兩次、在檔數裡算一次）。受保護 41 → 49。
        // 手維護清單不自我維持，自此不再是推論而是 n=6 的量測。
        "plugin/skills/akashic-venue-works/scripts/ndjson-abstracts-to-proposals.py",
        "plugin/.claude-plugin/plugin.json",
        "Sources/akashic-mcp/Server.swift",
        "Sources/akashic/CLI.swift",
        "Sources/akashic-guards/MarkerParityMutationsData.swift",
        "Sources/akashic-guards/main.swift",
        ".githooks/run-guards.sh",
        // `mcpb/manifest.json` 這一條由新檢查自己找出來（立案時的手工掃描漏了那個路徑根）——
        // 而它是 store format 的**第三份宣告來源**、且是出貨物（`release-signed.sh`
        // 會 zip 進 `.mcpb`）。`census-parity.yml` 的 paths 早就列了它，逐對迴圈卻
        // 一直看不到這一對。檢查上線的第一次執行就抓到自己的作者漏掉的那一個。
        "mcpb/manifest.json",
        // ── R2 verify 找到的第六個盲點：守衛的**資料檔**完全不被掃描 ──────────
        //
        // 下方那道檢查只掃 `GUARDS`，而 `Sources/akashic-guards/*Data.swift`（四個：
        // `AuditGuardsMutations`／`BacklinkRatchet`／`MarkerParityMutations`／
        // `TriggerCoverageMutations`）**不是守衛**——`main.swift` 沒有對應的 `case`，
        // 所以整個檔一行都不會被看到。而 `AuditGuardsMutationsData.swift` 用
        // `AGMEdit(path: "…")` 逐字寫著 20 個路徑，其中 **5 個存在卻未受保護**。
        //
        // **這一格特別要記**：上面那份「五種寫法會靜默繞過」的清單**全部零實例**
        // （示範用的是構造出來的例子），而這第六種**今天就有 5 個實例**，且它們全都
        // 已在 `census-parity.yml` 的 `paths:` 裡——與 `mcpb/manifest.json` 完全同型。
        // 誠實邊界列滿了假想的洞，漏掉唯一一個真的。
        //
        // **為什麼不直接把 `*Data.swift` 納入掃描（那才是根治）**：
        // `TriggerCoverageMutationsData.swift` 裡有 `"Sources/akashic-guards/ShellLex.swift"`
        // ——那是**負控刻意選的、必須永遠不在 `PROTECTED` 的目標**。納入掃描會讓這支
        // 守衛因為自己的負控 payload 而永久變紅。要根治得先分開「守衛自己讀的路徑」與
        // 「注入用的 payload 路徑」，那是判準問題不是一行改動——#522。
        ".github/workflows/census-parity.yml",
        "Sources/AkashicCore/Models.swift",
        "Sources/AkashicCore/Temporal.swift",
        "Sources/akashic/CreateEntryCommand.swift",
        "plugin/skills/akashic-promote-literals/SKILL.md",
        // #521：`MeasuredClaimsAudit` 的檢查 ③ 改指向這裡之後，它成了一條**真依賴**
        // ——而新加的「檔案不存在」那一半正是靠它才把舊的死引用抓出來的。
        // 這也補上 #518 regression 席指出的不對稱：`MarkerParityMutationsData.swift`
        // 早就在表裡，它的姊妹檔卻不在（而本輪的 diff 就改了它）。
        "Sources/akashic-guards/TriggerCoverageMutationsData.swift",
    ]
    // **兩個 glob 根要對稱**（#407 R50）：`.claude/rules/*.md` 已升成 live glob，而
    // 這一側曾是單一寫死路徑。`plugin/rules/` 一長出第二個檔，`declared()` 就會再次
    // **少解析**——正是那次改動要修的病，只是換到另一側。
    // 每個根的 `rules/*.md`，**還原真實路徑後去重**：discovery 的 `rules` 是指向
    // `plugin/rules` 的 symlink，而只有最後一段萬用字元的 glob 會穿過它（#625 tasks 1.1
    // 實測）——不還原的話同一條規則會以兩個路徑成為兩個受保護成員。
    DATA += realRepoRelative(pluginRoots().flatMap { globFiles("\($0)/rules/*.md") }).sorted()
    // #625：marketplace 與各 plugin 的 manifest（`marketplace-consistency` 讀它們）
    DATA += [".claude-plugin/marketplace.json"] + pluginRoots().map { "\($0)/\(pluginManifestRel)" }
    DATA += ["Sources/AkashicStoreIO/StoreVersion.swift", "Sources/AkashicCore/Venue.swift"]
    // repo 規則檔是 `measured-numbers-audit` 的輸入（#407 R48）。先前不在此列，於是
    // 那支守衛對 `.claude/rules/*.md` 的宣告**解析不到任何受保護檔**——宣告寫了卻等於
    // 沒寫，而既有的「有宣告但解析不到」只在**全部**宣告都落空時才報。
    DATA += globFiles(".claude/rules/*.md").sorted()
    // CLAUDE.md 是資料而非守衛：`decision-matrix-drift` 拿它的決策矩陣當輸入（#407 R27）。
    DATA += ["CLAUDE.md"]
    // #522：棘輪檔是 protected-ratchet 的輸入。**它自己也進清單**——那樣「棘輪檔被刪掉」
    // 除了 protected-ratchet 自己的 rc=2 之外，missing 檢查也會具名它。
    DATA += [".githooks/protected-ratchet.txt"]
    // 顯式條目與推導出的 manifest 會重疊（`plugin/.claude-plugin/plugin.json`）；保序去重
    var seen = Set<String>()
    DATA = DATA.filter { seen.insert($0).inserted }
    return (GUARDS, DATA)
}

/// glob 結果還原成真實的 repo 相對路徑並保序去重（#625）。經 symlink 才到達的檔以它的
/// 真實位置計一次。還原後落在 repo 外的（指向外部的 symlink）保留原路徑，不靜默丟棄。
func realRepoRelative(_ paths: [String]) -> [String] {
    let base = URL(fileURLWithPath: repoRoot).resolvingSymlinksInPath().path + "/"
    var seen = Set<String>(), out: [String] = []
    for p in paths {
        let real = URL(fileURLWithPath: "\(repoRoot)/\(p)").resolvingSymlinksInPath().path
        let rel = real.hasPrefix(base) ? String(real.dropFirst(base.count)) : p
        if seen.insert(rel).inserted { out.append(rel) }
    }
    return out
}
