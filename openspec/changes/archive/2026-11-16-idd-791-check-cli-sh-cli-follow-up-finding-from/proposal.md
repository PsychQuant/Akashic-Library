## Why

akashic-mcp plugin 的 SessionStart 檢查（`plugin/hooks/check-cli.sh`，#775）探測 CLI 時，暫存狀態是散在 `TMPDIR` 的兩個檔：只有輸出檔的名字經 `mktemp` 保留，逾時標記檔是同名加 `.timeout`，清理只靠探測子 shell 的 EXIT trap。#775 verify r3 指出三個後果：共用 `TMPDIR` 時標記檔可被預放（截斷別的檔、一般失敗被報成逾時）；hook 被 SIGKILL 時兩個檔留在 `TMPDIR`；`mktemp` 失敗時回 1，和 CLI 自己回 1 分不開，於是一支正常的 CLI 被報成執行失敗、還被叫去重建。

## What Changes

- 探測的暫存檔放進 `mktemp -d` 建的私有目錄，清理時整個目錄刪掉。
- 組內計時器在第 8 秒先刪輸出檔；探測的子 shell 還在就寫標記，不在就刪整個目錄。
- `mktemp -d` 失敗時探測回專用值 125（CLI 自己回 125 改成 1）；hook 收到 125 就說是自己建不出暫存目錄，不印 ✓、不說 CLI 失敗，之後不再比契約與落後。
- 新 capability `session-start-cli-check` 記這三個行為；檔頭「已知的界線」改成修完之後的情形。

## Non-Goals

- 不處理 hook 其他部分的行為（落後判定、分岔比對的成本，後者是 #793）。
- 不宣稱完全不會殘留：計時器檢查子 shell 之後 hook 才死、或 PID 被重用時，目錄仍可能留下，寫進界線說明。
- 不把 #775 既有的其他行為補寫成規格。

## Capabilities

### New Capabilities

- `session-start-cli-check`: SessionStart 檢查探測 akashic CLI 時暫存檔的位置與清理，以及建不出暫存目錄時的回報

### Modified Capabilities

(none)

## Impact

- Affected specs: session-start-cli-check (new)
- Affected code:
  - Modified: plugin/hooks/check-cli.sh, Tests/AkashicCLITests/CheckCLIHookTests.swift
  - New: changelog/2026-11-16-check-cli-probe-tempdir-791.md
  - Removed: (none)
