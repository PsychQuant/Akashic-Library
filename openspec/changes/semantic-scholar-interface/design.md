## Context

使用者有 Semantic Scholar（S2）的 API 金鑰，希望 Akashic 能用它查詢（#664）。現況（2026-09-28 量）：

- `Sources/` 沒有任何 HTTP client（`URLSession`／`URLRequest`／Network framework 0 處），沒有 Security framework，也沒有跨程序的檔案鎖。
- `.claude/rules/web-access-via-safari-browser.md` 規定 skill 的外部取得一律經 safari-browser，第 2 條規定 `Sources/` 不新增 HTTP client。
- 頁內 fetch 要把金鑰交給 `safari-browser js` 的指令參數，會出現在 process list（#640）。
- S2 官方 OpenAPI 規格：金鑰放在 header `x-api-key`（大小寫有別）；有金鑰時所有端點合計每秒 1 次。
- CLI 用 swift-argument-parser，自訂結束碼目前只有 1，參數錯誤是 ArgumentParser 內建的 64。MCP 工具在 `Sources/akashic-mcp/Server.swift` 註冊，`handleToolCall` 是同步函式，被包在 async 的 `CallTool` handler 裡。
- 外部字串的顯示清理函式 `displaySafe` 在 `AkashicCore`。

使用者已在 #664 的 Clarity Surface 與 spectra-discuss 定案：一個共用接口、兩個面都要、帶金鑰的 S2 呼叫列為 web-access 規則的封閉例外、只在本機使用、沒有金鑰就提示設定。金鑰已由使用者存入 keychain（service `semantic-scholar`、account `default`）。

## Goals / Non-Goals

**Goals:**

- 一個 target（`AkashicS2`）承擔 S2 的全部契約：八個端點、分頁、金鑰讀取、host 規則、跨程序節流與 429 退避、外部字串清理
- 使用者與 skill 都能取用：CLI `akashic s2 …`、MCP `akashic_s2`
- 金鑰不出現在指令參數、環境變數、process list、log、網址、檔案，也不出現在任何輸出
- 本機所有呼叫者合計每秒不超過 1 次請求
- 本體其他部分不連網、不讀 keychain，由守衛機械地檢查
- 沒有金鑰的使用者得到一段可以照做的設定說明

**Non-Goals:**

- 不接上任何使用者 skill。#640、#620、#621、#622、#665 各自以本接口為前提另外實作。**唯一的例外**：使用者 2026-09-29 的取得順序裁決（有金鑰走 `akashic s2`／`akashic_s2`，沒金鑰最後才經 safari-browser）寫進 plugin 側的 `akashic-bootstrap/SKILL.md` 與 `references/web-access.md`——plugin 讀者讀不到專案規則，而照「一律經 safari-browser」去查 S2 正是金鑰外露的那條路。那是路由文字，不是接線（bootstrap 並沒有開始用 S2 補欄位，那是 #665 的事）
- 不寫 store。S2 回傳一律是線索；欄位值的依據依 `source-of-truth-over-consent`
- 不做回應快取
- 不做跨機器的節流協調（Clarity 4：只在本機使用）
- 沒有金鑰時不退回匿名請求
- 不泛化成「任何需要金鑰的 API」的框架。之後出現第二個 API 時再決定
- 不改變不需金鑰的 API（OpenAlex、Crossref、ORCID）的取得路徑，它們照舊經 safari-browser
- 不支援 S2 的 bulk search 與 datasets API

## Decisions

### S2 放在獨立 target，不進 AkashicService 也不進 AkashicCore

`AkashicS2` 是新的 library target，依賴 `AkashicCore`（取用 `displaySafe`）。`akashic` 與 `akashic-mcp` 兩個 executable target 都直接依賴它。

- 否決「包進 `AkashicService`」：那是綁 store 的服務層，而 S2 查詢不開 store。包進去只多一層只轉呼叫的 adapter，刪掉它什麼都不壞。
- 否決「放進 `AkashicCore`」：網路程式與離線本體混在同一個 target，守衛只能靠掃字串分辨哪些檔案可以連網。獨立 target 讓「可連網的地方」等於一個目錄。

### 兩個面都做，MCP 面有位元組上限

依 `mcp-cli-parity.md` 的判準（可用性不該取決於用 MCP 還是 CLI）與 Clarity 1（使用者直接查、skill 取用都要），CLI 與 MCP 都提供。

- MCP 輸出進 LLM 的 context，呼叫端收到後無法退回已付的代價，所以設 48 KiB 上限，與 `akashic_doctor` 的 `candidateByteBudget` 同值。上限值由 MCP 面傳入 `AkashicS2` 的截斷函式，`AkashicS2` 不依賴 `AkashicMCPKit`。
- CLI 輸出進人的終端機，不截。

### 每個端點一個具型別子命令

否決通用的 `akashic s2 get <path>`：它把組網址的責任推回 skill，路徑白名單只能做字串比對，而五個使用者 skill 會各自組出不同的欄位參數。具型別子命令讓參數驗證、分頁與 `total` 的取得都在同一處。

### 金鑰：程序內非互動讀取，ACL 所有 app 可讀，header 只送 S2 主機

- 以 Security framework 的 generic password 查詢（service `semantic-scholar`、account `default`）在程序內讀取，**非互動**：ACL 不允許時回傳錯誤，不跳授權框。MCP server 在背景執行，看不到授權框，互動式讀取會讓它卡住。
- 非互動的寫法是在查詢中帶 `kSecUseAuthenticationContext`，值為 `interactionNotAllowed = true` 的 `LAContext`。依 Apple 文件，`kSecUseAuthenticationUIFail` 自 macOS 11 起棄用，改用這個寫法；需要驗證時回傳 `errSecInteractionNotAllowed`，找不到項目時回傳 `errSecItemNotFound`。文件沒有說明這是否也涵蓋舊式檔案型 keychain 的 ACL 對話框，所以由實機驗證確認。
- ACL 建議設為所有 app 可讀。`akashic` 是本機 ad-hoc 建置（#633），限定特定 binary 的 ACL 在每次重建後都會失效。S2 金鑰免費、有額度限制、可撤銷重發，這個風險可以接受；設定文件寫明這個取捨。
- `x-api-key` 只在請求的 host 恰為 `api.semanticscholar.org` 且 scheme 為 `https` 時附上。
- 金鑰以一個 description 一律回 `<redacted>` 的型別持有，避免被字串插值或 log 意外印出。
- 不提供環境變數或指令參數當金鑰來源：同使用者的程序可以用 `ps -E` 看到環境變數。
- **連線不留任何落盤的東西**（verify R1）：預設的共用 `URLSession` 帶著 `URLCache`，S2 的回應沒有 `Cache-Control`，GET 會被啟發式快取，序列化的請求（含 `x-api-key`）寫進 `~/Library/Caches/<程序名>/Cache.db`（實測：本機 8.3 的實機驗證留下一筆）。所以預設連線是 `URLSessionConfiguration.ephemeral`，`urlCache`、`httpCookieStorage` 都是 nil；每個請求另外帶 `reloadIgnoringLocalAndRemoteCacheData` 與不處理 cookie——**那只管「讀不讀快取」，不管「存不存」**（R2 實測：帶磁碟快取的連線照樣把含 `x-api-key` 的請求存進 `Cache.db`，task delegate 的 `willCacheResponse` 也不會被呼叫），所以保證放在連線這一層：`S2Client.send` 在讀金鑰、送出任何請求之前，對 `urlCache` 帶磁碟容量的注入連線以 `S2Error.unsafeSession` 拒絕（`S2Client.isCacheFree`；用錯誤，不用 `precondition`——後者在 MCP server 裡會讓每個工具一起掛掉；R3 抓到第一版是 `precondition`、也沒有測試），預設連線全程序共用一個（`S2Client.defaultSession`；每次新建一個，長駐的 `akashic-mcp` 會隨呼叫次數增長）。
- **不跟隨轉址**（verify R1）：host 規則只檢查第一個網址，而 URLSession 轉址時把自訂 header 原樣帶到新位址。每個請求帶一個 task delegate 把 3xx 當成最終回應交還，`S2Client` 把它報成錯誤（結束碼 5，訊息帶狀態碼），不對轉址目標送任何請求。S2 的 API 本來就不該轉址，所以沒有「同主機的轉址放行」這種例外。

### 跨程序節流：預約時段，429 退避共用

狀態檔 `~/Library/Caches/akashic/s2-throttle`（目錄**建立時** 0700——已存在的目錄不動它的權限；檔案 0600，已存在而較寬的收緊到 0600；開檔帶 `O_NOFOLLOW`，symlink 不跟隨），內容是 JSON `{"nextAllowedAt": <Unix 秒，Double>, "blockedUntil": <Unix 秒，Double，可省略>, "lastReleasedAt": <Unix 秒，Double，可省略>}`（`lastReleasedAt` 是 #701 加的）。

- **預約**：以 `flock(LOCK_EX)` 鎖住狀態檔 → 讀出 `nextAllowedAt` → `slot = max(now, nextAllowedAt)` → 寫回 `nextAllowedAt = slot + 1.05` → 解鎖 → 睡到 `slot` 才送出。睡眠期間不持有鎖，其他程序可以接著預約下一個時段，順序接近先到先得。
- **429 退避**：收到 429 時鎖住狀態檔，把 `nextAllowedAt` 與 `blockedUntil` 都推到至少 `now + retryAfter`，所有呼叫者一起等。
- **醒來後重新檢查**：只推 `nextAllowedAt` 不夠——已經預約了較早時段、正在睡的呼叫者不會受影響（實作任務 3.2 時發現）。所以每個呼叫者睡醒後、送出前，在鎖內再看一次 `blockedUntil`；仍在封鎖期就重新預約。`Retry-After` 可以是秒數或 HTTP-date；沒有這個 header 時依序用 2、4、8 秒。
- **放行間隔在鎖內保證**（#701）：預約只保證每一次放行不早於自己的時段，不保證兩次放行的間隔。`Task.sleep` 睡得越久晚醒越多（2026-09-30 實測：睡約 1.05 秒的晚醒 124–139 ms，睡約 0.5 秒的晚醒約 58 ms），前一個呼叫者晚醒、後一個準時醒時，兩次放行只差 0.92–0.98 秒。所以醒來後在鎖內比對上一次放行的時刻（`lastReleasedAt`），不到 1.05 秒就再等；放行時記下這一刻，並把 `nextAllowedAt` 推到至少這一刻加 1.05。小於 1 ms 的等待不睡，所以保證的間隔是 1.049 秒。舊 binary 寫回狀態檔時會丟掉 `lastReleasedAt`，那一次的間隔回到只由預約保證。
- **上限**：同一請求最多重試 3 次；`Retry-After` 超過 60 秒視為限流用盡，不等。讀到的 `nextAllowedAt` 與 `lastReleasedAt` 比現在晚超過 60 秒（時鐘回撥或狀態檔損毀）時視為過期，以現在為準重設。
- **放棄之前先記退避**（verify R1）：收到 429 時**先**把退避寫進共用狀態，再決定這次呼叫要不要等或放棄。最後一次 429 與 `Retry-After` 超過 60 秒原本都在寫入之前就拋錯，其他 session 看不到，照常打。沒有 `Retry-After` 時第 4 次 429 記 8 秒。
- **長退避不被當成過期**（verify R1）：`blockedUntil` 有自己的過期門檻——記錄時最多記一小時（`maxBackOff`），讀到比現在晚超過一小時加 60 秒才視為過期。原本與時段共用 60 秒的門檻，所以 `Retry-After: 120` 即使記下來也會在下次讀取時被清掉。
- **快速失敗，不睡過去**（verify R1）：其他呼叫者遇到剩下超過 60 秒（`maxWait`）的封鎖，在預約時段之前就以 `S2ThrottleError.blocked` 失敗，`S2Client` 把它報成 `rateLimited`（結束碼 4），不送請求、不睡；剩下 60 秒以內才睡過去再送。`Retry-After` 超過 60 秒的呼叫者與這些呼叫者因此得到同一個結果。
- `flock` 隨檔案描述子關閉而釋放，程序中途死掉不會留下鎖。
- 狀態檔不放在 `~/.akashic`：`RealHomeSandboxGuard` 監看那裡，全套測試期間的寫入會被判成沙箱逃逸。

否決程序內的鎖：CLI 與 MCP server 是不同程序，兩個 session 同時跑就會超速。

### 測試接縫：三個受限的覆寫

測試不得碰真的 keychain 項目、真的網路、真的 `~/Library/Caches/akashic`（連線不快取後，`AKASHIC_S2_STATE_DIR` 只管節流狀態檔，URLCache 不再有檔案可寫；CLI 測試 `testARunLeavesNoCacheFileBehind` 在前後比對那個目錄的檔案）。三個覆寫都走 `environment:` 注入參數（沿用 `LibraryLocator` 的慣例），而且各自有限制：

| 覆寫 | 限制 | 理由 |
|---|---|---|
| `AKASHIC_S2_BASE_URL` | 只接受 `http://127.0.0.1`、`http://localhost`、`http://[::1]`（可帶 port）；其他值整個請求拒絕 | 否則一個環境變數就能把請求導到別的主機。覆寫生效時 host 不是 S2，依 host 規則不附金鑰；**也不讀 keychain**：金鑰反正不會送出，測試因此不必碰真的 keychain 項目，成功路徑的 CLI 測試也不需要測試用的金鑰 |
| `AKASHIC_S2_KEYCHAIN_SERVICE` | 只接受以 `akashic-test-` 開頭的名稱 | 讓測試用一個不存在的 service 走完「沒有金鑰」路徑，但無法指向其他真實項目 |
| `AKASHIC_S2_STATE_DIR` | 必須是絕對路徑 | 測試用暫存目錄驗證跨程序節流 |

in-process 的 client 測試用 `URLProtocol` stub 攔截請求，並注入替身的金鑰提供者。

`CLITestHarness` 會先清掉所有 `AKASHIC_*` 再注入測試給的環境；因此一個忘了設覆寫的 `s2` 測試會讀到開發機上真的金鑰、連到真的 S2。harness 對 `s2` 呼叫在測試沒指定 `AKASHIC_S2_KEYCHAIN_SERVICE` 時補上 `akashic-test-harness`：最壞的結果是結束碼 3，不會連網，也不會讀到真的項目。

### 守衛：網路與 keychain API 只准出現在 AkashicS2

新增 `akashic-guards network-confinement`，掃描 `Sources/` 下所有 `.swift`。下列字樣（封閉列舉）只准出現在 `Sources/AkashicS2/`：

- 網路：`URLSession`、`URLRequest`、`NWConnection`、`import Network`、`/usr/bin/curl`
- keychain：`import Security`、`SecItem`、`import LocalAuthentication`、`/usr/bin/security`

排除清單只有守衛自己的兩個檔（它們把這些字樣寫成模式）。註解也計入，因為量測時 `Sources/` 內這些字樣為 0 處，保守的判準不會誤報現有程式。負對照 `network-confinement-mutations` 在暫存副本中注入違規，證明守衛會開火。

### MCP 面的 async 路徑

`akashic_s2` 需要網路，必須 async。在 `CallTool` 的 async handler 內，工具名為 `akashic_s2` 時改走 async 的處理函式，其餘工具照舊走同步的 `handleToolCall`，行為不變。

## Implementation Contract

**CLI 介面**（`akashic s2 <子命令>`，每個子命令都有 `--json`；`--fields` 為逗號分隔的 S2 欄位名，照原樣轉給 S2）：

| 子命令 | 參數 | S2 端點 |
|---|---|---|
| `paper <paper-id>` | `--fields` | `GET /graph/v1/paper/{id}` |
| `match --title <標題>` | `--year`、`--fields` | `GET /graph/v1/paper/search/match` |
| `batch --ids-file <檔>` | `--fields`；檔案一行一個 id，至多 500 個 | `POST /graph/v1/paper/batch` |
| `references <paper-id>` | `--fields`、`--limit N`（上限總筆數，預設全部）、`--offset K` | `GET /graph/v1/paper/{id}/references` |
| `citations <paper-id>` | 同上 | `GET /graph/v1/paper/{id}/citations` |
| `recommend <paper-id>` | `--limit N`（1–500，預設 100）、`--fields` | `GET /recommendations/v1/papers/forpaper/{id}` |
| `author-search --name <姓名>` | `--limit`、`--fields` | `GET /graph/v1/author/search` |
| `author-papers <author-id>` | `--fields`、`--limit`、`--offset` | `GET /graph/v1/author/{id}/papers` |
| `status` | 無 | 不連網 |

- `paper-id` 照 S2 的語法接收（`DOI:…`、`CorpusId:…`、S2 paperId 等）；以 `10.` 開頭的裸 DOI 自動加上 `DOI:`。id 在送出前做百分比編碼。
- `--json` 的輸出：`{"source":"semantic-scholar","endpoint":"<子命令名>","request":{…},"fetchedAt":"<ISO 8601，帶本機時區 offset>","total":<整數或 null>,"data":<S2 的資料>}`。字串原樣保留（只在超過長度上限時截斷），序列化後的 JSON 文字以 `\uXXXX` 無損逃脫危險 scalar（`documentSafeJSON`，與 CSL-JSON 出口同一個函式）；人可讀的面是終端機，字串經 `displaySafe`。分頁端點的 `data` 是全部筆數串成的陣列。
- 人可讀輸出與 `--json` 同源：分頁與單篇都一行一筆，格式為年份、標題、第一作者、主要 id。
- `status --json`：`{"keychain":{"service":"semantic-scholar","account":"default","present":<bool>,"readable":<bool>},"throttle":{"stateFile":"…","nextAllowedAt":"<ISO 8601 或 null>"},"host":"api.semanticscholar.org"}`。不印金鑰，也不印它的長度。

**結束碼**（新值不與既有的 1、64 衝突）：

| 碼 | 意思 |
|---|---|
| 0 | 成功 |
| 3 | 金鑰不可用：keychain 沒有這個項目，或 ACL 不允許非互動讀取。訊息寫明 service／account，並指向 `plugin/skills/akashic-bootstrap/references/semantic-scholar.md`；ACL 的情形另外說明要改成所有 app 可讀 |
| 4 | 限流用盡：同一請求 429 重試 3 次後仍是 429，或 `Retry-After` 超過 60 秒 |
| 5 | S2 或網路錯誤：404（訊息說明是哪一個 id 找不到）、其他 4xx、5xx、連線失敗 |
| 1 | 需要讀 argv 以外才判得出的錯誤（#549 的判準，`RuntimeFailure`）：環境覆寫被拒、`--ids-file` 讀不到或筆數不合、節流狀態檔無法使用 |
| 64 | 只看 argv 就判得出的參數錯誤（ArgumentParser 既有）：`--limit`、`--offset` 的範圍、識別碼空白或含 `.`／`..` 路徑片段——在 `validate()` 檢查，早於任何 I/O |

錯誤文字依 repo 既有的消毒紀律（#554）：字串 payload 在擲出端以 `displaySafeInvisible` 逃脫一次，描述原樣組句，五個錯誤型別宣告 `SanitizedErrorDescription`，之後每一層只截。CLI 與 MCP 都以 `displaySafeErrorMultiline(_:prefix: "Error: ")` 輸出錯誤，兩面逐字相同。（實作任務 5.1 時由 `SanitizationBoundaryTests` 抓出：初版在描述端才清理、方向相反。）

**MCP 工具 `akashic_s2`**：

- 參數：`endpoint`（`paper`／`match`／`batch`／`references`／`citations`／`recommend`／`author_search`／`author_papers`／`status`）、`id`、`title`、`year`、`name`、`ids`（陣列）、`fields`（陣列）、`offset`、`limit`。
- 回傳：`{"endpoint","total","returned","truncated","offset","nextOffset","data"}`。只放完整的筆數，加入下一筆會超過 48 KiB（量的是實際輸出的文字，含 `\uXXXX` 逃脫）就停，此時 `truncated: true`。**續查的訊號是 `nextOffset`，不是 `truncated`**：`nextOffset` 非 null 就用它當下一次的 `offset`，null 就是沒有下一頁。
- `nextOffset` 的規則（verify R1）：分頁端點（references／citations／author_search／author_papers）在位元組上限截斷、或 S2 自己回了前進的 `next`（`S2Result.hasMore`）時是 `offset + returned`，否則 null；`paper`／`match`／`batch`／`recommend` 不接 `offset`，永遠 null；空的一頁永遠 null（`nextOffset == offset` 是定點）。**不用 `total` 判斷有沒有下一頁**：它來自另一個請求，可以比 S2 實際給得出的筆數大（出版商沒提供的參考文獻），也可以查不到。第一筆就超過 48 KiB 時回錯誤並點名 `fields`，不回「成功、0 筆」。
- `limit`：分頁端點 1–1000（S2 的一頁），預設 100（一個呼叫不拉回上千筆，其餘以 `nextOffset` 續查）；不分頁的 `batch` 一次至多 500 個 id（空白的 id 丟掉，含空白或控制字元、超過 512 字元的 id 不送出）。
- `total` 的來源：references／citations 以同一個 paper 的 `referenceCount`／`citationCount` 取得（多一次請求，受同一個節流）；author-papers 以 author 的 `paperCount` 取得；search 類端點用 S2 回應的 `total`。
- 錯誤時 `isError: true`，文字與 CLI 同一段訊息（金鑰不可用、限流用盡、S2 錯誤）。

**驗收條件**：

- `swift test` 全綠，包括新的 `AkashicS2Tests` 與 CLI／MCP 測試；測試期間 `RealHomeSandboxGuard` 不報錯。
- `.githooks/run-guards.sh` 全綠，其中 `network-confinement` 通過、`network-confinement-mutations` 證明守衛會開火。
- 以 `URLProtocol` stub 驗證：只有 host 為 `api.semanticscholar.org` 的請求帶 `x-api-key`；網址中不含金鑰；429 重試至多 3 次；`Retry-After` 被遵守。
- 兩個子程序共用同一個 `AKASHIC_S2_STATE_DIR`、各送 3 個請求，所有請求的送出時間兩兩間隔至少 1 秒（容許 50 ms 誤差）。
- `AKASHIC_S2_KEYCHAIN_SERVICE=akashic-test-<隨機>`（不設 `AKASHIC_S2_BASE_URL`）時，`akashic s2 paper DOI:10.1037/a0038889` 以結束碼 3 結束；「讀不到金鑰時不發出任何請求」由 in-process 測試以 `URLProtocol` stub 驗證。
- 實機驗證（需真金鑰，只在使用者的機器上跑、不進自動測試）：`akashic s2 status` 回報 present／readable 皆為 true；`akashic s2 paper DOI:10.1037/a0038889 --json` 回傳該論文。
- **尚未驗證（verify R1 第 10 列）**：ACL 不允許非互動讀取的項目，是否真的不跳授權框。Apple 文件沒有說明 `interactionNotAllowed` 是否涵蓋舊式檔案型 keychain 的 ACL 對話框（見上〈金鑰〉）。自動測試只涵蓋 `-25308`／`-25293` 的狀態碼對應，沒有涵蓋「沒有框」本身；要驗得在使用者的 login keychain 建一個限制存取的測試項目、從 `akashic s2 status` 讀它，萬一跳框會出現在使用者的畫面上，所以不放進自動測試，也沒有替使用者做。MCP server 在背景執行、看不到框，這件事的風險是**卡住**而不是外洩。

**範圍**：

- 在範圍內：`AkashicS2` target、`akashic s2` 子命令群、`akashic_s2` MCP 工具、`network-confinement` 守衛與負對照、兩份規則與 `CLAUDE.md` 索引、`README.md`、設定文件。
- 不在範圍內：任何使用者 skill 的接線、store 寫入、回應快取、其他需要金鑰的 API、`~/bin/akashic` 的重建（依 #633 的閘另外處理）。

## verify R1 偏離與已知取捨（2026-09-29，#664）

pai-ensemble 六席驗證（4 lens＋DA＋Codex）判 FAIL，49 條合併為 33 列；修正都寫進上面各段與 spec。這裡只記**偏離原設計的決定**與**看過但沒有修的**：

| 項目 | 決定 |
|---|---|
| 預設連線、轉址 | 改成 ephemeral 無快取連線、不跟隨轉址（見〈金鑰〉）。原設計「金鑰不出現在檔案」是承諾，實作用共用連線破了它 |
| 429 | 放棄之前先記退避；長退避有自己的過期門檻；其他呼叫者快速失敗（見〈跨程序節流〉）。第 3 列（醒來後同時送出）已由 #701 在本單之外修掉 |
| 續查契約 | `S2Result.hasMore` 取自 S2 的 `next`；`nextOffset` 的規則見〈MCP 工具〉；MCP 預設 `limit` 100 是**新增的決定**（原 spec 情境沒有預設值，照寫會跑出 120 筆），情境改為明傳 `limit: 1000` 並補預設值的情境 |
| JSON 面的清理 | 改為字串原樣、序列化後無損逃脫；原設計「每個字串經 `displaySafe`」對終端機面成立、對 JSON 面會不可逆地改寫反斜線與排版空白 |
| bootstrap SKILL.md 與 `web-access.md` 的取得順序段落 | 見〈Non-Goals〉的例外：路由文字，不是接線；#665 要知道這段文字已經存在，避免兩處分岔 |
| `status` 的結束碼與 `present` | 取得順序看 `keychain.present`／`readable`，**不只看結束碼**（結束碼 3 涵蓋兩種情形）：`present` 為 false 只有一個意思——keychain 明確回答找不到（`errSecItemNotFound`），其他任何狀態（鎖著、權限、內容壞、不明的 keychain 錯誤）都是 `present: true, readable: false`，歸「停下回報」，不叫使用者重存、不退到 safari-browser。其他結果（1＝環境覆寫被拒；64 或「未知工具」＝裝的 binary 比本單舊）也停下來回報。R3 抓到第一版把不明的 keychain 錯誤也算成 `present: false`（程式與四份文字不一致）：現在 `probe()` 以 `itemMayExist(forAttributeStatus:)` 判斷，有單元測試。`AKASHIC_S2_BASE_URL` 生效時 `status` 不讀 keychain、回 0，只用於測試 |
| 識別碼保留 `/` | **沒有修**（第 18 列）：DOI、`URL:`、舊式 arXiv id 都含 `/`，不能一律編碼；識別碼是呼叫者自己給的，改指到的是同一個 S2 主機上的另一個 GET，不外洩金鑰、不寫入。`.`／`..` 片段照舊拒絕 |
| 非互動讀取的「不跳框」 | **沒有自動測試**（第 10 列）：見〈驗收條件〉的「尚未驗證」，風險是卡住不是外洩。**追蹤在 #725**（一次性的人工實機驗證）——規格的 SHALL 不因為 #664 結案而沒有人看 |
| 金鑰輪替 | R1 建議輪替（舊金鑰曾被 URLCache 寫進 `Cache.db`）。**使用者 2026-10-06 裁決沿用舊金鑰**（原話：「這用舊的沒官系，現在繼續往下座」，原文如此），不輪替。修正後已刪掉那些快取檔；刪檔不保證磁碟區塊被覆寫，也不處理 Time Machine 與本機快照——接受，理由：`~/Library/Caches` 是 0700、`-A` 的威脅模型本來就接受同使用者的程序讀得到金鑰。**暴露期要照實記**：公開 `main` 從 2026-09-29（原始實作推上去）起就帶著「把金鑰寫進磁碟快取」的版本，修正輪在分支上、推上 `main` 之前一直如此；但當時本機 `~/bin/akashic`、`~/bin/akashic-mcp` 與 plugin 釘的 0.12.1 都沒有 S2 程式碼，所以實際落盤的只有開發機上實機驗證的那一筆。這個「沿用」的前提（修正後不會再落盤）要等修正輪推上 `main` 並重新建置後才成立 |
| `AKASHIC_S2_STATE_DIR` 在正式環境也被接受 | **沒有修**（R2 第 11／24／29／35 列，R3 第 15 列更正理由）：它能把節流狀態檔指到別處、讓兩個程序不再共用全機額度。**更正：先前寫「沒有正式／測試的判別」不實**——`S2Settings.resolve` 同一個函式裡已經算了兩個測試判別式（`target == .loopback`、`akashic-test-` 服務前綴），只在其中之一成立時才接受這個覆寫，就能和另外兩個覆寫同樣受限。沒修的真正理由：影響範圍是使用者自己設的環境變數拆開自己的節流，不外洩金鑰、不寫別人的檔；而收緊它會改變測試縫（`testStateDirectoryOverrideMustBeAbsolute` 等只設這一個覆寫）與規格的第三個覆寫。要收緊是一個獨立的小決定，不是遺漏 |
| 節流狀態檔的硬連結 | **沒有修**（R2 第 29 列）：`O_NOFOLLOW` 擋 symlink，不擋硬連結；狀態檔只含時間戳，硬連結讓別的檔被寫進 JSON 的前提是攻擊者已能在同一個 0700 目錄建檔 |
| `--ids-file` 的形狀檢查認不出「長得像金鑰的一行」 | **沒有修**（R2 第 27／34 列，R3 第 15／23 列更正理由）：檢查只擋含空白或控制字元、超過 512 字元的行。**更正：先前寫「40 字元十六進位的 paperId 與金鑰在形狀上分不開」站不住**——S2 的 paper id 輸入是文件列出的封閉集合（40 字元十六進位 sha，或 `CorpusId:`、`DOI:`、`ARXIV:`、`MAG:`、`ACL:`、`PMID:`、`PMCID:`、`URL:` 前綴，加上 CLI 已會補 `DOI:` 的裸 `10.` DOI），拿它做正面檢查能擋下 `API_KEY=…`、帶帳密的網址、混合大小寫的 40 字元字串。**沒做的真正理由**：(1) 唯一的收件者是 S2——金鑰就是它發的，把金鑰 POST 回去沒有新的暴露；(2) `--json` 的 `request.ids` 回顯的是使用者自己給的輸入，回到使用者自己的終端；(3) 封閉集合要跟著 S2 加前綴，每個新前綴都會變成「合法 id 被拒」的 bug。**有做的**：被拒的識別碼不再回顯內容，只說第幾個（錯誤訊息會進終端或 agent 的對話）。要改成正面檢查是一個獨立的決定 |
| `nextOffset` 數的是筆數，不是 S2 的位置 | **沒有修**（R2 第 16 列）：S2 回短頁時 `offset + returned` 與 S2 的 `next` 可能差一段；`paginate` 本身照 `next` 翻（所以 CLI 不受影響），MCP 的 `nextOffset` 以筆數計。S2 的 `next` 在實測中等於 offset 加回傳筆數，目前沒有量到分歧。另一半（R3 第 39 列）：`limit` 省略（CLI 翻完全部頁）時，若 S2 回的筆數多過要的 1000，`paginate` 以 `prefix(want)` 截斷而不再翻——S2 沒有這樣的已知行為，也沒量到；記在這裡，不是修掉 |
| `--ids-file` 單次讀會漏第二段（R3 第 1 列，Codex 席） | **沒有成立**：實測 Foundation 的 `read(upToCount:)` 對分段寫入的 FIFO 一次就讀到 EOF（把循環改回單次讀，分兩段寫入的 FIFO 測試照綠）。循環保留，只是不押在那個實作細節上；那個測試是行為鎖定，不是抓得到 bug 的測試。該席的跨模型安全分類器當次逾時，審查的動作沒有被覆核，所以它的發現要自己對著程式核實，這一條就是核實的結果 |
| `--ids-file` 指向永遠不關閉的 FIFO 會一直等（R3 第 33 列） | **沒有修**：與任何讀 stdin 的 CLI 相同；位元組上限擋的是資料量，不是阻塞。使用者自己指定的檔案 |
| 公開的 `S2Client.defaultSession`（R3 第 25 列） | **沒有修**：給了匯入者一個通過字面守衛的 `URLSession` 把手。它是無快取、無 cookie 的連線，本身沒有金鑰；真正的風險是別人用它連到別處，那是程式審查的事（`network-confinement` 已寫明只擋字面清單） |
| 預約時段的 60 秒過期門檻 | **沒有改**（R2 第 17／33 列；R3 第 10 列更正成本的說法）：`nextAllowedAt` 仍用 60 秒。**這個重設發生在封鎖期間，不是之後**：排在短封鎖（不超過 60 秒）後面的呼叫者與之後到的呼叫者，會把 `nextAllowedAt` 重設成「現在」再寫回，於是封鎖結束前它們大約每 1.05 秒就醒來、重新鎖檔、重寫狀態檔一次。沒有超速（放行間隔由 #701 的 `release()` 在鎖內保證、封鎖本身看 `blockedUntil`），代價是封鎖期間多出的鎖與寫入、排隊順序不嚴格。收緊要把時段的過期門檻與封鎖分開處理，是獨立的小決定 |
| `network-confinement` | 字面的封閉清單，不證明沒有別的連網途徑；文件已改成這樣說 |
| `-A` ACL | 同使用者的任何程序（包括 agent 的 shell）不經提示就能讀到金鑰；規則與設定文件明寫「skill 與 agent 不得直接讀這個項目」，見規則〈例外〉第 2 類 |

## Risks / Trade-offs

- [本體第一次連網，之後的改動可能照抄] → 守衛把網路與 keychain API 鎖在單一目錄，負對照證明守衛會開火
- [ACL 所有 app 可讀：同使用者的任何程序都能讀到金鑰] → S2 金鑰免費、有額度、可撤銷；設定文件寫明取捨，使用者可以改成限定 binary，代價是每次重建都要重新授權
- [base URL 覆寫把金鑰導到別的主機] → 覆寫只接受 loopback，host 規則在非 S2 主機一律不附金鑰
- [錯誤訊息或除錯輸出印出 header] → 金鑰以 redacted 型別持有；錯誤訊息只含狀態碼與端點，不含請求 header
- [時鐘回撥或狀態檔損毀讓所有呼叫者卡住] → `nextAllowedAt` 比現在晚超過 60 秒即視為過期並重設
- [MCP 的 `total` 多花一次請求] → 受同一個節流，額度內可接受；`total` 取得失敗時回 `null`，資料照回
- [S2 改欄位名或回應形狀] → 接口原樣轉交 S2 的資料，不做欄位對映；只有 `total` 的取得依賴三個欄位名，失敗時回 `null`
- [守衛把註解中的字樣也算進去，可能誤報] → 目前 0 處；訊息說明改寫方式。之後若有正當需要，依規則加列，不放寬判準

## Migration Plan

- 不改 store 格式，沒有資料遷移。
- 部署：`akashic-mcp` 隨 plugin 的 release 發布；`akashic` CLI 依 #633 的閘，在其他工作線都驗證過後才重建 `~/bin/akashic`。
- 回退：撤回本分支即可。keychain 項目留著無害。

## Open Questions

(none)
