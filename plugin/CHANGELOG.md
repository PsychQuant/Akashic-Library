# Changelog

## [0.5.3] - 2026-08-14

- **`akashic-wos-intake` skill**（Akashic-Library #277）：WoS 型清單的匯入前 QA 閘——DOI 補查（寫回既有 `DOI` 欄）、同篇雙列偵測（early-access／erratum／重複；無 DOI 桶走標題∧年份∧type 三訊號）、機構欄容錯、intake 報告經人確認 → 另存 TSV → `import-wos --dry-run` → 寫入。分母在這一步定案。
- bootstrap 的 xlsx 匯入路徑改為先過 wos-intake（觸發競爭消解）；store 內 DOI 共用無自動偵測的缺口另記 #281。shell-only bump（binary 仍 0.5.0）。

## [0.5.2] - 2026-08-14

- **`akashic-person-verify` skill**（Akashic-Library #276）：歸戶查證——「這個 literal 作者是不是這個人」的證據鏈（Europe PMC core／ORCID／OpenAlex／出版商頁）、affiliation timeline、判定建議，經使用者確認後以 apply/reject 落 verdict；查不出來記 divergence（第三個出口）。`references/verification-traps.md` 收四類實測陷阱。shell-only bump（binary 仍 0.5.0）。
- `akashic-bootstrap` description 讓渡身分判定給 person-verify（觸發競爭消解）。

## [0.5.1] - 2026-08-14

- **Plugin shell 遷入 Akashic-Library**（#275）：plugin.json／.mcp.json／wrapper／skills 自 psychquant-claude-plugins `plugins/akashic-mcp/` 遷至本 repo `plugin/`；marketplace 改以 git-subdir source 引用本目錄。Release 流程單 repo 化——binary release 與 plugin bump 同 repo 同 commit。
- **`binary_version` 欄位**：wrapper 的 binary release tag 改讀 `binary_version`（缺席回讀 `version` 相容舊檔）——shell-only bump 不再產生不存在的 release tag（本版即例：shell 0.5.1、binary 0.5.0）。
- `akashic-bootstrap-workspace`（eval 工作區，504 檔）不隨遷入 plugin——移存本 repo `docs/skill-evals/`（不出貨給安裝者）。

## [0.5.0] - 2026-08-14

- 消解判定 ledger（Akashic-Library #232）：`akashic_resolve_people` 新增 `reject` 參數（顯式否決、entry 不動）；apply 同動作寫 `resolution-confirmed`；候選帶三態計數（confirmed/rejected/pending，不報比率）、已否決獨立 `rejected` 段、`pendingTotal` 可見
- **Store format 8**：verdict reference 需要 store format ≥ 8——format < 8 的 store 上 reject 硬擋（指路訊息）、apply 照常歸戶但跳過 verdict 並以 `verdictsSkipped` 揭露；升級程序見 Akashic-Library #247
- binary：signed + notarized universal（akashic-mcp-v0.5.0）

## [0.3.0] - 2026-08-04

### Added
- `akashic-bootstrap` skill：把資料補進 store 的完整路徑——認出手上是什麼（不要求使用者預先分類 person／work）→ 查 store 已有什麼 → 外部查詢 → 多訊號合取驗證 → 乾跑報告 → `--apply` 才寫。
  - `references/work-sources.md`：Crossref 與 Europe PMC 的實測覆蓋率與三類「像但不是」的記錄（審稿報告 DOI、preprint、同前綴會議摘要）。
  - `references/person-sources.md`：ORCID 的 employment 不回填歷史、given-names 常是英文暱稱；姓名比對靠佐證不靠拼音相似度。
  - `references/writing-to-the-store.md`：哪些操作有正規入口、哪些沒有（更新既有記錄欄位無入口，見 Akashic-Library#68）、以及沒有時的正確繞法（decode → 改 → encode，絕不手刻 YAML）。
  - `scripts/crossref_match.py`：標題→DOI 的四訊號合取比對 + 反向驗證，內建三類陷阱的自動繞行。

### Removed
- `person-search` skill —— 內容併入 `akashic-bootstrap`。它要求使用者先判定「這是 person 查詢」，但實務上人手上常是一個名字、一個 citekey、一份匯出檔，不知道也不該需要知道它對應到哪種實體形狀；分類是看內容就能決定的事。找人、消歧、聚合、追關係四段全部保留在新 skill 的步驟 1。

## [0.2.0] - 2026-07-30

### Added
- Binary v0.2.0（14→17 tools）：`akashic_libraries`（#13 membership views）、`akashic_person`（#14 人物聚合）、`akashic_files`（#18 多實體庫切換）；`akashic_search` 支援 `library` 過濾；index schema 版本機制；config schema v2（多檔案 registry，向後相容）。
- `person-search` skill（#14）：找人→消歧→聚合→追關係 workflow；需 akashic-mcp binary ≥ v0.2.0（`akashic_person` tool）。隨 akashic-mcp-v0.2.0 binary release 上架。

## 0.1.0 (2026-07-22)

- 首發：14 tools（7 讀 + 7 寫衍生層）；Akashic store 查詢/關係/圖形、person 解析逐候選 apply、Zotero 單向 pull。
