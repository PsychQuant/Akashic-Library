# proposition-semantics Specification

## Purpose

TBD - created by archiving change 'integrate-akashic-proposition-tractatus-map'. Update Purpose after archive.

## Requirements

### Requirement: Authored propositions SHALL use a closed typed representation

The proposition model SHALL represent its initial predicate as Proposition.authored(person:work:) with two named EntityRef arguments. EntityRef SHALL distinguish a resolved key from an unresolved non-empty literal. Proposition.makeAuthored SHALL reject a key that fails StoreKey validation and a literal that is empty after trimming whitespace. Argument arity and direction SHALL remain part of the proposition type and identity.

#### Scenario: A well-formed authored proposition is constructed

- **WHEN** a caller constructs authored with a valid person key and a non-empty work literal through Proposition.makeAuthored
- **THEN** construction SHALL succeed
- **AND** the proposition SHALL report predicateName authored and exactly two ordered arguments

##### Example: Resolved person and unresolved work title

- **GIVEN** person key `cheng-che` and work literal `Tractatus Logico-Philosophicus`
- **WHEN** Proposition.makeAuthored constructs the proposition
- **THEN** its ordered arguments SHALL be `[key("cheng-che"), literal("Tractatus Logico-Philosophicus")]`

#### Scenario: An invalid entity reference is rejected

- **WHEN** a caller passes a malformed key or a whitespace-only literal through Proposition.makeAuthored
- **THEN** construction SHALL throw the corresponding PropositionError
- **AND** the invalid reference SHALL NOT be represented as unresolved identity

##### Example: Invalid construction inputs

| Input | Expected error |
| ----- | -------------- |
| `key("Not A Key")` | `malformedKey("Not A Key")` |
| `literal("   ")` | `emptyLiteral` |

#### Scenario: Reversing arguments changes the proposition

- **WHEN** two authored propositions exchange their person and work arguments
- **THEN** the propositions SHALL compare as different values

##### Example: Direction is part of identity

- **GIVEN** keys `cheng-che` and `tractatus`
- **WHEN** authored(person: `cheng-che`, work: `tractatus`) is compared with authored(person: `tractatus`, work: `cheng-che`)
- **THEN** equality SHALL be false


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
### Requirement: Projection SHALL preserve identity resolution and role direction

Proposition.project(in:) SHALL return Projection.projected only when the person argument resolves to a Person and the work argument resolves to an Entry in the supplied PropositionModel. It SHALL return Projection.unprojectable with a specific UnprojectableReason for an unresolved literal, an unknown identity, or a key that resolves to the wrong entity kind. Person and work roles SHALL NOT be interchangeable.

#### Scenario: Both arguments resolve with the correct kinds

- **WHEN** authored refers to a known Person key in the person role and a known Entry key in the work role
- **THEN** projection SHALL return the resolved Person and Entry

##### Example: Fully resolved projection

- **GIVEN** Person `cheng-che` and Entry `cheng2025identifiability` in the model
- **WHEN** those keys occupy the person and work roles respectively
- **THEN** projection SHALL return projected(person: `cheng-che`, work: `cheng2025identifiability`)

#### Scenario: A literal remains unresolved

- **WHEN** either proposition role contains EntityRef.literal
- **THEN** projection SHALL return unresolvedSymbol with that role and literal
- **AND** projection SHALL NOT claim an identity match

##### Example: Unresolved person symbol

- **GIVEN** person literal `Che Cheng` and a resolved work key
- **WHEN** the proposition is projected
- **THEN** the reason SHALL be unresolvedSymbol(role: `person`, literal: `Che Cheng`)

#### Scenario: Reversed entity kinds are diagnosed

- **WHEN** an Entry key occupies the person role or a Person key occupies the work role
- **THEN** projection SHALL return wrongEntityKind for the affected role

##### Example: Work key in the person role

- **GIVEN** `cheng2025identifiability` resolves only as an Entry
- **WHEN** it occupies the person role
- **THEN** the reason SHALL be wrongEntityKind(role: `person`, expected: `person`)


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
### Requirement: Evaluation SHALL preserve open-world uncertainty

TruthValue SHALL provide holds, fails, and undetermined states. The authored evaluator SHALL return holds only when the projected work contains the projected person key in an author slot. An unprojectable proposition SHALL return undetermined with notProjectable. A matching unresolved author literal SHALL return undetermined with supportingEvidenceUnresolved. Absence of supporting author identity SHALL return undetermined with noSupportingEvidence. The current authored evaluator SHALL NOT produce fails because the model has no positive author-list completeness evidence.

#### Scenario: Resolved supporting evidence establishes authored

- **WHEN** the projected work contains an author key equal to the projected person key
- **THEN** evaluate(in:) SHALL return holds

##### Example: Matching author identity

- **GIVEN** work `cheng2025identifiability` has author key `cheng-che`
- **WHEN** authored(person: `cheng-che`, work: `cheng2025identifiability`) is evaluated
- **THEN** the truth value SHALL be holds

#### Scenario: Absence is not false

- **WHEN** the work contains no matching resolved author key
- **THEN** evaluate(in:) SHALL return undetermined
- **AND** evaluate(in:) SHALL NOT return fails

##### Example: Different author does not prove falsity

- **GIVEN** the work contains only author key `someone-else`
- **WHEN** the proposition asks whether `cheng-che` authored that work
- **THEN** the truth value SHALL be undetermined(noSupportingEvidence)

#### Scenario: A matching literal is not accepted as identity

- **WHEN** an unresolved author literal normalizes to one of the person's names
- **THEN** evaluate(in:) SHALL return supportingEvidenceUnresolved with the literal
- **AND** evaluate(in:) SHALL NOT return holds

##### Example: Name match without identity

- **GIVEN** Person `cheng-che` has name `Che Cheng` and the work has author literal `Che Cheng`
- **WHEN** authored is evaluated
- **THEN** the truth value SHALL be undetermined(supportingEvidenceUnresolved(`Che Cheng`))


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
### Requirement: Yes-no questions SHALL expose a tri-valued answer space

YesNoQuestion SHALL retain its subject proposition and SHALL expose exactly yes, no, and undetermined as its exhaustive Answer cases. answer(in:) SHALL map TruthValue.holds to yes, TruthValue.fails to no, and every TruthValue.undetermined value to undetermined while preserving the full TruthValue alongside the answer. It SHALL NOT flatten the result to Bool.

#### Scenario: The answer space is exhaustive

- **WHEN** a caller reads YesNoQuestion.answerSpace
- **THEN** it SHALL contain yes, no, and undetermined exactly once
- **AND** it SHALL equal the complete set of Answer cases

##### Example: Three exhaustive labels

- **GIVEN** any authored subject
- **WHEN** answerSpace is read
- **THEN** its value SHALL be `[yes, no, undetermined]`

#### Scenario: Evaluation remains tri-valued

- **WHEN** a subject evaluates to holds or undetermined
- **THEN** answer(in:) SHALL return yes or undetermined respectively
- **AND** it SHALL preserve the originating TruthValue

##### Example: Supported and unsupported subjects

| Subject truth | Answer |
| ------------- | ------ |
| `holds` | `yes` |
| `undetermined(noSupportingEvidence)` | `undetermined` |


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
### Requirement: Fact acceptance SHALL be gated from recorded assertions

Assertion SHALL record a proposition, a Stance, source, and recorded timestamp without itself asserting truth. AcceptedFact SHALL be a distinct type whose construction is restricted to adjudicate. adjudicate SHALL accept only an Assertion with stance asserted whose proposition evaluates to holds. It SHALL reject denied or questioned stances with stanceIsNotAssertion and SHALL reject fails or undetermined truth with notEstablished.

#### Scenario: An established assertion becomes an accepted fact

- **WHEN** an asserted Assertion evaluates to holds
- **THEN** adjudicate SHALL return an AcceptedFact that retains the assertion as its basis
- **AND** the result SHALL record acceptedBy and acceptedAt

##### Example: Accepted supported assertion

- **GIVEN** an asserted authored proposition that evaluates to holds
- **WHEN** `che` adjudicates it at `2026-08-09`
- **THEN** the fact SHALL retain that assertion, `che`, and `2026-08-09`

#### Scenario: A question or denial cannot become a fact

- **WHEN** an Assertion has questioned or denied stance
- **THEN** adjudicate SHALL throw stanceIsNotAssertion
- **AND** no AcceptedFact SHALL be created

##### Example: Non-asserting stances

| Stance | Expected refusal |
| ------ | ---------------- |
| `questioned` | `stanceIsNotAssertion(questioned)` |
| `denied` | `stanceIsNotAssertion(denied)` |

#### Scenario: Uncertainty cannot become a fact

- **WHEN** an asserted Assertion evaluates to undetermined
- **THEN** adjudicate SHALL throw notEstablished
- **AND** no AcceptedFact SHALL be created

##### Example: Missing support remains unaccepted

- **GIVEN** an asserted authored proposition with no supporting author identity
- **WHEN** it is adjudicated
- **THEN** the refusal SHALL be notEstablished(undetermined(noSupportingEvidence))

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