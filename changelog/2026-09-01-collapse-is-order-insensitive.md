# merge 側 verdict 收攏與排列無關（#461）

work merge 時 person／venue 身上的 `work:` holder verdict 收攏，在此之前**對 reference
排列敏感**：keeper 原版排在 doomed 之前才收攏；doomed-first 排列下 keeper 原版走
guard-else 無條件 append，兩筆 byte-identical verdict 落地（#460 verify 兩個 lens 以
探針實證；person 側自 #271 即有、venue 側 #460 鏡射繼承）。

## 修法：二階段（方案 b，#461 diagnose 裁決）

`DivergenceResolve.migrateWorkHolderVerdicts`——Pass 1 全部遷移並記下**本次觸及**的
(field, value)；Pass 2 只對被觸及的鍵保首見收攏。兩個 merge 迴圈（person／venue）改
呼叫同一 helper；#463 的四格裡 **org × work merge 那一格**可直接複用（其餘三格要
`person:` holder 或走 rename 側，不是這支）。

**刻意不採**方案 (a)（rename 式全量 dedup）：那會順手收攏與本次無關的既有重複，
與「消歧不是清理工具」（#71）的兩處明文裁決衝突。觸及集合守住的那條線要說準
（verify R1 六席收斂指出第一版措辭寫寬了）：**(field, value) 不等於任一遷移輸出**的
既有重複一筆不動——`testUnrelatedExistingDuplicatesAreUntouched` 釘的是這一半
（不同鍵的 bystander）。**落在觸及鍵上**的 keeper 既有重複則會一併收攏成一筆——
刻意為之：#271 起 `resolvePersonDivergence` 的遷移就以同樣方式折疊 doomed 自己的重複，
且這種輸入在正常寫入面產生不了、唯一自然來源是本次修掉的 bug——
`testTouchedKeyCollapsesKeeperPreexistingDuplicatesDeliberately` 釘住。

**丟棄不靜默**：收攏丟掉的每一列進 `ResolveReport.verdictsCollapsed`（value ＋ 被丟的
判定原文），CLI `resolve-divergence` 逐列印出。helper 另以 `pairing.holder != survivor`
自保——指向 survivor 的 verdict 永不算遷移對象（Codex R1 H-1：否則 `merged` 含
survivor 時觸及集合退化成全量 dedup 且 `changed` 恆真）。

rename 側的全量 dedup 行為（#232 原始設計）**維持現狀**：兩側立場各有出處，
統一屬更大裁決，出現實害再議（裁決記錄見 #461 diagnosis）。

## 測試

- pin 測試翻轉：`testMergeDoomedFirstArrangementCurrentlyKeepsDuplicate`（斷言現況
  count==2）→ `testMergeDoomedFirstArrangementAlsoCollapses`（count==1）——#460 verify
  就位的紅色目標按設計轉綠
- 新增 person 側 doomed-first 案＋不同鍵既有重複保留負向案，以及 helper 層純函數案
  （同鍵收攏刻意、留存者與揭露格式、二次執行 no-op、survivor 自保）
  （`OrderInsensitiveCollapseTests`）

kind 語意註記：收攏保首見——留存者的 judgement kind 依排列來自 doomed 或 keeper 側；
「與排列無關」只對**筆數與 (field, value)** 成立，不對留存者的 kind 成立。doomed-first
排列的丟棄在 #461 之前**不會發生**（兩筆並存），所以它是本修法引入的、不是 #460 verify
F9 的既有觀察——第一版把它寫成既有觀察是錯的（verify R1 DA D1）。留存者選擇政策
（首見／keeper 優先／last-wins）屬顯式裁決，由 verify follow-up 追蹤。
