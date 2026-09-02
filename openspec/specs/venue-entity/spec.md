# venue-entity Specification

## Purpose

TBD - created by archiving change 'add-venue-entities'. Update Purpose after archive.

## Requirements

### Requirement: Venue entity shape

The store SHALL support a first-class `venue` entity with top-level shape label `venue:`, carrying `id` (v4 UUID, single-origin, never recomputed from names), `key` (StoreKey grammar), `type` (closed enumeration — unknown values SHALL reject the whole file), flat `names` list with **two optional top-level partitions over it — `authorized` and `variant`** — and optional `note`.

The two partitions SHALL be disjoint: a name appearing in both `authorized` and `variant` SHALL fail validation. A name in neither is unclassified, which is a legitimate state (it makes no claim either way) and SHALL NOT fail validation.

This supersedes the earlier ruling that venue names follow the organization pattern *and not* the person partition. That ruling assumed `names`' multiplicity would carry renaming history, with aliases rare enough to live in `authorized`'s complement. Measured 11 days later across 405 venues: renaming history **0**, spelling variants **35**. The predicted primary use has no instances; the use predicted to be marginal is the only one.

The partitions are flat top-level lists (as `authorized` already is), not the nested person shape — 402 records already carry `authorized` at the top level, and restructuring them buys only cosmetic symmetry with `person`.

#### Scenario: A name in both partitions fails validation

- **GIVEN** a venue whose `authorized` and `variant` both contain `PLOS ONE`
- **WHEN** the store validates it
- **THEN** validation fails naming the offending name, because a name cannot be simultaneously the authorized form and a variant of it

#### Scenario: An unclassified name is not an error

- **GIVEN** a venue whose `names` carries three values, one listed in `authorized` and none in `variant`
- **WHEN** the store validates it
- **THEN** validation passes — the other two make no claim about their status, which is the honest state before anyone has judged them


<!-- @trace
source: venue-name-variants
updated: 2026-08-28
code:
  - Sources/AkashicMCPKit/AkashicService.swift
  - Sources/akashic/CLI.swift
  - Sources/AkashicStoreIO/VenueVariantMigration.swift
  - Sources/akashic/VenueCommand.swift
-->

---
### Requirement: Venue name history timeline

A venue `names` item MAY carry temporal fields (`start`, `end`, `ended`, `attested`) reusing the existing timeline-segment semantics, expressing journal renaming history. A names item without temporal fields SHALL make no claim about a time span.

**Names listed in the `variant` partition SHALL NOT carry temporal fields.** A spelling variant has no "in force from" date — asking when `PLoS One` started being a variant of `PLOS ONE` is not a question about the world. Temporal fields are reserved for renaming history, which is the use this requirement was written for.

This requirement is retained despite having zero instances. Renaming history is a real phenomenon (JRSS Series B/C is an unexpressed instance in the store today); the reason it has no instances is that variants were occupying its slot. Narrowing the scope turns "zero instances" from an embarrassment — the declared use going unused — into an honest state: that use has not been met yet, and nothing else is standing in its place.

#### Scenario: A variant carrying a date fails validation

- **GIVEN** a venue whose `variant` partition lists a name and that same names item carries `start: 2003`
- **WHEN** the store validates it
- **THEN** validation fails, because temporal fields express renaming history and a variant is not a rename

#### Scenario: Renamed journal keeps both names with spans

- **GIVEN** a venue whose `names` contains an old title with `end: 2003` and a current title with `start: 2003`, neither listed in `variant`
- **WHEN** the venue is presented
- **THEN** both names are shown with their spans, and the current title is derivable without deleting the old one


<!-- @trace
source: venue-name-variants
updated: 2026-08-28
code:
  - Sources/AkashicMCPKit/AkashicService.swift
  - Sources/akashic/CLI.swift
  - Sources/AkashicStoreIO/VenueVariantMigration.swift
  - Sources/akashic/VenueCommand.swift
-->

---
### Requirement: Entry venues reference edge

An entry SHALL support an ordered `venues` list whose elements are two-state references (`key` resolved to a venue entity, or `literal` verbatim string). The canonical side of the edge is the work side; the reverse direction (venue → works) SHALL always be derived, never stored on the venue record. Intake SHALL create these references as `literal` only (literal-first rule); promotion to `key` happens only through explicit resolution.

#### Scenario: Importer never guesses a venue key

- **GIVEN** a WoS row whose journal title exactly matches an existing venue's name
- **WHEN** the importer creates the entry
- **THEN** the entry's `venues` element is `literal` with the verbatim string, not `key`

#### Scenario: Venue record stores no article list

- **GIVEN** a venue with N referencing works
- **WHEN** its YAML record is inspected
- **THEN** it contains no list of works; the chronological article list is computed from the index at presentation time


<!-- @trace
source: add-venue-entities
updated: 2026-08-17
code:
-->

---
### Requirement: Chronological presentation

The venue read surface (CLI `akashic venue`, MCP `akashic_venue`) SHALL present the venue record, its name history, and the chronological list of referencing works ordered by publication year ascending. An empty list SHALL be reported as "zero works", distinct from "venue not found".

#### Scenario: Empty venue is not an error

- **GIVEN** a venue entity with no referencing works
- **WHEN** `akashic venue <key>` runs
- **THEN** the record is shown with an explicit zero-works statement and exit status success


<!-- @trace
source: add-venue-entities
updated: 2026-08-17
code:
-->

---
### Requirement: Venue backfill migration

A `migrate-venues` command SHALL backfill existing entries' `venues` references from their bibliographic string fields (journaltitle and related), defaulting to dry-run, echoing the target store, requiring a tracked-and-clean store for `--apply`, adding only absent `venues` keys and never modifying existing fields (additive-only, per the lossless-intake backfill criterion).

#### Scenario: Backfill is additive and idempotent

- **GIVEN** a store where some entries already have `venues`
- **WHEN** `migrate-venues --apply` runs twice
- **THEN** entries with existing `venues` are untouched, absent ones gain literal references from their fields, and the second run reports zero changes


<!-- @trace
source: add-venue-entities
updated: 2026-08-17
code:
-->

---
### Requirement: Store format gate

Writing a venue entity or an entry `venues` edge into a store whose format marker is below 11 SHALL be rejected with `invalidInput` pointing at the deployment procedure. The format 11 bump rationale SHALL record the empirically tested behavior of older binaries encountering the unknown `venue:` shape.

#### Scenario: Format 10 store refuses venue writes

- **GIVEN** a store at `format: 10`
- **WHEN** a venue entity write is attempted
- **THEN** the write fails with `invalidInput` and no file is created


<!-- @trace
source: add-venue-entities
updated: 2026-08-17
code:
-->

---
### Requirement: Venue MCP and CLI parity

Every venue capability (view, list, resolve, add) SHALL ship both CLI and MCP faces registered in the parity adjudication tables, following the resolve-people contract shape for resolution and the add-person shape for single-record creation.

#### Scenario: Parity audit finds no unadjudicated venue surface

- **GIVEN** the implemented venue tools
- **WHEN** the mcp-cli-parity mechanical audit runs (tool-name and subcommand enumeration)
- **THEN** every venue MCP tool has a CLI row and every venue CLI subcommand appears in one of the two tables

<!-- @trace
source: add-venue-entities
updated: 2026-08-17
code:
-->