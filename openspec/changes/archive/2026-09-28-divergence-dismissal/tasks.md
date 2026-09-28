## 1. Service

- [x] 1.1 實作 Requirement「Dismissing a question SHALL delete only its record」：`AkashicService.dismissDivergence(id:reason:dryRun:)` in `Sources/AkashicMCPKit/DivergenceDismissal.swift`：以 UUID 定位歧異記錄；理由空白或超過 4,096 位元組拒絕；乾跑只回報；實跑前走 `assertRecordsRecoverable`（tracked、clean），再刪記錄檔、重建 index；報告含 `dismissed`（id、question、candidates）與全文 `reason`。驗收：`DivergenceDismissalTests` 的刪除、候選不動、理由必填、未提交拒絕、乾跑不寫、id 不存在五支全綠
- [x] 1.2 負控：拿掉 commit 閘與理由檢查各一次，對應測試轉紅後還原

## 2. 兩面

- [x] 2.1 CLI `dismiss-divergence <id> --reason … [--dry-run]` 註冊進 `CLI.swift`，人可讀輸出與 service 同源
- [x] 2.2 MCP `akashic_dismiss_divergence`（`id`、`reason`、`dry_run`）；`StdioE2ETests` 的工具數 31 → 32
- [x] 2.3 `resolve-divergence` 的程式註解改寫：放棄一筆歧異的出路是 `dismiss-divergence`，spec 那句禁止的是刪候選實體

## 3. 規則與文件

- [x] 3.1 `mcp-cli-parity` 加 `akashic_dismiss_divergence` 一列、表頭工具數改 32；`two-kinds-of-edits` 加一列；`zero-instance-guards` 第 24 列的「只能手改 YAML（#586）」改指本面
- [x] 3.2 changelog 一份；`spectra validate` 與 `analyze` 無 Critical
