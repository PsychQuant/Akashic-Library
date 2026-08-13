## he2025personalized 缺 DOI — 已補上

查到這篇的正確資訊：

- **標題**：Personalized cancer treatment strategies incorporating irreversible and reversible drug resistance mechanisms
- **作者**：Wei He, Matthew D. McCoy, Rebecca B. Riggins, Robert A. Beckman, Chen-Hsiang Yeang
- **期刊**：npj Systems Biology and Applications
- **出版日期**：2025-07-03（與 store 裡記的 `2025 JUL 3` 一致）

**CHOSEN_DOI: 10.1038/s41540-025-00547-5**

### 重要提醒：這篇有兩個 DOI，不要搞混

透過 Crossref 查詢發現同一篇論文其實對應**兩筆 Crossref 紀錄**：

| 版本 | DOI | 出處 | 日期 |
|------|-----|------|------|
| **正式期刊版**（已選用）| `10.1038/s41540-025-00547-5` | npj Systems Biology and Applications | 2025-07-03 |
| Preprint 版（未選用）| `10.1101/2024.11.03.621749` | bioRxiv | 2024-11-04 |

Store 裡這筆條目的 `journaltitle` 已經填 `NPJ SYSTEMS BIOLOGY AND APPLICATIONS`、`date` 是 `2025 JUL 3`，代表這筆本來就是指向**已發表的期刊版本**，而不是 bioRxiv 那篇 preprint（發表日期是 2024 年 11 月）。所以正確補上的是 `10.1038/s41540-025-00547-5`，**不是** bioRxiv 的 `10.1101/2024.11.03.621749`。這兩個 DOI 指向內容幾乎一樣（同標題、同作者），純靠標題比對很容易誤植成 preprint 版，這裡是用期刊名 + 日期去對，才選對版本。

### 已執行的變更

直接編輯了 entity YAML（此 CLI 版本沒有 `edit`/`set-field` 之類的 subcommand，只能改檔案再重建 index），在 `fields:` 底下加了一行：

```yaml
fields:
  doi: 10.1038/s41540-025-00547-5
  journaltitle: NPJ SYSTEMS BIOLOGY AND APPLICATIONS
```

改完跑了 `akashic doctor` 重建 index、`akashic validate` 驗證 schema，兩者都乾淨通過（12 entries、12 people、0 quarantine/error）。

### 驗證方式

用 Crossref API（`api.crossref.org/works?query.bibliographic=...`）查詢比對標題、作者、期刊名、出版日期，五個欄位全部吻合，信心很高。沒有硬闖 Nature.com（該站對未登入請求會導到認證頁，拿不到內容），但 Crossref 本身就是 DOI 註冊機構的權威資料源，足以確認。
