# he2025personalized 補 DOI

## Store 現況

`he2025personalized`（entities/E80B293C-7A34-4CFC-95E2-7F4D1EF0FE24.yaml）目前確實沒有 `doi` 欄位：

```yaml
work:
  citekey: he2025personalized
  type: article
  title: Personalized cancer treatment strategies incorporating irreversible and reversible
    drug resistance mechanisms
  authors:
  - key: he-wei
  - key: mccoy-matthew-d
  - key: riggins-rebecca-b
  - key: beckman-robert-a
  - key: chen-hsiang-yeang
  date: 2025 JUL 3
  fields:
    journaltitle: NPJ SYSTEMS BIOLOGY AND APPLICATIONS
```

五位作者都已是歸戶好的 person key，不涉及作者歸戶問題，純粹補書目欄位。

## 外部查詢（Crossref，用標題查）

用標題查 `api.crossref.org/works?query.bibliographic=...` 前五筆命中裡，**同時出現了正解與一個陷阱**：

| DOI | type | container-title | 年份 | 標題相似度 |
|---|---|---|---|---|
| **10.1038/s41540-025-00547-5** | `journal-article` | npj Systems Biology and Applications | 2025-07-03 | 1.00 |
| 10.1101/2024.11.03.621749 | `posted-content`（openRxiv/bioRxiv） | （無） | 2024-11-04 | 1.00 |

兩筆標題完全相同、相似度都是 1.00——**這正是 preprint 陷阱**：單看標題無法區分。套四訊號合取判準：

```
標題相似度 ≥ 0.92  ∧  期刊名相似度 ≥ 0.75  ∧  |年份差| ≤ 1  ∧  type == journal-article
```

- `10.1038/s41540-025-00547-5`：標題 1.00、期刊名與 store 的 `NPJ SYSTEMS BIOLOGY AND APPLICATIONS` 相似度 ~1.0、年份差 0（2025 JUL 3 與 store 的 `2025 JUL 3` 逐字相符）、type = journal-article ✓ 四項全過
- `10.1101/2024.11.03.621749`：type = posted-content（bioRxiv 前導版），無 container-title，年份差 1 ✗ 期刊名與 type 兩項不過

判定：**10.1038/s41540-025-00547-5** 是正解，preprint 版本予以排除。

## 反向驗證（用 DOI 回查 Crossref）

用 `api.crossref.org/works/10.1038/s41540-025-00547-5` 回查，比對回來的內容與 store 記錄完全吻合：

- 標題：逐字相符
- 期刊：npj Systems Biology and Applications（與 store 的 journaltitle 相符，僅大小寫差異）
- 出版日期：2025-07-03（與 store 的 `2025 JUL 3` 相符）
- 作者：He, Wei / McCoy, Matthew D. / Riggins, Rebecca B. / Beckman, Robert A. / Chen-Hsiang Yeang —— **五位作者與 store 記錄的 5 個 person key 一一對應、順序也一致**
- volume: 11、issue: 1（Crossref 附帶查到，store 目前未存，未列入此次寫入範圍——使用者只要求補 DOI）

五個獨立訊號（標題、期刊、年份、type、作者名單）全部吻合，信心度高，非人工判定案例。

## 會寫入的內容（乾跑）

```
### work 欄位補完（1 筆）
  he2025personalized   + doi=10.1038/s41540-025-00547-5
```

尚未寫入 store。若要寫入請回覆「apply」——由於 store 目前沒有「更新既有記錄部分欄位」的正規 CLI/MCP 入口（`akashic_create_entry` 是 create-only，對已存在的 citekey 會拒寫），屆時會照 skill 文件的建議走法：用 store 自己的 `EntryYAML.decode → 補空欄位 → EntryYAML.encode` 一次性程式改寫該筆 YAML（只補 `doi`，不覆寫既有欄位），而不是手刻 YAML 字串。動手前會先確認 store 工作樹乾淨（目前已確認乾淨），寫完會跑 `akashic validate` 與 `akashic doctor` 複查。

CHOSEN_DOI: 10.1038/s41540-025-00547-5
