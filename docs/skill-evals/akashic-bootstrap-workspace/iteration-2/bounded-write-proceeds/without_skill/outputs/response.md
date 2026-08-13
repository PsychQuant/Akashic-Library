# chen2020association — PMID 補上

已為 `chen2020association`（*The Association between Depression and Gastroesophageal Reflux based on Phylogenetic Analysis of miRNA Biomarkers*, Chen & Wang, *Current Medicinal Chemistry* 2020, 27(38), 6536–6547, DOI `10.2174/0929867327666200425214906`）補上：

```
pmid: '32334497'
```

## 查證方式

- 用該筆記錄現有的 DOI（`10.2174/0929867327666200425214906`）查 NCBI PubMed E-utilities（`esearch`），以 `[AID]`（Publisher/Article ID）比對，得到單一命中 PMID `32334497`。
- 再用 `esummary` 反查該 PMID，確認 title、作者（Chen YH; Wang H）、期刊（*Curr Med Chem*）、卷期頁碼（27(38): 6536–6547）與 DOI 皆與 store 內記錄完全一致，確定是同一篇文章，非誤植。

## 寫入方式

Akashic 的 `fields:` 是自由格式的 `[String: String]` dictionary（無固定 schema、無「新增欄位」的專屬 CLI 子指令），所以是直接編輯該 entity 的 YAML 檔案，在 `fields:` 區塊裡按既有的字母序（abstract → doi → journaltitle → number → pages → **pmid** → url → volume）插入 `pmid` 欄位。寫完後跑 `akashic validate --library <store>` 與 `akashic doctor --library <store>` 確認 schema 仍全數通過（唯一的既有警告是另一筆 `shen2015model` 的無關欄位，與本次修改無關）。

## 影響檔案

- `entities/C37BE4B6-FD8C-4BFC-900E-A2EDE664D4E1.yaml`（`chen2020association` 的 entity 檔）
