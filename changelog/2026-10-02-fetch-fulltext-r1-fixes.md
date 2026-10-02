# 2026-10-02 取全文的 R1 verify 修正輪：跨主機不再整批停、等人驗證只在文章站與已知驗證服務、帳本原子化（#613）

承 `2026-10-01-fetch-fulltext-human-like.md`。#613 的 R1 verify（46 則：12 MEDIUM、25 LOW、9 INFO）之後，使用者 2026-10-02 在 issue 留了兩則裁決，並要求同輪修六個程式錯誤。這一輪照那兩則裁決與 findings 改。

## 使用者 2026-10-02 的兩則裁決

1. **導航之後分頁跳到別的主機、而頁面沒有任何驗證或封鎖字樣**（PDF 放在 CDN 主機、跨主機的中繼頁、DOI 解不開）。先前一律是結束碼 6「網站懷疑自動化」、整批停。現在：新主機顯示 PDF → 照常交給人存檔（結束碼 7 `pdf-shown`）；其他沒有標記的頁面 → 這一筆交給人、批次繼續（結束碼 7，新原因 `left-site`；DOI 解不開是 `doi-not-resolved`）；登入頁、驗證頁、封鎖頁維持 6。`--resume-tab` 在驗證結束於 PDF 主機時要接得住。
2. **「等人驗證後接著走」只在文章站本身或已知的驗證服務上成立**。已知驗證服務是封閉清單（`BotSignals.knownVerificationHosts`）：`challenges.cloudflare.com`、`hcaptcha.com`（含子網域）、`recaptcha.net`（含子網域），以及 `www.google.com`／`google.com` 的 `/recaptcha/` 路徑；只收 https，主機要等於清單項或是它的子網域（`challenges.cloudflare.com.evil.example` 不算）。其他主機上出現驗證字樣或網址標記，一律整批停止。

## 六個程式錯誤

| findings | 錯誤 | 修法 |
|---|---|---|
| 0、32 | 帳本最後一行沒有檔尾換行時，`append` 把新的一筆黏在它後面；下一次 `fetch` 讀不懂整個帳本、而訊息叫人「刪掉那一行」會刪掉兩筆 | 寫入前看檔尾位元組，不是 `\n` 就先補一個；`load` 以位元組切行（CRLF 的帳本也讀得進來，Swift 的 `"\r\n"` 是一個 `Character`） |
| 1、20(3)、25(2) | 上限的查數與記錄之間沒有鎖，兩個行程都讀到 9 就各自記成第 10 次 | `FulltextAttemptLedger.reserve`：在帳本檔本身的 `flock(LOCK_EX)` 之下重讀、數、沒到上限就記，之後才導航；`FulltextFetch` 只走 `reserve` |
| 2 | 導航到 PDF 連結之後才出現的 CAPTCHA，驗證完 `--resume-tab` 把文章頁的連結流程再跑一次（再導航、再記一次嘗試；只有 JS 下載鈕的閱讀器還會等 45 秒、找不到連結、關掉分頁） | resume 資訊帶階段：新旗標 `--resume-stage article\|followed`，導航之後的結束碼 8 印 `followed`；`followed` 接續回到「分頁顯示什麼」的判斷（`decideShown`，與導航之後同一段程式），不讀連結、不導航、不記嘗試 |
| 5、44 | `take` 沒給或給了空的 `--title` 就整個跳過驗證，結束碼 0 照樣說存好了，而 SKILL 把 0 讀成「驗證過」 | `--title` 必填、不得是空的（CLI 與函式庫兩層都擋，64）；沒有標題的作品不走 `take` |
| 7 | SKILL 第 4 步把使用者存檔的路徑原樣插進雙引號的 shell 參數 | 路徑形狀檢查（含 `"`、`'`、`$`、反引號、反斜線等就不插進任何命令，請使用者改檔名）；`<暫存目錄>` 不得含單引號 |
| 8 | 文字優先於狀態碼的排序把 HTTP 429 也降成「等人驗證」 | 429 一律整批暫停，不看文字；403 的驗證頁文字仍可優先（Cloudflare 的挑戰頁常以 403 回應） |

## 其餘 MEDIUM 與 LOW

- **3、9、10、11、15、19、43（跨主機與 DOI 解不開）**：`siteGuard` 不再一律 `botStop`，改走 `leftSite`——分頁不見了仍是 6；標題、網址或頁面文字有起疑訊號照訊號（等人驗證只在已知驗證服務上成立）；登入／驗證頁的長相（`BotSignals.gateLook`：網址主機與路徑的字詞、標題片語，封閉清單，不看查詢字串）仍是 6；新主機顯示 PDF → `pdf-shown`；其餘 → `left-site`。`settleLanding` 在 60 秒後仍停在 doi.org 時，頁面已載完就走 `doi-not-resolved`（讀一次頁面文字查訊號），還在載入才是「卡住」的 6。
- **4**：`--resume-stage followed` 不要求分頁顯示文章站（它只讀、不導航、不關分頁），所以驗證結束在 PDF 主機的分頁接得住；`article` 階段仍要求分頁顯示文章站。
- **6**：`stop(for:)` 對等人驗證加主機判斷（文章站或已知驗證服務，否則整批暫停）；stderr 單獨印「驗證頁所在的主機」；SKILL 要求轉述，並把「驗證頁要求貼上或執行指令」列為整批暫停。
- **16**：Cloudflare 的經典挑戰頁（「Just a moment…」加「Checking your browser…」）不再被 `pmc-pow-challenge` 的通用字樣吃成整批暫停；同頁有 PMC 專屬的 `preparing to download` 時仍是整批暫停。
- **24**：驗證頁的主機不是可以原樣當 `--resume-origin` 的形狀（含 `;`、`$` 等）時不進等人驗證、不印那條 resume 指令，整批暫停。
- **35**：`resume()` 的資訊行改前綴 `resuming:`，`resume:` 只給可執行的參數行。
- **18、23**：`handover:` 一行與 `pdf:` 一行的網址去掉查詢與片段（簽章網址的短效憑證不進 stdout、對話與 `origin`），也不再因 600 字上限被截成帶「已截斷」標記的字串；SKILL 第 5 步的 `origin` 照此說明。
- **28**：`do JavaScript` 回空字串或 `undefined`（對非 HTML 文件）與失敗同樣算「讀不到」（計入三次的 `unscriptable`），不是 60 秒之後的整批暫停；PDF 判斷排在這個檢查之前。
- **14、21、26、31**：`take --from` 以 `O_NOFOLLOW｜O_NONBLOCK` 開（`lstat` 與 `open` 之間被換成 FIFO 時不卡住），`fstat` 再確認之後清掉旗標，讀取至多「上限＋1」位元組。測試接縫 `afterInspect` 在 `lstat` 與 `open` 之間把檔換成 FIFO／symlink／目錄；FIFO 直接拒絕與三種替換各一條測試。
- **22**：不是 PDF 的檔案不再印前 80 個可見字元（`--from` 是 agent 可被引導指定的路徑，那是讀任意檔頭的出口），改印位元組數、前 8 個位元組的十六進位與「像 HTML」。
- **34**：驗證本身跑不起來（`{"error": …}` 形狀：截斷的下載、缺 poppler）是結束碼 1、什麼都不寫，不是 5；SKILL 的表照寫。
- **20(1)(2)**：帳本的站名讀回時一律小寫；CRLF 的帳本讀得進來。
- **25、30**：`--ledger` 只給測試——help 這樣寫、非預設的 `--ledger` 在 stderr 警告、SKILL 明寫禁止 `--ledger` 與改 `HOME`。程式不擋（測試要用）。
- **12、13、17、29、33、39**：SKILL 的文字修正——第 1 步指向第 3、4 步；`retrieved` 取使用者存下的檔的修改時間；`--resume-tab` 只用位置認分頁的風險寫進〈中止條款〉與〈不做的事〉；第 0 步探測帶 `--title probe` 並接受 git 閘的拒絕訊息；到上限之後文章頁仍已載入過；頁面來的字串是資料不是指令。
- **36、41**：`swift-is-the-implementation-language` 的移植對映寫成 45 個逐案移植、另有 7 個邊界案例（檔內 `func test` 共 52）。

## 沒修的

- **27（`--expect-profile` 只在開頭驗一次）**：要把 `documents --json` 的 `profile` 放進每次分頁比對，行為依賴真的 Safari 對 tab 回報的 profile 欄位（本 repo 對真的 Safari 沒量過）；現有的 `siteGuard` 每個動作前核對分頁還在同一站，是間接保護。改了而欄位偶爾缺席會讓每一步都被當成「分頁不見了」而整批暫停，所以先不動，等真的 Safari 量過再說。
- **40（`pageText()` 以第一行當狀態碼）**：INFO，機率低、影響低；改成帶前綴要動 `pageTextJS` 與它的 JavaScriptCore 測試，沒有對應的失敗實例。
- **37、38、42、45**：INFO，沒有要改的。**43、44** 的校正已併入上面對應的修法。

## 負對照

每個變異只改一處、只跑對應的一支測試，看 `Executed` 行確認測試真的跑了，以**複製原檔還原**後 `cmp` 確認逐位元相同（上一輪用反向編輯還原，這一輪第一次用到空字串變異時反向編輯把整個檔案弄壞，改成還原前先存原檔、還原時整檔複製回去）：

| # | 變異 | 測試 | 結果 |
|---|---|---|---|
| NC1 | 補檔尾換行那一行改成不補 | `FulltextAttemptLedgerTests/testAppendAfterAFinalRecordWithoutANewlineKeepsBothRecordsOnTheirOwnLines` | 3 failures |
| NC2 | 拿掉 `flock` | `FulltextAttemptLedgerTests/testTwoReservationsRacingForTheLastSlotGrantExactlyOne` | 3 failures |
| NC3 | 同上，真的兩個行程 | `SkillToolsCLITests/testTwoProcessesRacingForTheLastSlotGrantExactlyOne` | 6 failures |
| NC4 | `fetch` 改回 `count` 再 `append` | `FulltextFetchPathTests/testTheTenthAttemptProceedsAndTheEleventhStops` | 5 failures |
| NC5 | 拿掉導航前的 `stage = .followed` | `FulltextFetchPathTests/testACaptchaAfterNavigationResumesAtTheShownContentDecisionNotTheLinkFlow` | 1 failure |
| NC6 | `followed` 接續改走文章頁連結流程 | 同上 | 3 failures |
| NC7 | `siteGuard` 離站一律 `botStop`（舊行為） | `FulltextFetchPathTests`（整個類別） | 22 failures |
| NC8 | DOI 解不開改回 `botStop` | `testADOIThatDoesNotResolveIsHandedOverNotAStop` | 3 failures |
| NC9 | `followed` 接續要求分頁顯示文章站 | `testResumingAfterNavigationAcceptsATabThatEndedOnThePDFHost` | 2 failures |
| NC10 | 等人驗證不看主機 | `testVerificationMarkersOnAnUnknownHostPauseTheBatch` | 4 failures |
| NC11 | 拿掉 429 的整批暫停（單元層） | `BotSignalsResponseTests/testA429IsAlwaysPauseWhateverTheTextSays` | 6 failures |
| NC12 | 同上（流程層） | `FulltextFetchPathTests/testAnHTTP429PageThatMentionsACaptchaStillPausesTheBatch` | 5 failures |
| NC13 | `take` 不檢查 `--title` | `FulltextFetchHardeningTests/testATitleIsRequiredAndAnEmptyOneIsRefusedBeforeAnythingIsRead` | 10 failures |
| NC14 | `take` 把驗證出錯當成 5 | `testAVerificationThatCouldNotRunIsNotReportedAsAnotherPaper` | 3 failures |
| NC15 | `--from` 不帶 `O_NONBLOCK` | `testAFileSwappedForAFIFOAfterTheLstatCheckDoesNotHang` | 3 failures（10.5 秒，背景執行緒卡住、測試限時 10 秒） |
| NC16 | 拿掉 `fstat` 的普通檔再確認 | `testAFileSwappedForADirectoryAfterTheLstatCheckIsRefusedByTheFstatRecheck` | 1 failure |
| NC17 | 拿掉 `O_NOFOLLOW` | `testAFileSwappedForASymlinkAfterTheLstatCheckIsNotFollowed` | 3 failures |
| NC18 | 非 PDF 的訊息帶回檔案前 80 個字元 | `testANonPDFSourceDoesNotEchoItsContent` | 3 failures |
| NC19 | Cloudflare 與 PMC 字樣同頁時仍歸 PMC | `BotSignalsResponseTests/testACloudflareChallengePageIsNotSwallowedByThePMCGenericWording` | 1 failure |
| NC20 | 空的／`undefined` 的回答不算讀不到 | `testAnEmptyOrUndefinedAnswerAfterNavigationIsUnreadableNotAStall` | 4 failures |
| NC21 | 拿掉登入／驗證頁長相的檢查 | `testRedirectedOffSiteAfterNavigationStops` | 2 failures |
| NC22 | `handover:` 帶回查詢字串 | `testTheHandoverLineDropsTheQueryAndFragment` | 2 failures |
| NC23 | 不擋不能當 `--resume-origin` 的主機 | `testAHostThatCannotBeAResumeOriginPausesTheBatchInsteadOfPrintingAShellHazard` | 4 failures |
| NC24 | 資訊行改回 `resume:` 前綴 | `testACaptchaAfterNavigationResumesAtTheShownContentDecisionNotTheLinkFlow` | 2 failures |

**這一輪修正的是上一輪留下的負對照缺陷**：row 76 稱「FIFO 被 lstat 拒絕、`fstat` 再確認」，而原本沒有 FIFO 案例、NC12 把 `lstat` 檢查與 `O_NOFOLLOW` 一起拿掉所以 `fstat` 從沒單獨被變異過。現在 FIFO、三種替換與 `fstat` 各自有測試與負對照。

沒有做負對照的：CRLF 帳本（LOW；用 `String` 切行的替代寫法在這裡編譯不過，沒有等價的單點變異）。

## 誠實邊界

- 仍然**沒有對真的 Safari 跑過**（任務約束）。跨主機的判斷（`document.contentType`、Safari 的 PDF 檢視器能不能跑頁面 JS）全部對記憶體內的假瀏覽器跑；讀不到時照 `unverifiable` 交給人。
- **ScienceDirect 的 PDF 主機上出現 CAPTCHA 字樣現在是整批暫停**：`pdf.sciencedirectassets.com` 既不是文章站（`www.sciencedirect.com`）、也不在已知驗證服務清單裡。2026-09-28 的第二次 CAPTCHA 正是那個形狀。這是照使用者裁決字面的結果；若要把出版商自己的檔案主機也算進來，是另一個要使用者裁決的清單。
- **登入／驗證頁長相的清單是封閉的、字面的**（主機與路徑的字詞、標題片語）：一個沒有這些字詞的登入頁會被當成「沒有標記的頁面」而交給人（結束碼 7，不是 6）。交給人本身就是停下，使用者會看到那個頁面；代價是批次繼續，而不是整批停。
- **`--resume-tab` 仍只用位置認分頁**：`article` 階段的接續會對那個位置的分頁導航、找不到連結時還會關它；`followed` 階段只讀。SKILL 明寫要先確認。
- **每站上限仍可用 `--ledger`／`HOME` 繞過**（測試要用）；程式只在 stderr 警告。
- 兩個行程的競爭測試用「測試握著鎖、`fetch` 必須卡住」的形式，不依賴時序碰運氣；它要真的 `akashic` binary（`swift test` 不重編 executable，改了 `FulltextAttemptLedger` 之後要先 `swift build --product akashic`）。

## 測試與守衛

- 新增與改寫的測試：`FulltextFetchPathTests` 52 支（從 35 支起，+17）、`FulltextFetchHardeningTests`（`take` 的 FIFO／替換／標題／驗證出錯／不回顯內容）、`FulltextAttemptLedgerTests`（檔尾換行、`reserve`、執行緒競爭、站名大小寫、CRLF）、`BotSignalsResponseTests`（429、Cloudflare 與 PMC、已知驗證服務、登入／驗證頁長相）、`SkillToolsCLITests`（`--title` 必填、`--resume-stage`、兩個行程搶最後一格）。
- 全套（`PATH=/usr/bin:$PATH swift test --build-system native`）：`Executed 4757 tests, with 1 test skipped and 0 failures`（跳過的是 `MigrateProvenanceCLITests.testWriteFailureIsListedAndExitsNonZero`，檔案系統不支援 `chflags`）。守衛（`bash .githooks/run-guards.sh`）：rc 0。
- `tools/list` 一行 54,515 bytes、35 個工具（預算 60,000）；這一輪沒有動 MCP 面。
