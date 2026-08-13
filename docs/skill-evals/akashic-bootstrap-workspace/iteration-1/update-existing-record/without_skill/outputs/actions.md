# Actions log — chen2020association PMID 補值

## 唯讀查找／驗證（皆已實際執行）

1. `find <store> -iname "*chen2020*"` — 無結果（檔名是 UUID，不是 citekey）
2. `grep -rl "chen2020association" <store>` — 定位到 `entities/C37BE4B6-FD8C-4BFC-900E-A2EDE664D4E1.yaml`
3. `Read` 該 YAML，取得既有 DOI：`10.2174/0929867327666200425214906`
4. WebFetch `https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=10.2174/0929867327666200425214906[DOI]&retmode=json` — 命中唯一 PMID `32334497`
5. WebFetch `https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=32334497&retmode=json` — 核對標題／作者／期刊／卷期頁碼／DOI 與 store 記錄逐字相符
6. `grep -rl "pmid" <store>/entities/*.yaml` — 找到既有記錄 `8535E48C-...yaml`（huang2026aipowered）確認 store 內 `fields.pmid` 的既有欄位命名慣例（純數字，非字串）

## 實際修改 store 的動作

7. **實際執行**：用 `Edit` 工具直接編輯
   `entities/C37BE4B6-FD8C-4BFC-900E-A2EDE664D4E1.yaml`，
   在 `fields:` 底下、`pages:` 之後、`url:` 之前插入一行：
   ```yaml
   pmid: 32334497
   ```
   **寫入機制**：不是透過 CLI 或 MCP 的寫入指令（`akashic` CLI 沒有 `update-entry` /
   `edit` 這類 subcommand；MCP 工具依指示禁止使用），而是直接編輯 YAML 檔案本體
   （store 的資料本來就是純文字 YAML，這是 file-based store 設計下唯一可行的欄位更新
   路徑）。

8. **實際執行**：`akashic validate --library <store>` — 確認修改後 schema 仍合法
   （結果：12 entries、12 people、0 libraries 全部通過，exit 0）

9. **實際執行**：`akashic doctor --library <store>` — 重建/檢查 index，確保
   `.akashic/index.sqlite` 與修改後的 YAML 同步（結果：12 entries、12 people、
   0 relations、0 orphaned，exit 0）

10. **實際執行**：`akashic query --library <store> --json` 後過濾 `citekey ==
    chen2020association`，確認記錄仍可正常被 index 查到（query 的輸出欄位不含
    `pmid`，該欄位存在與否以直接編輯結果與 validate 通過為準）。

## 未執行 / 未使用

- 未使用任何 `mcp__*akashic*` MCP 工具（依指示全程避免）
- 未觸碰 `~/.akashic`
- 沒有其他寫入或刪除操作
