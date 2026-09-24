---
name: akashic-work-references
description: 從一篇已在 Akashic 的論文往回追——讀它 PDF 的參考文獻、與 OpenAlex 記錄的引用清單交叉比對，逐筆判定後把兩邊都對得上的文獻建檔、以 cites 連回這篇、掛進同一個 library，其餘列成報告（#617）。當使用者說「這篇引用了哪些」「把這篇的參考文獻補進來」「往回追這篇」「backward citation」「從這篇的 reference list 找文獻」「這篇 cite 的東西進 Akashic」，或在文獻回顧中要從一篇核心論文擴充 library 時使用。**不做**：往前追（誰引用了這篇，#620）、數字編號格式的參考文獻（`[1] …`）、只憑單一來源建檔、繞過網站的自動化偵測。
---

# 往回追：一篇論文的參考文獻

給一篇種子論文，找出它引用的文獻、補進 library、以 `cites` 連回種子。兩個來源交叉：**PDF 的參考文獻段**（作者實際印出來的清單）與 **OpenAlex 的 `referenced_works`**（索引端的連結）。兩者各有自己的錯——PDF 切分會切錯、OpenAlex 會錯連與漏連——所以**兩邊對上、且經你逐筆判定**的才建檔，其餘只列報告。

分工（D3，依 `identity-is-judged-not-matched`：字串相似只能提名）：

| 段 | 誰做 | 做什麼 |
|---|---|---|
| 提名 | `akashic references extract`／`nominate`（決定論） | 切分 PDF 清單、每筆列出至多 3 個 OpenAlex 候選與分數 |
| 判定 | 你 | 逐筆決定「是不是同一篇」並寫下理由；分數只用來排序，**不自動接受** |
| 落地 | `akashic-bootstrap` ＋ `akashic_link` ＋ `akashic_libraries` | 建檔、連 `cites`、掛 library |

## 開始前

1. **CLI**：`akashic references --help` 要列出 `extract` 與 `nominate`。沒有 → 請使用者在 Akashic-Library 跑 `swift build -c release` 並把 `.build/release/akashic` 放上 PATH（發布管道缺口見 #633）。**不要**改用別的方法切分或比對。
2. **種子**：使用者給 citekey。`akashic_get_entry` 取 DOI、標題、`libraries`。**沒有 DOI 就停下來問**——沒有 DOI 就查不到 OpenAlex 那一側，兩源交叉不成立。
3. **PDF**：由使用者每次給路徑（store 取 PDF 的入口要等 #614）。
4. **Safari**：先載 `safari-browser` skill 的 tab-locking 段。外部取得一律經 safari-browser（`.claude/rules/web-access-via-safari-browser.md` 是本 repo 的專案預設）——不用 `curl`、不用 WebFetch。

## 中止條款：網站一懷疑是自動化，整批就停

OpenAlex 的回應出現下列任何一項，**整個 run 結束**：不重試、不換來源、不改用別的工具繼續，**分頁留著**給使用者看。

- HTTP 403／429，或回應不是 JSON（驗證頁、「Just a moment…」、CAPTCHA、「too many requests」、access denied）
- 分頁跑到別的網域
- 回應 60 秒沒完成、或是空的

回報：哪一步、哪個訊號、完成到哪一批。何時繼續由使用者決定。判準同 `akashic-fetch-fulltext` 的中止條款——拿不準就當作是。

## 流程

以下 `$W` 是暫存目錄（`W=$(mktemp -d)`）。PDF 文字與 OpenAlex 回應是第三方內容，**只留在暫存目錄，不進任何 repo**。

### 1. PDF → 參考文獻清單

```bash
pdftotext -enc UTF-8 "<PDF 路徑>" "$W/paper.txt"
akashic references extract --text "$W/paper.txt" > "$W/refs.json"
```

- 結束碼非零、訊息是「找不到參考文獻段」→ 看 `paper.txt` 的結尾確認標題長什麼樣，告訴使用者，停。
- 「數字編號格式…不支援」→ 告訴使用者這篇用的是編號制，本 skill 第一版不處理（D7），停。
- 讀 `warnings`：沒有年份的條目通常是兩筆併成一筆或殘留的段落文字，判定時留意。

### 2. OpenAlex → 引用清單（經 safari-browser）

在**使用者自己的 profile** 的視窗開一個分頁，鎖定它：

```bash
safari-browser documents --json      # 找使用者自己 profile 的視窗編號 N
safari-browser open --new-tab --window N "https://api.openalex.org/works/doi:<DOI>?select=id,doi,title,referenced_works"
safari-browser documents --json      # 找到新分頁的 tab_in_window T
LOCK=(--window N --tab-in-window T)  # 陣列；zsh 不對未加引號的變數分詞
```

每一次取得都用同一個頁內 fetch 讀法（`akashic-fetch-fulltext/scripts/fetch-fulltext.sh` 的模式），**每次請求換一個新的變數名**（`K` 逐次遞增，不重複用）：

```bash
K=1
safari-browser js "${LOCK[@]}" "window.__oa_$K = {done:false};
  fetch('<URL>').then(r => { window.__oa_$K.status = r.status; return r.text(); })
  .then(t => { window.__oa_$K.body = t; window.__oa_$K.done = true; })
  .catch(e => { window.__oa_$K.err = String(e); window.__oa_$K.done = true; }); return 'started'"
safari-browser wait "${LOCK[@]}" --js "window.__oa_$K && window.__oa_$K.done" --timeout 60000
safari-browser js "${LOCK[@]}" "return JSON.stringify({s: window.__oa_$K.status, e: window.__oa_$K.err || null})"
safari-browser js "${LOCK[@]}" --large --output "$W/<檔名>.json" "window.__oa_$K.body || ''"
safari-browser js "${LOCK[@]}" "delete window.__oa_$K; return 'ok'"
```

每一步看結束碼，第一步要印出 `started`。狀態不是 200、有 `err`、或檔案不是 JSON → 中止條款。

**為什麼每次換變數名、而且一定要核對 id**：2026-09-24 校準時，第二批存下的檔案與第一批**逐位元相同**，每一步都回結束碼 0，重跑沒有重現。是「開始 fetch」那一步沒生效（頁面上留著第一批已完成的 `window.__oa`），還是 `--large` 讀取讀到了上一次的內容，沒有定論。換變數名只擋得住前一種：上一批的物件不可能滿足這一批的 `wait`，失手會變成逾時報錯。**兩種都擋得住的是下面第 3 點的 id 核對**——讀回來的若是上一批，id 一定對不上。

1. 種子：`https://api.openalex.org/works/doi:<DOI>?select=id,doi,title,referenced_works` → 取 `referenced_works`（`https://openalex.org/W…` 的清單）。**先核對回來的 `title` 就是種子**——OpenAlex 以 DOI 查到錯篇時，後面全部都錯。
2. 被引文獻：每批至多 50 個 id，`https://api.openalex.org/works?filter=openalex:W1|W2|…&per-page=50&select=id,doi,title,display_name,publication_year,authorships`，每批存成 `$W/oa-<批次>.json`。**逐批、不平行**，批與批之間等一下：`safari-browser wait $(( 2000 + RANDOM % 4000 ))`。
3. **核對每一批回來的 `results[].id` 就是這一批請求的 id**，全部取完後回來的 id 聯集要等於 `referenced_works`。少了的列進報告（OpenAlex 查無）；多了或對不上的，那一批重取一次，仍不對就停下來回報。

### 3. 提名

```bash
akashic references nominate --refs "$W/refs.json" --openalex "$W/oa-1.json" --openalex "$W/oa-2.json" > "$W/nominations.json"
```

輸出：`refs[]`（每筆 PDF 條目的 `candidates`，含 `score`、`basis`、已在庫者的 `inStore` citekey）、`unnominated[]`（OpenAlex 有、沒有任何 PDF 條目提名它）、`counts`、`warnings`。

### 4. 判定（逐筆，寫理由）

對每筆有候選的 PDF 條目，決定三者之一並寫一句理由：

- **同一篇**：標題實質相同（大小寫、副標、標點差異不算），作者與年份相容。`basis` 有 `doi` 仍要看標題——PDF 的 DOI 可能被 pdftotext 斷行弄壞。
- **不是**：候選是同作者同年的另一篇（`2015a`／`2015b` 最常見）、同名不同書、書與書中章節。
- **判不了**：例如 PDF 標題被切壞、只剩作者年份。**不猜**，列進報告交給使用者。

分數高低不是判定的理由（校準：判為不是的第一名分數 0.625–0.816，判為同一篇的最低分 0.55——兩個區間重疊）。同一個 OpenAlex work 不得判給兩筆 PDF 條目。

校準看到的三種型態（2026-09-24，見〈校準〉）：

- **OpenAlex 對同一篇有兩筆記錄**：APA 舊式雙斜線 DOI（`10.1037//0022-…` 與 `10.1037/0022-…`）、JSTOR 與出版商各一個 DOI、同一本書的線上再版。同一筆 PDF 條目可以認領這幾筆——判為同一篇、**只建一筆，幾個 DOI 都記在這一筆**（#456 合併雙斜線攣生時的識別碼聯集慣例；之後 `nominate` 的 `inStore` 兩種寫法都認得）；其餘記錄列在該條目底下，不算「只在 OpenAlex」。已在庫的攣生另由 `akashic-merge-twins` 處理，不是本 skill 的事。
- **書評被當成書**：PDF 是一本書，第一名候選標題相同、但第一作者是別人、年份晚一兩年、DOI 屬期刊（`10.2307/…`、`10.1198/jasa…`）——那是書評，判為不是。書本身這時通常不在 OpenAlex 的清單裡。
- **同作者同年的兄弟作品**：同一位作者同年的兩章或兩篇，標題共用很多詞（`latent difference score … dynamic … analyses`）。只有標題實質相同才算。

### 5. 乾跑，確認後才寫

先列出將要做的事，使用者確認後才寫入：

| 類別 | 條件 | 寫入 |
|---|---|---|
| 已建檔＋已連 | 判定同一篇、有 DOI、不在庫 | 交 `akashic-bootstrap` 以 DOI 驗證建檔 → `cites` → 掛 library |
| 已在庫只連 | 判定同一篇、`inStore` 有 citekey | 只寫 `cites`（D4）→ 掛 library |
| 無 DOI | 判定同一篇但兩邊都沒有 DOI | 只列報告（D6） |
| 只在 PDF | 沒有候選，或候選全判為不是 | 只列報告 |
| 只在 OpenAlex | `unnominated`，以及判為不是、沒被任何條目認領的候選 | 只列報告——可能是 OpenAlex 錯連，也可能是 PDF 切分漏掉 |
| 判不了 | 第 4 步的第三種 | 只列報告，附理由 |

寫入：
- 建檔：把 DOI 清單交給 `akashic-bootstrap`，照它自己的驗證與乾跑流程走。它拒絕的 DOI 移到報告。
- 連結：`akashic_link(citekey: <種子>, kind: "cites", add: [<citekeys>])`。
- library（D5）：種子屬於 **1** 個 library → 對每個被連到的 citekey `akashic_libraries(action: "add", key: <該 library>, citekey: …)`；屬於 **0** 個 → 不掛；屬於**多個** → 問使用者要掛哪些（每次執行問一次）。

### 6. 報告

依上表六類各列清單：PDF 條目的 index 與作者年份、OpenAlex id、citekey、判定理由。最後一行寫計數：PDF 條目數、OpenAlex 引用數、各類筆數。

**每個數字都是這次量到的**——見 [`assertions-must-be-measured`](../../rules/assertions-must-be-measured.md)。不寫「應該都補齊了」；只在 OpenAlex 的條目寫「OpenAlex 列為引用、PDF 清單沒有對應條目」，不寫「OpenAlex 錯了」——那是還沒查證的推論。

## 已知限制

- **切分是啟發式的**：作者—年份格式以外的清單、嚴重的排版（雙欄交錯、頁首夾在條目中間且每頁不同）會切錯。`warnings` 與「只在 PDF／只在 OpenAlex」兩類就是讓這些誤差被看見的地方。
- **計分權重是起點值**（標題 0.5、第一作者 0.25、年份 0.25，門檻 0.35）。校準（下節）沒有給出調整的理由：錯誤都出在「正確的那篇不在 OpenAlex 清單裡」，不是排序錯。
- PDF 由使用者給路徑，直到 #614 讓 store 能回傳條目的 PDF。

## 校準

2026-09-24，Hamaker, Kuiper & Grasman (2015)（`10.1037/a0038889`），本 skill 端到端跑一次。只記數字與誤差分類。

| 量 | 值 |
|---|---|
| PDF 參考文獻條目（`extract`） | 63 |
| OpenAlex `referenced_works` | 68（2 批取回，68／68） |
| 有候選的 PDF 條目 | 62／63（沒有的 1 筆是軟體手冊，OpenAlex 清單裡沒有它） |
| 第一名判為同一篇 | 59／62 |
| 第一名判為不是 | 3：2 本書的第一名是它們的書評、1 章的第一名是同作者同年的另一章 |

兩邊的差額逐筆歸因（ID 層級驗算，無重疊、無遺漏）：

- **OpenAlex 68 ＝ 59 對上 ＋ 6 重複記錄 ＋ 3 錯連**。重複記錄：5 筆是雙斜線 DOI 或 JSTOR／出版商兩個 DOI 的同一篇，1 筆是書的 2020 年線上再版。錯連：3 筆都是書評被當成書（其中 1 筆是編輯書的書評，PDF 引的是書中一章）。
- **PDF 63 ＝ 59 對上 ＋ 4 只在 PDF**：2 本被錯連成書評的書、1 章 OpenAlex 清單裡沒有的書章、1 份軟體手冊。

這次校準修掉的切分誤差（`extract` 的測試 T2b、T4b）：年份區間 `(1998 –2012)` 認不得、害下一筆被併進來（修正前切出 62 筆）；頁首與版權聲明在參考文獻段只出現一次、段內計數抓不到而併進條目原文（改為全文計數）。

**一篇的校準不是準確率**。這篇是 APA 期刊、參考文獻不印 DOI；印 DOI、其他出版商排版、其他引用格式的論文會有不同的誤差型態。
