## ADDED Requirements

### Requirement: A stored source's provenance note SHALL be correctable by appending a correction row

The provenance note of stored content SHALL be correctable by appending a correction row to `sources/index.jsonl`. No existing row SHALL be rewritten, truncated, or removed by a correction: the row being corrected SHALL keep its bytes, and SHALL be shown as superseded by the correction. A correction of a correction SHALL be another correction row, superseding the row that was current when it was written. The fields that a correction can change SHALL be exactly one: `note`. No other field SHALL be changed by a correction on the grounds that it is similar to the note.

#### Scenario: A wrong half-sentence in a note is corrected

- **GIVEN** stored content whose row records the note `take exit 5; no page range in the record`
- **WHEN** a correction is written with the note `take exit 5 (run without --pages); the record has a page range; re-run with --pages exited 0` and a reason
- **THEN** a new row SHALL be appended, the original row SHALL be byte-identical to before, and the current note SHALL be the corrected one

##### Example: The original row survives the correction

- **GIVEN** `sources/index.jsonl` whose third line is the only row for digest `sha256:ab…`
- **WHEN** that row's note is corrected
- **THEN** the file's first three lines SHALL be byte-identical to before, and the file SHALL have one more line

#### Scenario: A correction is itself corrected

- **WHEN** a second correction is written for the same content
- **THEN** it SHALL supersede the first correction, the first correction and the original row SHALL both remain, and the current note SHALL be the second correction's

##### Example: A chain of two corrections

- **GIVEN** digest `sha256:ab…` with its plain row on line 3 and a correction on line 9 that supersedes line 3
- **WHEN** a second correction is written for `sha256:ab…`
- **THEN** it SHALL be appended with `supersedes` 9, lines 3 and 9 SHALL be unchanged, and readers SHALL show line 3 as superseded by line 9 and line 9 as superseded by the new line

#### Scenario: A correction tries to change another field

- **WHEN** a correction is offered that changes `origin`, `retrieved`, `acquisition`, `media-type`, or `bytes`
- **THEN** it SHALL be refused, naming `note` as the only correctable field, and nothing SHALL be written

#### Scenario: Re-storing the same bytes still does not change the note

- **GIVEN** stored content with a recorded note
- **WHEN** the same bytes are stored again with a different note
- **THEN** no row SHALL be appended, the submitted note SHALL be returned as discarded as before, and the response SHALL name the correction entry point as the way to change the note

### Requirement: A correction row SHALL be parseable under the existing index grammar and distinguishable from a duplicate row

A correction row SHALL carry the same well-formed `content` digest as the row it corrects, so that a reader that does not know corrections reads it as one more row for that digest rather than as an unparseable line. It SHALL carry the key `correction` with the value `note`, which plain rows and the duplicate rows left by concurrent stores do not carry. It SHALL carry `supersedes` (the 1-based line number, counted as the index scan counts lines, of the row it supersedes), `corrected` (ISO 8601 with an explicit UTC offset), `reason` (a non-empty statement of what was wrong), and `note` (the corrected note). A row that carries `correction` but lacks one of these fields, or whose `supersedes` is not a positive integer, SHALL be reported as an unparseable line, with the consequences unparseable lines already have.

#### Scenario: A reader without correction support reads the index

- **WHEN** an index containing a correction row is scanned by the existing grammar
- **THEN** the correction row SHALL count as a row for its digest and SHALL NOT be counted as an unparseable line

#### Scenario: A duplicate row from a concurrent store is not a correction

- **GIVEN** two plain rows for one digest left by concurrent stores
- **WHEN** the index is read
- **THEN** neither SHALL be read as a correction, and the current note SHALL be the first plain row's note

#### Scenario: A correction row is damaged

- **WHEN** a row carries `correction` and no `reason`
- **THEN** it SHALL be reported as an unparseable line, and storing new content SHALL be refused until it is repaired, as for any unparseable line

### Requirement: Readers SHALL present the current note and mark what was superseded

For each digest, readers SHALL walk the rows in file order starting from the first plain row: a correction row SHALL be applied when its `supersedes` names the row that is current at that point, and it then becomes the current row; a correction row whose `supersedes` names any other line SHALL NOT be applied. The current note SHALL be the note of the current row after the walk. A correction that is not applied is reachable without hand edits, when two corrections are appended concurrently and both name the same line; such a row SHALL be listed by the store health report, and every surface below SHALL say that an unapplied correction exists for the digest. Every surface that returns an index row's `note` SHALL return the current note and SHALL say whether it was corrected. That set of surfaces is a closed enumeration of two: the `sourcesAdded` items of `update-entry --add-source` (and the tool interface's `add_sources`), and the `sourcesRemoved` items of `update-entry --remove-source` (and the tool interface's `remove_sources`). When the note was corrected, each item SHALL also return the superseded note texts in order and the reason and time of each correction. A surface added later that returns a `note` SHALL be added to this enumeration and SHALL follow the same rule.

#### Scenario: A corrected note is shown when a source is linked

- **GIVEN** stored content whose note was corrected once
- **WHEN** it is linked to a work with `update-entry --add-source`, dry run
- **THEN** the `sourcesAdded` item SHALL carry the corrected note, a flag that it was corrected, and the original note with the correction's reason and time

#### Scenario: Two concurrent corrections name the same row

- **GIVEN** a plain row on line 3, and two corrections appended concurrently on lines 9 and 10, both with `supersedes` 3
- **WHEN** the index is read
- **THEN** the correction on line 9 SHALL be applied, the one on line 10 SHALL NOT, the current note SHALL be line 9's, and the surfaces and the health report SHALL say that line 10 was not applied

#### Scenario: A note that was never corrected

- **WHEN** a source whose row has no correction is linked
- **THEN** the item SHALL carry the plain row's note and the flag SHALL say not corrected

### Requirement: The correction entry point SHALL be available on both interfaces and SHALL refuse a closed list of cases

Correcting a note SHALL be available through both the command-line interface and the tool interface, and both SHALL reach the same implementation. It SHALL take a digest, the corrected note, and a reason. It SHALL write nothing and refuse in exactly these cases, a closed enumeration of six:

| # | Case |
|---|---|
| 1 | the digest is not well formed |
| 2 | the index has an unparseable line |
| 3 | the digest has no row in the index |
| 4 | the corrected note or the reason is empty after trimming whitespace |
| 5 | git does not exclude `sources/index.jsonl` while the store is in a git working tree, or git cannot answer |
| 6 | the store's format is lower than the format that introduces correction rows |

When the corrected note equals the current note, the entry point SHALL write nothing and SHALL report that the note is already current; this outcome is not a refusal.
The response SHALL name the digest, the line number of the appended row, the line number it supersedes, and the note it superseded. A correction SHALL NOT be described, in output or in documentation, as having verified the corrected note; like the original note, it is a statement by its writer. The store health report SHALL list every correction row whose `supersedes` does not name a row for the same digest that was current when the correction was written.

#### Scenario: A correction is written through either interface

- **WHEN** the same correction is requested through the command-line interface and through the tool interface against identical stores
- **THEN** both SHALL append an identical row apart from the `corrected` time, and SHALL return the same line numbers

#### Scenario: The digest was never stored

- **WHEN** a correction names a digest with no index row
- **THEN** it SHALL be refused and nothing SHALL be written

##### Example: An orphan blob cannot be corrected

- **GIVEN** a blob in `sources/` whose digest `sha256:cd…` has no index row (an orphan blob in the store health report)
- **WHEN** a correction names `sha256:cd…`
- **THEN** it SHALL be refused, saying the digest has no row and that storing the same file again records one, and `sources/index.jsonl` SHALL be unchanged

#### Scenario: The store format predates corrections

- **WHEN** a correction is requested on a store whose format is lower than the one that introduces correction rows
- **THEN** it SHALL be refused, naming the required format, and nothing SHALL be written

#### Scenario: The corrected note is already current

- **WHEN** a correction offers exactly the current note
- **THEN** nothing SHALL be written, and the response SHALL say the note is already current without reporting an error

#### Scenario: A correction points at a row that is not the current one

- **GIVEN** an index edited by hand so that a correction row's `supersedes` names a line of another digest
- **WHEN** the store health report runs
- **THEN** it SHALL list that correction row, and SHALL NOT modify the index
