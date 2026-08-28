## MODIFIED Requirements

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
