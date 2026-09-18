# 閘只護著記錄、沒護著被併實體——而開發時撞到的正是記錄那一半（#558）

## 一個 untracked 的 venue 被直接刪掉，零警告

#553 加了 venue 的合併路徑。`resolve-divergence` 的版控可回溯性閘（#73）問的是
「要刪的檔刪掉之後能不能從 git 取回」，而它要問的檔案清單來自 `doomedRelativePaths`
——那個 switch 對 `.venue` 仍是 `continue`，註解寫「上游已擋」。

上游自 #553 起不擋了。實測（乾淨 fixture）：

```
?? entities/…002.yaml            ← 被併的 venue，從未 commit
$ akashic resolve-divergence … --survivor keeper-journal
✓ 併入 keeper-journal：doomed-journal
$ ls entities/                    ← 那個檔沒了
```

person／work 的被併檔會過 tracked+clean 檢查。venue 的不會。

## 為什麼 #553 沒抓到——閘是「部分有效」的

`doomedRelativePaths` 的 `ids` 一開始就放了 `record.id`（divergence 記錄本身），
所以 divergence **未 commit** 時閘仍會擋。#553 開發時在副本上第一次跑就撞到這一條：

> 以下檔案刪掉之後無法從版控取回，拒絕消歧：entities/66EBDF4F-….yaml：未被 git 追蹤

於是「閘對 venue 是有效的」成了一個**看起來被驗證過**的斷言——而它驗到的只是一半。
被併實體那一半沒有任何測試碰過，因為 fixture 一律 `commitAll`，從沒製造過
「記錄 tracked、實體 untracked」的狀態。

**live store 零實際損失**：`aa109e03` 刪的 16 檔逐一對照父 commit，16/16 都在。
但那是合併前的 `chore: 記錄 7 組 venue 攣生歧異（合併前置：檔案須受版控）` 補的，
不是閘擋的——這次沒事是流程補的，不是機制。

## 修法一行，理由兩處

`doomedRelativePaths` 補 `.venue`。`holderRelativePaths` 的 `.venue` **不改行為**——
它回 `[]` 是對的，但理由不是「上游已擋」：`VerdictHolderKind` 沒有 venue，退役的
venue key 不會讓任何 holder 的 verdict value 變 stale。同一句假註解在兩處，一處
遮住了真 bug、另一處遮住了真理由。

## 測試需要一個新 fixture 能力

`GitFixture.commit(_:paths:)`——只 commit 指定路徑。既有的 `commitAll` 做不出
「divergence tracked、被併實體 untracked」這個狀態，而那正是這個 bug 藏身的形狀。
負控：把 `.venue` 改回 `continue` → ~~3 紅~~ **唯一覆蓋這條路徑的測試 `testRefusesWhenDoomedVenueIsUntracked` 紅（3 條斷言）**，乾淨（R1 verify 第 32 列：單位是斷言不是測試，照字面讀會把負控寬度高估三倍）。

## 讀 org 分支時看到的

這張 issue 是 #555 的 diagnose 副產品：讀 `DivergenceResolve.swift` 的 organization
分支時，注意到同一個 switch 裡 `.venue` 還在「上游已擋」那一格。#555 選了「裁決暫不做」，
所以 org 那兩處的註解今天仍為真——但若日後實作，~~同樣的兩格~~ **三格**要一起補：`doomedRelativePaths`、`holderRelativePaths`、**以及 `predictedHolderVerdictMigration` 的 `case .org: break`**（R1 verify 第 9 列：只補前兩格會做出一個看起來完整、對 org holder 永遠回空的閘——與本張 issue 逐字同型）。

## R1 verify：四條驗收都成立，而它引用的原則沒收尾

六席齊、32 列（2 HIGH／7 MEDIUM／13 LOW／10 INFO），Aggregate FAIL。384a554 的四條驗收在 HEAD 逐項成立（security 第 28 列、requirements 第 25 列實跑）。
FAIL 的理由是**閘只護「要刪的檔」**，而合併會**改寫**的檔一個都不在閘裡：keeper venue（#554 R17／R18 的收攏讓 keeper 自己的判定列可以是輸家，
真 binary 實測一筆只存在於 untracked keeper 的人寫判定被刪、閘沉默，第 1／2 列）、去重刪列的 entry（第 8／11／15 列，live store 有 19 個 untracked 的
work 檔）、被塌縮／改名的 divergence 記錄（第 5／17 列——`doomedRelativePaths` 的 doc 說「要跑完合併才知道、不是疏漏」，而 #173 起那份預測在閘之前
就算好了）。新註解「沒有檔案會被改寫」為假（DA 第 21 列校正：384a554 當時 keeper 是純 append、後果為零，#554 R18 起承重）；理由押在 8,670 這個
會過期的普查數字上且寫了兩份（第 4／22 列，重量已是 8,671）。其餘：`GitFixture.commit(_:paths:)` 丟狀態（第 13／14／16／18 列，DA 第 20 列說今天
無假綠——同意，仍修）、changelog 的「3 紅」單位是斷言（第 32 列）、org 是三格不是兩格（第 9 列）、dry-run 也拒（第 30 列）、另一席的負控在共用
工作樹上跑（第 6 列，harness 形狀）。

## R2：閘的輸入從「要刪的檔」擴到「要刪或改寫的檔」（D86）

**D86（Claude 代裁，使用者可翻）**：版控可回溯性閘的輸入＝要刪的檔（`doomedRelativePaths`）＋會被改寫的 holder 檔（`holderRelativePaths`）
＋**會被改寫的檔**（`rewrittenRelativePaths`：倖存者實體檔、被改指的 entry 檔、遷移後要寫的其他歧異記錄）＋會被刪而先前不在清單的
（塌縮記錄、改名前的舊檔）。三種 shape 同一份；dry-run 同閘。代價寫出來：**合併前倖存者與所有會被改指的 entry 都要 commit**——那是 #73
「歷史託給版控而非 store」的既有紀律，先前只對 doomed 兌現了一半。

- `entriesTouchedByMerge` 是 preview 的 `rewritten` 與閘共用的一份判準（三個實跑迴圈各自有同一組，preview-vs-actual 測試釘住）。
- `filesNotSafelyRecoverable` 改成兩個子程序問完全部（`ls-files -z`／`diff --name-only -z HEAD`）——名單可達數百筆 entry，逐檔兩個子程序
  會讓一次合併跑上分鐘；語意不變。錯誤訊息改「刪掉或改寫之後」。
- `holderRelativePaths` 的 `.venue` 註解改結構論證（`VerdictHolderKind` 封閉、`parse` 拒其他前綴、venue 寫入閘要求 parse 成功——
  `venue:` verdict 寫不出來），普查數字拿掉、preview 那份副本改引用；`doomedRelativePaths` 的 doc 歸位、改真話；`case .org: break` 指回三格。
- `GitFixture.commit(_:paths:)` 任一句非零即 `XCTFail`；既有測試補「divergence 記錄不在清單」的斷言。
- 既有測試 `testPartialWriteFailureReportsAndExitsNonZero` 的 fixture 補一次 commit：它先前改寫的是一個 **untracked** 的 entry（正是 D86 要擋的形狀），
  R2 之後閘在寫入前就拒；測試要的是「載入得到、落地才失敗」，所以先 commit 再設 immutable。
- 新測試：keeper venue untracked（實跑與 dry-run 都拒、keeper 位元組不變、人寫判定仍在）、被改指的 entry untracked、會被塌縮的第二筆記錄
  untracked、keeper person untracked。

**誠實邊界**：閘仍是 per-file tracked+clean，不是整棵樹；`DestructiveTargetGate` 不列 `resolve-divergence`（#580 一族）；org 的三格在 #555
裁「暫不做」之下仍是空的。
