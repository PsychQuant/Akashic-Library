## Purpose

Lets a work's whole author list be replaced from the work's own full text, through one CLI and MCP write surface, while keeping every prior identity judgement and recording which source and page the new list rests on. It also stores, on the work, the member list of a group author as printed in the work.

## ADDED Requirements

### Requirement: The update-entry command SHALL offer a whole author-list replacement leg on both faces

The CLI `akashic update-entry <citekey> --replace-authors <file>` and the MCP tool `akashic_update_entry` with the `replace_authors` object SHALL perform the same replacement through one service path and one JSON decoder. The leg SHALL default to a dry run: the CLI writes only with `--apply`, and MCP writes only with `dry_run: false`. The leg SHALL run alone; a call combining it with `remove_fields`, `add_sources`, `remove_zotero_sources` or `remove_sources` SHALL be refused. The JSON SHALL carry `source`, `page`, `reason` and `authors`, and its only optional keys SHALL be `release` and `groupMembers`; any other key at any level SHALL be refused.

Each item of `authors` SHALL be exactly one of `{"literal": <name>}`, `{"group": <name>}` or `{"from": <index>}`. A `group` item SHALL be written to the store as a literal carrying the corporate-name mark; a `group` name that does not yield a corporate-marked name once marked (for example because its braces do not balance) SHALL be refused. A `from` item SHALL carry over the value at that zero-based position of the current author list unchanged, in whichever of the three author states it is. Every integer in the JSON SHALL be decoded exactly; an integer outside the platform's integer range SHALL be refused rather than truncated.

#### Scenario: A dry run writes nothing

- **WHEN** the leg runs without `--apply` (CLI) or with `dry_run` omitted (MCP)
- **THEN** no file under the store SHALL change
- **AND** the response SHALL show the author list before and after

#### Scenario: Both faces return the same payload

- **WHEN** the same JSON is given to the CLI as a file and to MCP as `replace_authors` on the same store
- **THEN** both responses SHALL carry the same keys and values, except that the MCP face caps `verdictsOnRetiredLiterals` and adds its total and truncation flag as the response requirement below states

#### Scenario: An unknown key is refused

- **WHEN** the JSON carries a key outside `source`, `page`, `reason`, `authors`, `release`, `groupMembers`, or an author item carries a key other than `literal`, `group`, `from`
- **THEN** the call SHALL be refused with zero writes and the error SHALL name the key

#### Scenario: A group item is written with the corporate mark

- **WHEN** `authors` contains `{"group": "Summer internship for INdigenous peoples in Genomics (SING) Consortium"}`
- **THEN** that position SHALL be stored as the literal `{Summer internship for INdigenous peoples in Genomics (SING) Consortium}`

#### Scenario: Combining with another leg is refused

- **WHEN** one call carries `replace_authors` and `remove_fields`
- **THEN** the call SHALL be refused with zero writes

---

### Requirement: Every resolved author position SHALL be carried over or explicitly released

Each position of the current author list that holds a person key or an organization key SHALL either be the target of exactly one `from` item, or be listed in `release` as `{"index": i, "reason": <non-blank>}`. A resolved position that is neither SHALL cause the whole call to be refused with zero writes, and the error SHALL list each such position with its value. A `release` entry naming a literal position, naming a position also taken by `from`, or repeating an index SHALL be refused. No `from` index SHALL be out of range or used twice. Releasing a position SHALL NOT delete any verdict.

#### Scenario: A silently dropped key is refused

- **GIVEN** the current author list `[literal("A"), key("garrison-nanibaa"), literal("B")]`
- **WHEN** `authors` is `[{"literal": "A"}, {"literal": "Nanibaa' A. Garrison"}]` with no `release`
- **THEN** the call SHALL be refused and the error SHALL name position 1 and `garrison-nanibaa`

#### Scenario: A key is carried over by position

- **GIVEN** the same current list
- **WHEN** `authors` is `[{"literal": "A"}, {"from": 1}]`
- **THEN** the new list SHALL be `[literal("A"), key("garrison-nanibaa")]`

#### Scenario: A key is released with a reason

- **WHEN** position 1 is listed in `release` with a non-blank reason and is not taken by `from`
- **THEN** the replacement SHALL proceed
- **AND** the response SHALL list the released position, its value and the reason

---

### Requirement: The replacement SHALL record the source it rests on as an author-list replacement record

A replacement written with `--apply` SHALL add exactly one reference to the work's `references` with field `authors`, no value, kind judgement, and a `rests-on` list holding exactly the `source` digest. Its statement SHALL follow the grammar `替換為 ⟦s1⟧ ⟦s2⟧ … ⟦sn⟧；依據第 N 頁：<reason>`, where each segment is the stored value of the corresponding new author position (a carried-over person key written as `key:<key>`, an organization key as `organization:<key>`), n equals the length of the new author list and is at least 1, N is the one-based physical PDF page, and the reason is non-blank. The grammar SHALL have exactly one parser, used by the write surface and by attachment validation. A work SHALL carry at most one replacement record. The `source` digest SHALL be a valid, non-empty-content digest, SHALL be linked in the work's `akashic.sources`, SHALL be present in the local `sources/` store, and SHALL be recorded in the source index with media type `application/pdf`.

#### Scenario: The record parses back to the new list

- **WHEN** a replacement to seven positions is applied with `page: 1`
- **THEN** the work SHALL carry one `field: authors` reference with no value whose statement parses to seven segments and page 1

#### Scenario: A source not linked to the work is refused

- **WHEN** `source` is a digest present in `sources/` but absent from the work's `akashic.sources`
- **THEN** the call SHALL be refused with zero writes

#### Scenario: Segment brackets are refused

- **WHEN** a `literal` or `group` value contains `⟦` or `⟧`
- **THEN** the call SHALL be refused with zero writes

#### Scenario: Input bounds are enforced

- **WHEN** `reason` is blank or longer than 4,096 bytes, `page` is not an integer of at least 1, `authors` is empty, or a `literal` or `group` value is blank, has leading or trailing whitespace, contains a scalar of the repository's unsafe-to-emit set (default-ignorable, Cc, Cf, Zl, Zp, a space separator other than U+0020, or a code point that renders blank; private-use code points and a ZWJ or ZWNJ in a script that uses it are allowed), contains a segment bracket scalar (U+27E6 or U+27E7, checked per scalar), a `literal` or `group` value would not stay a character of its own next to the segment brackets (it begins with a combining or spacing mark, or ends with a prepended character), or a value exceeds 65,536 bytes; or `reason` begins with a character that would join the separator before it
- **THEN** the call SHALL be refused with zero writes

#### Scenario: A source that is not a PDF is refused

- **WHEN** `source` is linked to the work and stored locally but its source-index media type is not `application/pdf`
- **THEN** the call SHALL be refused with zero writes

#### Scenario: A literal that already carries the corporate mark is refused

- **WHEN** a `literal` value is already wrapped in the corporate-name braces
- **THEN** the call SHALL be refused and the error SHALL direct the caller to `group`

---

### Requirement: Records about the previous author list SHALL be removed and listed

When a replacement is applied and the new author list differs from the current one, the work's split records, removal records and any earlier replacement record (all `field: authors` references), and its `akashic.author-list-completeness` witness, SHALL be removed. When the new author list is byte-identical to the current one, an earlier replacement record SHALL be replaced at its own position among the work's references, and split records, removal records and the witness SHALL be kept; when nothing changes at all — the authors, the member lists and every reference byte-identical to the stored ones — `unchanged` SHALL be true and `recordsRemoved` SHALL be empty; a replacement whose reason differs from the stored record only in Unicode normalization SHALL be written. The response SHALL list each removed record in `recordsRemoved` with its value, statement and rests-on, display-sanitised and length-bounded as every response value is, and SHALL state in `witnessRemoved` whether a witness was removed; when one was, `witnessRemovedDetail` SHALL give its fingerprint, its attested author list and the number of its references. Before writing, the work's file SHALL be committed and clean in git; otherwise the call SHALL be refused with zero writes. The response SHALL list in `verdictsOnRetiredLiterals` every confirmed verdict on a person or organization record whose value is `work:<this citekey> :: <literal>` for a literal that is not byte-equal to any literal position of the new list; such verdicts SHALL NOT be changed, and the list SHALL be computed before anything is written.

#### Scenario: A split record and a witness are removed

- **GIVEN** a work carrying one split record and a completeness witness
- **WHEN** a replacement is applied
- **THEN** neither SHALL remain on the work
- **AND** `recordsRemoved` SHALL hold the split record, `witnessRemoved` SHALL be true and `witnessRemovedDetail` SHALL give the witness's fingerprint

#### Scenario: A member-list-only replacement keeps the records about the list

- **GIVEN** a work carrying one split record, a completeness witness and an earlier replacement record
- **WHEN** a replacement whose new author list is byte-identical to the current one is applied with a new `groupMembers`
- **THEN** the split record and the witness SHALL remain
- **AND** `recordsRemoved` SHALL hold only the earlier replacement record and `witnessRemoved` SHALL be false

#### Scenario: An uncommitted work file is refused

- **WHEN** the work's file has uncommitted changes
- **THEN** the call with `--apply` SHALL be refused with zero writes

---

### Requirement: A work SHALL be able to carry the member lists of its group authors

A work SHALL accept a top-level `group-members` sequence. Each entry SHALL carry `group` (byte-equal to the stored value of a group author position at the time of writing, corporate mark included), `rests-on` (one valid digest), `page` (a one-based physical PDF page) and `members` (at least one string, in the order printed, with no byte-equal duplicates and no scalar of the unsafe-to-emit set). Members SHALL be stored as strings, not as person references. Only the replacement leg SHALL write `group-members`. A group position of the new list is any position holding a corporate-marked literal, whether it came from a `group` item or was carried over by `from`, and any position holding an organization key whose organization carries a confirmed verdict pairing this work with a literal that names a group (`resolve-people --attribute-org` records the marked literal, `resolve-organizations` records it with the mark removed; both count); such a position counts as that literal with the corporate mark. When the key of an organization position of the new list is held by more than one organization record, the replacement SHALL be refused with zero writes rather than reading one of them; when the key is held by no loadable organization record (missing, or its file quarantined) and the work has member lists or the leg's JSON gives `groupMembers`, the replacement SHALL likewise be refused, because whether that position is a promoted group cannot be decided. When `groupMembers` is present in the leg's JSON, including as an empty list, it SHALL replace the work's member lists wholesale and each entry SHALL name a group position of the new list; when it is absent, entries whose `group` is still byte-equal to a group position of the new list SHALL be kept and the rest SHALL be removed and listed in `groupMembersRemoved`. Every comparison of names in this requirement, including the loss check of a work merge, SHALL be by bytes, not by Unicode canonical equivalence.

#### Scenario: Members are stored on the work

- **WHEN** a replacement carries `groupMembers` with thirteen members for the SING Consortium group item, page 7
- **THEN** the work SHALL carry one `group-members` entry with those thirteen strings in the given order
- **AND** the `authors` list SHALL NOT contain any of them

#### Scenario: A member list for an unknown group is refused

- **WHEN** a `groupMembers` entry names a group that is byte-equal to no group position of the new list
- **THEN** the call SHALL be refused with zero writes

#### Scenario: A carried-over group position can hold a member list

- **GIVEN** a current author list whose position 5 is the literal `{SING Consortium}`
- **WHEN** `authors` carries that position with `{"from": 5}` and `groupMembers` names `SING Consortium`
- **THEN** the replacement SHALL proceed and the member list SHALL be stored for that group

#### Scenario: A promoted group position keeps its member list

- **GIVEN** a work whose group position `{SING Consortium}` was promoted to the organization key `sing-consortium`, whose organization carries the confirmed verdict `work:<citekey> :: {SING Consortium}`, and whose member list names that group
- **WHEN** a replacement carries that position with `from` and omits `groupMembers`
- **THEN** the member list SHALL be kept
- **AND** a replacement that names `SING Consortium` in `groupMembers` SHALL be accepted

#### Scenario: A group promoted by resolve-organizations keeps its member list

- **GIVEN** the same work, but promoted by `resolve-organizations --apply`, so the verdict reads `work:<citekey> :: SING Consortium`
- **WHEN** a replacement carries that position with `from` and omits `groupMembers`
- **THEN** the member list SHALL be kept

#### Scenario: A duplicate organization key is refused

- **GIVEN** two organization records that share the key `sing-consortium`
- **WHEN** a replacement carries the position `organization:sing-consortium`
- **THEN** the call SHALL be refused with zero writes, naming the key

#### Scenario: An organization position with no loadable record is refused when member lists are involved

- **GIVEN** a work with a member list whose author list holds `organization:sing-consortium`, and no organization record with that key can be loaded
- **WHEN** a replacement carries that position with `from`
- **THEN** the call SHALL be refused with zero writes, naming the key

#### Scenario: Names are compared by bytes

- **WHEN** `members` holds `José` written once in NFC and once in NFD
- **THEN** both SHALL be accepted as distinct members
- **AND** a `groupMembers` entry whose group is the NFD form of an NFC group position SHALL be refused

#### Scenario: Omitting groupMembers drops lists whose group is gone

- **GIVEN** a work whose member list names a group absent from the new author list
- **WHEN** a replacement without `groupMembers` is applied
- **THEN** that entry SHALL be removed and listed in `groupMembersRemoved`

---

### Requirement: The new shapes SHALL be governed by store format 23

A work carrying an author-list replacement record or a `group-members` entry SHALL only be written to a store whose format marker is 23 or later; the write gate SHALL refuse it on an older store with a message naming format 23. The supported format SHALL become 23 for the CLI, the MCP server and the App together.

#### Scenario: Applying to a format-22 store is refused

- **WHEN** the leg runs with `--apply` against a store whose marker is 22
- **THEN** no file SHALL change and the error SHALL name format 23

#### Scenario: A dry run on a format-22 store still reports the plan

- **WHEN** the leg runs without `--apply` against a store whose marker is 22
- **THEN** the plan SHALL be reported without writing

---

### Requirement: A stale replacement record SHALL be reported as a warning

Store health SHALL report a warning, in its own family with a count shown by doctor and the App, for each work whose replacement record no longer matches its author list: the segment count differs from the list length, or a position holds a literal that is not byte-equal to its segment. A position holding a person key or an organization key SHALL count as matching. The warning SHALL NOT block any write, and `akashic validate` SHALL exit 0 for it.

#### Scenario: A split after replacement makes the record stale

- **WHEN** one position of a replaced author list is later split into two
- **THEN** `akashic validate` SHALL print the warning for that work and exit 0

#### Scenario: A promotion does not make the record stale

- **WHEN** a literal position of a replaced list is later promoted to a person key
- **THEN** no warning SHALL be reported for that work

##### Example: Matching a record against the current list

| Record segments | Current author list | Warning |
| --------------- | ------------------- | ------- |
| `⟦A⟧ ⟦B⟧` | `[literal("A"), literal("B")]` | no |
| `⟦A⟧ ⟦B⟧` | `[literal("A"), key("b-person")]` | no |
| `⟦A⟧ ⟦B⟧` | `[literal("A"), literal("B2")]` | yes |
| `⟦A⟧ ⟦B⟧` | `[literal("A"), literal("B1"), literal("B2")]` | yes |

---

### Requirement: A Zotero pull SHALL keep an author list that carries a replacement record

When importing from Zotero updates an existing work, the importer SHALL keep the work's author list if the list holds any resolved position or the work carries an author-list replacement record, and SHALL list the work in `authorsPreserved`. Other fields SHALL follow the existing pull behaviour.

#### Scenario: A replaced list survives a pull

- **GIVEN** a work whose primary source is Zotero and which carries a replacement record over an all-literal author list
- **WHEN** an import from Zotero updates that work
- **THEN** the author list SHALL be unchanged
- **AND** the work SHALL be listed in `authorsPreserved`

---

### Requirement: The replacement response SHALL be bounded on the MCP face

The response SHALL carry `citekey`, `dryRun`, `unchanged`, `authorsBefore`, `authorsAfter`, `released`, `recordsRemoved`, `witnessRemoved`, `groupMembersAfter`, `groupMembersRemoved` and `verdictsOnRetiredLiterals`, and `witnessRemovedDetail` when a witness is removed. Each member list in `groupMembersAfter` and `groupMembersRemoved` SHALL carry its `restsOn` digest. On the MCP face `verdictsOnRetiredLiterals` SHALL hold at most 20 entries and SHALL be accompanied by `verdictsOnRetiredLiteralsTotal` and `truncated`; the CLI SHALL print every entry.

#### Scenario: Many retired-literal verdicts are truncated on MCP only

- **GIVEN** a replacement that leaves 25 confirmed verdicts on retired literals
- **WHEN** it runs through MCP
- **THEN** `verdictsOnRetiredLiterals` SHALL hold 20 entries, `verdictsOnRetiredLiteralsTotal` SHALL be 25 and `truncated` SHALL be true
- **AND** the CLI SHALL print all 25
