## Why

origin/main 的 e16c6f6 已新增具型別命題、投射、三值答案與裁決的垂直切片，但目前工作區因保留既有未提交 Tractatus 工作而刻意未執行 Git merge；正典語料仍把相關能力描述為尚未實作。需要在不帶入無關遠端變更、不改寫使用者 Git 狀態的前提下，精準整合該切片，並讓規格、逐條對照、測試與未完成邊界一致。

## What Changes

- 精準物化 e16c6f6 的 AkashicProposition 原始碼、測試與 SwiftPM target 宣告，並逐檔核對內容，不執行 pull、merge、stage 或 commit。
- 新增 proposition-semantics 正式能力規格，定義封閉命題型別、entity reference、投射結果、三值真值、問句答案空間，以及 assertion 到 accepted fact 的裁決邊界。
- 更新受該垂直切片影響的《邏輯哲學論》逐條專案關係、現況證據與歷史參照；只在可由程式碼、測試或規格直接證成時提升狀態。
- 要求每筆 aspirational 關係至少保留一個 GitHub issue 歷史參照，讓尚未實作的主張具有可追蹤的工程邊界。
- 依 IDD 建立並診斷仍未完成的有效時間／store revision、明確否定／否定答案、真值函數組合，以及命題建構／model identity 完整性邊界；四個 issues 保持開啟，不以本變更冒充實作完成。

## Capabilities

### New Capabilities

- proposition-semantics: Akashic 的具型別命題、投射、三值問答與受控事實接受模型。

### Modified Capabilities

- tractatus-project-map: 願景關係必須連到 issue 歷史，且命題語意垂直切片的目前證據與逐條關係必須反映實際工作區狀態。

## Impact

- Affected specs:
  - New: openspec/specs/proposition-semantics/spec.md
  - Modified: openspec/specs/tractatus-project-map/spec.md
- Affected code:
  - Package.swift
  - Sources/AkashicProposition/Proposition.swift
  - Sources/AkashicProposition/Projection.swift
  - Sources/AkashicProposition/Question.swift
  - Tests/AkashicPropositionTests/PropositionTests.swift
  - Sources/TractatusDocs/Validation.swift
  - Tests/TractatusDocsTests/CorpusValidationTests.swift
- Affected canonical data and generated output:
  - docs/tractatus/corpus/*.yaml
  - docs/tractatus/generated/tractatus-project-map.md
- External tracking:
  - Four GitHub issues created and diagnosed through the requested IDD workflow.
- No Akashic store schema, persisted entity format, CLI store command, MCP schema, or application behavior is migrated by this change.
