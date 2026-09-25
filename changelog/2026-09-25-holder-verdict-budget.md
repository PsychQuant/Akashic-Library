# 2026-09-25 person／organization 的 verdict 預算預警（#645）

## 背景

`resolution-undecided` 記錄設計上不退役（#619），未決腿的上限只擋單次呼叫、不擋累積。累積到 decode 的節點預算時，那筆記錄的所有寫入都會被 encode canary 拒絕，而在那之前沒有任何跡象。venue 側早有預警（#499，`zero-instance-guards` 第 16 列）；person 側沒有，#643 起 organization 也收未決記錄，同樣沒有。

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

## 驗證

- `HolderVerdictBudgetWarningTests`：門檻上下兩側、organization、rests-on 換算、`health(from:)` 的預設門檻與兩族分開、三面都接上。
- 負控：拿掉 organization 那一段，organization 的測試變紅；還原後檔案位元組相同。
