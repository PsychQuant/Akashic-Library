## MODIFIED Requirements

### Requirement: An entity SHALL designate which of its names are addressed outward

A record's names SHALL be partitioned into *authorized names* — the names by which the entity is addressed in output intended for people — and *variant names*. Both partitions are sets of access points; the distinction between them is which one is addressed outward.

The partition SHALL be structural. A name SHALL occupy exactly one partition, and the union of the two partitions SHALL be the record's names. It SHALL NOT be possible to express an authorized name that is not a name of the record, because there is no position in which such a string could be written.

Designation SHALL NOT depend on position. A name's index within its partition SHALL NOT determine whether it is addressed outward; membership in the authorized partition is the designation.

Either partition MAY be empty. A record whose authorized partition is empty is well-formed.

The union SHALL be ordered with the authorized partition first, so that a consumer asking for "any name" receives a designated one when a designation exists.

#### Scenario: A record designates two of its names

- **WHEN** a record's authorized partition contains `謝叔蓉` and `Shwu-Rong Grace Shieh`, and its variant partition contains `Shieh, Grace S.`
- **THEN** validation SHALL accept the record
- **AND** re-encoding it SHALL produce a byte-identical file
- **AND** the union of its names SHALL be `謝叔蓉`, `Shwu-Rong Grace Shieh`, `Shieh, Grace S.` in that order

#### Scenario: A designation cannot name a string the record does not carry

- **WHEN** a caller attempts to designate `Grace Shieh` as authorized for a record whose names are `謝叔蓉` and `Shwu-Rong Grace Shieh`
- **THEN** the attempt SHALL be unrepresentable, because designating a string places it in the authorized partition and thereby makes it one of the record's names
- **AND** validation SHALL NOT be required to detect this case

#### Scenario: A record designates nothing

- **WHEN** a record's authorized partition is empty and its variant partition contains `Guan, Yongtao`
- **THEN** validation SHALL accept the record
- **AND** the record SHALL be reportable as carrying no authorized name

#### Scenario: The serialized form carries each name once

- **WHEN** a record carrying both authorized and variant names is serialized
- **THEN** each name SHALL appear exactly once in the serialized form

##### Example: A person with two designations and one variant

- **GIVEN** a person whose authorized names are `梁佑任` and `Yu-Jen Liang`, and whose variant name is `Liang, Yu-Jen`
- **WHEN** the record is serialized
- **THEN** the names section SHALL contain an authorized subsection listing `梁佑任` and `Yu-Jen Liang`, and a variant subsection listing `Liang, Yu-Jen`
- **AND** no name SHALL appear in both subsections

### Requirement: At most one name per writing system SHALL be authorized

Within a single record, the authorized names SHALL be distinct in writing system. Two authorized names in the same writing system express an undecided question, not a designation, and SHALL be rejected.

This constraint is about the *content* of the authorized partition, not its structure, so it SHALL be enforced when a record is written rather than by the shape of the record. A record whose authorized partition contains two names in one writing system is expressible; it SHALL NOT be storable.

The writing system of a name SHALL be derived from the string, and SHALL NOT be stored. The derivation SHALL distinguish only as many writing systems as are needed to partition the names of one entity.

#### Scenario: Two authorized names share a writing system

- **WHEN** a record whose authorized partition contains both `Shwu-Rong Grace Shieh` and `Shieh, Grace S.` is written
- **THEN** the write SHALL be rejected
- **AND** the message SHALL name the writing system and both candidates

#### Scenario: Two authorized names in different writing systems

- **WHEN** a record whose authorized partition contains `謝叔蓉` and `Shwu-Rong Grace Shieh` is written
- **THEN** the write SHALL be accepted

#### Scenario: The constraint is enforced on every write path

- **WHEN** any path that persists a record attempts to write one violating this constraint
- **THEN** the write SHALL be rejected regardless of which path attempted it

#### Scenario: Writing system is derived, not declared

- **WHEN** a name containing unified ideographs is examined
- **THEN** its writing system SHALL be reported as the ideographic one
- **AND** a name written in basic Latin letters SHALL be reported as the Latin one

### Requirement: Removing the positional convention SHALL bump the store format marker

Changing the shape in which names are recorded SHALL raise the store format marker, because a reader that does not understand the new shape SHALL NOT silently misread it.

A record written in the partitioned shape SHALL NOT be written to a store whose format marker predates that shape; the write SHALL be refused with a message stating what must be upgraded first. Raising the marker SHALL be an explicit act by the operator, not a side effect of writing.

A reader encountering the earlier flat shape SHALL refuse the record rather than interpreting it. The earlier shape SHALL be reachable only through the migration path, so that no code path both accepts the old shape and produces the new one.

#### Scenario: Writing the partitioned shape to an older store is refused

- **WHEN** a record in the partitioned shape is written to a store whose format marker predates the shape
- **THEN** the write SHALL be refused
- **AND** the message SHALL state which components must be upgraded before the marker can be raised

#### Scenario: The flat shape is not silently accepted

- **WHEN** a record serialized in the earlier flat shape is read
- **THEN** it SHALL be refused and reported
- **AND** it SHALL NOT be interpreted as an empty authorized partition
