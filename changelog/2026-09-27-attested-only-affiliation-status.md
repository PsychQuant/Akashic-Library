# 2026-09-27 只被觀測到的隸屬不再被讀成「已退休」或「進行中」（#661）

一段只有 `attested` 觀測點的隸屬（有觀測時點，沒有 `end`，也不是 `ended-unknown`），在 `export-tables` 的兩張表裡說法互相矛盾：

- `researcher.status` 寫 `retired`。因為這種段不算現職（`isOpen` 在 #70 的裁決），而程式把「不是現職」一律當成「已結束」。這就是 `Temporal.swift` 警告過的錯誤：把被看到過誤當成離開了。
- `researcher_timeline` 沒有匯出 `attested`。那一列的 `valid_end` 和 `valid_end_unknown` 都是 NULL，照 DDL 的判準會被讀成進行中。

## 改了什麼

**`researcher.status` 多一個值 `undetermined`。**
- 判定：沒有開放段，但至少有一段只被觀測到過。
- 已結束的段加上只被觀測到的段，一樣是 `undetermined`：我們知道那個人某個時點在那裡，之後還在不在，資料說不出來。
- 只有已結束的段（有 `end` 或 `ended-unknown`），照舊是 `retired`。（attested 與 end 並存是 store 拒收的矛盾，所以不是一種情形。）
- 沒有隸屬資料時仍是 NULL，和 `undetermined` 分開：NULL 是沒資料，`undetermined` 是有資料但說不出來。

**`researcher_timeline` 在最後加一欄 `valid_attested`。**
- 內容是觀測點依序寫成 JSON 陣列（`["2019-05","2021"]`），沒有觀測點時是 NULL；以 `valid_attested::JSON` 取回。
- R1 用過 `;` 串接，R1 verify 否掉：store 不驗觀測點的值域，`attested: [""]` 會串成空字串、被 DuckDB 讀成 NULL，那一段又成了進行中；含 `;` 的觀測點與兩個觀測點分不開。JSON 陣列兩者都無歧義，開頭固定是 `[`，也不會被試算表當成公式。
- load.sql 依位置灌表，所以新欄放最後。

**DDL 更新。**
- 「進行中」的判準改成 `valid_end IS NULL AND valid_end_unknown IS NULL AND valid_attested IS NULL`。
- `status` 的 CHECK 收 `undetermined`。
- researcher 表「現況欄位可由 timeline 推出」的註解跟著改。
- README 的 format 6 歷史列補一句新判準，因為那一行的 SQL 會被照抄。
- `docs/store-format.md` §3 attested 第 2 條改寫：attested-only 段不算進行中，也不算已結束；舊的「status 推導不採計」有兩種讀法，其中一種正是 `retired` 的來源（R1 verify 三席同指）。`died` 與 `status` 那一節補上值域。

## 裁決

`undetermined` 是新值，不是 NULL。理由：把「沒有資料」與「有資料但判不出」合成同一個 NULL，會讓兩種觀察在輸出上無法區分（`lossless-intake` 執行細節 3 的形狀）。這只影響匯出，不動 store，要改可以隨時改。

## 測試

`RelationalExportTests.testAttestedOnlyAffiliationIsUndeterminedAndTimelineCarriesTheObservation` 涵蓋三種人：
- 只被觀測到；
- 已結束的段加上只被觀測到的段；
- 觀測點之外另有 end。

同一個測試也檢查欄位順序、JSON 陣列（含 `[""]` 與含 `;` 的觀測點）、CHECK 與判準字串。

`OrganizationTests` 的欄位順序斷言改成看最後三欄。

負控三組：
1. status 改回一律 `retired`：紅。
2. `valid_attested` 改回永遠 NULL：紅。
3. （R1 verify 後）`valid_attested` 改回 `;` 串接：紅。

真 binary 驗證：scratch store 裡一個只被觀測到的人，`export-tables` 輸出 `undetermined` 與觀測點（R1 當時是 `;` 串接，R1 verify 後改成 JSON 陣列）。以 DuckDB 1.5.5 跑 load.sql 灌表成功，新判準把那一段判為非進行中。
