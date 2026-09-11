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
負控：把 `.venue` 改回 `continue` → 3 紅，乾淨。

## 讀 org 分支時看到的

這張 issue 是 #555 的 diagnose 副產品：讀 `DivergenceResolve.swift` 的 organization
分支時，注意到同一個 switch 裡 `.venue` 還在「上游已擋」那一格。#555 選了「裁決暫不做」，
所以 org 那兩處的註解今天仍為真——但若日後實作，同樣的兩格要一起補。
