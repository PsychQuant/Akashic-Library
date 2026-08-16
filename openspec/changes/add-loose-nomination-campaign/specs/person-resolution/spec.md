## ADDED Requirements

### Requirement: Nomination SHALL never merge — apply is a separate, explicit act

The resolver SHALL only nominate pairings between a literal author reference and a person record. Promotion of a literal to a key SHALL occur only through an explicit apply step confirmed by the user. No tier of matching, however confident, SHALL cause an automatic rewrite of an entry.

#### Scenario: High-confidence match still requires apply

- **GIVEN** a literal that exactly matches an alias of exactly one person
- **WHEN** resolution runs
- **THEN** the pairing appears as a candidate and the entry remains unchanged until an explicit apply names that candidate

### Requirement: Matching tiers SHALL be a closed enumeration of four

Candidate nomination SHALL classify each pairing into exactly one of four tiers, in descending confidence order: `exact` (normalized alias equality), `confirmed-elsewhere` (same literal previously confirmed to the same person in another entry), `reorder` (token-reorder equality), `initials` (family-plus-initials equality). No other matching form SHALL nominate. Romanization variants (e.g. Wade-Giles vs pinyin) SHALL NOT match under any tier; adding such a form requires a new decision recorded in this spec.

#### Scenario: Token reorder nominates at reorder tier

- **GIVEN** an entry with literal author "Yung-Fong Hsu" and a person whose alias set includes "Hsu, Yung-Fong"
- **WHEN** resolution runs
- **THEN** a candidate for that person is nominated with tier `reorder`

#### Scenario: Initials form nominates at initials tier

- **GIVEN** an entry with literal author "Chen, Y.-H." and exactly one person whose alias set includes "Chen, Yi-Hau"
- **WHEN** resolution runs
- **THEN** a candidate for that person is nominated with tier `initials`

#### Scenario: Romanization variant does not nominate

- **GIVEN** an entry with literal author "Xu, Yung-Fong" and a person whose aliases contain only "Hsu, Yung-Fong"
- **WHEN** resolution runs
- **THEN** no candidate is nominated for that person under any tier

### Requirement: A literal occurrence SHALL nominate only at its highest matching tier

For each literal occurrence, the resolver SHALL evaluate tiers in descending confidence order and nominate only at the first tier with at least one hit. Lower tiers SHALL be suppressed for that occurrence, so the same pairing never appears twice in one report.

#### Scenario: Exact hit suppresses looser tiers

- **GIVEN** a literal that matches one person exactly and would also match the same person by token reorder
- **WHEN** resolution runs
- **THEN** exactly one candidate is nominated, with tier `exact`

### Requirement: Two or more hits within the nominating tier SHALL be reported as ambiguity

When the nominating tier yields two or more distinct person keys, the resolver SHALL report an ambiguity carrying that tier instead of any candidate. Ambiguities SHALL NOT be applicable.

#### Scenario: Initials collision becomes ambiguity

- **GIVEN** a literal "C-H Chen" and two persons whose aliases reduce to the same family-plus-initials key
- **WHEN** resolution runs
- **THEN** an ambiguity with tier `initials` listing both person keys is reported and no candidate is produced for that occurrence

### Requirement: Initials matching SHALL NOT guess family-name position

When a name carries a comma, the resolver SHALL treat the token(s) before the comma as the family name. When a name carries no comma, the resolver SHALL evaluate both family-first and family-last readings and SHALL NOT prefer either. Initials keys SHALL be generated only for names containing Latin letters.

#### Scenario: Comma fixes the family name

- **GIVEN** the alias "Chen, Chun-Houh"
- **WHEN** initials keys are generated
- **THEN** exactly one key is produced, with family "chen" and initials "ch"

#### Scenario: CJK name skips initials tier

- **GIVEN** the literal "鄭澈"
- **WHEN** initials keys are generated
- **THEN** no initials key is produced and reorder-tier matching remains available

### Requirement: Confirmed verdicts SHALL be reused as nomination knowledge

The resolver SHALL accept the set of previously confirmed pairings, derived from `resolution-confirmed` verdict references on person records. A literal occurrence whose normalized form equals the normalized literal of a confirmed pairing SHALL be nominated for that person with tier `confirmed-elsewhere`, unless that exact (entry, literal, person) pairing has been rejected. Applying a candidate SHALL NOT write the literal into the person's name set.

#### Scenario: Confirmation in one entry nominates the same literal elsewhere

- **GIVEN** the literal "Yung-Fong Hsu" confirmed to person `hsu-yung-fong` in entry X
- **AND** entry Y carries the same literal with no exact alias match
- **WHEN** resolution runs
- **THEN** entry Y's occurrence is nominated for `hsu-yung-fong` with tier `confirmed-elsewhere` and applying it does not modify the person's names

### Requirement: Rejected pairings SHALL be suppressed across all tiers

A pairing rejected by verdict SHALL NOT be re-nominated at any tier. The same literal in a different entry is a distinct observation and SHALL be nominated normally.

#### Scenario: Rejection suppresses loose re-nomination

- **GIVEN** a pairing (entry X, literal L, person P) rejected by verdict
- **AND** literal L would match person P at reorder tier
- **WHEN** resolution runs
- **THEN** no candidate for (X, L, P) appears, while the same literal in entry Y still nominates P

### Requirement: Every reported row SHALL disclose its tier on all faces

Candidates and ambiguities SHALL carry their tier in the resolver report, and every consuming face (CLI, MCP, App) SHALL surface it. The addition SHALL be additive: existing fields, row identity, and apply semantics remain unchanged.

#### Scenario: MCP report carries tier

- **GIVEN** a resolution report containing a reorder-tier candidate
- **WHEN** the MCP face serializes it
- **THEN** the candidate row includes a `tier` field with value `reorder` alongside the existing fields
