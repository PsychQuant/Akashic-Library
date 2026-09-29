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

- 不接上任何使用者 skill。#640、#620、#621、#622、#665 各自以本接口為前提另外實作
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

### 跨程序節流：預約時段，429 退避共用

狀態檔 `~/Library/Caches/akashic/s2-throttle`（目錄 0700、檔案 0600），內容是 JSON `{"nextAllowedAt": <Unix 秒，Double>, "blockedUntil": <Unix 秒，Double，可省略>}`。

- **預約**：以 `flock(LOCK_EX)` 鎖住狀態檔 → 讀出 `nextAllowedAt` → `slot = max(now, nextAllowedAt)` → 寫回 `nextAllowedAt = slot + 1.05` → 解鎖 → 睡到 `slot` 才送出。睡眠期間不持有鎖，其他程序可以接著預約下一個時段，順序接近先到先得。
- **429 退避**：收到 429 時鎖住狀態檔，把 `nextAllowedAt` 與 `blockedUntil` 都推到至少 `now + retryAfter`，所有呼叫者一起等。
- **醒來後重新檢查**：只推 `nextAllowedAt` 不夠——已經預約了較早時段、正在睡的呼叫者不會受影響（實作任務 3.2 時發現）。所以每個呼叫者睡醒後、送出前，在鎖內再看一次 `blockedUntil`；仍在封鎖期就重新預約。`Retry-After` 可以是秒數或 HTTP-date；沒有這個 header 時依序用 2、4、8 秒。
- **上限**：同一請求最多重試 3 次；`Retry-After` 超過 60 秒視為限流用盡，不等。讀到的 `nextAllowedAt` 比現在晚超過 60 秒（時鐘回撥或狀態檔損毀）時視為過期，以現在為準重設。
- `flock` 隨檔案描述子關閉而釋放，程序中途死掉不會留下鎖。
- 狀態檔不放在 `~/.akashic`：`RealHomeSandboxGuard` 監看那裡，全套測試期間的寫入會被判成沙箱逃逸。

否決程序內的鎖：CLI 與 MCP server 是不同程序，兩個 session 同時跑就會超速。

### 測試接縫：三個受限的覆寫

測試不得碰真的 keychain 項目、真的網路、真的 `~/Library/Caches/akashic`。三個覆寫都走 `environment:` 注入參數（沿用 `LibraryLocator` 的慣例），而且各自有限制：

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
- `--json` 的輸出：`{"source":"semantic-scholar","endpoint":"<子命令名>","request":{…},"fetchedAt":"<ISO 8601，帶本機時區 offset>","total":<整數或 null>,"data":<S2 的資料，字串經 displaySafe>}`。分頁端點的 `data` 是全部筆數串成的陣列。
- 人可讀輸出與 `--json` 同源：分頁與單篇都一行一筆，格式為年份、標題、第一作者、主要 id。
- `status --json`：`{"keychain":{"service":"semantic-scholar","account":"default","present":<bool>,"readable":<bool>},"throttle":{"stateFile":"…","nextAllowedAt":"<ISO 8601 或 null>"},"host":"api.semanticscholar.org"}`。不印金鑰，也不印它的長度。

**結束碼**（新值不與既有的 1、64 衝突）：

| 碼 | 意思 |
|---|---|
| 0 | 成功 |
| 3 | 金鑰不可用：keychain 沒有這個項目，或 ACL 不允許非互動讀取。訊息寫明 service／account，並指向 `plugin/skills/akashic-bootstrap/references/semantic-scholar.md`；ACL 的情形另外說明要改成所有 app 可讀 |
| 4 | 限流用盡：同一請求 429 重試 3 次後仍是 429，或 `Retry-After` 超過 60 秒 |
| 5 | S2 或網路錯誤：404（訊息說明是哪一個 id 找不到）、其他 4xx、5xx、連線失敗 |
| 64 | 參數錯誤（ArgumentParser 既有），包括 base URL 覆寫不在允許的範圍 |

**MCP 工具 `akashic_s2`**：

- 參數：`endpoint`（`paper`／`match`／`batch`／`references`／`citations`／`recommend`／`author_search`／`author_papers`／`status`）、`id`、`title`、`year`、`name`、`ids`（陣列）、`fields`（陣列）、`offset`、`limit`。
- 回傳：`{"endpoint","total","returned","truncated","offset","nextOffset","data"}`。只放完整的筆數，加入下一筆會超過 48 KiB 就停，此時 `truncated: true`、`nextOffset = offset + returned`。
- `total` 的來源：references／citations 以同一個 paper 的 `referenceCount`／`citationCount` 取得（多一次請求，受同一個節流）；author-papers 以 author 的 `paperCount` 取得；search 類端點用 S2 回應的 `total`。
- 錯誤時 `isError: true`，文字與 CLI 同一段訊息（金鑰不可用、限流用盡、S2 錯誤）。

**驗收條件**：

- `swift test` 全綠，包括新的 `AkashicS2Tests` 與 CLI／MCP 測試；測試期間 `RealHomeSandboxGuard` 不報錯。
- `.githooks/run-guards.sh` 全綠，其中 `network-confinement` 通過、`network-confinement-mutations` 證明守衛會開火。
- 以 `URLProtocol` stub 驗證：只有 host 為 `api.semanticscholar.org` 的請求帶 `x-api-key`；網址中不含金鑰；429 重試至多 3 次；`Retry-After` 被遵守。
- 兩個子程序共用同一個 `AKASHIC_S2_STATE_DIR`、各送 3 個請求，所有請求的送出時間兩兩間隔至少 1 秒（容許 50 ms 誤差）。
- `AKASHIC_S2_KEYCHAIN_SERVICE=akashic-test-<隨機>`（不設 `AKASHIC_S2_BASE_URL`）時，`akashic s2 paper DOI:10.1037/a0038889` 以結束碼 3 結束；「讀不到金鑰時不發出任何請求」由 in-process 測試以 `URLProtocol` stub 驗證。
- 實機驗證（需真金鑰，只在使用者的機器上跑、不進自動測試）：`akashic s2 status` 回報 present／readable 皆為 true；`akashic s2 paper DOI:10.1037/a0038889 --json` 回傳該論文。

**範圍**：

- 在範圍內：`AkashicS2` target、`akashic s2` 子命令群、`akashic_s2` MCP 工具、`network-confinement` 守衛與負對照、兩份規則與 `CLAUDE.md` 索引、`README.md`、設定文件。
- 不在範圍內：任何使用者 skill 的接線、store 寫入、回應快取、其他需要金鑰的 API、`~/bin/akashic` 的重建（依 #633 的閘另外處理）。

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
