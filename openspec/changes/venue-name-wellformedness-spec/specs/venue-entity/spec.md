## ADDED Requirements

### Requirement: Venue name well-formedness

Every string in a venue's `names[].value`, `authorized`, and `variant` SHALL satisfy the following invariants at write time. A violation SHALL fail validation at error level, so every write surface refuses to write the record until it is fixed. Decoding SHALL NOT enforce them: a stored record that violates them still loads, and `validate` and `doctor` report it. The fix is a human edit of the YAML; no write surface SHALL silently rewrite a stored name.

1. **Canonical form.** The string SHALL be NFC, with no leading or trailing whitespace, and every run of `White_Space` scalars inside it collapsed to a single U+0020. Canonicalization removes only whitespace; no other scalar is dropped.
2. **No dangerous or invisible scalar.** The string SHALL contain no member of the output gate `UnsafeToEmitScalar`, except private-use (Co) scalars. ZWJ (U+200D) and ZWNJ (U+200C) are accepted only in the two joiner contexts defined in `docs/store-format.md` §5.7, and are rejected anywhere else.
3. **At least one letter or digit.** The string SHALL contain at least one scalar of general category L or N.
4. **No canonically equal pair within one list.** Within `names`, `authorized`, or `variant`, no two entries SHALL be canonically equal. The one exception is two `names` segments with the same name that are disjoint renaming-history segments: both make a temporal claim, one has an `end` and the other a `start`, both endpoints are ISO 8601 prefixes, both segments are valid intervals, and the earlier `end`, truncated to the coarser granularity of the two, is strictly before the later `start`. Equal endpoints after truncation count as overlap, and a segment with only `attested` or `ended-unknown` never qualifies.
5. **Per-group evaluation cap.** A group of canonically equal `names` segments SHALL be compared pairwise for at most 5,000 pairs. A group beyond that SHALL fail validation whether or not its pairs would qualify for the exception.
6. **Per-record evaluation cap.** The pairwise comparisons across all groups of one venue SHALL total at most 100,000 pairs. Groups that do not fit in the remaining budget are not evaluated, and the record SHALL fail validation.

The scalar classes behind invariant 2 (the output gate's property: Default_Ignorable_Code_Point, Cc, Cf, Zl, Zp, non-U+0020 Zs, Co, U+2800), the two joiner contexts, and the wording of each message are specified in `docs/store-format.md` §5.7. That section is the per-character reference for this requirement and SHALL be kept consistent with it.

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
