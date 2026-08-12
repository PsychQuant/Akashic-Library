## ADDED Requirements

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

### Requirement: Valuation outcomes SHALL retain context and structured evidence

`evaluate(in:)` SHALL return a `Valuation` containing the evaluated proposition, `TruthValue`, complete `ValuationContext`, and typed `EvidenceTrace`. Evidence SHALL identify predicate scope, projected identities, the supporting author slot or affiliation segment, temporal assessment, and the final undetermined or refusal reason. Snapshot quarantine warnings that affect the captured model view SHALL remain visible in the trace. Trace semantics SHALL NOT depend on parsing a human-readable description.

#### Scenario: Supported authorship retains its matching slot

- **WHEN** authored holds because one work author slot contains the projected person key
- **THEN** the valuation trace SHALL identify the person key, work key, and matching author slot
- **AND** it SHALL mark authored as snapshot-scoped and time-invariant

#### Scenario: Temporal support retains the complete segment

- **WHEN** affiliated holds because one affiliation segment definitely contains the context valid day
- **THEN** the valuation trace SHALL retain that segment value, `DateRange`, source, note, and temporal assessment
- **AND** it SHALL mark affiliated as valid-time-scoped

#### Scenario: A question answer retains its originating valuation

- **WHEN** `YesNoQuestion.answer(in:)` maps a valuation to yes, no, or undetermined
- **THEN** its `AnswerResult` SHALL retain the complete originating valuation
- **AND** it SHALL NOT replace the valuation with a bare truth value

#### Scenario: Adjudication retains successful and refused valuations

- **WHEN** adjudication accepts a holds valuation or refuses a non-holds valuation
- **THEN** the `AcceptedFact` or `notEstablished` refusal SHALL retain that exact valuation
- **AND** snapshot ID, valid day, and evidence trace SHALL remain unchanged

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

## MODIFIED Requirements

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

### Requirement: Evaluation SHALL preserve open-world uncertainty

`TruthValue` SHALL provide holds, fails, and undetermined states. `evaluate(in: ValuationContext)` SHALL return a `Valuation` that retains the truth value, context, and evidence trace. The authored evaluator SHALL return holds only when the projected work contains the projected person key in an author slot. An unprojectable proposition SHALL return undetermined with notProjectable. A matching unresolved author literal SHALL return undetermined with supportingEvidenceUnresolved. Absence of supporting author identity SHALL return undetermined with noSupportingEvidence. The current authored evaluator SHALL NOT produce fails because the model has no positive author-list completeness evidence. Authored evaluation SHALL retain the context valid day while marking its predicate scope as snapshot-scoped and time-invariant.

#### Scenario: Resolved supporting evidence establishes authored

- **WHEN** the projected work contains an author key equal to the projected person key
- **THEN** the valuation truth SHALL be holds
- **AND** its trace SHALL retain the matching author evidence

#### Scenario: Absence is not false

- **WHEN** the work contains no matching resolved author key
- **THEN** the valuation truth SHALL be `undetermined(noSupportingEvidence)`
- **AND** it SHALL NOT be fails

#### Scenario: A matching literal is not accepted as identity

- **WHEN** an unresolved author literal normalizes to one of the person's names
- **THEN** the valuation truth SHALL be `undetermined(supportingEvidenceUnresolved)` with the literal
- **AND** it SHALL NOT be holds

#### Scenario: Authored remains snapshot-scoped across valid days

- **WHEN** the same authored proposition is evaluated against the same snapshot at two different valid days
- **THEN** both valuations SHALL have the same truth and authored evidence
- **AND** each valuation SHALL retain its distinct context valid day
- **AND** each trace SHALL state that authored did not interpret a valid-time timeline

### Requirement: Yes-no questions SHALL expose a tri-valued answer space

`YesNoQuestion` SHALL retain its subject proposition and SHALL expose exactly yes, no, and undetermined as its exhaustive `Answer` cases. `answer(in: ValuationContext)` SHALL map `TruthValue.holds` to yes, `TruthValue.fails` to no, and every `TruthValue.undetermined` to undetermined. It SHALL return an `AnswerResult` containing the complete originating `Valuation` and SHALL NOT flatten the result to Bool or a tuple containing only bare truth.

#### Scenario: The answer space is exhaustive

- **WHEN** a caller reads `YesNoQuestion.answerSpace`
- **THEN** it SHALL contain yes, no, and undetermined exactly once
- **AND** it SHALL equal the complete set of Answer cases

#### Scenario: Evaluation remains tri-valued

- **WHEN** a subject valuation is holds, fails, or undetermined
- **THEN** answer SHALL be yes, no, or undetermined respectively
- **AND** `AnswerResult.valuation` SHALL equal the originating valuation

##### Example: Tri-valued answer mapping

| Valuation truth | Answer |
| --------------- | ------ |
| `holds` | `yes` |
| `fails` | `no` |
| `undetermined(noSupportingEvidence)` | `undetermined` |

#### Scenario: Answer propagation preserves audit context

- **WHEN** a question is answered from a context-bound valuation
- **THEN** snapshot identity, revision, valid day, and evidence trace SHALL be unchanged in the answer result

### Requirement: Fact acceptance SHALL be gated from recorded assertions

`Assertion` SHALL record a proposition, a `Stance`, source, and `RecordedTime` without itself asserting truth. `AcceptedFact` SHALL be a distinct type whose construction is restricted to adjudication. Adjudication SHALL consume an existing `Valuation`, SHALL verify that its proposition equals the assertion proposition, and SHALL accept only an asserted assertion whose valuation truth is holds. It SHALL reject a mismatched valuation, denied or questioned stance, and fails or undetermined truth. A successful fact SHALL retain the assertion, acceptedBy, `AcceptedTime`, and complete valuation. A `notEstablished` refusal SHALL retain the refused valuation.

#### Scenario: An established assertion becomes an accepted fact

- **WHEN** an asserted Assertion is adjudicated with a matching holds valuation
- **THEN** adjudication SHALL return an AcceptedFact retaining the assertion and valuation
- **AND** the result SHALL record acceptedBy and typed acceptedAt

#### Scenario: A question or denial cannot become a fact

- **WHEN** an Assertion has questioned or denied stance
- **THEN** adjudication SHALL throw stanceIsNotAssertion
- **AND** no AcceptedFact SHALL be created

#### Scenario: Uncertainty cannot become a fact

- **WHEN** an asserted Assertion is adjudicated with a matching undetermined valuation
- **THEN** adjudication SHALL throw notEstablished with that valuation
- **AND** no AcceptedFact SHALL be created

#### Scenario: A valuation for another proposition is refused

- **WHEN** the supplied valuation proposition differs from the assertion proposition
- **THEN** adjudication SHALL throw propositionMismatch
- **AND** no stance or truth result SHALL override that mismatch

#### Scenario: Fact retains three independent time roles

- **WHEN** an assertion recorded on one day is evaluated for another valid day and accepted on a third day
- **THEN** the AcceptedFact SHALL retain all three typed values through its basis and valuation
