# plugin-marketplace-distribution Specification

## Purpose

Akashic-Library publishes its Claude Code plugins itself, as the marketplace `akashic`, so that `akashic-mcp` and the discovery plugin ship from the same repository commit. This capability defines the marketplace manifest, the on-disk plugin layout, the dependency between plugins, and the migration of the existing `akashic-mcp` install id.

## Requirements

### Requirement: Repository-root marketplace manifest

The repository SHALL contain a marketplace manifest at `.claude-plugin/marketplace.json` whose `name` is `akashic`, whose `owner` is set, and whose `plugins` array lists every plugin in the repository with a relative `source` path. `claude plugin validate --json .` run from the repository root reports no errors, and its only warning is the unknown-field warning for `binary_version` in `plugin/.claude-plugin/plugin.json`. That field is read by the MCP wrapper to choose the server binary release (#275) and by harness-devtools; it is deliberately kept. This allowlist is closed: exactly one entry, and any other warning MUST fail.

#### Scenario: Manifest lists both plugins with relative sources

- **WHEN** the marketplace manifest is read
- **THEN** it lists exactly the plugins below, each with the given source

##### Example: plugin entries

| Plugin name | Source |
| ----------- | ------ |
| `akashic-mcp` | `./plugin` |
| `akashic-discovery` | `./plugins/akashic-discovery` |

#### Scenario: Official validation passes except the allowlisted field

- **WHEN** `claude plugin validate --json .` runs in the repository root with Claude Code installed
- **THEN** its `errors` list is empty and its `warnings` list contains exactly one entry, whose path is `plugins[0] plugin.json → binary_version`

#### Scenario: A new unknown field fails

- **WHEN** a manifest in the repository gains any other field that the validator reports as unknown
- **THEN** official validation fails and names that field


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
### Requirement: Plugin directory layout

`akashic-mcp` SHALL remain at `plugin/`. Every other plugin SHALL live at `plugins/<plugin-name>/`, with its manifest at `plugins/<plugin-name>/.claude-plugin/plugin.json`, and the directory name MUST equal the manifest `name`.

#### Scenario: Discovery plugin location

- **WHEN** the `akashic-discovery` plugin is added
- **THEN** its manifest is at `plugins/akashic-discovery/.claude-plugin/plugin.json` and its `name` is `akashic-discovery`


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
### Requirement: Discovery plugin depends on akashic-mcp without a version range

The `akashic-discovery` manifest SHALL declare `dependencies` containing the bare string `akashic-mcp` and MUST NOT declare a version range for it. This change MUST NOT create git tags of the form `<plugin>--v<version>`. The binary release tag scheme `akashic-mcp-v<binary_version>`, used by the MCP wrapper to download the server binary, SHALL remain unchanged.

#### Scenario: Installing discovery pulls in akashic-mcp

- **WHEN** a user with the `akashic` marketplace added runs `claude plugin install akashic-discovery@akashic` without `akashic-mcp` installed
- **THEN** Claude Code installs `akashic-mcp@akashic` as a dependency and both plugins load

#### Scenario: No plugin version tags are introduced

- **WHEN** the change is complete
- **THEN** the repository has no tag whose name contains `--v`, and the binary download still resolves the release tag `akashic-mcp-v<binary_version>`


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
### Requirement: Shared rules through a directory symlink

`plugins/akashic-discovery/rules` SHALL be a symbolic link to `../../plugin/rules`, so every rule file under `plugin/rules/` is reachable from the discovery plugin without being copied.

#### Scenario: Rule reachable through the symlink

- **WHEN** a file is added under `plugin/rules/`
- **THEN** the same file is readable at the corresponding path under `plugins/akashic-discovery/rules/` with no further change


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
### Requirement: Install id migration

After this change the external marketplace `psychquant-claude-plugins` MUST NOT list `akashic-mcp`, and its manifest SHALL declare `renames` mapping `akashic-mcp` to `null`. The external entry SHALL be removed only after the `akashic` marketplace is pushed and `akashic-mcp@akashic` has been installed successfully from it. The README SHALL give the migration steps: add the marketplace from `PsychQuant/Akashic-Library`, install `akashic-mcp@akashic`, and remove the old `akashic-mcp@psychquant-claude-plugins` install.

#### Scenario: Old install id is reported as removed

- **WHEN** a user who installed `akashic-mcp@psychquant-claude-plugins` updates that marketplace after the change
- **THEN** the plugin is shown as removed from that marketplace, and the README's migration steps install `akashic-mcp@akashic`

#### Scenario: No window without an installable source

- **WHEN** the external entry is removed
- **THEN** `akashic-mcp@akashic` had already been installed successfully from the pushed `akashic` marketplace

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