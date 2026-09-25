# 2026-09-25 person／organization 的 verdict 預算預警（#645）

## 背景

`resolution-undecided` 記錄設計上不退役（#619），未決腿的上限只擋單次呼叫、不擋累積。累積超過 decode 的讀取預算（節點 200,000 或 8 MiB）時，那筆記錄會在下一次載入時被 quarantine——從所有面消失，指向它的 key 全部懸空。寫入路徑有 2 倍寬限（`writePathMultiplier`），所以寫得進去、讀不回來；在那之前沒有任何跡象。venue 側早有預警（#499，`zero-instance-guards` 第 16 列）；person 側沒有，#643 起 organization 也收未決記錄，同樣沒有。

## 變更

- `StoreHealth.holderVerdictBudgetWarnings`（前綴 `holderVerdictBudgetPrefix`）：person 或 organization 持有的 resolution verdict 數達 decode 硬預算的一半時，出一則 warning 並指名那筆記錄。
- 門檻沿用 `AliasEventBudget.venueVerdictWarningThreshold`：verdict 形狀相同、節點數相同、受同一個預算約束，另立等值常數就是同一件事的第二份描述。
- 等效筆數（rests-on 換算）的算法抽成 `LibraryStore.verdictBudgetCount`，venue 族與新族共用。
- 三個面各一格：
  - CLI `validate` 的計數行；
  - MCP `akashic_doctor` 的 `holderVerdictBudgetWarnings` 計數；
  - App 側欄的「人物／機構 verdict 逼近預算」。
- `zero-instance-guards` 第 31 列（含量測腳本）；第 30 列的誠實邊界與 `UndecidedVerdicts.swift` 的註解改寫。

## 量測

2026-09-25 live store，唯讀：

| 形狀 | 筆數 | 單筆最多 verdict |
|---|---|---|
| person | 4,575 | 40 |
| organization | 13 | 1 |

門檻 11,111，零實例。

2026-09-26 以第 31 列改寫後的腳本重跑（兩軸）：person 單筆最大等效 40 筆、內容 9,147 位元組；organization 1 筆、326 位元組；讀不到的檔 0。位元組門檻 1,048,576，同樣零實例。

## 驗證

- `HolderVerdictBudgetWarningTests`：門檻上下兩側、organization、rests-on 換算、`health(from:)` 的預設門檻與兩族分開、三面都接上。
- 負控：拿掉 organization 那一段，organization 的測試變紅；還原後檔案位元組相同。

## R1 verify（6 席中 3 席完成，其餘出錯；0 HIGH、1 MEDIUM）之後的修正

- **位元組軸**：decode 閘有節點與位元組兩軸，初版只看節點。未決記錄的說明可寫到 4,096 位元組，約 2,000 筆就先撞上 8 MiB 讀取上限，那時節點數只到預算的一成。新增 `AliasEventBudget.verdictByteWarningThreshold`（讀取位元組預算的一半 ÷ 最壞 YAML 跳脫 4 倍＝1 MiB），兩族共用；訊息說出是哪一軸達門檻
- 經 `health(from:)` 的正向測試（以未決記錄為 fixture），證明新族接進了 perRecord
- 背景一節的失效描述改正：是讀取路徑 quarantine，寫入路徑有 2 倍寬限擋不住
- `zero-instance-guards` 第 30 列記下觸發條件成立、重開後裁決不變；第 31 列的量測腳本改成鏡射工具的兩軸定義
- `AliasEventBudget.venueVerdictWarningThreshold` 的 doc 寫明兩族共用；`entity-backlink-completeness` 第 13 條補上 person／organization 那一族

