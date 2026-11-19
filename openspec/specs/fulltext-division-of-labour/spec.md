# fulltext-division-of-labour Specification

## Purpose

The full-text skill is prose that a model executes in the user's own browser session. This capability records who does what: the model performs every step a reader would perform, and only a closed list of situations is left for the person.

## Requirements

### Requirement: The skill SHALL make the model the default actor and hand over only a closed list

The `akashic-fetch-fulltext` skill SHALL state that every step is done by the model unless it falls in a closed list, and SHALL state that the list is closed and is not extended by resemblance. The list SHALL be: (a) CAPTCHA and other human checks; (b) signing in, entering credentials, or institutional single sign-on; (c) Safari's own permission dialogs and its save panel; (d) paying or purchasing; and (e) the stop clause's pause of the whole run. For (a) to (d) the skill SHALL say that the article is skipped and handed to the person once, after the rest of the batch has run. For (e) the skill SHALL say that the whole run stops at once. The skill SHALL separate two outcomes in its final report: articles handed to the person, and articles that could not be obtained.

#### Scenario: The skill names the division of labour

- **WHEN** the skill file is read
- **THEN** it SHALL contain a section that names the default actor and the closed list (a) to (e)

##### Example: Division of labour section lists five classes

- **GIVEN** `plugin/skills/akashic-fetch-fulltext/SKILL.md`
- **WHEN** the section headed `## 人機分工` is extracted
- **THEN** it SHALL contain the markers `(a)`, `(b)`, `(c)`, `(d)` and `(e)`, the words `封閉列舉`, and the words `不得依性質相似類推`

---
### Requirement: The skill SHALL NOT keep the superseded hand-over rules

The skill SHALL NOT contain the sentences that made the person the default actor: the instruction not to press any button on the person's behalf, the condition that pressing the article's own download control needs authorisation in the current conversation, and the instruction to wait for the person to finish one article before starting the next. The skill SHALL NOT instruct the model to take a displayed PDF with `pdf-cache get`; it SHALL instruct `safari-browser save-pdf` and SHALL name the acquisition value `browser-save-pdf` for a file obtained that way.

#### Scenario: Retired sentences are absent

- **WHEN** the skill file is searched for the retired sentences
- **THEN** none SHALL be found

##### Example: Retired hand-over sentences are gone

| Text searched in SKILL.md | Expected |
| --- | --- |
| `不要代按任何按鈕` | absent |
| `當次對話授權` | absent |
| `等使用者處理完再做下一篇` | absent |
| `先用 `pdf-cache get` | absent |
| `safari-browser save-pdf` | present |
| `browser-save-pdf` | present |

---
### Requirement: The skill SHALL count each click it makes

The skill SHALL instruct the model to run `akashic fulltext attempt` before each click on a publisher page and to stop that site for the day when the command exits 9. The skill SHALL say where the `--site` value comes from: the host on fetch's `attempt:` line, or, when fetch printed no `attempt:` line (exit 3 and `points off-site` stop before the reservation), the host of fetch's `page:` line. The skill SHALL say that exit 64 from the attempt command means the model does not click and the article is reported as not obtained, with the reason.

#### Scenario: The click procedure names the accounting command

- **WHEN** the skill file is read
- **THEN** its click procedure SHALL name `akashic fulltext attempt`

##### Example: Click procedure calls the attempt command

- **GIVEN** `plugin/skills/akashic-fetch-fulltext/SKILL.md`
- **WHEN** the section headed `#### 一層層按` is extracted and its line starting `2. **記帳**` is read
- **THEN** that line SHALL contain `akashic fulltext attempt --site` and `64`

#### Scenario: The site key has a source on every entry

- **WHEN** the skill's daily-cap section is read
- **THEN** it SHALL name fetch's `page:` line as the source of `--site` when there is no `attempt:` line

##### Example: The site key falls back to the page line

- **GIVEN** `plugin/skills/akashic-fetch-fulltext/SKILL.md`
- **WHEN** the section headed `## 每站每天 10 次嘗試` is extracted
- **THEN** it SHALL contain `page:` and `64`

---
### Requirement: The skill SHALL defer the rest of a site after a human check

The skill SHALL say that, after fetch exit 8 and after one of the four human checks reached by the model's own click on the article site or on a known verification service, the article and the batch's remaining articles from the same site are deferred to the end of the batch. The skill SHALL say how the same site is recognised: by the host fetch printed when it is known, and otherwise by the DOI prefix, which the skill SHALL call a heuristic. For a human check reached by a click, the skill SHALL say there is no `resume:` line and that, after the person says the check is done, the model judges the same tab again with the landing table without reloading it and without counting a new attempt for looking at it.

#### Scenario: Deferral covers both kinds of human check

- **WHEN** the skill file is read
- **THEN** the deferral of the same site SHALL apply to fetch exit 8 and to a human check reached by a click

##### Example: Deferral covers exit 8 and a click-reached check

- **GIVEN** `plugin/skills/akashic-fetch-fulltext/SKILL.md`
- **WHEN** the section headed `## 人機分工` is extracted
- **THEN** it SHALL contain `同一個站剩下的各篇` and `落點表第 8 種`

##### Example: Same site is recognised by host or DOI prefix

- **GIVEN** `plugin/skills/akashic-fetch-fulltext/SKILL.md`
- **WHEN** the section headed `## 中止條款` is extracted
- **THEN** it SHALL contain `DOI 前綴` and `經驗法則`

##### Example: A click-reached check is judged again without reloading

- **GIVEN** `plugin/skills/akashic-fetch-fulltext/SKILL.md`
- **WHEN** the section headed `#### 一層層按` is extracted and its table row starting `| 8 |` is read
- **THEN** that row SHALL contain `沒有 \`resume:\` 一行` and `不重新載入`

---
### Requirement: The landing table SHALL be judged in a fixed order and SHALL NOT lead to a second click on the same control

The skill SHALL give the click landing table a fixed order of judgement in which the no-change landing is judged before the another-own-control landing. The another-own-control landing SHALL apply only when the page changed (the URL changed or a new tab opened) and the control is not the one just clicked; the control just clicked SHALL never count as another one. After waiting once on the no-change landing, the model SHALL judge the other landings again, not only the new-tab, download and dialog landings. A click whose result matches no landing SHALL put the article on the hand-over list, and the division-of-labour section SHALL send a case outside its closed list to the same list. A `save-pdf` refusal saying the tab is not a PDF SHALL mean that the PDF landing does not hold and the judgement moves on.

#### Scenario: The order prevents a second click

- **WHEN** the click procedure is read
- **THEN** it SHALL state the order and SHALL keep the rule that the same control is not clicked a second time

##### Example: Landing order puts no-change before another control

- **GIVEN** `plugin/skills/akashic-fetch-fulltext/SKILL.md`
- **WHEN** the section headed `#### 一層層按` is extracted
- **THEN** it SHALL contain `5 → 3 → 4 → 1 → 8 → 6 → 7 → 9 → 2`

##### Example: The control just clicked never counts as another one

- **GIVEN** the section headed `#### 一層層按`
- **WHEN** its table rows starting `| 2 |` and `| 9 |` are read
- **THEN** the row `| 2 |` SHALL contain `剛按的那一個元件不算` and the row `| 9 |` SHALL contain `不按第二次`

##### Example: Waiting once re-judges every landing

- **GIVEN** the section headed `#### 一層層按`
- **WHEN** its table row starting `| 9 |` is read
- **THEN** it SHALL contain `第 1 到第 8 種都要再看`

##### Example: An unmatched landing goes to the hand-over list

- **GIVEN** `plugin/skills/akashic-fetch-fulltext/SKILL.md`
- **WHEN** the sections headed `#### 一層層按` and `## 人機分工` are extracted
- **THEN** the first SHALL contain `對不上落點表的任何一種` and the second SHALL contain `不在 (a)–(d) 裡`

##### Example: A save-pdf probe that is not a PDF moves on

- **GIVEN** the section headed `#### 一層層按`
- **WHEN** its table row starting `| 1 |` is read
- **THEN** it SHALL contain `not a PDF` and `往下判`

---
### Requirement: The skill SHALL read a page after a click with fixed read-only commands and check it for suspicion

The skill's rule on what the model does to a page SHALL be a closed list that includes the fixed read-only safari-browser commands `get url`, `get title`, `get text` and `get attr` for a control's `href`. After a click, the skill SHALL pipe the page text read by `safari-browser get text` to `akashic fulltext bot-signals --kind`, and SHALL say that `get text` is not used on a tab that shows a PDF. Before a click, the skill SHALL read the control's `href` with `safari-browser get attr` and SHALL NOT click a control whose absolute `href` points to another host.

#### Scenario: The reads are named and used

- **WHEN** the skill file is read
- **THEN** rule 5 SHALL name the reads and the click procedure SHALL use them

##### Example: Rule 5 names the fixed reads

- **GIVEN** `plugin/skills/akashic-fetch-fulltext/SKILL.md`
- **WHEN** the section headed `## 最高原則` is extracted and its line starting `5. ` is read
- **THEN** that line SHALL contain `get url`, `get title`, `get text` and `get attr`

##### Example: The landing check pipes page text to bot-signals

- **GIVEN** the section headed `#### 一層層按`
- **WHEN** it is searched
- **THEN** it SHALL contain `safari-browser get text --profile` and `| akashic fulltext bot-signals --kind`

##### Example: The href is read before a click

- **GIVEN** the section headed `#### 一層層按`
- **WHEN** its line starting `1. **讀**` is read
- **THEN** that line SHALL contain `get attr @<ref> href`

---
### Requirement: A login page on another host SHALL pause the whole run

The skill SHALL limit class (b) to a login page on the article site itself. A page on another host that asks the reader to sign in, or that has the login look of the stop clause, SHALL be the whole-run pause (e), both in the `left-site` hand-over row and in the click landing for login pages.

#### Scenario: The host decides between (b) and (e)

- **WHEN** the skill file is read
- **THEN** class (b), the login landing and the `left-site` row SHALL send a login page on another host to (e)

##### Example: Landing row 6 splits the hosts

- **GIVEN** the section headed `#### 一層層按`
- **WHEN** its table row starting `| 6 |` is read
- **THEN** it SHALL contain `文章站本身`, `別的主機` and `(e)`

##### Example: The left-site row pauses on a login page elsewhere

- **GIVEN** `plugin/skills/akashic-fetch-fulltext/SKILL.md`
- **WHEN** the table row starting ``| `left-site` |`` is read
- **THEN** it SHALL contain `(e)` and SHALL NOT contain `要求登入是 (b)`

##### Example: Class (b) is limited to the article site

- **GIVEN** the section headed `## 人機分工`
- **WHEN** its table row starting `| (b) |` is read
- **THEN** it SHALL contain `文章站本身`

---
### Requirement: The click procedure SHALL have a closed list of entries

The skill SHALL say that the click procedure is entered only from the five fetch outcomes it names, that a page reached without fetch is not an entry, and that adding an entry needs a user ruling. The publisher notes SHALL NOT send a page reached without fetch into the click procedure.

#### Scenario: Entries are closed

- **WHEN** the click procedure and the publisher notes are read
- **THEN** the entries SHALL be the five fetch outcomes and the EBSCO reader SHALL NOT be routed to the click procedure

##### Example: Click entries are the five fetch outcomes

- **GIVEN** the section headed `#### 一層層按`
- **WHEN** it is searched
- **THEN** it SHALL contain `只有這五種`, `不經 \`fetch\` 到達的頁面` and `需要使用者裁決`

##### Example: The EBSCO reader is not a click entry

- **GIVEN** `plugin/skills/akashic-fetch-fulltext/references/publishers.md`
- **WHEN** its paragraph starting `**然後**` is read
- **THEN** it SHALL contain `需要使用者裁決` and SHALL NOT contain `照 SKILL.md〈一層層按〉處理`

---
### Requirement: The skill SHALL list the mid-run stops as a closed list

The skill SHALL list, as a closed list, the states that stop the whole batch and are told to the person at once although no article is handed over: the three fetch exit-1 states already listed (an untrustworthy tab list, a tab that cannot be matched or was left in the user's window, a JavaScript dialog blocking the tab), an unreadable attempt ledger, Safari not answering a timed read after a click left something the tools cannot read, and a safari-browser too old to name a window by `--window-id` (#772). A window of another profile being open SHALL NOT be one of them (#772). The skill SHALL say that the timed read is not measured. The skill SHALL name, as a closed list, the only places where the model asks the person something in the middle of a batch, and SHALL send the Finder rename of an unusable path to the end-of-batch list.

#### Scenario: The stops and the asks are closed

- **WHEN** the skill file is read
- **THEN** it SHALL list six mid-run stops and two mid-run asks, and the Finder rename SHALL wait for the end of the batch

##### Example: Six mid-run stops without the other-profile stop

- **GIVEN** the section headed `## 人機分工`
- **WHEN** it is searched
- **THEN** it SHALL contain `只有這六種`, `不得依性質相似類推第七種`, `帳本讀不懂`, `定時讀取` and `2.9.0 or later is needed`, and SHALL NOT contain `a Safari window of another profile`

##### Example: No other mid-batch asks

- **GIVEN** `plugin/skills/akashic-fetch-fulltext/SKILL.md`
- **WHEN** the section headed `## 人機分工` and the line containing `在 Finder 裡改檔名` are read
- **THEN** the section SHALL contain `批次中途要你叫使用者的只有兩處` and the line SHALL contain `最後交給使用者的清單`

##### Example: The timed read is marked unmeasured

- **GIVEN** the section headed `#### 一層層按`
- **WHEN** it is searched
- **THEN** it SHALL contain `perl -e 'alarm shift; exec @ARGV' 20 safari-browser get url` and `沒有量過`

---
### Requirement: Values from a page SHALL reach the shell through a variable

The skill SHALL NOT show a command that writes a value chosen by a page (a tab URL or a substring of it) inside a double-quoted argument. It SHALL show the value taken from `safari-browser documents --json` with `jq -r` into a shell variable and used as `"$lock"`.

#### Scenario: No page value inside double quotes

- **WHEN** the skill file is searched for its tab locks
- **THEN** none SHALL be a placeholder inside double quotes, and the variable form SHALL be shown

##### Example: Tab locks use a variable

| Text searched in SKILL.md | Expected |
| --- | --- |
| `--url "<` | absent |
| `--url "$lock"` | present |
| `jq -r` | present |

---
### Requirement: Deferred hand-overs SHALL be done one at a time

The skill SHALL say that the articles deferred to the end of the batch are handed to the person one at a time, and that before each hand-over of a save panel or download prompt the model touches a fresh marker file and takes only a file newer than that marker.

#### Scenario: A fresh marker per hand-over

- **WHEN** the report step is read
- **THEN** it SHALL name the fresh marker and the one-at-a-time hand-over

##### Example: The report step names the fresh marker

- **GIVEN** `plugin/skills/akashic-fetch-fulltext/SKILL.md`
- **WHEN** the section headed `### 7. 回報` is extracted
- **THEN** it SHALL contain `.handover` and `一次一篇`
