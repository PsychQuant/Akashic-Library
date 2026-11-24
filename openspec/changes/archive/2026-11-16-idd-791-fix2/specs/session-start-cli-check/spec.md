## MODIFIED Requirements

### Requirement: The CLI probe SHALL keep its temporary files in a private directory and remove the directory

Each probe of the CLI SHALL create one directory with `mktemp -d` under `TMPDIR` (or `/tmp` when `TMPDIR` is unset) and SHALL keep both its output file and its timeout marker inside that directory. When the probe ends — the CLI exits, or the probe's own deadline stops it — and `TMPDIR` is still writable, the check SHALL remove that whole directory, so no `akashic-check-cli.*` entry is left in `TMPDIR`, except in the known cases listed under the timer requirement. The directory is private to the user only against other users who cannot rename entries in `TMPDIR`: a per-user `TMPDIR` or a sticky one such as `/tmp`.

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

### Requirement: The probe's timer SHALL remove the probe's directory when the hook is gone

The probe runs the CLI in its own process group together with an 8-second timer. When the timer fires and the shell that runs the probe is no longer alive, the timer SHALL remove the probe's whole directory, output file included; this is how the output file is removed when the hook is killed. When that shell is still alive, the timer SHALL leave the timeout marker for it to read and SHALL NOT remove the output file. A CLI that exited 0 SHALL be read from its output file whether or not the marker is present; the marker decides only whether a non-zero exit counts as a timeout. The check SHALL stop the probe's process group before it removes the directory. This requirement does not promise that no directory ever remains. Known cases in which the private directory can remain, holding at most the output file and the marker: the shell is killed after the group is stopped and before the directory is removed; the shell is killed after `mktemp -d` and before the timer starts; the shell dies after the timer's check; the shell's process ID is reused; the timer itself is killed; the timer creates its marker while the directory is being removed; `TMPDIR` stops being writable.

#### Scenario: The hook is killed during a probe

- **WHEN** the hook and the shell that runs the probe are killed with SIGKILL while the CLI is still running
- **THEN** the probe's directory SHALL be gone after the timer fires

##### Example: Killing the hook during a probe leaves nothing in TMPDIR after the timer

- **GIVEN** `TMPDIR` is an empty directory and the CLI never answers `--version`
- **WHEN** the hook process and the shell that runs the probe are both killed with SIGKILL while the CLI is running
- **THEN** within 30 seconds `TMPDIR` SHALL contain no entry whose name starts with `akashic-check-cli.`

#### Scenario: The CLI answers 0 and the timer has left its marker

- **WHEN** the CLI exits 0 with its answer in the output file and the timeout marker is present
- **THEN** the check SHALL use the answer and SHALL NOT report a timeout

##### Example: A version answered with 0 is read even when the timer left its mark

- **GIVEN** a CLI whose `--version` creates the timeout marker, prints its version and exits 0
- **WHEN** the check runs
- **THEN** its output SHALL contain the `✓` line with that version and SHALL NOT contain `沒有回應`

##### Example: A contract answered with 0 after the timer's mark does not ask for a rebuild

- **GIVEN** a CLI whose `--version` answers normally and whose `fulltext contract` creates the timeout marker, prints a contract at or above what the skill requires and exits 0
- **WHEN** the check runs
- **THEN** its output SHALL NOT contain `讀不到 akashic CLI 的 fulltext 契約` or `要先重建`

### Requirement: A check that cannot create its temporary directory SHALL say so and SHALL NOT report the CLI as failing

When `mktemp -d` fails, or the probe cannot create its output file in the new directory, the probe SHALL remove anything it created and return 125 without running the CLI, and a CLI that itself exits 125 SHALL be reported as exit 1. When the version probe returns 125, the check SHALL print that the hook could not create its temporary directory or file and name `TMPDIR`, SHALL NOT print the ✓ line and SHALL NOT say that the CLI failed; it SHALL still print the line that the CLI is not on `PATH` when that is so, and then SHALL stop, so it prints no rebuild or install hint. When the contract probe returns 125, the check SHALL print a message that names `TMPDIR` and says the contract was not compared, and SHALL NOT ask for a rebuild because of the contract; the later comparison with the source code runs as before.

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

##### Example: A CLI off PATH is still named when TMPDIR is unusable

- **GIVEN** the CLI exists only as `~/bin/akashic`, not on `PATH`, and `TMPDIR` names a directory that does not exist
- **WHEN** the check runs
- **THEN** its output SHALL mention `TMPDIR` and SHALL say that the CLI is not on `PATH`

##### Example: A TMPDIR that holds the directory but not its output file is reported as the hook's own problem

- **GIVEN** `TMPDIR` is an existing directory whose path is 996 bytes long, so `mktemp -d` can create the probe's directory but the output file's path exceeds `PATH_MAX`, and a CLI that would answer normally
- **WHEN** the check runs
- **THEN** its output SHALL mention `TMPDIR` and SHALL NOT contain `執行 --version 失敗`, `要先重建` or `install -m 755`, the CLI SHALL NOT have been run, and `TMPDIR` SHALL contain no entry whose name starts with `akashic-check-cli.`

### Requirement: The probe's timer SHALL NOT write its marker through an existing entry

When the timer leaves the timeout marker, it SHALL create the marker with an operation that fails when anything already exists at the marker's path and that neither opens nor follows that entry. An existing entry of any kind — a regular file, a directory, a FIFO, a device, or a symbolic link, whether or not the link points to an existing entry — SHALL be left as it is, nothing it points to SHALL be opened or written, and the timer SHALL go on to stop the probe's process group.

#### Scenario: Something already sits at the marker's path

- **WHEN** the timer fires while the probe's shell is alive and a symbolic link is already at the marker's path
- **THEN** the file the link points to SHALL keep its content

##### Example: A symbolic link at the marker's path is not written through

- **GIVEN** a CLI that places a symbolic link to a file with known content at the marker's path and then blocks, and the shell that runs the probe is stopped with SIGSTOP until the timer has fired
- **WHEN** the timer fires
- **THEN** the linked file SHALL still have its original content

##### Example: A FIFO at the marker's path does not stop the timer

- **GIVEN** a CLI that creates a FIFO with no reader at the marker's path and then blocks, and the shell that runs the probe is stopped with SIGSTOP
- **WHEN** the timer fires
- **THEN** the timer SHALL stop the CLI within 40 seconds
