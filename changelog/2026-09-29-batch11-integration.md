# 2026-09-29 batch11 整合：format 21、關係邊表第四次補列、零實例表第 43–47 列

batch11 由六個分支各自實作，整合在同一條分支上接起來：
- venue：#565、#567
- 文件：#595、#599（只落 repo 規則那一半）
- refs：#587
- zotero：#607、#610、#609
- entry：#544、#614
- library：#642

各分支的內容見各自的 changelog。這一份只記整合時才看得到、或整合時改判的東西。

## store format 升到 21（#642，整合時改判）

#642 的實作記的是「不 bump」：`membership` 是 registry 頂層的新鍵，舊 binary 走 tolerant-preserve 原樣保留。實作 agent 自己也標了「請整合者確認」。

整合時照 `StoreVersion` 判準表的先例改判成 bump。format 5 的 `authorized` 與 format 18 的附加 Zotero 來源都是頂層新鍵，也都 bump 了，理由相同：保留不等於遵守。format-20 binary 的 `library add` 不查規則，會對規則型與文件型 library 照樣寫進不符的成員，而且不會出聲。

- `StoreVersion.supported` 從 20 改成 21，另設門檻常數 `libraryMembershipFormat = 21`。
- 寫入閘 `LibraryStore.assertLibraryWritable`：`writeLibrary` 與 `updateLibrary` 都過它，對 format < 21 拒寫規則型與文件型。
- 主題型不閘。它不帶規則，舊 binary 的行為與新語意相同；擋它只會讓 format 20 的 store 連主題型都建不了，換不到任何保護。
- 同步改了：版本表的 21 那一列、§2.9、README、`plugin.json`／`manifest.json`、兩處釘住 20 的測試、`library` 命令的說明。

這是 Claude 代裁，使用者可以翻。翻的辦法是：在 live store 的 marker 升上去之前，把 `supported` 改回 20、拿掉寫入閘。

## 關係邊表：第四次不封閉

`entity-backlink-completeness` 的表在兩條分支上同時長出「第 16 條」：
- library 分支的 `Library.membership`
- entry 分支補上的 `Entry.akashic.sources`：#223 起就在 store 裡，表從來沒列過

整合時照合進來的順序編號：`Library.membership` 是第 16 條，`Entry.akashic.sources` 是第 17 條。表頭改成 17 條。

欄位棘輪 `BacklinkRatchetData` 早就把 `Models.sources` 列在「已裁決」裡，只是當時裁成「不是邊」。棘輪確保每個欄位都被看過，不確保看的人答對。這次把它加進 `edgeTypes`，失敗史的第四次那一段也照實改寫。

## 零實例表第 43–47 列

各分支依共用守則沒有自己加列（多個分支會撞列號），整合時依序加入：

| 列 | 來源 | 內容 |
|---|---|---|
| 43 | #565 | 合併把沿革安靜拿掉 |
| 44 | #567 | variant 的 format 14 寫入閘 |
| 45 | #587 | venue 通用 references 的上限 |
| 46 | #610 | 同一個 Zotero 來源被多筆 entry 宣稱 |
| 47 | #642 | library 成員規則的 warning |

每列都有量測腳本。`zero-instance-rows-audit` 與 `measured-numbers-audit` 都綠。

## 其他

- 受保護清單棘輪收進新的規則檔 `upstream-first-bibliographic-updates.md`（#599）。它在 CLAUDE.md 的 Rules 表裡有讀者，棘輪現為 71 條。
- README 的工具數改成實測 33。另有一處「31 tools」改成指向工具面那一段，不再複述數字。
- `akashic-verify-venue` 的誠實邊界原本寫「寫錯了沒有移除面、也沒有重號偵測面」，這在 #588 之後已經不成立。改成指向 `--remove-issn` 與 `validate` 的重號 warning，並寫明偵測面看不到的那一格：號只掛在錯的那一本時。
- `UpdateEntryCLITests` 改用 `scrubbedGitEnvironment`，並登記進 `GitSpawnHygieneTests` 的稽核清單。

## 測試與負控

新增 `LibraryMembershipFormatGateTests`（3 支）：
- `supported` 與門檻都是 21
- format 20 的 store 拒寫規則型與文件型、零寫入，改寫路徑同一道閘，主題型與未標性質照寫
- format 21 的 store 三種都收

負控：門檻放寬一格，6 個斷言失敗；還原後以 `cmp` 確認逐位元組相同。

整合後第一次全套跑出 2 支紅（`CLIIntegrationTests` 的文件型 library 兩支，共 9 個斷言），其餘 3,574 支全綠。紅的原因是新閘擋得對：那組 fixture 是 legacy 佈局的 format 1 store。改成測試開頭先跑 `akashic migrate` 遷到當前 format，檔案路徑改成 `entities/<uuid>.yaml`，兩支轉綠。

`run-guards.sh` rc=0。

## 升級前置（使用者動作）

- CLI、akashic-mcp、App 三個 binary 全部升到 v21 世代之後，才把 live store 的 `format:` 改成 21；marker 升上去之前不要 push store repo。
- live store 的 4 個 library 都還沒標性質。標成規則型或文件型需要 format 21，主題型不需要。
