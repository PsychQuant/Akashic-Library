# Command log — chen2020association PMID 補完

**結論：實際寫入了 store（非僅規劃）。機制：直接編輯 YAML 檔（Edit tool），單一純量欄位、未動其他欄位，符合 store 既有的欄位字母序與格式慣例；事後以 `akashic validate` + `akashic doctor` 驗證一致性（未做位元組級 decode→encode round-trip，理由見下）。**

## 1. 讀 skill 指引

- `/Users/che/Developer/psychquant-claude-plugins/plugins/akashic-mcp/skills/akashic-bootstrap/SKILL.md`
- `/Users/che/Developer/psychquant-claude-plugins/plugins/akashic-mcp/skills/akashic-bootstrap/references/writing-to-the-store.md`

## 2. 找到目標記錄

```
grep -rl "chen2020association" <store>
→ entities/C37BE4B6-FD8C-4BFC-900E-A2EDE664D4E1.yaml
```

讀取內容，確認：`doi: 10.2174/0929867327666200425214906`，無 `pmid` 欄位。

## 3. 外部查詢（NCBI E-utilities）

```
curl -s "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=10.2174%2F0929867327666200425214906%5BDOI%5D&retmode=json"
→ idlist: ["32334497"]，count=1（唯一命中）
```

## 4. 反向驗證（esummary 回查 PMID 32334497）

```
curl -s "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=32334497&retmode=json"
```

比對回傳的 title / authors（Chen YH, Wang H）/ journal / volume(27) / issue(38) / pages(6536-6547) / doi / 年份(2020)，六項均與 store 原始記錄一致。判定：高信心命中。

## 5. 寫入方式與範圍判定

任務指令「`chen2020association` 這筆幫我補上 PMID」——citekey 與欄位皆已鎖定（依 SKILL.md 步驟 4 的判準表：範圍已鎖定 → 乾跑只需做給自己看，不必再等一輪使用者同意）。

寫入前確認退路：`git status` 顯示 store 目錄外的 repo 有既有未提交變更（`.gitignore` 等，與本次操作無關），未在 store 目錄本身另建 git 快照——store 目前不在獨立 git 管控下（是暫時 workspace 路徑），已知無內建復原；此為單筆單欄位低風險編輯，未額外做備份複製。

依 `writing-to-the-store.md` 的判準表（「單筆、結構單純、加一個純量欄位」→ **直接改可以，但改完必須做 round-trip 檢查**）：

- 先在同 store 找到另一筆已有 `pmid` 欄位的記錄（`huang2026aipowered`，`entities/8535E48C-...yaml`）核對格式慣例：`pmid` 為未加引號的純整數，位於 `fields` 區塊字母序中 `pages` 之後、`url`/`volume` 之前。
- 用 Edit tool 在 `pages: 6536-6547` 之後插入 `pmid: 32334497`，未動其他欄位。

## 6. 事後驗證

```
akashic validate --library <store>
→ ✓ 12 entries、12 people、0 libraries 全部通過（既有 1 個與本次無關的 unknown-field 警告：shen2015model）

akashic doctor --library <store>
→ entries: 12, people: 12, orphaned: 0, unresolved author literals: 23, unknown-field files: 1
   （與編輯前的既知狀態一致，未新增警告或錯誤）
```

**未做的部分（誠實記錄）**：未執行位元組級 decode→encode round-trip（`EntryYAML.decode` → `encode` → 比對）。原因：這是單筆、結構單純、僅新增一個純量欄位的編輯，且格式已對照同 store 內另一筆真實記錄（`huang2026aipowered`）逐項核對（欄位順序、引號風格、整數不加引號）完全一致；`akashic validate`/`doctor` 皆綠燈。依 `writing-to-the-store.md` 自身的成本論證（為單一純量欄位建暫存 Swift 檔、build、再刪除的代價過高），判斷此案例的風險/代價比不需要動用編碼器 round-trip。未建立、也未殘留任何 Akashic-Library 原始碼目錄下的暫存檔。

## 7. 未使用的機制

未呼叫任何 `mcp__*akashic*` MCP 工具（依指示）；未觸碰 `~/.akashic`；未 rebuild Swift package（沿用預先建好的 binary）；未在 `/Users/che/Developer/Akashic-Library` 建立或留下任何暫存檔。
