# 各出版商的已知行為與陷阱

每一條都是**某一天觀察到的站點行為**，不是永久事實——出版商會改版。表中日期是最後一次實測；超過幾個月沒再遇到的，用之前先看一眼頁面。

2026-11-10 之前各批的觀察都在使用者的機構網路下、以使用者自己的 Safari profile 進行；2026-11-10 與 2026-11-19 兩批在哪個 profile、哪個網路下，issue 沒有回報（見〈2026-11-10、2026-11-19 的實測〉；#781 第 4 輪 verify 第 26 列：這一句先前涵蓋了那兩批）。**權限因機構而異**：這裡寫「取得成功」只代表那個機構那一天有權限。

## #613 之後怎麼讀這張表

2026-10-01 起 `akashic fulltext fetch` **只導航，然後交接**（結束碼 7；SKILL.md〈最高原則：跟真人一樣〉）。2026-11-19 起（#781、#780）交接之後預設由 Claude 接手：分頁顯示 PDF 就 `safari-browser save-pdf`，頁面要先按才到得了 PDF 就按這篇自己的連結（每一下先 `akashic fulltext attempt` 記帳），交給使用者的只有 SKILL.md〈人機分工〉的封閉清單。所以：

- **拼網址的規則全部拿掉**（`akashic fulltext url-rule` 與它的三條規則：SAGE `?download=true`、Wiley `pdfdirect`、PsycNet `/fulltext/<id>.pdf`）。`fetch` 只跟頁面自己的連結走；那個連結通到 HTML 閱讀器時，閱讀器上這篇自己的下載鈕由 Claude 照 SKILL.md〈一層層按〉按。
- 下表「觀察」欄裡 2026-09-23／09-28 的「成功」，多數是**頁內 fetch** 量到的——那條路已經不用了，經導航取這些站**大多沒有量過**。遇到了，把新的觀察（日期、做了什麼、看到什麼）補進該列。
- 「做法」欄寫的是 `fetch` 會怎麼處理（結束碼）與交接之後怎麼走，不是可以另外照做的取檔步驟。**2026-11-19 之前寫下的各列裡「請使用者按下載」「請使用者存」是當時的分工**；現在照 SKILL.md〈結束碼 7 之後〉與〈一層層按〉由 Claude 做，表裡的站點行為（哪個連結通到哪裡）仍然有效。
- **PDF 放在另一個主機**（儲存或 CDN 主機：ScienceDirect 的 `pdf.sciencedirectassets.com`、OUP 的 `watermark.silverchair.com` 之類）是正常結果，不是「網站懷疑自動化」：新主機顯示 PDF → 結束碼 7 `pdf-shown`（先判 PDF，不看分頁標題——PDF 分頁的標題常是文章標題）；那裡是 HTML 頁 → 等它載完，沒有命中封閉清單 → 結束碼 7 `left-site`；分頁讀不到（Safari 的 PDF 檢視器可能不跑頁面 JS）→ 結束碼 7 `unverifiable`，不看標題與網址的字樣（#613 R3；b34 起文章站上同一套），但讀不到的分頁停在登入主機上 → 結束碼 6；是登入／驗證／封鎖頁 → 結束碼 6（使用者 2026-10-02）。每站上限仍以**文章頁的主機**計。

## 規則表

| 站 | 已知行為 | `fetch` 的處置／交給人之後 | 觀察 |
|---|---|---|---|
| Taylor & Francis（tandfonline.com）| 跳轉中繼頁先回 `readyState=complete`，文章頁還沒載入，此時找不到 PDF 連結 | `fetch` 等 PDF 連結出現（45 秒）；頁面的 `/doi/pdf/<doi>` 連結 | 2026-09-23，6 篇成功（頁內 fetch；導航未量）。2026-11-20 補：導航之後量到一篇 `pdf-shown`，見〈2026-11-20 的實測〉（「導航未量」是 2026-09-23 的狀態，留著不刪）|
| SAGE（journals.sagepub.com）| `citation_pdf_url` 指向 `/doi/reader/`（HTML 線上閱讀器）| 導航後分頁是 HTML → 結束碼 7 `html-page`：閱讀器上這篇自己的下載鈕由 Claude 按（見下方〈2026-11-10、2026-11-19 的實測〉SAGE 兩列） | 2026-09-23，3 篇成功（當時以拼出來的 `?download=true` 頁內 fetch；#613 起不拼）|
| SAGE | 頁面 60 秒內 `readyState` 未到 `complete` | `interactive` 即可繼續 | 2026-09-23，1 篇 |
| Wiley（onlinelibrary.wiley.com）| 頁面的 `/doi/pdf/<doi>` 通到 HTML 檢視器 | 導航後分頁是 HTML → 結束碼 7 `html-page`：`snapshot -i` 讀得到這篇自己的下載鈕就由 Claude 按；epdf 閱讀器讀不到任何下載鈕（見下方實測 Wiley 一列）→「取不到」（2026-11-20 補：這一格的「epdf 閱讀器讀不到」也只是 2026-11-10 那一篇；到了 epdf 閱讀器照樣先讀，讀不到這篇自己的下載鈕才是「取不到」，見觀察欄） | 2026-09-23，2 篇成功（當時以拼出來的 `pdfdirect` 頁內 fetch；#613 起不拼）。**「epdf 閱讀器讀不到任何下載鈕」是 2026-11-10 那一篇量到的；2026-11-20 在學會子網域上的另一篇讀得到、也按成了**，見〈2026-11-20 的實測〉。所以到了 epdf 閱讀器先照 SKILL 讀那一頁，讀不到才是「取不到」|
| APA PsycNet（psycnet.apa.org）| 有權限時 DOI 跳到 `/fulltext/<id>.html`；有時停在 `doiLanding?doi=…`、只有 `/record/<id>` 連結 | 頁面沒有 `fetch` 認得的 PDF 連結時 → 結束碼 3。**不拼** `/fulltext/<id>.pdf`；Claude 照〈一層層按〉在頁面上找這篇自己的 PDF 連結 | 2026-09-23，3 篇成功（拼網址＋頁內 fetch）|
| APA PsycNet 無權限 | 書目頁只有 Login／Get Access；`/fulltext/<id>.pdf` 回 HTTP 200、約 8,028 bytes、內容「Loading…」 | 「沒有權限」，不是起疑：「取不到（無權限）」，或改走下方〈EBSCO APA PsycInfo〉 | 2026-09-23，6 篇；2026-09-28，1 篇（Luce & Edwards, 1958）；2026-10-07，1 篇（Marsh et al., 2013；手動開書目頁只有 Get Access。同一篇用 #613 之前的舊 shell 腳本跑，在 `doiLanding` 停於結束碼 6 `cloudflare-challenge`，但訊號網址是 sciencedirect.com 的 `__cf_chl_rt_tk`、不是 psycnet——舊腳本讀到哪一頁未查證）|
| Annual Reviews（annualreviews.org）| 「download PDF」是 `href="#"` 的按鈕，外層是 POST 表單 `form.ft-download-content__form--pdf`；第一個 `.pdf` 連結是**補充資料** | 結束碼 7 `button`：Claude 按那個下載按鈕（只按，不代填、不另外送表單；按之前先確認不是補充資料的連結）；`take` 的驗證會擋下補充資料。**2026-11-19 起的分工，按這個按鈕之後的行為沒有實測過** | 2026-09-23，1 篇（當時以表單頁內送出）|
| Oxford Academic（academic.oup.com）| 頁內 fetch PDF 回 403「Just a moment…」（Cloudflare）| Cloudflare「Just a moment」→ 結束碼 8 **等人驗證**（使用者 2026-09-28 裁決；挑戰頁以 403 回應也一樣）；頁面同時有封鎖句時整批暫停（結束碼 6）。2026-09-23 當時是改找 PMC 作者稿繼續——那是在被懷疑之後換路，2026-09-24 起不再這樣做 | 2026-09-23，1 篇 |
| PubMed Central（pmc.ncbi.nlm.nih.gov）| 頁內 fetch PDF 回約 1.8 KB 的防爬蟲驗證頁（「preparing to download」、proof of work） | 那個驗證頁是**整批暫停**（使用者 2026-10-01：下載前驗證頁不當成等人驗證）。#613 拿掉了 `--prime`：它只是為了讓之後的頁內 fetch 過得去，導航本來就像讀者點連結 | 2026-09-23，1 篇成功（`--prime`＋頁內 fetch）|
| Springer（link.springer.com）| 頁面自己的 PDF 連結是 `/content/pdf/<doi>.pdf`；curl 取同一個網址回 HTML | `fetch` 照頁面的連結導航；導航後顯示 PDF → 結束碼 7 `pdf-shown` | 2026-09-28，1 篇成功（頁內 fetch；導航未量；bronze OA）。之後補：導航之後的 `pdf-shown` 見下方各批——〈2026-11-02 一批〉一篇（Eur Spine J）、〈2026-11-20 的實測〉一篇書章、〈2026-11-21 的實測〉三篇期刊文章（入口是使用者確認的 `/article/<DOI>`）。「導航未量」是 2026-09-28 的狀態，留著不刪 |
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

**然後**：閱讀器自己的下載鈕是這一篇自己的元件，但這個閱讀器不經 `fetch` 到達，不在 SKILL.md〈一層層按〉封閉的五種入口裡（那五種都是 `fetch` 的結果；沒有 `fetch` 印的位置與主機，就沒有分頁可鎖、沒有 `--site` 可記帳）。所以這一篇列入最後交給使用者的清單、註明不在 (a)–(d) 裡，由使用者自己按閱讀器的下載鈕存檔；要把 EBSCO 閱讀器加成〈一層層按〉的一種入口，需要使用者裁決（#781 verify 第 1 輪第 14 列）。存下的檔交給 `akashic fulltext take`（與 SKILL.md 第 4 步同一條）。

**2026-09-28 的步驟 4–5 不再照做**：當時在閱讀器分頁內頁內 fetch 同源的 `api/researcher-edge-aggregator/v1/records/<id>/fulltext/pdf?…` 取得 JSON 裡的取件網址，再把分頁導到 `content.ebscohost.com/cds/retrieve?content=…`、在那個分頁頁內 fetch `location.href`。前者是頁內以 JS 發請求（最高原則規則 1）；後者**就算改成單純導航**，也是對閱讀器已經載入過的同一份檔再發一次請求（規則 2——ScienceDirect 的第二次 CAPTCHA 就是這個形狀）。所以這一段**沒有只用導航的寫法**：那個取件網址不由 Claude 去取；閱讀器之後只走閱讀器自己的下載鈕。

當時的其他觀察（保留作紀錄）：取回的是 16 頁、對應期刊頁碼 222–237，首頁有期刊名、卷期、標題、作者，另印「This document is copyrighted by the American Psychological Association」；全程沒有 CAPTCHA、驗證頁或起疑字樣；在 research.ebsco.com 頁內直接 fetch `content.ebscohost.com` 是 CORS 失敗。網址跨三個網域（research.ebsco.com → content.ebscohost.com），`--url` 子字串鎖會失配。權限依機構而異：「成功」只代表臺大 EBSCO 訂閱在 2026-09-28 涵蓋這篇。

### 2026-10-07 的觀察（含一次違規）

這一次是**用過期的 skill 版本**做的：本機 plugin 快取的內容停在 #613 修正輪之前，但它的版本號與 marketplace 上的同為 0.13.2——#613 的 skill 修改之後殼版本沒有再升，`claude plugin update` 回報「已是最新」，快取不會換（akashic-mcp 0.13.3 那一次修正；之後每一次 skill 的改動都要再升版才送得到使用者那裡，0.13.3 之後的 skill 改動跟著 0.13.4 起的版號出貨——`akashic-guards plugin-shell-version` 守著這件事）；本機 repo 也落後 origin 229 個 commit。agent 照舊版「頁內取檔」的寫法走，違反了當時上面三步之後「交給人」的規定（現在是「只走閱讀器自己的下載鈕」）。記下來是為了兩件事：留下量到的站點行為，以及讓這個失敗形狀被看見——**舊版 skill 沒有第 0 步的契約版本檢查，所以察覺不到自己過期**。

- **入口**：在機構網路下開 `…/c/rw5enf/search`，頁首直接顯示機構名，沒有出現登入頁（這一天、這個網路下的觀察；其他網路照上面的前提由使用者登入）。
- **搜尋**：`…/search/results?q=DO%20<DOI>`（`DO` 是 EBSCO 的 DOI 欄位）回 1 筆，即本篇；結果頁網址自己補上 `db=psyh`。在搜尋框 `fill`／`type` 之後按 Enter 或點檢索鈕都沒有送出（頁面掛著 Cookie 同意橫幅，未代按）。
- **詳細頁**：直接把分頁導到 `…/search/details/<id>` 回「頁面無法使用，發生錯誤」——詳細頁要從結果列表點進去（與上面第 2 步一致）。
- **「存取選項」**：這一次是**對按鈕派送合成的 pointer 事件**才展開（`click` 沒反應），選單有三項：`PDF`（`…/viewer/pdf/<recordId>`）、`線上全文`（HTML）、機構的 link resolver。**派送合成事件就是「往出版商頁面另外送 JS」（最高原則規則 5），不要照做**；展不開就照上面第 2 步走詳細頁。
- **違規的取檔**：在閱讀器分頁頁內 fetch `api/researcher-edge-aggregator/…/fulltext/pdf?…&intent=view…`（帶 credentials）取得 JSON 的取件網址，再在**同一個 research.ebsco.com 分頁**頁內 fetch `content.ebscohost.com/cds/retrieve?content=…`：**帶** `credentials:"include"` 那次沒有任何結果（沒接 `catch`，錯誤未記錄）；**不帶**的那次回 `200 application/pdf`、500,609 bytes。這與上面 2026-09-28「在 research.ebsco.com 頁內直接 fetch `content.ebscohost.com` 是 CORS 失敗」不同——兩次差在有沒有帶 credentials，但 09-28 那次帶了什麼沒有記錄，所以不能說哪一個是通則。**兩種都是被禁止的做法，記下來只為了不讓下一個人再去試。**
- 取回的檔：21 頁、對應期刊頁碼 108–128，`verify` 結果標題完全相符、首頁印的 DOI 相符、正式版。全程沒有 CAPTCHA、驗證頁或起疑字樣——**沒被擋不代表做法可以**（2026-09-28 ScienceDirect 的兩次 CAPTCHA 也是在同樣形狀的請求之後才出現）。

**這個管道沒有接進 `akashic fulltext fetch`**：`fetch` 從 `https://doi.org/<DOI>` 出發，走不到 EBSCO 的搜尋。上面三步是照 web-access.md 手動導航；到閱讀器之後照上面〈然後〉那一段。

## `fetch` 已內建、不必每次想起的陷阱

- **同一網址兩個分頁**：使用者已開著同一頁時，以網址鎖定會比對到兩個分頁，safari-browser 依設計 fail-closed。`fetch` 以它自己這次執行的記號鎖定（`--profile`＋`--url-endswith`，記號每次不同，不會對到使用者開著的同一頁）；記號不在時以視窗編號與分頁位置鎖，每一步前核對；有別的 profile 的視窗開著時一開始就停，執行當中才開的下一眼就停（一眼與命令之間才開、又搶到同一個編號的視窗，那一次擋不住，#768）。
- **推薦文章的 PDF 連結**：頁面上可能有別篇的 PDF 連結（ScienceDirect 的推薦文章）。`fetch` 取的是頁面上第一個符合的連結；拿到別篇時 `take` 的驗證（首頁標題、DOI）會擋下，結束碼 5。
- **zsh 保留變數**：`UID` 在 zsh 是唯讀的使用者 ID，賦值會變成「切換使用者」而被拒。這是舊 shell 腳本踩過的；#629 起 `fetch` 是 Swift，不再有這個問題（條目保留當作紀錄：新寫的 shell 片段仍要避開這個名字）。
- **`%PDF` 不等於這篇**：補充資料、作者稿都通過檔頭檢查；`akashic fulltext take`（與 `verify`）比對頁數與首頁標題（門檻與校準資料寫在 akashic repo 內 `FulltextVerify.swift` 的型別註解，plugin 安裝處讀不到）。
- **`pdfinfo` 的 Title 不可靠**：ScienceDirect 版本的 Title 是 `doi:…` 字串，不是論文標題；標題驗證看首頁文字（`take` 就是這樣做的）。

## 2026-11-02 一批（21 篇，pdf-cache 改接之後）

導航仍走 `fetch`；`pdf-shown` 之後用 `pdf-cache get --url` 取快取（#766）。**這是當時的工具**：`pdf-cache` 現在不認 WebKitCache Version 18，SKILL 改用 `save-pdf`（#780），不要照這一段做（#781 第 2 輪 verify 第 23 列）。都在使用者的機構網路、default profile 下。

| 站 | 結果 | 處置 | 觀察 |
|---|---|---|---|
| Oxford Academic（JAC，`watermark02.silverchair.com`）| `pdf-shown`，快取取得；首頁有印 DOI、無 XMP DOI，增刊頁碼 `iii11-iii24` 比不了 → `take` 結束碼 5 | Claude 讀首頁確認 | 1 篇成功 |
| Oxford Academic（CID）| 文章頁找不到 PDF 連結（結束碼 3）；同一批另一次交接時分頁位置對到使用者自己的分頁 | 列入「需要人」 | 1 篇未取得 |
| Deutsches Ärzteblatt | 轉到 `di.aerzteblatt.de` → `left-site` | 使用者存檔 | 1 篇成功 |
| SAGE | `pdf-shown`，網址在 `/history/<uuid>/<doi>.<n>.pdf`，快取取得，`take` 結束碼 0（正式版）| 自動 | 2 篇成功 |
| SAGE | 頁面的 `citation_pdf_url` 指向別的站（引用的德國指引 `awmf.org`）→ 結束碼 1 `points off-site`；文章頁的 `PDF/EPUB` 連結到 `/doi/epub/<doi>` 閱讀頁，閱讀頁的 `Download PDF`（`#favourite-download`）直接下載 | 使用者授權後代按，下載資料夾取檔 | 1 篇成功 |
| SAGE | 文章頁找不到 PDF 連結（結束碼 3）| 列入「需要人」 | 1 篇未取得 |
| Nature（Sci Rep）| `pdf-shown`（`/articles/<id>.pdf`），快取取得，結束碼 0 | 自動 | 1 篇成功 |
| MDPI | 導航到 `/pdf` 之後分頁不變（`tab-unchanged`），Safari 直接下載 `<journal>-<vol>-<id>-v<n>.pdf` 到下載資料夾；article number 比不了頁碼 → 結束碼 5 | 下載資料夾取檔；Claude 讀首頁確認 | 2 篇成功 |
| Wolters Kluwer（Neurosurgery）| DOI 轉到 `www.ovid.com/jnls/neurosurgery/fulltext/...`，找不到 PDF 連結（結束碼 3）| 列入「需要人」 | 1 篇未取得 |
| Wiley | `/doi/pdf/<doi>` 是 HTML 閱讀器（`html-page`）；`snapshot -i` 讀不到任何下載鈕（閱讀器多半在框架裡）| 列入「需要人」 | 1 篇未取得（2026-11-20 另一篇讀得到，見〈2026-11-20 的實測〉）|
| AME（jss.amegroups.org）| `/article/view/<id>/pdf` 是 HTML（`html-page`）；`#pdfDownloadLink`「Download」按下去跳出 Safari 的「要允許在『jss.amegroups.org』上下載嗎？」；`dialog dismiss` 回「無法在預算內檢查所有視窗」| 權限對話框交給使用者親手按 | 1 篇待使用者 |
| J-STAGE | `pdf-shown`（`/_pdf`），快取取得；首頁沒有 DOI 與卷期，第 2 頁起的頁首有 → 結束碼 5 | Claude 確認（頁首）| 1 篇成功 |
| AJNR | `pdf-shown`（`.full.pdf`），快取取得，結束碼 0 | 自動 | 1 篇成功 |
| Springer（Eur Spine J）| `pdf-shown`（`/content/pdf/<doi>.pdf`），快取取得，結束碼 0 | 自動 | 1 篇成功 |
| ScienceDirect | 第一篇落地就是 CAPTCHA（結束碼 8）；使用者驗證後在同一分頁接續，但視窗編號已變，`--resume-tab` 找不到分頁（結束碼 1，已記一次嘗試）。另一篇導航到 `pdf.sciencedirectassets.com` 的 `main.pdf?X-Amz-...` → `pdf-shown`，但 `pdf-cache get` 回 `No cached PDF matches`（不進快取）。在那個分頁以 `fetch(location.href,{cache:'only-if-cached',mode:'same-origin'})` 只讀探測（使用者同意後一次）回 `status=200 bytes=1220093 head=%PDF-`——WebKit 持有位元組，見 safari-browser#338 | 使用者存檔（1 篇）；其餘等 #338 | 1 篇成功、3 篇待 #338 |

## 2026-11-10、2026-11-19 的實測（#780、#781：一層層按與 `save-pdf`）

兩批在哪個 Safari profile、哪個網路下，issue 都沒有回報（#781 第 2 輪 verify 第 17 列：先前這裡寫兩批都在使用者自己的 profile 下）。2026-11-19 那一批 SAGE 的兩下是 Claude 按的，**沒有記進每站每天的帳本**（#780 的 2026-11-19 留言：當天的帳本沒有 `journals.sagepub.com` 的紀錄；當時還沒有 `akashic fulltext attempt`）。2026-11-10 那一批是誰按的，#780 正文沒有寫；當時同樣還沒有 `attempt`，所以那幾下也不可能記進帳本——這是推論，issue 沒有回報（#781 verify 第 1 輪第 18 列：先前這一段寫了兩批都在機構網路、2026-11-10 由 Claude 按，issue 都沒有回報）。環境：safari-browser v2.9.0；2026-11-19 是 macOS 27.3、`akashic fulltext contract` 印 10。**2026-11-20 另有一次在真的 Safari 上的量測**（按了之後分頁開在哪裡、對話框與儲存面板讀起來是什麼），用的是本機的測試頁、沒有連任何出版商網站，所以下表沒有新的一列；結果在 [safari-measurements.md](safari-measurements.md)，SKILL.md 第 3 步的規則以它為依據。

| 站 | `fetch` 的結果 | 之後做了什麼、看到什麼 | 觀察 |
|---|---|---|---|
| Ovid／LWW（`ovid.com/jnls/<刊>/fulltext/…`）| 結束碼 3 | 頁面有「View full text」與「Download PDF」；「Download PDF」是這篇自己的連結，後面才接推薦文章。按下去，同一個分頁導到 `/pdf/…`，`save-pdf` 取得 | 2026-11-10，2 篇成功 |
| Ovid／LWW，沒有權限 | 沒有回報 | 分頁在 `/abstract/`（#780 沒有寫那是 `fetch` 落的還是按了之後到的；#781 第 4 輪 verify 第 26 列），頁面只有「Check Access」「Log in for access」：沒有權限 | 2026-11-10，1 篇未取得 |
| SAGE（journals.sagepub.com）| 結束碼 1 `points off-site`：`citation_pdf_url` 指到 Google Scholar | 文章頁的「PDF/EPUB」連到 `/doi/epub/…` 閱讀頁，閱讀頁上再按 `#favourite-download`（#780 正文的寫法；href 與 aria-label 是 2026-11-19 那一次讀到的，見下一列）。沒有產生下載檔，最後由使用者自己存 | 2026-11-10，1 篇 |
| SAGE，同一條路 | 結束碼 1 `points off-site` | 同上兩下：文章頁的「PDF/EPUB」連結（href `/doi/reader/<DOI>`），閱讀頁上的 `a#favourite-download`（aria-label「Download PDF」，href 的路徑是 `/doi/pdf/<DOI>`）。第二下之後 `click` 結束碼 0、分頁網址不變、之後 18 秒下載資料夾沒有新檔：**Safari 掛著的是「儲存為」面板**（PsychQuant/safari-browser#358），不是下載權限提示；使用者按「儲存」之後檔案才寫入，`take` 結束碼 0（標題、PDF metadata 的 DOI、頁數都相符）。所以這一站目前每一篇最後都要使用者按一次「儲存」（SKILL.md〈人機分工〉的 (c)）。（2026-11-20 補：同一站的另一篇，同樣兩下之後沒有出現面板、檔案直接寫入，見〈2026-11-20 的實測〉。所以「每一篇都要按一次」是從 2026-11-19 這一篇推出來的，2026-11-20 的那一篇不是這樣。使用者說 2026-11-20 那天下載位置設成固定資料夾，2026-11-19 的設定沒有記錄：面板出不出現是不是由這個設定決定，兩天各一篇、沒有同一天改設定前後的對照，沒有量過。這段補註原本寫「只在會跳儲存面板的設定下成立」，說成了一條設定規則，#822 verify 第 1 輪第 6 列收窄。）當時沒有讀 `documents --json` 的 `blocking_dialog`；2026-11-20 在本機測試頁上量到儲存面板開著時它是 `unknown`（[safari-measurements.md](safari-measurements.md) 的 M6），照現在的 SKILL，按了之後讀到 `unknown` 就當場停下請使用者看（落點表第 5 種）——這一站會不會每一篇都這樣停一次，是從 M6 推出來的，沒有在這一站量過。2026-11-10 那一次沒有下載檔可能是同一個面板在等——這是推測，沒有查證 | 2026-11-19，1 篇成功 |
| AME（jss.amegroups）| `.com` 轉到 `.org`，結束碼 7 `left-site` | 文章頁 Article Options 的「PDF」連結（`a.pdf` → `/article/view/<id>/pdf`）開成新分頁（開在視窗的哪個位置當時沒有記）；新分頁裡的 `#pdfDownloadLink`「Download」按下去跳出 Safari 的下載權限提示，那一步由使用者按（這個提示在 `documents --json` 裡是什麼樣子沒有量過：2026-11-20 的量測裡它沒有出現） | 2026-11-10，1 篇 |
| Wiley epdf 閱讀器 | — | `snapshot -i` 讀不到任何下載鈕，由使用者自己存 | 2026-11-10（2026-11-20 另一篇讀得到，見〈2026-11-20 的實測〉）|
| Project Euclid | 結束碼 7 `pdf-shown`（PDF 在文章站本身）| `save-pdf` 以 `--url` 鎖 `fetch` 交接出來的分頁，取得（當時的鎖法；現在照 SKILL 第 3 步〈`fetch` 之後的鎖分頁〉，不用 `--url`） | 2026-11-19，2 篇成功 |
| Oxford Academic | 結束碼 7 `pdf-shown`（PDF 在 `watermark02.silverchair.com`）| `save-pdf` 取得，27 頁 | 2026-11-19，1 篇成功 |
| ScienceDirect | 結束碼 7 `pdf-shown`（PDF 在 `pdf.sciencedirectassets.com`）| `save-pdf` 取得，29 頁；中途兩次人工驗證（#819，處置待使用者裁決） | 2026-11-19，1 篇成功 |

`pdf-cache`：2026-11-10 與 2026-11-19 各試一次，都以同一個錯誤停下——Safari 的網路快取是 WebKitCache Version 18，`safari-browser pdf-cache`（v2.9.0）只認 Version 17（PsychQuant/safari-browser#375）。上表的 `pdf-shown` 都是 `save-pdf` 取得的。2026-11-19 的四篇 `pdf-shown` 是 1970 到 1997 年的文章，首頁都沒有印 DOI，`take` 都回結束碼 5，由 Claude 讀首頁確認後存入（SKILL.md 第 6 步）；當時 acquisition 記成 `browser-cache`，SAGE 那一篇記成 `browser-download`——`browser-save-pdf` 這個值是之後才定的。

## 2026-11-20 的實測（#822：合併後的流程第一次用在真的出版商網站）

一批九篇，使用者自己的 Safari profile、固定一個視窗（`fetch` 以 `--window-id` 鎖定）；網路路徑沒有記錄（這一句先前寫「機構網路」，#822 的紀錄裡沒有這個說法，#822 verify 第 1 輪第 4 列）；plugin 0.13.17、`akashic fulltext contract` 印 13、safari-browser v2.9.0。Safari 的檔案下載位置是固定的「下載項目」資料夾——這是使用者當場的說明，沒有從命令列讀到（讀出這個設定見 PsychQuant/safari-browser#388）。機器當時負載很高（load average 60–100）。**每一列都只有表裡寫的篇數**；「成功」「沒有權限」只代表那個網路、那一天、那個入口。

| 站 | `fetch` 的結果 | 之後做了什麼、看到什麼 | 觀察 |
|---|---|---|---|
| SAGE（`journals.sagepub.com`，APM 2014）| 結束碼 1 `points off-site`：`citation_pdf_url` 指到 `scholar.google.com` | 兩下，各記一次嘗試：文章頁的「PDF/EPUB」（分頁到 `/doi/epub/…` 閱讀頁），閱讀頁的「Download PDF」（href `/doi/pdf/<DOI>?download=true`）。第二下之後分頁網址不變，檔案在約 15 秒內直接出現在下載資料夾，**沒有儲存面板，使用者沒有按任何東西**；`take` 結束碼 0，17 頁。與 2026-11-19 那一篇（等使用者按「儲存」）的差別，使用者的說明是下載位置改成了固定資料夾；11-19 當天的設定沒有記錄，所以這不是同一天改設定前後各量一次的對照 | 1 篇成功 |
| SAGE（同一站，EPM 2014）| 結束碼 7 `html-page`：頁面自己的 `/doi/pdf/<DOI>` 通到 HTML 頁 | 那一頁寫「Restricted access」「Get full access to this article」「Purchase access」：沒有權限、頁面提供購買（落點表第 7 種的 (d)）。沒有按 | 1 篇，留給使用者決定 |
| Wiley 的學會子網域（`bpspsychub.onlinelibrary.wiley.com`，BJMSP 2014）| 結束碼 1 `points off-site`：頁面給的 PDF 連結在 `onlinelibrary.wiley.com`（母站，與文章頁不同主機；同一個樣子見 #726）| 兩下，各記一次嘗試：文章頁上同主機的 PDF 連結（分頁到 `/doi/epdf/…` 閱讀器），**閱讀器上這篇自己的「Download PDF」`snapshot -i` 讀得到**（href `/doi/pdfdirect/<DOI>?download=true`）。第二下之後檔案直接出現在下載資料夾，沒有儲存面板；21 頁。當時 `take` 沒有帶 `--pages`，結束碼 5、讀首頁確認後存入；事後帶上條目的頁碼重跑是結束碼 0 | 1 篇成功 |
| Cambridge Core（`www.cambridge.org`；Psychometrika 2016、1989、1983，DOI 仍是 `10.1007/…`）| 三篇都是結束碼 7 `tab-unchanged`：落地在 `/core/journals/psychometrika/article/abs/…`，頁面的 PDF 連結在 `/core/services/aop-cambridge-core/content/view/…/….pdf`，導航之後分頁沒有離開摘要頁 | 15 秒內下載資料夾沒有新檔；等一次之後落點仍然沒變；`save-pdf` 探測回「text/html, not a PDF」；`bot-signals` 沒有命中。頁面上是「Get access」「Access through your institution」「Log in to your personal account」與「Add article to cart」：沒有權限、頁面提供購買。沒有按。這裡的 `tab-unchanged` 不是「連結直接開始下載」，是沒有權限時被送回摘要頁——這是從頁面上的字推出來的，沒有看到轉址本身 | 3 篇，留給使用者決定。**這三篇隔天從 SpringerLink 的文章頁取得**，見〈2026-11-21 的實測〉：這一列量到的是那一天經 `doi.org` 落到的 Cambridge Core 頁面上是取得權限與購買的選項、導航到頁面的 PDF 連結之後沒有取得 PDF，不是這三篇拿不到（這一句先前寫那一頁「寫沒有權限」，#822 verify 第 2 輪）。兩天的網路路徑是否相同沒有記錄，同一天也沒有再從 `doi.org` 進一次 |
| Taylor & Francis（`www.tandfonline.com`，JASA 2001）| 結束碼 7 `pdf-shown`：分頁在 `/doi/pdf/<DOI>` 直接顯示 PDF | `save-pdf` 取得 11 頁（出版商封面頁加正文 10 頁）。當天 `take` 沒有帶 `--pages`，結束碼 5（PDF metadata 沒有 DOI，首頁印的 DOI 相符），讀首頁確認後存入；事後帶上條目的頁碼（10 頁）離線重跑，頁數仍判相符、結束碼 0。這一格先前只寫了重跑的結果（#822 verify 第 1 輪第 10 列）| 1 篇成功 |
| Oxford Academic（`academic.oup.com`，Biometrika 1967）| 結束碼 7 `pdf-shown`：PDF 顯示在 `watermark02.silverchair.com`，交接時記號還在 | `save-pdf` 取得 7 頁。首頁沒有印 DOI，`take` 結束碼 5（帶 `--pages` 也是：頁數相符但沒有 DOI 可比），讀首頁以刊名、年份、卷期、起始頁確認後存入。站的行為與〈2026-11-10、2026-11-19 的實測〉Oxford Academic 那一列同一個樣子 | 1 篇成功 |
| SpringerLink（`link.springer.com`，2026 年的書章）| 結束碼 7 `pdf-shown`：分頁在 `/content/pdf/<DOI>.pdf` | `save-pdf` 取得 26 頁。當天這一篇 `take` 的結束碼沒有記在 #822 的紀錄裡（那一批五次 `take` 都沒有帶 `--pages`）；事後帶上頁碼離線重跑是結束碼 0。站的行為與〈2026-11-02 一批〉Springer 那一列同一個樣子 | 1 篇成功 |

**對話框探測在這一批讀起來的樣子**（Safari 本身的行為，不是哪一站的；這一段量到的寫在 [safari-measurements.md](safari-measurements.md) 的 P1，2026-11-21 的量測是 P2）：視窗裡都是 HTML 分頁時，`documents --json` 的 `blocking_dialog` 多數是 `clear`，偶爾一次 `unknown`／`incomplete`，等一次再讀又是 `clear`。第一個顯示 PDF 的分頁出現之後（上表 Taylor & Francis 那一篇；safari-browser#345 記的時間是 17:39），之後每一次讀取整個視窗的每一個分頁都是 `unknown`／`incomplete`、沒有訊息。批次到第 7 篇前後連續四次讀到 `unknown`（其中一次在跑過節奏工具之後），照 SKILL 停下來請使用者看那個視窗；他 17:48 回答畫面上什麼都沒有掛著，之後第 8、9 篇照樣讀成 `unknown`。從這些時間看，那一次停下多半在第一個 PDF 分頁出現之後，逐次的先後沒有記錄。機器當時負載很高，這一點有沒有關係沒有查。這與 PsychQuant/safari-browser#345 記的是同一個樣子。**它碰到 SKILL 第 3 步〈一層層按〉的一條規則**：按之前讀到的不是 `clear` 就不按、仍然是 `unknown` 就停下整批。

（2026-11-21 更正，#822 verify 第 1 輪第 2、11 列。）這一段原本接著寫：「照那條規則，一批裡第一個 `pdf-shown` 的分頁出現之後，同一個視窗後面需要按的每一篇都會停下來問。這一批沒有碰到，是因為需要按的兩篇剛好排在第一個 PDF 分頁之前」。第一句是從這一批的讀數推的、沒有量過；2026-11-21 的唯讀量測指向相反的方向——狀態跟著**作用中的分頁**走（P2 量的那一個視窗裡，作用中分頁顯示 PDF 時讀成 `unknown`，不顯示 PDF 時是 `clear`；那個視窗留著 6 個 PDF 分頁，#822 verify 第 2 輪補上這個範圍），而 `fetch` 為下一篇開的分頁會成為作用中分頁（本機測試頁上的 M1；#828 對照存下的分頁清單，`is_current` 都是 `fetch` 開的那一個）——但出版商網站上、PDF 分頁出現之後還要按的一篇仍然沒有量過。第二句沒有寫到這一批確實停過一次（上面第 7 篇前後那一次）。需要按的兩篇（SAGE、Wiley）排在第一個 PDF 分頁（17:39）之前（#822 2026-11-20 的 Decision 留言），那一次停下從時間看多半在 17:39 之後；但那一次是哪一篇、哪一段（鎖分頁、落點，或按之前的讀取）讀到的 `unknown`，沒有記錄，所以它與第二句說的衝不衝突，從紀錄判斷不出來（這一句先前寫「第二句與上面那一次停下不合」，#822 verify 第 2 輪）。那條規則要不要改，沒有使用者的裁決，在 #828。

這一批的 `acquisition`：下載資料夾取得的兩篇是 `browser-download`，`save-pdf` 取得的三篇是 `browser-save-pdf`。存進 store 的 note 有兩筆寫了「記錄沒有頁碼」，那是錯的（條目有頁碼，是執行時沒有帶 `--pages`）；note 目前沒有更正的入口，見 #824。

## 2026-11-21 的實測（#822：三篇 Psychometrika 改從 SpringerLink 的文章頁進去）

前一天〈2026-11-20 的實測〉Cambridge Core 那一列的三篇，隔天各再試一次，入口不是 `https://doi.org/<DOI>`，而是 `https://link.springer.com/article/<DOI>`。這個入口是 Claude 把網址列給使用者、使用者在對話裡回覆確認之後才用的。SKILL 第 2 步寫的是 OpenAlex 回應裡的位址：「使用者看了回報、在對話裡自己說要改用那個網址時，它才算『使用者給定』」；web-access.md〈開哪個網址〉寫的是取自回應或頁面的網址：「把那個網址列給使用者、等他回覆確認——確認後才算『使用者給定』」。這個入口兩者都不是：它是 Claude 照 DOI 前綴自己組的，兩份文件都沒有用字涵蓋這一種，當天是把使用者的確認讀成「使用者給定」。這一種入口怎麼定在 #828（#822 verify 第 1 輪第 14 列：這裡先前把 SKILL 的句子轉述成「非 DOI 的入口要使用者確認」）。網址先過 `akashic web-read url`（印 `URL-OK 'https://link.springer.com'`）。使用者自己的 Safari profile、同一個固定視窗；安裝的 plugin 是 0.13.18，執行的區塊是前一天從 0.13.17 取出的（0.13.18 沒有改這些區塊）；`akashic fulltext contract` 印 13、safari-browser v2.9.0。這一天的網路路徑讀過一次，細節照 plugin 的規則第 5 條不寫進本檔；前一天的沒有記錄，所以兩天不一定是同一條路徑。機器負載高（load average 約 40）。**只有這三篇**；「取得」只代表那個網路、那一天、那個入口。

| 站 | `fetch` 的結果 | 之後做了什麼、看到什麼 | 觀察 |
|---|---|---|---|
| SpringerLink（`link.springer.com`；Psychometrika 2016、1989、1983，DOI 是 `10.1007/…`）| 三篇都是結束碼 7 `pdf-shown`：落地在 `/article/<DOI>`，頁面自己的 PDF 連結是 `/content/pdf/<DOI>.pdf`，導航之後分頁顯示 PDF；各記一次嘗試（當天 `link.springer.com` 1/10 到 3/10）| `save-pdf` 取得 17、24、13 頁，都與條目的頁碼相符。2016 那一篇 `take`（帶 `--pages`）結束碼 0：檔案的 metadata 與首頁都有 DOI。1989、1983 兩篇是掃描檔，沒有 DOI，`take` 結束碼 5（頁數相符、標題完全相符、`doi_state` 是 `absent`），讀首頁以刊名、卷期、年月、起始頁與作者確認後存入。沒有按任何東西，沒有出現驗證頁或登入頁 | 3 篇成功 |

**這一批說明了什麼、沒有說明什麼。** 同一個 DOI，`doi.org` 解析到 Cambridge Core（期刊現在的出版商），那一頁前一天上面是「Get access」「Add article to cart」這類取得權限與購買的選項，導航到頁面的 PDF 連結之後沒有取得 PDF（〈2026-11-20 的實測〉Cambridge Core 那一列；#822 的紀錄把這些選項讀成沒有權限、頁面提供購買。這一句先前寫那一頁「對這個機構」寫沒有權限，那一天的網路路徑沒有記錄，#822 verify 第 2 輪）；SpringerLink 的文章頁還在，而且給了全文。由此**推**的（推論，不是量到的）：「DOI 的落地頁上取不到 PDF、頁面給的是取得權限與購買的選項」不一定等於「拿不到這一篇」，期刊換過出版商時，舊出版商的站可能還提供舊文章。這個推論比較的是兩天、兩個入口、可能兩條網路路徑；沒有做的反向對照是同一天、同一條路徑再從 `doi.org` 進 Cambridge Core。其他沒有量的事：SpringerLink 上還留著這本期刊的哪些年份；這三篇是機構訂閱給的、還是 SpringerLink 對所有人開放（沒有在確定不帶訂閱權限的情況下對照；這一句先前多寫了一項網路的細節，#822 verify 第 2 輪）；前一天如果也從這個入口進去會怎樣。

**它碰到 SKILL 第 2 步的一條規則**：「第 3 步的 `--landing` 一律是 `https://doi.org/<DOI>`」；別的入口怎麼算「使用者給定」，SKILL 與 web-access.md 的原句見這一節第一段，照 DOI 前綴自己組的入口兩者都沒有涵蓋（#828；這一句先前轉述成「其他入口要使用者逐次確認」，#822 verify 第 2 輪）。照那條規則，Claude 自己不會去試舊出版商的站；這一批是使用者懷疑「沒有權限」的結論、Claude 才提出這個入口並取得確認。要不要讓流程在 DOI 的落地頁沒有權限時，自己提出（或自己試）以 DOI 前綴認得的舊出版商入口，沒有使用者的裁決；那是會改變流程怎麼判的句子，這裡只記事實。

**對話框探測**：這一批每一次讀取都是 `unknown`。三篇都是 `pdf-shown`，讀取時作用中的分頁是顯示 PDF 的那一個（#828 對照存下的分頁清單），與 [safari-measurements.md](safari-measurements.md) 的 P2 相符。這一段原本把它讀成「視窗裡留著前一天顯示 PDF 的分頁」所以 `unknown`、與前一天同一個樣子——那是照前一天的推論讀的，P2 指向別的解釋；這一批沒有切換分頁的對照，兩種讀法在這三篇上分不出來。三篇都不需要按，所以沒有碰到「不是 `clear` 就不按」那條規則。

這一批的 `acquisition` 都是 `browser-save-pdf`，`origin` 是 `https://link.springer.com/content/pdf/<DOI>.pdf`；note 寫明入口是使用者確認的 SpringerLink 文章頁、以及 `doi.org` 解析到的站前一天沒有權限。
