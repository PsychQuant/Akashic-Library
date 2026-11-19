## MODIFIED Requirements

### Requirement: The landing table SHALL be judged in a fixed order and SHALL NOT lead to a second click on the same control

The skill SHALL give the click landing table a fixed order of judgement in which the no-change landing is judged before the another-own-control landing. The another-own-control landing SHALL apply only when the page changed (the URL changed or a new tab was adopted) and the control is not the one just clicked; the control just clicked SHALL never count as another one. After waiting once on the no-change landing, the model SHALL judge the other landings again, not only the new-tab, download and dialog landings. A click whose result matches no landing SHALL put the article on the hand-over list, and the division-of-labour section SHALL send a case outside its closed list to the same list. A `save-pdf` refusal saying the tab is not a PDF SHALL mean that the PDF landing does not hold and the judgement moves on. Only the `save-pdf` failures that prove the tab is a PDF (raised after its content-type test: a service worker, the document not held, an HTTP status, a failed read, too large, bytes that are not a PDF, or the temporary copy not written) SHALL end the article as not obtained; any other `save-pdf` failure, a lock that finds no tab after a click, or a `get text` lock miss SHALL lead to one wait, a fresh lock and a judgement from the top of the order, and when it is still undeterminable the batch SHALL pause. After a click the host of the page being judged SHALL NOT count as a sign that the lock drifted. Each re-judgement SHALL compare with the state just before it and SHALL run the PDF probe whether or not the URL changed. A new tab SHALL be adopted only when it sits right of the clicked tab and appeared in that click (see the lock requirement) and its host is the clicked page's host or a known verification service; a tab that is adopted is judged with the whole table. A new tab right of the clicked tab on any other host SHALL receive only the `save-pdf` probe: it is adopted when the probe takes a PDF, and otherwise the batch pauses without any further command on it. A download that comes in the same click that changed the URL or adopted a tab SHALL first have the PDF probe run on that page and, when it is not a PDF, the suspicion read and the login check; `get text` SHALL NOT be run on a tab that may show a PDF before the probe. A blocking dialog after a click SHALL be class (c) only when every message is Safari's own download-permission prompt (the messages are tested, never printed); any other blocking dialog SHALL stop the batch as a JavaScript dialog. A click SHALL lead to at most one wait.

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

##### Example: Only PDF-proving save-pdf failures end the article

- **GIVEN** the section headed `#### 一層層按`
- **WHEN** its table row starting `| 1 |` is read
- **THEN** it SHALL contain `Could not read the PDF from the tab`, `What the tab holds does not start with %PDF-`, `等一次` and `(e)`, and SHALL NOT contain `表示分頁就是 PDF 而取不到`

##### Example: The judged page's host is not a drift signal

- **GIVEN** the section headed `#### 一層層按`
- **WHEN** it is searched
- **THEN** it SHALL contain `不是漂移的訊號`

##### Example: Re-judgements probe for a PDF and compare with the state just before

- **GIVEN** the section headed `#### 一層層按`
- **WHEN** its table rows starting `| 3 |` and `| 4 |` are read
- **THEN** the row `| 3 |` SHALL contain `右邊緊鄰的那一格`, `只送 \`save-pdf\`` and `不論網址變了沒有`, and SHALL NOT contain `任何主機`, and the row `| 4 |` SHALL contain `先跑第 1 種的探測` and `第 8 種的讀法`

##### Example: A dialog that is not Safari's download prompt stops the batch

- **GIVEN** the section headed `#### 一層層按`
- **WHEN** its table row starting `| 5 |` is read
- **THEN** it SHALL contain `dialog=present:safari-download`, `dialog=present:other` and `第 (3) 種`

##### Example: The verification hosts of the landing block are BotSignals'

- **GIVEN** the line starting `def vsvc:` in the landing block of `#### 一層層按`
- **WHEN** it is run with `jq` on https and http URLs on `challenges.cloudflare.com`, `hcaptcha.com`, `recaptcha.net`, their subdomains, `www.google.com/recaptcha/…`, `google.com/search`, hosts with userinfo, a port or a backslash, and look-alike hosts
- **THEN** its answer SHALL equal `BotSignals.isKnownVerificationService(url:)` for every URL

---
### Requirement: A login page on another host SHALL pause the whole run

The skill SHALL limit class (b) to a login page on the article site itself. A page on another host that asks the reader to sign in, or that has the login look of the stop clause, SHALL be the whole-run pause (e), both in the `left-site` hand-over row and in the click landing for login pages. A page on the article site that only offers a way to get access (「Log in for access」, 「Check Access」) and is not itself a sign-in page SHALL NOT be class (b): it is the no-access landing.

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

##### Example: An access offer is not class (b)

- **GIVEN** the section headed `## 人機分工`
- **WHEN** its table row starting `| (b) |` is read
- **THEN** it SHALL contain `Log in for access` and `落點表第 7 種`

---
### Requirement: The skill SHALL list the mid-run stops as a closed list

The skill SHALL list, as a closed list, the states that stop the whole batch and are told to the person at once although no article is handed over: the three fetch exit-1 states already listed (an untrustworthy tab list, a tab that cannot be matched or was left in the user's window, a JavaScript dialog blocking the tab), an unreadable attempt ledger, Safari not answering a timed read, a safari-browser too old to name a window by `--window-id`, the pacing tool not running, and two articles in a row on one site failing the same way. The tab that cannot be matched SHALL include the skill's own landing check still finding the clicked position changed after the one wait, and a dialog that is not Safari's download prompt SHALL count as the JavaScript dialog. Safari not answering SHALL cover every timed read of the skill (the `documents` reads of its blocks and its timed `get` reads) and an unreadable `documents` answer. A window of another profile being open SHALL NOT be one of them (#772). The skill SHALL describe the window lock as it is: position locks carry the window id, and the mark lock is the mark that `fetch` confirmed in the fixed window, unique to the run. The skill SHALL say that the timed read is not measured. The skill SHALL name, as a closed list, the only places where the model asks the person something in the middle of a batch, and SHALL send the Finder rename of an unusable path to the end-of-batch list.

#### Scenario: The stops and the asks are closed

- **WHEN** the skill file is read
- **THEN** it SHALL list eight mid-run stops and two mid-run asks, and the Finder rename SHALL wait for the end of the batch

##### Example: Eight mid-run stops

- **GIVEN** the section headed `## 人機分工`
- **WHEN** it is searched
- **THEN** it SHALL contain `只有這八種`, `不得依性質相似類推第九種`, `帳本讀不懂`, `定時讀取`, `2.9.0 or later is needed`, `節奏工具`, `連續兩篇` and `這八種不能「先跳過」`, and SHALL NOT contain `a Safari window of another profile` or `這六種`

##### Example: The window lock is described as it is

- **GIVEN** the sections headed `## 人機分工` and `### 3. 在使用者的 Safari 裡走到 PDF`
- **WHEN** they are searched
- **THEN** both SHALL contain `記號每次執行都不同`, and neither SHALL contain `把每一個動作鎖在開頭選定的視窗` or `之後的每一個命令都以開頭選定的視窗的 id 指定`

##### Example: No other mid-batch asks

- **GIVEN** `plugin/skills/akashic-fetch-fulltext/SKILL.md`
- **WHEN** the section headed `## 人機分工` and the line containing `在 Finder 裡改檔名` are read
- **THEN** the section SHALL contain `批次中途要你叫使用者的只有兩處` and the line SHALL contain `最後交給使用者的清單`

##### Example: The timed read is marked unmeasured

- **GIVEN** the section headed `#### 一層層按`
- **WHEN** it is searched
- **THEN** it SHALL contain `perl -e 'alarm shift; exec @ARGV' 20 safari-browser get url` and `沒有量過`

---
### Requirement: Reads and clicks after fetch SHALL stay on fetch's window and tab

After `fetch`, every safari-browser command the model sends to the article's tab (`snapshot -i`, `get`, `click`, `save-pdf`) SHALL be locked by the window id fetch printed on its `own-tab:` line and by the tab found in the same Bash call, and, when fetch printed the window's profile, also by `--profile`. Every `documents --json` read SHALL be timed and SHALL carry `--profile` when fetch printed the profile; only the window's rows SHALL be kept, the full list being deleted in the same call. At the start of an article the tab SHALL be found by this run's mark, and, when no tab carries the mark, by the position fetch printed on its `handover:` line; the start SHALL save the state before any click, and a host at that position other than the host fetch printed SHALL end the article as not obtained. The mark SHALL be kept in a file of the article and SHALL be cleared when a new tab is adopted, so that the lock follows the adopted tab. Without the mark the tab is the one tab of the window whose URL equals the full URL kept in a file; an empty kept URL SHALL match nothing. When no such tab, or more than one, is found, the command SHALL NOT be sent: before the article's first click the article is not obtained, and after a click the model waits once, takes the lock again and judges from the top, and the batch pauses when the tab is still not found. After a click, and when the tab is taken again after a hand-over, the tab at the clicked position SHALL be judged by the rule of fetch's position tracking (`stillOurTab`): a position that showed a URL and now shows none is not ours; when the window's tab count changed, the tab counts only if its URL is unchanged and the tabs to its left are unchanged; otherwise it is `moved`. `url-changed` SHALL compare with the URL at the click. A tab SHALL count as opened by the click only when the window gained exactly one tab, at the position right of the clicked tab, every other tab is unchanged and its URL was not seen before; any other growth SHALL NOT be adopted and the tab SHALL NOT be read or acted on. A `moved` result after a click that persists after the one wait SHALL stop the batch as a tab that cannot be matched. Before handing over an (a), (b) or (d) article at the end of the batch the state SHALL be refreshed by the same check, and after the person is done a `moved` result SHALL end the article as not obtained. The blocks SHALL print only a URL's host, without userinfo, and only the scheme of a URL without `://`.

#### Scenario: A drifted tab is not acted on

- **WHEN** the tab cannot be found by mark or by full URL in fetch's window
- **THEN** the block SHALL exit without sending the command

##### Example: The lock block finds the tab by mark or full URL in fetch's window

- **GIVEN** the section headed `### 3. 在使用者的 Safari 裡走到 PDF`
- **WHEN** it is searched
- **THEN** it SHALL contain `own-tab:`, `endswith("#" + $mk)`, `--rawfile u`, `exit 4`, `alarm shift`, `rm -f "$D/$K.raw.json"` and `"${PF[@]}"`

##### Example: After a click the tab is judged like fetch's position tracking

- **GIVEN** the section headed `#### 一層層按`
- **WHEN** it is searched
- **THEN** it SHALL contain `.before.json`, `($now | length) != ($last | length)`, `$shows == "" and $was != ""`, `.held.json`, `"${PF[@]}"` and `stillOurTab`

##### Example: The lock follows an adopted tab

- **GIVEN** the SKILL's start, adoption and lock blocks run against a fake safari-browser, with the mark on the article tab at position 2 and a new tab at position 3 adopted
- **WHEN** the lock block is run
- **THEN** its command SHALL be sent to tab 3

##### Example: A tab that slid into the article's position is not taken

- **GIVEN** the SKILL's landing block, with the state before the click `[left, article, private]`, position 2, and the window now `[left, private]`
- **WHEN** it is run
- **THEN** it SHALL print `moved`, exit 4 and SHALL NOT save the private tab's URL

##### Example: A tab the click did not open is not adopted

- **GIVEN** the SKILL's landing block and the state before a click on position 2 of a three-tab window
- **WHEN** a fourth tab appears at the end, or a tab on another host appears at position 3 while another tab also changed
- **THEN** it SHALL print `new-tab=unattributed`; and a single new tab at position 3 SHALL print its host and `same-host`, `verification` or `other`

##### Example: A lock miss after a click is not the end of the article

- **GIVEN** the SKILL's lock block and a window without the article's tab
- **WHEN** it is run before the article's first click and after it
- **THEN** it SHALL exit 4 before and 2 after, sending no command either time

##### Example: The start finds the tab by the mark and then by position

- **GIVEN** the SKILL's start block, the position from `handover:`, and a window whose tabs do or do not carry the mark
- **WHEN** it is run
- **THEN** it SHALL print `by=mark` or `by=position`, save the URL and the state before any click, and send nothing else

##### Example: Only the host is printed

- **GIVEN** the SKILL's lock and landing blocks and tab URLs with `user:pw@` or without `://`
- **WHEN** they are run
- **THEN** their output SHALL contain neither the userinfo nor the URL after its scheme

##### Example: The three not-obtained outcomes of the lock are stated

- **GIVEN** `plugin/skills/akashic-fetch-fulltext/SKILL.md`
- **WHEN** the sections headed `### 3. 在使用者的 Safari 裡走到 PDF` and `#### 一層層按` are extracted
- **THEN** the first SHALL contain `印的那個主機就不往下` and the second SHALL contain `這一篇還沒按過` and `接手之後還沒按任何東西`

---
### Requirement: The skill SHALL state the edge behaviours of the click procedure

The skill SHALL state: that an article has no fixed limit on the number of clicks; that the rule on two failures in a row counts only articles not obtained; that a `get text` or `get title` read that fails or comes back empty pauses the batch and that a lock miss there leads to one wait; that `--site` is written only for plain hosts; that a tab fetch handed over as `unverifiable` is not obtained and that fetch prints no `take` hint for it, and that a resumed tab that cannot be read is not obtained either; that a page offering a purchase is class (d), handed to the person, and a page saying there is no access without offering one is not obtained; that the row-1 probe runs safari-browser's own script on an HTML page, including a page on another host right of the clicked tab, a cost accepted with its reason; and that the exception of rule 1 (d) is bounded by fetch's fixed window, not by a profile.

#### Scenario: The edge behaviours are written down

- **WHEN** the skill file is read
- **THEN** each of these behaviours SHALL be stated

##### Example: Edge behaviours are in the skill

| Text searched in SKILL.md | Expected |
| --- | --- |
| `不設固定的層數上限` | present |
| `只算「取不到」` | present |
| `決定要不要付費` | present |
| `接受的代價` | present |
| `不印 take 的提示` | present |
| `get title rc=` | present |
| `別的主機上的分頁也會跑到` | present |
| `在 \`fetch\` 的固定視窗裡` | present |
| `profile 也對得上` | absent |
| `顯示 PDF 就請他存` | absent |
