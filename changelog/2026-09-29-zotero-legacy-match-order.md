# 2026-09-29 Zotero 匯入：附加來源的比對先於 legacy 裸 key，且裸 key 的「已被其他 library 持有」看附加來源（#607）

#605 讓一筆 entry 可以帶多個 Zotero 來源之後，匯入端對回既有 entry 的順序是「主來源 composite → legacy 裸 key → 附加來源 composite」，而 legacy 分支判斷「同一個裸 key 已被其他 library 持有」時只看主來源。

兩個後果（2026-09-29 以測試重現，正式 store 目前沒有缺 `library_id` 的來源，觸發面窄）：

- 群組 library 的條目會被一筆恰好同裸 key 的 legacy 舊檔認領：舊檔的主來源被改寫成那個 library、書目欄位被群組那份覆寫，而真正持有這個來源的附加來源從此不再被更新——同一個來源變成兩筆 entry 宣稱（#610 的形狀）。
- 附加來源持有的裸 key 被當成「沒有人持有」，legacy 舊檔可以被另一個 library 的同 key 條目認領。

## 改了什麼

`ZoteroImporter.run` 的比對順序改成 ① 主來源 composite ② 附加來源 composite ③ legacy 裸 key，並寫在程式註解裡。「同一個裸 key 已被其他 library 持有」改由一張裸 key → library 集合的表判斷，主來源與附加來源都登記進去。

## 測試與負控

新檔 `Tests/AkashicKitTests/ZoteroSourceRoutingTests.swift`，3 支：

- `testSecondarySourceMatchComesBeforeLegacyBareKey`：附加來源的比對先於 legacy（修之前三條斷言全紅：legacy 被改成 lib 5、標題被覆寫、附加來源的版本沒更新）。
- `testLegacyClaimRefusedWhenAnotherLibraryHoldsTheKeyAsSecondary`：附加來源持有的裸 key 擋下 legacy 認領（修之前紅）。
- `testLegacyStillClaimedWhenNobodyElseHoldsTheKey`：沒有人持有時 legacy 照舊被認領、補上 `library_id`（回歸防線，修之前就綠）。

負控兩組（反向編輯後以 `cmp` 確認還原）：拿掉 legacy 分支的 `secondaryID == nil` 條件 → 第 1 支紅；不把附加來源登記進裸 key 表 → 第 2 支紅。

## 誠實邊界

- legacy 被「其他 library 已持有」擋下時，那個 Zotero 條目照舊走「建新 entry」——這是 #3 就有的語意，本次不動。結果是 legacy 舊檔與新建的那筆並存，要人判斷（`record-divergence`）。
- `enrich-from-zotero`（#340）的比對仍只看主來源，#605 已明訂在範圍外。
