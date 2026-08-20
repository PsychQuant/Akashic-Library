## ADDED Requirements

### Requirement: An identifier SHALL settle reference, not description

An identifier assigned by a registration authority SHALL be sufficient to settle which entity is referred to. The same identifier SHALL NOT be treated as evidence that the fields accompanying it are correct.

This distinguishes identifiers from names. A name does not settle reference and requires judgement; an identifier settles reference and requires no judgement. Neither guarantees that the attached facts are correct.

#### Scenario: Two records carry the same identifier

- **WHEN** two work records carry the same DOI
- **THEN** the store SHALL treat them as referring to the same work
- **AND** the store SHALL NOT require a disambiguation judgement for that pairing

#### Scenario: An identifier accompanies a field value that is wrong

- **WHEN** a record's identifier resolves to an authority record whose affiliation string is misspelled by the publisher
- **THEN** the identifier SHALL still settle which work is referred to
- **AND** the misspelled field value SHALL NOT be treated as correct by virtue of the identifier being correct

##### Example: Identifier settles reference while a field remains wrong

| Fact | Settled by identifier? |
| ---- | ---------------------- |
| Which work this record refers to | yes |
| Whether the affiliation reads `Institute of Statistical Science` or `Institute of Statistical Sciences` | no |

### Requirement: An identifier SHALL live on the entity it identifies

An identifier SHALL be stored as a named top-level field of the record for the entity that the registration authority assigned it to. An identifier SHALL NOT be stored on a record for a different entity merely because that record has a place to put it.

#### Scenario: A serial identifier is stored on a work record

- **WHEN** a work record carries an ISSN
- **THEN** the store SHALL treat that as a misplacement, because ISSN identifies the serial and not the article
- **AND** the ISSN SHALL be stored on the venue record that the work's venue edge names

##### Example: ISSN moves from work to venue

- **GIVEN** 64 work records each carrying an `issn` field, all 64 naming an already-resolved venue edge
- **WHEN** identifiers are placed on the entity they identify
- **THEN** the count of work records carrying `issn` SHALL become 0
- **AND** the 39 distinct venues named by those edges SHALL carry the ISSN values instead

### Requirement: An identifier value SHALL be typed

An identifier SHALL be represented by a type that validates its shape and defines its normal form. A free-text field SHALL NOT satisfy this requirement.

#### Scenario: A malformed identifier reaches the write path

- **WHEN** a caller writes an identifier whose shape does not match its kind
- **THEN** the store SHALL reject the write
- **AND** the error SHALL name the rejected value and the expected shape for that kind

#### Scenario: A malformed identifier already exists in the store

- **WHEN** a record read from disk carries an identifier value that does not match the normal form
- **THEN** the store SHALL load the record and preserve the value
- **AND** `akashic validate` SHALL emit a diagnostic naming the record and the value

##### Example: Values that a typed ISSN accepts, normalizes, or rejects

| Input | Outcome | Reason |
| ----- | ------- | ------ |
| `0003-066X` | accepted as-is | already in normal form |
| `0003-066x` | normalized to `0003-066X` | ISSN check digit `X` is uppercase |
| `1467-8624(Electronic),0009-3920(Print)` | rejected on write | two identifiers in one value |
| `12345` | rejected on write | shape is not `NNNN-NNNN` |

### Requirement: Identifier cardinality SHALL be decided per kind

Each identifier kind SHALL declare whether an entity carries at most one of it or a list of them. A single cardinality SHALL NOT be imposed across all kinds.

#### Scenario: A serial carries both a print and an electronic identifier

- **WHEN** a venue has both a print ISSN and an electronic ISSN
- **THEN** the venue record SHALL carry both
- **AND** neither SHALL be discarded in favour of the other

##### Example: Cardinality by kind

| Kind | Cardinality | Evidence |
| ---- | ----------- | -------- |
| ORCID | at most one per person | one iD per person by definition |
| ROR | at most one per organization | one record per organization by definition |
| ISSN | list per venue | `1554-351X` and `1554-3528` are the print and electronic ISSNs of one journal |
| DOI | list per work | 37 groups of work records share title and year while carrying different DOIs |
| PMID | list per work | a biomedical article carries a PMID alongside its DOI |
| ISBN | list per work | one work has separate ISBNs across editions |

### Requirement: Normalization SHALL occur on the write path only

An identifier SHALL be normalized when it is written. The read path SHALL accept and preserve values that are not in normal form.

#### Scenario: A stored value is not in normal form

- **WHEN** a record carrying `0003-066x` is read
- **THEN** the store SHALL return the record with the value preserved
- **AND** the store SHALL NOT quarantine the record

#### Scenario: A provenance reference points at a value that migration rewrites

- **WHEN** migration rewrites an identifier value to its normal form
- **THEN** migration SHALL rewrite the `value` of every provenance reference pointing at the old value in the same write
- **AND** no provenance reference SHALL be left naming a value absent from the record

### Requirement: Identifier equality SHALL be admissible as an identity judgement

The rule that identity is judged and not matched SHALL carry a closed exception naming the identifier kinds whose equality alone settles identity. That exception SHALL name DOI, PMID, ISBN, ISSN, ORCID, and ROR, and SHALL state that no further kind is admissible by analogy.

#### Scenario: Two records are paired by identifier equality

- **WHEN** two records carry equal DOIs
- **THEN** pairing them SHALL NOT require the evidence-beyond-the-name discipline that name-based pairing requires

#### Scenario: A locator is proposed as an identifier

- **WHEN** a URL is proposed as grounds for an identity judgement
- **THEN** it SHALL be refused, because a URL names a location rather than a registered identity

##### Example: What the closed exception covers

| Value kind | Admissible for identity judgement | Reason |
| ---------- | --------------------------------- | ------ |
| DOI, PMID, ISBN, ISSN, ORCID, ROR | yes | assigned by a registration authority |
| `url` | no | names a location, not a registered identity |
| Zotero item key | no | names a row in one user's local library |
