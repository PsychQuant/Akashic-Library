# 2026-09-27 repoint／demote 刪判定記錄之前要求 git 裡有副本；CLI 全列被刪的判定（#573）

`ResolutionLedger.supersede`（#554 D20）讓 `resolve-venues --repoint`／`--demote` 在寫新判定時**刪掉**同一配對的相反判定。doc 與兩面描述都說代價由 git 承擔（「歷史留在 git」），但**沒有任何東西確認 git 在**：repoint／demote 的前置只有 store format。campaign 的常態節奏是 apply 很多筆再一次 commit，正是最常沒 commit 的時候——那時被刪的判定沒有任何副本。另外，`verdictsRetired` 兩面都截 20 筆，CLI 的操作者無法列舉第 21 筆之後被刪了什麼。

**裁決（使用者 2026-09-27）：issue 列的 (a) 與 (c) 兩項都做。**

- **(a) 刪之前要求 tracked＋clean**：repoint／demote **真的會退役判定時**，在任何寫入之前，對那些會失去判定的 venue 檔跑 `resolve-divergence` 同一支檢查（`LibraryStore.filesNotSafelyRecoverable`：tracked、無未提交修改、HEAD 可解析、無 assume-unchanged／skip-worktree）。
  - 不過就整批拒絕、零寫入，訊息列出每個檔的原因、指路「先 commit 再跑」。
  - store 根本不在 git 工作樹時另說這一件（先前那支檢查對非工作樹會回「無法執行 git」，指錯原因）。
  - 實際上每次 repoint／demote 都會退役該配對的 confirmed，所以這等於「repoint／demote 之前要 commit」。這是 issue 寫明、裁決時接受的取捨。
- **(c) CLI 面全列**：`resolveVenues` 多一個 `retiredLimit` 參數。MCP 面傳 20（輸出進 LLM context），CLI 面傳 nil 全列，與 `validate` 的面級截斷分工一致。`mcp-cli-parity` 的 `akashic_resolve_venues` 列記為有記錄的差異。
- (b)（把被刪的判定寫成一筆 retired 記錄）沒有選。
- 兩面描述（MCP tool 描述、CLI 的 `--repoint`／`--demote` help）寫明新前置。
- 測試（`VenueAuthorizedWriteTests`）：
  - `testRetiringVerdictsIsRefusedOutsideGit`：拒絕，判定與邊都沒被改；
  - `testRetiringVerdictsIsRefusedWhenTheVenueFileIsDirty`：apply 之後沒 commit 就 demote → 點名那個 venue 與「未提交」；commit 之後就過；
  - `testVerdictsRetiredIsNotCappedForTheCLIFace`：26 筆全列。

  負控：拿掉 demote 路徑的閘，前兩支 5 個斷言失敗。
- 既有 17 處 repoint／demote 測試改成先 commit store 再呼叫（新增測試 helper `StoreGitCommit`，同樣剝除 `GIT_*`）。這正是新契約要使用者做的事，測試照同一個流程走，產品碼沒有開任何後門。
