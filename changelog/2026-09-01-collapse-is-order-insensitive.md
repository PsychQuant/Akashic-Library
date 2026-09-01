# merge 側 verdict 收攏與排列無關（#461）

work merge 時 person／venue 身上的 `work:` holder verdict 收攏，在此之前**對 reference
排列敏感**：keeper 原版排在 doomed 之前才收攏；doomed-first 排列下 keeper 原版走
guard-else 無條件 append，兩筆 byte-identical verdict 落地（#460 verify 兩個 lens 以
探針實證；person 側自 #271 即有、venue 側 #460 鏡射繼承）。

## 修法：二階段（方案 b，#461 diagnose 裁決）

`DivergenceResolve.migrateWorkHolderVerdicts`——Pass 1 全部遷移並記下**本次觸及**的
(field, value)；Pass 2 只對被觸及的鍵保首見收攏。兩個 merge 迴圈（person／venue）改
呼叫同一 helper，#463 補 org 格時直接複用、不再鏡射複製。

**刻意不採**方案 (a)（rename 式全量 dedup）：那會順手收攏與本次無關的既有重複，
與「消歧不是清理工具」（#71）的兩處明文裁決衝突。觸及集合守住這條線——
`testUnrelatedExistingDuplicatesAreUntouched` 釘住。

rename 側的全量 dedup 行為（#232 原始設計）**維持現狀**：兩側立場各有出處，
統一屬更大裁決，出現實害再議（裁決記錄見 #461 diagnosis）。

## 測試

- pin 測試翻轉：`testMergeDoomedFirstArrangementCurrentlyKeepsDuplicate`（斷言現況
  count==2）→ `testMergeDoomedFirstArrangementAlsoCollapses`（count==1）——#460 verify
  就位的紅色目標按設計轉綠
- 新增 person 側 doomed-first 案＋無關重複保留負向案（`OrderInsensitiveCollapseTests`）

kind 語意註記：收攏保首見——留存者的 judgement kind 依排列來自 doomed 或 keeper 側；
kind 級丟棄可見性是 #460 verify F9 的既有觀察，不在本次 scope。
