## ADDED Requirements

### Requirement: Classical evaluation uses a complete bivalent assignment

The library SHALL expose `ClassicalValuation` as a store-independent assignment from validated, structurally distinct atoms to `Bool`. Its public throwing initializer SHALL accept an entry list `[(atom: Proposition, value: Bool)]`, not a raw-`Proposition` dictionary. It SHALL inspect entry count first, SHALL reject more than 63 entries with `ClassicalSemanticsError.valuationAtomLimitExceeded(actual:maximum:)`, SHALL then validate each atom before any library-owned hashing or indexing, and SHALL reject a repeated validated atom with `ClassicalSemanticsError.duplicateValuationAtom(Proposition)` rather than choosing the first or last value. Malformed atomic syntax SHALL propagate its original `PropositionError`. A valuation used for an expression SHALL contain one value for every structurally distinct atom in that expression. It SHALL also be permitted to contain unrelated validated assignments, which classical evaluation SHALL ignore. `PropositionExpression.classicalValue(under:)` SHALL return one `Bool`, SHALL evaluate every connective compositionally, and SHALL reject missing assignments with `ClassicalSemanticsError.incompleteValuation(missing:)` before evaluating any connective. The missing payload SHALL use canonical atom order.

Classical evaluation SHALL use these connective definitions for Boolean values `p` and `q`:

| Expression | Result |
| --- | --- |
| `not(p)` | `!p` |
| `and(p, q)` | `p && q` |
| `or(p, q)` | `p || q` |
| `implies(p, q)` | `!p || q` |
| `nor(p, q)` | `!(p || q)` |

Classical evaluation SHALL NOT consult `PropositionStore`, `EvidenceTrace`, epistemic state, provenance, confidence, or partial-information projection.

#### Scenario: A complete assignment evaluates a compound expression

- **GIVEN** distinct atoms `p` and `q`
- **AND** the expression `and(p, not(q))`
- **AND** a `ClassicalValuation` containing `p = true` and `q = false`
- **WHEN** `classicalValue(under:)` evaluates the expression
- **THEN** it returns `true`
- **AND** the result is independent of every `PropositionStore`

##### Example:

| `p` | `q` | `and(p, not(q))` |
| --- | --- | --- |
| `true` | `false` | `true` |

#### Scenario: Missing assignments fail closed

- **GIVEN** the expression `and(p, q)`
- **AND** a valuation containing `p = true` but no value for `q`
- **WHEN** the valuation is validated or used for classical evaluation
- **THEN** the operation returns `ClassicalSemanticsError.incompleteValuation(missing: [q])`
- **AND** no partial result is returned

#### Scenario: Extra assignments are ignored

- **GIVEN** the expression `and(p, q)`
- **AND** a valuation containing values for `p`, `q`, and unrelated atom `r`
- **WHEN** the valuation is used for classical evaluation
- **THEN** the result depends only on the values of `p` and `q`
- **AND** changing only the value of `r` does not change the result

#### Scenario: The valuation container has a fixed atom bound

- **GIVEN** 63 validated, structurally distinct atom assignments
- **WHEN** `ClassicalValuation` is initialized
- **THEN** initialization succeeds
- **GIVEN** 64 validated, structurally distinct atom assignments
- **WHEN** `ClassicalValuation` is initialized
- **THEN** it returns `ClassicalSemanticsError.valuationAtomLimitExceeded(actual: 64, maximum: 63)`
- **AND** it constructs no valuation

#### Scenario: Valuation entries are validated before indexing

- **GIVEN** a public entry list containing a malformed raw atom
- **WHEN** `ClassicalValuation` is initialized
- **THEN** the original `PropositionError` is returned before library-owned hashing or lookup indexing
- **GIVEN** an in-bound entry list repeats one validated atom with two values
- **WHEN** `ClassicalValuation` is initialized
- **THEN** it returns `ClassicalSemanticsError.duplicateValuationAtom` and constructs no valuation
- **AND** no public initializer accepts `[Proposition: Bool]`

#### Scenario: Every supported connective is evaluated compositionally

- **GIVEN** any complete classical valuation for the atoms in an expression built from `atom`, `not`, `and`, `or`, `implies`, and `nor`
- **WHEN** `classicalValue(under:)` evaluates the expression
- **THEN** each node uses only the Boolean results of its immediate children and the connective definition in this requirement
- **AND** the final value equals direct Boolean substitution

### Requirement: Binary connectives have complete four-row matrices

`PropositionExpression.truthTable()` SHALL enumerate the complete truth matrix for every expression within the fixed classical limits. For two distinct ordered atoms `p` and `q`, the four rows SHALL occur in the order `(false, false)`, `(false, true)`, `(true, false)`, `(true, true)`. The matrices for `and`, `or`, `implies`, and `nor` SHALL exactly match the following table.

| Row | `p` | `q` | `and(p, q)` | `or(p, q)` | `implies(p, q)` | `nor(p, q)` |
| ---: | --- | --- | --- | --- | --- | --- |
| 0 | `false` | `false` | `false` | `false` | `true` | `true` |
| 1 | `false` | `true` | `false` | `true` | `true` | `false` |
| 2 | `true` | `false` | `false` | `true` | `false` | `false` |
| 3 | `true` | `true` | `true` | `true` | `true` | `false` |

#### Scenario: Conjunction has all four rows

- **GIVEN** distinct atoms `p` and `q` with `p` ordered before `q`
- **WHEN** `truthTable()` evaluates `and(p, q)`
- **THEN** the ordered result vector is `[false, false, false, true]`
- **AND** every complete assignment appears exactly once

#### Scenario: Disjunction has all four rows

- **GIVEN** distinct atoms `p` and `q` with `p` ordered before `q`
- **WHEN** `truthTable()` evaluates `or(p, q)`
- **THEN** the ordered result vector is `[false, true, true, true]`
- **AND** every complete assignment appears exactly once

#### Scenario: Material implication has all four rows

- **GIVEN** distinct atoms `p` and `q` with `p` ordered before `q`
- **WHEN** `truthTable()` evaluates `implies(p, q)`
- **THEN** the ordered result vector is `[true, true, false, true]`
- **AND** the `p = true, q = false` row is the only false row

#### Scenario: Joint denial has all four rows

- **GIVEN** distinct atoms `p` and `q` with `p` ordered before `q`
- **WHEN** `truthTable()` evaluates `nor(p, q)`
- **THEN** the ordered result vector is `[true, false, false, false]`
- **AND** the `p = false, q = false` row is the only true row

### Requirement: Atom order, row order, and canonical bytes are deterministic

Every atom SHALL have injective canonical bytes derived from its complete logical structural identity. Literal normalization and empty-literal syntax SHALL use repository-bundled Unicode 15.1.0 normalization, assigned-scalar, and White_Space data; they SHALL NOT call an operating-system, Foundation, CoreFoundation, or toolchain normalization or whitespace table. The checked-in trust chain SHALL contain official `UnicodeData.txt`, `CompositionExclusions.txt`, `DerivedNormalizationProps.txt`, `PropList.txt`, and `NormalizationTest.txt`; a manifest SHALL pin the SHA-256 of every input, the generator source, the production runtime-normalizer source, the generated Swift table source, the Unicode and manifest schema versions, and all four v1 canonical domains. Independently fixed digests, offline byte-identical regeneration, the complete official normalization conformance corpus, pinned White_Space fixtures, and a static source ban on platform normalization or whitespace APIs SHALL be verification gates. Changing any manifest, input, generator, runtime, or generated-source byte without changing the v1 canonical domain SHALL fail verification.

A literal containing a scalar unassigned in that pinned version SHALL fail with `PropositionError.unsupportedUnicodeScalar(value:normalizationVersion:)`. After the raw byte cap and pinned syntax validation, assigned scalars SHALL be checked in source order; only then SHALL a capped streaming NFC sink encode UTF-8 and stop when it observes byte 4097 rather than materialize a complete oversized normalized buffer. An unsupported scalar SHALL take precedence over a normalized overflow later in the same input. Every admitted string payload SHALL therefore be Unicode Normalization Form C UTF-8. Canonically equivalent Swift strings within the admitted scalar set, including NFC and NFD spellings of the same text, SHALL produce identical canonical bytes. Canonical atom bytes SHALL use the following encoding, with no locale-sensitive transformation beyond this specified pinned normalization:

1. An unsigned 64-bit big-endian length followed by the UTF-8 bytes of the domain `akashic-proposition-atom-v1`.
2. A one-byte predicate tag: `0x00` for `authored` and `0x01` for `affiliated`.
3. Each predicate argument in declaration order, encoded as a one-byte reference tag, then an unsigned 64-bit big-endian payload length, then its NFC-normalized UTF-8 payload bytes. The reference tag SHALL be `0x00` for a key reference and `0x01` for a literal reference.

The canonical atom order SHALL be unsigned lexicographic order of canonical atom bytes. A `ClassicalTruthTable` with `n` atoms SHALL contain exactly `2^n` rows. Row index SHALL increase from zero through `2^n - 1`; the first ordered atom SHALL be the most-significant assignment bit and the last ordered atom SHALL be the least-significant assignment bit. `false` SHALL encode as bit zero and `true` SHALL encode as bit one.

Canonical expression bytes SHALL use an unsigned 64-bit big-endian length followed by the UTF-8 domain `akashic-proposition-expression-v1`, followed by an unsigned 64-bit big-endian distinct-atom count and every canonical-order atom as an unsigned 64-bit byte length plus canonical atom bytes. The atom table SHALL be followed by an unsigned 64-bit big-endian node count and a prefix encoding of the expression. Node tags SHALL be `0x00` for `atom`, `0x01` for `not`, `0x02` for `and`, `0x03` for `or`, `0x04` for `implies`, and `0x05` for `nor`. An atom node SHALL contain an unsigned 64-bit big-endian index into the preceding atom table. A unary node SHALL contain its child encoding. A binary node SHALL contain the left child followed by the right child without reordering. The encoding SHALL NOT duplicate full atom bytes per syntax occurrence.

Canonical truth-table bytes SHALL use this exact sequence:

1. An unsigned 64-bit big-endian length followed by the UTF-8 domain `akashic-classical-truth-table-v1`.
2. An unsigned 64-bit big-endian atom count.
3. For every ordered atom, an unsigned 64-bit big-endian byte count followed by its canonical atom bytes.
4. An unsigned 64-bit big-endian row count.
5. For every ordered row, its unsigned 64-bit big-endian row index followed by one result byte, `0x00` for false or `0x01` for true.

Canonical encodings SHALL NOT depend on Swift `Hashable` seeds, dictionary iteration, process identity, toolchain identity, memory addresses, JSON encoders, YAML emitters, whitespace, operating-system locale, or operating-system Unicode data. The bundled normalization manifest and the four encoding domains SHALL version every normalization or framing change.

#### Scenario: Atom order is stable across insertion order

- **GIVEN** structurally identical expressions constructed in processes that discover atoms in different orders
- **WHEN** each process constructs a truth table
- **THEN** both tables sort atoms by unsigned lexicographic canonical bytes
- **AND** both tables expose identical ordered atoms, rows, results, and canonical truth-table bytes

#### Scenario: Two-atom row order treats the first atom as most significant

- **GIVEN** ordered atoms `[p, q]`
- **WHEN** row indices zero through three are decoded
- **THEN** row zero is `p = false, q = false`
- **AND** row one is `p = false, q = true`
- **AND** row two is `p = true, q = false`
- **AND** row three is `p = true, q = true`

##### Example:

| Index | Binary index | `p` | `q` |
| ---: | ---: | --- | --- |
| 0 | `00` | `false` | `false` |
| 1 | `01` | `false` | `true` |
| 2 | `10` | `true` | `false` |
| 3 | `11` | `true` | `true` |

#### Scenario: Structural identity is preserved in canonical expression bytes

- **GIVEN** expressions `or(p, q)` and `or(q, p)` built from the same two distinct atoms
- **WHEN** canonical expression bytes are produced
- **THEN** the two byte sequences differ because left and right child order is preserved
- **AND** repeated encoding of either expression produces the same byte sequence

#### Scenario: Canonically equivalent Unicode spellings have identical bytes

- **GIVEN** one atom whose literal uses an NFC spelling
- **AND** a Swift-equal atom whose literal uses the canonically equivalent NFD spelling
- **WHEN** canonical atom bytes, canonical expression bytes, and classical truth tables are produced independently
- **THEN** the corresponding canonical atom byte sequences are identical
- **AND** the corresponding canonical expression byte sequences are identical
- **AND** the corresponding canonical truth-table byte sequences are identical

#### Scenario: The pinned normalization manifest governs admitted scalars

- **GIVEN** the five checked-in official Unicode 15.1.0 inputs, generator source, production runtime-normalizer source, generated table source, and trust-chain manifest
- **WHEN** their independently fixed SHA-256 values and offline regeneration are verified
- **THEN** every input, generator, generated output, and manifest digest SHALL match
- **AND** all official `NormalizationTest.txt` cases and pinned `PropList.txt` White_Space fixtures SHALL pass
- **AND** a production source gate SHALL reject Foundation or CoreFoundation normalization and whitespace APIs in the canonicalization path
- **AND** a scalar marked unassigned in the manifest SHALL return `PropositionError.unsupportedUnicodeScalar(value:normalizationVersion:)`
- **AND** changing any trust-chain byte while retaining a v1 canonical domain SHALL fail verification

#### Scenario: Unsupported scalars precede later normalized overflow

- **GIVEN** a raw-cap-compliant literal containing an unsupported Unicode 15.1.0 scalar before a suffix whose NFC UTF-8 would exceed 4096 bytes
- **WHEN** logical reference validation runs
- **THEN** it returns `PropositionError.unsupportedUnicodeScalar(value:normalizationVersion:)`
- **AND** it does not emit a complete normalized buffer

#### Scenario: Four canonical surfaces match exact golden bytes

- **GIVEN** `p = authored(person: key("p"), work: key("w"))`
- **AND** `e = not(p)`
- **AND** `t = try e.truthTable()`
- **AND** `f = BooleanFunctionTable(atomsInInputBitOrder: [p], outputsInInputBitRowOrder: [true, false])`
- **WHEN** canonical bytes for `p`, `e`, `t`, and `f` are encoded
- **THEN** the atom hex SHALL equal `000000000000001b616b61736869632d70726f706f736974696f6e2d61746f6d2d7631000000000000000000017000000000000000000177`
- **AND** the expression hex SHALL equal `0000000000000021616b61736869632d70726f706f736974696f6e2d65787072657373696f6e2d763100000000000000010000000000000038000000000000001b616b61736869632d70726f706f736974696f6e2d61746f6d2d7631000000000000000000017000000000000000000177000000000000000201000000000000000000`
- **AND** the classical truth-table hex SHALL equal `0000000000000020616b61736869632d636c6173736963616c2d74727574682d7461626c652d763100000000000000010000000000000038000000000000001b616b61736869632d70726f706f736974696f6e2d61746f6d2d76310000000000000000000170000000000000000001770000000000000002000000000000000001000000000000000100`
- **AND** the Boolean-function-table hex SHALL equal `0000000000000021616b61736869632d626f6f6c65616e2d66756e6374696f6e2d7461626c652d763100000000000000010000000000000038000000000000001b616b61736869632d70726f706f736974696f6e2d61746f6d2d76310000000000000000000170000000000000000001770000000000000002000000000000000001000000000000000100`
- **AND** the two table byte sequences SHALL differ because their domains differ

#### Scenario: Tags and lengths prevent structural concatenation collisions

- **GIVEN** atom pairs that differ only as key versus literal, authored versus affiliated, or payload splits `("ab", "c")` versus `("a", "bc")`
- **WHEN** canonical atom bytes are encoded
- **THEN** every pair SHALL produce different byte sequences
- **AND** removing a predicate tag, reference tag, or UInt64 length SHALL break at least one golden or collision fixture

#### Scenario: Every expression node tag and child position is pinned

- **GIVEN** canonical atom table `[p, q]` and UInt64 atom indices zero and one
- **WHEN** the prefix node payload after the shared expression header, atom table, and node count is encoded
- **THEN** `atom(p)` has exact payload hex `000000000000000000`
- **AND** `not(p)` has exact payload hex `01000000000000000000`
- **AND** `and(p,q)` has exact payload hex `02000000000000000000000000000000000001`
- **AND** `or(p,q)` has exact payload hex `03000000000000000000000000000000000001`
- **AND** `implies(p,q)` has exact payload hex `04000000000000000000000000000000000001`
- **AND** `nor(p,q)` has exact payload hex `05000000000000000000000000000000000001`
- **AND** `and(not(q),p)` has exact payload hex `0201000000000000000001000000000000000000`

#### Scenario: Rewrite and synthesis share an exact NOR representative

- **GIVEN** `p = authored(person: key("p"), work: key("w"))`
- **WHEN** `not(p)` is rewritten and the one-atom function vector `[true, false]` is synthesized
- **THEN** both results are structurally `nor(p,p)`
- **AND** both canonical expression hex values equal `0000000000000021616b61736869632d70726f706f736974696f6e2d65787072657373696f6e2d763100000000000000010000000000000038000000000000001b616b61736869632d70726f706f736974696f6e2d61746f6d2d7631000000000000000000017000000000000000000177000000000000000305000000000000000000000000000000000000`

#### Scenario: Canonical truth-table bytes are reproducible

- **GIVEN** the same structurally identified atoms and ordered result vector on two supported platforms
- **WHEN** each platform serializes a `ClassicalTruthTable`
- **THEN** the complete byte sequences are identical
- **AND** interpreting either sequence according to this versioned layout yields the same atom order, row order, and result vector

### Requirement: Classical enumeration and expansion use fixed hard bounds

`PropositionLogicLimits` SHALL expose immutable public constants with these values:

| Limit | Value |
| --- | ---: |
| `maximumReferenceUTF8ByteCount` | 4096 |
| `maximumOperatorDepth` | 64 |
| `maximumNodeCount` | 4096 |
| `maximumDistinctAtomCount` | 63 |
| `maximumClassicalRows` | 4096 |
| `maximumSupervaluationCompletions` | 4096 |
| `maximumRewriteNodeCount` | 4096 |
| `maximumSynthesisNodeCount` | 4096 |

`maximumClassicalRows` SHALL derive an enumeration threshold of 12 distinct atoms because `2^12 = 4096`; it SHALL NOT reduce the 63-atom expression-construction bound. NOR rewriting and NOR synthesis SHALL enforce `maximumRewriteNodeCount` and `maximumSynthesisNodeCount` respectively as independent 4096-node output bounds. No public initializer or operation SHALL accept caller-supplied replacements for any limit.

Every library-owned logical operation SHALL check each key or literal with an early-exit raw UTF-8 counter before syntax validation, trimming, normalization, library-owned hashing, or canonical allocation. The first observed byte beyond 4096 SHALL throw `PropositionError.referenceUTF8ByteCountExceeded(stage: .rawUTF8, minimumObserved: 4097, maximum: 4096)`. After syntax validation with the pinned White_Space table, a source-order assigned-scalar scan SHALL reject the first unsupported scalar; a capped streaming pinned-NFC sink SHALL then emit UTF-8 only through the first observed byte beyond the bound. It SHALL stop at byte 4097 and throw the same case with stage `.normalizedUTF8` without constructing the rest of an oversized normalized buffer. Syntax error SHALL precede unsupported-scalar error, which SHALL precede normalized overflow. An overlong whitespace-only literal SHALL therefore report the raw resource error before `emptyLiteral`. Every accepted atom SHALL have bounded canonical bytes, and the canonical expression atom-table encoding SHALL give every 4096-node expression a derived finite byte bound.

`PropositionExpression.atom(_:)`, `not(_:)`, `and(_:_:)`, `or(_:_:)`, `implies(_:_:)`, and `nor(_:_:)` SHALL be the primary public throwing factories. Every factory SHALL preflight its candidate depth, node count, and distinct atom count against the fixed constants before exposing a value.

Expression construction, truth-table enumeration, equivalence checks, NOR rewriting, and synthesis SHALL preflight every relevant count with checked or saturating arithmetic before shifting, allocating output storage, constructing a rejected node, or emitting a partial result. Expression resource-limit failures SHALL use `PropositionExpressionError`, while malformed atom validation SHALL propagate its original `PropositionError`; classical row failures SHALL use `ClassicalSemanticsError`; rewrite and synthesis failures SHALL use `PropositionTransformationError`. A rewrite whose planned output depth exceeds 64 SHALL return `PropositionTransformationError.rewriteDepthLimitExceeded(minimumRequired:maximum:)`; synthesis whose planned output depth exceeds 64 SHALL return `PropositionTransformationError.synthesisDepthLimitExceeded(minimumRequired:maximum:)`. A count whose exact value cannot be represented SHALL saturate to the applicable maximum plus one for the error payload. The implementation SHALL NOT wrap, trap, truncate to an accepted count, or continue after a failed preflight.

Every truth-table, function-table, and supervaluation `2^n` cardinality calculation SHALL use one guarded internal helper that checks the variable limit before invoking its checked-shift operation. Verification SHALL inject a counting or trapping shift operation and SHALL prove that rejected 13- and 63-variable requests invoke it zero times; a static source gate SHALL reject another cardinality shift outside that helper. Checked bit operations that decode an already bounded row index after this guard are permitted. Allocation-only observation SHALL NOT be treated as proof that the cardinality shift did not occur.

Truth-table row count SHALL be computed only after verifying that the atom count is at most 12. The implementation SHALL reject larger atom sets with `ClassicalSemanticsError.rowLimitExceeded(atomCount:maximumRows:)` before executing any expression equivalent to `1 << atomCount`. Rewrite and synthesis estimates SHALL use checked or saturating addition and multiplication.

#### Scenario: Exact expression boundaries are accepted

- **GIVEN** a valid expression whose maximum root-to-leaf operator depth is exactly 64
- **AND** whose total node count is exactly 4096
- **WHEN** the expression is constructed through opaque factories
- **THEN** construction succeeds
- **AND** the stored operator depth and node count remain 64 and 4096

#### Scenario: The next expression values are rejected

- **GIVEN** an attempted expression with operator depth 65 or total node count 4097
- **WHEN** an opaque factory preflights the new node
- **THEN** it returns `PropositionExpressionError.operatorDepthExceeded(actual: 65, maximum: 64)` for depth 65 or `PropositionExpressionError.nodeCountExceeded(actual: 4097, maximum: 4096)` for 4097 nodes
- **AND** it does not construct a partial expression

#### Scenario: Reference byte boundaries fail before expensive processing

- **GIVEN** a valid key or nonempty literal with exactly 4096 raw and normalized UTF-8 bytes
- **WHEN** atom validation and canonicalization run
- **THEN** the reference byte limit accepts it
- **GIVEN** a key or literal for which the early-exit counter observes byte 4097
- **WHEN** validation begins
- **THEN** it returns `PropositionError.referenceUTF8ByteCountExceeded(stage: .rawUTF8, minimumObserved: 4097, maximum: 4096)` before library-owned syntax validation, trimming, normalization, hashing, or canonical allocation
- **AND** an overlong whitespace-only literal returns this resource error before `emptyLiteral`

#### Scenario: Normalization expansion has the same fixed bound

- **GIVEN** 2048 repetitions of U+0344, whose raw UTF-8 occupies 4096 bytes and whose pinned NFC expansion exceeds 4096 bytes
- **WHEN** literal validation uses the pinned normalizer
- **THEN** raw preflight succeeds
- **AND** normalized preflight returns `PropositionError.referenceUTF8ByteCountExceeded(stage: .normalizedUTF8, minimumObserved: 4097, maximum: 4096)`
- **AND** the streaming NFC sink stops at its first observed out-of-bound byte
- **AND** no complete oversized normalized buffer, canonical atom, or expression bytes are allocated

#### Scenario: Function-table arity fails before adversarial element work

- **GIVEN** an array of 13 atoms that also contains an early duplicate, a malformed atom, and an overlong sentinel
- **WHEN** `BooleanFunctionTable` initialization begins
- **THEN** it returns `ClassicalSemanticsError.rowLimitExceeded(atomCount: 13, maximumRows: 4096)` from `atoms.count`
- **AND** it performs no duplicate comparison, atom normalization, bit shift, or library-owned row allocation

#### Scenario: Twelve atoms produce the maximum accepted table

- **GIVEN** a valid expression containing 12 distinct atoms
- **WHEN** `truthTable()` preflights enumeration
- **THEN** it computes exactly 4096 rows
- **AND** enumeration succeeds when all other limits are satisfied

##### Example:

| Atom count | Mathematical row count | Disposition |
| ---: | ---: | --- |
| 1 | 2 | accepted |
| 2 | 4 | accepted |
| 12 | 4096 | accepted enumeration boundary |
| 13 | 8192 | rejected before allocation or shift |
| 63 | greater than the row bound | valid expression, enumeration rejected before shift |
| 64 | greater than the expression bound | expression factory rejected |

#### Scenario: Thirteen atoms fail before row allocation

- **GIVEN** a valid expression containing 13 distinct atoms
- **WHEN** a truth table or semantic comparison preflights the atom union
- **THEN** it returns `ClassicalSemanticsError.rowLimitExceeded(atomCount: 13, maximumRows: 4096)`
- **AND** it does not compute, shift for, or allocate the mathematical 8192 rows

#### Scenario: Sixty-three atoms remain a valid expression but cannot be enumerated

- **GIVEN** an expression containing exactly 63 validated, structurally distinct atoms within the depth and node bounds
- **WHEN** the expression factories construct it
- **THEN** construction succeeds
- **WHEN** `truthTable()` preflights that expression
- **THEN** it returns `ClassicalSemanticsError.rowLimitExceeded(atomCount: 63, maximumRows: 4096)`
- **AND** no expression equivalent to `1 << 63` executes

#### Scenario: A sixty-fourth distinct atom is rejected by the factory

- **GIVEN** bounded expressions whose candidate union would contain 64 distinct atoms
- **WHEN** `and`, `or`, `implies`, or `nor` preflights that union
- **THEN** it returns `PropositionExpressionError.distinctAtomCountExceeded(actual: 64, maximum: 63)`
- **AND** it constructs no candidate expression

#### Scenario: NOR expansion accepts the largest reachable in-bound count and rejects the first reachable out-of-bound count

- **GIVEN** a valid rewrite plan whose checked expansion estimate is exactly 4095 atom-plus-NOR nodes, the largest reachable odd count within the 4096-node limit
- **WHEN** `rewrittenUsingNor()` preflights the plan
- **THEN** rewriting proceeds
- **AND** the returned expression contains exactly 4095 nodes
- **GIVEN** a valid rewrite plan whose checked expansion estimate is 4097 atom-plus-NOR nodes
- **WHEN** `rewrittenUsingNor()` preflights the plan
- **THEN** it returns `PropositionTransformationError.rewriteNodeLimitExceeded(minimumRequired: 4097, maximum: 4096)`
- **AND** it emits no partial expression

#### Scenario: NOR synthesis accepts the largest reachable in-bound count and rejects the first reachable out-of-bound count

- **GIVEN** the fixed five-atom synthesis plan with true canonical rows `{3, 6, 7, 11, 13, 15}`, whose checked output contains exactly 4095 atom-plus-NOR nodes
- **WHEN** synthesis constructs and verifies the result
- **THEN** synthesis succeeds
- **GIVEN** the fixed five-atom synthesis plan with true canonical rows `{1, 2, 3, 4, 7}`, whose checked output requires 4103 atom-plus-NOR nodes
- **WHEN** synthesis preflights the plan
- **THEN** it returns `PropositionTransformationError.synthesisNodeLimitExceeded(minimumRequired: 4103, maximum: 4096)`
- **AND** it emits no partial expression

#### Scenario: Checked arithmetic failure is typed

- **GIVEN** adversarial count metadata whose addition, multiplication, or exponentiation cannot be represented
- **WHEN** expression construction, classical enumeration, rewriting, or synthesis preflights that metadata
- **THEN** it returns the applicable layered limit error
- **AND** a transformation error reports `minimumRequired` as 4097 when its exact count cannot be represented
- **AND** the process neither traps nor allocates from a wrapped count

#### Scenario: Caller-controlled diagnostic rendering is bounded and sanitized

- **GIVEN** classical errors or `supervaluationInconclusive(atoms:)` carrying 63 valid atoms whose literals contain bidi controls, control scalars, backslashes, and long sentinels
- **WHEN** callers use `localizedDescription`, `String(describing:)`, or `String(reflecting:)` as applicable
- **THEN** each human-readable rendering displays at most 5 atoms and at most 2048 Unicode scalars after escaping
- **AND** no raw control scalar, bidi override, or undisplayed sentinel tail appears
- **AND** the typed machine payload still retains all 63 atoms
- **AND** direct `Mirror` access to a public associated value remains explicitly outside this rendering guarantee

### Requirement: Semantic equivalence is distinct from structural equality

`PropositionExpression.isClassicallyEquivalent(to:)` SHALL compare two expressions by evaluating both over every assignment to the canonical ordered union of their atoms. It SHALL return true exactly when the result values match on every row. It SHALL enforce the same atom and row limits as `truthTable()` before enumeration.

Structural equality and hashing SHALL continue to represent exact AST identity, including the complete canonical atom-table payload, connective kind, occurrence atom index, and left-to-right child order. The internal deterministic hash-component feed SHALL include the atom-table length and bytes before node components, so single-node `atom(p)` and `atom(q)` do not have an identical feed. No semantic operation SHALL replace structural equality, structural hashing, canonical expression bytes, or collection identity; no collision-freedom claim is made for Swift's final randomized `hashValue`.

#### Scenario: Commutative formulas are semantically equal but structurally unequal

- **GIVEN** distinct atoms `p` and `q`
- **AND** expressions `or(p, q)` and `or(q, p)`
- **WHEN** structural equality compares the expressions
- **THEN** it returns false
- **WHEN** `isClassicallyEquivalent(to:)` compares the expressions
- **THEN** it returns true

#### Scenario: Material implication equals its disjunctive expansion

- **GIVEN** expressions `implies(p, q)` and `or(not(p), q)`
- **WHEN** `isClassicallyEquivalent(to:)` compares them over the ordered union `[p, q]`
- **THEN** all four row results match
- **AND** the operation returns true

#### Scenario: Different atom sets are evaluated over their union

- **GIVEN** expressions `p` and `and(p, or(q, not(q)))`
- **WHEN** `isClassicallyEquivalent(to:)` compares them
- **THEN** the ordered atom union contains `p` and `q`
- **AND** all four row results match
- **AND** the operation returns true

#### Scenario: An oversized atom union fails before comparison

- **GIVEN** two individually valid expressions whose canonical atom union contains 13 distinct atoms
- **WHEN** `isClassicallyEquivalent(to:)` preflights the comparison
- **THEN** it returns `ClassicalSemanticsError.rowLimitExceeded(atomCount: 13, maximumRows: 4096)`
- **AND** it compares no rows

### Requirement: Tautology and contradiction are defined by complete truth tables

`PropositionExpression.isClassicalTautology()` SHALL return true exactly when every row in its complete classical truth table is true. `PropositionExpression.isClassicalContradiction()` SHALL return true exactly when every row is false. Both operations SHALL use deterministic canonical atom and row order, SHALL enforce the fixed classical limits, and SHALL propagate typed construction or enumeration errors without returning a Boolean classification.

These classifications SHALL describe only finite classical semantics. They SHALL NOT infer evidence availability, epistemic certainty, provenance, psychological interpretation, or truth in a `PropositionStore`.

#### Scenario: Excluded middle is a tautology

- **GIVEN** the expression `or(p, not(p))`
- **WHEN** `isClassicalTautology()` evaluates both rows
- **THEN** it returns true
- **AND** `isClassicalContradiction()` returns false

##### Example:

| `p` | `or(p, not(p))` |
| --- | --- |
| `false` | `true` |
| `true` | `true` |

#### Scenario: Contradiction is false on every row

- **GIVEN** the expression `and(p, not(p))`
- **WHEN** `isClassicalContradiction()` evaluates both rows
- **THEN** it returns true
- **AND** `isClassicalTautology()` returns false

##### Example:

| `p` | `and(p, not(p))` |
| --- | --- |
| `false` | `false` |
| `true` | `false` |

#### Scenario: An atom is neither classification

- **GIVEN** the expression `p`
- **WHEN** both classical classifications evaluate it
- **THEN** `isClassicalTautology()` returns false
- **AND** `isClassicalContradiction()` returns false

### Requirement: Every expression has a bounded deterministic NOR rewrite

`PropositionExpression.rewrittenUsingNor()` SHALL recursively rewrite a valid expression to an expression containing only `atom` and `nor` nodes. `PropositionExpression.isNorOnly` SHALL return true exactly when every non-atom node is `nor`. Rewriting SHALL preserve source child order, structural atom identity, classical truth on every assignment, and deterministic canonical expression bytes.

The rewrite SHALL use these identities after recursively rewriting children `p` and `q`:

| Source | NOR-only replacement |
| --- | --- |
| `not(p)` | `nor(p, p)` |
| `and(p, q)` | `nor(nor(p, p), nor(q, q))` |
| `or(p, q)` | `nor(nor(p, q), nor(p, q))` |
| `implies(p, q)` | `nor(nor(nor(p, p), q), nor(nor(p, p), q))` |
| `nor(p, q)` | `nor(p, q)` |

Before allocating the rewritten tree, the operation SHALL compute its bounded expanded depth and node count with checked or saturating arithmetic, SHALL produce a bounded internal rewrite plan, and SHALL enforce `PropositionLogicLimits.maximumOperatorDepth` and `PropositionLogicLimits.maximumRewriteNodeCount`. Planned output depth 65 SHALL return `PropositionTransformationError.rewriteDepthLimitExceeded(minimumRequired: 65, maximum: 64)`; an oversized node plan SHALL return `PropositionTransformationError.rewriteNodeLimitExceeded(minimumRequired:maximum:)`. After construction and before return, an independent iterative verifier SHALL compare the source occurrences, rewrite plan, and materialized output for exact rule, node-tag, child-order, and atom-identity correspondence and SHALL verify `isNorOnly`. This production self-check SHALL NOT enumerate truth rows, so expressions containing 13 through 63 atoms remain rewritable. Complete truth tables for enumerable expressions SHALL independently verify the identities in tests. A failed rewrite invariant SHALL return `PropositionTransformationError.rewriteVerificationFailed` and no expression.

#### Scenario: Every connective rewrites to atoms and NOR

- **GIVEN** an expression containing `not`, `and`, `or`, `implies`, and `nor`
- **WHEN** `rewrittenUsingNor()` succeeds
- **THEN** the returned expression contains only `atom` and `nor` nodes
- **AND** `isNorOnly` is true
- **AND** the source and result have identical truth-table result vectors

#### Scenario: Rewrite structure is golden for every connective

- **GIVEN** ordered atoms `p` and `q`, with `N(x,y)` denoting the exact ordered `nor(x,y)` tree
- **WHEN** the five operator roots are rewritten
- **THEN** `not(p)` SHALL equal `N(p,p)`
- **AND** `and(p,q)` SHALL equal `N(N(p,p),N(q,q))`
- **AND** `or(p,q)` SHALL equal `N(N(p,q),N(p,q))`
- **AND** `implies(p,q)` SHALL equal `N(N(N(p,p),q),N(N(p,p),q))`
- **AND** `nor(p,q)` SHALL equal `N(p,q)`
- **AND** each result's canonical expression bytes SHALL equal the independently fixed bytes for that exact tree

#### Scenario: A NOR node preserves ordered children

- **GIVEN** the expression `nor(p, q)`
- **WHEN** it is rewritten
- **THEN** the result is structurally `nor(p, q)` after recursive child rewriting
- **AND** it is not reordered to `nor(q, p)`

#### Scenario: Repeated rewriting is deterministic

- **GIVEN** one valid source expression within all limits
- **WHEN** independent processes rewrite it
- **THEN** both results have identical structural ASTs
- **AND** both results have identical canonical expression bytes

#### Scenario: Rewrite self-check failure returns no expression

- **GIVEN** a module-internal per-call fault injector that corrupts one generated NOR node after construction
- **WHEN** the rewrite self-check compares the source, bounded rewrite plan, and materialized output
- **THEN** it returns `PropositionTransformationError.rewriteVerificationFailed`
- **AND** it exposes no corrupted result
- **AND** the public path uses a fixed no-op injector and no global mutable seam exists

#### Scenario: Rewriting refuses an oversized expansion

- **GIVEN** a source expression whose bounded NOR expansion requires more than 4096 nodes
- **WHEN** `rewrittenUsingNor()` preflights its expansion
- **THEN** it returns `PropositionTransformationError.rewriteNodeLimitExceeded`
- **AND** it allocates no rewritten subtree

#### Scenario: Rewriting refuses an oversized output depth

- **GIVEN** a bounded rewrite plan whose calculated output depth is 65
- **WHEN** `rewrittenUsingNor()` preflights the plan
- **THEN** it returns `PropositionTransformationError.rewriteDepthLimitExceeded(minimumRequired: 65, maximum: 64)`
- **AND** it allocates no rewritten subtree

### Requirement: BooleanFunctionTable represents bounded finite functions and guarantees binary NOR synthesis

`BooleanFunctionTable` SHALL represent a Boolean function over validated, structurally distinct atoms. It SHALL support every nonzero arity from 1 through 12 with exactly `2^n` output bits. It SHALL additionally represent arity zero with exactly one output bit so that synthesis can reject that unsupported expression shape explicitly. Its initializer SHALL label the inputs as `atomsInInputBitOrder` and `outputsInInputBitRowOrder` and SHALL accept atoms in caller-specified input-bit order; the first caller atom SHALL be the most-significant bit and the last caller atom SHALL be the least-significant bit of each supplied row. The initializer SHALL inspect `atoms.count` first and SHALL reject 13 or more atoms before duplicate checking, atom validation, shifting, or allocation. For 0...12 atoms it SHALL validate atom syntax, reject duplicates with a bounded comparison, validate output count, sort stored atoms by canonical atom bytes, and permute the supplied output vector so the stored rows use canonical atom order. For each canonical row index `j`, it SHALL decode the canonical bits, reorder them into caller bits by locating every `atomsInInputBitOrder[i]` in the canonical atom array, form `callerRowIndex` from those bits, and assign `storedOutputs[j] = suppliedOutputs[callerRowIndex]`.

Duplicate atoms SHALL return `ClassicalSemanticsError.duplicateFunctionAtom`; malformed atoms SHALL propagate their original `PropositionError`; 13 or more atoms SHALL return `ClassicalSemanticsError.rowLimitExceeded(atomCount:maximumRows:)` before any shift or allocation; and an output vector whose count is not exactly `2^n` SHALL return `ClassicalSemanticsError.outputCountMismatch(expected:actual:)`.

Canonical `BooleanFunctionTable` bytes SHALL contain this exact sequence:

1. An unsigned 64-bit big-endian length followed by the UTF-8 domain `akashic-boolean-function-table-v1`.
2. An unsigned 64-bit big-endian atom count.
3. For every canonically ordered atom, an unsigned 64-bit big-endian byte count followed by its canonical atom bytes.
4. An unsigned 64-bit big-endian row count.
5. For every canonical row, its unsigned 64-bit big-endian row index followed by one output byte, `0x00` for false or `0x01` for true.

The classical truth-table and Boolean-function-table encodings SHALL use their respective `akashic-classical-truth-table-v1` and `akashic-boolean-function-table-v1` domains even when their canonical atoms and output vectors match. Raw canonical bytes of those two different table types SHALL therefore differ by design.

`PropositionExpression.synthesizeUsingNor(_:)` SHALL reject a zero-arity table with `PropositionTransformationError.zeroArityFunctionUnsupported`. For a valid nonzero `BooleanFunctionTable`, it SHALL deterministically construct an expression containing only the table's canonical atoms and `nor` nodes when the fixed depth and 4096-node construction bounds permit that construction. A construction requiring output depth greater than 64 SHALL return `PropositionTransformationError.synthesisDepthLimitExceeded(minimumRequired:maximum:)`; a construction requiring more than 4096 nodes SHALL return `PropositionTransformationError.synthesisNodeLimitExceeded(minimumRequired:maximum:)`. Both preflights SHALL occur before allocating a partial result. Synthesis SHALL guarantee success within the fixed bounds for every one of the 16 binary four-bit output vectors from `0000` through `1111`, including constant-false and constant-true functions without adding a constant AST node.

Before returning, synthesis SHALL evaluate the result in canonical row order and compare its canonical atom array and ordered result vector with the table's canonical atom array and ordered output vector. It SHALL NOT compare raw `ClassicalTruthTable.canonicalBytes` with raw `BooleanFunctionTable.canonicalBytes` because the types have distinct encoding domains. It SHALL also verify `isNorOnly`, allowed atom membership, node count, and deterministic canonical expression bytes. A failed check SHALL return `PropositionTransformationError.synthesisVerificationFailed` and no expression.

#### Scenario: A valid binary table has one exact interpretation

- **GIVEN** distinct atoms `[p, q]` in caller input-bit order
- **AND** output bits `[false, false, false, true]`
- **WHEN** a `BooleanFunctionTable` is initialized
- **THEN** its rows denote `00 -> false`, `01 -> false`, `10 -> false`, and `11 -> true`
- **AND** its canonical bytes identify the binary conjunction function

##### Example:

| Bits in `00, 01, 10, 11` order | Familiar function |
| --- | --- |
| `0000` | constant false |
| `0001` | conjunction |
| `0110` | exclusive disjunction |
| `0111` | disjunction |
| `1000` | joint denial |
| `1101` | material implication |
| `1111` | constant true |

#### Scenario: Caller atom order is canonicalized with its output permutation

- **GIVEN** one function table expressed in caller order `[p, q]`
- **AND** the same logical function expressed in caller order `[q, p]` with its output bits permuted to that bit order
- **WHEN** both tables are initialized
- **THEN** both store the same canonically ordered atoms
- **AND** both store the same output vector in canonical row order
- **AND** both have identical canonical `BooleanFunctionTable` bytes

#### Scenario: A non-symmetric three-cycle exposes permutation direction

- **GIVEN** canonical atom order `[a, b, c]`
- **AND** caller input-bit order `[b, c, a]`
- **AND** the function whose output equals `a`, supplied in caller row order as `01010101`
- **WHEN** the function table is initialized
- **THEN** stored canonical atoms are `[a, b, c]`
- **AND** stored canonical outputs are `00001111`
- **AND** merely sorting atoms without permuting outputs cannot satisfy the result

#### Scenario: Invalid table data fails closed with layered errors

- **GIVEN** a table request containing duplicate atoms, malformed atom syntax, or an output count other than exactly `2^n`
- **WHEN** `BooleanFunctionTable` validates the request
- **THEN** it returns `ClassicalSemanticsError.duplicateFunctionAtom`, the original `PropositionError`, or `ClassicalSemanticsError.outputCountMismatch(expected:actual:)` respectively
- **AND** it constructs no table

#### Scenario: The function-table row boundary is exact

- **GIVEN** 12 distinct validated atoms and exactly 4096 outputs in caller row order
- **WHEN** `BooleanFunctionTable` is initialized
- **THEN** initialization succeeds and stores 4096 canonical rows
- **GIVEN** 13 distinct validated atoms and 8192 supplied outputs
- **WHEN** `BooleanFunctionTable` preflights the atom count
- **THEN** it returns `ClassicalSemanticsError.rowLimitExceeded(atomCount: 13, maximumRows: 4096)`
- **AND** it performs no shift and allocates no row vector

#### Scenario: Zero arity is representable but not synthesizable

- **GIVEN** a zero-arity `BooleanFunctionTable` with exactly one output
- **WHEN** the table is initialized
- **THEN** initialization succeeds with one canonical row
- **WHEN** the table is passed to `PropositionExpression.synthesizeUsingNor(_:)`
- **THEN** it returns `PropositionTransformationError.zeroArityFunctionUnsupported`
- **AND** it constructs no expression

#### Scenario: All sixteen binary functions synthesize to NOR

- **GIVEN** two distinct atoms in canonical order `p < q`
- **AND** each four-bit vector from `0000` through `1111`
- **WHEN** each vector is placed in a valid `BooleanFunctionTable` and passed to `synthesizeUsingNor(_:)`
- **THEN** all 16 operations succeed within the fixed operator-depth and 4096-node bounds
- **AND** every result has `isNorOnly == true`
- **AND** every result references only `p` and `q`
- **AND** each result reproduces its requested four-bit vector exactly

##### Example:

| Hex index | Output vector |
| ---: | --- |
| `0x0` | `0000` |
| `0x1` | `0001` |
| `0x2` | `0010` |
| `0x3` | `0011` |
| `0x4` | `0100` |
| `0x5` | `0101` |
| `0x6` | `0110` |
| `0x7` | `0111` |
| `0x8` | `1000` |
| `0x9` | `1001` |
| `0xA` | `1010` |
| `0xB` | `1011` |
| `0xC` | `1100` |
| `0xD` | `1101` |
| `0xE` | `1110` |
| `0xF` | `1111` |

#### Scenario: Synthesis structure is golden for folds and constants

- **GIVEN** the exact deterministic pre-rewrite synthesis plan
- **WHEN** a three-atom table has only canonical row 7 true
- **THEN** the plan SHALL be `and(and(p,q),r)`
- **WHEN** the two-atom vector is `0111`
- **THEN** the plan SHALL be `or(or(and(not(p),q),and(p,not(q))),and(p,q))`
- **WHEN** a three-atom table has canonical true rows `{1,3,6}`
- **THEN** the plan SHALL be `or(or(and(and(not(p),not(q)),r),and(and(not(p),q),r)),and(and(p,q),not(r)))`
- **WHEN** the two-atom vector is `0000`
- **THEN** the plan SHALL be `or(and(p,not(p)),and(q,not(q)))`
- **WHEN** the two-atom vector is `1111`
- **THEN** the plan SHALL be `and(or(p,not(p)),or(q,not(q)))`
- **AND** every final result SHALL be structurally equal and byte-equal to applying the fixed rewrite identities to that exact plan

#### Scenario: Constant functions require no constant node

- **GIVEN** valid tables `0000` and `1111` over atoms `[p, q]`
- **WHEN** both tables are synthesized
- **THEN** each result contains only `p`, `q`, and `nor` nodes
- **AND** each result references both `p` and `q` at least once so its canonical atom array remains exactly `[p, q]`
- **AND** the `0000` result is false on all four rows
- **AND** the `1111` result is true on all four rows

#### Scenario: A bounded nonbinary function has one deterministic outcome

- **GIVEN** a valid function table with between 1 and 12 atoms
- **WHEN** the deterministic synthesis construction fits the operator-depth and 4096-node bounds
- **THEN** synthesis returns a verified NOR-only expression over exactly those atoms
- **WHEN** the same construction exceeds the fixed node bound
- **THEN** synthesis returns `PropositionTransformationError.synthesisNodeLimitExceeded`
- **AND** it returns no partial expression

#### Scenario: Synthesis retains a typed defensive depth preflight

- **GIVEN** a synthesis plan whose checked output-depth estimator reports 65
- **WHEN** synthesis preflights the plan before materialization
- **THEN** it returns `PropositionTransformationError.synthesisDepthLimitExceeded(minimumRequired: 65, maximum: 64)`
- **AND** it returns no partial expression

#### Scenario: Synthesis is canonical for identical input bytes

- **GIVEN** two independently constructed tables with identical canonical `BooleanFunctionTable` bytes
- **WHEN** each is passed to `synthesizeUsingNor(_:)`
- **THEN** both results have identical AST structure
- **AND** both results have identical canonical expression bytes

#### Scenario: Synthesis enforces the largest reachable node boundary

- **GIVEN** the fixed five-atom synthesis plan with true canonical rows `{3, 6, 7, 11, 13, 15}`, whose checked output contains exactly 4095 atom-plus-NOR nodes
- **WHEN** the result is constructed and self-checked
- **THEN** synthesis succeeds
- **GIVEN** the fixed five-atom synthesis plan with true canonical rows `{1, 2, 3, 4, 7}`, whose checked output requires 4103 atom-plus-NOR nodes
- **WHEN** synthesis preflights the plan
- **THEN** it returns `PropositionTransformationError.synthesisNodeLimitExceeded(minimumRequired: 4103, maximum: 4096)`
- **AND** it emits no partial expression

#### Scenario: Synthesis mismatch fails closed

- **GIVEN** a module-internal per-call fault injector that changes one generated result bit
- **WHEN** the synthesis self-check compares canonical atoms and ordered outputs
- **THEN** it returns `PropositionTransformationError.synthesisVerificationFailed`
- **AND** it exposes no expression
- **AND** the public path uses a fixed no-op injector and no global mutable seam exists
