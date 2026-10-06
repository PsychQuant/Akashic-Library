# Semantic Scholar：金鑰設定與使用

`akashic s2 <子命令>`（CLI）與 MCP 工具 `akashic_s2` 查 Semantic Scholar（S2）。兩者共用同一個接口：金鑰從 keychain 讀、全機每秒至多 1 個請求、只讀。**沒有金鑰就不會送出任何請求**（結束碼 3），所以第一次用先做〈存金鑰〉。

**S2 的回應是線索，不是寫入的依據。** 這個接口不開 store、不寫 store；它回傳的值要進 store，得先回被引作品本身核對，見 [source-of-truth-over-consent](../../../rules/source-of-truth-over-consent.md)。

## 能查什麼

| 子命令 | MCP `endpoint` | 用途 |
|---|---|---|
| `paper <paper-id>` | `paper` | 一篇論文 |
| `match --title <標題>` | `match` | 以標題比對一篇（可加 `--year`） |
| `batch --ids-file <檔>` | `batch` | 批次；檔案一行一個 id，至多 500 個（MCP 用 `ids` 陣列） |
| `references <paper-id>` | `references` | 參考文獻 |
| `citations <paper-id>` | `citations` | 引用它的論文 |
| `recommend <paper-id>` | `recommend` | 相似論文（`--limit` 1–500，預設 100） |
| `author-search --name <姓名>` | `author_search` | 以姓名搜尋作者 |
| `author-papers <author-id>` | `author_papers` | 一位作者的著作 |
| `status` | `status` | 檢查金鑰與節流狀態，不連網 |

- `paper-id` 照 S2 的寫法（`DOI:…`、`CorpusId:…`、S2 paperId）；以 `10.` 開頭的裸 DOI 自動加 `DOI:`。
- `--fields` 是逗號分隔的 S2 欄位名，照原樣轉給 S2；省略時論文類取 `title,year,authors`、作者類取 `name,paperCount`。
- CLI 加 `--json` 輸出 `{"source","endpoint","request","fetchedAt","total","data"}`。分頁端點（references、citations、author-papers）CLI 預設取全部，用 `--limit`、`--offset` 收窄，輸出不截。
- MCP 一次只回完整的筆數，整份以 48 KiB 為上限。**續查看 `nextOffset`**：非 null 就把它當下一次的 `offset`，null 就是沒有下一頁。`truncated` 只表示被 48 KiB 上限截斷，不是續查的訊號（預設一頁 100 筆剛好放得下、S2 還有更多時，`truncated` 是 false、`nextOffset` 非 null）。
- 分頁端點（references、citations、author_search、author_papers）的 `limit` 預設 100、至多 1000；`paper`、`match`、`batch`、`recommend` 不分頁，`nextOffset` 永遠是 null。`batch`／`recommend` 被截斷（`truncated` 為 true）時，少給幾個 id、少要幾個 `fields` 重查。第一筆就超過 48 KiB 時回錯誤，用 `fields` 縮小（例如拿掉 abstract、authors）或改用 CLI。

## 存金鑰

金鑰放在 keychain 的 generic password：service `semantic-scholar`、account `default`。接口在程序內讀它。金鑰不收環境變數或指令參數（同一使用者的程序看得到環境變數），只在請求的 host 恰為 `api.semanticscholar.org`、scheme 為 `https` 時附在 `x-api-key` header，不出現在網址、輸出、錯誤訊息或任何檔案：請求不經任何快取或 cookie 儲存，也不跟隨轉址（S2 回 3xx 就是錯誤、結束碼 5），所以金鑰不會被寫進磁碟，也不會被帶到別的主機。

```bash
security add-generic-password -s semantic-scholar -a default -A -w
```

`-w` 放在最後、後面不接值，`security` 會提示輸入金鑰：它因此不進 shell 歷史，也不出現在指令參數（process list）裡。

**為什麼帶 `-A`**（所有 app 可讀）：

- `security` 建立項目時，預設只信任建立它的程式；接口以 `akashic` 或 `akashic-mcp` 的身分讀，會被存取權限擋下（結束碼 3 的第二種原因）。
- 接口讀 keychain 時一律不允許互動：MCP server 在背景執行，授權框沒有人能按。
- 只授權特定 binary（`-T`）也行，但 `akashic` 是本機建置、ad-hoc 簽署的，每次重建都是新的 binary 身分，限定 binary 的存取權限隨之失效，得重新授權。**讀金鑰的有兩個不同的 binary**：CLI 的 `akashic` 與 MCP server 的 `akashic-mcp`，`-T` 要各給一個（`-T <akashic 的路徑> -T <akashic-mcp 的路徑>`）；只授權其中一個，另一個會以結束碼 3 讀不到。

**取捨**：同一使用者下跑的任何程序都讀得到這把金鑰。S2 金鑰免費、有額度限制、可撤銷重發，這個風險可以接受。不接受的話改用 `-T`（兩個 binary 各一個），代價是每次重建後都要刪掉重存。

**`-A` 的另一面：不要用別的方式把金鑰印出來。** 帶 `-A` 時，同使用者的任何程序（包括 AI agent 的 shell）都能用 `security find-generic-password -s semantic-scholar -w` 不經提示印出金鑰，值就進了對話或 log。接口自己永遠不印金鑰，但這條路不在接口裡：skill 與 agent **不得**直接讀這個項目（也不得加 `-w`、`-g` 印它）；要確認金鑰在不在，用 `akashic s2 status`。

**換金鑰或改存取權限**：

- 只換金鑰的值：同一條指令加 `-U`（項目已存在時更新）。
- 改存取權限**不要靠 `-U`**：本檔沒有驗證它會不會改動既有項目的存取權限。先刪除，再照上面的指令加一次：

```bash
security delete-generic-password -s semantic-scholar -a default
```

## 確認

```bash
akashic s2 status          # 人可讀
akashic s2 status --json
```

不連網。回報 keychain 項目（service、account）存在與否、能不能在不跳授權框的情況下讀，以及節流狀態檔與下次可送時間。**不印金鑰，也不印它的長度。** 結束碼 0＝存在且可讀，3＝不是。

結束碼 0 與 3 之外還有三種結果，**都不是「沒有金鑰」**：1＝`AKASHIC_S2_*` 測試覆寫被拒（一般使用不要設）；64＝裝的 `akashic` 比 #664 舊、沒有 `s2` 子命令（ArgumentParser 的用法錯誤）；MCP 的「未知工具」＝裝的 `akashic-mcp` 比 #664 舊（plugin 釘的 binary 版本可能還沒有這個工具）。另外 `AKASHIC_S2_BASE_URL` 生效時 `status` 不讀 keychain、直接回 0，只出現在測試。

```json
{"keychain":{"service":"semantic-scholar","account":"default","present":true,"readable":true},"throttle":{"stateFile":"…","nextAllowedAt":null},"host":"api.semanticscholar.org"}
```

skill 只看結束碼就能決定要不要請使用者設定。用 MCP 時呼叫 `akashic_s2` 的 `endpoint: status`，讀回傳的 `keychain.present` 與 `keychain.readable`；金鑰不在或讀不了時它也不會回 `isError`。

## 結束碼

| 碼 | 意思 |
|---|---|
| 0 | 成功 |
| 1 | 要讀參數以外才判得出的錯誤：`--ids-file` 讀不到、超過 256 KiB、筆數不合、有一行不像識別碼（含空白或控制字元、超過 512 字元；送出前就擋），節流狀態檔無法使用，測試用的環境覆寫（`AKASHIC_S2_*`，一般使用不要設）被拒 |
| 3 | 金鑰不可用：keychain 沒有這個項目，或存取權限不允許不跳授權框就讀（下一節） |
| 4 | 限流用盡：同一請求 429 重試 3 次後仍是 429，或 `Retry-After` 超過 60 秒，或另一個呼叫者記下的 429 封鎖還剩超過 60 秒（不送請求、不睡） |
| 5 | S2 或網路錯誤：404（訊息寫明哪一個 id 找不到）、其他 4xx、5xx、連線失敗 |
| 64 | 只看參數就判得出的錯誤：`--limit`、`--offset` 超出範圍、識別碼或 `--title`／`--name` 空白、識別碼含 `.`／`..` 路徑片段；早於任何 keychain 讀取與連線 |

MCP 遇到錯誤時回 `isError: true`，文字與 CLI 的錯誤訊息相同。

## 結束碼 3：兩種原因

訊息會寫明是哪一種，並指向本檔。

**1. keychain 裡沒有這個項目。** 訊息說「keychain 裡沒有 service「semantic-scholar」、account「default」的項目」。照〈存金鑰〉存一次。沒有金鑰時接口**不會退回匿名請求**（設計如此），什麼都不送出。

**2. 項目存在，但現在無法在不跳出授權框的情況下讀取。** 狀態碼 `errSecInteractionNotAllowed` 有兩個原因，訊息依序列出：(a) **keychain 鎖著**（SSH 或背景工作階段最常見）——先解鎖，不必動項目；(b) 項目的存取權限不允許——刪除該項目，照〈存金鑰〉帶 `-A` 重存。先排除 (a)：解鎖後問題消失就不用重存。

`status` 只說存在與可讀，不說原因；要看原因，跑一次任何查詢子命令讀它的訊息（金鑰不可用時，它在送出請求之前就停下）。

另有兩種少見的情形也是結束碼 3：項目的內容不是可用的金鑰（空的、不是 UTF-8，或含換行等控制字元），照〈存金鑰〉重存；其他 keychain 錯誤，訊息帶 OSStatus 碼，本檔不涵蓋。

## 沒有金鑰時，skill 怎麼查

skill 查 Semantic Scholar 之前先看 `status`：

1. **結束碼 0（金鑰存在且可讀）**：一律用 `akashic s2`／`akashic_s2`。不會再經 safari-browser 查 S2——那會用另一個額度打同一個主機，繞過全機節流。
2. **結束碼 3（沒有金鑰或讀不到）**：skill 先請你照〈存金鑰〉設定。你不設定、或這次設定不了，skill 才**最後**經 safari-browser、不帶金鑰查 S2（共用額度，常回 429；照 [web-access.md](web-access.md) 的程序與中止條款）。

查詢遇到結束碼 4 或 5 時，skill 不會改走 safari-browser 補查。`akashic s2` 本身沒有匿名模式：退到 safari-browser 的是 skill，不是這個接口。

## 頻率限制

- 全機所有程序（CLI、MCP server、多個 session）合計每秒至多 1 個請求。每個請求先在狀態檔上預約一個送出時段（間隔 1.05 秒），等到時段才送。分頁端點的每一頁各占一個時段，一次取全部 references 會花對應的時間。
- 狀態檔在 `~/Library/Caches/akashic/s2-throttle`（檔案 0600，已存在而較寬的會收緊；目錄在建立時是 0700，已存在的目錄不改權限；不跟隨 symlink）。可以刪，下次請求會重建；空檔、損毀的內容、或存的時間比現在晚超過 60 秒，都視同全新。
- 收到 429 時，所有呼叫者一起退避：共用的下次可送時間被推到 `Retry-After` 之後（秒數或 HTTP 日期都收；沒有這個 header 時依序等 2、4、8 秒），再重試同一個請求，至多 3 次。仍是 429，或 `Retry-After` 超過 60 秒（不等），就是結束碼 4。**不論這次呼叫等不等，429 都先記進共用狀態**（最多記一小時）：其他呼叫者遇到剩下超過 60 秒的封鎖，不睡、直接結束碼 4；60 秒以內才睡過去再送。
