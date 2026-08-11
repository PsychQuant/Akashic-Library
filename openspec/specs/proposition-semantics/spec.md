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

`TruthValue` SHALL provide holds, fails, and undetermined states. `PropositionExpression.evaluate(in: ValuationContext)` SHALL return a `Valuation` that retains the exact expression, truth value, context, and recursive evidence trace. Atomic authored SHALL return holds when the projected work contains the projected person key in an author slot; positive identity support SHALL take precedence over completeness evidence.

When no author key matches, a matching unresolved literal SHALL return `undetermined(supportingEvidenceUnresolved)`. Any other unresolved author literal SHALL return `undetermined(authorIdentityUnresolved)`. If every author slot is a resolved key, authored SHALL return fails only when the Entry contains a valid author-list completeness witness bound to that exact work and ordered author snapshot and the resolved list excludes the projected person. Without that witness it SHALL return `undetermined(noSupportingEvidence)`. An empty author list SHALL establish fails only when an exact valid witness attests that empty list. Malformed or stale witnesses SHALL be rejected before truth evaluation rather than treated as absence. Authored evaluation SHALL retain the context valid day while marking its predicate scope as snapshot-scoped and time-invariant.

An unprojectable atom SHALL return `undetermined(notProjectable)`. Atomic affiliated SHALL preserve its existing valid-time open-world behavior and SHALL NOT produce fails because no affiliation-completeness witness exists. Expression negation SHALL apply only after atomic evaluation according to the recursive-negation requirement.

#### Scenario: Resolved supporting evidence establishes authored

- **WHEN** the projected work contains an author key equal to the projected person key
- **THEN** the atomic valuation truth SHALL be holds
- **AND** it SHALL remain holds even when a valid completeness witness is present
- **AND** its trace SHALL retain the matching author evidence

#### Scenario: Witnessed resolved exclusion refutes authored

- **WHEN** a valid witness exactly attests a work author list containing only resolved keys and that list excludes the projected person
- **THEN** the atomic authored valuation truth SHALL be fails
- **AND** its trace SHALL retain the witness and full author list

#### Scenario: Unwitnessed absence is not false

- **WHEN** the work contains no matching resolved author key and has no completeness witness
- **THEN** the atomic valuation truth SHALL be `undetermined(noSupportingEvidence)`
- **AND** it SHALL NOT be fails

#### Scenario: Every unresolved author blocks negative inference

- **WHEN** any author slot is a literal and no resolved key supports the projected person
- **THEN** the atomic valuation truth SHALL be an unresolved undetermined value
- **AND** it SHALL NOT be fails regardless of whether the literal resembles the person's names

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

---
### Requirement: Yes-no questions SHALL expose a tri-valued answer space

`YesNoQuestion` SHALL retain a validated `PropositionExpression` subject and SHALL expose exactly yes, no, and undetermined as its exhaustive `Answer` cases. Its throwing initializer SHALL ensure both the subject and a possible `not(subject)` fit the expression depth budget. `answer(in: ValuationContext)` SHALL evaluate the subject exactly once and SHALL return an `AnswerResult` containing `subjectValuation` plus an optional `EstablishedAnswer` whose expression is obtained from its own holds valuation.

For subject holds, answer SHALL be yes and the established-answer valuation SHALL equal the subject holds valuation. For subject fails, answer SHALL be no and the established-answer valuation SHALL be `not(subject)` with truth holds and a negation trace wrapping the subject fails trace. For every subject undetermined value, answer SHALL be undetermined and established answer SHALL be absent. The operation SHALL NOT flatten results to Bool or construct an expression without a matching valuation.

#### Scenario: The answer space is exhaustive

- **WHEN** a caller reads `YesNoQuestion.answerSpace`
- **THEN** it SHALL contain yes, no, and undetermined exactly once
- **AND** it SHALL equal the complete set of Answer cases

#### Scenario: A yes answer retains an established subject

- **WHEN** the subject valuation is holds
- **THEN** answer SHALL be yes
- **AND** subject and established-answer valuations SHALL be the same holds valuation

#### Scenario: A no answer retains an established negation

- **WHEN** the subject valuation is fails
- **THEN** answer SHALL be no
- **AND** subject valuation SHALL remain the exact subject expression with fails
- **AND** established-answer valuation SHALL be the structural `not(subject)` expression with holds
- **AND** its trace SHALL wrap the complete subject trace without re-evaluation

#### Scenario: A negative subject produces structural double negation in a no answer

- **WHEN** the question subject is `not(p)` and its valuation is fails
- **THEN** the no-answer established expression SHALL be `not(not(p))`
- **AND** it SHALL NOT be normalized to `p`

#### Scenario: An undetermined answer is not assertible

- **WHEN** the subject valuation is any undetermined value
- **THEN** answer SHALL be undetermined
- **AND** established answer SHALL be absent

##### Example: Tri-valued answer mapping

| Subject truth | Answer | Established answer |
| ------------- | ------ | ------------------ |
| `holds` | `yes` | `subject / holds` |
| `fails` | `no` | `not(subject) / holds` |
| `undetermined(noSupportingEvidence)` | `undetermined` | absent |

#### Scenario: Answer propagation preserves audit context

- **WHEN** a question is answered from a context-bound subject valuation
- **THEN** snapshot identity, revision, valid day, atomic evidence, and complete quarantine SHALL be unchanged in subject and established-answer traces

---
### Requirement: Fact acceptance SHALL be gated from recorded assertions

`Assertion` SHALL record a `PropositionExpression`, `Stance`, source, and `RecordedTime` without itself asserting truth. `AcceptedFact` SHALL be a distinct type whose construction is restricted to adjudication. Adjudication SHALL consume an existing `Valuation`, validate the complete assertion and valuation expressions, and verify exact structural expression equality before checking stance or truth. It SHALL accept only an asserted Assertion whose matching expression valuation truth is holds. It SHALL reject a mismatched expression, denied or questioned stance, and fails or undetermined truth. A successful fact SHALL retain the expression, assertion, acceptedBy, `AcceptedTime`, and complete recursive valuation. A `notEstablished` refusal SHALL retain the refused valuation.

#### Scenario: An established assertion becomes an accepted fact

- **WHEN** an asserted Assertion is adjudicated with a structurally matching holds valuation
- **THEN** adjudication SHALL return an AcceptedFact retaining the expression, assertion, and valuation
- **AND** the result SHALL record acceptedBy and typed acceptedAt

#### Scenario: An asserted negation can become a negative fact

- **WHEN** `asserted(not(p))` is adjudicated with the established `not(p) / holds` valuation from a no-answer
- **THEN** adjudication SHALL return an AcceptedFact for the exact negated expression
- **AND** its recursive trace SHALL retain the original `p / fails` evidence

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

#### Scenario: Fact retains three independent time roles

- **WHEN** an assertion recorded on one day is evaluated for another valid day and accepted on a third day
- **THEN** the AcceptedFact SHALL retain all three typed values through its basis and valuation

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

Every public operation that derives a projection, truth value, answer, or accepted fact SHALL validate the proposition before interpreting it against a model. `project(in:)`, `evaluate(in:)`, and `answer(in:)` SHALL propagate `PropositionError` through throwing APIs. `adjudicate` SHALL defensively propagate the same error and SHALL NOT produce `AcceptedFact` from malformed syntax. Syntax invalidity SHALL NOT be represented as `Projection.unprojectable`, `TruthValue.undetermined`, or another epistemic result. `PropositionError` localized, default, and debug string rendering SHALL use the same `displaySafe(max: 120)` summary and SHALL NOT reflect a raw malformed key.

#### Scenario: A direct empty literal is rejected across semantic operations

- **WHEN** a caller directly constructs `authored(person: literal("   "), work: key("work-a"))`
- **THEN** project, evaluate, answer, and adjudicate SHALL each throw `PropositionError.emptyLiteral`
- **AND** none of those operations SHALL return an unprojectable or undetermined result

#### Scenario: A malformed key cannot be made true by a matching malformed model

- **WHEN** a directly constructed proposition contains malformed key `Not A Key` and a hand-built unique model contains the same malformed person and author key
- **THEN** evaluation SHALL throw `PropositionError.malformedKey("Not A Key")`
- **AND** adjudication SHALL NOT create an `AcceptedFact`

#### Scenario: Valid absence remains epistemically undetermined

- **WHEN** a valid canonical proposition and unique model contain no matching author identity
- **THEN** evaluation SHALL return `undetermined(noSupportingEvidence)`
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

`evaluate(in:)` SHALL return a `Valuation` containing the evaluated `PropositionExpression`, `TruthValue`, complete `ValuationContext`, and typed recursive `EvidenceTrace`. Atomic evidence SHALL identify predicate scope, projected identities, the supporting author slot, author-list completeness witness, or affiliation segment, temporal assessment, and the final undetermined reason. Snapshot quarantine warnings that affect the captured model view SHALL remain visible. A negation trace SHALL contain its complete operand trace and its own conclusion. Trace semantics SHALL NOT depend on parsing a human-readable description.

#### Scenario: Supported authorship retains its matching slot

- **WHEN** atomic authored holds because one work author slot contains the projected person key
- **THEN** the valuation trace SHALL identify the person key, work key, matching author slot, and any present completeness witness
- **AND** it SHALL mark authored as snapshot-scoped and time-invariant

#### Scenario: Refuted authorship retains its complete exclusion evidence

- **WHEN** atomic authored fails because a valid witness attests a fully resolved author snapshot that excludes the projected person
- **THEN** the atomic trace SHALL retain the witness and every author slot assessment
- **AND** a surrounding negation trace SHALL retain that atomic trace unchanged

#### Scenario: Temporal support retains the complete segment

- **WHEN** atomic affiliated holds because one affiliation segment definitely contains the context valid day
- **THEN** the valuation trace SHALL retain that segment value, `DateRange`, source, note, and temporal assessment
- **AND** it SHALL mark affiliated as valid-time-scoped

#### Scenario: A question answer retains subject and established valuations

- **WHEN** `YesNoQuestion.answer(in:)` maps a subject valuation to yes, no, or undetermined
- **THEN** its `AnswerResult` SHALL retain the complete subject valuation
- **AND** a determinate result SHALL retain a complete established-answer holds valuation
- **AND** it SHALL NOT replace either valuation with a bare truth value

#### Scenario: Adjudication retains successful and refused valuations

- **WHEN** adjudication accepts a holds valuation or refuses a non-holds valuation
- **THEN** the `AcceptedFact` or `notEstablished` refusal SHALL retain that exact expression valuation
- **AND** snapshot ID, valid day, and recursive evidence trace SHALL remain unchanged

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

`Proposition` SHALL remain the closed atomic predicate type. `PropositionExpression` SHALL be the single public formula type and SHALL initially provide `atom(Proposition)` and `not(PropositionExpression)`. It SHALL implement structural `Equatable` and `Hashable`: an atom, its negation, and its double negation SHALL remain three distinct values when compared or inserted into a hashed collection. Hashing SHALL incorporate structural node tags and payloads while making no collision-freedom guarantee beyond Swift's `Hashable` contract. Semantic simplification SHALL NOT occur during construction, equality, or hashing.

Expression validation SHALL inspect every nested atom and SHALL reject operator nesting greater than 64 with a typed error. Public evaluation, question answering, and adjudication SHALL repeat expression validation because public enum cases can bypass safe factories. Equality, hashing, validation, and evaluation SHALL use a traversal that does not recursively consume the call stack for an unvalidated unary chain.

#### Scenario: Negation has structural identity

- **WHEN** `p`, `not(p)`, and `not(not(p))` are compared and inserted into a hashed set
- **THEN** all three SHALL remain distinct structural values

#### Scenario: Double negation is semantically equal but structurally distinct

- **WHEN** `p` and `not(not(p))` are evaluated in the same context
- **THEN** their truth values SHALL be equal
- **AND** the double-negation trace SHALL retain two negation nodes
- **AND** their expression identities SHALL remain unequal

#### Scenario: Nested malformed atoms are rejected

- **WHEN** a malformed key or empty literal occurs inside one or more `not` nodes
- **THEN** evaluation, question answering, and adjudication SHALL throw the original typed proposition error
- **AND** double-negation handling SHALL NOT erase or bypass atom validation

#### Scenario: Expression depth is bounded

- **WHEN** an expression has 64 operator nodes
- **THEN** expression validation SHALL succeed if its atom is valid
- **WHEN** an expression has 65 operator nodes
- **THEN** expression validation SHALL throw a typed depth error

#### Scenario: A question reserves one representable negation

- **WHEN** a caller constructs a yes-no question
- **THEN** the throwing initializer SHALL validate both its subject and `not(subject)` within the 64-node limit
- **AND** every determinate no-answer SHALL have a valid expression

---
### Requirement: Negation evaluation SHALL derive a recursive evidence trace

Expression evaluation SHALL require a `ValuationContext` and SHALL produce a `Valuation` whose expression is the exact input expression. Atomic evaluation SHALL produce an `EvidenceTrace` atom node. Negation SHALL produce an `EvidenceTrace` negation node containing the complete operand trace and a conclusion equal to the negated operand truth. Public callers SHALL receive read-only trace kind, operand, conclusion, and atomic audit views; they SHALL NOT receive raw atom or negation constructors that can pair an operand with an arbitrary conclusion. Trace equality SHALL traverse node chains iteratively rather than use synthesized recursive equality. Negation SHALL exchange holds and fails; it SHALL preserve every `undetermined(reason)` value exactly. It SHALL preserve the same snapshot ID, valid day, atomic projection, evidence items, and complete quarantine list without reloading a store or recomputing a different model view. A context-free public truth-negation helper SHALL NOT exist.

#### Scenario: Determinate truth is inverted

- **WHEN** an operand truth is holds or fails
- **THEN** its negation truth SHALL be fails or holds respectively

#### Scenario: Every undetermined reason is preserved

- **WHEN** an operand is undetermined because it is not projectable, lacks supporting evidence, contains unresolved support, contains unresolved author identity, has indeterminate temporal evidence, or has invalid temporal evidence
- **THEN** its negation SHALL retain the exact same reason and payload
- **AND** it SHALL NOT become holds or fails

##### Example: Three-valued negation

| Operand truth | Negated truth |
| ------------- | ------------- |
| `holds` | `fails` |
| `fails` | `holds` |
| `undetermined(noSupportingEvidence)` | `undetermined(noSupportingEvidence)` |

#### Scenario: Negation retains its complete operand trace

- **WHEN** a negated valuation is derived from an atomic authored or affiliated valuation
- **THEN** the negation node SHALL contain the entire atomic operand trace
- **AND** its final conclusion SHALL equal the valuation truth
- **AND** snapshot ID, valid day, quarantine, projection, and evidence SHALL remain unchanged

#### Scenario: Multiple negations are derived without re-evaluation

- **WHEN** an expression has two or more negation nodes
- **THEN** the evaluator SHALL evaluate the atom once against the supplied immutable context
- **AND** it SHALL wrap the trace once per structural negation from inner to outer

#### Scenario: Trace construction and equality remain controlled

- **WHEN** an external caller inspects an evaluated trace
- **THEN** it SHALL be able to read each node kind, operand, conclusion, and atomic evidence
- **AND** it SHALL NOT be able to construct a negation node with a caller-selected conclusion
- **AND** equality of an internally assembled 32,768-node trace chain SHALL complete without recursively exhausting the call stack

---
### Requirement: Denied stance SHALL remain distinct from asserted negation

`Stance.denied` SHALL describe a source's meta-level stance toward the exact recorded expression. It SHALL NOT construct, imply, evaluate, or establish the negation of that expression. A negative proposition-level assertion SHALL use `Stance.asserted` with an explicit `PropositionExpression.not`. The API SHALL NOT provide an automatic denied-to-negation conversion.

#### Scenario: Denial is not an asserted negative proposition

- **WHEN** one record is `denied(atom(p))` and another is `asserted(not(atom(p)))`
- **THEN** they SHALL remain distinct Assertions
- **AND** the denied record SHALL NOT supply the negative expression or its valuation

#### Scenario: A denied stance cannot become a fact

- **WHEN** a denied Assertion is adjudicated with any valuation
- **THEN** adjudication SHALL throw `stanceIsNotAssertion`
- **AND** it SHALL NOT convert the stance to asserted negation
