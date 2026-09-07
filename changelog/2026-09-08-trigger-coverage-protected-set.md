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

## 判準：兩個候選各有一個沉默方向

| 方案 | 新增（守衛開始讀一個沒被保護的檔） | 刪除（受保護檔被刪掉） |
|---|---|---|
| 顯式 `DATA` 條目 | **靜默** ← 就是 #516 | 紅（既有 `missing` 前置檢查） |
| 放寬 glob | 綠 | **靜默**（glob 只是回傳更少的檔；#433 已記過同型：「刪檔會讓那支守衛整個離開覆蓋表，而輸出仍印 ✓ 涵蓋 6/6」） |

裁決：**顯式條目 ＋ 一道會紅的檢查**。

> **這一版原本在這裡寫「新增由檢查擋，刪除由 `missing` 擋，兩個方向都不沉默」。那句話是假的，
> 被 R1 verify 的 Devil's Advocate 用實測推翻、coordinator 獨立重現。** 保留這段而不是刪掉它，
> 是因為本 repo 的規則要求把失敗史寫進文件本身——見下方「誠實邊界」的逐項量測。

## 落地

- **新檢查**：對每支守衛掃 `codeOnly()` 裡的 repo 相對路徑字面，**存在於磁碟且不在 `PROTECTED`** → 進 `fails`。
  三個條件都是機械可判定的事實，故不是 warning。
- **`DATA` 補 8 條**（**8 個相異檔／6 支守衛／9 個 (守衛,檔) 配對**——`.githooks/run-guards.sh` 被兩支守衛
  引用，在對數裡算兩次、在檔數裡算一次）。其中**這道檢查自己找出 5 支守衛／8 對／7 個檔**：

  | 守衛 | 讀了但原本不受保護的檔 | 這道檢查看得到嗎 |
  |---|---|---|
  | `ndjson-abstracts-to-proposals.py`（守衛） | `plugin/skills/akashic-venue-works/scripts/ndjson-abstracts-to-proposals.py` | ✅ |
  | `plugin-store-format-parity.py` | `plugin/.claude-plugin/plugin.json`、`mcpb/manifest.json` | ✅ |
  | `ParityTableDrift.swift` | `Sources/akashic-mcp/Server.swift`、`Sources/akashic/CLI.swift` | ✅ |
  | `TriggerCoverage.swift` | `.githooks/run-guards.sh`、`Sources/akashic-guards/main.swift` | ✅ |
  | `MigratedGuardControl.swift` | `.githooks/run-guards.sh` | ✅ |
  | **`RuleProseGuards.swift`** | **`Sources/akashic-guards/MarkerParityMutationsData.swift`** | ❌ **手補的** |

  **最後一列不是這道檢查找的。** 它的讀取是 `RuleProseGuards.swift:285` 的
  `abspath("\(plugin)/../Sources/akashic-guards/MarkerParityMutationsData.swift")`——組出來的路徑，
  引號不緊鄰，檢查看不到；那一條是**人照著報表手補**的。（本檔第一版把它歸給
  `RuleProseGuardsMutations.swift`，而那裡**只是註解**提到它——歸錯守衛，又把一列非檢查產出的東西
  列進「由檢查找出」的表。R1 verify 的 requirements 席抓到。）

  「手維護清單不自我維持」自此不是推論，是 **n=6 的量測**。其中 `plugin.json` 與 `mcpb/manifest.json`
  尤其諷刺：`plugin-store-format-parity` 整支守衛的職責就是比對這三份 store format 宣告，而改**其中兩份**
  不會觸發任何逐對檢查。`mcpb/manifest.json` 是**新檢查上線的第一次執行自己找出來的**——立案時的手工
  掃描漏了 `mcpb/` 這個路徑根。
- **報表撞名消歧**：`base()` → `label()`，`PROTECTED` 內 basename 撞名時印足以區分的路徑後綴
  （`tests/ndjson-…` vs `scripts/ndjson-…`），不撞名的維持 basename、輸出寬度不變。
  **失敗訊息裡的違規檔則一律印完整路徑**——`label()` 的唯一性是相對 `PROTECTED` 求的，而違規檔依定義
  不在其中，用 `label()` 會印出另一個而且**已受保護**的檔（R1 verify 三席獨立命中）。印完整路徑同時
  給出要貼進 `DATA` 的字串。
- **負控**：`trigger-coverage-mutations` 加一個 case——讓某支守衛引用 `Sources/akashic-guards/ShellLex.swift`
  （存在、在守衛目錄內、但 `main.swift` 沒有對應 `case` 故永遠不是守衛），`trigger-coverage` 必須變紅並指名它。

## 量測

| | 修正前 | 修正後 |
|---|---|---|
| 受保護檔 | 41 | **49** |
| 逐對缺口 | 0（其中至少 9 對根本沒被看過） | **0**（全部進了迴圈） |
| pre-push 涵蓋 | 23/23 | 23/23 |
| 負控 case | 30 | **31，全綠** |

> **「逐對缺口 0」的 CI 那一半在世界裡到不了。** 8 個新受保護檔的路徑確實全在
> `census-parity.yml` 的 `paths:` 裡（逐條核對過），但那個 workflow 的 `:131` 與 `:137` 兩個 step 跑
> **已刪除**的 `.py`（`marker-parity-mutations.py`、`audit-guards-mutations.py`，`989ac64` Python 歸零時刪的），
> 而本 diff 的 CI 覆蓋唯一來源 `run-guards.sh` 在 `:149`。同一個 job、循序在前、**無 `continue-on-error`、
> 無 `if:`** → job 在 `:131` 就終止。所以這一格是**在 `trigger-coverage` 的模型內成立**。
> 這是 #521 家族（守衛的輸入消失了而它仍然綠）的第三個實例。

## 誠實邊界（全部經 R1 verify 實測，不是推測）

**1. 新增方向只涵蓋「引號緊鄰完整路徑」的寫法。** 這道 ratchet 保證的**不是**「守衛的依賴都受保護」，
而是「**恰好那樣寫出來的**依賴都受保護」。五種自然寫法靜默通過：字串串接、`./` 前綴、雙斜線、
`os.path.join(...)`、組出來的路徑（`abspath("\(plugin)/../…")`——上表最後一列就踩到）。

**2. `# trigger-coverage: reads` 宣告機制補不了這個洞。** 本檔第一版寫「兩者互補」——說反了。
`declared()` 只能在 `PROTECTED` **內部做選取**，永遠無法把一個檔**帶進** `PROTECTED`；實測對一個未受保護
的檔只寫宣告會**多兩條紅**，不是覆蓋。它互補的是**歸屬**，不是**收錄**。

**3. 刪除方向只涵蓋 14/49。** `missing` 檢查「清單裡列的路徑還在不在磁碟上」，而 glob 產生的成員永遠不會
「列了卻不存在」。`PROTECTED` 的 49 條裡只有 14 條是顯式的（`GUARDS` 整組是 glob 23 條、`DATA` 自己還有
兩個 glob 12 條）。**35/49（71%）刪掉不會出聲**——實測刪掉一整支守衛 `plugin/tests/review-claim-audit.sh`
→ 守衛 23→22、受保護 49→48、**rc=0、照印「無缺口」**。也就是說：拿來否決 glob 的那個性質，在被選中的
方案裡已經涵蓋 71%。

**4. 「從 `DATA` 拿掉一條」與「檔案被刪掉」是兩件事。** 前者只有在某支守衛的程式碼裡有那條路徑的引號
字面時才會紅。14 條顯式條目裡 **5 條看不見**：`hash-merging-ranges.txt`、`derive-hash-extenders.swift`、
`MarkerParityMutationsData.swift`、`Venue.swift`（四條完全靜默），與 `CLAUDE.md`（會紅，但紅的是「宣告
解析到零」這個別的機制）。**`MarkerParityMutationsData.swift` 是最尖的一格**：本輪自己補進來的、是真依賴，
而拿掉它一聲不吭——#518 的標題所描述的形狀，發生在 #518 自己修完之後、在它自己加的條目上。

**5. `PATH_ROOTS` 自己是手維護白名單，而且已經漏過一次。** 13 個根目錄漏著 `AkashicApp/`、`Tools/`、
`Vendor/`、`mcps/`、`repos/`、`scripts/` 六個；`mcpb/` 之所以在裡面，正因為它第一次就被漏掉。
同一個失效搬了一層。零實例。

**6. `DATA` 住在一支守衛裡**，所以每條顯式條目的 basename 都逐字出現在 `TriggerCoverage.swift` 的原始碼裡，
於是 `READS` 的 basename 子串比對讓它自動獲得一個 phantom reader（實測它被判定讀 15 個受保護檔，真的只有 3 個；
main 上是 6 個 phantom，本輪加倍到 12）。後果不只是計數噪音：往一個 `census-parity.yml` 沒涵蓋的路徑根加條目，
會產生指向 phantom 依賴的**真紅**。

**7. `withCopy` 的複製清單是 `DATA` 的第三份副本**，兩者之間沒有東西在對帳。這次是加完才發現（`CLAUDE.md`
那次也是，#407 R27）。本次只把失敗訊息改成指名真因（baseline 改跑 copy），**沒有**根治那個副本關係。

**8. 檔案不存在時直接跳過**——守衛引用已刪除的檔那一半是 #521，刻意不在本輪做。

上述 1／3／4／5／6 的根治都需要在 `zero-instance-guards` 加一列裁決（例如「`PROTECTED.count` 下降時出聲」），
而那是人要做的判斷，不是實作可以順手決定的——追蹤 #522。
