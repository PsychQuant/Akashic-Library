# 2026-09-28 venue／organization 的重複 key 以 error 出聲，讀取端不再因重複 key 崩潰（#669）

兩筆 venue（或兩筆 organization）持有同一個 key 時，store 沒有任何面報它：`crossRecordIssues` 只查 citekey 與 person key。讀取端的行為取決於它碰巧用哪一種字典建法：

- 以 `Dictionary(uniqueKeysWithValues:)` 建查找表的地方，重複的 key 讓 process **trap**（precondition failure，不是可捕捉的錯誤）：`export-bib`、`apa7Report`、CSL 匯出、Projection、attribute-org 的 org 表、migrate-identifiers 的 venue 表。匯出端連重複的 **person key** 也一樣會崩潰。
- 以 `uniquingKeysWith: { a, _ in a }` 建表的地方安靜地留第一筆，第一筆取決於檔案的列舉順序。

2026-09-28 實測 live store：venue 485、organization 13，同 kind 重複 key 0 組，是零實例的形狀。可達路徑：手改 YAML、合併兩份 clone、舊 binary、或 entities 佈局下兩個不同 UUID 的檔寫了同一個 key。

## 改了什麼

- **`crossRecordIssues` 對 venue key 與 organization key 的重複報 error**，與 citekey、person key 同級：key 是 `.key(…)` 參照、verdict holder 與每一個寫入面的定位依據。error 也讓改名與合併（`assertNoCrossRecordErrors`）先停下。三個面（CLI `validate`、MCP `akashic_doctor`、App）都走 `crossRecordIssues`，不必逐面接。不同 kind 共用一個 key 不算重複（live store 有 2 個 organization×venue 同 key）。
- **讀取端的查找表不 trap**：store key 的表改成留第一筆（`uniquingKeysWith: { first, _ in first }`）——選哪一筆是列舉順序、不是判定，validate 的 error 說明了它。
- **以 key 定位寫入的兩個面拒絕**：attribute-org（把 verdict 寫進那個 organization）與 migrate-identifiers（把 ISSN 搬進那個 venue）遇到重複 key 整批拒絕、零寫入，同 #627 對 citekey 的處置。
- **同一輪查到同形的第二個來源**：MCP／CLI 的 payload 以**消毒後**的字串當鍵，而 `displaySafe` 會截斷，所以不是單射。`enrich` 的 `provenanceOmitted` 自 #668 起收 `fields.<鍵>`：format 16 的 store 上兩個共用 80 字元前綴的欄位名，真 binary 報 `Fatal error: Duplicate values for key`、rc=133（#668 那一版）。同形的還有 `addedFields`、`residualFields`、`droppedColumns`、兩個 `writeFailed`。全部改成依原始鍵排序後留第一個，與 `fields` 既有的處置相同。**誠實邊界**：兩個鍵撞在一起時報告只列一個，這是顯示面的取捨，store 不受影響。
- **#581 的定址拒絕訊息改寫**。原本對 venue／organization 照實說「目前沒有跨記錄檢查報這個重複」；本輪之後那句話為假，改成一律指路 validate，測試同時斷言 validate 真的列出它。
- **守衛**：`DuplicateVenueOrgKeyTests.testNoStoreKeyLookupTableTrapsOnDuplicates` 掃 `Sources/`，`uniqueKeysWithValues` 的來源以 `$0.key`、`$0.citekey` 或 `displaySafe…` 當鍵即紅（多行寫法也算）。唯一留下的 `uniqueKeysWithValues` 是由生成器發、生成即唯一的 ref（註解寫著理由），它的鍵不是這三種。
- `zero-instance-guards` 加第 42 列，並把第 33 列的量測錨在「沒有對應的 venue 檔」上：新的重複訊息同樣以 `venue key「` 起頭，不錨的話會被數進懸空 venue key。`mcp-cli-parity` 的 attribute-org 與 migrate-identifiers 兩處加註。

**不在本輪**：其餘以 key 定位寫入 venue／organization 的面（resolve-venues／resolve-organizations 的 verdict 寫入、update-venue、venue 合併）仍安靜地留第一筆——它們不看跨記錄 error。比照 #627／#641 做「無法唯一定位」另案記 #670。

## 測試

- `DuplicateVenueOrgKeyTests`：重複的 venue／organization key 是跨記錄 error；不同 kind 共用 key 不報；`bibFile`、`apa7Report`、`cslJSON` 在重複的 person／organization／venue key 下跑完（trap 會讓整個 test process 崩潰，所以「跑完」就是通過）；源碼掃描守衛。
- `DuplicateKeyServiceTests`：attribute-org 對重複的 org key 整批拒絕、作者位不變；format 16 的 `enrich` 遇到兩個截斷後相撞的欄位名不崩潰。
- `PerRecordFullListingTests`：定址拒絕的訊息指路 validate，且 validate 真的列出那個重複。

負控：

- 在 `BibExport` 放回一處多行的 `uniqueKeysWithValues`：掃描守衛指名 `BibExport.swift:450`，變紅。
- 拿掉 venue 那一支跨記錄檢查：直接的測試與「訊息說 validate 會列出」那一條斷言一起變紅。
- `enrich` 的崩潰用真 binary 重現：#668 那一版 rc=133，本輪 rc=0、省略理由照常印出。
