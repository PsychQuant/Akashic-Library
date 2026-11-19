## 1. 測試先寫（在 5aa42d02 上看它們失敗）

- [x] 1.1 （Requirement: The skill SHALL count each click it makes）`Tests/AkashicCLITests/FulltextDivisionOfLabourTests.swift`：`Click procedure calls the attempt command` 改成只看〈一層層按〉第 2 步那一行，並要求 `64`；新增 `The site key falls back to the page line`
- [x] 1.2 `Tests/AkashicCLITests/FulltextClickProcedureTests.swift`：其餘七條 requirement 的每個 Example 一支，帶 `spec-example: fulltext-division-of-labour / <Example 名稱>` 標記；另有不帶標記的幾支（verify 第 10、11、17、19、26、29、30 列的文字）
- [x] 1.3 驗證：`swift test --filter 'FulltextDivisionOfLabourTests|FulltextClickProcedureTests'` 在 5aa42d02 的 SKILL 上，每一支帶標記的新測試都失敗；`Division of labour section lists five classes` 與 `Retired hand-over sentences are gone` 照舊通過

## 2. SKILL 與出版商表 [after: 1.3]

- [x] 2.1 （Requirement: A login page on another host SHALL pause the whole run）〈人機分工〉(b) 限文章站本身；落點表第 6 種分主機；`left-site` 列恢復基底的整批暫停
- [x] 2.2 （Requirement: The skill SHALL read a page after a click with fixed read-only commands and check it for suspicion）規則 5 列出 `get url`、`get title`、`get text`、`get attr … href`；落點表前寫讀法，`get text` 交給 `bot-signals --kind`；第 1 步讀 href
- [x] 2.3 （Requirement: The landing table SHALL be judged in a fixed order and SHALL NOT lead to a second click on the same control）落點表的順序、第 2 種的條件、第 9 種等一次之後整張表再判、對不上任何一種列入交給人的清單、第 1 種的 `save-pdf` 探測
- [x] 2.4 （Requirement: The skill SHALL defer the rest of a site after a human check）(a) 的邊界、同站延後、同一個站怎麼認、按了之後的驗證頁沒有 `resume:`
- [x] 2.5 （Requirement: The click procedure SHALL have a closed list of entries）入口的封閉清單；`publishers.md` 的 EBSCO 那一段
- [x] 2.6 （Requirement: The skill SHALL list the mid-run stops as a closed list）六種停下、兩處中途詢問、定時讀取、帳本讀不懂整批停、Finder 改檔名移到最後
- [x] 2.7 （Requirement: Values from a page SHALL reach the shell through a variable）`$lock` 的取法與每個鎖分頁的命令
- [x] 2.8 （Requirement: Deferred hand-overs SHALL be done one at a time）第 7 步的一次一篇與 `.handover` 記號
- [x] 2.9 （Requirement: The skill SHALL count each click it makes）`--site` 的來源與結束碼 64
- [x] 2.10 其餘各列：規則 3 拿掉 `dialog dismiss` 的條件；規則 1 例外 (d) 收 `left-site` 之後顯示 PDF 的同一個分頁；`tab-unchanged` 寫明 `fetch` 的導航算第一下；「連續兩篇同樣的失敗」只算「取不到」；`browser-cache` 那一句；`publishers.md` 2026-11-10、2026-11-19 那一段只寫 issue 回報過的事
- [x] 2.11 驗證：1.1、1.2 的測試全部轉綠；以 grep 逐一核對改過的概念在 SKILL、description、publishers.md、兩份 changelog、work-sources.md、web-access 規則之間一致

## 3. 鏡像與程式文字 [after: 2.11]

- [x] [P] 3.1 `plugin/skills/akashic-bootstrap/references/work-sources.md` 取 PDF 的那一句改成新的分工
- [x] [P] 3.2 `.claude/rules/web-access-via-safari-browser.md`〈不適用〉第 3 類的例子改成登入、授權、付費，並指向 fetch-fulltext〈人機分工〉
- [x] [P] 3.3 `Sources/akashic/FulltextCommands.swift` 的 `fetch` 說明文字；`Sources/AkashicSkillTools/FulltextFetch.swift` 交接的各原因提示（`pdf-shown`、`unverifiable`、`left-site`）與兩處註解
- [x] 3.4 `plugin/CHANGELOG.md` 0.13.17 那一則、`changelog/2026-11-19-fulltext-ai-default-781.md` 補這一輪；`.githooks/plugin-shell-versions.txt` 0.13.17 那一列的摘要照改過的殼重算

## 4. 驗證 [after: 3.4]

- [x] 4.1 `swift build -Xswiftc -warnings-as-errors`、全套 `swift test`、`bash .githooks/run-guards.sh` 都通過；`spectra validate idd-781-fix1` 通過
