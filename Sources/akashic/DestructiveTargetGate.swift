import ArgumentParser
import Foundation
import AkashicCore

/// 破壞性寫入的目標 store 必須被呼叫者指名（#298）。
///
/// ## 事故（2026-08-16 00:40 +08:00）
///
/// 驗證 agent 在 **scratch 目錄**下執行無 `--library` 的
/// `migrate-person-identity --apply`，`LibraryLocator.resolveDetailed()` 對 CWD
/// **零感知**、循 registry 的 `current` 解析到真 store `~/.akashic`——**867 個 person
/// 檔被改名重發 id**。因真 store 是乾淨的 git worktree 而完全可逆。
///
/// 事故的核心不是「解析錯了」——解析完全按設計。核心是**呼叫者以為自己在 scratch，
/// 其實在真 store**，而沒有任何東西告訴他。
///
/// ## 為什麼是「拒絕」而不是「CWD 感知」
///
/// issue 的 Expected 給了三個方向。判準不是「哪個比較好」而是**哪個防得住已經發生過
/// 的那次**：
///
/// | 方向 | 對該事故 |
/// |---|---|
/// | 無顯式目標即拒絕（本檔）| **防得住** |
/// | CWD 感知層 | **防不住**——事故發生在 scratch 目錄，而它不在任何已註冊 store 內；CWD 感知找不到 store 只能退回 registry，行為與現況相同 |
/// | 只回顯 + `--yes` | **防不住**——即時緩解就是回顯，而**回顯不是同意閘** |
///
/// 回顯仍然重要，但它的位置是**拒絕訊息裡**——那是事故最缺的東西（「你以為的目標」
/// 與「實際的目標」在那一刻才會對上）。
///
/// ## 只擋 CLI，不擋 MCP（面不對稱，有先例）
///
/// 六個命令裡 `resolve-people` / `resolve-organizations` 有 MCP 面。#310 裁決記載
/// 「MCP 面的 active store 是 session 狀態，『本次呼叫有沒有顯式指定』恆為否」——但那
/// 個約束**只在閘門要作用於 MCP 時才綁**。
///
/// 本閘門不作用於 MCP，理由不是規避而是**兩面的動作形狀不同**：CLI 的 `--apply` 是
/// **篩選式批次掃蕩**（`--holder` / `--org` 收窄，其餘全掃），MCP 的 apply 收**逐 id
/// 顯式指名**的清單。
///
/// `mcp-cli-parity` 對**同一組命令**已記錄同型的不對稱：「tier 閘只在 CLI 篩選式批次
/// （MCP per-id 顯式＋tier 可見，刻意不閘）」。所以這不是臨時挖的洞，是已裁決過的
/// 形狀再次適用。
enum DestructiveTargetGate {

    /// 破壞性 CLI 命令的**封閉列舉**（#298 D3）。
    ///
    /// **不得用名字猜。** 型別層零 destructive marker——38 個 subcommand 完全等價，
    /// 而任何模式規則都會在邊界上出錯：`rename` 與 `resolve-divergence` 都不以
    /// `migrate` 開頭，卻同樣不可逆。
    ///
    /// 新增會改寫或刪除記錄的命令時**必須在同一個變更裡加進這裡**。
    /// `DestructiveTargetGateTests` 的雙向機械稽核接住漏網的。
    ///
    /// ## 本表是什麼、不是什麼（#580）
    ///
    /// 本表是**會呼叫本閘的命令**的清單，不是「會寫 store 的命令」的清單。閘防的是**寫錯 store**
    /// （#298：呼叫者以為自己在 scratch），而不是寫錯哪幾筆——從錯的 store 列出來的 id 在錯的
    /// store 上全部對得上，所以逐 id 指名的寫入腿同樣受它保護（`enrich`／`enrich-from-zotero`／
    /// `resolve-venues` 都是逐 id 的，都在表內）。各成員的觸發條件由命令自己決定：多數是布林
    /// `--apply`；`resolve-organizations` 另含篩選式 `--reject` 與逐 id 的 `--undecided`（R2 verify）；`resolve-venues` 是任一寫入腿。
    ///
    /// **表外仍有會寫 store 的命令沒有閘**，而且不是一類：預設就寫的（`fmt`、`migrate`、
    /// `migrate-provenance`、`import-wos`、`import-zotero`、`create-entry`……）、`resolve-people`
    /// 的逐 id 腿（`--reject`／`--judge`／`--split-author`……）、`resolve-divergence`、`rename`
    /// （`rename-person` 無條件呼叫本閘）。它們要不要閘**沒有逐一裁決過**——清單與裁決記在 #653／#650，
    /// 本段刻意不寫成封閉列舉：上一版寫了「不閘的只有一類」，#580 R1 verify 當場找到六個反例。
    ///
    /// 稽核（`DestructiveTargetGateTests`）認得布林旗標的兩種宣告寫法：省略型別與寫出 `: Bool`
    /// （`authorize-names` 曾因後者漏網）。這段 doc 不逐字寫出宣告——稽核以字面比對，會把 doc 當成命令。
    static let destructiveCommands: Set<String> = [
        // #394：識別碼自 fields 升格、work 的 issn 移位至 venue——改寫既有記錄。
        "migrate-identifiers",
        "migrate-person-identity",
        "migrate-venues", "migrate-venue-variants",
        "bootstrap-people",
        "bootstrap-organizations",
        "bootstrap-venues",
        "resolve-people",
        "resolve-organizations",
        "enrich-from-zotero",
        // #458：generic add-only 補值——只加不存在的鍵，但它仍改寫既有記錄檔；閘的成本是一行。
        "enrich",
        // #580：逐 id 的寫入腿（apply／reject／repoint／demote／undecided），比照 enrich
        "resolve-venues",
        // #580 R1 verify：全庫掃蕩的布林 --apply，先前因宣告寫成 `: Bool` 而漏在稽核之外
        "authorize-names",
    ]

    /// 呼叫者有沒有指名目標 store。**只在真的要寫的時候呼叫**——dry-run 不得被擋
    /// （它不寫東西，而且正是使用者用來確認目標的手段）。
    ///
    /// 本函式**不查 CWD**、不改解析——它只判斷「呼叫者有沒有指名」。
    static func assertTargetNamed(command: String,
                                  flag: String = "--apply",
                                  hasDryRun: Bool = true,
                                  explicitLibrary: String?,
                                  yes: Bool,
                                  resolved: URL) throws {
        // 正向寫法：指名了就通過。`guard ... else { return }` 的通過分支會是錯誤
        // 路徑，讀起來與慣例相反。
        if explicitLibrary != nil || yes { return }
        // 旗標名與預覽提示依呼叫端而定（#580 R2 verify）：逐 id 的寫入腿與 rename-person 沒有 dry-run，
        // 叫人「先跑 dry-run」是假話。rename-person 沒有旗標可掛，flag 傳空字串。
        let invocation = flag.isEmpty ? command : command + " " + flag
        let previewHint = hasDryRun
            ? "先跑一次不帶 " + flag + " 的 dry-run 可以看到會改什麼。"
            : "這個寫入沒有 dry-run；不帶寫入旗標執行只會列出候選，不預覽這次會改什麼。"
        // 這一行的路徑用性質式逃脫（R31；R30 verify 第 24 列）——R30 曾改回列舉式 `displaySafe`，理由是「貼回去就是那個目錄」，但列舉式也給不了
        // 這件事（反斜線、C0、bidi 照逃），而它放行的正是讓兩個路徑肉眼不可分的那一類字元（ZWSP／NBSP／變體選擇子）；訊息的職責是
        // 「確認這就是你要改的 store」，可辨識比可貼上重要。含這類字元的路徑要顯式指定時，請照 `解析到的目標是：` 那一行的 `\u{…}` 形自己還原（R31 verify 第 27 列）。
        throw ValidationError("""
            \(invocation) 拒絕執行：未指名目標 store。

            解析到的目標是：\(displaySafeInvisible(resolved.path, max: 800))
            （由 registry 的 current 決定，**與你目前所在的目錄無關**）

            確認這就是你要改的 store，則二擇一：
              --library \(displaySafeInvisible(resolved.path, max: 800))   顯式指定（推薦——同時消除歧義）
              --yes                                                知情地沿用 registry 解析

            \(previewHint)
            """)
    }
}
