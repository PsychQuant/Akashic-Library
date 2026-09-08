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
| 顯式 `DATA` 條目 | **靜默** ← 就是 #516 | **紅 19/19**（`missing` 逐條具名） |
| 放寬 glob | **只涵蓋 1/8**（見下） | **0**（glob 結構上不會「列了卻不存在」） |

裁決：**顯式條目 ＋ 一道會紅的檢查**。**兩軸都是顯式勝**——這張表的 glob 那一列是 R2 verify 量出來的，
本檔前兩版都只憑「glob 會自動收」寫成綠：同形放寬（`plugin/skills/*/scripts/*.{sh,py}`）只涵蓋得到本輪
8 個新檔裡的 **1 個**；要 8/8 得同時放寬六條 glob 根、**156 個檔進 `PROTECTED`**（54 → 191）。
只放寬 `Sources/*/*.swift` 一條實跑就是 **rc=1、受保護 172、72 條缺口**。

> **這一版原本在這裡寫「新增由檢查擋，刪除由 `missing` 擋，兩個方向都不沉默」。那句話是假的，
> 被 R1 verify 的 Devil's Advocate 用實測推翻、coordinator 獨立重現。** 保留這段而不是刪掉它，
> 是因為本 repo 的規則要求把失敗史寫進文件本身——見下方「誠實邊界」的逐項量測。

## 落地

- **新檢查**：對每支守衛掃 `codeOnly()` 裡的 repo 相對路徑字面，**存在於磁碟且不在 `PROTECTED`** → 進 `fails`。
  三個條件都是機械可判定的事實，故不是 warning。
- **`DATA` 補 13 條**（第一批 8 條 ＋ R2 verify 找到的 5 條，見下方誠實邊界 9）。第一批是
  **8 個相異檔／6 支守衛／9 個 (守衛,檔) 配對**——`.githooks/run-guards.sh` 被兩支守衛
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
| 受保護檔 | 41 | **54** |
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

**3. 刪除方向：這道守衛自己對 32 條沉默，但整條 pre-push 只對 9 條沉默。** `PROTECTED` 的 54 條組成
（實測）：顯式 **19**、`GUARDS` **23**（**7 個 glob ＋ 16 個由 `swiftGuards()` 解析 `main.swift` 的 `case`
分派**——本檔前一版寫「整組是 glob」，機制描述錯）、rules glob **12**。35 條 glob 成員刪檔實測：**出聲 3**
（`entity-backlink-completeness.md`、`mcp-cli-parity.md` 被具名宣告指到；`assertions-must-be-measured.md`
是 `plugin/rules/*.md` 的唯一成員，glob 解析到零）、**沉默 32**。實測刪掉一整支守衛
`plugin/tests/review-claim-audit.sh` → 守衛 23→22、**rc=0、照印「無缺口」**。

> **前一版寫「35/49（71%）」，那個分子沒量過**（是從集合組成推導的，而且 23+11=34 被寫成 35）。
> 更重要的是它對**整條 pre-push** 過度悲觀：那 32 條裡 **23 條在別的階段是大聲的**——16 支 Swift 守衛
> 的檔一刪，`main.swift` 的 `case` 分派找不到符號、`swift build` 直接失敗；7 支腳本守衛一刪，
> `run-guards.sh` 以路徑呼叫它們、rc=127。**整條 pre-push 都靜默的只剩 9 個 `.claude/rules/*.md`（17%）。**

**4. 「從 `DATA` 拿掉一條」與「檔案被刪掉」是兩件事。** 前者只有在某支守衛的程式碼裡有那條路徑的引號
字面時才會紅。**19 條顯式條目裡 10 條看不見。** 其中 `MarkerParityMutationsData.swift` 最尖：本輪自己補
進來的、是真依賴（`RuleProseGuards.swift:285` 真的讀它），而拿掉它一聲不吭——#518 的標題所描述的形狀，
發生在 #518 自己修完之後、在它自己加的條目上。

> **10/19 比修法前的 5/14 更差，而那是本輪自己造成的**：誠實邊界 9 補進來的那 5 條，唯一的讀者就是那個
> **不被掃描的資料檔**，所以它們一進來就全部落在盲區。寫出來而不是只報「受保護 41 → 54」，因為後者
> 看起來像單調的進步。

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

**9. 守衛的資料檔完全不被掃描——而這是唯一一個今天有實例的盲點。** 上面 1～8 條列的盲區**全部零實例**
（示範用的都是構造出來的例子）。R2 verify 找到第六種，**今天有 5 個實例**：這道檢查只掃 `GUARDS`，而
`Sources/akashic-guards/*Data.swift`（四個）**不是守衛**——`main.swift` 沒有對應的 `case`，所以整個檔一行
都不會被看到。`AuditGuardsMutationsData.swift` 用 `AGMEdit(path: "…")` 逐字寫著 20 個路徑，其中 5 個存在
卻未受保護（`census-parity.yml`、`Models.swift`、`Temporal.swift`、`CreateEntryCommand.swift`、
`akashic-promote-literals/SKILL.md`），而它們全都已在 `census-parity.yml` 的 `paths:` 裡——與招牌案例
`mcpb/manifest.json` 完全同型。本輪把這 5 條補進 `DATA`（41 → 54，逐對缺口仍 0）。

**為什麼不直接把 `*Data.swift` 納入掃描（那才是根治）**：`TriggerCoverageMutationsData.swift` 裡有
`"Sources/akashic-guards/ShellLex.swift"`——那是**負控刻意選的、必須永遠不在 `PROTECTED` 的目標**。
納入掃描會讓這支守衛因為自己的負控 payload 而永久變紅。要根治得先分開「守衛自己讀的路徑」與「注入用的
payload 路徑」，那是判準問題不是一行改動。

上述各條的根治需要人裁決，不是實作可以順手決定的——追蹤 #522。**理由不是「零實例」**：`GUARDS.count`
下降有實測前例（`#433` 記著「21 支 → 6 支而輸出照印 ✓ 涵蓋 6/6」）。真正的理由是第 9 條末尾那個——
根治要先分開「守衛自己讀的路徑」與「注入用的 payload 路徑」，那是判準問題。
