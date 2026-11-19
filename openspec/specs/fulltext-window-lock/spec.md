# fulltext-window-lock Specification

## Purpose

TBD - created by archiving change 'idd-772-fetch-window-id'. Update Purpose after archive.

## Requirements

### Requirement: The fetch command SHALL lock every position-based action to the window chosen at the start

`akashic fulltext fetch` SHALL read, before opening anything, the stable id of the window that `--window N` names at that moment, and SHALL name that window by `--window-id <id>` in every later command that names a window: the new tab (`open --new-tab --window-id <id>`) and every position lock (`--window-id <id> --tab-in-window <T>`). It SHALL NOT send `--window <N>` to safari-browser. The mark lock (`--profile <P> --url-endswith '#akashic-…'`) and the stop when the new tab went to another window SHALL stay.

#### Scenario: Commands name the window by its id

- **WHEN** fetch runs with a page that keeps the mark and with a page that drops it
- **THEN** the new tab and every position-locked command SHALL carry `--window-id` and none SHALL carry `--window`

##### Example: The new tab is opened by window id

- **GIVEN** a Safari window 5 whose id is 9005
- **WHEN** fetch runs with `--window 5`
- **THEN** the new tab SHALL be opened with `open --new-tab --window-id 9005`

##### Example: Position locks carry the window id

- **GIVEN** an article page that drops the mark after the redirect
- **WHEN** fetch runs to its hand-over
- **THEN** every command with `--tab-in-window` SHALL also carry `--window-id 9005`, and no command SHALL carry `--window`

#### Scenario: A raised window does not move the target

- **WHEN** another window comes to the front between a look and the next command
- **THEN** that command SHALL still reach the window chosen at the start

##### Example: A window raised between a look and a command does not change the target

- **GIVEN** an article page that drops the mark, and window 5 (id 9005) becomes window 6 right before a position-locked read
- **WHEN** fetch runs
- **THEN** it SHALL end with exit 7 and the read SHALL have carried `--window-id 9005`

---
### Requirement: The fetch command SHALL NOT stop because a window of another profile is open

`akashic fulltext fetch` SHALL NOT stop, at the start, on a resume, or during the run, because a Safari window of another profile, or a window whose profile cannot be read, is open. It SHALL NOT print that profile's name or that window's addresses.

#### Scenario: Another profile's window is not a stop

- **WHEN** a window of another profile is open at the start, on a resume, or opens during the run
- **THEN** fetch SHALL go on as it would with no such window

##### Example: Another profile's window at the start does not stop the run

- **GIVEN** window 5 of profile `own` and window 6 of profile `someone-else` showing a mail page
- **WHEN** fetch runs on window 5
- **THEN** it SHALL end with exit 7, and neither `someone-else` nor the mail address SHALL appear in its output

##### Example: Another profile's window does not stop a resume

- **GIVEN** a resume on window 5 while a window of profile `someone-else` is open
- **WHEN** fetch resumes
- **THEN** it SHALL NOT print `a Safari window of another profile`

##### Example: Another profile's window opened mid-run does not stop the run

- **GIVEN** a window of profile `someone-else` that opens after the fourth look
- **WHEN** fetch runs
- **THEN** it SHALL end with exit 7

---
### Requirement: The profile SHALL only choose the window

`--expect-profile` SHALL be optional. When it is given, fetch SHALL compare it with the window's profile once, before opening anything, and SHALL refuse a window of another profile or one whose profile cannot be read. When it is not given, a window whose profile cannot be read SHALL be usable; the mark lock needs the profile, so such a window is locked by position.

#### Scenario: The profile check happens only at the start

- **WHEN** fetch is run with or without `--expect-profile`
- **THEN** the flag SHALL be accepted when absent, and a mismatch SHALL be refused before anything is opened

##### Example: The expected profile can be omitted

- **GIVEN** the `akashic` CLI
- **WHEN** `fulltext fetch --window 5 --landing https://doi.org/10.1/x` is run against a stub safari-browser that lists no window
- **THEN** it SHALL NOT exit 64, and it SHALL say that window 5 was not found

##### Example: A window of another profile is refused when a profile is expected

- **GIVEN** window 5 of profile `own`
- **WHEN** fetch runs with `--expect-profile someone-else`
- **THEN** it SHALL exit 1 before opening any tab

##### Example: A window whose profile cannot be read is used when no profile is expected

- **GIVEN** window 5 whose rows have no profile
- **WHEN** fetch runs without `--expect-profile`
- **THEN** it SHALL end with exit 7, and no command SHALL carry `--profile`

---
### Requirement: The fetch command SHALL refuse a safari-browser without window ids before opening anything

`akashic fulltext fetch` SHALL check that `safari-browser documents --json` reports a top-level `window_id` key on its rows (added in safari-browser v2.9.0 together with `--window-id`) and SHALL stop with exit 1 before opening any tab when it does not, naming 2.9.0. It SHALL check the capability, not a version string.

#### Scenario: An old safari-browser is refused

- **WHEN** the rows of `documents --json` lack the top-level `window_id`
- **THEN** fetch SHALL exit 1 and open nothing

##### Example: Rows without window_id stop the run before anything is opened

- **GIVEN** a safari-browser whose `documents --json` rows carry `blocking_dialog.window_id` but no top-level `window_id`
- **WHEN** fetch runs
- **THEN** it SHALL exit 1, its message SHALL contain `2.9.0`, and no `open` SHALL have been sent

---
### Requirement: The fetch command SHALL print the window id and the mark of its tab

When fetch has identified its own tab, it SHALL print one stdout line `own-tab: window-id <W> tab <T>` followed by ` mark <mark>` while the mark is on the tab, so that later reads and clicks can be locked to the same window and tab.

#### Scenario: The own-tab line

- **WHEN** fetch opens and identifies its tab
- **THEN** stdout SHALL carry the window id, the position and the mark

##### Example: The own-tab line carries the window id and the mark

- **GIVEN** window 5 whose id is 9005 and the run's mark `akashic-0123456789abcdef`
- **WHEN** fetch runs
- **THEN** stdout SHALL contain `own-tab: window-id 9005 tab 2 mark akashic-0123456789abcdef`

---
### Requirement: The skill SHALL require the window-id contract

The fetch-fulltext skill SHALL require fulltext contract 12 in its step 0 and safari-browser 2.9.0 or later, SHALL describe the lock by window id, and SHALL NOT keep the other-profile stop.

#### Scenario: The skill matches the CLI

- **WHEN** the skill file is read
- **THEN** it SHALL name the window-id lock and the minimum safari-browser version, and SHALL NOT name the other-profile stop

##### Example: The skill names the window-id lock

| Text searched in SKILL.md | Expected |
| --- | --- |
| `--window-id` | present |
| `2.9.0` | present |
| `a Safari window of another profile` | absent |
| `-ge 12` | present |
