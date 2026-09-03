## ADDED Requirements

### Requirement: Add-only enrichment has exactly one policy implementation

The system SHALL implement the add-only field policy once, in `AddOnlyEnrichment` (AkashicCore), and every enrichment surface (the generic CLI command, the generic MCP tool, and the Zotero adapter) SHALL delegate to it. The policy SHALL be: only keys absent from `fields` are added; `issn` proposals are rejected; `doi`, `pmid`, and `isbn` proposals are written to the structured identifier fields with unparsed residue kept in `fields`; `date` is filled only when empty; literal `authors` are filled only when the entry has no authors and the include-absent-authors flag is set; `type`, `title`, `venues`, and `attachments` are never modified.

#### Scenario: Existing keys are never overwritten

- **WHEN** a proposal targets an entry whose `fields` already contain `abstract` and proposes a different `abstract`
- **THEN** the entry's `abstract` is unchanged and the item is reported as `skipped` with the key listed as already present

#### Scenario: Zotero adapter is behaviourally equivalent

- **WHEN** the existing Zotero enrichment test suite (`ZoteroEnrichmentTests`, 12 tests) runs against the adapter that delegates to `AddOnlyEnrichment`
- **THEN** every test passes without modification

### Requirement: Proposals locate a work by citekey or DOI

Each proposal SHALL name its target by exactly one of `citekey` or `doi`. A DOI SHALL be matched against entries' structured `doi` lists using the `DOI` type's normal form. When the DOI matches exactly one entry, the system SHALL resolve it to that citekey. When the DOI matches two or more entries, the system SHALL classify the item as `ambiguous`, list every matching citekey, and write nothing for that item. When the DOI matches no entry, the system SHALL classify the item as `notFound`. A proposal that gives both keys or neither SHALL be an input error that rejects the whole batch with zero writes.

#### Scenario: DOI matching several entries is refused and named

- **WHEN** a proposal gives `doi: 10.1037/x` and the store holds two entries whose `doi` lists both contain that DOI
- **THEN** the item is reported as `ambiguous` with both citekeys listed and neither entry is modified

##### Example: twin works sharing a DOI

- **GIVEN** entries `smith2020a` and `smith2020b` both carry `doi: 10.1037/x`
- **WHEN** a proposal `{ doi: "10.1037/x", fields: { abstract: "…" } }` is applied
- **THEN** the report item has `category: ambiguous`, `matches: ["smith2020a", "smith2020b"]`, and both entries' `fields` are byte-identical to before

#### Scenario: DOI matching one entry resolves to it

- **WHEN** a proposal gives a DOI that exactly one entry carries
- **THEN** the item's `citekey` is that entry's citekey and additions are computed against it

#### Scenario: Both keys given is an input error

- **WHEN** any proposal in the batch gives both `citekey` and `doi`
- **THEN** the whole batch is rejected with an error naming the offending proposal index and no entry is written

### Requirement: Two abstracts are stored under two keys

When a source provides more than one abstract, the caller SHALL name the second key (`abstract-<lang>` when the language is known, `abstract-2` otherwise) and the system SHALL store it under that key after `FieldKey.normalized` (for example `abstract_es`, `abstract_2`). The system SHALL NOT concatenate abstracts, SHALL NOT drop the second abstract, and SHALL NOT invent a key name.

#### Scenario: Second abstract lands under its own key

- **WHEN** a proposal's `fields` contain both `abstract` and `abstract-es` for an entry with neither key
- **THEN** the entry gains `abstract` and `abstract_es` as two separate fields

##### Example: Spanish second abstract

- **GIVEN** entry `garcia2021` with no abstract fields
- **WHEN** a proposal `{ citekey: "garcia2021", fields: { abstract: "English text", "abstract-es": "Texto español" } }` is applied
- **THEN** `fields["abstract"] == "English text"` and `fields["abstract_es"] == "Texto español"`, and the report lists two additions

#### Scenario: First abstract present, only the second is added

- **WHEN** the entry already has `abstract` and the proposal provides `abstract` and `abstract-2`
- **THEN** only `abstract_2` is added and `abstract` is reported as already present

### Requirement: Dry run is the default and apply is gated on the CLI only

The CLI command `enrich --from <file>` SHALL compute and print the report without writing unless `--apply` is given, and `--apply` SHALL pass through the destructive-target gate. The MCP tool `akashic_enrich` SHALL default `dry_run` to true and SHALL NOT apply the destructive-target gate, because its proposals name their targets explicitly. Both surfaces SHALL call the same service function, which loads the store once, applies all writable items, and rebuilds the index once.

#### Scenario: CLI dry run writes nothing

- **WHEN** `akashic enrich --from proposals.json` runs without `--apply`
- **THEN** the report is printed and no entity file changes

#### Scenario: MCP dry run is the default

- **WHEN** `akashic_enrich` is called with `proposals` and without `dry_run`
- **THEN** the response carries the report and no entity file changes

### Requirement: Source digests are reported, never stored on the work

The `Proposal` shape SHALL include an optional `sourceDigest` used only for reporting. When present, the system SHALL echo it in the report item and SHALL NOT write it into `Entry.references`.

#### Scenario: Digest appears in the report only

- **WHEN** a proposal carries `sourceDigest: sha256:…` and is applied
- **THEN** the report item shows that digest and the entry's `references` list is unchanged
