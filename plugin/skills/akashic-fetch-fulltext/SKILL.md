---
name: akashic-fetch-fulltext
description: 取得 Akashic 條目的全文 PDF 並存進 store——EndNote「Find Full Text」的對應（#613）。最高原則：**跟真人一樣**——每一個對網站的動作都要是真人也會做的。給 citekey、library、或一批 DOI，逐篇：從 store 取 DOI 與書目 → 以 OpenAlex 查有沒有合法開放版本 → 在使用者自己的 Safari 裡**只用導航**走到頁面自己的 PDF 連結，然後**交給使用者存檔**（`akashic fulltext fetch`；不在頁內取檔、不拼網址、按鈕與 CAPTCHA 交給人、每站每天 10 次嘗試）→ 使用者存好的檔交給 `akashic fulltext take` 比對頁數與首頁標題、分辨正式版／作者稿／補充資料 → `store-source` 存進 sources/ → 用 `update-entry --add-source`（MCP `akashic_update_entry` 的 `add_sources`）把 digest 連回條目的 `akashic.sources`。當使用者說「幫我下載這些論文」「抓 PDF」「把全文存進 Akashic」「這批文獻要全文」「Find Full Text」「下載 paper」，或手上有一個 library 要補全文、要讀原文查證引用時使用。**不做**：繞過付費牆、代替使用者登入或按授權按鈕、解 CAPTCHA、平行大量下載、在頁內以 JS 取檔。
---

# 取得全文

把一篇 work 的全文取回、確認是對的那一份，存進 store。這是 `replace-endnote-and-zotero` 規則缺口表裡 EndNote **Find Full Text** 的對應（#613）。

> **先讀這一段（2026-10-01 起）：舊的「頁內取檔」路徑已經拿掉。** #613 之前的 `akashic fulltext fetch` 在文章頁內以 JS `fetch()` 取 PDF 的位元組——
> 那正是 2026-09-28 兩次 ScienceDirect CAPTCHA 之前做的事。現在 `fetch` **只導航、交給人**，位元組由使用者自己存，再交給 `akashic fulltext take`。
> **使用者機器上的 `akashic` 若比 #613 舊，它的 `fetch` 仍會在頁內取檔：不要拿它對任何出版商網站跑。** 開始前第 0 步會檢查這件事。

## 最高原則：跟真人一樣（使用者 2026-09-28）

**每一個對網站的動作，都要是真人也會做的動作。** 本 skill 的中止條款、「等人驗證」、每站上限與下面五條，都是這條原則的展開；**規則之間衝突、或遇到規則沒寫到的情形，以這條為準**。

2026-09-28 一晚三次 CAPTCHA，每一次都緊跟在一個真人不會做的動作之後：頁內以 JS fetch PDF 端點、短時間重複載入同一篇、固定間隔（ScienceDirect #1）；PDF 已經顯示，又對同一個簽章網址多送一次請求（ScienceDirect #2）；導航之前先以 curl 打了 DOI 頁與 PDF 端點（Optica）。相對地，完全用導航、由使用者按按鈕存檔的那一次沒有任何檢查。

1. **出版商網站只用瀏覽器導航**：不用 curl 或任何 HTTP 客戶端，不在頁內以 JS 取檔（`fetch()` 帶 `Sec-Fetch-Mode: cors`，看得出來）。
   決定原文另寫：「開放典藏（機構 repository、S3 預簽章的公開檔）不在此限」——例外只放寬這一條，而且只對那兩種來源；本 skill 目前**沒有用到它**，開放典藏也走同一條路（導航、交給人）。要用這個例外，得先由使用者裁決怎麼認定一個站是開放典藏。
2. **每個請求都要有真人對應的動作**：不重抓已載入的檔、不猜網址、不試端點（#613 起不再拼 SAGE `?download=true`、Wiley `pdfdirect`、PsycNet `/fulltext/<id>.pdf`，只跟頁面自己的連結走）；失敗就停，不臨場換招。
3. **需要按鈕或驗證的步驟交給人**：存 PDF（用預覽程式打開、下載鈕、⌘S）、頁面的下載按鈕、CAPTCHA。命令列只做沒有副作用的讀取。
4. **一次一篇、節奏像人**：篇與篇之間跑節奏工具（jitter），不用固定的 `sleep`；上一篇交給人之後，等使用者處理完再做下一篇。
5. **頁面上執行的 JS 要少而且正確**：網站的分析工具看得到頁面的 JS 錯誤（2026-09-28 NVA 的 Matomo 記錄了 agent 的 SyntaxError）。`fetch` 注入的每一段都是固定的、驗過能解析的運算式；**不要自己另外往出版商頁面送 JS**。

## 這個 skill 能做到哪裡（誠實邊界）

- **能**：在使用者的 Safari 裡走到頁面自己的 PDF 連結、交給使用者存檔；驗證使用者存下來的檔、以 `store-source` 存進 `sources/`（內容定址、git 排除已驗證才寫），回報每筆的 digest。
- **能**（#614 起）：把驗證過的 digest 寫進條目的 `akashic.sources`（store-format.md §2.4.1）——見第 6 步。**不要手寫條目 YAML 補上**（writing-to-the-store.md：沒走編碼器又沒驗的手改是唯一真正錯的走法）。
- **不能自己取得位元組**：PDF 顯示出來之後，存檔是使用者的動作。三種存法（用預覽程式打開、下載鈕、⌘S）哪一個是標準流程，由 PsychQuant/safari-browser#210 的實驗決定，本 skill 不挑；那之前使用者用他習慣的方式存。
- **只用使用者自己的存取權**。付費牆後面、使用者沒有權限的，就是拿不到——回報「無權限」，不找替代管道硬拿。

## 中止條款：起疑訊號分兩種處置

**只要你覺得網站開始懷疑這是 AI／機器人，就停下。** 這是使用者定的規矩（2026-09-24），優先於本 skill 其他所有步驟；使用者 2026-09-28、2026-10-01 把停下的方式分成兩種：

**等人驗證**（`fetch` 結束碼 8）——**只有這四種**：CAPTCHA、人類檢查（「Are you a robot?」「證明你是人類」）、Cloudflare「Just a moment…」、按住驗證（press and hold）。

- **暫停這一篇**，請使用者在他自己的 Safari 裡、那個分頁完成驗證。**不代解、不繞過、不重新載入、不開新分頁、不換站。**
- 使用者說完成了之後，**在同一個分頁接著走**：同一條 `fetch` 命令加上它印出的 `--resume-tab <T> --resume-origin <https://主機>`。分頁若還在驗證頁，會再停在 8。
- 使用者把那個視窗拉到前面時，視窗編號會變：用 `safari-browser documents --json --profile "<P>"` 找出顯示那個主機的分頁，換成它的 `--window`／`--resume-tab`。對不上時 `fetch` 拒絕（結束碼 1），**不猜是哪一個分頁**。

**整批暫停**（`fetch` 結束碼 6）——其他所有訊號：

- 頁面或回應出現起疑字樣（`akashic fulltext bot-signals`）：Akamai／PerimeterX／DataDome 的封鎖頁、「存取遭拒」、「異常流量」、「請求過多」、PMC 的下載前驗證頁（「preparing to download」）、**ScienceDirect 點 View PDF 之後的「Preparing your download」中介頁**（`cra_js_challenge`；使用者 2026-10-01 裁決為起疑訊號，不當成一般讀者流程等它自己過）；以及 HTTP 403／429 本身（頁面有這個值、而文字不是上面四種驗證頁時——挑戰頁本身常以 403 回應，那時照等人驗證）
- 分頁在流程中途**跑到別的網域**（驗證子網域、登入／SSO 頁）
- 頁面**卡住**：60 秒沒載完、導航到 PDF 連結之後 60 秒沒落定
- 頁面**讀不到**、無從檢查——「沒辦法檢查」不等於「乾淨」

整批暫停時：**不重試、不換來源、不換站繼續**（被懷疑之後改走別條路，就是在繞偵測）；**不關那個分頁**，留給使用者看；回報哪個站、哪個訊號、在哪一步、這批完成到哪篇。之後要不要繼續、何時繼續，由使用者決定。

同一頁同時出現兩種訊號時（PerimeterX 的封鎖頁同時寫著「Access to this page has been denied」與「Press & Hold」），**整批暫停優先**。

判準是「**看起來像被懷疑**」，不是「符合某個清單」：上面的自動偵測是**下限**。沒有命中、但讀起來像懷疑的東西，**也停**（拿不準是哪一種就當整批暫停）。自動偵測會誤停：一篇**談** CAPTCHA 或存取控制的論文，文章頁本身就含那些字。這是刻意接受的代價；回報裡寫明訊號，由使用者決定那一篇要不要重跑。這條刻意寫成開放判準（和一般規格「能列舉就列舉」的紀律相反），因為它只往「停」的方向擴張：誤停的代價是使用者看一眼，漏停的代價是出版商封鎖使用者機構的 session。**等人驗證的四種則是封閉列舉**，不得依「看起來也是驗證頁」類推第五種。

**不算懷疑的**：付費牆的登入殼（PsycNet 無權限時的「Loading…」頁）是「沒有權限」。`fetch` 把它交給人看（結束碼 7，`html-page`），由使用者確認，列入「需要人」。

## 每站每天 10 次嘗試（使用者 2026-10-01）

- `fetch` 每次**準備導航到 PDF 連結（或把頁面的下載按鈕交給人）**就記一次嘗試；之後失敗、驗證不過、使用者沒存，都已經算了。
- 站以 doi.org 轉址之後**文章頁的主機**區分（例如 `www.sciencedirect.com`，不是 `pdf.sciencedirectassets.com`），日界是 **Asia/Taipei** 的日曆日。
- 到上限時 `fetch` 以結束碼 9 停下，**沒有向那個站要 PDF**。停那個站、隔天再跑；這批裡已知會到同一個站的其他篇（同一個 DOI 前綴，例如 `10.1016`）不要再跑，列入「每日上限，明天再跑」。別的站照常一次一篇繼續。
- 帳本在 store 之外（預設 `~/Library/Application Support/akashic/fulltext-attempts.jsonl`，每行一筆、時間帶 `+08:00`）。帳本讀不懂時 `fetch` 在開任何分頁之前拒絕（結束碼 1）——數不出今天的次數，就不能保證沒超過上限。不要為了繞過上限去刪改帳本。

## 開始前

0. **確認 `akashic` CLI 含 #613 的 `fulltext take`**（舊的 `fetch` 還在頁內取檔，見本檔開頭）。plugin 只自動下載 `akashic-mcp`、不出貨 `akashic` CLI，所以 plugin 文字可能比使用者機器上的 CLI 新。用真的呼叫探測（`--help` 對舊 binary 也回 0，探不出來）：

   ```bash
   W="<暫存目錄>"
   rc=0; akashic fulltext take --from "$W/does-not-exist.pdf" --out "$W/probe.pdf" 2>"$W/probe.err" || rc=$?
   [ "$rc" -eq 1 ] && grep -q -- '--from does not exist' "$W/probe.err" \
     || { echo "akashic CLI 比 #613 舊（或沒裝）：它的 fulltext fetch 仍在頁內取檔——先更新 CLI，不要對出版商網站跑" >&2; exit 1; }
   ```

   **確認不了就停，不要用舊的 `fetch`、也不要自己改寫一段取檔的流程。**
1. **確認節奏工具**：`safari-browser wait --help` 有 `--jitter` 就用 `safari-browser wait --jitter cauchy`；沒有就用 `akashic fulltext jitter`（同一個分布與預設值；印出秒數再睡；**跑不起來就停下，不要略過節奏**）。**不要**用固定的 `sleep`，也不要用 safari-browser SKILL.md 舊的 `max(2, …)` 一行公式——它把 22.3% 的間隔堆在 2.0 秒（PsychQuant/safari-browser#182 的 10⁶ 次模擬）。
2. **選視窗**：`safari-browser documents --json --profile "<使用者自己的 profile>"` 只列那個 profile 的視窗（**不要不帶 `--profile`**：會把所有 profile、含別人的 session 的分頁網址與標題倒進對話）。選一個視窗編號 `<N>`，第 3 步的 `--window` 用它；其他 profile 是別人的 session。拿不準就問。
3. **先載 `safari-browser` skill** 的 tab-locking 段（全域 CLAUDE.md 要求）。
4. **第 2 步的 OpenAlex 查詢**（頁內 fetch，查的是 OpenAlex 的 API，不是出版商）先照 [web-access.md](../akashic-bootstrap/references/web-access.md) 的〈開始前〉問 profile、建暫存目錄。

## 流程（逐篇，不平行）

### 1. 從 store 取書目

每筆 work 需要：DOI、標題、頁碼範圍（`fields.pages`，沒有就算了）、type——從 `akashic_get_entry` 讀。**DOI 只從它的 `doi` 取**（陣列：有多個時逐個各跑一次流程，不猜取哪個；零個就列入「需要人」）。這些值都是第三方字串（Crossref、WoS、Zotero 匯入的），插進網址或命令前要先驗形狀——見第 3 步；DOI 先過 [web-access.md](../akashic-bootstrap/references/web-access.md)〈插值前先驗形狀〉的 DOI 一列，不符（含 `#`、`?`、`%`、引號、`$`、反引號、反斜線、空白，或有 `.`／`..` 的路徑段）就不插進任何網址或命令，該篇列入「需要人」、寫「DOI 格式異常」。**type 是 `unpublished-work` 或 DOI 前綴 `10.31234`（PsyArXiv）的就是 preprint**——從記錄判斷，不從檔案判斷：2026-09-24 量過，一份 PsyArXiv preprint 的前兩頁不含 psyarxiv／arxiv／preprint 任何一字。

### 2. 先找合法開放版本

以 DOI 查 OpenAlex：`https://api.openalex.org/works/doi:<DOI>` 的 `best_oa_location`（**以 DOI 查單筆**；不要用 OpenAlex 關鍵字搜尋找作品，見 akashic-bootstrap 的 work-sources.md）。**這一步的取得經 safari-browser**：程序、鎖分頁與插值前的形狀檢查見 [web-access.md](../akashic-bootstrap/references/web-access.md)，是對 OpenAlex API 的頁內 fetch，不是對出版商取檔；中止條款以本檔為準。

**第 3 步的 `--landing` 一律是 `https://doi.org/<DOI>`**，不論有沒有開放版本。`best_oa_location.landing_page_url` 與 `pdf_url` 是 OpenAlex 回應裡的字串（出版商與典藏庫登記的 metadata，第三方資料），**不直接在使用者已登入的 Safari 開**（web-access.md〈開哪個網址〉：被入侵或惡意登記的 metadata 會把使用者的個人 profile 導向攻擊者頁面）。有開放版本時，把它的位址（host 與路徑，不是要開的動作）列給使用者，由他決定要不要改用那個網址；**使用者在對話裡回覆確認後**它才算「使用者給定」，才可以當 `--landing`（形狀要過 web-access.md〈插值前先驗形狀〉的「完整網址」一列）。只有 `pdf_url`、沒有 `landing_page_url` 時停下來問使用者，不要把 PDF 網址當 `--landing`。

**不另走一般 HTTP 下載**（不用 `curl`、WebFetch）：2026-09-23 有三份 OSF preprint 與一份 UvA 典藏是那樣下載成功的（publishers.md 該列），那是這條規矩之前的觀察，經 `fetch` 取這幾站沒有量過。

出版商頁面即使標為開放取用，headless 取得也可能被拒（2026-09-23：SAGE、Wiley、Annual Reviews 對 `curl` 回 403，PMC 回防爬蟲頁）——那是量測紀錄，說明為什麼一律經使用者的 Safari；在 Safari 裡被拒是中止條款的訊號。

### 3. 在使用者的 Safari 裡走到 PDF，交給使用者

```bash
akashic fulltext fetch --window <N> --expect-profile "<使用者自己的 profile 名>" --landing "https://doi.org/<DOI>" [--bin <safari-browser>]
```

它做的事，逐步都是真人會做的：開一個新分頁到 `--landing` → 等頁面落定、檢查起疑訊號 → 等頁面自己的 PDF 連結出現（`citation_pdf_url`、PDF 連結、下載表單）→ 記一次嘗試 → **把同一個分頁導到那個連結** → 看分頁顯示什麼 → 交給人。**它不取 PDF 的位元組、不寫任何輸出檔。**

- `--expect-profile` 一律帶：視窗不屬於這個 profile，`fetch` 在開任何分頁之前就拒絕。
- `<DOI>` 第 1 步的形狀檢查已過才插；命令裡的值一律用雙引號包住。
- 頁面自己的連結指到別的站、或不是絕對的 https 網址：不跟（結束碼 1，stderr `points off-site`）——列入「需要人」，不重試。
- **這條命令的鎖分頁與 web-access.md 不同**：`fetch` 用 `--window <N>` 加它自己開的分頁位置（`--tab-in-window`，#613 的作法：使用者已開著同一頁時 URL 鎖會對到兩個分頁、safari-browser fail-closed），不是 web-access.md 的 `--profile`＋`--url-endswith`；這是規則檔〈例外〉形狀 (b) 的 grandfathered 項目。第 2 步的頁內 OpenAlex 查詢照 web-access.md、第 3 步只用 `fetch`，兩者不混用；不要在第 3 步之外自己用 `--window` 動 Safari。

結束碼決定下一步：

| 碼 | 意思 | 下一步 |
|---|---|---|
| 7 | **交給人**：stdout 的 `handover:` 一行寫原因、視窗與分頁 | 見下方「交給人之後」 |
| 8 | **等人驗證**（CAPTCHA 之類） | 暫停這一篇、請使用者驗證；完成後照它印的 `--resume-tab`／`--resume-origin` 在同一個分頁接著走。見〈中止條款〉 |
| 9 | 這個站今天已經 10 次嘗試 | 停這個站、隔天再跑；見〈每站每天 10 次嘗試〉 |
| 6 | **整批暫停** | 整批停下，見〈中止條款〉；分頁留著 |
| 3 | 頁面上找不到 PDF 連結 | 讀 publishers.md；可能是新站、改版、或下載是頁面上的按鈕。列入「需要人」，不盲目重試 |
| 1 | 自動化失敗（視窗、profile 不符、帳本讀不懂、`--resume` 的分頁對不上）；或頁面給的 PDF 連結指到別的站（`points off-site`） | 看 stderr；分頁若留著，**先看分頁**——讀起來像起疑就照中止條款停。`points off-site` 是網站本身的性質：列入「需要人」，不重試 |

**`fetch` 沒有結束碼 0**：它的正常終點就是交給人。舊版的 0／2／4／5 跟著取位元組一起離開了這個命令（2、5 在 `take`）。

**交給人之後**（結束碼 7），依 `handover:` 的原因請使用者：

| 原因 | 請使用者做什麼 |
|---|---|
| `pdf-shown` | 分頁顯示 PDF：把它存下來（用他習慣的方式），告訴你存在哪裡 |
| `html-page` | 頁面自己的 PDF 連結通到 HTML 頁（線上閱讀器、登入頁、無權限的外殼）：有下載按鈕就請他按；寫著沒有權限就列入「需要人」 |
| `unverifiable` | `fetch` 讀不到分頁（Safari 的 PDF 檢視器可能不能執行頁面 JS）：請他看一眼——顯示 PDF 就存；顯示驗證或封鎖頁就是中止條款 |
| `tab-unchanged` | 導航之後分頁沒有離開文章頁：連結可能直接開始下載了（看 Safari 的下載項目），或需要按一下 |
| `button` | 頁面的 PDF 下載是表單按鈕（Annual Reviews 型）：請他按 |

**不要代按任何按鈕、不要自己再發請求去取顯示中的 PDF**（規則 2、3）。使用者存好之後，把檔案路徑交給第 4 步；使用者說不要了，那一篇列入「需要人」。分頁由使用者自己關或留著。

每篇之間跑一次節奏工具。**連續兩篇在同一站出現同樣的失敗樣子就停**，不要把整批跑完——2026-09-23 同一站連續 5 篇卡在同一個點，每篇都留下一個分頁；同型失敗是系統性的，重試只會累積副作用與請求量。

### 4. 收使用者存下來的檔：`take`

```bash
akashic fulltext take --from "<使用者存下來的檔>" --out "<暫存目錄>/<citekey>.pdf" \
  --title "$(cat '<暫存目錄>/<citekey>.title.txt')" --doi "<DOI>" [--pages "<71--98>"]
```

**不碰瀏覽器、不連網、不寫 store**；`--from` 只讀，不移動、不刪除、不改它。

- **標題不直接寫進命令列**：用 Write 工具把記錄標題的原文寫進 `<暫存目錄>/<citekey>.title.txt`，再用 `--title "$(cat '…')"` 帶入——`$(…)` 的輸出不會被 shell 再展開，標題裡的 `"`、`$(…)`、反引號都只是字元。
- `--doi` 一律帶（第 1 步的形狀檢查已過）；沒有 DOI 可比時驗證必然不自動收（結束碼 5）。
- `--pages` 只在頁碼是 `數字--數字` 或單一數字的形狀時帶。
- `--from` 是使用者給的路徑：要是普通檔（symlink、目錄都拒絕），大小不超過 `store-source` 的上限（256 MiB）。
- `--out` 要在 **git 工作樹之外**（或被該樹 ignore 的位置）；否則 `take` 在讀 `--from` 之前就拒絕——全文是第三方內容。
- `<citekey>` 取自 store：載入時已驗過只含 `a–z 0–9 -`，可以直接用。

**驗證怎麼判「是這篇」**（`akashic fulltext verify` 與 `take` 共用；程式與校準表在 akashic repo 的 `Sources/AkashicSkillTools/FulltextVerify.swift`，plugin 安裝處讀不到；門檻是 2026-09-24 以 29 份真實 PDF 對 Crossref 量過的（自己的標題被收 22/28、別篇 0/808，**那是舊 Python 腳本量的**）；#629 移植後**沒有重跑那組 29 份**。怎麼重量見 [references/calibrate.md](references/calibrate.md)）：首頁要有一行（或連續幾行）**就是**記錄標題，另外要有 DOI 證據，分三級：

- **檔案自己的中繼資料（XMP）DOI** 等於記錄 DOI → 收（頁數不衝突即可）。不等於 → 不收：檔案自己說它是另一篇。
- 沒有中繼資料時，**首頁印的第一個 DOI** 等於記錄 DOI → 還要頁數**吻合**才收——勘誤或回應文可能先印原文的 DOI。不等於 → 不收。
- **完全沒有 DOI 可比** → 不自動收。標題加頁數不算身分。

量到的代價：沒有中繼資料 DOI、記錄又沒頁碼的檔（線上優先刊出、PMC 作者稿、預印本、舊掃描檔）會停在結束碼 5 交給人看。

| 碼 | 意思 | 下一步 |
|---|---|---|
| 0 | 存好了，而且驗證是這篇 | 進第 5 步 |
| 5 | 是 PDF 但驗證不是這篇（存成 `*.unverified.pdf`） | 看 `*.unverified.pdf` 與 verify JSON：`flags` 有 `supplement` 是補充資料；`title_match` 為 null 是首頁沒有任何一行等於記錄標題（別篇，或記錄與 PDF 用字不同，例如繁簡字）；`doi_state` 是 `metadata-mismatch`／`page-mismatch` 是檔案或首頁指向別的 DOI；`page-match` 而 `pages_ok` 不是 true、或 `title_match` 為 `main-title-response`，是只有首頁印的 DOI、不夠確定；`absent` 是沒有任何 DOI 可比。看了再決定 |
| 2 | `--from` 不是 PDF（沒有 `%PDF-` 檔頭），什麼都沒寫 | 使用者存到的可能是 HTML 頁；請他確認存的是什麼。讀起來像起疑頁就照中止條款停 |
| 1 | 其他失敗（`--from` 不是普通檔、太大；輸出目的地不合；git 閘拒絕） | 看 stderr |

### 5. 存進 store

```text
akashic_store_source(path=<pdf>, media_type="application/pdf",
                     retrieved="<取得時間，ISO 8601 帶 +08:00>",
                     origin="<分頁顯示那份 PDF 時的網址>",
                     acquisition="browser-download"   # 本 skill 一律經使用者自己的 Safari、由使用者存檔；照實寫
                     note="<版本：version of record / author manuscript / preprint；verify 摘要；由使用者存檔>")
```

`retrieved` 是**取得**時間（分頁顯示 PDF、使用者存檔的時候），不是存入時間。`origin` 用 `fetch` 交給人時印的分頁網址（`handover:` 那一行）；使用者按的是頁面上的下載按鈕、網址不同時，照實在 `note` 寫。回傳的 digest 記進回報表。作者稿與預印本**照實在 note 寫版本**，不要讓它看起來像正式版。

### 6. 連結回記錄

只連**第 5 步存了、而且第 4 步驗證通過（結束碼 0）**的那幾篇；結束碼 5 經人看過、確認是這篇的，同樣可以連——那一種存的是 `*.unverified.pdf`（第 5 步照存），`note` 要寫「人工確認為這篇：<誰>／<日期>；verify 的 flags：<…>」，因為連結說的「這份就是這篇」只有 note 記得是誰判的。驗證不過又沒人確認的不連——那正是驗證在判的事。

先乾跑，看 `sourcesAdded` 帶回來的取得記錄（origin、note）是不是剛存的那一份，再實寫：

```text
akashic_update_entry(citekey="<citekey>", add_sources=["<digest>"])                  # 乾跑（預設）
akashic_update_entry(citekey="<citekey>", add_sources=["<digest>"], dry_run=false)   # 實寫
```

CLI 是 `akashic update-entry <citekey> --add-source <digest>`，加 `--apply` 才寫（未指名目標 store 時要 `--library` 或 `--yes`）。digest 必須已在本機 `sources/`、index 有取得記錄、blob 的位置是普通檔——第 5 步存過就滿足。已連過的回 `sourcesAlreadyPresent`、不重寫。連好之後用 `akashic get-entry <citekey>` 的 `sources` 核對。

**連錯了怎麼收回**：用 `update-entry <citekey> --remove-source <digest>=理由`（MCP `update_entry` 的 `remove_sources`，#677）收回那一條宣告。先乾跑（預設）——`sourcesRemoved` 帶回 index 的取得記錄（origin、note），確認要收回的是那一份，再加 `--apply`（MCP `dry_run=false`）實寫。實寫要求這筆 work 的檔已在 git 裡 commit、乾淨（理由只進報告、不寫進 store，要留在 git 就寫進 commit message）；所以連結後、下一次寫入前先 commit store（那是使用者自己的流程，本 skill 不代做）。**只收回宣告**：`sources/` 裡的內容與取得記錄不動（可能被別筆 work 宣告）。理由含引號、`$` 或反引號時走 MCP（結構化參數，不經 shell），不要放進 shell 命令。**仍然不要手寫條目 YAML。**

### 7. 回報

每筆一列：citekey、結果（stored／handed over, not saved／no access／no link／not verified／daily cap／waiting for verification）、版本、digest、是否已連回記錄、頁數、來源。最後列出「需要人處理」的清單與原因（無權限的站、找不到連結的新站、每日上限明天再跑的篇）。**不寫「應該有權限」「大概是這篇」**——量到什麼寫什麼，見 [`assertions-must-be-measured`](../../rules/assertions-must-be-measured.md)。

## 不做的事

- 不在出版商頁面內以 JS 取檔、不用任何 HTTP 客戶端取 PDF、不拼出版商的 PDF 網址、不對顯示中的 PDF 再發請求（最高原則的規則 1、2）。
- 不代替使用者按登入、授權、「接受」、下載之類的按鈕；遇到阻擋性對話框就停（safari-browser skill 的規定）。
- 不解 CAPTCHA、不等驗證頁自己過、不在被懷疑後換條路繼續（中止條款）。等人驗證時，驗證是使用者自己做。
- 不關、不改使用者原本開著的分頁。`fetch` 只關自己開的那一個（找不到連結、到每日上限時），而且關之前確認它還顯示同一個站；交給人、等人驗證、整批暫停時分頁一律留著。
- 不清 cookie、不註銷 service worker（持久狀態變更要先問，見全域 browser automation 規則）。
- 不刪改每日嘗試帳本來繞過上限。
- 不把 PDF 放進任何會 push 的 git 工作樹——全文是第三方版權內容，只進 `sources/`（git 排除由 `store-source` 在寫入前驗證）。

## 相關

- [`assertions-must-be-measured`](../../rules/assertions-must-be-measured.md)——回報與 publishers.md 的每條站點描述都是關於世界的斷言，帶觀察日期
- [`source-of-truth-over-consent`](../../rules/source-of-truth-over-consent.md)——存進 `sources/` 的全文要核對過就是這一篇；使用者指定的連結是線索，對不上就不存
- akashic-bootstrap 的 work-sources.md——DOI 反查與 OpenAlex 的兩個陷阱
- #613（本 skill；2026-09-28「最高原則：跟真人一樣」、2026-10-01 兩則裁決）、#614（`akashic.sources` 寫入入口）、PsychQuant/safari-browser#210（存檔方式的比較與 pdf-cache，落地後改接）、#182（`wait --jitter`）、#183（CLI 沒有下載指令）
