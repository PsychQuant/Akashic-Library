# 2026-09-29 取全文、Crossref 比對與摘要轉換的腳本變成 `akashic` 子命令（#629 第二塊）

`swift-is-the-implementation-language` 訂下「新的程式一律寫成 Swift」時，`plugin/` 裡還有 9 支 Python 與 2 支 shell 是規則成文之前就有的（列在該檔〈既有檔〉）。第一塊移植（守衛與 census）之後，剩下的全在三個 skill 裡：取全文（`akashic-fetch-fulltext`）、Crossref 比對（`akashic-bootstrap`）、摘要轉換（`akashic-venue-works`）。

這一塊把它們全部搬進 `akashic` CLI。同時解掉兩件不只是「換語言」的事：

- `crossref_match.py` 與 `calibrate_title_match.py` 用 `urllib` 直連 Crossref，違反 `web-access-via-safari-browser`（`Sources/` 沒有 HTTP client、skill 取外部資料一律經 safari-browser）。搬成 Swift 而不改這一點，等於把違規原樣移植。
- `fetch-fulltext.sh` 要不要算規則例外 1（純串接殼層），得先回答「它裡面有沒有判斷」。

## 舊檔 → 新位置

| 舊檔 | 新位置 |
|---|---|
| `akashic-fetch-fulltext/scripts/verify_pdf.py` | `akashic fulltext verify`（`FulltextVerify.swift`、`PDFReader.swift`） |
| `…/pdf_url_rules.py` | `akashic fulltext url-rule`（`PdfUrlRules.swift`） |
| `…/bot_signals.py` | `akashic fulltext bot-signals`（`BotSignals.swift`） |
| `…/jitter.py` | `akashic fulltext jitter`（`CauchyJitter.swift`） |
| `…/fetch-fulltext.sh` | `akashic fulltext fetch`（`FulltextFetch.swift`、`SafariBrowser.swift`） |
| `…/calibrate_title_match.py` | `akashic fulltext calibrate`（`TitleCalibration.swift`），改讀本機的 Crossref 回應目錄 |
| `akashic-bootstrap/scripts/crossref_match.py` | `akashic crossref-match`（`CrossrefMatch.swift`），改為「重播」協定，不連網 |
| `akashic-venue-works/scripts/ndjson-abstracts-to-proposals.py` | `akashic abstracts-to-proposals`（`AbstractProposals.swift`） |
| `…/scripts/tests/test_rules_and_verify.py`（54 個測試） | `Tests/AkashicKitTests/FulltextRulesTests.swift`（同 54 個，逐一移植） |
| `…/scripts/tests/fetch-fulltext-paths.sh`（19 條路徑） | `Tests/AkashicKitTests/FulltextFetchPathTests.swift`（對記憶體內的假瀏覽器跑） |
| `plugin/tests/ndjson-abstracts-to-proposals.py` | `Tests/AkashicKitTests/AbstractProposalsTests.swift` |

新的 SwiftPM target `AkashicSkillTools`（依賴 `AkashicCore`、`AkashicStoreIO`）放全部邏輯，`akashic` 只放 ArgumentParser 的殼。它不含 HTTP client；兩個守衛（`DisplaySinkCoverageTests`、`SanitizationBoundaryTests`）掃它。

## `fetch-fulltext.sh` 不是規則例外 1，所以搬進 Swift

例外 1 只收「串接」：檢查 binary、依序呼叫、下載、編排外部 CLI。逐行讀過之後，`fetch-fulltext.sh` 裡有 11 個出口是中止條款（結束碼 6）——遇到驗證挑戰、403／429、access denied、登入頁就整批停、分頁留著、不重試。那是**政策**：什麼算「懷疑是自動化」、停在哪一步、要不要關自己開的分頁，都是判斷，而且是這個 repo 對外行為的核心。規則說領域判斷一旦出現在殼層裡就移進 Swift，所以不能把它歸為例外。

搬法的重點是可測：`FulltextFetch` 只透過 `SafariBrowser` 協定碰瀏覽器，協定的輸入是逐字的 `safari-browser` 引數向量。真的實作（`ProcessSafariBrowser`）與測試裡的假瀏覽器收到同一串引數，「這支程式對瀏覽器說了什麼」可以逐條斷言。鎖分頁的方式沒動（`--window N --tab-in-window T`）——那是 #634 的 (b) 形狀，另案處理。

## `crossref-match`：不連網的重播協定

舊腳本邊比對邊向 Crossref 發請求。Swift 版不發請求，改成兩段式：

- `crossref-match --works <ndjson> --responses <目錄> -o <輸出>`：每個需要的請求以 `id`（網址去掉 `mailto` 之後 sha256 的前 16 個十六進位字元）標記；目錄裡有 `<id>.json`（200 的回應本體）或 `<id>.404`（查無）就消耗它。
- 還缺回應時結束碼 3，stdout 印 `{"pending":[{id,url}],"resolved":N,"total":M}`；skill 經 safari-browser 取回、存進目錄、再跑一次，直到結束碼 0。

比對與評分的邏輯是舊腳本的逐行移植；有三處刻意比舊腳本嚴，寫在下面〈刻意的行為差異〉。

## 證據：舊實作與新實作逐一對過

- **判定規則**（`verify` 的 assess、標題規則、DOI 正規化與尋找、頁數容差、`pdf-url` 三個出版商、`bot-signals`）：173,677 個生成案例、0 個不一致。語料是 237 個本機真 PDF 加上對抗性的隨機字串；各項操作的案例數：assess 146,100、title_match 15,444、title_score 9,444、norm_doi 94、expected_page_count 15、detect 410、page_one_doi 237、pdf_url 1,686、doi_from_xmp 247。
  **更正**：「0 個不一致」只對這組生成案例成立，不是對全部輸入。R1 驗證在這組之外找到可重現的分岔（NFKC、`İ`／`ı`、`\b`，與 url-rule 對畸形 IPv6 主機；見 `2026-09-29-b13p-verify-r1.md` 第 17 則），R2 驗證又找到一處（`bot-signals` 緊接 U+0345，第 19 則）。前三類與 U+0345 已修，IPv6 那一類是良性差異。
- **`fulltext verify` 對真 PDF**：1,728 種組合（呼叫真的 `pdfinfo`、`pdftotext`），stdout 與結束碼全相同。
- **`crossref-match`**：30 個種子 × 62 筆 works = 1,860 筆，用假的 Crossref 目錄與修補過的舊 `Client` 對跑，輸出檔逐位元組相同（`cmp`）。
- **`abstracts-to-proposals`**：60 個隨機 ndjson，結束碼、stdout、stderr 全相同。
- **`fulltext fetch` 對舊 `fetch-fulltext.sh`**：同一個 Python stub 下 18 個情境，結束碼、stdout、stderr、呼叫記錄與輸出檔全相同（舊測試 19/19 也仍過）。
- 正式 store 的 2,449 個 work DOI 全部通過 `crossref-match` 的 DOI 形狀檢查（0 個被擋）。

## 刻意的行為差異

- **參數錯誤的結束碼**：`fulltext fetch` 的用法錯誤改由 ArgumentParser 回 64（舊腳本是 1）；`FETCH_FULLTEXT_NAP` 環境變數拿掉（測試用的睡眠時間改由注入的 sleeper 承擔）。
- **`crossref-match` 三處更保守**：（一）回應的 DOI 與請求的 DOI 不同時具名拒絕（`IdentityMismatch`）——這是 PsychQuant/safari-browser#190 那個形狀（讀到上一批的結果、結束碼卻是 0）在比對端的防線；（二）要插進網址的 DOI 先驗形狀（`^10\.[0-9]{4,9}/[^\s'"\\$`#?%]+$`，且不含 `.`／`..` 路徑段），不合的具名拒絕；（三）搜尋端點回 404 或形狀不對，具名結束碼 1，不當成「沒有候選」。另外 `--delay` 拿掉（不再有請求可延遲），`--mailto` 進網址而不進 User-Agent（頁內 fetch 用 Safari 自己的 User-Agent）。
- **`fulltext calibrate` 缺記錄時不出數字**：舊腳本邊跑邊向 Crossref 取；現在讀 `--crossref` 目錄，缺哪些 DOI 就列出（連同要取的網址）、結束碼 3，除非明說 `--partial`。半套的數字不得冒充完整的。任何一個「別篇標題被收」結束碼 1。
- **`abstracts-to-proposals` 的 `--library`**：舊腳本自己解三步鏈；現在走 `LibraryOptions`（與其他子命令同一個解析）。跳過報告裡的不可印字元逃脫格式改成 `\u{001B}`（舊的是 `\x1b`）。
- **保留的 Python 怪癖**：舊腳本用 `splitlines()`，U+2028 也切行；Swift 版逐字保留（測試釘住），因為 ndjson 的實際內容不含它，改成只切 `\n` 會讓新舊在邊界輸入上分岔。
- `LibraryStore.sourceBlobURL(digest:)` 新增為 public——`abstracts-to-proposals` 要讀 `sources/` 裡的 blob，而原本只有內部的 `sourceURL`。

## 測試與負控

新增測試 159 個（XCTest；下表是各檔 `func test` 的個數）：

| 檔 | 個數 |
|---|---|
| `FulltextRulesTests.swift`（54 個逐一移植 ＋ 7 個邊界） | 61 |
| `PythonPortPrimitivesTests.swift`（`PySequenceMatcher`、`PyJSON`、`PyText`、`CauchyJitter`；期望值取自 Python 實跑） | 16 |
| `CrossrefMatchTests.swift` | 23 |
| `FulltextFetchPathTests.swift`（19 條舊路徑 ＋ 中止條款各出口 ＋ `GIT_DIR` 閘） | 26 |
| `AbstractProposalsTests.swift` | 16 |
| `TitleCalibrationTests.swift` | 5 |
| `SkillToolsCLITests.swift`（跑真 binary） | 12 |

順序是先把舊測試逐一移植、對舊實作跑過（證明測試本身對），再換成新實作。

負控分三批（27 ＋ 9 ＋ 1 ＝ 37 個 mutation），逐一注入、確認指名的測試變紅、再以反向編輯還原。第一批 27 個分布在 `FulltextVerify`／`PdfUrlRules`／`BotSignals`／`CauchyJitter`／`FulltextFetch`／`CrossrefMatch`／`AbstractProposals` 的核心分支（這一批的逐項清單只留在當次的工作紀錄，這裡不重述）。第二批 9 個是：

`CauchyJitter` 的截斷取樣（M17b）、`FulltextFetch.containsLoading` 恆回否（M30）、啟動分頁後不關自己開的分頁（M31）、`CrossrefMatch` 的去評論尾綴救援判成 probable（M32）、`TitleCalibration` 配對時不排除自己（M33）、landing 的 DOI 來源前綴改成大小寫不分（M34）、`PyText.splitLines` 少切 FF（M35）、`PyText.isSpace` 少 NEL（M36）、`AbstractProposals` 的 BOM 剝除（M38）。第三批 1 個見下一節：`ToolRunner.git` 不剝 `GIT_*`。

有兩個 mutation 一開始沒抓到，各自換成能抓到的形式：

- 「截斷取樣改成夾擠」在反函數取樣下與原碼等價（取樣值永遠落在區間內），改成「先不截斷地取樣、再夾擠」才是真的不同的行為，才抓得到。
- 「拿掉 BOM 剝除」沒被抓到，是因為 Foundation 讀檔時自己就會剝 BOM；補一個「位元組 3」的偏移測試（有 BOM 與沒有 BOM 的檔各一），讓剝不剝的差別在輸出裡看得見。

## 移植時多補的一道防線：`git` 呼叫剝除 `GIT_*`

全套測試第一次跑時 `GitSpawnHygieneTests`（#234／#239 的架構測試）紅了，指名 `FulltextFetch.swift` 與它的測試檔「spawn git 但沒有剝除 `GIT_*`」。那不是誤報：`fulltext fetch` 在碰瀏覽器**之前**用 `git -C <輸出目錄> check-ignore` 確認輸出路徑不會落進一個沒有忽略它的 git 工作樹（第三方全文不得進版控範圍），而 `git -C` 擋不住 `GIT_DIR`——從 git hook 執行時它指向呼叫 hook 的 repo，`check-ignore` 就是對錯的 repo 問的。舊的 `fetch-fulltext.sh` 用裸的 `git -C`，本來就有這個 fail-open；移植時原樣抄過來會把它一起帶過來。

改法：模組裡每一處 spawn git 都走 `ToolRunner.git(_:)`，它把環境剝掉 `GIT_*` 與 xcrun 選路的三個變數（`DEVELOPER_DIR`、`TOOLCHAINS`、`SDKROOT`，與 `AkashicStoreIO` 的同名 helper 同一條理由）。`ToolRunner.swift` 登記進 `GitSpawnHygieneTests` 的 `auditedFiles`。新測試 `testGitDirInTheCallersEnvironmentCannotMakeTheGateFailOpen` 造一個 `info/exclude` 寫 `*` 的誘餌 repo、把 `GIT_DIR` 指過去，要求閘仍以 `-C` 指的那個 repo 判斷、回結束碼 1 且沒碰瀏覽器；把 `ToolRunner.git` 的環境剝除拿掉，這支測試紅（結束碼 0：閘 fail-open，且開了分頁）。

## 守衛與清單

- `.githooks/run-guards.sh` 拿掉三個測試呼叫（兩個 Python、一個 shell），改註解列出 Swift 的取代者。
- `.githooks/protected-ratchet.txt` 以 `akashic-guards protected-ratchet --accept` 重生成（61 → 57 條；被拿掉的四條是兩個 ndjson 檔、`test_rules_and_verify.py`、`fetch-fulltext-paths.sh`），沒有手改。
- `ProtectedInventory.swift` 拿掉 `ndjson-abstracts-to-proposals.py` 的顯式條目。
- `WriteGateRulings.swift` 加 8 格（`fulltext` 的六個葉命令、`crossref-match`、`abstracts-to-proposals`），全部裁決為「不寫 store」；`--out` 的寫入是使用者指定的暫存檔（拒絕非一般檔案、`mkstemps` ＋ `rename`、權限 0600），不是 store。
- `mcp-cli-parity` 的 CLI-only 表加三列（`fulltext` 群組、`crossref-match`、`abstracts-to-proposals`）：三者都是 skill 的內部步驟，輸入是本機檔案，開 MCP 面等於要求呼叫端把整份 PDF 文字或整批回應當工具參數送進來。
- `swift-is-the-implementation-language` 的〈既有檔〉清單清空（Python 0、shell 4，恰為例外 1 的四個檔），語言組成重量為 Swift 497、Python 0、shell 4。`web-access-via-safari-browser` 的直連清單從 3 個減為 1 個（`assertions-must-be-measured.md`），鎖法一節的 grep 改為也掃 `Sources`。

## 誠實邊界

- **沒有跑過真的 Safari。** `fulltext fetch` 只對兩個替身跑過：舊測試用的 Python stub（18 個情境逐一與舊 shell 比對）與測試裡的記憶體假瀏覽器。它從沒對真的 `safari-browser` 說過話。
- **`fulltext calibrate` 沒有重跑校準數字。** 舊紀錄是「自己的標題 22/28 被收、別篇 0/808 被收」（2026-09-24，29 個 PDF）。這批 PDF 與當時的 Crossref 標題在本機找不到（找過 Downloads、各工作暫存目錄、`~/.akashic/sources/`——只有 5 個 PDF、沒有 Crossref 回應），而重取需要連網，這一輪不允許。替代的證據是上面的判定規則逐案對照（173,677 個案例 0 個不一致）——它證明 Swift 版與舊版判得一樣，不證明那組數字在新語料上仍成立。
- **Unicode 行為不是逐項可重現的。** Foundation 與 Python 在 NFKC、`re.I` 的大小寫等價類、`html.unescape` 的實體表上有差；`HTMLEntities` 只實作了用得到的子集，`&#abc;` 這類壞實體回 nil。上面的差分測試涵蓋了真語料與隨機字串，沒涵蓋全部 Unicode。
- **`plugins/akashic-discovery/skills/akashic-work-references/SKILL.md` 第 102 行**仍提到 `fetch-fulltext.sh`；那個目錄這一輪不歸我改，要由整合的人處理。
- **plugin 需要新 binary。** 三個 skill 現在呼叫的子命令只在含這次變更的 `akashic` 裡；plugin 的 `binary_version`（目前 0.12.1）要在 release 之後跟著升，舊 binary 上這些 skill 會找不到子命令。
- `docs/skill-evals/` 底下有一份 `skill-snapshot-old/scripts/crossref_match.py` 的舊快照，是評測當時的樣子，沒有動。
