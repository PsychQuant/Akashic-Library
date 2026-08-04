## ADDED Requirements

### Requirement: An unresolved identity question SHALL be recordable

The store SHALL admit a record whose subject is an open question about identity — whether two or more entities are one. Such a record SHALL be marked by a bare shape label, and that label SHALL be added to the closed set of known shapes.

The record SHALL state the question in words, and SHALL name at least two candidates. A record naming fewer than two candidates SHALL be refused, because a question about identity requires something to be identical to.

All candidates of one record SHALL name entities of the same shape. A record whose candidates span shapes SHALL be refused, naming both candidates and their shapes, because the question "are these one" is unanswerable across shapes.

#### Scenario: A two-candidate record loads

- **WHEN** a record naming a question and two entity keys of the same shape is loaded
- **THEN** it SHALL be accepted

##### Example: Two spellings of one name

- **GIVEN** a record whose question is `是否為同一人` and whose candidates are `fann-cathy-s-j` and `fann-cathy-s-j-2`, both person keys
- **WHEN** the store is loaded
- **THEN** the record SHALL be accepted and both candidates SHALL remain separate entities

#### Scenario: A single-candidate record is refused

- **WHEN** a record naming only one candidate is loaded
- **THEN** it SHALL be refused, and the reason SHALL state that at least two candidates are required

#### Scenario: Candidates spanning shapes are refused

- **WHEN** a record names one person key and one work key as candidates
- **THEN** it SHALL be refused, and the reason SHALL name both candidates and the shape of each

---

### Requirement: The judgment SHALL reuse the provenance vocabulary

A record MAY carry a judgment: a statement of which candidate was believed correct and why, together with the digests of the evidence it rests on.

The judgment SHALL use the same two fields the store uses elsewhere to record a claim reached by reasoning rather than by retrieval — a statement in words and a list of digests. It SHALL NOT introduce a second vocabulary for the same concept.

The judgment SHALL NOT carry the field-naming component that a provenance reference carries, because the judgment concerns which candidate is correct, not which field of a host record is supported.

The two judgment fields SHALL appear together. A record carrying one without the other SHALL be refused, because a statement without its evidence and evidence without its statement are each incomplete.

#### Scenario: A record carries a judgment

- **WHEN** a record carries both a statement and at least one digest
- **THEN** it SHALL be accepted

#### Scenario: A statement without evidence is refused

- **WHEN** a record carries a statement but no digests
- **THEN** it SHALL be refused, and the reason SHALL state that the two appear together

#### Scenario: Evidence without a statement is refused

- **WHEN** a record carries digests but no statement
- **THEN** it SHALL be refused, and the reason SHALL state that the two appear together

---

### Requirement: Resolving SHALL merge, rewrite references, and delete atomically

Resolving an identity question SHALL name one candidate as the survivor. Resolution SHALL merge the other candidates' aliases into the survivor, SHALL rewrite every reference in the store that names a merged entity so that it names the survivor, and SHALL then delete both the merged entities and the record of the question.

These three SHALL constitute one operation. Deleting a record without rewriting its references SHALL NOT be offered, because it would leave references naming entities that no longer exist.

A survivor not among the candidates SHALL be refused, and the refusal SHALL list the actual candidates.

Where a single write fails during reference rewriting, the remaining writes SHALL still be attempted, the failures SHALL be named, and the operation SHALL exit non-zero — so that no run ends with some references rewritten, others not, and nothing said about it.

#### Scenario: Resolution rewrites the references that named the merged entity

- **WHEN** an identity question over two person keys is resolved in favour of one of them
- **THEN** every record that named the merged key SHALL name the survivor instead
- **AND** the merged entity's file SHALL NOT exist
- **AND** the record of the question SHALL NOT exist

##### Example: A work's author list follows the merge

- **GIVEN** a work whose authors include the key `fann-cathy-s-j-2`
- **AND** an identity question naming `fann-cathy-s-j` and `fann-cathy-s-j-2`
- **WHEN** it is resolved in favour of `fann-cathy-s-j`
- **THEN** that work's authors SHALL include `fann-cathy-s-j` and SHALL NOT include `fann-cathy-s-j-2`

#### Scenario: A survivor outside the candidates is refused

- **WHEN** resolution names a survivor that the record does not list as a candidate
- **THEN** it SHALL be refused, and the refusal SHALL list the candidates the record does name

---

### Requirement: Deletion SHALL require version control

The history of a resolved question lives in version control rather than in the store, so deletion SHALL be permitted only where that history will exist.

Resolution SHALL verify that the store lies within a version-controlled working tree before deleting anything. Where it does not, resolution SHALL refuse and SHALL say that version control is the precondition for deletion.

This SHALL be verified rather than assumed, because a store may be created at any location and one outside version control loses the record irrecoverably.

#### Scenario: Resolution refuses outside version control

- **WHEN** resolution is attempted on a store that is not inside a version-controlled working tree
- **THEN** it SHALL refuse
- **AND** no file SHALL have been deleted
- **AND** the reason SHALL state that version control is the precondition

---

### Requirement: The new shape SHALL be serialized like every other

A record of an identity question SHALL be written in the same canonical form the store applies to its other shapes: deterministic ordering, byte-preserving retention of unrecognized fields, and a self-check before writing that the bytes read back to the same value.

#### Scenario: The record round-trips

- **WHEN** a record is encoded, decoded, and encoded again
- **THEN** the two encodings SHALL be byte-identical

#### Scenario: An unrecognized field survives

- **WHEN** a record carrying a field the store does not recognize is loaded and written back
- **THEN** that field SHALL be present in the output unchanged
