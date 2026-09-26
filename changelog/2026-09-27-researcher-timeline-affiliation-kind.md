# 2026-09-27 `researcher_timeline` 加 `affiliation_kind`（#651）

`export-tables` 的 `researcher_timeline.organization_id` 用 NULL 表示「未歸戶」。但隸屬是 `.key(k)` 而 k 懸空時，那一列同樣是 `organization_id` NULL、`value` = k。字面「iss」與懸空的 key「iss」在這張表裡完全分不開。#596 在 `publication_author` 修過同一個形狀（`author_kind`），同一個論證在這裡也成立。

- 在最後加一欄 `affiliation_kind`（`load.sql` 依位置灌表，所以加在最後）：
  - 只有 `dimension = 'affiliation'` 的列有值：`organization`（含懸空的 key）或 `literal`（未歸戶）；
  - 其他維度是 NULL，那一欄對它們不適用。
- 「還沒歸戶的隸屬」是 `WHERE affiliation_kind = 'literal'`，不是 `organization_id IS NULL`。DDL 的註解寫明這一點，原本「這張表分不開兩者（缺口 #651）」那句拿掉。
- 測試：`OrganizationTests.testAffiliationKindSeparatesLiteralFromDanglingKey`，涵蓋已歸戶、字面「iss」、懸空的 key「iss」（value 相同也分得開），以及非隸屬維度是 NULL。實作前 5 個斷言失敗。
- 端到端：在沙箱 store（`AKASHIC_HOME` 指向暫存目錄）跑真的 `export-tables`：
  - CSV 表頭與 DDL 的欄位順序逐欄一致；
  - 用 Python 的 duckdb 執行產出的 `load.sql`，`affiliation_kind = 'literal'` 查得到那一列。

## R1 verify 之後

- `RelationalExport` 型別 doc 裡的欄位清單停在很早的版本（沒有 `note`、`organization_id`，欄名也不對），改成現況並指向 `columns` 與 DDL。
- 同形的姊妹格：`researcher.affiliation_current`（現況便利欄位）同樣分不開 key 與 literal，也沒有機構 id。開 #656 追蹤。
