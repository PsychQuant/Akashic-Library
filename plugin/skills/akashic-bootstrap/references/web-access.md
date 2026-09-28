# 經 safari-browser 取得外部網頁與 web API

本 plugin 的 skill 讀外部網頁或 web API——OpenAlex、Crossref、Europe PMC、ORCID、ROR、ISSN Portal、Unpaywall、OpenLibrary、出版商頁、`doi.org`——**一律經 safari-browser**：不用 `curl`、不用 WebFetch、不用 agent-browser、不自己寫 HTTP 請求。這是 Akashic-Library 的專案預設，規則寫在 repo 的 `.claude/rules/web-access-via-safari-browser.md`（該 repo 為 private，plugin 安裝處讀不到）。**本檔只寫怎麼做，不重寫為什麼**：理由、例外清單、哪些檔還沒遷移都在那條規則裡。各 skill 與 references 引用本檔，不各抄一份——抄出去的副本會各自演化。

各處寫的端點網址（例如 `https://api.crossref.org/works/<doi>`）是**要取的位址**：照本檔的程序取，不是給 `curl` 或 WebFetch 的參數。

本 plugin 還有兩處尚未遷移：`akashic-bootstrap/scripts/crossref_match.py` 與 `akashic-fetch-fulltext/scripts/calibrate_title_match.py` 自己以 `urllib.request` 直連 Crossref（移植成 `akashic` CLI 子命令由 #629 追蹤）。這兩處各自在描述它們的地方寫明走的是別的路，**不在下面中止條款的涵蓋範圍內**。`akashic-verify-venue` 的三源查詢段自 b11c R1（#595）起經本檔取得；它的第 4 源（出版商頁）不抓不讀，瀏覽器契約仍待使用者裁決（#593）。

## 開始前

1. 先載 `safari-browser` skill 的 tab-locking 段。
2. **Profile**：問使用者他自己的 Safari profile 是哪一個（`safari-browser documents --json` 的 `profile` 欄位列出有哪些），**不要猜**。以下寫成 `<P>`。它必須逐字等於列出的某個值，而且不含 `"`、`$`、反引號、反斜線或換行；不符合就停下來問。其他 profile 是別人的 session，不碰。
3. **暫存目錄**：`mktemp -d`，印出路徑，以下寫成 `<W>`。回應是第三方內容，只留在這裡，不進任何 repo；承重的那幾份另以 `store-source` 存進 `sources/`（見 [writing-to-the-store.md](writing-to-the-store.md)）。
4. **shell 變數不跨 Bash 呼叫保留**（每次呼叫是新的 shell）：`<P>`、`<W>`、分頁網址每次都寫成字面值。`LOCK` 若是空的，safari-browser 會退回 front tab——那可能是別人 profile 的分頁。

## 中止條款：網站一懷疑是自動化，整批就停

判準與停下時的做法**以 akashic-fetch-fulltext SKILL.md〈中止條款〉為準**（使用者 2026-09-24 定的規矩；那一段是單一來源，本檔不重列它的訊號清單，免得兩份分岔）：整個 run 結束，不重試、不換來源、不改用別的工具繼續，**分頁留著**給使用者看；回報哪一站、哪個訊號、哪一步、完成到哪裡，何時繼續由使用者決定。拿不準就當作是。

取 API 時，那一段的訊號（含 HTTP 403／429）照樣適用，另外多這幾種形狀：

- JSON 端點回的不是 JSON（驗證頁、擋截頁）
- `fetch` 拋錯
- 回應 60 秒沒完成，或是空的

**404 不是訊號**：那是「這一站查無」，照各 skill 的「查不到」處理。其餘非 200 的狀態碼（例如 5xx）：停下回報，不重試。

頁面文字可以交給 akashic-fetch-fulltext 的 `scripts/bot_signals.py` 比對（從 stdin 讀；命中時印出訊號、結束碼 0，沒命中不印、結束碼 1）。它只認得一份清單，沒命中不代表乾淨。

## 一站一個分頁，用完整網址鎖定

每個站開一個分頁。網址尾端加一段只屬於這次的 fragment（fragment 不會送到伺服器），讓 `--url-exact` 只可能對到這一個分頁：

```bash
N=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')
echo "<這一站第一個請求的網址>#akashic-$N"
```

把印出的網址記下，以下寫成 `<U>`：

```bash
safari-browser open --new-tab --profile "<P>" "<U>"
```

頁內 `fetch` 不換頁，所以取 API 的整個流程裡分頁網址不變、這把鎖一直有效。換一個站就另開一個帶新 fragment 的分頁。

**不要**用 `--url <子字串>` 鎖（取第一個符合的分頁，而且跨所有 profile），也**不要**用 `--window N --tab-in-window T` 鎖（視窗編號依前後順序排，使用者一切換視窗，同一個編號就指到別的視窗）。

### 會轉址的頁面（`doi.org`、出版商頁、名冊）

轉址之後網址變了，`<U>` 就鎖不到。HTTP 規格要求：轉址的 `Location` 沒帶 fragment 時，沿用原網址的 fragment。所以在 `safari-browser documents --json` 裡找 `profile` 是 `<P>`、`url` 以 `#akashic-<N>` 結尾的分頁：**恰好一個** → 用它的完整 `url` 當新的 `<U>`；零個或多個 → 停下回報，**不要**退回子字串或視窗編號。各站實際上保不保留 fragment 沒有逐站量過——保留不了的站，在這個鎖法下就讀不了，交給使用者決定。

同一站要讀下一頁時不另開分頁：在鎖定的分頁裡設 `location.href = '<下一頁網址>#akashic-<N>-<序號>'`，再照上一段以新的 fragment 找回分頁。

## 插值前先驗形狀

插進網址、shell 或 JS 字串的值先驗形狀，不符合就停下來問，不要硬塞進去。這是擋注入的形狀檢查，不是合法性檢查：

| 值 | 形狀 |
|---|---|
| DOI | `` ^10\.[0-9]{4,9}/[^[:space:]'"\\$`#?]+$ `` |
| OpenAlex id | `^[WASIP][0-9]+$` |
| ORCID iD | `^[0-9]{4}-[0-9]{4}-[0-9]{4}-[0-9]{3}[0-9X]$` |
| ISSN | `^[0-9]{4}-[0-9]{3}[0-9X]$` |
| PMID | `^[0-9]+$` |
| ROR id | `^0[a-z0-9]{8}$` |

**自由文字**（標題、刊名、姓名、機構名）不經 shell 引號：用 Write 工具把原文寫進 `<W>/q-<序號>.txt`，再把它轉成百分比編碼——

```bash
python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(open(sys.argv[1],encoding="utf-8").read().strip(),safe=""))' "<W>/q-<序號>.txt"
```

輸出只含 `A–Z a–z 0–9 % . _ ~ -`，才插進網址。查詢語法本身帶引號與冒號的（例如 Europe PMC 的 `AUTH:"<姓名>"`），先把整個查詢值組好寫進檔案再編碼，不要只編碼姓名那一段。組好的完整網址插進 JS 之前再看一次：不含 `'`、`"`、反斜線、反引號、`$` 或空白。

## 取一次 API：頁內 fetch，每次換一個變數名

一次取得的五個步驟寫在**同一次** Bash 呼叫裡（開頭的守衛擋住變數遺失）：

```bash
set -euo pipefail
LOCK=(--profile "<P>" --url-exact "<U>")
K=<這次的序號，字面值，逐次遞增>
[ ${#LOCK[@]} -eq 4 ] && [ -n "$K" ] || { echo "lock/K missing" >&2; exit 1; }
safari-browser js "${LOCK[@]}" "window.__ak_$K = {done:false};
  fetch('<URL>').then(r => { window.__ak_$K.status = r.status; return r.text(); })
  .then(t => { window.__ak_$K.body = t; window.__ak_$K.done = true; })
  .catch(e => { window.__ak_$K.err = String(e); window.__ak_$K.done = true; }); return 'started'"
safari-browser wait "${LOCK[@]}" --js "window.__ak_$K && window.__ak_$K.done" --timeout 60000
safari-browser js "${LOCK[@]}" "return JSON.stringify({s: window.__ak_$K.status, e: window.__ak_$K.err || null})"
safari-browser js "${LOCK[@]}" --large --output "<W>/<檔名>" "window.__ak_$K.body || ''"
safari-browser js "${LOCK[@]}" "delete window.__ak_$K; return 'ok'"
```

- `<URL>` 與 `<U>` 同一個站（分頁開在那個站，請求才是同源）。ORCID 要回 JSON：`fetch` 帶第二個參數 `{headers: {Accept: 'application/json'}}`。
- 每一步看結束碼，第一步要印出 `started`。有 `err`、逾時、或狀態碼是上面的訊號 → 中止條款。
- **讀回後核對身分**：以 DOI 或 id 查的，回應裡的 DOI／id 要就是這次請求的；批次查詢，回應的 id 集合要就是這一批請求的。搜尋類請求沒有單一 id 可比：每次存成不同檔名，存完用 `cmp -s` 比對上一次的檔案，逐位元相同就當成讀到上一次的內容，停下回報。

為什麼每次換變數名、而且一定要核對：PsychQuant/safari-browser#190（2026-09-24 校準時第二批存下的檔案與第一批逐位元相同，每一步結束碼都是 0，成因沒有定論）。換變數名只擋得住「開始 fetch 那一步沒生效」；核對身分兩種都擋得住。

**節奏**：逐筆、不平行，請求之間跑節奏工具（同 akashic-fetch-fulltext SKILL.md〈開始前〉第 1 點：`safari-browser wait --help` 有 `--jitter` 就用 `safari-browser wait --jitter cauchy`，沒有就用那個 skill 的 `scripts/jitter.py`）。

## 讀渲染後的頁面

出版商頁、機構名冊、PsycNet 這類要讀 DOM 的頁面，照〈會轉址的頁面〉鎖定之後：

1. 等頁面載完：`safari-browser wait "${LOCK[@]}" --js "['complete','interactive'].includes(document.readyState)" --timeout 60000`。60 秒沒完成是中止條款的訊號。
2. 先查訊號：`safari-browser js "${LOCK[@]}" "return document.title + '\\n' + (document.body ? document.body.innerText.slice(0, 3000) : '')"` 的輸出交給 `bot_signals.py`，也自己讀一遍。
3. 讀取：`safari-browser js "${LOCK[@]}" --large --output "<W>/<檔名>" "<取值的運算式>"`。
4. 核對是對的那一頁：頁面上的 DOI 或標題就是這次要的。

## 其他

- **持久狀態變更先問**：清 cache、註銷 service worker、改 cookie 或 storage，先說明意圖、取得同意再做。
- **不代按登入、授權、「接受」之類的按鈕**：那是使用者本人的操作。
- **用完的分頁**：整個 run 沒有觸發中止條款時，把開過的分頁（profile 與網址）列給使用者。本檔不教關分頁的指令——safari-browser 的 `close` 能不能以 `--profile`／`--url-exact` 指定分頁沒有查證過（safari-browser 2.9.0 的 skill 文件寫 `close` 只收 `--window`），而以視窗編號指定正是上面不用的鎖法。
