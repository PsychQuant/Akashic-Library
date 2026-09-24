# entity-shape-label Specification

## Purpose

TBD - created by archiving change 'add-entity-shape-label'. Update Purpose after archive.

## Requirements

### Requirement: Record shape SHALL be carried by a bare label

Every record in the canonical entity namespace SHALL carry its shape as a bare label — a top-level key whose value is empty — and SHALL NOT carry it as the value of a field that names the concept of shape.

A label SHALL NOT take a value. A record whose shape label carries a value SHALL be quarantined, because a label with a value is a shape-naming field under another name.

#### Scenario: A record carries its shape as a label

- **WHEN** a file in the canonical entity namespace carries a bare label naming a known shape
- **THEN** it SHALL be decoded as that shape
- **AND** re-encoding it SHALL produce a byte-identical file

#### Scenario: A shape label is given a value

- **WHEN** a file carries a shape label with a non-empty value
- **THEN** the file SHALL be quarantined with a reason stating that a shape label does not take a value

#### Scenario: Shape is not inferred from other fields

- **WHEN** a file carries the fields characteristic of a shape but no label
- **THEN** the file SHALL be quarantined rather than classified by its fields, so that the label remains the single place where shape is stated


<!-- @trace
source: add-entity-shape-label
updated: 2026-08-02
code:
  - .agents/skills/spectra-ingest/SKILL.md
  - Sources/akashic/Commands.swift
  - Sources/AkashicCore/Temporal.swift
  - Sources/AkashicCore/YAML.swift
  - .agents/skills/spectra-drift/SKILL.md
  - docs/design-principles-and-philosophy.md
  - .agents/skills/spectra-audit/SKILL.md
  - Sources/AkashicCore/Organization.swift
  - Sources/AkashicStoreIO/LibraryStore.swift
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - Tests/AkashicKitTests/OrganizationTests.swift
  - .agents/skills/spectra-commit/SKILL.md
  - Tests/AkashicKitTests/TemporalPersonTests.swift
  - CLAUDE.md
  - Tests/AkashicKitTests/AliasEventBudgetTests.swift
  - Sources/AkashicStoreIO/StoreVersion.swift
  - Tests/AkashicKitTests/EntityShapeLabelTests.swift
  - docs/explainers/entity-vs-view.md
  - .agents/skills/spectra-archive/SKILL.md
  - Sources/AkashicCore/DeterministicUUID.swift
  - docs/store-format.md
  - docs/explainers/yaml-alias-dos.md
  - .spectra.yaml
  - Sources/AkashicExport/RelationalExport.swift
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - Tests/AkashicKitTests/RelationalExportTests.swift
  - Sources/AkashicCore/AliasEventBudget.swift
  - AGENTS.md
  - .agents/skills/spectra-debug/SKILL.md
  - Sources/AkashicStoreIO/StoreMigration.swift
-->

---
### Requirement: A write SHALL NOT overwrite an entity file holding another record (#631)

In the entities layout every record is written to `entities/<id>.yaml`. Before writing, the system SHALL confirm that the destination either does not exist or decodes to a record of the same shape and the same identifier; otherwise it SHALL refuse the write by name and leave the destination untouched. When a work or person exists only as a legacy copy (`entries/<citekey>.yaml` or `people/<key>.yaml` with the same identifier, and no file under `entities/`), writing it SHALL move it: the record is written under `entities/` and the legacy copy is removed, because the single copy is the source of the new content. When both a legacy copy and the `entities/` file exist for the same identifier, the write SHALL be refused by name and neither copy SHALL be deleted, because the two may have diverged. Multi-file operations (rename, rename-person, merges, venue apply) SHALL run these checks for every record they will write before the first write. A destination quarantined for its shape label, its identifier or an invalid key counts as holding another record.

#### Scenario: The destination is a quarantined record

- **GIVEN** `entities/<id>.yaml` holds a record the store cannot load (quarantined)
- **WHEN** any writer writes a record with that identifier
- **THEN** the write is refused by name and the destination's bytes are unchanged

#### Scenario: A record that exists only as a legacy copy is moved

- **GIVEN** a work whose only copy is `entries/<citekey>.yaml`
- **WHEN** the work is written or renamed
- **THEN** the record is written under `entities/` and the legacy copy is removed, leaving exactly one copy

#### Scenario: Both a legacy copy and the entities file exist

- **GIVEN** a work with both `entries/<citekey>.yaml` and `entities/<id>.yaml` for the same identifier
- **WHEN** the work is written
- **THEN** the write is refused by name and both files are unchanged

### Requirement: Shape labels SHALL be drawn from a closed set

The closed set of recognized top-level entity shape labels SHALL be `work:`, `person:`, `organization:`, `divergence:`, and `venue:` (added by this change). A file under `entities/` whose first line is not one of these labels SHALL NOT be silently skipped by any enumeration path; the behavior (quarantine with report) SHALL be uniform across CLI, MCP, and App read surfaces.

#### Scenario: Venue label is recognized by enumeration

- **GIVEN** a store containing a valid `venue:` file
- **WHEN** any read surface enumerates entities
- **THEN** the venue record is decoded and counted, not skipped

#### Scenario: Unrecognized label is surfaced, not skipped

- **GIVEN** a file under `entities/` whose first line is `series:`
- **WHEN** enumeration runs
- **THEN** the file is reported as unrecognized (quarantine report), not silently omitted from counts


<!-- @trace
source: add-venue-entities
updated: 2026-08-17
code:
  - .vscode/launch.json
-->

---
### Requirement: A record MAY carry more than one shape label

Shape labels SHALL form a set rather than a single value, so that an ontology which is not a flat partition can be expressed.

A record SHALL record only those labels that cannot be derived from the schema. Where one shape is subsumed by another, only the more specific label SHALL be written, because subsumption is a fact about the schema rather than about each record.

Where several labels are present, the most specific SHALL determine which decoder is used.

#### Scenario: A record carries a specific and a general label

- **WHEN** a file carries two labels, one of which is subsumed by the other
- **THEN** the more specific label SHALL determine the decoder
- **AND** the presence of the derivable label SHALL be reported as redundant


<!-- @trace
source: add-entity-shape-label
updated: 2026-08-02
code:
  - .agents/skills/spectra-ingest/SKILL.md
  - Sources/akashic/Commands.swift
  - Sources/AkashicCore/Temporal.swift
  - Sources/AkashicCore/YAML.swift
  - .agents/skills/spectra-drift/SKILL.md
  - docs/design-principles-and-philosophy.md
  - .agents/skills/spectra-audit/SKILL.md
  - Sources/AkashicCore/Organization.swift
  - Sources/AkashicStoreIO/LibraryStore.swift
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - Tests/AkashicKitTests/OrganizationTests.swift
  - .agents/skills/spectra-commit/SKILL.md
  - Tests/AkashicKitTests/TemporalPersonTests.swift
  - CLAUDE.md
  - Tests/AkashicKitTests/AliasEventBudgetTests.swift
  - Sources/AkashicStoreIO/StoreVersion.swift
  - Tests/AkashicKitTests/EntityShapeLabelTests.swift
  - docs/explainers/entity-vs-view.md
  - .agents/skills/spectra-archive/SKILL.md
  - Sources/AkashicCore/DeterministicUUID.swift
  - docs/store-format.md
  - docs/explainers/yaml-alias-dos.md
  - .spectra.yaml
  - Sources/AkashicExport/RelationalExport.swift
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - Tests/AkashicKitTests/RelationalExportTests.swift
  - Sources/AkashicCore/AliasEventBudget.swift
  - AGENTS.md
  - .agents/skills/spectra-debug/SKILL.md
  - Sources/AkashicStoreIO/StoreMigration.swift
-->

---
### Requirement: The bibliographic type SHALL NOT name a shape

The field carrying a work's bibliographic type SHALL play no part in determining shape, and SHALL retain an open value domain.

A record whose shape label contradicts a shape name appearing in that field SHALL be quarantined rather than resolved in favour of either signal. Where the field merely repeats what the label already states, its value SHALL be ignored and SHALL NOT be written back.

#### Scenario: An unfamiliar bibliographic type is loaded

- **WHEN** a work carries a bibliographic type that the store has not seen before
- **THEN** it SHALL load normally, because the value domain is open

#### Scenario: The bibliographic type contradicts the label

- **WHEN** a file carries a label naming one shape and a bibliographic type naming a different shape
- **THEN** the file SHALL be quarantined

#### Scenario: A redundant shape name is dropped on rewrite

- **WHEN** a record carries a label together with a bibliographic type field repeating that same shape name
- **THEN** the record SHALL load, and re-encoding it SHALL omit the redundant field


<!-- @trace
source: add-entity-shape-label
updated: 2026-08-02
code:
  - .agents/skills/spectra-ingest/SKILL.md
  - Sources/akashic/Commands.swift
  - Sources/AkashicCore/Temporal.swift
  - Sources/AkashicCore/YAML.swift
  - .agents/skills/spectra-drift/SKILL.md
  - docs/design-principles-and-philosophy.md
  - .agents/skills/spectra-audit/SKILL.md
  - Sources/AkashicCore/Organization.swift
  - Sources/AkashicStoreIO/LibraryStore.swift
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - Tests/AkashicKitTests/OrganizationTests.swift
  - .agents/skills/spectra-commit/SKILL.md
  - Tests/AkashicKitTests/TemporalPersonTests.swift
  - CLAUDE.md
  - Tests/AkashicKitTests/AliasEventBudgetTests.swift
  - Sources/AkashicStoreIO/StoreVersion.swift
  - Tests/AkashicKitTests/EntityShapeLabelTests.swift
  - docs/explainers/entity-vs-view.md
  - .agents/skills/spectra-archive/SKILL.md
  - Sources/AkashicCore/DeterministicUUID.swift
  - docs/store-format.md
  - docs/explainers/yaml-alias-dos.md
  - .spectra.yaml
  - Sources/AkashicExport/RelationalExport.swift
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - Tests/AkashicKitTests/RelationalExportTests.swift
  - Sources/AkashicCore/AliasEventBudget.swift
  - AGENTS.md
  - .agents/skills/spectra-debug/SKILL.md
  - Sources/AkashicStoreIO/StoreMigration.swift
-->

---
### Requirement: Existing records SHALL be migrated without loss

Records written before this change carry no shape label. Migration SHALL add the label to each existing record and SHALL leave the remainder of each record unchanged.

Migration SHALL verify every record before writing any record, SHALL be idempotent under re-run, and SHALL NOT raise the store format marker until every step has succeeded.

#### Scenario: An existing store is migrated

- **WHEN** a store written before this change is migrated
- **THEN** every record SHALL gain a shape label
- **AND** every record SHALL be otherwise byte-identical to its previous content

#### Scenario: Migration is interrupted

- **WHEN** migration is interrupted partway
- **THEN** no record SHALL have been lost
- **AND** re-running migration SHALL complete it without duplicating work already done


<!-- @trace
source: add-entity-shape-label
updated: 2026-08-02
code:
  - .agents/skills/spectra-ingest/SKILL.md
  - Sources/akashic/Commands.swift
  - Sources/AkashicCore/Temporal.swift
  - Sources/AkashicCore/YAML.swift
  - .agents/skills/spectra-drift/SKILL.md
  - docs/design-principles-and-philosophy.md
  - .agents/skills/spectra-audit/SKILL.md
  - Sources/AkashicCore/Organization.swift
  - Sources/AkashicStoreIO/LibraryStore.swift
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - Tests/AkashicKitTests/OrganizationTests.swift
  - .agents/skills/spectra-commit/SKILL.md
  - Tests/AkashicKitTests/TemporalPersonTests.swift
  - CLAUDE.md
  - Tests/AkashicKitTests/AliasEventBudgetTests.swift
  - Sources/AkashicStoreIO/StoreVersion.swift
  - Tests/AkashicKitTests/EntityShapeLabelTests.swift
  - docs/explainers/entity-vs-view.md
  - .agents/skills/spectra-archive/SKILL.md
  - Sources/AkashicCore/DeterministicUUID.swift
  - docs/store-format.md
  - docs/explainers/yaml-alias-dos.md
  - .spectra.yaml
  - Sources/AkashicExport/RelationalExport.swift
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - Tests/AkashicKitTests/RelationalExportTests.swift
  - Sources/AkashicCore/AliasEventBudget.swift
  - AGENTS.md
  - .agents/skills/spectra-debug/SKILL.md
  - Sources/AkashicStoreIO/StoreMigration.swift
-->

---
### Requirement: The store format version SHALL be raised

Because records written under this change carry a label that earlier binaries do not recognise, the store format marker SHALL be raised, so that an earlier binary refuses the store and reports that an upgrade is needed.

#### Scenario: An earlier binary opens an upgraded store

- **WHEN** a binary that predates this change opens a store written under it
- **THEN** it SHALL refuse the store and state that a newer binary is required
- **AND** it SHALL NOT report per-file errors whose stated reasons are unrelated to the actual cause

<!-- @trace
source: add-entity-shape-label
updated: 2026-08-02
code:
  - .agents/skills/spectra-ingest/SKILL.md
  - Sources/akashic/Commands.swift
  - Sources/AkashicCore/Temporal.swift
  - Sources/AkashicCore/YAML.swift
  - .agents/skills/spectra-drift/SKILL.md
  - docs/design-principles-and-philosophy.md
  - .agents/skills/spectra-audit/SKILL.md
  - Sources/AkashicCore/Organization.swift
  - Sources/AkashicStoreIO/LibraryStore.swift
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - Tests/AkashicKitTests/OrganizationTests.swift
  - .agents/skills/spectra-commit/SKILL.md
  - Tests/AkashicKitTests/TemporalPersonTests.swift
  - CLAUDE.md
  - Tests/AkashicKitTests/AliasEventBudgetTests.swift
  - Sources/AkashicStoreIO/StoreVersion.swift
  - Tests/AkashicKitTests/EntityShapeLabelTests.swift
  - docs/explainers/entity-vs-view.md
  - .agents/skills/spectra-archive/SKILL.md
  - Sources/AkashicCore/DeterministicUUID.swift
  - docs/store-format.md
  - docs/explainers/yaml-alias-dos.md
  - .spectra.yaml
  - Sources/AkashicExport/RelationalExport.swift
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - Tests/AkashicKitTests/RelationalExportTests.swift
  - Sources/AkashicCore/AliasEventBudget.swift
  - AGENTS.md
  - .agents/skills/spectra-debug/SKILL.md
  - Sources/AkashicStoreIO/StoreMigration.swift
-->