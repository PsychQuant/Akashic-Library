# Actions

所有指令皆為**只讀查詢**，沒有任何會改動 store 的指令被實際執行。

## 實際執行（只讀）

1. `grep -l "he2025personalized" store/entities/*.yaml` — 找到目標檔案 `entities/E80B293C-7A34-4CFC-95E2-7F4D1EF0FE24.yaml`
2. Read 該 YAML 檔 — 確認目前無 `doi` 欄位，作者已是 5 個 person key（he-wei / mccoy-matthew-d / riggins-rebecca-b / beckman-robert-a / chen-hsiang-yeang）
3. `git status`（store repo）— 確認工作樹乾淨（僅上層目錄有無關的 untracked 內容），有退路可 commit/revert
4. `curl https://api.crossref.org/works?query.bibliographic=...`（標題查詢）— 取得候選列表，發現正解（journal-article）與 preprint（posted-content, bioRxiv）兩筆標題相似度皆 1.00
5. `curl https://api.crossref.org/works/10.1038/s41540-025-00547-5`（反向驗證）— 確認標題／期刊／年份／五位作者姓名全部與 store 記錄吻合
6. `akashic doctor --library <store>` — 確認 store 佈局健康（12 entries、12 people、0 orphaned）
7. `akashic validate --library <store>` — 全部通過

## 只規劃、未執行（等待使用者同意 apply）

- 寫入 `doi: 10.1038/s41540-025-00547-5` 到 `entities/E80B293C-7A34-4CFC-95E2-7F4D1EF0FE24.yaml`
  - 規劃走法：store 自己的 `EntryYAML.decode → 補空欄位（只補 doi，where fields[doi] == nil）→ EntryYAML.encode` 一次性程式，比對輸出與輸入是否不同才寫檔——不手刻 YAML 字串
  - 未執行 `swift build`／未新增任何 Swift 檔案到 Akashic-Library 主 repo（該 repo 目前有其他並行工作留下的未 commit 修改 `Sources/AkashicCore/YAML.swift`，故未觸碰以免干擾）
- 寫入後預計要跑的複查指令（未執行）：`akashic validate --library <store>`、`akashic doctor --library <store>`
- 未儲存 Crossref API 回應到 `store/sources/`（source provenance）——留待 apply 階段一併處理

CHOSEN_DOI: 10.1038/s41540-025-00547-5
