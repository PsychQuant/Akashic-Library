# session-start-cli-check Specification

## Purpose

The akashic-mcp plugin runs a SessionStart check (`plugin/hooks/check-cli.sh`) that probes the `akashic` CLI for its version and fulltext contract. This capability records where that probe keeps its temporary files, how they are removed, and what the check says when it cannot create them.

## Requirements

### Requirement: The CLI probe SHALL keep its temporary files in a private directory and remove the directory

Each probe of the CLI SHALL create one directory with `mktemp -d` under `TMPDIR` (or `/tmp` when `TMPDIR` is unset) and SHALL keep both its output file and its timeout marker inside that directory. When the probe ends — the CLI exits, or the probe's own deadline stops it — the check SHALL remove that whole directory, so no `akashic-check-cli.*` entry is left in `TMPDIR`.

#### Scenario: Probes leave nothing behind

- **WHEN** the check probes a CLI that answers normally, or a CLI that hangs until the probe's deadline stops it
- **THEN** no entry whose name starts with `akashic-check-cli.` SHALL remain in `TMPDIR` after the check exits

##### Example: A normal probe leaves nothing in TMPDIR

- **GIVEN** `TMPDIR` is an empty directory and the CLI prints its version and a fulltext contract at or above what the skill requires
- **WHEN** the check runs to the end
- **THEN** `TMPDIR` SHALL contain no entry whose name starts with `akashic-check-cli.`

##### Example: A timed-out probe leaves nothing in TMPDIR

- **GIVEN** `TMPDIR` is an empty directory and the CLI never answers `--version`
- **WHEN** the check runs to the end and reports that the CLI did not answer
- **THEN** `TMPDIR` SHALL contain no entry whose name starts with `akashic-check-cli.`

---
### Requirement: The probe's timer SHALL remove the probe's directory when the hook is gone

The probe runs the CLI in its own process group together with an 8-second timer. When the timer fires it SHALL first remove the probe's output file; then, if the shell that runs the probe is no longer alive, it SHALL remove the probe's whole directory, and otherwise it SHALL leave the timeout marker for that shell to read. A directory MAY still remain only when that shell dies after the timer's check and before it removes the directory, or when its process ID has been reused.

#### Scenario: The hook is killed during a probe

- **WHEN** the hook and the shell that runs the probe are killed with SIGKILL while the CLI is still running
- **THEN** the probe's directory SHALL be gone after the timer fires

##### Example: Killing the hook during a probe leaves nothing in TMPDIR after the timer

- **GIVEN** `TMPDIR` is an empty directory and the CLI never answers `--version`
- **WHEN** the hook process and the shell that runs the probe are both killed with SIGKILL while the CLI is running
- **THEN** within 30 seconds `TMPDIR` SHALL contain no entry whose name starts with `akashic-check-cli.`

---
### Requirement: A check that cannot create its temporary directory SHALL say so and SHALL NOT report the CLI as failing

When `mktemp -d` fails, the probe SHALL return 125 without running the CLI, and a CLI that itself exits 125 SHALL be reported as exit 1. When the version probe returns 125, the check SHALL print that the hook could not create its temporary directory and name `TMPDIR`, SHALL NOT print the ✓ line, SHALL NOT say that the CLI failed, and SHALL stop there, so it prints no rebuild or install hint. When the contract probe returns 125, the check SHALL print a message that names `TMPDIR` and says the contract was not compared, and SHALL NOT ask for a rebuild because of the contract; the later comparison with the source code runs as before.

#### Scenario: TMPDIR points at a missing directory

- **WHEN** `TMPDIR` names a directory that does not exist
- **THEN** the check SHALL report its own temporary-directory problem and SHALL NOT report the CLI as failing

##### Example: A missing TMPDIR is reported as the hook's own problem

- **GIVEN** `TMPDIR` names a directory that does not exist, and a CLI that would answer normally
- **WHEN** the check runs
- **THEN** its output SHALL mention `TMPDIR`, SHALL NOT contain `✓`, `執行 --version 失敗`, `要先重建` or `install -m 755`, and the CLI SHALL NOT have been run

##### Example: A CLI that exits 125 is reported as exit 1

- **GIVEN** a CLI whose `--version` exits 125 and a `TMPDIR` the hook can write to
- **WHEN** the check runs
- **THEN** its output SHALL say that `--version` failed with exit 1 and SHALL NOT contain the temporary-directory message

##### Example: A contract probe that cannot create its directory does not ask for a rebuild

- **GIVEN** a CLI whose `--version` answers normally and, while answering, makes `TMPDIR` unwritable
- **WHEN** the check probes the fulltext contract
- **THEN** its output SHALL contain the `✓` line and a message that names `TMPDIR` and says the contract was not compared, and SHALL NOT contain `讀不到 akashic CLI 的 fulltext 契約` or `要先重建`
