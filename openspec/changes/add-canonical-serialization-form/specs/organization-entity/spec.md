## MODIFIED Requirements

### Requirement: Existing temporal dimensions SHALL be unaffected

Introducing a reference-or-literal value for affiliations SHALL NOT change the behaviour of the other temporal dimensions, which SHALL continue to carry plain text with an open value domain.

Timeline equality SHALL remain independent of storage order.

Round-tripping SHALL preserve bytes only for input that is already in canonical form. For input that is not, loading and re-encoding SHALL yield the canonical form of the same value, and re-encoding that result SHALL change nothing further.

The earlier unconditional byte-identity requirement was unsatisfiable: an encoder that imposes any order cannot return arbitrary input unchanged, and the store held records that violated it while every self-check passed.

#### Scenario: A rank timeline round-trips

- **WHEN** a person record in canonical form, carrying rank, administrative, appointment, and field timelines, is loaded and re-encoded
- **THEN** the result SHALL be byte-identical to the input
- **AND** two timelines holding the same entries in different orders SHALL compare equal

#### Scenario: A record not in canonical form converges

- **WHEN** a person record whose timelines are held out of canonical order is loaded and re-encoded
- **THEN** the result SHALL be the canonical form of that record
- **AND** loading and re-encoding that result SHALL be byte-identical to it

##### Example: Affiliations held newest-first

- **GIVEN** a person record holding an affiliation segment starting `2013-07` before one starting `2003-01`
- **WHEN** the record is loaded and re-encoded
- **THEN** the result SHALL differ from the input
- **AND** the segment starting `2003-01` SHALL appear first
- **AND** re-encoding that result SHALL leave it unchanged

#### Scenario: An organization's names keep their authored order

- **WHEN** an organization record whose names carry no validity ranges is loaded and re-encoded
- **THEN** the names SHALL appear in the order the record held them

##### Example: Aliases of a single institution

- **GIVEN** an organization record holding the names `中央研究院`, `Academia Sinica`, `中研院`, none carrying a range
- **WHEN** the record is loaded and re-encoded
- **THEN** the names SHALL appear in that same order

#### Scenario: An organization's historical names order by time

- **WHEN** an organization record holds names carrying distinct validity ranges
- **THEN** the names SHALL appear in ascending order of the start of their range

##### Example: An institute that was renamed

- **GIVEN** an organization record holding a name valid `1987-08` onward before a name valid `1982-07` to `1987-08`
- **WHEN** the record is loaded and re-encoded
- **THEN** the name valid from `1982-07` SHALL appear first
