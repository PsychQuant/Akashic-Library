# #791：SessionStart 檢查的探測暫存檔改放私有目錄、被砍時由計時器收尾、建不出暫存目錄時不怪 CLI

`plugin/hooks/check-cli.sh`（#775）探測 CLI 時，暫存狀態原本是散在 `TMPDIR` 的兩個檔：`mktemp` 建的輸出檔，與同名加 `.timeout` 的逾時標記檔（名字沒有保留）；清理只靠探測子 shell 的 EXIT trap。#775 verify r3 指出的三件事這一輪修掉。規格：新 capability `session-start-cli-check`（Spectra change `idd-791-check-cli-sh-cli-follow-up-finding-from`），三條 requirement、六個 Example，各有一支帶 `spec-example` 標記的測試。

## 改了什麼

- **私有目錄**：`probe` 以 `mktemp -d "${TMPDIR:-/tmp}/akashic-check-cli.XXXXXX"` 建目錄（0700），輸出檔 `out` 與標記 `timeout` 都在裡面；`probe_cleanup` 整個刪掉。別的使用者無法在裡面預放 symlink 或標記，所以「`: >` 截斷別的檔」與「一般失敗被報成逾時」兩條路都沒有了。
- **計時器收尾**：組內的 8 秒計時器先刪輸出檔，再看跑探測的子 shell 還在不在：不在就刪掉整個目錄，在就照舊留下標記再收掉整組。子 shell 的 PID 取自 `bash -p -c` 那支小 shell 的 `$PPID`（計時器的 `( … )` 沿用同一個值）；macOS 的 `/bin/bash` 是 3.2，沒有 `BASHPID`，不能在探測裡自己取。
- **專用回傳值 125**：`mktemp -d` 失敗時探測回 125、不執行 CLI；CLI 自己回 125 時改成 1（比照 124）。`--version` 的探測回 125 時，hook 印「hook 建不出探測用的暫存目錄（TMPDIR=…）」並結束：不印 ✓、不說 CLI 失敗、不比契約與落後，所以不再叫人重建一支正常的 CLI。契約探測回 125 時另印一句（說 TMPDIR、沒有比對契約）、不因契約要求重建，之後的落後比對照舊。

## spectra-verify 之後的調整

- 清理順序改成先刪目錄、再砍整組；逾時路徑在送 TERM 之前先刪目錄。子 shell 在刪除之前被砍時計時器還活著，會收尾；刪除之後被砍時已經沒有東西留下。先前是先砍整組（計時器一起停）再刪目錄，中間有一段沒人收尾的時間。
- 先看逾時標記再讀輸出：系統很忙、迴圈慢過 8 秒時，CLI 可能已經回 0，而計時器已刪掉輸出檔並留下標記——那一次算逾時，不會讀到空的版本、也不會因此誤報要重建。
- 規格第三條加兩個 Example（CLI 自己回 125 報成 1、契約探測回 125 不要求重建），各一支測試。

## 版號

plugin 殼 0.13.16 → 0.13.17（`plugin/.claude-plugin/plugin.json`、`plugin/CHANGELOG.md`、`.githooks/plugin-shell-versions.txt` 接一列）。binary 與 fulltext 契約版本不變，不需要重建 CLI。

## 還在的界線

- 計時器檢查子 shell 之後、子 shell 才死，或子 shell 的 PID 在 8 秒內被重用時，目錄會留在 `TMPDIR`（檔頭「已知的界線」照實寫）。

## 測試

`Tests/AkashicCLITests/CheckCLIHookTests.swift` 加六支：

- 正常與逾時兩條路徑之後 `TMPDIR` 沒有 `akashic-check-cli.*`（這兩支在舊 hook 上就是綠的，只證明新版不退步）。
- hook 與探測的子 shell 分別被 SIGKILL（不砍 process group：hook 由測試直接啟動，可能與測試同一組）之後，最多等 30 秒看目錄消失。舊 hook 上留下輸出檔與 `.timeout` 兩個檔（紅）。
- `TMPDIR` 指向不存在的目錄：輸出提到 TMPDIR、沒有 ✓／執行失敗／重建／install，假 CLI 沒有被執行。舊 hook 上報「執行 --version 失敗（結束碼 1）」並印重建與 install 的提示（紅）。
- CLI 自己回 125：報成結束碼 1，沒有暫存目錄的訊息。契約探測建不出目錄（假 CLI 回答 `--version` 時把 `TMPDIR` 改成唯讀）：有 ✓ 與「沒有比對契約」，沒有要求重建。這兩支是 spectra-verify 之後加的，覆蓋既有行為，在修正前的 hook 上也是綠的。

實測（2026-11-16，1 分鐘負載約 34）：`CheckCLIHookTests` 60 支全過，155 秒（spectra-verify 之後 62 支全過，177 秒，負載約 50）；被 SIGKILL 那一支 9.7 秒（計時器的 8 秒加收尾），舊 hook 上它等滿 30 秒後失敗（32.9 秒）。

## verify 第 1 輪之後（change `idd-791-fix1`）

verify r1 判 FAIL，三個 Blocking 都出在〈spectra-verify 之後的調整〉改的兩處，這一輪改回 base 的做法，再補上原本要處理的漏洞：

- **計時器寫標記不再寫穿既有的項目**（Blocking 1）：先刪目錄、再停組的順序讓計時器在目錄名字釋出之後還可能照舊路徑寫標記，`: >` 會跟著 symlink 走。計時器寫標記時開 `set -C`（noclobber），路徑上已經有檔案或 symlink（不論指向是否存在）就不寫；2026-11-16 在 /bin/bash 3.2.57 量過兩種 symlink 都被拒。清理順序改回先停整組、再刪目錄。
- **計時器在子 shell 還在時不刪輸出檔，分類改回「結束碼 0 一律讀輸出」**（Blocking 2、3）：先看標記的分類讓 CLI 在第 8 秒前後以 0 回答時被報成逾時，契約探測接著叫人重建一支正常的 CLI。現在標記只決定非 0 的結束碼算不算逾時；issue Expected 第 2 項（計時器刪掉輸出檔）由「子 shell 不在時刪整個目錄」涵蓋，那正是 hook 被砍的情形。上一節第二條（先看標記）因此撤回。
- 殘留的情形改成不封閉的清單（檔頭與規格），寫明留下的只會是那個私有目錄；私有目錄的保護寫明前提（TMPDIR 私有或 sticky）。
- `--version` 探測回 125 時仍印「不在 PATH 上」那一行。
- 計時器不再需要 `PROBE_OUT_FILE`，這個變數不再傳進 CLI 的環境。
- 更正：封存的 tasks.md 2.2 說探測子 shell 的 PID「以環境變數傳入」，實際取自 `bash -p -c` 那支小 shell 的 `$PPID`（本 changelog〈改了什麼〉第二條寫的才對）。

測試加四支，各對應規格的一個新 Example，先對 `7689f5f2` 的 hook 跑出紅燈再修：標記路徑上的 symlink 不被寫穿（舊 hook 把 victim 截成空的）；版本與契約以 0 回答時即使有標記也照常讀（舊 hook 報「沒有回應」、叫人重建）；CLI 只在 `~/bin`、TMPDIR 不能用時仍說不在 PATH 上。symlink 那一支以 SIGSTOP 停住探測的 shell、等計時器收掉 CLI（`ps` 看到 zombie）才檢查，約 9.6 秒。kill 那一支另外斷言探測期間恰好一個 0700 的目錄、輸出檔在裡面，kill 之前排除 hook 與測試程序自己的 PID。

實測（2026-11-16，1 分鐘負載約 40–55）：`CheckCLIHookTests` 66 支全過，164 秒。

沒有在這一輪做、記在 follow-up issue 的：目錄建好、輸出檔卻建不出來時仍報成 CLI 失敗（沒有穩定的測法）；契約探測逾時被報成要重建；訊息裡的 TMPDIR 沒有長度上限；`PROBE_TIMED_OUT`、`PROBE_DIR` 仍在 CLI 的環境裡。
