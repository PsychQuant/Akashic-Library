## ADDED Requirements

### Requirement: Store snapshots SHALL carry trusted identity and content revision

StoreIO SHALL expose `StoreIdentity`, `StoreRevision`, `StoreSnapshotID`, and `LibrarySnapshot` as read-only public value shapes. A production `LibrarySnapshot` SHALL be created only by `LibraryStore.loadSnapshot()`. Store identity SHALL come from a strictly parsed store incarnation UUID. Store revision SHALL be a content digest and SHALL NOT be derived from a filesystem path, modification time, `StoreVersion`, Git branch, or Git commit.

#### Scenario: A valid incarnation identifies the store

- **WHEN** `loadSnapshot()` captures a store whose incarnation contains one valid UUID
- **THEN** the snapshot store identity SHALL equal that UUID
- **AND** repeated captures of unchanged content SHALL retain the same store identity

#### Scenario: Missing or malformed incarnation is refused

- **WHEN** the incarnation file is missing, unreadable, empty, or not one UUID
- **THEN** `loadSnapshot()` SHALL throw a typed snapshot error
- **AND** it SHALL NOT fall back to path identity or create an incarnation file

#### Scenario: Git references are not model revisions

- **WHEN** a caller has a Git branch or commit that contains the store files
- **THEN** that Git reference SHALL NOT be accepted as a `StoreRevision`
- **AND** the revision SHALL still be derived from captured canonical bytes

### Requirement: Snapshot decoding and revision SHALL use the same stable capture

`loadSnapshot()` SHALL capture the complete path inventory and raw bytes consumed by `LibraryLoad`, SHALL verify that two consecutive bounded capture passes are identical, and SHALL decode only the accepted in-memory capture. It SHALL NOT reread canonical files after accepting the capture. A changing store that cannot produce two identical consecutive captures within three attempts SHALL be refused.

#### Scenario: One accepted capture drives both digest and model

- **WHEN** canonical content changes after a first capture pass and is stable during the next two passes
- **THEN** `loadSnapshot()` SHALL return a snapshot decoded from the final stable bytes
- **AND** its revision SHALL be computed from those exact bytes

#### Scenario: Persistent drift fails closed

- **WHEN** at least one canonical path or byte sequence changes during every bounded capture attempt
- **THEN** `loadSnapshot()` SHALL throw `changedDuringCapture`
- **AND** it SHALL NOT return a mixed model or a revision for an unaccepted capture

#### Scenario: Existing tolerant load remains available

- **WHEN** a legacy caller invokes `LibraryStore.load()`
- **THEN** its existing load and quarantine behavior SHALL remain available
- **AND** that unbound `LibraryLoad` SHALL NOT itself claim a snapshot identity or revision

### Requirement: Store revision SHALL be deterministic and structurally framed

`StoreRevision.digest` SHALL match `sha256:` followed by 64 lowercase hexadecimal digits. The SHA-256 input SHALL use a versioned domain separator, a record count, globally sorted relative-path UTF-8 bytes, and fixed-width length prefixes for every path and content payload. The captured set SHALL include the presence and bytes of `store.yaml`, the incarnation bytes, and every non-hidden YAML file that the loader enumerates under `entities`, `entries`, `people`, and `libraries`. It SHALL exclude `.akashic`, `sources`, hidden files, and non-YAML files.

#### Scenario: Enumeration order does not affect revision

- **WHEN** two stores have the same incarnation, relative paths, and bytes but their files were created or enumerated in different orders
- **THEN** their store revisions SHALL be equal

#### Scenario: Canonical content changes revision

- **WHEN** one captured canonical YAML byte, relative path, marker byte, or quarantined YAML byte changes
- **THEN** the store revision SHALL change
- **AND** the store identity SHALL remain unchanged when the incarnation UUID is unchanged

#### Scenario: Derived and source content does not change revision

- **WHEN** only `.akashic`, `sources`, a hidden file, or a non-YAML file changes
- **THEN** the store revision SHALL remain unchanged

#### Scenario: Structural framing prevents concatenation collisions

- **WHEN** two path/content record sequences have the same unframed byte concatenation but different record boundaries
- **THEN** their structurally framed digest inputs SHALL differ
- **AND** their store revisions SHALL differ
