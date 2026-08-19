## Why

**2026-08-16 00:40（+08:00）發生過一次真實事故**：驗證 agent 在 scratch 目錄下執行無
`--library` 的 `migrate-person-identity --apply`，`LibraryLocator.resolveDetailed()`
對 CWD **零感知**、循 registry 的 `current` 解析到真 store `~/.akashic`——**867 個
person 檔被改名重發 id**。因真 store 是乾淨的 git worktree 而完全可逆，已依裁決還原。

根因是設計層的，且診斷確認並**強化**了它：`resolveDetailed` 的輸入面只有
`{explicit, environment, configURL}`，CWD 在結構上**無法**影響解析——不是漏了分支。

診斷另指出兩個根因：

- **程式碼零 destructive marker**——38 個 subcommand 在型別層完全等價，沒有任何東西
  知道哪些是不可逆的
- **即時緩解的覆蓋率是 2/6**——六個 `--apply` 點只有兩個有目標回顯，其餘連可見性都沒有

## What Changes

破壞性 CLI subcommand 的 `--apply` 在**未顯式指定目標 store** 時**拒絕執行**，並在拒絕
訊息中回顯它**實際**會改的那個 store。

拒絕不是終點——訊息給兩條顯式出路：指定 `--library <path>`（推薦），或 `--yes` 表示
知情地沿用 registry 解析。

「破壞性」是**封閉列舉**，不是判準：型別層沒有這個概念，所以必須逐一點名。

## Non-Goals

- **不加 CWD 感知層**（`## Expected` 的方向 (b)）。見下方 Alternatives——它**無法防止
  本 issue 具名的那次事故**。
- **不擋 MCP 面**。破壞性遷移全是 CLI-only；`resolve-people`／`resolve-organizations`
  雖有 MCP 面，但那一面是**逐 id 顯式指名**而非篩選式批次掃蕩——與 parity 表已記錄的
  tier 閘同型不對稱。
- **不改 `LibraryLocator` 的解析語意**。#105 的既有裁決（`--library` 是「指定一個 store」
  不是「繞過 registry」）不動。
- **不擋非破壞性命令**。`validate`／`query`／`doctor` 讀錯 store 的代價是看到錯的答案，
  不是改壞資料。

## Alternatives Considered

**(b) registry 解析加 CWD 感知層** —— **被事故本身否決**。

事故發生在 **scratch 目錄**，而 scratch 目錄**不在任何已註冊的 store 內**。CWD 感知層
在這種情況下找不到 store、只能退回 registry 解析——也就是**行為與現況完全相同，事故
照樣發生**。

一個防不了具名事故的方案不該被選。它另外還要推翻 #105 的既有裁決，代價更高而收益是零。

**(c) 單獨採用（只回顯 + `--yes`）** —— 比現況好，但**回顯不是同意閘**。issue 的
`## Actual` 已記錄即時緩解就是回顯，而事故正是在有回顯的那個命令上發生的（緩解上線於
事故之後）。所以 (c) 併入 (a) 作為訊息內容，不單獨採用。

## Capabilities

### New Capabilities

- `destructive-store-target`: 破壞性操作的目標 store 必須被顯式確認，且拒絕訊息必須
  回顯實際解析到的目標

### Modified Capabilities

(none)

## Impact

- Affected specs: `destructive-store-target`
- Affected code:
  - New: `Sources/akashic/DestructiveTargetGate.swift`
  - New: `Tests/AkashicCLITests/DestructiveTargetGateTests.swift`
  - Modified: `Sources/akashic/CLI.swift`
  - Modified: `Sources/akashic/Commands.swift`
  - Modified: `Sources/akashic/VenueCommand.swift`
