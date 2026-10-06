## Purpose

Akashic reaches the Semantic Scholar (S2) API through one shared interface, so that every skill and the user query S2 with the same key handling, the same host rule, and the same machine-wide rate limit. The interface is read-only: what it returns is evidence for a later judgement, never a value written to the store.

## ADDED Requirements

### Requirement: One interface serves both faces

The system SHALL expose Semantic Scholar through a single library target, `AkashicS2`, and SHALL offer it on two faces that both call that target directly: the CLI subcommand group `akashic s2` and the MCP tool `akashic_s2`. Neither face SHALL route the call through the store-bound service layer, and neither face SHALL open, read, or write the store.

The interface SHALL cover exactly these endpoints: paper lookup, title match, batch lookup, references, citations, recommendations for a paper, author search, and author papers. The CLI SHALL offer one typed subcommand per endpoint (`paper`, `match`, `batch`, `references`, `citations`, `recommend`, `author-search`, `author-papers`) plus `status`.

#### Scenario: The same lookup through both faces

- **GIVEN** a key is available and S2 knows the paper `DOI:10.1037/a0038889`
- **WHEN** the user runs `akashic s2 paper DOI:10.1037/a0038889 --json` and a caller invokes `akashic_s2` with `endpoint: paper` and `id: DOI:10.1037/a0038889`
- **THEN** both SHALL return the same paper record, and neither SHALL touch the store

#### Scenario: A bare DOI is accepted

- **WHEN** the user runs `akashic s2 paper 10.1037/a0038889`
- **THEN** the request SHALL be sent for `DOI:10.1037/a0038889`

### Requirement: The key is read from the keychain without interaction and never exposed

The system SHALL read the API key from the keychain generic-password item with service `semantic-scholar` and account `default`, inside the process, without presenting any authorization dialog. The key SHALL NOT be accepted from a command-line argument or an environment variable, and SHALL NOT appear in any URL, log line, error message, file, CLI output, or MCP result. A value holding the key SHALL render as `<redacted>` when described or interpolated.

#### Scenario: The keychain item denies non-interactive access

- **GIVEN** a keychain item whose access control does not allow the reading binary without a prompt
- **WHEN** any `akashic s2` subcommand other than `status` runs
- **THEN** no dialog SHALL appear, the command SHALL exit with code 3, and the message SHALL say that the item exists but is not readable without a prompt and SHALL point to the setup document

#### Scenario: A request leaves no cache or cookie file behind

- **GIVEN** any endpoint is requested through either face
- **WHEN** the request completes
- **THEN** the networking layer SHALL NOT have written the request or its headers to any cache or cookie file, and the run SHALL NOT create or modify `~/Library/Caches/akashic/Cache.db` or `fsCachedData`

##### Example: Why the session is not the shared default

The platform's shared default session carries a disk cache. S2 answers without `Cache-Control`, so a GET is cached heuristically, and the cached entry holds the serialized request, custom headers included. The interface therefore SHALL use a session with no URL cache and no cookie storage, and SHALL refuse a caller-supplied session whose cache has a disk capacity. A per-request cache policy is not a substitute: it controls only whether a cached response is read, and does not stop the request from being stored.

#### Scenario: A failed request does not echo the key

- **GIVEN** S2 answers a request with HTTP 500
- **WHEN** the error is reported on either face
- **THEN** the report SHALL contain the endpoint and the status code, and SHALL NOT contain any request header

### Requirement: The key header is sent only to the Semantic Scholar host

The `x-api-key` header SHALL be attached only when the request's scheme is `https` and its host is exactly `api.semanticscholar.org`. A request to any other host SHALL be sent without the header. The interface SHALL NOT follow HTTP redirects: a 3xx response SHALL be reported as an error carrying its status code, and no request SHALL be sent to the redirect target, so the key cannot travel to another host or to `http`.

#### Scenario: A redirect is not followed

- **GIVEN** S2 answers a request with `302` and a `Location` on another host, or a `301` to `http`
- **WHEN** the request is sent
- **THEN** the call SHALL fail with the status code (CLI exit code 5), and no second request SHALL be sent

#### Scenario: A loopback base URL receives no key

- **GIVEN** `AKASHIC_S2_BASE_URL` is `http://127.0.0.1:8765`
- **WHEN** any endpoint is requested
- **THEN** the request SHALL go to `127.0.0.1:8765` without an `x-api-key` header, and the keychain SHALL NOT be read

### Requirement: A missing key stops the command with setup guidance

When requests are addressed to the Semantic Scholar host and no key item exists, the system SHALL stop before sending any request, SHALL NOT fall back to anonymous access, and SHALL tell the user which keychain service and account to create, give the command that stores it (without the key on the command line), and say where the setup document is. The CLI SHALL exit with code 3; the MCP tool SHALL return the same text with `isError: true`.

#### Scenario: A user without a key looks up a paper

- **GIVEN** `AKASHIC_S2_KEYCHAIN_SERVICE` is `akashic-test-7f3a` and no such item exists
- **WHEN** the user runs `akashic s2 paper DOI:10.1037/a0038889`
- **THEN** the command SHALL exit with code 3, SHALL name service `akashic-test-7f3a` and account `default`, SHALL point to `plugin/skills/akashic-bootstrap/references/semantic-scholar.md`, and SHALL send no network request

### Requirement: Requests are throttled machine-wide

All processes on one machine that use the interface SHALL together send at most one request per second. Each request SHALL reserve a send slot under an exclusive file lock on the throttle state file, SHALL release the lock before waiting, and SHALL be sent no earlier than its slot. The state file SHALL live outside the Akashic home directory, at `~/Library/Caches/akashic/s2-throttle` unless `AKASHIC_S2_STATE_DIR` names an absolute directory.

#### Scenario: Two sessions request at almost the same time

- **WHEN** two processes sharing one state directory each send three requests
- **THEN** every pair of send times SHALL be at least one second apart, within a 50 ms tolerance

##### Example: Slot reservation

- **GIVEN** the state file says the next allowed send time is t = 0.00
- **WHEN** session A requests at t = 0.00 and session B requests at t = 0.30
- **THEN** A SHALL send at t = 0.00, and B SHALL wait and send at t = 1.00 or later

#### Scenario: A stale state file does not block callers

- **GIVEN** no back-off is recorded, and the state file's next allowed send time is more than 60 seconds after now
- **WHEN** a request reserves a slot
- **THEN** the stored time SHALL be treated as stale and the slot SHALL be reserved from now

A recorded 429 back-off is not stale: it has its own bound (see "Rate-limit responses back off for every caller") and SHALL outlive the 60-second threshold that applies to send slots.

### Requirement: Rate-limit responses back off for every caller

On HTTP 429 the system SHALL move the shared next allowed send time to at least now plus the `Retry-After` delay, so that every caller waits, and SHALL then retry the same request. `Retry-After` SHALL be accepted as seconds or as an HTTP date; without it, the delays SHALL be 2, 4, and 8 seconds. A request SHALL be retried at most three times. When the retries are exhausted, or when `Retry-After` exceeds 60 seconds, the CLI SHALL exit with code 4 and the MCP tool SHALL return an error.

In every case the back-off SHALL be recorded in the shared state **before** the call gives up: a caller that stops retrying does not release the other callers from S2's back-off. The recorded back-off SHALL be at most one hour. A caller that finds a recorded back-off with more than 60 seconds left SHALL fail the same way (exit code 4) without sending a request and without sleeping through it; with 60 seconds or less left it SHALL wait for the back-off to pass and then send.

#### Scenario: A 429 delays the other session too

- **WHEN** session A receives 429 with `Retry-After: 3` at t = 1.00 while session B's next request is waiting
- **THEN** the shared next allowed send time SHALL become at least t = 4.00, and B's next request SHALL be sent no earlier than t = 4.00

##### Example: Retry budget

| Responses to one request | Outcome |
| ------------------------ | ------- |
| 429, 200 | success after one retry |
| 429, 429, 429, 200 | success after three retries |
| 429, 429, 429, 429 | exit code 4 after three retries |
| 429 with `Retry-After: 120` | exit code 4 without waiting; the 120-second back-off is recorded for every caller |
| any request while a recorded back-off has more than 60 seconds left | exit code 4 without sending |

### Requirement: The CLI prints complete results in two forms

Each CLI subcommand SHALL print a human-readable form by default and SHALL print a JSON envelope with `--json`. The envelope SHALL contain `source` (`semantic-scholar`), `endpoint`, `request`, `fetchedAt` (ISO 8601 with the local time-zone offset), `total`, and `data`. For paginated endpoints the CLI SHALL follow every page until the result set or `--limit` is exhausted, and `data` SHALL hold every record. The CLI output SHALL NOT be truncated by size.

#### Scenario: A paper with 1,000 references

- **GIVEN** S2 lists 1,000 references for a paper
- **WHEN** the user runs `akashic s2 references <id> --json`
- **THEN** `data` SHALL contain 1,000 records and `total` SHALL be 1000

#### Scenario: A limit caps the records

- **WHEN** the user runs `akashic s2 references <id> --limit 50 --json` for the same paper
- **THEN** `data` SHALL contain 50 records

### Requirement: The MCP tool bounds its result by bytes

The MCP result SHALL contain only whole records and SHALL stop before the record whose addition would make the result exceed 48 KiB, measured on the text actually returned. The result SHALL report `total`, `returned`, `truncated`, `offset`, and `nextOffset`. For references and citations, `total` SHALL come from the paper's `referenceCount` or `citationCount`; for author papers, from the author's `paperCount`; for searches, from the S2 response. When `total` cannot be obtained it SHALL be `null` and the records SHALL still be returned.

`truncated` SHALL mean only that the byte bound cut the page. The signal to continue is `nextOffset`: when it is not `null` the caller SHALL pass it as `offset` for the next call, and when it is `null` there is no next page. `nextOffset` SHALL be:

- `offset + returned` when the byte bound cut the page, or when S2 itself reported a further page (its `next` cursor), and `null` otherwise;
- always `null` for the endpoints that do not take an `offset` (`paper`, `match`, `batch`, `recommend`), because a cursor they would ignore only returns the same page;
- `null` for an empty page, never equal to the `offset` the call was made with.

`total` SHALL NOT decide whether a next page exists: it comes from another request, may be larger than what S2 returns, and may be unavailable.

The paginated endpoints (`references`, `citations`, `author_search`, `author_papers`) SHALL take `limit` from 1 to 1000 (one S2 page) and SHALL default it to 100. When the first record alone does not fit in 48 KiB, the tool SHALL return an error that names `fields` as the way to shrink the record, not a successful empty page.

#### Scenario: The same paper through MCP

- **GIVEN** S2 lists 1,000 references for a paper and only 120 whole records fit in 48 KiB
- **WHEN** a caller invokes `akashic_s2` with `endpoint: references`, that id, `offset: 0`, and `limit: 1000`
- **THEN** the result SHALL have `total: 1000`, `returned: 120`, `truncated: true`, and `nextOffset: 120`, and no record SHALL be cut short

#### Scenario: The default page fits and S2 has more

- **GIVEN** S2 lists 1,000 references and the first 100 fit in 48 KiB
- **WHEN** a caller invokes `akashic_s2` with `endpoint: references` and that id, without `limit`
- **THEN** the result SHALL have `returned: 100`, `truncated: false`, and `nextOffset: 100`

#### Scenario: The last page ends the continuation

- **GIVEN** S2 lists 130 references
- **WHEN** a caller invokes `akashic_s2` with `endpoint: references`, that id, and `offset: 100`
- **THEN** the result SHALL have `returned: 30` and `nextOffset: null`

#### Scenario: A batch that does not fit offers no cursor

- **GIVEN** a `batch` of 500 ids whose records do not all fit in 48 KiB
- **WHEN** the result is returned
- **THEN** it SHALL have `truncated: true` and `nextOffset: null`, and the documentation SHALL tell the caller to query fewer ids or fewer `fields`

#### Scenario: One record larger than the bound

- **GIVEN** the first record alone exceeds 48 KiB
- **WHEN** the tool returns
- **THEN** it SHALL return an error that names `fields`, and SHALL NOT return `returned: 0` as a success

### Requirement: Text from Semantic Scholar is sanitized before display

Every string value from an S2 response SHALL be neutralized before it appears in CLI output or an MCP result, by the face that shows it:

- the human-readable CLI form is terminal output and SHALL pass every string through the existing display-safe sanitizer;
- the JSON forms (`--json`, the MCP result, `status --json`) SHALL keep every string value intact, truncating only past the length limit, and SHALL escape the serialized JSON text losslessly (dangerous scalars written as the JSON `\uXXXX` escape), so that the decoded string equals what S2 sent and no dangerous scalar appears raw in the text.

#### Scenario: A title with a control character

- **GIVEN** S2 returns a title containing U+202E (right-to-left override)
- **WHEN** the record is printed by either face
- **THEN** the printed text SHALL NOT contain U+202E as a raw character

#### Scenario: A title with legitimate bibliographic characters

- **GIVEN** S2 returns the title `The $\beta$<NBSP>model<SHY>ling` (a backslash, a no-break space, a soft hyphen)
- **WHEN** a JSON form carries it
- **THEN** decoding the JSON SHALL give back exactly that title

### Requirement: Test overrides are confined

The interface SHALL accept three environment overrides and SHALL refuse any value outside its bound:

- `AKASHIC_S2_BASE_URL`: only `http` on `127.0.0.1`, `localhost`, or `[::1]`, with an optional port
- `AKASHIC_S2_KEYCHAIN_SERVICE`: only names that begin with `akashic-test-`
- `AKASHIC_S2_STATE_DIR`: only absolute paths

A refused value SHALL stop the command before any request, with exit code 1 on the CLI: environment variables are not command-line arguments, and exit code 64 is reserved for errors decidable from the arguments alone. While `AKASHIC_S2_BASE_URL` is set, the interface SHALL NOT read the keychain and SHALL NOT attach a key, because no request goes to the Semantic Scholar host.

#### Scenario: A base URL pointing elsewhere is refused

- **GIVEN** `AKASHIC_S2_BASE_URL` is `https://example.org`
- **WHEN** any endpoint is requested
- **THEN** the command SHALL exit with code 1, SHALL name `AKASHIC_S2_BASE_URL`, and SHALL send no request

#### Scenario: A keychain override naming a real item is refused

- **GIVEN** `AKASHIC_S2_KEYCHAIN_SERVICE` is `stat-sinica-compute`
- **WHEN** any endpoint is requested
- **THEN** the command SHALL exit with code 1 and SHALL NOT read the keychain

#### Scenario: Argument errors are caught before any I/O

- **WHEN** the user runs `akashic s2 references DOI:10.1/x --limit 0`, `akashic s2 paper ../../author/1`, `akashic s2 recommend DOI:10.1/x --limit 501`, or `akashic s2 match --title ""`
- **THEN** each command SHALL exit with code 64 without reading the keychain or sending a request

### Requirement: Status reports readiness without revealing the key

`akashic s2 status` SHALL report the keychain service and account, whether the item is present, whether it is readable without a prompt, the throttle state file, and the next allowed send time. It SHALL NOT send a network request, and SHALL NOT print the key or its length.

#### Scenario: Status on a configured machine

- **GIVEN** the key item exists and allows non-interactive reading
- **WHEN** the user runs `akashic s2 status --json`
- **THEN** `keychain.present` and `keychain.readable` SHALL both be true and the output SHALL contain no part of the key

### Requirement: Other failures are reported with their cause

A 404 SHALL be reported as the identifier S2 does not know. Any other 4xx, any 5xx, and any connection failure SHALL be reported with the endpoint and the status code or error class. The CLI SHALL exit with code 5 for all of these; the MCP tool SHALL return `isError: true` with the same text.

#### Scenario: An unknown identifier

- **GIVEN** S2 answers 404 for `DOI:10.0000/none`
- **WHEN** the user runs `akashic s2 paper DOI:10.0000/none`
- **THEN** the command SHALL exit with code 5 and the message SHALL name `DOI:10.0000/none` as not found
