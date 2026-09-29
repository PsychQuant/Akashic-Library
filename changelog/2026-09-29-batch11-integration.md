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
- `akashic-verify-venue` 的誠實邊界原本寫「寫錯了沒有移除面、也沒有重號偵測面」，這在 #588 之後已經不成立。改成指向 `--remove-issn` 與 `validate` 的重號 warning，並寫明偵測面看不到的那一格：號只掛在錯的那一本時。**（R1 verify：同一個檔還有兩處過期敘述沒改——步驟 3(c) 的「全庫沒有重號掃描」「沒有移除面，只能手改 YAML」、以及「非陣列會被 `argList` 折成空陣列」（#561 起是拒絕）。整合時只 grep 了一處。已在 `2026-09-29-library-membership-r1.md` 補改。）**
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
- **marker 升到 21 之前，live store 上規則型保護不存在**（#642 R1 verify 補記）：live marker 是 18，規則型與文件型標不上（`set-kind`／`create` 撞寫入閘），
  唯一標得上的性質是 `topic`——而 `topic` 不檢查成員，等於回到 #642 起因的狀態。**不要為了讓 `library add` 恢復而改標 `topic`**；
  在 marker 升上去之前，4 個 unmarked library 的 `add` 被拒絕是預期的、也是唯一的保護。拒絕訊息、validate 的 warning、`akashic-venue-works` 都已寫明這一點。
- **`authorize-names --apply` 與 `migrate` 會無條件把 marker 寫成 `StoreVersion.supported`**（`AuthorizedNameMigration.swift`、`StoreMigration.swift`；過度升級是既有行為，
  它們各自只需要自己那一代的版本）。`supported` 從 20 變 21 之後，在 live store 上跑其中任何一個，都會**提早替你把 marker 升到 21**，繞過上面「三個 binary 都升級之後才手動改」的順序。
  升級順序沒走完之前不要跑它們；`authorize-names` 改成只升到它需要的版本沒做（需要先確認 marker < 該版本時的寫法對 format-1 legacy store 不會破壞佈局判定，那不是一行的事），`migrate` 升到 `supported` 是它的語意。
- **release 時 `binary_version` 要同批 bump**：`plugin.json` 與 `manifest.json` 的描述已寫「Store format 21」（`plugin-store-format-parity` 守衛要求描述與 `StoreVersion.supported` 一致），
  但 `binary_version` 仍是 0.12.1（format 20 世代的 binary）。format 19、20 的 bump 同型；在發出 v21 世代的 binary 之前，plugin 的描述比實際下載到的 binary 先走一步。
