## REMOVED Requirements

### Requirement: The fetch contract version SHALL be 10

**Reason**: The contract version rises to 11 because the skill now depends on the `fulltext attempt` command, which only a version 11 CLI has.

**Migration**: See the added requirement "The fetch contract version SHALL be 11"; rebuild the `akashic` CLI from the merged commit.

## ADDED Requirements

### Requirement: The fetch contract version SHALL be 11

`akashic fulltext contract` SHALL print `fulltext-contract 11`, and the skill's step 0 SHALL require at least 11. Version 11 SHALL mean that the CLI has the `fulltext attempt` command; the exit codes of `fetch` and `take` are those of version 10.

#### Scenario: Contract printed

- **WHEN** `akashic fulltext contract` runs
- **THEN** it SHALL print `fulltext-contract 11`

##### Example: Skill and CLI agree on contract 11

- **GIVEN** the CLI's contract version and the skill's step-0 threshold
- **WHEN** they are compared
- **THEN** both SHALL be 11
