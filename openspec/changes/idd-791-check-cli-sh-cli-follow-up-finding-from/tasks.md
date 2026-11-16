## 1. 測試先行（每個 Example 一支，帶 spec-example 標記）

ASSUMPTION: Plan tier 在 /idd-all 的無人值守批次裡沒有經過 /idd-plan 的核准；取捨照 #791 Diagnosis（comment 6906743562）的最保守方向：私有目錄、計時器依探測子 shell 是否還在決定刪目錄或寫標記、專用回傳值 125、收到 125 就結束不再比契約與落後。

- [x] 1.1 `Tests/AkashicCLITests/CheckCLIHookTests.swift` 加 `A normal probe leaves nothing in TMPDIR` 與 `A timed-out probe leaves nothing in TMPDIR` 兩支（`TMPDIR` 指向測試自己的空目錄），這兩支在現行 hook 上就是綠的（舊版的正常與逾時路徑都會呼叫 `probe_cleanup`），只證明新版不退步；會在現行 hook 上變紅的是 1.2 與 1.3。驗證：`swift test --filter CheckCLIHookTests` 的結果
- [x] 1.2 加 `Killing the hook during a probe leaves nothing in TMPDIR after the timer`：假 CLI 記下 PPID（探測的子 shell）後卡住，測試分別 SIGKILL hook 與那個子 shell（不砍 process group），最多等 30 秒看目錄消失；在現行 hook 上應為紅。驗證：同上
- [x] 1.3 加 `A missing TMPDIR is reported as the hook's own problem`：`TMPDIR` 指向不存在的目錄，斷言輸出提到 TMPDIR、沒有 ✓／執行失敗／重建／install，假 CLI 的呼叫紀錄是空的；在現行 hook 上應為紅。驗證：同上

## 2. hook（`plugin/hooks/check-cli.sh`）

- [x] 2.1 `The CLI probe SHALL keep its temporary files in a private directory and remove the directory`：`probe` 以 `mktemp -d` 建目錄，輸出檔與標記檔放在裡面，`probe_cleanup` 刪整個目錄。驗證：1.1 兩支轉綠，既有的 `testAFailedProbeWithTheTimeoutMarkIsATimeout` 仍綠
- [x] 2.2 `The probe's timer SHALL remove the probe's directory when the hook is gone`：計時器第 8 秒先刪輸出檔，探測子 shell（以環境變數傳入它的 PID）不在就刪目錄、在就寫標記。驗證：1.2 轉綠
- [x] 2.3 `A check that cannot create its temporary directory SHALL say so and SHALL NOT report the CLI as failing`：`mktemp -d` 失敗回 125、CLI 自己回 125 改成 1；`--version` 探測回 125 時印 TMPDIR 訊息並結束，契約探測回 125 時同訊息、不設重建。驗證：1.3 轉綠，`CheckCLIHookTests` 全綠
- [x] 2.4 檔頭「已知的界線」與 `probe` 的回傳值契約註解改成修完之後的實際情形（剩下的窄窗照實寫）。驗證：`bash -n plugin/hooks/check-cli.sh` 通過，註解與程式對照一致

## 3. 收尾

- [x] 3.1 新增 `changelog/2026-11-16-check-cli-probe-tempdir-791.md`，記三件改了什麼、剩下的界線、測試的耗時。驗證：檔案存在
- [x] 3.2 `spectra validate` 通過；封存後 `spec-change.py links` 回 ok（四個 Example 都有標記）

## 4. spectra-verify 之後（無 critical；照 3 個 warning 與 2 個 suggestion 修）

- [x] 4.1 清理順序改成先刪目錄、再砍整組；逾時路徑在送 TERM 之前先刪目錄。子 shell 在刪除之前被砍時計時器還活著，會收尾；刪除之後被砍時沒有東西留下，所以規格「only when」那句成立。先看逾時標記再讀輸出：CLI 已回 0 而計時器已刪掉輸出檔時算逾時。驗證：`bash -n` 通過；兩處都是競態窗口，沒有可穩定重現的測試，`CheckCLIHookTests` 全綠證明沒有退步
- [x] 4.2 規格第三條加兩個 Example（`A CLI that exits 125 is reported as exit 1`、`A contract probe that cannot create its directory does not ask for a rebuild`），把「the same message」改成「a message that names TMPDIR and says the contract was not compared」；各加一支帶 spec-example 標記的測試。兩支覆蓋的是既有行為，在修正前的 hook 上也是綠的。驗證：`swift test --filter CheckCLIHookTests` 62 支全過
- [x] 4.3 changelog 刪掉 zombie 那一條界線（hook 沒有 EXIT trap，那段描述與程式不符），加〈spectra-verify 之後的調整〉一節。驗證：檔案內容
