# authorship-completeness-witness Specification

## Purpose

TBD - created by archiving change 'add-evidenced-proposition-negation'. Update Purpose after archive.

## Requirements

### Requirement: Canonical entries SHALL carry a typed author-list completeness witness

An Entry SHALL expose at most one optional `AuthorListCompletenessWitness` inside its Akashic-owned metadata. The witness SHALL contain the Entry work UUID, an ordered exact `Author` snapshot, a versioned `AuthorListFingerprint`, and a non-empty provenance-reference bundle. It SHALL NOT use Zotero provenance, a bare Boolean, citekey identity, `StoreRevision`, or caller-supplied model overlays as a completeness carrier.

`AuthorListFingerprint` SHALL be SHA-256 over the domain `akashic-author-list-v1`, a UInt64 big-endian slot count, and for each ordered slot a distinct key-or-literal tag followed by UInt64 big-endian raw UTF-8 byte length and bytes. The fingerprint SHALL preserve slot order and raw NFC/NFD bytes. It SHALL NOT contain `StoreRevision` or any digest derived from the enclosing canonical file.

#### Scenario: A complete witness is constructed

- **WHEN** a caller supplies one work UUID, an ordered author snapshot, its derived v1 fingerprint, and a valid authors provenance chain
- **THEN** throwing witness construction SHALL succeed
- **AND** every stored property SHALL be read-only

#### Scenario: Structural author differences change the fingerprint

- **WHEN** two author snapshots differ by slot order, key-versus-literal case, raw UTF-8 bytes, or slot boundary
- **THEN** their v1 fingerprints SHALL differ

##### Example: Fingerprint separation

| Left snapshot | Right snapshot | Expected |
| ------------- | -------------- | -------- |
| `[key("ab"), key("c")]` | `[key("a"), key("bc")]` | different |
| `[key("a"), literal("b")]` | `[literal("a"), key("b")]` | different |
| `[literal("é")]` in NFC | `[literal("e◌́")]` in NFD | different |
| `[key("a"), key("b")]` | `[key("b"), key("a")]` | different |

#### Scenario: A witness cannot refer to its enclosing store revision

- **WHEN** a canonical Entry witness is encoded
- **THEN** its known shape SHALL contain work ID, author-list fingerprint, attested authors, and references only
- **AND** it SHALL NOT contain a store revision or snapshot ID field

---
### Requirement: Completeness provenance SHALL form a closed local evidence chain

Every witness reference SHALL have field exactly `authors` and no collection `value`. The bundle SHALL contain at least one retrieval with a valid `sha256:` content digest and at least one judgement whose trimmed statement and `rests-on` list are non-empty. Every judgement digest SHALL be valid and SHALL equal a retrieval content digest in the same witness bundle. The witness initializer and canonical decode boundary SHALL revalidate these invariants even when a `ProvenanceReference` was created through its public non-throwing initializer.

#### Scenario: A retrieval-backed judgement is accepted

- **WHEN** a judgement rests on the valid content digest of an authors retrieval in the same bundle
- **THEN** the provenance chain SHALL be valid

#### Scenario: A judgement cannot cite an external digest

- **WHEN** a judgement `rests-on` digest has no matching retrieval content in the same witness bundle
- **THEN** witness construction or decode SHALL throw a typed validation error
- **AND** no truth-bearing model SHALL receive that witness

#### Scenario: Directly forged provenance is revalidated

- **WHEN** a public `ProvenanceReference` value contains an empty judgement, empty `rests-on`, malformed digest, a field other than `authors`, or a non-nil value
- **THEN** witness construction SHALL reject it

#### Scenario: Diagnostics remain bounded and display-safe

- **WHEN** invalid provenance contains caller-controlled control characters, direction controls, or oversized strings
- **THEN** the machine-readable error SHALL retain its typed reason
- **AND** localized, describing, and reflecting diagnostics SHALL sanitize displayed data and apply a fixed post-escape length bound

---
### Requirement: Witnesses SHALL bind exactly to the current work and author snapshot

Canonical Entry decode SHALL require `witness.workID == Entry.id`, `witness.attestedAuthors == Entry.authors` in exact order, and `witness.fingerprint == fingerprint(Entry.authors)`. A mismatch SHALL fail closed and quarantine the canonical file. `PropositionModel` construction SHALL revalidate the same association so an in-memory mutation or internal test seam cannot bypass decode. Binding errors SHALL be typed, deterministic, and aggregated independently of input order; a valid record SHALL NOT hide a stale record.

#### Scenario: A citekey rename preserves a valid witness

- **WHEN** an Entry citekey changes while its UUID and ordered authors remain unchanged
- **THEN** the witness binding SHALL remain valid

#### Scenario: Copying a witness to another work is rejected

- **WHEN** a witness is attached to an Entry with a different UUID
- **THEN** decode SHALL quarantine the file or programmatic model construction SHALL reject it

#### Scenario: Author mutation invalidates the witness

- **WHEN** an author is added, removed, reordered, changes key-or-literal case, or changes raw UTF-8 bytes after attestation
- **THEN** the witness SHALL be stale
- **AND** it SHALL NOT establish authored failure

#### Scenario: Duplicate witness keys are rejected

- **WHEN** canonical YAML contains the `author-list-completeness` key more than once
- **THEN** mapping validation SHALL reject the file
- **AND** one witness SHALL NOT silently select or hide another

---
### Requirement: Witness serialization SHALL be additive, deterministic, and revision-bearing

The optional witness SHALL serialize under `akashic.author-list-completeness` with fixed known-key order and strict nested shapes. A missing witness SHALL preserve existing Entry bytes and open-world behavior. Existing unknown Akashic fields SHALL coexist without loss. A witness byte change SHALL change the enclosing library `StoreRevision` because revision and decode SHALL consume the same accepted capture. This optional tolerant-namespace addition SHALL NOT require a store-version bump or bulk migration.

#### Scenario: A valid witness round-trips exactly by value

- **WHEN** an Entry with a valid witness is encoded, decoded, and encoded again
- **THEN** its typed witness SHALL remain equal
- **AND** the second canonical encoding SHALL equal the first

#### Scenario: Existing entries remain unchanged

- **WHEN** an Entry has no witness
- **THEN** its canonical encoding and authored open-world behavior SHALL remain unchanged

#### Scenario: Witness bytes participate in snapshot revision

- **WHEN** the accepted canonical Entry changes only by adding or changing a valid witness
- **THEN** the store identity SHALL remain equal
- **AND** the content revision SHALL change
- **AND** the decoded proposition model SHALL reflect the same accepted witness bytes

#### Scenario: Malformed witness YAML is quarantined

- **WHEN** a known witness field has the wrong shape, tag, digest, fingerprint, work binding, author binding, or provenance chain
- **THEN** snapshot loading SHALL quarantine that file with a typed store error
- **AND** it SHALL NOT silently treat the malformed witness as absent
