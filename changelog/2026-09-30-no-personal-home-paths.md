# 2026-09-30 tracked 檔不再寫死個人家目錄的絕對路徑（#688）

README 的一段 Python 範例（`booktitle` 容器的觸發條件量測）寫死了一個個人家目錄下的 store 路徑。本 repo 是公開的，而且範例換一台機器就跑不動。

## 改了什麼

量法（排除 `repos/`；`.build` 與封存目錄不是 tracked 檔，量不到）：

```bash
git grep -nE '/Users/[A-Za-z]|/home/[a-z]' -- . ':!repos/'
```

修前 16 個檔命中，逐一處置：

| 檔 | 處置 |
|---|---|
| `README.md`、`.claude/rules/entity-backlink-completeness.md` 的同一段量測腳本 | 改成 `os.path.expanduser('~/.akashic/entities')`；改後以唯讀方式對 live store 跑過一次，輸出與原意相同（`12 3`） |
| `CLAUDE.md` 兩處（2026-08-23 量到的 `core.hooksPath` 值） | 改成 `~/Developer/Akashic-Library/.githooks`，量測值不變、只拿掉使用者名稱 |
| `docs/specs/2026-07-21-akashic-library-phase1-design.md` 的佈局圖 | 同上改成 `~/…`（箭頭順帶與下面幾行對齊） |
| `docs/skill-evals/akashic-bootstrap-workspace/` 五個 `outputs/actions.md` | skill 評測當時的輸出紀錄。只把 `/Users/<名字>/` 換成 `~/`，其餘一字不動 |
| `LiteralCensus.swift` 的 doc comment、`LiteralCensusTests`（`/home` 底下的虛構家目錄 `ann`） | 保留：測試 `tilde` 比到路徑邊界的虛構 fixture |
| `SanitizationBoundaryTests`（虛構家目錄 `someone`）、`ReferenceWriteContractTests`（虛構家目錄 `x` 底下的 `file://` URL）、三個 S2 測試檔（虛構家目錄 `tester`） | 保留：虛構的 fixture 路徑，不是任何人的家目錄 |

修後命中只剩上表「保留」的 7 個檔。`changelog/` 沒有命中——本檔描述那幾個 fixture 時刻意不寫出完整路徑，否則它自己會成為第 8 個命中。
