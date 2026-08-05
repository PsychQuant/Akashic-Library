## ADDED Requirements

### Requirement: Serialization order SHALL be governed by time alone

The byte order in which a timeline's entries are written SHALL be determined by their date ranges. Entries whose ranges compare equal SHALL retain the relative order in which they are held, and SHALL NOT be reordered by their values.

Timeline equality SHALL continue to use a total order that breaks ties by value. The comparison used for equality and the comparison used for serialization are distinct; neither SHALL be defined in terms of the other.

The serialization order SHALL be produced by a construction that guarantees stability explicitly. It SHALL NOT rely on the stability of any sort whose stability the standard library does not guarantee.

#### Scenario: A timeline carrying dates is written in chronological order

- **WHEN** a timeline holding entries with distinct start dates is encoded
- **THEN** the entries SHALL appear in ascending order of start date

##### Example: Two affiliation segments held newest-first

- **GIVEN** an affiliations timeline holding, in this order, a segment starting `2013-07` and a segment starting `2003-01`
- **WHEN** the record is encoded
- **THEN** the segment starting `2003-01` SHALL be written first

#### Scenario: A timeline carrying no dates keeps its held order

- **WHEN** a timeline whose entries all lack a start date is encoded
- **THEN** the entries SHALL appear in the order they are held

##### Example: Organization aliases with no validity ranges

- **GIVEN** a names timeline holding, in this order, `中央研究院`, `Academia Sinica`, `中研院`, none carrying a range
- **WHEN** the record is encoded
- **THEN** the names SHALL be written in that same order

#### Scenario: Undated entries sort after dated ones

- **WHEN** a timeline mixes entries with and without a start date
- **THEN** the entries carrying a start date SHALL be written first, in ascending order, and the undated entries SHALL follow in their held order

##### Example: Mixed timeline

| Held order | Written order |
| ---------- | ------------- |
| `B` (no start), `A` (start `2000`) | `A` (start `2000`), `B` (no start) |

#### Scenario: Equality remains blind to storage order

- **WHEN** two timelines hold the same entries in different orders
- **THEN** they SHALL compare equal
- **AND** the change in serialization order SHALL NOT alter this outcome

---

### Requirement: Normalization SHALL be reachable from a command

The system SHALL offer a command that rewrites records into the canonical byte form, and a mode of that command that reports deviation without writing.

The reporting mode SHALL NOT open any file for writing.

The command SHALL derive the canonical form by decoding and re-encoding each record through the same encoders the store already uses to write. It SHALL NOT define the canonical form a second time.

#### Scenario: Reporting mode finds deviation

- **WHEN** the command runs in reporting mode over a store holding records whose bytes differ from their canonical form
- **THEN** it SHALL name each deviating record
- **AND** it SHALL exit with a non-zero code
- **AND** no file SHALL have been modified

#### Scenario: Reporting mode finds nothing

- **WHEN** the command runs in reporting mode over a store whose records are all in canonical form
- **THEN** it SHALL exit with code zero

#### Scenario: Rewriting mode aligns the store

- **WHEN** the command runs without the reporting flag over a store holding deviating records
- **THEN** each deviating record SHALL be overwritten with its canonical form
- **AND** the command SHALL name every record it overwrote
- **AND** a subsequent run in reporting mode SHALL exit with code zero

#### Scenario: An unreadable record does not stop the run

- **WHEN** a record cannot be decoded or its re-encoding is refused by the encoder's self-check
- **THEN** the command SHALL name that record and the reason
- **AND** it SHALL continue processing the remaining records
- **AND** it SHALL exit with a non-zero code
- **AND** no bytes SHALL have been written for that record

---

### Requirement: Normalization SHALL reach a fixed point in one pass

Applying normalization to any record the store can decode SHALL yield bytes that are themselves canonical. A second application SHALL produce byte-identical output to the first.

#### Scenario: Normalizing twice changes nothing the second time

- **WHEN** a record is normalized, and the result is normalized again
- **THEN** the two results SHALL be byte-identical

##### Example: A record held in reverse chronological order

- **GIVEN** a person record whose affiliations are held newest-first
- **WHEN** it is normalized once, producing output `X`
- **AND** `X` is normalized again, producing output `Y`
- **THEN** `X` SHALL differ from the original record
- **AND** `Y` SHALL be byte-identical to `X`

---

### Requirement: Order-bearing sequences SHALL be excluded from reordering

Sequences whose position carries meaning SHALL be written in the order they are held, and SHALL NOT be subject to any ordering rule. The authors of a work are such a sequence: position distinguishes first author from the rest.

#### Scenario: Author order survives normalization

- **WHEN** a work record carrying several authors is normalized
- **THEN** the authors SHALL appear in the order they were held
