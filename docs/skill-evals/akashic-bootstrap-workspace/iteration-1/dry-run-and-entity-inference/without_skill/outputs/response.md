三篇都已加進 akashic store，並通過 `validate` / `doctor` 檢查，`export-bib` 也能正常輸出：

## 1. Fourier analysis of spatial point processes
- **Citekey**：`yang2026fourier`
- **作者**：Junho Yang（中研院統計所）、Yongtao Guan（香港中文大學（深圳）data science 學院）
- **期刊**：Bernoulli, 32(1), 2026-02-01
- **DOI**：[10.3150/25-bej1862](https://doi.org/10.3150/25-bej1862)

## 2. A Generalized Mean Approach for Distributed-PCA
- **Citekey**：`jou2026generalized`
- **作者**：Zhi-Yu Jou、Su-Yun Huang（皆中研院統計所）、Hung Hung（台大健康數據分析與統計研究所）、Shinto Eguchi（統計數理研究所，日本）
- **期刊**：Journal of Computational and Graphical Statistics, 35(2), 685–693, 2026-04-03
- **DOI**：[10.1080/10618600.2025.2561234](https://doi.org/10.1080/10618600.2025.2561234)

## 3. Pseudo datasets explain artificial neural networks
- **Citekey**：`chu2025pseudo`
- **作者**：Yi-Chi Chu、Yi-Hau Chen、Chao-Yu Guo
- **期刊**：International Journal of Data Science and Analytics, 20(2), 1263–1304, 2025-08
- **DOI**：[10.1007/s41060-024-00526-9](https://doi.org/10.1007/s41060-024-00526-9)

---

### 怎麼查到、怎麼加的

使用者只給了標題（其中第一篇有附註「Bernoulli, 2026」），沒給作者/期刊細節，所以我先用
Crossref API（`api.crossref.org/works?query.bibliographic=...`）逐篇比對標題找到精確 DOI，
再用該 DOI 抓完整 metadata（作者、卷期頁碼、ISSN、出版日期）核實，避免只憑標題猜測。

這個 CLI（`akashic`）**沒有**「新增一筆文獻」的子命令——它只有 `import-zotero` / `import-wos`
兩種匯入管道，手動新增文獻的路徑是照 `docs/store-format.md` 的 v2 entities 規格（`format: 4`），
直接在 `entities/` 下手寫 `<UUID>.yaml`：

- 檔名＝新配發的 UUID，內容第一行是**裸形狀標籤** `work:`（value 為空），
  底下平接 `id` / `citekey` / `type` / `title` / `authors` / `date` / `fields`。
- `citekey` 依專案規則生成：小寫第一作者姓 + 年份 + 標題首個實詞（跳過冠詞/介系詞）。
- 三篇作者目前都是**未解析**（`literal:` 而非 `key:`）——store 裡沒有任何既有 person 記錄
  跟這些姓名對得上（含 Yi-Hau Chen，雖然 `chen2020association` 那篇也掛他名字，但同樣是
  literal，尚未有 person 檔可連），依專案「絕不自動合併」的紀律，不代為建 person 記錄或代為
  猜測合併，留給 `akashic bootstrap-people` / `resolve-people` 之後人工處理。

寫完三個檔後跑了：

```
akashic validate --library <store>   # ✓ 15 entries、12 people、0 libraries 全部通過
akashic doctor   --library <store>   # entries: 15（含新三筆）、重建 index
```

`akashic query --author Yang` 與 `akashic export-bib --citekeys yang2026fourier,jou2026generalized,chu2025pseudo`
都能正確撈到新增的三筆，biblatex 輸出格式也正常。

### 需要你之後確認的地方

- 三篇的作者姓名目前都存成 literal（原始字串），沒有連到任何 person 記錄——如果你之後要用
  `akashic bootstrap-people` 建人物檔或用 `resolve-people` 手動歸戶，這三篇會被排進候選。
- 第 2、3 篇的「date」我用的是**印刷版**日期（分別是 2026-04-03、2025-08），不是更早的
  online-first 日期（分別是 2025-10-24、2024-04-10）——因為卷期頁碼都已經定案，用印刷版日期
  比較符合正式引用慣例；如果你偏好用 online-first 日期，我可以改。
