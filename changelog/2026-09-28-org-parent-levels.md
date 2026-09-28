# 2026-09-28 load.sql 逐層回填上級機構，三層以上的機構鏈載得進 DuckDB（#667）

`export-tables` 的 `load.sql` 載入 organization 分兩步（#92）：先插不含 `parent_id` 的骨架，再用**一句** `UPDATE … FROM read_csv(...)` 回填全部 `parent_id`。機構鏈有三層時，那一句同時設「b→a」與「c→b」，DuckDB 報外鍵錯誤（`Violates foreign key constraint because key … does not exist`），整份腳本中止。live store 有一條三層鏈（`data-science-statistical-cooperation-center` → `institute-of-statistical-science` → `academia-sinica`），所以用 live store 匯出的 `load.sql` 在修之前載不進去。

CI 沒抓到，是因為 `ci.yml` 的端對端 fixture 與 #92 的回歸測試都只有兩層——兩層時一句 UPDATE 回填得完。

## 改了什麼

- **回填逐層、由上而下，一層一句。** 先用遞迴 CTE 從 CSV 算出每個機構的層數（根是第 0 層），存進暫存表 `akashic_organization_level`，再對第 1 層、第 2 層……各下一句 UPDATE。第 k 層回填時，它的母機構（第 k−1 層）已在前一句填好，它的子機構（第 k+1 層）還是 NULL，所以同一句裡沒有任何一列被另一列的新值參照。自我參照外鍵約束保留（#92 的立場：拿掉約束，下游就再也擋不住懸空的 parent）。
- **層數由匯出端算。** SQL 腳本沒有迴圈，所以要幾句只能在匯出時決定：`RelationalExport.organizationParentLevels(_:)` 從同一次匯出的 organization 表算出最深的一層，`duckDBScript` 依它產生對應句數。這是腳本裡唯一從資料來的東西；資料本身仍走 CSV，「不內嵌資料」的設計不變。
- **`duckDBScript` 的層數參數刻意沒有預設值。** 預設一層就是 #667 之前的行為，漏傳的呼叫端會安靜地回到三層鏈中止的狀態。
- **腳本尾端加一句檢查。** CSV 裡帶上級機構、載入後卻還是 NULL 的列（成環，或 `load.sql` 與 CSV 不是同一次匯出、層數對不上）會讓腳本以 `error()` 中止並說出筆數，不留下安靜的 NULL。成環的列到不了根，匯出端不替它們算層數，交給這一句出聲（#179 的 validate 本來就擋環，這裡是載入端的最後一道）。duckdb CLI 的 `.read` 在第一個錯誤就停下並以 1 結束（1.5.5 實測），所以 CI 的端對端步驟會紅。
- CI 的端對端 fixture 加第三層機構（`grandchild-org` → `child-org` → `parent-org`），並在載入後斷言 `parent_id` 非空的列是 2。README 的 CI 檢查表加一列。

## 量測

live store 的唯讀副本（複製 `entities/`、`libraries/`、`store.yaml` 到暫存目錄，binary 以暫存的 `AKASHIC_HOME` 與 `--library` 執行），duckdb CLI 1.5.5：

- `export-tables` 算出 2 層，`load.sql` 產生 2 句回填；
- `.read load.sql` rc=0、不印任何東西；organization 13 列、`parent_id` 非空 3 列，與 CSV 的非空 `parent_id` 3 列相同——三層鏈 `data-science-statistical-cooperation-center → institute-of-statistical-science → academia-sinica` 與 `taiwan-international-graduate-program → academia-sinica` 全部回填；
- 其餘各表的列數與匯出一致（publication 2,563、publication_author 8,372、publication_doi 2,444、researcher 4,575）。

CI 的端對端步驟在本機以 debug binary 跑（去掉 `brew install` 與 release build 兩行）：修好的 binary 通過；**#667 之前的 binary（`8b8002d1`）對新的三層 fixture 報 `Constraint Error: Violates foreign key constraint`、rc=1**——fixture 抓得到這個 bug。

檢查句原本寫成裸 `SELECT error(…) … HAVING count(*) > 0`，通過時 duckdb CLI 會印一個空的結果表，看起來像出了事；改成 `CREATE OR REPLACE TEMP TABLE … AS SELECT error(…)`，通過時不印任何東西，失敗時照樣中止（成環的 fixture 實測 rc=1、之後的句子不執行）。

## 測試

`OrganizationParentLevelsTests`：

- 層數：四層鏈加一條旁支得 3；沒有上級機構得 0；成環的列不計入。
- 腳本：一層一句、由上而下；層數是多少就幾句；不再有那一句從 CSV 一次回填全部的 UPDATE；層數為 0 時沒有 UPDATE 但保留檢查句。
- 真的交給 duckdb 跑（本機有 duckdb CLI 才跑，找不到就 skip——端對端的權威是 CI 的步驟）：四層鏈加旁支全部回填；負控：層數給 1（#667 之前能處理的深度），檢查句中止並說出「2 筆的上級機構沒有回填」。

另外用 python duckdb 1.5.5 對同一份 fixture 確認：#667 之前的單一 UPDATE 會報外鍵錯誤（負控重現），逐層版本載得進去。

負控：把逐層的 UPDATE 收回成一句（`l.level >= 1`），四層鏈那一支測試變紅（duckdb 以 1 結束）；還原後綠。
