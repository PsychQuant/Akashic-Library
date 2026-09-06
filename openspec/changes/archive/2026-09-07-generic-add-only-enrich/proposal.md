## Why

`enrich-from-zotero`（#340）把「只補不存在的鍵」這條 add-only 紀律做進了 `ZoteroEnrichment.plan`，但它只吃 Zotero item。#423／#455 之後 store 裡有 148 筆以 DOI 為鍵的摘要存檔（`sources/`）與其他非 Zotero 來源（Crossref／OpenAlex／人工查證），要把它們補進 work 的 `fields` 今天沒有任何面收得下——唯一的路是手改 YAML，而那正是 `replace-endnote-and-zotero` 第 4 條要防的安靜失敗。#458 的 decision（2026-09-03）裁定：add-only 政策只能有一份，抽成 generic core，Zotero 版降為 adapter；輸入以 citekey 或 DOI 定位；DOI 反向命中多筆時拒絕並具名；一篇文章有兩個摘要時分兩個鍵收。

## What Changes

- 新增 `Sources/AkashicCore/AddOnlyEnrichment.swift`：`Proposal { citekey | doi（二擇一）, fields, date?, authors[] }` → `Result`（每筆一個分類：`added`／`skipped`／`ambiguous`／`notFound`／`rejected`，加上逐鍵 `Addition`）。欄位政策**逐字**自 `ZoteroEnrichment.plan` 搬入：只補 `fields` 裡 nil 的鍵；`issn` 一律拒（住 venue）；`doi`／`pmid`／`isbn` 走結構化欄位、部分解析的殘留保留在 `fields`；`date` 空才補；`authors` 空且旗標開才補 literal；`type`／`title`／`venues`／`attachments` 不動。
- DOI 定位：`doi` 命中恰一筆 → 對回 citekey；命中 ≥2 筆（store 實測 37 組同題同年不同 DOI 的攣生）→ 該筆 `ambiguous`，具名全部命中的 citekey，零寫入；命中 0 → `notFound`。DOI 相等是 `identity-is-judged-not-matched` 的識別碼例外，所以對回 citekey 可以由程式做（`two-kinds-of-edits`：程式編輯）。
- 雙摘要：`fields` 裡第一個摘要用鍵 `abstract`，第二個由呼叫端具名——知道語言用 `abstract-<lang>`、不知道用 `abstract-2`，經 `FieldKey.normalized` 落地為 `abstract_es`／`abstract_2`。core 不猜鍵名、不拼接、不只收第一個。
- `Sources/AkashicZoteroImport/ZoteroEnrichment.swift` 改成 adapter：找 item → 以既有 probe 產 `Proposal` → 委派 core。既有 `ZoteroEnrichmentTests`（22 支（#340 時 12 支，其後隨 #394 各輪成長；測的是「零改動綠」不是支數））**零改動**即驗收等價。
- CLI 新 subcommand `enrich --from <file.json> [--apply] [--include-absent-authors]`（`Sources/akashic/EnrichCommand.swift`，註冊進 `Sources/akashic/CLI.swift`）；`--apply` 走 #298 的破壞性目標閘（`Sources/akashic/DestructiveTargetGate.swift` 加一列）。
- MCP 新 tool `akashic_enrich(proposals:, dry_run:, include_absent_authors:)`（`Sources/akashic-mcp/Server.swift`；service 面 `AkashicService.enrich`），`dry_run` 預設 true、不設閘——契約差異沿 `akashic_enrich_from_zotero` 那列。
- 兩份規則表各加一列：`.claude/rules/mcp-cli-parity.md`（MCP 表 `akashic_enrich` ↔ `enrich`）與 `.claude/rules/two-kinds-of-edits.md`（generic enrich：程式編輯——只補不存在的鍵、來源給什麼收什麼、不判定）。
- 報告：摘要的來源（sha256 存檔 digest）只進報告、不進 store；每筆 `Addition` 帶 key／value 摘要（`displaySafe`）；`ambiguous` 逐筆列出命中的 citekey。

## Capabilities

### New Capabilities

- `add-only-enrichment`: 以 citekey 或 DOI 定位一筆 work，只補 `fields` 裡不存在的鍵（含結構化識別碼、date、literal authors 的既有政策），DOI 多筆命中拒絕並具名，雙摘要分鍵；Zotero 版是它的 adapter；CLI 與 MCP 兩面同一條實作路徑。

### Modified Capabilities

（none）——既有的 entry-source-reference 與 provenance-reference 兩份 spec 的要求不變：摘要來源不進 work 的 references（值域只收識別碼，#394 §5；擴值域是 #450 的裁決）。

## Impact

- Affected specs: `add-only-enrichment`（新）
- Affected code:
  - New: `Sources/AkashicCore/AddOnlyEnrichment.swift`、`Sources/AkashicCore/IdentifierTokenizer.swift`（識別碼 tokenizer 自 StoreIO 搬入——core 要在 Core 重現 ISBN 三態解析；`IdentifierMigration` 自己的 doc 早已記為 #427 follow-up）、`Sources/akashic/EnrichCommand.swift`、`Tests/AkashicKitTests/AddOnlyEnrichmentTests.swift`、`Tests/AkashicMCPTests/EnrichServiceTests.swift`、`Tests/AkashicCLITests/EnrichCLITests.swift`、`changelog/2026-09-06-generic-add-only-enrich.md`
  - Modified: `Sources/AkashicZoteroImport/ZoteroEnrichment.swift`（adapter）、`Sources/AkashicZoteroImport/ZoteroMapping.swift`（自 `applyBiblatexFields` 抽出 `mappedFields`／`normalizedDate`，pull 與 adapter 同一份對映）、`Sources/AkashicStoreIO/IdentifierMigration.swift`（tokenizer 一族改為轉發 `IdentifierTokenizer`）、`Tests/AkashicMCPTests/StdioE2ETests.swift`（tool 數 31、`akashic_enrich` 乾跑預設與頂層未知鍵拒絕）、`Sources/AkashicMCPKit/AkashicService.swift`（`enrich(proposals:dryRun:includeAbsentAuthors:)`）、`Sources/akashic-mcp/Server.swift`（`akashic_enrich` tool）、`Sources/akashic/CLI.swift`（註冊 `enrich`）、`Sources/akashic/DestructiveTargetGate.swift`（`enrich --apply` 入閘）、`.claude/rules/mcp-cli-parity.md`、`.claude/rules/two-kinds-of-edits.md`、`Tests/AkashicCLITests/PersonCLITests.swift`（service 建構計數 +1，#503 的既有形狀）
  - Removed: （none）
- 依賴方向：core 住 `AkashicCore`（`Entry`、識別碼型別、`FieldKey` 都在那裡）；`AkashicZoteroImport` 只依賴 StoreIO／Core，不反向依賴。
- 相鄰：#340（原形）、#394（結構化識別碼）、#450（第 15 條邊值域——摘要來源進 store 的問題留給它）、#449（pages 回填同族）、#455（批次面一次 load 一次 rebuild——本 core 每次呼叫收一批 proposals，同一形）。
