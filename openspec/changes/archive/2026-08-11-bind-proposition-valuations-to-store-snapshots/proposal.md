## Why

`AkashicProposition` 目前只回傳脫離資料版本與有效時間的裸真值，因此同一句命題即使源自不同 store 內容或不同日期，答案與 accepted fact 也無法區分或重播。#205 已先封閉命題與模型的正規輸入邊界；現在必須把每次 valuation 綁定到可信的不可變 snapshot、合法的 valid time 與可檢查的 evidence trace，才適合繼續加入否定與真值函數。Refs #202。

## What Changes

- 新增 StoreIO 擁有的 `StoreIdentity`、內容定址 `StoreRevision`、`StoreSnapshotID` 與 `LibrarySnapshot`；revision 由同一次擷取且實際用於解碼的 canonical store bytes 決定，不依賴 Git、mtime 或檔案列舉順序。
- **BREAKING**：`PropositionModel` 改由 `LibrarySnapshot` 建立，並以無法由呼叫端拆配 snapshot/model 的 `ValuationContext` 執行求值。
- 新增嚴格的 `ValidDay`、`RecordedTime` 與 `AcceptedTime` 名目型別，禁止以裸 `String` 混用有效時間、記錄時間與接受時間。
- **BREAKING**：命題求值改回傳保存真值、snapshot、valid day 與結構化 evidence trace 的 `Valuation`；question answer 與 adjudication 結果沿用同一 context，不再提供缺少 context 的真值路徑。
- 新增第一個有效時間 predicate：`affiliated(person:organization:)`，依人的 affiliation timeline 與日期精度作 fail-closed 判定。
- authored 維持 open-world 與 unknown-not-false，並在 trace 明示它是 snapshot-scoped、time-invariant predicate。
- 以 TDD 覆蓋 deterministic replay、跨 revision、跨 valid day、時間精度邊界、context 傳遞與 #205 回歸。
- 更新正式規格、Tractatus 4.05 對照證據及自動產生的並排 Markdown。

## Capabilities

### New Capabilities

- `store-snapshot-identity`：定義可信 store identity、內容 revision、同次擷取／解碼與不可變 library snapshot 的契約。

### Modified Capabilities

- `proposition-semantics`：命題模型、valuation、answer 與 adjudication 改為 snapshot／valid-time/context-bound，並加入 affiliation temporal predicate 與 evidence trace。
- `organization-entity`：人的 affiliation timeline 新增可由確切有效日期查詢且對粗精度邊界 fail closed 的正式語意。

## Impact

- Affected specs: `store-snapshot-identity`、`proposition-semantics`、`organization-entity`
- Affected code:
  - `Package.swift`
  - `Sources/AkashicStoreIO/LibraryStore.swift`
  - `Sources/AkashicStoreIO/StoreIncarnation.swift`
  - `Sources/AkashicCore/Temporal.swift`
  - `Sources/AkashicProposition/{Proposition,Projection,Question}.swift`
  - StoreIO、Core 與 Proposition 對應測試
  - `docs/tractatus/corpus/4.yaml`
  - `docs/tractatus/generated/tractatus-project-map.md`
- API impact: `AkashicProposition` 新增對 `AkashicStoreIO` 的 target dependency；model、evaluate、answer、assertion 與 adjudication 呼叫端需要遷移到 typed time 與 context-bound results。
- Persistence impact: 本 change 只產生可保存的 snapshot ID，不建立歷史 snapshot 倉庫。
