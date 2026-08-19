## ADDED Requirements

### Requirement: A destructive command SHALL NOT act on a store the caller did not name

A command that rewrites or deletes stored records SHALL refuse to act unless the caller
has named the target store for that invocation, or has stated that the resolved target is
accepted.

Resolution of the target SHALL NOT depend on the directory the command is run from. A
caller working in an unrelated directory SHALL NOT be given the impression that the
operation is confined to that directory.

#### Scenario: A destructive command is run without naming a store

- **GIVEN** a caller in a directory that is not part of any registered store
- **WHEN** the caller asks a destructive command to write
- **THEN** the command SHALL refuse, and the refusal SHALL name the store that would
  otherwise have been written to

#### Scenario: The caller names the store

- **GIVEN** a caller who names the target store for the invocation
- **WHEN** the caller asks a destructive command to write
- **THEN** the command SHALL proceed against the named store

#### Scenario: The caller accepts the resolved target

- **GIVEN** a caller who does not name a store but states that the resolved target is
  accepted
- **WHEN** the caller asks a destructive command to write
- **THEN** the command SHALL proceed, and SHALL report the target it acted on

#### Scenario: A non-destructive command is run without naming a store

- **GIVEN** any command that only reads
- **WHEN** it is run without a named store
- **THEN** it SHALL proceed as before, because reading the wrong store yields a wrong
  answer rather than damaged records

### Requirement: The set of destructive commands SHALL be enumerated, not inferred

Which commands are destructive SHALL be recorded as a closed list. A command SHALL NOT be
treated as destructive because it resembles one, and SHALL NOT escape the gate because no
one remembered to classify it.

Adding a command that rewrites or deletes stored records SHALL require adding it to that
list in the same change.

#### Scenario: A new destructive command is added without being listed

- **GIVEN** a command that offers to write over stored records
- **WHEN** it is not present in the enumerated list
- **THEN** the omission SHALL be detectable mechanically, rather than depending on review

##### Example: Why enumeration rather than a naming rule

- **GIVEN** a rule that treats any command whose name begins with `migrate` as destructive
- **WHEN** a destructive command is named `rename` or `resolve-divergence`
- **THEN** the rule admits it silently, so the classification SHALL be a list that names
  each command rather than a pattern that guesses
