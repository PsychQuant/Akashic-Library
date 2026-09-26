# 2026-09-27 enrich 的來源行不再把計畫說成已發生（#542）

#542 的前兩項已在 2026-09-09 的 `8d965fc1`（PR #545）落地：payload 帶 `provenanceWritten`／`provenanceSkipped`，CLI 由 payload 現算那一行。但 issue 上沒有留下紀錄，第三項（釘住「CLI 那一行不得與 payload 矛盾」的測試）也沒有做。

補那支測試時，它第一次跑就抓到同一個病的反方向：
- **dry-run** 什麼都沒寫，payload 卻照樣帶 `provenanceWritten`（那是計畫值），CLI 因此印「已寫入 1 筆 reference」；
- `--apply` 而那一筆寫入失敗時，同樣會宣稱寫了。

#542 修的是「寫了卻說沒寫」，這裡是「沒寫卻說寫了」。

- payload 的鍵名本身說出事實，三種狀態三個鍵：
  - `provenancePlanned`：dry-run，`--apply` 時會寫；
  - `provenanceWritten`：`--apply` 且那一筆真的寫入；
  - `provenanceNotWritten`：`--apply` 但那一筆寫入失敗。

  消費端不必自己拿 `dryRun` 與 `writeFailed` 交叉推論。MCP 面同一個 payload，兩面同源。
- CLI 各印一種句子。原本「寫入與否於 --apply 時回報」那個分支已經到不了，改成「沒有補任何值，所以沒有 reference」。這是真的會發生的第四種情況：有 digest 但這筆沒有要補的欄位。
- 測試：`EnrichCLITests.testSourceLineAgreesWithPayload`（真 binary），涵蓋以下情形：
  - dry-run 的 CLI 行不得出現「已寫入」，payload 不帶 `provenanceWritten`、帶 `provenancePlanned`；
  - `--apply` 時 payload 的 `provenanceWritten` 與 store 裡真的有的 reference 相符；
  - 只有 digest 時印具名理由。
- 誠實邊界：`provenanceNotWritten` 那一格沒有專屬測試，要造出單筆寫入失敗需要注入 I/O 錯誤。
