> 本清單的每個群組標明它落實哪一條 spec requirement 與哪一個 design 決策。
> Spec：`canonical-serialization`、`organization-entity`（delta）。Design：D1–D5 與「Implementation Contract」各節。

## 1. 序列化順序與相等性分離

> 落實 requirement **Serialization order SHALL be governed by time alone**。
> 依據 design 的 **D1：序列化順序與相等性順序分離**、**D4：穩定性必須顯式構造，不可依賴 `sorted()`**，
> 判準取自 design 的 **排序行為的判準** 表，範圍取自 design 的 **範圍邊界**。
> **D2：不引入 `primary` 標記** 是本群組的否決記錄——本群組**不得**新增任何欄位到 `TemporalValue` 或 `Organization`。

- [x] 1.1 RED — [requirement: Serialization order SHALL be governed by time alone] 在 `Tests/AkashicKitTests/` 新增 `TimelineSerializationOrderTests`，四個測試對應 design **排序行為的判準** 表的四列：`testDatedEntriesWriteChronologically`（`[2013-07, 2003-01]` → `2003-01` 在前）、`testUndatedEntriesKeepHeldOrder`（三筆無 range 的 names，encode 後順序與輸入相同）、`testUndatedEntriesFollowDatedOnes`（`[B(nil), A(2000)]` → `[A, B]`）、`testEqualityStillIgnoresStorageOrder`（同樣段落不同順序的兩條 timeline 仍 `==`，對應 requirement 的 Scenario「Equality remains blind to storage order」）。執行 `swift test --filter TimelineSerializationOrderTests`，前三個必須失敗、第四個必須通過——第四個先綠是刻意的迴歸哨兵
- [x] 1.2 GREEN — 在 `Sources/AkashicCore/Temporal.swift` 的 `TimelineOf` 加一個序列化順序存取點，與既有的 `sorted`（全序、供 `==` 使用）並存且互不呼叫，落實 **D1**。實作以原始索引裝飾後比較：先比 `range`，`range` 相等時比索引，落實 **D4**——**不得**呼叫 `sorted()` 後期待其穩定。`sorted` 本身與 `TemporalValue.<` 一律不動
- [x] 1.3 GREEN — 在 `Sources/AkashicCore/YAML.swift` 把 `PersonYAML.timelineNode` 與 `PersonYAML.orgTimelineNode` 內的 `t.sorted` 改為新的序列化順序存取點，落實 design **可觀察行為** 第 2 條。`OrganizationYAML.encode` 透過 `timelineNode` 間接受惠，不需個別修改。執行 `swift test --filter TimelineSerializationOrderTests` 四個全綠

## 2. 冪等性與 organization 行為

> 落實 requirement **Normalization SHALL reach a fixed point in one pass** 與
> requirement **Existing temporal dimensions SHALL be unaffected**（`organization-entity` delta）。
> 依據 design **D1** 的「冪等性不受影響」論證與 **可觀察行為** 第 4 條。

- [x] 2.1 RED — [requirement: Normalization SHALL reach a fixed point in one pass] 新增 `CanonicalFormIdempotenceTests.testNormalizingTwiceIsStable`：取一筆 affiliations 反時間序的 person YAML 字面值，計算 `X = encode(decode(input))` 與 `Y = encode(decode(X))`，斷言 `X != input` 且 `Y == X`。執行 `swift test --filter CanonicalFormIdempotenceTests` 確認通過——若失敗代表 1.2 的排序不是不動點，回頭修 1.2
- [x] 2.2 RED — [requirement: Existing temporal dimensions SHALL be unaffected] 同檔加 `testOrganizationAliasesKeepAuthoredOrder`（三筆無 range 的 names，對應 `organization-entity` delta 的 Scenario「An organization's names keep their authored order」）與 `testOrganizationHistoricalNamesOrderByTime`（兩筆帶 range 的 names，對應 Scenario「An organization's historical names order by time」）。執行後兩者皆須通過

## 3. 位置即語意的序列不受影響

> 落實 requirement **Order-bearing sequences SHALL be excluded from reordering**。
> 依據 design **範圍邊界** 的「在範圍外：`authors` 與 `attachments` 的順序」。

- [x] 3.1 RED — [requirement: Order-bearing sequences SHALL be excluded from reordering] 新增 `AuthorOrderRegressionTests.testAuthorOrderSurvivesNormalization`：取一筆多作者且作者非字母序的 work YAML，斷言 `encode(decode(x))` 的作者順序與輸入完全相同。執行 `swift test --filter AuthorOrderRegressionTests` 必須通過——本測試是哨兵，任何把排序誤加到 `authors` 的改動都會讓它變紅

## 4. `akashic fmt`

> 落實 requirement **Normalization SHALL be reachable from a command**。
> 依據 design **D3：正規化實作為 decode + encode，不新增抽象**、**D5：`validate` 不擋排版，`fmt --check` 才擋**，
> 錯誤行為取自 design 的 **失敗模式**。

- [x] 4.1 RED — [requirement: Normalization SHALL be reachable from a command] 新增 `FormatCommandTests`，以注入的假 home 建臨時 store（比照既有測試對 `AkashicHome` 的處置），寫入一筆 canonical 記錄與一筆非 canonical 記錄。三個測試：`testCheckReportsDeviationAndExitsNonZero`、`testCheckDoesNotModifyFiles`（比對執行前後所有檔案的位元組與 mtime，對應 **失敗模式** 的「`--check` 不得開啟任何檔案的寫入控制代碼」）、`testCheckOnCleanStoreExitsZero`。執行 `swift test --filter FormatCommandTests` 全部失敗（命令尚不存在）
- [x] 4.2 GREEN — 新增 `Sources/akashic/FormatCommands.swift`，內含 `Fmt: ParsableCommand`（`commandName: "fmt"`），沿用 `LibraryOptions` 的 `@OptionGroup`。走訪 store 內所有記錄，依裸標籤分派到 `EntryYAML` / `PersonYAML` / `OrganizationYAML` 的 decode 與 encode——落實 **D3**，**不得**新增任何正規化型別。`--check` 旗標下只比對不寫檔；無旗標時對輸出與輸入不同者以既有的原子寫入路徑覆寫並列出檔名
- [x] 4.3 GREEN — 在 `Sources/akashic/CLI.swift` 的 subcommands 清單註冊 `Fmt`。依 **D5**，`Sources/akashic/Commands.swift` 的 `Validate` 一律不動。執行 `swift test --filter FormatCommandTests` 三個全綠
- [x] 4.4 RED — 在 `FormatCommandTests` 加 `testUndecodableRecordDoesNotAbortRun`：store 內放一筆壞掉的 YAML 加兩筆正常記錄，斷言命令列出壞檔與原因、仍處理完另外兩筆、退出碼非 0，且壞檔的位元組未變。對應 **失敗模式** 的前兩條。執行後必須失敗
- [x] 4.5 GREEN — 在 `Fmt` 的走訪迴圈為每筆記錄包上錯誤處理：捕捉 decode 與 encode 的例外、累積後續報告、繼續下一筆，結束時依是否有失敗或偏離決定退出碼。執行 `swift test --filter FormatCommandTests` 四個全綠

## 5. 既有記錄對齊

> 落實 design **驗收條件** 的最後一項，並以 design **量測（全 store decode → encode 逐檔比對）** 的數字作為預期值。
> 依 proposal 的「以獨立提交 reflow」要求，本群組的檔案改動不得與第 1–4 群組的程式碼改動放進同一次提交。

- [x] 5.1 執行 `akashic export-tables` 對 `~/.akashic` 產出基準 CSV 並保存到工作目錄外的暫存位置，作為 reflow 前後的比對基準
- [x] 5.2 對 `~/.akashic` 執行 `akashic fmt`（無旗標），確認被改寫的記錄數為 79（77 person、2 organization），且 636 筆 work 記錄未被改寫——數字取自 design 的 **量測（全 store decode → encode 逐檔比對）** 表。若數字不符則停下並回報差異，不得逕行繼續
- [x] 5.3 再次執行 `akashic export-tables`，與 5.1 的基準逐檔比對，確認衍生層零差異——這是「純序列化正規化、零語意變更」的證據
- [x] 5.4 執行 `akashic fmt --check` 確認退出碼 0，並執行 `swift test` 確認全套測試通過，落實 design **驗收條件** 的前兩項
