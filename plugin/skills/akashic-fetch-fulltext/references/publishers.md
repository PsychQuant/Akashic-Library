# 各出版商的已知行為與陷阱

每一條都是**某一天觀察到的站點行為**，不是永久事實——出版商會改版。表中日期是最後一次實測；超過幾個月沒再遇到的，用之前先看一眼頁面。

所有觀察都在使用者的機構網路下、以使用者自己的 Safari profile 進行。**權限因機構而異**：這裡寫「取得成功」只代表那個機構那一天有權限。

## #613 之後怎麼讀這張表

2026-10-01 起 `akashic fulltext fetch` **只導航、交給人**（SKILL.md〈最高原則：跟真人一樣〉）。所以：

- **拼網址的規則全部拿掉**（`akashic fulltext url-rule` 與它的三條規則：SAGE `?download=true`、Wiley `pdfdirect`、PsycNet `/fulltext/<id>.pdf`）。`fetch` 只跟頁面自己的連結走；那個連結通到 HTML 閱讀器時，下載按鈕交給使用者按。
- 下表「觀察」欄裡 2026-09-23／09-28 的「成功」，多數是**頁內 fetch** 量到的——那條路已經不用了，經導航取這些站**大多沒有量過**。遇到了，把新的觀察（日期、做了什麼、看到什麼）補進該列。
- 「做法」欄寫的是 `fetch` 會怎麼處理（結束碼）與交給人之後使用者要做什麼，不是可以另外照做的取檔步驟。
- **PDF 放在另一個主機**（儲存或 CDN 主機：ScienceDirect 的 `pdf.sciencedirectassets.com`、OUP 的 `watermark.silverchair.com` 之類）是正常結果，不是「網站懷疑自動化」：新主機顯示 PDF → 結束碼 7 `pdf-shown`（先判 PDF，不看分頁標題——PDF 分頁的標題常是文章標題）；那裡是 HTML 頁 → 等它載完，沒有命中封閉清單 → 結束碼 7 `left-site`；分頁讀不到（Safari 的 PDF 檢視器可能不跑頁面 JS）→ 結束碼 7 `unverifiable`，不看標題與網址的字樣（#613 R3；b34 起文章站上同一套），但讀不到的分頁停在登入主機上 → 結束碼 6；是登入／驗證／封鎖頁 → 結束碼 6（使用者 2026-10-02）。每站上限仍以**文章頁的主機**計。

## 規則表

| 站 | 已知行為 | `fetch` 的處置／交給人之後 | 觀察 |
|---|---|---|---|
| Taylor & Francis（tandfonline.com）| 跳轉中繼頁先回 `readyState=complete`，文章頁還沒載入，此時找不到 PDF 連結 | `fetch` 等 PDF 連結出現（45 秒）；頁面的 `/doi/pdf/<doi>` 連結 | 2026-09-23，6 篇成功（頁內 fetch；導航未量）|
| SAGE（journals.sagepub.com）| `citation_pdf_url` 指向 `/doi/reader/`（HTML 線上閱讀器）| 導航後分頁是 HTML → 結束碼 7 `html-page`：請使用者在閱讀器按下載 | 2026-09-23，3 篇成功（當時以拼出來的 `?download=true` 頁內 fetch；#613 起不拼）|
| SAGE | 頁面 60 秒內 `readyState` 未到 `complete` | `interactive` 即可繼續 | 2026-09-23，1 篇 |
| Wiley（onlinelibrary.wiley.com）| 頁面的 `/doi/pdf/<doi>` 通到 HTML 檢視器 | 導航後分頁是 HTML → 結束碼 7 `html-page`：請使用者在檢視器按下載 | 2026-09-23，2 篇成功（當時以拼出來的 `pdfdirect` 頁內 fetch；#613 起不拼）|
| APA PsycNet（psycnet.apa.org）| 有權限時 DOI 跳到 `/fulltext/<id>.html`；有時停在 `doiLanding?doi=…`、只有 `/record/<id>` 連結 | 頁面沒有自己的 PDF 連結時 → 結束碼 3。**不拼** `/fulltext/<id>.pdf`；請使用者在頁面上找 PDF 按鈕 | 2026-09-23，3 篇成功（拼網址＋頁內 fetch）|
| APA PsycNet 無權限 | 書目頁只有 Login／Get Access；`/fulltext/<id>.pdf` 回 HTTP 200、約 8,028 bytes、內容「Loading…」 | 「沒有權限」，不是起疑：列入「需要人」，或改走下方〈EBSCO APA PsycInfo〉 | 2026-09-23，6 篇；2026-09-28，1 篇（Luce & Edwards, 1958）|
| Annual Reviews（annualreviews.org）| 「download PDF」是 `href="#"` 的按鈕，外層是 POST 表單 `form.ft-download-content__form--pdf`；第一個 `.pdf` 連結是**補充資料** | 結束碼 7 `button`：請使用者按下載按鈕（不代按、不代送表單）；`take` 的驗證會擋下補充資料 | 2026-09-23，1 篇（當時以表單頁內送出）|
| Oxford Academic（academic.oup.com）| 頁內 fetch PDF 回 403「Just a moment…」（Cloudflare）| Cloudflare「Just a moment」→ 結束碼 8 **等人驗證**（使用者 2026-09-28 裁決；挑戰頁以 403 回應也一樣）；頁面同時有封鎖句時整批暫停（結束碼 6）。2026-09-23 當時是改找 PMC 作者稿繼續——那是在被懷疑之後換路，2026-09-24 起不再這樣做 | 2026-09-23，1 篇 |
| PubMed Central（pmc.ncbi.nlm.nih.gov）| 頁內 fetch PDF 回約 1.8 KB 的防爬蟲驗證頁（「preparing to download」、proof of work） | 那個驗證頁是**整批暫停**（使用者 2026-10-01：下載前驗證頁不當成等人驗證）。#613 拿掉了 `--prime`：它只是為了讓之後的頁內 fetch 過得去，導航本來就像讀者點連結 | 2026-09-23，1 篇成功（`--prime`＋頁內 fetch）|
| Springer（link.springer.com）| 頁面自己的 PDF 連結是 `/content/pdf/<doi>.pdf`；curl 取同一個網址回 HTML | `fetch` 照頁面的連結導航；導航後顯示 PDF → 結束碼 7 `pdf-shown` | 2026-09-28，1 篇成功（頁內 fetch；導航未量；bronze OA）|
| ScienceDirect（sciencedirect.com）| 「View PDF」連結有兩種形狀（`/science/article/pii/<PII>/pdf?md5=…&pid=…` 與 `/pdfft?md5=…&pid=…`），頁面上還有推薦文章的 `pdfft` 連結；由 DOI 猜 PII 不可靠。點 View PDF 先到「**Preparing your download**」中介頁（`cra_js_challenge`），再跳到 `pdf.sciencedirectassets.com` 的 S3 簽章網址（`X-Amz-Expires=300`）；對已顯示的 PDF 再發一次請求會觸發 CAPTCHA | 中介頁 → 結束碼 6 **整批暫停**（使用者 2026-10-01）；文章站上的 CAPTCHA 頁（「Are you a robot?」）→ 結束碼 8（導航之後的驗證另印 `--resume-stage followed`；驗證完分頁到 `pdf.sciencedirectassets.com` 也接得住）。導航之後分頁跑到 `pdf.sciencedirectassets.com`（別的主機）：顯示 PDF → 結束碼 7 `pdf-shown`（使用者 2026-10-02；先前是 6）；**那個主機上出現 CAPTCHA 字樣**（2026-09-28 的第二次 CAPTCHA 就是那樣）→ 結束碼 6，因為它既不是文章站、也不在已知驗證服務清單裡（使用者 2026-10-02）。**這一站目前沒有自動走得完的路**；PDF 的網路快取也不留（safari-browser#210 比對 4/4 不在快取裡）| 2026-09-28，3 篇成功（導航到簽章網址後頁內 fetch）；同晚 2 次 CAPTCHA，見 #613 |
| Optica（opg.optica.org）| 導航之前先以 curl 打了 DOI 頁與 `viewmedia.cfm`（第二次回「Please wait...」），隨後 Safari 導航即被導到 `/captcha/` | CAPTCHA → 結束碼 8。**不要在 Safari 之外先碰這個站**（最高原則規則 1） | 2026-09-28，1 篇 |
| OSF／PsyArXiv、機構典藏（UvA）| — | 2026-09-23 以一般 HTTP 下載成功；**這條路自 #634 起不是本 skill 的取得方式**（一律經 Safari），經 `fetch` 取這幾站沒有量過——遇到照結束碼處理，新量到的寫在這一列 | 2026-09-23，4 篇成功（一般 HTTP 下載）|

## EBSCO APA PsycInfo（PsycNet 沒有權限時的替代管道）

2026-09-28 的觀察（使用者：「那邊必須要用 safari-browser 取，這是重點」）：PsycNet 對某篇只給 Login／Get Access 時，使用者的機構 EBSCO 入口可能有 APA PsycInfo 的全文。整條路都在**使用者自己的 Safari**、以使用者自己的登入進行；取件網址是加密、短效、綁瀏覽器 session 的，**不能**拿到任何 HTTP 客戶端去取。

**前提（使用者動作）**：使用者自己在 Safari 開好機構的 EBSCO 入口並登入。臺大的入口是 `https://research.ebsco.com/c/rw5enf/search`（`rw5enf` 是臺大的 EBSCO 客戶路徑，資料庫 `db=psyh`＝APA PsycInfo）。**不代替使用者登入。**

**導航的部分**（每一步都是讀者會做的；照 web-access.md 鎖分頁，一次一篇、請求之間跑節奏工具）：

1. **搜尋**：同一個分頁導到 `…/c/rw5enf/search/results?q=%22<完整標題>%22`（標題加引號的精確檢索；標題先照 web-access.md〈插值前先驗形狀〉處理，放進網址前百分比編碼）。2026-09-28 的例子 2 筆結果、第 1 筆即本篇。
2. **詳細頁**：點結果標題 → `…/search/details/<recordId>?db=psyh…`。有全文權限時，頁面有「前往全功能閱讀檢視」連到 `…/viewer/pdf/<recordId>`。結果列表的「存取選項」按鈕在該例展不開，不要依賴它。
3. **閱讀器**：導到 `…/viewer/pdf/<recordId>`。PDF 由閱讀器自己的 JS 載入並繪製，頁面上沒有直接的檔案連結。

**然後交給人**：**請使用者用閱讀器自己的下載鈕存檔**，再把檔案交給 `akashic fulltext take`（與 SKILL.md 第 4 步同一條）。

**2026-09-28 的步驟 4–5 不再照做**：當時在閱讀器分頁內頁內 fetch 同源的 `api/researcher-edge-aggregator/v1/records/<id>/fulltext/pdf?…` 取得 JSON 裡的取件網址，再把分頁導到 `content.ebscohost.com/cds/retrieve?content=…`、在那個分頁頁內 fetch `location.href`。前者是頁內以 JS 發請求（最高原則規則 1）；後者**就算改成單純導航**，也是對閱讀器已經載入過的同一份檔再發一次請求（規則 2——ScienceDirect 的第二次 CAPTCHA 就是這個形狀）。所以這一段**沒有只用導航的寫法**：閱讀器之後一律交給人。

當時的其他觀察（保留作紀錄）：取回的是 16 頁、對應期刊頁碼 222–237，首頁有期刊名、卷期、標題、作者，另印「This document is copyrighted by the American Psychological Association」；全程沒有 CAPTCHA、驗證頁或起疑字樣；在 research.ebsco.com 頁內直接 fetch `content.ebscohost.com` 是 CORS 失敗。網址跨三個網域（research.ebsco.com → content.ebscohost.com），`--url` 子字串鎖會失配。權限依機構而異：「成功」只代表臺大 EBSCO 訂閱在 2026-09-28 涵蓋這篇。

**這個管道沒有接進 `akashic fulltext fetch`**：`fetch` 從 `https://doi.org/<DOI>` 出發，走不到 EBSCO 的搜尋。上面三步是照 web-access.md 手動導航；到閱讀器就交給人。

## `fetch` 已內建、不必每次想起的陷阱

- **同一網址兩個分頁**：使用者已開著同一頁時，以網址鎖定會比對到兩個分頁，safari-browser 依設計 fail-closed。`fetch` 全程以「視窗＋分頁位置」鎖定，每一步前核對該分頁仍顯示同一站。
- **推薦文章的 PDF 連結**：頁面上可能有別篇的 PDF 連結（ScienceDirect 的推薦文章）。`fetch` 取的是頁面上第一個符合的連結；拿到別篇時 `take` 的驗證（首頁標題、DOI）會擋下，結束碼 5。
- **zsh 保留變數**：`UID` 在 zsh 是唯讀的使用者 ID，賦值會變成「切換使用者」而被拒。這是舊 shell 腳本踩過的；#629 起 `fetch` 是 Swift，不再有這個問題（條目保留當作紀錄：新寫的 shell 片段仍要避開這個名字）。
- **`%PDF` 不等於這篇**：補充資料、作者稿都通過檔頭檢查；`akashic fulltext take`（與 `verify`）比對頁數與首頁標題（門檻與校準資料寫在 akashic repo 內 `FulltextVerify.swift` 的型別註解，plugin 安裝處讀不到）。
- **`pdfinfo` 的 Title 不可靠**：ScienceDirect 版本的 Title 是 `doi:…` 字串，不是論文標題；標題驗證看首頁文字（`take` 就是這樣做的）。
