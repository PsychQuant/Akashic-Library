# 2026-09-29 venue 合併的名字併入：整段搬、只有原本的 variant 才標 variant（#565）

## 問題

`resolveVenueDivergence`（#553）把被併者的名字併進倖存者時做了兩件事：

1. **一律標成 `variant`**。不只被併者的 authorized（#553 的提醒只講這一格），連被併者未標的名字也被標成「異寫」。#554 D1（使用者 2026-09-12）對 `--authorize` 的降級目標選了未標，理由是 `venue-entity` spec 寫的「A name in neither is unclassified … it makes no claim either way」：「兩筆是同一本刊」蘊含「這些名字都是本刊的名字」，不蘊含「它們都是倖存者對外形的異寫」。合併端在反方向做了 #554 修掉的那件事。
2. **以 `TemporalValue(value:)` 重建名字，丟掉時間欄位**。被併者 `names` 裡帶 `start`／`end`／`attested` 的沿革段，併過去之後只剩字串；`source`、`note` 同樣消失。倖存者已有同名的一段時，被併者那一段連同時間被 canonical 濾除，也不出聲。

live store 今天沒有實例（2026-09-29 唯讀量測：485 筆 venue、537 段名字，帶時間欄位 0、帶 source 0、帶 note 0），所以這是設計上的形狀問題，不是已發生的資料損失。`zero-instance-guards` 第 22 列保留沿革，就是為了讓它有位置可落，而合併會把落進去的東西再拿掉。

## 改了什麼

搬什麼、標不標 variant 由新的 `LibraryStore.venueNameAbsorption(keeper:doomed:)` 決定。`validateVenuePreconditions`（拒絕與提醒）與 `mergedVenueKeeper`（實際併入）共用這一份，dry-run 與實跑對「搬了什麼」給同一個答案。

1. **整段搬**。`TemporalValue` 連同時間欄位、`source`、`note` 原樣進倖存者的 `names`。
2. **被併者原本在 `variant` 的才標 variant**。其餘，包括被併者的 authorized，併入後未標。
3. **同名段**（canonical 相等）：
   - 與倖存者或先併入的某一段完全相同（時間、source、note 都相同）就不再搬。
   - 否則要能與同名的每一段並存。判準是 `Venue.sameNameSegmentsCanCoexist`：兩段都帶時間、且依 `segmentsAreDisjoint` 不相交，也就是沿革改回舊名。這個判準從 `Venue.validate()` 的近重複檢查抽出來，兩處共用。
   - 不能並存的，前置以 `wouldLoseFields` 具名拒絕、零寫入。訊息指名被併者、兩段各自的時間／source／note、衝突的那一段來自倖存者還是先併入的被併者。哪一段的時間對是判定，合併不做。在此之前那一段的時間欄位會被安靜丟掉。
4. **倖存者已有的名字不改分類**。被併者把它標成 variant 而倖存者沒有時，合併不替倖存者多標，但被併者那句話會隨檔案消失，所以加一則提醒（dry-run 與實跑同一句）。倖存者把它當 authorized 時，提醒說兩邊的分類衝突、以倖存者為準。
5. **被併者的孤兒 variant**（不在它自己的 names 裡；#473 起是 error，只有手改或舊 binary 寫得出來）當成一段不帶時間的名字搬，並標 variant。#553 就是這樣併它的，這裡不讓它安靜消失。
6. **authorized 降級的提醒**：`Demotion.Outcome.becomesVariant` 改名 `becomesUnclassified`，措辭從「成為…的 variant」改成「併入…的 names、成為未標（不進 variant；倖存者同書寫系統的對外形不變）」。其餘兩種結果（已在倖存者 names 而未標、已在倖存者 variant）不變。
7. 被併者的名字內容檢查（D8，`doomedRecordInvalid`）改成檢查 `incoming`，也就是真的會搬過去的段。一段會以沿革身分搬過去的同名段，也要通過內容檢查。

`mergedVenueKeeper` 對不能並存的段照樣搬（不略過）。前置會先拒絕；若有呼叫端跳過前置，寫入閘的近重複檢查會擋下，失敗方向是拒絕而不是丟資料。

文件同步：`two-kinds-of-edits` 的 resolve-divergence 列、`mcp-cli-parity` 的 `resolve-divergence`（重新確認，裁決不變）與 `akashic_update_venue` 兩列、`update-venue --authorize` 的 help 與 `AkashicService` 的註解（「合併把名字降成 variant」自 #565 起是歷史）。

## 測試與負控

新增 `VenueMergeNameAbsorptionTests`（10 支）：

- 只有被併者原本在 variant 的才標 variant；被併者的 authorized 併入後的提醒說「成為未標」，dry-run 與實跑同一句。
- 沿革段整段搬（`start`／`end`／`source`／`note`，另一段 `attested`）。
- 同名沿革段兩段都帶不相交的時間時並存（`Sankhyā` 1933–1960 與 2002–2007）。
- 同名段時間不同而不能並存：dry-run 與實跑都拒、訊息指名被併者與時間、零寫入。
- 同一段只差 note 也拒。
- 三方合併時兩個被併者各帶一份完全相同的段，只留一段。
- 被併者的 variant 碰上倖存者已有而未標、或已是 authorized 的名字：分類不變，提醒說出來。
- 被併者的孤兒 variant 照樣併進 names 與 variant。

`DivergenceResolveVenueTests` 更新三支：原本斷言被併者的 authorized 進 variant，改成未標；降級提醒改斷言「成為未標」。

先寫測試：舊實作下 10 支新測試有 9 支紅（完全相同的段只留一段那支本來就綠，舊實作以字串去重）。

負控七組，都是反向編輯後跑測試、再以備份還原並 `cmp` 確認逐位元組相同：

| # | 改壞什麼 | 轉紅的測試 |
|---|---|---|
| 1 | 所有搬進去的段都標 variant | 8 支（含 `testOnlyTheDoomedsVariantsAreTaggedVariant`、兩支降級提醒） |
| 2 | 搬進去的段只留字串（丟時間） | `testDatedSegmentMovesWholeWithSourceAndNote`、`testSameNameRenamingHistorySegmentCoexistsWithTheKeepers` |
| 3 | 不記錄不能並存的段 | `testConflictingSameNameSegmentIsRefusedAndNamed`、`testSameSegmentDifferingOnlyInNoteIsRefused` |
| 4 | 「完全相同」不比 note | `testSameSegmentDifferingOnlyInNoteIsRefused` |
| 5 | 不提醒沒帶過去的 variant 標記 | 兩支 variant 標記提醒 |
| 6 | 不搬孤兒 variant | `testDoomedOrphanVariantIsStillCarried` |
| 7 | 不略過完全相同的段 | 5 支（含 `testIdenticalSegmentsAreNotDuplicatedAcrossDoomedRecords`、髒名字不擋合併那支） |

負控 3 值得記一筆：拿掉具名拒絕後，合併仍然被寫入閘的近重複檢查擋下，但訊息指向倖存者、不提被併者與時間。測試斷言的是訊息內容，所以轉紅。

## 誠實邊界

- 「完全相同」比的是 canonical 名字加時間、source、note。只差 source 或 note 的同一段現在會拒絕合併，而在此之前會安靜丟掉被併者那一份。live store 今天 0 段帶 source 或 note。
- 倖存者已有的名字，被併者對它的 variant 標記只提醒、不帶過去。帶過去的話，倖存者一個原本「不作宣稱」的名字會多一句宣稱，而工具面沒有把名字移出 variant 的操作（只能手改 YAML）。提醒是可逆的做法：要標的話之後用 `update-venue --add-variant`。
- 被併者自己的 variant 標記可能是機械產生的（`migrate-venue-variants` 的補集規則，#567 退場）。對新搬進來的名字照樣帶過去，這是 #565 Expected 的明文要求。
- 三方合併時，被併者的 authorized 降級提醒仍只對倖存者比，不對先併入的被併者比（結果一樣是未標，只是句子可能說「成為未標」而那個名字其實是前一個被併者帶進來的）。同理，「倖存者已有這個名字」那則 variant 提醒在三方合併時，那個名字可能是前一個被併者帶進來的。
- 同名段的衝突拒絕是一道新的零實例守衛（live store 帶時間的名字段 0）。它在 `zero-instance-guards` 的列由整合者加。
