# entity-boundary Specification

## Purpose

TBD - created by archiving change 'add-formal-concept-boundary'. Update Purpose after archive.

## Requirements

### Requirement: Formal concepts SHALL NOT occupy the canonical entity namespace

A *formal concept* is an expression whose role is to select, group, or index entities — a view, a classification, a query, a saved filter, or an index structure. A formal concept is recognised by what it fails to do: it determines no fields of its own, so the loader must decode it as some existing shape.

The canonical entity namespace (`entities/<uuid>.yaml`) SHALL contain only records that determine their own fields. Formal concepts SHALL NOT be stored there, and SHALL NOT be assigned an entity UUID.

The discriminating test SHALL be whether the candidate corresponds to a record shape — that is, whether it determines which fields exist and therefore which decoder the loader dispatches to. The test SHALL be stated independently of how a shape is marked in a file, because the marking mechanism may change while the criterion does not. Identity, a stable name, aliases, and a change history are necessary but NOT sufficient: an index schema version has all four and is not an entity.

Being referred to by other records SHALL NOT be required for admission, and grouping entities SHALL NOT by itself be grounds for refusal. Both criteria were previously implied by describing the admitted class as "something referred to in the world" and the refused class as anything that groups entities. Neither survives contact with the discriminating test: a record of an unresolved identity question groups two entities and is referred to by nothing, yet it determines its own fields and therefore selects its own decoder, while a view is referred to by configuration and still selects no shape. Where the earlier phrasing and the test disagree, the test SHALL govern — it is the criterion the loader actually enforces.

#### Scenario: A record that groups entities but selects its own shape is admitted

- **WHEN** a candidate groups two or more entities, is referred to by no other record, and determines a set of fields that no existing shape decodes
- **THEN** it SHALL be admitted, because the discriminating test asks what the loader must dispatch to, not what points at the record

##### Example: An unresolved identity question

- **GIVEN** a candidate whose fields are a question in words, a list of candidate entity references, and an optional judgment with its evidence
- **AND** that nothing in the store refers to it, and that it exists to group two entities
- **WHEN** the discriminating test is applied
- **THEN** it SHALL be admitted, because no existing decoder reads those fields
- **AND** the contrast with a view SHALL be recorded: a view groups entities too, but a view's fields are decodable as an existing shape, so no dispatch decision turns on it


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
### Requirement: The entity criterion SHALL be stated as a single discriminating test

The design principles document SHALL state, in its normative subsection on first-class entities, exactly one discriminating test for entity-hood: whether the candidate selects a record shape.

The document MAY cite relation-endpoint participation as a corroborating symptom, but SHALL NOT present it as the criterion, because a contributor can satisfy it by adding a relation, whereas shape selection is a fact about the notation that cannot be added to.

The document SHALL NOT present the full list of entity characteristics as if any subset were sufficient, because that presentation is what permitted the incorrect inference recorded in the accompanying explainer.

#### Scenario: A reader consults the document to classify a candidate

- **WHEN** a reader or agent needs to decide whether a proposed artifact belongs in the canonical entity namespace
- **THEN** the document SHALL provide a citable normative statement using MUST NOT, together with the shape-selection test
- **AND** the reader SHALL be able to reach a decision without inferring which characteristics are load-bearing


<!-- @trace
source: add-formal-concept-boundary
updated: 2026-08-02
code:
  - CLAUDE.md
  - Sources/AkashicCore/Temporal.swift
  - AGENTS.md
  - .agents/skills/spectra-drift/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - Tests/AkashicKitTests/OrganizationTests.swift
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - docs/design-principles-and-philosophy.md
  - .spectra.yaml
  - Sources/AkashicCore/DeterministicUUID.swift
  - Sources/AkashicCore/AliasEventBudget.swift
  - docs/explainers/yaml-alias-dos.md
  - Sources/AkashicCore/Organization.swift
  - Sources/AkashicStoreIO/StoreVersion.swift
  - Sources/AkashicStoreIO/StoreMigration.swift
  - docs/store-format.md
  - .agents/skills/spectra-debug/SKILL.md
  - .agents/skills/spectra-apply/SKILL.md
  - Sources/AkashicStoreIO/LibraryStore.swift
  - Tests/AkashicKitTests/EntityShapeLabelTests.swift
  - .agents/skills/spectra-propose/SKILL.md
  - Sources/akashic/Commands.swift
  - docs/explainers/entity-vs-view.md
  - .agents/skills/spectra-audit/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - Sources/AkashicExport/RelationalExport.swift
  - Tests/AkashicKitTests/TemporalPersonTests.swift
  - Tests/AkashicKitTests/RelationalExportTests.swift
  - Tests/AkashicKitTests/AliasEventBudgetTests.swift
  - Sources/AkashicCore/YAML.swift
-->

---
### Requirement: Predicates SHALL be expressed as fields on the shapes they apply to

A *predicate* relates a record to another record or to a value: authorship, citation, affiliation, containment. The set of record shapes a predicate applies to is its domain.

A predicate's domain SHALL be expressed by which record shapes carry the corresponding field, and SHALL NOT be expressed as stored data.

The canonical store SHALL NOT contain a generic edge table of the form `(subject, predicate, object)`, and SHALL NOT contain metadata that declares which subjects a predicate admits. A graph or triple representation MAY exist as a derived artifact, on the same footing as the relational export, because a derived layer can be discarded and rebuilt.

Extending a predicate's domain SHALL require a schema change, not the insertion of a record.

#### Scenario: A predicate is proposed for a shape it does not apply to

- **WHEN** a contributor proposes recording an institutional affiliation directly on a work
- **THEN** the absence of the field on that shape SHALL be treated as the statement of the rule, and the proposal SHALL be rejected
- **AND** the apparent affiliation of a work SHALL be recognised as shorthand for the affiliations its authors held at the time, which is derived rather than primitive

#### Scenario: A generic edge table is proposed

- **WHEN** a contributor proposes replacing the per-shape predicate fields with a single canonical table of subject-predicate-object rows
- **THEN** the proposal SHALL be rejected for the canonical store, because such a table makes every predicate a sibling of every other and therefore admits rows whose subject shape does not carry the predicate
- **AND** the same representation MAY still be produced as a derived export

#### Scenario: A predicate domain declaration is proposed as data

- **WHEN** a contributor proposes a table or file that records, for each predicate, which record shapes may appear as its subject
- **THEN** the proposal SHALL be rejected, because it would make extending a domain indistinguishable from asserting a fact — both become a single inserted row
- **AND** the distinction between changing the grammar and stating something in it SHALL remain visible in the cost of the change

#### Scenario: Two predicates share a surface form

- **WHEN** one word in natural language covers both a person's membership in an organisation and one organisation's containment within another
- **THEN** they SHALL be modelled as two predicates on two shapes, not merged into one predicate on a shared supertype
- **AND** the shared surface form SHALL NOT be treated as evidence of a shared predicate


<!-- @trace
source: add-formal-concept-boundary
updated: 2026-08-02
code:
  - CLAUDE.md
  - Sources/AkashicCore/Temporal.swift
  - AGENTS.md
  - .agents/skills/spectra-drift/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - Tests/AkashicKitTests/OrganizationTests.swift
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - docs/design-principles-and-philosophy.md
  - .spectra.yaml
  - Sources/AkashicCore/DeterministicUUID.swift
  - Sources/AkashicCore/AliasEventBudget.swift
  - docs/explainers/yaml-alias-dos.md
  - Sources/AkashicCore/Organization.swift
  - Sources/AkashicStoreIO/StoreVersion.swift
  - Sources/AkashicStoreIO/StoreMigration.swift
  - docs/store-format.md
  - .agents/skills/spectra-debug/SKILL.md
  - .agents/skills/spectra-apply/SKILL.md
  - Sources/AkashicStoreIO/LibraryStore.swift
  - Tests/AkashicKitTests/EntityShapeLabelTests.swift
  - .agents/skills/spectra-propose/SKILL.md
  - Sources/akashic/Commands.swift
  - docs/explainers/entity-vs-view.md
  - .agents/skills/spectra-audit/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - Sources/AkashicExport/RelationalExport.swift
  - Tests/AkashicKitTests/TemporalPersonTests.swift
  - Tests/AkashicKitTests/RelationalExportTests.swift
  - Tests/AkashicKitTests/AliasEventBudgetTests.swift
  - Sources/AkashicCore/YAML.swift
-->

---
### Requirement: Borrowed philosophical vocabulary SHALL name its source

Where the design principles document borrows a technical term from an external philosophical source, the document SHALL name that source.

This applies at minimum to the term rendered as 事態, which is a precise borrowing of *Sachverhalt* from Wittgenstein's *Tractatus Logico-Philosophicus*.

#### Scenario: A reader encounters borrowed vocabulary

- **WHEN** a reader encounters 事態 in the section on recordable units
- **THEN** the document SHALL make it discoverable that the term is a precise borrowing rather than an incidental Chinese word
- **AND** the full argument SHALL live in an explainer, so that the normative document remains scannable for MUST and SHALL statements


<!-- @trace
source: add-formal-concept-boundary
updated: 2026-08-02
code:
  - CLAUDE.md
  - Sources/AkashicCore/Temporal.swift
  - AGENTS.md
  - .agents/skills/spectra-drift/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - Tests/AkashicKitTests/OrganizationTests.swift
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - docs/design-principles-and-philosophy.md
  - .spectra.yaml
  - Sources/AkashicCore/DeterministicUUID.swift
  - Sources/AkashicCore/AliasEventBudget.swift
  - docs/explainers/yaml-alias-dos.md
  - Sources/AkashicCore/Organization.swift
  - Sources/AkashicStoreIO/StoreVersion.swift
  - Sources/AkashicStoreIO/StoreMigration.swift
  - docs/store-format.md
  - .agents/skills/spectra-debug/SKILL.md
  - .agents/skills/spectra-apply/SKILL.md
  - Sources/AkashicStoreIO/LibraryStore.swift
  - Tests/AkashicKitTests/EntityShapeLabelTests.swift
  - .agents/skills/spectra-propose/SKILL.md
  - Sources/akashic/Commands.swift
  - docs/explainers/entity-vs-view.md
  - .agents/skills/spectra-audit/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - Sources/AkashicExport/RelationalExport.swift
  - Tests/AkashicKitTests/TemporalPersonTests.swift
  - Tests/AkashicKitTests/RelationalExportTests.swift
  - Tests/AkashicKitTests/AliasEventBudgetTests.swift
  - Sources/AkashicCore/YAML.swift
-->

---
### Requirement: The boundary SHALL be documented with a recorded failure case

The explainer accompanying this boundary SHALL include at least one real misclassification that occurred, stating what was proposed, why it appeared reasonable at the time, and where the artifact correctly belongs.

Abstract statements of the rule alone SHALL NOT be considered sufficient documentation, because a reader who believes their case is different will not be stopped by an abstract rule.

#### Scenario: A reader is about to repeat a known misclassification

- **WHEN** a reader considers storing a formal concept as an entity, reasoning that it has identity and changes over time
- **THEN** the explainer SHALL show that exact reasoning having been made and corrected
- **AND** the explainer SHALL state which inference step was invalid

<!-- @trace
source: add-formal-concept-boundary
updated: 2026-08-02
code:
  - CLAUDE.md
  - Sources/AkashicCore/Temporal.swift
  - AGENTS.md
  - .agents/skills/spectra-drift/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - Tests/AkashicKitTests/OrganizationTests.swift
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - docs/design-principles-and-philosophy.md
  - .spectra.yaml
  - Sources/AkashicCore/DeterministicUUID.swift
  - Sources/AkashicCore/AliasEventBudget.swift
  - docs/explainers/yaml-alias-dos.md
  - Sources/AkashicCore/Organization.swift
  - Sources/AkashicStoreIO/StoreVersion.swift
  - Sources/AkashicStoreIO/StoreMigration.swift
  - docs/store-format.md
  - .agents/skills/spectra-debug/SKILL.md
  - .agents/skills/spectra-apply/SKILL.md
  - Sources/AkashicStoreIO/LibraryStore.swift
  - Tests/AkashicKitTests/EntityShapeLabelTests.swift
  - .agents/skills/spectra-propose/SKILL.md
  - Sources/akashic/Commands.swift
  - docs/explainers/entity-vs-view.md
  - .agents/skills/spectra-audit/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - Sources/AkashicExport/RelationalExport.swift
  - Tests/AkashicKitTests/TemporalPersonTests.swift
  - Tests/AkashicKitTests/RelationalExportTests.swift
  - Tests/AkashicKitTests/AliasEventBudgetTests.swift
  - Sources/AkashicCore/YAML.swift
-->

---
### Requirement: Admissions to the entity namespace SHALL be recorded with their reasoning

When a candidate is admitted to the canonical entity namespace, the decision SHALL be recorded together with the reasoning that the discriminating test produced — which fields the candidate determines, and therefore which decoder it selects.

Recording the reasoning SHALL be required because the test is stated once but applied repeatedly; without the applications on record, a later contributor sees only a list of admitted shapes and cannot tell which of the necessary-but-insufficient criteria did the work. That is the inference the accompanying explainer records as incorrect.

A recorded admission SHALL cite the contrast that made the decision non-trivial — a candidate the test rejects for the same reason this one passes — so that the record teaches the test rather than merely reporting its outcome.

This requirement SHALL apply to admissions made after it takes effect. Shapes already in the set when it takes effect SHALL NOT be treated as incomplete for lacking such a record. The scoping is deliberate rather than an oversight: a requirement that declares the set retroactively incomplete on the day it lands says nothing about what anyone should do, and the reasoning for an earlier admission reconstructed years later is not the reasoning that was actually applied. Where an earlier admission's reasoning is wanted, it SHALL be recovered from that admission's own change rather than invented here.

#### Scenario: An admission is recorded with its reasoning

- **WHEN** a candidate is admitted to the canonical entity namespace
- **THEN** the record SHALL state which fields the candidate determines
- **AND** it SHALL cite a rejected candidate that fails the same test

##### Example: A record of an unresolved identity question is admitted

- **GIVEN** a candidate whose fields are a question in words, a list of candidate entity references, and an optional judgment with its evidence
- **WHEN** the discriminating test is applied
- **THEN** the candidate SHALL be admitted, because those fields exist only on this shape and the loader must dispatch to a decoder that reads them
- **AND** the record SHALL cite the view as the contrasting rejection: a view selects no shape of its own, so the loader would decode it as some existing shape, whereas this candidate cannot be decoded as any existing shape

#### Scenario: An admission without recorded reasoning is incomplete

- **WHEN** a shape is added to the known set with no recorded shape-selection reasoning
- **THEN** the addition SHALL be treated as incomplete, because the set's closure is a property of how it changes and an unargued addition does not exhibit that property

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