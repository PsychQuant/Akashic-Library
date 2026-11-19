## REMOVED Requirements

### Requirement: The fetch contract version SHALL be 11

**Reason**: The contract version rises to 12 because `fetch` now names its window by `--window-id`, no longer stops on another profile's window, takes `--expect-profile` as optional, and prints the `own-tab:` line the skill reads.

**Migration**: See the added requirement "The fetch contract version SHALL be 12"; rebuild the `akashic` CLI from the merged commit and use safari-browser 2.9.0 or later.

## ADDED Requirements

### Requirement: The fetch contract version SHALL be 12

`akashic fulltext contract` SHALL print `fulltext-contract 12`, and the skill's step 0 SHALL require at least 12. Version 12 SHALL mean that `fetch` names the window chosen at the start by `--window-id` in every position-based command, does not stop because a window of another profile is open, accepts a missing `--expect-profile`, stops before opening anything when safari-browser reports no window ids, and prints an `own-tab:` line; the exit codes of `take`, the hand-over reasons and the pages that pause the whole run are those of version 11.

#### Scenario: Contract printed

- **WHEN** `akashic fulltext contract` runs
- **THEN** it SHALL print `fulltext-contract 12`

##### Example: Skill and CLI agree on contract 12

- **GIVEN** the CLI's contract version and the skill's step-0 threshold
- **WHEN** they are compared
- **THEN** both SHALL be 12
