## ADDED Requirements

### Requirement: An identifier field SHALL be attachable

The set of named fields a reference is attachable to SHALL include the identifier fields of every entity kind that carries them. An identifier that cannot carry a reference SHALL NOT be treated as a first-class field of the record.

Recording where an identifier came from is what distinguishes a first-class identifier from a string stored at the top level of a record. A venue whose ISSN cannot name its source leaves no way to tell a value read from the ISSN portal apart from a value typed by hand.

#### Scenario: A venue identifier names its source

- **WHEN** a venue record carries an ISSN obtained from the ISSN portal
- **THEN** the record SHALL be able to carry a reference naming the `issn` field and that source

#### Scenario: A reference names an identifier field the record does not carry

- **WHEN** a reference names an identifier field absent from the record
- **THEN** the store SHALL reject the record with an error naming the field

##### Example: Identifier fields attachable per entity kind

| Entity kind | Attachable identifier fields |
| ----------- | ---------------------------- |
| person | `orcid`, `openalex` |
| work | `doi`, `pmid`, `isbn` |
| venue | `issn` |
| organization | `ror` |

### Requirement: A reference to a list-valued identifier SHALL name which value it supports

A reference attached to an identifier field that holds a list SHALL carry a `value` naming which entry in that list it supports. A reference attached to an identifier field that holds at most one value SHALL NOT carry a `value`.

This mirrors the existing split between list fields and scalar fields: a record-level reference that does not say which of several identifiers it supports leaves the remaining identifiers unsourced while appearing sourced.

#### Scenario: A venue carries two ISSNs from different sources

- **WHEN** a venue carries a print ISSN and an electronic ISSN obtained from different sources
- **THEN** each reference SHALL name the `issn` field and carry the `value` it supports

##### Example: A venue with two sourced ISSNs

- **GIVEN** a venue carrying `1554-351X` and `1554-3528`
- **WHEN** each value is sourced separately
- **THEN** two references SHALL exist, each naming field `issn`, one carrying value `1554-351X` and the other carrying value `1554-3528`

#### Scenario: A reference to a scalar identifier carries a value

- **WHEN** a reference names a scalar identifier field and carries a `value`
- **THEN** the store SHALL reject it with an error stating that `value` positions a reference within a list field

#### Scenario: A reference names a value absent from the identifier list

- **WHEN** a reference names an identifier field and carries a `value` that is not among the identifiers the record holds
- **THEN** the store SHALL reject the record with an error naming the orphaned value
