## ADDED Requirements

### Requirement: Canonical proposition models SHALL reject ambiguous identity keys

`PropositionModel.init(entries:people:)` SHALL reject construction before creating identity dictionaries when the supplied entries contain duplicate citekeys or the supplied people contain duplicate keys. The rejection SHALL report the complete deduplicated and ascending-sorted duplicate entry citekeys and duplicate person keys in one equatable error. Swift-equal canonical-equivalent spellings SHALL use a raw-UTF-8-stable representative so the machine payload bytes remain independent of input order. Its localized description and default Swift error rendering SHALL report each class total, display at most the first five ascending-sorted keys from each class, state the omitted count, and sanitize every displayed key with `displaySafe(max: 120)` without truncating either machine-readable payload. The implementation SHALL NOT select a first or last record for a duplicate key.

#### Scenario: Duplicate entry and person keys are rejected together

- **WHEN** model input contains two entries with citekey `work-a` and two people with key `person-a`
- **THEN** construction SHALL throw an error with duplicate entry citekeys `["work-a"]` and duplicate person keys `["person-a"]`
- **AND** no `PropositionModel` SHALL be created

##### Example: Both duplicate classes are preserved

| Entries | People | Expected error payload |
| ------- | ------ | ---------------------- |
| `[work-a, work-a]` | `[person-a, person-a]` | entries `[work-a]`, people `[person-a]` |
| `[work-b, work-a, work-b, work-a]` | `[person-b, person-b]` | entries `[work-a, work-b]`, people `[person-b]` |

#### Scenario: Duplicate rejection is independent of input order

- **WHEN** the same conflicting entry or person records are supplied in forward and reverse order
- **THEN** both constructions SHALL throw equal validation errors
- **AND** neither order SHALL produce a truth-bearing model

##### Example: Supporting and non-supporting duplicates

- **GIVEN** one `work-a` entry contains author `person-a` and another `work-a` entry contains no matching author
- **WHEN** model construction receives `[supporting, non-supporting]` and `[non-supporting, supporting]`
- **THEN** both attempts SHALL throw the same payload with duplicate entry citekeys `["work-a"]`

#### Scenario: Unique identity keys remain accepted

- **WHEN** every entry citekey is unique and every person key is unique
- **THEN** model construction SHALL succeed
- **AND** each input SHALL be retrievable by its canonical key

##### Example: One canonical work and person

- **GIVEN** one entry with citekey `work-a` and one person with key `person-a`
- **WHEN** model construction receives those inputs
- **THEN** `entriesByKey["work-a"]` and `peopleByKey["person-a"]` SHALL contain the supplied values

#### Scenario: Large duplicate sets retain complete payloads and bounded diagnostics

- **WHEN** model input contains 20 distinct duplicate entry citekeys and 17 distinct duplicate person keys
- **THEN** the validation error SHALL retain all 20 entry citekeys and all 17 person keys in its sorted machine-readable payloads
- **AND** its localized description SHALL display only the first five keys from each class and SHALL state both total and omitted counts
- **AND** caller-controlled control or direction characters in either displayed class SHALL be sanitized

#### Scenario: Default error rendering cannot expose raw payloads

- **WHEN** a duplicate-model error is rendered through `String(describing:)`, string interpolation, or debug reflection
- **THEN** rendering SHALL equal the bounded localized description
- **AND** it SHALL NOT expose raw direction characters or every machine-payload key

#### Scenario: Canonical-equivalent duplicate spelling is byte-stable

- **WHEN** a model receives canonically equivalent NFC and NFD spellings in forward and reverse order
- **THEN** both errors SHALL retain one equal-class representative with identical UTF-8 bytes
- **AND** neither input order SHALL determine the representative

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
