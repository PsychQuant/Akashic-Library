## Purpose

AkashicKit builds and tests on Linux (Ubuntu 22.04 and 24.04) as an additional check beside macOS, so that build and test work can run on Linux machines. Behaviour that the store depends on is identical on both platforms, capabilities that exist only on macOS fail on Linux with a named error, and every test skipped on Linux is on an audited list.

## ADDED Requirements

### Requirement: The package builds on the supported Linux platforms

The package SHALL build every target except `AkashicAppKit`, `AkashicAppKitTests` and `UnicodeNormalizationGenerator` on Ubuntu 22.04 and Ubuntu 24.04 with the official Swift 6.4 toolchain, with warnings treated as errors. The three excluded targets SHALL NOT be declared when the manifest is evaluated on Linux, and SHALL be declared unchanged on macOS. The supported Linux images are `swift:6.4.2-jammy` and `swift:6.4.2-noble`, referenced by their multi-architecture index digests.

#### Scenario: Clean build in both images

- **WHEN** the package is built from an empty build directory in each supported image with warnings treated as errors
- **THEN** the build SHALL succeed with no error and no warning

##### Example: Clean build on both Ubuntu images

| Image | Index digest | Command | Expected |
|---|---|---|---|
| `swift:6.4.2-noble` | `sha256:23d9b28ad97fb1cf1999edc3a0cb265ee915ed42299a9344e7173d5a6d2b05f4` | `swift build --build-tests --force-resolved-versions -Xswiftc -warnings-as-errors` | exit 0, zero `warning:` lines |
| `swift:6.4.2-jammy` | `sha256:18a1cdd3e55ee32b0b3e1a15f12a4e1320b67544e542ed96c907629e5e434144` | same | exit 0, zero `warning:` lines |

#### Scenario: Targets declared per platform

- **WHEN** the manifest is evaluated
- **THEN** the set of declared targets SHALL differ between macOS and Linux by exactly the three excluded targets

##### Example: Targets declared on Linux and macOS

- **GIVEN** the package at the change's final commit
- **WHEN** `swift package dump-package` runs on macOS and in `swift:6.4.2-noble`
- **THEN** the macOS output lists `AkashicAppKit`, `AkashicAppKitTests` and `UnicodeNormalizationGenerator`, the Linux output lists none of them, and every other target name appears in both

### Requirement: Linux builds refuse a Swift compiler older than 6.4

On Linux, a module that writes store records SHALL fail to compile under a Swift compiler older than 6.4, with a compile-time error that names the minimum version. Swift 6.0.3 for Linux replaces an existing file with `FileManager.replaceItemAt` by deleting the destination, so a build with it would delete store records on their first overwrite; Swift 6.4.2 is the only Linux toolchain measured to replace correctly. A toolchain that cannot resolve the package's dependencies is refused earlier, at resolution.

#### Scenario: An old compiler is refused

- **WHEN** the package is built on Linux with a Swift compiler older than 6.4
- **THEN** the build SHALL stop before any binary is produced, either at dependency resolution or with a compile-time error that names Swift 6.4 as the minimum

##### Example: Older Linux toolchains are refused

| Image | Where the build stops | Output contains |
|---|---|---|
| `swift:6.0.3-noble` | dependency resolution (swift-crypto 4.5.2 declares tools version 6.1) | `6.1` |
| any official 6.1, 6.2 or 6.3 image | compiling `AkashicStoreIO` | `Swift 6.4` and `#794` |

- No executable check: CI pins Swift 6.4.2 only; both rows are verified once by hand when the guard is added, and the output is recorded in the task

#### Scenario: Overwriting a record keeps it on Linux

- **WHEN** an existing store record is overwritten on Linux with Swift 6.4.2
- **THEN** the record SHALL hold the new content and no temporary file SHALL remain

##### Example: Record overwrite on Linux

- **GIVEN** a store with a person record `doe-jane` holding the name `Jane Doe`
- **WHEN** the record is rewritten with the name `Doe, Jane` in `swift:6.4.2-jammy`
- **THEN** reading the record returns `Doe, Jane`, and the entities directory contains no file whose name contains `.tmp-`

### Requirement: One lockfile serves both platforms

The package SHALL resolve to a single `Package.resolved` on macOS and on Linux. Dependencies used only on Linux SHALL be declared for every platform, with their products attached to targets only on Linux. Linux CI SHALL resolve with the lockfile read-only and SHALL fail when the lockfile would change.

#### Scenario: Resolving on either platform leaves the lockfile unchanged

- **WHEN** the committed lockfile is resolved on macOS, and separately on Linux with resolved versions forced
- **THEN** the lockfile bytes SHALL be unchanged in both cases

##### Example: Lockfile unchanged after Linux resolve

- **GIVEN** the committed `Package.resolved` with SHA-256 digest `D`
- **WHEN** `swift package resolve --force-resolved-versions` runs in `swift:6.4.2-noble`, and `swift package resolve` runs on macOS
- **THEN** the digest of `Package.resolved` is `D` after each run, and `git diff --exit-code Package.resolved` exits 0

#### Scenario: Linux-only products are not compiled on macOS

- **WHEN** the package is built on macOS
- **THEN** no object file of the Linux-only products SHALL be produced and macOS SHALL link the system `SQLite3` and `CryptoKit`

##### Example: macOS build contains no Linux-only product

- **GIVEN** a macOS debug build of every target
- **WHEN** the build directory is searched for files whose names contain `SwiftToolchainCSQLite` or `CCryptoBoringSSL`
- **THEN** none are found

### Requirement: macOS behaviour is unchanged

On macOS, the build with warnings treated as errors, the full test suite, the guards and the pre-push hook SHALL pass as they did before this change. The Unicode table generator's source SHALL stay byte-identical so that its pinned digest stays valid.

#### Scenario: macOS suite and guards pass

- **WHEN** the macOS build, test suite, guards and pre-push hook run at the change's final commit
- **THEN** each SHALL exit 0

##### Example: Generator digest pin stays valid

- **GIVEN** the generator source `Tools/UnicodeNormalizationGenerator/main.swift` at commit `8fc7fc0b` with SHA-256 `c52fe7f7f1c209d14973ab1461df4cb8195a640dc9a0dd4ae7be6baf60cd5c6f`
- **WHEN** `ExpressionConstructionTests/testUnicodeV1TrustChainAndOfficialConformanceArePinned` runs on macOS at the change's final commit
- **THEN** the generator's SHA-256 is still `c52fe7f7f1c209d14973ab1461df4cb8195a640dc9a0dd4ae7be6baf60cd5c6f` and the test passes

### Requirement: macOS-only capabilities fail with a named platform error on Linux

The keychain read used by the Semantic Scholar commands and the Safari-driven full-text fetch exist only on macOS. On Linux, their commands and options SHALL remain present, and using them SHALL fail with an error that states the capability exists only on macOS. The error SHALL NOT instruct the user to run the macOS `security` command, SHALL be raised before any network request, and SHALL be raised before any file is written.

#### Scenario: Semantic Scholar on Linux

- **WHEN** an `akashic s2` subcommand or the `akashic_s2` MCP tool needs the key on Linux
- **THEN** it SHALL fail with the platform error, send no request, and the CLI and MCP faces SHALL report the same text

##### Example: S2 key read on Linux

- **GIVEN** `swift:6.4.2-jammy`, a non-root user, and `AKASHIC_S2_BASE_URL` unset (a loopback base URL never reads the keychain)
- **WHEN** `akashic s2 paper DOI:10.1037/a0038889` runs
- **THEN** it exits 3, its message contains `macOS` and `keychain`, and it does not contain `security add-generic-password`
- **AND** an in-process `S2Client` aimed at the Semantic Scholar host, with a session that records requests, throws the platform error and records zero requests

##### Example: S2 status on Linux

- **GIVEN** `swift:6.4.2-jammy`
- **WHEN** `akashic s2 status` runs
- **THEN** the key line reports that the keychain is unavailable on this platform, not that the item is absent, and the command exits 3

#### Scenario: Full-text fetch on Linux

- **WHEN** `akashic fulltext fetch` runs on Linux
- **THEN** it SHALL fail with the platform error before resolving its attempt ledger and before starting any process

##### Example: Fetch writes nothing on Linux

- **GIVEN** `swift:6.4.2-noble` and a `--ledger` path that does not exist
- **WHEN** `akashic fulltext fetch --window 1 --landing https://doi.org/10.1234/abc --expect-profile p --ledger <path>` runs
- **THEN** it exits 1, its message names macOS and Safari, and `<path>` still does not exist

### Requirement: Line splitting is identical on both platforms

Every split of text into lines under `Sources/` SHALL go through one shared function whose result equals the result of `components(separatedBy: "\n")` on macOS, byte for byte: it splits at each U+000A, keeps every U+000D, and keeps empty fields. `akashic-guards`, which has no dependencies, SHALL carry its own copy, and the two copies SHALL be checked against the same table. No file under `Sources/` other than the splitter's own documentation SHALL call `components(separatedBy: "\n")`.

#### Scenario: CRLF input is split the same way

- **WHEN** text containing CRLF line endings is split on Linux and on macOS
- **THEN** both platforms SHALL return the same array

##### Example: Line splitting table

| Input | Expected |
|---|---|
| `"a\nb"` | `["a", "b"]` |
| `"a\r\nb\r\n"` | `["a\r", "b\r", ""]` |
| `"a\rb"` | `["a\rb"]` |
| `""` | `[""]` |
| `"\n"` | `["", ""]` |
| `"é\n日"` | `["é", "日"]` |
| `"a\u{2028}b"` | `["a\u{2028}b"]` |

##### Example: No direct newline split remains

- **GIVEN** the tree at the change's final commit
- **WHEN** the source-scan test counts `components(separatedBy: "\n")` under `Sources/`
- **THEN** the count is 0

### Requirement: JSON scalar types are classified identically on both platforms

Values decoded by `JSONSerialization` SHALL be classified as boolean, integer, non-integer number or other by one shared function that gives the same answer on macOS and Linux. Every check under `Sources/` that uses CoreFoundation type identity (`CFGetTypeID`, `CFBooleanGetTypeID`, `CFNumberIsFloatType`) to tell a JSON boolean from a JSON number SHALL use it instead. Checks written with `is Bool` are out of scope: `is Bool` is true for the JSON numbers `0`, `1` and `1.0` on macOS as well as on Linux, so they already behave the same on both platforms.

#### Scenario: Booleans and numbers are told apart on Linux

- **WHEN** JSON containing `true`, `0`, `1` and `1.0` is decoded on Linux
- **THEN** only `true` SHALL be classified as boolean

##### Example: JSON scalar table

| JSON text | Classification |
|---|---|
| `true` | boolean |
| `false` | boolean |
| `0` | integer 0 |
| `1` | integer 1 |
| `-3` | integer -3 |
| `1.0` | non-integer number |
| `1e3` | non-integer number |
| `18446744073709551617` | integer out of range |
| `"1"` | other |

### Requirement: The deletability check reads the immutable and append-only flags on Linux

Before a divergence merge deletes files, the check that a file can be deleted SHALL, on Linux, treat a file whose `FS_IOC_GETFLAGS` flags include `FS_IMMUTABLE_FL` or `FS_APPEND_FL` as undeletable. When the flags cannot be read, the check SHALL treat the file as carrying no flag, which is the macOS behaviour when the immutable attribute cannot be read. The parent-directory permission check SHALL be unchanged on both platforms.

#### Scenario: Flag decoding

- **WHEN** the deletability check reads a file's flags on Linux
- **THEN** it SHALL decide by the two flags only

##### Example: Linux flag table

| Flags read | Deletable |
|---|---|
| `0x00000000` | yes |
| `0x00080000` (extents only) | yes |
| `0x00000010` (immutable) | no |
| `0x00000020` (append-only) | no |
| read fails with `ENOTTY` | yes |

#### Scenario: A read-only parent directory stops a merge on both platforms

- **WHEN** a divergence merge would delete a file whose parent directory is not writable
- **THEN** the merge SHALL delete nothing and SHALL name the file

##### Example: Read-only parent directory

- **GIVEN** a doomed record file inside a directory with mode `0555`, run as a non-root user
- **WHEN** the merge is applied
- **THEN** every record file is byte-identical to before and the error names the doomed file

### Requirement: The plugin's CLI check hook works with GNU and BSD userlands

The shell hook that compares the installed CLI with the plugin SHALL read a file's modification time and link count with commands that work on both GNU coreutils and BSD.

#### Scenario: Hook on Linux

- **WHEN** the hook compares file times on Linux
- **THEN** it SHALL read the modification time and reach the same decision as on macOS

##### Example: Hook tests on both userlands

- **GIVEN** `swift:6.4.2-noble`, `swift:6.4.2-jammy` and macOS
- **WHEN** `CheckCLIHookTests` runs
- **THEN** every test passes, including `testUnknownVersionComparesFileTimes` and `testSignatureDisplayNeitherRunsGpgNorHidesStaleness`

### Requirement: Tests skipped on Linux equal an audited list

A test that can run only on macOS SHALL skip itself individually on Linux with a reason, so that the Linux test output counts every skipped test. The set of tests skipped in a Linux CI run SHALL equal the set listed in `Tests/linux-skipped-tests.txt`, where each entry names the test, a category (`macos-only` or `environment`) and a reason. `akashic-guards linux-skip-audit` SHALL compare the two sets and SHALL fail on any difference in either direction.

#### Scenario: The skip count is truthful

- **WHEN** the test suite runs on Linux
- **THEN** each skipped test SHALL appear once in the output with its reason, and the number of skipped tests SHALL equal the number of entries in the list

##### Example: A new unlisted skip fails the audit

- **GIVEN** a Linux test log in which `FooTests/testBar` is reported skipped, and a list that does not contain it
- **WHEN** `akashic-guards linux-skip-audit --log <log> --list Tests/linux-skipped-tests.txt` runs
- **THEN** it exits non-zero and names `FooTests/testBar` as skipped but not listed

##### Example: A listed test that ran fails the audit

- **GIVEN** a list containing `IndexIdentityTests/testIsCurrentAcceptsOwnIndexIncludingPathAliases` and a log in which that test passed
- **WHEN** `akashic-guards linux-skip-audit` runs
- **THEN** it exits non-zero and names the test as listed but not skipped

##### Example: Mutation control for the skip audit

- **WHEN** `akashic-guards linux-skip-audit-mutations` runs
- **THEN** the unmodified fixture passes, an added unlisted skip fails, a removed listed skip fails, an entry without a category or reason fails, and the command exits 0

### Requirement: akashic-guards stays dependency-free and platform-independent

`akashic-guards` SHALL have no package dependency, and its output SHALL be the same on macOS and Linux for the same tree. Its SHA-256 SHALL be its own implementation, checked against published test vectors and, on macOS, against CryptoKit.

#### Scenario: Guard hashing

- **WHEN** the guard hashes bytes
- **THEN** it SHALL return the standard SHA-256 digest

##### Example: SHA-256 test vectors

| Input | SHA-256 |
|---|---|
| empty | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `abc` | `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad` |
| `abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq` | `248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1` |
| 1,000,000 × `a` | `cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0` |

### Requirement: Linux CI builds and tests both Ubuntu versions as a non-root user

A GitHub Actions workflow SHALL build and test the package in both supported images, referenced by digest. It SHALL build and run the tests as one non-root user who owns the checked-out tree, SHALL pass `--force-resolved-versions` to both the build and the test run and fail if the lockfile has changed after the tests, SHALL check out submodules, and SHALL run `akashic-guards linux-skip-audit` on the test output. Its actions SHALL be pinned to commit SHAs and SHALL NOT persist credentials.

#### Scenario: Workflow structure

- **WHEN** the workflow file is read
- **THEN** it SHALL contain one job per image with the image digest, a non-root build and test step, the lockfile check and the skip audit

##### Example: Static check of the Linux workflow

- **GIVEN** `.github/workflows/linux.yml`
- **WHEN** the workflow source-scan test reads it
- **THEN** it finds both index digests, `--force-resolved-versions`, `git diff --exit-code Package.resolved`, `linux-skip-audit`, `persist-credentials: false`, and no build or test step run as root
