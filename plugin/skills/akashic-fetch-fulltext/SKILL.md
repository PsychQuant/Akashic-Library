---
name: akashic-fetch-fulltext
description: 取得 Akashic 條目的全文 PDF 並存進 store——EndNote「Find Full Text」的對應（#613）。給 citekey、library、或一批 DOI，逐篇：從 store 取 DOI 與書目 → 先找合法開放版本 → 否則用使用者自己 Safari 的既有登入狀態（機構訂閱）下載 → 比對頁數與首頁標題確認是這篇、分辨正式版／作者稿／補充資料 → `store-source` 存進 sources/。當使用者說「幫我下載這些論文」「抓 PDF」「把全文存進 Akashic」「這批文獻要全文」「Find Full Text」「下載 paper」，或手上有一個 library 要補全文、要讀原文查證引用時使用。**不做**：繞過付費牆、代替使用者登入或按授權按鈕、平行大量下載。
---

# 取得全文

把一篇 work 的全文取回、確認是對的那一份，存進 store。這是 `replace-endnote-and-zotero` 規則缺口表裡 EndNote **Find Full Text** 的對應（#613）。

## 這個 skill 能做到哪裡（誠實邊界）

- **能**：取回 PDF、驗證、以 `store-source` 存進 `sources/`（內容定址、git 排除已驗證才寫），回報每筆的 digest。
- **還不能**：把 digest 寫進條目的 `akashic.sources`。store 格式有這個欄位（store-format.md §2.4.1），但 **CLI 與 MCP 目前沒有任何入口寫它**——2026-09-24 在 `Sources/` grep 設值點只有 decode 與 init（#614）。在 #614 落地前，回報表就是連結的唯一紀錄；**不要手寫條目 YAML 補上**（writing-to-the-store.md：沒走編碼器又沒驗的手改是唯一真正錯的走法）。
- **只用使用者自己的存取權**。付費牆後面、使用者沒有權限的，就是拿不到——回報「無權限」，不找替代管道硬拿。

## 中止條款：網站一懷疑是自動化，整批就停

**只要你覺得網站開始懷疑這是 AI／機器人，就停下整批——不是跳過這篇，是整個 run 結束。** 這是使用者定的規矩（2026-09-24），優先於本 skill 其他所有步驟。

停下時：
- **不重試、不換來源、不換站繼續**。被懷疑之後改走別條路，就是在繞偵測。
- **不關那個分頁**，留給使用者看網站實際顯示了什麼。
- 回報：哪個站、哪個訊號、在哪一步、這批完成到哪篇。之後要不要繼續、何時繼續，由使用者決定。

判準是「**看起來像被懷疑**」，不是「符合某個清單」。腳本會自動攔下（結束碼 6）的是**下限**：

- 頁面或回應出現起疑字樣（`scripts/bot_signals.py`）：Cloudflare「Just a moment…」、CAPTCHA／「證明你是人類」、「異常流量」、「請求過多」、「存取遭拒」、PMC 的下載前驗證頁、Akamai／PerimeterX／DataDome 的封鎖頁；以及 HTTP 403／429 本身
- 分頁在流程中途**跑到別的網域**（驗證子網域、登入／SSO 頁）
- 回應**卡住或是空的**：頁面 60 秒沒載完、取 PDF 120 秒沒回應、回應 0 位元組、請求本身拋錯
- 頁面**讀不到**、無從檢查——「沒辦法檢查」不等於「乾淨」

沒有命中上面任何一條、但讀起來像懷疑的東西，**也停**。拿不準就當作是。自動偵測會誤停：一篇**談** CAPTCHA 或存取控制的論文，文章頁本身就含那些字。這是刻意接受的代價；回報裡寫明訊號，由使用者決定那一篇要不要重跑。

**這條刻意寫成開放判準**（和一般規格「能列舉就列舉」的紀律相反），因為它只往「停」的方向擴張：誤停的代價是使用者看一眼，漏停的代價是出版商封鎖使用者機構的 session，兩者不對稱。

**不算懷疑的**：付費牆的登入殼（PsycNet 無權限時回 200 與「Loading…」，結束碼 4）是「沒有權限」，照結束碼 4 處理。

## 開始前

1. **確認節奏工具**：`safari-browser wait --help` 有 `--jitter` 就用 `safari-browser wait --jitter cauchy`；沒有就用本 skill 的 `scripts/jitter.py`。**不要**用 safari-browser SKILL.md 舊的 `max(2, …)` 一行公式——它把 22.3% 的間隔堆在 2.0 秒（PsychQuant/safari-browser#182 的 10⁶ 次模擬）。
2. **選視窗**：`safari-browser documents --json` 列出各視窗的 `profile`。只在**使用者自己的** profile 的視窗開分頁；其他 profile 是別人的 session。拿不準就問。
3. **先載 `safari-browser` skill** 的 tab-locking 段（全域 CLAUDE.md 要求）。

## 流程（逐篇，不平行）

### 1. 從 store 取書目

每筆 work 需要：DOI、標題、頁碼範圍（`fields.pages`，沒有就算了）、type。**type 是 `unpublished-work` 或 DOI 前綴 `10.31234`（PsyArXiv）的就是 preprint**——從記錄判斷，不從檔案判斷：2026-09-24 量過，一份 PsyArXiv preprint 的前兩頁不含 psyarxiv／arxiv／preprint 任何一字。

### 2. 先找合法開放版本

以 DOI 查 OpenAlex：`https://api.openalex.org/works/doi:<DOI>` 的 `best_oa_location`（**以 DOI 查單筆**；不要用 OpenAlex 關鍵字搜尋找作品，見 akashic-bootstrap 的 work-sources.md）。開放版本若是 OSF／機構典藏的直接 PDF，一般 HTTP 下載即可（2026-09-23：三份 OSF preprint 與一份 UvA 典藏直接下載成功）。
出版商頁面即使標為開放取用，headless 下載也可能被拒（2026-09-23：SAGE、Wiley、Annual Reviews 對 curl 回 403，PMC 回防爬蟲頁）——那時走下一步。

### 3. 用使用者的 Safari 下載

```bash
scripts/fetch-fulltext.sh --window <N> --expect-profile "<使用者自己的 profile 名>" \
  --landing "https://doi.org/<DOI>" --out "<暫存目錄>/<citekey>.pdf" \
  --title "<記錄標題>" [--pages <71--98>] [--doi <DOI>] [--prime <PDF URL>] [--bin <safari-browser>]
```

- `--expect-profile` 一律帶：視窗不屬於這個 profile，腳本在開任何分頁之前就拒絕。
- `--out` 要在 **git 工作樹之外**（或被該樹 ignore 的位置）；否則腳本在碰瀏覽器之前就拒絕——全文是第三方內容。
- `--prime`：PMC 用。先像讀者點 PDF 連結那樣開一次 PDF 網址再關掉，之後才從文章頁取（見 publishers.md）。prime 的分頁一有起疑訊號就照中止條款停。

- `--title`／`--pages`／`--doi`：驗證用的記錄資料。`--landing` 是 `https://doi.org/…` 時 DOI 自動從網址取；`--pages` 有就帶。

**驗證怎麼判「是這篇」**（`verify_pdf.py`，2026-09-24 以 29 份真實 PDF 對 Crossref 量過）：首頁要有一行（或連續幾行）**就是**記錄標題，另外要有 DOI 證據，分三級：

- **檔案自己的中繼資料（XMP）DOI** 等於記錄 DOI → 收（頁數不衝突即可）。不等於 → 不收：檔案自己說它是另一篇。
- 沒有中繼資料時，**首頁印的第一個 DOI** 等於記錄 DOI → 還要頁數**吻合**才收——勘誤或回應文可能先印原文的 DOI。不等於 → 不收。
- **完全沒有 DOI 可比** → 不自動收。標題加頁數不算身分。

量到的代價：沒有中繼資料 DOI、記錄又沒頁碼的檔（線上優先刊出、PMC 作者稿、預印本、舊掃描檔）會停在結束碼 5 交給人看。

腳本在**文章頁面內**以頁面自己的 cookie 取 PDF，驗證後才用要求的檔名存；驗證不過的存成 `*.unverified.pdf`，不是 PDF 的回應存成 `*.response.txt` 給人看。各出版商的規則與已知陷阱見 [references/publishers.md](references/publishers.md)——**遇到新站或新失敗樣子先讀它**。

結束碼決定下一步：

| 碼 | 意思 | 下一步 |
|---|---|---|
| 0 | 取得且驗證通過 | 進第 4 步 |
| 3 | 頁面上找不到 PDF 連結 | 讀 publishers.md；可能是新站或改版，看頁面再決定，不盲目重試 |
| 2 | 回應不是 PDF | 看 `*.response.txt`；讀起來像登入頁或起疑，就照中止條款停 |
| 4 | 無權限（網站給了登入殼）| **停止這個站**，列入「需要人」 |
| 6 | **網站懷疑是自動化** | **整批停止**，見「中止條款」；分頁留著 |
| 5 | 是 PDF 但驗證不是這篇 | 看 `*.unverified.pdf` 與 verify JSON：`flags` 有 `supplement` 是抓到補充資料；`title_match` 為 null 是首頁沒有任何一行等於記錄標題（別篇，或記錄與 PDF 用字不同，例如繁簡字）；`doi_state` 是 `metadata-mismatch`／`page-mismatch` 是檔案或首頁指向別的 DOI；`page-match` 而 `pages_ok` 不是 true、或 `title_match` 為 `main-title-response`（標題後接回應／更正類字樣），是只有首頁印的 DOI、不夠確定；`absent` 是沒有任何 DOI 可比。看了再決定 |
| 1 | 自動化失敗（參數、視窗、profile 不符、輸出位置、讀取或解碼失敗） | 看 stderr；分頁若留著，**先看分頁**——讀起來像起疑就照中止條款停，確定是操作問題才修好再繼續 |

每篇之間跑一次節奏工具。

**連續兩篇在同一站出現同樣的失敗樣子就停**，不要把整批跑完——2026-09-23 同一站連續 5 篇卡在同一個點，每篇都留下一個分頁；同型失敗是系統性的，重試只會累積副作用與請求量。

### 4. 存進 store

```text
akashic_store_source(path=<pdf>, media_type="application/pdf",
                     retrieved="<取得時間，ISO 8601 帶 +08:00>",
                     origin="<實際取得的 PDF URL>",
                     acquisition="browser-download"   # 開放版本直接下載用 "api" 或照實寫
                     note="<版本：version of record / author manuscript / preprint；verify 摘要>")
```

`retrieved` 是**取得**時間，不是存入時間。回傳的 digest 記進回報表。作者稿與預印本**照實在 note 寫版本**，不要讓它看起來像正式版。

### 5. 回報

每筆一列：citekey、結果（stored／no access／no link／not verified）、版本、digest、頁數、來源。最後列出「需要人處理」的清單與原因（無權限的站、找不到連結的新站）。**不寫「應該有權限」「大概是這篇」**——量到什麼寫什麼，見 [`assertions-must-be-measured`](../../rules/assertions-must-be-measured.md)。

## 不做的事

- 不代替使用者按登入、授權、「接受」之類的按鈕；遇到阻擋性對話框就停（safari-browser skill 的規定）。
- 不解 CAPTCHA、不等驗證頁自己過、不在被懷疑後換條路繼續（中止條款）。
- 不關、不改使用者原本開著的分頁。腳本只關自己開的那一個，而且關之前確認它還顯示同一個站。
- 不清 cookie、不註銷 service worker（持久狀態變更要先問，見全域 browser automation 規則）。
- 不把 PDF 放進任何會 push 的 git 工作樹——全文是第三方版權內容，只進 `sources/`（git 排除由 `store-source` 在寫入前驗證）。

## 相關

- [`assertions-must-be-measured`](../../rules/assertions-must-be-measured.md)——回報與 publishers.md 的每條站點描述都是關於世界的斷言，帶觀察日期
- [`source-of-truth-over-consent`](../../rules/source-of-truth-over-consent.md)——存進 `sources/` 的全文要核對過就是這一篇；使用者指定的連結是線索，對不上就不存
- akashic-bootstrap 的 work-sources.md——DOI 反查與 OpenAlex 的兩個陷阱
- #613（本 skill）、#614（`akashic.sources` 寫入入口）、PsychQuant/safari-browser#182（`wait --jitter`）、#183（CLI 沒有下載指令）
