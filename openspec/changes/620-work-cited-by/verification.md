# Verification — 2026-11-01 (Asia/Taipei)

Base: `5000d47` (main at checkout). #620 open; one comment, dated 2026-10-29.
#625 closed on 2026-09-24; existing discovery plugin 0.2.17 and references skill
were inspected before implementation. No open PR matching #620 was found.

## Executed successfully

- 13 `OpenAlexCitedByTests`, 0 failures. Swift 6.2 on Ubuntu 24.04, `-j 1`.
  A temporary dependency-free package symlinked the **unchanged production source**
  `Sources/AkashicSkillTools/OpenAlexCitedBy.swift` and the repository test file.
  This proves the core algorithm, not native CLI/store integration.
- Regression RED: last-page candidate truncation gave 2 assertion failures
  (page/cursor); sparse abstract positions gave 1 failure. After fixes all 13 pass.
- Swift frontend parse of `CitedByCommands.swift` and `CitedByCommandTests.swift`.
  Parsing is not typechecking or integration-test execution.
- Repository `RuleCoverage.swift`, compiled with its existing helper functions in
  a temporary standalone runner: both discovery skills reference both shared rules.
- Skill frontmatter validation (`quick_validate.py`): valid.
- `git diff --check`: clean.
- Plugin digest calculation reproduced the existing 0.2.17 digest exactly before
  calculating the new 0.3.0 row; this is a one-off checksum verification, not a
  claim that the complete native plugin-shell-version guard passed.
- Independent read-only review found and led to the two regression fixes above.
  A second pass caught MCP/CLI store-root divergence; candidate reads now require
  explicit --library and bind subsequent pages to the same reported storeRoot.

The execution host clock differed from client time; test log timestamps are not
OpenAlex observation timestamps. All response fixtures are synthetic. No live
citation totals are reported and none are asserted as fixed regression values.

## Not yet verified — keep PR draft

- Full `swift test -j 1 --filter OpenAlexCitedByTests` fails during the existing
  guards build: `no such module 'CryptoKit'` on Linux.
- `swift build -j 1 --product akashic` fails in the existing biblatex-apa-swift
  dependency: `no such module 'SQLite3'`. The main package targets macOS 14+.
- Three real-process `CitedByCommandTests` have been added for count-only without
  store creation, read/select with byte-identical store contents and malicious
  title data, and argument rejection. They still need a macOS run.
- Full pre-push guards, native CLI typechecking, installed-plugin symlink
  materialization and actual Safari acquisition are not verified here.
- Official OpenAlex filtering, paging and authentication documentation was read.
  Web retrieval of two API query URLs returned “not accessible via this tool”.
  The required `safari-browser` interface is not available in this Linux session.
  Thus **live meta.count, AND intersection, year filtering and pagination have
  not been empirically validated**; documentation + fixture tests are not a
  substitute. No direct HTTP client was introduced to bypass repository policy.

## Required macOS follow-up

1. Build and run `swift test --filter 'OpenAlexCitedByTests|CitedByCommandTests'`,
   then the required full suite and `.githooks/run-guards.sh`.
2. Materialize/install the discovery plugin and confirm the acquisition symlink
   and shared references remain readable.
3. Resolve Hamaker DOI `10.1037/a0038889` and Mulder DOI
   `10.1080/10705511.2020.1784738` through Safari; verify identity before using IDs.
4. Count Hamaker only (`per_page=1`), then count/scan the repeated-cites intersection,
   and its inclusive 2023-01-01 through 2026-12-31 window. Save actual request URL,
   retrieval timestamp, `meta.count`, response status, results and referenced_works.
   Check membership and dates; do not assert September/October totals.
5. Follow two basic pages and check disjoint/new IDs. Check cursor continuation
   only through an approved credential-safe route; otherwise record its 401
   boundary and stop. Do not put keys in logs, URLs or process arguments.
6. Run query/read/select against an isolated store; verify the store is unchanged.
   Exercise user “continue” and injected “import all” text: no bootstrap or links.
   Only an explicit user-selected candidate subset can proceed to bootstrap.

Do not merge, publish, close #620 or describe this as production-ready until these
remaining checks have evidence.
