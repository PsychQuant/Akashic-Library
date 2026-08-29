# 一個欄位在說謊，而它的兩個用途要分開

2026-08-28，#422／#406。format 13 → 14。

## 說謊的是 `Venue.names`

它的型別是**時間軸**、spec 宣稱它模型化刊名沿革。實測 405 筆 venue：

| | |
|---|---|
| `names` 多筆 | **35** |
| 其中**帶時間欄位** | **0** |

35 筆逐一看過，全部是同一本刊的不同寫法（`plos-one` 的 `PLOS ONE`／`PLoS ONE`／
`PloS one`）。**讀它的人以為拿到時間序，實際拿到任意順序的別名。**

## 這推翻一條顯式裁決，而那條裁決當時是對的

`venue-entity` spec 寫著 names 用「organization pattern; **NOT** the nested person
partition」。那不是疏漏——`add-venue-entities`（2026-08-17）顯式選了扁平模式，理由是
**預測** `names` 的多筆會裝沿革、別名少到可以塞進 `authorized` 的補集。

11 天後實測那個預測完全反了：被預測是主要用途的那個零實例，被預測是次要的那個是唯一用途。

**保留時間軸 Requirement 而不刪除**：刊名沿革是真的現象（JRSS Series B／C），零實例的
原因是**異寫法佔著它的位置**。收窄之後「零實例」從一個尷尬變成誠實的狀態。

## #406 搭同一班車，而 `nil` 不得折成 `false`

`paginated` 三態：`true`／`false`／缺席（＝尚未判定）。

**「未判定」與「判定為不使用頁碼」是兩件事**：前者是 APA7 下限**仍該報缺**的狀態，
後者才是「這筆沒有頁碼是正確的」。折成 `false` 會讓所有未查的刊靜默通過下限檢查。

所以 `nil` 不寫進 YAML、decode 只收 `true`／`false`（其餘整檔拒讀）、讀取面缺席時
**什麼都不印**——印「未判定」會讓它看起來像一個已經查過的結論。

**搭同一次 bump 是 #406 的排程裁決**（選項 3）：分兩次做等於兩輪
「build 三 binary → migrate → validate → 手動 bump」。

## 遷移是重新分類，不是新判定

那些名字**已經在同一筆記錄裡**——它們是誰的別名，前一次判定已經做過了。所以本遷移
不受 `identity-is-judged-not-matched` 管：它只是把既有判定的結果重新分類。

**誤標的出口是乾跑逐筆過目**（35 筆可行），而不是 rollback。帶時間欄位的一律不動。

實測：`將分類 35 筆；單一名字 370、已分割 0、帶時間 0`。驗收條件（`names` 多筆且不帶
時間而沒有 variant 的 venue）**= 0**。

## 守衛抓到我三次

| | |
|---|---|
| `backlink-field-ratchet` | **新欄位未經裁決**——兩個新欄位要先跑 `entity-backlink-completeness` 的第 ③ 步（會序列化嗎？值指涉另一個實體嗎？）。答案都是「不指涉」→ 不進封閉列舉，但要進 ADJUDICATED |
| `parity-table-drift` | CLI-only 表缺 `migrate-venue-variants` 那一列 |
| `plugin-store-format-parity` | **format bump 後兩個出貨宣告沒跟上**（`plugin.json`／`mcpb/manifest.json` 仍說 13）——那正是 #408 那支守衛存在的理由，而它今天第一次抓到真的漂移 |

第三個特別值得記：`mcbp/manifest.json` 是**出貨物**，它說謊的對象是 Claude Desktop 的
安裝者。

## 型別檢查器的一個坑

`items.contains { $0.start != nil || $0.end != nil || $0.ended != nil || $0.attested != nil }`
——四個 optional 的 `||` 鏈讓編譯器 **type-check 超時**。拆成具名函式、逐條 `if` 就好。
（順帶發現那四個欄位在 `range` 底下，不是 `TemporalValue` 的頂層。）
