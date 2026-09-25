## Purpose

Give resolve-organizations the same undecided leg that resolve-people and resolve-venues have, so that a literal→organization pairing that was checked but could not be decided is recorded with what was checked instead of looking identical to a pairing nobody has looked at.

## ADDED Requirements

### Requirement: resolve-organizations SHALL provide an explicit undecided leg on both faces

resolve-organizations SHALL accept undecided ids on the CLI (`--undecided`, with optional `--rests-on`) and on the MCP face (`undecided`, with optional `rests_on`). The leg SHALL be called alone and SHALL NOT be combined with apply or reject. Evidence digests SHALL apply to every id in the call and SHALL be refused when given without any undecided id. The leg SHALL require store format 19 or higher.

The whole batch SHALL be refused with zero writes when any of the following holds:

- an id cannot be parsed into exactly one known row (see the id requirement);
- an id is duplicated;
- a statement is blank;
- the named organization does not exist or does not belong to the named row;
- a digest is malformed;
- the store format is below 19;
- digests are given without any undecided id;
- the call carries more than 200 ids, more than 20 digests, or a statement longer than 4,096 bytes;
- an id is longer than the longest known row id plus the longest nominated organization key plus 2 bytes plus 4,096 bytes;
- the row id names both a person row and an organization row on the listing (the two holders share a key).

A single id SHALL be skipped and named, while the rest of the batch proceeds, when any of the following holds:

- the citekey of a work holder cannot be uniquely located;
- the organization already holds a confirmed or rejected verdict for the normalized pairing.

A row whose work was deleted or whose author slot is no longer a literal is not produced by the resolution run, so its id is refused as an unknown row, not skipped.

When an identical undecided record already exists on the organization, the id SHALL be reported as already recorded and SHALL NOT be written again. When two ids in the same call produce the same record on the same organization, the second SHALL be reported as recorded in this call.

#### Scenario: Recording an undecided affiliation pairing

- **WHEN** person `chen-ch` holds the affiliation literal `ISS Academia Sinica`, the candidate list shows the row `chen-ch::ISS Academia Sinica` nominating organization `iss`, and the undecided leg is called with `chen-ch::ISS Academia Sinica@iss=研究所名稱縮寫與兩個機構都相容`
- **THEN** organization `iss` SHALL hold a `resolution-undecided` record whose value is `person:chen-ch :: ISS Academia Sinica` and whose statement is the given text
- **AND** the affiliation SHALL still be the literal

#### Scenario: Combining the leg with apply

- **WHEN** the MCP face receives both `undecided` and `apply`
- **THEN** the call SHALL be refused with zero writes

#### Scenario: Undecided write on a format-18 store

- **WHEN** the undecided leg is called against a store whose marker is 18
- **THEN** the call SHALL be refused with zero writes and an error naming the required format

### Requirement: An undecided id SHALL be split only where the prefix is a known row id

An undecided id SHALL have the form `<rowID>@<orgKey>=<statement>`, where `rowID` is byte-identical to the id the listing returns for a candidate row or an ambiguity entry, and `orgKey` is a store key. The leg SHALL try every position where `@`, a store key, and `=` appear in sequence, and SHALL accept a split only when the text before `@` is byte-identical to a row id produced by the same load. The known row ids SHALL be every row of the listing's resolution run, which excludes rejected pairings, plus the rows of a run that does not exclude them whose pairing with the named organization is already decided. An id shown in the listing is therefore always known; a decided pairing that is still produced by the unfiltered run reaches the skip; and a row that left the listing without being decided is refused as an unknown row. When a row id names both a person row and an organization row on the listing, the whole batch SHALL be refused; a same-key row that appears only because its pairing is decided SHALL NOT cause that refusal. Exactly one accepted split SHALL be required; zero or more than one SHALL refuse the whole batch.

#### Scenario: A literal that contains `@` and `=`

- **WHEN** the row id is `chen-ch::Lab@Sinica=Dept` and the undecided id is `chen-ch::Lab@Sinica=Dept@iss=查過`
- **THEN** the id SHALL be parsed with row `chen-ch::Lab@Sinica=Dept`, organization `iss`, and statement `查過`

##### Example: split outcomes

| Undecided id | Known row ids | Outcome |
| ------------ | ------------- | ------- |
| `p::A@iss=x` | `p::A` | row `p::A`, org `iss`, statement `x` |
| `p::A@iss=x` | none | refused: no known row |
| `p::A@b=c@iss=x` | `p::A`, `p::A@b=c` | refused: two accepted splits |

A known row whose id is another known row id followed by `@<key>=` can therefore never be recorded; this is accepted as a known limit. When the shorter row leaves the listing, the same input is accepted as a split of the longer row.

### Requirement: The named organization SHALL belong to the named row

For a candidate row, the organization in the id SHALL be the organization the row nominates. For an ambiguity entry, it SHALL be one of the organizations the entry lists. Any other organization SHALL refuse the whole batch.

#### Scenario: Recording against each organization of an ambiguity

- **WHEN** the literal `Sinica` held by person `p` matches organizations `as` and `iss`, and the leg is called with `p::Sinica@as=查過院本部名冊` and `p::Sinica@iss=查過所名冊`
- **THEN** organization `as` and organization `iss` SHALL each hold one undecided record for that pairing

#### Scenario: An organization outside the row

- **WHEN** the row `p::Sinica` nominates only `iss` and the leg is called with `p::Sinica@ntu=x`
- **THEN** the call SHALL be refused with zero writes

### Requirement: The listing SHALL disclose undecided checks and give every row an id

The MCP listing SHALL carry an `id` on candidate rows and on ambiguity entries. A candidate row SHALL carry `undecidedChecks` as the number of undecided records its organization holds for the normalized pairing when the pairing is in the undecided state, and 0 otherwise. An ambiguity entry SHALL carry `undecidedChecks` as a map from organization key to that number, listing only non-zero counts. Both counts SHALL cover only pairings in the undecided state, that is, pairings with at least one undecided record and no confirmed or rejected verdict. The listing SHALL carry `undecidedTotal`, the number of candidate pairings in the undecided state, which SHALL equal the undecided count on the CLI four-state line, and `ambiguityUndecidedTotal`, the number of distinct ambiguity pairings (holder, literal, organization) in the undecided state. The CLI listing SHALL print each row's id and SHALL mark rows with undecided records with the number of checks. When sanitizing or truncating changes the printed id, the CLI SHALL say that the printed id cannot be sent back.

#### Scenario: A checked candidate in the listing

- **WHEN** organization `iss` holds one undecided record for `person:chen-ch :: ISS Academia Sinica` and the listing is requested
- **THEN** the candidate row for that pairing SHALL carry `undecidedChecks` equal to 1

### Requirement: Filtered CLI apply SHALL exclude checked candidates

The CLI `--apply` of resolve-organizations SHALL NOT apply a candidate whose organization holds an undecided record for the pairing. Excluded candidates SHALL be listed with a pointer to applying them by explicit id on the MCP face; the CLI has no per-id apply for organizations. When every in-scope candidate is excluded, the command SHALL write nothing and exit non-zero. `--reject` SHALL NOT exclude checked candidates.

#### Scenario: Filtered apply with one checked candidate

- **WHEN** two candidates are in scope, one of them has an undecided record, and `resolve-organizations --apply` is run
- **THEN** only the other candidate SHALL be applied
- **AND** the output SHALL list the checked candidate as not applied
