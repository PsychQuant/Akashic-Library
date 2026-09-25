# 2026-09-25 person／organization 的記錄檔預算預警（#645）

## 背景

`resolution-undecided` 記錄設計上不退役（#619），未決腿的上限只擋單次呼叫、不擋累積。一筆記錄的檔案超過讀取上限（8 MiB）時，下一次載入會把它 quarantine：它從所有面消失，指向它的 key 全部懸空。寫入路徑有 2 倍寬限（`writePathMultiplier`），所以這樣的檔寫得進去、卻讀不回來，而且在那之前沒有任何跡象。

venue 側早有預警（#499，`zero-instance-guards` 第 16 列）。person 側沒有；#643 起 organization 也收未決記錄，同樣沒有。

## 變更

- `StoreHealth.holderVerdictBudgetWarnings`（前綴 `holderVerdictBudgetPrefix`）：person 或 organization 的記錄檔達讀取上限的一半時，出一則 warning 並指名那筆記錄。訊息說出檔案位元組、門檻，以及其中的 resolution verdict 筆數。
- 門檻 `AliasEventBudget.recordFileWarningBytes`＝`maxBytes / 2`（4 MiB），由 venue 族與新族共用。量的是**記錄檔本身的位元組**。
- 三個面各一格：
  - CLI `validate` 的計數行；
  - MCP `akashic_doctor` 的 `holderVerdictBudgetWarnings` 計數；
  - App 側欄的「人物／機構 verdict 逼近預算」。
- **venue 族（#499）的門檻同步更正**：原本以「節點預算的一半 ÷ 每筆 verdict 9 節點」換算成 11,111 筆，但節點軸對 store 檔不生效（見下），所以改量檔案位元組。`nodesPerVenueVerdict` 與 `venueVerdictWarningThreshold` 退場。裁決（候選 3：不改序列化位置、半預算處出聲、達門檻重開）不變，變的是預算的量綱。venue 的處置也先查是否有人重複記未決。
- `zero-instance-guards`：
  - 第 31 列新增；
  - 第 16 列加註 2026-09-26 的更正；
  - 第 30 列記下觸發條件成立、重開後裁決不變；
  - 兩段量測腳本改量檔案位元組。
- `entity-backlink-completeness` 第 13 條同步更正。

## 為什麼量的是檔案位元組（三輪才量對）

- **初版**照 #499 用節點換算的筆數。
- **R1 verify** 指出：未決記錄的說明可寫到 4,096 位元組，會先撞上 8 MiB 位元組上限。所以加了「verdict 內容位元組」軸，並以 YAML 最壞跳脫 4 倍換算。
- **R2 verify** 的 DA 席用真 binary 量出：`AliasEventBudget.estimate` 的節點軸**只在檔案含 alias 時生效**，而 store 寫出的檔不含 alias。65,000 筆 verdict 的 person（節點是「預算」的 2.9 倍）照常載入；8.7 MB 的單筆檔才被 quarantine。讀取路徑上唯一會觸發的是 `maxBytes`。

前兩版修的都是估計。檔案大小已經包含 YAML 跳脫與 verdict 以外的內容，所以直接量它，不再估。

## 量測

2026-09-26 live store，唯讀：

| 形狀 | 筆數 | 最大檔 |
|---|---|---|
| person | 4,575 | 10,869 bytes（`chen-chien-hsiun`） |
| organization | 13 | 717 bytes |
| venue | 485 | 268,627 bytes（`psychological-methods`，1,352 筆 verdict） |

門檻 4,194,304 bytes，零實例；venue 最大檔距門檻約 15.6 倍。

## 驗證

- `HolderVerdictBudgetWarningTests`：
  - 門檻恰等於檔案大小時出聲、大一 byte 時不出；
  - organization 同樣適用；
  - 以 1,000 筆未決記錄把 person 檔推過預設門檻，經 `health(from:)` 出聲，且 venue 族不重複報；
  - 門檻的推導；
  - 三個面都接上。
- `VenueVerdictBudgetWarningTests` 改用同一個量法。
- 負控：
  - 拿掉 organization 那一段 → organization 的測試變紅；
  - 拿掉 `health(from:)` 接上新族的那一行 → 經 health 的測試變紅。

  兩者還原後檔案位元組都與原本相同。

## 誠實邊界

預警只在讀取面計算。寫入路徑有 2 倍寬限，一次夠大的寫入可以從門檻之下直接跳過讀取上限：judge／refute 的理由沒有長度上限；未決的說明含控制字元時，YAML 跳脫會放大 4 倍。這是寫入閘的缺口，記 #648。
