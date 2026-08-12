# Design：有界命題公式語意、子公式 trace 與有限真值函數完備性

## Context

AkashicProposition 目前以 `Proposition` 表示封閉的 atomic predicate，並由 `PropositionExpression` 承接 `atom` 與結構式 `not`。現行 expression 是 public enum，呼叫端可以直接使用 raw cases，繞過 factory 與深度驗證；expression evaluator 也只處理 unary chain。`EvidenceTrace` 因而只有 atom／negation 形狀，並以 `atomic`、`scope`、`projection`、`evidence` 等 root proxy 假定整棵樹只有一個最內層 atom。這些假定不能安全延伸到 and／or／implies／nor。

PR #210 曾另建 `Formula`，加入 classical truth table、semantic equivalence、strong-Kleene partial evaluation 與 NOR rewrite。該方向不能直接採用：第二套 AST 會使 assertion、question、valuation 與 trace 失去單一 expression identity；strong Kleene 會令 unknown `p` 的 `p ∨ ¬p` 仍為未定，與 #214 選定的 bounded completions／supervaluation 不一致；caller-adjustable enumeration limit 與未檢查的 `1 << atoms.count` 也可造成 overflow 或不受控資源消耗。

本設計以 #205 的 canonical-input boundary、#212 的 snapshot-bound `ValuationContext` 與 #213 的 expression-aware recursive trace 為既定前置。實作前須依序封存 `harden-proposition-canonical-input-boundary`、`bind-proposition-valuations-to-store-snapshots`、`add-evidenced-proposition-negation`，再以封存後 canonical specs 建立 #214 delta。封存順序是規格基底前置條件，不改變本設計的 runtime contract。

## Goals / Non-Goals

### Goals

- 維持唯一的 public `PropositionExpression`，在同一 opaque、hard-bounded 結構中支援 atom、not、and、or、implies、nor。
- 正式分離 classical bivalent semantics 與 context-bound epistemic partial semantics。
- partial evaluator 採 bounded supervaluation，並釘住 tautology、contradiction、implication 與 mixed-known／unknown 反例。
- 每個 syntax occurrence 都產生具 exact expression、context、conclusion 與 ordered children 的 trace node；每個 atom leaf 保留 projection、evidence、quarantine 與原始 refusal。
- 所有 atom、depth、node、row、completion、rewrite 預算由 library 固定，呼叫端不能提高。
- 所有 enumeration 與 generated-tree size 在 shift、配置或建立節點前完成 checked preflight，超界以具型別錯誤 fail closed。
- 提供 deterministic classical truth table、semantic equivalence、NOR-only rewrite 與 bounded truth-table-to-NOR synthesis。
- 以完整二原子 operator matrix、全部 16 種二元 Boolean functions、byte-for-byte replay 與 load-bearing mutation probes 作為驗收證據。

### Non-Goals

- 不加入量化、模態、機率、無限公式、一般 SAT solver、theorem prover 或 symbolic simplifier。
- 不改變 `Proposition` 的封閉 predicate 集合，也不建立字串式 predicate registry。
- 不改變 authored completeness witness、negative adjudication、snapshot identity 或 valid-time affiliation 的既有 atomic semantics。
- 不把 `Stance.denied` 轉成 asserted negation。
- 不保留或移植 PR #210 的第二套 `Formula`、strong-Kleene evaluator 或 caller-adjustable `limit`。
- 不保證每一張 row budget 內的 truth table 都能在 node／depth budget 內產生公式；超出 deterministic synthesis construction budget 時回傳具型別錯誤。
- 不支援無 atom 的 constant-expression AST；`BooleanFunctionTable` initializer 接受 0...12 atoms，零元形式可表示唯一一列的 constant table，但 synthesis 明確以具型別錯誤拒絕。

## Decisions

### Decision 1：以單一 opaque `PropositionExpression` 承接所有公式

`PropositionExpression` 由 public indirect enum 改為 public struct，內部使用 private indirect storage。public surface 不提供 raw cases 或 public initializer；所有 instance 都只能由 throwing factories 或既有 expression 的 read-only child view 取得。因此一旦 factory 回傳，結構、nested atoms 與 cached metrics 均已符合 hard bounds，evaluation、equality 與 hashing 不必重新接受未驗證樹。

```swift
public struct PropositionExpression: Hashable {
    public enum Kind: Equatable {
        case atom
        case not
        case and
        case or
        case implies
        case nor
    }

    public var kind: Kind { get }
    public var proposition: Proposition? { get }
    public var children: [PropositionExpression] { get }
    public var operatorDepth: Int { get }
    public var nodeCount: Int { get }
    public var atoms: [Proposition] { get }
    public var canonicalBytes: Data { get }

    @available(*, deprecated, message: "Use PropositionLogicLimits.maximumOperatorDepth")
    public static var maximumOperatorDepth: Int { get }

    public static func atom(_ proposition: Proposition) throws -> Self
    public static func not(_ operand: Self) throws -> Self
    public static func and(_ lhs: Self, _ rhs: Self) throws -> Self
    public static func or(_ lhs: Self, _ rhs: Self) throws -> Self
    public static func implies(_ lhs: Self, _ rhs: Self) throws -> Self
    public static func nor(_ lhs: Self, _ rhs: Self) throws -> Self
}

extension Proposition {
    public func asExpression() throws -> PropositionExpression
}
```

`proposition` 只在 atom node 非 nil。`children` 的 arity 固定為 atom 0、not 1、binary operators 2，binary 順序永遠是 lhs、rhs。`operatorDepth` 定義為 atom 0、operator 為 `1 + max(child depth)`；`nodeCount` 計算 structural occurrences，不以 storage sharing 折疊；`atoms` 是 distinct `Proposition` 的 canonical order。

Structural `Equatable`／`Hashable` 納入 canonical atom-table payload、node tag、child order 與 occurrence atom index，不做 double-negation、commutativity 或其他 semantic normalization。`atom(p)` 與 `atom(q)` 的 hash feed 因 canonical atom payload 不同而不同；`not(not(p))` 與 `p` 必須維持不同 identity，即使 classical equivalence 為 true。這不承諾不同 feed 的最終 `hashValue` 不碰撞。

既有 `makeAtom`、`makeNot` 保留為 deprecated forwarding wrappers，`PropositionExpression.maximumOperatorDepth` 也保留為指向 `PropositionLogicLimits.maximumOperatorDepth` 的 deprecated read-only alias，避免安全 factory／limit 使用者立即中斷；非 throwing 的 `Proposition.expression` 移除。原因是 raw `Proposition` cases 仍可承載 malformed key／empty literal，非 throwing property 無法同時保證 expression invariant 與原始 `PropositionError`。

### Decision 2：以固定、不可提高的 library budgets 定義可接受公式與運算

```swift
public enum PropositionLogicLimits {
    public static let maximumReferenceUTF8ByteCount = 4_096
    public static let maximumOperatorDepth = 64
    public static let maximumNodeCount = 4_096
    public static let maximumDistinctAtomCount = 63
    public static let maximumClassicalRows = 4_096
    public static let maximumSupervaluationCompletions = 4_096
    public static let maximumRewriteNodeCount = 4_096
    public static let maximumSynthesisNodeCount = 4_096
}
```

沒有 public initializer、setter、`limit` 或 `budget` 參數。任何 logical key／literal 在進入 library-owned syntax validation、whitespace trimming、Unicode normalization、hashing 或 canonical `Data` 前，先以 early-exit UTF-8 計數檢查 raw bytes；第 4,097 個 byte 出現就拒絕，不掃描完整巨大輸入。Literal 通過 syntax 檢查後，再以 repository-pinned Unicode NFC 實作正規化，並對 normalized UTF-8 套用同一上限。Factories 再依 depth、node count、distinct atom count 的順序檢查 candidate metrics。每個 operand 已經 bounded，因此加法採 checked arithmetic，並在 overflow 時視為超過相應 maximum。Metrics 儲存在 private storage，binary factory 合併 bounded canonical atom lists，不在每次 query 重走整棵樹。

邊界行為固定如下：

- depth 64 接受；新增第 65 層 operator 時丟出 depth error。
- raw 與 pinned-NFC normalized logical reference 各自 4,096 UTF-8 bytes 接受；計數觀察到第 4,097 byte 就以 typed `PropositionError` 拒絕。超長空白 literal 的 resource error 優先於 `emptyLiteral`。
- node count 4,096 接受；candidate 4,097 在建立 storage 前拒絕。
- 63 distinct atoms 接受；加入第 64 個 distinct atom 時拒絕。
- 63-atom expression 本身合法，但 `truthTable()` 在任何 shift 或 row allocation 前因 4,096-row limit 拒絕。
- classical rows 與 supervaluation completions 的 4,096 上限等同最多列舉 12 個 Boolean variables。實作先判斷 variable count `<= 12`，之後才可計算 `1 << count`。
- rewrite 與 synthesis 先以 saturating／checked arithmetic 計算 structural output depth 與 node count；大於上限時不得建立部分輸出樹。

`YesNoQuestion` initializer 除了接受 subject，還必須成功建立並私下保留 `not(subject)`，同時預留一個 operator node、node count 與 depth。合法 expression 若已用滿 depth 64 或 node count 4,096，仍會被 question initializer 以既有 expression error 拒絕，確保 determinate no-answer 一定可表示。

### Decision 3：資源、classical 與 transformation 失敗使用分層 typed errors

```swift
public enum PropositionExpressionError: Error, Equatable {
    case operatorDepthExceeded(actual: Int, maximum: Int)
    case nodeCountExceeded(actual: Int, maximum: Int)
    case distinctAtomCountExceeded(actual: Int, maximum: Int)
}

public enum PropositionReferenceEncodingStage: String, Equatable, Sendable {
    case rawUTF8
    case normalizedUTF8
}

public enum ClassicalSemanticsError: Error, Equatable {
    case valuationAtomLimitExceeded(actual: Int, maximum: Int)
    case duplicateValuationAtom(Proposition)
    case incompleteValuation(missing: [Proposition])
    case rowLimitExceeded(atomCount: Int, maximumRows: Int)
    case duplicateFunctionAtom(Proposition)
    case outputCountMismatch(expected: Int, actual: Int)
}

public enum PropositionEvaluationError: Error, Equatable {
    case supervaluationCompletionLimitExceeded(
        undeterminedAtomCount: Int,
        maximumCompletions: Int
    )
}

public enum PropositionTransformationError: Error, Equatable {
    case rewriteDepthLimitExceeded(minimumRequired: Int, maximum: Int)
    case rewriteNodeLimitExceeded(minimumRequired: Int, maximum: Int)
    case synthesisDepthLimitExceeded(minimumRequired: Int, maximum: Int)
    case synthesisNodeLimitExceeded(minimumRequired: Int, maximum: Int)
    case zeroArityFunctionUnsupported
    case rewriteVerificationFailed
    case synthesisVerificationFailed
}
```

Malformed atomic syntax仍原樣丟出 `PropositionError`，不包裝成 expression resource error。`PropositionError` 新增 `referenceUTF8ByteCountExceeded(stage:minimumObserved:maximum:)` 與 `unsupportedUnicodeScalar(value:normalizationVersion:)`；前者的 `minimumObserved` 在 early-exit 時固定為 4,097，後者只帶 scalar number 與 library-owned version，不帶 raw string。`minimumRequired` 使用 saturating result；若精確結果大於可安全表示範圍，就固定回報 `maximum + 1`，不做會 overflow 的精確計算。所有新 errors 均採 `LocalizedError + CustomStringConvertible + CustomDebugStringConvertible`；`TruthValue` 與 `UndeterminedReason` 也提供 bounded `description`／`debugDescription`。Machine payload 保持完整，`localizedDescription`、`String(describing:)` 與 `String(reflecting:)` 只顯示最多 5 筆 caller atoms，每筆先以 `displaySafe(max: 120)` 處理，再將完整訊息限制在 2,048 Unicode scalars；不得以自動 reflection 洩漏完整 caller-controlled `Proposition` payload。`displaySafe` 本身改用 bounded reserve／iteration，不先計算完整 `unicodeScalars.count`。Public associated-value machine payload 仍可由 caller 主動讀取，本契約不宣稱能阻止 `Mirror`。

### Decision 4：classical semantics 是獨立、完整的 bivalent layer

```swift
public struct ClassicalValuation: Equatable {
    public init(assignments: [(atom: Proposition, value: Bool)]) throws
}

public struct ClassicalTruthTable: Equatable {
    public struct Row: Equatable {
        public let inputs: [Bool]
        public let output: Bool
    }

    public let atoms: [Proposition]
    public let rows: [Row]
    public let canonicalBytes: Data
}

public struct BooleanFunctionTable: Equatable {
    public let atoms: [Proposition]
    public let outputs: [Bool]
    public let canonicalBytes: Data

    public init(
        atomsInInputBitOrder atoms: [Proposition],
        outputsInInputBitRowOrder outputs: [Bool]
    ) throws
}

extension PropositionExpression {
    public func classicalValue(under valuation: ClassicalValuation) throws -> Bool
    public func truthTable() throws -> ClassicalTruthTable
    public func isClassicallyEquivalent(to other: Self) throws -> Bool
    public func isClassicalTautology() throws -> Bool
    public func isClassicalContradiction() throws -> Bool
}
```

`ClassicalValuation` 只保留 Bool assignment，不持有 `ValuationContext`、projection、evidence 或 undetermined reason。Initializer 刻意接受 entry list，而不是 `[Proposition: Bool]`：先以 array count 拒絕超過 63 entries，才逐筆做 raw byte cap、syntax、pinned normalization與 canonical encoding，接著以最多 63 筆的 bounded comparison拒絕 `duplicateValuationAtom`，最後才可建立 library-owned lookup index。如此 caller 不必在進入驗證前先對 raw `Proposition` 做 Dictionary hashing。Expression evaluation 要求其全部 canonical atoms 都有值，missing payload 依 canonical order回傳。最多 63 個額外 assignment 可存在，但不影響 expression結果；超過 63 一律拒絕，避免 valuation本身成為繞過 atom budget 的 public container。

每個 operator 的 truth function 固定為：not `!a`、and `a && b`、or `a || b`、implies `!a || b`、nor `!(a || b)`。二原子 canonical rows 固定為 `FF, FT, TF, TT`，第一個 canonical atom 是最高位、最慢變動位：

| Operator | FF | FT | TF | TT |
| --- | --- | --- | --- | --- |
| and | F | F | F | T |
| or | F | T | T | T |
| implies | T | T | F | T |
| nor | T | F | F | F |

`isClassicallyEquivalent` 以兩式 canonical atom union 建立共同 valuations，再逐列比較 outputs；不得呼叫 structural `==` 代替。Atom union 超過 row budget時丟 `rowLimitExceeded`。Tautology／contradiction 分別要求所有 rows 為 true／false。

### Decision 5：atoms、expressions、rows 與 bytes 使用單一 deterministic canonical order

所有 canonical byte surface 都以精確的 versioned ASCII domain 開頭，domain 本身也採 UInt64 big-endian byte length framing：

- atom：`akashic-proposition-atom-v1`
- expression：`akashic-proposition-expression-v1`
- classical truth table：`akashic-classical-truth-table-v1`
- caller-supplied Boolean function table：`akashic-boolean-function-table-v1`

Canonical atom payload 以固定 one-byte tag 區分 predicate（authored `0x00`、affiliated `0x01`），並以固定 one-byte tag 區分每個 `EntityRef` case（key `0x00`、literal `0x01`）。Expression preorder node tag 固定為 atom `0x00`、not `0x01`、and `0x02`、or `0x03`、implies `0x04`、nor `0x05`；這些值與 child order 都是 v1 public byte contract。

Canonicalizer 使用檢入 module 的 Unicode 15.1.0 normalization、assigned-scalar與 White_Space data；production 不呼叫 OS／Foundation 的浮動 normalization或 whitespace tables。Trust chain包含：

1. `Vendor/Unicode/15.1.0/` 中官方 `UnicodeData.txt`、`CompositionExclusions.txt`、`DerivedNormalizationProps.txt`、`PropList.txt` 與 `NormalizationTest.txt`。
2. `unicode-normalization-v1.manifest.json` 中每一份 UCD input 的固定 URL／SHA-256、Unicode version、generator source SHA-256、production runtime-normalizer source SHA-256、generated Swift table source SHA-256、manifest schema version與四個 canonical domains。
3. 可離線重播的固定command：`swift run UnicodeNormalizationGenerator --ucd-root Vendor/Unicode/15.1.0 --manifest unicode-normalization-v1.manifest.json --output Sources/AkashicProposition/Generated/UnicodeNormalizationTablesV1.swift --verify-v1`。它只讀vendored inputs，產生deterministic Swift tables，並拒絕在input／generator／runtime／generated digest改變而canonical domain仍為v1時覆寫結果。
4. 測試內獨立固定的manifest SHA-256、五份UCD input SHA-256、generator SHA-256、runtime-normalizer source SHA-256與generated-table source SHA-256，外加官方`NormalizationTest.txt`全量conformance及pinned White_Space fixtures。Static source gate掃描production canonicalization path並禁止`precomposedStringWithCanonicalMapping`、`decomposedStringWithCanonicalMapping`、`applyingTransform`、`StringTransform`、`CFStringNormalize`、`CharacterSet.whitespaces`／`whitespacesAndNewlines`及`trimmingCharacters(in:)`等Foundation／CoreFoundation normalization或whitespace入口。修改manifest與data但未升canonical domain，或把production改回平台API，必須使gate轉紅。

每個 raw logical reference 依固定順序處理：early-exit raw UTF-8 cap；使用 pinned White_Space table與既有 key grammar做 syntax validation；依 source-scalar order拒絕第一個 Unicode 15.1.0 未指派 scalar；最後透過 capped streaming NFC sink發出 normalized UTF-8，觀察到第 4,097 byte就停止並丟 normalized resource error，不先建立完整超界 buffer。若同一個 raw-cap內輸入同時含 unsupported scalar與會造成 normalized overflow的後段，unsupported scalar error優先；syntax error則先於兩者。Key仍須通過既有 ASCII grammar。每段可變長度 bytes前置 UInt64 big-endian byte length，每個可變長度集合或序列前置 UInt64 big-endian element count。Predicate arguments與AST children的arity已由tag固定，不另加count；每種surface以下方exact layout為準。如此一來，在 pinned admitted scalar set內Swift-equal的NFC／NFD literal會得到完全相同的canonical atom bytes，不必從輸入中挑選代表元，也不會因輸入順序、OS或toolchain normalization／whitespace版本而漂移。Distinct atoms依完整canonical atom bytes lexicographic排序。

Expression canonical payload 使用 root-first、lhs-before-rhs preorder。Domain 後先寫 UInt64 distinct atom count 與 canonical-order atom table，每筆 atom 使用 UInt64 length framing；再寫 UInt64 node count與依序的固定 node tag。Atom node寫UInt64 atom-table index，不重複內嵌同一大型atom bytes；operator arity由tag固定，不另依賴runtime type description。六種node tag各有exact suffix golden，另有非對稱nested-child-order golden；`not(p)` rewrite與同一unary truth vector synthesis都必須重播為exact `nor(p,p)` v1 bytes。在63 distinct atoms、4,096 nodes與每reference 4,096 bytes下，canonical `Data`大小有可推導的固定上限，不會依同一atom的occurrence數重複放大payload。Structural identity不做語意化簡，因此`not(not(p))`與`p`的expression canonical bytes不同。

`BooleanFunctionTable` initializer 接受 0...12 atoms；第一步只讀 `atoms.count`，超過 12 個 atoms 時，在 duplicate comparison、atom validation、shift 或 library-owned output 配置前丟 `rowLimitExceeded`。零 atoms 只接受恰好一個 output，以便保存唯一一列的 constant table；synthesis 仍以 `zeroArityFunctionUnsupported` 拒絕。對 0...12 atoms，initializer 依輸入順序先做 bounded atom validation，再以最多 12 筆的 bounded comparison 拒絕 Swift-equal duplicates，接著驗證 output count。非零 `atomsInInputBitOrder` 視為 caller truth-vector 的 bit order，第一個 atom 是最高位、最慢變動位。Initializer 再 canonicalize stored atoms，並將 caller outputs permutation 成 canonical atom order。對每個 canonical row index `j`，先解出 canonical bits，再依 `atomsInInputBitOrder[i]` 在 canonical atoms 中的 index 重排成 caller bits；該 bits 組成 `callerRowIndex`，並且 `storedOutputs[j] = suppliedOutputs[callerRowIndex]`。Stored `atoms` 與 `outputs` 因此永遠是 canonical order，不保留 caller order。

`ClassicalTruthTable.canonicalBytes` 先寫專屬 domain、UInt64 atom count 與逐筆 UInt64 length-framed canonical atom bytes，再寫 UInt64 row count；每列寫 UInt64 big-endian row index 與一個 Bool output byte。Input assignment 由 canonical atom order 與 row index 唯一重建，不重複寫入。`BooleanFunctionTable.canonicalBytes` 改用自己的專屬 domain，寫同樣的 canonical atoms、UInt64 row count，並對每列寫 UInt64 row index 與 canonical output byte。Bool 固定編碼為 `0x00`／`0x01`。兩種 table 描述相同函數時，canonical atoms 與 output vector 必須相同，但因 domain 不同，raw canonical bytes 必須不同。不得使用 `Dictionary` iteration、`Set` iteration、localized description、`Hasher` 或 encoder 的預設 key order。相同 logical input 重播必須產生 byte-for-byte 相同結果；NFC／NFD-equal atoms 也必須重播成相同 bytes。

### Decision 6：epistemic partial semantics 採 bounded supervaluation

對 expression `φ` 與 `ValuationContext`，先依 canonical atom order各求值一次，得到 partial atomic valuation `v : Atom -> {holds, fails, undetermined(reason)}`。定義 compatible completions 集合：

- `v(a) = holds` 時，每個 completion `c(a) = true`。
- `v(a) = fails` 時，每個 completion `c(a) = false`。
- `v(a) = undetermined(reason)` 時，`c(a)` 可為 false 或 true。
- 同一個 Swift-equal `Proposition` 的所有 syntax occurrences 共用同一 completion variable。

若 undetermined distinct atom count 大於 12，evaluator 在計算 `1 << count`、配置 completion buffers 或建立 operator trace 前丟 `supervaluationCompletionLimitExceeded`。否則依 canonical unknown-atom bit order 列舉全部 `2^n` completions；`n = 0` 時仍有唯一 completion。

每個 completion 以 iterative postorder 對每個 syntax occurrence 計算 classical Bool，並為每個 node ID 累積 `observedTrue`／`observedFalse` bit。Stable node ID 由 root-first、lhs-before-rhs preorder配置；postorder evaluator 與 trace builder 使用同一張 bounded node table。Operator node 的 epistemic conclusion 規則為：

- `observedTrue == true && observedFalse == false` → `holds`。
- `observedTrue == false && observedFalse == true` → `fails`。
- 兩者皆 true → `undetermined`。
- 兩者皆 false 是 internal invariant violation，因 compatible completion 集合不可能為空。

Atom node 的 trace conclusion 保留原始 atomic `TruthValue`，不以任一 completion value覆寫。Not node 若 mixed，必須保留 child 的完整 `UndeterminedReason` 與 payload。Binary mixed node 在 `UndeterminedReason` 原 enum declaration 新增：

```swift
case supervaluationInconclusive(atoms: [Proposition])
```

其 `atoms` 是從該 mixed subformula 的 undetermined children 可達、而且仍會隨 compatible completions 影響結論的 distinct atoms，依 canonical order 排列；已在 child 收斂為 tautology、contradiction 或 absorbing determinate truth 的內部 unknown 不列入上一層 aggregate，但完整 leaf trace 仍保留。此 aggregate reason 說明結論隨 compatible completions 改變；每個 atom 的精確 refusal reason 仍保存在 leaf，不以 aggregate 取代。Machine payload 保留完整 canonical atom 清單；所有人類可見的 error／debug rendering 必須先逐筆 `displaySafe`，再套用固定筆數與最終字數上限，不得 reflection raw proposition payload。

必須成立的反例：

- unknown `p`：`p ∨ ¬p` holds；`p ∧ ¬p` fails；`p → p` holds；`p NOR ¬p` fails。
- false `p`、unknown `q`：`p → q` holds；`p ∧ q` fails。
- true `p`、unknown `q`：`p → q` undetermined；`p ∨ q` holds。
- unknown `p,q`：`p → q` undetermined。

Evaluator 可以重用 atom result與 per-completion Bool buffers，但不得以 truth short-circuit 省略 syntax child。最大 work 上界是 4,096 nodes × 4,096 completions；trace 只保留 node observations與一棵 bounded tree，不保留每個 completion 的完整樹。

### Decision 7：trace 是 exact expression occurrence 的唯讀稽核樹

```swift
public struct SupervaluationSummary: Equatable {
    public let completionCount: Int
    public let observedTrue: Bool
    public let observedFalse: Bool
}

public struct EvidenceTrace: Equatable {
    public enum Kind: Equatable {
        case atom
        case not
        case and
        case or
        case implies
        case nor
    }

    public let context: ValuationContext
    public var expression: PropositionExpression { get }
    public var kind: Kind { get }
    public var conclusion: TruthValue { get }
    public var children: [EvidenceTrace] { get }
    public var atomicEvidence: AtomicEvidenceTrace? { get }
    public var completionSummary: SupervaluationSummary? { get }
}

extension AtomicEvidenceTrace {
    public var refusal: UndeterminedReason? { get }
}
```

Trace storage與 constructors 維持 private 或 module-only，public caller 不能把任意 conclusion 配到 children。Trace 維持 `Equatable` 而不新增 `Hashable`；其 equality 以 iterative node table 比較，不使用 recursive synthesized equality。每個 returned trace 必須同時滿足：

1. `Valuation.expression == Valuation.trace.expression`。
2. `Valuation.truth == Valuation.trace.conclusion`。
3. 每個 trace view 的 `context == Valuation.context`。
4. `kind` 與 `expression.kind` 一致。
5. children count與順序精確對應 expression children。
6. atom 的 `atomicEvidence` 非 nil、`completionSummary` nil、children 空；operator 相反。
7. atom leaf 原封不動保留 scope、projection、全部 evidence items、完整 snapshot quarantine與原始 `undetermined(reason)`。
8. operator `completionSummary.completionCount` 等於本次 root evaluation 實際列舉的 completion count；observed flags 機械決定 conclusion。
9. 重複 atom 只投射／求值一次，但每個 occurrence 各有 exact-expression leaf。

目前 unary-only 的 `trace.atomic`、root `scope`、root `projection`、root `evidence`、root `snapshotQuarantine` proxies 在 binary tree 無唯一意義，因此移除。呼叫端必須依 `children` 遍歷至 `atomicEvidence`。`operand` 可保留一版 deprecated read-only wrapper，只在 `kind == .not` 回傳 `children.first`；新測試與文件不得再依賴它。

Question 的 determinate no-answer 使用 initializer 已保留的 `not(subject)`，由 subject fails valuation 機械新增 not trace；不重投射 atoms、不重讀 store。Derived not node 的 completion observations由 child observations交換；atomic fails child視為唯一 false completion，因此新 not node觀察到 true。所有 context與 child trace identity 保持不變。

### Decision 8：NOR rewrite 是 bounded structural transformation

```swift
extension PropositionExpression {
    public func rewrittenUsingNor() throws -> Self
    public var isNorOnly: Bool { get }
}
```

Rewrite 先以 postorder 對每個 structural occurrence 計算輸出 depth／node count，並產生一份 bounded internal rewrite plan。depth 超過 64 時丟 `rewriteDepthLimitExceeded`，node count 超過 4,096 時丟 `rewriteNodeLimitExceeded`；兩項 preflight 都在建立任何局部輸出前完成。成功時依下列 deterministic identities 建立只含 atom／nor 的 tree，其中 `R(x)` 表示 child 已 rewrite；重複出現計為重複 structural occurrences：

- `R(atom) = atom`
- `R(not x) = nor(R(x), R(x))`
- `R(nor(x,y)) = nor(R(x), R(y))`
- `R(and(x,y)) = nor(nor(R(x),R(x)), nor(R(y),R(y)))`
- `R(or(x,y))`：令 `t = nor(R(x),R(y))`，結果為 `nor(t,t)`。
- `R(implies(x,y))`：令 `nx = nor(R(x),R(x))`、`u = nor(nx,R(y))`，結果為 `nor(u,u)`。

`isNorOnly` 對 atom 回 true；任何 not／and／or／implies 回 false；nor 只有在兩個 children 都為 NOR-only 時回 true。建立後以獨立 iterative verifier 比對 source occurrence、rewrite plan 與 materialized output 的 exact node tags／child order／atom identity，並驗證 `isNorOnly`。此 verifier 不列舉 truth rows，因此 13...63-atom expression 仍可 rewrite；可列舉的 tests 另以完整 truth tables 釘住每條 identity。Plan／output 不相符時丟 `rewriteVerificationFailed` 且不回傳 expression。Rewrite 不宣稱 canonical minimal form，也不改變原 expression。

Rewrite golden不只比較truth：以`N(x,y)`表示ordered `nor`，tests必須對`not(p)`、`and(p,q)`、`or(p,q)`、`implies(p,q)`、`nor(p,q)`逐一比較上述exact structural tree與canonical expression bytes；因此另一個語意等價但結構不同的NOR公式不符合v1 contract。Unary `not(p)`的full hex沿用Decision 5的`N(p,p)` golden。

### Decision 9：truth-table synthesis 使用 deterministic balanced DNF，再轉為 NOR 並自我驗證

```swift
extension PropositionExpression {
    public static func synthesizeUsingNor(
        _ table: BooleanFunctionTable
    ) throws -> PropositionExpression
}
```

Synthesis 只接受至少一個 atom。零元 table 丟 `zeroArityFunctionUnsupported`，不偷偷引入 constant case。演算法依 canonical rows ascending order處理：

1. 對每個 output 為 true 的 row，依 canonical atom order建立 literal；input true 使用 atom，false 使用 not(atom)。
2. 以 deterministic pairwise balanced and fold組成 minterm；奇數層最後一項原位晉級下一層。
3. 依 row order，以同一 balanced fold規則用 or 合併 minterms。
4. 全 false table 對每個 canonical atom `a` 建立 `and(a, not(a))`，再以 deterministic balanced or fold 合併所有 contradictions；全 true table 對每個 atom 建立 `or(a, not(a))`，再以 balanced and fold 合併所有 tautologies。兩條特例都必須讓 candidate syntactically reference table 的全部 atoms，使 exact canonical atom-array self-check 成立。
5. 在建立 DNF 前預算 intermediate depth／nodes，也預算依 Decision 8 rewrite 後的 depth／nodes；depth 超過 64 時丟 `synthesisDepthLimitExceeded`，nodes 超過 4,096 時丟 `synthesisNodeLimitExceeded`。在目前 0...12 arity 與 balanced construction 下，public input 的實際 depth 不會達 65；depth guard 仍作為未來演算法變更的 defensive invariant，只以 internal estimator test 與 code audit 驗證，不宣稱有當前 public failure fixture。
6. 建立 DNF、轉成 NOR-only expression。
7. 對 candidate 產生 classical table；由於 truth table 與 function table 使用不同 canonical domains，自我驗證比較 canonical atoms 與 canonical output vector，不比較跨型別 raw bytes。不相等丟 `synthesisVerificationFailed`，不得回傳未驗證公式。

固定structural synthesis goldens在rewrite前明列為：

- 三原子僅row 7為true：`and(and(p,q),r)`，釘住minterm的pairwise fold與奇數項晉級。
- 二原子OR vector `0111`：`or(or(and(not(p),q),and(p,not(q))),and(p,q))`，釘住ascending true-row order與三minterm的balanced OR fold。
- 三原子true rows `{1,3,6}`：`or(or(and(and(not(p),not(q)),r),and(and(not(p),q),r)),and(and(p,q),not(r)))`，同時釘住非對稱literal polarity、三literal minterm fold、multiple-row order與奇數minterm晉級。
- 二原子constant false `0000`：`or(and(p,not(p)),and(q,not(q)))`。
- 二原子constant true `1111`：`and(or(p,not(p)),or(q,not(q)))`。

Tests必須以獨立fixture逐一比較pre-rewrite plan component sequence，以及final expression與Decision 8套用在上述exact tree後的structural equality／canonical bytes；不得只比較truth vector、NOR-only或同process replay。這些goldens與unary`[true,false] -> N(p,p)`共同阻擋改用另一個正確但不同的DNF、fold或constant construction。

此 construction deterministic 但不保證最少 nodes。即使存在較小的另一個公式，只要這條固定 construction 超過 hard budget就拒絕；這是可預測資源上界換取非最佳化結果的明示 trade-off。全部 16 種二原子 Boolean functions 都必須在 budgets 內成功並得到 NOR-only expression。

### Decision 10：測試與 mutation evidence 是實作契約的一部分

新增四個固定 XCTest suites：

- `Tests/AkashicPropositionTests/ExpressionConstructionTests.swift`／`ExpressionConstructionTests`
- `Tests/AkashicPropositionTests/ClassicalSemanticsTests.swift`／`ClassicalSemanticsTests`
- `Tests/AkashicPropositionTests/SupervaluationTests.swift`／`SupervaluationTests`
- `Tests/AkashicPropositionTests/TruthFunctionSynthesisTests.swift`／`TruthFunctionSynthesisTests`

下表每一列都必須先在缺少 production behavior 時得到預期 RED，完成 GREEN 後暫時施加指定 mutation、確認列出的 locator 轉紅，再復原 mutation。Mutation evidence 要記錄被改的 production symbol、執行的 test locator與失敗 assertion；不能只寫「測試有抓到」。

| Test locator | GREEN contract | 必須抓到的 production mutation |
| --- | --- | --- |
| `ExpressionConstructionTests.testOpaqueFactoriesCoverEveryOperatorAndPreserveStructuralIdentity` | 六種 kind、arity、child order與 structural identity正確 | 將 double negation 化簡；交換 binary children |
| `ExpressionConstructionTests.testStructuralHashFeedIncludesAtomTableEveryNodeTagAndChildBoundary` | internal deterministic hash-component feed精確含canonical atom-table payload、每個node tag、child boundary與atom index；`atom(p)`／`atom(q)` feed不同；`hash(into:)`的code audit確認只消費此feed | 從feed移除atom payload、任一node tag或child boundary |
| `ExpressionConstructionTests.testExpressionBudgetsAcceptExactBoundaryAndRejectNextValue` | depth／node／atom exact maximum接受，next value typed拒絕 | 移除任一 check；將 `<=` 改為 `<` 或反向 off-by-one |
| `ExpressionConstructionTests.testReferenceByteBudgetsPrecedeSyntaxAndPinnedNormalization` | raw／normalized 4,096 bytes接受、4,097 typed拒絕；超長空白、unsupported scalar與U+0344 expansion優先序正確；capped NFC sink不發出第4,097 byte後內容 | 在trim／Foundation NFC／完整buffer／canonical `Data`之後才檢查；移除normalized cap；交換unsupported／overflow優先序 |
| `ExpressionConstructionTests.testUnicodeV1TrustChainAndOfficialConformanceArePinned` | 五份UCD inputs、generator、runtime normalizer source、generated table source與manifest各自符合獨立fixed SHA；官方NormalizationTest全量通過；pinned White_Space fixtures穩定；offline regeneration byte-identical；production static ban無平台normalization／whitespace API | 同改manifest與data但不升v1 domain；改generator／runtime／generated source；回用Foundation／CoreFoundation normalization或whitespace |
| `ExpressionConstructionTests.testExternalClientsCannotConstructRawExpressionStorageOrRaiseLimits` | 非 `@testable` swiftc probe無法 raw construct，也不存在 limit overload | 將 storage/case改 public；新增 caller limit參數 |
| `ClassicalSemanticsTests.testEveryBinaryOperatorHasCompleteFourRowMatrix` | and／or／implies／nor 的四列逐格符合 Decision 4 | 將任一 operator 實作複製成另一個；反轉任一 truth cell |
| `ClassicalSemanticsTests.testClassicalEvaluationRequiresCompleteBivalentAssignment` | missing atoms依 canonical order typed拒絕 | 將 missing value預設為 false |
| `ClassicalSemanticsTests.testClassicalValuationEntryListValidatesBeforeIndexing` | public initializer只收entry list；先count、再atom validation、bounded duplicate comparison，最後才建立lookup；duplicate以`duplicateValuationAtom`拒絕 | 改收raw dictionary；在validator前hash；讓duplicate採first／last wins |
| `ClassicalSemanticsTests.testClassicalValuationIgnoresExtraAssignmentsWithinFixedContainerLimit` | expression atoms 完整時，額外 assignments 可存在且不影響結果；第 64 個 assignment 拒絕 | 將額外 assignment 視為錯誤；讓額外值改變 expression 結果；移除 63-atom container guard |
| `ClassicalSemanticsTests.testTruthTableAtomAndRowOrderIsDeterministic` | atom／row順序與 bytes跨重播完全相同 | 使用 Dictionary/Set iteration；交換 bit significance |
| `ClassicalSemanticsTests.testCanonicalBytesNormalizeUnicodeEquivalentLiterals` | NFC／NFD-equal atom、expression 與 table bytes 完全相同 | 略過 NFC 正規化；直接編碼 raw UTF-8 |
| `ClassicalSemanticsTests.testCanonicalByteGoldenVectorsAndStructuralCollisionPairs` | atom／expression／truth table／function table對應exact v1 hex；六個expression node tags、non-symmetric child order、`nor(p,p)` rewrite／synthesis representative均有exact suffix或full hex；tag／length collision pairs全分離 | 刪除或重映射任一domain／predicate／reference／node tag、UInt64 length／count／row index；交換children；改寫rewrite／synthesis bytes |
| `ClassicalSemanticsTests.testCanonicalBytesReplayInFreshSubprocesses` | 兩個獨立 subprocess 輸出同一 exact hex，且 normalization conformance gate 全綠 | 使用 randomized `Hasher`、Dictionary／Set iteration 或 OS normalization |
| `ClassicalSemanticsTests.testFunctionTableCanonicalizesCallerBitOrderAndPermutesOutputs` | 1...12 atoms 依 caller bit order 解讀後轉成 canonical atoms 與 output vector；三原子 `[b,c,a]` 函數 `a` 從 `01010101` 轉成 `[a,b,c]` 的 `00001111` | 只排序 atoms 而未同步 permutation outputs；顛倒第一個 bit 的 significance |
| `ClassicalSemanticsTests.testFunctionTableRejectsOversizedArityBeforeElementWork` | 13 atoms即使同時含duplicate／malformed／overlong sentinel，仍先回row limit；injected shift closure與allocator probe皆為0 | 在`atoms.count` guard前做duplicate、validation、shift或allocation |
| `ClassicalSemanticsTests.testTwelveAtomsProduceFourThousandNinetySixRowsAndThirteenRejectBeforeShift` | 12 atoms接受並產生4,096 rows；13 atoms在shift／allocation前typed拒絕，internal checked-shift closure與workspace probe證明兩者均未呼叫 | 將row cap改成64；把guard移到shift closure後；接受13 atoms |
| `ClassicalSemanticsTests.testSixtyThreeAndSixtyFourAtomEnumerationFailsClosedBeforeShift` | 63-atom table與第64 atom都在shift前typed拒絕，checked-shift closure為0；static gate無其他裸shift | 將guard移到shift後；繞過shared helper；移除atom／row guard |
| `ClassicalSemanticsTests.testClassicalEquivalenceIsNotStructuralEquality` | AST identity與truth-condition equivalence分離 | 以 structural `==` 實作 equivalence |
| `ClassicalSemanticsTests.testClassicalLawsUseSemanticEquivalence` | double negation、implication identity、兩條 De Morgan皆等價 | 改錯 implication或任一 De Morgan operator |
| `SupervaluationTests.testUnknownExcludedMiddleHoldsAndUnknownContradictionFails` | unknown p 的 tautology／contradiction符合 supervaluation | 換成 strong Kleene rule |
| `SupervaluationTests.testImplicationAndMixedKnownUnknownFollowAllCompletions` | Decision 6 全部 mixed cases逐格成立 | 將 implication當成 `a || b`；移除 absorbing known value |
| `SupervaluationTests.testEverySubformulaProducesOrderedContextBoundTrace` | 每個 occurrence有 exact kind/expression/context/conclusion/children | 丟棄 child；反轉 children；覆寫 context或root conclusion |
| `SupervaluationTests.testDuplicateAtomsAreEvaluatedOnceButEveryOccurrenceIsTraced` | per-call internal observer 證明 distinct atom只評估一次，occurrence leaves仍完整 | 每個 leaf重投射；將兩個 occurrence折成一個 trace leaf |
| `SupervaluationTests.testCompletionLimitFailsClosedBeforeEnumeration` | 12個unknown atoms接受並列舉4,096 completions；第13個在shift／allocation前拒絕，internal checked-shift closure與workspace probe皆為0 | 移除preflight；把guard移到shift closure後；先配置completion array；將上限改成64 |
| `PropositionTests.testFormulaDiagnosticsBoundAutomaticRenderingWithoutTruncatingPayloads` | error／TruthValue 的 localized、describing、reflecting 限 5 筆／2,048 scalars 並消毒，machine payload 保持 63 atoms | 回復 synthesized reflection；先輸出 raw payload；只限 input 而不限 post-escape 總長 |
| `TruthFunctionSynthesisTests.testNorRewritePreservesEveryOperatorAndUsesOnlyNor` | 每種 operator rewrite都等價且NOR-only | 留下非NOR node；改錯任一 Decision 8 identity |
| `TruthFunctionSynthesisTests.testRewriteStructuralGoldensPinEveryOperator` | 五種operator逐一等於Decision 8 exact ordered NOR tree與canonical bytes | 換成另一個語意等價NOR identity；交換或分享duplicated child |
| `TruthFunctionSynthesisTests.testRewriteSelfCheckRejectsCorruptedPlan` | per-call internal fault injector破壞一個materialized node時回`rewriteVerificationFailed`且無結果 | 移除rewrite verifier；忽略fault；回傳corrupted tree |
| `TruthFunctionSynthesisTests.testZeroArityFunctionTableIsRepresentableButSynthesisRejectsIt` | 零元 table 接受恰好一個 output；synthesis 以 `zeroArityFunctionUnsupported` 拒絕 | 讓 initializer 拒絕合法零元 table；偷偷引入 constant expression；回傳其他 transformation error |
| `TruthFunctionSynthesisTests.testAllSixteenBinaryBooleanFunctionsSynthesizeToNor` | 16個 output masks全部成功、等價、NOR-only | 漏一個 mask；反轉 row bit order；改錯全真／全假 construction |
| `TruthFunctionSynthesisTests.testSynthesisStructuralGoldensPinMintermMultirowAndConstants` | 三原子single-minterm、三原子`{1,3,6}` non-symmetric multirow、二原子`0111` fold、`0000`／`1111` constants的pre-rewrite plan與final structural／bytegoldens完全相符 | 改fold association、true-row order、literal polarity、constant branch或換成另一個等價NOR structure |
| `TruthFunctionSynthesisTests.testRewriteAndSynthesisRespectFixedExpansionBudget` | Rewrite的4,095接受／4,097拒絕；synthesis以五原子true rows`{3,6,7,11,13,15}`產生4,095接受／`{1,2,3,4,7}`產生第一個可達界外計畫4,103拒絕，均以maximum 4,096的typed preflight處理且無部分結果 | 移除rewrite node／synthesis node guard；把`> maximum`改成錯誤比較 |
| `TruthFunctionSynthesisTests.testRewriteEstimatorRetainsDepthPreflight` | internal estimator對synthetic rewrite depth65回`rewriteDepthLimitExceeded`，不建立public forged expression | 移除rewrite depth guard；先materialize再檢查 |
| `TruthFunctionSynthesisTests.testSynthesisEstimatorRetainsDefensiveDepthPreflight` | internal estimator 對 synthetic depth 65 回 `synthesisDepthLimitExceeded`，不建立 public forged table或expression | 移除 defensive synthesis depth guard；先materialize再檢查 |
| `TruthFunctionSynthesisTests.testSynthesisSelfCheckRejectsMismatchedCandidate` | per-call internal fault injector翻轉一個candidate output時回`synthesisVerificationFailed`且無結果 | 移除semantic verifier；忽略fault；回傳mismatched expression |
| `TruthFunctionSynthesisTests.testSynthesisAndTruthTableCanonicalBytesReplayExactly` | 重複 table／synthesis bytes完全相同 | 改用不穩定 iteration或未固定的 serializer |

## Implementation Contract

### Production file ownership

- `Sources/AkashicProposition/Expression.swift`：`PropositionLogicLimits`、opaque `PropositionExpression`、cached metrics、factories、expression errors、`Proposition.asExpression()` 與 deprecated safe wrappers。
- `Sources/AkashicProposition/Proposition.swift`、新增runtime `UnicodeNormalizationV1.swift`、generated `Sources/AkashicProposition/Generated/UnicodeNormalizationTablesV1.swift`、`Vendor/Unicode/15.1.0/`五份固定UCD inputs、`unicode-normalization-v1.manifest.json`與可離線重現的table generator：raw／normalized reference byte preflight、pinned White_Space syntax、Unicode 15.1.0 assigned-scalar gate、capped streaming NFC、編譯進module的tables／完整SHA-256 trust chain與新`PropositionError`cases。`Package.swift`只在generator或generated source整合必要時做最小調整，production不從network或外部檔案載入table。
- `Sources/AkashicProposition/ClassicalSemantics.swift`：`ClassicalValuation`、`ClassicalTruthTable`、`BooleanFunctionTable`、canonical atom／row／byte encoding、classical evaluation、truth table與equivalence APIs。
- `Sources/AkashicProposition/TruthFunctionSynthesis.swift`：NOR-only inspection、bounded rewrite、balanced DNF synthesis、self-verification與transformation errors。
- `Sources/AkashicProposition/Projection.swift`：atomic semantics保持原狀；擴充 `UndeterminedReason`、`EvidenceTrace`、`SupervaluationSummary`、`Valuation` 與 `PropositionExpression.evaluate(in:)`。
- `Sources/AkashicProposition/Question.swift`：question construction預留 negated subject；no-answer從既有 subject valuation導出，不重評 atoms。
- `Sources/AkashicCore/Models.swift`：`displaySafe` 改為 bounded reserve／iteration，不先全量計算 caller-controlled scalar count。
- 不新增 `Formula`、`Negation.swift` 第二套 AST 或接受 caller limit 的 `TruthFunction.swift` API。

### Required construction and failure order

1. Shared proposition validator 對每個 argument 先做 raw UTF-8 early-exit cap，再以既有 key grammar／pinned White_Space做 syntax validation，接著依 source order做pinned assigned-scalar scan，最後以capped streaming NFC sink做normalized cap；unsupported scalar先於後續normalized overflow。Atom factory呼叫此validator，失敗原樣傳遞`PropositionError`。
2. Unary／binary factory以已驗證 child metrics依序檢查 depth、node count、distinct atoms；全部通過後才建立 storage。
3. Classical valuation只接受entry list；先檢查array count，再驗證atoms，以bounded comparison拒絕duplicate，最後才建立library-owned lookup index。Public API不接受raw-`Proposition` dictionary。
4. Function table 先以 `atoms.count` 檢查 0...12 arity；13+ 立即回 `rowLimitExceeded`。合法 arity 才依序做 atom validity、bounded duplicate comparison、output count，再同步 canonicalize atoms 與 permute outputs；零元 table 只接受一個 output。
5. `truthTable()` 與 equivalence先以 canonical atom count判斷最多12個列舉 variables，再計算 row count。
6. Context-bound evaluation先求值最多63個 distinct atoms；知道 exact unknown count後，在任何 completion shift／allocation前套用12-variable cap。
7. Rewrite／synthesis先計算 capped output metrics，再建立 expression；超界不得回傳或保留部分 tree。

### Traversal and storage rules

- Expression construction、expression equality／hashing、classical evaluation、supervaluation、trace build、rewrite preflight與trace equality均使用 bounded iterative traversal或以64-depth已驗證 recursion；production採 iterative node tables，避免未來 budget調整時重新引入 stack dependency。
- Node tables長度不得超過4,096；stable preorder ID與postorder index必須由同一 traversal建立。
- Atomic evaluation cache key只取自opaque expression內已驗證的canonical atoms；raw public `Proposition`在shared validator完成前不得進入library-owned hashing或lookup。Cache value包含完整atomic valuation與evidence trace payload。
- Supervaluation的 per-completion workspace是固定長度 Bool array與每node兩個observation bits；不得累積 `completionCount × nodeCount` 棵 trace。
- Public value types的 constructors要封閉，使 `Valuation.truth`、trace conclusion與expression identity只能由 evaluator機械建立。
- Truth-table、function-table與completion的`2^n` cardinality計算全部經過單一module-internal `checkedPowerOfTwoCount(variableCount:maximum:shift:)`；helper先做variable guard，通過後才呼叫注入的shift closure，production使用checked shift，tests以會計數／trap的closure證明13／63-variable拒絕時shift完全未執行。另由module-internal、per-call `EnumerationWorkspaceProbe`證明guard失敗時workspace allocator未被呼叫。兩種seam都不得是global mutable state，且static code gate只禁止cardinality計算繞過helper的裸shift；guard成功後解碼已界定row index之assignment bits仍可使用checked bit operations。
- Atomic evaluator 使用 module-internal、per-call observer 記錄真正的 projection／evaluation 次數；public path 使用 no-op observer，tests 以它證明 duplicate occurrences 只求值一次。
- Expression storage提供module-internal deterministic `structuralHashFeed`組件序列；feed先完整納入canonical atom-table length／bytes，再納入每個node tag、child boundary與atom index，`hash(into:)`只依序消費此feed。Tests驗證移除atom payload、node tag或child boundary都會轉紅；code audit驗證沒有第二條hash路徑，不主張unequal values的raw `hashValue`必然不同。
- Rewrite-plan verifier與synthesis semantic verifier各接受module-internal、per-call fault injector，public path固定no-op；tests可只破壞一個planned/materialized node或一個candidate output並釘`rewriteVerificationFailed`／`synthesisVerificationFailed`。Seam不得公開或使用global mutable state。

### Required regression preservation

- #205：malformed keys／empty literals仍在 projection、atomic evaluation、question與adjudication boundary以原始 typed error拒絕；expression factory成為新增的最早拒絕點。
- #212：每個 valuation／trace保留同一 immutable snapshot ID、revision與valid day，不提供 context-free evaluation overload。
- #213：not交換 holds/fails、完整保留每種 undetermined reason；question no-answer與negative fact保留完整operand trace；`Stance.denied`仍不等於asserted negation。
- Existing atomic authored／affiliated projection、evidence、completeness與temporal tests不得因formula evaluator重構而改變結果。

### Verification gates

完成條件同時包含：

1. 四個新增 suites 全綠。
2. `Tests/AkashicPropositionTests/NegationTests.swift`、`AuthorshipCompletenessPropositionTests.swift`、`ContextValuationTests.swift`、`PropositionTests.swift` 完成 API 遷移並全綠。
3. 每一個 Decision 10 mutation至少實際執行一次，指定 locator確實轉紅並在復原後轉綠。
4. 完整 Swift test suite全綠。
5. `swift build -Xswiftc -warnings-as-errors` 全綠。
6. #214 proposal、兩份 delta specs、design與tasks通過 strict Spectra validation後，#216 才能引用 production symbol與test locator作為 landed evidence。

## Risks / Trade-offs

- **來源相容性破壞**：raw enum cases、非 throwing `.expression` 與 ambiguous trace proxies會消失。這是讓所有 expression 永遠 bounded／validated 的必要代價；deprecated safe wrappers與一版 `operand` view降低安全呼叫端的遷移成本。
- **指數運算仍存在**：supervaluation與truth tables本質為指數。單棵 4,096-node expression 乘 4,096 completions／rows約為1,678萬次簡單 node evaluations；equivalence 同時比較兩棵滿界樹，最壞約3,355萬次。Atomic snapshot projection 成本另依 model 大小，不包在此數字；超界不嘗試近似或猜測。
- **Trace tree增加記憶體**：binary formula最多保留4,096個trace nodes，但不保留逐completion trees。Atomic evidence在重複occurrences中以value semantics呈現；private storage可以共享不可變payload，public觀察仍是一leaf一occurrence。
- **Synthesis不是最佳化器**：balanced DNF可重現、可稽核，但可能拒絕一張其實存在較小NOR公式的table。固定construction與typed budget failure優先於不可預測的搜尋。
- **Canonical bytes成為長期契約**：一旦對外公開就不能無版本修改。Domain與version framing讓未來格式演進能新增版本而不把不同bytes誤認為同一格式。
- **Supervaluation與既有直覺不同**：unknown tautology可以holds、unknown contradiction可以fails。這是「所有相容completion均成立／均不成立」的明示 epistemic contract，不是把unknown當第三個truth-functional truth value。
- **Question可拒絕合法極限subject**：用滿expression depth／nodes的subject不能再包一層not，因此不適合作yes-no question。Initializer提前拒絕比在產生no-answer時失敗安全。
- **Unicode canonical equality 需要固定正規化**：Swift-equal 的 NFC／NFD spelling 若直接編碼 raw UTF-8 會產生不同 bytes。v1 檢入 Unicode 15.1.0 tables 並拒絕該版本未指派 scalar；支援新 scalar 需要新 canonical domain／manifest 與 migration，不會無聲改變 v1 bytes。

## Migration Plan

1. 依序封存 #205、#212、#213，確認 post-archive canonical specs包含 canonical input、snapshot context與evidenced negation完整契約；再建立 #214 change artifacts。
2. 先加入 `ExpressionConstructionTests` RED cases與external non-`@testable` swiftc probes；之後將 `Expression.swift` 改成opaque storage並加入limits/errors/factories。
3. 遷移 production callers：`Projection.swift` 不再pattern-match public raw cases；`Question.swift` 以throwing factory保留negated subject；`Proposition.evaluate(in:)` 改呼叫 `try asExpression()`。
4. 遷移 tests與下游source：`p.expression` 改為 `try p.asExpression()`；`.atom(p)`／`.not(e)` 改為throwing factories；case matching改讀 `kind`／`proposition`／`children`。
5. 將原本靠raw cases製造65層、4,096層或malformed expression的測試改成exact factory boundaries與external compile probes。Malformed atomic boundary仍可直接建立raw `Proposition`，但必須驗證 `asExpression()`在形成expression前丟原始錯誤。
6. 加入 classical types與tests，完成canonical ordering、guard-before-shift、truth tables與semantic equivalence。
7. 擴充trace storage與partial evaluator，先使supervaluation／trace tests全綠，再遷移現有 `trace.atomic`／`scope`／`projection`／`evidence` callers為leaf traversal。
8. 加入NOR rewrite與synthesis，逐一驗證全部16種二元函數、expansion budgets與canonical replay。
9. 依Decision 10執行並記錄每個mutation probe，復原後跑完整tests、warnings-as-errors與strict Spectra validation。
10. 只移植PR #210可重用的classical matrix／equivalence／NOR測試意圖；不merge其`Formula`宣告、strong-Kleene evaluator、caller limit或未檢查shift。完成後把固定production symbols與test locators交給#216 corpus disposition。

受來源破壞影響的現有檔案清單固定為：

- `Sources/AkashicProposition/Expression.swift`
- `Sources/AkashicProposition/Projection.swift`
- `Sources/AkashicProposition/Question.swift`
- `Tests/AkashicPropositionTests/NegationTests.swift`
- `Tests/AkashicPropositionTests/AuthorshipCompletenessPropositionTests.swift`
- `Tests/AkashicPropositionTests/ContextValuationTests.swift`
- `Tests/AkashicPropositionTests/PropositionTests.swift`

## Open Questions

截至本設計定稿沒有未決語意或API問題。容易造成後續分歧的四項邊界已固定如下：

- `BooleanFunctionTable` initializer 接受 0...12 atoms；零元形式只可表示一列 constant output，且 `synthesizeUsingNor` 以 `zeroArityFunctionUnsupported` 拒絕。本 change 不新增 constant expression case。
- `canonicalBytes` 是public、versioned interoperability surface，不只作為test helper。
- Binary mixed conclusion使用canonical undetermined atom清單作aggregate reason；每個精確atomic refusal只存在leaf，避免遞迴reason payload與重複資料。
- #214只保留一個`PropositionExpression`；任何導入第二套`Formula`或caller-adjustable budgets的整合都視為違反本設計，而非相容替代方案。
