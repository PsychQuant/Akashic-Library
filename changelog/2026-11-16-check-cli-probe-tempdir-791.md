# #791：SessionStart 檢查的探測暫存檔改放私有目錄、被砍時由計時器收尾、建不出暫存目錄時不怪 CLI

`plugin/hooks/check-cli.sh`（#775）探測 CLI 時，暫存狀態原本是散在 `TMPDIR` 的兩個檔：`mktemp` 建的輸出檔，與同名加 `.timeout` 的逾時標記檔（名字沒有保留）；清理只靠探測子 shell 的 EXIT trap。#775 verify r3 指出的三件事這一張修掉。規格：新 capability `session-start-cli-check`，經三個 Spectra change（`idd-791-check-cli-sh-cli-follow-up-finding-from`、verify 第 1 輪之後的 `idd-791-fix1`、第 2 輪之後的 `idd-791-fix2`）；現在是四條 requirement、十二個 Example，各有一支帶 `spec-example` 標記的測試。

這一份依時間分節。〈改了什麼〉描述現在的行為；後面幾節是各輪改了什麼，被後來取代的句子就地標成撤回。

## 改了什麼（現況）

- **私有目錄**：`probe` 以 `mktemp -d "${TMPDIR:-/tmp}/akashic-check-cli.XXXXXX"` 建目錄（0700），先在裡面建好輸出檔 `out`，逾時標記 `timeout` 也在裡面；探測結束時先停探測的 process group、再整個刪掉。前提是別人不能改名 TMPDIR 裡的項目（每個使用者私有的 TMPDIR，或 sticky 的 /tmp）。
- **計時器收尾**：組內的 8 秒計時器看跑探測的子 shell 還在不在（PID 取自 `bash -p -c` 那支小 shell 的 `$PPID`，計時器的 `( … )` 沿用同一個值；macOS 的 `/bin/bash` 是 3.2，沒有 `BASHPID`）。不在（hook 被砍了）就刪掉整個目錄，輸出檔在裡面；還在就以 `/bin/mkdir` 建標記，再收掉整組，不碰輸出檔。`mkdir` 遇到路徑上有任何東西（檔案、目錄、FIFO、裝置、symlink，不論指向是否存在）都失敗，不開也不跟隨。
- **探測結果的分類**：結束碼 0 一律讀輸出；標記只決定非 0 的結束碼算不算逾時。
- **專用回傳值 125**：`mktemp -d` 失敗，或目錄建好了而輸出檔建不出來時，探測回 125、不執行 CLI；CLI 自己回 125 時改成 1（比照 124）。`--version` 的探測回 125 時，hook 印「hook 建不出探測用的暫存目錄或暫存檔（TMPDIR=…）」，CLI 不在 PATH 上時照樣說出來，然後結束：不印 ✓、不說 CLI 失敗、不比契約與落後。契約探測回 125 時另印一句（說 TMPDIR、沒有比對契約）、不因契約要求重建，之後的落後比對照舊。
- **環境**：CLI 只拿到 `PROBE_TIMED_OUT`（與 base 相同）；`PROBE_DIR` 只給計時器，`exec` 之前就 unset。

## 還在的界線（現況）

目錄仍可能留在 TMPDIR，已知的情形有：子 shell 在停組之後、刪目錄之前被砍；在 `mktemp -d` 之後、計時器起來之前被砍；在計時器檢查之後才死；它的 PID 被重用；計時器自己被砍；刪目錄時計時器正好建出標記；TMPDIR 變成不可寫。留下的只會是那個私有目錄，裡面最多是輸出檔與標記。這份清單是已知的情形，不是完整的保證。

## 第一版（`eb120466`）

- 私有目錄、125 與上面相同。
- ~~計時器先刪輸出檔，再看子 shell 還在不在~~（撤回：verify 第 1 輪之後，子 shell 還在時不碰輸出檔）。
- 測試四支：正常與逾時兩條路徑之後 `TMPDIR` 沒有 `akashic-check-cli.*`（這兩支在舊 hook 上就是綠的）；hook 與探測的子 shell 分別被 SIGKILL 之後，最多等 30 秒看目錄消失（舊 hook 上留下兩個檔，紅）；`TMPDIR` 指向不存在的目錄時說是 TMPDIR、不執行 CLI（舊 hook 報「執行 --version 失敗」並叫人重建，紅）。實測（1 分鐘負載約 34）：`CheckCLIHookTests` 60 支全過，155 秒；SIGKILL 那一支 9.7 秒，舊 hook 上等滿 30 秒後失敗。

## spectra-verify 之後（`f3269c1a`）

- ~~清理順序改成先刪目錄、再砍整組~~（撤回：verify 第 1 輪 Blocking 1，計時器會在名字釋出之後照舊路徑寫標記）。
- ~~先看逾時標記再讀輸出~~（撤回：verify 第 1 輪 Blocking 2、3，CLI 以 0 回答時被報成逾時、被叫去重建）。
- 規格第三條加兩個 Example（CLI 自己回 125 報成 1、契約探測回 125 不要求重建），各一支測試，覆蓋既有行為，在修正前的 hook 上也是綠的。62 支全過，177 秒（負載約 50）。

## 版號

plugin 殼 0.13.16 → 0.13.17（`plugin/.claude-plugin/plugin.json`、`plugin/CHANGELOG.md`、`.githooks/plugin-shell-versions.txt` 接一列）。0.13.17 還沒推上 main，後面兩輪改 hook 時原地重算那一列的摘要。binary 與 fulltext 契約版本不變，不需要重建 CLI。

## verify 第 1 輪之後（change `idd-791-fix1`，`422059a0`）

verify r1 判 FAIL，三個 Blocking 都出在 spectra-verify 之後改的兩處，這一輪改回 base 的做法：

- 清理順序改回先停整組、再刪目錄。~~計時器寫標記時開 `set -C`（noclobber）~~（撤回：verify 第 2 輪，noclobber 只擋一般檔案，FIFO 會讓計時器卡在開檔；改用 `mkdir`）。
- 計時器在子 shell 還在時不刪輸出檔，分類改回「結束碼 0 一律讀輸出」。issue Expected 第 2 項（計時器刪掉輸出檔）由「子 shell 不在時刪整個目錄」涵蓋，那正是 hook 被砍的情形。
- 殘留的情形改成不封閉的清單；私有目錄的保護寫明前提。
- `--version` 探測回 125 時仍印「不在 PATH 上」那一行。
- 計時器不再需要 `PROBE_OUT_FILE`，這個變數不再傳進 CLI 的環境。
- 更正：封存的第一個 change 的 tasks.md 2.2 說探測子 shell 的 PID「以環境變數傳入」，實際取自 `bash -p -c` 的 `$PPID`。
- 測試加四支，先對 `7689f5f2` 的 hook 跑出紅燈再修：標記路徑上的 symlink 不被寫穿；版本與契約以 0 回答時即使有標記也照常讀；CLI 只在 `~/bin`、TMPDIR 不能用時仍說不在 PATH 上。66 支全過，164 秒（負載約 40–55）。
- ~~目錄建好、輸出檔卻建不出來時仍報成 CLI 失敗，沒有穩定的測法，記在 #818~~（撤回：verify 第 2 輪 DA 實測可以穩定重現，這一張第 2 輪修掉）。

## verify 第 2 輪之後（change `idd-791-fix2`）

verify r2 判 PASS 但不乾淨（2 個 MEDIUM）：

- **計時器以 `mkdir` 建標記**：noclobber 對標記路徑上的 FIFO 照樣開檔，沒有讀者時計時器卡在 open、收不掉整組。2026-11-16 量過：一般檔案、目錄、FIFO、指向一般檔案／FIFO／`/dev/null` 的 symlink、dangling symlink，`mkdir` 都失敗、不開、不跟隨，victim 內容不變。
- **輸出檔建不出來也回 125**：TMPDIR 的實際路徑長 995–998 位元組時，`mktemp -d` 建得出目錄（再加 25 位元組），`/out` 卻超過 PATH_MAX（1024，含結尾的 NUL），背景 job 在執行 CLI 之前就失敗、被報成 CLI 失敗。現在 `mktemp -d` 之後先建輸出檔，失敗就刪目錄、回 125。
- `exec` 之前 unset `PROBE_DIR`，CLI 的環境回到 base。
- 已知殘留清單補「刪目錄時計時器正好建出標記」；Requirement 1 的承諾註明已知情形是例外。
- 測試加兩支，先對 `6efbc91b` 的 hook 跑出紅燈再修：標記路徑上有 FIFO 時計時器照樣收掉 CLI；TMPDIR 長 996 位元組時說是 TMPDIR、不執行 CLI、不留目錄。另外補強三處：kill 那一支斷言標記的路徑就在那個 0700 目錄裡；symlink 那一支的假 CLI 改睡 300 秒，CLI 被收掉之後再確認探測目錄與 symlink 都還在（迴圈期限那條路會刪掉它們，計時器那條路不會）；靠 `$PROBE_TIMED_OUT` 放標記的三支測試都斷言假 CLI 真的放成了。

兩支新測試在 `6efbc91b` 的 hook 上：FIFO 那一支計時器卡住、40 秒內沒收掉 CLI；長 TMPDIR 那一支被報成「執行 --version 失敗」並叫人重建（都紅）。修好之後 `CheckCLIHookTests` 68 支全過，203 秒（2026-11-16，1 分鐘負載約 140–200）。

仍記在 #818 的：契約探測逾時被報成要重建；訊息裡的 TMPDIR 沒有長度上限與字元過濾；`PROBE_TIMED_OUT` 仍在 CLI 的環境裡（三支測試靠它放標記，拿掉時要一起改）。
