## ADDED Requirements

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

## MODIFIED Requirements

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
