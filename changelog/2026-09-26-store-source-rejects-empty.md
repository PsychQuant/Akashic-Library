# 2026-09-26 store-source 拒收 0 byte 的內容（#546）

`store-source` 原本對 0 byte 的檔照收不誤，鑄出空字串的 SHA-256（`sha256:e3b0c442…`）。這個 digest 是常數，任何空輸入都得到它，因此：
- 兩次不同的失敗抓取會折成同一筆存檔，而內容定址的去重讓它看起來只是「已經存過了」；
- 拿它當 `sourceDigest` 的 retrieval reference 會指向一份空的「證據」，store 卻把它和真的存檔一視同仁。

實例（2026-09-09）：`open(path,'wb').write(fetch(url))` 先截斷再抓取，HTTP 429 時留下空檔，下一輪以為抓過了。

- `SourceStore.storeSource` 在任何磁碟寫入之前擋下空內容：整個拒絕、零寫入，錯誤說出「0 byte」並提示重新取得。與 #519 的上界同型。
- 閘放在 store 層，所以 CLI `store-source`、MCP `akashic_store_source` 與日後的呼叫端都經過它。
- 範圍只到入口。live store 既有的 1 個空 blob 與它的索引列沒有任何記錄引用，要清掉它需要一個「移除一筆存檔」的面，而那個面還不存在（與 #544 同族）。
- 測試：`SourceStoreTests.testStoreSourceRefusesEmptyContent`，驗證會拋錯、不留 blob、不留 index 條目，而 1 byte 照收。實作前先跑過，三個斷言都失敗。

## R1 verify 之後

- 錯誤訊息點名是哪個檔（三席）：批次存檔時只說「0 byte」查不下去。服務層在呼叫 store 之前先檢查並點名路徑；真正的閘仍在 `SourceStore.storeSource`，所有呼叫端都經過它。
- changelog 列出的第二個危害（retrieval reference 指向空 digest）入口閘沒有涵蓋：`enrich` 的 `sourceDigest` 仍收 `sha256:e3b0…`。live store 0 筆，記在 #654。
