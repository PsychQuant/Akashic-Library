# organization-entity Specification

## Purpose

TBD - created by archiving change 'add-organization-entity'. Update Purpose after archive.

## Requirements

### Requirement: An organization SHALL be a record shape of its own

The canonical entity namespace SHALL admit organization records. An organization record SHALL be marked by a bare shape label, and that label SHALL be added to the closed set of known shapes.

The organization identity field MAY reuse the name used by another shape, because the label already determines the shape.

An organization record SHALL be able to record its own name variants and its own history, independently of any person or work that refers to it.

An organization record SHALL designate its outward-facing names by the same means as any other entity: an explicit subset of the names it carries, at most one per writing system. The name history SHALL be retained and SHALL remain orthogonal to that designation — renaming and writing system are independent axes, and an organization that has been renamed SHALL still be able to designate one outward-facing name per writing system among the names currently in force.

Resolving the outward-facing name of an organization SHALL proceed as for any other entity, with one additional step before the stable key: when no name is designated, the name currently in force SHALL be used. That step SHALL be retained because it is a query over the name history, not a reading of name order.

#### Scenario: An organization is stored and reloaded

- **WHEN** an organization record is written to the canonical entity namespace and reloaded
- **THEN** it SHALL be decoded as an organization on the strength of its shape label alone
- **AND** re-encoding it SHALL produce a byte-identical file

#### Scenario: An organization is renamed

- **WHEN** an organization's name changes while the organization continues to exist
- **THEN** the record SHALL retain both names with their validity ranges
- **AND** references from person records SHALL remain valid without being rewritten

#### Scenario: An organization designates one outward-facing name per writing system

- **WHEN** an organization carries both an ideographic name and a Latin name currently in force, and designates one of each as authorized
- **THEN** validation SHALL accept the record
- **AND** resolving its outward-facing name for the ideographic writing system SHALL yield the ideographic one

#### Scenario: A renamed organization designates only its current name

- **WHEN** an organization has been renamed and designates only the name currently in force
- **THEN** validation SHALL accept the record
- **AND** the superseded name SHALL remain recorded with its validity range

#### Scenario: An organization designates nothing

- **WHEN** an organization designates no authorized name
- **THEN** resolving its outward-facing name SHALL yield the name currently in force
- **AND** SHALL yield the stable key when no name is currently in force

---
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


<!-- @trace
source: add-organization-entity
updated: 2026-08-02
code:
  - Sources/AkashicCore/Temporal.swift
  - Sources/AkashicStoreIO/StoreMigration.swift
  - .agents/skills/spectra-audit/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - Sources/AkashicStoreIO/StoreVersion.swift
  - .agents/skills/spectra-propose/SKILL.md
  - Tests/AkashicKitTests/AliasEventBudgetTests.swift
  - Tests/AkashicKitTests/EntityShapeLabelTests.swift
  - Sources/AkashicExport/RelationalExport.swift
  - docs/store-format.md
  - AGENTS.md
  - Tests/AkashicKitTests/TemporalPersonTests.swift
  - Sources/AkashicCore/YAML.swift
  - docs/explainers/yaml-alias-dos.md
  - Sources/AkashicCore/DeterministicUUID.swift
  - .agents/skills/spectra-drift/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - Sources/AkashicCore/Organization.swift
  - .agents/skills/spectra-apply/SKILL.md
  - Sources/akashic/Commands.swift
  - CLAUDE.md
  - .agents/skills/spectra-archive/SKILL.md
  - Sources/AkashicStoreIO/LibraryStore.swift
  - .spectra.yaml
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-debug/SKILL.md
  - Tests/AkashicKitTests/RelationalExportTests.swift
  - Tests/AkashicKitTests/OrganizationTests.swift
  - .agents/skills/spectra-commit/SKILL.md
  - docs/design-principles-and-philosophy.md
  - docs/explainers/entity-vs-view.md
  - Sources/AkashicCore/AliasEventBudget.swift
-->

---
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


<!-- @trace
source: add-organization-entity
updated: 2026-08-02
code:
  - Sources/AkashicCore/Temporal.swift
  - Sources/AkashicStoreIO/StoreMigration.swift
  - .agents/skills/spectra-audit/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - Sources/AkashicStoreIO/StoreVersion.swift
  - .agents/skills/spectra-propose/SKILL.md
  - Tests/AkashicKitTests/AliasEventBudgetTests.swift
  - Tests/AkashicKitTests/EntityShapeLabelTests.swift
  - Sources/AkashicExport/RelationalExport.swift
  - docs/store-format.md
  - AGENTS.md
  - Tests/AkashicKitTests/TemporalPersonTests.swift
  - Sources/AkashicCore/YAML.swift
  - docs/explainers/yaml-alias-dos.md
  - Sources/AkashicCore/DeterministicUUID.swift
  - .agents/skills/spectra-drift/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - Sources/AkashicCore/Organization.swift
  - .agents/skills/spectra-apply/SKILL.md
  - Sources/akashic/Commands.swift
  - CLAUDE.md
  - .agents/skills/spectra-archive/SKILL.md
  - Sources/AkashicStoreIO/LibraryStore.swift
  - .spectra.yaml
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-debug/SKILL.md
  - Tests/AkashicKitTests/RelationalExportTests.swift
  - Tests/AkashicKitTests/OrganizationTests.swift
  - .agents/skills/spectra-commit/SKILL.md
  - docs/design-principles-and-philosophy.md
  - docs/explainers/entity-vs-view.md
  - Sources/AkashicCore/AliasEventBudget.swift
-->

---
### Requirement: Resolution SHALL be biased toward splitting

When it is uncertain whether two affiliation strings name the same organization, the store SHALL default to treating them as two organizations rather than one.

Migration of existing affiliation text SHALL produce literals only, and SHALL NOT merge any two strings automatically.

#### Scenario: Two spellings might name the same organization

- **WHEN** two affiliation literals differ in wording and it is not established that they name the same organization
- **THEN** they SHALL remain separate
- **AND** merging them later SHALL remain possible because both histories are still present


<!-- @trace
source: add-organization-entity
updated: 2026-08-02
code:
  - Sources/AkashicCore/Temporal.swift
  - Sources/AkashicStoreIO/StoreMigration.swift
  - .agents/skills/spectra-audit/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - Sources/AkashicStoreIO/StoreVersion.swift
  - .agents/skills/spectra-propose/SKILL.md
  - Tests/AkashicKitTests/AliasEventBudgetTests.swift
  - Tests/AkashicKitTests/EntityShapeLabelTests.swift
  - Sources/AkashicExport/RelationalExport.swift
  - docs/store-format.md
  - AGENTS.md
  - Tests/AkashicKitTests/TemporalPersonTests.swift
  - Sources/AkashicCore/YAML.swift
  - docs/explainers/yaml-alias-dos.md
  - Sources/AkashicCore/DeterministicUUID.swift
  - .agents/skills/spectra-drift/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - Sources/AkashicCore/Organization.swift
  - .agents/skills/spectra-apply/SKILL.md
  - Sources/akashic/Commands.swift
  - CLAUDE.md
  - .agents/skills/spectra-archive/SKILL.md
  - Sources/AkashicStoreIO/LibraryStore.swift
  - .spectra.yaml
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-debug/SKILL.md
  - Tests/AkashicKitTests/RelationalExportTests.swift
  - Tests/AkashicKitTests/OrganizationTests.swift
  - .agents/skills/spectra-commit/SKILL.md
  - docs/design-principles-and-philosophy.md
  - docs/explainers/entity-vs-view.md
  - Sources/AkashicCore/AliasEventBudget.swift
-->

---
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

---
### Requirement: Affiliation ranges SHALL support fail-closed valid-day assessment

A person affiliation `DateRange` SHALL be assessable at one exact Gregorian `ValidDay` without using `TimelineOf.current` or `DateRange.overlaps`. Assessment SHALL distinguish definite containment, definite exclusion, temporal indeterminacy, and invalid temporal evidence. Bounded endpoints SHALL be inclusive. A year- or month-precision endpoint SHALL represent its complete possible day interval and SHALL NOT be silently replaced by its first or last day as a claimed fact.

#### Scenario: An exact bounded affiliation contains an interior day

- **WHEN** an affiliation range starts at `2020-01-01`, ends at `2020-12-31`, and is assessed at `2020-06-15`
- **THEN** the assessment SHALL be definite containment

#### Scenario: A coarse endpoint leaves its boundary indeterminate

- **WHEN** an affiliation starts at month precision `2020-06` and is assessed at `2020-06-15`
- **THEN** the assessment SHALL be temporal indeterminacy
- **AND** it SHALL NOT claim definite containment or exclusion

#### Scenario: A day after the latest possible coarse start is contained

- **WHEN** an open affiliation starts at month precision `2020-06` and is assessed at `2020-07-01`
- **THEN** the assessment SHALL be definite containment

#### Scenario: Unknown endpoints do not become infinities

- **WHEN** an affiliation has no start or has `endedUnknown` without a known applicable end
- **THEN** a non-excluded requested day SHALL be temporal indeterminacy
- **AND** unknown start SHALL NOT be treated as negative infinity
- **AND** unknown end SHALL NOT be treated as positive infinity

#### Scenario: An exact attestation establishes only its observed day

- **WHEN** an attested-only affiliation contains `2020-06-15`
- **THEN** assessment at `2020-06-15` SHALL be definite containment
- **AND** assessment at a different day SHALL NOT extend that observation into a range

#### Scenario: Contradictory or malformed evidence is invalid

- **WHEN** an affiliation mixes attested observations with start or end, contains an invalid Gregorian endpoint, or has an end definitely earlier than its start
- **THEN** the assessment SHALL be invalid temporal evidence
- **AND** it SHALL NOT be converted to a Boolean result
