## ADDED Requirements

### Requirement: An entity SHALL designate which of its names are addressed outward

A record MAY carry a set of *authorized names* — the names by which the entity is addressed in output intended for people. The set SHALL be a subset of the names the record already carries; an authorized name SHALL NOT introduce a string that is not otherwise recorded as a name.

Designation SHALL be an explicit field. A name's position within the sequence of names SHALL NOT determine whether it is addressed outward.

The field SHALL be optional. A record carrying no authorized name is well-formed.

#### Scenario: A record designates one of its names

- **WHEN** a record carries the names `謝叔蓉`, `Shwu-Rong Grace Shieh`, and `Shieh, Grace S.`, and designates the first two as authorized
- **THEN** validation SHALL accept the record
- **AND** re-encoding it SHALL produce a byte-identical file

#### Scenario: A designation names a string that is not a name of the record

- **WHEN** a record designates `Grace Shieh` as authorized while its names are `謝叔蓉` and `Shwu-Rong Grace Shieh`
- **THEN** validation SHALL reject the record
- **AND** the message SHALL name the offending string and the record it belongs to

#### Scenario: A record designates nothing

- **WHEN** a record carries names but designates none of them as authorized
- **THEN** validation SHALL accept the record

### Requirement: At most one name per writing system SHALL be authorized

Within a single record, the authorized names SHALL be distinct in writing system. Two authorized names in the same writing system express an undecided question, not a designation, and SHALL be rejected.

The writing system of a name SHALL be derived from the string, and SHALL NOT be stored. The derivation SHALL distinguish only as many writing systems as are needed to partition the names of one entity.

#### Scenario: Two authorized names share a writing system

- **WHEN** a record designates both `Shwu-Rong Grace Shieh` and `Shieh, Grace S.` as authorized
- **THEN** validation SHALL reject the record
- **AND** the message SHALL name the writing system and both candidates

#### Scenario: Two authorized names in different writing systems

- **WHEN** a record designates `謝叔蓉` and `Shwu-Rong Grace Shieh` as authorized
- **THEN** validation SHALL accept the record

#### Scenario: Writing system is derived, not declared

- **WHEN** a name containing unified ideographs is examined
- **THEN** its writing system SHALL be reported as the ideographic one
- **AND** a name written in basic Latin letters SHALL be reported as the Latin one
- **AND** no writing system SHALL be read from the record

### Requirement: Outward-facing name resolution SHALL be script-aware and SHALL NOT fall back to name order

Resolving the outward-facing name of an entity for a requested writing system SHALL proceed in this order:

1. the authorized name whose derived writing system matches the request;
2. any authorized name, when no authorized name matches the request;
3. the record's stable key.

Resolution SHALL NOT fall back to an arbitrary member of the record's names. When a record designates no authorized name, resolution SHALL yield the stable key, so that the absence of a designation is visible in output rather than silently replaced by an index-derived form.

#### Scenario: The requested writing system is available

- **WHEN** the outward-facing name is resolved for the ideographic writing system, and the record designates `謝叔蓉` and `Shwu-Rong Grace Shieh` as authorized
- **THEN** the result SHALL be `謝叔蓉`

#### Scenario: The requested writing system is not available

- **WHEN** the outward-facing name is resolved for the ideographic writing system, and the record designates only `Shwu-Rong Grace Shieh` as authorized
- **THEN** the result SHALL be `Shwu-Rong Grace Shieh`

#### Scenario: No name is designated

- **WHEN** the outward-facing name is resolved for a record whose only name is `Guan, Yongtao` and which designates no authorized name
- **THEN** the result SHALL be the record's stable key
- **AND** the result SHALL NOT be `Guan, Yongtao`

### Requirement: Every published rendering of an entity SHALL use the resolved outward-facing name

Every path that renders an entity's name for a person to read — bibliography export, citation-data export, relational export, and the tool surface — SHALL obtain the name through outward-facing name resolution. No such path SHALL read a name by its position in the sequence of names.

#### Scenario: A bibliography is exported for a record with no designation

- **WHEN** a bibliography is exported for a record whose only name is `Guan, Yongtao` and which designates no authorized name
- **THEN** the exported author field SHALL be the record's stable key
- **AND** it SHALL NOT be `Guan, Yongtao`

#### Scenario: A rendering path reads name order

- **WHEN** a rendering path selects a name by its position in the sequence of names
- **THEN** that path SHALL be considered non-conforming

### Requirement: Records carrying no authorized name SHALL be reported, not rejected

The consistency report SHALL list the records that designate no authorized name. Validation SHALL NOT reject such records.

The two SHALL be distinguished because the information needed to designate an outward-facing name cannot be derived from the record: rejecting an underspecified record would make the store unloadable pending work that no mechanism can perform.

#### Scenario: The store contains records with no designation

- **WHEN** the consistency report is produced for a store in which some records designate no authorized name
- **THEN** the report SHALL list those records
- **AND** validation of the same store SHALL succeed

### Requirement: The absence of a designation SHALL be fillable without deciding what cannot be decided

A migration path SHALL propose authorized names for existing records and SHALL separate the cases that admit only one answer from the cases that require a judgement.

For a given writing system: when exactly one of the record's names is written in it, that name SHALL be adopted, because no choice exists. When more than one name is written in it and exactly one of those is not an index-derived citation form, that name SHALL be proposed. When the candidates remain more than one, the writing system SHALL be left undesignated and reported.

The migration path SHALL default to reporting its proposals without writing, and SHALL write only when explicitly instructed.

#### Scenario: Only one candidate exists

- **WHEN** a record's only name is `Guan, Yongtao`
- **THEN** the migration path SHALL adopt it as authorized for its writing system

#### Scenario: One candidate is a citation form

- **WHEN** a record carries `Wei-chung Liu` and `Liu, Wei-chung` in the Latin writing system
- **THEN** the migration path SHALL propose `Wei-chung Liu`
- **AND** SHALL NOT propose `Liu, Wei-chung`

#### Scenario: The candidates remain ambiguous

- **WHEN** a record carries two names in one writing system and neither is an index-derived citation form
- **THEN** the migration path SHALL leave that writing system undesignated
- **AND** SHALL report the record

#### Scenario: The migration path is run without instruction to write

- **WHEN** the migration path is run with no explicit instruction to write
- **THEN** it SHALL report its proposals
- **AND** the store SHALL be unchanged

### Requirement: Removing the positional convention SHALL bump the store format marker

The store format marker SHALL be raised, because the meaning of an existing field changes: the first element of the sequence of names ceases to be the outward-facing name. A reader built before this change SHALL be refused rather than allowed to read the new store under the old meaning.

#### Scenario: A reader built before this change opens the new store

- **WHEN** a reader whose supported format is below the new marker opens a store carrying the new marker
- **THEN** it SHALL refuse the store as a whole before decoding any record
- **AND** the message SHALL name both the store's marker and the reader's supported maximum

#### Scenario: A reader built for this change opens the new store

- **WHEN** a reader whose supported format includes the new marker opens the store
- **THEN** it SHALL load the store
