# 外部網頁與 web API 一律經 safari-browser 取得

使用者 2026-09-24（+08:00）在 #617 規劃時定調：「Sources 中並沒有 HTTP client，可以讓她仰賴
safari-browser，這可以是整個專案預設的」。

**本 repo 的本體是離線的**：`Sources/` 內沒有任何 HTTP client（2026-09-24 量：`URLSession`／
`URLRequest` 0 處）。對外查詢（OpenAlex、Crossref、ORCID、DOI 解析、出版商頁面）一直是 skill
層的事；本規則把「skill 層用什麼去拿」定成一條路徑。

## 規則

1. **skill 為了取得資料而讀外部網頁或 web API，一律經 safari-browser。** SKILL.md 與它的
   references 文件寫的取得指令，是 safari-browser 的指令，不是 `curl`、`WebFetch` 或裸 URL。
2. **`Sources/` 不新增 HTTP client。** 需要外部資料的能力，由 skill 經 safari-browser 取得後，
   以本機檔案交給 `akashic` CLI 處理（見 [swift-is-the-implementation-language.md](swift-is-the-implementation-language.md)
   的放置表）。

## 使用紀律（每一條都有踩過的理由）

- **分頁以 `--profile` ＋ `--url-exact` 鎖定，網址帶一次性 fragment**：
  `LOCK=(--profile "<使用者的 profile>" --url-exact "<開分頁時用的完整網址>#akashic-<隨機碼>")`，
  再用 `"${LOCK[@]}"`（陣列：zsh 不對未加引號的變數分詞）。fragment 不送伺服器，只讓這把鎖
  對得到唯一的分頁。**不要**用 `--url <子字串>`：它取第一個符合的分頁、而且跨所有 profile，
  別人的 session 開著同一站就會被選中（#617 verify）。**也不要**用 `--window N --tab-in-window T`：
  視窗編號依前後順序排，使用者一切換就漂移（#617 落地時實際發生）。
- **shell 變數不跨 Bash 呼叫保留**：一次取得的所有步驟寫在同一次呼叫裡，或每次呼叫把 profile
  與網址寫成字面值；`LOCK` 若是空的，safari-browser 會退回 front tab。
- **只碰「個人」profile 的分頁。** 這台機器的 Safari 有其他人的 profile，那些是別人的 session。
- **中止條款**：網站一出現「懷疑是自動化」的訊號（驗證挑戰、403／429、access denied、
  unusual traffic），**整批停止**、分頁留著、不重試、不換來源。實作範例是
  `plugin/skills/akashic-fetch-fulltext/`（結束碼 6）。
- **讀大型回應**：頁內 `fetch` 存進 `window` 變數（**每次請求換一個新的變數名**）→ `wait --js`
  等完成 → `js --large --output` 讀出，不依賴頁面渲染後的文字；讀回後**核對內容身分**（例如
  回傳的 id 就是請求的 id）。#617 校準時有一批讀到上一批的結果、結束碼全為 0
  （PsychQuant/safari-browser#190）。範例見 `plugins/akashic-discovery/skills/akashic-work-references/`。
- **持久狀態變更先告知**：清 cache、註銷 service worker、改 cookie／storage 要先說明並取得同意。

## 例外：可以不經 safari-browser 的取得指令（封閉列舉，只有一類，不得依性質相似類推第二類）

1. **本規則成文前已存在的檔（grandfathered）**，逐檔列在下方〈既有檔〉。可以修 bug；不得新增
   同類指令，也不得在新 skill 裡照抄。遷移由 #634 追蹤，改完一檔就從清單拿掉。

## 不適用（同樣是封閉列舉，只有三類）

1. **開發與發布工具鏈自身的網路操作**——`git`、`gh`、`swift` 的套件解析、`claude plugin`、
   `xcrun notarytool`。它們不是 skill 在「取得資料」，是工具在做自己的工作。
2. **本機檔案與本機工具**——`pdftotext`、`akashic` CLI、`akashic-guards`。沒有網路。
3. **使用者本人在瀏覽器上的操作**——登入、授權、付費牆後的點擊。那是人的動作；skill 不代按
   登入或授權按鈕。

## 既有檔（grandfathered，2026-09-24 量、2026-09-25 補量）

量法（2026-09-25 #617 verify 放寬——原量法只看 SKILL.md 與 references、不看 `scripts/`，也不認
ORCID／doi.org，漏了 3 個會直連的檔）：

```bash
grep -rlE 'api\.(openalex|crossref)\.org|pub\.orcid\.org|api\.orcid\.org|https?://(dx\.)?doi\.org/|curl |WebFetch|urllib\.request|requests\.get|URLSession' \
  plugin/skills plugins/*/skills | grep -vE '__pycache__|/tests/'
```

命中 13 個檔，其中 2 個不算：`akashic-fetch-fulltext/scripts/fetch-fulltext.sh`（只解析 doi.org 字串，取得
走 safari-browser）與 `akashic-work-references/SKILL.md`（網址交給 safari-browser 開）。其餘 11 個：

- `plugin/skills/akashic-bootstrap/references/person-sources.md`（ORCID）
- `plugin/skills/akashic-bootstrap/references/work-sources.md`
- `plugin/skills/akashic-bootstrap/scripts/crossref_match.py`（`urllib.request` 直連 Crossref）
- `plugin/skills/akashic-disambiguate/SKILL.md`
- `plugin/skills/akashic-disambiguate/references/ambiguity-traps.md`
- `plugin/skills/akashic-fetch-fulltext/SKILL.md`
- `plugin/skills/akashic-fetch-fulltext/scripts/calibrate_title_match.py`（`urllib.request` 直連 Crossref）
- `plugin/skills/akashic-venue-works/references/site-access.md`
- `plugin/skills/akashic-verify-person/SKILL.md`
- `plugin/skills/akashic-verify-person/references/verification-traps.md`
- `plugin/skills/akashic-verify-venue/SKILL.md`

其中 `akashic-fetch-fulltext` 與 `akashic-verify-person` 已部分使用 safari-browser；命中的是仍寫著
裸 URL 或其他路徑的段落。這張清單只減不增——「不增」指的是不得新增新的直連檔。2026-09-25 補列的 3 個檔在本規則成文前就存在，是第一次的量法漏掉的（沒掃 `scripts/`、不認 ORCID），補列是更正量測，不是放寬例外。

## 為什麼

1. **本體已經是離線的**。把 HTTP client 加進 `Sources/` 是架構上的改變，不該為了某一個 skill
   方便就發生；所有外部取得都在 skill 層，路徑統一才看得清楚。
2. **Safari 帶著使用者的 session 與一般瀏覽器指紋**。2026-09-17 實測：Bargh 等 (1996)、
   Greenwald 等 (1998)、Gignac 與 Zajenkowski (2020) 的摘要，PsycNet 回 loading 頁、
   ScienceDirect 回 403、OpenAlex 一篇空白一篇對錯篇，開 Safari 則都讀得到（使用者全域規則
   「網頁抓不到就開 Safari」記載的事例）。
3. **只有一條路徑，中止條款才涵蓋得到**。fetch-fulltext 的「懷疑是自動化就整批停」只作用在
   它自己走的那條路；若同一個 repo 裡還有 `curl` 與 `WebFetch` 在跑，同一個網站會從別的路徑
   繼續被打。

## 觸發過的實例

| 日期 | 實例 | 處置 |
|---|---|---|
| 2026-09-24 | #617 規劃時原打算照其他 skill 的慣例，把 OpenAlex 取得寫成 `curl` 指令；使用者指出 `Sources/` 本來就沒有 HTTP client，應仰賴 safari-browser 並設為專案預設 | 成文為本規則；`akashic-work-references` 從第一版起就經 safari-browser；既有 8 檔列為 grandfathered（#634） |
| 2026-09-25 | #617 verify 指出三件事：規則推薦的 `--url` 鎖法會跨 profile 取分頁；grandfathered 清單的量法漏了 `scripts/` 與 ORCID（3 個直連檔未列）；新 skill 的建檔交給 bootstrap，而 bootstrap 仍直連 Crossref | 鎖法改為 `--profile`＋`--url-exact`＋一次性 fragment；量法放寬並補列 3 檔；SKILL 寫明 bootstrap 那段不在其中止條款範圍內（#634） |
