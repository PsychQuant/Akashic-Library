# 2026-09-27 #543／#585／#573／#653／#650／#637／#638／#644／#577 的 R2 verify 修正

R2 ensemble 6 席齊：0 HIGH、15 MEDIUM。依停損規則，verify 迴圈在 R2 結束；以下 MEDIUM 屬本輪範圍，就地修正。其中幾條是 R1 修正自己引進的回歸。

## git 那一層（#573／#585）

R1 與 `be495327` 各引進了一個回歸：

- **內容比對誤判乾淨的檔**（logic 席在 scratch repo 重現三種）：以 CRLF commit 之後才設 `core.autocrlf`、`* text=auto`、被追蹤的 symlink。`git status` 說乾淨，`hash-object` 卻與 HEAD 不同，閘因此永久拒絕，還叫人 commit 一個沒有東西可 commit 的檔。
  - 修法：拿掉 `hash-object`。改在暫存路徑以 `read-tree HEAD` 建一份沒有任何 stat 資訊的 index，拿它再比一次 HEAD：每個檔都得重讀內容，判斷乾淨的邏輯仍是 git 自己的。真正的 index 不動。
  - 第一版改用 `update-index --really-refresh`，不行：它只是不理會 assume-unchanged，stat 照信。測試抓到。
  - 只有重讀內容才看得到的修改另給一個理由：指向 `git update-index --really-refresh`，不叫人「先 commit」（requirements 席：那種情形下 `git status` 說乾淨，commit 也會說沒有東西）。
- **`GIT_CONFIG_GLOBAL=/dev/null` 打太寬**（logic、regression 兩席）：它連帶關掉 `safe.directory`（別的 uid 擁有的 store 被誤報成「無法執行 git」）與 `core.excludesFile`（`migrate-person-identity` 把 `.DS_Store` 當成 dirty）。改回保留 global config。
- **global attributes 仍然到得了閘**（security 席；DA 以真 binary 確認）：`~/.config/git/attributes` 不受 global config 開關影響，一行 `*.yaml ident` 就讓修改在比對時折回原樣。`git(_:in:)` 帶 `-c core.attributesFile=/dev/null`，環境設 `GIT_ATTR_NOSYSTEM=1`。
- `scrubbedGitEnvironment` 的 doc 改成逐條列出關掉了哪些向量、哪些仍是邊界（repo 自己的 `.git/config`、`.gitattributes`、`.git/info/attributes`，以及被 repo 自己的 attributes 點名的 global filter driver），不再宣稱「呼叫者的環境不影響答案」。
- **測試**：
  - `testGlobalAttributesFileCannotHideAnEdit`（ident）；
  - `testFilesGitConsidersCleanAreNotReportedDirty`（CRLF + autocrlf、symlink）；
  - 污染 index 那支改驗「stat 快取」的專屬理由。
- **負控**：拿掉 `core.attributesFile` 覆寫 → 3 紅；讓全新 index 不生效 → 2 紅。碰 git 的相關測試 601 支 0 失敗。

## #637

- **措辭與正典規則矛盾**（DA）：「DOI 相同只是提名、不是同一性證據」違反 `identity-is-judged-not-matched`——該規則說 DOI 相等是充分的身分判定。不拒絕的真正理由是 erratum 會與原文共用 DOI（規則的「識別碼終結指涉、不終結描述」），拒絕會擋掉這類合法記錄。code doc、CLI、MCP 描述、parity 列、changelog 都已改。
- **`create-entry --dry-run` 不回報命中**（DA、requirements）：這讓命中只在寫入之後才看得到，正是 `disambiguate-before-irreversible-writes` 要防的順序。`createEntries` 加 `dryRun`，CLI 的乾跑改成開 store 走同一條路徑，並印出命中。
- **命中算到寫入失敗的同批記錄**（Codex 等四席）：命中只對寫成功的記錄報；比對表也只加寫成功的那筆。
- **測試**：`testDryRunReportsDOIHitsAndWritesNothing`、`testFailedBatchMateIsNotReportedAsAnExistingHit`。負控（把比對移回寫入之前）紅。

## #638

- 我改寫時把 `year_from` 寫成 `yearFrom`，MCP 會默默忽略——正是本張要修的那種缺陷，又造了一次（regression 席）。已改。
- 我寫「沒有以 DOI 查詢的入口」是錯的（DA 實測）：`enrich` 的乾跑（提案只帶 `doi`）零寫入，會回命中、`ambiguous` 或 `notFound`。第 1 步改成先用它，另加 `create-entry --dry-run`。
- 表名是 `publication` 不是 `publications`；它只有 CLI 面，而且 `doi` 欄只放第一個 DOI（#657）。

## #644

- `--prose-only` 對不存在或空的根印「2/2 PASS」（logic 席）：空掃描不是通過，改成具名拒絕。負控 harness 新增一格，並改從 `plugin-roots` 取根，不寫死 discovery 的路徑。harness 16/16。

## #577

- pre-push 的 bin-path 核對在兩邊都解析不到時，會因「兩個空字串相等」而通過。改成兩邊都必須解析得到。
- 補 `.build/debug` 不存在、是真目錄、兩邊都解析不到三個情形；最後一個才區分得出舊的比較，負控紅。

## #653／#650

- `DestructiveTargetGateTests` 的三份寫死清單沒跟上 #653 的五個命令（R1 第 19 列，R2 指出沒有下文）：收成一份 `enumerated` 共用，補上五個命令；rename 與 rename-person 驗無條件呼叫，migrate 族與 resolve-divergence 驗 `!dryRun`。負控（從表拿掉 rename-person）紅。
- migrate 乾跑提示裡的 store 路徑沒有做 shell 引號，有空白就貼不回去（Codex）：可以原樣安全顯示的加單引號；需要逃脫才能顯示的印佔位字。

## #543

- DOI 清單有重複值時，`DOI` 欄與 addendum 會各印一次同一個號（R1 第 21 列 (a)）：兩面共用 `otherDOIs`，以正規形去重。
- TeX 逃脫補 `<`、`>`、`|`（DA：SICI 形的 DOI 含 `<>`，OT1 編碼下印成 ¡¿）。

## R1 finding 的處置（R2 第 5 列：沒記下的就等於「全處理了」）

- **第 19、21(a)、26 列**：本輪修正，見上。repoint 路徑的負向測試 `testRepointIsRefusedWhenTheFromVenueFileIsDirty` 的負控紅。
- **第 21(c) 列（大寫的 `ADDENDUM` 鍵）**：不處理。live store 10,789 個 `fields` 鍵全是小寫，屬零實例。
- **第 26 列後半（CLI 的 `retiredLimit: nil` 沒有經 binary 測）**：不另加。service 層的 `testVerdictsRetiredIsNotCappedForTheCLIFace` 驗 nil 全列；CLI 的接線是一個參數，要造出多於 20 筆被退役的判定需要手改 store，成本與收益不成比例。
- **第 28 列（`filesNotSafelyRecoverable`／`isInsideVersionedWorkTree` 改成 public）**：它們原本就是 AkashicStoreIO 對外的 git 檢查，#573 讓 AkashicMCPKit 呼叫它們，API 擴大是必要的，在此記錄。
- **第 38 列**：#653 changelog 把 rename 算成遷移，已改。
- **第 39 列（un-split 同樣靠「歷史留在 git」卻沒有 git 前置）**：開 #659 待裁決。

## 其他

- #617 那份 skill 有一句在 #637 之後已經不成立（「create-entry 遇到已在庫的 DOI 不會回報」），那個檔屬另一個 session，已在 #617 留言告知。
