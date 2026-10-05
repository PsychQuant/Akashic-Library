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
/// 過閘的命令裡有好幾個也有 MCP 面（`resolve-people`、`resolve-venues`、`resolve-organizations`、
/// `import-zotero`、`enrich`……）。#310 裁決記載「MCP 面的 active store 是 session 狀態，『本次呼叫有沒有
/// 顯式指定』恆為否」——以「有沒有指名」為判準的閘在 MCP 面只會退化成一律擋或一律放，所以不作用於 MCP。
///
/// 這一段先前的理由是「CLI 的 `--apply` 是篩選式批次掃蕩、MCP 收逐 id 清單」；#580 把逐 id 的
/// `resolve-venues`／`enrich` 也放進閘之後那個理由不再成立（`mcp-cli-parity` 的 `--yes` 列同批更正過），
/// 留下的是上面那一條：閘防的寫錯 store，只在 CLI 那一面有「每次呼叫重新解析」的形狀。
enum DestructiveTargetGate {

    // ## 哪些命令過閘（#298 D3 → #658）
    //
    // **不得用名字猜。** 型別層零 destructive marker，任何模式規則都會在邊界上出錯：`rename` 與
    // `resolve-divergence` 都不以 `migrate` 開頭，卻同樣不可逆。所以過閘的集合是一張封閉的裁決表——
    // `WriteGateRulings.swift` 的 `commandRulings`（CLI 每一個葉命令一格）與 `legRulings`（三個逐腿命令的
    // 每一條腿一格），`destructiveCommands` 由它現算。#658 之前這裡是一份手寫的 `destructiveCommands`，
    // 它只列過閘的命令，不閘的理由散在各處（#580 R1 寫過「不閘的只有一類」，當場被找到六個反例），
    // 而稽核只認布林的 `--apply`／`--reject`——預設就寫的命令與逐 id 的寫入腿長出來時它看不到。
    //
    // 本閘防的是**寫錯 store**（#298：呼叫者以為自己在 scratch），不是寫錯哪幾筆——從錯的 store 列出來的
    // id 在錯的 store 上全部對得上，所以逐 id 的寫入腿同樣受它保護（#580）。各格的觸發條件由命令自己決定：
    // 多數是布林 `--apply`；預設就寫的（migrate 族、`resolve-divergence`）在不帶 `--dry-run` 時；沒有乾跑的
    // （`rename`、`rename-person`、`import-zotero`）無條件；逐腿的是那一條腿。
    //
    // 表外（`.notGated`）的每一格都寫著自己的理由（#653：只閘使用者點名的不可逆寫入；#658：
    // `resolve-people --drop-author` 與 `import-zotero` 自 2026-09-28 起過閘）。新增命令或新腿要在表裡加一格，
    // `WriteGateRulingsTests` 與 `DestructiveTargetGateTests` 會紅。

    /// 呼叫者有沒有指名目標 store。**只在真的要寫的時候呼叫**——dry-run 不得被擋
    /// （它不寫東西，而且正是使用者用來確認目標的手段）。
    ///
    /// 本函式**不查 CWD**、不改解析——它只判斷「呼叫者有沒有指名」。
    static func assertTargetNamed(command: String,
                                  flag: String = "--apply",
                                  hasDryRun: Bool = true,
                                  dryRunFlag: String? = nil,
                                  noPreviewHint: String? = nil,
                                  explicitLibrary: String?,
                                  yes: Bool,
                                  resolved: URL) throws {
        // 正向寫法：指名了就通過。`guard ... else { return }` 的通過分支會是錯誤
        // 路徑，讀起來與慣例相反。
        if explicitLibrary != nil || yes { return }
        // 旗標名與預覽提示依呼叫端而定（#580 R2 verify）：逐 id 的寫入腿與 rename-person 沒有 dry-run，
        // 叫人「先跑 dry-run」是假話。rename-person 沒有旗標可掛，flag 傳空字串。
        let invocation = flag.isEmpty ? command : command + " " + flag
        // 預設就寫、以 `--dry-run` 預覽的命令（migrate 族、resolve-divergence，#653）：提示要說「加」那個旗標，不是「不帶」寫入旗標
        // `noPreviewHint`：沒有乾跑、也沒有「不帶寫入旗標只列候選」模式的寫入腿自己說怎麼辦（update-organization --remove-name，#564 b33 X1）
        let previewHint = dryRunFlag.map { "加 " + $0 + " 可以先看到會改什麼。" } ?? noPreviewHint
            ?? (hasDryRun
                ? "先跑一次不帶 " + flag + " 的 dry-run 可以看到會改什麼。"
                : flag.isEmpty
                    // 沒有寫入旗標也沒有乾跑（rename／rename-person）：再跑一次就是整批改寫（#653 R1 verify 第 17 列）
                    ? "這個命令沒有 dry-run，也沒有只列候選的模式——指名之後就會直接改寫；要先看影響範圍，在 store 的副本上跑。"
                    : "這個寫入沒有 dry-run；不帶寫入旗標執行只會列出候選，不預覽這次會改什麼。")
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
