## Why

#777 收尾時留下的五處散文與當時的事實沒有對齊（#777 verify 第 2、3 輪的 LOW／INFO，記在 #802）：規格 `fulltext-gate-look` 的三條 requirement 各有一句少寫或寫錯了既有行為，changelog 與 parity 文件各有措辭跟程式、跟同一列後面的裁決不一致。程式與測試的行為沒有錯，錯的是描述；讀規格的人會照錯的句子判斷。

## What Changes

- `fulltext-gate-look` 的 `An Atypon showLogin path segment SHALL have the look of a login page`：最後一句列出「導航之前判斷文章站上的 HTML 頁」的地方，原本只列 DOI 落地頁落定之後、讀文字時分頁變成的頁兩處，補上第三處：在文章站上 resume、導航之前。
- 同一份規格的 `An unreadable same-site tab with a human-check marker at a login path SHALL pause the run`：補一句既有的順序——標題或網址同時命中一個整批暫停的服務標記時，以那個標記整批暫停（exit 6），訊息是那個標記、不含 `(login page)`。
- 同一份規格的 `The fetch contract version SHALL be 10`：「Because two cells changed exit code」改成指這幾格（與程式裡 `contractVersion` 的逐格註解一致）。
- `changelog/2026-11-11-fulltext-login-look-rulings-777.md`：契約版本那一行「兩格的結束碼變了」改成「這幾格」；〈併入 main〉最後一句改成「沒有手動修改、main 帶進來的檔照原樣」。
- `docs/rulings/mcp-cli-parity.md` 的 `fulltext` 列：已裁決的「是否保留待使用者裁決（#777 第 4 件，#779 加註）」照該檔慣例劃掉並指向同列 #777 那一段的裁決。
- 新增一則 changelog 記這五處。

## Non-Goals

- 不改任何程式、測試、SKILL、plugin 殼；`fulltext-contract` 仍是 10，不升版。
- 不新增 scenario、Example 或 SHALL：補的兩句都描述既有行為。若要為「整批暫停的標記優先」加一個可執行的 Example，那是新的行為紀錄，不在這張的範圍內。
- 不改 `openspec/changes/archive/` 底下 #777 的封存檔（封存是歷史）。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `fulltext-gate-look`: 三條 requirement 的本文各改一句，既有 scenario 與 Example 原樣保留

## Impact

- Affected specs: fulltext-gate-look
- Affected code:
  - Modified: openspec/specs/fulltext-gate-look/spec.md（經 archive 併回）, changelog/2026-11-11-fulltext-login-look-rulings-777.md, docs/rulings/mcp-cli-parity.md
  - New: changelog/2026-11-16-fulltext-gate-look-wording-802.md
  - Removed: (none)
