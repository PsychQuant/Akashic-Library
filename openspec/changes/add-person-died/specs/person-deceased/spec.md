## ADDED Requirements

### Requirement: A person record SHALL be able to record that the person is deceased

A person record SHALL carry an optional `died` field holding the date of the person's death as an ISO 8601 prefix string. The field SHALL be absent when no death has been recorded; an empty string or an explicit null placeholder SHALL NOT be written.

A value that is empty or consists only of whitespace SHALL be normalised to absence at every boundary through which a record enters the model — both decoding and construction. It SHALL NOT be retained, SHALL NOT be written back, and SHALL NOT be read as a recorded death. An empty value carries no information, and both readings a contributor might intend by it resolve to absence: "it is unknown whether this person has died" is what absence already means, and "this person has died but the date is unknown" is the unrepresentable case that MUST go in the note field rather than a placeholder value. The empty string is never a valid ISO 8601 prefix, so normalising it discards no expressible fact.

`died` SHALL be registered in the set of known person keys. A field present in the record shape but absent from that set is retained twice — once by the shape and once by the tolerant-preserve mechanism — and emitted twice on write.

#### Scenario: A death date is recorded and read back

- **WHEN** a person record is written with a `died` value and then loaded
- **THEN** the value SHALL be returned unchanged
- **AND** the record SHALL NOT be quarantined

#### Scenario: No death has been recorded

- **WHEN** a person record carries no `died` field
- **THEN** loading SHALL succeed
- **AND** the absence SHALL NOT be an error, and SHALL NOT be inferred or guessed

#### Scenario: The field is registered against duplicate emission

- **WHEN** a person record carrying `died` is loaded and written back unchanged
- **THEN** the emitted document SHALL contain exactly one `died` key

#### Scenario: An empty value is normalised to absence

- **WHEN** a person record carries `died` whose value is empty or whitespace-only, by either decoding or construction
- **THEN** the loaded record SHALL report no death date
- **AND** writing the record back SHALL emit no `died` key
- **AND** the record SHALL NOT appear in any report of deceased persons

#### Scenario: A non-scalar value is rejected

- **WHEN** a person record contains `died` whose value is a sequence or a mapping
- **THEN** decoding SHALL fail with an error naming the field

### Requirement: Recorded precision SHALL be preserved exactly as written

The `died` value SHALL be stored and returned as the ISO 8601 prefix string that was written. A year-only or year-month value SHALL NOT be completed into a full date at any layer.

Precision carries meaning: the width of the prefix is the width of the interval within which the death is known to have occurred. Completing `2004` into `2004-01-01` asserts a day that no source stated.

#### Scenario: Each supported precision survives a round trip

- **WHEN** a person record is written with a `died` value at year, year-month, or year-month-day precision and then loaded
- **THEN** the loaded value SHALL be byte-identical to the written value

##### Example: The three admissible precisions

| Written | Loaded | Interval the value asserts |
| ------- | ------ | -------------------------- |
| `2004` | `2004` | some time during 2004 |
| `2004-11` | `2004-11` | some time during November 2004 |
| `2004-11-18` | `2004-11-18` | that day |

### Requirement: The absence of a death date SHALL be read as right-censored, not as living

An absent `died` field SHALL mean that no death has been observed within the store's record. It SHALL NOT be read as an assertion that the person is living.

Absence therefore covers two situations that the data cannot separate: the person is living, and the person has died without the death having been recorded. This is the definition of right censoring and SHALL NOT be treated as a defect of the format. A recorded `died` value at any precision is an observed event bounded on both sides; an absent value is an observation bounded below only.

Because death is universal, absence SHALL NOT be read as the field being inapplicable. Every person has a death; the field records whether it has been observed. Absence is therefore a complete state — censored — and not a gap in the record.

Absence SHALL admit no reading other than censoring. Death is a sharply bounded event: a person does not partly die, and does not become part of another person. Where an analogous field records the end of an entity whose ending is not sharply bounded — an organization that merges, is absorbed, or is refounded — absence can additionally conceal an undecided question of identity, and such a question belongs in a divergence record rather than in a date field. No such reading applies here.

The case of an observed death whose date is entirely unknown — an event known to have occurred with no bound on when — SHALL NOT be representable by this field. It is the only state this capability leaves unexpressible: a censored observation is complete, a bounded observed event is complete, and only the unbounded observed event has no representation. That case belongs to the separate question of expressing "ended, date unknown", which this capability does not address.

#### Scenario: A consumer asks whether a person is alive

- **WHEN** a consumer reads a person record with no `died` field
- **THEN** the correct reading SHALL be "no death recorded", not "living"

#### Scenario: A death is known but its date is not

- **WHEN** a contributor knows that a person has died but has no date at any precision
- **THEN** the `died` field SHALL NOT be populated with a fabricated or placeholder date
- **AND** the situation SHALL be recorded in the person's note field until an unbounded-interval representation exists

### Requirement: A death date SHALL NOT alter any derivation that describes affiliation

The affiliation-derived status of a person SHALL be computed from the affiliation timeline alone. The presence, absence, or value of `died` SHALL NOT change it.

Death and affiliation are orthogonal facts. A person whose affiliation ended is `retired` with respect to that affiliation regardless of whether the affiliation ended by resignation, by transfer, or by death.

#### Scenario: A person who died in office

- **WHEN** a person record has a `died` value and an affiliation segment whose end coincides with it
- **THEN** the derived affiliation status SHALL be `retired`, exactly as it was before `died` existed

##### Example: A director who died in post

- **GIVEN** a person with an affiliation segment running from `1990-09` to `2004-11` and `died` set to `2004-11-18`
- **WHEN** the relational export is produced
- **THEN** the status column SHALL read `retired`
- **AND** the died column SHALL read `2004-11-18`

#### Scenario: A living person with an open affiliation

- **WHEN** a person record has no `died` value and one open affiliation segment
- **THEN** the derived affiliation status SHALL be `current`

### Requirement: Academic activity SHALL NOT be recorded as a stored field

No field, derivation function, or exported column asserting whether a person remains academically active SHALL be added.

Activity has no non-arbitrary threshold, so recording it would store a stipulation as if it were a fact. The exported publication table already carries dates, from which a consumer computes a latest-publication year directly. A stored activity field would be recomputable from data the consumer already holds, and deleting it would break nothing.

#### Scenario: A consumer needs to know who is still publishing

- **WHEN** a consumer wants the latest publication year per researcher
- **THEN** it SHALL be computed from the exported publication table
- **AND** no stored field SHALL be consulted

### Requirement: A deceased person retaining an open affiliation SHALL be reported and SHALL NOT be corrected

Diagnostics SHALL report person records that carry a `died` value while at least one affiliation segment remains open. The report SHALL list the record keys in lexicographic order.

The reported records SHALL NOT be modified. Closing an affiliation at the death date is an inference, and that inference can be wrong: a person who left the institution years before dying produces the same open segment, which is then a missing end date rather than a death in office.

This condition SHALL NOT be an error. It SHALL NOT quarantine the record and SHALL NOT block loading.

#### Scenario: The contradiction is surfaced

- **WHEN** diagnostics run against a store containing a person with `died` set and an open affiliation segment
- **THEN** that person's key SHALL appear in the report

#### Scenario: The record is left untouched

- **WHEN** diagnostics have run against such a store
- **THEN** the person record SHALL be byte-identical to its state before the run

#### Scenario: Loading is not blocked

- **WHEN** a store containing such a record is loaded
- **THEN** loading SHALL succeed and the record SHALL NOT be quarantined

### Requirement: Adding the death field SHALL NOT change the supported store format version

The supported store format version SHALL remain unchanged by this capability.

Adding a field is an additive change. An older binary retains an unrecognised field verbatim through the tolerant-preserve mechanism and therefore cannot interpret new data under an older meaning, which is the condition that requires a version bump. Bumping on every additive change would force all binaries to upgrade in lockstep and would defeat tolerant-preserve.

#### Scenario: An older binary reads a store containing death dates

- **WHEN** a binary that does not recognise `died` loads a person record carrying it, then writes the record back
- **THEN** the `died` value SHALL survive unchanged

#### Scenario: The version constant is unchanged

- **WHEN** this capability has shipped
- **THEN** the supported store format version SHALL equal its value before the change

### Requirement: The relational export SHALL expose the death date and SHALL state what its status column describes

The exported researcher table SHALL include a `died` column carrying the recorded death date, or NULL where none is recorded.

The export SHALL state, in the exported schema description rather than only in source comments, that its status column describes **affiliation** and describes neither academic activity nor whether the person is living.

#### Scenario: The death date reaches a downstream consumer

- **WHEN** the researcher table is exported from a store containing recorded death dates
- **THEN** each such person's row SHALL carry the date in the `died` column
- **AND** rows for persons with no recorded death SHALL carry NULL

#### Scenario: A consumer reads the schema description

- **WHEN** a consumer inspects the exported schema for the status column
- **THEN** the description SHALL state that the column describes affiliation
