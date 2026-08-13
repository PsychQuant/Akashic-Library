# work 的外部來源

補完一筆論文需要的東西通常是：DOI、卷期頁、作者機構。三者的來源不同，覆蓋率差很多。

## 決策順序

```
有 DOI？
  ├─ 有 → 直接用 DOI 查 Crossref（書目）與 Europe PMC（機構）
  └─ 無 → 先用標題＋期刊＋年份查出 DOI（見下方「用標題查 DOI」），
           查到後回到上一行
```

**先拿 DOI 再拿其他。** 有了 DOI，後續每一項都變成查表；沒有 DOI，每一項都是模糊比對。實測一份 100 篇的 WoS 匯出（無 DOI 欄），補完 DOI 後卷期頁與機構幾乎是附帶取得的。

## Crossref — 書目的主力

```
https://api.crossref.org/works?query.bibliographic=<標題>&rows=5&filter=type:journal-article
https://api.crossref.org/works/<doi>
```

免費、免金鑰。請帶 `User-Agent: <你的工具>/<版本> (mailto:<你的信箱>)`——Crossref 用它區分禮貌流量，會給比較好的服務。請求之間留 0.3–0.6 秒。

**回傳的欄位**：`DOI` `title` `container-title` `volume` `issue` `page` `published` `type` `author`。

**biblatex 對應**：`issue` → `number`（不是 `issue`）；`page` 有時是 `e81105-e81105` 這種重複，前後段相同時取一段即可。

### Crossref 會回傳三種「像但不是」的記錄

這是用標題查 Crossref 最大的風險。實測 100 篇裡有 9 篇踩到：

| 型態 | 徵狀 | 處置 |
|---|---|---|
| **審稿報告** | DOI 帶 `/v1/reviewN` 後綴，`type: peer-review`，`container-title` 為空 | 剝掉後綴就是論文本體的 DOI，回查確認 |
| **preprint** | bioRxiv `10.1101/…`、Research Square `10.21203/…`、medRxiv，`type: posted-content` | 查詢加 `filter=type:journal-article` |
| **同前綴的會議摘要** | DOI 與正解只差幾碼（例：`10.1158/0008-5472.30517553` vs 正解 `…can-25-0006`） | 靠期刊名比對揪出；`type` 也常不是 journal-article |

**preprint 的標題相似度可以是 1.00**，比期刊版還高（期刊版常被編輯改標題）。所以標題相似度**單獨用一定會錯**。

### 判定門檻

四個獨立訊號合取：

```
標題相似度 ≥ 0.92  ∧  期刊名相似度 ≥ 0.75  ∧  |年份差| ≤ 1  ∧  type == journal-article
```

比對前把兩邊都正規化（轉小寫、非英數字轉空白、壓縮空白）。期刊名另外處理常見縮寫（`journal of` → `j`、去掉 `the`／`and`／`&`）。

**放寬的時機**：期刊名相似度達 1.0 且年份吻合時，標題門檻降到 0.85 是安全的——那通常是 WoS 標題帶了更正註記或截斷。實測這個放寬救回 2 筆真命中，零誤收。

### 反向驗證（寫入前必做）

拿到 DOI 後，用 `https://api.crossref.org/works/<doi>` 回查，比對標題／期刊／年份／type。方向與查詢階段相反，所以「查詢時選錯候選」這類錯誤不會一致地重複。

實測 97 筆有 1 筆未過，人工核對後發現是 WoS 標題內嵌了更正註記：

```
… in a Taiwanese population (Sep, 10.1007/s40620-025-02380-9, 2025)
```

那個 `(月, DOI, 年)` 是 WoS 的 **correction notice** 格式——DOI 反而被來源自己確認了，同時揭露該筆是更正公告而非原始論文（標題該清理）。

## Europe PMC — 作者機構的主力

```
https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=DOI:"<doi>"&format=json&resultType=core
```

`resultType=core` 才會帶 `authorList`。機構在 `author[].authorAffiliationDetailsList.authorAffiliation[].affiliation`，舊記錄則在 `author[].affiliation`——兩處都要看。

**覆蓋特性（實測 97 篇）**：命中 62 篇；命中的當中 **59 篇每位作者都有機構、0 篇完全沒有**。也就是說 Europe PMC 是全有全無——查得到就齊全，查不到就完全沒有。

**只涵蓋生醫。** 統計、數學、CS、環境類期刊查不到（`Statistics and Computing`、`Mathematics of Computation`、`Advances in Applied Probability` 等實測全滅）。

同時它也提供 `journalInfo.volume` / `issue`、`pageInfo`、`pmid`，可以補 Crossref 缺的卷期頁。

### 用 Europe PMC 查 Crossref 查不到的論文

Crossref 的 `query.bibliographic` 對很新的、作者數上百的大型合作論文常常失手。Europe PMC 的欄位搜尋更精準：

```
query=TITLE:"<標題的獨特片段>"
query=TITLE:"<片段A>" AND TITLE:"<片段B>"
```

實測三篇 Crossref 全查不到的大型論文（作者 124–143 位），用 `TITLE:` 一次命中。注意搜尋結果裡**同一篇的 preprint 版也會出現**，靠 `journalInfo` 與年份區分。

## 非生醫論文的機構：一條有明確順序的路

Europe PMC 不收的那些（統計、數學、CS、環境），要一條一條試。以下順序來自三組獨立作業各自撞出來的結果——**它們互不知情卻收斂到同一組結論**，所以這個順序可信：

| 順位 | 路徑 | 實測 |
|---:|---|---|
| 0 | **先用 Unpaywall 問「有沒有合法免費版本」** | `https://api.unpaywall.org/v2/<doi>?email=<你的信箱>`。`is_oa=false` 且 `oa_locations` 為空 → **沒有任何開放版本**，別再找 PDF，直接跳到順位 2 |
| 1 | **出版商的 open-access PDF**（`link.springer.com/content/pdf/<doi>.pdf` 之類） | 最可信——讀到的就是印刷版的作者註腳 |
| 2 | **真的瀏覽器 session**（macOS 用 `safari-browser`） | **這條路在 headless 工具全滅時仍然通**。見下方 |
| 3 | **arXiv 預印本 PDF** | 數學／統計論文常有，含完整機構與地址。**但那是預印本版本**，與出版版本可能有差異，要標明 |
| 4 | **DOAJ API**（開放取用的 Elsevier 文章） | Elsevier 自己餵的 metadata feed，離印刷版一步之遙 |
| 5 | **OpenAlex `raw_affiliation_strings`** | 最後手段。見下方的重要區分 |

### 真的瀏覽器 session 能過 Cloudflare

headless 工具（WebFetch、curl 不論什麼 UA、r.jina.ai proxy）對 ScienceDirect 全部 403；**同一個 URL 在真的 Safari 分頁裡正常載入**——因為那是帶著使用者 cookie 與（可能的）機構訂閱的真實 session。

更好的是：**ScienceDirect 把出版商自己的結構化機構資料嵌在頁面的 `<script>` JSON 裡**，包含逐字的 `source-text`：

```js
// 在該分頁執行
for (const s of document.querySelectorAll("script")) {
  const t = s.textContent || "";
  if (!t.includes("source-text")) continue;
  const out = [];
  const re = /"#name":"source-text","\$":\{"id":"[a-z]+\d+"\},"_":"([^"]+)"/g;
  let m; while ((m = re.exec(t)) !== null) if (!out.includes(m[1])) out.push(m[1]);
  if (out.length) return out;
}
```

Springer 則在 DOM：`[data-test='author-affiliation']` / `.c-article-author-affiliation__address`。

**兩個實作注意**：正則會連參考文獻裡被引用論文的機構一起撈到——**該篇自己的機構是最前面幾筆**，後面的要丟掉。以及上標編號（作者↔機構的對應）常常抽不可靠；抽不到就把機構列成「未對應」，**不要靠順序猜**。

**先別碰的**：

| 來源 | 實測 |
|---|---|
| ScienceDirect / Elsevier 網頁（headless） | **全路徑被 Cloudflare 擋**——WebFetch、帶瀏覽器 UA 的 curl、帶 Googlebot UA 的 curl、r.jina.ai proxy 全部 403。**不要反覆重試**，改走真瀏覽器 |
| AMS 的文章頁 | JS 渲染的 SPA，headless 抓到的是空殼 |
| PubMed E-utilities（非生醫論文） | 統計／數學／CS／環境期刊實測 0/4 收錄，與 Europe PMC 一致 |
| 出版商頁面的 `citation_author_institution` meta | 0/4（Springer、Elsevier、AMS、Cambridge 抽樣）——這個 Google Scholar 標準多數出版商沒實作 |
| Semantic Scholar `authors.affiliations` | 0/6 抽樣，這類論文完全沒有 |
| Crossref `author[].affiliation` | 44/97 篇有、且常只有部分作者。當補充不當主力 |

### OpenAlex：要區分「原始字串」與「推論出的機構」

OpenAlex 有兩層資料，可信度完全不同：

- **`raw_affiliation_strings`** —— 出版商提交的原始文字，OpenAlex 原樣保留。這層本質上是**鏡像**，不是判斷
- **`institutions`**（已消歧、對到 ROR ID 的機構）—— 那是 OpenAlex 的**推論**，會出錯

補機構字串時只取 `raw_affiliation_strings`，不要用它推論出的機構對應。用了要在 provenance 註明來源是 OpenAlex 而非印刷版。

**實測的兩種結果**（拿 OpenAlex 與同一篇的出版商頁面逐字比對）：

- **忠實的情形**：兩篇完全一致，包含出版商端的誤植——有一筆把「Institute of Statistical Science」寫成複數「Sciences」，出版商自己的排版資料就是那樣，OpenAlex 原樣保留。那是出版商／作者端的錯，不是 OpenAlex 的問題，但也不是該機構的正式名稱。
- **多出來的情形**：一篇的某位作者，出版商頁面列 2 個機構，**OpenAlex 給了 3 個**（多一個大學）。多出來那個無從查證。

所以 OpenAlex 可以當最後手段，但**只要出版商頁面拿得到就以它為準**——不是因為 OpenAlex 不可信，而是因為它多一層來源，而那一層會加東西。

### 先問值不值得

這條路慢且每篇都要人看。**若目的只是判定「某作者是否屬於某機構」，該機構自己的名冊或作者的 ORCID employment 往往更快更準**——而且是當事人或機構自己維護的，不必穿過出版商的排版。走出版商路線的理由應該是「需要發表當下的機構」（名冊只有現況），不是「想要更權威」。

## 附帶的腳本

`scripts/crossref_match.py` 實作了上面的比對＋反向驗證流程，可直接用或當範本改。它讀一份 `[{citekey, title, journal, year}]` 的 JSON，輸出每筆的判定（`confident` / `probable` / `needs_review`）與候選明細。
