# 2026-09-29「只有 hash 不同」改看 Zotero 的同步狀態、主來源也分出這一格；MCP 匯入報告的清單加上限（#608、#694、#696）

三張都在 Zotero 匯入報告上：#608 是 verify R1 的修正，#694 出自 #608 實作報告的誠實邊界，#696 出自 #684 實作報告的「沒做的事」。

## #608 verify R1：「version 沒變」不等於「沒有人改」

**問題**：#608 把附加來源的「hash 不同而 Zotero 的 `version` 沒動」另列一格（`secondarySourceHashOnly`），並說成「Zotero 端沒有人改這個條目」。但 Zotero 本機資料庫的 `items.version` 只在同步時才寫：

- 還沒同步的本機修改：`synced` = 0，`version` 不動；
- 從未同步的 library：每個條目的 `version` 都是 0。

這兩種都是內容變動，#608 之前在 `secondarySourceChanged`，#608 初版把它們報成「只有 hash 不同」。本 repo 自己早就寫著這件事：`docs/store-format.md` §2.5.2 說 hash 比對「同時抓到本機未同步修改」。

**改了什麼**：判準變成一份函式 `ZoteroImporter.isHashOnlyDifference`，四個條件都成立才算「只有 hash 不同」——有舊 hash 且與現在不同；Zotero 那一列說已同步（`items.synced` = 1）；`version` > 0；`version` 與存下的相同。其餘一律留在「有變動」那一格，包括資料庫沒有 `synced` 欄（無從判斷）。`ZoteroReader` 讀 `items.synced`（先用 `PRAGMA table_info` 確認有這一欄，沒有就是 nil），`ZoteroItem.synced` 不參與相等、不進 mapping hash、不存進 store。

說明改成只說觀察到的事實、不宣稱原因（多半是 mapping 定義演進，或子項附件增減）：`ImportReport` 註解、importer 註解、CLI 那一行、MCP 描述、store-format §2.5.3、`mcp-cli-parity` 的列（刪除線保留原句）、#608 的測試註解。

## #694：主來源的 `updated` 也分出這一格

主來源命中 update 條件時，同一份判準成立的列在新的 `updatedHashOnly`，其餘仍在 `updated`：

| 情形 | 報告 |
|---|---|
| 有舊 hash 且不同，已同步、version > 0 且沒變 | **`updatedHashOnly`（新）** |
| 同上但 `synced` = 0（本機修改還沒同步） | `updated` |
| `version` = 0（從未同步） | `updated` |
| 資料庫沒有 `synced` 欄 | `updated` |
| version 前進或倒退而 hash 不同 | `updated` |
| version 前進而 hash 相同 | `updated`（既有：照舊改寫） |
| 沒有舊 hash（pre-Phase-2） | `updated` |

**寫入不變**：主來源的 `updated` 所在的分支也決定要不要改寫書目欄位。分類放在那個分支裡、只決定寫入成功後 append 到哪一格。`testWriteIsIdenticalWhicheverBucketTheUpdateLandsIn` 用兩個 store 釘住：同一筆記錄、同一份 Zotero 內容，只差存下的 version，一份落在新格、一份落在 `updated`，兩份寫出的檔逐位元組相同，而且都真的改寫了（title 蓋回、手加的欄位被整份替換拿掉、未歸戶作者被覆寫），`fieldsRemovedByPull`／`authorsOverwritten` 等也相同。

MCP payload 多 `updatedHashOnly`（永遠在，與 `updated` 同形），CLI 非空時多一行；store-format §2.5.2 同步。

## #696：`akashic_import_zotero` 其餘清單在 MCP 面沒有上限

MCP 面每個 citekey 清單至多 20 筆（依 citekey 排序留前面的）：`created`、`updated`、`updatedHashOnly`、`orphaned`、`orphanCleared`、四個 `secondarySource*`、`unnormalizedDates`、`authorsPreserved`、`quarantineConflicts`、`writeFailed`（截的是條目數）。

- **揭露是一對鍵**：`listTotals`（清單名 → 完整筆數；十三個名字都在，空的是 0）與 `truncatedLists`（被截的清單名，排序；沒有截就是空陣列），兩個鍵永遠在，呼叫端不必猜「沒有鍵＝沒有截」。形照 `akashic_enrich` 的 `counts`（封閉列舉的名字 → 完整筆數）加截斷揭露。
- **不採 #684 的逐清單 `…Total`／`…Truncated`**：十三對鍵名都要寫進工具描述（`ToolPayloadKeyGuardTests`），會吃掉 tools/list 的位元組預算（#578）。`ambiguousSourceClaims` 維持 #684 自己的鍵，所以同一份 payload 裡有兩種揭露形狀——這是有意的取捨。
- 上限是 service `importZotero` 的 `listLimit`，由 server 傳入 `AkashicMCPServer.importListLimit` = 20；沒給＝全列；小於 1 在動 store 之前拒絕。上限只截報告、不截寫入；計數永遠完整；index rebuild 失敗時錯誤訊息裡的報告同一個上限。
- `residualFields` 不截：鍵是 Zotero 的欄位名，筆數受 schema 的欄位表限制，不隨一次匯入的筆數成長。
- CLI 不受此上限。

`tools/list` 從 48,150 位元組變成 48,357（預算 49,000）。

**不加零實例列**：`zero-instance-guards` 管的是當下零實例的形狀。這裡的形狀早有實例——一次首次匯入的 `created` 就是整個 Zotero library 的筆數（第 68 列記的唯讀量測：Zotero 來源 535 筆），mapping 定義演進時被改寫的主來源也是全部。第 68 列（`ambiguousSourceClaims`）量到的是 0，情況不同。

## 測試與負控

新增 23 支：`ZoteroImportTests` +12（主來源九種情形含寫入逐位元組相同；附加來源三種：還沒同步的本機修改、version 0、沒有 `synced` 欄）、`ImportZoteroReportSurfaceTests` +9（payload 的新格、每個清單的截斷／上限之內／沒給上限／空清單、`ImportReport` 集合欄位不是有上限就是具名理由、服務層只截報告、上限 < 1 拒絕、rebuild 失敗路徑同一個上限）、`ZoteroReportCLITests` +1、`StdioE2ETests` +1。#608 原有的三支「只有 hash 不同」測試加上 `synced` = 1（最小 fixture 沒有這一欄，現在讀成無從判斷）；`ZoteroFixture.setSynced` 在 item 都插入之後加欄。

**負控**（反向編輯、以備份逐位元組還原，全部轉紅）：判準回到 #608 初版（只看 version 相同）→ 7 支；不看 `synced` → 5 支；不看 `version` > 0 → 2 支；reader 不讀 `synced` → 7 支；新格永遠為空 → 7 支；新格那一格不改寫書目欄位／不更新 provenance／不寫入 → 各 2 支（都含寫入逐位元組相同）；清單不截 → 4 支；server 不傳 `listLimit` → 真 binary 那支；`listTotals` 報顯示的筆數 → 5 支；`writeFailed` 不截 → 1 支；沒有截時不給 `truncatedLists` → 3 支；`listLimit` < 1 不拒絕 → 1 支；截的不是排序後的前面 → 2 支；`ImportReport` 多一個沒有歸屬的清單欄位 → 1 支；描述漏掉 `truncatedLists` 或 `updatedHashOnly` → `ToolPayloadKeyGuardTests`。

## 沒做的事

- CLI 的既有差異沒動：`created` 只印筆數、`unnormalizedDates` 只印前 8 筆；`authorsOverwritten`／`fieldsRemovedByPull` 只在 CLI，MCP payload 沒有。
- 判準是觀察、不是證明：`synced` 與 `version` 是 Zotero 自己記的狀態，Akashic 不驗證它們。報告因此只說觀察到的事實、不宣稱原因。
- 沒有對照 Zotero 官方文件驗證 `synced`／`version` 的語意，依據是 verify 的發現與本 repo 的設計文件。
