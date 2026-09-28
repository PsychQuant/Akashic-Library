## ADDED Requirements

### Requirement: Dismissing a question SHALL delete only its record

A recorded identity question MAY be dismissed without being resolved — because the question does not hold, its candidates were recorded in error, or it can no longer be carried forward (for example, a shape whose merge is not implemented). Dismissal SHALL delete the record of the question and SHALL NOT delete, merge, or rewrite any candidate entity or any reference to one. Nothing in the store references a divergence record, so deleting it leaves no dangling reference; the prohibition on deleting a record without rewriting its references concerns merged candidate entities and does not apply to the record of the question.

Dismissal SHALL require a reason. The reason SHALL appear in the dismissal report and SHALL NOT be written into the store; the store format SHALL NOT change.

Before deleting, dismissal SHALL verify that the record's file is tracked by version control with no uncommitted changes, so that the deleted record survives in version-control history. Where it cannot be verified, dismissal SHALL refuse, SHALL name the reason, and SHALL delete nothing.

Dismissal SHALL offer a dry run that reports what would be deleted and writes nothing. Dismissal SHALL be offered on both the command-line and the MCP surface with the same contract.

#### Scenario: Dismissal deletes the record and nothing else

- **WHEN** a recorded question naming two person candidates is dismissed with a reason
- **THEN** the record of the question SHALL NOT exist
- **AND** both candidate person records SHALL still exist, unchanged
- **AND** the report SHALL contain the reason in full

#### Scenario: Dismissal requires a reason

- **WHEN** dismissal is attempted with an empty or whitespace-only reason
- **THEN** it SHALL refuse
- **AND** no file SHALL have been deleted

#### Scenario: Dismissal refuses an uncommitted record

- **WHEN** dismissal is attempted on a record whose file has uncommitted changes, or on a store outside a version-controlled working tree
- **THEN** it SHALL refuse and name why the record cannot be recovered
- **AND** no file SHALL have been deleted

#### Scenario: Dry run writes nothing

- **WHEN** dismissal is run as a dry run
- **THEN** the report SHALL name the record that would be deleted
- **AND** no file SHALL have been deleted
