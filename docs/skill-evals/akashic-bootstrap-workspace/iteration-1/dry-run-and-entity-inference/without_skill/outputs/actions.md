# Actions taken (store-modifying)

Store: `/Users/che/Developer/psychquant-claude-plugins/plugins/akashic-mcp/skills/akashic-bootstrap-workspace/iteration-1/dry-run-and-entity-inference/without_skill/store`

All actions below were actually executed (nothing was only planned). No `mcp__*akashic*` MCP tool was used — CLI + direct file writes only, exactly as instructed.

## 1. Research (read-only, not store-modifying)

Ran `curl` against the public Crossref REST API (`api.crossref.org`) to resolve each
user-supplied title to a DOI and pull full metadata (authors, journal, volume/issue/pages,
ISSN, publication dates). No akashic command involved; purely external lookup to avoid
fabricating bibliographic data.

## 2. Wrote 3 new entity files directly (CLI has no "add entry" subcommand)

The `akashic` CLI only supports `import-zotero` / `import-wos` as write paths for new
entries — there is no manual "create entry" subcommand. Per `docs/store-format.md` §5.-1
(entities/<uuid>.yaml, format 4, bare shape label `work:`/`person:`/`organization:`), I
hand-authored 3 new YAML files under `entities/`:

- `entities/83B552E8-16A7-4330-874A-E1296027E343.yaml` — citekey `yang2026fourier`
  ("Fourier analysis of spatial point processes", Bernoulli 2026, DOI 10.3150/25-bej1862)
- `entities/2379F0E7-F8AB-4B12-B35E-E575C2D9550F.yaml` — citekey `jou2026generalized`
  ("A Generalized Mean Approach for Distributed-PCA", JCGS 2026, DOI 10.1080/10618600.2025.2561234)
- `entities/3AD71A3A-1259-4C84-8D89-DF1F47BC0420.yaml` — citekey `chu2025pseudo`
  ("Pseudo datasets explain artificial neural networks", Int. J. Data Sci. Anal. 2025,
  DOI 10.1007/s41060-024-00526-9)

Each file: bare `work:` shape label, `id` = filename UUID, `citekey` generated per project
rule (lowercase first-author surname + year + first substantive title word), `type: article`,
`title`, `authors:` as unresolved `literal:` entries (no matching `person` record exists in
this store for any of these author names, so per "never auto-merge" policy they were left
unresolved rather than guessed into an existing person key), `date`, and `fields:` (journaltitle,
volume, number, pages where applicable, doi, issn, url).

**Actually executed** — files written via the Write tool, not a dry-run.

## 3. Validated the store

```
/Users/che/Developer/Akashic-Library/.build/arm64-apple-macosx/debug/akashic validate --library <store>
```
Result: `✓ 15 entries、12 people、0 libraries 全部通過` (exit 0). **Actually run.**

## 4. Rebuilt the index

```
/Users/che/Developer/Akashic-Library/.build/arm64-apple-macosx/debug/akashic doctor --library <store>
```
Result: `entries: 15, people: 12, relations: 0, orphaned: 0, unresolved author literals: 32`
(exit 0). **Actually run.** This rebuilds `.akashic/index.sqlite`, a derived cache — safe/
idempotent, not a canonical-data mutation beyond what step 2 already did.

## 5. Verification queries (read-only, not store-modifying)

```
akashic query --library <store> --author Yang --json
akashic export-bib --library <store> --citekeys yang2026fourier,jou2026generalized,chu2025pseudo
```
Both confirm the three new entries are indexed and export correctly. **Actually run**, no
side effects (query/export-bib don't write to the store).

## Not done / left for the user

- No `person` records were created for any of the new authors (`bootstrap-people` /
  `resolve-people` were not run) — left as unresolved `literal:` authors per the
  never-auto-merge policy.
- No `akashic.tags` or `akashic.libraries` were set (user didn't request categorization).
