## MODIFIED Requirements

### Requirement: An unreadable same-site tab with a human-check marker at a login path SHALL pause the run

When a tab on the article site cannot be read at all (not even `document.contentType`), and the service marker found in its title or URL is `cloudflare-challenge` or `perimeterx-press-and-hold`, and the URL's path has the look of a login page, the fetch command SHALL pause the whole run (exit 6) with a message containing `(login page)`, instead of waiting for human verification (exit 8). The marker found is the one the service-marker check returns, and that check prefers a marker that pauses the whole run: when the host does not have the look of a login host and the title or URL also matches such a marker, the tab is paused (exit 6) under that marker, and the message names that marker and does not contain `(login page)`. When the service-marker check returns `cloudflare-challenge` or `perimeterx-press-and-hold` and the path does not have the look of a login page (a path with the look of a verification page included), the path SHALL NOT change the outcome: the tab is judged as it was before this ruling, which means waiting for human verification (exit 8) when the article site is a plain `https://<host>` origin whose host does not have the look of a login host. Without a service-marker hit, the path SHALL NOT be judged for an unreadable tab: when its host is neither a known verification service nor a host with the look of a login host, such a tab SHALL be handed to the user as `unverifiable` (exit 7).

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

