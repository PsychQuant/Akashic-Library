# 命題公式語意與遷移指南

Akashic Library 只有一種 public 公式型別：`PropositionExpression`。它是具有固定資源
上限的 opaque value；遞迴 storage 與 raw node initializer 都不對外。每個可取得的公式
都已通過原子語法、Unicode、深度、節點數與不同原子數檢查，後續的古典求值、知識狀態
求值、問題、裁決與轉換都沿用這項 invariant。

本文件描述目前的 source-breaking 遷移方式、兩層語意、稽核 trace、固定 limits，以及
Unicode 15.1.0 正典化信任鏈。

## 建構公式

主要 public 入口都是 throwing factories：

```swift
let p = try PropositionExpression.atom(proposition)
let notP = try PropositionExpression.not(p)
let conjunction = try PropositionExpression.and(p, notP)
let disjunction = try PropositionExpression.or(p, notP)
let implication = try PropositionExpression.implies(p, notP)
let neither = try PropositionExpression.nor(p, notP)

// Atomic proposition 的便利入口；同樣會驗證並可能丟出 PropositionError。
let atomic = try proposition.asExpression()
```

Factory 不會替呼叫端化簡 double negation、交換 children、去重或短路。結構本身就是公式
identity 的一部分。建立成功後，可從唯讀的 `kind`、`proposition`、`children`、
`operatorDepth`、`nodeCount`、`atoms` 與 `canonicalBytes` 觀察結果；不能取得或偽造 raw
storage。原子驗證錯誤維持為 `PropositionError`，公式資源錯誤則是
`PropositionExpressionError`，失敗時不會留下部分公式。

### Source-breaking 遷移

這次變更刻意移除下列舊用法：

- `PropositionExpression` 不再是可由外部直接建立 raw cases 的 public recursive enum。
- 非 throwing 的 `Proposition.expression` 已移除；改用 `try proposition.asExpression()`。
- enum-style `.atom(...)`／`.not(...)` 建構與 raw case pattern matching 已移除；改用六個
  throwing factories，並以 `kind`、`proposition`、`children` 讀取結構。
- `EvidenceTrace.atomic`、`scope`、`projection`、`evidence`、`snapshotQuarantine` 等
  ambiguous root proxies 已移除。Binary trace 沒有唯一的 atomic leaf，必須遞迴走訪
  `children`，並在 leaf 讀取 `atomicEvidence`。
- `ClassicalValuation` 不接受 raw `Dictionary<Proposition, Bool>`；改傳
  `[(atom: Proposition, value: Bool)]`，讓 library 在建立自己的 lookup index 前先驗證
  count、atom 與 duplicate。

仍保留的 deprecated 遷移橋接如下；新程式碼不應再採用：

| Deprecated symbol | 新寫法 |
| --- | --- |
| `PropositionExpression.makeAtom(_:)` | `try PropositionExpression.atom(_:)` |
| `PropositionExpression.makeNot(_:)` | `try PropositionExpression.not(_:)` |
| `PropositionExpression.maximumOperatorDepth` | `PropositionLogicLimits.maximumOperatorDepth` |
| `EvidenceTrace.operand` | `children.first`，且只適用 `kind == .not` |

`YesNoQuestion` 的 initializer 也會預先以 `PropositionExpression.not(_:)` 保留否定答案所需
的結構，因此現在必須使用 `try`。這確保合法 subject 若已沒有一個否定節點的剩餘 budget，
會在問題建立時立即失敗。

## 固定且不可調整的 limits

所有 limits 都定義在 `PropositionLogicLimits`，沒有 public setter、initializer 參數、
`limit` 或 `budget` 參數可由呼叫端提高。

| Symbol | 固定值 | 約束 |
| --- | ---: | --- |
| `maximumReferenceUTF8ByteCount` | 4,096 | 每個 logical reference 的 raw 與 NFC-normalized UTF-8 bytes |
| `maximumOperatorDepth` | 64 | root 到最深 atom 的 operator 數 |
| `maximumNodeCount` | 4,096 | 一份 formula 的 atom 與 operator occurrence 總數 |
| `maximumDistinctAtomCount` | 63 | 一份 formula／valuation container 的不同原子數 |
| `maximumClassicalRows` | 4,096 | 完整古典真值表或 Boolean function table 的列數 |
| `maximumSupervaluationCompletions` | 4,096 | 一次 context-bound 求值可列舉的相容 completions |
| `maximumRewriteNodeCount` | 4,096 | `rewrittenUsingNor()` 的輸出節點 budget |
| `maximumSynthesisNodeCount` | 4,096 | `synthesizeUsingNor(_:)` 的輸出節點 budget |

完整列舉的 4,096 列上限等同最多 12 個 variables；公式本身仍可保存最多 63 個不同原子。
當完整真值表、等價性判定或 supervaluation 需要超過 4,096 種組合時，library 會在位移與
workspace 配置前丟出具型別錯誤，而不是接受呼叫端提供較高上限。

## 古典語意與 bounded supervaluation

這兩層處理的是不同問題，不能混用。

### Store-independent 古典語意

`ClassicalValuation` 是呼叫端明示提供的完整 Bool assignment。公式可使用：

- `classicalValue(under:)`
- `truthTable()`
- `isClassicallyEquivalent(to:)`
- `isClassicalTautology()`
- `isClassicalContradiction()`

這些 API 不讀 Akashic store、投射結果或 epistemic state。`ClassicalTruthTable` 依
canonical atom order 列舉完整二值 rows；缺少 assignment、duplicate、錯誤 output count
或超過 row limit 時會丟出 `ClassicalSemanticsError`。

`BooleanFunctionTable(atomsInInputBitOrder:outputsInInputBitRowOrder:)` 保存有限 Boolean
function。呼叫端提供的 atom bit order 只用來解讀傳入 outputs；儲存時 atoms 與 outputs
會同步換成 canonical order。

### Context-bound bounded supervaluation

`try expression.evaluate(in: ValuationContext)` 先把每個不同原子投射並求值一次，再對
所有 undetermined atoms 的相容 completions 做 compositional evaluation。若所有
completions 對某個 subformula 都為真或都為假，它可分別得到 `.holds` 或 `.fails`；結果
分歧時才得到 `.undetermined(.supervaluationInconclusive(atoms: ...))`。

這不是 strong Kleene evaluator，也不會因某個 absorbing operand 已足以決定結果便省略
另一個 child。每個 syntax occurrence 都會留下 trace。12 個 undetermined atoms恰為
4,096 completions；第 13 個會在列舉前丟出
`PropositionEvaluationError.supervaluationCompletionLimitExceeded`。

## Evidence trace

`Valuation` 保留完整的 `expression`、`truth`、`context` 與 `trace`。`EvidenceTrace` 是
與公式每個 syntax occurrence 對應的唯讀稽核樹：

- `kind` 與公式 node kind一致。
- `expression`、`context`、`conclusion` 保留該 occurrence 的完整結果。
- `children` 保留原公式的 child 順序。
- Atomic leaf 以 `atomicEvidence` 提供 `AtomicEvidenceTrace`。
- Operator node 以 `completionSummary` 提供 `SupervaluationSummary`，包含 completion count、
  是否觀察到 true，以及是否觀察到 false。

走訪時應從 root 使用 stack 或 recursion 逐層讀 `children`，在
`atomicEvidence != nil` 時處理 leaf。Deprecated `operand` 只是一版 unary 遷移橋接，
不能用來走訪 binary tree。

## Unicode 15.1.0 與正典 bytes

Logical key／literal 的正典化不依賴作業系統的 Unicode 版本。Repository 檢入下列五份
Unicode 15.1.0 UCD 官方輸入，位置為 `Vendor/Unicode/15.1.0/`：

1. `UnicodeData.txt`
2. `CompositionExclusions.txt`
3. `DerivedNormalizationProps.txt`
4. `PropList.txt`
5. `NormalizationTest.txt`

`unicode-normalization-v1.manifest.json` 固定：

- `schema_version` 與 `unicode_version`
- 五份 `inputs` 的官方 URL 與 SHA-256
- `generator`、`runtime_normalizer`、`generated_tables` 三種 source role、path 與 SHA-256
- 四個 versioned canonical domains
- `regeneration_command`

信任鏈的程式檔分別是：

- `Tools/UnicodeNormalizationGenerator/main.swift`
- `Sources/AkashicProposition/UnicodeNormalizationV1.swift`
- `Sources/AkashicProposition/Generated/UnicodeNormalizationTablesV1.swift`

離線重播命令為：

```sh
swift run UnicodeNormalizationGenerator --ucd-root Vendor/Unicode/15.1.0 --manifest unicode-normalization-v1.manifest.json --output Sources/AkashicProposition/Generated/UnicodeNormalizationTablesV1.swift --verify-v1
```

Generator 只讀檢入的 UCD；`--verify-v1` 會核對 manifest、輸入與 source digests，重播結果
必須與檢入的 generated Swift source byte-identical。測試另以
`Tests/AkashicPropositionTests/Fixtures/UnicodeNormalizationV1TrustAnchor.json` 固定獨立
SHA-256 anchors。

Runtime 對每個 reference 採固定順序：

1. raw UTF-8 early-exit cap
2. 既有 ASCII key grammar，或 pinned `White_Space` literal syntax
3. 依 source scalar order檢查 Unicode 15.1.0 assigned scalars
4. repository-pinned streaming NFC 與 normalized UTF-8 cap

正典序列化使用四個不同 domains：

- `akashic-proposition-atom-v1`
- `akashic-proposition-expression-v1`
- `akashic-classical-truth-table-v1`
- `akashic-boolean-function-table-v1`

Unicode 版本或 admitted scalar set 若要更新，必須建立新的 domain／manifest 版本與遷移，
不能在 v1 名稱下無聲改變 bytes。

### 正典化的明確界線

- NFC 只統一 admitted scalar set內正典等價的 Unicode spelling；它不是 semantic
  normalization，不會合併別名、同義詞、大小寫、identity 或命題意義。
- `canonicalBytes` 是可重播的結構編碼；Swift `Hashable` 仍不保證不碰撞，也不應把
  `hashValue` 當成永久格式或 identity。
- `ClassicalTruthTable.canonicalBytes` 與 `BooleanFunctionTable.canonicalBytes` 使用不同
  domains。即使 atoms 與 output vector 相同，也不應主張或比較跨型別 bytes 相等。
- 呼叫端不能調高任何固定 limit。

## 零元 Boolean function

零元 `BooleanFunctionTable` 是合法資料形狀，但必須恰有一個 output：

```swift
let constantTrue = try BooleanFunctionTable(
    atomsInInputBitOrder: [],
    outputsInInputBitRowOrder: [true]
)
```

它可表示零元 constant function；公式 AST 則沒有 constant node。因此
`try PropositionExpression.synthesizeUsingNor(constantTrue)` 會丟出
`PropositionTransformationError.zeroArityFunctionUnsupported`。Library 不會偷偷加入常數
case 或用任意原子偽裝它。

## 診斷 rendering 與 Mirror

資源、古典、求值與轉換 errors 的 associated values 保留完整 machine payload；自動的人類
可見 rendering（`localizedDescription`、`String(describing:)`、`String(reflecting:)`）會以
`displaySafe` 消毒 caller-controlled references、限制顯示的 atoms 筆數，並套用固定訊息
長度上限。

這項 automatic rendering 保證不包含直接 `Mirror` 存取。Public associated values 原本就
允許呼叫端主動讀取完整 machine payload；若程式自行用 `Mirror` 展開它，必須自行負責
消毒、截斷與輸出邊界。
