# 2026-09-27 隸屬與上級機構的懸空 key 會出聲（#660）

`crossRecordIssues` 對 work 的三種參照邊有懸空檢查（#579、#652），但指向 organization 的另外兩條邊沒有：

- 第 7 條邊：`Person.profile.affiliations`（隸屬）
- 第 8 條邊：`Organization.parents`（上級機構）

這兩條邊的 `.key` 指向不存在的 organization 時，`akashic validate`、doctor、App 都不出聲。#656 R1 verify 的 DA 席用 scratch store 實測過：rc=0，沒有 warning。

## 改了什麼

`crossRecordIssues` 多兩種 warning，形狀比照第 33 列：

- `隸屬 key「…」沒有對應的 organization 檔（N 位 person 引用，如 …）`
- `上級機構 key「…」沒有對應的 organization 檔（N 個 organization 引用，如 …）`

如果 key 本身不是合法的 StoreKey，訊息會另外說明它不可能對應任何記錄。

literal 不報：未歸戶的隸屬與上級機構是誠實狀態。

## 裁決

`zero-instance-guards` 加第 34 列。2026-09-27 實測 live store：organization 13 筆、person 4,575 筆，懸空的隸屬 key 0 筆、懸空的上級機構 key 0 筆。

列裡記下了為什麼第 33 列沒把這兩條邊一起補上：第 33 列照 work 的欄位窮舉，而指向同一個目標（organization）的另外兩條邊住在別的形狀上。

## 測試

`CrossRecordValidationTests.testDanglingAffiliationAndParentKeysAreWarnings` 涵蓋：

- 懸空的隸屬與上級機構都被報出；
- 非法 key 附上說明；
- 存在的 org 不報；
- literal 不報。

負控兩組：分別拿掉兩個迴圈的記錄動作，測試各自變紅。

真 binary 驗證：scratch store 加一條懸空隸屬，`validate` 印出這一則 warning，rc=0。
