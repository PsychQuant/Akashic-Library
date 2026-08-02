# entity-boundary Specification

## Purpose

TBD - created by archiving change 'add-formal-concept-boundary'. Update Purpose after archive.

## Requirements

### Requirement: Formal concepts SHALL NOT occupy the canonical entity namespace

A *formal concept* is an expression whose role is to select, group, or index entities — a view, a classification, a query, a saved filter, or an index structure. A *first-class entity* is something referred to in the world: a person, a work, an organization.

The canonical entity namespace (`entities/<uuid>.yaml`) SHALL contain only first-class entities. Formal concepts SHALL NOT be stored there, and SHALL NOT be assigned an entity UUID.

The discriminating test SHALL be whether the candidate corresponds to a record shape — that is, whether it determines which fields exist and therefore which decoder the loader dispatches to. The test SHALL be stated independently of how a shape is marked in a file, because the marking mechanism may change while the criterion does not. Identity, a stable name, aliases, and a change history are necessary but NOT sufficient: an index schema version has all four and is not an entity.

#### Scenario: A view definition is proposed as an entity

- **WHEN** a contributor proposes storing a view definition (for example, a saved selection named "ISS people") as `entities/<uuid>.yaml` with `type: view`
- **THEN** the proposal SHALL be rejected, because no decoder is selected by that value — a view has no record shape of its own, and the loader would decode it as some existing shape

##### Example: The ISS view

- **GIVEN** a proposed file `entities/7a7f0a53-9d44-5f61-8b54-e3b8b791c7f8.yaml` containing `type: view`, `key: iss`, `name: 中研院統計所`, and a predicate matching `profile.affiliations`
- **WHEN** the shape-selection test is applied
- **THEN** the answer is that the value selects no shape, so the record SHALL NOT be an entity
- **AND** its predicate belongs in machine-local configuration and its extension belongs in the derived index

#### Scenario: A bibliographic type is mistaken for an entity kind

- **WHEN** a contributor observes that a shape name and a bibliographic type occupy the same key in a file and concludes that a third sibling value is therefore admissible
- **THEN** the shape-selection test SHALL separate them: one determines which fields exist and the other is a value inside a fixed set of fields
- **AND** getting the bibliographic type wrong SHALL be recognised as a factual error correctable by editing one field, whereas getting the shape wrong SHALL be recognised as a structural error that invalidates the remaining fields
- **AND** the shared key SHALL be recognised as the notational defect that invited the error, addressed by a separate change

#### Scenario: An artifact satisfies identity and mutability but selects no shape

- **WHEN** a candidate has a stable identity, a display name, aliases, and a recorded change history, but selects no record shape
- **THEN** the candidate SHALL NOT be stored in the canonical entity namespace, regardless of how many of the other criteria it satisfies


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