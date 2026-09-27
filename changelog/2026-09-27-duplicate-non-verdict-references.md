# 2026-09-27 非判定 reference 的重複看得見了（#582）

#554 R25／R26 把三個寫入面的去重換成**位元組相等**（D69／D73），理由是「零資訊損失」的承諾是對 store 裡的位元組說的。三個寫入面：

- `paginated` 冪等閘
- `UpdatePerson` 的 references append-only
- `AddOnlyEnrichment.applied`

代價是只差 NFC／NFD 的兩筆 reference 都寫得進來。第 28 列那一族（重複的判定記錄）第一行就只看 verdict 欄位，所以這個狀態進得來、卻看不見。

## 改了什麼

`StoreHealth` 多一族 `duplicateReferences`，前綴是「重複的 reference」：

- 條件：同一筆記錄裡有 ≥2 筆非判定 reference 彼此 canonical 相等。
- 分組用逐段 NFC，和 Swift `String` 的 `==` 是同一個等價關係；位元組只用來數有幾種拼法。
- 位元組不同的變體與位元組完全相同的重複都報，措辭分開：
  - 前者是位元組相等的去重收下的；
  - 後者工具面寫不出，是手改或舊 binary 寫的。
- 掃描範圍：work、person、organization、venue 的 references。判定欄位留給第 28 列那一族，不重報。
- warning 級；不設 per-record 上限（一組一則，屬於線性家族）。

三個面都接上了：

- CLI：`validate` 逐則印出，另印一行計數。
- MCP：`akashic_doctor` 的 `recordIssues.duplicateReferences`，tool 描述同步更新。
- App：側欄「記錄」Section 多一列。

`ProvenanceReference.byteExactKey` 的站點列舉從九處改成十處，並寫明這一處問的正是「canonical 相等而位元組不同」。

## 裁決

`zero-instance-guards` 加第 35 列。2026-09-27 實測 live store：非判定 reference 90 筆、重複 0 組；新 binary 的 `validate` 對 live store 這一族 0 則。

issue 另給了一個出口：「裁決變體是合法並存、不報」。沒有採用。並存的兩筆對同一件事說了兩次；倖存者只有其中一種拼法時，合併會被 `fieldsLostByMerging` 擋下，而那時才是第一次出聲，而且出在錯的操作上。

## 測試

`DuplicateReferenceScanTests` 涵蓋：

- NFC／NFD 變體與位元組完全相同的重複都報，措辭分開；
- 兩次不同的判定不報；
- 判定欄位不重報。

負控兩組：

1. 分組鍵改回位元組鍵：紅。
2. 拿掉判定欄位的排除：紅。

真 binary 驗證：scratch store 走 issue 記載的可達路徑，對同一本刊以 NFC 與 NFD 兩種拼法各跑一次 `update-venue --paginated false`。`validate` 印出這一則 warning 與計數行，rc=0。
