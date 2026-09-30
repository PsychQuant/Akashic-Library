# 2026-09-30 pre-push 改跑被推送的工作樹自己的 hook（#697）

`core.hooksPath` 設成共用 checkout 的絕對路徑時，從另一個 git worktree 推送，git 在那個 worktree 的根目錄執行 hook，hook 檔卻取自共用 checkout。共用 checkout 可以落後被推送的程式碼很多個 commit，於是舊的 `run-guards.sh` 檢查新的程式碼：

- 假失敗：2026-09-29 推送 #664 時，舊 hook 呼叫 #629 已刪除的 `plugin/tests/rule-coverage.sh`，全套測試跑完之後才在守衛階段失敗。
- 假通過：被推送的程式碼新增的守衛（例如 #664 的 `network-confinement`），舊 hook 不知道它存在，就不會跑。

## 改了什麼

- `.githooks/pre-push` 開頭比對 hook 檔所在的目錄與工作樹的 `.githooks`（兩者都取實體路徑，`pwd -P`）。不同、而工作樹有自己的 `.githooks/pre-push` 時，以 `exec` 改跑那一份；被改跑的那一份進來時兩者相同，不會再轉。
- 這一段放在讀 stdin 之前，被改跑的 hook 接手同一份 ref 清單（#434／#530 的早退判斷讀的就是它）。
- 工作樹沒有 `.githooks/pre-push` 時照常往下跑，stderr 說這次用的是別處的 hook。
- README〈CI〉的安裝說明補一句：`core.hooksPath` 用相對路徑 `.githooks`，git 會以各 worktree 的根目錄解析它。

## 生效的前提

hook 是從 `core.hooksPath` 指的那個檔開始執行的。設定仍是絕對路徑時，改跑這一段要等**共用 checkout 的那一份** hook 也含有它才會發生；在那之前，從 worktree 推送仍跑舊 hook。把設定改成相對路徑（`git config core.hooksPath .githooks`）則不需要這一段就不會發生，這一段是設定是絕對路徑時的保險。這台機器的共用 checkout 目前是絕對路徑，改不改是使用者的決定，本次沒有動。

## 測試與負控

`PrePushHookTests.testHookRunsTheWorktreesOwnHookWhenInvokedFromElsewhere`：用真 hook 的複本扮共用 checkout 那一份、一支 stub 扮工作樹自己的 hook，三格：

1. 工作樹有自己的 hook → 結束碼是 stub 的（42）、stub 收到同一份 stdin、共用那份沒有呼叫 swift。
2. 工作樹沒有 `.githooks` → 照常往下跑，stderr 帶警告。
3. 工作樹的 `.githooks` 是指回同一個目錄的 symlink → 不改跑、不印任何 #697 的訊息。

負控（每次以備份還原、`cmp` 確認）：

| 改動 | 結果 |
|---|---|
| 拿掉 `exec` | 第 1 格紅 3 項（結束碼 0、stub 沒收到 stdin、swift 被呼叫） |
| 改跑之前先讀掉 stdin | 第 1 格紅 1 項（stub 收到空字串） |
| `pwd -P` 改成 `pwd` | 第 3 格紅（symlink 被當成另一個目錄而改跑） |

## 誠實邊界

- 改跑的是**工作樹**的 hook，不是被推送的 commit 的 hook。工作樹有未 commit 的修改時兩者不同；這與 hook 一直以來檢查工作樹（`swift build`、`swift test` 都讀工作樹）的語意一致，本次不改。
- 同一個絕對路徑出現在公開文件裡的隱私面由 #693 處理，本次不動。
