# tractatus-project-map Specification

## Purpose

定義一套可機械驗證且可追溯來源的《邏輯哲學論》逐句正典，完整保存多版本對齊、臺灣正體中文工作譯文與哲學解讀，並以可解析的現況證據誠實記錄每個命題和 Akashic-Library 的關係。此規格同時約束離線來源權利、決定性並排文件產生與持續整合閘門，避免哲學宣稱超過專案實作。

## Requirements

### Requirement: The corpus SHALL declare an exact authorial scope

The canonical corpus SHALL include exactly eight Wittgenstein preface paragraphs and all 526 numbered propositions from 1 through 7. Validation SHALL compare the ordered manifest inventory with a fixed canonical fingerprint rather than trusting a self-declared shortened inventory. The dedication and motto SHALL be retained only as source metadata and SHALL match the pinned authorial wording exactly. Russell's introduction and the index SHALL NOT appear as interpreted corpus records.

#### Scenario: Scope inventory is complete

- **WHEN** strict validation reads the source manifest and every corpus volume
- **THEN** the set of corpus record IDs SHALL equal the manifest inventory for the preface and propositions 1 through 7
- **AND** no record from Russell's introduction or the index SHALL be accepted

#### Scenario: A numbered proposition is omitted

- **WHEN** a proposition ID present in the manifest inventory is absent from all corpus volumes
- **THEN** validation SHALL fail with `missing-proposition`


<!-- @trace
source: add-tractatus-project-map
updated: 2026-08-09
code:
  - docs/tractatus/source-assets/images/531064e7807699e5544919383c09e44c0041e20bae70ec24417d5cc8e39fc4d6.svg
  - docs/tractatus/source-assets/images/6f5736dff9d73c6c95c36f30466ceb36b6191d4b51adec9af05bd29016ef01ea.svg
  - docs/tractatus/source-assets/images/200px-TLP_6.1203e.png
  - Sources/TractatusDocs/Corpus.swift
  - docs/tractatus/source-snapshots/en-ogden-ramsey-1922-wittgenstein-project.md
  - Sources/TractatusDocs/DocumentService.swift
  - docs/tractatus/source-assets/images/2363c84eb861521de9141a1ef7e7f9b8e30ee559dbe0fdd98ebe96665b1cacc5.svg
  - docs/tractatus/source-assets/images/250px-TLP_6.1203d.png
  - docs/tractatus/source-assets/images/9a45f5fb107652caa2fff811b19eeb0547bb7389fade741c2bd6e8b866f47858.svg
  - docs/tractatus/generated/tractatus-project-map.md
  - docs/tractatus/source-assets/images/79fe9d279c0691bdeef7a6bf88e5f6a6364bd5b2dabfd79444199d7e0fb31ca7.svg
  - docs/tractatus/source-assets/images/250px-TLP_6.1203a.png
  - .vscode/launch.json
  - docs/tractatus/corpus/6.yaml
  - docs/tractatus/source-assets/images/2f81698ca04ab3ce262aa94e5d57f69a5eaa2cadf033aba83d9dc9724869a8b0.svg
  - docs/tractatus/source-assets/images/ddf71a60f25ff0e495d94d2bd39bcde1e3e20286201c7de357bfe8b3b1575a1a.svg
  - Tests/TractatusDocsTests/CorpusSourceFidelityTests.swift
  - docs/tractatus/corpus/2.yaml
  - docs/tractatus/source-assets/images/fe681449dc8d64199e5d1bdbf8208df658a75a9e18932d30c9dfe7f01673531e.svg
  - docs/tractatus/source-snapshots/de-wittgenstein-project.md
  - Tests/TractatusDocsTests/Fixtures/rendering-expected.md
  - docs/tractatus/source-assets/images/8972055d3850ecff6e47e1516fc07474dfcc4bf7f0095ed9bcf5389c004a6d07.svg
  - docs/tractatus/source-assets/images/cbe2c1a200eb49c3a9b16c7105afbb9fbed122da767f2d37389ac28a9e93e102.svg
  - .github/workflows/ci.yml
  - docs/tractatus/corpus/preface.yaml
  - Package.swift
  - Sources/tractatus-doc/main.swift
  - docs/tractatus/corpus/3.yaml
  - docs/tractatus/source-assets/images/250px-TLP_5.5423.png
  - docs/tractatus/source-assets/images/2bdad2e773a893d516dedb66aae27db7901736d7838298078d42775abc368450.svg
  - docs/tractatus/source-assets/images/b62025c4a407e7eb826ef60301c7aba855768d91af1e7b6d3248a9d8c43658f1.svg
  - Sources/TractatusDocs/SourceManifest.swift
  - docs/tractatus/source-assets/images/1bd88ac2bf5db57ea9040cc5e72c42410c17abe58b77c117e3bfb0772eaf1d77.svg
  - docs/tractatus/source-assets/images/d61fa425857e85da7c94020ddafdf3f8038c3f33900d3f3c7e222856a8859af8.svg
  - Tests/TractatusDocsTests/TractatusInterfaceTests.swift
  - docs/tractatus/corpus/7.yaml
  - docs/tractatus/source-assets/SHA256SUMS
  - docs/tractatus/source-assets/images/356a71ba81334c39be3a91a1d42c9d51eb9ad1ea7b726f750fd3a307d7947385.svg
  - docs/tractatus/source-assets/images/ea9e48f6e881e8a034e4cbc779a077ac01d2da54238fa332cfbe2255015dca69.svg
  - docs/tractatus/corpus/4.yaml
  - docs/tractatus/source-assets/images/250px-TLP_6.1203b.png
  - docs/tractatus/source-assets/images/300px-TLP_6.1203a-en.png
  - docs/tractatus/source-assets/images/250px-TLP_6.1203e-en.png
  - Sources/TractatusDocs/Rendering.swift
  - docs/tractatus/source-assets/images/250px-TLP_5.6331.png
  - Sources/TractatusDocs/Validation.swift
  - Tests/TractatusDocsTests/SourceManifestTests.swift
  - Tests/TractatusDocsTests/TractatusDiskFixture.swift
  - docs/tractatus/source-assets/images/300px-TLP_6.1203d-en.png
  - docs/tractatus/README.md
  - docs/tractatus/source-assets/images/6dfd74305dc6480d900085f169502024845a873e4e905856bf37dbc80f3bb653.svg
  - docs/tractatus/source-assets/images/b3394a04eba3cf3b36ede15e974e646aa098169220c2c60478507502e024c872.svg
  - docs/tractatus/corpus/5.yaml
  - docs/tractatus/source-assets/images/250px-TLP_6.1203c-en.png
  - docs/tractatus/source-assets/images/336cae8a41089348ef601ba5dbe893d3758f7baa1841701bd587566e0f16d282.svg
  - docs/tractatus/sources.yaml
  - docs/tractatus/source-assets/images/2c3e0efa8931e01e650511958fc1f6d5b5cba8c4120db825866394563d645203.svg
  - docs/tractatus/source-assets/images/109747f0cdbcfd62f1bce67d93eb51350f5f3835c6459539f96d2dc70d84420f.svg
  - docs/tractatus/source-assets/images/300px-TLP_6.1203b-en.png
  - docs/tractatus/source-assets/images/330px-TLP_6.36111.png
  - Tests/TractatusDocsTests/RenderingTests.swift
  - Tests/TractatusDocsTests/TractatusValidationCLITests.swift
  - docs/tractatus/source-assets/images/d1cf195aa1fb631bffe7b018f1114530b8c1bcc712299ba306fdef8ed6c55335.svg
  - docs/tractatus/source-assets/images/9bfe93c20fc75f7848141a5dc2cdd0308e48f56967903cda5e95d9574182253c.svg
  - docs/tractatus/corpus/1.yaml
  - Tests/TractatusDocsTests/CorpusValidationTests.swift
  - docs/tractatus/source-assets/images/120px-TLP_6.1203c.png
  - docs/tractatus/source-assets/images/22c545a9a90d2f7b95fb0636e2d79882d0cd328a78afb1e7c723da5b44a774bf.svg
  - docs/tractatus/source-assets/images/eb37987510f581cb73f8db614bd71715f510cf605279d48188050d8b509b47ed.svg
  - docs/tractatus/source-assets/images/e5973c9367aeacc00f2830f165ecedfaa5664ca53875c29edf6be4ddffb89c18.svg
  - docs/tractatus/source-assets/images/250px-TLP_5.6331en.png
  - docs/tractatus/source-assets/images/3b27b08186c4d2531ace97a6a386ca76d9996f0b7f4701697fb39daebd242145.svg
-->

---
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


<!-- @trace
source: close-tractatus-validation-audit-gaps
updated: 2026-08-09
code:
  - docs/tractatus/source-assets/images/9a45f5fb107652caa2fff811b19eeb0547bb7389fade741c2bd6e8b866f47858.svg
  - Tests/TractatusDocsTests/TractatusDiskFixture.swift
  - Tests/TractatusDocsTests/CorpusSourceFidelityTests.swift
  - docs/tractatus/source-assets/images/356a71ba81334c39be3a91a1d42c9d51eb9ad1ea7b726f750fd3a307d7947385.svg
  - docs/tractatus/corpus/7.yaml
  - docs/tractatus/source-assets/images/d1cf195aa1fb631bffe7b018f1114530b8c1bcc712299ba306fdef8ed6c55335.svg
  - docs/tractatus/corpus/6.yaml
  - docs/tractatus/source-assets/images/250px-TLP_5.6331.png
  - docs/tractatus/source-assets/images/3b27b08186c4d2531ace97a6a386ca76d9996f0b7f4701697fb39daebd242145.svg
  - Sources/TractatusDocs/Rendering.swift
  - docs/tractatus/source-assets/images/250px-TLP_5.6331en.png
  - Tests/TractatusDocsTests/SourceManifestTests.swift
  - Tests/TractatusDocsTests/TractatusValidationCLITests.swift
  - docs/tractatus/corpus/4.yaml
  - docs/tractatus/source-assets/images/250px-TLP_5.5423.png
  - docs/tractatus/source-assets/images/b62025c4a407e7eb826ef60301c7aba855768d91af1e7b6d3248a9d8c43658f1.svg
  - Tests/TractatusDocsTests/TractatusInterfaceTests.swift
  - Sources/TractatusDocs/Validation.swift
  - docs/tractatus/README.md
  - docs/tractatus/source-assets/images/109747f0cdbcfd62f1bce67d93eb51350f5f3835c6459539f96d2dc70d84420f.svg
  - docs/tractatus/source-assets/images/300px-TLP_6.1203b-en.png
  - docs/tractatus/corpus/5.yaml
  - docs/tractatus/source-assets/images/22c545a9a90d2f7b95fb0636e2d79882d0cd328a78afb1e7c723da5b44a774bf.svg
  - docs/tractatus/corpus/preface.yaml
  - docs/tractatus/source-assets/images/330px-TLP_6.36111.png
  - docs/tractatus/source-assets/images/6dfd74305dc6480d900085f169502024845a873e4e905856bf37dbc80f3bb653.svg
  - Sources/tractatus-doc/main.swift
  - Tests/TractatusDocsTests/RenderingTests.swift
  - docs/tractatus/generated/tractatus-project-map.md
  - docs/tractatus/source-assets/images/6f5736dff9d73c6c95c36f30466ceb36b6191d4b51adec9af05bd29016ef01ea.svg
  - .vscode/launch.json
  - Sources/TractatusDocs/Corpus.swift
  - docs/tractatus/source-snapshots/de-wittgenstein-project.md
  - docs/tractatus/source-assets/images/120px-TLP_6.1203c.png
  - docs/tractatus/source-assets/images/1bd88ac2bf5db57ea9040cc5e72c42410c17abe58b77c117e3bfb0772eaf1d77.svg
  - Tests/TractatusDocsTests/Fixtures/rendering-expected.md
  - docs/tractatus/source-assets/images/250px-TLP_6.1203e-en.png
  - docs/tractatus/corpus/2.yaml
  - docs/tractatus/source-assets/images/cbe2c1a200eb49c3a9b16c7105afbb9fbed122da767f2d37389ac28a9e93e102.svg
  - docs/tractatus/source-assets/images/fe681449dc8d64199e5d1bdbf8208df658a75a9e18932d30c9dfe7f01673531e.svg
  - docs/tractatus/source-assets/images/250px-TLP_6.1203c-en.png
  - docs/tractatus/source-assets/images/531064e7807699e5544919383c09e44c0041e20bae70ec24417d5cc8e39fc4d6.svg
  - docs/tractatus/source-assets/images/200px-TLP_6.1203e.png
  - docs/tractatus/source-assets/images/b3394a04eba3cf3b36ede15e974e646aa098169220c2c60478507502e024c872.svg
  - docs/tractatus/source-assets/images/2f81698ca04ab3ce262aa94e5d57f69a5eaa2cadf033aba83d9dc9724869a8b0.svg
  - docs/tractatus/source-assets/images/d61fa425857e85da7c94020ddafdf3f8038c3f33900d3f3c7e222856a8859af8.svg
  - Sources/TractatusDocs/RichText.swift
  - docs/tractatus/source-assets/images/300px-TLP_6.1203d-en.png
  - docs/tractatus/corpus/3.yaml
  - docs/tractatus/source-assets/images/2bdad2e773a893d516dedb66aae27db7901736d7838298078d42775abc368450.svg
  - docs/tractatus/source-assets/images/9bfe93c20fc75f7848141a5dc2cdd0308e48f56967903cda5e95d9574182253c.svg
  - docs/tractatus/corpus/1.yaml
  - docs/tractatus/source-assets/images/eb37987510f581cb73f8db614bd71715f510cf605279d48188050d8b509b47ed.svg
  - docs/tractatus/source-assets/images/2363c84eb861521de9141a1ef7e7f9b8e30ee559dbe0fdd98ebe96665b1cacc5.svg
  - docs/tractatus/source-snapshots/en-ogden-ramsey-1922-wittgenstein-project.md
  - docs/tractatus/source-assets/images/300px-TLP_6.1203a-en.png
  - Package.swift
  - Sources/TractatusDocs/DocumentService.swift
  - docs/tractatus/source-assets/images/2c3e0efa8931e01e650511958fc1f6d5b5cba8c4120db825866394563d645203.svg
  - .github/workflows/ci.yml
  - Sources/TractatusDocs/SourceManifest.swift
  - docs/tractatus/source-assets/images/79fe9d279c0691bdeef7a6bf88e5f6a6364bd5b2dabfd79444199d7e0fb31ca7.svg
  - docs/tractatus/source-assets/SHA256SUMS
  - docs/tractatus/sources.yaml
  - docs/tractatus/source-assets/images/e5973c9367aeacc00f2830f165ecedfaa5664ca53875c29edf6be4ddffb89c18.svg
  - docs/tractatus/source-assets/images/250px-TLP_6.1203a.png
  - docs/tractatus/source-assets/images/ddf71a60f25ff0e495d94d2bd39bcde1e3e20286201c7de357bfe8b3b1575a1a.svg
  - docs/tractatus/source-assets/images/8972055d3850ecff6e47e1516fc07474dfcc4bf7f0095ed9bcf5389c004a6d07.svg
  - docs/tractatus/source-assets/images/336cae8a41089348ef601ba5dbe893d3758f7baa1841701bd587566e0f16d282.svg
  - docs/tractatus/source-assets/images/ea9e48f6e881e8a034e4cbc779a077ac01d2da54238fa332cfbe2255015dca69.svg
  - Tests/TractatusDocsTests/CorpusValidationTests.swift
  - docs/tractatus/source-assets/images/250px-TLP_6.1203d.png
  - docs/tractatus/source-assets/images/250px-TLP_6.1203b.png
-->

---
### Requirement: Corpus records SHALL use stable hierarchical identifiers

Numbered propositions SHALL use their printed decimal numbers as IDs. Preface paragraphs SHALL use `preface.<paragraph-number>`. Aligned segments SHALL append a lowercase alphabetic suffix to their owner, such as `2.0121.a`. IDs SHALL be unique across all volumes, every non-root proposition SHALL identify an existing parent, and each YAML `volume` value SHALL equal its physical filename so exchanging two complete files cannot pass validation.

#### Scenario: Numeric proposition order is accepted

- **WHEN** a volume contains `2.1`, `2.01`, `2.011`, and `2.012` in their canonical hierarchical order
- **THEN** validation SHALL preserve that order without using ordinary lexicographic sorting

#### Scenario: Parent or duplicate ID is invalid

- **WHEN** a record repeats an existing ID or names a parent that does not exist
- **THEN** validation SHALL fail with `duplicate-id` or `missing-parent`, respectively


<!-- @trace
source: add-tractatus-project-map
updated: 2026-08-09
code:
  - docs/tractatus/source-assets/images/531064e7807699e5544919383c09e44c0041e20bae70ec24417d5cc8e39fc4d6.svg
  - docs/tractatus/source-assets/images/6f5736dff9d73c6c95c36f30466ceb36b6191d4b51adec9af05bd29016ef01ea.svg
  - docs/tractatus/source-assets/images/200px-TLP_6.1203e.png
  - Sources/TractatusDocs/Corpus.swift
  - docs/tractatus/source-snapshots/en-ogden-ramsey-1922-wittgenstein-project.md
  - Sources/TractatusDocs/DocumentService.swift
  - docs/tractatus/source-assets/images/2363c84eb861521de9141a1ef7e7f9b8e30ee559dbe0fdd98ebe96665b1cacc5.svg
  - docs/tractatus/source-assets/images/250px-TLP_6.1203d.png
  - docs/tractatus/source-assets/images/9a45f5fb107652caa2fff811b19eeb0547bb7389fade741c2bd6e8b866f47858.svg
  - docs/tractatus/generated/tractatus-project-map.md
  - docs/tractatus/source-assets/images/79fe9d279c0691bdeef7a6bf88e5f6a6364bd5b2dabfd79444199d7e0fb31ca7.svg
  - docs/tractatus/source-assets/images/250px-TLP_6.1203a.png
  - .vscode/launch.json
  - docs/tractatus/corpus/6.yaml
  - docs/tractatus/source-assets/images/2f81698ca04ab3ce262aa94e5d57f69a5eaa2cadf033aba83d9dc9724869a8b0.svg
  - docs/tractatus/source-assets/images/ddf71a60f25ff0e495d94d2bd39bcde1e3e20286201c7de357bfe8b3b1575a1a.svg
  - Tests/TractatusDocsTests/CorpusSourceFidelityTests.swift
  - docs/tractatus/corpus/2.yaml
  - docs/tractatus/source-assets/images/fe681449dc8d64199e5d1bdbf8208df658a75a9e18932d30c9dfe7f01673531e.svg
  - docs/tractatus/source-snapshots/de-wittgenstein-project.md
  - Tests/TractatusDocsTests/Fixtures/rendering-expected.md
  - docs/tractatus/source-assets/images/8972055d3850ecff6e47e1516fc07474dfcc4bf7f0095ed9bcf5389c004a6d07.svg
  - docs/tractatus/source-assets/images/cbe2c1a200eb49c3a9b16c7105afbb9fbed122da767f2d37389ac28a9e93e102.svg
  - .github/workflows/ci.yml
  - docs/tractatus/corpus/preface.yaml
  - Package.swift
  - Sources/tractatus-doc/main.swift
  - docs/tractatus/corpus/3.yaml
  - docs/tractatus/source-assets/images/250px-TLP_5.5423.png
  - docs/tractatus/source-assets/images/2bdad2e773a893d516dedb66aae27db7901736d7838298078d42775abc368450.svg
  - docs/tractatus/source-assets/images/b62025c4a407e7eb826ef60301c7aba855768d91af1e7b6d3248a9d8c43658f1.svg
  - Sources/TractatusDocs/SourceManifest.swift
  - docs/tractatus/source-assets/images/1bd88ac2bf5db57ea9040cc5e72c42410c17abe58b77c117e3bfb0772eaf1d77.svg
  - docs/tractatus/source-assets/images/d61fa425857e85da7c94020ddafdf3f8038c3f33900d3f3c7e222856a8859af8.svg
  - Tests/TractatusDocsTests/TractatusInterfaceTests.swift
  - docs/tractatus/corpus/7.yaml
  - docs/tractatus/source-assets/SHA256SUMS
  - docs/tractatus/source-assets/images/356a71ba81334c39be3a91a1d42c9d51eb9ad1ea7b726f750fd3a307d7947385.svg
  - docs/tractatus/source-assets/images/ea9e48f6e881e8a034e4cbc779a077ac01d2da54238fa332cfbe2255015dca69.svg
  - docs/tractatus/corpus/4.yaml
  - docs/tractatus/source-assets/images/250px-TLP_6.1203b.png
  - docs/tractatus/source-assets/images/300px-TLP_6.1203a-en.png
  - docs/tractatus/source-assets/images/250px-TLP_6.1203e-en.png
  - Sources/TractatusDocs/Rendering.swift
  - docs/tractatus/source-assets/images/250px-TLP_5.6331.png
  - Sources/TractatusDocs/Validation.swift
  - Tests/TractatusDocsTests/SourceManifestTests.swift
  - Tests/TractatusDocsTests/TractatusDiskFixture.swift
  - docs/tractatus/source-assets/images/300px-TLP_6.1203d-en.png
  - docs/tractatus/README.md
  - docs/tractatus/source-assets/images/6dfd74305dc6480d900085f169502024845a873e4e905856bf37dbc80f3bb653.svg
  - docs/tractatus/source-assets/images/b3394a04eba3cf3b36ede15e974e646aa098169220c2c60478507502e024c872.svg
  - docs/tractatus/corpus/5.yaml
  - docs/tractatus/source-assets/images/250px-TLP_6.1203c-en.png
  - docs/tractatus/source-assets/images/336cae8a41089348ef601ba5dbe893d3758f7baa1841701bd587566e0f16d282.svg
  - docs/tractatus/sources.yaml
  - docs/tractatus/source-assets/images/2c3e0efa8931e01e650511958fc1f6d5b5cba8c4120db825866394563d645203.svg
  - docs/tractatus/source-assets/images/109747f0cdbcfd62f1bce67d93eb51350f5f3835c6459539f96d2dc70d84420f.svg
  - docs/tractatus/source-assets/images/300px-TLP_6.1203b-en.png
  - docs/tractatus/source-assets/images/330px-TLP_6.36111.png
  - Tests/TractatusDocsTests/RenderingTests.swift
  - Tests/TractatusDocsTests/TractatusValidationCLITests.swift
  - docs/tractatus/source-assets/images/d1cf195aa1fb631bffe7b018f1114530b8c1bcc712299ba306fdef8ed6c55335.svg
  - docs/tractatus/source-assets/images/9bfe93c20fc75f7848141a5dc2cdd0308e48f56967903cda5e95d9574182253c.svg
  - docs/tractatus/corpus/1.yaml
  - Tests/TractatusDocsTests/CorpusValidationTests.swift
  - docs/tractatus/source-assets/images/120px-TLP_6.1203c.png
  - docs/tractatus/source-assets/images/22c545a9a90d2f7b95fb0636e2d79882d0cd328a78afb1e7c723da5b44a774bf.svg
  - docs/tractatus/source-assets/images/eb37987510f581cb73f8db614bd71715f510cf605279d48188050d8b509b47ed.svg
  - docs/tractatus/source-assets/images/e5973c9367aeacc00f2830f165ecedfaa5664ca53875c29edf6be4ddffb89c18.svg
  - docs/tractatus/source-assets/images/250px-TLP_5.6331en.png
  - docs/tractatus/source-assets/images/3b27b08186c4d2531ace97a6a386ca76d9996f0b7f4701697fb39daebd242145.svg
-->

---
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


<!-- @trace
source: add-tractatus-project-map
updated: 2026-08-09
code:
  - docs/tractatus/source-assets/images/531064e7807699e5544919383c09e44c0041e20bae70ec24417d5cc8e39fc4d6.svg
  - docs/tractatus/source-assets/images/6f5736dff9d73c6c95c36f30466ceb36b6191d4b51adec9af05bd29016ef01ea.svg
  - docs/tractatus/source-assets/images/200px-TLP_6.1203e.png
  - Sources/TractatusDocs/Corpus.swift
  - docs/tractatus/source-snapshots/en-ogden-ramsey-1922-wittgenstein-project.md
  - Sources/TractatusDocs/DocumentService.swift
  - docs/tractatus/source-assets/images/2363c84eb861521de9141a1ef7e7f9b8e30ee559dbe0fdd98ebe96665b1cacc5.svg
  - docs/tractatus/source-assets/images/250px-TLP_6.1203d.png
  - docs/tractatus/source-assets/images/9a45f5fb107652caa2fff811b19eeb0547bb7389fade741c2bd6e8b866f47858.svg
  - docs/tractatus/generated/tractatus-project-map.md
  - docs/tractatus/source-assets/images/79fe9d279c0691bdeef7a6bf88e5f6a6364bd5b2dabfd79444199d7e0fb31ca7.svg
  - docs/tractatus/source-assets/images/250px-TLP_6.1203a.png
  - .vscode/launch.json
  - docs/tractatus/corpus/6.yaml
  - docs/tractatus/source-assets/images/2f81698ca04ab3ce262aa94e5d57f69a5eaa2cadf033aba83d9dc9724869a8b0.svg
  - docs/tractatus/source-assets/images/ddf71a60f25ff0e495d94d2bd39bcde1e3e20286201c7de357bfe8b3b1575a1a.svg
  - Tests/TractatusDocsTests/CorpusSourceFidelityTests.swift
  - docs/tractatus/corpus/2.yaml
  - docs/tractatus/source-assets/images/fe681449dc8d64199e5d1bdbf8208df658a75a9e18932d30c9dfe7f01673531e.svg
  - docs/tractatus/source-snapshots/de-wittgenstein-project.md
  - Tests/TractatusDocsTests/Fixtures/rendering-expected.md
  - docs/tractatus/source-assets/images/8972055d3850ecff6e47e1516fc07474dfcc4bf7f0095ed9bcf5389c004a6d07.svg
  - docs/tractatus/source-assets/images/cbe2c1a200eb49c3a9b16c7105afbb9fbed122da767f2d37389ac28a9e93e102.svg
  - .github/workflows/ci.yml
  - docs/tractatus/corpus/preface.yaml
  - Package.swift
  - Sources/tractatus-doc/main.swift
  - docs/tractatus/corpus/3.yaml
  - docs/tractatus/source-assets/images/250px-TLP_5.5423.png
  - docs/tractatus/source-assets/images/2bdad2e773a893d516dedb66aae27db7901736d7838298078d42775abc368450.svg
  - docs/tractatus/source-assets/images/b62025c4a407e7eb826ef60301c7aba855768d91af1e7b6d3248a9d8c43658f1.svg
  - Sources/TractatusDocs/SourceManifest.swift
  - docs/tractatus/source-assets/images/1bd88ac2bf5db57ea9040cc5e72c42410c17abe58b77c117e3bfb0772eaf1d77.svg
  - docs/tractatus/source-assets/images/d61fa425857e85da7c94020ddafdf3f8038c3f33900d3f3c7e222856a8859af8.svg
  - Tests/TractatusDocsTests/TractatusInterfaceTests.swift
  - docs/tractatus/corpus/7.yaml
  - docs/tractatus/source-assets/SHA256SUMS
  - docs/tractatus/source-assets/images/356a71ba81334c39be3a91a1d42c9d51eb9ad1ea7b726f750fd3a307d7947385.svg
  - docs/tractatus/source-assets/images/ea9e48f6e881e8a034e4cbc779a077ac01d2da54238fa332cfbe2255015dca69.svg
  - docs/tractatus/corpus/4.yaml
  - docs/tractatus/source-assets/images/250px-TLP_6.1203b.png
  - docs/tractatus/source-assets/images/300px-TLP_6.1203a-en.png
  - docs/tractatus/source-assets/images/250px-TLP_6.1203e-en.png
  - Sources/TractatusDocs/Rendering.swift
  - docs/tractatus/source-assets/images/250px-TLP_5.6331.png
  - Sources/TractatusDocs/Validation.swift
  - Tests/TractatusDocsTests/SourceManifestTests.swift
  - Tests/TractatusDocsTests/TractatusDiskFixture.swift
  - docs/tractatus/source-assets/images/300px-TLP_6.1203d-en.png
  - docs/tractatus/README.md
  - docs/tractatus/source-assets/images/6dfd74305dc6480d900085f169502024845a873e4e905856bf37dbc80f3bb653.svg
  - docs/tractatus/source-assets/images/b3394a04eba3cf3b36ede15e974e646aa098169220c2c60478507502e024c872.svg
  - docs/tractatus/corpus/5.yaml
  - docs/tractatus/source-assets/images/250px-TLP_6.1203c-en.png
  - docs/tractatus/source-assets/images/336cae8a41089348ef601ba5dbe893d3758f7baa1841701bd587566e0f16d282.svg
  - docs/tractatus/sources.yaml
  - docs/tractatus/source-assets/images/2c3e0efa8931e01e650511958fc1f6d5b5cba8c4120db825866394563d645203.svg
  - docs/tractatus/source-assets/images/109747f0cdbcfd62f1bce67d93eb51350f5f3835c6459539f96d2dc70d84420f.svg
  - docs/tractatus/source-assets/images/300px-TLP_6.1203b-en.png
  - docs/tractatus/source-assets/images/330px-TLP_6.36111.png
  - Tests/TractatusDocsTests/RenderingTests.swift
  - Tests/TractatusDocsTests/TractatusValidationCLITests.swift
  - docs/tractatus/source-assets/images/d1cf195aa1fb631bffe7b018f1114530b8c1bcc712299ba306fdef8ed6c55335.svg
  - docs/tractatus/source-assets/images/9bfe93c20fc75f7848141a5dc2cdd0308e48f56967903cda5e95d9574182253c.svg
  - docs/tractatus/corpus/1.yaml
  - Tests/TractatusDocsTests/CorpusValidationTests.swift
  - docs/tractatus/source-assets/images/120px-TLP_6.1203c.png
  - docs/tractatus/source-assets/images/22c545a9a90d2f7b95fb0636e2d79882d0cd328a78afb1e7c723da5b44a774bf.svg
  - docs/tractatus/source-assets/images/eb37987510f581cb73f8db614bd71715f510cf605279d48188050d8b509b47ed.svg
  - docs/tractatus/source-assets/images/e5973c9367aeacc00f2830f165ecedfaa5664ca53875c29edf6be4ddffb89c18.svg
  - docs/tractatus/source-assets/images/250px-TLP_5.6331en.png
  - docs/tractatus/source-assets/images/3b27b08186c4d2531ace97a6a386ca76d9996f0b7f4701697fb39daebd242145.svg
-->

---
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


<!-- @trace
source: close-tractatus-validation-audit-gaps
updated: 2026-08-09
code:
  - docs/tractatus/source-assets/images/9a45f5fb107652caa2fff811b19eeb0547bb7389fade741c2bd6e8b866f47858.svg
  - Tests/TractatusDocsTests/TractatusDiskFixture.swift
  - Tests/TractatusDocsTests/CorpusSourceFidelityTests.swift
  - docs/tractatus/source-assets/images/356a71ba81334c39be3a91a1d42c9d51eb9ad1ea7b726f750fd3a307d7947385.svg
  - docs/tractatus/corpus/7.yaml
  - docs/tractatus/source-assets/images/d1cf195aa1fb631bffe7b018f1114530b8c1bcc712299ba306fdef8ed6c55335.svg
  - docs/tractatus/corpus/6.yaml
  - docs/tractatus/source-assets/images/250px-TLP_5.6331.png
  - docs/tractatus/source-assets/images/3b27b08186c4d2531ace97a6a386ca76d9996f0b7f4701697fb39daebd242145.svg
  - Sources/TractatusDocs/Rendering.swift
  - docs/tractatus/source-assets/images/250px-TLP_5.6331en.png
  - Tests/TractatusDocsTests/SourceManifestTests.swift
  - Tests/TractatusDocsTests/TractatusValidationCLITests.swift
  - docs/tractatus/corpus/4.yaml
  - docs/tractatus/source-assets/images/250px-TLP_5.5423.png
  - docs/tractatus/source-assets/images/b62025c4a407e7eb826ef60301c7aba855768d91af1e7b6d3248a9d8c43658f1.svg
  - Tests/TractatusDocsTests/TractatusInterfaceTests.swift
  - Sources/TractatusDocs/Validation.swift
  - docs/tractatus/README.md
  - docs/tractatus/source-assets/images/109747f0cdbcfd62f1bce67d93eb51350f5f3835c6459539f96d2dc70d84420f.svg
  - docs/tractatus/source-assets/images/300px-TLP_6.1203b-en.png
  - docs/tractatus/corpus/5.yaml
  - docs/tractatus/source-assets/images/22c545a9a90d2f7b95fb0636e2d79882d0cd328a78afb1e7c723da5b44a774bf.svg
  - docs/tractatus/corpus/preface.yaml
  - docs/tractatus/source-assets/images/330px-TLP_6.36111.png
  - docs/tractatus/source-assets/images/6dfd74305dc6480d900085f169502024845a873e4e905856bf37dbc80f3bb653.svg
  - Sources/tractatus-doc/main.swift
  - Tests/TractatusDocsTests/RenderingTests.swift
  - docs/tractatus/generated/tractatus-project-map.md
  - docs/tractatus/source-assets/images/6f5736dff9d73c6c95c36f30466ceb36b6191d4b51adec9af05bd29016ef01ea.svg
  - .vscode/launch.json
  - Sources/TractatusDocs/Corpus.swift
  - docs/tractatus/source-snapshots/de-wittgenstein-project.md
  - docs/tractatus/source-assets/images/120px-TLP_6.1203c.png
  - docs/tractatus/source-assets/images/1bd88ac2bf5db57ea9040cc5e72c42410c17abe58b77c117e3bfb0772eaf1d77.svg
  - Tests/TractatusDocsTests/Fixtures/rendering-expected.md
  - docs/tractatus/source-assets/images/250px-TLP_6.1203e-en.png
  - docs/tractatus/corpus/2.yaml
  - docs/tractatus/source-assets/images/cbe2c1a200eb49c3a9b16c7105afbb9fbed122da767f2d37389ac28a9e93e102.svg
  - docs/tractatus/source-assets/images/fe681449dc8d64199e5d1bdbf8208df658a75a9e18932d30c9dfe7f01673531e.svg
  - docs/tractatus/source-assets/images/250px-TLP_6.1203c-en.png
  - docs/tractatus/source-assets/images/531064e7807699e5544919383c09e44c0041e20bae70ec24417d5cc8e39fc4d6.svg
  - docs/tractatus/source-assets/images/200px-TLP_6.1203e.png
  - docs/tractatus/source-assets/images/b3394a04eba3cf3b36ede15e974e646aa098169220c2c60478507502e024c872.svg
  - docs/tractatus/source-assets/images/2f81698ca04ab3ce262aa94e5d57f69a5eaa2cadf033aba83d9dc9724869a8b0.svg
  - docs/tractatus/source-assets/images/d61fa425857e85da7c94020ddafdf3f8038c3f33900d3f3c7e222856a8859af8.svg
  - Sources/TractatusDocs/RichText.swift
  - docs/tractatus/source-assets/images/300px-TLP_6.1203d-en.png
  - docs/tractatus/corpus/3.yaml
  - docs/tractatus/source-assets/images/2bdad2e773a893d516dedb66aae27db7901736d7838298078d42775abc368450.svg
  - docs/tractatus/source-assets/images/9bfe93c20fc75f7848141a5dc2cdd0308e48f56967903cda5e95d9574182253c.svg
  - docs/tractatus/corpus/1.yaml
  - docs/tractatus/source-assets/images/eb37987510f581cb73f8db614bd71715f510cf605279d48188050d8b509b47ed.svg
  - docs/tractatus/source-assets/images/2363c84eb861521de9141a1ef7e7f9b8e30ee559dbe0fdd98ebe96665b1cacc5.svg
  - docs/tractatus/source-snapshots/en-ogden-ramsey-1922-wittgenstein-project.md
  - docs/tractatus/source-assets/images/300px-TLP_6.1203a-en.png
  - Package.swift
  - Sources/TractatusDocs/DocumentService.swift
  - docs/tractatus/source-assets/images/2c3e0efa8931e01e650511958fc1f6d5b5cba8c4120db825866394563d645203.svg
  - .github/workflows/ci.yml
  - Sources/TractatusDocs/SourceManifest.swift
  - docs/tractatus/source-assets/images/79fe9d279c0691bdeef7a6bf88e5f6a6364bd5b2dabfd79444199d7e0fb31ca7.svg
  - docs/tractatus/source-assets/SHA256SUMS
  - docs/tractatus/sources.yaml
  - docs/tractatus/source-assets/images/e5973c9367aeacc00f2830f165ecedfaa5664ca53875c29edf6be4ddffb89c18.svg
  - docs/tractatus/source-assets/images/250px-TLP_6.1203a.png
  - docs/tractatus/source-assets/images/ddf71a60f25ff0e495d94d2bd39bcde1e3e20286201c7de357bfe8b3b1575a1a.svg
  - docs/tractatus/source-assets/images/8972055d3850ecff6e47e1516fc07474dfcc4bf7f0095ed9bcf5389c004a6d07.svg
  - docs/tractatus/source-assets/images/336cae8a41089348ef601ba5dbe893d3758f7baa1841701bd587566e0f16d282.svg
  - docs/tractatus/source-assets/images/ea9e48f6e881e8a034e4cbc779a077ac01d2da54238fa332cfbe2255015dca69.svg
  - Tests/TractatusDocsTests/CorpusValidationTests.swift
  - docs/tractatus/source-assets/images/250px-TLP_6.1203d.png
  - docs/tractatus/source-assets/images/250px-TLP_6.1203b.png
-->

---
### Requirement: Every proposition SHALL state at least one explicit project relation

Every proposition SHALL contain at least one project relation. Its status SHALL be one of implemented, partial, aspirational, analogy_only, rejected, not_applicable, or intentional_nonconformance. Its mode, when applicable, SHALL be one of instance, structural_invariant, semantic_operation, formal_derivation, refusal, shown_constraint, meta_elucidation, or declared_nonconformance. Every relation SHALL contain a Traditional Chinese claim and rationale.
Each rationale SHALL be proposition-specific: after whitespace normalization, a rationale SHALL NOT be reused by a different proposition.
Every aspirational relation SHALL be backed by at least one proposition history item whose kind is issue and whose reference is a complete GitHub issue URL of the exact path form `https://github.com/{owner}/{repo}/issues/{positive-integer}`. Extra path components, issue number zero, and negative issue numbers SHALL be rejected. The same issue SHALL be reusable only for relations that identify the same concrete engineering gap. Offline validation SHALL verify this structural trace without querying GitHub.

#### Scenario: Honest absence of a project mapping

- **WHEN** a proposition has no defensible Akashic counterpart
- **THEN** it SHALL use status not_applicable
- **AND** its rationale SHALL state why forcing an analogy would be misleading

##### Example: No engineering counterpart

- **GIVEN** a proposition whose subject is outside a software library's representational boundary
- **WHEN** no direct invariant, operation, refusal, or declared nonconformance exists
- **THEN** its relation SHALL use status `not_applicable` with a proposition-specific reason

#### Scenario: Invalid or incomplete relation is rejected

- **WHEN** a proposition has no relation, an unknown enum value, an empty claim, or an empty rationale
- **THEN** validation SHALL fail with invalid-relation

##### Example: Empty rationale

- **GIVEN** record `6.5` has one relation whose rationale is empty
- **WHEN** strict validation runs
- **THEN** it SHALL report `6.5:invalid-relation`

#### Scenario: A generic relation rationale is reused across propositions

- **WHEN** two different proposition records contain the same rationale after whitespace normalization
- **THEN** validation SHALL fail with duplicate-rationale
- **AND** the diagnostic SHALL direct the editor to explain each proposition's concrete philosophical content

##### Example: Reused explanation

- **GIVEN** records `5` and `5.1` contain the same whitespace-normalized rationale
- **WHEN** strict validation runs
- **THEN** both affected records SHALL be reported with `duplicate-rationale`

#### Scenario: An aspirational relation has no issue trace

- **WHEN** an aspirational relation has no history item containing a complete GitHub issue URL
- **THEN** validation SHALL fail with invalid-relation
- **AND** the diagnostic SHALL identify the affected proposition and require an issue history reference
- **AND** URL paths with extra components, issue number zero, or a negative issue number SHALL be treated as incomplete

##### Example: Untracked truth-function aspiration

- **GIVEN** record `5.101` has status `aspirational` and an empty history array
- **WHEN** strict validation runs
- **THEN** it SHALL report `5.101:invalid-relation` and require a GitHub issue history reference

#### Scenario: Related aspirations share a precise issue

- **WHEN** two or more aspirational relations describe the same concrete engineering gap
- **THEN** each relation SHALL retain proposition-specific claim and rationale text
- **AND** each containing proposition SHALL reference that gap's complete GitHub issue URL in history

##### Example: One precise issue traces a proposition family

- **GIVEN** records `5.1` and `5.101` both require truth-functional composition
- **WHEN** each record keeps distinct claim and rationale text
- **THEN** both histories SHALL be allowed to reference `https://github.com/PsychQuant/Akashic-Library/issues/204`


<!-- @trace
source: integrate-akashic-proposition-tractatus-map
updated: 2026-08-09
code:
  - Sources/TractatusDocs/DocumentService.swift
  - docs/tractatus/source-snapshots/de-wittgenstein-project.md
  - Sources/tractatus-doc/main.swift
  - Tests/AkashicPropositionTests/PropositionTests.swift
  - Tests/TractatusDocsTests/CorpusSourceFidelityTests.swift
  - Tests/TractatusDocsTests/SourceManifestTests.swift
  - docs/tractatus/source-assets/images/250px-TLP_6.1203b.png
  - Sources/AkashicProposition/Projection.swift
  - Tests/TractatusDocsTests/TractatusDiskFixture.swift
  - Sources/TractatusDocs/Corpus.swift
  - docs/tractatus/corpus/7.yaml
  - Tests/TractatusDocsTests/TractatusInterfaceTests.swift
  - docs/tractatus/source-assets/images/6dfd74305dc6480d900085f169502024845a873e4e905856bf37dbc80f3bb653.svg
  - docs/tractatus/source-assets/images/2bdad2e773a893d516dedb66aae27db7901736d7838298078d42775abc368450.svg
  - docs/tractatus/source-assets/images/2c3e0efa8931e01e650511958fc1f6d5b5cba8c4120db825866394563d645203.svg
  - Tests/TractatusDocsTests/RenderingTests.swift
  - docs/tractatus/source-assets/images/9bfe93c20fc75f7848141a5dc2cdd0308e48f56967903cda5e95d9574182253c.svg
  - docs/tractatus/corpus/4.yaml
  - docs/tractatus/corpus/preface.yaml
  - Package.swift
  - docs/tractatus/source-assets/images/109747f0cdbcfd62f1bce67d93eb51350f5f3835c6459539f96d2dc70d84420f.svg
  - docs/tractatus/source-assets/images/250px-TLP_6.1203e-en.png
  - Tests/TractatusDocsTests/CorpusValidationTests.swift
  - Sources/TractatusDocs/SourceManifest.swift
  - docs/tractatus/source-assets/images/9a45f5fb107652caa2fff811b19eeb0547bb7389fade741c2bd6e8b866f47858.svg
  - docs/tractatus/source-assets/images/fe681449dc8d64199e5d1bdbf8208df658a75a9e18932d30c9dfe7f01673531e.svg
  - docs/tractatus/corpus/1.yaml
  - docs/tractatus/source-assets/images/200px-TLP_6.1203e.png
  - docs/tractatus/source-assets/images/300px-TLP_6.1203a-en.png
  - .vscode/launch.json
  - docs/tractatus/sources.yaml
  - .github/workflows/ci.yml
  - docs/tractatus/source-assets/images/250px-TLP_5.6331.png
  - docs/tractatus/source-assets/images/3b27b08186c4d2531ace97a6a386ca76d9996f0b7f4701697fb39daebd242145.svg
  - docs/tractatus/source-snapshots/en-ogden-ramsey-1922-wittgenstein-project.md
  - docs/tractatus/source-assets/images/1bd88ac2bf5db57ea9040cc5e72c42410c17abe58b77c117e3bfb0772eaf1d77.svg
  - Sources/TractatusDocs/Rendering.swift
  - docs/tractatus/source-assets/images/2363c84eb861521de9141a1ef7e7f9b8e30ee559dbe0fdd98ebe96665b1cacc5.svg
  - docs/tractatus/source-assets/images/6f5736dff9d73c6c95c36f30466ceb36b6191d4b51adec9af05bd29016ef01ea.svg
  - docs/tractatus/generated/tractatus-project-map.md
  - docs/tractatus/source-assets/images/120px-TLP_6.1203c.png
  - docs/tractatus/source-assets/images/ea9e48f6e881e8a034e4cbc779a077ac01d2da54238fa332cfbe2255015dca69.svg
  - docs/tractatus/source-assets/images/d61fa425857e85da7c94020ddafdf3f8038c3f33900d3f3c7e222856a8859af8.svg
  - Sources/AkashicProposition/Question.swift
  - Tests/TractatusDocsTests/Fixtures/rendering-expected.md
  - Tests/TractatusDocsTests/TractatusValidationCLITests.swift
  - docs/tractatus/source-assets/images/8972055d3850ecff6e47e1516fc07474dfcc4bf7f0095ed9bcf5389c004a6d07.svg
  - docs/tractatus/corpus/6.yaml
  - docs/tractatus/source-assets/images/250px-TLP_6.1203a.png
  - docs/tractatus/source-assets/images/250px-TLP_6.1203d.png
  - Sources/TractatusDocs/RichText.swift
  - Sources/TractatusDocs/Validation.swift
  - docs/tractatus/README.md
  - docs/tractatus/source-assets/images/250px-TLP_6.1203c-en.png
  - docs/tractatus/source-assets/images/330px-TLP_6.36111.png
  - docs/tractatus/corpus/5.yaml
  - docs/tractatus/source-assets/images/300px-TLP_6.1203b-en.png
  - docs/tractatus/source-assets/images/356a71ba81334c39be3a91a1d42c9d51eb9ad1ea7b726f750fd3a307d7947385.svg
  - docs/tractatus/source-assets/images/22c545a9a90d2f7b95fb0636e2d79882d0cd328a78afb1e7c723da5b44a774bf.svg
  - docs/tractatus/source-assets/images/531064e7807699e5544919383c09e44c0041e20bae70ec24417d5cc8e39fc4d6.svg
  - docs/tractatus/source-assets/images/79fe9d279c0691bdeef7a6bf88e5f6a6364bd5b2dabfd79444199d7e0fb31ca7.svg
  - docs/tractatus/source-assets/images/cbe2c1a200eb49c3a9b16c7105afbb9fbed122da767f2d37389ac28a9e93e102.svg
  - docs/tractatus/source-assets/images/e5973c9367aeacc00f2830f165ecedfaa5664ca53875c29edf6be4ddffb89c18.svg
  - docs/tractatus/corpus/2.yaml
  - docs/tractatus/source-assets/images/250px-TLP_5.5423.png
  - docs/tractatus/corpus/3.yaml
  - docs/tractatus/source-assets/images/250px-TLP_5.6331en.png
  - docs/tractatus/source-assets/images/300px-TLP_6.1203d-en.png
  - docs/tractatus/source-assets/images/b62025c4a407e7eb826ef60301c7aba855768d91af1e7b6d3248a9d8c43658f1.svg
  - docs/tractatus/source-assets/images/2f81698ca04ab3ce262aa94e5d57f69a5eaa2cadf033aba83d9dc9724869a8b0.svg
  - docs/tractatus/source-assets/images/d1cf195aa1fb631bffe7b018f1114530b8c1bcc712299ba306fdef8ed6c55335.svg
  - docs/tractatus/source-assets/SHA256SUMS
  - docs/tractatus/source-assets/images/ddf71a60f25ff0e495d94d2bd39bcde1e3e20286201c7de357bfe8b3b1575a1a.svg
  - Sources/AkashicProposition/Proposition.swift
  - docs/tractatus/source-assets/images/eb37987510f581cb73f8db614bd71715f510cf605279d48188050d8b509b47ed.svg
  - docs/tractatus/source-assets/images/336cae8a41089348ef601ba5dbe893d3758f7baa1841701bd587566e0f16d282.svg
  - docs/tractatus/source-assets/images/b3394a04eba3cf3b36ede15e974e646aa098169220c2c60478507502e024c872.svg
-->

---
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


<!-- @trace
source: close-tractatus-validation-audit-gaps
updated: 2026-08-09
code:
  - docs/tractatus/source-assets/images/9a45f5fb107652caa2fff811b19eeb0547bb7389fade741c2bd6e8b866f47858.svg
  - Tests/TractatusDocsTests/TractatusDiskFixture.swift
  - Tests/TractatusDocsTests/CorpusSourceFidelityTests.swift
  - docs/tractatus/source-assets/images/356a71ba81334c39be3a91a1d42c9d51eb9ad1ea7b726f750fd3a307d7947385.svg
  - docs/tractatus/corpus/7.yaml
  - docs/tractatus/source-assets/images/d1cf195aa1fb631bffe7b018f1114530b8c1bcc712299ba306fdef8ed6c55335.svg
  - docs/tractatus/corpus/6.yaml
  - docs/tractatus/source-assets/images/250px-TLP_5.6331.png
  - docs/tractatus/source-assets/images/3b27b08186c4d2531ace97a6a386ca76d9996f0b7f4701697fb39daebd242145.svg
  - Sources/TractatusDocs/Rendering.swift
  - docs/tractatus/source-assets/images/250px-TLP_5.6331en.png
  - Tests/TractatusDocsTests/SourceManifestTests.swift
  - Tests/TractatusDocsTests/TractatusValidationCLITests.swift
  - docs/tractatus/corpus/4.yaml
  - docs/tractatus/source-assets/images/250px-TLP_5.5423.png
  - docs/tractatus/source-assets/images/b62025c4a407e7eb826ef60301c7aba855768d91af1e7b6d3248a9d8c43658f1.svg
  - Tests/TractatusDocsTests/TractatusInterfaceTests.swift
  - Sources/TractatusDocs/Validation.swift
  - docs/tractatus/README.md
  - docs/tractatus/source-assets/images/109747f0cdbcfd62f1bce67d93eb51350f5f3835c6459539f96d2dc70d84420f.svg
  - docs/tractatus/source-assets/images/300px-TLP_6.1203b-en.png
  - docs/tractatus/corpus/5.yaml
  - docs/tractatus/source-assets/images/22c545a9a90d2f7b95fb0636e2d79882d0cd328a78afb1e7c723da5b44a774bf.svg
  - docs/tractatus/corpus/preface.yaml
  - docs/tractatus/source-assets/images/330px-TLP_6.36111.png
  - docs/tractatus/source-assets/images/6dfd74305dc6480d900085f169502024845a873e4e905856bf37dbc80f3bb653.svg
  - Sources/tractatus-doc/main.swift
  - Tests/TractatusDocsTests/RenderingTests.swift
  - docs/tractatus/generated/tractatus-project-map.md
  - docs/tractatus/source-assets/images/6f5736dff9d73c6c95c36f30466ceb36b6191d4b51adec9af05bd29016ef01ea.svg
  - .vscode/launch.json
  - Sources/TractatusDocs/Corpus.swift
  - docs/tractatus/source-snapshots/de-wittgenstein-project.md
  - docs/tractatus/source-assets/images/120px-TLP_6.1203c.png
  - docs/tractatus/source-assets/images/1bd88ac2bf5db57ea9040cc5e72c42410c17abe58b77c117e3bfb0772eaf1d77.svg
  - Tests/TractatusDocsTests/Fixtures/rendering-expected.md
  - docs/tractatus/source-assets/images/250px-TLP_6.1203e-en.png
  - docs/tractatus/corpus/2.yaml
  - docs/tractatus/source-assets/images/cbe2c1a200eb49c3a9b16c7105afbb9fbed122da767f2d37389ac28a9e93e102.svg
  - docs/tractatus/source-assets/images/fe681449dc8d64199e5d1bdbf8208df658a75a9e18932d30c9dfe7f01673531e.svg
  - docs/tractatus/source-assets/images/250px-TLP_6.1203c-en.png
  - docs/tractatus/source-assets/images/531064e7807699e5544919383c09e44c0041e20bae70ec24417d5cc8e39fc4d6.svg
  - docs/tractatus/source-assets/images/200px-TLP_6.1203e.png
  - docs/tractatus/source-assets/images/b3394a04eba3cf3b36ede15e974e646aa098169220c2c60478507502e024c872.svg
  - docs/tractatus/source-assets/images/2f81698ca04ab3ce262aa94e5d57f69a5eaa2cadf033aba83d9dc9724869a8b0.svg
  - docs/tractatus/source-assets/images/d61fa425857e85da7c94020ddafdf3f8038c3f33900d3f3c7e222856a8859af8.svg
  - Sources/TractatusDocs/RichText.swift
  - docs/tractatus/source-assets/images/300px-TLP_6.1203d-en.png
  - docs/tractatus/corpus/3.yaml
  - docs/tractatus/source-assets/images/2bdad2e773a893d516dedb66aae27db7901736d7838298078d42775abc368450.svg
  - docs/tractatus/source-assets/images/9bfe93c20fc75f7848141a5dc2cdd0308e48f56967903cda5e95d9574182253c.svg
  - docs/tractatus/corpus/1.yaml
  - docs/tractatus/source-assets/images/eb37987510f581cb73f8db614bd71715f510cf605279d48188050d8b509b47ed.svg
  - docs/tractatus/source-assets/images/2363c84eb861521de9141a1ef7e7f9b8e30ee559dbe0fdd98ebe96665b1cacc5.svg
  - docs/tractatus/source-snapshots/en-ogden-ramsey-1922-wittgenstein-project.md
  - docs/tractatus/source-assets/images/300px-TLP_6.1203a-en.png
  - Package.swift
  - Sources/TractatusDocs/DocumentService.swift
  - docs/tractatus/source-assets/images/2c3e0efa8931e01e650511958fc1f6d5b5cba8c4120db825866394563d645203.svg
  - .github/workflows/ci.yml
  - Sources/TractatusDocs/SourceManifest.swift
  - docs/tractatus/source-assets/images/79fe9d279c0691bdeef7a6bf88e5f6a6364bd5b2dabfd79444199d7e0fb31ca7.svg
  - docs/tractatus/source-assets/SHA256SUMS
  - docs/tractatus/sources.yaml
  - docs/tractatus/source-assets/images/e5973c9367aeacc00f2830f165ecedfaa5664ca53875c29edf6be4ddffb89c18.svg
  - docs/tractatus/source-assets/images/250px-TLP_6.1203a.png
  - docs/tractatus/source-assets/images/ddf71a60f25ff0e495d94d2bd39bcde1e3e20286201c7de357bfe8b3b1575a1a.svg
  - docs/tractatus/source-assets/images/8972055d3850ecff6e47e1516fc07474dfcc4bf7f0095ed9bcf5389c004a6d07.svg
  - docs/tractatus/source-assets/images/336cae8a41089348ef601ba5dbe893d3758f7baa1841701bd587566e0f16d282.svg
  - docs/tractatus/source-assets/images/ea9e48f6e881e8a034e4cbc779a077ac01d2da54238fa332cfbe2255015dca69.svg
  - Tests/TractatusDocsTests/CorpusValidationTests.swift
  - docs/tractatus/source-assets/images/250px-TLP_6.1203d.png
  - docs/tractatus/source-assets/images/250px-TLP_6.1203b.png
-->

---
### Requirement: Validation SHALL be strict, deterministic, and actionable

The `tractatus-doc validate` command SHALL perform schema, cross-volume, alignment, Chinese-content, relation, evidence, source-digest, image-digest, and license checks. Unknown YAML keys SHALL be rejected. Before YAML composition, every canonical volume SHALL be limited to 1 MiB of UTF-8 and SHALL pass the shared alias-event expansion budget. The source manifest SHALL be limited to 256 KiB of UTF-8, at most sixteen editions, and SHALL pass the same alias-event expansion budget. The corpus directory SHALL accept at most eight canonical YAML files and sixty-four total direct entries, including hidden entries; each volume SHALL contain at most 256 propositions, each proposition at most eight project relations and thirty-two history references, and each relation at most thirty-two current-evidence items. A validation run SHALL process at most 1,024 current-evidence items and 512 history references, SHALL read at most 4 MiB from any current-evidence file, SHALL capture at most 2 MiB from each inline source snapshot, SHALL read at most 256 KiB from the asset checksum manifest, SHALL read at most 8 MiB from a referenced asset, and SHALL capture at most 64 MiB across unique canonical referenced-asset paths. Each canonical inline snapshot or referenced-asset path SHALL be captured at most once, and accepted snapshot bytes SHALL be reused for both digest and corpus-fidelity validation. Exceeding any fixed limit SHALL fail closed with a `resource-limit` diagnostic before unbounded composition, locator, digest, or Git-history work. Swift lexical views SHALL be cached once per evidence file. Errors SHALL use `path:record-id:error-code: message`, SHALL use project-relative paths, and SHALL be sorted by path, record ID, and error code before output. Every diagnostic field SHALL escape control characters, bidirectional text controls, backslashes, and field separators so untrusted YAML values cannot forge terminal output. Construction gaps SHALL be sorted independently and rendered as `incomplete: KIND VALUE` before diagnostics, including when diagnostics make the command fail. Any error SHALL produce a non-zero exit status.

#### Scenario: Alias-expanded evidence cannot amplify validation work without bound

- **GIVEN** a syntactically valid corpus relation uses YAML aliases to expand beyond thirty-two current-evidence items
- **WHEN** the canonical volume is decoded
- **THEN** validation SHALL fail with `resource-limit`
- **AND** no locator or Git-history subprocess SHALL run for the rejected payload

#### Scenario: Oversized canonical volume is rejected before composition

- **GIVEN** a canonical volume contains more than 1 MiB of UTF-8
- **WHEN** validation reads the volume
- **THEN** it SHALL read no more than the fixed limit plus one sentinel byte
- **AND** it SHALL fail with `resource-limit` before YAML composition

#### Scenario: Source and asset inputs are captured within fixed limits

- **GIVEN** a source manifest, inline snapshot, checksum manifest, current-evidence file, or referenced asset exceeds its fixed byte limit
- **WHEN** validation reads that input
- **THEN** it SHALL read no more than the applicable limit plus one sentinel byte
- **AND** it SHALL report `resource-limit` instead of `schema-error`, `broken-path`, or `digest-mismatch`
- **AND** an accepted inline snapshot SHALL use the same captured bytes for digest and fidelity checks

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


<!-- @trace
source: harden-tractatus-validation-boundaries
updated: 2026-08-09
code:
  - docs/tractatus/source-assets/images/b62025c4a407e7eb826ef60301c7aba855768d91af1e7b6d3248a9d8c43658f1.svg
  - docs/tractatus/source-assets/images/250px-TLP_6.1203d.png
  - docs/tractatus/source-assets/images/22c545a9a90d2f7b95fb0636e2d79882d0cd328a78afb1e7c723da5b44a774bf.svg
  - docs/tractatus/source-assets/images/336cae8a41089348ef601ba5dbe893d3758f7baa1841701bd587566e0f16d282.svg
  - docs/tractatus/source-assets/images/250px-TLP_5.5423.png
  - docs/tractatus/source-assets/images/9a45f5fb107652caa2fff811b19eeb0547bb7389fade741c2bd6e8b866f47858.svg
  - Tests/TractatusDocsTests/Fixtures/rendering-expected.md
  - docs/tractatus/source-assets/images/200px-TLP_6.1203e.png
  - .vscode/launch.json
  - docs/tractatus/source-assets/images/2f81698ca04ab3ce262aa94e5d57f69a5eaa2cadf033aba83d9dc9724869a8b0.svg
  - docs/tractatus/source-assets/images/6f5736dff9d73c6c95c36f30466ceb36b6191d4b51adec9af05bd29016ef01ea.svg
  - Sources/tractatus-doc/main.swift
  - docs/tractatus/corpus/4.yaml
  - docs/tractatus/source-assets/images/120px-TLP_6.1203c.png
  - docs/tractatus/source-assets/images/300px-TLP_6.1203d-en.png
  - docs/tractatus/source-assets/images/330px-TLP_6.36111.png
  - docs/tractatus/corpus/preface.yaml
  - docs/tractatus/corpus/2.yaml
  - docs/tractatus/source-assets/images/eb37987510f581cb73f8db614bd71715f510cf605279d48188050d8b509b47ed.svg
  - .github/workflows/ci.yml
  - Tests/TractatusDocsTests/TractatusValidationCLITests.swift
  - docs/tractatus/source-assets/images/ddf71a60f25ff0e495d94d2bd39bcde1e3e20286201c7de357bfe8b3b1575a1a.svg
  - docs/tractatus/source-snapshots/de-wittgenstein-project.md
  - docs/tractatus/source-assets/images/79fe9d279c0691bdeef7a6bf88e5f6a6364bd5b2dabfd79444199d7e0fb31ca7.svg
  - Tests/TractatusDocsTests/CorpusValidationTests.swift
  - docs/tractatus/corpus/7.yaml
  - docs/tractatus/source-assets/images/ea9e48f6e881e8a034e4cbc779a077ac01d2da54238fa332cfbe2255015dca69.svg
  - Tests/TractatusDocsTests/CorpusSourceFidelityTests.swift
  - docs/tractatus/source-assets/images/250px-TLP_5.6331en.png
  - docs/tractatus/source-assets/images/d1cf195aa1fb631bffe7b018f1114530b8c1bcc712299ba306fdef8ed6c55335.svg
  - Tests/TractatusDocsTests/TractatusInterfaceTests.swift
  - docs/tractatus/source-assets/images/2c3e0efa8931e01e650511958fc1f6d5b5cba8c4120db825866394563d645203.svg
  - docs/tractatus/source-snapshots/en-ogden-ramsey-1922-wittgenstein-project.md
  - docs/tractatus/source-assets/images/109747f0cdbcfd62f1bce67d93eb51350f5f3835c6459539f96d2dc70d84420f.svg
  - docs/tractatus/source-assets/images/cbe2c1a200eb49c3a9b16c7105afbb9fbed122da767f2d37389ac28a9e93e102.svg
  - docs/tractatus/source-assets/images/250px-TLP_6.1203a.png
  - docs/tractatus/generated/tractatus-project-map.md
  - docs/tractatus/source-assets/images/250px-TLP_5.6331.png
  - docs/tractatus/source-assets/images/8972055d3850ecff6e47e1516fc07474dfcc4bf7f0095ed9bcf5389c004a6d07.svg
  - docs/tractatus/source-assets/images/250px-TLP_6.1203b.png
  - docs/tractatus/source-assets/images/250px-TLP_6.1203e-en.png
  - docs/tractatus/source-assets/images/e5973c9367aeacc00f2830f165ecedfaa5664ca53875c29edf6be4ddffb89c18.svg
  - docs/tractatus/source-assets/SHA256SUMS
  - docs/tractatus/sources.yaml
  - docs/tractatus/source-assets/images/fe681449dc8d64199e5d1bdbf8208df658a75a9e18932d30c9dfe7f01673531e.svg
  - docs/tractatus/corpus/1.yaml
  - docs/tractatus/corpus/3.yaml
  - docs/tractatus/source-assets/images/1bd88ac2bf5db57ea9040cc5e72c42410c17abe58b77c117e3bfb0772eaf1d77.svg
  - docs/tractatus/source-assets/images/2363c84eb861521de9141a1ef7e7f9b8e30ee559dbe0fdd98ebe96665b1cacc5.svg
  - docs/tractatus/corpus/5.yaml
  - docs/tractatus/source-assets/images/d61fa425857e85da7c94020ddafdf3f8038c3f33900d3f3c7e222856a8859af8.svg
  - docs/tractatus/README.md
  - Sources/TractatusDocs/Validation.swift
  - Tests/TractatusDocsTests/SourceManifestTests.swift
  - docs/tractatus/source-assets/images/3b27b08186c4d2531ace97a6a386ca76d9996f0b7f4701697fb39daebd242145.svg
  - docs/tractatus/source-assets/images/300px-TLP_6.1203b-en.png
  - docs/tractatus/source-assets/images/9bfe93c20fc75f7848141a5dc2cdd0308e48f56967903cda5e95d9574182253c.svg
  - Sources/TractatusDocs/Rendering.swift
  - Tests/TractatusDocsTests/TractatusDiskFixture.swift
  - docs/tractatus/source-assets/images/b3394a04eba3cf3b36ede15e974e646aa098169220c2c60478507502e024c872.svg
  - Sources/TractatusDocs/DocumentService.swift
  - docs/tractatus/source-assets/images/2bdad2e773a893d516dedb66aae27db7901736d7838298078d42775abc368450.svg
  - Package.swift
  - docs/tractatus/source-assets/images/356a71ba81334c39be3a91a1d42c9d51eb9ad1ea7b726f750fd3a307d7947385.svg
  - Sources/TractatusDocs/SourceManifest.swift
  - Sources/TractatusDocs/Corpus.swift
  - docs/tractatus/source-assets/images/250px-TLP_6.1203c-en.png
  - docs/tractatus/source-assets/images/300px-TLP_6.1203a-en.png
  - Sources/TractatusDocs/RichText.swift
  - Tests/TractatusDocsTests/RenderingTests.swift
  - docs/tractatus/corpus/6.yaml
  - docs/tractatus/source-assets/images/6dfd74305dc6480d900085f169502024845a873e4e905856bf37dbc80f3bb653.svg
  - docs/tractatus/source-assets/images/531064e7807699e5544919383c09e44c0041e20bae70ec24417d5cc8e39fc4d6.svg
-->

---
### Requirement: Markdown rendering SHALL be derived and byte-deterministic

The renderer SHALL emit German, Ogden/Ramsey, Pears/McGuinness, and Traditional Chinese columns in that order. External-reference editions SHALL render a bibliographic reference and link instead of copied text. Each segment SHALL render its Chinese interpretation, and each proposition SHALL render its project relations, evidence, and history. Pinned source-image references SHALL render as HTML images pointing to checked-in offline assets rather than broken snapshot-relative links. The output SHALL contain a generated-file notice and SHALL NOT contain timestamps, absolute paths, or environment-dependent values.

#### Scenario: Rendering the same corpus twice is identical

- **WHEN** the same validated corpus is rendered twice with the same tool version
- **THEN** both output byte streams SHALL have identical SHA-256 digests

#### Scenario: Checked-in output has drifted

- **WHEN** `render --check` produces bytes different from the checked-in Markdown
- **THEN** the command SHALL fail with `generated-drift`
- **AND** it SHALL NOT modify the output file


<!-- @trace
source: add-tractatus-project-map
updated: 2026-08-09
code:
  - docs/tractatus/source-assets/images/531064e7807699e5544919383c09e44c0041e20bae70ec24417d5cc8e39fc4d6.svg
  - docs/tractatus/source-assets/images/6f5736dff9d73c6c95c36f30466ceb36b6191d4b51adec9af05bd29016ef01ea.svg
  - docs/tractatus/source-assets/images/200px-TLP_6.1203e.png
  - Sources/TractatusDocs/Corpus.swift
  - docs/tractatus/source-snapshots/en-ogden-ramsey-1922-wittgenstein-project.md
  - Sources/TractatusDocs/DocumentService.swift
  - docs/tractatus/source-assets/images/2363c84eb861521de9141a1ef7e7f9b8e30ee559dbe0fdd98ebe96665b1cacc5.svg
  - docs/tractatus/source-assets/images/250px-TLP_6.1203d.png
  - docs/tractatus/source-assets/images/9a45f5fb107652caa2fff811b19eeb0547bb7389fade741c2bd6e8b866f47858.svg
  - docs/tractatus/generated/tractatus-project-map.md
  - docs/tractatus/source-assets/images/79fe9d279c0691bdeef7a6bf88e5f6a6364bd5b2dabfd79444199d7e0fb31ca7.svg
  - docs/tractatus/source-assets/images/250px-TLP_6.1203a.png
  - .vscode/launch.json
  - docs/tractatus/corpus/6.yaml
  - docs/tractatus/source-assets/images/2f81698ca04ab3ce262aa94e5d57f69a5eaa2cadf033aba83d9dc9724869a8b0.svg
  - docs/tractatus/source-assets/images/ddf71a60f25ff0e495d94d2bd39bcde1e3e20286201c7de357bfe8b3b1575a1a.svg
  - Tests/TractatusDocsTests/CorpusSourceFidelityTests.swift
  - docs/tractatus/corpus/2.yaml
  - docs/tractatus/source-assets/images/fe681449dc8d64199e5d1bdbf8208df658a75a9e18932d30c9dfe7f01673531e.svg
  - docs/tractatus/source-snapshots/de-wittgenstein-project.md
  - Tests/TractatusDocsTests/Fixtures/rendering-expected.md
  - docs/tractatus/source-assets/images/8972055d3850ecff6e47e1516fc07474dfcc4bf7f0095ed9bcf5389c004a6d07.svg
  - docs/tractatus/source-assets/images/cbe2c1a200eb49c3a9b16c7105afbb9fbed122da767f2d37389ac28a9e93e102.svg
  - .github/workflows/ci.yml
  - docs/tractatus/corpus/preface.yaml
  - Package.swift
  - Sources/tractatus-doc/main.swift
  - docs/tractatus/corpus/3.yaml
  - docs/tractatus/source-assets/images/250px-TLP_5.5423.png
  - docs/tractatus/source-assets/images/2bdad2e773a893d516dedb66aae27db7901736d7838298078d42775abc368450.svg
  - docs/tractatus/source-assets/images/b62025c4a407e7eb826ef60301c7aba855768d91af1e7b6d3248a9d8c43658f1.svg
  - Sources/TractatusDocs/SourceManifest.swift
  - docs/tractatus/source-assets/images/1bd88ac2bf5db57ea9040cc5e72c42410c17abe58b77c117e3bfb0772eaf1d77.svg
  - docs/tractatus/source-assets/images/d61fa425857e85da7c94020ddafdf3f8038c3f33900d3f3c7e222856a8859af8.svg
  - Tests/TractatusDocsTests/TractatusInterfaceTests.swift
  - docs/tractatus/corpus/7.yaml
  - docs/tractatus/source-assets/SHA256SUMS
  - docs/tractatus/source-assets/images/356a71ba81334c39be3a91a1d42c9d51eb9ad1ea7b726f750fd3a307d7947385.svg
  - docs/tractatus/source-assets/images/ea9e48f6e881e8a034e4cbc779a077ac01d2da54238fa332cfbe2255015dca69.svg
  - docs/tractatus/corpus/4.yaml
  - docs/tractatus/source-assets/images/250px-TLP_6.1203b.png
  - docs/tractatus/source-assets/images/300px-TLP_6.1203a-en.png
  - docs/tractatus/source-assets/images/250px-TLP_6.1203e-en.png
  - Sources/TractatusDocs/Rendering.swift
  - docs/tractatus/source-assets/images/250px-TLP_5.6331.png
  - Sources/TractatusDocs/Validation.swift
  - Tests/TractatusDocsTests/SourceManifestTests.swift
  - Tests/TractatusDocsTests/TractatusDiskFixture.swift
  - docs/tractatus/source-assets/images/300px-TLP_6.1203d-en.png
  - docs/tractatus/README.md
  - docs/tractatus/source-assets/images/6dfd74305dc6480d900085f169502024845a873e4e905856bf37dbc80f3bb653.svg
  - docs/tractatus/source-assets/images/b3394a04eba3cf3b36ede15e974e646aa098169220c2c60478507502e024c872.svg
  - docs/tractatus/corpus/5.yaml
  - docs/tractatus/source-assets/images/250px-TLP_6.1203c-en.png
  - docs/tractatus/source-assets/images/336cae8a41089348ef601ba5dbe893d3758f7baa1841701bd587566e0f16d282.svg
  - docs/tractatus/sources.yaml
  - docs/tractatus/source-assets/images/2c3e0efa8931e01e650511958fc1f6d5b5cba8c4120db825866394563d645203.svg
  - docs/tractatus/source-assets/images/109747f0cdbcfd62f1bce67d93eb51350f5f3835c6459539f96d2dc70d84420f.svg
  - docs/tractatus/source-assets/images/300px-TLP_6.1203b-en.png
  - docs/tractatus/source-assets/images/330px-TLP_6.36111.png
  - Tests/TractatusDocsTests/RenderingTests.swift
  - Tests/TractatusDocsTests/TractatusValidationCLITests.swift
  - docs/tractatus/source-assets/images/d1cf195aa1fb631bffe7b018f1114530b8c1bcc712299ba306fdef8ed6c55335.svg
  - docs/tractatus/source-assets/images/9bfe93c20fc75f7848141a5dc2cdd0308e48f56967903cda5e95d9574182253c.svg
  - docs/tractatus/corpus/1.yaml
  - Tests/TractatusDocsTests/CorpusValidationTests.swift
  - docs/tractatus/source-assets/images/120px-TLP_6.1203c.png
  - docs/tractatus/source-assets/images/22c545a9a90d2f7b95fb0636e2d79882d0cd328a78afb1e7c723da5b44a774bf.svg
  - docs/tractatus/source-assets/images/eb37987510f581cb73f8db614bd71715f510cf605279d48188050d8b509b47ed.svg
  - docs/tractatus/source-assets/images/e5973c9367aeacc00f2830f165ecedfaa5664ca53875c29edf6be4ddffb89c18.svg
  - docs/tractatus/source-assets/images/250px-TLP_5.6331en.png
  - docs/tractatus/source-assets/images/3b27b08186c4d2531ace97a6a386ca76d9996f0b7f4701697fb39daebd242145.svg
-->

---
### Requirement: Continuous integration SHALL enforce the complete corpus and generated output

The main-branch workflow SHALL run strict corpus validation and generated-output checking after Swift tests. CI SHALL operate from checked-in files without retrieving source texts from the network.

#### Scenario: Corpus regression blocks integration

- **WHEN** a pushed change omits required content, breaks evidence, violates source rights, or leaves generated Markdown stale
- **THEN** the CI job SHALL fail before reporting the repository as valid

##### Example: Stale generated output fails the workflow

- **GIVEN** a canonical YAML translation changes while `docs/tractatus/generated/tractatus-project-map.md` remains unchanged
- **WHEN** CI runs strict validation followed by `render --check`
- **THEN** `render --check` SHALL report `generated-drift` and the job SHALL fail

<!-- @trace
source: add-tractatus-project-map
updated: 2026-08-09
code:
  - docs/tractatus/source-assets/images/531064e7807699e5544919383c09e44c0041e20bae70ec24417d5cc8e39fc4d6.svg
  - docs/tractatus/source-assets/images/6f5736dff9d73c6c95c36f30466ceb36b6191d4b51adec9af05bd29016ef01ea.svg
  - docs/tractatus/source-assets/images/200px-TLP_6.1203e.png
  - Sources/TractatusDocs/Corpus.swift
  - docs/tractatus/source-snapshots/en-ogden-ramsey-1922-wittgenstein-project.md
  - Sources/TractatusDocs/DocumentService.swift
  - docs/tractatus/source-assets/images/2363c84eb861521de9141a1ef7e7f9b8e30ee559dbe0fdd98ebe96665b1cacc5.svg
  - docs/tractatus/source-assets/images/250px-TLP_6.1203d.png
  - docs/tractatus/source-assets/images/9a45f5fb107652caa2fff811b19eeb0547bb7389fade741c2bd6e8b866f47858.svg
  - docs/tractatus/generated/tractatus-project-map.md
  - docs/tractatus/source-assets/images/79fe9d279c0691bdeef7a6bf88e5f6a6364bd5b2dabfd79444199d7e0fb31ca7.svg
  - docs/tractatus/source-assets/images/250px-TLP_6.1203a.png
  - .vscode/launch.json
  - docs/tractatus/corpus/6.yaml
  - docs/tractatus/source-assets/images/2f81698ca04ab3ce262aa94e5d57f69a5eaa2cadf033aba83d9dc9724869a8b0.svg
  - docs/tractatus/source-assets/images/ddf71a60f25ff0e495d94d2bd39bcde1e3e20286201c7de357bfe8b3b1575a1a.svg
  - Tests/TractatusDocsTests/CorpusSourceFidelityTests.swift
  - docs/tractatus/corpus/2.yaml
  - docs/tractatus/source-assets/images/fe681449dc8d64199e5d1bdbf8208df658a75a9e18932d30c9dfe7f01673531e.svg
  - docs/tractatus/source-snapshots/de-wittgenstein-project.md
  - Tests/TractatusDocsTests/Fixtures/rendering-expected.md
  - docs/tractatus/source-assets/images/8972055d3850ecff6e47e1516fc07474dfcc4bf7f0095ed9bcf5389c004a6d07.svg
  - docs/tractatus/source-assets/images/cbe2c1a200eb49c3a9b16c7105afbb9fbed122da767f2d37389ac28a9e93e102.svg
  - .github/workflows/ci.yml
  - docs/tractatus/corpus/preface.yaml
  - Package.swift
  - Sources/tractatus-doc/main.swift
  - docs/tractatus/corpus/3.yaml
  - docs/tractatus/source-assets/images/250px-TLP_5.5423.png
  - docs/tractatus/source-assets/images/2bdad2e773a893d516dedb66aae27db7901736d7838298078d42775abc368450.svg
  - docs/tractatus/source-assets/images/b62025c4a407e7eb826ef60301c7aba855768d91af1e7b6d3248a9d8c43658f1.svg
  - Sources/TractatusDocs/SourceManifest.swift
  - docs/tractatus/source-assets/images/1bd88ac2bf5db57ea9040cc5e72c42410c17abe58b77c117e3bfb0772eaf1d77.svg
  - docs/tractatus/source-assets/images/d61fa425857e85da7c94020ddafdf3f8038c3f33900d3f3c7e222856a8859af8.svg
  - Tests/TractatusDocsTests/TractatusInterfaceTests.swift
  - docs/tractatus/corpus/7.yaml
  - docs/tractatus/source-assets/SHA256SUMS
  - docs/tractatus/source-assets/images/356a71ba81334c39be3a91a1d42c9d51eb9ad1ea7b726f750fd3a307d7947385.svg
  - docs/tractatus/source-assets/images/ea9e48f6e881e8a034e4cbc779a077ac01d2da54238fa332cfbe2255015dca69.svg
  - docs/tractatus/corpus/4.yaml
  - docs/tractatus/source-assets/images/250px-TLP_6.1203b.png
  - docs/tractatus/source-assets/images/300px-TLP_6.1203a-en.png
  - docs/tractatus/source-assets/images/250px-TLP_6.1203e-en.png
  - Sources/TractatusDocs/Rendering.swift
  - docs/tractatus/source-assets/images/250px-TLP_5.6331.png
  - Sources/TractatusDocs/Validation.swift
  - Tests/TractatusDocsTests/SourceManifestTests.swift
  - Tests/TractatusDocsTests/TractatusDiskFixture.swift
  - docs/tractatus/source-assets/images/300px-TLP_6.1203d-en.png
  - docs/tractatus/README.md
  - docs/tractatus/source-assets/images/6dfd74305dc6480d900085f169502024845a873e4e905856bf37dbc80f3bb653.svg
  - docs/tractatus/source-assets/images/b3394a04eba3cf3b36ede15e974e646aa098169220c2c60478507502e024c872.svg
  - docs/tractatus/corpus/5.yaml
  - docs/tractatus/source-assets/images/250px-TLP_6.1203c-en.png
  - docs/tractatus/source-assets/images/336cae8a41089348ef601ba5dbe893d3758f7baa1841701bd587566e0f16d282.svg
  - docs/tractatus/sources.yaml
  - docs/tractatus/source-assets/images/2c3e0efa8931e01e650511958fc1f6d5b5cba8c4120db825866394563d645203.svg
  - docs/tractatus/source-assets/images/109747f0cdbcfd62f1bce67d93eb51350f5f3835c6459539f96d2dc70d84420f.svg
  - docs/tractatus/source-assets/images/300px-TLP_6.1203b-en.png
  - docs/tractatus/source-assets/images/330px-TLP_6.36111.png
  - Tests/TractatusDocsTests/RenderingTests.swift
  - Tests/TractatusDocsTests/TractatusValidationCLITests.swift
  - docs/tractatus/source-assets/images/d1cf195aa1fb631bffe7b018f1114530b8c1bcc712299ba306fdef8ed6c55335.svg
  - docs/tractatus/source-assets/images/9bfe93c20fc75f7848141a5dc2cdd0308e48f56967903cda5e95d9574182253c.svg
  - docs/tractatus/corpus/1.yaml
  - Tests/TractatusDocsTests/CorpusValidationTests.swift
  - docs/tractatus/source-assets/images/120px-TLP_6.1203c.png
  - docs/tractatus/source-assets/images/22c545a9a90d2f7b95fb0636e2d79882d0cd328a78afb1e7c723da5b44a774bf.svg
  - docs/tractatus/source-assets/images/eb37987510f581cb73f8db614bd71715f510cf605279d48188050d8b509b47ed.svg
  - docs/tractatus/source-assets/images/e5973c9367aeacc00f2830f165ecedfaa5664ca53875c29edf6be4ddffb89c18.svg
  - docs/tractatus/source-assets/images/250px-TLP_5.6331en.png
  - docs/tractatus/source-assets/images/3b27b08186c4d2531ace97a6a386ca76d9996f0b7f4701697fb39daebd242145.svg
-->
