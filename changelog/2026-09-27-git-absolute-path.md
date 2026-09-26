# 2026-09-27 store 的 git 呼叫釘死 `/usr/bin/git`（#585）

`LibraryStore.git` 以 `/usr/bin/env git` 啟動子程序，環境只剝除 `GIT_*`（#239），`PATH` 原樣繼承。#558 R3 verify 用一支二十行的 `git` shim 排在 `PATH` 前面，讓可回溯性閘從「拒絕消歧」變成「✓ 併入、刪檔、rc 0」。#239 的 doc 說「答案不該被呼叫者的環境改變」，但 `PATH` 決定的是**哪個程式回答問題**，那句話對它不成立。

**裁決（使用者 2026-09-27）：釘死 `/usr/bin/git`。**

- `LibraryStore.gitExecutable = "/usr/bin/git"`：直接執行這個路徑，不經 `PATH`。它不存在時 `git(_:in:)` 回 nil，呼叫端一律 fail-closed；`cannotRun` 的訊息點名這個路徑與 #585。
- 代價是裁決時接受的：把 git 放在別處的環境（nix 一類）這幾個命令會具名拒絕。macOS 上 `/usr/bin/git` 一定存在。
- 測試 fixture（`GitFixture.run`／`capture`）同批改成絕對路徑，issue 點名它與產品碼同形。
- `GitSpawnHygieneTests` 原本只用 argv 裡的 `"git",` 字面偵測「哪裡起了 git」。改成直接執行絕對路徑之後，這個字面消失，守衛會看不見這幾個呼叫點，所以偵測條件擴充成也認 `"/usr/bin/git"`。
- **擴充偵測當場抓到一個既有漏洞**：`PrePushHookTests` 直接執行 `/usr/bin/git`，卻**沒有剝除 `GIT_*`**。舊偵測一直看不到它，而它正是在 pre-push hook 裡跑的測試，hook 環境帶著 `GIT_DIR`（#234／#239 的形狀）。已補上剝除。
- 測試：`GitSpawnHygieneTests.testAShimEarlierInPathDoesNotAnswerForGit`，把一個會印 `SHIM-ANSWERED` 的 shim 放在 `PATH` 最前面，驗證答案來自真的 git。負控：`LibraryStore.git` 改回經 `/usr/bin/env`，2 個斷言失敗。
- 範圍：store 的 git 呼叫全部經 `LibraryStore.git`。`TractatusDocs` 的 corpus 管線另有兩處 `/usr/bin/env git`，不是 store 的閘，不在本張範圍。
