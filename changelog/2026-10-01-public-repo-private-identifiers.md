# 2026-10-01 公開 repo 的工作樹不再帶私有識別資訊（#693）

本 repo 是公開的。#599 的驗證（2026-09-29）順帶列出幾處仍帶私有識別資訊的地方。使用者 2026-10-01 裁決：「歷史留著，只改工作樹」。

- **第 1 項（main 的歷史）不重寫**：重寫是破壞性、不可逆的，會讓 clone、tag 與 issue 裡的 commit 連結失效，而已公開過的內容收不回快取與 fork。
- **第 2–4 項改成角色描述**，本檔記改了哪裡、刻意沒改哪裡。本檔自己不寫出被拿掉的名字、路徑與連結。

## 量法

```bash
git grep -nI -i '<私有下游 repo 的名字>' -- . ':!repos/'
git grep -nI -E '/Users/[A-Za-z]|/home/[a-z]|~/Develope[r]' -- . ':!repos/'
git grep -n 'github.com/<個人帳號>/' -- . ':!repos/'
git grep -nI -E '無存取權|repo 為 private|repo 是 private|private repo，|（private）|外部讀者取不到|private，無' -- . ':!repos/' ':!changelog/' ':!openspec/changes/archive/' ':!plugin/CHANGELOG.md'
```

尖括號是刻意不寫出的值（寫出來本檔就會成為下一個命中）。

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
| `plugin/bin/akashic-mcp-wrapper.sh` | 下載失敗訊息：原因是下載走 `gh`、要先 `gh auth login`，不是 repo 私有 |
| `README.md` 的 submodule 註解 | `mcps/` 的兩個 submodule 都是公開 repo（2026-10-01 以 `gh repo view --json visibility` 查），改成「optional」 |
| `CLAUDE.md` 耗時表下方一段 | 拿掉「（private repo，外部讀者取不到）」——那是本 repo 自己的規則檔 |
| `Sources/AkashicStoreIO/LiteralCensus.swift` | 普查輸出指向 `docs/store-format.md` 的兩句 |
| `Sources/akashic-guards/RuleProseGuards.swift` | 第 1 項的理由註解（相對路徑在 plugin 安裝處指不到東西；blob 深連結點得開，但指的是 main 的現況）與第 5 項未涵蓋時的訊息 |
| `Sources/akashic-guards/RuleProseGuardsMutations.swift` | 負控注入字串的揭露詞改成「讀不到」「跑不了」，仍在 `DISCLOSE` 的字面內，負控 14/14 |
| `Sources/akashic-guards/AuditGuardsMutations.swift`、`TriggerCoverageMutations.swift` | 註解裡的括號 |

## 刻意沒改的

| 位置 | 理由 |
|---|---|
| `openspec/changes/archive/` 底下三個檔（五處提到那個私有下游 repo 的名字） | 封存目錄受 archive-first 保護，要使用者先解鎖；本次沒有解鎖 |
| `Akashic-Library.code-workspace` 的第二個 folder | 那是 VS Code workspace 指向本機一個相鄰 checkout 的相對路徑，路徑裡有那個私有 repo 的名字。它是設定不是散文，改成角色描述會讓 workspace 打不開；要不要從版控拿掉由使用者決定 |
| `openspec/changes/**/.openspec.yaml` 的 `created_by`／`archived_by` | Spectra 自動寫入的作者 email，與 git commit 的作者欄同一份資訊；不在這次裁決的範圍 |
| `changelog/`、`plugin/CHANGELOG.md` 裡關於 repo 當時是 private 的敘述 | 歷史紀錄，描述的是當時的狀態 |
| `plugin/rules/assertions-must-be-measured.md` 的「揭露不對稱」一列、立案一的標題與裁決表、2026-08-21 量的「兩個 repo 皆為 private」、「本 repo 當時是 private」 | 前兩者講的是另一個仍然私有的 repo；後兩者是有日期的觀察或明寫「當時」 |
| `docs/specs/2026-07-21-*`、`docs/specs/2026-07-22-*` 的「repo 維持 private」 | 有日期的設計文件，記的是當時的決定 |
| `.gitignore` 第 16 行、`docs/explainers/yaml-alias-dos.md` 的「remote 是 private」 | 講的是使用者的資料 repo（store），它仍是私有的 |
| `README.md` 與 `docs/store-format.md` 的「判準不是 repo 公開/私密」 | 一般原則，不是在說本 repo |
| 測試裡的虛構家目錄、`docs/skill-evals/` 評測紀錄與 `docs/specs/2026-07-21-*` 佈局圖裡以 `~` 開頭的路徑 | #688 已逐一處置（虛構 fixture 保留；真實路徑拿掉使用者名稱） |
| `RuleProseGuards.swift` 的 `DISCLOSE` 仍收 `private` | 守衛行為不在這次範圍；`plugin/CHANGELOG.md` 的歷史段落仍以它揭露 |

## 誠實邊界

- 公開 main 的歷史照舊讀得到這些內容（第 1 項的裁決）。
- 量法是字面 grep：換個寫法的私有識別資訊（例如只寫 issue 號、不寫 repo 名）掃不到。第 2 項那兩處不帶名字的 issue 號是逐段讀才找到的。
- 沒有新增守衛防止日後又寫進去（#688 R1 verify 記過同一件事，也沒做）。
