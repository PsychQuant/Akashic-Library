# 2026-09-26 export-tables 分得出團體作者（#596）；resolve-people 列表模式的篩選（#597）

## #596：`publication_author` 的團體作者不再與未歸戶同形

`export-tables` 過去把 `.organization` 作者寫成 `researcher_id` NULL＋`name_full`，與未歸戶的 `.literal` 完全同形。#378 花力氣把團體作者接到 `.organization`，到了關聯匯出這一層又被折回 literal 的樣子。下游（storyline 的 JSON 交付物）因此把三個已歸戶的團體作者報成「沒對到人」。另外，`--view` 的機構閉包只收隸屬與 parents，不收作者位指到的機構，所以 `name_full` 落成 key，外鍵也接不上。

- `publication_author` 在最後加兩欄：
  - `author_kind`：`person`／`organization`／`literal`；
  - `organization_id`：團體作者時指向 `organization` 表，懸空的 key 為 NULL、不造 id。
  - 加在最後是因為 `load.sql` 以 `INSERT … SELECT *` 依位置灌表。
- 「還沒歸戶的」改成 `WHERE author_kind = 'literal'`；CLI 結尾的未歸戶計數同步改。先前以 `researcher_id IS NULL` 計數，會把團體作者算進去。
- view 的機構閉包把被保留著作的團體作者一併收進來。
- `load.sql` 的 DDL 加欄與外鍵。

**下游影響**：CSV 多兩欄，前四欄的位置與語意不變。
- 只讀前四欄、容許多出欄位的消費端：照舊可用。
- 固定四欄解析、整列解包、或沿用舊版四欄資料表 schema 的消費端：要同步更新。
- 以欄名讀的消費端：可以直接用 `author_kind`。

**匯出結尾的計數**（R1 verify）：
- 未歸戶只數 `author_kind = 'literal'`。
- 另報「作者 key 懸空」（`author_kind` 不是 literal 而 id 為 NULL）：團體作者 key 懸空時，`validate` 也不報（#652）。
- `researcher_timeline` 仍有同一個形狀：literal 與懸空 key 都是 NULL，另案 #651。

**驗證**：
- `RelationalExportTests`：三態可辨、懸空 org key、DDL；
- `ViewExportTests`：團體作者進閉包、外鍵閉合、顯示名；
- 真 binary 端到端：Python duckdb 1.5.5 執行產出的 `load.sql`，`organization_id` 以外鍵 join 得上；
- 負控：拿掉閉包的團體作者迴圈 → 3 個失敗。

## #597：`resolve-people` 的 `--citekey`／`--person`／`--tier` 在列表模式也收窄

先前這三個篩選只作用於 `--apply`：列表一律顯示全部，用來防止「收窄後以為其他候選不存在」。代價是逐篇查證時只能自己 grep 全列表。

現在不帶 `--apply` 時，篩選會收窄候選列與歧義條目（歧義條目以「任一命中的 person」比 `--person`），並印一行「候選 N 個（全部 M 個）、歧義 n 筆（全部 m 筆）」，原本要防的誤會由這一行照顧。`--apply` 模式不變。

**#597 R1 verify 的修正**：
- 收窄行移到零候選路徑的提早返回之前。先前 store 沒有唯一候選時，歧義段會被靜默收窄；DA 以真 binary 重現，畫面上只剩一句「任何提名層皆無命中」，而 exact 層其實命中了 2 筆歧義。那句話也改了：有歧義時改說「無唯一候選（歧義 N 筆見下）」。
- 已否決的沉底列跟著用 `--citekey`／`--person` 收窄。它們沒有 tier，所以 `--tier` 不作用。四態計數仍涵蓋全庫；收窄時畫面上明說這兩件事。
- 歧義段「用 --citekey／--person 收窄」的提示在 `--apply` 模式改成「不帶 --apply 時用…」，因為 `--apply` 不收窄歧義段。
- 測試補齊：`--tier` 單獨使用與取交集、歧義條目以「任一 person」收窄、零候選路徑。負控共 6 個失敗。
- `mcp-cli-parity` 的 `resolve_people` 列記下「CLI 列表收窄、MCP 列表面沒有」這個差異與理由。
