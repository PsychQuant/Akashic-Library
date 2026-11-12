## Purpose

The `sources/` directory holds third-party content addressed by digest. Two gates protect it on every supported platform: placement onto an address never overwrites what is already there, and content is stored only when version control excludes it. This capability states both gates so that a platform port cannot make either of them weaker.

## ADDED Requirements

### Requirement: Placement never overwrites an existing address

On every supported platform, putting a completed temporary file onto its content address SHALL be a single atomic step that fails when the address is already occupied, leaving the occupant's bytes unchanged. On macOS the step is `renamex_np` with `RENAME_EXCL`; on Linux it is `renameat2` with `RENAME_NOREPLACE`, obtained at run time by symbol lookup so that the repository adds no C source.

#### Scenario: The address is already occupied on Linux

- **WHEN** a blob is placed on Linux onto an address that already holds a file
- **THEN** placement SHALL report the address as already occupied, and the occupant's bytes SHALL be unchanged

##### Example: Exclusive rename onto an occupied address

| Filesystem (Linux) | Occupant before | Result | Occupant after |
|---|---|---|---|
| overlayfs `/tmp` | `B` | already occupied (`EEXIST`) | `B` |
| tmpfs `/dev/shm` | `B` | already occupied (`EEXIST`) | `B` |
| any, address free | none | placed | the new content |

### Requirement: Unsupported placement falls back to a hard link, then to a named refusal

When the exclusive rename reports that the filesystem does not support it, placement SHALL try `link(2)`; when that also reports no support, the store SHALL refuse the write by name and SHALL write nothing. The errno values that mean "not supported" are a closed list per call and per platform, and any other errno SHALL be raised as a named error without falling back. On Linux the exclusive rename's list is `ENOTSUP`, `EOPNOTSUPP`, `EINVAL` and `ENOSYS`, and a missing `renameat2` symbol SHALL count as `ENOSYS`; the hard link's list is `ENOTSUP`, `EOPNOTSUPP` and `EPERM`. On macOS both lists are unchanged.

#### Scenario: Fallback decisions on Linux

- **WHEN** the placement calls return the errno values below through the existing test seam
- **THEN** placement SHALL take the action listed

##### Example: Linux placement fallback table

| Exclusive rename returns | Hard link returns | Outcome | Files written |
|---|---|---|---|
| 0 | not called | placed | the blob |
| `EEXIST` | not called | already occupied | none |
| `EINVAL` | 0 | placed by hard link | the blob |
| `ENOSYS` | 0 | placed by hard link | the blob |
| symbol missing | 0 | placed by hard link | the blob |
| `EINVAL` | `EPERM` | named refusal | none |
| `EIO` | not called | named error, no fallback | none |

#### Scenario: The refusal names filesystems that fit the platform

- **WHEN** the store refuses a write because neither call is supported
- **THEN** on Linux the refusal SHALL name `renameat2` and SHALL NOT tell the user to move the store to APFS or HFS+

##### Example: Linux refusal text

- **GIVEN** placement calls that return `EINVAL` and `EPERM` in `swift:6.4.2-noble`
- **WHEN** `store-source` stores a file
- **THEN** the error contains `renameat2` and does not contain `APFS`, and the `sources/` directory contains no new file

### Requirement: An unknown volume capability is decided by a real placement on every write

When the volume's capability flags cannot be read, the store SHALL place an empty temporary file once inside the shard directory before writing the blob, and SHALL refuse the write when that placement is not supported. On Linux the capability is always unknown; the store SHALL NOT keep a list of filesystem types that are assumed capable.

#### Scenario: Linux probes before each write

- **WHEN** a blob is stored on Linux
- **THEN** one probe placement SHALL happen in the shard directory before the blob is placed, and the blob's address SHALL appear in one atomic step with its complete content

##### Example: Rename count on Linux

- **GIVEN** a store on Linux and a new 200-byte file
- **WHEN** `store-source` stores it
- **THEN** exactly one exclusive rename targets the content address, one more targets a probe name in the same shard directory, and no probe name remains afterwards

### Requirement: Content is synced before it is placed

The temporary file SHALL be synced to the storage device before it is placed on its address, and a failed sync SHALL leave the address empty. On macOS the sync is `fcntl(F_FULLFSYNC)`, falling back to `fsync(2)` only when the full sync reports no support; on Linux it is `fsync(2)`.

#### Scenario: A failed sync places nothing

- **WHEN** the sync of the temporary file fails
- **THEN** nothing SHALL be placed on the address and the temporary file SHALL be removed

##### Example: Injected sync failure on Linux

- **GIVEN** a sync seam that returns `EIO` in `swift:6.4.2-jammy`
- **WHEN** `store-source` stores a file
- **THEN** it fails with an error naming the sync, the content address does not exist, and no temporary file remains in the shard directory

### Requirement: The exclusion judgement is never wider than git

The store's judgement that version control excludes `sources/` SHALL NOT report the content as excluded in any case where `git check-ignore` reports one of the probed paths as not excluded. Where the two disagree, the store SHALL refuse. The judgement's negation reach SHALL stay case-insensitive on every platform; on a case-sensitive repository this refuses some layouts that git would accept, and that disagreement is accepted.

#### Scenario: Case-variant negation on a case-sensitive repository

- **WHEN** the `.gitignore` excludes `sources/*` and then negates `!Index.JSONL`, in a repository where `core.ignorecase` is unset on Linux
- **THEN** git SHALL report `sources/index.jsonl` as excluded, and the store SHALL report the rule as negated later and refuse

##### Example: Judgement against git on Linux

| `.gitignore` after the block | `core.ignorecase` | git excludes `sources/index.jsonl` | Store judgement |
|---|---|---|---|
| (none) | unset | yes | present |
| `!Index.JSONL` | unset | yes | rule negated later (refuse) |
| `!Index.JSONL` | `true` | no | rule negated later (refuse) |
