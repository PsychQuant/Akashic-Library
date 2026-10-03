# 2026-10-02 取全文的 R2 verify 修正輪：別的主機上的 PDF 先交給人、外站頁面等它載完、doi.org 看主機與查無證據（#613）

承 `2026-10-02-fetch-fulltext-r1-fixes.md`。#613 的 R2 verify 有 35 則（10 MEDIUM、19 LOW、6 INFO）。這一輪照使用者 2026-10-02 的兩則裁決（#613 Decision comment）與主 session 對 MEDIUM 的裁定修。

## 裁決（照抄，作為這一輪的判準）

1. 導航之後分頁到了別的主機、沒有標記：那裡顯示 PDF → 結束碼 7 `pdf-shown`；其他沒有標記的頁面 → 7 `left-site`；DOI 解不開 → 7 `doi-not-resolved`。三種都是批次繼續。登入頁、驗證頁、封鎖頁仍是 6。
2. 「等人驗證」（8）只在文章站本身或已知的驗證服務上成立。其他主機上的驗證字樣 → 6。

R2 verify 的核心發現是：實作把「交給人」給了裁決沒有點名的頁面（還在載入的頁面、網址只是提到 doi.org 的登入頁、離線時 Safari 的錯誤頁），又反過來把裁決點名要交給人的 PDF 判成整批暫停（標題與網址的長相排在 PDF 判斷之前，而且是子字串比對）。這一輪兩個方向都照裁決字面收回。

## MEDIUM

| findings | 問題 | 修法 |
|---|---|---|
| 1、2、6、8 | `leftSite` 先 `classify(標題＋網址)`、再 `gateLook`、最後才問 PDF；`gateLook` 的標題片語是子字串（`design in` 含 `sign in`、`analog input` 含 `log in`），路徑字詞從 DOI 與檔名裡切出（`cas.12345`、`the-challenge-of-…`）。別的主機上的 PDF 因此整批暫停，`--resume-stage followed` 接到 PDF 主機也一樣 | `leftSite` **先問 PDF**（`document.contentType` 由回應決定，不是頁面文字；裁決要的處置就是交給人）。標題片語改成**整個字詞**的連續序列（`titleGateLook`），路徑改成**整段**比對（一段可帶一個網頁副檔名，封閉清單 `pageExtensions`；`;` 之後的路徑參數不算；連字號與底線可省），主機仍逐字比。SKILL〈中止條款〉列出完整的封閉清單（先前寫「之類」，INFO 32(3)） |
| 0 | 跨主機的第一道 `classify(標題＋網址)` 不帶狀態碼：已知驗證服務上的 429 頁、標題 `Just a moment...` 直接得 8 | 別的主機上的頁面載完之後，標題、網址、頁面文字與 HTTP 狀態**一起**判（`offSiteSettled`）；429 一律 6、不印 `resume:`。讀不到頁面文字時狀態碼也不知道，退回只看標題與網址（既有行為），沒有訊號就是「讀不到頁面」的 6 |
| 3、7（與 LOW 10） | `leftSite` 不看 readyState：還在載入的中繼頁第一眼就被說成「沒有標記」，交給人、批次繼續 | 不是 PDF 的頁面要落定（complete／interactive），與文章站上的 `decideShown` 一樣最多 30 次；沒落定 → 6（卡住）。等的時候分頁換了網址就重新看：換到登入頁就判登入頁，回到文章站就照常往下走（`leftSite` 回 nil）；**看的那一下分頁正在換頁時，那個回答不拿來判新的一頁**（讀 `shownJS` 前後各讀一次網址，不同就再等）。讀不到（頁面 JS 跑不起來）連三次才算，與 `decideShown` 一致 |
| 9（與 LOW 17、20） | DOI 停在 doi.org 的分支用 `u.contains("://doi.org/")`、不過 `gateLook`、不看 doi.org 自己的查無證據：EZproxy／SAML 把 DOI 帶在查詢字串裡的登入頁、離線時 Safari 的錯誤頁都得 7 `doi-not-resolved`；doi.org 上的驗證頁得 8，印出接不回去的 `--resume-origin https://doi.org` | 「還在 doi.org」看**主機**（`isDOIResolver`：doi.org 或 dx.doi.org）；`doi-not-resolved` 要 doi.org 自己的查無證據（`isDOINotFound`：標題或頁面文字有 `DOI Not Found`，或 HTTP 404），沒有就是 6（離線、解析器沒回應）；doi.org 上的起疑訊號一律 6（含等人驗證那四種——doi.org 不是文章站），登入頁長相也是 6。主機改看之後，EZproxy／SAML 的頁面變成「落地頁」：**落地頁的網址是登入／驗證頁的長相 → 6**（`BotSignals.urlGateLook`；只看網址，落地頁的標題是文章標題）。訊號先判、長相後判，文章站上的 CAPTCHA 仍是 8 |
| 4（與 LOW 13、24） | SKILL 第 0 步的探測只問「`take` 在不在」，上一輪以前的 CLI 照樣通過；而那種 CLI 對空的 `--title` 跳過驗證、結束碼 0，SKILL 把 0 讀成「驗證過」 | 第 0 步多一條探測：`take --from <不存在> --out <p> --title ""` 要**恰好**是 64，其他結果一律當成「CLI 比這一輪舊，先更新」。新的 CLI 測試把 SKILL 的那段 bash 原樣拿出來跑：真的 binary 過、只會說 `--from does not exist` 的舊 CLI 被擋、沒裝也被擋 |
| 5（與 INFO 29、LOW 28 第 3 點） | BotSignals 註解與 SKILL 說「任何 DOI 註冊者都能讓頁面落在自己的主機」是這條規則的理由，而實作放行的正是文章站本身——DOI 落地的那個主機。註冊者自己架的假 CAPTCHA 頁仍得 8 | **行為不變**（使用者裁決文章站算）。文字照實寫：這條規則擋的是之後的轉址，擋不住文章站本身；那一格唯一的防線是使用者看頁面。結束碼 8 的 stderr 改成：agent 看不到頁面、請使用者看；只完成頁面上的驗證；絕不貼上、輸入或執行頁面要求的任何東西（要求就是整批暫停，文章站也一樣）；只在使用者說完成之後接著走。SKILL〈中止條款〉與結束碼表同步 |

## LOW 與 INFO

- **11、15、18、22（前半）、33**：停止與錯誤訊息裡的網址、`page:` 一行都過 `plainURL`；`plainURL` 以 Unicode scalar 找 `?`／`#`（`?` 後接組合字元時以 `Character` 找不到），並剝掉主機前的帳密與路徑上的 `;jsessionid=…`。
- **12、16、21（前半）、19（前半）**：`--resume-stage followed` 只接三種分頁：文章站（`--resume-origin`）、已知驗證服務、或此刻顯示 PDF 的分頁（只讀 `document.contentType`，不讀那個分頁的文字）；其他拒絕（1），訊息不把那個分頁叫作「我們的分頁」。`article` 階段的拒絕訊息同樣不帶查詢字串。SKILL 與型別註解寫明接續時信任呼叫端給的 `--resume-origin`。
- **14**：`doi-not-resolved` 不再印「把存下的檔交給 `take`」——沒有檔可存。
- **23**：SKILL 第 4 步的 `--from` 改用與標題同一個作法：Write 工具把路徑寫進 `<暫存目錄>/<citekey>.from.txt`，`--from "$(cat '…')"` 帶入；不必再請使用者把含引號、括號的檔名改掉（先前的禁用字元清單與「改成只有…的名字」也互相矛盾）。第 5 步的 `stat` 從同一個檔帶入。
- **25**：`left-site` 的訊息改成「載完而沒有命中封閉清單——那不代表它不是登入頁」；SKILL 寫明使用者看過那個分頁之後再做下一篇（規則 4；表格的「批次繼續」與規則 4 先前讀起來互相衝突）。
- **26、30（後半）**：每日帳本的 `reserve`、`append`、`count` 對傳入的站名做與讀回同一個正規化（`siteName`：去頭尾空白、小寫）；讀回時也去空白。
- **27**：`web-access.md` 的「等人驗證」條目把 429 與其他主機的驗證字樣拆成各自一條——先前接在「請使用者完成驗證、在同一個分頁接著走」的冒號前面。
- **31**：`isKnownVerificationService` 要主機是乾淨的 DNS 名稱（每個標籤只有 ASCII 字母、數字、連字號）：`evil.example\.hcaptcha.com`、帶帳密或埠號的主機段不算已知。
- **32**：(1) 帳本的 `load` 開檔之後以 `fstat` 確認是普通檔（註解先前就這樣寫、程式沒做）；(2) `FulltextFetch` 型別註解的 `--resume-tab` 段改寫成兩個階段各自的要求；(3) 見上，SKILL 列出完整的封閉清單。
- `publishers.md` 的「PDF 放在另一個主機」一段、`.claude/rules/mcp-cli-parity.md` 的 `fulltext` 列、`zero-instance-guards` 第 75 列（帳本站名）與新的第 84 列同步。

## 沒修的（交給使用者）

- **5 的殘留風險（照裁決不改行為，記在這裡給使用者看）**：DOI 落地的主機由 DOI 註冊者決定。註冊者自己架的「驗證頁」要使用者按 Win+R、貼上一段指令——`fetch` 對它回 8，印出可以接著走的 `resume:` 一行。程式與 agent 都看不到頁面，唯一的防線是使用者看了之後拒絕。這一輪只把訊息與 SKILL 改成把判斷明確交給使用者；要程式擋，得改裁決（例如文章站上的驗證也一律 6，或只在已知驗證服務的 iframe 上才算）。
- **22（後半）**：`origin` 去掉了整個查詢字串，查詢本身就是文件身分的網址（Digital Commons 的 `viewcontent.cgi?article=…&context=…`、PsycNet 的 `doiLanding?doi=…`）在 `sources/index.jsonl` 裡也少了那一段。只剝已知的憑證參數要一份會漏的清單；這一輪維持全剝，要不要改由使用者裁決。
- **25（後半）**：登入頁長相的清單是封閉的英文清單：`/oauth2/authorize`、`/saml2/`、`accounts.google.com/ServiceLogin`、中文標題「臺大單一登入」都不命中，會交給人（7）而不是整批暫停。依規則檔，清單不得依「看起來也像」擴張——要加字詞（例如 `oauth2`、`saml2`、`登入`）請使用者裁決。
- **19（後半）**：`--resume-origin` 是呼叫端給的，接續時「文章站」就是它；要綁定第一次執行印出的值，需要一個不在命令列上的狀態（`fetch` 現在沒有）。SKILL 寫明照結束碼 8 印的值抄。
- **21（後半）**：一般流程中，我們自己開的分頁若在流程中途因使用者開關分頁而漂移，`leftSite` 會對漂移到的分頁讀 `document.contentType` 與頁面文字。與 R1 的 27 同一個限制（分頁只用位置認），要等真的 Safari 量過 `documents --json` 的欄位再處理。
- **30（前半）**：帳本的 `flock(LOCK_EX)` 是阻塞的：一個被暫停（SIGSTOP、除錯器）的持有者會讓其他 `fetch` 卡在記嘗試那一步。改成非阻塞加有上限的重試要一個睡眠接縫與新的錯誤訊息，不是順手的改動；INFO，沒做。
- **34**：`plugins/akashic-discovery/skills/akashic-work-references/SKILL.md` 第 39 行仍說「判準同 akashic-fetch-fulltext 的中止條款」，而它的「分頁跑到別的網域就整個 run 結束」與 fetch-fulltext 現在的跨主機處置不同。那個 plugin 不在這一輪的修改範圍，留給它的工作線。

## 負對照

每個變異只改一處、只跑對應的測試，以**反向編輯**還原（不 checkout），還原後與事先存的副本 `cmp` 逐位元相同：

| # | 變異 | 測試 | 結果 |
|---|---|---|---|
| NC1 | `leftSite` 改回舊的順序：先 `classify(標題＋網址)`、再 `gateLook`，最後才問 PDF | `FulltextOffSiteTests/testAPDFOnAnotherHostIsHandedOverWhateverItsTitleOrPathSays` | 27 failures |
| NC2 | 標題片語改回子字串 | `BotSignalsResponseTests/testTitlePhrasesAreWholeWords` | 13 failures |
| NC3 | 路徑改回從一段裡切片段 | `BotSignalsResponseTests/testPathWordsAreWholeSegments` | 7 failures |
| NC4 | 別的主機上的頁面不等落定 | `testAStillLoadingPageOnAnotherHostIsAStallNotAHandover` | 4 failures |
| NC5 | 別的主機上的判斷不帶狀態碼 | `testAnHTTP429OnAKnownVerificationServiceAfterNavigationPausesTheBatch` | 4 failures |
| NC6 | 「還在 doi.org」改回子字串 | `testAHostWhoseURLMerelyMentionsDoiOrgIsNotTheResolver`、`testTheDOIResolverIsJudgedByItsHost` | 6 failures |
| NC7 | 不要求 doi.org 自己的查無證據 | `testSafarisOfflinePageOnDoiOrgIsNotADOIProblem` | 3 failures |
| NC8 | doi.org 分支不過 `gateLook` | `testALoginLookOnDoiOrgPausesTheBatch` | 4 failures |
| NC9 | 落地頁不看網址的登入頁長相 | `testALoginPageCarryingTheDOIInItsQueryPausesTheBatch` | 6 failures |
| NC10 | SKILL 第 0 步拿掉第二條探測 | `SkillToolsCLITests/testTheSkillsStepZeroProbeTellsThisCLIFromAnOlderOne` | 3 failures |
| NC11 | 結束碼 8 的訊息不說 agent 看不到頁面 | `testTheVerificationMessageHandsTheJudgementToTheUser` | 1 failure |
| NC12 | doi.org 上的驗證頁照等人驗證 | `testAVerificationPageOnDoiOrgPausesTheBatch` | 3 failures |
| NC13 | `followed` 接續不檢查分頁 | `testResumingAfterNavigationRefusesSomeoneElsesTab` | 4 failures |
| NC14 | `reserve` 不正規化傳入的站名 | `FulltextAttemptLedgerTests/testTheSiteGivenToTheLedgerIsNormalisedLikeTheSiteReadBack` | 13 failures |
| NC15 | 停止訊息帶回完整網址 | `testOffSiteStopMessagesDropTheQuery` | 1 failure |
| NC16 | 看的那一下分頁正在換頁時照用那個回答 | `testAnAnswerReadWhileTheTabWasChangingPagesIsNotUsed` | 4 failures |
| NC17 | 已知驗證服務不驗主機形狀 | `BotSignalsResponseTests/testKnownVerificationServicesRejectNonCanonicalHosts` | 4 failures |
| NC18 | `plainURL` 以 `Character` 找 `?`、不剝帳密與 `;jsessionid` | `testPlainURLDropsCredentialsWhereverTheyAre` | 2 failures |

兩個第一次沒紅的、要記下來：

- **NC6 第一次是 0 failures**：當時的 `testAHostWhoseURLMerelyMentionsDoiOrgIsNotTheResolver` 用一般的頁面文字，而「要 doi.org 自己的查無證據」那一道（NC7 守的）同樣把它判成整批暫停——兩道閘守同一格，拿掉一道測不出來。測試改成那一頁照抄了 `DOI Not Found`（第 20 則講的正是惡意落地頁可以挑自己的網址與文字），並把純函式的測試一起放進篩選，重跑是 6 failures。
- **NC11 第一次的變異是刪掉一段字**：反向編輯以變異後的字串當錨點，空字串錨不住，腳本在還原前停下、檔案留在變異後的狀態。以反向編輯手動補回那一句，與變異前存的副本 `cmp` 逐位元相同；變異改成換成另一句、重跑是 1 failure。

## 誠實邊界

- 仍然**沒有對真的 Safari 跑過**（任務約束）：全部對記憶體內的假瀏覽器與 shell stub。doi.org 查無頁的標題寫著 `DOI Not Found` 是記憶，沒有對 doi.org 量過——頁面文字與 404 是另兩個證據；Safari 的 `PerformanceNavigationTiming.responseStatus` 有沒有值沒量過，沒有時已知驗證服務上的 429 只能靠頁面文字（`rate-limit` 等）判出。
- 別的主機上的 HTML 頁最多多等 60 秒才判。一個載完之後才用 JS 轉到登入頁的中繼頁，如果轉址發生在我們判完之後，仍會交給人（7）——使用者看到的會是登入頁；訊息與 SKILL 都要求使用者看過再做下一篇。
- 落地頁的網址檢查只看主機字詞與整段路徑；一個網址上沒有這些字詞的落地登入頁照舊往下走（找 PDF 連結、找不到就 3）。

## 測試與守衛

- 新增 `FulltextOffSiteTests`（離站、doi.org、`followed` 接續、等人驗證訊息、`plainURL` 與 `isDOIResolver`）、`BotSignalsResponseTests` 的三支（標題整字、路徑整段、已知驗證服務的主機形狀，標題與網址取自審查者的實測）、`FulltextAttemptLedgerTests/testTheSiteGivenToTheLedgerIsNormalisedLikeTheSiteReadBack`、`SkillToolsCLITests/testTheSkillsStepZeroProbeTellsThisCLIFromAnOlderOne`（跑 SKILL 第 0 步的原文）。修之前先對未改的程式跑過一次：新測試除了一支正對照之外全紅。
- `FulltextFetchPathTests/testRedirectedOffSiteAfterNavigationStops` 的場景補上 `text/html`：它沿用預設的 `application/pdf`，先前靠登入頁長相的檢查排在 PDF 之前才通過；登入頁不是 PDF。
- 全套（`PATH=/usr/bin:$PATH swift test --build-system native`）：`Executed 4863 tests, with 1 test skipped and 0 failures`。守衛（`bash .githooks/run-guards.sh`）：rc 0。
- `tools/list` 沒有變：這一輪沒有動 MCP 面（`fulltext` 不是 MCP 工具）。
