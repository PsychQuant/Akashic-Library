# Design

## Read-only pipeline

Swift `cited-by query` validates resolved OpenAlex seed IDs and creates a query
plan. `cited-by read` consumes one browser-fetched JSON response at a time and
records its retrieval time. `cited-by select` emits only explicitly named IDs
as a handoff proposal; it does not invoke bootstrap or write to the store.
The skill enforces that selection originates in a user message after the table.

Count-only uses per_page=1 and reads meta.count, never a seed's cited_by_count.
Multiple seeds use repeated cites filters (AND), or one pipe filter (OR).
Year endpoints become inclusive publication dates. Filtered retrieval uses
bounded basic paging by default (at most 10,000 hits), optional cursor paging, at most 100 rows/page, a finite page and candidate budget, stable
query parameters, ID deduplication, repeated-cursor rejection and explicit
partial status. Every page keeps its observed count/time; index updates can
change counts. No count is hardcoded into a regression test.

## Methodological screening

Retain the fetched candidate pool. Expose separate title/abstract clues for
critique, extension and evaluation, with literal evidence; these are nomination
signals, not semantic verdicts. Missing abstracts remain unknown. Have the agent
read evidence and classify critique / extension / evaluation / application /
uncertain, explaining each judgement. Offer both citation and recent-date sorting;
do not silently exclude recent, low-citation or non-core-journal papers.

## Reuse and boundaries

Implement deterministic logic in Swift. External retrieval remains browser-based,
following the existing web-access procedure. Share that procedure through a
plugin-local symlink; installed plugins must materialize it. CLI-only intermediate
file processing is explicitly recorded in the parity table. The CLI reads the
existing canonical store snapshot to annotate DOI matches and conflicts; bootstrap
must repeat identity and duplicate checks immediately before any write.

## Verification

Synthetic fixtures exercise URLs, count-only, AND/OR, year limits, cursor progress,
changing counts, malformed pages, budgets, deduplication, evidence, selection and
injection boundaries. Live API checks must record actual timestamps and responses;
network/toolchain limitations are recorded as unverified, never as passing.
