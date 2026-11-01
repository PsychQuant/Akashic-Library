# #620 OpenAlex forward citation discovery

Add `akashic-work-cited-by` to the existing discovery plugin. #625 is closed;
reuse its marketplace, dependency and shared rules. Reuse canonical DOI/store
lookups, bootstrap identity verification and `akashic_link` for selected works.
No new HTTP client, store writer, automatic import or reference expansion.

The user requested implementation on 2026-11-01. Decisions for this change:
intersection by default; explicit union supported; no narrowing criterion means
count only; journals are caller-supplied OpenAlex source IDs, not a hidden allowlist;
selection is by stable OpenAlex ID in conversation; no recursive expansion.
