## Purpose

Lets a work's stored bibliographic fields be checked against the work's own full text. Deterministic steps (page text extraction, text-layer detection, field-by-field comparison) are `akashic fulltext` subcommands; reading the byline and the member list is left to the model inside the `akashic-verify-work` skill, which shows a dry run before anything is written.

## ADDED Requirements

### Requirement: fulltext text SHALL write the page text of one of the work's PDFs to a file outside any git work tree

`akashic fulltext text --citekey <ck> [--source <digest>] --out <file>` SHALL read one PDF linked in the work's `akashic.sources` whose source index media type is `application/pdf`, obtain the page count with `pdfinfo` and the text of every page with `pdftotext`, and write JSON `{"citekey", "source", "pageCount", "hasTextLayer", "pages": [{"page", "text"}]}` to `--out`. When the work links more than one PDF and `--source` is not given, the command SHALL be refused and SHALL list the digests. The command SHALL be refused when `--out` lies inside a git work tree, when the digest is absent from the local `sources/` store, or when the work links no PDF. It SHALL NOT write the store. The two-page reading used by `fulltext verify` and `fulltext take` SHALL remain unchanged.

#### Scenario: All pages are written

- **WHEN** the command runs on a seven-page PDF with a text layer
- **THEN** the output file SHALL hold `pageCount` 7, `hasTextLayer` true and seven page entries numbered 1 to 7

#### Scenario: An output path inside a git work tree is refused

- **WHEN** `--out` points into a directory that belongs to a git work tree
- **THEN** the command SHALL exit non-zero and write no file

#### Scenario: Two linked PDFs without a source choice are refused

- **WHEN** the work links two PDFs and `--source` is omitted
- **THEN** the command SHALL exit non-zero and the message SHALL list both digests

---

### Requirement: A PDF with no letters in any page SHALL be reported as having no text layer

`hasTextLayer` SHALL be false exactly when no page text contains a character of Unicode general category L. A work whose PDF has no text layer SHALL be reported by the skill as not checkable, and the skill SHALL NOT run OCR or propose any write for it.

#### Scenario: An image-only PDF

- **WHEN** the command runs on a PDF whose pages carry no extractable letters
- **THEN** `hasTextLayer` SHALL be false

#### Scenario: The skill skips it

- **WHEN** the skill receives `hasTextLayer` false for a work
- **THEN** it SHALL report that work as not checkable with the reason and SHALL NOT call `update-entry`

---

### Requirement: fulltext compare SHALL compare a proposal with the store and emit a ready replacement without writing

`akashic fulltext compare --citekey <ck> --proposal <file> [--out <file>]` SHALL read the work and a proposal JSON `{"source", "authors": {"page", "items"}, "release", "groupMembers", "title", "volume", "issue", "pages", "articleNumber", "date"}` where every field other than `source` and `authors` is optional and each scalar field is `{"value", "page"}`. It SHALL output `{"citekey", "rows": [{"field", "store", "proposed", "page", "status"}], "replaceAuthors", "refusal"}` with `status` one of `same`, `differs`, `absentInStore`, `notProposed`. When the proposed author list differs from the stored one, `replaceAuthors` SHALL be a JSON object accepted as-is by `update-entry --replace-authors`; otherwise it SHALL be null. The proposed `authors`, `release` and `groupMembers` SHALL be checked by the same validator as the replacement leg, and a refusal it would raise SHALL appear in `refusal` rather than as a command failure. The command SHALL NOT write the store and SHALL NOT emit write commands for fields other than the author list.

#### Scenario: A differing byline yields a replacement object

- **GIVEN** a stored list of twenty literals and a proposal of seven items
- **WHEN** compare runs
- **THEN** the `authors` row SHALL have status `differs`
- **AND** `replaceAuthors` SHALL be accepted by `update-entry --replace-authors` in a dry run without refusal

#### Scenario: A proposal that drops a key is reported, not applied

- **GIVEN** a stored list with a person key at position 6 and a proposal that neither carries nor releases it
- **WHEN** compare runs
- **THEN** `refusal` SHALL name position 6 and the command SHALL exit 0

#### Scenario: A differing volume is listed only

- **WHEN** the proposal's `volume` differs from the stored value
- **THEN** a `volume` row SHALL have status `differs`
- **AND** the output SHALL carry no write command for `volume`

---

### Requirement: The akashic-verify-work skill SHALL show a dry run and write only after explicit approval

The skill SHALL take a citekey, run `fulltext text` into a temporary directory outside any git work tree, have the model read the byline, the member list and the scalar fields with their PDF pages into a proposal, run `fulltext compare`, and show a table whose rows are field, store value, value in the work with its page, and proposed write. It SHALL call `update-entry --replace-authors … --apply` only after the user explicitly approves that table in the session; in unattended mode it SHALL stop after the dry run. It SHALL read only local `sources/` content and SHALL NOT fetch from the network. For fields other than the author list it SHALL list the mismatches and state that this change records no source for them. `akashic-fetch-fulltext` SHALL point to this skill as the next step after a full text is stored.

#### Scenario: No approval means no write

- **WHEN** the dry-run table has been shown and the user has not approved it
- **THEN** the skill SHALL NOT call `update-entry` with `--apply`

#### Scenario: fetch-fulltext hands over

- **WHEN** `akashic-fetch-fulltext` finishes storing and linking a PDF
- **THEN** its final step SHALL name `akashic-verify-work` as the next step
