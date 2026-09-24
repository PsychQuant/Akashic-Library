# plugin-root-guard-coverage Specification

## Purpose

The repository's guards protect test scripts and rule references from silent deletion or disconnection. This capability makes every plugin root visible to those guards through a single source of truth, checks that the filesystem and the marketplace manifest agree on which plugins exist, and proves by mutation that a plugin root outside `plugin/` is actually seen.

## Requirements

### Requirement: Single source of plugin roots

The guard binary SHALL compute the plugin roots in one function: `plugin`, plus every immediate child directory of `plugins/` that contains `.claude-plugin/plugin.json`. The subcommand `akashic-guards plugin-roots` SHALL print these roots as repository-relative paths, one per line, sorted, and exit 0. Shell scripts MUST obtain plugin roots from this subcommand and MUST NOT keep their own list.

#### Scenario: Roots printed for shell consumers

- **WHEN** `akashic-guards plugin-roots` runs
- **THEN** it prints each plugin root on its own line in sorted order

##### Example: directory without a manifest is not a root

- **GIVEN** directories `plugin/`, `plugins/akashic-discovery/` containing `.claude-plugin/plugin.json`, and `plugins/scratch/` without a manifest
- **WHEN** `akashic-guards plugin-roots` runs
- **THEN** the output is exactly `plugin` and `plugins/akashic-discovery`, in that order


<!-- @trace
source: akashic-plugin-marketplace
updated: 2026-09-24
code:
  - Sources/AkashicEntity/PersonResolver.swift
  - Sources/AkashicCore/DuplicateCitekeys.swift
  - Tests/AkashicMCPTests/DuplicateCitekeyResolveTests.swift
  - Sources/akashic/Commands.swift
  - Tests/AkashicAppKitTests/AdjudicationTests.swift
  - Sources/AkashicMCPKit/AkashicService.swift
  - Tests/AkashicKitTests/PersonResolverTests.swift
  - Sources/akashic-mcp/Server.swift
  - changelog/2026-09-24-skill-exits-and-fulltext.md
  - Sources/AkashicAppKit/Adjudication.swift
-->

---
### Requirement: Filesystem and marketplace manifest agree

The subcommand `akashic-guards marketplace-consistency` SHALL exit non-zero and name every offending path or plugin when any of the following holds; otherwise it SHALL exit 0. This is a closed list: (1) a plugin root has no marketplace entry whose `source` resolves to it; (2) a marketplace entry's `source` does not resolve to a plugin root; (3) a marketplace entry's `name` differs from the `name` in the manifest at its source; (4) an immediate child directory of `plugins/` has no `.claude-plugin/plugin.json`; (5) a plugin manifest lists a dependency name that is not the name of a plugin in the same marketplace.

#### Scenario: Each disagreement fails with the offender named

- **WHEN** `akashic-guards marketplace-consistency` runs against a tree in one of the states below
- **THEN** it produces the listed result

##### Example: consistency outcomes

| Tree state | Result |
| ---------- | ------ |
| Filesystem roots and manifest sources are equal, names match, dependencies resolve | exit 0 |
| `plugins/foo/` has a manifest but no marketplace entry | non-zero, names `plugins/foo` |
| Entry `bar` has source `./plugins/bar` and that directory is absent | non-zero, names `bar` |
| Entry name `akashic-discovery`, manifest name `akashic-discover` | non-zero, names both |
| `plugins/scratch/` exists without a manifest | non-zero, names `plugins/scratch` |
| `akashic-discovery` depends on `akashic-core`, which no entry lists | non-zero, names `akashic-core` |


<!-- @trace
source: akashic-plugin-marketplace
updated: 2026-09-24
code:
  - Sources/AkashicEntity/PersonResolver.swift
  - Sources/AkashicCore/DuplicateCitekeys.swift
  - Tests/AkashicMCPTests/DuplicateCitekeyResolveTests.swift
  - Sources/akashic/Commands.swift
  - Tests/AkashicAppKitTests/AdjudicationTests.swift
  - Sources/AkashicMCPKit/AkashicService.swift
  - Tests/AkashicKitTests/PersonResolverTests.swift
  - Sources/akashic-mcp/Server.swift
  - changelog/2026-09-24-skill-exits-and-fulltext.md
  - Sources/AkashicAppKit/Adjudication.swift
-->

---
### Requirement: Protected inventory covers every plugin root

The protected inventory SHALL apply each of its existing test-script and rule patterns under every plugin root returned by the single source of plugin roots, not only under `plugin/`. A file reachable only through the `rules` directory symlink MUST be counted once, under its real path in `plugin/rules/`.

#### Scenario: Deleting a protected test under a new root is caught

- **WHEN** a protected test script under `plugins/akashic-discovery/` is deleted without updating the ratchet
- **THEN** `akashic-guards protected-ratchet` exits non-zero and names the deleted file

#### Scenario: Unwired test under a new root is caught

- **WHEN** a test script matching a protected pattern is added under `plugins/akashic-discovery/` and no guard entry point runs it
- **THEN** `akashic-guards trigger-coverage` exits non-zero and names that file

#### Scenario: Symlinked rules are not double counted

- **WHEN** the protected inventory is computed with `plugins/akashic-discovery/rules` linking to `plugin/rules`
- **THEN** each rule file appears exactly once, under `plugin/rules/`


<!-- @trace
source: akashic-plugin-marketplace
updated: 2026-09-24
code:
  - Sources/AkashicEntity/PersonResolver.swift
  - Sources/AkashicCore/DuplicateCitekeys.swift
  - Tests/AkashicMCPTests/DuplicateCitekeyResolveTests.swift
  - Sources/akashic/Commands.swift
  - Tests/AkashicAppKitTests/AdjudicationTests.swift
  - Sources/AkashicMCPKit/AkashicService.swift
  - Tests/AkashicKitTests/PersonResolverTests.swift
  - Sources/akashic-mcp/Server.swift
  - changelog/2026-09-24-skill-exits-and-fulltext.md
  - Sources/AkashicAppKit/Adjudication.swift
-->

---
### Requirement: Rule coverage runs per plugin root

`plugin/tests/rule-coverage.sh` SHALL accept an optional plugin root argument, defaulting to `plugin`. The guard entry point SHALL run it once for every root printed by `akashic-guards plugin-roots`. A root with no `skills/` directory, or with zero skill directories, SHALL print a line stating that it has 0 skills and is vacuously covered, and SHALL pass.

#### Scenario: Plugin with no skills passes visibly

- **WHEN** rule coverage runs for `plugins/akashic-discovery` before any skill exists
- **THEN** it prints that the root has 0 skills (vacuous) and exits 0

#### Scenario: Skill missing a rule reference fails

- **WHEN** a skill under `plugins/akashic-discovery/skills/` has no resolvable relative reference to a rule file under that root's `rules/`
- **THEN** rule coverage for that root exits non-zero and names the skill and the rule


<!-- @trace
source: akashic-plugin-marketplace
updated: 2026-09-24
code:
  - Sources/AkashicEntity/PersonResolver.swift
  - Sources/AkashicCore/DuplicateCitekeys.swift
  - Tests/AkashicMCPTests/DuplicateCitekeyResolveTests.swift
  - Sources/akashic/Commands.swift
  - Tests/AkashicAppKitTests/AdjudicationTests.swift
  - Sources/AkashicMCPKit/AkashicService.swift
  - Tests/AkashicKitTests/PersonResolverTests.swift
  - Sources/akashic-mcp/Server.swift
  - changelog/2026-09-24-skill-exits-and-fulltext.md
  - Sources/AkashicAppKit/Adjudication.swift
-->

---
### Requirement: CI triggers include plugin roots and the manifest

The workflow that runs the guard entry point SHALL trigger on changes under `plugins/**` and `.claude-plugin/**` in addition to its existing paths. The Swift build workflow SHALL ignore changes confined to `plugins/**` and `.claude-plugin/**`, as it already ignores `plugin/**`.

#### Scenario: Change confined to a new plugin runs the guards

- **WHEN** a push changes only files under `plugins/akashic-discovery/`
- **THEN** the guard workflow runs and the Swift build workflow does not


<!-- @trace
source: akashic-plugin-marketplace
updated: 2026-09-24
code:
  - Sources/AkashicEntity/PersonResolver.swift
  - Sources/AkashicCore/DuplicateCitekeys.swift
  - Tests/AkashicMCPTests/DuplicateCitekeyResolveTests.swift
  - Sources/akashic/Commands.swift
  - Tests/AkashicAppKitTests/AdjudicationTests.swift
  - Sources/AkashicMCPKit/AkashicService.swift
  - Tests/AkashicKitTests/PersonResolverTests.swift
  - Sources/akashic-mcp/Server.swift
  - changelog/2026-09-24-skill-exits-and-fulltext.md
  - Sources/AkashicAppKit/Adjudication.swift
-->

---
### Requirement: Official validation where the CLI exists

The guard entry point SHALL run `claude plugin validate --json .` when the `claude` command is available, and fail when the result has any error or any warning outside the closed allowlist defined by the repository-root marketplace manifest requirement (exactly one entry: the `binary_version` unknown-field warning on `plugin/.claude-plugin/plugin.json`). When `claude` is not available it SHALL print a line stating that official validation was skipped because the CLI is absent, and continue. It MUST NOT skip silently.

#### Scenario: CI without the CLI

- **WHEN** the guard entry point runs where `claude` is not on the PATH
- **THEN** its output contains a line stating that `claude plugin validate` was skipped because the CLI is absent


<!-- @trace
source: akashic-plugin-marketplace
updated: 2026-09-24
code:
  - Sources/AkashicEntity/PersonResolver.swift
  - Sources/AkashicCore/DuplicateCitekeys.swift
  - Tests/AkashicMCPTests/DuplicateCitekeyResolveTests.swift
  - Sources/akashic/Commands.swift
  - Tests/AkashicAppKitTests/AdjudicationTests.swift
  - Sources/AkashicMCPKit/AkashicService.swift
  - Tests/AkashicKitTests/PersonResolverTests.swift
  - Sources/akashic-mcp/Server.swift
  - changelog/2026-09-24-skill-exits-and-fulltext.md
  - Sources/AkashicAppKit/Adjudication.swift
-->

---
### Requirement: Mutation proof that new roots are seen

The subcommand `akashic-guards plugin-roots-mutations` SHALL copy the repository tree, apply each mutation below to the copy, run the named guard against the copy, and exit non-zero unless every mutation makes its guard fail. It MUST NOT modify the original tree.

#### Scenario: Every mutation is caught

- **WHEN** `akashic-guards plugin-roots-mutations` runs
- **THEN** each mutation below makes its guard exit non-zero, and the subcommand exits 0

##### Example: mutation table

| Mutation applied to the copy | Guard that must fail |
| ---------------------------- | -------------------- |
| Add an unwired test script under `plugins/akashic-discovery/skills/probe/scripts/tests/` | trigger-coverage |
| Delete a protected test script under `plugins/akashic-discovery/` | protected-ratchet |
| Remove `plugins/**` from the guard workflow's trigger paths | trigger-coverage |
| Add `plugins/foo/` with a manifest and no marketplace entry | marketplace-consistency |
| Point the `akashic-discovery` entry's source at a missing directory | marketplace-consistency |
| Add a skill under `plugins/akashic-discovery/skills/` with no rule reference | rule-coverage for that root |

<!-- @trace
source: akashic-plugin-marketplace
updated: 2026-09-24
code:
  - Sources/AkashicEntity/PersonResolver.swift
  - Sources/AkashicCore/DuplicateCitekeys.swift
  - Tests/AkashicMCPTests/DuplicateCitekeyResolveTests.swift
  - Sources/akashic/Commands.swift
  - Tests/AkashicAppKitTests/AdjudicationTests.swift
  - Sources/AkashicMCPKit/AkashicService.swift
  - Tests/AkashicKitTests/PersonResolverTests.swift
  - Sources/akashic-mcp/Server.swift
  - changelog/2026-09-24-skill-exits-and-fulltext.md
  - Sources/AkashicAppKit/Adjudication.swift
-->