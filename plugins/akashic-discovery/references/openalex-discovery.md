# 共用 OpenAlex 查詢與 bootstrap 交接

## 取得與身分

載入 [web-access](acquisition/web-access.md) 的 Safari profile、鎖定、節奏、HTTP 狀態、
內容檢查及中止程序。引用端點只是資料位址，不是改用 curl 的許可。先確認使用者 profile，
不能猜。此共用檔供 discovery skills 使用；往回 skill 的雙來源判定仍由其自身契約規範。

以 DOI 解析種子：`https://api.openalex.org/works/https://doi.org/<已編碼DOI>`，核對
回應 DOI、標題、作者及年份，再採用 `id`。任一不一致就停；404 是查無，不是零筆被引。

`cites:W1,cites:W2` 是交集；`cites:W1|W2` 是聯集。`from_publication_date` 與
`to_publication_date` 是出版日期的含端點篩選，不是引用發生日期。`meta.count` 是當次
**整個篩選查詢**的總筆數，與回傳陣列長度、種子或候選的 `cited_by_count` 不同。
不使用 `referenced_works.id:`；候選回應的 `referenced_works` 用來再核對引用方向。

每次觀測保留查詢、時間、頁數與當次 count。索引會更新；2026-09-24 issue 的數字及
2026-10-29 留言數字只屬於各自當時的觀測，不是測試預期值，也不能直接相減當成新增論文數。

## 分頁與額度

預設 `page` 模式是有限候選搜尋；每頁至多 100、page × per_page ≤ 10,000。
不為取得總數而掃完整個集合。總數模式只取 per_page=1，丟掉其中那筆候選。
`--paging cursor` 才用 `cursor=*` 和 API 回傳的 next_cursor；後續頁需要 API key。

OpenAlex API key 與 mailto 不等價，mailto 不增加額度。不要在聊天、命令列、URL、
query/report JSON、Git、截圖或瀏覽器紀錄中放 key。現有 Akashic 安全憑證介面只供 S2，
不能挪來存 OpenAlex key。**本版不提供 OpenAlex 金鑰管理或自動帶 key**；通常用 page 模式。
只有使用者已提供符合專案規則、且不暴露金鑰的取得介面時才選 cursor；否則不啟用。

401、403、429、非 JSON、逾時或無法核對身分時停下；不得改分頁方式或換來源繞過。
回報已成功取得的頁數與候選，標示不完整。不要自動申請 key、寄驗證信、付費或重試耗盡額度。
若取得介面可讀剩餘額度與 reset，先看；無資訊時說未知，不推算固定免費次數。

## 選取後的交接

1. 在對話中保留使用者明確選取的穩定 W ID 與它對應的 report；分頁或重新排序後不能用舊列號猜。
2. 把**選取的**候選 DOI／書目資料交給 `akashic-bootstrap`，由它驗證身分、來源、DOI 與庫內重複。
   `storeStatus` 只是快照提名；`doi-conflict`、`incomplete-store-scan` 必須先釐清，不能擅選 citekey。
   缺 DOI 不直接略過或自動建立：沿用 bootstrap 無 DOI 的身分驗證，證據不足就列為待處理。
3. 種子若尚未在庫中，先告知「建立引用關係還需要哪些種子」，取得使用者明確選取後才交 bootstrap；
   本輪選候選不等於同意建種子。未獲選取只完成已授權的候選建檔，不寫無效關係。
4. 重新核對候選與種子的身分，以及候選的 referenced_works 命中集合。只有 OpenAlex 索引支持的連結
   要標為該索引的證據，不宣稱讀過全文。來源衝突時停下，先查候選全文或權威書目證據。
5. 使用既有 `akashic_link` 寫 `cites`：**候選 citekey → 已驗證且存在的種子 citekey**。
   聯集只連 `citedSeeds` 中實際命中的種子。依工具即時 schema 提供參數；不得自行編造 evidence 欄位。
6. 每筆回報建檔、既有、連結成功或失敗；部分失敗不宣稱整批完成。不自動掛 library 或擴展參考文獻。

## 官方參考（2026-11-01 查核）

- https://help.openalex.org/api/filtering/
- https://help.openalex.org/api/paging/
- https://help.openalex.org/api/authentication/

文件查核不等於 live API 實測；實測狀態記在本次 change 的驗證紀錄。
