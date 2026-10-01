# 2026-10-01 公開 repo 的工作樹不再帶私有識別資訊（#693）

本 repo 是公開的。#599 的驗證（2026-09-29）順帶列出幾處仍帶私有識別資訊的地方。使用者 2026-10-01 裁決：「歷史留著，只改工作樹」。

- **第 1 項（main 的歷史）不重寫**：重寫是破壞性、不可逆的，會讓 clone、tag 與 issue 裡的 commit 連結失效，而已公開過的內容收不回快取與 fork。
- **第 2–4 項改成角色描述**，本檔記改了哪裡、刻意沒改哪裡。本檔自己不寫出被拿掉的名字、路徑與連結。

## 量法

```bash
git grep -nI -i '<私有下游 repo 的名字>' -- . ':!repos/'
git grep -nI -E '/Users/[A-Za-z]|/home/[a-z]|~/Develope[r]' -- . ':!repos/'
git grep -n 'github.com/<個人帳號>/' -- . ':!repos/' ':!.gitmodules'
git grep -nI -E '無存取權|repo 為 private|repo 是 private|private repo，|（private）|外部讀者取不到|private，無' -- . ':!repos/' ':!changelog/' ':!openspec/changes/archive/' ':!plugin/CHANGELOG.md'
```

尖括號是刻意不寫出的值（寫出來本檔就會成為下一個命中）。

**第 3 行排除 `.gitmodules`（R1 verify 第 18／29 則）**：它列著兩個 `mcps/` submodule 的 URL，URL 裡帶個人帳號名，指向的兩個 repo 都是公開的（2026-10-01 `gh repo view --json visibility` 查，PUBLIC），內容沒有問題；不排除的話量法會在目前的樹上命中那兩行，下一個重跑的人會當成漏改。

## 第 2 項：私有下游 repo 的名字與 issue 號

改前 18 個 tracked 檔命中那個名字。改成「一個私有下游 repo」「那張 issue」這類角色描述，issue 號一併拿掉（同一段裡沒帶名字的 `#7`、`#9` 指的也是那個 repo 的 issue，會被讀成本 repo 的 issue，一起改）：

| 檔 | 內容 |
|---|---|
| `Sources/AkashicCore/Models.swift`、`Tests/AkashicKitTests/PagesShapeGuardTests.swift` | `pages` 形狀守衛的起因 |
| `changelog/2026-08-21-pages-shape-guard.md` | 起因的 issue、它的 Expected、另一張改吃 `export-tables --view iss` 的 issue |
| `changelog/2026-09-23-multi-zotero-sources.md` | 三組攣生的出處 |
| `changelog/2026-09-26-export-tables-corporate-authors.md` | JSON 交付物的出處 |
| `.claude/rules/identity-is-judged-not-matched.md` | lab meeting 簡報的所在位置（連同檔案路徑） |
| `README.md`、`Sources/AkashicStoreIO/ViewDefinition.swift`、`Tests/AkashicKitTests/ViewDefinitionTests.swift` | view 判準被推到 store 之外的實例（連同那個 repo 裡的腳本檔名） |
| `Sources/AkashicMCPKit/UpdatePerson.swift`、`Sources/akashic/FormatCommands.swift` | 外部寫入者的例子 |
| `plugin/skills/akashic-promote-literals/SKILL.md`、`plugin/skills/akashic-venue-works/SKILL.md`、`plugin/skills/akashic-venue-works/references/site-access.md` | 查證動線與頁碼事件的出處 |

## 第 3 項：`CLAUDE.md` 的本機路徑與私有 repo 連結

- 2026-08-23 量到的 `core.hooksPath` 值（兩處）：#688 已把使用者名稱換成 `~`，這次改成角色——「以絕對路徑指向本機主 repo（共用 checkout）的 `.githooks`」。
- 設計原則上游那個私有 repo 的連結拿掉，名字留著、註明是使用者的私有 repo、外部讀者讀不到。名字留著是因為 `CLAUDE.md` 與規則檔都以它指稱那份協定，裁決要拿掉的是連結。同一個連結另外出現在 `.claude/rules/disambiguate-before-irreversible-writes.md`（兩處）與 `plugin/skills/akashic-promote-literals/SKILL.md`，一起改。

## 第 4 項：過時的「本 repo 為 private」

本 repo 公開之後，「private，無存取權者取不到」不再是讀不到的原因；plugin 散文裡那些規則檔與原始碼讀不到，是因為它們不隨 plugin 出貨、plugin 安裝處沒有它們。改成實際的原因：

| 檔 | 改法 |
|---|---|
| `plugin/rules/assertions-must-be-measured.md` | 第 5 節的揭露與「請有存取權的人補」、〈這份文件犯過的錯〉表的「就地重述讀不到的規範」一列、自我量測表兩列的括號、最後一段 verify comment 的括號 |
| `plugin/skills/akashic-bootstrap/references/work-sources.md`（兩處）、`plugin/skills/akashic-disambiguate/SKILL.md`、`plugin/skills/akashic-import-wos/SKILL.md`、`plugin/skills/akashic-promote-literals/SKILL.md` | 「不隨 plugin 出貨，plugin 安裝處讀不到」 |
| `plugin/skills/akashic-fetch-fulltext/references/publishers.md`（兩處） | 原本已寫「plugin 安裝處讀不到」，拿掉前面的「該 repo 為 private」 |
| `plugin/bin/akashic-mcp-wrapper.sh` | 下載失敗訊息。**首版（本列原本寫的「原因是下載走 `gh`、要先 `gh auth login`」）是錯的**，R1 verify 更正：repo 公開之後 `gh` 不可用時 `curl` 退路拿得到，走到那則 ERROR 代表兩條都失敗，原因是沒有網路、該版本的 asset 還沒上傳（#630 的情形）、或下載的檔不是 Mach-O，不是 `gh` 沒登入。改成中性的訊息：說出兩次嘗試（`gh release download <tag>`，沒有安裝 `gh` 時寫「略過」；再 `curl` 公開的 release 網址，網址印出來）與可能的原因，並明說不需要 `gh auth login`（見文末 R1 verify 一節） |
| `README.md` 的 submodule 註解 | `mcps/` 的兩個 submodule 都是公開 repo（2026-10-01 以 `gh repo view --json visibility` 查），改成「optional」 |
| `CLAUDE.md` 耗時表下方一段 | 拿掉「（private repo，外部讀者取不到）」——那是本 repo 自己的規則檔 |
| `Sources/AkashicStoreIO/LiteralCensus.swift` | 普查輸出指向 `docs/store-format.md` 的兩句 |
| `Sources/akashic-guards/RuleProseGuards.swift` | 第 1 項的理由註解（相對路徑在 plugin 安裝處指不到東西；blob 深連結點得開，但指的是 main 的現況）與第 5 項未涵蓋時的訊息 |
| `Sources/akashic-guards/RuleProseGuardsMutations.swift` | 負控注入字串的揭露詞改成「讀不到」「跑不了」，仍在 `DISCLOSE` 的字面內，負控 14/14 |
| `Sources/akashic-guards/AuditGuardsMutations.swift`、`TriggerCoverageMutations.swift` | 註解裡的括號 |

## 刻意沒改的

| 位置 | 理由 |
|---|---|
| ~~`openspec/changes/archive/` 底下三個檔（五處提到那個私有下游 repo 的名字）~~ | ~~封存目錄受 archive-first 保護，要使用者先解鎖；本次沒有解鎖~~ → **已改**，見文末〈補記〉 |
| ~~`Akashic-Library.code-workspace` 的第二個 folder~~ | ~~那是 VS Code workspace 指向本機一個相鄰 checkout 的相對路徑……要不要從版控拿掉由使用者決定~~ → **已取消追蹤**，見文末〈補記〉（含其他 checkout 下次更新時會失去這個檔） |
| `.gitmodules` 的兩個 submodule URL | 帶個人帳號名，指向兩個公開 repo（`gh repo view` 查 PUBLIC）；量法第 3 行已排除它（見上） |
| `openspec/changes/**/.openspec.yaml` 的 `created_by`／`archived_by` | Spectra 自動寫入的作者 email，與 git commit 的作者欄同一份資訊；不在這次裁決的範圍 |
| `changelog/`、`plugin/CHANGELOG.md` 裡關於 repo 當時是 private 的敘述 | 歷史紀錄，描述的是當時的狀態 |
| `plugin/rules/assertions-must-be-measured.md` 的「揭露不對稱」一列、立案一的標題與裁決表、2026-08-21 量的「兩個 repo 皆為 private」、「本 repo 當時是 private」 | 前兩者講的是另一個仍然私有的 repo；後兩者是有日期的觀察或明寫「當時」 |
| `docs/specs/2026-07-21-*`、`docs/specs/2026-07-22-*` 的「repo 維持 private」 | 有日期的設計文件，記的是當時的決定。同一份 `2026-07-21-*` 設計文件另有一處**裸的個人帳號名**（「remote 推 <個人帳號> private」，不是 URL，量法第 3 行的 pattern 掃不到）：同樣是當時的決定，不改（R1 verify 第 18 則） |
| `.gitignore` 第 16 行、`docs/explainers/yaml-alias-dos.md` 的「remote 是 private」 | 講的是使用者的資料 repo（store），它仍是私有的 |
| `README.md` 與 `docs/store-format.md` 的「判準不是 repo 公開/私密」 | 一般原則，不是在說本 repo |
| 測試裡的虛構家目錄、`docs/skill-evals/` 評測紀錄與 `docs/specs/2026-07-21-*` 佈局圖裡以 `~` 開頭的路徑 | #688 已逐一處置（虛構 fixture 保留；真實路徑拿掉使用者名稱） |
| `RuleProseGuards.swift` 的 `DISCLOSE` 仍收 `private` | 守衛行為不在這次範圍；`plugin/CHANGELOG.md` 的歷史段落仍以它揭露 |

## 誠實邊界

- 公開 main 的歷史照舊讀得到這些內容（第 1 項的裁決）。**「全樹 0 處」只對 git 工作樹成立**：公開 issue 的標題與內文（R1 verify 量到 36 則提到那個私有下游 repo 的名字，例如 #274 的標題）、wiki 的 git 歷史不在這次裁決內，沒有動。
- 量法是字面 grep：換個寫法的私有識別資訊（例如只寫 issue 號、不寫 repo 名）掃不到。第 2 項那兩處不帶名字的 issue 號是逐段讀才找到的。
- 沒有新增守衛防止日後又寫進去（#688 R1 verify 記過同一件事，也沒做）。

## 補記（2026-10-01，使用者裁決）

- `Akashic-Library.code-workspace` 取消追蹤、檔案留在本機，`.gitignore` 加 `*.code-workspace`：它的資料夾路徑指向本機其他 checkout，改路徑會讓工作區壞掉，所以不改內容、只不再隨公開 repo 出貨。
- `changelog/2026-09-23-multi-zotero-sources.md` 的共享群組 library 名稱改成「一個共用的 Zotero 群組」。
- `openspec/changes/archive/` 的 5 處（3 個檔）：使用者解鎖封存保護後改成角色描述（「一個私有下游 repo／專案」），改完重新上鎖。改後全樹（不含 `repos/`）字面 grep 那個名字 0 處。

- **取消追蹤的工作區檔，其他 checkout 下次更新時會失去它**（R1 verify 第 7／28／37 則，2026-10-01 實測：本機主 checkout 仍追蹤這個檔、沒有修改；把那個 commit 快轉進去，git 會把這個未修改的追蹤檔從工作樹刪除）。上一則說的「檔案留在本機」只對執行 `git rm --cached` 的那份 checkout 成立；`.gitignore` 的 `*.code-workspace` 只擋日後被重新加入，救不回已被刪的檔。**更新其他 checkout 之前**先備份，或更新之後從取消追蹤之前的版本取回（內容 3,349 bytes）：

  ```bash
  git show f4255fe0^:Akashic-Library.code-workspace > Akashic-Library.code-workspace
  ```

  `f4255fe0` 是「工作區檔取消追蹤、共享群組名改成角色描述」那個 commit 在 main 上的雜湊；同一個 commit 在別的分支上是 `46ab7e99`，兩個 `^` 取出的內容逐位元組相同。取回之後檔案是被 `.gitignore` 擋掉的未追蹤檔，不會再被 git 動到。

## R1 verify 之後（2026-10-01）

六席驗證（與 #611、#692、#708 同一次）對本張的裁決是 HIGH 0、MEDIUM 0；下面是 LOW 的處置。

| R1 # | 一句話 | 處置 |
|---|---|---|
| 15、16、26、27 | wrapper 的下載失敗訊息說「下載走 gh、要先 `gh auth login`」，但 repo 已公開、腳本有 `curl` 退路，這句把人指錯方向 | 改成中性的兩行：已試的兩條路（`gh release download <tag> --repo <repo>`，沒有 `gh` 時寫「沒有安裝，略過」；再 `curl <公開的 release 網址>`）、可能原因（沒有網路、該版本的 asset 還沒上傳、網路擋住 github.com），並明說不需要 `gh auth login`。`WrapperDownloadTests` 加兩支：兩條路都失敗時的訊息（兩次嘗試、網址、原因、不得再出現「需先 gh auth login」）與沒有 `gh` 時的訊息 |
| 17 | `plugin/skills/akashic-disambiguate/SKILL.md` 同一段相鄰一句仍寫「請有存取權的人補」 | 改成「請讀得到的人補」，與兄弟檔一致。量法第 4 行的 pattern 只涵蓋「無存取權」，沒涵蓋「有存取權」，所以先前漏掉；目前 `git grep '有存取權的人' -- plugin` 0 處 |
| 18、29 | 量法第 3 行命中 `.gitmodules`；「刻意沒改的」表與〈補記〉互相矛盾；`docs/specs/` 裡有一處裸的個人帳號名 | 量法第 3 行排除 `.gitmodules` 並說明；表中兩列劃掉、指向〈補記〉；裸的帳號名記進表（當時的決定，不改） |
| 7、28、37 | 取消追蹤的工作區檔在其他 checkout 下次更新時被刪，不是「留在本機」 | 上面〈補記〉的最後一則：寫明，並附復原指令 |
| 33 | `plugin/CHANGELOG.md` 沒記 wrapper 與 verify-venue 的行為改動 | 補上兩個條目（#693 的 wrapper、#692 的 skill） |
| 26（後半） | wrapper 下載後不驗完整性就執行：`gh` 路徑完全沒有檢查、`curl` 路徑只看 `file` 輸出有 Mach-O，沒有用 release 流程已產出的 `.sha256` 與 Developer ID 簽章 | **不在這一輪做**（那是新增驗證、不是訊息更正），記為後續：雜湊核對（`.sha256`）與 `codesign --verify` 要另案；這是每次 session 啟動都會跑的自動下載執行路徑 |
| 36 | 公開 issue 的標題與內文（36 則，含 #274 的標題）、wiki 的 git 歷史仍帶私有 repo 名；「全樹 0 處」只對 git 工作樹成立 | **不改**：使用者的裁決只涵蓋工作樹與 main 的歷史；issue 標題可編輯、與 main 歷史性質不同，要不要改由使用者決定，這一輪沒有動任何 GitHub issue。〈誠實邊界〉第一條補一句，讀者不會把「全樹 0 處」讀成整個公開面都乾淨 |

### wrapper 訊息的負控

反向編輯一處 → `swift build --build-tests` → 跑 `WrapperDownloadTests`（`Executed 4 tests`）→ 還原後 `cmp` 對備份相同。

| # | 反向編輯 | 結果 |
|---|---|---|
| W1 | 原因那行改回「下載走 gh，需先 gh auth login」 | 紅：3 個斷言、1 支（原因、「不需要 gh auth login」、不得再出現「需先 gh auth login」） |
| W2 | 拿掉 `curl` 那次嘗試與網址 | 紅：2 支 |
| W3 | 沒有安裝 `gh` 時不說「略過」 | 紅：1 支 |
