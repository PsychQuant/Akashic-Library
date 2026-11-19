## MODIFIED Requirements

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
