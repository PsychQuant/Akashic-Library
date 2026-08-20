## Why

一個 literal 由**多個真人共用**時，判定做得出來卻寫不進去。

實測（2026-08-20，全庫 937 works／867 people）：`resolve-people` 報 71 列歧義。單就 literal
「C-H Chen」的 15 列，逐篇查該作者位在論文上登記的機構後，分屬**至少 6 個不同機構**
（中研院統計所 2、慈濟 3、長庚 2、UC Davis 2、UCSD 2、馬偕／國衛院／陸軍軍醫大學／北榮／
北醫／高醫各 1）。證據充足、判定明確，但 store 沒有任何地方能記下「**這一篇的這個作者位**
是這個人」——歧義的兩條既有出口（補 variant alias、`add-person` 建檔）都是**全庫**動作，
會把其他 14 列一起誤升。

於是查證結果只能留在 issue 的散文裡，下次接手要整套重查——那正是 verdict 機制當初要解決的
問題，在「共用 literal」這一格上尚未被解決。

## What Changes

- **新增 `AuthorPairing` protocol**，抽出歸戶寫入實際需要的四個欄位
  （citekey／authorIndex／literal／personKey）。既有的 `ResolutionCandidate` 與新增的
  `JudgedPairing` 並列 conform；`PersonResolver.apply` 改為泛型接受任一 conforming 型別。
- **新增 `JudgedPairing`**：judgement 必填（空字串在型別層建構不出來）、**無 tier**
  （判定不是被提名出來的）、**無 restsOn**（依 #280 的既有裁決，證據走被判 person 的
  `references`）。
- **判定的 verdict rule 用新字面值**，並**參與** `confirmedByLiteral`：同一個 literal 在
  其他 entry 的 occurrence 因此以 `confirmedElsewhere` tier 浮出，且既有的弱血統揭露機制
  會逐字印出那個 rule，讓判定的來歷在提名理由裡可見。每一處仍須逐列決定。
- **CLI 新增逐 id 顯式旗標**（可重複），收三段形 id 與 judgement 文字。**不提供**篩選式
  批次旗標。
- **MCP 面同步**，per-id 顯式指名（沿用該面既有契約）。
- **spec 界定**：歧義 occurrence 可以有 judgement、不可以有 candidate。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `person-resolution`: 界定歧義 occurrence 的 judgement 出口；界定判定的 rule 參與
  confirmed-elsewhere 層的提名且血統可見

## Impact

- Affected specs: `person-resolution`
- Affected code:
  - Modified:
    - `Sources/AkashicEntity/PersonResolver.swift`
    - `Sources/AkashicEntity/ResolutionLedger.swift`
    - `Sources/akashic/Commands.swift`
    - `Sources/AkashicMCPKit/AkashicService.swift`
    - `Sources/akashic-mcp/Server.swift`
    - `openspec/specs/person-resolution/spec.md`
    - `.claude/rules/mcp-cli-parity.md`
    - `Tests/AkashicKitTests/StdioE2ETests.swift`
  - New:
    - `Tests/AkashicKitTests/JudgedPairingTests.swift`
    - `changelog/`（本輪紀錄，檔名於實作時依既有日期慣例命名）
  - Removed: (none)
