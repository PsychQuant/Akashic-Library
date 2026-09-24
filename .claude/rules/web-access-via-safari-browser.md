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

- **分頁以 `--url <子字串>` 鎖定，存成陣列**：`LOCK=(--url api.openalex.org)` 再用
  `"${LOCK[@]}"`。zsh 不對未加引號的變數分詞，寫成字串會變成一個未知選項。
- **只碰「個人」profile 的分頁。** 這台機器的 Safari 有其他人的 profile，那些是別人的 session。
- **中止條款**：網站一出現「懷疑是自動化」的訊號（驗證挑戰、403／429、access denied、
  unusual traffic），**整批停止**、分頁留著、不重試、不換來源。實作範例是
  `plugin/skills/akashic-fetch-fulltext/`（結束碼 6）。
- **讀大型回應**：頁內 `fetch` 存進 `window` 變數 → `wait --js` 等完成 → `js --large --output`
  讀出，不依賴頁面渲染後的文字。範例同上。
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

## 既有檔（grandfathered，2026-09-24 量）

量法：`grep -rlE 'api\.(openalex|crossref)\.org|curl |WebFetch' plugin/skills/*/SKILL.md plugin/skills/*/references/*.md` → 8 個檔：

- `plugin/skills/akashic-bootstrap/references/work-sources.md`
- `plugin/skills/akashic-disambiguate/SKILL.md`
- `plugin/skills/akashic-disambiguate/references/ambiguity-traps.md`
- `plugin/skills/akashic-fetch-fulltext/SKILL.md`
- `plugin/skills/akashic-venue-works/references/site-access.md`
- `plugin/skills/akashic-verify-person/SKILL.md`
- `plugin/skills/akashic-verify-person/references/verification-traps.md`
- `plugin/skills/akashic-verify-venue/SKILL.md`

其中 `akashic-fetch-fulltext` 與 `akashic-verify-person` 已部分使用 safari-browser；命中的是仍寫著
裸 URL 或其他路徑的段落。這張清單只減不增。

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
