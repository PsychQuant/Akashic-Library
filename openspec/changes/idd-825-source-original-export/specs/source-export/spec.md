## Purpose

The stored copy in `sources/` is the original of a work's full-text PDF; copies outside the library are exported from it by one entry point that verifies the bytes, names the file by a fixed rule, and records each export so that stale copies can be found later.

## ADDED Requirements

### Requirement: The original of a work's full-text PDF SHALL be the stored copy linked to the work

The original of a work's full-text PDF SHALL be stored content in `sources/` whose digest is on that work's `akashic.sources` and whose index row records `application/pdf` as its media type. A copy of that PDF outside the library SHALL be written only by the export entry point of this capability, from the stored bytes. A file outside the library that was not written by the export entry point SHALL NOT be described by any surface of this system as a copy of the original.

#### Scenario: A copy is made for a project folder

- **WHEN** a user needs a work's PDF in a folder outside the library
- **THEN** the copy SHALL be produced by the export entry point from the bytes in `sources/`, and not by copying a scratch file, a download, or another copy

##### Example: A downloaded file is not the source of a copy

- **GIVEN** a work whose linked PDF has digest `sha256:aa…` and a file in the downloads folder with the same bytes
- **WHEN** a copy is needed in a project's references folder
- **THEN** the copy SHALL be written by the export entry point, and its export record SHALL name digest `sha256:aa…`

### Requirement: Which linked PDF is the original SHALL be decided by a closed table

When the caller does not name a digest, the export entry point SHALL decide the original from the PDFs linked to the work by the following closed table, and SHALL NOT infer a version from the free-text `note`. This is a closed enumeration of six cases; no other case SHALL be decided by similarity to one of them. "Candidates" are the linked PDFs not recorded as `supplement`, counted by the rule below the table.

| # | Linked PDFs | Original |
|---|---|---|
| 1 | none | none: refuse, saying the work has no linked PDF |
| 2 | one or more, every one recorded as `supplement` | none: refuse, saying only supplements are linked |
| 3 | exactly one candidate, of any recorded version other than `supplement` or of no recorded version | that candidate |
| 4 | more than one candidate, exactly one recorded as `version-of-record` | the `version-of-record` one |
| 5 | more than one candidate, none recorded as `version-of-record` | none: refuse and list every candidate digest with its recorded version or "version unknown" |
| 6 | more than one candidate, two or more recorded as `version-of-record` | none: refuse and list them |

A linked PDF is a digest on `akashic.sources` whose index row records media type `application/pdf` and whose blob is present locally. A linked digest whose media type cannot be read locally (absent, unreadable, or not matching its index row) SHALL also be counted as a candidate for the purpose of cases 3 to 6, as `fulltext text` counts it, so that it can make the choice ambiguous but SHALL NOT be chosen; when it is the only candidate, export SHALL refuse and say that the stored copy is not present. A PDF recorded as `supplement` SHALL NOT be a candidate and SHALL NOT make the choice ambiguous. In case 4, the other linked PDFs SHALL NOT be exported by default. Any linked PDF, a supplement included, SHALL be exportable when the caller names its digest.

#### Scenario: A version of record and an author manuscript are both linked

- **WHEN** a work links two PDFs, one recorded as `version-of-record` and one as `accepted-manuscript`
- **THEN** export without a named digest SHALL write the `version-of-record` one, and SHALL NOT write the other

##### Example: Only the version of record is written

- **GIVEN** work `magis2016efficient` linking `sha256:aa…` (`version-of-record`) and `sha256:bb…` (`accepted-manuscript`)
- **WHEN** it is exported to a folder without naming a digest
- **THEN** exactly one PDF is written, with digest `sha256:aa…`

#### Scenario: Only a supplement is linked

- **WHEN** a work's only linked PDF is recorded as `supplement`
- **THEN** export without a named digest SHALL refuse and write nothing, and SHALL NOT write the supplement as `<citekey>.pdf`

#### Scenario: Several PDFs and no recorded version

- **WHEN** a work links two PDFs and neither row records a version
- **THEN** export without a named digest SHALL refuse, write nothing, and list both digests as "version unknown"

#### Scenario: A non-original version is named

- **WHEN** the caller names the digest of a linked `accepted-manuscript`
- **THEN** export SHALL write that PDF, under the non-original file name

#### Scenario: A named digest is not linked to the work

- **WHEN** the caller names a digest that is not on the work's `akashic.sources`
- **THEN** export SHALL refuse and write nothing

### Requirement: An index row SHALL be able to record the version of a stored PDF

`store-source` (both interfaces) SHALL accept an optional version for the content it stores and SHALL write it to the new index row as the field `version`. The accepted values SHALL be exactly `version-of-record`, `accepted-manuscript`, `preprint`, and `supplement`; any other value SHALL be refused before anything is written. An index row without `version` SHALL be read as "version unknown". When the content is already indexed, a submitted version that differs from the recorded one SHALL be returned as discarded, in the same way as the other discarded provenance fields.

#### Scenario: A version is recorded at storage time

- **WHEN** a PDF is stored with version `version-of-record`
- **THEN** its new index row SHALL carry `"version": "version-of-record"`

#### Scenario: An unknown version value is offered

- **WHEN** `store-source` is called with version `published`
- **THEN** it SHALL refuse, name the four accepted values, and write nothing

#### Scenario: A row written before this change is read

- **WHEN** an index row has no `version` field
- **THEN** it SHALL load as before and SHALL count as "version unknown" in the original table

### Requirement: The export entry point SHALL write verified stored bytes outside the library

The export entry point SHALL be available through both the command-line interface and the tool interface, and both SHALL reach the same implementation. It SHALL take a work's citekey, or a digest that is linked to exactly one work, and a destination directory; it SHALL optionally take a named digest, a file name, a Markdown digest, and a replace flag. Before writing, it SHALL hash the stored bytes it is about to write and SHALL refuse, writing nothing outside the library, when the result differs from the digest. It SHALL NOT modify, move, or delete anything in `sources/` other than appending its export record.

#### Scenario: A digest without a citekey is given

- **WHEN** the caller gives a digest linked to exactly one work and no citekey
- **THEN** export SHALL proceed with that work's citekey

##### Example: A digest linked to two works is refused

- **GIVEN** digest `sha256:cc…` on the `akashic.sources` of two works
- **WHEN** it is exported without a citekey
- **THEN** export SHALL refuse, name both citekeys, and write nothing

#### Scenario: The stored bytes no longer match their digest

- **GIVEN** a stored blob of the indexed size whose bytes were altered
- **WHEN** it is exported
- **THEN** export SHALL refuse, name the computed digest, and write no file at the destination

#### Scenario: Both interfaces receive the same request

- **WHEN** the same export is requested through the command-line interface and through the tool interface against identical stores
- **THEN** both SHALL write identical bytes under the same file name and SHALL append export records with the same fields

### Requirement: The export file name SHALL follow a fixed rule unless overridden

Without a file-name override, the export entry point SHALL name the original `<citekey>.pdf`, a named non-original PDF `<citekey>.<first 12 hexadecimal characters of its digest>.pdf`, and an exported Markdown file with the same stem as its PDF and the extension `.md`. A file-name override SHALL be a single path component that is not empty, not `.` or `..`, and contains no `/` and no NUL; it SHALL be used as given, without transliteration of non-ASCII characters.

#### Scenario: The default names

- **WHEN** work `warm1989weighted` is exported with its original PDF and the Markdown derived from it
- **THEN** the files SHALL be named `warm1989weighted.pdf` and `warm1989weighted.md`

#### Scenario: A non-original version is named

- **WHEN** the caller names linked digest `sha256:0a9a79d3030c…`, which is not the original
- **THEN** the file SHALL be named `<citekey>.0a9a79d3030c.pdf`

#### Scenario: An override contains a path separator

- **WHEN** the override is `refs/warm.pdf`
- **THEN** export SHALL refuse before writing anything

### Requirement: The export destination SHALL pass the full-text output gate

The destination SHALL be an existing directory. When the directory has a git ancestor, the export entry point SHALL require git to report both the final file name and the temporary name used for the atomic write as ignored, and SHALL refuse when git cannot be run or does not answer, with the same rule as `fulltext take`. The export entry point SHALL NOT follow a symlink at the final file name. When a regular file already exists at the final file name, it SHALL compare that file's digest with the bytes to be written: identical bytes SHALL NOT be rewritten; different bytes SHALL be refused, naming the found digest, unless the replace flag is given, in which case the file SHALL be replaced by an atomic rename from a temporary file in the same directory. A directory, symlink, or other non-regular file at the final file name SHALL be refused in every case.

#### Scenario: A references folder ignored by its repository

- **WHEN** the destination is inside a git working tree that ignores the final and temporary file names
- **THEN** export SHALL write the file

#### Scenario: A folder its repository does not ignore

- **WHEN** the destination is inside a git working tree that does not ignore the final file name
- **THEN** export SHALL refuse, name the working tree, and write nothing

##### Example: A folder tracked by its repository

- **GIVEN** a project repository whose `.gitignore` does not mention `references/`
- **WHEN** a work is exported to that repository's `references/` folder
- **THEN** export SHALL refuse, no file SHALL appear in `references/`, and no record SHALL be appended

#### Scenario: The same bytes are already there

- **WHEN** the file at the destination already has the digest being exported
- **THEN** export SHALL NOT rewrite it, and SHALL record the outcome `already-present`

#### Scenario: Different bytes are already there

- **WHEN** the file at the destination has a different digest and the replace flag is absent
- **THEN** export SHALL refuse, name the found digest, and leave the file unchanged

##### Example: An older copy blocks the export until replace is given

- **GIVEN** a folder holding `warm1989weighted.pdf` with digest `sha256:ee…`, and the work's original `sha256:aa…`
- **WHEN** the work is exported to that folder without the replace flag, and then again with it
- **THEN** the first run SHALL refuse naming `sha256:ee…` and append no record; the second SHALL replace the file and append one record with outcome `replaced` and `replaced` `sha256:ee…`

### Requirement: Every export SHALL append a record in the store

Every file the export entry point writes, finds already present, or replaces SHALL be recorded by appending one line to `sources/exports.jsonl`. The line SHALL carry `at` (ISO 8601 with an explicit UTC offset), `citekey`, `digest`, `role` (`pdf` or `markdown`), `selection` (`original` when the PDF was chosen by the original table, `named` when the caller named its digest; a Markdown line carries the selection of its PDF), `destination` (the physical absolute path of the directory), `file`, and `outcome` (`written`, `already-present`, or `replaced`); a `replaced` line SHALL also carry `replaced`, the digest of the file it replaced. Before appending, the export entry point SHALL verify, fail-closed, that git excludes `sources/exports.jsonl` when the store is in a git working tree, with the same rule that guards `sources/index.jsonl`. Existing lines SHALL NOT be rewritten or deleted. A refused export SHALL append nothing.

#### Scenario: A PDF and its Markdown are exported

- **WHEN** a work's original PDF and its Markdown are written to a folder
- **THEN** two lines SHALL be appended, one with role `pdf` and one with role `markdown`, each naming its own digest and file

#### Scenario: The record would not be excluded from git

- **WHEN** the store is a git working tree whose ignore rules do not exclude `sources/exports.jsonl`
- **THEN** export SHALL refuse before writing any file at the destination

#### Scenario: An export is refused

- **WHEN** an export is refused for any reason
- **THEN** `sources/exports.jsonl` SHALL be unchanged

### Requirement: A read-only check SHALL report the state of every recorded copy

A read-only check SHALL report, for each line of `sources/exports.jsonl`, exactly one of the following states, computed when the check runs. This is a closed enumeration of five states.

| State | Condition |
|---|---|
| `current` | the file exists and its digest equals the recorded digest, and: for selection `original`, the recorded PDF digest is still the work's original by the original table; for selection `named`, the recorded PDF digest is still on the work's `akashic.sources` (a Markdown line follows its PDF's line) |
| `superseded` | the file exists and its digest equals the recorded digest, but the condition for `current` no longer holds: for `original`, the work's original is now another digest or none can be decided; for `named`, the digest is no longer linked to the work |
| `differs` | the file exists as a regular file and its digest differs from the recorded digest |
| `missing` | the destination directory can be read and the file does not exist |
| `unreadable` | the destination directory or the file cannot be read, or the path holds something other than a regular file |

The check SHALL NOT write, move, or delete any file, and SHALL NOT rewrite the record. A line written for a file that a later line replaced SHALL be reported against the file's present content like any other line.

#### Scenario: The original changes after an export

- **WHEN** a work exported as `sha256:aa…` later has a new `version-of-record` linked, so that its original becomes `sha256:dd…`
- **THEN** the check SHALL report the earlier copy as `superseded`

#### Scenario: A named non-original export stays current

- **WHEN** an `accepted-manuscript` exported by naming its digest is still linked to the work, while the work's original is the `version-of-record`
- **THEN** the check SHALL report that copy as `current`, not `superseded`

#### Scenario: The copy was edited

- **WHEN** the exported file was modified after the export
- **THEN** the check SHALL report `differs` and SHALL leave the file and the record unchanged

#### Scenario: The folder cannot be read

- **WHEN** the destination directory exists but cannot be listed
- **THEN** the check SHALL report `unreadable`, not `missing`

### Requirement: A Markdown converted from a stored PDF SHALL record its PDF and converter and be exported with it

`store-source` (both interfaces) SHALL accept two optional fields for the content it stores, `derived-from` and `converter`, and SHALL write them to the new index row. `derived-from` SHALL be a digest that already has an index row with media type `application/pdf`; `converter` SHALL name the converting program and its version and SHALL be required whenever `derived-from` is given. The Markdown bytes SHALL be stored as submitted. When a PDF is exported, the export entry point SHALL also write the stored Markdown whose `derived-from` is that PDF's digest when there is exactly one such Markdown; when there are several and the caller has not named one, it SHALL write the PDF, write no Markdown, and list the candidate digests; when the caller names a Markdown digest whose `derived-from` is not the exported PDF, it SHALL refuse and write nothing.

#### Scenario: A Markdown is stored with its source PDF

- **WHEN** a Markdown file is stored with `derived-from` `sha256:aa…` and converter `marker-pdf 1.2.3`
- **THEN** its index row SHALL carry both fields, and its stored bytes SHALL equal the submitted file

#### Scenario: The derived-from digest is not an indexed PDF

- **WHEN** `derived-from` names a digest with no index row, or one whose media type is not `application/pdf`
- **THEN** `store-source` SHALL refuse and write nothing

#### Scenario: Two Markdown conversions of one PDF

- **WHEN** two stored Markdown files are derived from the exported PDF and none is named
- **THEN** export SHALL write the PDF, write no Markdown, and list both Markdown digests

##### Example: Two marker versions

- **GIVEN** PDF `sha256:aa…` with Markdown `sha256:m1…` (converter `marker-pdf 1.2.3`) and `sha256:m2…` (converter `marker-pdf 1.4.0`), both derived from it
- **WHEN** the work is exported without naming a Markdown, and then with `sha256:m2…` named
- **THEN** the first run SHALL write only the PDF and list `sha256:m1…` and `sha256:m2…`; the second SHALL write the PDF and `sha256:m2…` as `<citekey>.md`

### Requirement: The full-text skill SHALL place copies outside the library only by export

After a full text is stored and linked, the `akashic-fetch-fulltext` skill SHALL produce any copy the user wants outside the library with the export entry point, and SHALL NOT copy the scratch file written by `fulltext take`, a file from the downloads folder, or another copy. The store-writing reference of the plugin SHALL state that the original of a full-text PDF is the stored copy and that copies outside the library are exported from it.

#### Scenario: The user asks for the PDFs in a project folder

- **WHEN** the skill has stored and linked a batch and the user wants the PDFs in a project's references folder
- **THEN** the skill SHALL run the export entry point for each work, and its report SHALL list each exported file with its digest

#### Scenario: The skill text is read

- **WHEN** the skill's steps after linking are read
- **THEN** they SHALL name the export entry point and SHALL NOT instruct a `cp` from the scratch directory
