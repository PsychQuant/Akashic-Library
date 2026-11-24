## 1. 測試先行（新 Example 各一支，先對 7689f5f2 的 hook 跑出紅燈）

- [x] 1.1 Requirement「The probe's timer SHALL NOT write its marker through an existing entry」的 Example `A symbolic link at the marker's path is not written through`：假 CLI 在 `$PROBE_TIMED_OUT` 放指向 victim 檔的 symlink、記下 `$PPID` 與自己的 PID 後卡住；測試 SIGSTOP 那個 PPID，等到 CLI 被計時器收掉（`ps` 看到 Z 或程序不在），檢查 victim 內容，再 SIGCONT。驗證：舊 hook 上 victim 被截斷（紅），修好後綠
- [x] 1.2 Requirement「The probe's timer SHALL remove the probe's directory when the hook is gone」的兩個 Example：`A version answered with 0 is read even when the timer left its mark` 與 `A contract answered with 0 after the timer's mark does not ask for a rebuild`：假 CLI 寫標記後照常回答並 `exit 0`。驗證：舊 hook 上報「沒有回應」或「要先重建」（紅），修好後綠
- [x] 1.3 Requirement「A check that cannot create its temporary directory SHALL say so and SHALL NOT report the CLI as failing」的 Example `A CLI off PATH is still named when TMPDIR is unusable`：CLI 只在 `~/bin`、TMPDIR 不存在。驗證：舊 hook 沒有「不在 PATH 上」（紅），修好後綠
- [x] 1.4 Requirement「The CLI probe SHALL keep its temporary files in a private directory and remove the directory」：kill 那一支（屬 Requirement 2 的 Example）探測期間斷言 TMPDIR 裡恰好一個探測目錄、權限 0700、`out` 在裡面；kill 之前遇到 hook 自己或測試程序的 PID 就停。驗證：`swift test --filter CheckCLIHookTests` 綠

## 2. hook（`plugin/hooks/check-cli.sh`）

- [x] 2.1 計時器寫標記時開 `set -C`；子 shell 還在時不刪輸出檔，不在時刪整個目錄。驗證：1.1 轉綠
- [x] 2.2 分類改回「結束碼 0 就讀輸出」，標記只決定非 0 的結束碼算不算逾時。驗證：1.2 轉綠
- [x] 2.3 `probe_cleanup` 與逾時路徑改回先停整組、再刪目錄。驗證：kill 那一支與兩支「leaves nothing」仍綠
- [x] 2.4 `--version` 回 125 時先印「不在 PATH 上」那一行再停。驗證：1.3 轉綠
- [x] 2.5 檔頭：私有目錄的前提（TMPDIR 私有或 sticky）、殘留情形改成不封閉的清單、清理順序與分類的理由。驗證：`bash -n` 通過，註解與程式對照一致

## 3. 收尾

- [x] 3.1 changelog：〈verify 第 1 輪之後〉一節；修正「印同一句」；記下封存的 tasks.md 2.2 寫錯了 PID 的來源（實際取自 `bash -p -c` 的 `$PPID`）。驗證：檔案內容
- [x] 3.2 `plugin/CHANGELOG.md` 0.13.17 那一則與 `.githooks/plugin-shell-versions.txt` 0.13.17 那一列的摘要（原地重算）。驗證：`akashic-guards plugin-shell-version` 綠
- [x] 3.3 `spectra validate` 通過；`swift build --build-tests -Xswiftc -warnings-as-errors` 通過；封存後 `spec-change.py links` 回 ok。驗證：三者的輸出
