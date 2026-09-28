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

---
### Requirement: Venue name well-formedness

Every string in a venue's `names[].value`, `authorized`, and `variant` SHALL satisfy the following invariants at write time. A violation SHALL fail validation at error level, so every write surface refuses to write the record until it is fixed. Decoding SHALL NOT enforce them: a stored record that violates them still loads, and `validate`, the MCP `akashic_doctor` payload, and the App report it (the CLI `doctor` prints no per-record issues). The fix is a human edit of the YAML, with one mechanical exception: a string whose only violation is invariant 1, whose canonical form satisfies every other invariant, and whose record passes validation once all such strings in it are rewritten, MAY be rewritten by `akashic repair-venue-names`, which lists every rewrite in a dry run and writes only with `--apply`. No write surface SHALL silently rewrite a stored name.

1. **Canonical form.** The string SHALL be NFC, with no leading or trailing whitespace, and every run of `White_Space` scalars inside it collapsed to a single U+0020. Canonicalization removes only whitespace; no other scalar is dropped.
2. **No dangerous or invisible scalar.** The string SHALL contain no member of the output gate `UnsafeToEmitScalar`, except private-use (Co) scalars. ZWJ (U+200D) and ZWNJ (U+200C) are accepted only in the two joiner contexts defined in `docs/store-format.md` §5.7, and are rejected anywhere else.
3. **At least one letter or digit.** The string SHALL contain at least one scalar of general category L or N.
4. **No canonically equal pair within one list.** Within `names`, `authorized`, or `variant`, no two entries SHALL be canonically equal. The one exception is two `names` segments with the same name that are disjoint renaming-history segments: both make a temporal claim, one has an `end` and the other a `start`, both endpoints are ISO 8601 prefixes, both segments are valid intervals, and the earlier `end`, truncated to the coarser granularity of the two, is strictly before the later `start`. Equal endpoints after truncation count as overlap, and a segment with only `attested` or `ended-unknown` never qualifies.
5. **Per-group evaluation cap.** A group of canonically equal `names` segments SHALL be compared pairwise for at most 5,000 pairs. A group beyond that SHALL fail validation whether or not its pairs would qualify for the exception.
6. **Per-record evaluation cap.** The pairwise comparisons across all groups of one venue SHALL total at most 100,000 pairs. Groups that do not fit in the remaining budget are not evaluated, and the record SHALL fail validation.

The scalar classes behind invariant 2 (the output gate's property: Default_Ignorable_Code_Point, Cc, Cf, Zl, Zp, non-U+0020 Zs, Co, and the five code points that render blank without belonging to those classes — U+2800, U+13441, U+13442, U+16FE4, U+1D159), the two joiner contexts, and the wording of each message are specified in `docs/store-format.md` §5.7. That section is the per-character reference for this requirement and SHALL be kept consistent with it.

#### Scenario: A name with trailing whitespace fails validation

- **GIVEN** a venue whose `names` contains `Psychometrika ` with a trailing space
- **WHEN** the store validates it
- **THEN** validation fails at error level and the message says the name is not in canonical form

#### Scenario: A TAG character in a name fails validation

- **GIVEN** a venue whose `authorized` contains `Tag` followed by U+E0041 and `Name`
- **WHEN** the store validates it
- **THEN** validation fails at error level and the message names the code point U+E0041

#### Scenario: A Persian name with a legal ZWNJ passes

- **GIVEN** a venue whose `names` contains a Persian title with ZWNJ between two Arabic-script letters
- **WHEN** the store validates it
- **THEN** validation passes, because that ZWNJ is in a legal joiner context

#### Scenario: A name with no letter or digit fails validation

- **GIVEN** a venue whose `names` contains only `×`
- **WHEN** the store validates it
- **THEN** validation fails at error level

#### Scenario: A numeric title passes

- **GIVEN** a venue whose `names` contains `1843`
- **WHEN** the store validates it
- **THEN** validation passes, because digits count

#### Scenario: A renamed-back journal is exempt only when its segments are disjoint

- **GIVEN** a venue whose `names` contains `Sankhyā` with `start: 1933, end: 1960` and again `Sankhyā` with `start: 2002, end: 2007`
- **WHEN** the store validates it
- **THEN** validation passes
- **AND GIVEN** the second segment instead has `start: 1960`
- **THEN** validation fails, because equal endpoints after truncation count as overlap

#### Scenario: Canonically equal entries in one list fail validation

- **GIVEN** a venue whose `authorized` contains `Sankhyā` twice, both in canonical form
- **WHEN** the store validates it
- **THEN** validation fails at error level and the message names the near-duplicate pair

#### Scenario: An oversized same-name group fails even if every pair is exempt

- **GIVEN** a venue whose `names` contains more than 100 canonically equal segments, each a disjoint renaming-history segment
- **WHEN** the store validates it
- **THEN** validation fails at error level, because the group exceeds 5,000 pairwise comparisons

#### Scenario: A trailing-whitespace name is rewritten only on explicit apply

- **GIVEN** a stored venue whose `names` and `authorized` both contain `Psychometrika ` with a trailing space, in a store whose venue files are committed
- **WHEN** the operator runs `akashic repair-venue-names`
- **THEN** it lists both rewrites to `Psychometrika` and writes nothing
- **AND WHEN** the operator runs it again with `--apply`
- **THEN** both strings become `Psychometrika` and the record passes validation

#### Scenario: A name that needs judgment is only named

- **GIVEN** a stored venue whose `names` contains a string with U+200B
- **WHEN** the operator runs `akashic repair-venue-names --apply`
- **THEN** the record is not modified and the report names the string and the reason

<!-- @trace
source: venue-name-wellformedness-spec
updated: 2026-09-27
code:
  - Sources/AkashicCore/Venue.swift
  - Sources/AkashicCore/NameIdentity.swift
  - Sources/AkashicCore/Models.swift
  - Tests/AkashicKitTests/VenueNameInvariantTests.swift
  - docs/store-format.md
-->