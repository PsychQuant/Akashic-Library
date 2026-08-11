# Mutation evidence：complete bounded proposition formula semantics

日期：2026-08-11  
基準：`43a2910c44c73c9609eff4467f616c0d2b654958`  
共同命令前綴：

```sh
swift test --disable-automatic-resolution \
  --scratch-path /tmp/akashic-214-mut-41-limit \
  -Xswiftc -warnings-as-errors --filter <locator>
```

所有 mutation 都只暫時修改一個 production seam，以 `apply_patch` 寫入與精確反向
patch 復原；每組結束後以 `git status --short`、`git diff --check` 與 SHA-256
確認沒有 production mutation 殘留。

## 4.1 Expression／Unicode／classical

| Production mutation | Load-bearing locator | RED evidence |
|---|---|---|
| `PropositionLogicLimits.maximumNodeCount` 由 4,096 改成 4,095（同批 off-by-one probe 亦把 depth guard `<=` 改成 `<`） | `ExpressionConstructionTests/testExpressionBudgetsAcceptExactBoundaryAndRejectNextValue` | 1 test／2 failures；固定常數由 4,096 變 4,095，且合法的 depth 64 被拒絕。 |
| `PropositionExpression.structuralHashFeed` 移除完整 canonical atom payload | `ExpressionConstructionTests/testStructuralHashFeedIncludesAtomTableEveryNodeTagAndChildBoundary` | 1 test／2 failures；`atom(p)` 與 `atom(q)` feed 變成相同，atomPayload 數量由 2 變 0。 |
| classical `.implies` truth cell 由 `!lhs || rhs` 改成 `lhs || rhs` | `ClassicalSemanticsTests/testEveryBinaryOperatorHasCompleteFourRowMatrix` | 1 test／1 failure；實得 `[false,true,true,true]`，預期 `[true,true,false,true]`。 |
| pinned Unicode runtime version 改成 `15.0.0`，但不更新 v1 trust-chain domain／manifest | `ExpressionConstructionTests/testUnicodeV1TrustChainAndOfficialConformanceArePinned` | 1 test／4 failures；runtime source SHA、manifest source digest與 offline regeneration 都拒絕漂移。 |

這組同時由既有 RED locators 承重 count→validate→duplicate、guard-before-shift、
六種 node tag／length／row-index canonical goldens、caller bit-order permutation、
unsupported-before-normalized-overflow 與 raw/syntax/normalization precedence；上述四個
實際 mutation 選取資源、hash payload、truth cell與 trust chain 四條獨立失效面。

## 4.2 Supervaluation／trace／question

| Production mutation | Load-bearing locator | RED evidence |
|---|---|---|
| supervaluation `.or` 只取左 child，遺失右 child completion | `SupervaluationTests/testUnknownExcludedMiddleHoldsAndUnknownContradictionFails` | 1 test／1 failure；unknown excluded middle 由 `holds` 退化成 `supervaluationInconclusive`。 |
| `EvidenceTrace.operation` 將 ordered children 反轉 | `SupervaluationTests/testEverySubformulaProducesOrderedContextBoundTrace` | 1 test／6 failures；root children、preorder kind與 exact occurrence expression 全部被 locator 捕捉。 |
| `YesNoQuestion` internal answer seam 重評 subject 一次 | `SupervaluationTests/testQuestionReservesNegationAndNoAnswerDoesNotReevaluateAtoms` | observer 從單一 atom 變成相同 atom 兩次，測試轉紅；證明 no-answer 只能包裝原 valuation。 |

既有同 suite locators另直接固定 absorbing truth仍保留兩邊 refusal/context、duplicate atom
只投射一次、第 13 個 unknown 在 shift／allocator 前拒絕，以及 assertion／denied stance
不得經 question path 偷換 expression identity。

## 4.3 NOR rewrite／synthesis

| Production mutation | Load-bearing locator | RED evidence |
|---|---|---|
| `not(p)` 的 NOR plan 由 `nor(p,p)` 改成原 child | `TruthFunctionSynthesisTests/testNorRewritePreservesEveryOperatorAndUsesOnlyNor` | 1 test／1 unexpected failure；獨立 structural verifier 拋 `rewriteVerificationFailed`。 |
| rewrite node maximum 改成 `Int.max`，等同移除固定 node guard | `TruthFunctionSynthesisTests/testRewriteAndSynthesisRespectFixedExpansionBudget` | warnings-as-errors 在 guard body報「will never be executed」，mutation 在測試前即轉紅。 |
| rewrite self-check 忽略 caller 的 per-call fault injector、固定使用 `.noOp` | `TruthFunctionSynthesisTests/testRewriteSelfCheckRejectsCorruptedPlan` | 1 test／1 failure；預期 `rewriteVerificationFailed`，實際沒有拋錯。 |

完整 transformation suite另外固定五種 exact rewrite、16 個 binary masks、三原子
non-symmetric DNF、全真／全假 all-atoms construction、4,095／4,097／4,103
邊界、synthesis fault injector與 fresh-process canonical replay；因此代表 mutation 不是只靠
semantic equivalence 假綠，而會由 structural／budget／independent verifier 三條路徑攔截。

## 復原 gate

Mutation 全部復原後，production tree 無任何 mutation diff；最終安全掃描另外只加入
`display-safe-exempt` 理由註解。完成所有閘門時的 SHA-256 如下：

```text
Expression.swift                 481f556b0203e2b4de183e619b6238bd15d7d5f865b03de61589c28bd8553818
ClassicalSemantics.swift         5d7bb6842548d934d46d35107b553eb4f4c1ed7b6be28a135c64a033658a1559
UnicodeNormalizationV1.swift    a4b19c16dfe54f1a19c2ba3b5ab6f8436cf25835b2d3710658b3c1cc9e1965cd
Projection.swift                 674698743f1dd15c4aef2086bdd33a872e438f715acd5425b482288662c28f78
Question.swift                   426587fa9c3f65fd8457a07d62cf7584715c604f888284f35619f95593f7b0ec
TruthFunctionSynthesis.swift     c051a85a770aff53f8d954289765dd8a2db490391d42b0365dca242a1522e7b3
```

## 4.4 最終閘門

- 完整 warnings-as-errors suite：1,468 tests、1 skipped、0 failures。
- `AkashicPropositionTests`：118／118。
- fresh subprocess canonical replay：通過；child 直接由目前 XCTest bundle 啟動，沒有
  遞迴 SwiftPM lock。
- Unicode 15.1.0 offline `--verify-v1` regeneration：byte-identical，manifest／runtime／
  generator／generated source digest 全部相符。
- `spectra validate ... --strict`：valid；`spectra analyze ... --json` 四維度全 Clean。
- `tractatus-doc validate`：534 propositions／2,399 source units／1,186 segments／534
  project relations；`render --check` clean。
- `DisplaySinkCoverageTests`：新增診斷路徑全數有 bounded sanitizer 或同列的封閉 enum／
  純整數安全理由。
