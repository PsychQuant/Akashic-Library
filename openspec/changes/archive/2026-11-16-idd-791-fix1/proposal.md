## Problem

#791 的 verify 第 1 輪（comment 6908144440）判 FAIL，三個 Blocking 都出在 spectra-verify 之後改的兩處：

- 清理先刪探測目錄、再停探測的 process group。兩步之間計時器還活著，它照舊路徑以 `: >` 寫標記，會跟著 symbolic link 走；在共用的 `TMPDIR` 裡，別的使用者可以讓它截斷別處的檔。
- 探測改成先看逾時標記、再看結束碼，並把「結束碼 0 但輸出檔不在」算成逾時。沒有 requirement 寫這件事。
- 計時器在探測的 shell 還在時也刪輸出檔，所以 CLI 在第 8 秒前後以 0 回答時被報成逾時，契約探測接著叫人重建一支正常的 CLI。

## Root Cause

計時器在兩個分支都刪輸出檔，探測只好先看標記；清理順序改成讓計時器在刪目錄時還活著，也讓它在名字釋出之後還可能寫入。標記的寫法與探測結果的分類都沒有 requirement 涵蓋。

## Proposed Solution

- 計時器以 noclobber 寫標記：標記的路徑上已經有東西（檔案或 symbolic link，不論指向是否存在）就不寫。
- 計時器只在探測的 shell 不在時刪整個目錄，那個 shell 還在時不碰輸出檔。結束碼 0 一律讀輸出；標記只決定非 0 的結束碼算不算逾時。
- 清理先停探測的 process group，再刪目錄。
- 殘留的情形改成不封閉的清單；Requirement 1 限定在 `TMPDIR` 保持可寫時。
- `--version` 探測回 125 時，仍印「CLI 不在 PATH 上」那一行再停。

## Non-Goals

- 目錄建好、輸出檔卻建不出來時仍報成 CLI 失敗：沒有穩定的測法，不在這一輪加沒有測試的新行為。它與契約探測逾時被報成要重建、訊息裡的 `TMPDIR` 沒有長度上限、兩個內部變數進了 CLI 的環境，合成一張 follow-up issue。

## Success Criteria

- 探測的 shell 被停住、計時器動手時，標記路徑上的 symbolic link 不會被寫穿。
- CLI 在計時器留下標記之後以 0 回答時照常讀輸出，版本與契約兩次探測都是。
- CLI 只在 `~/bin`、`TMPDIR` 不能用時，仍印「不在 PATH 上」。
- 上面每一項的測試在 `7689f5f2` 的 hook 上失敗，修好之後通過。

## Impact

- Affected specs: session-start-cli-check
- Affected code:
  - Modified: plugin/hooks/check-cli.sh, Tests/AkashicCLITests/CheckCLIHookTests.swift, changelog/2026-11-16-check-cli-probe-tempdir-791.md, plugin/CHANGELOG.md, .githooks/plugin-shell-versions.txt
