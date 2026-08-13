## (a) 可能修改 store 的指令

none — 全程只用 `akashic query`（read-only，走 index）、`grep -r`（唯讀搜尋 entities 目錄）、以及 `Read` 工具讀取單一 yaml 檔案。未執行 `resolve-people --apply`、`bootstrap-people`、`rename`、`migrate`、`doctor`（會寫入/重建 index）或任何其他會寫入 store 的指令。

## (b) 對外網路查詢

none — 未使用 Crossref、Europe PMC、web search、WebFetch 或任何外部服務；所有資訊皆來自本地 store 的既有紀錄。
