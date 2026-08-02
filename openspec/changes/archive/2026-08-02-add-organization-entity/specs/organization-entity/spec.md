## ADDED Requirements

### Requirement: An organization SHALL be a record shape of its own

The canonical entity namespace SHALL admit organization records. An organization record SHALL be marked by a bare shape label, and that label SHALL be added to the closed set of known shapes.

The organization identity field MAY reuse the name used by another shape, because the label already determines the shape.

An organization record SHALL be able to record its own name variants and its own history, independently of any person or work that refers to it.

#### Scenario: An organization is stored and reloaded

- **WHEN** an organization record is written to the canonical entity namespace and reloaded
- **THEN** it SHALL be decoded as an organization on the strength of its shape label alone
- **AND** re-encoding it SHALL produce a byte-identical file

#### Scenario: An organization is renamed

- **WHEN** an organization's name changes while the organization continues to exist
- **THEN** the record SHALL retain both names with their validity ranges
- **AND** references from person records SHALL remain valid without being rewritten

### Requirement: An affiliation SHALL be either a reference or a literal

The value of an affiliation entry SHALL be either a reference to an organization record or a literal string, and SHALL NOT be both.

An affiliation that has not been resolved to an organization SHALL be represented as a literal. The absence of a reference SHALL itself carry the information that the affiliation is unresolved; no separate flag field SHALL be introduced for that purpose.

#### Scenario: An unresolved affiliation is loaded

- **WHEN** a person record carries an affiliation recorded only as text
- **THEN** it SHALL load as a literal affiliation
- **AND** no field SHALL be required to declare that it is unresolved

#### Scenario: A resolved affiliation is exported

- **WHEN** a person's affiliation refers to an organization record and the store is exported to relational form
- **THEN** the exported row SHALL carry a non-null foreign key to that organization

#### Scenario: An affiliation refers to an organization that does not exist

- **WHEN** a person's affiliation names an organization identity that no record in the store defines
- **THEN** the export SHALL leave the foreign key null rather than fabricating an identifier
- **AND** the condition SHALL be reported by the diagnostic command

### Requirement: Membership and containment SHALL be distinct predicates

A person's membership in an organization and one organization's containment within another SHALL be recorded as two separate fields on two separate shapes, and SHALL NOT be merged into a single relation over a common supertype.

The fact that one word in natural language covers both SHALL NOT be treated as evidence that they are one predicate.

#### Scenario: An organization belongs to a larger organization

- **WHEN** an institute is part of a larger academy
- **THEN** the containment SHALL be recorded on the institute's own record
- **AND** it SHALL NOT be recorded using the field that records a person's membership

#### Scenario: An affiliation is proposed for a work

- **WHEN** a contributor attempts to record an institutional affiliation on a work
- **THEN** no field SHALL exist on the work shape to hold it
- **AND** the institutional attribution of a work SHALL be obtainable only by joining through its authors' affiliations at the relevant time

### Requirement: Resolution SHALL be biased toward splitting

When it is uncertain whether two affiliation strings name the same organization, the store SHALL default to treating them as two organizations rather than one.

Migration of existing affiliation text SHALL produce literals only, and SHALL NOT merge any two strings automatically.

#### Scenario: Two spellings might name the same organization

- **WHEN** two affiliation literals differ in wording and it is not established that they name the same organization
- **THEN** they SHALL remain separate
- **AND** merging them later SHALL remain possible because both histories are still present

### Requirement: Existing temporal dimensions SHALL be unaffected

Introducing a reference-or-literal value for affiliations SHALL NOT change the behaviour of the other temporal dimensions, which SHALL continue to carry plain text with an open value domain.

Timeline equality SHALL remain independent of storage order.

#### Scenario: A rank timeline round-trips

- **WHEN** a person record carrying rank, administrative, appointment, and field timelines is loaded and re-encoded
- **THEN** the result SHALL be byte-identical to the input
- **AND** two timelines holding the same entries in different orders SHALL compare equal
