# 寫進 store

## 有正規入口的操作

| 要做的事 | 入口 | 語意 |
|---|---|---|
| 建立新 work | `akashic_create_entry` MCP | **create-only**——目的檔已存在直接拒寫 |
| 建立新 person | `akashic_add_person` MCP | **create-only**——key 已存在直接拒 |
| 從裸字串作者批次建 person | `akashic bootstrap-people --apply` CLI | 有 `--min-occurrences` 與 `--limit`；計畫讀到 legacy 拷貝（同一筆 work 或 person 在 `entries/`／`people/` 還有一份）或無法唯一定位的記錄（work：citekey 重複、與另一筆共用 id，或檔案寫入時會被拒；person：key 重複，或檔案寫入時會被拒——`akashic validate` 說出是哪一種）時整批拒絕、零寫入。乾跑逐份、逐筆點名，`--json` 的 `legacyCopiesInPlan`／`unlocatableInPlan` 是兩個計數；拷貝確認 entities/ 那份是新的之後刪掉 legacy 那份，無法唯一定位的先修好，再跑（#709） |
| 把裸字串作者歸戶到 person | `akashic resolve-people --apply` CLI | 篩選式批次：寬鬆層（非 exact）要 `--tier` 具名；有 `--citekey` / `--person` 可收窄；淘汰而得的唯一候選自動排除（#624）。**查過但判不出來的配對不要放進批次**——工具看不到它（#619），確認過的逐筆 `--judge` 或 MCP 三段 id 送 |
| 匯入 WoS tab-delimited 匯出 | `akashic import-wos` CLI | 有 `--dry-run`；citekey 撞號且內容不同時**不覆寫** |
| 加標籤 / 關係 / 狀態 | `akashic_tag` / `akashic_link` / `akashic_set_status` MCP | — |
| 依作品全文整組替換作者列 | `akashic update-entry --replace-authors <JSON>` CLI／`akashic_update_entry` 的 `replace_authors` MCP | 預設乾跑；判定——依據（全文 digest、PDF 頁序）與理由必填，寫成作者列替換記錄；已歸戶位要 `from` 沿用或 `release` 附理由；團體成員記在 `group-members`；需要 store format 23（#742）。流程走 `akashic-verify-work` skill |

以上全部走 store 自己的編碼路徑，產出的位元組形式一致。

## 沒有正規入口的操作

**更新既有 work 的部分欄位，各欄位的路徑不同**（`create_entry` 與 `add_person` 都是 create-only，對已存在的目標拒寫，不能拿來改）：

- **作者列**：`update-entry --replace-authors`（上表；#742）。依作品本身的 byline 整組替換，依據寫進 store。局部的改動另有 `resolve-people` 的歸戶、拆分、移除各腿。
- **其他欄位**（標題、卷、期、頁碼、article number、日期）：`enrich` 只補**不存在**的鍵；值錯了要先 `update-entry --remove-field <鍵>=理由` 移除再 `enrich` 補。這條路寫得進值，卻**記不下「出自哪份全文第幾頁」**——`enrich` 的來源記錄要 url 與 HTTP 狀態，本機全文沒有這兩欄。依全文更正這些欄位的寫入面是 #742 之後另開的 issue。
- 上面都涵蓋不到的改動（例如改一個已存在、沒有專用面的值）仍沒有正規入口，下面的紀律適用。這份文件其餘段落的過時之處記在 #743。

沒有正規入口時：

### 保證或檢查，二擇一——兩個都沒有才是錯的

真正保護 store 的是「**同一份資料只有一種位元組形式**」這個不變式。有兩條路可以守住它：

- **保證**：走編碼器（decode → 改 → encode）。形狀由建構決定，不可能錯。
- **檢查**：直接改檔，然後 round-trip 驗——把改完的檔案 decode 再 encode，比對位元組是否與檔案相同。相同＝仍在 canonical form。

**兩者選一即可，但不得都沒有。** 手改之所以危險，正是因為它同時跳過了這兩者。

> **現況（重要）**：round-trip 檢查目前只能靠寫一支呼叫 `EntryYAML.decode`／`encode` 的一次性程式來做——**代價與直接走編碼器相同**。所以「直接改檔比較省事」這條路**現在還不存在**：省不掉的部分是驗證，不是寫入。
>
> 既然代價相同，**預設走編碼器**——它至少用建構換到了保證，而檢查只換到事後的確認。
>
> 這條限制會在 `akashic fmt --check`（Akashic-Library#69）落地後消失：屆時檢查是一個指令，手改 + 驗才真的變便宜。在那之前不要把「可以直接改」讀成「可以直接改而不驗」。

**一定要走編碼器的情況**（連檢查都不足以替代）：記錄帶你不認得的欄位。那可能是 tolerant-preserve 保留的未知區塊，手改極容易破壞它，而破壞後 round-trip 檢查會通過——因為 decode 已經先把它丟了。

### 走編碼器時：decode → 改 → encode

用 store 自己的編碼器讀進來、改物件、再寫回去。這樣未知欄位、排序、引號風格全部由編碼器保證，且它的寫入自檢（canary）仍然生效。

在 Akashic-Library 的 package 裡，這是一段用完即刪的一次性程式：

```swift
let input = try String(contentsOf: url, encoding: .utf8)
var entry = try EntryYAML.decode(input)        // person 用 PersonYAML
for (k, v) in newFields where entry.fields[k] == nil {
    entry.fields[k] = v                        // 只補空的，不覆寫既有值
}
let out = try EntryYAML.encode(entry)          // 編碼器保證形狀
if out != input { try out.write(to: url, atomically: true, encoding: .utf8) }
```

三個要點：

- **`where entry.fields[k] == nil`** —— 只補空欄位。覆寫既有值需要另外的判斷（那個值是誰寫的？比新的可靠嗎？），不該混在補完裡順手做。
- **`if out != input`** —— 沒變就不寫。這讓「重跑一次」是安全的，也讓改寫檔數變成可驗證的數字。
- **先跑一次不寫檔的版本**，確認改寫筆數與新增欄位統計符合預期，再實際寫。

### 直接改檔時：改完一定要驗

在 store 之外拼 YAML 字串寫檔而**不驗**，是唯一真正錯的走法。實際後果（Akashic-Library#69 的實證）：同一份資料出現兩種位元組表示，而且下一次任何正規寫入碰到那些檔案會靜默重排——產生看起來像資料變更、實際只是排版的 diff，review 的人分不出來。

危險的不是「用 Edit 改了檔」，是「改完沒人知道還是不是 canonical」。所以直接改的流程是：

1. 改之前先看清楚該檔目前長什麼樣（欄位順序、引號風格、有沒有你不認得的欄位）
2. 改（新欄位依既有欄位的排列規則插入——`fields` 是字母序）
3. **驗**：decode → encode → 比對位元組。不同就代表你改出了非 canonical 的東西，改回去走編碼器
4. `akashic validate` 與 `akashic doctor`

**看到不認得的欄位就停**——那可能是 tolerant-preserve 保留的未知區塊，手改極容易破壞它。那種記錄一律走編碼器。

## 批次操作的範圍問題

**`bootstrap-people` 是全 store 掃描，沒有範圍旗標。** 直接跑會把整個 store 的裸字串作者都建成實體。實測某個 store：只想處理 100 篇論文的作者（745 個候選），全 store 跑會建 1871 筆。

**限定範圍的作法**：另建一個只含目標記錄的暫存 store，在那裡跑，再把產出的實體檔複製回主 store。

> ⚠️ **下面的 `--library` 是「開哪個 store」，不是 membership 分類（#315）。** 同名的
> MCP 參數（`akashic_person(library:)`）指的是 store **內**的分類——見 `SKILL.md`。
> 兩者同名、不同型別、**錯用不會報錯**。
>
> 另外：`--apply` 屬破壞性寫入，未指定 `--library` 時會**拒絕執行**並說出它解析到的
> store（#298）。下面的例子每條都帶 `--library`，所以不會撞到那個閘。

```bash
akashic doctor --library <暫存路徑>          # 建立佈局
# 把目標 work 的 YAML 複製進 <暫存路徑>/entities/
akashic bootstrap-people --apply --library <暫存路徑>
# 把產出的 person YAML 複製回主 store
akashic doctor                               # 主 store 重建 index
```

這樣**產生實體的邏輯仍是正規工具**，只有檔案搬移是手動的——而實體檔是自足的（UUID 由 key 決定性推導，跨 store 一致）。

**複製前必查兩件事**：

1. **UUID 檔名與 person key 是否與主 store 碰撞**——零碰撞才能複製
2. **主 store 是否已有記錄能對上這些裸字串**——暫存 store 看不到主 store 的既有 person，會重複建立。先在主 store 跑一次 `resolve-people`（不加 `--apply`）看有沒有落在目標範圍內的候選

實測第 2 點：某次全部 82 個候選都落在目標範圍**之外**，所以暫存 store 的作法對該範圍零重複——但這是查出來的，不是假設出來的。

**`resolve-people` 有 `--citekey`／`--person`／`--tier`**（可重複），歸戶階段的範圍限定有正規支援，不需要繞——但注意收窄不豁免寬鬆層的 `--tier` 具名要求（#303）。

## 安全網

**動手前確認退路。** store 若在 git 管控下，先確認工作樹乾淨（或先 commit）——批次寫入沒有內建復原。不在 git 下就先複製一份。

**記錄新增的檔案清單。** 批次建立時把產生的檔名寫進一份清單，回復時才能精確移除（`git checkout` 不會刪掉未追蹤的新檔）。

**寫完驗證**：

```bash
akashic validate      # schema 與跨記錄檢查
akashic doctor        # 佈局、index、孤兒、未歸戶計數
```

`doctor` 的 `unresolved author literals` 計數是補完進度的直接指標。

## 原始資料存成 source

外部查來的東西（API 回應、機構字串、著作清單）以內容定址存進 `sources/`，並在 `sources/index.jsonl` 追加一列 provenance：

```json
{"content": "sha256:<hash>", "bytes": 174999, "media-type": "application/json",
 "retrieved": "2026-08-04", "origin": "<來源與查詢方式>", "acquisition": "api",
 "note": "<未正規化／未決問題／對應 issue>"}
```

檔案放 `sources/<hash 前 2 碼>/<其餘>`，無副檔名。上例是 API 直接回應的寫法；經 safari-browser 讀到的內容（頁內 fetch、DOM 讀取）怎麼寫 `acquisition`／`origin`／`media-type`，見 [web-access.md](web-access.md)〈承重存檔〉——那不是伺服器的原始位元組，不要照抄 `"api"`。

**`sources/` 通常被 gitignore 擋住**（第三方原始位元組只留 local）。存之前用 `git check-ignore sources/index.jsonl sources/<hash 前 2 碼>/<其餘>` 確認擋住了——**不加 `-v`**：它只印出被排除的路徑，沒印出來的就沒被排除；`-v` 也列出被否定規則放回來的路徑（那一行的規則以 `!` 開頭）。這件事失敗是不可逆的（推上去就在遠端了）。`akashic store-source` 寫入前自己也以 git 驗這幾條路徑，沒被排除就拒寫。

存 source 的價值是讓「這個欄位憑什麼是這個值」之後查得到。特別是當你**刻意不把某些資料寫成實體**時（例如建模問題未決），source 讓資料不會消失，判斷可以之後補。
