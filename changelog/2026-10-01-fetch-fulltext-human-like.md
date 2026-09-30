# 2026-10-01 取全文只用導航、存檔交給人、每站每天 10 次嘗試（#613）

2026-09-28 一晚三次 CAPTCHA，每一次都緊跟在一個真人不會做的動作之後：頁內以 JS fetch PDF 端點、對已顯示的 PDF 再發一次請求、導航前先以 curl 打網站。使用者當晚定下最高原則「跟真人一樣」與五條展開規則，2026-10-01 補了兩個待決點（ScienceDirect「Preparing your download」是起疑訊號；每站每天 10 篇），同日再裁決實作時撞到的設計分岔（#613 的三則 Decision）。這一輪照那三則改 skill 與 `akashic fulltext` 子命令。

## 改了什麼

**`akashic fulltext fetch` 只導航、交給人**（`Sources/AkashicSkillTools/FulltextFetch.swift`，整個重寫）：

- 開 `--landing`（`https://doi.org/<DOI>`）→ 等頁面落定、檢查起疑訊號 → 等頁面自己的 PDF 連結 → 記一次嘗試 → 把**同一個分頁**導到那個連結（`safari-browser open --window N --tab-in-window T <連結>`）→ 看分頁顯示什麼 → 交給人。
- **沒有頁內取檔**：`fetchJS`（`fetch(…, credentials:'include')`）、base64 讀回、`window.__aff`、暫存目錄都刪了。PDF 的位元組由使用者存。
- **不拼網址**：`PdfUrlRules`（SAGE `?download=true`、Wiley `pdfdirect`、PsycNet `/fulltext/<id>.pdf`）與 `akashic fulltext url-rule` 刪除；`URLSplit` 搬到自己的檔。`hasLinkJS`／`linkJS` 不再找 PsycNet 的 `/record/` 連結（那只是給拼網址規則取 id 用的）。
- **按鈕交給人**：頁面的下載是表單（Annual Reviews 型）時不代送，交給人（`button`）。
- **`--prime` 拿掉**：它只是為了讓之後的頁內 fetch 過得了 PMC 的驗證頁；導航本來就像讀者點連結，而 PMC 的下載前驗證頁依 2026-10-01 的裁決是整批暫停。
- **注入頁面的 JS 全部是運算式**（`readyStateJS`、`pageTextJS`、`hasLinkJS`、`linkJS`、`shownJS`，`injectedExpressions` 一份清單）。`safari-browser js` 先把程式碼當運算式包一次、解析失敗才退回函式本體（它的 `JSWrapper`），所以舊的 `return …` 敘述形第一次注入就是一段解析不了的程式碼。頁面的錯誤處理器看不看得到那個解析錯誤沒有實測；使用者訂規則 5 的理由是 NVA 的 Matomo 記錄了 agent 的 SyntaxError。
- `pageTextJS` 另讀頁面自己的 `PerformanceNavigationTiming.responseStatus`（已載入的資料，不發請求），補回導航之後看不到的 403／429；Safari 有沒有這個值沒有實測，沒有時那一行是空的。
- 導航之後的判斷：分頁 20 秒沒離開文章頁 → `tab-unchanged`（連結可能直接觸發下載）；`document.contentType` 含 pdf → `pdf-shown`；HTML 頁落定 → 查起疑訊號、沒有就 `html-page`；頁面 JS 連三次跑不起來（Safari 的 PDF 檢視器可能不能跑頁面 JS）→ 只看標題與網址，有訊號照訊號、沒有就 `unverifiable`；60 秒沒落定 → 整批暫停。
- 比對分頁還在不在同一個站時主機不分大小寫（先前比字面；導航之後瀏覽器可能把主機改成小寫）。

**結束碼**：

| 碼 | 之前（`fetch`） | 之後（`fetch`） | 之後（`take`） |
|---|---|---|---|
| 0 | 取得且驗證通過 | 不再出現 | 存好且驗證是這篇（或沒給 `--title`） |
| 1 | 自動化失敗、連結指到別站、轉址到別站 | 自動化失敗、連結指到別站、帳本讀不懂、`--resume` 的分頁對不上 | `--from` 不是普通檔或太大、輸出目的地不合、git 閘拒絕 |
| 2 | 回應不是 PDF | 不再出現 | `--from` 不是 PDF，什麼都沒寫 |
| 3 | 找不到 PDF 連結 | 同 | — |
| 4 | 無權限（登入殼） | 不再出現（登入殼是 `html-page`，由人判斷） | — |
| 5 | 是 PDF 但不是這篇 | 不再出現 | 同（`*.unverified.pdf`） |
| 6 | 整批停止（所有起疑訊號） | 整批暫停（等人驗證的四種以外的訊號） | — |
| 7 | — | **交給人** | — |
| 8 | — | **等人驗證**（`--resume-tab`／`--resume-origin` 在同一個分頁接著走） | — |
| 9 | — | **這個站今天已經 10 次嘗試** | — |

`fetch` 沒有 0：它的正常終點是交給人。舊的呼叫端把 0 讀成「檔案存好了」，新的碼不會被讀錯；拿掉的旗標（`--out`、`--title`、`--pages`、`--doi`、`--prime`）讓舊的呼叫以 64 失敗。

**`akashic fulltext take`**（新，`FulltextTake.swift`）：收使用者存下來的本機檔。不碰瀏覽器、不連網、不寫 store；`--from` 只讀一次進記憶體（`lstat` 是普通檔、`O_NOFOLLOW`、`fstat` 再確認、不超過 `LibraryStore.maxSourceBytes`），同一份位元組寫進 0700 的暫存目錄給 `verify` 讀、再寫到 `--out`——驗的就是存的。輸出目的地的檢查、原子替換與 git 閘是原本 `fetch` 的那一份，搬過來（`*.response.txt` 不再有）。`verdictJSON` 也搬過來，`fulltext verify` 改呼叫它。

**起疑訊號分兩種處置**（`BotSignals.classify`）：

- 等人驗證只有四個標籤（封閉列舉 `humanVerificationLabels`）：`captcha`、`human-check`、`cloudflare-challenge`、`perimeterx-press-and-hold`。PerimeterX 原本的一個標籤拆成按住驗證與封鎖句兩個。
- 新標籤 `sciencedirect-download-challenge`（`preparing your download|cra_js_challenge`），整批暫停。
- 優先順序：文字裡的整批暫停標籤 → 文字裡的等人驗證標籤 → 狀態碼 403／429。第二條排在狀態碼前面是這一輪的判斷，不是裁決原文：Cloudflare 的挑戰頁依它的文件以 403 回應（沒有實測），狀態碼若優先，使用者列為等人驗證的「Just a moment」在看得到狀態碼時就永遠走不到等人驗證。
- `detect` 回 `classify` 的標籤（同一套順序）。`bot-signals --kind` 以 tab 分隔印 `verify`／`pause`；命中的結束碼仍一律 0，舊的呼叫端（以 0＝停寫成）不會把等人驗證讀成「沒有訊號」。

**每站每天 10 次嘗試**（`FulltextAttemptLedger.swift`）：準備導航到 PDF 連結（或把按鈕交給人）的那一刻就在帳本記一筆，之後失敗也算；站以文章頁的主機（小寫）區分，日界是 Asia/Taipei，時間一律帶 `+08:00`。帳本預設在 `$HOME/Library/Application Support/akashic/fulltext-attempts.jsonl`：

- **不放 `$AKASHIC_HOME/state/`**（協調者提的位置）：`~/.akashic` 就是 `main` store 的 root 與資料 git repo 的根，它的 `.gitignore` 只排除 `config.yaml`、`index/`、`sources/`，`state/` 會變成資料 repo 裡未追蹤的檔（2026-10-01 以 `git check-ignore` 確認）。
- **不從 `sources/index.jsonl` 推算**：`fetch` 不碰 store；index 只記存進去的成功，失敗的嘗試不會出現；index 的 `origin` 是 PDF 的主機（`pdf.sciencedirectassets.com`）而不是文章頁的；`retrieved` 是沒有強制時區的自由字串。
- 讀不懂（不是普通檔、有一行不是 `{"at": 帶偏移的 ISO 8601, "site": 主機}`）就在開任何分頁之前拒絕。

**等人驗證之後在同一個分頁接著走**：`--resume-tab T --resume-origin https://<主機>`。不開新分頁、不重新載入；那個位置的分頁此刻必須顯示那個 origin，否則拒絕（使用者把視窗拉到前面時視窗編號會變）。分頁已經顯示 PDF（驗證發生在導航之後）就直接交給人、不再記一次嘗試；分頁回到文章頁就照常讀連結、導過去。

**零實例守衛**：`zero-instance-guards` 加第 75 列（帳本讀不懂就拒絕）與第 76 列（`take --from` 只收普通檔、只讀一次、上限同 `store-source`），各有一條「理由」bullet；第 62、63 列註明那兩道閘 #613 起在 `take`。

**文件**：skill 的 `SKILL.md` 改寫（頂端警告舊的頁內取檔路徑、最高原則與五條、兩種中止處置、每站上限、`fetch`／`take` 兩步、第 0 步以 `take` 的真呼叫探測 CLI 版本）；`publishers.md` 改寫成導航版並收錄 EBSCO APA PsycInfo 管道；`web-access.md` 的中止條款與區塊二同步（`--kind`、讀頁面的 JS 改成運算式、第 4 點的探測帶 `--kind`）；`.claude/rules/web-access-via-safari-browser.md` 的中止條款、〈操作程序的兩份描述〉第 (9) 條與〈觸發過的實例〉一列；`mcp-cli-parity` CLI-only 表的 `fulltext` 列；`swift-is-the-implementation-language` 的移植對映；`work-sources.md` 的只讀用法；`WriteGateRulings`（刪 `fulltext url-rule`、加 `fulltext take`、改 `fulltext fetch` 的理由）。

## 開放典藏的例外

決定原文：「開放典藏（機構 repository、S3 預簽章的公開檔）不在此限」。SKILL.md 照原文寫，只放寬規則 1、只對那兩種來源，並寫明**本 skill 目前沒有用到它**——開放典藏也走導航、交給人。要用這個例外，得先由使用者裁決怎麼認定一個站是開放典藏；這一輪沒有替它寫任何程式路徑。

## EBSCO APA PsycInfo 管道

2026-09-28 的步驟 4–5（在閱讀器分頁頁內 fetch 同源 API 取得取件網址，再導到 `content.ebscohost.com` 頁內 fetch）**沒有只用導航的寫法**：前者是頁內發請求（規則 1），後者就算改成純導航，也是對閱讀器已載入的同一份檔再發一次請求（規則 2）。所以 publishers.md 寫成：搜尋 → 詳細頁 → 閱讀器（都是導航），之後請使用者用閱讀器的下載鈕存檔、交給 `take`。這個管道沒有接進 `fetch`（`fetch` 從 doi.org 出發，走不到 EBSCO 的搜尋）。

## 測試

- `FulltextFetchPathTests`（重寫，35 支）：主路徑交給人、注入的 JS 沒有任何取檔的東西（`fetch(`、`XMLHttpRequest`、`credentials`、`location.href`…）且只有固定的五段、拼網址規則不在了、導航之後的五種交給人、ScienceDirect 中介頁與 403 整批暫停、驗證頁等人、表單按鈕不代按、每站上限（第 10 次過、第 11 次擋；臺北日界、別站不算、隔天重算）、帳本讀不懂或是 symlink 時在碰瀏覽器之前停、`--resume` 的五種情形。
- `FulltextFetchHardeningTests`（重寫，37 支）：`fetch` 的 `--landing` 形狀與頁面連結的來源限制（導航版）；`take` 的 `--from` 限制、輸出目的地、原子替換、驗證、git 閘（原本對 `fetch` 的那些搬過來）、暫存目錄 0700。
- `FulltextHumanLikeTests.swift`（新）：`BotSignalsResponseTests`（四種等人驗證、其餘整批暫停、整批暫停優先、驗證頁以 403 回應仍等人）、`FulltextAttemptLedgerTests`（`+08:00`、臺北日界、檔 0600／目錄 0700、沒有偏移的時間拒收、symlink 拒寫、預設路徑在 store 之外）、`FulltextJavaScriptTests`（JavaScriptCore 照 safari-browser 的運算式包法解析每一段；負對照：解析器真的會拒絕敘述形；在假 document 上跑出期待的形狀、沒有 navigation timing 時不拋錯）。
- `FulltextRulesTests`：拼網址規則的 9 支隨規則刪除（54 → 45 支移植測試）；`testVendorBlockPagesStop` 的一個期望依裁決改寫；`URLSplit` 的測試改成只驗 origin。
- `SkillToolsCLITests`：`url-rule` 回 64；`bot-signals --kind`；`fetch` 拒絕拿掉的旗標與半個 `--resume`；`take` 的真 binary 端到端（0／5／2／64、`--from` 不動）。

全套（`PATH=/usr/bin:$PATH swift test --build-system native`）：`Executed 4466 tests, with 1 test skipped and 0 failures`。守衛（`bash .githooks/run-guards.sh`）：rc 0（zero-instance 裁決表 75 列、parity 表 MCP 34／CLI 56／橫切 2）。

同一輪中途跑的 `SanitizationBoundaryTests` 抓到兩處：帳本的錯誤訊息把逃脫過的路徑放在一個計算屬性裡再內插（守衛要逃脫呼叫就在內插處）、CLI 的 `--resume-origin` 驗證把一個名叫 `why` 的區域變數交給 `displaySafeInvisible`（守衛把 `why` 當成已消毒的載體）。前者改成內插處直接逃脫，後者改名。

## 負對照

每個變異只改一處、只跑對應的一支測試，看 `Executed` 行確認測試真的跑了，再以反向編輯還原並 `cmp` 對原檔確認逐位元相同：

| # | 變異 | 測試 | 結果 |
|---|---|---|---|
| NC1 | 導航到頁面連結加上 `?download=true`（拼網址） | `FulltextFetchPathTests/testThePublisherURLRulesAreGone` | Executed 1 test, 2 failures |
| NC2 | 拿掉 `sciencedirect-download-challenge` | `FulltextFetchPathTests/testTheScienceDirectDownloadInterstitialPausesTheBatch` | Executed 1 test, 3 failures |
| NC3 | 等人驗證的文字標籤優先於整批暫停的 | `BotSignalsResponseTests/testAPauseSignalWinsWhereverItIsInTheList` | Executed 1 test, 5 failures |
| NC4 | PMC 下載前驗證頁加進等人驗證 | `BotSignalsResponseTests/testEverythingElsePausesTheBatch` | Executed 1 test, 1 failure |
| NC5 | 上限 `>=` 改 `>`（多放一次） | `FulltextFetchPathTests/testTheTenthAttemptProceedsAndTheEleventhStops` | Executed 1 test, 5 failures |
| NC6 | 日界改成 UTC | `FulltextFetchPathTests/testTheDayIsTaipeisAndOtherSitesDoNotCount` | Executed 1 test, 3 failures |
| NC7 | 嘗試不在導航前記（失敗不算） | `FulltextFetchPathTests/testAFailedNavigationIsAnAutomationFailure` | Executed 1 test, 1 failure |
| NC8 | `--resume` 被忽略、重新開文章頁 | `FulltextFetchPathTests/testResumingContinuesInTheSameTabWithoutReloading` | Executed 1 test, 1 failure |
| NC9 | `readyStateJS` 改成 `return …` 敘述形 | `FulltextJavaScriptTests/testEveryInjectedSnippetParsesAsAnExpression` | Executed 1 test, 1 failure |
| NC10 | 驗證頁當成整批暫停 | `FulltextFetchPathTests/testChallengeOnLandingWaitsForVerification` | Executed 1 test, 4 failures |
| NC11 | `take` 不過 git 閘 | `FulltextFetchHardeningTests/testOutInsideAGitTreeThatDoesNotIgnoreItIsRefused` | Executed 1 test, 3 failures |
| NC12 | `take` 收 symlink／目錄的 `--from`（拿掉 lstat 檢查與 `O_NOFOLLOW`） | `FulltextFetchHardeningTests/testTheSourceMustBeARegularFile` | Executed 1 test, 4 failures |
| NC13 | 狀態碼排在驗證頁文字之前 | `BotSignalsResponseTests/testAVerificationPageServedWithA403StillWaitsForTheHuman` | Executed 1 test, 3 failures |

十三個都在還原後以 `cmp` 對變異前的副本確認逐位元相同。**第一輪有一次還原出錯，照實記**：NC11 的變異把 git 閘那一行換成 `        return`，反向編輯以「第一個出現的 `        return`」為目標，換到了 `run()` 裡的 `            return 0`（前 8 個空白相同），`cmp` 報 DIFFERENT；接著的 NC12、NC13 因此編不過（沒有 `Executed` 行，不算數）。手動把那兩行換回、確認其餘追蹤中的檔與變異前的 `git diff` 相同之後，把 NC11 的變異改成獨一無二的字串（`return // NC11-no-git-gate`）、還原前斷言目標恰好出現一次，重跑 NC11–NC13，上表是重跑的結果。

## 誠實邊界

- **沒有對真的 Safari 跑過**（任務約束：不碰出版商網站）。全部路徑只對記憶體內的假瀏覽器跑。下列都沒有實測：`safari-browser open --window N --tab-in-window T <網址>` 把分頁導到 PDF 時 Safari 實際的行為（它以 `window.location.href=` 導航，失敗才退回 `set URL`，讀自 safari-browser 原始碼）；Safari 的 PDF 檢視器能不能跑頁面 JS、`document.contentType` 在那裡回什麼；`PerformanceNavigationTiming.responseStatus` 在 Safari 有沒有值；Content-Disposition 為 attachment 的連結導航後分頁是否停在文章頁。讀不到時一律照「無從檢查」處理（交給人或暫停），不當成乾淨。
- **位元組由人存**：三種存法哪一個是標準，等 PsychQuant/safari-browser#210 的實驗；pdf-cache（safari-browser PR #228）落地並實測一次之後才改接。在那之前每一篇都要使用者動手。
- **每站上限只擋 PDF 那一步**：文章頁本身仍會被載入；到上限之後，這批裡同一個站的其他篇若照跑，每篇仍會載一次文章頁再以 9 停下。SKILL.md 要 agent 把同一個 DOI 前綴的篇留到隔天（前綴對到同一個站是經驗，不是保證）。`--resume` 必須重新導航時會再記一次嘗試（寧可多算）。
- **帳本的預設位置跟著 `HOME`**：只設 `AKASHIC_HOME` 的沙箱仍會寫到真的 `~/Library/Application Support/akashic/`；測試一律傳 `--ledger`。
- **`--resume` 的鎖仍是視窗編號加分頁位置**（規則檔〈例外〉形狀 (b)）：以 `--resume-origin` 核對那個位置的分頁此刻顯示哪個站，對不上就拒絕；同一個視窗裡恰好有另一個同站的分頁佔了那個位置時分不出來。
- **`web-access.md` 的其他區塊**（取 API 的頁內 fetch）仍是 `return …` 的敘述形 JS；這一輪只改了中止條款用到的讀頁面那一段。那些區塊碰的是 API 站，不是出版商網站。
- **副本沒有同步**：`plugins/akashic-discovery/skills/akashic-work-references` 的中止條款仍是「一律整批停」；那個目錄屬另一條工作線，分岔記在規則檔〈操作程序的兩份描述〉第 (9) 條，由 #687 同步（沒有改 #687）。
