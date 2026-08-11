## MODIFIED Requirements

### Requirement: Every edition SHALL have auditable provenance and reproduction rights

Each edition SHALL declare a stable edition ID, role, language, non-empty bibliographic description, absolute HTTP(S) source URL, ISO retrieval date, upstream revision or immutable source identifier, copyright status, rights note, and inclusion mode. An inline edition SHALL additionally declare a 64-hex-character SHA-256 digest and have a local snapshot whose digest matches the manifest. Every inline snapshot SHALL contain each authorial passage ID from `manifest.scope.inventory` exactly once and in that exact order; order SHALL be measured from every heading's global position in the original snapshot, without normalizing preface and numbered-passage blocks. Missing, extra, duplicate, or reordered passage headings SHALL fail closed before corpus fidelity comparison. Inline snapshot structural validation SHALL run even when zero corpus volumes are loaded in construction mode. An external-reference edition SHALL NOT contain reproduced source text or declare `sha256`; its provenance SHALL instead be audited through bibliography, source URL, revision, and rights note without a fabricated content digest. Each external-reference value in a corpus record SHALL equal that record's fixed canonical proposition reference; translation prose or any other free text in that field SHALL count as reproduced source text. The fixed edition set SHALL be German original inline, Ogden/Ramsey 1922 English inline, and Pears/McGuinness English external reference, with unique IDs. A licensed inline edition SHALL also declare an auditable `license_evidence_url`. Corpus inline text SHALL reconstruct the pinned snapshots exactly apart from whitespace and recorded editorial footnote markers. Every source image recognized by the renderer's shared rich-text grammar SHALL exist under `source-assets/` and match `source-assets/SHA256SUMS`, regardless of whether the reference occurs in source text, translation, interpretation, project relation, evidence note, or history note. The shared image grammar SHALL include relative `images/` paths containing spaces.

#### Scenario: Public-domain edition is stored inline

- **WHEN** an edition is marked `inline`
- **THEN** validation SHALL recompute its local snapshot digest
- **AND** the digest SHALL match the value recorded in the source manifest

#### Scenario: Partial snapshot is present before any corpus volume

- **WHEN** `--allow-incomplete` loads a digest-matching inline snapshot that contains at least one valid authorial heading but omits another ID from `manifest.scope.inventory`, while zero corpus volumes exist
- **THEN** validation SHALL fail with `source-mismatch`
- **AND** missing-volume construction gaps SHALL NOT suppress that source failure

#### Scenario: Snapshot headings are duplicate or reordered

- **WHEN** an inline snapshot repeats an authorial passage heading or presents the complete inventory in a different order
- **THEN** validation SHALL fail with `source-mismatch`
- **AND** corpus text SHALL NOT be used to hide the structural defect

#### Scenario: Passage kinds are globally reordered

- **WHEN** a numbered proposition heading appears before a preface heading even though `manifest.scope.inventory` orders the preface first
- **THEN** validation SHALL preserve those headings' original global positions
- **AND** validation SHALL fail with `source-mismatch` rather than normalizing passage kinds into the expected order

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

- **WHEN** an edition has empty or malformed provenance, a snapshot inventory is incomplete or malformed, or a referenced figure is absent or has a different digest
- **THEN** validation SHALL fail with `invalid-source`, `source-mismatch`, `broken-path`, or `digest-mismatch`

#### Scenario: Rich-text field references an offline image

- **WHEN** any renderer-recognized rich-text field contains a Markdown image reference, including an `images/` path with spaces
- **THEN** validation SHALL resolve the same reference grammar used by rendering
- **AND** validation SHALL fail with `broken-path` or `digest-mismatch` when the asset is missing, escapes `source-assets/`, is not listed, or has different bytes

### Requirement: Every aligned segment SHALL contain separate Traditional Chinese translation and interpretation

Every segment SHALL contain non-empty `translation_zh_tw` and `interpretation_zh_tw` values, and each value SHALL contain at least one assigned Unicode Han ideograph. Unified ideographs, U+3007, Unicode 17 Extension J, and assigned compatibility ideographs SHALL satisfy this structural floor; unassigned scalars in an ideograph block SHALL NOT. The translation SHALL be a project-authored working translation based primarily on German and checked against licensed inline translations. The interpretation SHALL explain the philosophical claim, terminology, ambiguity, or limit and SHALL NOT be substituted by the translation. Corpus-construction boilerplate that merely quotes a clause and says it starts, advances, or concludes the proposition SHALL NOT count as interpretation. Placeholder markers SHALL be detected as tokens even when decorated with a proposition number or punctuation, such as the four-letter marker formed by `T`, `O`, `D`, and `O`, or the three-letter marker formed by `T`, `B`, and `D`, followed by `：2.01`.

#### Scenario: Translation and interpretation are present

- **WHEN** a segment has distinct non-placeholder values containing Han-script content for both Chinese fields
- **THEN** the segment SHALL pass the Chinese-content check

##### Example: Proposition 1 keeps translation and reading separate

- **GIVEN** `translation_zh_tw` is `世界是一切發生之事。`
- **AND** `interpretation_zh_tw` explains that the opening defines the world through facts rather than a mere collection of things
- **WHEN** strict validation checks proposition `1`
- **THEN** both fields SHALL be accepted as distinct, substantive content

#### Scenario: Missing or placeholder content is rejected

- **WHEN** either Chinese field is empty or contains `<unfinished>`, `<unreviewed>`, or another configured placeholder marker
- **THEN** strict validation SHALL fail with `missing-translation` or `missing-interpretation`

#### Scenario: Non-Chinese filler is rejected

- **WHEN** a non-empty Chinese field contains no Unicode Han-script scalar
- **THEN** strict validation SHALL fail with `missing-translation` or `missing-interpretation` according to the field
- **AND** distinct English prose SHALL NOT satisfy the Chinese-content contract

#### Scenario: Assigned and unassigned ideograph scalars are distinguished

- **WHEN** a Chinese field contains a Unicode 17 Extension J or assigned compatibility ideograph
- **THEN** that scalar SHALL satisfy the Han-content structural floor
- **AND** a scalar from an unassigned compatibility-block gap SHALL NOT satisfy it

#### Scenario: Construction boilerplate replaces sentence-level interpretation

- **WHEN** an interpretation merely wraps a translated clause in stock text such as starting, advancing, or concluding the proposition
- **THEN** strict validation SHALL fail with `generic-interpretation`
- **AND** the editor SHALL replace it with a direct explanation of that sentence's philosophical role, terminology, ambiguity, or limit

### Requirement: Current evidence and historical context SHALL remain separate

Project relations SHALL describe the current `main` state and SHALL cite current evidence with project-root-relative paths plus stable symbols, requirement names, test names, or document headings. Historical branch, commit, and issue references SHALL live under `history` and SHALL declare `retained`, `revised`, or `rejected`. Commit history references SHALL resolve to a commit in the local Git object database without a network request. Branch history references SHALL identify a resolvable local branch under `refs/heads/` or remote-tracking branch under `refs/remotes/`; a SHA, tag, `HEAD`, other ref namespace, or unresolved branch SHALL fail with `unknown-branch`. A generated document SHALL NOT serve as load-bearing current evidence. The evidence `kind` SHALL be structural: headings must resolve as exact Markdown heading lines, tests as named test function declarations under `Tests/`, requirements as exact complete `### Requirement:` names under `openspec/`, and symbols as Swift declaration identifiers. Swift comments and string literal contents SHALL be excluded before symbol or test declaration matching, so a locator present only as prose cannot satisfy evidence. Canonical corpus and source snapshots SHALL NOT cite themselves as current implementation evidence. Paths SHALL be standardized before these policy checks so `./`, `..`, or symlink spelling cannot bypass them.

#### Scenario: Current source evidence resolves locally

- **WHEN** evidence names an existing project file and a symbol declared in that file
- **THEN** evidence validation SHALL succeed without network access

##### Example: A Swift symbol is verified structurally

- **GIVEN** evidence kind `symbol` names `Sources/AkashicStoreIO/LibraryStore.swift` and the Swift declaration identifier `LibraryStore`
- **WHEN** evidence validation runs from the repository root
- **THEN** it SHALL locate that declaration in the named file without a network request

#### Scenario: Broken current or historical reference is surfaced

- **WHEN** a current path or symbol is absent, or a history commit or branch cannot be resolved by Git
- **THEN** validation SHALL fail with `broken-path`, `missing-symbol`, `unknown-commit`, or `unknown-branch`

#### Scenario: Existing local branch history resolves

- **WHEN** a branch history reference resolves to a commit through the local Git object database
- **THEN** evidence validation SHALL accept the reference without fetching a remote
- **AND** validation SHALL NOT require the branch commit to be an ancestor of `main`

#### Scenario: Commit-ish value cannot masquerade as branch history

- **WHEN** history kind `branch` names a SHA, tag, `HEAD`, or a ref outside `refs/heads/` and `refs/remotes/`
- **THEN** validation SHALL fail with `unknown-branch`
- **AND** a value peelable to a commit SHALL NOT be sufficient unless it is a true branch ref

#### Scenario: Locator kind is only a coincidental substring

- **WHEN** a locator exists in a file but does not match its declared heading, test declaration, complete requirement name, or Swift declaration structure
- **THEN** validation SHALL fail with `invalid-evidence`

#### Scenario: Comment or string imitates a Swift declaration

- **WHEN** a symbol or test locator appears only inside a Swift line comment, nested block comment, ordinary string, multiline string, or raw string
- **THEN** validation SHALL fail with `invalid-evidence`
- **AND** no prose occurrence SHALL be accepted as structural evidence
