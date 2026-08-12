# proposition-semantics Specification

## Purpose

TBD - created by archiving change 'integrate-akashic-proposition-tractatus-map'. Update Purpose after archive.

## Requirements

### Requirement: Authored propositions SHALL use a closed typed representation

The proposition model SHALL represent its initial predicate as Proposition.authored(person:work:) with two named EntityRef arguments. EntityRef SHALL distinguish a resolved key from an unresolved non-empty literal. Proposition.makeAuthored SHALL reject a key that fails StoreKey validation and a literal that is empty after trimming whitespace. Argument arity and direction SHALL remain part of the proposition type and identity.

#### Scenario: A well-formed authored proposition is constructed

- **WHEN** a caller constructs authored with a valid person key and a non-empty work literal through Proposition.makeAuthored
- **THEN** construction SHALL succeed
- **AND** the proposition SHALL report predicateName authored and exactly two ordered arguments

##### Example: Resolved person and unresolved work title

- **GIVEN** person key `cheng-che` and work literal `Tractatus Logico-Philosophicus`
- **WHEN** Proposition.makeAuthored constructs the proposition
- **THEN** its ordered arguments SHALL be `[key("cheng-che"), literal("Tractatus Logico-Philosophicus")]`

#### Scenario: An invalid entity reference is rejected

- **WHEN** a caller passes a malformed key or a whitespace-only literal through Proposition.makeAuthored
- **THEN** construction SHALL throw the corresponding PropositionError
- **AND** the invalid reference SHALL NOT be represented as unresolved identity

##### Example: Invalid construction inputs

| Input | Expected error |
| ----- | -------------- |
| `key("Not A Key")` | `malformedKey("Not A Key")` |
| `literal("   ")` | `emptyLiteral` |

#### Scenario: Reversing arguments changes the proposition

- **WHEN** two authored propositions exchange their person and work arguments
- **THEN** the propositions SHALL compare as different values

##### Example: Direction is part of identity

- **GIVEN** keys `cheng-che` and `tractatus`
- **WHEN** authored(person: `cheng-che`, work: `tractatus`) is compared with authored(person: `tractatus`, work: `cheng-che`)
- **THEN** equality SHALL be false


<!-- @trace
source: integrate-akashic-proposition-tractatus-map
updated: 2026-08-09
code:
  - Sources/TractatusDocs/DocumentService.swift
  - docs/tractatus/source-snapshots/de-wittgenstein-project.md
  - Sources/tractatus-doc/main.swift
  - Tests/AkashicPropositionTests/PropositionTests.swift
  - Tests/TractatusDocsTests/CorpusSourceFidelityTests.swift
  - Tests/TractatusDocsTests/SourceManifestTests.swift
  - docs/tractatus/source-assets/images/250px-TLP_6.1203b.png
  - Sources/AkashicProposition/Projection.swift
  - Tests/TractatusDocsTests/TractatusDiskFixture.swift
  - Sources/TractatusDocs/Corpus.swift
  - docs/tractatus/corpus/7.yaml
  - Tests/TractatusDocsTests/TractatusInterfaceTests.swift
  - docs/tractatus/source-assets/images/6dfd74305dc6480d900085f169502024845a873e4e905856bf37dbc80f3bb653.svg
  - docs/tractatus/source-assets/images/2bdad2e773a893d516dedb66aae27db7901736d7838298078d42775abc368450.svg
  - docs/tractatus/source-assets/images/2c3e0efa8931e01e650511958fc1f6d5b5cba8c4120db825866394563d645203.svg
  - Tests/TractatusDocsTests/RenderingTests.swift
  - docs/tractatus/source-assets/images/9bfe93c20fc75f7848141a5dc2cdd0308e48f56967903cda5e95d9574182253c.svg
  - docs/tractatus/corpus/4.yaml
  - docs/tractatus/corpus/preface.yaml
  - Package.swift
  - docs/tractatus/source-assets/images/109747f0cdbcfd62f1bce67d93eb51350f5f3835c6459539f96d2dc70d84420f.svg
  - docs/tractatus/source-assets/images/250px-TLP_6.1203e-en.png
  - Tests/TractatusDocsTests/CorpusValidationTests.swift
  - Sources/TractatusDocs/SourceManifest.swift
  - docs/tractatus/source-assets/images/9a45f5fb107652caa2fff811b19eeb0547bb7389fade741c2bd6e8b866f47858.svg
  - docs/tractatus/source-assets/images/fe681449dc8d64199e5d1bdbf8208df658a75a9e18932d30c9dfe7f01673531e.svg
  - docs/tractatus/corpus/1.yaml
  - docs/tractatus/source-assets/images/200px-TLP_6.1203e.png
  - docs/tractatus/source-assets/images/300px-TLP_6.1203a-en.png
  - .vscode/launch.json
  - docs/tractatus/sources.yaml
  - .github/workflows/ci.yml
  - docs/tractatus/source-assets/images/250px-TLP_5.6331.png
  - docs/tractatus/source-assets/images/3b27b08186c4d2531ace97a6a386ca76d9996f0b7f4701697fb39daebd242145.svg
  - docs/tractatus/source-snapshots/en-ogden-ramsey-1922-wittgenstein-project.md
  - docs/tractatus/source-assets/images/1bd88ac2bf5db57ea9040cc5e72c42410c17abe58b77c117e3bfb0772eaf1d77.svg
  - Sources/TractatusDocs/Rendering.swift
  - docs/tractatus/source-assets/images/2363c84eb861521de9141a1ef7e7f9b8e30ee559dbe0fdd98ebe96665b1cacc5.svg
  - docs/tractatus/source-assets/images/6f5736dff9d73c6c95c36f30466ceb36b6191d4b51adec9af05bd29016ef01ea.svg
  - docs/tractatus/generated/tractatus-project-map.md
  - docs/tractatus/source-assets/images/120px-TLP_6.1203c.png
  - docs/tractatus/source-assets/images/ea9e48f6e881e8a034e4cbc779a077ac01d2da54238fa332cfbe2255015dca69.svg
  - docs/tractatus/source-assets/images/d61fa425857e85da7c94020ddafdf3f8038c3f33900d3f3c7e222856a8859af8.svg
  - Sources/AkashicProposition/Question.swift
  - Tests/TractatusDocsTests/Fixtures/rendering-expected.md
  - Tests/TractatusDocsTests/TractatusValidationCLITests.swift
  - docs/tractatus/source-assets/images/8972055d3850ecff6e47e1516fc07474dfcc4bf7f0095ed9bcf5389c004a6d07.svg
  - docs/tractatus/corpus/6.yaml
  - docs/tractatus/source-assets/images/250px-TLP_6.1203a.png
  - docs/tractatus/source-assets/images/250px-TLP_6.1203d.png
  - Sources/TractatusDocs/RichText.swift
  - Sources/TractatusDocs/Validation.swift
  - docs/tractatus/README.md
  - docs/tractatus/source-assets/images/250px-TLP_6.1203c-en.png
  - docs/tractatus/source-assets/images/330px-TLP_6.36111.png
  - docs/tractatus/corpus/5.yaml
  - docs/tractatus/source-assets/images/300px-TLP_6.1203b-en.png
  - docs/tractatus/source-assets/images/356a71ba81334c39be3a91a1d42c9d51eb9ad1ea7b726f750fd3a307d7947385.svg
  - docs/tractatus/source-assets/images/22c545a9a90d2f7b95fb0636e2d79882d0cd328a78afb1e7c723da5b44a774bf.svg
  - docs/tractatus/source-assets/images/531064e7807699e5544919383c09e44c0041e20bae70ec24417d5cc8e39fc4d6.svg
  - docs/tractatus/source-assets/images/79fe9d279c0691bdeef7a6bf88e5f6a6364bd5b2dabfd79444199d7e0fb31ca7.svg
  - docs/tractatus/source-assets/images/cbe2c1a200eb49c3a9b16c7105afbb9fbed122da767f2d37389ac28a9e93e102.svg
  - docs/tractatus/source-assets/images/e5973c9367aeacc00f2830f165ecedfaa5664ca53875c29edf6be4ddffb89c18.svg
  - docs/tractatus/corpus/2.yaml
  - docs/tractatus/source-assets/images/250px-TLP_5.5423.png
  - docs/tractatus/corpus/3.yaml
  - docs/tractatus/source-assets/images/250px-TLP_5.6331en.png
  - docs/tractatus/source-assets/images/300px-TLP_6.1203d-en.png
  - docs/tractatus/source-assets/images/b62025c4a407e7eb826ef60301c7aba855768d91af1e7b6d3248a9d8c43658f1.svg
  - docs/tractatus/source-assets/images/2f81698ca04ab3ce262aa94e5d57f69a5eaa2cadf033aba83d9dc9724869a8b0.svg
  - docs/tractatus/source-assets/images/d1cf195aa1fb631bffe7b018f1114530b8c1bcc712299ba306fdef8ed6c55335.svg
  - docs/tractatus/source-assets/SHA256SUMS
  - docs/tractatus/source-assets/images/ddf71a60f25ff0e495d94d2bd39bcde1e3e20286201c7de357bfe8b3b1575a1a.svg
  - Sources/AkashicProposition/Proposition.swift
  - docs/tractatus/source-assets/images/eb37987510f581cb73f8db614bd71715f510cf605279d48188050d8b509b47ed.svg
  - docs/tractatus/source-assets/images/336cae8a41089348ef601ba5dbe893d3758f7baa1841701bd587566e0f16d282.svg
  - docs/tractatus/source-assets/images/b3394a04eba3cf3b36ede15e974e646aa098169220c2c60478507502e024c872.svg
-->

---
### Requirement: Projection SHALL preserve identity resolution and role direction

`Proposition.project(in:)` SHALL require a `ValuationContext`. For authored, it SHALL return the authored projection only when the person argument resolves to a Person and the work argument resolves to an Entry in the context model. For affiliated, it SHALL return the affiliation projection only when the person argument resolves to a Person and the organization argument resolves to an Organization. It SHALL return `Projection.unprojectable` with a specific `UnprojectableReason` for an unresolved literal, unknown identity, or key that resolves to the wrong entity kind. Person, work, and organization roles SHALL NOT be interchangeable.

#### Scenario: Authored arguments resolve with the correct kinds

- **WHEN** authored refers to a known Person key in the person role and a known Entry key in the work role
- **THEN** projection SHALL return the resolved Person and Entry

#### Scenario: Affiliation arguments resolve with the correct kinds

- **WHEN** affiliated refers to a known Person key in the person role and a known Organization key in the organization role
- **THEN** projection SHALL return the resolved Person and Organization

#### Scenario: A literal remains unresolved

- **WHEN** any proposition role contains `EntityRef.literal`
- **THEN** projection SHALL return unresolvedSymbol with that role and literal
- **AND** projection SHALL NOT claim an identity match

#### Scenario: Reversed entity kinds are diagnosed

- **WHEN** a key resolves to an Entry, Person, or Organization other than the kind required by its role
- **THEN** projection SHALL return wrongEntityKind for the affected role

---
### Requirement: Evaluation SHALL preserve open-world uncertainty

`TruthValue` SHALL provide holds, fails, and undetermined states. `PropositionExpression.evaluate(in: ValuationContext)` SHALL return a `Valuation` that retains the exact expression, truth value, context, and complete recursive evidence trace. Before evaluating composite semantics, the evaluator SHALL rely on the expression's opaque validated-structure invariant, collect its cached distinct atoms in canonical order, and evaluate each distinct atom exactly once against the supplied immutable context.

Atomic authored SHALL return holds when the projected work contains the projected person key in an author slot; positive identity support SHALL take precedence over completeness evidence. When no author key matches, a matching unresolved literal SHALL return `undetermined(supportingEvidenceUnresolved)`. Any other unresolved author literal SHALL return `undetermined(authorIdentityUnresolved)`. If every author slot is a resolved key, authored SHALL return fails only when the Entry contains a valid author-list completeness witness bound to that exact work and ordered author snapshot and the resolved list excludes the projected person. Without that witness it SHALL return `undetermined(noSupportingEvidence)`. An empty author list SHALL establish fails only when an exact valid witness attests that empty list. Malformed or stale witnesses SHALL be rejected before truth evaluation rather than treated as absence. Authored evaluation SHALL retain the context valid day while marking its predicate scope as snapshot-scoped and time-invariant.

An unprojectable atom SHALL return `undetermined(notProjectable)`. Atomic affiliated SHALL preserve its existing valid-time open-world behavior and SHALL NOT produce fails because no affiliation-completeness witness exists.

Composite epistemic evaluation SHALL use bounded supervaluation over the already captured atomic valuations. Atomic holds SHALL be fixed to classical true, atomic fails SHALL be fixed to classical false, and each distinct undetermined atom SHALL be one shared Boolean variable in every compatible completion. The evaluator SHALL enumerate completions in canonical atom order with false before true. If every compatible completion makes a subexpression true, that subexpression SHALL conclude holds. If every completion makes it false, that subexpression SHALL conclude fails. If completions disagree, negation SHALL preserve its operand's exact undetermined reason and a binary subexpression SHALL conclude `undetermined(supervaluationInconclusive(atoms:))`, carrying the canonical ordered distinct atoms reachable through undetermined children that remain completion-dependent for that mixed conclusion. An unknown inside a child that has already collapsed to a tautology, contradiction, or absorbing determinate truth SHALL remain in its leaf trace but SHALL NOT be added to the parent's inconclusive aggregate. The typed atom payload SHALL remain complete, while human-readable rendering SHALL sanitize each atom and apply fixed item and final-length bounds. Supervaluation SHALL NOT use strong-Kleene operator tables.

Completion enumeration SHALL take no caller-supplied limit. Exactly 4,096 compatible completions SHALL be accepted; an expression requiring more SHALL throw `PropositionEvaluationError.supervaluationCompletionLimitExceeded(undeterminedAtomCount:maximumCompletions:)` before shift, allocation, or atom re-evaluation. Truth-table and completion `2^n` cardinalities SHALL share one guarded internal helper; a rejected 13- or 63-variable request SHALL invoke an injected checked-shift operation zero times, and cardinality code SHALL contain no second bare-shift path. Guarded row-bit decoding remains permitted. Every operator SHALL compute both child traces even when its truth is already determined by an absorbing value.

#### Scenario: Resolved supporting evidence establishes authored

- **WHEN** the projected work contains an author key equal to the projected person key
- **THEN** the atomic valuation truth SHALL be holds
- **AND** it SHALL remain holds even when a valid completeness witness is present
- **AND** its trace SHALL retain the matching author evidence

##### Example: Matching resolved author

| Query | Work author slots | Truth |
| --- | --- | --- |
| `authored(p,w)` | `[key(p)]` | holds |

#### Scenario: Witnessed resolved exclusion refutes authored

- **WHEN** a valid witness exactly attests a work author list containing only resolved keys and that list excludes the projected person
- **THEN** the atomic authored valuation truth SHALL be fails
- **AND** its trace SHALL retain the witness and full author list

##### Example: Witnessed exclusion

| Query | Attested author slots | Witness | Truth |
| --- | --- | --- | --- |
| `authored(p,w)` | `[key(q)]` | valid and exact | fails |

#### Scenario: Unwitnessed absence is not false

- **WHEN** the work contains no matching resolved author key and has no completeness witness
- **THEN** the atomic valuation truth SHALL be `undetermined(noSupportingEvidence)`
- **AND** it SHALL NOT be fails

#### Scenario: Every unresolved author blocks negative inference

- **WHEN** any author slot is a literal and no resolved key supports the projected person
- **THEN** the atomic valuation truth SHALL be an unresolved undetermined value
- **AND** it SHALL NOT be fails regardless of whether the literal resembles the person's names

##### Example: Literal blocks exclusion

| Query person | Author slot | Truth |
| --- | --- | --- |
| `key(p)` | `literal("P")` | undetermined |

#### Scenario: A matching literal is not accepted as identity

- **WHEN** an unresolved author literal normalizes to one of the person's names
- **THEN** the atomic valuation truth SHALL be `undetermined(supportingEvidenceUnresolved)` with the literal
- **AND** it SHALL NOT be holds or fails

#### Scenario: An exact witnessed empty list can refute authored

- **WHEN** a valid witness attests an exact empty author list for the projected work
- **THEN** atomic authored SHALL return fails for the projected person
- **WHEN** the same empty list lacks a witness
- **THEN** atomic authored SHALL remain `undetermined(noSupportingEvidence)`

#### Scenario: Invalid witness data never becomes epistemic uncertainty

- **WHEN** witness shape, provenance, work binding, fingerprint, or author binding is invalid
- **THEN** canonical decode or proposition-model construction SHALL reject the input
- **AND** evaluation SHALL NOT silently return `undetermined(noSupportingEvidence)` from that malformed model

#### Scenario: Authored remains snapshot-scoped across valid days

- **WHEN** the same authored expression is evaluated against the same snapshot at two different valid days
- **THEN** both valuations SHALL have the same truth and authored evidence
- **AND** each valuation SHALL retain its distinct context valid day
- **AND** each trace SHALL state that authored did not interpret a valid-time timeline

##### Example: Two valid days, one snapshot fact

| Valid day | Truth | Authored evidence |
| --- | --- | --- |
| `2026-01-01` | holds | `key(p)` slot |
| `2026-12-31` | holds | same `key(p)` slot |

#### Scenario: Excluded middle is supervaluation-valid

- **GIVEN** atomic `p` is undetermined for any typed atomic reason
- **WHEN** `or(p,not(p))` is evaluated
- **THEN** every compatible completion SHALL make the expression true
- **AND** its valuation truth SHALL be holds

#### Scenario: Contradiction is supervaluation-false

- **GIVEN** atomic `p` is undetermined for any typed atomic reason
- **WHEN** `and(p,not(p))` is evaluated
- **THEN** every compatible completion SHALL make the expression false
- **AND** its valuation truth SHALL be fails

#### Scenario: Implication and absorbing cases follow all completions

- **GIVEN** `U(p)` and `U(q)` denote undetermined atomic valuations
- **WHEN** the listed expressions are evaluated
- **THEN** their results SHALL be:

| Expression inputs | Expression | Result |
| ----------------- | ---------- | ------ |
| `U(p)` | `implies(p,p)` | `holds` |
| `fails, U(q)` | `implies(p,q)` | `holds` |
| `U(p), holds` | `implies(p,q)` | `holds` |
| `holds, U(q)` | `implies(p,q)` | `undetermined(supervaluationInconclusive(atoms: [q]))` |
| `U(p), fails` | `implies(p,q)` | `undetermined(supervaluationInconclusive(atoms: [p]))` |
| `fails, U(q)` | `and(p,q)` | `fails` |
| `holds, U(q)` | `or(p,q)` | `holds` |
| `holds, U(q)` | `and(p,q)` | `undetermined(supervaluationInconclusive(atoms: [q]))` |
| `fails, U(q)` | `or(p,q)` | `undetermined(supervaluationInconclusive(atoms: [q]))` |
| `holds, U(q)` | `nor(p,q)` | `fails` |
| `U(p)` | `nor(p,not(p))` | `fails` |
| `U(p), U(q)` with canonical `p < q` | `implies(p,q)` | `undetermined(supervaluationInconclusive(atoms: [p, q]))` |

#### Scenario: Completion enumeration is bounded

- **WHEN** an expression contains twelve distinct undetermined atoms
- **THEN** evaluation SHALL enumerate exactly 4,096 compatible completions
- **WHEN** it contains thirteen distinct undetermined atoms
- **THEN** evaluation SHALL throw `PropositionEvaluationError.supervaluationCompletionLimitExceeded(undeterminedAtomCount: 13, maximumCompletions: 4096)` without enumerating a partial result
- **AND** an injected checked-shift operation and workspace allocator SHALL each be invoked zero times

---
### Requirement: Yes-no questions SHALL expose a tri-valued answer space

`YesNoQuestion` SHALL retain a validated opaque `PropositionExpression` subject and SHALL expose exactly yes, no, and undetermined as its exhaustive `Answer` cases. Its throwing initializer SHALL rely on the subject's validated-structure invariant and SHALL construct a reserved negative answer expression through `PropositionExpression.not(subject)`, enforcing depth, node, and atom limits before storing the question. `answer(in: ValuationContext)` SHALL evaluate the complete subject exactly once and SHALL return an `AnswerResult` containing `subjectValuation` plus an optional `EstablishedAnswer` whose expression is obtained from its own holds valuation.

For subject holds, answer SHALL be yes and the established-answer valuation SHALL equal the subject holds valuation. For subject fails, answer SHALL be no and the established-answer valuation SHALL be the reserved structural `not(subject)` with truth holds and a negation trace wrapping the complete subject fails trace. For every subject undetermined value, answer SHALL be undetermined and established answer SHALL be absent. The operation SHALL NOT flatten results to `Bool`, use classical equivalence in place of structural identity, re-evaluate any atom, or construct an expression without a matching valuation.

#### Scenario: The answer space is exhaustive

- **WHEN** a caller reads `YesNoQuestion.answerSpace`
- **THEN** it SHALL contain yes, no, and undetermined exactly once
- **AND** it SHALL equal the complete set of Answer cases

#### Scenario: A yes answer retains an established subject

- **WHEN** a compound subject valuation is holds
- **THEN** answer SHALL be yes
- **AND** subject and established-answer valuations SHALL be the same occurrence-complete holds valuation

##### Example: Established yes

| Subject | Subject truth | Answer | Established expression |
| --- | --- | --- | --- |
| `and(p,q)` | holds | yes | `and(p,q)` |

#### Scenario: A no answer retains an established negation

- **WHEN** the complete subject valuation is fails
- **THEN** answer SHALL be no
- **AND** subject valuation SHALL remain the exact subject expression with fails
- **AND** established-answer valuation SHALL be the structural `not(subject)` expression with holds
- **AND** its trace SHALL wrap the complete subject trace without re-evaluation

#### Scenario: A negative subject produces structural double negation in a no answer

- **WHEN** the question subject is `not(p)` and its valuation is fails
- **THEN** the no-answer established expression SHALL be `not(not(p))`
- **AND** it SHALL NOT be normalized to `p`

#### Scenario: A compound contradiction produces an established negative answer

- **WHEN** the subject is `and(p,not(p))` and `p` is atomically undetermined
- **THEN** supervaluation SHALL make the subject fails
- **AND** the answer SHALL be no
- **AND** the established expression SHALL be the structurally exact `not(and(p,not(p)))` with a complete holds trace

#### Scenario: An undetermined answer is not assertible

- **WHEN** the subject valuation is any undetermined value
- **THEN** answer SHALL be undetermined
- **AND** established answer SHALL be absent

##### Example: Tri-valued answer mapping

| Subject truth | Answer | Established answer |
| ------------- | ------ | ------------------ |
| `holds` | `yes` | `subject / holds` |
| `fails` | `no` | `not(subject) / holds` |
| `undetermined(supervaluationInconclusive(atoms: [p]))` | `undetermined` | absent |

#### Scenario: Question construction reserves resource budget

- **WHEN** a valid subject already consumes the maximum operator depth or total node count so that `not(subject)` would exceed a limit
- **THEN** `YesNoQuestion` initialization SHALL throw the corresponding typed `PropositionExpressionError`
- **AND** no question SHALL be returned

#### Scenario: Answer propagation preserves audit context

- **WHEN** a question is answered from a context-bound compound subject valuation
- **THEN** snapshot identity, revision, valid day, every occurrence's atomic evidence or refusal, and complete quarantine SHALL be unchanged in subject and established-answer traces

##### Example: Answer context propagation

| Field | Subject valuation | Established valuation |
| --- | --- | --- |
| Snapshot revision | `r1` | `r1` |
| Valid day | `2026-08-10` | `2026-08-10` |

---
### Requirement: Fact acceptance SHALL be gated from recorded assertions

`Assertion` SHALL record a validated opaque `PropositionExpression`, `Stance`, source, and `RecordedTime` without itself asserting truth. `AcceptedFact` SHALL be a distinct type whose construction is restricted to adjudication. Assertion construction and adjudication SHALL rely on the expression's preserved validated-structure invariant; any new expression they construct SHALL pass through a bounded throwing factory. Adjudication SHALL consume an existing `Valuation` and verify exact structural expression equality before checking stance or truth. Classical semantic equivalence SHALL NOT satisfy this identity gate. Adjudication SHALL accept only an asserted Assertion whose structurally matching expression valuation truth is holds. It SHALL reject a mismatched expression, denied or questioned stance, and fails or undetermined truth. A successful fact SHALL retain the expression, assertion, acceptedBy, `AcceptedTime`, complete recursive valuation, every occurrence trace, context, evidence, refusal, and quarantine. A `notEstablished` refusal SHALL retain the refused valuation unchanged.

#### Scenario: An established assertion becomes an accepted fact

- **WHEN** an asserted atomic or compound Assertion is adjudicated with a structurally matching holds valuation
- **THEN** adjudication SHALL return an AcceptedFact retaining the expression, assertion, and complete valuation
- **AND** the result SHALL record acceptedBy and typed acceptedAt

##### Example: Accepted asserted expression

| Stance | Matching truth | Result |
| --- | --- | --- |
| asserted | holds | AcceptedFact |

#### Scenario: An asserted negation can become a negative fact

- **WHEN** `asserted(not(p))` is adjudicated with the established `not(p) / holds` valuation from a no-answer
- **THEN** adjudication SHALL return an AcceptedFact for the exact negated expression
- **AND** its recursive trace SHALL retain the original `p / fails` evidence

#### Scenario: A compound supervaluation conclusion can become a fact

- **WHEN** `asserted(or(p,not(p)))` is adjudicated with its structurally matching holds valuation while atomic `p` is undetermined
- **THEN** adjudication SHALL return an AcceptedFact for the exact disjunction
- **AND** the fact SHALL retain both occurrences of `p`, the negation node, their undetermined atomic evidence, and the holds root conclusion

#### Scenario: A failed positive expression cannot become a negative fact

- **WHEN** `asserted(p)` is adjudicated with `p / fails`
- **THEN** adjudication SHALL throw `notEstablished` with that valuation
- **AND** it SHALL NOT synthesize `not(p)` or a fact

#### Scenario: A question or denial cannot become a fact

- **WHEN** an Assertion has questioned or denied stance
- **THEN** adjudication SHALL throw `stanceIsNotAssertion`
- **AND** no AcceptedFact or implicit negation SHALL be created

#### Scenario: Uncertainty cannot become a fact

- **WHEN** an asserted expression is adjudicated with a matching undetermined valuation
- **THEN** adjudication SHALL throw `notEstablished` with that valuation
- **AND** no AcceptedFact SHALL be created

#### Scenario: A valuation for another expression is refused first

- **WHEN** the supplied valuation expression differs structurally from the assertion expression
- **THEN** adjudication SHALL throw `expressionMismatch`
- **AND** no stance or truth result SHALL override that mismatch

#### Scenario: Semantic equivalence does not replace recorded syntax

- **WHEN** an assertion records `or(p,q)` and the supplied valuation records structurally different `or(q,p)`
- **THEN** adjudication SHALL throw `expressionMismatch` even when classical equivalence returns true
- **AND** no AcceptedFact SHALL be created

#### Scenario: Fact retains three independent time roles

- **WHEN** an assertion recorded on one day is evaluated for another valid day and accepted on a third day
- **THEN** the AcceptedFact SHALL retain all three typed values through its basis and valuation

##### Example: Independent time roles

| RecordedTime | ValidDay | AcceptedTime |
| --- | --- | --- |
| `2026-08-01` | `2026-07-31` | `2026-08-10` |

---
### Requirement: Canonical proposition models SHALL reject ambiguous identity keys

`PropositionModel` SHALL reject construction before creating identity dictionaries when the supplied snapshot contains duplicate entry citekeys, duplicate person keys, or duplicate organization keys. The rejection SHALL report the complete deduplicated and ascending-sorted duplicate keys for all three classes in one equatable error. Its localized description SHALL report each class total, display at most the first five ascending-sorted keys from each class, state the omitted count, and sanitize every displayed key with `displaySafe(max: 120)` without truncating any machine-readable payload. The implementation SHALL NOT select a first or last record for a duplicate key. A production proposition model SHALL retain the `StoreSnapshotID` of the trusted `LibrarySnapshot` from which it was constructed.

#### Scenario: Entry person and organization duplicates are rejected together

- **WHEN** snapshot input contains duplicate `work-a` entries, duplicate `person-a` people, and duplicate `org-a` organizations
- **THEN** construction SHALL throw one error with entry `["work-a"]`, person `["person-a"]`, and organization `["org-a"]` payloads
- **AND** no `PropositionModel` SHALL be created

#### Scenario: Duplicate rejection is independent of input order

- **WHEN** the same conflicting entry, person, or organization records are supplied in forward and reverse order
- **THEN** both constructions SHALL throw equal validation errors
- **AND** neither order SHALL produce a truth-bearing model

#### Scenario: Unique snapshot identities remain accepted

- **WHEN** every entry citekey, person key, and organization key in a trusted snapshot is unique
- **THEN** model construction SHALL succeed
- **AND** each input SHALL be retrievable by its canonical key
- **AND** the model SHALL retain the snapshot ID

#### Scenario: Large duplicate sets retain complete payloads and bounded diagnostics

- **WHEN** snapshot input contains more than five distinct duplicate keys in every identity class
- **THEN** the validation error SHALL retain every sorted key in all three machine-readable payloads
- **AND** its localized description SHALL display only the first five keys from each class and state every total and omitted count
- **AND** caller-controlled control or direction characters in any displayed class SHALL be sanitized

---
### Requirement: Truth-bearing proposition operations SHALL reject malformed syntax

Every public operation that derives a projection, truth value, answer, established answer, or accepted fact from `PropositionExpression` SHALL accept only the opaque validated value produced by its throwing factories or read-only child views. `PropositionExpression.atom(_:)`, `Proposition.asExpression()`, and raw `Proposition` projection or evaluation entry points SHALL validate the atom before interpreting it against a model and SHALL propagate its original `PropositionError`. Higher expression factories, `YesNoQuestion`, `Assertion`, and `adjudicate` SHALL preserve the expression invariant and SHALL propagate any error produced while creating a new bounded expression. No operation SHALL produce a partial expression, trace, answer, or `AcceptedFact` after atom validation or candidate-budget failure. Syntax invalidity SHALL NOT be represented as `Projection.unprojectable`, `TruthValue.undetermined`, a classical value, or another epistemic result. `PropositionError` localized, default, and debug string rendering SHALL use the same `displaySafe(max: 120)` summary and SHALL NOT reflect a raw malformed key.

#### Scenario: A direct empty literal is rejected across semantic operations

- **WHEN** a caller passes `authored(person: literal("   "), work: key("work-a"))` to `PropositionExpression.atom(_:)`, `Proposition.asExpression()`, or a raw `Proposition` semantic entry point
- **THEN** the attempted expression construction or raw semantic operation SHALL throw `PropositionError.emptyLiteral`
- **AND** no expression SHALL exist for question construction, answer, assertion construction, or adjudication to turn into an unprojectable, undetermined, or successful result

#### Scenario: A malformed key cannot be made true by a matching malformed model

- **WHEN** a proposition contains malformed key `Not A Key` and a hand-built unique model contains the same malformed person and author key
- **THEN** `PropositionExpression.atom(_:)`, `Proposition.asExpression()`, and raw `Proposition` semantic entry points SHALL throw `PropositionError.malformedKey("Not A Key")`
- **AND** adjudication SHALL NOT create an `AcceptedFact`

#### Scenario: Malformed syntax inside a binary branch is rejected before evaluation

- **WHEN** an external caller attempts to place a malformed raw atom in either branch of `and`, `or`, `implies`, or `nor`
- **THEN** atom construction SHALL throw the original `PropositionError` before the enclosing factory can receive that branch
- **AND** no sibling atom SHALL be interpreted against the context
- **AND** no partial child trace SHALL be returned

#### Scenario: Over-budget syntax is not uncertainty

- **WHEN** a factory candidate would exceed depth, node, or distinct-atom limits
- **THEN** the first applicable typed `PropositionExpressionError` SHALL be thrown before an expression exists
- **AND** no operation SHALL translate that failure into any `undetermined(...)` value

#### Scenario: External callers cannot bypass the expression invariant

- **WHEN** a non-`@testable` client attempts to invoke recursive storage, raw node initializers, enum-style cases, or a factory overload with a caller-selected limit
- **THEN** the client SHALL fail to compile
- **AND** the only constructible expression values SHALL come from the bounded throwing factories or their read-only child views

#### Scenario: Proposition and formula diagnostics do not reflect raw payloads

- **WHEN** a proposition error, classical error, evaluation reason, or transformation error carries bounded but adversarial atom payloads
- **THEN** default, localized, and debug rendering as applicable SHALL escape controls, show at most 5 atoms, and stop at 2048 Unicode scalars after escaping
- **AND** the typed machine payload SHALL remain complete

#### Scenario: Valid absence remains epistemically undetermined

- **WHEN** a valid canonical atomic proposition and unique model contain no matching author identity
- **THEN** atomic evaluation SHALL return `undetermined(noSupportingEvidence)`
- **AND** it SHALL NOT throw a canonical-input error or return `fails`

---
### Requirement: Valuation contexts SHALL bind an immutable model view to a valid day

`PropositionModel` SHALL be publicly constructible from a trusted `LibrarySnapshot` and SHALL retain its `StoreSnapshotID`. `PropositionModel.context(validAt:)` SHALL create a `ValuationContext` that binds that exact immutable model, snapshot ID, and one validated `ValidDay`. `ValuationContext` SHALL NOT expose a public initializer that permits a caller to combine a model with a different snapshot ID. Truth-bearing APIs SHALL NOT provide an overload that omits context, reads a mutable current store, or substitutes the system clock.

#### Scenario: A complete context is created from one snapshot

- **WHEN** a caller loads one trusted library snapshot, constructs its proposition model, and requests valid day `2026-08-09`
- **THEN** the context SHALL retain that snapshot store identity and revision
- **AND** its valid day SHALL equal `2026-08-09`
- **AND** its internal model SHALL be the model derived from that snapshot

#### Scenario: A context cannot be assembled from unrelated parts

- **WHEN** a caller has models and snapshot IDs from two different revisions
- **THEN** the public API SHALL NOT permit construction of a context that pairs one model with the other revision

#### Scenario: Evaluation requires explicit context

- **WHEN** a caller invokes projection, evaluation, or question answering
- **THEN** the public operation SHALL require a `ValuationContext`
- **AND** it SHALL NOT infer a valid day or reload a current store

#### Scenario: Two valid days preserve distinct contexts

- **WHEN** two contexts use the same immutable snapshot and different valid days
- **THEN** their snapshot IDs SHALL be equal
- **AND** their contexts SHALL remain distinguishable by valid day

---
### Requirement: Valuation outcomes SHALL retain context and structured evidence

`evaluate(in:)` SHALL return a `Valuation` containing the evaluated `PropositionExpression`, `TruthValue`, complete `ValuationContext`, and typed recursive `EvidenceTrace`. Every syntax occurrence SHALL produce one trace node with read-only `kind`, exact subexpression, exact context, ordered `children`, typed `atomicEvidence`, and derived `conclusion` views. Trace `Kind` SHALL use `atom`, `not`, `and`, `or`, `implies`, and `nor`. Atom nodes SHALL have no children and SHALL retain predicate scope, projection or refusal, supporting and excluding evidence, author-list completeness witness or affiliation segment, temporal assessment, final atomic undetermined reason, and the complete snapshot quarantine. Not nodes SHALL have one operand child. And, or, implies, and nor nodes SHALL have exactly two children ordered left then right. Composite nodes SHALL NOT fabricate atomic evidence or require parsing a human-readable description.

The evaluator SHALL evaluate each distinct atom once per root evaluation while creating a separate atom trace node for every syntax occurrence. Repeated occurrence nodes SHALL retain the same immutable atomic valuation payload without reloading the store. Every composite conclusion SHALL be mechanically derived from bounded supervaluation over its complete child structure. Both binary children SHALL remain in the trace even when an absorbing truth value determines the parent. Public callers SHALL NOT receive constructors that pair arbitrary children, contexts, evidence, or conclusions. Trace equality SHALL use iterative traversal; this change SHALL NOT add `Hashable` conformance to `EvidenceTrace`.

#### Scenario: Supported authorship retains its matching slot

- **WHEN** atomic authored holds because one work author slot contains the projected person key
- **THEN** the valuation trace SHALL identify the person key, work key, matching author slot, and any present completeness witness
- **AND** it SHALL mark authored as snapshot-scoped and time-invariant

##### Example: Positive trace fields

| Person | Work | Matching slot | Scope |
| --- | --- | --- | --- |
| `p` | `w` | `key(p)` | snapshot-scoped |

#### Scenario: Refuted authorship retains its complete exclusion evidence

- **WHEN** atomic authored fails because a valid witness attests a fully resolved author snapshot that excludes the projected person
- **THEN** the atomic trace SHALL retain the witness and every author slot assessment
- **AND** every surrounding operator trace SHALL retain that atomic occurrence unchanged

##### Example: Negative trace fields

| Query | Attested slots | Retained witness | Truth |
| --- | --- | --- | --- |
| `authored(p,w)` | `[key(q),key(r)]` | exact author-list witness | fails |

#### Scenario: Temporal support retains the complete segment

- **WHEN** atomic affiliated holds because one affiliation segment definitely contains the context valid day
- **THEN** the valuation trace SHALL retain that segment value, `DateRange`, source, note, and temporal assessment
- **AND** it SHALL mark affiliated as valid-time-scoped

#### Scenario: Every syntax occurrence has an ordered trace node

- **WHEN** `implies(and(p,p),nor(q,not(p)))` is evaluated
- **THEN** the trace SHALL contain one node for every written atom and operator occurrence
- **AND** the two occurrences of `p` under `and` SHALL be distinct trace nodes backed by one atomic evaluation
- **AND** every binary node's children SHALL remain ordered left then right
- **AND** the root conclusion SHALL equal the valuation truth

#### Scenario: Absorbing truth does not short-circuit audit evidence

- **WHEN** a known-false atom is conjoined with an undetermined atom containing projection refusal or quarantine evidence
- **THEN** the conjunction conclusion SHALL be fails
- **AND** both child nodes and the undetermined atom's complete refusal, evidence, context, and quarantine SHALL remain in the trace

##### Example: Absorbing false with retained sibling

| Left child | Right child | Parent | Retained children |
| --- | --- | --- | --- |
| fails | undetermined with refusal | fails | left and right |

#### Scenario: A question answer retains subject and established valuations

- **WHEN** `YesNoQuestion.answer(in:)` maps a compound subject valuation to yes, no, or undetermined
- **THEN** its `AnswerResult` SHALL retain the complete subject valuation
- **AND** a determinate result SHALL retain a complete established-answer holds valuation
- **AND** it SHALL NOT replace either valuation with a bare truth value

#### Scenario: Adjudication retains successful and refused valuations

- **WHEN** adjudication accepts a holds valuation or refuses a non-holds valuation
- **THEN** the `AcceptedFact` or `notEstablished` refusal SHALL retain that exact expression valuation
- **AND** snapshot ID, valid day, occurrence-complete evidence trace, and quarantine SHALL remain unchanged

---
### Requirement: Valuation time roles SHALL remain nominally distinct

`ValidDay`, `RecordedTime`, and `AcceptedTime` SHALL be distinct public value types rather than type aliases. Each SHALL accept only a real Gregorian day in ASCII `YYYY-MM-DD` form and SHALL preserve its canonical raw value. `Assertion` SHALL accept only `RecordedTime`; `ValuationContext` SHALL accept only `ValidDay`; adjudication SHALL accept only `AcceptedTime`. No truth-bearing API SHALL accept a raw time string.

#### Scenario: Invalid Gregorian days are rejected

- **WHEN** a caller constructs any time role with a year-only value, month-only value, impossible day, or non-ASCII digits
- **THEN** construction SHALL throw a typed time validation error

##### Example: Date validation boundaries

| Input | Expected result |
| ----- | --------------- |
| `2024-02-29` | accepted |
| `2023-02-29` | rejected |
| `2026-08` | rejected |
| `２０２６-０８-０９` | rejected |

#### Scenario: Recorded valid and accepted days remain independent

- **WHEN** an assertion is recorded on `2026-08-08`, evaluated at valid day `2020-01-01`, and accepted on `2026-08-09`
- **THEN** all three typed values SHALL be retained without substitution

#### Scenario: One time role cannot replace another

- **WHEN** a caller has a `RecordedTime`
- **THEN** the typed API SHALL NOT accept it where `ValidDay` or `AcceptedTime` is required

---
### Requirement: Temporal affiliation propositions SHALL evaluate person affiliation timelines

`Proposition` SHALL include the closed typed predicate `affiliated(person:organization:)`. Both arguments SHALL pass canonical proposition validation and project to a `Person` and `Organization` in the context model with their declared role direction. Evaluation SHALL inspect only `Person.profile.affiliations`; organization containment or parent relations SHALL NOT satisfy person affiliation.

A resolved matching organization segment with `TemporalContainment.definitelyContains` SHALL produce holds. A matching unresolved literal, temporal indeterminacy, or invalid temporal evidence SHALL produce a typed undetermined result and trace. No matching active segment SHALL produce `undetermined(noSupportingEvidence)`. The evaluator SHALL NOT produce fails because the snapshot has no positive affiliation-completeness evidence. If any matching segment definitely contains the day, that positive evidence SHALL establish holds while all other segment assessments remain in the trace.

#### Scenario: The same affiliation differs across valid days

- **WHEN** a resolved affiliation runs from `2020-01-01` through `2020-12-31`
- **THEN** evaluation at `2020-06-15` SHALL return holds
- **AND** evaluation at `2021-01-01` SHALL return `undetermined(noSupportingEvidence)`

#### Scenario: An unresolved organization literal remains undetermined

- **WHEN** a matching affiliation value is a literal rather than a resolved organization key
- **THEN** evaluation SHALL return `undetermined(supportingEvidenceUnresolved)`
- **AND** it SHALL NOT infer identity from a normalized organization name

#### Scenario: Coarse or unknown temporal boundaries fail closed

- **WHEN** a matching segment assessment is precision-indeterminate, unknown-start, or unknown-end
- **THEN** evaluation SHALL return an undetermined result that retains that temporal reason
- **AND** it SHALL NOT return holds or fails from that segment alone

#### Scenario: Invalid temporal evidence remains visible

- **WHEN** a matching segment has contradictory shape, an impossible Gregorian endpoint, or an end definitely earlier than its start
- **THEN** evaluation SHALL return `undetermined(invalidTemporalEvidence)` unless another matching segment definitely contains the day
- **AND** the invalid evidence SHALL remain in the trace

#### Scenario: Organization containment does not establish affiliation

- **WHEN** an organization has a parent relation to another organization but the person's affiliation timeline lacks the requested organization
- **THEN** affiliated SHALL remain `undetermined(noSupportingEvidence)`

---
### Requirement: Proposition expressions SHALL represent bounded structural negation

`Proposition` SHALL remain the closed atomic predicate type. `PropositionExpression` SHALL become the single opaque public formula value. Its recursive storage and raw node initializers SHALL NOT be public. It SHALL expose read-only `Kind` values `atom`, `not`, `and`, `or`, `implies`, and `nor`, together with read-only proposition and ordered children views appropriate to each kind.

The primary public construction paths SHALL be the throwing factories `atom`, `not`, `and`, `or`, `implies`, and `nor`. `Proposition.asExpression()` SHALL validate its raw atomic proposition and forward to `PropositionExpression.atom(_:)`. The library SHALL retain deprecated `makeAtom` and `makeNot` wrappers as throwing safe forwarders to `atom` and `not`, and SHALL retain deprecated read-only `PropositionExpression.maximumOperatorDepth` as an alias of `PropositionLogicLimits.maximumOperatorDepth`; they SHALL NOT expose raw storage, bypass validation, add a nonthrowing construction path, or allow a caller-selected limit. Every atom factory SHALL validate its `Proposition`; every unary or binary factory SHALL combine only already-valid opaque operands and SHALL validate the complete candidate metrics before returning. A malformed atomic `Proposition` SHALL propagate its original `PropositionError` rather than be wrapped as a resource or epistemic error. No factory SHALL simplify, reorder, deduplicate, or short-circuit its operands.

`PropositionExpression` SHALL implement syntax-sensitive structural `Equatable` and `Hashable`. An atom, its negation, its double negation, and any differently ordered binary tree SHALL remain distinct values. Its deterministic internal structural hash feed SHALL first include the complete canonical atom-table lengths and payloads, then every occurrence's structural node tag, child boundary, and atom index. `atom(p)` and `atom(q)` SHALL therefore have different feeds, while no collision-freedom guarantee is made for Swift's final `hashValue`. Equality, hashing, validation, and public inspection SHALL use bounded iterative traversal rather than recursively consuming the call stack.

The library-owned hard limits SHALL be 4,096 raw and pinned-NFC normalized UTF-8 bytes per logical key or literal, operator depth 64, total syntax nodes 4,096, and distinct atoms 63. A repeated atom SHALL count once toward the distinct-atom limit and once per occurrence toward the node limit. The exact boundary values SHALL be accepted; byte 4,097, 65 operator levels, 4,097 nodes, or 64 distinct atoms SHALL throw the corresponding `PropositionError.referenceUTF8ByteCountExceeded(stage:minimumObserved:maximum:)`, `PropositionExpressionError.operatorDepthExceeded(actual: 65, maximum: 64)`, `nodeCountExceeded(actual: 4097, maximum: 4096)`, or `distinctAtomCountExceeded(actual: 64, maximum: 63)`. Public APIs SHALL NOT accept caller-supplied limit parameters. Shape metadata and checked arithmetic SHALL enforce each expression limit before storage allocation. Classical row enumeration, epistemic completion enumeration, and transformation output SHALL use their separate 4,096 hard limits and their respective `ClassicalSemanticsError`, `PropositionEvaluationError`, and `PropositionTransformationError` types.

Every library-owned proposition-semantic entry point SHALL use early-exit UTF-8 counting for raw logical references before syntax validation, trimming, normalization, library-owned hashing, or canonical allocation. An overlong whitespace-only literal SHALL receive the raw resource error before `emptyLiteral`. Syntax SHALL use pinned Unicode 15.1.0 White_Space; source-order assigned-scalar validation SHALL follow syntax; a capped streaming pinned-NFC sink SHALL then stop at normalized byte 4097 without building a complete oversized buffer. Syntax error SHALL precede unsupported-scalar error, and unsupported scalar SHALL precede a later normalized overflow. Every factory-produced `PropositionExpression` SHALL carry the opaque validated-structure invariant and bounded cached metrics for its lifetime. Public evaluation, question construction and answering, classical operations, transformation, assertion construction, and adjudication SHALL consume that invariant rather than promise to reconstruct or revalidate inaccessible raw storage. Raw `Proposition` entry points, including `Proposition.asExpression()`, SHALL validate before an expression exists; library-owned hash and cache keys SHALL contain only validated expression atoms. No invalid raw proposition or over-budget candidate SHALL become an expression, `TruthValue.undetermined`, a classical result, or a partial trace.

#### Scenario: Negation has structural identity

- **WHEN** `p`, `not(p)`, and `not(not(p))` are constructed through factories, compared, and inserted into a hashed set
- **THEN** all three SHALL remain distinct structural values

#### Scenario: Structural hashing includes the atom table

- **WHEN** `atom(p)` and `atom(q)` are constructed for distinct validated atoms
- **THEN** their deterministic structural hash feeds SHALL differ in canonical atom-table payload
- **AND** removing that payload, any node tag, or any child boundary SHALL fail a load-bearing test

#### Scenario: The legacy depth constant remains a safe alias

- **WHEN** existing source reads deprecated `PropositionExpression.maximumOperatorDepth`
- **THEN** it SHALL receive `PropositionLogicLimits.maximumOperatorDepth`
- **AND** it SHALL NOT gain a setter or a caller-controlled limit

#### Scenario: Double negation is semantically equal but structurally distinct

- **WHEN** `p` and `not(not(p))` are evaluated in the same context
- **THEN** their truth values SHALL be equal
- **AND** the double-negation trace SHALL retain two negation nodes
- **AND** their expression identities SHALL remain unequal

#### Scenario: Nested malformed atoms are rejected

- **WHEN** `PropositionExpression.atom(_:)` or `Proposition.asExpression()` receives a malformed key or empty literal
- **THEN** it SHALL throw the original typed proposition error before returning an expression
- **AND** an external caller SHALL NOT be able to raw-construct a malformed nested operand for `not`, `and`, `or`, `implies`, or `nor`

#### Scenario: Overlong and unsupported logical references are rejected before expression storage

- **WHEN** a raw key or literal reaches byte 4,097, a pinned-NFC result reaches byte 4,097, or a literal contains a scalar unassigned in Unicode 15.1.0
- **THEN** `PropositionExpression.atom(_:)` and `Proposition.asExpression()` SHALL throw the corresponding typed `PropositionError`
- **AND** syntax trimming, operating-system normalization, expression hashing, and canonical expression allocation SHALL NOT run after that failure
- **AND** no enclosing operator SHALL receive a partial operand

#### Scenario: Normalized output is capped while streaming

- **WHEN** a syntax-valid raw-cap-compliant literal expands past 4096 pinned-NFC UTF-8 bytes
- **THEN** the normalizer SHALL stop at observed byte 4097 and return `PropositionError.referenceUTF8ByteCountExceeded(stage: .normalizedUTF8, minimumObserved: 4097, maximum: 4096)`
- **AND** it SHALL NOT build a complete oversized normalized buffer
- **WHEN** an earlier unsupported scalar and a later normalized overflow coexist
- **THEN** `PropositionError.unsupportedUnicodeScalar(value:normalizationVersion:)` SHALL win

#### Scenario: Expression depth is bounded

- **WHEN** an expression has 64 operator levels
- **THEN** expression construction and validation SHALL succeed if every other limit and atom are valid
- **WHEN** an expression would have 65 operator levels
- **THEN** its factory SHALL throw `PropositionExpressionError.operatorDepthExceeded(actual: 65, maximum: 64)`

#### Scenario: Node count is bounded independently of depth

- **WHEN** a balanced expression contains exactly 4,096 total syntax occurrences without exceeding another limit
- **THEN** validation SHALL succeed
- **WHEN** a factory would create occurrence 4,097
- **THEN** it SHALL throw `PropositionExpressionError.nodeCountExceeded(actual: 4097, maximum: 4096)` before allocating the invalid result

#### Scenario: Distinct atom count has a safe machine boundary

- **WHEN** a valid expression contains exactly 63 distinct atoms
- **THEN** expression validation SHALL succeed even when a later truth-table operation exceeds its separate row limit
- **WHEN** a factory would add a sixty-fourth distinct atom
- **THEN** it SHALL throw `PropositionExpressionError.distinctAtomCountExceeded(actual: 64, maximum: 63)` without performing a bit shift

#### Scenario: Binary child order remains structural

- **WHEN** `and(p,q)` and `and(q,p)` are compared
- **THEN** structural equality SHALL be false
- **AND** semantic equivalence SHALL remain a separate throwing operation

#### Scenario: A question reserves one representable negation

- **WHEN** a caller constructs a yes-no question
- **THEN** the throwing initializer SHALL accept only a validated subject and SHALL construct `not(subject)` within depth, node, and atom limits
- **AND** every determinate no-answer SHALL have a valid expression

---
### Requirement: Negation evaluation SHALL derive a recursive evidence trace

Expression evaluation SHALL require a `ValuationContext` and SHALL produce a `Valuation` whose expression is the exact input expression. Atomic evaluation SHALL produce an `EvidenceTrace` atom node. Every operator SHALL produce its corresponding not, and, or, implies, or nor trace node after all child nodes have been created. Public callers SHALL receive read-only kind, expression, context, children, atomic evidence, and conclusion views; they SHALL NOT receive raw constructors that combine a caller-selected conclusion with arbitrary children or evidence. Trace equality SHALL traverse iteratively rather than use synthesized recursive operations; `EvidenceTrace` SHALL remain non-`Hashable`.

Negation SHALL exchange holds and fails and SHALL preserve every `undetermined(reason)` value exactly. Binary operator conclusions SHALL use bounded supervaluation, including determinate tautologies, contradictions, implications, and absorbing cases that strong-Kleene evaluation leaves undetermined. Every operator SHALL preserve the same snapshot ID, valid day, atomic projections, evidence items, refusals, and complete quarantine without reloading a store or recomputing a different model view. A context-free public epistemic truth helper SHALL NOT exist.

#### Scenario: Determinate truth is inverted

- **WHEN** a negation operand truth is holds or fails
- **THEN** its negation truth SHALL be fails or holds respectively

##### Example: Determinate negation

| Operand | Negation |
| --- | --- |
| holds | fails |
| fails | holds |

#### Scenario: Every undetermined reason is preserved

- **WHEN** a negation operand is undetermined because it is not projectable, lacks supporting evidence, contains unresolved support, contains unresolved author identity, has indeterminate temporal evidence, has invalid temporal evidence, or is supervaluation-inconclusive
- **THEN** its negation SHALL retain the exact same reason and payload
- **AND** it SHALL NOT become holds or fails

##### Example: Three-valued negation

| Operand truth | Negated truth |
| ------------- | ------------- |
| `holds` | `fails` |
| `fails` | `holds` |
| `undetermined(noSupportingEvidence)` | `undetermined(noSupportingEvidence)` |

#### Scenario: Negation retains its complete operand trace

- **WHEN** a negated valuation is derived from an atomic or compound operand valuation
- **THEN** the negation node SHALL contain the complete operand trace
- **AND** its final conclusion SHALL equal the valuation truth
- **AND** snapshot ID, valid day, quarantine, projection, refusal, and evidence SHALL remain unchanged

##### Example: Wrapped operand trace

| Root kind | Child kind | Context identity | Evidence identity |
| --- | --- | --- | --- |
| not | atom | unchanged | unchanged |

#### Scenario: Binary operators retain both child traces

- **WHEN** conjunction, disjunction, implication, or joint denial has a child whose evidence does not affect the determinate parent truth
- **THEN** the operator node SHALL retain both complete ordered children
- **AND** it SHALL NOT short-circuit atom evaluation or trace construction

##### Example: Ordered binary trace

| Operator | Left child | Right child | Stored order |
| --- | --- | --- | --- |
| and | fails | undetermined | left, right |

#### Scenario: Multiple negations are derived without re-evaluation

- **WHEN** an expression has two or more structural negation nodes, including `not(not(p))`
- **THEN** the evaluator SHALL evaluate that distinct atom once against the supplied immutable context
- **AND** it SHALL wrap the complete child trace once per structural negation from inner to outer
- **AND** it SHALL preserve both negation occurrences without normalization

#### Scenario: Trace construction and equality remain controlled

- **WHEN** an external caller inspects an evaluated trace
- **THEN** it SHALL be able to read each node kind, expression, context, ordered children, conclusion, and atomic evidence
- **AND** it SHALL NOT be able to construct any node with a caller-selected conclusion
- **AND** equality of two library-produced traces for a valid 4,096-node boundary expression SHALL complete without recursively exhausting the call stack
- **AND** an external caller SHALL NOT be able to raw-construct an expression or trace with node 4,097

---
### Requirement: Denied stance SHALL remain distinct from asserted negation

`Stance.denied` SHALL describe a source's meta-level stance toward the exact recorded expression. It SHALL NOT construct, imply, evaluate, or establish the negation of that expression. A negative proposition-level assertion SHALL use `Stance.asserted` with an explicit expression returned by `PropositionExpression.not(_:)`. The API SHALL NOT provide an automatic denied-to-negation conversion.

#### Scenario: Denial is not an asserted negative proposition

- **WHEN** one record is `denied(p)` and another is `asserted(not(p))`
- **THEN** they SHALL remain distinct Assertions
- **AND** the denied record SHALL NOT supply the negative expression or its valuation

#### Scenario: A denied stance cannot become a fact

- **WHEN** a denied Assertion is adjudicated with any valuation
- **THEN** adjudication SHALL throw `stanceIsNotAssertion`
- **AND** it SHALL NOT convert the stance to asserted negation

---
### Requirement: Classical formula semantics SHALL be total, bivalent, bounded, and deterministic

`ClassicalValuation` SHALL assign `Bool` values to proposition atoms. Its public throwing initializer SHALL accept `[(atom: Proposition, value: Bool)]`, not `[Proposition: Bool]`; it SHALL reject more than 63 entries before element work, validate every atom before library-owned hashing, and reject a duplicate validated atom with `ClassicalSemanticsError.duplicateValuationAtom(Proposition)`. `PropositionExpression.classicalValue(under:)` SHALL implement atom lookup, Boolean negation, conjunction, disjunction, material implication, and joint denial with the following definitions: `not(a) = !a`, `and(a,b) = a && b`, `or(a,b) = a || b`, `implies(a,b) = !a || b`, and `nor(a,b) = !(a || b)`. Classical evaluation SHALL reject a valuation that omits any distinct atom required by the expression with `ClassicalSemanticsError.incompleteValuation(missing:)`, whose missing atoms are in canonical order. Valid assignments for atoms outside the expression SHALL be permitted within the 63-assignment valuation limit and SHALL be ignored. Classical evaluation SHALL NOT interpret `TruthValue.undetermined` as a third classical truth value.

`truthTable()` SHALL take no caller-supplied limit. It SHALL return a `ClassicalTruthTable` whose atom order is the ascending byte order of the canonical atom encoding and whose rows enumerate `false` before `true`, with the first atom changing slowest. Canonical atom encoding SHALL begin with a UInt64 length-framed ASCII versioned domain `akashic-proposition-atom-v1`; predicate tags SHALL be authored `0x00` and affiliated `0x01`, while `EntityRef` tags SHALL be key `0x00` and literal `0x01`. Expression tags SHALL be atom `0x00`, not `0x01`, `and` `0x02`, or `0x03`, implies `0x04`, and nor `0x05`, with left child before right child. Every admitted logical string identity SHALL use repository-bundled Unicode 15.1.0 NFC followed by UTF-8 and its UInt64 big-endian byte length. Swift-equal NFC and NFD spellings in that pinned admitted scalar set SHALL therefore produce identical canonical atom bytes. `ClassicalTruthTable.canonicalBytes` SHALL use the separate ASCII versioned domain `akashic-classical-truth-table-v1` and UInt64 big-endian length and count framing.

Unicode v1 inputs SHALL include the five official normalization, composition, property, and conformance files named by `finite-truth-function-semantics`; an independently checked manifest SHALL pin every input SHA-256, generator SHA-256, runtime-normalizer source SHA-256, generated-table source SHA-256, Unicode version, White_Space property, and canonical domain. Offline regeneration, official normalization conformance, pinned White_Space fixtures, a production static source ban on Foundation／CoreFoundation normalization and whitespace APIs, and a domain-version gate SHALL fail if the data, manifest, generator, runtime, or generated source changes without a domain revision. Row-count arithmetic SHALL go through one guarded checked-power-of-two helper and SHALL be checked before invoking its shift operation, multiplication, allocation, or iteration. A table whose row count would exceed 4,096 SHALL throw `ClassicalSemanticsError.rowLimitExceeded(atomCount:maximumRows:)`; at most twelve distinct atoms SHALL be enumerated because twelve atoms produce exactly 4,096 rows and thirteen produce 8,192.

#### Scenario: Every binary operator has a complete four-row matrix

- **GIVEN** canonical atom order `[p, q]`
- **WHEN** the four valuations are enumerated as `FF`, `FT`, `TF`, and `TT`
- **THEN** the complete result matrix SHALL be:

| p | q | `and(p,q)` | `or(p,q)` | `implies(p,q)` | `nor(p,q)` |
| - | - | ---------- | --------- | -------------- | ---------- |
| F | F | F | F | T | T |
| F | T | F | T | T | F |
| T | F | F | T | F | F |
| T | T | T | T | T | F |

#### Scenario: Negation has a complete two-row matrix

- **WHEN** `not(p)` is evaluated under `p = false` and `p = true`
- **THEN** the results SHALL be `true` and `false` respectively

#### Scenario: Missing assignments fail closed

- **WHEN** an expression contains distinct atoms `p` and `q` and a classical valuation assigns only `p`
- **THEN** `classicalValue(under:)` SHALL throw `ClassicalSemanticsError.incompleteValuation(missing: [q])`
- **AND** it SHALL NOT substitute `false`, consult a store, or return a partial value

#### Scenario: Extra assignments do not change a classical result

- **GIVEN** a valid classical valuation within the 63-assignment limit assigns every atom required by an expression
- **WHEN** the valuation also assigns atoms outside that expression
- **THEN** `classicalValue(under:)` SHALL ignore the extra assignments
- **AND** it SHALL return the same result as the valuation restricted to the expression's atoms

#### Scenario: Classical valuation validates an entry list before indexing

- **WHEN** an in-bound entry list contains a malformed raw atom
- **THEN** its original `PropositionError` SHALL be returned before library-owned hashing or indexing
- **WHEN** an in-bound entry list repeats a validated atom
- **THEN** `ClassicalSemanticsError.duplicateValuationAtom` SHALL be returned with no first-wins or last-wins result
- **AND** no public initializer SHALL accept a raw-`Proposition` dictionary

#### Scenario: Truth-table ordering is replay-stable

- **WHEN** the same expression is used to produce a truth table in separate processes
- **THEN** atom order, row order, assignments, and result values SHALL be identical
- **AND** canonical encodings of both tables SHALL be byte-for-byte equal

##### Example: Replayed implication table

| Process | Atom order | Row order | Result vector |
| --- | --- | --- | --- |
| A | `[p,q]` | `FF,FT,TF,TT` | `TTFT` |
| B | `[p,q]` | `FF,FT,TF,TT` | `TTFT` |

#### Scenario: Unicode-equivalent atoms have one canonical encoding

- **WHEN** Swift-equal atom payloads are supplied once in NFC spelling and once in NFD spelling
- **THEN** their canonical atom bytes SHALL be identical NFC UTF-8 payloads
- **AND** truth tables built from the logically equal expressions SHALL have byte-for-byte equal canonical encodings

#### Scenario: Unicode v1 has a complete reproducible trust chain

- **WHEN** the vendored UCD inputs, manifest, generator, runtime-normalizer source, and generated table source are verified and regenerated offline
- **THEN** all independently fixed SHA-256 values and every official normalization conformance case SHALL match
- **AND** pinned White_Space fixtures SHALL define empty-literal syntax
- **AND** changing any trust-chain byte without changing the v1 canonical domain SHALL fail verification

#### Scenario: Every expression tag and transformation representative is golden

- **WHEN** atom, not, and, or, implies, nor, a non-symmetric nested child order, `not(p)` rewrite, and unary-not synthesis are encoded
- **THEN** their node payload or full canonical bytes SHALL match the exact v1 golden vectors in `finite-truth-function-semantics`
- **AND** neither tag remapping nor child reordering SHALL preserve the gate

#### Scenario: Row enumeration is bounded before arithmetic

- **WHEN** a table requires exactly 4,096 rows
- **THEN** `truthTable()` SHALL succeed if all other expression limits are satisfied
- **WHEN** a table requires 8,192 rows
- **THEN** `truthTable()` SHALL throw `ClassicalSemanticsError.rowLimitExceeded(atomCount: 13, maximumRows: 4096)` before performing an overflowing shift or allocating rows
- **AND** an injected checked-shift operation SHALL be invoked zero times on rejection

---
### Requirement: Classical equivalence and NOR transformation SHALL preserve bounded truth conditions

`isClassicallyEquivalent(to:)` SHALL compare truth conditions over the canonical ordered union of both expressions' atoms and SHALL return a semantic result independent of structural equality. It SHALL take no caller-supplied limit and SHALL enforce the 4,096-row hard bound before enumeration. Structural `Equatable` and `Hashable` SHALL remain syntax-sensitive and SHALL NOT call semantic equivalence.

`rewrittenUsingNor()` SHALL deterministically return a structurally valid `PropositionExpression` containing only atom and nor nodes. It SHALL enforce the expression limits and the 4,096 rewrite-node limit, then use an independent bounded rewrite-plan verifier to check exact rule, child-order, atom-identity, and NOR-only correspondence before returning it. The production self-check SHALL NOT require truth-row enumeration, so valid expressions with 13 through 63 atoms remain rewritable; enumerable rewrite identities SHALL also be verified by complete truth tables in tests. `BooleanFunctionTable` initialization SHALL accept zero through twelve valid distinct atoms and exactly `2^n` outputs within the 4,096-row bound; a zero-atom table SHALL contain exactly one output and SHALL remain a valid constant-function representation. `PropositionExpression.synthesizeUsingNor(_:)` SHALL accept a validated `BooleanFunctionTable` with one through twelve atoms, deterministically construct an atom/NOR expression within the same limits, and verify that the generated truth table has the same canonical atoms and result vector as the input table. Synthesis of a valid zero-atom table SHALL throw `PropositionTransformationError.zeroArityFunctionUnsupported`. Cross-type canonical bytes SHALL NOT be compared because `BooleanFunctionTable` SHALL use the distinct ASCII versioned domain `akashic-boolean-function-table-v1`. A rewrite whose planned output depth exceeds 64 SHALL throw `PropositionTransformationError.rewriteDepthLimitExceeded(minimumRequired:maximum:)`; one that exceeds its node budget SHALL throw `PropositionTransformationError.rewriteNodeLimitExceeded(minimumRequired:maximum:)`; a rewrite-plan mismatch SHALL throw `PropositionTransformationError.rewriteVerificationFailed`. Synthesis SHALL analogously throw `PropositionTransformationError.synthesisDepthLimitExceeded(minimumRequired:maximum:)` or `PropositionTransformationError.synthesisNodeLimitExceeded(minimumRequired:maximum:)`. A synthesis semantic mismatch SHALL throw `PropositionTransformationError.synthesisVerificationFailed`. Rewrite and synthesis verifiers SHALL expose only module-internal per-call fault injectors for load-bearing tests; public paths SHALL use fixed no-op injectors and no global mutable seam. Every verification failure SHALL return no expression.

#### Scenario: Structural identity differs from semantic equivalence

- **WHEN** `or(p,q)` is compared with `or(q,p)`
- **THEN** structural equality SHALL be false
- **AND** `isClassicallyEquivalent(to:)` SHALL return true

#### Scenario: Core equivalence laws are executable

- **WHEN** classical equivalence is checked for double negation, material implication, both De Morgan laws, and a NOR rewrite
- **THEN** each of the following pairs SHALL be equivalent:
  - `not(not(p))` and `p`
  - `implies(p,q)` and `or(not(p),q)`
  - `not(and(p,q))` and `or(not(p),not(q))`
  - `not(or(p,q))` and `and(not(p),not(q))`
  - `e.rewrittenUsingNor()` and `e`
- **AND** no pair SHALL be required to compare as structurally equal

##### Example: Semantic laws

| Left | Right | Equivalent |
| --- | --- | --- |
| `not(not(p))` | `p` | true |
| `implies(p,q)` | `or(not(p),q)` | true |

#### Scenario: NOR rewrite contains only the complete basis

- **WHEN** a bounded expression containing every public operator is rewritten using NOR
- **THEN** every generated node SHALL have kind atom or nor
- **AND** the generated expression SHALL be classically equivalent to the source expression
- **AND** repeated rewrites of the same source SHALL be structurally equal

##### Example: Implication rewrite

| Source | Exact NOR-only result | Node kinds |
| --- | --- | --- |
| `implies(p,q)` | `nor(nor(nor(p,p),q),nor(nor(p,p),q))` | atom, nor |

#### Scenario: Every rewrite operator has an exact structural golden

- **WHEN** not, and, or, implies, and nor roots over ordered atoms are rewritten
- **THEN** each result SHALL be structurally equal and byte-equal to its exact ordered NOR tree in `finite-truth-function-semantics`
- **AND** a different semantically equivalent NOR tree SHALL NOT satisfy the transformation contract

#### Scenario: All sixteen binary Boolean functions are synthesized

- **GIVEN** canonical atoms `[p, q]` and row order `FF`, `FT`, `TF`, `TT`
- **WHEN** `PropositionExpression.synthesizeUsingNor(_:)` is invoked for each of the sixteen possible four-bit result vectors from `0000` through `1111`
- **THEN** all sixteen invocations SHALL return an expression containing only atom and nor nodes
- **AND** each synthesized expression's truth table SHALL exactly equal its input vector
- **AND** repeated synthesis of the same vector SHALL produce a structurally equal expression

#### Scenario: Synthesis folds and constants have exact structural goldens

- **WHEN** synthesis receives the single-minterm, three-atom `{1,3,6}` multirow, binary `0111`, `0000`, or `1111` fixture from `finite-truth-function-semantics`
- **THEN** its pre-rewrite plan and final NOR expression SHALL match the specified exact structural and byte golden
- **AND** semantic equivalence or replay stability alone SHALL NOT substitute for that structural match

#### Scenario: Transformation limits fail closed

- **WHEN** a rewrite or synthesis would create more than 4,096 nodes
- **THEN** rewrite SHALL throw `PropositionTransformationError.rewriteNodeLimitExceeded(minimumRequired: 4097, maximum: 4096)` for a 4,097-node plan, and synthesis SHALL report its exact checked requirement, including `PropositionTransformationError.synthesisNodeLimitExceeded(minimumRequired: 4103, maximum: 4096)` for the fixed first reachable five-atom fixture
- **AND** neither operation SHALL return or partially expose a generated expression

#### Scenario: Transformation depth limits retain layered errors

- **WHEN** a rewrite plan's checked output depth is 65
- **THEN** rewrite SHALL throw `PropositionTransformationError.rewriteDepthLimitExceeded(minimumRequired: 65, maximum: 64)`
- **WHEN** a synthesis plan's defensive checked output depth is 65
- **THEN** synthesis SHALL throw `PropositionTransformationError.synthesisDepthLimitExceeded(minimumRequired: 65, maximum: 64)`
- **AND** neither operation SHALL return or partially expose a generated expression

#### Scenario: Transformation self-check faults fail closed

- **WHEN** a module-internal per-call rewrite fault injector corrupts one materialized node
- **THEN** rewrite SHALL throw `PropositionTransformationError.rewriteVerificationFailed` and return no expression
- **WHEN** a module-internal per-call synthesis fault injector flips one candidate output
- **THEN** synthesis SHALL throw `PropositionTransformationError.synthesisVerificationFailed` and return no expression
- **AND** neither seam SHALL be public or global mutable state
