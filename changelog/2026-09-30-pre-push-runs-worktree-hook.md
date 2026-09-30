# 2026-09-30 pre-push 改跑被推送的工作樹自己的 hook（#697）

`core.hooksPath` 設成共用 checkout 的絕對路徑時，從另一個 git worktree 推送，git 在那個 worktree 的根目錄執行 hook，hook 檔卻取自共用 checkout。共用 checkout 可以落後被推送的程式碼很多個 commit，於是舊的 `run-guards.sh` 檢查新的程式碼：

- 假失敗：2026-09-29 推送 #664 時，舊 hook 呼叫 #629 已刪除的 `plugin/tests/rule-coverage.sh`，全套測試跑完之後才在守衛階段失敗。
- 假通過：被推送的程式碼新增的守衛（例如 #664 的 `network-confinement`），舊 hook 不知道它存在，就不會跑。

## 改了什麼

- `.githooks/pre-push` 開頭比對 hook 檔所在的目錄與工作樹的 `.githooks`（兩者都取實體路徑，`pwd -P`）。不同、而工作樹有自己的 `.githooks/pre-push` 時，以 `exec` 改跑那一份；被改跑的那一份進來時兩者相同，不會再轉。
- 這一段放在讀 stdin 之前，被改跑的 hook 接手同一份 ref 清單（#434／#530 的早退判斷讀的就是它）。
- 工作樹沒有 `.githooks/pre-push` 時照常往下跑，stderr 說這次用的是別處的 hook。
- README〈CI〉的安裝說明補一句：`core.hooksPath` 用相對路徑 `.githooks`，git 會以各 worktree 的根目錄解析它。
- CLAUDE.md 的 hooksPath 三值分析補一段 2026-09-30 補記（上面三值寫於 2026-08，本機已沒有「指向主 repo」這一值）。

## 生效的前提

hook 是從 `core.hooksPath` 指的那個檔開始執行的。設定是絕對路徑時，改跑這一段要等**共用 checkout 的那一份** hook 也含有它才會發生。設定是相對路徑 `.githooks` 時，git 以各 worktree 的根目錄解析它，這個問題本來就不會發生；這一段是設定是絕對路徑時的保險。

使用者 2026-09-30 裁決把這台機器的 `core.hooksPath` 改成相對路徑（先前是共用 checkout 的絕對路徑），同日已改。相對路徑的代價寫進 README：工作樹裡沒有 `.githooks/pre-push`（例如 checkout 了它存在之前的 commit）時，git 找不到 hook 就什麼都不跑、也不出聲。

## 測試與負控

`PrePushHookTests.testHookRunsTheWorktreesOwnHookWhenInvokedFromElsewhere` 用真 hook 的複本扮共用 checkout 那一份，工作樹那一份用 stub（記下參數、stdin、被呼叫次數）或真 hook 的複本。hook 以兩個參數（remote 名稱、URL）呼叫，與 git 相同：

1. 工作樹的 hook 失敗（42）→ 結束碼是它的、它收到同一份 stdin 與兩個參數、共用那份沒有呼叫 swift。
2. 工作樹的 hook 通過（0）→ 它恰好跑一次、共用那份沒有呼叫 swift、沒有警告。**`exec` 與一般呼叫只有這一格分得開**：一般呼叫在第 1 格也會因 `set -e` 把 42 傳出來，而在這一格會讓共用那份在 stdin 已被讀走之後接著跑完整個 gate（R1 verify logic 與 devil's advocate 實測）。
3. 工作樹沒有 `.githooks` → 照常往下跑（swift build、swift test 各一次），stderr 帶警告。
4. 工作樹有 `.githooks/` 但沒有 `pre-push` → 同 3。
5. 工作樹的 `.githooks` 是指回同一個目錄的 symlink → 不改跑、不印任何 #697 的訊息。
6. 工作樹放的是真 hook 的複本 → 改跑恰好一次，gate 恰好跑一次（被改跑的那份不再轉）。
7. 設了 CDPATH，而 CDPATH 裡另有一個 `.githooks` → 仍改跑工作樹那一份，CDPATH 裡的 hook 沒有被執行。

hook 在 R1 之後另改兩處：比對之前先 `unset CDPATH`（設了 CDPATH 時 `cd` 會把目的目錄印到 stdout，`$(...)` 收到兩行，改跑靜默失效）；改跑用 `/bin/bash`，與本檔 shebang 相同（先前是 PATH 上的 `bash`）。

負控（每次以備份還原、`cmp` 確認；每一次都先確認輸出有 `Executed 1 test` 那一行再讀失敗數）：

| 改動 | 結果 |
|---|---|
| a. 只拿掉 `exec` 這個字（改成一般呼叫） | 第 2 格紅（swift 被呼叫、有警告）、第 6 格紅（gate 跑了兩次） |
| b. 只把 `exec` 那一行換成 `:`（訊息照印、不改跑） | 第 1 格紅（結束碼、stdin、參數、swift）、第 2 格紅、第 7 格紅；第 6 格不紅——訊息在 `exec` 之前印，gate 也恰好跑一次 |
| c. 改跑之前先讀掉 stdin | 第 1 格紅（stub 收到空字串） |
| d. 兩邊的 `pwd -P` 都改成 `pwd` | 第 5 格紅（symlink 被當成另一個目錄而改跑） |
| e. `exec` 那一行拿掉 `"$@"` | 第 1 格紅（參數沒有轉交） |
| f. 拿掉 `[ -f "$hook_tree_dir/pre-push" ]` | 第 4 格紅（`exec` 一個不存在的檔） |
| g. 拿掉 `unset CDPATH` | 第 7 格紅（改跑落到 CDPATH 裡的那一份） |

R1 報告的負控表第一列寫「拿掉 `exec` → 第 1 格紅 3 項」，量的其實是 b；只拿掉 `exec` 一字時那三格都不紅（R1 verify 第 2、4 則）。上表 a 是改正後的量測。

d 第一次跑是綠的：那一次緊接在停掉一個卡住的舊負控 runner 之後，最可能是舊 runner 的 EXIT trap 在新的一次執行中途把 hook 還原了；原因沒有查明。單獨重跑一次是紅（第 5 格，XCTAssertFalse：印了改跑訊息）。另一個形狀——只把 `hook_tree_dir` 改成 `pwd`、`hook_self_dir` 仍是 `pwd -P`——在第 5 格會無限 `exec`，測試卡住而不是失敗，所以不當成負控；它說明兩邊都要取實體路徑。

## 誠實邊界

- 改跑的是**工作樹**的 hook，不是被推送的 commit 的 hook。工作樹有未 commit 的修改時兩者不同；這與 hook 一直以來檢查工作樹（`swift build`、`swift test` 都讀工作樹）的語意一致，本次不改。
- 同一個絕對路徑出現在公開文件裡的隱私面由 #693 處理，本次不動。
- 信任錨點移到被推送的樹本身：工作樹的 `.githooks/pre-push` 可以自我核准（R1 security 第 34 則）。這與相對路徑的 `core.hooksPath` 相同，而 pre-push 本來就只是本機的品質閘，不是安全邊界。
- 比對依賴 cwd 是工作樹根目錄：git 呼叫 hook 時成立；手動從子目錄執行時會對「其實就是工作樹自己的那一份」印出「工作樹沒有 .githooks/pre-push」的警告（R1 第 27、42 則），不影響結果。
