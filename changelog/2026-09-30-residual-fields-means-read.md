# 2026-09-30 import-zotero 的 residualFields 說的是「讀到的」（#704）

`residualFields` 的計數發生在讀進每一個 Zotero 條目時，不論這一趟有沒有寫（沒變動、被多筆宣稱而略過、寫入失敗的條目都算）。但它的說明寫的是寫入的事：MCP 描述是「未映射欄位→次數」，CLI 印「已以原名入庫」，`docs/store-format.md` 還停在 #206 之前的說法（「不入庫」、`dropped fields`）。對寫入失敗的那一筆，「入庫」不成立。

使用者 2026-09-30 裁決 (a)：計數照舊，說明改成「這次讀到的條目」。沒有變動的條目，這些欄位本來就在 store 裡，照算不會誤導；只計寫入成功的條目（b）會連沒變動的一起掉出去。

## 改了什麼

- MCP `akashic_import_zotero` 描述：`residualFields（這次讀到的條目中未映射的欄位→條目數）`。
- CLI：`residual fields（這次讀到的條目中無 canonical 對照的欄位；寫入的條目以原名收進 fields）`。
- `ZoteroImporter.Report.residualFields` 的 doc comment 第一行不再說「被捨棄」（#206 之後就不成立）。
- `docs/store-format.md` §2.5 那一段改成現況：未映射欄位以正規化後的原名收進 `fields`，報告欄位是 `residualFields`。

計數、鍵名、回應形狀都不變，所以沒有新測試；既有的 `ZoteroImportTests`、`ImportZoteroReportSurfaceTests` 與 tools/list 預算測試照跑。
