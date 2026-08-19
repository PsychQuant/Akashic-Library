## Why

`SourceStore.storeSource(_:provenance:)` 在 #224 落地了完整的 API 層寫入面防護（換行守衛、
O_APPEND、index 過閘、腐壞拒寫），但**全樹零 production 呼叫端**——實測
`grep -rn storeSource Sources/` 只命中宣告本身一次，測試命中 23 次。

也就是說「存一份 source」這個能力**今天只有寫 Swift 的人做得到**。這與 #206 對匯入面的
判準同形：

> 能不能無損匯入，不該取決於使用者會不會寫 script。

而它同時是 `replace-endnote-and-zotero` 的承重結構——那份規則明寫，完全取代 Zotero 意味著
大量第三方版權 PDF 會進入本機 store，`sources/` 的 gitignore 排除與 `SourceStore` 的
fail-closed 驗證因此「從保險升級為承重結構」。一個沒有使用者入口的承重結構，承不了重。

## What Changes

新增兩個對等的使用者入口，走**同一條** service 路徑：

- MCP tool `akashic_store_source`
- CLI subcommand `store-source`

兩面的回應都必須呈現 receipt 的四個欄位，其中兩個是本變更的重點：

- `discardedProvenance` —— 冪等早退時，呼叫端這次交來卻**沒有被寫入**的敘述。
  依 `lossless-intake` 的「丟棄必須可見」，這不能靜默。
- `exclusionVerified` —— 該 blob 是否確認被 gitignore 排除。這是 `sources/` 不進 remote
  的那道 fail-closed 閘的可觀察面。

`provenance-reference` 規格新增一條 requirement：規範入口的存在與 receipt 的可見性。
既有的儲存語意 requirement **不動**。

## Non-Goals

- **不改 `SourceStore.storeSource` 的行為**。寫入面防護已在 #224 完成並經 verify；本變更
  只接呼叫端。任何對該函式的修改都不在範圍內。
- **不新增取回（read）面**。`akashic_files` 一族已有讀取入口；本變更只補「存進去」。
- **不做批次存入**。單筆是最小可用形狀；批次要先回答「部分失敗怎麼回報」，那是另一次裁決。
- **不自動抓取 URL 內容**。呼叫端交來的是**位元組**，不是網址——由本專案抓取會讓
  `retrieved` 的語意從「呼叫端何時取得」變成「工具何時抓的」，兩者不同。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `provenance-reference`: 新增「儲存內容 SHALL 有使用者入口，且 receipt 的丟棄與排除驗證
  結果 SHALL 在回應中可見」的 requirement

## Impact

- Affected specs: `provenance-reference`
- Affected code:
  - Modified: `Sources/AkashicMCPKit/AkashicService.swift`
  - Modified: `Sources/akashic-mcp/Server.swift`
  - Modified: `Sources/akashic/CLI.swift`
  - Modified: `.claude/rules/mcp-cli-parity.md`
  - New: `Sources/akashic/StoreSourceCommand.swift`
  - New: `Tests/AkashicMCPTests/StoreSourceEntryPointTests.swift`
