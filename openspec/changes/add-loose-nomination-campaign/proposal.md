## Why

literal 歸零 campaign（#303）的終局已裁定（#304：全 entity 域、字面歸零），但實測 `resolve-people` 現況**零候選**——2,123 個 literal 作者邊沒有任何一個與既有 alias 完全命中（exact 面已被 8/14 的 37 筆收完）。「Yung-Fong Hsu」×18 收不進「Hsu, Yung-Fong」的記錄：正規化吸收大小寫／連字號／空白，但不重排 token、不比縮寫。沒有寬鬆提名層，campaign 的每個異形都要先人工補 alias 才有 apply 把手；同時 campaign 本身缺「以 literal 歸零為目標」的編排層（census、分批、每輪進度）。使用者於 idd-plan（2026-08-16）拍板 B 案：resolver 增寬鬆提名 tier，campaign skill 層併同一 change。

## What Changes

- `PersonResolver.resolve` 增**寬鬆提名 tier**（封閉兩類）：L1 token 重排（`Hsu, Yung-Fong` ↔ `Yung-Fong Hsu`）、L2 姓＋首字母（`C-H Chen`；姓前／姓後兩種解讀都生鍵，不猜姓氏位置）。只提名不 apply——絕不自動合併鐵律不動
- 候選回報新增 `tier` 欄（`exact`／`confirmed-elsewhere`／`reorder`／`initials`，信心降冪排序）；單一 candidates 列，L2 命中照樣可 apply（防線在 campaign 查證紀律＋tier 可見性）。多命中照舊落 `AmbiguousMatch`
- `resolve` 增吃 `confirmed: Set<ResolutionPairing>`（鏡像既有 `rejected`，刻意必填）：同 literal 已在他處 confirmed → `confirmed-elsewhere` tier 提名。查證知識持久化走 verdict、不寫 alias（`ResolutionLedger` 增 `confirmedPairings`）
- 寬鬆鍵生成器（`LooseNameKey`）與 `NameNormalization` 並列住 AkashicCore——resolver 與 bootstrap 共用單一定義（#140 分岔血案的既定防線）
- CLI `resolve-people`／MCP `akashic_resolve_people`／App Adjudication 面同步帶 `tier`（additive）
- 新 plugin skill `akashic-literal-campaign`：三域 census（author／venue／affiliation 的 literal 計數，附 `scripts/literal-census.sh`）→ 按批 TaskCreate → 驅動「查證 → resolve → apply」管線 → 每輪計數落一筆 #303 comment
- person-resolution 契約首次成文為 spec（`openspec/specs/` 目前無此 capability）

## Non-Goals

- **CJK 羅馬化異拼**（Hsu↔Xu）明確排除——查表域、失效模式不同；重啟需新裁決
- **Venue／Org resolver 不加寬鬆 tier**——venue 異形是縮寫刊名（查證域，`akashic-venue-verify` 涵蓋），token 重排對刊名無意義；org 域只剩 1 個 literal
- **apply 不寫 alias**——otherwise-recorded 原則（authorized-name spec）下 alias 寫入是 bootstrap 的顯式動作，不是 apply 的副作用
- **campaign 各輪的實際執行**（R1 高頻批、R2 統計所批、R3+ 長尾建檔）不在本 change——那是 skill 落地後由使用者驅動的持續工作
- venue 域 census 依賴 format 11 部署（venue change 的部署鏈），本 change 不含部署

## Capabilities

### New Capabilities

- `person-resolution`: literal 作者的提名／apply／verdict 契約——exact 與寬鬆 tier 的封閉列舉、tier 欄位語意、confirmed-elsewhere 的 verdict 消費、歧義回報、絕不自動合併

### Modified Capabilities

(none)

## Impact

- Affected specs: `person-resolution`（新）
- Affected code:
  - New: `Sources/AkashicCore/LooseNameKey.swift`、`plugin/skills/akashic-literal-campaign/SKILL.md`、`plugin/skills/akashic-literal-campaign/scripts/literal-census.sh`、`Tests/AkashicKitTests/LooseNameKeyTests.swift`、`Tests/AkashicKitTests/PersonResolverTests.swift`（tier 案例新檔；既有 resolver 測試住 EntityTests）
  - Modified: `Sources/AkashicEntity/PersonResolver.swift`、`Sources/AkashicEntity/ResolutionLedger.swift`、`Sources/AkashicMCPKit/AkashicService.swift`、`Sources/akashic-mcp/Server.swift`、`Sources/akashic/CLI.swift`（resolve-people 輸出）、`Sources/AkashicAppKit/Adjudication.swift`（候選列 tier 標示）、`Tests/AkashicKitTests/EntityTests.swift`（resolve 簽名改動的既有守衛）、`Tests/AkashicKitTests/ResolutionLedgerTests.swift`、`Tests/AkashicKitTests/AdjudicationTests.swift`、`plugin/CHANGELOG.md`、`.claude/rules/mcp-cli-parity.md`（契約差異列更新）
  - Removed: (none)
