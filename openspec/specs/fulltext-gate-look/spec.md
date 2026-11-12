# fulltext-gate-look Specification

## Purpose

The full-text fetch command decides, from what it can read of a Safari tab, whether to hand the tab to the user, wait for the user to pass a human check, or pause the whole run. This capability records the rulings on what counts as the look of a login page and how an unreadable tab on the article site is judged.

## Requirements

### Requirement: An Atypon showLogin path segment SHALL have the look of a login page

A URL SHALL have the look of a login page when one whole path segment, after percent-decoding (a segment whose escapes cannot be decoded is left as it is), lowercasing, removing any `;` path parameters and removing one web-page extension, equals `showlogin`. This list SHALL be used for path segments only: a host label `showlogin` SHALL NOT make a host a login host, and `showlogin` inside a longer hyphenated slug SHALL NOT count. The login words shared by host and path SHALL NOT gain `showlogin`. When the fetch command judges an HTML page on the article site before navigating to the PDF link (the DOI landing page once it has settled, or the page the tab turned into while its text was being read) and that page's URL has this look, it SHALL pause the whole run (exit 6) with a message containing `(login page)`.

#### Scenario: The Atypon login path

- **WHEN** the URL is `https://onlinelibrary.example/action/showLogin` or the same with a query string
- **THEN** the URL's gate look SHALL be `login`

##### Example: showLogin path is a login look

- **GIVEN** the URL `https://onlinelibrary.example/action/showLogin?redirectUri=%2Fdoi%2Fx`
- **WHEN** the URL's gate look is computed
- **THEN** it SHALL be `login`

##### Example: showlogin host label is not a login host

- **GIVEN** the URL `https://showlogin.uni.example/x`
- **WHEN** the URL's gate look is computed
- **THEN** it SHALL NOT be `login`

##### Example: showlogin inside a longer slug does not count

- **GIVEN** the URL `https://pub.example/doi/how-to-showlogin-errors`
- **WHEN** the URL's gate look is computed
- **THEN** it SHALL NOT be `login`

##### Example: A percent-encoded showLogin segment is a login look

- **GIVEN** the URL `https://pub.example/action/%73howLogin`, or `https://pub.example/action/show%4Cogin?x=1`
- **WHEN** the URL's gate look is computed
- **THEN** it SHALL be `login`

##### Example: A CAPTCHA on the showLogin page after navigation pauses the run

- **GIVEN** the tab, after navigating to the page's own PDF link, settles on `https://pub.example/action/showLogin` on the article site and the page text asks for a CAPTCHA
- **WHEN** the fetch command judges the tab
- **THEN** it SHALL exit 6 and its message SHALL contain `(login page)`

##### Example: A showLogin page on another host pauses the run

- **GIVEN** the tab, after navigation, settles on `https://other.example/action/showLogin`, an HTML page with no signal text
- **WHEN** the fetch command judges the tab
- **THEN** it SHALL exit 6, not hand the tab over as `left-site`

##### Example: A landing page at showLogin pauses the run

- **GIVEN** the DOI resolves to `https://pub.example/action/showLogin?redirectUri=%2Fdoi%2F10.1%2Fx`
- **WHEN** the fetch command judges the landing page
- **THEN** it SHALL exit 6 with a message containing `(login page)`, SHALL NOT navigate to a PDF link, and SHALL NOT record an attempt

##### Example: A page that turns into showLogin before navigation pauses the run

- **GIVEN** the landing page passed the URL check, and while its text is being read the tab moves to `https://pub.example/action/showLogin?redirectUri=x` on the article site, a page whose text asks for a CAPTCHA
- **WHEN** the fetch command judges the page it read again
- **THEN** it SHALL exit 6 with a message containing `(login page)` and print no `resume:` line

---
### Requirement: An unreadable same-site tab with a human-check marker at a login path SHALL pause the run

When a tab on the article site cannot be read at all (not even `document.contentType`), and the service marker found in its title or URL is `cloudflare-challenge` or `perimeterx-press-and-hold`, and the URL's path has the look of a login page, the fetch command SHALL pause the whole run (exit 6) with a message containing `(login page)`, instead of waiting for human verification (exit 8). When the marker is found and the path does not have the look of a login page (a path with the look of a verification page included), the path SHALL NOT change the outcome: the tab is judged as it was before this ruling, which means waiting for human verification (exit 8) when the article site is a plain `https://<host>` origin whose host does not have the look of a login host. Without a service-marker hit, the path SHALL NOT be judged for an unreadable tab: when its host is neither a known verification service nor a host with the look of a login host, such a tab SHALL be handed to the user as `unverifiable` (exit 7).

#### Scenario: Marker and login path

- **WHEN** an unreadable same-site tab is at `/login` and its title is Cloudflare's "Just a moment..."
- **THEN** the fetch command SHALL exit 6

##### Example: Unreadable same-site login path with a Cloudflare marker pauses

- **GIVEN** after navigation the tab is at `https://pub.example/login`, titled `Just a moment...`, and no page JavaScript can run
- **WHEN** the fetch command judges the tab
- **THEN** it SHALL exit 6, print `STOP THE WHOLE RUN` and `(login page)`, and print no `resume:` line

##### Example: Unreadable same-site verification path with a Cloudflare marker still waits

- **GIVEN** after navigation the tab is at `https://pub.example/captcha/x`, titled `Just a moment...`, and no page JavaScript can run
- **WHEN** the fetch command judges the tab
- **THEN** it SHALL exit 8, print a `resume:` line with `--resume-stage followed`, and print no `(login page)`

##### Example: Unreadable same-site login path without a marker is handed over

- **GIVEN** after navigation the tab is at `https://pub.example/login`, titled `Sign in`, and no page JavaScript can run
- **WHEN** the fetch command judges the tab
- **THEN** it SHALL exit 7 with handover `unverifiable`

##### Example: Unreadable same-site PDF path with an auth segment is handed over

- **GIVEN** after navigation the tab is at `https://pub.example/auth/12345.pdf`, titled with the article title, and no page JavaScript can run
- **WHEN** the fetch command judges the tab
- **THEN** it SHALL exit 7 with handover `unverifiable`

---
### Requirement: The fetch contract version SHALL be 10

Because two cells changed exit code, `akashic fulltext contract` SHALL print `fulltext-contract 10`, and the skill's step 0 SHALL require at least 10.

#### Scenario: Contract printed

- **WHEN** `akashic fulltext contract` runs
- **THEN** it SHALL print `fulltext-contract 10`

##### Example: Skill and CLI agree on contract 10

- **GIVEN** the CLI's contract version and the skill's step-0 threshold
- **WHEN** they are compared
- **THEN** both SHALL be 10
