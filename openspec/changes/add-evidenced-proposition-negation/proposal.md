## Why

現行命題層只有 atomic predicate，`.no` 與 `Stance.denied` 都不是可求值、可主張或可裁決的 `¬p`；同時 authored 缺少具來源且綁定 canonical 作者清單 snapshot 的完備性證言，因此資料缺席正確地只能是未定，卻沒有任何可稽核的負向成立路徑。#202 已建立 snapshot／revision／valid-day context 與 typed trace，現在必須讓否定與反證沿用同一條可重播邊界，並為 #204 的有限真值函數共用單一 expression 型別。

## What Changes

- 新增結構式、可雜湊且遞迴驗證的 `PropositionExpression.atom／not`；double negation 保留語法結構差異，但求值與原 operand 相同。
- 否定求值只交換 `holds`／`fails`，完整保留 `undetermined` 原因、context 與 operand evidence trace；trace 的原始節點建構限於模組內，對外只暴露唯讀結構視圖，相等比較必須以迭代 traversal 避免深鏈爆棧。
- **BREAKING**：question、valuation、assertion、adjudication 與 accepted fact 改以 `PropositionExpression` 作為命題內容，不再把 atomic `Proposition` 當成完整 expression。
- no-answer 除了 `.no` 標籤，還必須攜帶 truth 為 `holds` 的 `¬subject` established answer；未定答案不得偽造 established expression。
- 在 Entry 的 Akashic-owned canonical metadata 新增作者清單完備性證言；證言綁定 work UUID、ordered exact 作者槽 snapshot、具 domain separator 與 length-prefix framing 的 author-list fingerprint，以及由 content-addressed retrieval 到 judgement `rests-on` 的 `authors` provenance chain。
- authored 只有在證言與當下 canonical Entry 完全相符、作者槽全數已歸戶且排除目標 person 時才產生 `fails`。證言缺席或任何 literal 仍為具名 `undetermined`；YAML／provenance shape 不合法時 decode fail closed 並 quarantine；well-formed 但 work／作者 snapshot 過期時 model construction 擲具型別 binding error，三類結果不得互相降格。
- asserted `¬p` 只有在相同 expression 的 valuation 為 `holds` 時才能產生 `AcceptedFact`；`Stance.denied(p)` 仍只是來源立場，不自動轉換成 asserted `¬p`。
- 更新規格、store-format 文件、測試與《邏輯哲學論》4.023、4.05、4.06、4.2、4.25、4.26、4.431、5、5.31、5.44、5.51、5.512、6.5 對照；所有關係仍維持誠實的 partial／aspirational／intentional-nonconformance 邊界，不宣稱完成 #204 的 conjunction／disjunction／implication。

## Capabilities

### New Capabilities

- `authorship-completeness-witness`: 定義 canonical 作者清單完備性證言的資料形狀、provenance chain、snapshot 綁定、序列化與 fail-closed 驗證。

### Modified Capabilities

- `proposition-semantics`: 新增顯式否定 expression、三值否定、negative answer content、遞迴 evidence trace，以及 negative assertion／fact gate。

## Impact

- Affected specs: `authorship-completeness-witness`（新增）、`proposition-semantics`（修改）
- Affected code:
  - New: `Sources/AkashicCore/AuthorshipCompleteness.swift`, `Tests/AkashicKitTests/AuthorshipCompletenessTests.swift`, `Tests/AkashicPropositionTests/NegationTests.swift`, `openspec/changes/add-evidenced-proposition-negation/specs/authorship-completeness-witness/spec.md`
  - Modified: `Sources/AkashicCore/Models.swift`, `Sources/AkashicCore/YAML.swift`, `Sources/AkashicProposition/Proposition.swift`, `Sources/AkashicProposition/Projection.swift`, `Sources/AkashicProposition/Question.swift`, `Tests/AkashicKitTests/StoreIOTests.swift`, `Tests/AkashicPropositionTests/PropositionTests.swift`, `Tests/AkashicPropositionTests/ContextValuationTests.swift`, `docs/store-format.md`, `docs/tractatus/corpus/4.yaml`, `docs/tractatus/corpus/5.yaml`, `docs/tractatus/corpus/6.yaml`, `docs/tractatus/generated/tractatus-project-map.md`, `openspec/changes/add-evidenced-proposition-negation/specs/proposition-semantics/spec.md`
  - Removed: none
