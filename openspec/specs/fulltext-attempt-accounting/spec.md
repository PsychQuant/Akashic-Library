# fulltext-attempt-accounting Specification

## Purpose

The full-text skill limits itself to ten attempts per publisher site per Asia/Taipei calendar day. This capability records how an attempt made outside `akashic fulltext fetch`, such as a click the skill makes on the article's own download link, is counted in the same ledger.

## Requirements

### Requirement: The attempt command SHALL record one attempt in the ledger that fetch uses

`akashic fulltext attempt --site <host> --landing <url>` SHALL reserve one attempt for `<host>` in the per-site daily attempt ledger, using the same reservation that `akashic fulltext fetch` uses (count and record in one step under the ledger's lock). When the reservation is granted it SHALL print one line `attempt: <host> <n>/10 <day>` on standard output, where `<n>` includes this attempt and `<day>` is the Asia/Taipei calendar day, and exit 0. The host SHALL be compared case-insensitively. The command SHALL NOT drive a browser, SHALL NOT open a network connection and SHALL NOT read or write a store. The `--ledger` option SHALL exist for tests only and the command SHALL warn on standard error when it names a ledger other than the default.

#### Scenario: An attempt is recorded

- **WHEN** the command runs for a site that has fewer than ten attempts today
- **THEN** the ledger SHALL gain exactly one line for that site and the command SHALL exit 0

##### Example: First attempt of the day is recorded

- **GIVEN** an empty ledger file path that does not exist yet
- **WHEN** `akashic fulltext attempt --site journals.example --landing https://doi.org/10.1/x --ledger <path>` runs
- **THEN** it SHALL exit 0, standard output SHALL start with `attempt: journals.example 1/10 `, and the ledger SHALL hold one line whose `site` is `journals.example`

##### Example: Host case does not split the count

- **GIVEN** a ledger with one attempt today for `journals.example`
- **WHEN** the command runs with `--site Journals.EXAMPLE`
- **THEN** standard output SHALL start with `attempt: journals.example 2/10 `

---
### Requirement: The attempt command SHALL stop at the daily cap without recording

When the site already has ten attempts on the current Asia/Taipei day, the attempt command SHALL print one line `cap: <host> <n>/10 <day>` on standard output, SHALL exit 9, and SHALL leave the ledger unchanged. Exit 9 SHALL mean the same as it does for `fetch`: stop this site for today.

#### Scenario: The cap is reached

- **WHEN** the command runs for a site with ten attempts today
- **THEN** it SHALL exit 9 and the ledger SHALL still hold ten lines for that site

##### Example: Eleventh attempt is refused

- **GIVEN** a ledger with ten attempts today for `journals.example`
- **WHEN** `akashic fulltext attempt --site journals.example --landing https://doi.org/10.1/x --ledger <path>` runs
- **THEN** it SHALL exit 9, standard output SHALL start with `cap: journals.example 10/10 `, and the ledger SHALL still hold ten lines

##### Example: Attempts and fetch share one count

- **GIVEN** an empty ledger, then ten runs of the attempt command for `pub.example`, each exiting 0
- **WHEN** `akashic fulltext fetch` runs with the same ledger against a stub browser whose article page on `pub.example` offers its own PDF link
- **THEN** fetch SHALL exit 9 without navigating to the PDF link, and the ledger SHALL still hold ten lines

---
### Requirement: The attempt command SHALL refuse a site that is not a plain host name

`--site` SHALL be a plain DNS host name: no scheme, no path, no user information, no port, no percent-encoding and no whitespace. `--landing` SHALL be an absolute https URL. When either is not, the command SHALL exit 64 before touching the ledger, so that no ledger file is created.

#### Scenario: A malformed site is refused

- **WHEN** `--site` is a URL, carries a port, or carries user information
- **THEN** the command SHALL exit 64 and SHALL NOT create the ledger file

##### Example: Malformed sites are refused before the ledger is touched

| `--site` | Exit | Ledger file |
| --- | --- | --- |
| `https://journals.example` | 64 | not created |
| `journals.example:8443` | 64 | not created |
| `user@journals.example` | 64 | not created |
| `journals.example/doi/x` | 64 | not created |

---
### Requirement: The attempt command SHALL refuse a ledger it cannot read

When the ledger exists and cannot be parsed, the attempt command SHALL exit 1, SHALL print the reason on standard error and SHALL NOT append to the ledger: today's count is unknown, so the cap cannot be honoured.

#### Scenario: An unreadable ledger

- **WHEN** the ledger holds a line that is not an attempt record
- **THEN** the command SHALL exit 1 and the ledger's bytes SHALL be unchanged

##### Example: A garbage line stops the command

- **GIVEN** a ledger file whose only line is `not json`
- **WHEN** `akashic fulltext attempt --site journals.example --landing https://doi.org/10.1/x --ledger <path>` runs
- **THEN** it SHALL exit 1 and the file SHALL still contain exactly `not json` and a newline
