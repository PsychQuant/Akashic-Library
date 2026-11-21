## MODIFIED Requirements

### Requirement: The skill SHALL require the window-id contract

The fetch-fulltext skill SHALL require fulltext contract 13 in its step 0 and safari-browser 2.9.0 or later, SHALL describe the lock by window id, and SHALL NOT keep the other-profile stop.

#### Scenario: The skill matches the CLI

- **WHEN** the skill file is read
- **THEN** it SHALL name the window-id lock and the minimum safari-browser version, and SHALL NOT name the other-profile stop

##### Example: The skill names the window-id lock

| Text searched in SKILL.md | Expected |
| --- | --- |
| `--window-id` | present |
| `2.9.0` | present |
| `a Safari window of another profile` | absent |
| `-ge 13` | present |
