## Why

取全文 skill 現在預設把每一步交給人：按這篇文章自己的 PDF 連結、存下分頁顯示的 PDF 都要等使用者，批次每一篇都停。使用者 2026-11-10 裁決改成預設由 Claude 做，只有封閉清單裡的情形交給人，2026-11-19 再次確認（#781、#780）。Claude 按的每一下要算進每站每天 10 次，而 skill 目前沒有可以記一次的命令。

## What Changes

- 新增 `akashic fulltext attempt --site <主機> --landing <網址>`：在與 `fulltext fetch` 共用的每日嘗試帳本上記一次。記到時結束碼 0、印 `attempt:` 一行；該站當天已滿時結束碼 9、印 `cap:` 一行、帳本不變；`--site` 不是乾淨的 DNS 主機名稱時結束碼 64、不建帳本。不碰瀏覽器、不連網、不寫 store。
- **BREAKING**（對 skill 的契約）：`akashic fulltext contract` 從 10 升到 11；SKILL 第 0 步要求 11。版本 11 的 CLI 才有 `attempt`。
- `akashic-fetch-fulltext` 的 SKILL 改寫人機分工：預設由 Claude 做；交給人只有封閉清單（人類驗證、登入、Safari 權限對話框與儲存面板、付費）與整批暫停；交給人的那一篇先跳過、整批跑完一次交給人；`pdf-shown` 改用 `safari-browser save-pdf`；Claude 以 `save-pdf` 取得的檔 acquisition 記成 `browser-save-pdf`。
- `references/publishers.md` 補 2026-11-10 與 2026-11-19 的實測。

## Non-Goals

- 不改 `fetch` 的結束碼 6／8 分類與已知驗證主機的清單（#819 另案，等使用者裁決）。
- 不讓 `fetch` 自己按頁面上的元件：點擊由 skill 以 safari-browser 做，CLI 只提供記帳。
- 不設每篇的點擊上限（使用者 2026-11-10 裁決：網站沒有起疑就可以），靠每站每天 10 次與中止條款。
- 不驗 `store-source` 的 acquisition 值：那個欄位是自由字串，新值只寫在 SKILL。
- 這次實作不對任何出版商網站送請求；實際站點的重跑由維護者在合併前手動做。

## Capabilities

### New Capabilities

- `fulltext-attempt-accounting`: 取全文的每站每日嘗試帳本對 skill 開放的記帳命令（`fulltext attempt`）與它和 `fetch` 共用同一本帳
- `fulltext-division-of-labour`: 取全文 skill 的人機分工：預設由 Claude 做、交給人的封閉清單、被取代的舊規定不得留在 SKILL

### Modified Capabilities

- `fulltext-gate-look`: 契約版本的 requirement 從 10 改成 11

## Impact

- Affected specs: fulltext-attempt-accounting（新）、fulltext-division-of-labour（新）、fulltext-gate-look（契約版本）
- Affected code:
  - Modified: Sources/akashic/FulltextCommands.swift, Sources/AkashicSkillTools/FulltextFetch.swift, Sources/akashic/WriteGateRulings.swift, docs/rulings/mcp-cli-parity.md, Tests/AkashicKitTests/FulltextLoginLookRulingsTests.swift, plugin/skills/akashic-fetch-fulltext/SKILL.md, plugin/skills/akashic-fetch-fulltext/references/publishers.md, plugin/CHANGELOG.md, plugin/.claude-plugin/plugin.json, .githooks/plugin-shell-versions.txt
  - New: Tests/AkashicCLITests/FulltextAttemptCLITests.swift, Tests/AkashicCLITests/FulltextDivisionOfLabourTests.swift, changelog/2026-11-19-fulltext-ai-default-781.md
