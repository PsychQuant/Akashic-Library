# 已將三篇論文加進 Akashic

依 `akashic-bootstrap` skill 的流程（先查 store 有無重複 → 查 Crossref → 四訊號驗證＋DOI 反查 → 寫入 → 驗證），已將以下三篇新增為 `work` 實體：

| Citekey | 標題 | 期刊 | 年份 | DOI |
|---|---|---|---|---|
| `yang2026fourier` | Fourier analysis of spatial point processes | Bernoulli | 2026 | [10.3150/25-bej1862](https://doi.org/10.3150/25-bej1862) |
| `jou2025generalized` | A Generalized Mean Approach for Distributed-PCA | Journal of Computational and Graphical Statistics | 2025 | [10.1080/10618600.2025.2561234](https://doi.org/10.1080/10618600.2025.2561234) |
| `chu2024pseudo` | Pseudo datasets explain artificial neural networks | International Journal of Data Science and Analytics | 2024 | [10.1007/s41060-024-00526-9](https://doi.org/10.1007/s41060-024-00526-9) |

## 驗證過程

三篇在 Crossref 的標題相似度皆為 1.00、期刊名與年份一致、type 皆為 `journal-article`，通過 skill 要求的四訊號合取門檻，並以 DOI 反查覆核無誤，判定信心高。作者暫以裸字串（`literal`）形式記錄，尚未歸戶為 person 實體——這是刻意的範圍收斂：本次任務只要求「把這三篇加進去」，作者是否對應到 store 裡的既有人物需要另一輪逐一消歧確認，不在這次的指令範圍內。

由於 store 沒有「新建單筆 work」的正規 CLI 或 MCP 入口，改採直接手寫 entity YAML（依 `YAML.swift` 的編碼器規則重建欄位順序與格式），寫入後跑過 `akashic validate`（15 筆全數通過）與 `akashic doctor`（entries 12→15）確認 store 仍是合法狀態。三篇的原始 Crossref API 回應也已依 skill 紀律內容定址存進 `sources/`，並在 `sources/index.jsonl` 留下查詢方式與時間的 provenance 紀錄。

作者歸戶與機構資料未觸碰，皆屬本次任務範圍之外。
