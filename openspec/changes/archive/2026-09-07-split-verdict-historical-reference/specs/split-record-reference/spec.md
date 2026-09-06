## ADDED Requirements

### Requirement: A work record SHALL be able to carry a split record for a retired author literal

The set of fields a work-level provenance reference can attach to SHALL be exactly `doi`, `pmid`, `isbn`, and `authors`. A reference with `field: authors` SHALL carry the retired literal as its `value`, verbatim, and SHALL be a judgement whose statement follows the split grammar. The split command SHALL append this reference in the same write that rewrites the author positions, so that a split is never recorded without its record and never recorded twice.

#### Scenario: Splitting a glued literal writes the record alongside the new positions

- **WHEN** the split command is applied to a work whose author position holds one glued literal
- **THEN** the work's author positions hold the parts in order and the work's references gain exactly one `authors` reference whose value is the original literal verbatim

##### Example: Two authors glued by 與

- **GIVEN** work `chen2020a` with `authors[2] = .literal("某人與雷庚玲")`
- **WHEN** `split-author chen2020a:2:與=兩位作者被匯出黏成一格` is applied
- **THEN** `authors[2] = .literal("某人")`, `authors[3] = .literal("雷庚玲")`, and `references` contains `{field: authors, value: "某人與雷庚玲", judgement: "拆為 ⟦某人⟧ ⟦雷庚玲⟧：兩位作者被匯出黏成一格"}`

#### Scenario: Any other field on a work reference is still rejected

- **WHEN** a work record carries a reference whose field is neither `doi`, `pmid`, `isbn`, nor `authors`
- **THEN** the store SHALL reject the record and the error message SHALL list the four accepted fields

### Requirement: The split record refers to a retired value and SHALL be validated by presence of its parts, not of its value

For a reference with `field: authors`, the store SHALL NOT require the `value` to be present among the work's current author positions, because the value is the literal that the split retired. Instead, consistency SHALL be defined as: at least one part named in the statement is still an author position of that work. A record whose parts are all absent SHALL still load and SHALL be reported as a warning by the health scan.

#### Scenario: Retired value is accepted on load

- **WHEN** a work carries an `authors` reference whose value is not among its author positions but whose statement names a part that is
- **THEN** the record loads without a quarantine

#### Scenario: All parts gone is a warning, not a rejection

- **WHEN** every part named in a split record's statement is absent from the work's author positions
- **THEN** the record still loads and the health scan reports one warning naming the work and the retired literal

### Requirement: An empty rests-on SHALL be admissible for first-order rulings through a second named set

The set of fields whose judgement references are allowed an empty `restsOn` SHALL be `firstOrderRulingFields`, defined as the resolution verdict fields plus `authors`. The resolution verdict field set itself SHALL NOT change, and code that parses resolution verdict grammar SHALL NOT be applied to `authors` references.

#### Scenario: Split record with empty rests-on is accepted

- **WHEN** an `authors` reference carries a judgement with an empty `restsOn`
- **THEN** the reference is accepted because `authors` is in `firstOrderRulingFields`

#### Scenario: Resolution verdict parsing ignores split records

- **WHEN** the resolution ledger, the dead-verdict scan, or the demote path reads a work's references
- **THEN** `authors` references are not parsed as resolution verdicts and produce no verdict entries

### Requirement: The split statement grammar SHALL have exactly one parser

The statement of a split record SHALL take the form `拆為 ⟦part⟧ ⟦part⟧…：reason`, with two or more parts and a non-empty reason, and SHALL be produced and consumed only through `SplitRecordValue` (`parse` and `encoded`). A part SHALL NOT contain the reserved characters `⟦` or `⟧`; the split command SHALL refuse a literal whose parts would contain them.

#### Scenario: Round trip is verbatim

- **WHEN** a `SplitRecordValue` with parts `["某人", "雷庚玲"]` and reason `兩位作者被匯出黏成一格` is encoded and parsed back
- **THEN** the parts and reason are byte-identical to the input

#### Scenario: Malformed statements are rejected at decode

- **WHEN** a work carries an `authors` reference whose statement has fewer than two parts, an empty reason, or unbalanced brackets
- **THEN** the store SHALL reject the record on load

##### Example: Statements and verdicts

| Statement | Result |
| --------- | ------ |
| `拆為 ⟦某人⟧ ⟦雷庚玲⟧：兩位作者被匯出黏成一格` | parts `["某人","雷庚玲"]`, reason `兩位作者被匯出黏成一格` |
| `拆為 ⟦某人⟧：理由` | rejected (one part) |
| `拆為 ⟦某人⟧ ⟦雷庚玲⟧：` | rejected (empty reason) |
| `拆為 ⟦某人 ⟦雷庚玲⟧：理由` | rejected (unbalanced) |

### Requirement: The split record SHALL be governed by store format 16

A work carrying an `authors` reference SHALL only be written to a store whose format is 16 or later; the write gate SHALL refuse it on an older store with a message that names the required format. The supported format SHALL become 16 for the CLI, the MCP server, and the App together.

#### Scenario: Writing a split record to a format-15 store is refused

- **WHEN** the split command runs against a store whose format marker is 15
- **THEN** no file changes and the error names format 16 as required

#### Scenario: Format-16 store accepts the record

- **WHEN** the store marker is 16
- **THEN** the same command writes the positions and the record

### Requirement: A verdict whose literal has been retired by a split SHALL be reported as an orphan

The health scan SHALL report, as a warning owned by the holder, every resolution verdict held by a person or organization whose value names a work and a literal such that the work carries a split record with that literal as its value. The warning SHALL name the work and state that the literal was split. The scan SHALL match on the pair (work citekey, literal), never on the literal alone.

#### Scenario: Rejected literal later split

- **WHEN** person `p-one` holds `resolution-rejected` with value `work:chen2020a :: 某人與雷庚玲` and `chen2020a` is then split with that literal
- **THEN** the health scan reports one warning owned by `p-one` naming `chen2020a` and the split

#### Scenario: Same literal on a different work is not an orphan

- **WHEN** person `p-one` holds a verdict on `work:other2021 :: 某人與雷庚玲` and only `chen2020a` was split
- **THEN** no warning is reported for that verdict

#### Scenario: Clean store reports nothing

- **WHEN** no work carries a split record
- **THEN** the health scan reports zero orphan warnings
