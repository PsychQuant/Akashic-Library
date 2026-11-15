## Why

#777 列的四件取全文判斷，使用者 2026-11-11 裁決：Atypon 平台的 `/action/showLogin` 算登入頁長相；連 `document.contentType` 都讀不到的同站分頁，在 Cloudflare 挑戰或按住驗證的標記命中、路徑又有登入長相時整批暫停；另兩件維持現行行為。前兩件改變結束碼（8 → 6），要寫進規格並調契約版本。

## What Changes

- 網址的登入長相：路徑某一整段（去掉 `;` 之後的路徑參數與網頁副檔名、小寫）是 `showlogin` 時算登入頁。只給路徑用，主機標籤 `showlogin` 不算；較長 slug 裡的 `showlogin` 不算。
- 讀不到的同站分頁：驗證服務標記命中 `cloudflare-challenge` 或 `perimeterx-press-and-hold`，而網址路徑有登入長相時，整批暫停（結束碼 6，訊息帶 `(login page)`），不再等人驗證（8）。沒有標記時照舊不看路徑，交給人（7 `unverifiable`）。
- **BREAKING**（對 skill 的契約）：`akashic fulltext contract` 從 9 升到 10；SKILL 第 0 步要求 10。
- 第 3、4 件（PDF 連結路徑的 `auth`／`login`、主機標籤 `signon` 一族）程式不動，文件改成已裁決。

## Non-Goals

- 不把 `showlogin` 加進 `loginTokens` 或 `compoundLoginWords`：那兩份清單也給主機用，主機那一格使用者沒有裁過。
- 不讓讀不到的分頁在沒有驗證服務標記時看路徑：使用者 2026-10-02 的裁決保護 Safari PDF 檢視器的分頁。
- 不改其他四個驗證服務標記的處置（它們本來就是 6）。

## Capabilities

### New Capabilities

- `fulltext-gate-look`: 取全文命令對登入頁長相與讀不到分頁的判斷（本 change 只寫裁決改到的兩格與契約版本）

### Modified Capabilities

(none)

## Impact

- Affected specs: fulltext-gate-look（新）
- Affected code:
  - Modified: Sources/AkashicSkillTools/BotSignals.swift, Sources/AkashicSkillTools/FulltextFetch.swift, Tests/AkashicKitTests/FulltextB37Tests.swift, plugin/skills/akashic-fetch-fulltext/SKILL.md, plugin/CHANGELOG.md, plugin/.claude-plugin/plugin.json, changelog/2026-11-04-b49-fulltext-613.md
  - New: Tests/AkashicKitTests/FulltextLoginLookRulingsTests.swift
