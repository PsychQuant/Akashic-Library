---
name: akashic-fetch-fulltext
description: 取得 Akashic 條目的全文 PDF 並存進 store——EndNote「Find Full Text」的對應（#613）。給 citekey、library、或一批 DOI，逐篇：從 store 取 DOI 與書目 → 以 OpenAlex 查有沒有合法開放版本 → 一律用使用者自己 Safari 的既有登入狀態下載（開放版本與機構訂閱都走這條，不另走一般 HTTP）→ 比對頁數與首頁標題確認是這篇、分辨正式版／作者稿／補充資料 → `store-source` 存進 sources/（index 記下取得記錄）→ 用 `update-entry --add-source`（MCP `akashic_update_entry` 的 `add_sources`）把 digest 連回條目的 `akashic.sources`（要求 index 有取得記錄，孤兒 blob 與非普通檔拒絕）。當使用者說「幫我下載這些論文」「抓 PDF」「把全文存進 Akashic」「這批文獻要全文」「Find Full Text」「下載 paper」，或手上有一個 library 要補全文、要讀原文查證引用時使用。**不做**：繞過付費牆、代替使用者登入或按授權按鈕、平行大量下載。
---

# 取得全文

把一篇 work 的全文取回、確認是對的那一份，存進 store。這是 `replace-endnote-and-zotero` 規則缺口表裡 EndNote **Find Full Text** 的對應（#613）。

## 這個 skill 能做到哪裡（誠實邊界）

- **能**：取回 PDF、驗證、以 `store-source` 存進 `sources/`（內容定址、git 排除已驗證才寫），回報每筆的 digest。
- **能**（#614 起）：把驗證過的 digest 寫進條目的 `akashic.sources`（store-format.md §2.4.1），宣告「這份內容是這篇的副本」——見第 5 步。**不要手寫條目 YAML 補上**（writing-to-the-store.md：沒走編碼器又沒驗的手改是唯一真正錯的走法）。
- **只用使用者自己的存取權**。付費牆後面、使用者沒有權限的，就是拿不到——回報「無權限」，不找替代管道硬拿。

## 中止條款：網站一懷疑是自動化，整批就停

**只要你覺得網站開始懷疑這是 AI／機器人，就停下整批——不是跳過這篇，是整個 run 結束。** 這是使用者定的規矩（2026-09-24），優先於本 skill 其他所有步驟。

停下時：
- **不重試、不換來源、不換站繼續**。被懷疑之後改走別條路，就是在繞偵測。
- **不關那個分頁**，留給使用者看網站實際顯示了什麼。
- 回報：哪個站、哪個訊號、在哪一步、這批完成到哪篇。之後要不要繼續、何時繼續，由使用者決定。

判準是「**看起來像被懷疑**」，不是「符合某個清單」。`akashic fulltext fetch` 會自動攔下（結束碼 6）的是**下限**：

- 頁面或回應出現起疑字樣（`akashic fulltext bot-signals`）：Cloudflare「Just a moment…」、CAPTCHA／「證明你是人類」、「異常流量」、「請求過多」、「存取遭拒」、PMC 的下載前驗證頁、Akamai／PerimeterX／DataDome 的封鎖頁；以及 HTTP 403／429 本身
- 分頁在流程中途**跑到別的網域**（驗證子網域、登入／SSO 頁）
- 回應**卡住或是空的**：頁面 60 秒沒載完、取 PDF 120 秒沒回應、回應 0 位元組、請求本身拋錯
- 頁面**讀不到**、無從檢查——「沒辦法檢查」不等於「乾淨」

沒有命中上面任何一條、但讀起來像懷疑的東西，**也停**。拿不準就當作是。自動偵測會誤停：一篇**談** CAPTCHA 或存取控制的論文，文章頁本身就含那些字。這是刻意接受的代價；回報裡寫明訊號，由使用者決定那一篇要不要重跑。

**這條刻意寫成開放判準**（和一般規格「能列舉就列舉」的紀律相反），因為它只往「停」的方向擴張：誤停的代價是使用者看一眼，漏停的代價是出版商封鎖使用者機構的 session，兩者不對稱。

**不算懷疑的**：付費牆的登入殼（PsycNet 無權限時回 200 與「Loading…」，結束碼 4）是「沒有權限」，照結束碼 4 處理。

## 開始前

1. **確認節奏工具**：`safari-browser wait --help` 有 `--jitter` 就用 `safari-browser wait --jitter cauchy`；沒有就用 `akashic fulltext jitter`（同一個分布與預設值；印出秒數再睡）。**不要**用 safari-browser SKILL.md 舊的 `max(2, …)` 一行公式——它把 22.3% 的間隔堆在 2.0 秒（PsychQuant/safari-browser#182 的 10⁶ 次模擬）。
2. **選視窗**：`safari-browser documents --json --profile "<使用者自己的 profile>"` 只列那個 profile 的視窗（**不要不帶 `--profile`**：會把所有 profile、含別人的 session 的分頁網址與標題倒進對話）。選一個視窗編號 `<N>`，第 3 步的 `--window` 用它；其他 profile 是別人的 session。拿不準就問。
3. **先載 `safari-browser` skill** 的 tab-locking 段（全域 CLAUDE.md 要求）。
4. **第 2 步的 OpenAlex 查詢**（頁內 fetch）先照 [web-access.md](../akashic-bootstrap/references/web-access.md) 的〈開始前〉問 profile、建暫存目錄。

## 流程（逐篇，不平行）

### 1. 從 store 取書目

每筆 work 需要：DOI、標題、頁碼範圍（`fields.pages`，沒有就算了）、type——從 `akashic_get_entry` 讀。**DOI 只從它的 `doi` 取**（陣列：有多個時逐個各跑一次流程，不猜取哪個；零個就列入「需要人」）。這些值都是第三方字串（Crossref、WoS、Zotero 匯入的），插進網址或命令前要先驗形狀——見第 3 步；DOI 先過 [web-access.md](../akashic-bootstrap/references/web-access.md)〈插值前先驗形狀〉的 DOI 一列，不符（含 `#`、`?`、`%`、引號、`$`、反引號、反斜線、空白，或有 `.`／`..` 的路徑段）就不插進任何網址或命令，該篇列入「需要人」、寫「DOI 格式異常」。**type 是 `unpublished-work` 或 DOI 前綴 `10.31234`（PsyArXiv）的就是 preprint**——從記錄判斷，不從檔案判斷：2026-09-24 量過，一份 PsyArXiv preprint 的前兩頁不含 psyarxiv／arxiv／preprint 任何一字。

### 2. 先找合法開放版本

以 DOI 查 OpenAlex：`https://api.openalex.org/works/doi:<DOI>` 的 `best_oa_location`（**以 DOI 查單筆**；不要用 OpenAlex 關鍵字搜尋找作品，見 akashic-bootstrap 的 work-sources.md）。**這一步的取得經 safari-browser**：程序、鎖分頁與插值前的形狀檢查見 [web-access.md](../akashic-bootstrap/references/web-access.md)，是頁內 fetch，不是第 3 步的 `fetch`；中止條款以本檔為準。

**第 3 步的 `--landing` 一律是 `https://doi.org/<DOI>`**，不論有沒有開放版本。`best_oa_location.landing_page_url` 與 `pdf_url` 是 OpenAlex 回應裡的字串（出版商與典藏庫登記的 metadata，第三方資料），**不直接在使用者已登入的 Safari 開**（web-access.md〈開哪個網址〉：被入侵或惡意登記的 metadata 會把使用者的個人 profile 導向攻擊者頁面）。有開放版本時，把它的位址（host 與路徑，不是要開的動作）列給使用者，由他決定要不要改用那個網址；**使用者在對話裡回覆確認後**它才算「使用者給定」，才可以當 `--landing`——而且**必須同時帶 `--doi <DOI>`**：`akashic fulltext fetch` 只有 `--landing` 是 doi.org 網址時才從網址取 DOI（`FulltextFetch.doiFromLanding`：`https://doi.org/`、`http://doi.org/`、`https://dx.doi.org/` 三個前綴、區分大小寫），其他網址不帶 `--doi`，`akashic fulltext verify` 沒有 DOI 可比，`doi_state` 是 `absent`，檔案必然存成 `*.unverified.pdf`、結束碼 5（讀碼確定，不是偶然）。

**不另走一般 HTTP 下載**（不用 `curl`、WebFetch）：2026-09-23 有三份 OSF preprint 與一份 UvA 典藏是那樣下載成功的（publishers.md 該列），但那是這條規矩之前的觀察，**經第 3 步的 Safari 路徑取這幾站沒有量過**（DOI 經 `doi.org` 轉到那些站的頁面再找 PDF 連結，沒有實跑）——找不到 PDF 連結會結束碼 3，照該碼處理。只有 `pdf_url`、沒有 `landing_page_url` 時停下來問使用者，**不要**把 PDF 網址當 `--landing`：讀碼（沒有實跑）——`fetch` 在等頁面載完時讀 `document.readyState`，而 Safari 的 PDF 檢視器讀不到，60 秒後以「頁面沒載完（stalled）」結束碼 6 整批停。

出版商頁面即使標為開放取用，headless 取得也可能被拒（2026-09-23：SAGE、Wiley、Annual Reviews 對 `curl` 回 403，PMC 回防爬蟲頁）——那是量測紀錄，說明為什麼取得一律走使用者的 Safari；在 Safari 裡被拒是中止條款的訊號。

### 3. 用使用者的 Safari 下載

```bash
akashic fulltext fetch --window <N> --expect-profile "<使用者自己的 profile 名>" \
  --landing "https://doi.org/<DOI>" --out "<暫存目錄>/<citekey>.pdf" \
  --title "$(cat '<暫存目錄>/<citekey>.title.txt')" [--pages "<71--98>"] [--doi "<DOI>"] [--prime "<PDF URL>"] [--bin <safari-browser>]
```

（#629 之前這是 `scripts/fetch-fulltext.sh`，驗證與規則是同目錄的 Python 腳本；現在全是 `akashic` 的子命令，沒有 Python、沒有 shell。旗標與結束碼的契約不變，**只有兩點差別**：命令列本身打錯（缺必填旗標、視窗編號不是數字、未知旗標）是結束碼 64 而不是 1——那是 ArgumentParser 的用法錯誤；環境變數 `FETCH_FULLTEXT_NAP`（舊路徑測試用來把等待歸零）不再存在，等待由測試注入。）

**插進這條命令的第三方值要先處理**（與 #595 同一類；命令裡的值一律用雙引號包住）：

- **標題不直接寫進命令列**：用 Write 工具把記錄標題的原文寫進 `<暫存目錄>/<citekey>.title.txt`，再用 `--title "$(cat '…')"` 帶入——`$(…)` 的輸出不會被 shell 再展開，標題裡的 `"`、`$(…)`、反引號都只是字元。
- `<DOI>`：第 1 步的形狀檢查已過才插；`--doi` 與 `--landing` 用同一個值。
- `--landing`／`--prime` 的網址若來自 OpenAlex 回應（`landing_page_url`／`pdf_url`）是第三方字串：**不直接使用**，見第 2 步；使用者確認過的網址才可以，而且要過 web-access.md〈插值前先驗形狀〉的「完整網址」一列（只收 https、不含空白、`"`、反引號、`$`、反斜線、`#`，也不是 `localhost` 或 IP 位址）才插進命令，否則停下來問使用者。
- `--pages` 只在頁碼是 `數字--數字` 或單一數字的形狀時帶，否則不帶（它是選填的驗證資料）。
- `<citekey>` 取自 store：載入時已驗過只含 `a–z 0–9 -`，可以直接用。

- `--expect-profile` 一律帶：視窗不屬於這個 profile，`fetch` 在開任何分頁之前就拒絕。
- `--out` 要在 **git 工作樹之外**（或被該樹 ignore 的位置）；否則 `fetch` 在碰瀏覽器之前就拒絕——全文是第三方內容。
- `--prime`：PMC 用。先像讀者點 PDF 連結那樣開一次 PDF 網址再關掉，之後才從文章頁取（見 publishers.md）。prime 的分頁一有起疑訊號就照中止條款停。

- `--title`／`--pages`／`--doi`：驗證用的記錄資料。`--landing` 是 `https://doi.org/…` 時 DOI 自動從網址取；**不是 doi.org 的 `--landing` 一律要帶 `--doi <DOI>`**（否則驗證必然停在結束碼 5，見第 2 步）；`--pages` 有就帶。

**這條命令的鎖分頁與 web-access.md 不同**：`fetch` 用 `--window <N>` 加它自己開的分頁位置（`--tab-in-window`，#613 的作法，理由見 publishers.md：使用者已開著同一頁時 URL 鎖會對到兩個分頁、safari-browser fail-closed），**不是** web-access.md 的 `--profile`＋`--url-endswith`。這是 grandfathered 的例外（規則檔〈既有檔〉形狀 (b)）。**#629 把腳本移植成 `akashic fulltext fetch` 時沒有改鎖法**（改成 `--profile`＋`--url-endswith` 要使用者裁決、而且要實跑 Safari；規則檔記著便宜的解：對 `--landing` 加一次性 fragment，沒實測）。同一個 skill 因此有兩個鎖法，分工是：第 2 步的頁內 OpenAlex 查詢照 web-access.md、第 3 步只用 `fetch`，兩者不混用；不要在第 3 步之外自己用 `--window` 動 Safari。

**驗證怎麼判「是這篇」**（`akashic fulltext verify`；程式與校準表在 akashic repo 的 `Sources/AkashicSkillTools/FulltextVerify.swift`，該 repo 為 private、plugin 安裝處讀不到；門檻是 2026-09-24 以 29 份真實 PDF 對 Crossref 量過的，#629 移植後**沒有重跑那組校準**——那 29 份 PDF 不在本機，見 changelog `2026-09-29-fulltext-scripts-to-swift.md`）：首頁要有一行（或連續幾行）**就是**記錄標題，另外要有 DOI 證據，分三級：

- **檔案自己的中繼資料（XMP）DOI** 等於記錄 DOI → 收（頁數不衝突即可）。不等於 → 不收：檔案自己說它是另一篇。
- 沒有中繼資料時，**首頁印的第一個 DOI** 等於記錄 DOI → 還要頁數**吻合**才收——勘誤或回應文可能先印原文的 DOI。不等於 → 不收。
- **完全沒有 DOI 可比** → 不自動收。標題加頁數不算身分。

量到的代價：沒有中繼資料 DOI、記錄又沒頁碼的檔（線上優先刊出、PMC 作者稿、預印本、舊掃描檔）會停在結束碼 5 交給人看。

`fetch` 在**文章頁面內**以頁面自己的 cookie 取 PDF，驗證後才用要求的檔名存；驗證不過的存成 `*.unverified.pdf`，不是 PDF 的回應存成 `*.response.txt` 給人看。各出版商的規則與已知陷阱見 [references/publishers.md](references/publishers.md)——**遇到新站或新失敗樣子先讀它**。

結束碼決定下一步：

| 碼 | 意思 | 下一步 |
|---|---|---|
| 0 | 取得且驗證通過 | 進第 4 步 |
| 3 | 頁面上找不到 PDF 連結 | 讀 publishers.md；可能是新站或改版，看頁面再決定，不盲目重試 |
| 2 | 回應不是 PDF | 看 `*.response.txt`；讀起來像登入頁或起疑，就照中止條款停 |
| 4 | 無權限（網站給了登入殼）| **停止這個站**，列入「需要人」 |
| 6 | **網站懷疑是自動化** | **整批停止**，見「中止條款」；分頁留著 |
| 5 | 是 PDF 但驗證不是這篇 | 看 `*.unverified.pdf` 與 verify JSON：`flags` 有 `supplement` 是抓到補充資料；`title_match` 為 null 是首頁沒有任何一行等於記錄標題（別篇，或記錄與 PDF 用字不同，例如繁簡字）；`doi_state` 是 `metadata-mismatch`／`page-mismatch` 是檔案或首頁指向別的 DOI；`page-match` 而 `pages_ok` 不是 true、或 `title_match` 為 `main-title-response`（標題後接回應／更正類字樣），是只有首頁印的 DOI、不夠確定；`absent` 是沒有任何 DOI 可比。看了再決定 |
| 1 | 自動化失敗（視窗、profile 不符、輸出位置、讀取或解碼失敗；命令列打錯是 64） | 看 stderr；分頁若留著，**先看分頁**——讀起來像起疑就照中止條款停，確定是操作問題才修好再繼續 |

每篇之間跑一次節奏工具。

**連續兩篇在同一站出現同樣的失敗樣子就停**，不要把整批跑完——2026-09-23 同一站連續 5 篇卡在同一個點，每篇都留下一個分頁；同型失敗是系統性的，重試只會累積副作用與請求量。

### 4. 存進 store

```text
akashic_store_source(path=<pdf>, media_type="application/pdf",
                     retrieved="<取得時間，ISO 8601 帶 +08:00>",
                     origin="<實際取得的 PDF URL>",
                     acquisition="browser-download"   # 本 skill 一律經使用者自己的 Safari 取得；照實寫
                     note="<版本：version of record / author manuscript / preprint；verify 摘要>")
```

`retrieved` 是**取得**時間，不是存入時間。回傳的 digest 記進回報表。作者稿與預印本**照實在 note 寫版本**，不要讓它看起來像正式版。

### 5. 連結回記錄

只連**第 4 步存了、而且第 3 步驗證通過（結束碼 0）**的那幾篇；結束碼 5 經人看過、確認是這篇的，同樣可以連——那一種存的是 `*.unverified.pdf`（第 4 步照存），`note` 要寫「人工確認為這篇：<誰>／<日期>；verify 的 flags：<…>」，因為連結說的「這份就是這篇」只有 note 記得是誰判的。驗證不過又沒人確認的不連——那正是驗證在判的事。

先乾跑，看 `sourcesAdded` 帶回來的取得記錄（origin、note）是不是剛存的那一份，再實寫：

```text
akashic_update_entry(citekey="<citekey>", add_sources=["<digest>"])                  # 乾跑（預設）
akashic_update_entry(citekey="<citekey>", add_sources=["<digest>"], dry_run=false)   # 實寫
```

CLI 是 `akashic update-entry <citekey> --add-source <digest>`，加 `--apply` 才寫（未指名目標 store 時要 `--library` 或 `--yes`）。digest 必須已在本機 `sources/`、index 有取得記錄、blob 的位置是普通檔——第 4 步存過就滿足。已連過的回 `sourcesAlreadyPresent`、不重寫。連好之後用 `akashic get-entry <citekey>` 的 `sources` 核對。

**連錯了怎麼收回**：用 `update-entry <citekey> --remove-source <digest>=理由`（MCP `update_entry` 的 `remove_sources`，#677）收回那一條宣告。先乾跑（預設）——`sourcesRemoved` 帶回 index 的取得記錄（origin、note），確認要收回的是那一份，再加 `--apply`（MCP `dry_run=false`）實寫。實寫要求這筆 work 的檔已在 git 裡 commit、乾淨（理由只進報告、不寫進 store，要留在 git 就寫進 commit message）；所以連結後、下一次寫入前先 commit store（那是使用者自己的流程，本 skill 不代做）。**只收回宣告**：`sources/` 裡的內容與取得記錄不動（可能被別筆 work 宣告）。理由含引號、`$` 或反引號時走 MCP（結構化參數，不經 shell），不要放進 shell 命令。**仍然不要手寫條目 YAML。**

### 6. 回報

每筆一列：citekey、結果（stored／no access／no link／not verified）、版本、digest、是否已連回記錄、頁數、來源。最後列出「需要人處理」的清單與原因（無權限的站、找不到連結的新站）。**不寫「應該有權限」「大概是這篇」**——量到什麼寫什麼，見 [`assertions-must-be-measured`](../../rules/assertions-must-be-measured.md)。

## 不做的事

- 不代替使用者按登入、授權、「接受」之類的按鈕；遇到阻擋性對話框就停（safari-browser skill 的規定）。
- 不解 CAPTCHA、不等驗證頁自己過、不在被懷疑後換條路繼續（中止條款）。
- 不關、不改使用者原本開著的分頁。`fetch` 只關自己開的那一個，而且關之前確認它還顯示同一個站。
- 不清 cookie、不註銷 service worker（持久狀態變更要先問，見全域 browser automation 規則）。
- 不把 PDF 放進任何會 push 的 git 工作樹——全文是第三方版權內容，只進 `sources/`（git 排除由 `store-source` 在寫入前驗證）。

## 相關

- [`assertions-must-be-measured`](../../rules/assertions-must-be-measured.md)——回報與 publishers.md 的每條站點描述都是關於世界的斷言，帶觀察日期
- [`source-of-truth-over-consent`](../../rules/source-of-truth-over-consent.md)——存進 `sources/` 的全文要核對過就是這一篇；使用者指定的連結是線索，對不上就不存
- akashic-bootstrap 的 work-sources.md——DOI 反查與 OpenAlex 的兩個陷阱
- #613（本 skill）、#614（`akashic.sources` 寫入入口）、PsychQuant/safari-browser#182（`wait --jitter`）、#183（CLI 沒有下載指令）
