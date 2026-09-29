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
- MCP 一次只回完整的筆數，整份以 48 KiB 為上限；回傳的 `truncated` 為 true 時，把 `nextOffset` 當下一次的 `offset` 續查。

## 存金鑰

金鑰放在 keychain 的 generic password：service `semantic-scholar`、account `default`。接口在程序內讀它。金鑰不收環境變數或指令參數（同一使用者的程序看得到環境變數），只在請求的 host 恰為 `api.semanticscholar.org`、scheme 為 `https` 時附在 `x-api-key` header，不出現在網址、輸出、錯誤訊息或任何檔案。

```bash
security add-generic-password -s semantic-scholar -a default -A -w
```

`-w` 放在最後、後面不接值，`security` 會提示輸入金鑰：它因此不進 shell 歷史，也不出現在指令參數（process list）裡。

**為什麼帶 `-A`**（所有 app 可讀）：

- `security` 建立項目時，預設只信任建立它的程式；接口以 `akashic` 或 `akashic-mcp` 的身分讀，會被存取權限擋下（結束碼 3 的第二種原因）。
- 接口讀 keychain 時一律不允許互動：MCP server 在背景執行，授權框沒有人能按。
- 只授權某一個 binary（`-T`）也行，但 `akashic` 是本機建置、ad-hoc 簽署的，每次重建都是新的 binary 身分，限定 binary 的存取權限隨之失效，得重新授權。

**取捨**：同一使用者下跑的任何程序都讀得到這把金鑰。S2 金鑰免費、有額度限制、可撤銷重發，這個風險可以接受。不接受的話改用 `-T <binary 路徑>`，代價是每次重建後都要刪掉重存。

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

```json
{"keychain":{"service":"semantic-scholar","account":"default","present":true,"readable":true},"throttle":{"stateFile":"…","nextAllowedAt":null},"host":"api.semanticscholar.org"}
```

skill 只看結束碼就能決定要不要請使用者設定。用 MCP 時呼叫 `akashic_s2` 的 `endpoint: status`，讀回傳的 `keychain.present` 與 `keychain.readable`；金鑰不在或讀不了時它也不會回 `isError`。

## 結束碼

| 碼 | 意思 |
|---|---|
| 0 | 成功 |
| 1 | 要讀參數以外才判得出的錯誤：`--ids-file` 讀不到或筆數不合、節流狀態檔無法使用、測試用的環境覆寫（`AKASHIC_S2_*`，一般使用不要設）被拒 |
| 3 | 金鑰不可用：keychain 沒有這個項目，或存取權限不允許不跳授權框就讀（下一節） |
| 4 | 限流用盡：同一請求 429 重試 3 次後仍是 429，或 `Retry-After` 超過 60 秒 |
| 5 | S2 或網路錯誤：404（訊息寫明哪一個 id 找不到）、其他 4xx、5xx、連線失敗 |
| 64 | 只看參數就判得出的錯誤：`--limit`、`--offset` 超出範圍、識別碼空白或含 `.`／`..` 路徑片段；早於任何 keychain 讀取與連線 |

MCP 遇到錯誤時回 `isError: true`，文字與 CLI 的錯誤訊息相同。

## 結束碼 3：兩種原因

訊息會寫明是哪一種，並指向本檔。

**1. keychain 裡沒有這個項目。** 訊息說「keychain 裡沒有 service「semantic-scholar」、account「default」的項目」。照〈存金鑰〉存一次。沒有金鑰時接口**不會退回匿名請求**（設計如此），什麼都不送出。

**2. 項目存在，但它的存取權限不允許在不跳出授權框的情況下讀取。** 訊息說「請把該項目改成所有 app 可讀」。刪除該項目，照〈存金鑰〉帶 `-A` 重存。

`status` 只說存在與可讀，不說原因；要看原因，跑一次任何查詢子命令讀它的訊息（金鑰不可用時，它在送出請求之前就停下）。

另有兩種少見的情形也是結束碼 3：項目的內容不是可用的金鑰（空的、不是 UTF-8，或含換行等控制字元），照〈存金鑰〉重存；其他 keychain 錯誤，訊息帶 OSStatus 碼，本檔不涵蓋。

## 頻率限制

- 全機所有程序（CLI、MCP server、多個 session）合計每秒至多 1 個請求。每個請求先在狀態檔上預約一個送出時段（間隔 1.05 秒），等到時段才送。分頁端點的每一頁各占一個時段，一次取全部 references 會花對應的時間。
- 狀態檔在 `~/Library/Caches/akashic/s2-throttle`（目錄 0700、檔案 0600）。可以刪，下次請求會重建；空檔、損毀的內容、或存的時間比現在晚超過 60 秒，都視同全新。
- 收到 429 時，所有呼叫者一起退避：共用的下次可送時間被推到 `Retry-After` 之後（秒數或 HTTP 日期都收；沒有這個 header 時依序等 2、4、8 秒），再重試同一個請求，至多 3 次。仍是 429，或 `Retry-After` 超過 60 秒（不等），就是結束碼 4。
