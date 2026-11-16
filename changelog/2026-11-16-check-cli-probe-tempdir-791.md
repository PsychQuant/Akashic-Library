# #791：SessionStart 檢查的探測暫存檔改放私有目錄、被砍時由計時器收尾、建不出暫存目錄時不怪 CLI

`plugin/hooks/check-cli.sh`（#775）探測 CLI 時，暫存狀態原本是散在 `TMPDIR` 的兩個檔：`mktemp` 建的輸出檔，與同名加 `.timeout` 的逾時標記檔（名字沒有保留）；清理只靠探測子 shell 的 EXIT trap。#775 verify r3 指出的三件事這一輪修掉。規格：新 capability `session-start-cli-check`（Spectra change `idd-791-check-cli-sh-cli-follow-up-finding-from`），三條 requirement、四個 Example，各有一支帶 `spec-example` 標記的測試。

## 改了什麼

- **私有目錄**：`probe` 以 `mktemp -d "${TMPDIR:-/tmp}/akashic-check-cli.XXXXXX"` 建目錄（0700），輸出檔 `out` 與標記 `timeout` 都在裡面；`probe_cleanup` 整個刪掉。別的使用者無法在裡面預放 symlink 或標記，所以「`: >` 截斷別的檔」與「一般失敗被報成逾時」兩條路都沒有了。
- **計時器收尾**：組內的 8 秒計時器先刪輸出檔，再看跑探測的子 shell 還在不在：不在就刪掉整個目錄，在就照舊留下標記再收掉整組。子 shell 的 PID 取自 `bash -p -c` 那支小 shell 的 `$PPID`（計時器的 `( … )` 沿用同一個值）；macOS 的 `/bin/bash` 是 3.2，沒有 `BASHPID`，不能在探測裡自己取。
- **專用回傳值 125**：`mktemp -d` 失敗時探測回 125、不執行 CLI；CLI 自己回 125 時改成 1（比照 124）。`--version` 的探測回 125 時，hook 印「hook 建不出探測用的暫存目錄（TMPDIR=…）」並結束：不印 ✓、不說 CLI 失敗、不比契約與落後，所以不再叫人重建一支正常的 CLI。契約探測回 125 時印同一句、不因契約要求重建，之後的落後比對照舊。

## 還在的界線

- 計時器檢查子 shell 之後、子 shell 才死，或子 shell 的 PID 在 8 秒內被重用時，目錄會留在 `TMPDIR`（檔頭「已知的界線」照實寫）。
- 子 shell 被砍、hook 本身還活著時，子 shell 成了 hook 還沒收的 zombie，`kill -0` 仍成功：計時器照舊寫標記，目錄要等 hook 的 EXIT trap 清。

## 測試

`Tests/AkashicCLITests/CheckCLIHookTests.swift` 加四支：

- 正常與逾時兩條路徑之後 `TMPDIR` 沒有 `akashic-check-cli.*`（這兩支在舊 hook 上就是綠的，只證明新版不退步）。
- hook 與探測的子 shell 分別被 SIGKILL（不砍 process group：hook 由測試直接啟動，可能與測試同一組）之後，最多等 30 秒看目錄消失。舊 hook 上留下輸出檔與 `.timeout` 兩個檔（紅）。
- `TMPDIR` 指向不存在的目錄：輸出提到 TMPDIR、沒有 ✓／執行失敗／重建／install，假 CLI 沒有被執行。舊 hook 上報「執行 --version 失敗（結束碼 1）」並印重建與 install 的提示（紅）。

實測（2026-11-16，1 分鐘負載約 34）：`CheckCLIHookTests` 60 支全過，155 秒；被 SIGKILL 那一支 9.7 秒（計時器的 8 秒加收尾），舊 hook 上它等滿 30 秒後失敗（32.9 秒）。
