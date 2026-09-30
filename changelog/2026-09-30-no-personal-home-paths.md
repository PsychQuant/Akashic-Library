# 2026-09-30 tracked 檔不再寫死個人家目錄的絕對路徑（#688）

README 的一段 Python 範例（`booktitle` 容器的觸發條件量測）寫死了一個個人家目錄下的 store 路徑。本 repo 是公開的，而且範例換一台機器就跑不動。

## 改了什麼

量法（排除 `repos/`——submodule 是別的 repo；`.build` 不是 tracked 檔。封存目錄 `openspec/changes/archive/` **是** tracked 的、在量測範圍內，0 命中；R1 verify 更正先前「封存目錄不是 tracked 檔」的說法）：

```bash
git grep -nE '/Users/[A-Za-z]|/home/[a-z]' -- . ':!repos/'
```

修前 16 個檔命中，逐一處置：

| 檔 | 處置 |
|---|---|
| `README.md`、`.claude/rules/entity-backlink-completeness.md` 的同一段量測腳本 | 改成 `os.path.expanduser('~/.akashic/entities')`；改後以唯讀方式對 live store 跑過一次，輸出與原意相同（`12 3`） |
| `CLAUDE.md` 兩處（2026-08-23 量到的 `core.hooksPath` 值） | 改成 `~/Developer/Akashic-Library/.githooks`，只拿掉使用者名稱。git 印的是絕對路徑，所以這已不是逐字的量測輸出（R1 verify 更正先前「量測值不變」；第一處補了一句說明） |
| `docs/specs/2026-07-21-akashic-library-phase1-design.md` 的佈局圖 | 同上改成 `~/…`（箭頭順帶與下面幾行對齊） |
| `docs/skill-evals/akashic-bootstrap-workspace/` 五個 `outputs/actions.md` | skill 評測當時的輸出紀錄。只把 `/Users/<名字>/` 換成 `~/`，其餘一字不動 |
| `LiteralCensus.swift` 的 doc comment、`LiteralCensusTests`（`/home` 底下的虛構家目錄 `ann`） | 保留：測試 `tilde` 比到路徑邊界的虛構 fixture |
| `SanitizationBoundaryTests`（虛構家目錄 `someone`）、`ReferenceWriteContractTests`（虛構家目錄 `x` 底下的 `file://` URL）、三個 S2 測試檔（虛構家目錄 `tester`） | 保留：虛構的 fixture 路徑，不是任何人的家目錄 |

修後命中只剩上表「保留」的 7 個檔。`changelog/` 沒有命中——本檔描述那幾個 fixture 時刻意不寫出完整路徑，否則它自己會成為第 8 個命中。

## R1 verify 修正（2026-09-30）

六席（requirements、logic、security、regression、devil's advocate、Codex）。與本 issue 有關的兩個 LOW：

- **封存目錄是 tracked 的**（requirements、logic、DA 三席）。`git ls-files` 列得到 `openspec/changes/archive/` 底下 152 個檔，上面的 `git grep` 也掃了它們（0 命中）。結論不變，說明改成「在範圍內、0 命中」。
- **量測範例對空目錄安靜地印 `0 0`**（logic 席）。`README.md` 與 `.claude/rules/entity-backlink-completeness.md` 的同一段腳本：store 不在 `~/.akashic`（設了 `AKASHIC_HOME`、或換了機器）時 glob 回空，印出的 `0 0` 讀起來是「觸發條件未達」。現在先讀 `AKASHIC_HOME`（沒設才用 `~/.akashic`），glob 為空時以非零結束並說「沒量到，不是 0」。改後唯讀跑 live store 仍是 `12 3`；指向不存在的目錄時 rc=1。
- `CLAUDE.md` 的 `core.hooksPath` 值不再是逐字的 git 輸出（logic、regression 兩席），第一處補了一句說明，本檔的表同步更正。`docs/skill-evals/` 的 `actions.md` 也已不是逐字的執行紀錄，上表原本就寫明「只把 `/Users/<名字>/` 換成 `~/`」。
- 不修：security 席提到沒有守衛防止日後又貼進一條絕對路徑、`docs/skill-evals` 的 fixture 帶第三方學術 email、git 歷史仍含舊路徑。三者都不在 #688 的範圍，issue 也沒有要求改寫歷史。
