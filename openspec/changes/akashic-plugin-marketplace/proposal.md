## Why

discovery 路線的五個 skill（#617、#620–#623）需要一個跟 `akashic-mcp` 分開、但同 repo 同 commit 出貨的 plugin；目前 Akashic-Library 不是 marketplace，`akashic-mcp` 由外部 marketplace 以 git-subdir 列出，而且本 repo 的守衛只看得見 `plugin/` 一個目錄——新 plugin 放進來，它的測試被刪掉也不會有任何守衛出聲。本 change 是那五個 skill 的共同前提（#625）。

## What Changes

- 新增 repo 根的 marketplace manifest：名稱 `akashic`，列出 `akashic-mcp`（source 為 `./plugin`，位置不動）與新的 `akashic-discovery`（source 為 `./plugins/akashic-discovery`）。
- 新增 `akashic-discovery` 骨架：manifest 以純字串宣告依賴 `akashic-mcp`（不宣告版本範圍、不打 plugin 版本 tag）；`rules/` 以目錄 symlink 共用 `plugin/rules/`；本 change 不含任何 skill。
- 守衛從單一的「plugin 根目錄清單」展開：受保護清單、trigger-coverage、rule-coverage 都涵蓋每一個 plugin 根；新增一道守衛核對「檔案系統上的 plugin 根」與「marketplace manifest 列出的 source」集合相等；新增對應的 mutations 子命令作負對照。
- rule-coverage 逐根執行；0 個 skill 的 plugin 明確回報 vacuous 並通過。
- CI 觸發路徑涵蓋新目錄與 marketplace manifest。
- `claude plugin validate --json` 在 pre-push（有 CLI 時）執行，任何 error 或允許清單以外的 warning 即失敗（允許清單只有 akashic-mcp 的 `binary_version` 一項）；CI 沒有 CLI 時印出略過訊息，不靜默。
- store-format parity 測試改為正式覆蓋 repo 內的 marketplace 條目描述（原本記為跨 repo、無法覆蓋）；README 與量測斷言改寫成新的安裝方式。
- **BREAKING**（安裝 id）：`akashic-mcp@psychquant-claude-plugins` 由 `akashic-mcp@akashic` 取代。外部 marketplace 端移除舊條目並以 renames 將舊名標為已移除（官方機制不支援跨 marketplace 轉址）；使用者需重新 add marketplace 並安裝。

## Non-Goals (optional)

Non-Goals 與被否決的做法記在 design.md。

## Capabilities

### New Capabilities

- `plugin-marketplace-distribution`: Akashic-Library 作為 marketplace `akashic` 的發布契約——manifest 內容、plugin 佈局約定、plugin 間依賴、安裝 id 遷移。
- `plugin-root-guard-coverage`: 守衛對 plugin 根目錄的涵蓋契約——根目錄清單的單一來源、與 marketplace manifest 的一致性、每一根的受保護清單與 rule-coverage、負對照。

### Modified Capabilities

(none)

## Impact

- Affected specs: `plugin-marketplace-distribution`（新）、`plugin-root-guard-coverage`（新）
- Affected code:
  - New: .claude-plugin/marketplace.json, plugins/akashic-discovery/.claude-plugin/plugin.json, plugins/akashic-discovery/rules, Sources/akashic-guards/PluginRoots.swift, Sources/akashic-guards/MarketplaceConsistency.swift, Sources/akashic-guards/OfficialValidate.swift, Sources/akashic-guards/PluginRootsMutations.swift
  - Modified: Sources/akashic-guards/ProtectedInventory.swift, Sources/akashic-guards/main.swift, Sources/akashic-guards/TriggerCoverageMutations.swift, Sources/akashic-guards/AuditGuardsMutations.swift, plugin/tests/rule-coverage.sh, .githooks/run-guards.sh, .githooks/protected-ratchet.txt, .github/workflows/census-parity.yml, .github/workflows/ci.yml, plugin/tests/plugin-store-format-parity.py, plugin/rules/assertions-must-be-measured.md, README.md
  - Removed: (none)
- 外部 repo：psychquant-claude-plugins 的 marketplace manifest（移除 `akashic-mcp` 條目、加 renames）與其遺留的空目錄；使用者本機的 plugin 安裝與啟用設定。
- 相依：harness-devtools 的 `plugin-update` 要認得 `akashic`，由 PsychQuant/che-plugin-devtools#27 處理，不在本 change 內。
