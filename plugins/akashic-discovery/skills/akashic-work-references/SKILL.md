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

每一次取得都用同一個頁內 fetch 讀法（`akashic-fetch-fulltext/scripts/fetch-fulltext.sh` 的模式）：

```bash
safari-browser js "${LOCK[@]}" "window.__oa = {done:false};
  fetch('<URL>').then(r => { window.__oa.status = r.status; return r.text(); })
  .then(t => { window.__oa.body = t; window.__oa.done = true; })
  .catch(e => { window.__oa.err = String(e); window.__oa.done = true; }); return 'started'"
safari-browser wait "${LOCK[@]}" --js "window.__oa && window.__oa.done" --timeout 60000
safari-browser js "${LOCK[@]}" "return JSON.stringify({s: window.__oa.status, e: window.__oa.err || null})"
safari-browser js "${LOCK[@]}" --large --output "$W/<檔名>.json" "window.__oa.body || ''"
```

狀態不是 200、有 `err`、或檔案不是 JSON → 中止條款。

1. 種子：`https://api.openalex.org/works/doi:<DOI>?select=id,doi,title,referenced_works` → 取 `referenced_works`（`https://openalex.org/W…` 的清單）。**先核對回來的 `title` 就是種子**——OpenAlex 以 DOI 查到錯篇時，後面全部都錯。
2. 被引文獻：每批至多 50 個 id，`https://api.openalex.org/works?filter=openalex:W1|W2|…&per-page=50&select=id,doi,title,display_name,publication_year,authorships`，每批存成 `$W/oa-<批次>.json`。**逐批、不平行**，批與批之間等一下：`safari-browser wait $(( 2000 + RANDOM % 4000 ))`。
3. 取完：`safari-browser js "${LOCK[@]}" "delete window.__oa; return 'ok'"`。

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

分數高低不是判定的理由。同一個 OpenAlex work 不得判給兩筆 PDF 條目。

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
- **計分權重是起點值**（標題 0.5、第一作者 0.25、年份 0.25，門檻 0.35）。校準結果見下節。
- PDF 由使用者給路徑，直到 #614 讓 store 能回傳條目的 PDF。

## 校準

（#617 S6：以 Hamaker, Kuiper & Grasman (2015) 端到端跑一次後填入——只記數字與誤差分類，不記參考文獻原文。）
