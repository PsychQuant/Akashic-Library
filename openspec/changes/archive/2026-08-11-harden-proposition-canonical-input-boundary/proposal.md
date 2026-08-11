## Why

`AkashicProposition` 目前把「命題合法」與「模型鍵唯一」當成外部前提，卻沒有在投射、求值、問答與裁決的信任邊界強制成立。非法命題因此可能被誤表成知識未定，重複鍵更可能只因輸入順序不同而改變真值與 `AcceptedFact`；在任何 CLI、MCP 或持久化介面公開前，必須先讓這條路徑 fail closed。Refs #205。

## What Changes

- **BREAKING**：`PropositionModel.init(entries:people:)` 改為 throwing initializer；任何重複 entry citekey 或 person key 都拒絕構造，並以決定性排序回報完整重複鍵集合。
- `PropositionModelValidationError` 的 machine payload 保留完整衝突集合；`LocalizedError` 與 Swift 預設錯誤字串顯示皆使用同一個有界摘要，每類最多列出前五筆、逐筆消毒並明示總數與未顯示筆數，避免大量 caller-controlled keys 透過一般插值放大終端或日誌輸出。
- **BREAKING**：`Proposition.project(in:)`、`evaluate(in:)` 與 `YesNoQuestion.answer(in:)` 改為 throwing API，在最上游投射邊界驗證命題並逐層保留錯誤。
- `adjudicate` 防禦性傳遞命題／模型輸入錯誤，確保非法或歧義輸入絕不產生 `AcceptedFact`。
- 保留既有 open-world 語意：合法但缺少支持的資料仍是 `undetermined`，不得因本修補改判為 `fails`。
- 加入 malformed direct enum case、非法 key 搭配手工模型、重複鍵正反序與 mutation-sensitive 回歸測試。
- 更新正式命題語意規格，以及受 #205 影響的 Tractatus 對照證據與並排文件。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `proposition-semantics`：將 canonical proposition／model 輸入與錯誤傳遞提升為投射、求值、問答及裁決的強制契約。

## Impact

- Affected specs: `proposition-semantics`
- Affected code:
  - Modified:
    - `Sources/AkashicProposition/Proposition.swift`
    - `Sources/AkashicProposition/Projection.swift`
    - `Sources/AkashicProposition/Question.swift`
    - `Tests/AkashicPropositionTests/PropositionTests.swift`
    - `docs/tractatus/corpus/3.yaml`
    - `docs/tractatus/corpus/4.yaml`
    - `docs/tractatus/generated/tractatus-project-map.md`
  - New: （無）
  - Removed: （無）
- API impact: `PropositionModel` 構造與三個唯讀語意 API 需要呼叫端使用 `try`；目前專案內呼叫點限於 `AkashicPropositionTests`。
- Dependencies: 不新增套件或 target 依賴。
