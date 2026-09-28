# 2026-09-29 既有 skill 的網頁取得指令遷移到 safari-browser（#634）

`.claude/rules/web-access-via-safari-browser.md` 訂下「skill 讀外部網頁或 web API 一律經 safari-browser」時，有 11 個既有檔寫的是別的取得方式（直接給 API 網址、`curl`、WebFetch、`urllib.request`，另有 osascript 與「一般 HTTP 下載」）。兩條路並存的後果：中止條款與 profile 鎖只在其中一條生效，同一個網站會從另一條路繼續被請求。

2026-09-29 量測：11 個檔裡有 8 個是散文（`SKILL.md`、`references/*.md`），可以只改文字；另外 3 個各有阻塞原因（見〈誠實邊界〉）。

## 改了什麼

**新檔 `plugin/skills/akashic-bootstrap/references/web-access.md`**：操作程序。規則檔在 plugin 安裝處讀不到（repo 為 private），所以 `plugin/` 的 skill 需要一份自己讀得到的程序；它只寫怎麼做（問 profile、`--profile`＋`--url-exact`＋一次性 fragment 鎖分頁、轉址頁怎麼找回分頁、插值前的形狀檢查、頁內 fetch 存檔並核對身分、讀渲染後的頁面），理由與例外清單留在規則檔。中止條款**不重寫**：指向 `akashic-fetch-fulltext` SKILL.md〈中止條款〉，只補取 API 時多出來的三種形狀。

逐檔（原本 → 改成）：

- `akashic-bootstrap/references/person-sources.md`：ORCID 三個端點是裸網址加 `Accept: application/json` 標頭 → 標成要取的位址、指向 web-access.md，JSON 改為頁內 `fetch` 的第二個參數；個人網站與名冊的批次抓取加「經 safari-browser、逐筆不平行」；「抓取禮儀」段的被擋處置從「留延遲」改成「被擋就是中止條款，不記成頁面不存在也不放慢重試」。
- `akashic-bootstrap/references/work-sources.md`：Crossref 端點附 `User-Agent: … (mailto:…)` → 頁內 fetch 送 Safari 自己的 User-Agent，信箱改放 `&mailto=` 查詢參數（這個參數在頁內 fetch 下的效果沒有量過，寫明）；反向驗證改為「經 safari-browser 取」；非生醫機構的取得順序表前加一句「每一條都經 safari-browser」（API 頁內 fetch、頁面讀 DOM、PDF 交給 `akashic-fetch-fulltext`），順位 1、2、3 三列的取法欄跟著改寫（「真的瀏覽器 session」改為讀出版商頁的 DOM），headless 工具（WebFetch、curl）被 Cloudflare 擋的兩處改為量測紀錄；ScienceDirect 內嵌 JSON 的擷取腳本補上鎖分頁與查訊號的前置；文末 `crossref_match.py` 一段補上它的錯誤處理實況（見〈誠實邊界〉）。
- `akashic-bootstrap/SKILL.md`：兩份指南的引導處加一段「怎麼取」指向 web-access.md（原本只列兩份指南，沒有取得程序）。
- `akashic-disambiguate/SKILL.md`：第 3 步的兩個裸 URL（OpenAlex `works/doi:`、Crossref `works/`）→ 加一段「一律經 safari-browser、DOI 先驗形狀、遇到中止訊號整批停」。
- `akashic-disambiguate/references/ambiguity-traps.md`：用標題搜 OpenAlex 的網址（自由文字直接插進 URL）→ 標明經 safari-browser、標題先百分比編碼。
- `akashic-fetch-fulltext/SKILL.md`：第 2 步「以 DOI 查 OpenAlex」與「開放版本若是 OSF／機構典藏的直接 PDF，一般 HTTP 下載即可」→ OpenAlex 查詢改為頁內 fetch；開放版本一律用 `landing_page_url` 當第 3 步的 `--landing`，不另走一般 HTTP 下載；只有 `pdf_url` 沒有 `landing_page_url` 時停下問使用者（讀碼：腳本讀不到 Safari 的 PDF 檢視器，會以結束碼 6 整批停）；「開始前」補一條指向 web-access.md。
- `akashic-fetch-fulltext/references/publishers.md`：OSF／UvA 一列「一般 HTTP 下載即可，不需 Safari」→ 保留 2026-09-23 的觀察、標明自 #634 起不是取得方式（不在原清單內，但它與 SKILL.md 直接矛盾）。
- `akashic-venue-works/references/site-access.md`：「升級階梯」（curl → agent-browser → Safari 逐級升）→ 改為「取得路徑」加「已量過而不再走的路」；PsycNet 的 osascript 專用縮小視窗（原標「正解」，附 AppleScript）→ 降為量測紀錄、拿掉程式碼、改指現行取法，並寫明兩件沒重量的事（`open --new-tab` 是否仍搶前景、9 秒／筆是否成立）；「批次結束關掉分頁」改為列給使用者；補「被擋就整批停」一條。
- `akashic-venue-works/SKILL.md`：階段 A 的 OpenAlex cursor 分頁補「經 safari-browser」；階段 B 對 site-access.md 的描述（「升級階梯」「縮小視窗方案」）跟著改（不在原清單內，改 site-access.md 之後這兩處成了過期描述）。
- `akashic-verify-person/SKILL.md`：證據鏈引言補「一律經 safari-browser、姓名先編碼、遇到中止訊號整批停」；出版商頁一列的「headless 常 403 → 改真瀏覽器」→ 改為一律在 Safari 分頁讀、headless 被擋是量測紀錄。
- `akashic-verify-person/references/verification-traps.md`：OpenAlex `institutions?search=` 與 `works/doi:` 的網址標明取法；「請求節流」補「被擋就是中止條款」。
- `akashic-import-wos/SKILL.md`：DOI 補查「查 Crossref」一句補取法（不在原清單內）。
- `.claude/rules/web-access-via-safari-browser.md`：〈既有檔〉清單從 11 個減為 3 個並重量；量法加最後一段（`xargs grep -F -L 'web-access.md'`），寫明兩個盲區；〈使用紀律〉補「操作程序的位置」（`plugins/akashic-discovery` 自帶一份，兩份要一起改）；〈觸發過的實例〉加一列。

## 測試與負控

這一輪改的是散文，沒有新增程式行為，所以沒有新測試。驗證的是：

- `bash .githooks/run-guards.sh` rc=0（散文守衛：repo 專屬路徑不得成為可跟隨連結、提到就要在同一行揭露、`plugin/rules` 的掛載完整）。
- 橫切與相關 suite（`LibraryTermDisambiguationTests`、`SanitizationBoundaryTests`、`DisplaySinkCoverageTests`、`PackageManifestTests`、`StoreHealthSurfaceTests`、`WriteGateRulingsTests`、`DestructiveTargetGateTests`、`StdioE2ETests`、`ServiceTests`）合計 299 個測試、0 失敗（native 建置；`LibraryTermDisambiguationTests` 會讀 `akashic-bootstrap/SKILL.md`，是唯一讀到本輪改動檔的一支）。
- 14 個改動與新增的 `.md`（13 個 plugin 檔加規則檔）裡所有相對連結逐一解析，無斷連。
- 重量 grandfathered 清單（規則檔量法）：命中 6 個檔，其中 3 個不算，其餘 3 個是 `crossref_match.py`、`calibrate_title_match.py`、`akashic-verify-venue/SKILL.md`。

量法的負控（在 scratch 副本上做，沒碰工作樹）：乾淨樹回 6；把 `person-sources.md` 的 `web-access.md` 指標全部改掉 → 它重新出現在清單；新增一個帶 `curl` 而沒有指標的檔 → 出現在清單；**已遷移的檔加一行 `curl` 但保留指標 → 量法看不到**（這是預期的盲區，已寫進規則檔〈既有檔〉，並逐條讀過遷移後仍出現的 `curl`／WebFetch 字樣，全部是量測紀錄或「不要用」的敘述）。

## 誠實邊界

- **沒有實跑 safari-browser**（任務限制：只改指令文字）。`--profile`、`--url-exact`、`open --new-tab --profile` 的組合來自規則檔與 #617 落地的範本；另在本機 `safari-browser` binary 的字串表裡確認過 `--profile`、`--url-exact` 存在、`--profile` 只在 `open --new-window` 被忽略（`open --new-tab` 可用）。已安裝的 safari-browser 2.9.0 skill 文件沒有列 `--profile`／`--url-exact`。
- **轉址頁的 fragment 沿用**（web-access.md〈會轉址的頁面〉）只依 HTTP 規格，沒有逐站量過；保留不了 fragment 的站在這個鎖法下讀不了。
- **osascript 縮小視窗那條路被降為紀錄**：它是 #423 的 psycnet 批次（151 筆）實際用的作法，改成 safari-browser 後兩件事沒有量過（前景干擾、節奏）。這是為了守規則付出的量測缺口，不是判斷它們等價。
- **剩下 3 個檔照實保留**：`crossref_match.py`、`calibrate_title_match.py` 是 Python 直連腳本，去處是移植成 `akashic` CLI 子命令（#629），不是改文字；`akashic-verify-venue/SKILL.md` 的鎖分頁方法待使用者裁決（#593）。
- **`crossref_match.py` 的錯誤處理不是中止條款**（讀碼）：查詢階段的請求失敗會讓整支腳本以未捕捉的例外中止，結果檔在迴圈之後才寫；審稿報告後綴那一步吞掉例外；反向驗證把錯誤寫進結果後繼續請求。已寫進 work-sources.md，要執行它得先告訴使用者。
- **`akashic-fetch-fulltext/scripts/fetch-fulltext.sh` 以視窗編號＋分頁位置鎖分頁**（#613 的作法，`publishers.md` 記著理由：同一頁已開時 URL 鎖會對到兩個分頁），與規則檔現行禁用的 `--window N --tab-in-window T` 相同。它取得走 safari-browser、不在清單內，這一輪沒有動它；是否改成 `--profile`＋`--url-exact`＋fragment 是另一個裁決。
- **`plugins/akashic-discovery/skills/akashic-work-references/SKILL.md`（本輪不得動）有一句已過期**：它說 bootstrap 的 DOI 反查「仍走自己的路徑（直接呼叫 Crossref）」——遷移後 bootstrap 的文字取得經 safari-browser，只有 `crossref_match.py` 還直連。要在 #617 那條線上更新。
- 量法有兩個盲區（規則檔〈既有檔〉）：沒有網址或工具字樣的寫法，與「有指標但殘留直連指令」。
