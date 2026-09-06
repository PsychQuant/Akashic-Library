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
    ]

    /// 呼叫者有沒有指名目標 store。**只在真的要寫的時候呼叫**——dry-run 不得被擋
    /// （它不寫東西，而且正是使用者用來確認目標的手段）。
    ///
    /// 本函式**不查 CWD**、不改解析——它只判斷「呼叫者有沒有指名」。
    static func assertTargetNamed(command: String,
                                  explicitLibrary: String?,
                                  yes: Bool,
                                  resolved: URL) throws {
        // 正向寫法：指名了就通過。`guard ... else { return }` 的通過分支會是錯誤
        // 路徑，讀起來與慣例相反。
        if explicitLibrary != nil || yes { return }
        throw ValidationError("""
            \(command) --apply 拒絕執行：未指名目標 store。

            解析到的目標是：\(displaySafe(resolved.path, max: 800))
            （由 registry 的 current 決定，**與你目前所在的目錄無關**）

            確認這就是你要改的 store，則二擇一：
              --library \(displaySafe(resolved.path, max: 800))   顯式指定（推薦——同時消除歧義）
              --yes                                                知情地沿用 registry 解析

            先跑一次不帶 --apply 的 dry-run 可以看到會改什麼。
            """)
    }
}
