# 2026-09-27 `researcher` 表的現職隸屬分得開三態（#656）

#651 讓 `researcher_timeline` 以 `affiliation_kind` 分開「未歸戶的字面」與「懸空的 key」。同一次匯出的 `researcher` 表還有一個現況便利欄位 `affiliation_current`，它只放顯示名：字面「iss」與 key「iss」印出來一樣，也沒有機構 id 可以 join。

比照 #651，在 `researcher` 表最後加兩欄（`load.sql` 依位置灌表，新欄只能加在最後）：

- `affiliation_current_kind`：`organization`（此時 `affiliation_current` 是機構的 key 字串本身，不是機構名，包含懸空的 key）或 `literal`（未歸戶）；沒有現職隸屬時是 NULL。
- `affiliation_current_id`：key 對得到機構時才有值（外鍵到 `organization`）。懸空的 key 與字面都是 NULL，要分兩者看 kind；不造 id，與懸空作者同一條理由。

issue 的 Expected 把 id 列為「可能」。它正是 join 所需，所以一起加。

## 驗證

- 測試 `OrganizationTests.testAffiliationCurrentKindSeparatesLiteralFromDanglingKey` 涵蓋四種情形：已歸戶、字面、懸空的 key、沒有現職隸屬。負控（kind 一律回 literal）紅 2 條。
- 真 binary 端到端：在 scratch store 上 `export-tables`，以 DuckDB（Python 模組 1.5.5）執行 `load.sql`，四種情形的兩欄都如預期，`affiliation_current_id` 能 join 回 `organization`。

## R1 verify（5 席齊，0 HIGH、0 MEDIUM）

- DDL 註解寫「value 是機構 key 的顯示名」，但 `researcher` 表沒有 `value` 欄。這句是從 #651 的註解搬過來的，而且對已歸戶的 key，實際印出的是 key 字串（`academia-sinica`），不是機構名。兩處一起改，避免同一個檔案裡出現兩種說法。
- DDL 的測試原本只查欄名有沒有出現，改成驗兩欄的型別、外鍵與先後順序（Codex 席）。
- 兩個既有缺口不在本張範圍，另開 issue：只有 attested 段落的人被標成 `retired`，而 `researcher_timeline` 沒有匯出 `attested`（#661）；懸空的隸屬 key 沒有任何面會報出來（#660）。
