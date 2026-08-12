## ADDED Requirements

### Requirement: The corpus SHALL declare an exact authorial scope

The canonical corpus SHALL include exactly eight Wittgenstein preface paragraphs and all 526 numbered propositions from 1 through 7. Validation SHALL compare the ordered manifest inventory with a fixed canonical fingerprint rather than trusting a self-declared shortened inventory. The dedication and motto SHALL be retained only as source metadata and SHALL match the pinned authorial wording exactly. Russell's introduction and the index SHALL NOT appear as interpreted corpus records.

#### Scenario: Scope inventory is complete

- **WHEN** strict validation reads the source manifest and every corpus volume
- **THEN** the set of corpus record IDs SHALL equal the manifest inventory for the preface and propositions 1 through 7
- **AND** no record from Russell's introduction or the index SHALL be accepted

#### Scenario: A numbered proposition is omitted

- **WHEN** a proposition ID present in the manifest inventory is absent from all corpus volumes
- **THEN** validation SHALL fail with `missing-proposition`

### Requirement: Every edition SHALL have auditable provenance and reproduction rights

Each edition SHALL declare a stable edition ID, role, language, non-empty bibliographic description, absolute HTTP(S) source URL, ISO retrieval date, upstream revision or immutable source identifier, copyright status, rights note, and inclusion mode. An inline edition SHALL additionally declare a 64-hex-character SHA-256 digest and have a local snapshot whose digest matches the manifest; a snapshot whose authorial structure cannot be parsed SHALL fail closed. An external-reference edition SHALL NOT contain reproduced source text or declare `sha256`; its provenance SHALL instead be audited through bibliography, source URL, revision, and rights note without a fabricated content digest. The fixed edition set SHALL be German original inline, Ogden/Ramsey 1922 English inline, and Pears/McGuinness English external reference, with unique IDs. A licensed inline edition SHALL also declare an auditable `license_evidence_url`. Corpus inline text SHALL reconstruct the pinned snapshots exactly apart from whitespace and recorded editorial footnote markers. Every referenced source image SHALL exist under `source-assets/` and match `source-assets/SHA256SUMS`.

#### Scenario: Public-domain edition is stored inline

- **WHEN** an edition is marked `inline`
- **THEN** validation SHALL recompute its local snapshot digest
- **AND** the digest SHALL match the value recorded in the source manifest

#### Scenario: External edition is represented without copied text

- **WHEN** an edition is marked `external_reference`
- **THEN** corpus records SHALL contain edition metadata and proposition references only
- **AND** the source manifest SHALL omit `sha256`
- **AND** validation SHALL fail with `license-violation` if reproduced text is present

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

### Requirement: Corpus records SHALL use stable hierarchical identifiers

Numbered propositions SHALL use their printed decimal numbers as IDs. Preface paragraphs SHALL use `preface.<paragraph-number>`. Aligned segments SHALL append a lowercase alphabetic suffix to their owner, such as `2.0121.a`. IDs SHALL be unique across all volumes, every non-root proposition SHALL identify an existing parent, and each YAML `volume` value SHALL equal its physical filename so exchanging two complete files cannot pass validation.

#### Scenario: Numeric proposition order is accepted

- **WHEN** a volume contains `2.1`, `2.01`, `2.011`, and `2.012` in their canonical hierarchical order
- **THEN** validation SHALL preserve that order without using ordinary lexicographic sorting

#### Scenario: Parent or duplicate ID is invalid

- **WHEN** a record repeats an existing ID or names a parent that does not exist
- **THEN** validation SHALL fail with `duplicate-id` or `missing-parent`, respectively

### Requirement: Alignment SHALL cover every inline source unit exactly once

Each proposition SHALL store an ordered source-unit array for every inline edition. Each segment SHALL align one or more indexes from every inline edition. Across all segments owned by a proposition, each source-unit index SHALL occur exactly once. The permitted alignment shapes SHALL be 1-to-1, 2-to-1, or 1-to-2; the latter two SHALL be used only for edition boundary differences. A 2-to-2 alignment or any alignment containing three or more units from one edition SHALL fail. This bound SHALL preserve sentence-level translation and interpretation rather than allowing a mega-segment to satisfy coverage mechanically. Flattened alignment indexes SHALL be strictly ordered for every inline edition. A 1-to-1 pair whose units in both editions each contain an obvious internal sentence boundary SHALL fail, because array boundaries themselves SHALL NOT be trusted as proof of sentence-level granularity. For 2-to-1 or 1-to-2, the single-unit side SHALL NOT hide multiple complete sentences and the multi-unit side SHALL use plausible punctuation boundaries rather than arbitrary character splits.

#### Scenario: Different sentence boundaries are aligned

- **WHEN** German units `[0, 1]` correspond to Ogden/Ramsey unit `[0]`
- **THEN** one segment with `de: [0, 1]` and `en_ogden_ramsey_1922: [0]` SHALL pass validation

#### Scenario: Mega-segment hides sentence-level interpretation

- **WHEN** one segment aligns 2-to-2 units or three or more source units from any single inline edition
- **THEN** validation SHALL fail with `alignment-granularity`
- **AND** the diagnostic SHALL direct the editor to split the units into sentence-level translations and interpretations

#### Scenario: A source unit hides multiple sentences

- **WHEN** both sides of a 1-to-1 alignment contain an obvious complete-sentence boundary inside one source unit
- **THEN** validation SHALL fail with `source-unit-granularity`

#### Scenario: Covered source indexes are cross-wired

- **WHEN** every source index is covered once but one edition's flattened indexes are out of order
- **THEN** validation SHALL fail with `alignment-order`

##### Example: Coverage outcomes

| Source indexes | Segment alignments | Expected result |
| --- | --- | --- |
| `[0, 1]` | `.a=[0]`, `.b=[1]` | valid |
| `[0, 1]` | `.a=[0]` | `alignment-gap` for index 1 |
| `[0, 1]` | `.a=[0]`, `.b=[0, 1]` | `alignment-duplicate` for index 0 |

### Requirement: Every aligned segment SHALL contain separate Traditional Chinese translation and interpretation

Every segment SHALL contain non-empty `translation_zh_tw` and `interpretation_zh_tw` values. The translation SHALL be a project-authored working translation based primarily on German and checked against licensed inline translations. The interpretation SHALL explain the philosophical claim, terminology, ambiguity, or limit and SHALL NOT be substituted by the translation.
Corpus-construction boilerplate that merely quotes a clause and says it starts, advances, or concludes the proposition SHALL NOT count as interpretation. Placeholder markers SHALL be detected as tokens even when decorated with a proposition number or punctuation, such as the four-letter marker formed by `T`, `O`, `D`, and `O`, or the three-letter marker formed by `T`, `B`, and `D`, followed by `：2.01`.

#### Scenario: Translation and interpretation are present

- **WHEN** a segment has distinct non-placeholder values for both Chinese fields
- **THEN** the segment SHALL pass the Chinese-content check

##### Example: Proposition 1 keeps translation and reading separate

- **GIVEN** `translation_zh_tw` is `世界是一切發生之事。`
- **AND** `interpretation_zh_tw` explains that the opening defines the world through facts rather than a mere collection of things
- **WHEN** strict validation checks proposition `1`
- **THEN** both fields SHALL be accepted as distinct, substantive content

#### Scenario: Missing or placeholder content is rejected

- **WHEN** either Chinese field is empty or contains `<unfinished>`, `<unreviewed>`, or another configured placeholder marker
- **THEN** strict validation SHALL fail with `missing-translation` or `missing-interpretation`

#### Scenario: Construction boilerplate replaces sentence-level interpretation

- **WHEN** an interpretation merely wraps a translated clause in stock text such as starting, advancing, or concluding the proposition
- **THEN** strict validation SHALL fail with `generic-interpretation`
- **AND** the editor SHALL replace it with a direct explanation of that sentence's philosophical role, terminology, ambiguity, or limit

### Requirement: Every proposition SHALL state at least one explicit project relation

Every proposition SHALL contain at least one project relation. Its `status` SHALL be one of `implemented`, `partial`, `aspirational`, `analogy_only`, `rejected`, `not_applicable`, or `intentional_nonconformance`. Its `mode`, when applicable, SHALL be one of `instance`, `structural_invariant`, `semantic_operation`, `formal_derivation`, `refusal`, `shown_constraint`, `meta_elucidation`, or `declared_nonconformance`. Every relation SHALL contain a Traditional Chinese claim and rationale.
Each rationale SHALL be proposition-specific: after whitespace normalization, a rationale SHALL NOT be reused by a different proposition.

#### Scenario: Honest absence of a project mapping

- **WHEN** a proposition has no defensible Akashic counterpart
- **THEN** it SHALL use `status: not_applicable`
- **AND** its rationale SHALL state why forcing an analogy would be misleading

#### Scenario: Invalid or incomplete relation is rejected

- **WHEN** a proposition has no relation, an unknown enum value, an empty claim, or an empty rationale
- **THEN** validation SHALL fail with `invalid-relation`

#### Scenario: A generic relation rationale is reused across propositions

- **WHEN** two different proposition records contain the same rationale after whitespace normalization
- **THEN** validation SHALL fail with `duplicate-rationale`
- **AND** the diagnostic SHALL direct the editor to explain each proposition's concrete philosophical content

### Requirement: Current evidence and historical context SHALL remain separate

Project relations SHALL describe the current `main` state and SHALL cite current evidence with project-root-relative paths plus stable symbols, requirement names, test names, or document headings. Historical branch, commit, and issue references SHALL live under `history` and SHALL declare `retained`, `revised`, or `rejected`. A generated document SHALL NOT serve as load-bearing current evidence. The evidence `kind` SHALL be structural: headings must resolve as exact Markdown heading lines, tests as named test functions under `Tests/`, requirements under `openspec/`, and symbols as identifiers in Swift source. Canonical corpus and source snapshots SHALL NOT cite themselves as current implementation evidence. Paths SHALL be standardized before these policy checks so `./`, `..`, or symlink spelling cannot bypass them.

#### Scenario: Current source evidence resolves locally

- **WHEN** evidence names an existing project file and a symbol present in that file
- **THEN** evidence validation SHALL succeed without network access

##### Example: A Swift symbol is verified structurally

- **GIVEN** evidence kind `symbol` names `Sources/AkashicStoreIO/LibraryStore.swift` and the Swift identifier `LibraryStore`
- **WHEN** evidence validation runs from the repository root
- **THEN** it SHALL locate that identifier in the named file without a network request

#### Scenario: Broken current or historical reference is surfaced

- **WHEN** a current path or symbol is absent, or a history commit cannot be resolved by Git
- **THEN** validation SHALL fail with `broken-path`, `missing-symbol`, or `unknown-commit`

#### Scenario: Locator kind is only a coincidental substring

- **WHEN** a locator exists in a file but does not match its declared heading, test, requirement, or symbol structure
- **THEN** validation SHALL fail with `invalid-evidence`

### Requirement: Validation SHALL be strict, deterministic, and actionable

The `tractatus-doc validate` command SHALL perform schema, cross-volume, alignment, Chinese-content, relation, evidence, source-digest, and license checks. Unknown YAML keys SHALL be rejected. Errors SHALL use `path:record-id:error-code: message`, SHALL use project-relative paths, and SHALL be sorted by path, record ID, and error code before output. Every diagnostic field SHALL escape control characters, bidirectional text controls, backslashes, and field separators so untrusted YAML values cannot forge terminal output. Any error SHALL produce a non-zero exit status.

#### Scenario: Strict corpus passes

- **WHEN** all scoped records and required content are valid
- **THEN** `swift run tractatus-doc validate --root docs/tractatus` SHALL exit zero
- **AND** it SHALL print counts for propositions, source units, aligned segments, and project relations

#### Scenario: Construction mode reports incompleteness

- **WHEN** `--allow-incomplete` is supplied during corpus construction
- **THEN** missing volumes and propositions SHALL be listed explicitly
- **AND** structural, alignment, license, digest, and evidence errors SHALL still fail the command

#### Scenario: Hostile schema value cannot forge a diagnostic line

- **WHEN** an unknown key, identifier, or enum value contains a newline, terminal control, bidirectional override, or backslash
- **THEN** validation SHALL render those scalars as visible escape sequences in one diagnostic line
- **AND** the raw control scalar SHALL NOT reach stdout or stderr

##### Example: Diagnostic escapes remain visible and single-line

- **GIVEN** an unknown key consists of `field`, LF, ESC, U+202E, a backslash, and `tail`
- **WHEN** validation formats its `unknown-key` diagnostic
- **THEN** the output SHALL contain the literal escapes `\u{000A}`, `\u{001B}`, `\u{202E}`, and `\u{005C}`
- **AND** the output SHALL contain no raw LF, ESC, or U+202E scalar inside that diagnostic field

### Requirement: Markdown rendering SHALL be derived and byte-deterministic

The renderer SHALL emit German, Ogden/Ramsey, Pears/McGuinness, and Traditional Chinese columns in that order. External-reference editions SHALL render a bibliographic reference and link instead of copied text. Each segment SHALL render its Chinese interpretation, and each proposition SHALL render its project relations, evidence, and history. Pinned source-image references SHALL render as HTML images pointing to checked-in offline assets rather than broken snapshot-relative links. The output SHALL contain a generated-file notice and SHALL NOT contain timestamps, absolute paths, or environment-dependent values.

#### Scenario: Rendering the same corpus twice is identical

- **WHEN** the same validated corpus is rendered twice with the same tool version
- **THEN** both output byte streams SHALL have identical SHA-256 digests

#### Scenario: Checked-in output has drifted

- **WHEN** `render --check` produces bytes different from the checked-in Markdown
- **THEN** the command SHALL fail with `generated-drift`
- **AND** it SHALL NOT modify the output file

### Requirement: Continuous integration SHALL enforce the complete corpus and generated output

The main-branch workflow SHALL run strict corpus validation and generated-output checking after Swift tests. CI SHALL operate from checked-in files without retrieving source texts from the network.

#### Scenario: Corpus regression blocks integration

- **WHEN** a pushed change omits required content, breaks evidence, violates source rights, or leaves generated Markdown stale
- **THEN** the CI job SHALL fail before reporting the repository as valid

##### Example: Stale generated output fails the workflow

- **GIVEN** a canonical YAML translation changes while `docs/tractatus/generated/tractatus-project-map.md` remains unchanged
- **WHEN** CI runs strict validation followed by `render --check`
- **THEN** `render --check` SHALL report `generated-drift` and the job SHALL fail
