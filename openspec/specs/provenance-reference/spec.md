# provenance-reference Specification

## Purpose

TBD - created by archiving change 'add-provenance-references'. Update Purpose after archive.

## Requirements

### Requirement: A provenance reference SHALL record both the retrieval path and the retrieved content

A provenance reference SHALL carry two distinct components: the path by which the content was obtained (a URL and a retrieval date), and the identity of the content that was obtained (a cryptographic digest of the retrieved bytes). A reference that carries only a URL SHALL NOT be accepted as complete provenance.

The two components answer different questions and neither substitutes for the other. The path answers "how was this obtained, and can it be obtained again"; the content digest answers "what did the source actually say". A URL that has ceased to resolve still records a valid path; the digest still identifies what the claim depended on.

#### Scenario: A reference is recorded for a claim sourced from a web page

- **WHEN** a field's value is asserted on the basis of a web page
- **THEN** the reference SHALL record the URL, the retrieval date, and the SHA-256 digest of the retrieved bytes

#### Scenario: A reference omits the content digest

- **WHEN** a reference carries a URL and retrieval date but no content digest
- **THEN** the store SHALL reject the record with an error naming the missing digest

#### Scenario: Two distinct URLs return identical content

- **WHEN** two URLs are retrieved and produce the same digest
- **THEN** both references SHALL be retained as separate paths to the same content, and the content SHALL be stored once

##### Example: One institute page reachable under two host names

- **GIVEN** `https://sites.stat.sinica.edu.tw/cheng/` and `https://www.stat.sinica.edu.tw/cheng/` were both retrieved on 2026-08-03
- **WHEN** both responses are 62302 bytes with digest `d1f446b3507bd24a…`
- **THEN** two reference entries are recorded, both naming digest `d1f446b3507bd24a…`, and one stored copy of the bytes exists

#### Scenario: A retrieval returns an error page

- **WHEN** a retrieval returns an HTTP error status
- **THEN** the recorded digest SHALL be the digest of the received body, and the recorded status SHALL be the received status

---
### Requirement: Retrieved content SHALL be addressed by the digest of its bytes

Stored content SHALL be located by the digest of the exact bytes retrieved. Two retrievals producing identical bytes SHALL resolve to one stored copy. The store SHALL NOT normalize, reformat, or transform retrieved bytes before computing the digest or before storing them.

#### Scenario: The same content is retrieved twice

- **WHEN** a URL is retrieved on two occasions and both retrievals produce identical bytes
- **THEN** one stored copy SHALL exist, and both references SHALL name the same digest

#### Scenario: The content at a URL changes between retrievals

- **WHEN** a URL is retrieved on two occasions producing different bytes
- **THEN** two stored copies SHALL exist under two digests, and each reference SHALL name the digest current at its own retrieval date

#### Scenario: A digest names content that is not stored locally

- **WHEN** a record names a digest for which no stored copy exists
- **THEN** the store SHALL load the record and SHALL report the absent content as a distinct condition from a malformed record

---
### Requirement: Stored content SHALL NOT be tracked by the version-control remote

Retrieved content is third-party verbatim material. The directory holding stored content SHALL be excluded from version control, in the same manner as the project already excludes raw third-party transcripts and recordings.

References themselves — URL, retrieval date, digest, and status — SHALL be tracked. The distinction is between the record of what was referred to, which is tracked, and the referred-to bytes, which are not.

#### Scenario: A store is committed after content is archived

- **WHEN** content is stored and the store is committed
- **THEN** the reference fields SHALL appear in the commit and the stored bytes SHALL NOT

#### Scenario: A store is cloned on a second machine

- **WHEN** a store is cloned where content was archived on the original machine
- **THEN** every reference SHALL be present, and the absent stored content SHALL be reported as absent rather than as corruption

---
### Requirement: Stored content SHALL NOT occupy the canonical entity namespace

Stored content SHALL NOT be written to the entity directory, SHALL NOT carry a shape label, and SHALL NOT be given a key.

Two grounds, either sufficient. First, the criterion recorded in the entity-boundary capability: a web page does not determine the shape of a record and causes no loader branch to a distinct decoder. Second, and specific to content addressing: an entity retains identity across a change of name, whereas content addressed by its digest becomes different content when one byte changes. Content so addressed has no name, no history, and no lifecycle; its identity is exhausted by its bytes.

#### Scenario: Stored content is proposed as an entity record

- **WHEN** archived content is proposed for the entity directory with a shape label
- **THEN** the proposal SHALL be refused, and the refusal SHALL name the content-addressing ground rather than only the shape ground

#### Scenario: One source is referenced by many records

- **WHEN** a single digest is named by references on many records
- **THEN** the shared digest SHALL NOT be grounds for promoting the content to an entity

---
### Requirement: A reference SHALL be attachable to a named field

A reference SHALL identify which assertion it supports. A record-level list of references that does not distinguish which field each reference supports SHALL NOT satisfy this requirement.

#### Scenario: One record carries values from several sources

- **WHEN** a record's fields derive from different sources
- **THEN** each reference SHALL name the field it supports

##### Example: A person record with three sourced fields

| Field | Source | Reference names field |
| ----- | ------ | --------------------- |
| `profile.affiliations` | institute roster page | yes |
| `orcid` | ORCID public API | yes |
| `names` alias entry | manual adjudication | yes |

#### Scenario: A reference names a field the record does not carry

- **WHEN** a reference names a field absent from the record
- **THEN** the store SHALL reject the record with an error naming the field

---
### Requirement: A reference SHALL be able to record a judgement that is not a retrieval

Some assertions rest on reasoning over other evidence rather than on a single retrieval. A reference SHALL be able to record such a judgement, naming the evidence it rests on, without a URL or a content digest.

#### Scenario: A value is asserted on cross-referenced evidence

- **WHEN** a value is asserted because several retrieved sources agree
- **THEN** the reference SHALL record the reasoning and SHALL name the digests of the sources it rests on

##### Example: An identifier confirmed by corroboration

- **GIVEN** an ORCID record whose employment field names only a current institution
- **WHEN** the identifier is accepted because the work dates fall within a known tenure window, the subject matter matches, and one work is co-authored with a confirmed member of the same institution
- **THEN** the reference records that reasoning and names the digests of the ORCID record and of the co-author's page

#### Scenario: A judgement reference is given a content digest

- **WHEN** a judgement reference carries a content digest of its own
- **THEN** the store SHALL reject the record, because a judgement is not a retrieval and has no bytes of its own

---
### Requirement: Existing records SHALL remain loadable

Records carrying no references SHALL load unchanged. The existing per-segment source field SHALL continue to be accepted and SHALL NOT be rewritten by this change.

#### Scenario: A record predating this change is loaded

- **WHEN** a record with no reference field is loaded
- **THEN** it SHALL load without error and SHALL be rewritten byte-identically

#### Scenario: A record carries the existing per-segment source field

- **WHEN** a record carries a timeline segment with a source value
- **THEN** that value SHALL be preserved and SHALL NOT be converted into a reference
