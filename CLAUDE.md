<!-- SPECTRA:START v1.0.2 -->

# Spectra Instructions

This project uses Spectra for Spec-Driven Development(SDD). Specs live in `openspec/specs/`, change proposals in `openspec/changes/`.

## Use `/spectra-*` skills when:

- A discussion needs structure before coding → `/spectra-discuss`
- User wants to plan, propose, or design a change → `/spectra-propose`
- Tasks are ready to implement → `/spectra-apply`
- There's an in-progress change to continue → `/spectra-ingest`
- User asks about specs or how something works → `/spectra-ask`
- Implementation is done → `/spectra-archive`
- Commit only files related to a specific change → `/spectra-commit`

## Workflow

discuss? → propose → apply ⇄ ingest → archive

- `discuss` is optional — skip if requirements are clear
- Requirements change mid-work? Plan mode → `ingest` → resume `apply`

## Parked Changes

Changes can be parked（暫存）— temporarily moved out of `openspec/changes/`. Parked changes won't appear in `spectra list` but can be found with `spectra list --parked`. To restore: `spectra unpark <name>`. The `/spectra-apply` and `/spectra-ingest` skills handle parked changes automatically.

<!-- SPECTRA:END -->

## Parked change 不進版本控制（#72）

> 上面那段由 Spectra 自動維護，這段是本 repo 的規則。

`spectra park` 把 change 移到 **`.git/spectra-app/changes/`**。`.git/` 底下的內容 git 從不追蹤（那是它自己的目錄），所以：

- 連 `.gitignore` 規則都不需要——它根本沒進入候選集合，`git check-ignore` 也不回報任何東西
- **parked change 的全部設計產出只存在於單一台機器上**
- `spectra list --parked` 與 `spectra status` 都正常回報（artifacts 全部 `done`），從工具的角度看不出任何異常

生命週期裡因此有一個裸露窗口：

```
propose ──→ park ──────────────→ apply ──→ archive
            └── 不在版控 ─────────┘        └─ 進版控 ─┘
```

**規則**：park 只用於「今天不做、而且丟了也無所謂」的東西。任何要保留的設計——尤其是對應著仍開啟 issue 的——**不要停在 parked 狀態**。要暫時挪開就 `spectra unpark <name>` 搬回 `openspec/changes/`（那裡是 tracked）再 commit；`openspec/changes/` 裡有未完成的 change 不是問題，那本來就是它的用途。

實際踩過：三個 change、18 檔、124 KB 的設計工作曾同時停在 parked（#72）。park 位置本身屬 Spectra.app 的行為，不在本 repo 可修範圍。

## Rules

**`.claude/rules/` 下的每一條規則，本 repo 的所有實踐都必須遵守。** 它們不是建議、
不是風格偏好、也不是「參考一下」——是本 repo 已經付過代價換來的裁決。

三條執行語意：

1. **規則勝過臨場判斷。** 當某條規則與「這次這樣做比較快／比較合理」衝突時，以規則為準。
   規則存在的理由通常正是「當時也覺得那樣比較合理」。
2. **覺得規則錯了就顯式改規則**，不要靜默偏離。改法是在同一個變更裡改那個檔案、寫下
   為什麼、附上量測——每條規則的「觸發過的實例」段就是為此而存在。
3. **規則的封閉列舉不得依性質相似類推。** 好幾條規則刻意用「封閉表 ＋ 逐列理由」而不給
   總括判準（理由見全域 `common-spec-prose-enumeration`）。遇到表裡沒有的情形，**加一列**，
   不要從既有列推導。

寫給會照著執行的人與模型看。

| 規則 | 一句話 |
|---|---|
| [lossless-intake.md](.claude/rules/lossless-intake.md) | 匯入不得有損——來源給了什麼就收什麼；不收的只有秘密與隱私邊界兩類，且丟棄必須報出來 |
| [literal-first-then-key.md](.claude/rules/literal-first-then-key.md) | 每個 entity reference 先以 literal 進庫、再經顯式消歧升格 key——進庫不猜、升格留 verdict；終局是全域 literal 歸零（#303/#304） |
| [identity-is-judged-not-matched.md](.claude/rules/identity-is-judged-not-matched.md) | 身分是**判定**出來的不是**比對**出來的——`literal → key` 是 AI 判斷函數，不得由字串謂詞單獨做出；Jaccard 實測同一人 0.40／不同人 0.50，提名是 recall 不是判定 |
| [mcp-cli-parity.md](.claude/rules/mcp-cli-parity.md) | 新增任一面（MCP／CLI）的能力時必須裁決另一面——三張封閉裁決表（MCP／CLI-only／橫切選項）+ 四步機械稽核（#259 起雙向，#310 補橫切面），缺口不得安靜累積 |
| [entity-backlink-completeness.md](.claude/rules/entity-backlink-completeness.md) | 呈現 entity 時所有相關 entity 都要看得到——反向一律現算不儲存；可儲存的關係邊是一張封閉列舉表＋可執行稽核（條數見該檔，摘要刻意不複述——複述過的數字會與表分岔） |
| [no-compat-fallback.md](.claude/rules/no-compat-fallback.md) | 不留相容 fallback——要改格式就一次改完全部；例外須離開 default 位置、附退場量測、退場即刪 |
| [replace-endnote-and-zotero.md](.claude/rules/replace-endnote-and-zotero.md) | 目標是完全取代 EndNote 與 Zotero——檔案住 Akashic、位元組複製進 store、對 Zotero 的 pull 是過渡、能力缺口記 issue 不得靠「回去用 Zotero」帶過 |
| [apa7-is-the-work-floor.md](.claude/rules/apa7-is-the-work-floor.md) | 一筆 work 的資訊下限是「能產出正確的 APA7 參考文獻」——ch10 的 113 例是驗收矩陣、`Entry.type` 的值域須**細分**（非等於）ch10 的 16 節；下限不是上限，分類可更細不可更粗 |
| [zero-instance-guards.md](.claude/rules/zero-instance-guards.md) | 為「還沒發生過的形狀」寫守衛是一列一列裁決出來的——封閉決策表＋理由欄同列，刻意不給總括判準（那會在邊界上長出沒人同意的答案）|
| [blocked-issues-must-be-scannable.md](.claude/rules/blocked-issues-must-be-scannable.md) | 被阻塞的 issue 必須把「在等什麼」寫在工具掃得到的三個位置之一，不得只寫在散文裡——四次「空等」的實測（#314）＋哪些「等」需要標記的封閉裁決表 |

> **plugin 另有自己的規則目錄。** `plugin/rules/` 隨 plugin 走（plugin 安裝到哪，規則就在哪），
> 由 skill 以相對路徑引用——**不像上表那樣自動注入**。目前一條：
> [`assertions-must-be-measured`](plugin/rules/assertions-must-be-measured.md)，管「寫下一句可能是錯的話
> 之前先回答四個問題」（不是分類法——理由見該檔）。刻意不列進上表：那張表的語意是「自動注入的 repo 規則」，
> 混進去會讓那個性質變成謊話（#407）。
>
> **那條規則有守衛，而守衛有 negative control。** `plugin/tests/`（覆蓋、散文，
> 純 python／bash）與 `plugin/skills/akashic-literal-campaign/scripts/tests/`
> （store-marker parity ＋ hash 表漂移，拿建好的 CLI／Swift 當 oracle）。**支數不寫死**——每輪都在長，而寫死的計數會與目錄分岔（這正是本 repo 反覆記過的形狀）。要知道有幾支就跑 `ls plugin/tests/*.{sh,py} plugin/skills/*/scripts/tests/*.{sh,py}`。
>
> **觸發點已接上，但 2026-08-21 實測：一個都沒在跑**（#407 R8 verify）：
>
> | 觸發點 | 檔案 | 實際執行 |
> |---|---|---|
> | `.githooks/pre-push`（全部） | ✅ | ❌ `core.hooksPath` 指向**主 repo** 的 `.githooks`，那份對這些守衛 0 命中——worktree 的修改不是實際生效的那份。**merge 到 main 後自癒** |
> | `plugin-guards.yml`（ubuntu，1×） | ✅ | ⬜ 從未執行（branch 未 push） |
> | `census-parity.yml`（macOS；只在 census／parity 測試／生成表／oracle 改動時觸發） | ✅ | ❌ macOS runner 帳務擱置——main 最近 8 次 CI run 全部 `failure` 且 **steps=0**（runner 層拒跑） |
>
> **目前唯一實際跑過它們的路徑是本機手動執行。** 這一格寫在這裡，是因為
> 「接上觸發點」與「觸發點會跑」是兩件事，而把後者寫成既成事實正是這條規則要防的
> 那種斷言——它在 R8 verify 被具名。
>
> **上表的「已接上」那一欄現在有守衛在量**（`plugin/tests/trigger-coverage.py`，
> #407 R19）。它問的不是聯集而是**逐對**：對每個受保護檔案 × 每個讀它的守衛，
> 是否存在一個 workflow 同時在該檔改動時觸發、且執行該守衛。判準取自
> `census-parity.yml` 自己的檔頭——「兩者合起來涵蓋五支」在檔案集合的聯集意義上
> 成立，在任一次變更的意義上不成立，而後者才是觸發點要保證的事。當下實測**零缺口**，
> pre-push 涵蓋全部。**右欄（「實際執行」）它量不到**——那需要 CI 真的跑起來，
> 而那三格的狀態如上。
>
> **`ci.yml` 的 `paths-ignore` 仍排除 `plugin/**`**——理由已從「plugin 沒有測試
> 讀取」換成純計費（macOS runner 10×）。它另有一個 parity step，但那是第二層：
> 它的觸發是 push-to-main ＋ 該 paths-ignore，所以**只改 census 時它反而被跳過**
> ——`census-parity.yml` 補的正是那一格（#407 R7 verify：守衛的觸發條件與它保護
> 的檔案剛好互斥）。
>
> 兩支 negative control 各自證明對應的守衛會紅，並且**mutate 一份 copy 而不是
> 出貨檔**：前一版就地改寫版控中的檔案，跨模型審查在審查期間實際觀察到 tracked
> 的 `literal-census.sh` 出現三種被注入的狀態（#407 R6）。
