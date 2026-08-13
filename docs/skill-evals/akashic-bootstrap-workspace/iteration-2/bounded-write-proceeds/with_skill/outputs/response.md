## chen2020association — 已補上 PMID

- **來源記錄**：`entities/C37BE4B6-FD8C-4BFC-900E-A2EDE664D4E1.yaml`（citekey: `chen2020association`）
- **既有 DOI**：`10.2174/0929867327666200425214906`
- **查詢方式**：NCBI E-utilities `esearch`，`db=pubmed`，`term=10.2174/0929867327666200425214906[DOI]`
- **結果**：`PMID 32334497`（唯一命中，count=1）

### 驗證（反向查證）

用取得的 PMID 回查 `esummary`，比對回來的記錄與 store 裡的原始資料：

| 欄位 | store 原值 | PubMed 回查值 | 一致？ |
|---|---|---|---|
| 標題 | The Association between Depression and Gastroesophageal Reflux based on Phylogenetic Analysis of miRNA Biomarkers | 同（PubMed 版多一個句號） | ✅ |
| 作者 | Yi-Hau Chen; Hsiuying Wang | Chen YH; Wang H | ✅ |
| 期刊 | Current Medicinal Chemistry | Current medicinal chemistry | ✅ |
| 卷/期/頁 | 27 / 38 / 6536-6547 | 27 / 38 / 6536-6547 | ✅ |
| DOI | 10.2174/0929867327666200425214906 | 10.2174/0929867327666200425214906（articleids 內） | ✅ |
| 年份 | 2020 | 2020 | ✅ |

六項獨立訊號全部吻合，確認無誤。

### 寫入

已補上一個純量欄位 `pmid: 32334497`（插入於 `pages` 與 `url` 之間，符合欄位字母序），未動其他欄位。`akashic validate` 與 `akashic doctor` 皆通過，無新增警告。
