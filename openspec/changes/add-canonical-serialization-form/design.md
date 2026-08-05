## Context

`TimelineOf.sorted` 目前同時承擔兩個互不相干的職責：

1. **相等性的正規化** — `TimelineOf.==` 定義為 `a.sorted == b.sorted`。要讓「同樣的段落、不同的儲存順序」判為相等，`sorted` 必須是**全序**，因此需要在 `range` 相同時以 `value` 決勝。
2. **序列化的輸出順序** — `PersonYAML.timelineNode` 與 `orgTimelineNode` 直接吃 `t.sorted`。

職責 2 是**順便繼承**職責 1 的比較器，沒有人決定過「檔案裡也要按字串排」。後果在沒有日期的時間軸上顯現：`Organization.names` 三筆全部無 `range`，排序完全由 `value` 決勝，於是主名（中文正式名）被推到英文名之後。

### 量測（全 store decode → encode 逐檔比對）

| 形狀 | 偏離 canonical | 寫入者 |
|---|---|---|
| `work` | 0 / 636 | Swift encoder |
| `person` | 77 / 77 | 外部 R pipeline |
| `organization` | 2 / 2 | 手寫 |

decode/encode 失敗 0 筆。分界與寫入者完全一致——canonical form 已存在且確定性可靠，缺的只是「讓 encoder 以外的人也能用」的入口。

person 記錄的偏離全部是引號風格（`key: "x"` 對上 `key: x`）；organization 記錄的偏離是 `names` 順序，外加 `note` 長字串的折行位置。

## Goals / Non-Goals

**Goals**

- 讓「時間順序」只在時間確實有話說時生效；時間沒話說時保留寫入順序
- 讓 canonical form 有一個可執行的對齊入口，外部寫入者不必各自重製排序規則
- 修正 `organization-entity` spec 內互斥的兩條 clause，讓 byte-identical 成為可執行而非必然被違反的要求

**Non-Goals**

- **不改 `DateRange.<` 對 `nil` 的處理。** 現行行為是無 `start` 排最後。另一種讀法（「不知道何時，可能很早」→ 排最前）與 `end: nil` 的語意歧義同源，屬 Akashic-Library#63 的範圍
- **不改 Yams emitter 的折行寬度。** 折行已是 636 筆 work 記錄的既成形式，改動會把 reflow 範圍從 79 筆擴大到約 715 筆，代價與收益不成比例
- **不引入 `primary` 標記欄位。** 見下方 D2 的否決理由
- **不動 `authors` 的順序。** 作者位置即語意（第一作者、通訊作者），任何排序都是資料破壞
- **不實作外部 pipeline 端的呼叫。** 本 change 只提供入口；storyline 的匯出腳本要不要呼叫 `fmt` 是該 repo 的決定

## Decisions

### D1：序列化順序與相等性順序分離

序列化改用「依 `range` 排序，`range` 相同時保留寫入順序」；相等性維持現行全序不動。

兩者是不同的函式，沒有必須共用比較器的理由。相等性需要全序才能成立；序列化需要的只是「時間有話說時照時間排」。

**代價（明確接受）**：失去「一個值只有一種位元組表示」。兩個 `==` 成立的 timeline 若 `entries` 陣列順序不同，會寫出不同位元組。查證確認 store 內沒有任何機制對 entity YAML 做內容雜湊（`sources/` 走內容定址，entities 走 UUID 定址），因此此性質目前沒有依賴者。

**冪等性不受影響**：序列化是 `entries` 陣列的純函式，decode 保留陣列順序，故 `fmt(fmt(x)) == fmt(x)` 成立。這正是本 change 要寫進 spec 的 idempotence 要求。

被否決的替代方案：

- **維持 `value` 決勝** — `fmt` 每次把主名推到後面，人每次改回來。工具與人對抗的結局是沒人執行 `fmt`
- **`Organization.names` 改為純陣列**（比照 `Person.names`）— 直接移除 `range`，違反 `organization-entity` 已發布的改名建模要求（「SHALL retain both names with their validity ranges」）

### D2：不引入 `primary` 標記

候選方案是加一個布林欄位，排序鍵改成 `(primary, range, value)`。否決理由是**同一概念兩種機制**：`Person.names` 是純陣列、主名以位置表達（第一個），`Organization.names` 若改用顯式旗標，讀 store 的人必須同時記住兩套規則。D1 讓兩者都回到「位置即主次」。

### D3：正規化實作為 decode + encode，不新增抽象

對「是否需要一個 `CanonicalForm` 正規化型別」跑深度檢查：

| 問 | 答 |
|---|---|
| 邊界該放哪 | 沒有新邊界。canonical form 已住在三個 `encode` 函式裡 |
| 轉接層數量 | 新增一層即是疊在 encoder 上的第二層 |
| 深度 | 該層背後藏什麼行為？無——只會重述 encoder 已做的事 |
| 刪除測試 | 刪掉它會壞什麼？無。encoder 仍是唯一定義 |

因此 `fmt` 直接呼叫既有的 decode 與 encode。獨立的正規化型別會成為 canonical form 的第二份定義，兩者漂移時無人能判斷誰對——正是本 change 要修的病。

### D4：穩定性必須顯式構造，不可依賴 `sorted()`

Swift 標準函式庫**未**承諾 `sorted()` 穩定（現行實作為 timsort，實務上穩定，但非文件保證）。序列化排序必須以原始索引裝飾後再比較，形式為：先比 `range`，`range` 相同時比原始索引。依賴未文件化的行為屬於「今天能跑、升版就壞」。

### D5：`validate` 不擋排版，`fmt --check` 才擋

`Validate.run()` 現行的失敗條件是 quarantine 與 `.error` severity——兩者都是資料正確性。排版偏離不是正確性問題。若 `validate` 擋排版，外部 pipeline 每次寫完都得先跑 `fmt` 才過驗證，摩擦大到會讓人繞過 `validate` 本身。

`fmt --check` 提供給 CI 與外部 pipeline 作為明確的關卡，語意與 `swift format --lint` 一致。

## Implementation Contract

### 可觀察行為

1. `TimelineOf` 取得一個新的序列化順序存取點，其結果為：依 `range` 遞增排序；`range` 相等的項目維持它們在 `entries` 內的相對順序。既有的相等性存取點（全序，含 `value` 決勝）行為不變。
2. `PersonYAML.timelineNode`、`PersonYAML.orgTimelineNode` 改用序列化順序存取點。
3. `akashic fmt` 走訪 store 內所有記錄，對每筆執行 decode 後 encode：
   - 無旗標：輸出與輸入不同者就地覆寫，並列出被改寫的記錄；退出碼 0
   - `--check`：不寫任何檔案，列出輸出與輸入不同的記錄；有偏離者退出碼非 0，無偏離者退出碼 0
   - 兩種模式下 decode 或 encode 拋錯的記錄都須列出且不得靜默跳過；`--check` 視其為失敗
4. `organization-entity` spec 的 round-trip scenario 改為以 canonical 輸入為前提，並新增 idempotence scenario。

### 排序行為的判準

| 輸入 `entries` | 序列化輸出 |
|---|---|
| `[start 2013-07, start 2003-01]` | `[2003-01, 2013-07]` |
| `[A（無 range）, B（無 range）, C（無 range）]` | `[A, B, C]`（不變）|
| `[籌備處 1982-07~1987-08, 統計所 1987-08~]` | `[籌備處, 統計所]` |
| `[B（無 range）, A（start 2000）]` | `[A, B]`（無 `start` 者排最後）|

### 失敗模式

- 記錄 decode 失敗：`fmt` 印出檔名與錯誤後繼續處理其餘記錄，結束時以非 0 退出。**不得**因單筆失敗而中止整批
- 記錄 encode 失敗（encode canary 拒寫）：同上處理，且**不得**寫出任何位元組
- `--check` 模式**不得**開啟任何檔案的寫入控制代碼

### 驗收條件

- `swift test` 全綠
- `akashic fmt --check` 對 reflow 後的 `~/.akashic` 退出碼 0
- 新增測試：對含反時間序 `affiliations` 的記錄，encode 後順序為時間遞增
- 新增測試：對三筆全無 `range` 的 `names`，encode 後順序與輸入相同
- 新增測試：對任意合法輸入，`encode(decode(encode(decode(x))))` 與 `encode(decode(x))` 位元組相同
- 新增測試：`TimelineOf` 相等性仍與儲存順序無關（既有 spec scenario 不回歸）

### 範圍邊界

**在範圍內**：`Sources/AkashicCore/Temporal.swift` 的序列化順序存取點、`Sources/AkashicCore/YAML.swift` 的兩個 timeline 節點建構函式、新的 `fmt` 命令與其註冊、`organization-entity` spec 的兩條 scenario、79 筆既有記錄的 reflow。

**在範圍外**：`DateRange.<` 對 `nil` 的處理、Yams 折行寬度、`authors` 與 `attachments` 的順序、`fields` 鍵的字母序（`EntryYAML.encode` 現行行為維持）、外部 pipeline 端的呼叫。

## Risks / Trade-offs

- **reflow 的 diff 淹沒語意變更** — 77 筆 person 記錄的差異主要是引號。緩解：reflow 單獨一次提交，提交訊息明示「純序列化正規化，零語意變更」，並以 `akashic export-tables` 前後輸出比對確認衍生層無變化
- **`fmt` 是破壞性寫入** — 緩解：`--check` 為唯讀且不開寫入控制代碼；無旗標模式列出所有被改寫的記錄
- **失去「一個值一種表示」** — 已於 D1 明確接受並記錄查證結果。若未來引入 entity 內容雜湊（例如同步或去重），此決定需重新評估
- **`fields` 的順序在 person 側會改變** — 現行 17 筆多值 `fields` 依 `value` 排序，改後保留寫入順序（名冊頁的列序）。這是預期的改善而非回歸，但會出現在 reflow 的 diff 內
