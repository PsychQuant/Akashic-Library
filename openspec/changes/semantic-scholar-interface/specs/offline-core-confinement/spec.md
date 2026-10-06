## Purpose

Akashic's core stays offline: only the `AkashicS2` target may use networking or keychain APIs. A guard checks this mechanically on every guard run, and a mutation control proves the guard fires. The guard is a closed lexical list: it catches a later change that spells one of the listed patterns outside `AkashicS2`. It does not prove that no other path exists (a subprocess, a dynamically loaded API, or a pattern not on the list); those are for code review, and a new pattern is added to the list when one is found.

## ADDED Requirements

### Requirement: Networking and keychain APIs are confined to AkashicS2

Outside `Sources/AkashicS2/`, no Swift file under `Sources/` SHALL contain any of these patterns, comments included:

- networking: `URLSession`, `URLRequest`, `NWConnection`, `import Network`, `/usr/bin/curl`
- keychain: `import Security`, `SecItem`, `import LocalAuthentication`, `/usr/bin/security`

This list is closed. A new pattern SHALL be added as an explicit list entry; it SHALL NOT be derived by similarity to an existing entry. The only files exempt from the scan are the guard's own two files, `Sources/akashic-guards/NetworkConfinement.swift` and `Sources/akashic-guards/NetworkConfinementMutations.swift`, because they spell the patterns out.

#### Scenario: The current tree passes

- **WHEN** `akashic-guards network-confinement` runs on a tree where these patterns appear only under `Sources/AkashicS2/` and in the two exempt files
- **THEN** it SHALL exit 0

#### Scenario: A networking call outside AkashicS2 is caught

- **GIVEN** a file under `Sources/AkashicCore/` that contains `URLSession.shared`
- **WHEN** `akashic-guards network-confinement` runs
- **THEN** it SHALL exit non-zero and SHALL name that file, the line, and the matched pattern

#### Scenario: A comment mentioning a keychain API is caught

- **GIVEN** a comment reading `// uses SecItemCopyMatching` in `Sources/akashic/CLI.swift`
- **WHEN** `akashic-guards network-confinement` runs
- **THEN** it SHALL exit non-zero and SHALL name that line

### Requirement: The guard runs with the other guards

`.githooks/run-guards.sh` SHALL run `akashic-guards network-confinement` and `akashic-guards network-confinement-mutations`, and a failure of either SHALL fail the guard run.

#### Scenario: A violation blocks the guard run

- **GIVEN** a file outside `Sources/AkashicS2/` that contains `import Network`
- **WHEN** `.githooks/run-guards.sh` runs
- **THEN** it SHALL exit non-zero

### Requirement: A mutation control proves the guard fires

`akashic-guards network-confinement-mutations` SHALL copy the scanned sources into a temporary directory, and SHALL confirm there that:

1. the unmodified copy passes;
2. each pattern in the closed list, injected into a file outside `Sources/AkashicS2/`, makes the guard fail;
3. the same pattern placed under `Sources/AkashicS2/` does not make the guard fail.

It SHALL exit non-zero if any of these outcomes differs, and SHALL NOT modify the working tree.

#### Scenario: Every pattern is exercised

- **WHEN** `akashic-guards network-confinement-mutations` runs
- **THEN** it SHALL report one failing mutation for each of the nine patterns, one passing placement under `Sources/AkashicS2/`, and a passing unmodified copy, and it SHALL exit 0
