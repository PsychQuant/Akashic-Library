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
### Requirement: Shape labels SHALL be drawn from a closed set

The set of shape labels SHALL be closed. A record carrying a label that is not a known shape SHALL be quarantined, and the reason SHALL name the unrecognised label.

A record carrying no shape label SHALL be quarantined with a reason distinct from the unrecognised-label reason, because the two describe different mistakes.

Where the unrecognised label names something the project handles elsewhere, the reason SHALL say where it belongs. Naming a sign as unrecognised establishes only that it has no meaning in this position; a reader also needs to know the position in which it does have one.

Membership of the set SHALL change only by a recorded decision that the candidate selects a record shape, per the discriminating test the entity-boundary capability states. Closure is a property of how the set changes, not a claim that it is finished — a set that grows by argument is still closed against labels that arrive without one.

#### Scenario: A formal concept is proposed as a shape

- **WHEN** a file carries a label naming a formal concept such as a view
- **THEN** the file SHALL be quarantined
- **AND** the reason SHALL name that label as unrecognised, rather than reporting a generic classification failure
- **AND** the reason SHALL state where a definition of that kind does belong, so that the report distinguishes a misplaced sign from a meaningless one

#### Scenario: A record carries no label

- **WHEN** a file carries no shape label
- **THEN** the file SHALL be quarantined with a reason stating that the shape label is missing

#### Scenario: One unclassifiable record does not stop the load

- **WHEN** one file in the canonical entity namespace cannot be classified
- **THEN** the remaining files SHALL still load, and the unclassifiable file SHALL appear in the quarantine report

#### Scenario: A label admitted by the discriminating test is recognised

- **WHEN** a file carries a label that names a shape admitted to the set by a recorded shape-selection decision
- **THEN** the file SHALL be decoded as that shape rather than quarantined

##### Example: The identity-question shape

- **GIVEN** the label naming a record of an unresolved identity question, admitted because it determines its own fields and therefore its own decoder
- **WHEN** a file carrying that label is loaded
- **THEN** it SHALL be decoded as that shape
- **AND** re-encoding it SHALL produce a byte-identical file


<!-- @trace
source: add-divergence-record
updated: 2026-08-05
code:
  - Sources/AkashicStoreIO/LibraryStore.swift
  - README.md
  - Tests/AkashicKitTests/ExportTests.swift
  - Tests/AkashicMCPTests/ServiceTests.swift
  - docs/store-format.md
  - Sources/AkashicCore/DeterministicUUID.swift
  - Sources/AkashicExport/BibExport.swift
  - Tests/AkashicKitTests/RelationalExportTests.swift
  - Tests/AkashicKitTests/PersonDeceasedTests.swift
  - Tests/AkashicKitTests/DivergenceRecordTests.swift
  - Sources/AkashicMCPKit/AkashicService.swift
  - Sources/AkashicCore/AuthorizedName.swift
  - Sources/AkashicStoreIO/StoreVersion.swift
  - Sources/AkashicCore/Models.swift
  - Sources/AkashicCore/YAML.swift
  - Sources/akashic/Commands.swift
  - Sources/AkashicStoreIO/DivergenceResolve.swift
  - Sources/AkashicWoSImport/WoSImport.swift
  - Tests/AkashicCLITests/CLIIntegrationTests.swift
  - Tests/AkashicKitTests/WoSImportTests.swift
  - Sources/AkashicCore/Organization.swift
  - Sources/AkashicExport/RelationalExport.swift
  - Sources/AkashicExport/CSLExport.swift
  - Sources/AkashicStoreIO/AuthorizedNameMigration.swift
  - Tests/AkashicKitTests/AuthorizedNameTests.swift
  - Sources/akashic/CLI.swift
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