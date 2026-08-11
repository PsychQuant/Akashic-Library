## Why

目前命題層只有有界 atom／not，無法以正式規格表達 and、or、implies、nor、完整二值真值條件與子公式證據；PR #210 的另一套 `Formula` 又採 strong Kleene 且讓 caller 放寬列舉上限，會造成語意分歧、證據遺失與遞迴／指數資源耗盡。#214 必須在既有 snapshot-bound `PropositionExpression` 上建立單一、有硬界線、可重播且可稽核的 truth-functional 語意。

## What Changes

- **BREAKING**：把 public recursive enum `PropositionExpression` 收斂為 opaque value；只有 throwing factories 能建立 atom、not、and、or、implies、nor，外部 caller 無法直接組 raw storage 或提高資源上限。
- **BREAKING**：移除 nonthrowing `Proposition.expression` 與 ambiguous root trace proxies；所有expression construction、question與adjudication caller改用throwing factory與recursive trace traversal，只保留一版deprecated unary `operand` read-only view作遷移橋接。
- **BREAKING**：logical key／literal 的 raw 與 pinned-NFC UTF-8 各限 4,096 bytes，並拒絕 Unicode 15.1.0 未指派 scalar；超界或版本外輸入不再能進入命題語意。
- 新增完整、bivalent、store-independent classical valuation、決定性 truth table、semantic equivalence、tautology／contradiction 判定。
- 新增 snapshot-bound bounded supervaluation：每個 distinct atom 在同一 context 求值一次，所有相容 completions 全同真／全同假才建立 holds／fails，否則保留具名 undetermined。
- 每個 syntax occurrence 產生 source-order、context-bound trace node；不得以 short-circuit 丟棄 child projection、evidence、quarantine 或 refusal。
- 新增固定 reference-byte／atom／depth／node／row／completion／rewrite hard bounds與 typed fail-closed errors；所有 trimming、normalization、shift、allocation、rewrite 先做 overflow-safe preflight。
- Canonical bytes 使用檢入的五份官方 Unicode 15.1.0 inputs、完整 SHA-256 trust chain、pinned White_Space／capped streaming NFC、fixed framing 與六種 node tag exact golden vectors，不受 OS／toolchain normalization 或 whitespace table 漂移。
- `ClassicalValuation` 以 entry list先驗證再建立library-owned index，不接受會在initializer前hash raw `Proposition`的dictionary；既有`PropositionExpression.maximumOperatorDepth`保留deprecated safe alias。
- 新增有界 NOR rewrite 與 truth-table-to-NOR synthesis，完整驗證 16 種二元 Boolean functions、決定性 canonical bytes 與 truth-preserving self-check。
- 不保留 PR #210 的第二套 `Formula`、strong Kleene evaluator或 caller-adjustable limit。

## Capabilities

### New Capabilities

- `finite-truth-function-semantics`: 定義有界 classical truth tables、semantic equivalence、NOR rewrite／synthesis、決定性列序與不可放寬的資源界線。

### Modified Capabilities

- `proposition-semantics`: 將有界 unary expression 擴為單一 opaque truth-functional expression，並把 epistemic evaluation 改為 context-bound bounded supervaluation與完整 subformula trace。

## Impact

- Affected specs: `finite-truth-function-semantics`, `proposition-semantics`
- Affected code:
  - New:
    - Sources/AkashicProposition/ClassicalSemantics.swift
    - Sources/AkashicProposition/TruthFunctionSynthesis.swift
    - Sources/AkashicProposition/UnicodeNormalizationV1.swift
    - Sources/AkashicProposition/Generated/UnicodeNormalizationTablesV1.swift
    - Tools/UnicodeNormalizationGenerator/
    - Vendor/Unicode/15.1.0/
    - unicode-normalization-v1.manifest.json
    - Tests/AkashicPropositionTests/ExpressionConstructionTests.swift
    - Tests/AkashicPropositionTests/ClassicalSemanticsTests.swift
    - Tests/AkashicPropositionTests/SupervaluationTests.swift
    - Tests/AkashicPropositionTests/TruthFunctionSynthesisTests.swift
  - Modified:
    - Package.swift
    - Sources/AkashicCore/Models.swift
    - Sources/AkashicProposition/Proposition.swift
    - Sources/AkashicProposition/Expression.swift
    - Sources/AkashicProposition/Projection.swift
    - Sources/AkashicProposition/Question.swift
    - Tests/AkashicPropositionTests/NegationTests.swift
    - Tests/AkashicPropositionTests/AuthorshipCompletenessPropositionTests.swift
    - Tests/AkashicPropositionTests/ContextValuationTests.swift
    - Tests/AkashicPropositionTests/PropositionTests.swift
    - Tests/AkashicKitTests/DisplaySafeTests.swift
  - Removed: none
