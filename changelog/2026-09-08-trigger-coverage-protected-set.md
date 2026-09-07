# 受保護集合的收錄判準：從手維護清單改成「會紅的檢查 ＋ 顯式條目」（#518，follow-up from #516 verify）

`trigger-coverage` 的逐對保證（#407 R45b）建立在 `PROTECTED = GUARDS ∪ DATA` 上，而 `DATA` 是**手維護清單**。
`literal-census.sh` 的先例把判準定成「每出現一個就手加一條」——#516 是它的第一次復發：新守衛
`plugin/tests/ndjson-abstracts-to-proposals.py` 進了 `GUARDS`，它保護的
`plugin/skills/akashic-venue-works/scripts/ndjson-abstracts-to-proposals.py` 沒進 `DATA`，
於是那一對**結構上進不了逐對迴圈**，而報表照印「無缺口」。

## 缺口不是沉默，是偽裝成一個通過

報表原本一律印 basename，而**守衛與被測檔同名**。修正前的實跑：

```
   ndjson-abstracts-to-proposals.py → （只有自己）
✓ ndjson-abstracts-to-proposals.py   讀它的守衛 1｜CI 未覆蓋 0
```

那個 `✓` 是**守衛在保護它自己**（`READS[g]` 恆含自身），不是腳本。讀報表的人會合理讀成「那支腳本被涵蓋了」。
這比沉默壞一級。而只修收錄不修顯示，會得到兩列逐字相同的結果——把隱形的缺口換成讀不懂的報表。

## 判準：兩個候選各有一個沉默方向，所以兩個都不選

| 方案 | 新增（守衛開始讀一個沒被保護的檔） | 刪除（受保護檔被刪掉） |
|---|---|---|
| 顯式 `DATA` 條目 | **靜默** ← 就是 #516 | 紅（既有 `missing` 前置檢查） |
| 放寬 glob | 綠 | **靜默**（glob 只是回傳更少的檔；#433 已記過同型：「刪檔會讓那支守衛整個離開覆蓋表，而輸出仍印 ✓ 涵蓋 6/6」） |

裁決：**顯式條目 ＋ 一道會紅的檢查**。新增由檢查擋，刪除由 `missing` 擋，兩個方向都不沉默。

## 落地

- **新檢查**：對每支守衛掃 `codeOnly()` 裡的 repo 相對路徑字面，**存在於磁碟且不在 `PROTECTED`** → 進 `fails`。
  三個條件都機械可判定，故不是 warning。抓不到的那一半（把路徑組出來的守衛）明寫在註解裡，由既有的
  `# trigger-coverage: reads` 宣告機制互補。
- **`DATA` 補 9 條**。立案時以為是一個實例，掃過 23 支守衛後是**六支守衛、九個檔**：

  | 守衛 | 讀了但原本不受保護的檔 |
  |---|---|
  | `ndjson-abstracts-to-proposals.py`（守衛） | `plugin/skills/akashic-venue-works/scripts/ndjson-abstracts-to-proposals.py` |
  | `plugin-store-format-parity.py` | `plugin/.claude-plugin/plugin.json`、`mcpb/manifest.json` |
  | `ParityTableDrift.swift` | `Sources/akashic-mcp/Server.swift`、`Sources/akashic/CLI.swift` |
  | `RuleProseGuardsMutations.swift` | `Sources/akashic-guards/MarkerParityMutationsData.swift` |
  | `TriggerCoverage.swift` | `.githooks/run-guards.sh`、`Sources/akashic-guards/main.swift` |
  | `MigratedGuardControl.swift` | `.githooks/run-guards.sh` |

  「手維護清單不自我維持」自此不是推論，是 **n=6 的量測**。其中 `plugin.json` 與 `mcpb/manifest.json`
  尤其諷刺：`plugin-store-format-parity` 整支守衛的職責就是比對這三份 store format 宣告，而改**其中兩份**
  不會觸發任何逐對檢查。`mcpb/manifest.json` 是**新檢查上線的第一次執行自己找出來的**——立案時的手工
  掃描漏了 `mcpb/` 這個路徑根。
- **報表撞名消歧**：`base()` → `label()`，`PROTECTED` 內 basename 撞名時印足以區分的路徑後綴
  （`tests/ndjson-…` vs `scripts/ndjson-…`），不撞名的維持 basename、輸出寬度不變。
- **負控**：`trigger-coverage-mutations` 加一個 case——讓某支守衛引用 `Sources/akashic-guards/ShellLex.swift`
  （存在、在守衛目錄內、但 `main.swift` 沒有對應 `case` 故永遠不是守衛），`trigger-coverage` 必須變紅並指名它。

## 量測

| | 修正前 | 修正後 |
|---|---|---|
| 受保護檔 | 41 | **49** |
| 逐對缺口 | 0（其中至少 9 對根本沒被看過） | **0**（全部進了迴圈） |
| pre-push 涵蓋 | 23/23 | 23/23 |
| 負控 case | 30 | **31，全綠** |

## 附帶修正：harness 的 baseline 跑錯了樹

每個 case 都跑在 copy 上，而 baseline 跑的是**原始 repo**。往 `DATA` 加 `mcpb/manifest.json` 之後實地踩到：
原始 repo 的 baseline 照樣綠，31 個 case 全部因為「copy 裡少了那個受保護檔」變紅、每一個都報
「沒指名 ← 訊息對它是盲的」——**31 個誤導的紅，沒有一個說得出真因**。baseline 改跑 copy 之後，
同一情形只產生一條守衛自己的話（「受保護清單裡有不存在的路徑：mcpb/manifest.json」）。
已用「暫時抽掉複製清單那條」反證這道 baseline 承重。

## 誠實邊界

- 新檢查對**動態組路徑**的守衛是盲的（`ROOT / dir / name` 不會讓字面出現）。那是宣告機制的領域，兩者互補；
  沒有便宜的方法讓一道檢查同時涵蓋兩者。
- `withCopy` 的複製清單是 `DATA` 的**第三份副本**，兩者之間沒有東西在對帳。這次是加完才發現（`CLAUDE.md`
  那次也是，#407 R27）。本次只把失敗訊息改成指名真因，**沒有**根治那個副本關係——記在 #518 的 residue。
