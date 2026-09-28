# 2026-09-28 `fields.<鍵>` 的來源 reference 補上 store format 17 的寫入閘（#668）

#517 讓 work 的 `references` 多了一格 `field: fields.<鍵名>`（`entity-backlink-completeness` 第 15 條邊）。那一格落地時**沒有自己的 store format 閘，也沒有 bump**：#517 早 format 17（#457）約 1.5 小時合進來，當時 `StoreVersion.supported` 前後都是 16。

所以存在一批「支援 format 16、但早於 #517」的 binary。它們的 `Entry.validateReferenceAttachment` 沒有 `fields.*` 這一格，封閉的 default 擲錯，那筆 work 被**整檔隔離**、rc=0。而新 binary 照樣把這一格寫進 format 13–16 的 store——與 16／17／18／20 各道閘要防的是同一個形狀。

live store 在 format 18（能讀它的 binary 都晚於 #517），不受影響；受影響的是停在 13–16、可能被舊 binary 讀到的其他 store。

## 改了什麼

- **寫入閘**：`LibraryStore.assertEntryWritable` 對 format < 17 拒寫帶 `fields.<鍵>` reference 的 entry，訊息說要升到幾（與 16／17／18／20 各道閘同形）。門檻是 17 不是 16：17 的每一個 binary 都晚於 #517。
- **門檻只有一份**：`StoreVersion.workFieldReferenceFormat = 17`，寫入閘與 `enrich` 的事前判斷共用（同 #655 的 `workDateReferenceFormat`）。
- **`enrich` 在寫入前讀 marker**，低於 17 時**值照補、reference 不寫、理由逐鍵進 `provenanceOmitted`**（鍵是 `fields.<鍵>`），不讓寫入閘在 apply 時擋下整筆——那會連同值一起 `writeFailed`，dry-run 還說「會寫」。這是 #655 對 `date` 已經定下的做法，兩格同形。`AddOnlyEnrichment.DateReferenceCell` 因此改名 `ReferenceCell`、`plan` 多一個 `fieldsReference` 參數。
- MCP `akashic_enrich` 的描述與 CLI `enrich --from` 的說明同步寫出兩個門檻；`StoreVersion` 的 17 那一條與 `docs/store-format.md` 的 17、20 兩列、第 15 條邊的 `fields.<鍵>` 列一起更新（20 那一列原本寫著「這一格至今沒有自己的閘，另案」）。

**不做資料遷移**：這一格在 format 13–16 的 store 裡若已經寫進去，舊 binary 早就讀不到它，新 binary 照常讀。live store 在 18，零 diff。

## 測試

- `WorkFieldReferenceFormatGateTests`：門檻是 17 且在 `supported` 之內；format 16 拒寫、訊息帶門檻常數、零副作用；format 16 照收識別碼的來源 reference（#394 的門檻不變）；format 17 寫得進去也讀得回來。
- `EnrichmentFieldsReferenceCellTests`：收不下時值照補、每個鍵各自具名省略、`date` 那一格不受影響；預設 `.writable` 與 #668 之前相同。
- `EnrichFieldsReferenceFormatServiceTests`：format 16 的 dry-run 不說「會寫」、理由帶 format 與門檻，apply 值照補、沒有 writeFailed、store 裡沒有 reference；format 17 照常寫。
