## ADDED Requirements

### Requirement: A record's stable identifier SHALL have exactly one origin event

A record's stable identifier SHALL be assigned once, at the moment the record is created, and SHALL NOT be derived from any attribute of the record. An identifier that can be recomputed from the record's attributes carries no information those attributes do not already carry: it changes when they change, and it collides when they collide.

Deriving an identifier from an attribute is permitted only as a **one-time backfill** for records that predate the identifier field, and only where independent machines must reach the same answer without coordinating. Such a derivation SHALL be written to disk at the moment it is computed, and SHALL NOT remain reachable as a default for newly created records.

#### Scenario: A newly created record receives an independent identifier

- **WHEN** a record is created without an explicit identifier
- **THEN** the identifier SHALL be randomly generated
- **AND** it SHALL NOT be a function of the record's key, names, or any other attribute

#### Scenario: Two records with identical attributes receive different identifiers

- **WHEN** two records are created that carry the same key-derived attributes in two separate stores
- **THEN** their identifiers SHALL differ

##### Example: Two people who share a key across stores

- **GIVEN** store A contains a person whose key is `chen-wei`, and store B contains a *different* person whose key is also `chen-wei`
- **WHEN** the two stores are merged
- **THEN** the two records SHALL remain distinguishable, because their identifiers were assigned independently
- **AND** the merge SHALL surface them as two records sharing a key, which is a decision for a person to resolve

#### Scenario: A backfill derivation is retired once it has no remaining subjects

- **WHEN** every record on disk carries an explicit identifier
- **THEN** the derivation used to backfill absent identifiers SHALL have no production call site
- **AND** its retirement SHALL be verifiable by searching the source tree for callers

### Requirement: A record's human-readable key SHALL NOT be recomputed after assignment

A record's key SHALL be assigned once and SHALL remain the record's key thereafter. The key MAY be derived from the record's content at the moment of assignment, but SHALL NOT be re-derived on subsequent passes over the same record.

Re-derivation makes the key a function of the order in which records are processed: when two records would produce the same key, the one processed first takes the base form and the other takes a suffix, so the same corpus imported in a different order yields a different assignment.

#### Scenario: Re-running key assignment does not change existing keys

- **WHEN** the key-assignment pass runs a second time over a store whose records already carry keys
- **THEN** no existing key SHALL change

#### Scenario: A collision suffix is a fact about assignment order, not about the record

- **WHEN** two records would produce the same base key and one receives a numeric suffix
- **THEN** the suffix SHALL NOT be treated as information about the record it is attached to

### Requirement: Identifier reassignment SHALL keep the record locatable at every point

Where a record's on-disk location is derived from its identifier, reassigning the identifier SHALL update the location and the stored identifier together. A state in which the two disagree SHALL NOT be observable after the operation completes.

The operation SHALL write the new location before removing the old one, so that an interruption leaves a duplicate — which is detectable and repairable — rather than an absence, which is not.

#### Scenario: The stored identifier and the location agree after reassignment

- **WHEN** a record's identifier is reassigned
- **THEN** the record's location SHALL correspond to the new identifier
- **AND** the identifier stored inside the record SHALL be the new one

#### Scenario: An interruption leaves a detectable state

- **WHEN** identifier reassignment is interrupted after the new location is written and before the old one is removed
- **THEN** both locations SHALL contain a well-formed record
- **AND** the condition SHALL be reportable as a duplicate rather than presenting as data loss

### Requirement: An irreversible reassignment SHALL require a working recovery path

An operation that reassigns identifiers across an existing store SHALL default to reporting what it would do without writing, and SHALL write only when explicitly instructed.

When instructed to write, the operation SHALL first confirm that the store's recovery path is intact, and SHALL refuse otherwise. A recovery path that exists but cannot restore the prior state is not a recovery path.

#### Scenario: The default run does not write

- **WHEN** the reassignment operation runs without explicit instruction to write
- **THEN** no file SHALL be created, modified, or removed
- **AND** the operation SHALL report the records it would have changed

#### Scenario: Writing is refused when the recovery path is compromised

- **WHEN** the operation is instructed to write and the store carries uncommitted modifications
- **THEN** the operation SHALL refuse
- **AND** the message SHALL state that the prior state must be committed first

#### Scenario: Re-running after a completed reassignment is safe

- **WHEN** the operation runs again over a store it has already processed
- **THEN** records already carrying independent identifiers SHALL be left unchanged
- **AND** they SHALL be counted separately from records that were changed

#### Scenario: A single failing record does not abort the batch

- **WHEN** one record cannot be reassigned
- **THEN** that record SHALL be left in its prior state
- **AND** the remaining records SHALL still be processed
- **AND** the report SHALL name the failing record and the reason
