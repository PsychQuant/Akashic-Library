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
所以 org 那兩處的註解今天仍為真——但若日後實作，~~同樣的兩格~~ ~~三格~~ **帶 `org-merge-slot` 標記的每一格**要一起補（數量以 grep 量、不寫死：R1 verify 第 9 列說三格，R2 同一個 commit 又新增兩格而散文仍寫三——R2 verify 第 8／15 列；只補部分會做出一個看起來完整、對 org holder 永遠回空的閘，與本張 issue 逐字同型）。

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
  會讓一次合併跑上分鐘；~~語意不變~~ **R3 更正：語意在巢狀 store 上變了（見下）**。錯誤訊息改「刪掉或改寫之後」。
- `holderRelativePaths` 的 `.venue` 註解改結構論證（`VerdictHolderKind` 封閉、`parse` 拒其他前綴、venue 寫入閘要求 parse 成功——
  `venue:` verdict 寫不出來），普查數字拿掉、preview 那份副本改引用；`doomedRelativePaths` 的 doc 歸位、改真話；`case .org: break` 指回三格。
- `GitFixture.commit(_:paths:)` 任一句非零即 `XCTFail`；既有測試補「divergence 記錄不在清單」的斷言。
- 既有測試 `testPartialWriteFailureReportsAndExitsNonZero` 的 fixture 補一次 commit：它先前改寫的是一個 **untracked** 的 entry（正是 D86 要擋的形狀），
  R2 之後閘在寫入前就拒；測試要的是「載入得到、落地才失敗」，所以先 commit 再設 immutable。
- 新測試：keeper venue untracked（實跑與 dry-run 都拒、keeper 位元組不變、人寫判定仍在）、被改指的 entry untracked、會被塌縮的第二筆記錄
  untracked、keeper person untracked。

**誠實邊界**：閘仍是 per-file tracked+clean，不是整棵樹；`DestructiveTargetGate` 不列 `resolve-divergence`（#580 一族）；org 的三格在 #555
裁「暫不做」之下仍是空的。

## R2 verify：批次化把 dirty 那一半打死了

六席齊、每席一個 HIGH、六席同指一件事（Codex 盲審獨立命中）：`git ls-files` 的輸出相對 **cwd**、`git diff --name-only` 的輸出**預設相對 repo root**。
R2 把兩個 per-file、看 exit status 的查詢換成兩個批次、比輸出路徑集合的查詢——store 是 repo 根時兩個基準重合（live store 今天如此，
`rev-parse --show-prefix` 空），store 是 repo 子目錄時 `dirtySet` 裝的是 `store/entities/X.yaml`、永遠不等於 `rel`，「有未提交的修改」那一半
**整個 fail-open**。五席真 binary 重現：巢狀 store、dirty 的被併檔——dry-run 沉默、實跑刪檔 rc 0、工作樹那一版永久消失。這是 R2 引入的回歸，
而且方向是壞的那個；untracked 那一半不受影響（`ls-files` 是 cwd 相對）。R2 的 doc 寫「語意與逐檔相同」——pathspec 與 HEAD 相同，輸出基準不同，
那句等價性沒有量測支撐。巢狀不是邊角：`isInsideVersionedWorkTree` 逐層往上找 `.git`，`outsideVersionControl` 的訊息主動建議「位於工作樹內的
store」。R2 自己的四個新測試全在 store＝repo 根的 fixture 上跑，所以全綠——與 #558 立案時「fixture 一律 `commitAll`、從沒製造過那個狀態」同型。

## R3：`--relative`，與一個巢狀 store 的測試

`diff --name-only --relative -z HEAD -- <paths>`——輸出改成相對 cwd，與 `ls-files` 同基準。同一輪的 MEDIUM 一併處置：unborn HEAD（fresh `git init`）分開判、tracked 的檔報「尚無任何 commit」而不是「無法執行 git」（第 11／22 列）；pathspec 每 500 筆一批（第 20／33 列）；拒絕清單截 `Entry.perRecordWarningCap`＋「另有 N 個檔未列出（共 M 個）」（第 13／19 列）；org 的五個空格全加 `org-merge-slot` 標記、三處散文改成以 grep 量（第 8／15 列）；`docs/store-format.md` 的閘契約改「要刪或改寫」（第 7 列）；被改指 entry 與塌縮記錄的 dirty 測試（第 9 列）；`.work` 的觸及判準改以 keeper id（第 29 列）；`commitAll` 也驗狀態（第 24 列）；person 側倖存者測試補 dry-run（第 18 列）；註解第三句改三族 holder（第 17 列）。**代價再補一句**（第 23 列）：閘的輸入擴大後，它會**先於** shape 專屬診斷（`candidateMissing`、`wouldLoseFields`、名字不變式）開火——一筆與本次消歧無關、只是碰巧 dirty 的 entry 會讓使用者先看到「有未提交的修改」。git config 會改變 `ls-files`／`diff` 輸出的部分（`core.quotePath`——路徑純 ASCII 不受影響）記為邊界（第 21 列）。`testRefusesDirtyFilesWhenStoreIsARepoSubdirectory`
把 store 放在 repo 的 `library/` 子目錄（斷言 `show-prefix` 是 `library/`），dirty 的被併實體、dirty 的倖存者各拒一次（實跑與 dry-run、
只列那一個檔、`why` 說的是 dirty 不是 untracked），全部 commit 後照常通過。負控：拿掉 `--relative` → 紅。doc 改成寫出兩個基準與這一輪的來歷。
