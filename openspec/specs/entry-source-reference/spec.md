# entry-source-reference Specification

## Purpose

TBD - created by archiving change 'replace-pool-attachment-with-source-digest'. Update Purpose after archive.

## Requirements

### Requirement: A work record SHALL name stored content that is a copy of the work

A work record SHALL be able to carry a list of content digests declaring that the named stored content is a copy of the work the record describes. Each entry SHALL use the digest form already established for provenance references. An absent list and an empty list SHALL be equivalent.

The reverse relation — which records a given stored content belongs to — SHALL be computed by scanning records and SHALL NOT be stored separately. Content is acquired before the record that describes it exists, so only the record side is able to name its counterpart at the moment the link becomes knowable.

#### Scenario: A record names one stored copy

- **WHEN** a work record carries a copy list with one digest
- **THEN** the record SHALL load and the digest SHALL be preserved verbatim on write

##### Example: A journal article with one archived PDF

- **GIVEN** a work record for an article, and stored content with digest `sha256:0a9a79d3030c457b7a3f54ecc98c9fa11d60b8901ffd8e709b528d47f151125a`
- **WHEN** the record declares that digest as a copy of the work
- **THEN** reading the record yields exactly that one digest, and writing the record emits the same string unchanged

#### Scenario: The named content is not stored on this machine

- **WHEN** a record names a digest for which no stored copy exists locally
- **THEN** the record SHALL load, and the absent content SHALL be reported as a condition distinct from a malformed record

#### Scenario: A digest does not satisfy the digest grammar

- **WHEN** a record carries a copy entry that is not a well-formed digest
- **THEN** the store SHALL reject the record with an error naming the copy list field

#### Scenario: An empty copy list is present

- **WHEN** a record carries a copy list with no entries
- **THEN** the record SHALL load and SHALL be indistinguishable in behaviour from a record carrying no copy list

---
### Requirement: Content the store is able to ingest SHALL be referenced by digest rather than by file-system path

A reference to content that the store is able to ingest SHALL name that content by the digest of its bytes. A file-system path SHALL NOT be introduced as a new reference form for such content. A path breaks when the file is moved or renamed and carries no means of detecting that the bytes changed, whereas the digest is the identity the store already uses for stored content.

Exactly one path-based reference form is retained: the reference into an external reference manager's own storage, which exists because that manager holds bytes this store has not ingested. That form is a transition mechanism. This is a closed enumeration of one form. A second path-based form SHALL NOT be admitted, and resemblance to the retained form SHALL NOT be accepted as grounds for admitting one.

#### Scenario: A path-based reference form is offered for ingestible content

- **WHEN** a reference form names content by a file-system path resolved against a configured root
- **THEN** the store SHALL NOT admit that form

#### Scenario: The retained external-manager reference is read

- **WHEN** a record carries the retained reference into an external reference manager's storage
- **THEN** the record SHALL load

---
### Requirement: The set of accepted attachment kinds SHALL contain exactly one kind

The set of accepted attachment kinds SHALL contain exactly one kind: the reference into an external reference manager's own storage. Any other kind SHALL be rejected on load, and the rejection message SHALL name the accepted kind.

#### Scenario: A record carries an attachment of the removed pool kind

- **WHEN** a record carries an attachment whose kind is `pool`
- **THEN** the store SHALL reject the record, and the error message SHALL NOT present `pool` as an accepted value

#### Scenario: A record carries an attachment of the retained kind

- **WHEN** a record carries an attachment whose kind is `zotero`
- **THEN** the record SHALL load

---
### Requirement: The copy reference SHALL remain distinct from field-level provenance references

The copy reference and the field-level provenance reference SHALL remain separate fields with separate meanings. A field-level provenance reference asserts that a named field's value rests on retrieved content. A copy reference asserts that stored content is a copy of the work the record describes. The two SHALL NOT be merged into one field, and a copy reference SHALL NOT be expressed as a field-level reference naming a whole record.

The two live on different record shapes: the copy reference belongs to the work record, the field-level reference belongs to the person and organization records. They meet only at the content they both name. Naming the same stored content SHALL NOT cause either assertion to be rewritten as the other.

#### Scenario: Two record shapes name the same stored content

- **WHEN** a work record carries a copy reference naming a digest, and a person record carries a field-level provenance reference naming the same digest
- **THEN** both SHALL be retained as separate assertions, neither SHALL be rewritten into the other, and the shared content SHALL be stored once

---
### Requirement: The copy reference SHALL be governed by a store format increment

A store whose format predates the copy reference SHALL NOT accept a record carrying one. A store whose format includes the copy reference SHALL be refused in full by a reader that supports only earlier formats.

The narrowing of the attachment kind domain SHALL be treated as a change that requires a format increment, because attachment element keys are validated strictly and an unrecognised kind quarantines the whole record rather than being preserved. The number of records currently affected SHALL NOT be accepted as grounds for omitting the increment.

#### Scenario: A record carrying a copy reference is written to a store of an earlier format

- **WHEN** a record carrying a copy reference is written to a store whose format predates the copy reference
- **THEN** the write SHALL be refused with an error naming the required format

#### Scenario: A store of the new format is opened by a reader supporting only earlier formats

- **WHEN** a reader that supports only formats earlier than the copy reference opens a store of the new format
- **THEN** the reader SHALL refuse to open the store in full rather than reading it under the earlier interpretation
