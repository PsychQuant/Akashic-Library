# 2026-09-28 歧異記錄可以放棄了（#586）

歧異記錄有記錄面（`record-divergence`）、讀取面（`divergences`）與合併面（`resolve-divergence`），沒有移除面。一筆記錄撞上沒有合併管線的 shape（organization，`zero-instance-guards` 第 24 列裁「暫不做」的那個），或記錯了，唯一的出路是手改 YAML。

## 改了什麼

**移除面，兩面同契約**：CLI `dismiss-divergence <id> --reason … [--dry-run]`，MCP `akashic_dismiss_divergence`（`id`、`reason`、`dry_run`），同走 `dismissDivergence`。

- **只刪那筆問題記錄**，候選實體與參照都不動。
- 理由必填，只進報告（全文不截斷），不寫進 store、不改 store format——使用者 2026-09-27 對移除面一族（#572／#586／#588）的裁決。
- 刪除前要求記錄檔已 commit、沒有未提交修改（`assertRecordsRecoverable`）；store 不在 git 工作樹同樣拒絕。
- 帶本 binary 不認得的欄位的記錄不刪（與 `resolve-divergence` 的 #75 同一條理由），訊息指向升級 binary。
- 乾跑只回報要刪哪一筆。
- CLI 不過目標 store 確認閘：以 UUID 定位，指錯 store 只會找不到。

## spec

Spectra change `divergence-dismissal`：`divergence-record` 加一條 Requirement「Dismissing a question SHALL delete only its record」。既有的「Deleting a record without rewriting its references SHALL NOT be offered」指的是被併的**候選實體**；`resolve-divergence` 的程式註解先前把它讀成「放棄一筆歧異只能手改」，那個註解同輪改寫。

## MCP／CLI parity

MCP 工具 31 → 32。它與 `resolve-divergence` 的 CLI-only 裁決不矛盾：那一格缺席的理由是合併＋全庫改寫＋刪檔不可逆；本面只刪一筆記錄且 git 有副本，而記錄面本來就在 MCP 上——只有記錄面沒有移除面，記錯的代價會落在手改 YAML。

## 測試

`DivergenceDismissalTests` 6 支：只刪記錄且候選逐欄不動、理由全文；理由空白或過長拒絕；不在 git 與未提交各拒絕；乾跑不寫；id 不存在或不合法；未知欄位拒絕。負控：拿掉理由檢查與 commit 閘，對應測試轉紅。
