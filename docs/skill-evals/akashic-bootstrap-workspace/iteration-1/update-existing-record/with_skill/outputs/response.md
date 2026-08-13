`chen2020association` 已補上 PMID，補的值是 **32334497**。

## 判定依據

這筆記錄已經有 DOI（`10.2174/0929867327666200425214906`），所以直接照 work-sources 的決策順序，用 DOI 查 Europe PMC（`https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=DOI:"<doi>"&format=json&resultType=core`），命中 1 筆，且四項獨立欄位全部逐字對上：

| 欄位 | store 裡的值 | Europe PMC 回傳 |
|---|---|---|
| DOI | `10.2174/0929867327666200425214906` | 同（查詢鍵本身） |
| 標題 | The Association between Depression and Gastroesophageal Reflux based on Phylogenetic Analysis of miRNA Biomarkers | 逐字相同 |
| 作者 | Yi-Hau Chen, Hsiuying Wang | Chen YH, Wang H（同一組人） |
| 期刊 / 卷 / 期 / 頁碼 | Current Medicinal Chemistry / 27 / 38 / 6536-6547 | 同 |

這已經不是「相似度夠高」的模糊比對，是拿 DOI 直接查表命中，等於完全確認同一篇。

## 寫入方式

`chen2020association` 是已存在的記錄，只補一個空欄位——這種「更新既有記錄部分欄位」的操作目前沒有正規的 CLI／MCP 入口（`akashic_create_entry` / `akashic_add_person` 都是 create-only，遇到既有 key 會直接拒寫）。所以照 akashic-bootstrap skill 的指示，走 **decode → 改 → encode** 的繞法：用 store 自己的 `EntryYAML.decode` 讀進來、只在 `fields["pmid"] == nil` 時補值、再用 `EntryYAML.encode` 寫回去，讓編碼器保證位元組形狀不跑掉。

寫入前先跑過一次不寫檔的乾跑，確認 diff 只多了一行 `pmid: 32334497`（插在 `pages` 與 `url` 之間，符合欄位的字母序排列），沒有動到其他任何欄位或格式，才實際落地寫入。寫完後跑過 `akashic validate`（12 entries、12 people 全部通過）與 `akashic doctor`（12 entries、0 orphaned），確認沒有破壞其他東西。

用完的一次性 Swift script 已經刪除，沒有留在 repo 裡。
