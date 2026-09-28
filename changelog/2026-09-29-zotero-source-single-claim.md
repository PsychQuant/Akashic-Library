# 2026-09-29 同一個 Zotero 來源被多筆 entry 宣稱時，匯入不猜、doctor 報出來（#610）

匯入把 Zotero 條目對回 entry 的三張索引（主來源 composite、附加來源 composite、legacy 裸 key）都是「後寫覆蓋先寫」的字典。store 裡兩筆 entry 都宣稱同一個 `(library_id, zotero_key)` 時，路由安靜地只更新其中一筆：可能把這個條目的書目欄位寫進另一篇的記錄，另一筆則從此停在舊版。沒有任何地方說出這件事。

成因可以是手改、舊 binary，或 #607 修掉的 legacy 認領。2026-09-29 量測正式 store：2,563 筆 work、535 個 Zotero 來源（附加 3），被兩筆以上宣稱的 0 個、legacy 來源 0 個。

## 改了什麼

- `AkashicCore/ZoteroSourceClaims.swift`：來源鍵 → 宣稱它的 entry（主來源與附加來源都算、同一筆 entry 只算一次、沒記 `library_id` 的不算）。匯入端與跨記錄檢查用同一份定義。
- `ZoteroImporter.run`：來源被兩筆以上宣稱 → 本趟不更新任何一筆、不新建，列進新的報告欄位 `ambiguousSourceClaims`（來源鍵 → citekeys）。兩筆以上 legacy 舊檔宣稱同一個裸 key 同樣不認領、不新建，鍵寫成 `?:<zotero_key>`。
- `crossRecordIssues`：多筆宣稱是一則 warning（CLI `validate`／`doctor`、MCP `akashic_doctor`、App 都讀這份），排在 DOI／標題重複之前（MCP 只送前 20 則）。
- CLI `import-zotero` 與 MCP `akashic_import_zotero` 的報告印出 `ambiguousSourceClaims`（MCP 只在非空時出現，消毒後的鍵相撞時留第一個，#669 的處置）。
- `docs/store-format.md` §2.5.3 加一條「一個來源只能由一筆 entry 宣稱」。

## 測試與負控

`ZoteroSourceRoutingTests` 加 5 支：兩筆主來源同一個來源、一筆主來源一筆附加來源、兩筆 legacy 同裸 key（這三支修之前紅：其中一筆被改寫、報告為空）、跨記錄 warning（修之前紅）、同一筆 entry 的主來源與附加來源相同不算多筆（回歸防線）。

負控（反向編輯、`cmp` 確認還原）：路由的宣稱者門檻改成 >99 → 前兩支紅；legacy 的 `count == 1` 改成 `>= 1` → 第三支紅；宣稱者不以 entry 去重 → 最後一支紅。

## 誠實邊界

- 被多筆宣稱的來源，本趟連 orphan 標記的清除也不做（整個條目略過）；Zotero 端刪除時各筆的 orphan 標記照舊逐來源標上——那是關於來源的事實，不是路由選擇。
- 沒記 `library_id` 的舊檔與某個 library 的來源同裸 key 時不算多筆宣稱（歸屬不明，不是確定的重複），跨記錄檢查不報；匯入端照 #607 的規則不認領。
- 活著的 Zotero 來源沒有移除面：「其中一筆記錯了」的處置目前只能手改 YAML。
