# 2026-10-05 `web-read`：分頁在已知的驗證服務上一律以頁面文字分（#692）

使用者 2026-10-05 的裁決（#692 Decision，第 2 項）：

> **統一交給文字比對**：不論換到或直接落在驗證服務，都照中止條款以頁面文字分 3（等人驗證）或 2（整批暫停）

## 先前的兩種處置

`akashic web-read` 只看 Safari 那一側的主機，看不到頁面文字。同一個終態（分頁停在 Cloudflare 挑戰、hCaptcha、reCAPTCHA 的主機上）依「有沒有觀察到換主機」走兩條路：

| 情形 | 先前 |
|---|---|
| `landing --expect <網址檔>`，落地主機是驗證服務而與那條網址的主機不同 | 2（整批暫停），不寫落地主機檔 |
| `check`，讀取前後主機不同、其中一個是驗證服務 | 2 |
| `check --landing <檔>`，Safari 回報的主機是驗證服務而與驗過的落地主機不同 | 2 |
| `landing --expect -`，落地主機是驗證服務 | `OK`，寫下它 |
| `check`，讀取前後都在驗證服務上、與落地主機相同或 `--landing -` | `READ-OK`，交給區塊二的 `bot-signals`：等人驗證 3、整批暫停 2、**沒有訊號 0** |

最後一列的 0 讓區塊二往下走，讀取區塊（`check --limit 20000`）把驗證服務的頁面讀成內容。中止條款說驗證服務上的驗證頁是等人驗證（3），而前三列不看文字一律 2——兩邊不一致，b33 verify X2 第 5／21 列標成待裁決。

## 現在

**`landing`**：落地主機是已知的驗證服務時，不論 `--expect` 的主機同不同，都寫下它、印 `OK` 並註明是驗證服務（`OK '<驗證服務>'（已知的驗證服務；開的網址的主機是 '…'）：…`）。這裡看不到頁面文字，不在這裡判。

**`check`**：讀取之前或之後 Safari 回報的主機有一個是已知的驗證服務時，主機比對都不做，**沒有 `READ-OK`、文字不寫出**，以剔除後的文字分（`WebRead.judgeOnVerificationService`）：

| 文字與分頁 | 結果 |
|---|---|
| 等人驗證的四種標籤（`captcha`、`human-check`、`cloudflare-challenge`、`perimeterx-press-and-hold`——`BotSignals.classify` 的 `.humanVerification`，與 `bot-signals --kind` 的 `verify` 同一個判斷），**而且讀完時分頁還在驗證服務上** | `READ-VERIFY`，3 |
| 整批暫停的標籤 | `READ-PAUSE`，2 |
| **沒有訊號** | `READ-PAUSE`，2 |
| 讀回的文字不能用（太大、欄位型別不對、`rawLength` 不合、剔除之後沒有看得見的字） | `READ-PAUSE`，2（不是 `READ-FAIL` 的 1） |
| 等人驗證的標籤，但讀完時分頁已經離開驗證服務 | `READ-PAUSE`，2 |

**文字判不出是驗證頁時是 2**。依據是中止條款的最後一句「拿不準是不是訊號就當作是；拿不準是哪一種就當整批暫停」：分頁在驗證服務上本身就是訊號，而文字分不出是哪一種。`akashic fulltext fetch` 對**讀不到**的分頁落在驗證服務上是同一個方向（`judgeUnreadable`：沒有訊號也整批暫停）。

**讀取當中換了主機**時，文字出自哪一頁分不出來，仍拿它比對；3 另外要求讀完時分頁停在驗證服務上（等人驗證只在文章站本身或已知的驗證服務上成立，使用者要驗證的是那個分頁）。文字錯配時的最壞情形是請使用者去看一個確實停在驗證服務上的分頁，或多停一次。

**區塊二與讀取區塊同一套**：讀取區塊因此也可能以 3 結束（文件與 verify-venue 都補上）。

**只看主機**：Safari 那一側的網址取到的是 `<協定>://<主機>`，沒有路徑，所以 `www.google.com`、`google.com` 也算驗證服務（reCAPTCHA 在那裡以路徑區分）。先前只在「換到」那裡時有影響；現在**直接落在** `www.google.com` 的頁面也不給 `READ-OK`、以文字分 3／2。保守的一邊，沒有實例。

## 改了哪些路徑

- `Sources/AkashicSkillTools/WebRead.swift`：結束碼的說明、`landingMode`、`checkMode`（主機分流在最前面）、`readPage`（原本內嵌在 `checkBody` 的 JSON 檢查與剔除抽出來，`READ-OK` 與驗證服務兩條路共用）、`judgeOnVerificationService`（取代只看主機的 `pauseIfVerificationService`）、新增 `verifyCode`。
- `Sources/akashic/WebReadCommands.swift`：`web-read`、`landing`、`check` 的說明。
- `plugin/skills/akashic-bootstrap/references/web-access.md`：〈中止條款〉的那一條；〈讀頁面文字用的運算式與檢查〉的結束碼清單、`landing`、`check` 兩點，「結束碼 2 比中止條款保守」那一點換成「分頁在已知的驗證服務上：一律以頁面文字分」；區塊二結尾的結束碼說明與「只在 READ-OK 之後才有這個檔」；落地主機區塊的段落與限制 (4)；讀取區塊結尾的結束碼說明。
- `plugin/skills/akashic-verify-venue/SKILL.md`：「讀」一段（驗證服務照樣 OK、寫進第 3 項時註明）、「中止條款」一段（區塊二或讀取以 3 結束是等人驗證）。

**同一判斷的路徑，查過而沒有改**：

- `BotSignals.isKnownVerificationService`（`akashic fulltext fetch` 用）與 `WebRead.isVerificationServiceHost` 是**同一份清單**（`knownVerificationHosts`、`knownVerificationPathPrefixes`），判斷的形不同：前者有完整網址、看路徑，後者只有主機。沒有共用處置的程式碼。
- `FulltextFetch` 本來就以文字分 8（等人驗證）／6（整批暫停），而且同樣要求主機是文章站或已知的驗證服務。兩點不同：(1) 它比對的是**標題、完整網址與頁面文字**，驗證服務的網址多半自己帶著標籤（`challenge-platform`、`hcaptcha`、`recaptcha`）；`web-read` 只有主機、沒有路徑與標題，所以只比對頁面文字（裁決說的是「以頁面文字分」）。(2) 讀得到、落定的頁面在驗證服務上而標題、網址、文字都沒有標籤時（例如 `https://challenges.cloudflare.com/x`），`offSiteSettled` 走到 `gateLook`（主機字詞 `challenges` 不是驗證字詞）、再到交給人（7）；`web-read` 對同一種頁面是 2。不在本裁決範圍（裁決的對象是 `web-read`），沒有改；記在給使用者的決定事項。
- `mcp-cli-parity` 的 `web-read` 列與 `WriteGateRulings` 的四格沒有描述結束碼 2，「READ-OK 才把剔除後的文字寫到 --out」在新行為下仍為真，沒有改。`web-read` 沒有 MCP 面，`Server.swift` 沒有動。

## 測試

先寫、在修改前的程式上跑：8 支紅（`WebReadTests` 5 支新的；`WebAccessReadContractTests` 2 支改寫、1 支新的）。

- `WebReadTests`：`testLandingOnAVerificationServiceGoesToTheTextComparison`（`--expect` 是網址檔與 `-` 都 OK、寫下驗證服務）；`testAPageOnAVerificationServiceIsJudgedByItsTextAndNeverRead`（`--landing -`、落地主機是文章站、落地主機是驗證服務三種 × 五種文字：3／3／3／2／2，都沒有輸出檔）；`testAHostChangeDuringTheReadInvolvingAVerificationServiceIsJudgedByTheText`（換到驗證服務：等人驗證 3、沒有訊號 2；離開驗證服務：2）；`testUnusableTextOnAVerificationServiceIsAPauseNotAReadFailure`（四種不能用的輸入都是 2，不在驗證服務上仍是 1）；`testWwwGoogleComIsJudgedByTheTextToo`。
- `WebAccessReadContractTests`（從 web-access.md 抽出區塊、假 safari-browser 接真 `akashic`）：`testAVerificationServiceHostIsJudgedByThePageTextInsteadOfReportingUnreachable`（讀取當中換到驗證服務：沒有訊號 2、`Just a moment...` 3）；`testAConfirmedUrlRedirectedElsewhereIsRejected`（`EXPECT` 之下轉到驗證服務：落地主機區塊 0、寫下它，區塊二 3／2）；`testLandingDirectlyOnAVerificationServiceIsJudgedTheSameWay`（`EXPECT="-"`，區塊二與讀取區塊、`LAND` 是落地主機檔與 `-` 兩種，都是 3／2、沒有 `first-<T>.txt`、`r-7.txt`）；`testTheDocsDescribeOneHandlingForVerificationServices`（文件與 verify-venue 不再有「比中止條款保守」「也不判驗證服務」「換到已知的驗證服務是結束碼 2」這些說法；在修改前的文件上紅）。

**負控**（反向編輯還原，還原後與改之前的檔逐字相同）：

| | 改動 | 紅 |
|---|---|---|
| NC1 | `landing` 不認驗證服務 | 3 支（11 則） |
| NC2 | `check` 不走驗證服務分流 | 8 支（93 則） |
| NC3 | 3 不要求讀完時在驗證服務上 | 1 支（2 則） |
| NC4 | 文字不能用改回 1 | 1 支（4 則） |
| NC5 | 沒有訊號放行 0 | 7 支（17 則） |

## 給使用者

1. `akashic fulltext fetch` 對讀得到、在驗證服務上而標題、網址、文字都沒有標籤的頁面是交給人（7），`web-read` 是整批暫停（2）。要不要對齊？
2. 區塊二的 `bot-signals` 那一條（分頁不在驗證服務上）判 3 時不看主機：`LAND="-"`（沒接上落地主機檢查）時，被轉到第三方主機的驗證頁會是 3，而中止條款說其他主機上的驗證字樣是整批暫停。這是另一件事（不是驗證服務的處置），沒有改。

## 驗證

- 建置（`--build-system native`、`-warnings-as-errors`，含 `--build-tests`）乾淨。
- 全套 `swift test`（分離執行）：5096 支、1 支略過、0 失敗。
- 守衛（`.githooks/run-guards.sh`）：rc 0。
- `tools/list`：沒有動 MCP 的描述，58,949 bytes 不變。
