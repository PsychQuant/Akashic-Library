## REMOVED Requirements

### Requirement: The fetch contract version SHALL be 12

**Reason**: The contract version rises to 13 because the CLI gains `akashic fulltext same-target`, which the skill's landing block calls after every click that adds a tab, and because the stderr hint of the `tab-unchanged` hand-over changed.

**Migration**: See the added requirement "The fetch contract version SHALL be 13"; rebuild the `akashic` CLI from the merged commit.

## ADDED Requirements

### Requirement: The fetch contract version SHALL be 13

`akashic fulltext contract` SHALL print `fulltext-contract 13`, and the skill's step 0 SHALL require at least 13. Version 13 SHALL mean that the CLI has the read-only subcommand `fulltext same-target` (see the capability `fulltext-division-of-labour`) and that the `tab-unchanged` hint of `fetch` tells the model to judge the landing as the skill says; the exit codes and stdout lines of `fetch`, `take` and `attempt`, the hand-over reasons and the pages that pause the whole run are those of version 12.

#### Scenario: Contract printed

- **WHEN** `akashic fulltext contract` runs
- **THEN** it SHALL print `fulltext-contract 13`

##### Example: Skill and CLI agree on contract 13

- **GIVEN** the CLI's contract version and the skill's step-0 threshold
- **WHEN** they are compared
- **THEN** both SHALL be 13

##### Example: The tab-unchanged hint points to the landing table

- **GIVEN** a `fetch` run that ends with the hand-over reason `tab-unchanged`
- **WHEN** its stderr is read
- **THEN** it SHALL contain `Following the link was the click: do not click it again` and `judge what happened as the skill's landing table says`, and SHALL NOT contain `wait once and then hand the item to the person`
