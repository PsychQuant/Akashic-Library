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

The skill SHALL instruct the model to run `akashic fulltext attempt` before each click on a publisher page and to stop that site for the day when the command exits 9.

#### Scenario: The click procedure names the accounting command

- **WHEN** the skill file is read
- **THEN** its click procedure SHALL name `akashic fulltext attempt`

##### Example: Click procedure calls the attempt command

- **GIVEN** `plugin/skills/akashic-fetch-fulltext/SKILL.md`
- **WHEN** it is searched for `akashic fulltext attempt --site`
- **THEN** the text SHALL be present
