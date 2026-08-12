## MODIFIED Requirements

### Requirement: Every edition SHALL have auditable provenance and reproduction rights

Each edition SHALL declare a stable edition ID, role, language, non-empty bibliographic description, absolute HTTP(S) source URL, ISO retrieval date, upstream revision or immutable source identifier, copyright status, rights note, and inclusion mode. An inline edition SHALL additionally declare a 64-hex-character SHA-256 digest and have a local snapshot whose digest matches the manifest; a snapshot whose authorial structure cannot be parsed SHALL fail closed. Inline snapshot structural parsing SHALL run even when zero corpus volumes are loaded in construction mode. An external-reference edition SHALL NOT contain reproduced source text or declare `sha256`; its provenance SHALL instead be audited through bibliography, source URL, revision, and rights note without a fabricated content digest. Each external-reference value in a corpus record SHALL equal that record's fixed canonical proposition reference; translation prose or any other free text in that field SHALL count as reproduced source text. The fixed edition set SHALL be German original inline, Ogden/Ramsey 1922 English inline, and Pears/McGuinness English external reference, with unique IDs. A licensed inline edition SHALL also declare an auditable `license_evidence_url`. Corpus inline text SHALL reconstruct the pinned snapshots exactly apart from whitespace and recorded editorial footnote markers. Every source image recognized by the renderer's shared rich-text grammar SHALL exist under `source-assets/` and match `source-assets/SHA256SUMS`, regardless of whether the reference occurs in source text, translation, interpretation, project relation, evidence note, or history note. The shared image grammar SHALL include relative `images/` paths containing spaces.

#### Scenario: Public-domain edition is stored inline

- **WHEN** an edition is marked `inline`
- **THEN** validation SHALL recompute its local snapshot digest
- **AND** the digest SHALL match the value recorded in the source manifest

#### Scenario: Malformed snapshot is present before any corpus volume

- **WHEN** `--allow-incomplete` loads an inline snapshot whose digest matches the manifest but whose fixed preface and proposition structure cannot be parsed, while zero corpus volumes exist
- **THEN** validation SHALL fail with `source-mismatch`
- **AND** missing-volume construction gaps SHALL NOT suppress that source failure

#### Scenario: External edition is represented without copied text

- **WHEN** an edition is marked `external_reference`
- **THEN** corpus records SHALL contain edition metadata and the fixed canonical proposition reference only
- **AND** the source manifest SHALL omit `sha256`
- **AND** validation SHALL fail with `license-violation` if reproduced text is present

#### Scenario: External-reference field contains translation prose

- **WHEN** an external-reference field differs from the fixed canonical reference for its owning record
- **THEN** validation SHALL fail with `license-violation`
- **AND** the renderer SHALL NOT be allowed to reproduce that field

#### Scenario: Inclusion mode contradicts digest presence

- **WHEN** an inline edition omits `sha256`, or an external-reference edition declares any `sha256`
- **THEN** validation SHALL fail with `invalid-source`

#### Scenario: Corpus text drifts from its pinned snapshot

- **WHEN** an inline corpus text is altered while the pinned snapshot remains unchanged
- **THEN** validation SHALL fail with `source-mismatch`

#### Scenario: Licensed inline text lacks auditable license evidence

- **WHEN** an inline edition is marked `licensed` without an absolute HTTP(S) `license_evidence_url`
- **THEN** validation SHALL fail with `license-violation`

#### Scenario: Source metadata or offline figure is not auditable

- **WHEN** an edition has empty or malformed provenance, a snapshot cannot be structurally parsed, or a referenced figure is absent or has a different digest
- **THEN** validation SHALL fail with `invalid-source`, `source-mismatch`, `broken-path`, or `digest-mismatch`

#### Scenario: Rich-text field references an offline image

- **WHEN** any renderer-recognized rich-text field contains a Markdown image reference, including an `images/` path with spaces
- **THEN** validation SHALL resolve the same reference grammar used by rendering
- **AND** validation SHALL fail with `broken-path` or `digest-mismatch` when the asset is missing, escapes `source-assets/`, is not listed, or has different bytes

### Requirement: Current evidence and historical context SHALL remain separate

Project relations SHALL describe the current `main` state and SHALL cite current evidence with project-root-relative paths plus stable symbols, requirement names, test names, or document headings. Historical branch, commit, and issue references SHALL live under `history` and SHALL declare `retained`, `revised`, or `rejected`. A generated document SHALL NOT serve as load-bearing current evidence. The evidence `kind` SHALL be structural: headings must resolve as exact Markdown heading lines, tests as named test function declarations under `Tests/`, requirements as exact complete `### Requirement:` names under `openspec/`, and symbols as Swift declaration identifiers. Swift comments and string literal contents SHALL be excluded before symbol or test declaration matching, so a locator present only as prose cannot satisfy evidence. Canonical corpus and source snapshots SHALL NOT cite themselves as current implementation evidence. Paths SHALL be standardized before these policy checks so `./`, `..`, or symlink spelling cannot bypass them.

#### Scenario: Current source evidence resolves locally

- **WHEN** evidence names an existing project file and a symbol declared in that file
- **THEN** evidence validation SHALL succeed without network access

##### Example: A Swift symbol is verified structurally

- **GIVEN** evidence kind `symbol` names `Sources/AkashicStoreIO/LibraryStore.swift` and the Swift declaration identifier `LibraryStore`
- **WHEN** evidence validation runs from the repository root
- **THEN** it SHALL locate that declaration in the named file without a network request

#### Scenario: Broken current or historical reference is surfaced

- **WHEN** a current path or symbol is absent, or a history commit cannot be resolved by Git
- **THEN** validation SHALL fail with `broken-path`, `missing-symbol`, or `unknown-commit`

#### Scenario: Locator kind is only a coincidental substring

- **WHEN** a locator exists in a file but does not match its declared heading, test declaration, complete requirement name, or Swift declaration structure
- **THEN** validation SHALL fail with `invalid-evidence`

#### Scenario: Comment or string imitates a Swift declaration

- **WHEN** a symbol or test locator appears only inside a Swift line comment, nested block comment, ordinary string, multiline string, or raw string
- **THEN** validation SHALL fail with `invalid-evidence`
- **AND** no prose occurrence SHALL be accepted as structural evidence

### Requirement: Validation SHALL be strict, deterministic, and actionable

The `tractatus-doc validate` command SHALL perform schema, cross-volume, alignment, Chinese-content, relation, evidence, source-digest, image-digest, and license checks. Unknown YAML keys SHALL be rejected. Errors SHALL use `path:record-id:error-code: message`, SHALL use project-relative paths, and SHALL be sorted by path, record ID, and error code before output. Every diagnostic field SHALL escape control characters, bidirectional text controls, backslashes, and field separators so untrusted YAML values cannot forge terminal output. Construction gaps SHALL be sorted independently and rendered as `incomplete: KIND VALUE` before diagnostics, including when diagnostics make the command fail. Any error SHALL produce a non-zero exit status.

#### Scenario: Strict corpus passes

- **WHEN** all scoped records and required content are valid
- **THEN** `swift run tractatus-doc validate --root docs/tractatus` SHALL exit zero
- **AND** it SHALL print counts for propositions, source units, aligned segments, and project relations

#### Scenario: Construction mode reports incompleteness

- **WHEN** `--allow-incomplete` is supplied during corpus construction
- **THEN** missing volumes and propositions SHALL be listed explicitly
- **AND** structural, alignment, license, digest, image, and evidence errors SHALL still fail the command

#### Scenario: Construction mode has gaps and a substantive error

- **WHEN** `--allow-incomplete` encounters at least one missing volume or proposition and at least one substantive validation diagnostic in the same run
- **THEN** the command SHALL exit non-zero
- **AND** stderr SHALL contain every sorted `incomplete:` line followed by every sorted diagnostic line

#### Scenario: Hostile schema value cannot forge a diagnostic line

- **WHEN** an unknown key, identifier, or enum value contains a newline, terminal control, bidirectional override, or backslash
- **THEN** validation SHALL render those scalars as visible escape sequences in one diagnostic line
- **AND** the raw control scalar SHALL NOT reach stdout or stderr

##### Example: Diagnostic escapes remain visible and single-line

- **GIVEN** an unknown key consists of `field`, LF, ESC, U+202E, a backslash, and `tail`
- **WHEN** validation formats its `unknown-key` diagnostic
- **THEN** the output SHALL contain the literal escapes `\u{000A}`, `\u{001B}`, `\u{202E}`, and `\u{005C}`
- **AND** the output SHALL contain no raw LF, ESC, or U+202E scalar inside that diagnostic field
