# person-resolution Specification

## Purpose

TBD - created by archiving change 'add-loose-nomination-campaign'. Update Purpose after archive.

## Requirements

### Requirement: Nomination SHALL never merge — apply is a separate, explicit act

The resolver SHALL only nominate pairings between a literal author reference and a person record. Promotion of a literal to a key SHALL occur only through an explicit apply step confirmed by the user. No tier of matching, however confident, SHALL cause an automatic rewrite of an entry.

#### Scenario: High-confidence match still requires apply

- **GIVEN** a literal that exactly matches an alias of exactly one person
- **WHEN** resolution runs
- **THEN** the pairing appears as a candidate and the entry remains unchanged until an explicit apply names that candidate


<!-- @trace
source: add-loose-nomination-campaign
updated: 2026-08-17
code:
  - .vscode/launch.json
-->

---
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


<!-- @trace
source: add-loose-nomination-campaign
updated: 2026-08-17
code:
  - .vscode/launch.json
-->

---
### Requirement: A literal occurrence SHALL nominate only at its highest matching tier

For each literal occurrence, the resolver SHALL evaluate tiers in descending confidence order and nominate only at the first tier with at least one hit. Lower tiers SHALL be suppressed for that occurrence, so the same pairing never appears twice in one report.

#### Scenario: Exact hit suppresses looser tiers

- **GIVEN** a literal that matches one person exactly and would also match the same person by token reorder
- **WHEN** resolution runs
- **THEN** exactly one candidate is nominated, with tier `exact`


<!-- @trace
source: add-loose-nomination-campaign
updated: 2026-08-17
code:
  - .vscode/launch.json
-->

---
### Requirement: Two or more hits within the nominating tier SHALL be reported as ambiguity

When the nominating tier yields two or more distinct person keys, the resolver SHALL report an ambiguity carrying that tier instead of any candidate. Ambiguities SHALL NOT be applicable.

The sanctioned exit for an ambiguity is verified alias promotion: after human verification, the literal's correct spelling is recorded as a variant alias on the right person **together with a provenance reference documenting the verification**, whereupon the occurrence nominates at the exact tier and is applied explicitly. Guidance surfaces SHALL NOT direct operators to add discriminator fields (ORCID, affiliation) as a way to change nomination — the matching key space is names only, and discriminators inform the human, not the resolver.

#### Scenario: Initials collision becomes ambiguity

- **GIVEN** a literal "C-H Chen" and two persons whose aliases reduce to the same family-plus-initials key
- **WHEN** resolution runs
- **THEN** an ambiguity with tier `initials` listing both person keys is reported and no candidate is produced for that occurrence


<!-- @trace
source: add-loose-nomination-campaign
updated: 2026-08-17
code:
  - .vscode/launch.json
-->

---
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


<!-- @trace
source: add-loose-nomination-campaign
updated: 2026-08-17
code:
  - .vscode/launch.json
-->

---
### Requirement: Confirmed verdicts SHALL be reused as nomination knowledge

The resolver SHALL accept the set of previously confirmed pairings, derived from `resolution-confirmed` verdict references on person records. A literal occurrence whose normalized form equals the normalized literal of a confirmed pairing SHALL be nominated for that person with tier `confirmed-elsewhere`, unless that exact (entry, literal, person) pairing has been rejected. Applying a candidate SHALL NOT write the literal into the person's name set.

#### Scenario: Confirmation in one entry nominates the same literal elsewhere

- **GIVEN** the literal "Yung-Fong Hsu" confirmed to person `hsu-yung-fong` in entry X
- **AND** entry Y carries the same literal with no exact alias match
- **WHEN** resolution runs
- **THEN** entry Y's occurrence is nominated for `hsu-yung-fong` with tier `confirmed-elsewhere` and applying it does not modify the person's names


<!-- @trace
source: add-loose-nomination-campaign
updated: 2026-08-17
code:
  - .vscode/launch.json
-->

---
### Requirement: Rejected pairings SHALL be suppressed across all tiers

A pairing rejected by verdict SHALL NOT be re-nominated at any tier. Suppression matching SHALL use the same normalization as nomination — a rejection recorded with a normalization-equivalent variant of the literal suppresses the pairing. The same literal in a different entry is a distinct observation and SHALL be nominated normally.

Hits within a tier are counted after rejected pairings are removed. Two consequences are normative, not incidental: (a) when removal leaves exactly one hit, that survivor is nominated as a candidate, and its reason SHALL disclose that same-key candidates were eliminated by rejection; (b) when removal empties a tier, evaluation falls through to lower tiers, and a nomination produced this way carries the same disclosure.

#### Scenario: Rejection suppresses loose re-nomination

- **GIVEN** a pairing (entry X, literal L, person P) rejected by verdict
- **AND** literal L would match person P at reorder tier
- **WHEN** resolution runs
- **THEN** no candidate for (X, L, P) appears, while the same literal in entry Y still nominates P

#### Scenario: Rejection recorded with a punctuation variant still suppresses

- **GIVEN** a rejection recorded with literal "Cheng–Der Fuh" (EN DASH)
- **AND** the entry carries literal "Cheng-Der Fuh" (ASCII hyphen)
- **WHEN** resolution runs
- **THEN** the pairing is suppressed — normalization applies to suppression exactly as it applies to nomination

#### Scenario: Elimination survivor is disclosed

- **GIVEN** two persons both matching a literal at the exact tier, one of whose pairings is rejected
- **WHEN** resolution runs
- **THEN** the other person is nominated as a candidate and the reason discloses the eliminated same-key candidate


<!-- @trace
source: add-loose-nomination-campaign
updated: 2026-08-17
code:
  - .vscode/launch.json
-->

---
### Requirement: Confirmed-pairing nomination SHALL consume only work-holder verdicts

The confirmed-elsewhere tier SHALL derive its knowledge exclusively from `resolution-confirmed` verdicts whose pairing holder kind is a work. Verdicts held for other pairing families SHALL NOT feed person nomination.

#### Scenario: Organization-family verdict does not nominate a person

- **GIVEN** a confirmed pairing whose holder kind is a person (an organization-family verdict)
- **WHEN** resolution runs against an entry carrying the same literal
- **THEN** no confirmed-elsewhere candidate is produced


<!-- @trace
source: add-loose-nomination-campaign
updated: 2026-08-17
code:
  - .vscode/launch.json
-->

---
### Requirement: Verdicts SHALL record the nominating tier's calibration class

Applying or rejecting a candidate SHALL write a verdict whose rule name is derived from the candidate's tier, drawn from a closed mapping (exact → `author-name-exact`; confirmed-elsewhere → `author-name-confirmed-elsewhere`; reorder → `author-name-reorder`; initials → `author-name-initials`). Calibration counts SHALL bucket pending candidates by each candidate's own tier-derived rule. Legacy verdicts without a rule tail default to the exact rule — they predate loose tiers and the default is semantically correct.

#### Scenario: Loose-tier apply is traceable afterwards

- **GIVEN** a reorder-tier candidate
- **WHEN** it is applied
- **THEN** the stored verdict's rule reads `author-name-reorder`, and the exact tier's calibration history is unchanged


<!-- @trace
source: add-loose-nomination-campaign
updated: 2026-08-17
code:
  - .vscode/launch.json
-->

---
### Requirement: Apply SHALL address a nominated pairing, not a position

Candidate identifiers listed for apply — and the identifiers every shipped face sends — SHALL pin the nominated person (`citekey:authorIndex:personKey`). When an identifier's pinned person no longer matches the current nomination at that position, apply SHALL fail explicitly, naming both persons, and SHALL NOT write anything. A two-segment legacy identifier is accepted and resolves to the position's current unique nomination — it carries no pin, so hand-typed legacy ids trade retarget protection for brevity; faces SHALL NOT emit the legacy form. In a combined apply+reject call, cross-leg coordination SHALL match at the pairing level (`citekey:authorIndex` plus the pinned person when the apply identifier carries one): a pinned apply id whose person differs from the rejected pairing at the same position is a distinct pairing and proceeds to the apply leg, while a legacy (unpinned) apply id at a rejected position is treated as the rejected pairing and skipped. Coordination SHALL use the service's internal untruncated pairings, never sanitised response echoes. Single-leg response shapes remain unchanged.

#### Scenario: Retargeted nomination refuses a stale pinned id

- **GIVEN** a listed identifier pinned to person A at some position
- **AND** the nomination at that position now targets person B
- **WHEN** apply is invoked with the stale identifier
- **THEN** the call fails naming A and B, and no entry or verdict is written


<!-- @trace
source: add-loose-nomination-campaign
updated: 2026-08-17
code:
  - .vscode/launch.json
-->

---
### Requirement: Bulk apply SHALL NOT cross tiers implicitly

The gated surface is a **closed enumeration of one**: the CLI's filter-driven bulk apply (`resolve-people --apply`, whose apply set is produced by filters rather than by naming identifiers). On that surface, applying any looser-than-exact candidate SHALL require naming the tier explicitly, and scoping by entry or person SHALL NOT exempt the requirement — narrowing does not attest tier awareness, and person scoping in particular selects exactly the co-keyed rows a name-collision defect produces.

The MCP apply is **deliberately outside this gate**: its apply set is a list of explicit per-row identifiers, each row's tier is disclosed in the listing, and the campaign skill binds its operators to per-tier batching discipline. This asymmetry is recorded in `mcp-cli-parity.md`; a tier-acknowledgment parameter for the MCP face is tracked as a follow-up, not silently absent. Do not generalize this requirement to "every face" — that unqualified form was the R2→R3 defect (an undefined blanket term whose reach exceeded the enumerated surfaces).

#### Scenario: Bare bulk apply refuses on mixed tiers

- **GIVEN** an apply set (the filtered candidates after eliminated survivors are excluded) containing reorder- and initials-tier rows
- **WHEN** an unscoped bulk apply is invoked
- **THEN** the face refuses with the tier breakdown and no write occurs

#### Scenario: Person-scoped bulk apply still requires the tier

- **GIVEN** a bulk apply scoped to one person whose selected rows include an initials-tier candidate
- **WHEN** it is invoked without a tier filter
- **THEN** the face refuses and no write occurs

#### Scenario: Bulk apply excludes an eliminated survivor (#624)

- **GIVEN** a candidate that is the sole survivor after other same-position candidates were rejected (its `eliminatedPairings` is greater than zero)
- **WHEN** a filter-driven bulk apply is invoked, with or without a tier filter
- **THEN** that candidate is not applied and is listed as excluded with a pointer to per-row judgement; the tier gate is evaluated on the apply set after this exclusion; if nothing remains, no write occurs and the face exits non-zero
- **AND** a two-segment identifier resolving to such a candidate is refused for MCP apply, MCP reject and CLI `--reject` (it names a position, not a person; the CLI bulk apply only ever sends three-segment identifiers), while a three-segment identifier naming its person proceeds as usual
- **AND** a three-segment identifier shared by two positions (duplicate citekey) is refused rather than resolved to either one

#### Scenario: A duplicated citekey is never resolved by guessing (#627)

- **GIVEN** a citekey that does not locate exactly one work (a supported corrupt state): two works share the citekey — including two copies of one work that also share its identifier — or the work shares its identifier with another work under a different citekey
- **WHEN** any resolve-people write targets that citekey — explicit apply or reject identifiers (two- or three-segment), judge or refute, author split, un-split, removal, organization attribution, or an adjudication accept — or a filter-driven bulk apply includes a candidate on it, or an unrelated apply runs in the same store
- **THEN** neither work is rewritten and no verdict is written for it: explicit identifiers, the author-slot operations and the adjudication accept are refused by name, judge and refute skip that pairing by name while the rest proceed (if the index then cannot be rebuilt, the call reports that failure naming the judged and skipped pairings), and the bulk apply excludes and lists such candidates while applying the rest

#### Scenario: A confirmed verdict is written only where the author slot changed (#627)

- **GIVEN** an apply or judge call
- **WHEN** a pairing in it does not end up rewriting its author slot
- **THEN** no confirmed verdict is written for that pairing, it is not reported as applied or judged, and the response names it

#### Scenario: One author slot cannot be judged for two people in one call (#627)

- **GIVEN** a judge call that assigns the same author slot to two different people
- **WHEN** it is submitted
- **THEN** the whole call is refused and nothing is written; refuting several people for one slot remains allowed


<!-- @trace
source: add-loose-nomination-campaign
updated: 2026-08-17
code:
  - .vscode/launch.json
-->

---
### Requirement: Every reported row SHALL disclose its tier on all faces

Candidates and ambiguities SHALL carry their tier in the resolver report, and every consuming face (CLI, MCP, App) SHALL surface it. Existing fields remain; the recorded contract changes accompanying the tier work (three-segment pinned identifiers, tier-derived verdict rules, normalized rejection suppression, elimination disclosure, and the bulk-apply tier gate) are deliberate and documented — the report shape is additive, the apply contract is not.

#### Scenario: MCP report carries tier

- **GIVEN** a resolution report containing a reorder-tier candidate
- **WHEN** the MCP face serializes it
- **THEN** the candidate row includes a `tier` field with value `reorder` alongside the existing fields

<!-- @trace
source: add-loose-nomination-campaign
updated: 2026-08-17
code:
  - .vscode/launch.json
-->