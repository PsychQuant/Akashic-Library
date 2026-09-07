# 階段 B 摘要存檔的出口：NDJSON → `[Proposal]` 腳本＋148 列實跑（#516）

#458 交付了 generic add-only 面（`akashic enrich --from`／`akashic_enrich`），但 #423 階段 B 抓回來的摘要存檔
（`sources/6c/0adfc06b97e9…`，NDJSON、以 DOI 為鍵）沒有路變成 `[Proposal]`——design 留的 Open Question 是
「腳本住 plugin skill 還是 CLI 子命令，由第一次實跑決定」。本 change 就是那次實跑。

## 腳本住 `akashic-venue-works/scripts/`，不走 CLI 子命令

- 新增 `plugin/skills/akashic-venue-works/scripts/ndjson-abstracts-to-proposals.py`：`--source sha256:<hex>`（在
  `<library>/sources/<2>/<62>` 解析並驗內容定址）或檔路徑（由位元組算 `sourceDigest`）；輸出
  `[{doi, fields:{abstract}, sourceDigest}]`，`sort_keys` 決定論、無網路。
- 只收 `status == got`、摘要非空、DOI 在場的列；其餘**逐筆**印在 stderr（`skip\t<reason>\t<doi>\tline <n>`，
  理由封閉四值 `no-doi`／`status:<v>`／`empty-abstract`／`duplicate-doi`）——丟棄必須可見（`lossless-intake`
  執行細節 3）。
- `doi` **原樣透傳**：URL 前綴與大小寫由 core 的 `DOI` 吸收，腳本裡再寫一份就是第二份會分岔的副本；所以
  「重複」只認逐位元相同的字串，近重複（單／雙斜線）留給 core 報 `skipped`。
- 為什麼不是 CLI 子命令：NDJSON 的形狀是該 skill 階段 B 的 scrape 產物，不是 store 契約；store 的公開面只有
  `[Proposal]` JSON（`decodeProposals` 唯一解析器）。焊進 CLI 要在 `mcp-cli-parity` 加一列、換一個來源再長一個
  子命令。adapter 跟產物住一起（`akashic-bootstrap/scripts/crossref_match.py` 的先例）。
- fixture 測試 `plugin/tests/ndjson-abstracts-to-proposals.py`（6 列、純 Python、不需 build）掛進
  `.githooks/run-guards.sh`；RED（`984d924`）→ GREEN。

## 148 列實跑：`added 73／skipped 75`，不是 Diagnosis 估的 139

| 量 | 數 |
|---|---|
| NDJSON 列數 | 155（`got` 148、`landing-failed` 5、`none-verified` 2；1 列 DOI 為 null） |
| 148 列 `got` 對應的 work | **82**（66 對是 keeper 單／雙斜線兩個 DOI 各抓一列，摘要逐字相同；16 筆單列） |
| 其中原已有摘要 | 9 |
| dry-run／apply counts | `added 73／skipped 75（66 重複列＋9 已有）／notFound 0／ambiguous 0` |
| `written` | 73；validate 2280 全過、doctor 無 quarantine；有摘要的 work 1444 → 1517 |

Diagnosis 寫的 `added 139` 是**把列數當筆數**：交叉比對只問「每列命中幾筆」，沒問「幾列命中同一筆」。
閘（「數字不符即停」）擋下了第一次 apply 判斷，重量後原因具名、無資訊損失（重複對的摘要相同）才 apply。
這正是 `assertions-must-be-measured` 要的形：估計要被實跑打臉時，打臉要留下記錄。

## 不在本 change 內

- 7 列 non-got 仍缺摘要（5 `landing-failed`、2 `none-verified`）——資料工作，記在 #516 Diagnosis 的 Sister Concerns。
- 摘要的來源 provenance（`landing`、`retrieved`）不進 store，`sourceDigest` 只回顯——#517。
- store repo（`~/.akashic`）的 commit 未 push，由使用者決定。
