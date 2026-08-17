## MODIFIED Requirements

### Requirement: Shape labels SHALL be drawn from a closed set

The closed set of recognized top-level entity shape labels SHALL be `work:`, `person:`, `organization:`, `divergence:`, and `venue:` (added by this change). A file under `entities/` whose first line is not one of these labels SHALL NOT be silently skipped by any enumeration path; the behavior (quarantine with report) SHALL be uniform across CLI, MCP, and App read surfaces.

#### Scenario: Venue label is recognized by enumeration

- **GIVEN** a store containing a valid `venue:` file
- **WHEN** any read surface enumerates entities
- **THEN** the venue record is decoded and counted, not skipped

#### Scenario: Unrecognized label is surfaced, not skipped

- **GIVEN** a file under `entities/` whose first line is `series:`
- **WHEN** enumeration runs
- **THEN** the file is reported as unrecognized (quarantine report), not silently omitted from counts
