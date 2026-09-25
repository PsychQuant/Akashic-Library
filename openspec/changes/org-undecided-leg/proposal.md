## Why

change `resolution-verdict-states`（#619）替 resolve-people 與 resolve-venues 開了未決（`resolution-undecided`）的寫入面，org 族沒有（#643）。store 層對三種 holder 本來就通用，只缺寫入面與揭露面：affiliation、parents、團體作者位查過而判不出來時，store 裡仍與「沒查過」同形，#303 campaign 的 org 長尾每輪都要重查。

## What Changes

- `resolve-organizations` 兩面新增未決腿：CLI `--undecided`／`--rests-on`，MCP `undecided`／`rests_on`；單獨呼叫，不與 apply／reject 組合
- 未決 id 的形狀是 `<rowID>@<orgKey>=<說明>`。`rowID` 與列表回傳的回程把手逐字相同：person 與 org holder 是 `holderKey::literal`，團體作者位是 `citekey[i]::literal`
- 解析方式：在每個 `@<StoreKey>=` 的位置試切，前綴必須是列表中已知的 rowID（候選列或歧義條目）。恰好一個位置成立才收；零個或多個都整批拒絕，不猜
- 歧義條目（一個 literal 命中 2+ 個 org）也帶 `id`，可以逐個 org 記未決
- 兩面同契約，沿用 people／venues 的未決腿：整批拒絕、逐筆略過、完全相同＝`alreadyRecorded`；上限是一次 200 個 id、20 個 digest、單句 4,096 位元組；需要 store format ≥ 19
- 揭露：MCP 列表的候選列與歧義條目帶 `undecidedChecks`；CLI 列表逐列印出 rowID、標「查過未決 N 次」，計數行為四態
- CLI 篩選式 `--apply` 排除查過未決的候選並另列，指路以 id 點名的寫入（與 resolve-people 同形，#624）

## Capabilities

### New Capabilities

- `org-undecided-leg`: resolve-organizations 的未決寫入面、id 形狀與解析、列表揭露、CLI 篩選式 apply 的排除

### Modified Capabilities

(none)

## Impact

- Affected specs: `org-undecided-leg`（新）
- Affected code:
  - New: Sources/AkashicMCPKit/OrgUndecidedVerdicts.swift, Tests/AkashicKitTests/OrgUndecidedLegTests.swift, Tests/AkashicCLITests/OrgUndecidedCLITests.swift, changelog/2026-09-25-org-undecided-leg.md
  - Modified: Sources/AkashicMCPKit/AkashicService.swift, Sources/AkashicMCPKit/UndecidedVerdicts.swift, Sources/akashic/Commands.swift, Sources/akashic-mcp/Server.swift, .claude/rules/mcp-cli-parity.md, .claude/rules/two-kinds-of-edits.md
