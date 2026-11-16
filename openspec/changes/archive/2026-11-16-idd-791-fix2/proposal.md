## Problem

#791 的 verify 第 2 輪（comment 6909025664）判 PASS 但不乾淨，兩個 MEDIUM：

- 計時器以 `set -C; : >` 寫標記。noclobber 只擋目標是一般檔案的情形；標記路徑上是 FIFO，或指向 FIFO、裝置的 symlink 時照樣開檔，沒有讀者的 FIFO 會讓計時器卡在 open、收不掉整組。Requirement 4 的「create the marker only if nothing exists」因此說得太滿。
- `mktemp -d` 成功、輸出檔卻建不出來時（例如 TMPDIR 的實際路徑長 995–998 位元組，目錄建得出來而 `/out` 超過 PATH_MAX），背景 job 在執行 CLI 之前就失敗，hook 把它報成 CLI 執行失敗並叫人重建：issue 第 3 項的症狀。

## Root Cause

noclobber 的語意是「不覆寫既有的一般檔案」，不是「路徑上有東西就不開」。輸出檔由背景 job 的重導向建立，它的失敗與 CLI 的結束碼混在一起。

## Proposed Solution

- 計時器以 `/bin/mkdir` 建標記：路徑上有任何東西就失敗，不開、不跟隨。
- `mktemp -d` 之後先在目錄裡建好輸出檔，建不出來就刪掉目錄、回 125；訊息改成「建不出探測用的暫存目錄或暫存檔」。
- 同一輪處理 LOW／INFO 列：`exec` 之前 `unset PROBE_DIR`；已知殘留清單補「刪目錄時計時器正好建出標記」，Requirement 1 的承諾註明已知情形是例外；測試補判別與 sentinel。

## Non-Goals

- 契約探測逾時被報成要重建、訊息裡 TMPDIR 的長度與字元類、`PROBE_TIMED_OUT` 仍在 CLI 的環境裡：留在 #818。

## Success Criteria

- 標記路徑上有 FIFO 時，計時器照樣在探測的 shell 被停住時收掉 CLI。
- TMPDIR 長到建得出目錄、建不出 `/out` 時，hook 說是 TMPDIR 的問題、不呼叫 CLI、不叫人重建，TMPDIR 裡不留東西。
- 兩支測試在 `6efbc91b` 的 hook 上失敗，修好之後通過。

## Impact

- Affected specs: session-start-cli-check
- Affected code:
  - Modified: plugin/hooks/check-cli.sh, Tests/AkashicCLITests/CheckCLIHookTests.swift, changelog/2026-11-16-check-cli-probe-tempdir-791.md, plugin/CHANGELOG.md, .githooks/plugin-shell-versions.txt
