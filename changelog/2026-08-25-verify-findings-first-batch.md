# 驗收條件只問「有沒有多」——#394 的 6-AI verify 第一批修復

2026-08-25 清晨。`wf_fa0fabd3-065` 回報 **52 個 merged finding**（5 CRITICAL、17 HIGH），
其中三件已經作用在真實 store 上。本篇記第一批修復，以及一個我自己在過程中犯下、
被編譯器打臉的歸因錯誤。

## 為什麼「遷移後 `validate` 零新增 diagnostic」通過了，而東西是壞的

那條驗收條件是**單調遞增**的檢查——它只抓得到「多」。而一次遷移最典型的傷害是
**少**（警告消失）與**變質**（訊息變成假的），兩者它都看不到。

實測（`~/.akashic`，遷移前後各算一次）：

| | 遷移前 | 遷移後 |
|---|---|---|
| 「DOI 被 N 筆 work 共用」警告 | **18 組** | **0** |
| 其中改由下一條檢查印成「標題與年份相同但 **DOI 不同**」 | — | **15 組**（而兩筆 DOI 逐字相同）|
| 其中完全靜默 | — | **3 組** |

`LibraryStore.validate` 的那條檢查讀 `e.fields["doi"]`，而 §8 的遷移把 664 筆的
`fields.doi` 移走了。**一條檢查變瞎不只是少報，它讓另一條開始說謊**——第二條用
`reportedByDOI` 抑制「已被 DOI 那條涵蓋」的組，而那個集合現在是空的。

一個具體實例：

```
⚠ [跨記錄] 標題與年份相同但 DOI 不同的 2 筆 work（zhou2017bincidence, zhou2017incidence）
                                     ^^^^^^^^  兩筆都是 10.1007/s00277-017-3160-1
```

## 同一個坑的第三與第四次

changelog 自己在 `2026-08-24-migrate-identifiers.md` 開了一節叫「同一個坑，這一節踩了
兩次」。ensemble 又找到四處，全部是「能力做好了、呼叫端沒接線」：

| 面 | 修前 | 修後 |
|---|---|---|
| `CSLExport`（csl-json，CLI ＋ MCP 兩面） | DOI 3 / ISSN 0 / ISBN 2 | **667 / 176 / 31** |
| `RelationalExport`（`export-tables` 的 `publication.doi`） | 3 | **664** |
| `WoSImport.identity`（重跑會生重複） | `created 1` | **`created 0`** |
| `BibExport.apa7Report`（評的 BibEntry ≠ 實際匯出的那份） | 分岔 | 接上 `venues` |

**最後那一條是編譯器找到的**，因為這一輪同時做了另一件事：拿掉 `venues:` 的預設值。

### 預設空值把編譯期錯誤降級成執行期靜默

`bibEntry(…, venues: [String: Venue] = [:])` 這個預設讓漏接的呼叫端**編譯照過**，
然後在執行期安靜地少一個欄位。移除它之後編譯器立刻指出 `apa7Report`——那正是
ensemble 另外找到的一條。

代價是 62 處測試呼叫要補參數（13 個測試檔）。換到的是這一類漏接以後不可能再靜默。

## 我在過程中犯的歸因錯誤

看到「`canonicalDOIs` 零 production 呼叫端」＋「doc comment 寫著『讀取請走
canonicalDOIs』」，我**推導**出一個能同時解釋兩者的機制：那些 accessor 不是
`public`，所以 module 外呼叫不到。於是我加上 `public`、寫進 commit message、
也告訴了使用者。

它是假的。那個 extension 本來就是 `public extension Entry`。打臉來自
`swift build -Xswiftc -warnings-as-errors`：

```
error: 'public' modifier is redundant for property declared in a public extension
```

四個未接線的呼叫端**就是四次疏忽**，沒有結構性解釋。

記在這裡是因為它與本篇的主題同形：**一個看起來自洽的說法，掩蓋著沒被量測的那一半。**
`assertions-must-be-measured` 的四個問題裡，我沒問「這句話怎麼驗」。

## 遷移的寫入順序——唯一還會再毀資料的那個

`IdentifierMigration.run(apply:)` 先寫全部 work（`fields.issn` 已刪）、再逐一嘗試
venue。venue 那格失敗時 ISSN **從兩邊都消失**，而且工具內不可逆（重跑回報 0 筆可改，
因為沒有東西可搬了）。兩個觸發條件都被端到端重現過：venue 檔未被 git 追蹤、venue key
懸空。

**這不是沒人想到的形狀。** `mcp-cli-parity` 為這條命令新增的那一列自己寫著：

> 它多一個該族沒有的性質——它會**跨記錄搬動資料**（work 的 `issn` 移位到它的 venue），
> 所以一次失敗的部分寫入會讓兩邊都不對

規則指名了風險，實作沒有對應的守衛。

修法：所有前提（venue 存在、venue 檔被追蹤、work 檔被追蹤）在**任何寫入之前**裁決；
落點被擋的 work **整筆不動**，不是「照寫但少一個欄位」——它的 `fields.issn` 是那個號
此刻唯一的棲身處。

**trackedness 改成乾跑也查。** 先前只在 `apply` 內查，於是一個保證會毀資料的前提在
乾跑輸出裡完全看不見——而這條命令的 doc comment 主張乾跑存在的理由正是
「讓會靜默毀資料的問題在寫入前現形」。

`Report.failed` 收斂成 `blockers`（`no-compat-fallback`：不留兩條讀法）。前者的語意是
「寫到一半失敗」，而那正是本命令不該有的狀態。

## `run()` 的測試，此前是零

ensemble 指出改寫了 731 個檔的那個函式全樹零覆蓋，而兩支姊妹遷移（`VenueMigration`／
`PersonIdentityMigration`）各有 8 與 10+ 支 `run()` 測試。

補 5 支。**負控**：移除 `blockedEntries` 過濾後 **3/5 轉紅**；另 2 支（快樂路徑、乾跑）
保持綠是正確的，它們本來就不受該 mutation 影響。

## 一個誠實記錄的行為改變（非回歸）

`WoSImportTests` 的 fixture 用 `10.1/abc`，而那**不是形狀合法的 DOI**（`DOI.init`
要求註冊者 ≥4 碼）。改讀 `canonicalDOIs` 之後它落回 (標題, 年份)——於是先前有
**4 支測試通過的理由是錯的**：它們以為在測 DOI 身分，實際測到的是標題年份。

真實 store 有 **3 筆**解析不出的殘留（`DOI ` 前綴、`Doi ` 前綴、附錄 DOI 黏在後面），
它們現在退回 (標題, 年份)。**不是回歸**——舊實作對同樣那 3 筆也配不上（庫內鍵是
`doi:doi 10.1037/…`、probe 是 `doi:10.1037/…`）。差別只在退路。

## 尚未修（具名，不假裝不存在）

| # | 內容 | 為什麼還沒動 |
|---|---|---|
| 1 | 沒有任何讀取面顯示 venue 的 ISSN（org 的 ROR 同理） | 使用者自己找到的那一條，影響 39 個 venue |
| 2 | 遷移刪掉 **8 筆**的括號註記（`(Electronic)`／`(Print)`／`(Linking)`／`(alk. paper)`／`(hardcover)`）且不在報告任何一處 | 需要裁決：qualifier 要不要建模。可逆（`9e22750` 仍在）|
| 3 | `store.yaml` 仍宣告 `format: 12` 而資料已是 13 的語意 | bump 前要確認三個 binary 都換代 |
| 4 | `rewritingProvenance` 是恆等空殼，而 `tasks.md` 8.3 標 `[x]` | 文件層 |
| 5 | `enrich-from-zotero` 會把遷移刪掉的殘留寫回來 | 會讓遷移部分回退 |

**兩席缺席**：`logic` 與 `security` 兩個 lens 都因 API 中斷未完成，而它們正是最該看
`Identifier.swift`（check-digit 算術、raw/normalized 設計）與 `displaySafe()` 紀律的
兩席。**下面沒有它們的 finding 不代表那兩個面乾淨，只代表沒有人看過**——修完這批要
重跑它們。
