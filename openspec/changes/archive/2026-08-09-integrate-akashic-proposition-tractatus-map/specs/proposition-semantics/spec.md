## ADDED Requirements

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

### Requirement: Projection SHALL preserve identity resolution and role direction

Proposition.project(in:) SHALL return Projection.projected only when the person argument resolves to a Person and the work argument resolves to an Entry in the supplied PropositionModel. It SHALL return Projection.unprojectable with a specific UnprojectableReason for an unresolved literal, an unknown identity, or a key that resolves to the wrong entity kind. Person and work roles SHALL NOT be interchangeable.

#### Scenario: Both arguments resolve with the correct kinds

- **WHEN** authored refers to a known Person key in the person role and a known Entry key in the work role
- **THEN** projection SHALL return the resolved Person and Entry

##### Example: Fully resolved projection

- **GIVEN** Person `cheng-che` and Entry `cheng2025identifiability` in the model
- **WHEN** those keys occupy the person and work roles respectively
- **THEN** projection SHALL return projected(person: `cheng-che`, work: `cheng2025identifiability`)

#### Scenario: A literal remains unresolved

- **WHEN** either proposition role contains EntityRef.literal
- **THEN** projection SHALL return unresolvedSymbol with that role and literal
- **AND** projection SHALL NOT claim an identity match

##### Example: Unresolved person symbol

- **GIVEN** person literal `Che Cheng` and a resolved work key
- **WHEN** the proposition is projected
- **THEN** the reason SHALL be unresolvedSymbol(role: `person`, literal: `Che Cheng`)

#### Scenario: Reversed entity kinds are diagnosed

- **WHEN** an Entry key occupies the person role or a Person key occupies the work role
- **THEN** projection SHALL return wrongEntityKind for the affected role

##### Example: Work key in the person role

- **GIVEN** `cheng2025identifiability` resolves only as an Entry
- **WHEN** it occupies the person role
- **THEN** the reason SHALL be wrongEntityKind(role: `person`, expected: `person`)

### Requirement: Evaluation SHALL preserve open-world uncertainty

TruthValue SHALL provide holds, fails, and undetermined states. The authored evaluator SHALL return holds only when the projected work contains the projected person key in an author slot. An unprojectable proposition SHALL return undetermined with notProjectable. A matching unresolved author literal SHALL return undetermined with supportingEvidenceUnresolved. Absence of supporting author identity SHALL return undetermined with noSupportingEvidence. The current authored evaluator SHALL NOT produce fails because the model has no positive author-list completeness evidence.

#### Scenario: Resolved supporting evidence establishes authored

- **WHEN** the projected work contains an author key equal to the projected person key
- **THEN** evaluate(in:) SHALL return holds

##### Example: Matching author identity

- **GIVEN** work `cheng2025identifiability` has author key `cheng-che`
- **WHEN** authored(person: `cheng-che`, work: `cheng2025identifiability`) is evaluated
- **THEN** the truth value SHALL be holds

#### Scenario: Absence is not false

- **WHEN** the work contains no matching resolved author key
- **THEN** evaluate(in:) SHALL return undetermined
- **AND** evaluate(in:) SHALL NOT return fails

##### Example: Different author does not prove falsity

- **GIVEN** the work contains only author key `someone-else`
- **WHEN** the proposition asks whether `cheng-che` authored that work
- **THEN** the truth value SHALL be undetermined(noSupportingEvidence)

#### Scenario: A matching literal is not accepted as identity

- **WHEN** an unresolved author literal normalizes to one of the person's names
- **THEN** evaluate(in:) SHALL return supportingEvidenceUnresolved with the literal
- **AND** evaluate(in:) SHALL NOT return holds

##### Example: Name match without identity

- **GIVEN** Person `cheng-che` has name `Che Cheng` and the work has author literal `Che Cheng`
- **WHEN** authored is evaluated
- **THEN** the truth value SHALL be undetermined(supportingEvidenceUnresolved(`Che Cheng`))

### Requirement: Yes-no questions SHALL expose a tri-valued answer space

YesNoQuestion SHALL retain its subject proposition and SHALL expose exactly yes, no, and undetermined as its exhaustive Answer cases. answer(in:) SHALL map TruthValue.holds to yes, TruthValue.fails to no, and every TruthValue.undetermined value to undetermined while preserving the full TruthValue alongside the answer. It SHALL NOT flatten the result to Bool.

#### Scenario: The answer space is exhaustive

- **WHEN** a caller reads YesNoQuestion.answerSpace
- **THEN** it SHALL contain yes, no, and undetermined exactly once
- **AND** it SHALL equal the complete set of Answer cases

##### Example: Three exhaustive labels

- **GIVEN** any authored subject
- **WHEN** answerSpace is read
- **THEN** its value SHALL be `[yes, no, undetermined]`

#### Scenario: Evaluation remains tri-valued

- **WHEN** a subject evaluates to holds or undetermined
- **THEN** answer(in:) SHALL return yes or undetermined respectively
- **AND** it SHALL preserve the originating TruthValue

##### Example: Supported and unsupported subjects

| Subject truth | Answer |
| ------------- | ------ |
| `holds` | `yes` |
| `undetermined(noSupportingEvidence)` | `undetermined` |

### Requirement: Fact acceptance SHALL be gated from recorded assertions

Assertion SHALL record a proposition, a Stance, source, and recorded timestamp without itself asserting truth. AcceptedFact SHALL be a distinct type whose construction is restricted to adjudicate. adjudicate SHALL accept only an Assertion with stance asserted whose proposition evaluates to holds. It SHALL reject denied or questioned stances with stanceIsNotAssertion and SHALL reject fails or undetermined truth with notEstablished.

#### Scenario: An established assertion becomes an accepted fact

- **WHEN** an asserted Assertion evaluates to holds
- **THEN** adjudicate SHALL return an AcceptedFact that retains the assertion as its basis
- **AND** the result SHALL record acceptedBy and acceptedAt

##### Example: Accepted supported assertion

- **GIVEN** an asserted authored proposition that evaluates to holds
- **WHEN** `che` adjudicates it at `2026-08-09`
- **THEN** the fact SHALL retain that assertion, `che`, and `2026-08-09`

#### Scenario: A question or denial cannot become a fact

- **WHEN** an Assertion has questioned or denied stance
- **THEN** adjudicate SHALL throw stanceIsNotAssertion
- **AND** no AcceptedFact SHALL be created

##### Example: Non-asserting stances

| Stance | Expected refusal |
| ------ | ---------------- |
| `questioned` | `stanceIsNotAssertion(questioned)` |
| `denied` | `stanceIsNotAssertion(denied)` |

#### Scenario: Uncertainty cannot become a fact

- **WHEN** an asserted Assertion evaluates to undetermined
- **THEN** adjudicate SHALL throw notEstablished
- **AND** no AcceptedFact SHALL be created

##### Example: Missing support remains unaccepted

- **GIVEN** an asserted authored proposition with no supporting author identity
- **WHEN** it is adjudicated
- **THEN** the refusal SHALL be notEstablished(undetermined(noSupportingEvidence))
