# 2026-10-15 裁決史表格搬出自動載入的規則目錄

## 為什麼

`.claude/rules/` 下的每一個檔在每個 session 開頭都會自動載入。2026-10-15 在 base `f2a321e` 量（`cat .claude/rules/*.md | wc -c`）：
規則目錄共 **738,145 bytes**，加上 `CLAUDE.md` 的 42,246 bytes，一開場就是 780,391 bytes。以 UTF-8 的中文每字 3 bytes 粗估，
這是 30 萬 token 以上（依位元組推估，沒有用 tokenizer 實量）。雲端 session 因此在開始工作前就撞上 context 上限。

其中三份檔佔了 542,455 bytes（73%），而它們的大頭都是**裁決史**——逐列累積的歷輪補記，不是每次寫程式都需要讀的規則本身：

| 檔 | base（bytes） |
|---|---|
| `mcp-cli-parity.md` | 281,520 |
| `zero-instance-guards.md` | 187,777 |
| `two-kinds-of-edits.md` | 73,158 |

## 做了什麼

把這三份檔的裁決史表格（以及 `mcp-cli-parity` 的識別碼寫入面那一節）**逐位元組不改地**搬到 `docs/rulings/<同名>.md`（不自動載入）。
規則檔留下規則本身、各節標題與指向新位置的一句話；新增一列的地方改成那份檔。表格的內容一個字都沒改——
搬移以腳本切出原文段落、寫到新檔，再比對「新檔的段落＝原檔被移除的段落」。

| | base（bytes） | 之後（bytes） |
|---|---|---|
| `.claude/rules/` 合計 | 738,145 | 235,377 |
| `CLAUDE.md` | 42,246 | 42,381 |
| **自動載入合計** | **780,391** | **277,758** |
| `mcp-cli-parity.md`（規則檔） | 281,520 | 23,893 |
| `zero-instance-guards.md`（規則檔） | 187,777 | 9,175 |
| `two-kinds-of-edits.md`（規則檔） | 73,158 | 6,463 |
| `docs/rulings/mcp-cli-parity.md` | — | 259,453 |
| `docs/rulings/zero-instance-guards.md` | — | 180,620 |
| `docs/rulings/two-kinds-of-edits.md` | — | 67,915 |

`CLAUDE.md` 只改了一句：`zero-instance-guards` 那一列原本說「規則檔每一列只留核心」，搬移之後規則檔裡已經沒有列，那句話為假，
改成指向 `docs/rulings/`。其餘不動。

## 守衛（一個都沒有放寬）

讀這些表格的守衛改成讀新位置；舊位置出現表格內容時守衛照樣紅：

| 檔 | 改了什麼、為什麼 |
|---|---|
| `ZeroInstanceRowsAudit.swift` | 裁決表的列、「各列共通的東西」與自證閘改從 `docs/rulings/zero-instance-guards.md` 讀；規則檔裡又出現表列即紅（防表格分成兩半）；棘輪標記在規則檔與裁決史檔都不得出現；檔案上限的檢查也涵蓋裁決史檔；裁決史檔不在時中止，不當成「零列」 |
| `ParityTableDrift.swift` | 把規則檔與 `docs/rulings/mcp-cli-parity.md` 接成一份再抽表；裁決史檔讀不到時紅 |
| `MeasuredNumbersAudit.swift` | 掃描來源加入 `docs/rulings/*.md`（數字搬家之後仍要有時間錨） |
| `ProtectedInventory.swift` | `docs/rulings/*.md` 進受保護清單 |
| `.githooks/protected-ratchet.txt` | 對應加入三個檔（棘輪要求與清單逐字相等） |
| `.github/workflows/census-parity.yml` | `paths` 加 `docs/rulings/**`，讓改裁決史檔的 push 與 PR 會跑讀它們的守衛（trigger-coverage 的逐對要求） |
| `AuditGuardsMutationsData.swift` | 負控的注入點改指向表格的新位置（每一個 needle 在新位置恰好找到一次，`replaceAll` 的命中數與 base 相同）；新增三格負控：裁決史檔被刪、一列表格被放回規則檔、棘輪標記被注入規則檔 |
| `AuditGuardsMutations.swift`、`TriggerCoverageMutations.swift`、`PluginRootsMutations.swift` | 負控的暫存副本也複製 `docs/rulings/`，否則被測的守衛在副本裡讀不到表 |

## 驗證與誠實邊界

這一輪的環境沒有 Swift toolchain，**沒有編譯、沒有跑 `swift test`、沒有跑任何 `akashic-guards` 子命令**。做過的是以 python 照守衛的邏輯模擬：

- 負控的每一個 needle 在新目標檔裡找得到（51 個字面 needle，0 個找不到；`replaceAll` 的命中數與 base 相同）
- parity：`Server.swift` 的 35 個 MCP tool 與表格第一欄零差集；表格第一欄的 token 集合與 base 相同（65 個）
- zero-instance-rows-audit：102 列連續、表頭列數相符、規則檔 0 列、「共通」段引用全部列、棘輪標記只在量測文件
- measured-numbers-audit：23 個來源檔，沒有時間錨的「實測 N」0 個
- trigger-coverage：三個新檔與讀它們的守衛逐對有 workflow 覆蓋（缺口 0）；trigger-coverage 負控的 needle 與 base 相同
- 守衛引用的 `docs/rulings/` 路徑全部存在

模擬不是編譯器：Swift 端的型別錯誤、`copyItem` 的行為與實際輸出字串只能交給 macOS CI 的 `census-parity.yml` 確認。

程式碼註解裡仍有三處寫「見 `.claude/rules/zero-instance-guards.md` 第 N 列」（`VenueBootstrap.swift`、`Organization.swift`、
`VenueBootstrapTests.swift`）——那份規則檔指向新位置，這次沒有改註解。
