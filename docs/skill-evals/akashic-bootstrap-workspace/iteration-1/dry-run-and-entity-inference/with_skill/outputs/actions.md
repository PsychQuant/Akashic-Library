# Actions log

## 可能改動 store 的操作

| 操作 | 狀態 |
|---|---|
| `akashic_create_entry`（MCP，建立 `yang2026fourier`） | **只規劃，未執行** — 禁止呼叫 MCP 工具；也沒有等效 CLI 子指令 |
| `akashic_create_entry`（MCP，建立 `jou2025generalized` / `jou2026generalized`） | **只規劃，未執行** — 同上；日期年份待人工判定 |
| `akashic_create_entry`（MCP，建立 `chu2024pseudo` / `chu2025pseudo`） | **只規劃，未執行** — 同上；日期年份待人工判定 |
| `akashic bootstrap-people --apply`（把 9 個候選作者裸字串建成 person） | **只規劃，未執行** — 使用者尚未決定要不要建；且該指令是全 store 掃描，若執行需先用暫存 store 限定範圍 |
| 把 3 篇論文的 Crossref 原始 JSON 存進 `sources/` + 附 provenance JSONL | **只規劃，未執行** — 等 apply 才連同 work 一起寫入 |
| 手刻 YAML 直接寫進 `entities/` | **未考慮、未執行** — skill 明文禁止的錯誤繞法，即使可行也不會採用 |
| 用 `import-wos` 偽裝格式塞入這 3 篇 | **未考慮、未執行** — 該指令是為真實 WoS TSV 匯出設計，硬套等於變相手刻資料，不採用 |

**結論：本次沒有任何一個會改動 store 內容的指令被實際執行過。**

## 實際執行過的指令（唯讀，不會改動 store）

```bash
akashic doctor --library <store>
akashic validate --library <store>
```

以及一系列唯讀的 shell 檢查（`grep`／`ls`／`git status` 於 store 目錄，皆未加 `-w`/`--apply` 等寫入旗標）與對 Crossref API 的唯讀查詢（`curl`／WebFetch，查 3 個 DOI 的書目資料，含反向驗證）。這些都只讀取，不寫入 store 或任何外部服務。
