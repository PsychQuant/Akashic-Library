## 1. 測試先行（新 Example 各一支，先對 6efbc91b 的 hook 跑出紅燈）

- [x] 1.1 Requirement「The probe's timer SHALL NOT write its marker through an existing entry」的 Example `A FIFO at the marker's path does not stop the timer`：假 CLI 在 `$PROBE_TIMED_OUT` 建 FIFO、寫 sentinel、記下 PID 後卡住；測試 SIGSTOP 探測的 shell，斷言 CLI 在 40 秒內被收掉。驗證：舊 hook 卡在開 FIFO（紅），修好後綠
- [x] 1.2 Requirement「A check that cannot create its temporary directory SHALL say so and SHALL NOT report the CLI as failing」的 Example `A TMPDIR that holds the directory but not its output file is reported as the hook's own problem`：TMPDIR 是實際路徑長 996 位元組的既有目錄。驗證：舊 hook 報「執行 --version 失敗」（紅），修好後綠
- [x] 1.3 Requirement「The CLI probe SHALL keep its temporary files in a private directory and remove the directory」：kill 那一支斷言 `$PROBE_TIMED_OUT` 的上一層就是那個 0700 的探測目錄
- [x] 1.4 Requirement「The probe's timer SHALL remove the probe's directory when the hook is gone」：symlink 那一支的假 CLI 改睡 300 秒，確認 CLI 被收掉之後再斷言探測目錄與 symlink 都還在；三支靠 `$PROBE_TIMED_OUT` 放標記的測試加 sentinel 斷言。驗證：`swift test --filter CheckCLIHookTests` 綠

## 2. hook（`plugin/hooks/check-cli.sh`）

- [x] 2.1 計時器以 `/bin/mkdir` 建標記。驗證：1.1 轉綠，symlink 那一支仍綠
- [x] 2.2 `mktemp -d` 之後先建輸出檔，建不出來刪目錄、回 125；兩則 125 訊息改成「暫存目錄或暫存檔」。驗證：1.2 轉綠，既有的 TMPDIR 測試仍綠
- [x] 2.3 `-c` 的腳本在 `exec` 之前 `unset PROBE_DIR`；檔頭的殘留清單補一種、標記的說明改成 mkdir。驗證：`bash -n` 通過

## 3. 收尾

- [x] 3.1 changelog：開頭各段改成現況、被取代的句子就地標成撤回，加〈verify 第 2 輪之後〉一節。驗證：檔案內容
- [x] 3.2 `plugin/CHANGELOG.md` 0.13.17 那一則與殼版號表 0.13.17 那一列的摘要（原地重算）。驗證：`akashic-guards plugin-shell-version` 綠
- [x] 3.3 `spectra validate`、`swift build --build-tests -Xswiftc -warnings-as-errors`、封存後的連結檢查。驗證：三者的輸出
