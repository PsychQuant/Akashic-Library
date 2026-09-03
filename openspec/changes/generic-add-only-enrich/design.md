## Context

`enrich-from-zotero`（#340）是 store 目前唯一的 add-only 補值面：`ZoteroEnrichment.plan(entries:…)` 拿 Zotero item 對照一筆 work，只補 `fields` 裡不存在的鍵，既有值一個都不動。那條政策是對的，但它綁死在 Zotero item 這個輸入形上。#423／#455 之後 store 有 148 筆以 DOI 為鍵的摘要存檔（`sources/`，Psychological Methods 全量匯入時抓的）與其他非 Zotero 來源（Crossref／OpenAlex／人工查證的 pages），今天沒有任何面收得下——唯一的路是手改 YAML（2026-08-28 就差點弄丟一筆 DOI）。

#458 spectra-discuss（2026-09-03）的五條假設全部核可，並補一條雙摘要裁決（Psychological Methods 一篇文章可能有兩個摘要）。本 design 把那份 decision 原封搬進來，實作時以此為契約。

相鄰：#394（識別碼結構化欄位）、#450（第 15 條邊值域——work 的欄位能不能攜帶來源）、#449（pages 回填同族）、#455（批次面一次 load 一次 rebuild）。

## Goals / Non-Goals

**Goals:**

- add-only 政策只有一份：抽成 `AddOnlyEnrichment`（`Sources/AkashicCore/AddOnlyEnrichment.swift`），Zotero 版降為 adapter，既有 12 支 `ZoteroEnrichmentTests` 零改動即驗收等價。
- 輸入以 citekey 或 DOI 定位；DOI 反向命中多筆時拒絕並具名（新分類 `ambiguous`），零寫入。
- 雙摘要分兩個鍵收，core 不猜鍵名。
- CLI `enrich` 與 MCP `akashic_enrich` 兩面同一條實作路徑；契約差異與 `akashic_enrich_from_zotero` 那列相同。

**Non-Goals:**

- 摘要的來源（sha256 存檔 digest）**不進 store**——`Entry.references` 值域只收識別碼（#394 §5）；擴值域是 #450 的裁決，本張不擴。來源只進報告。
- 不做任何「判定」：core 不決定 DOI 攣生中哪一筆才對（那是 divergence 管線的事，#459）；命中 ≥2 就拒絕。
- 不改 `import-zotero` 的 pull 語意（整份替換）；本張只動 add-only 這一族。
- 不加批次專用的 MCP tool（#455 的既有裁決：批次屬操作者規模）；MCP 收一個 `proposals` 陣列是「一次呼叫多筆」，與 CLI 收一個 JSON 檔同形。
- 不處理 `issn`——它住 venue，`ZoteroEnrichment.plan` 已一律拒，逐字搬。

## Decisions

### core 住 AkashicCore、Zotero 版改 adapter

依賴方向決定落點：`AkashicZoteroImport` 只依賴 StoreIO／Core、不依賴 `AkashicEntity`；而 core 需要的東西（`Entry`、`DOI`／`PMID`／`ISBN`、`FieldKey`）全在 Core。Zotero 版改成三步：找 item → 以既有 probe 產 `Proposal` → 委派 core。兩份政策就是兩條會分岔的路徑（`entity-backlink-completeness` 執行細節 2），所以 `ZoteroEnrichment.plan` 的欄位政策**逐字**搬入、不重寫：只補 `fields` 裡 nil 的鍵；`issn` 一律拒；`doi`／`pmid`／`isbn` 走結構化欄位並保留部分解析的殘留；`date` 空才補；`authors` 空且旗標開才補 literal；`type`／`title`／`venues`／`attachments` 不動。

替代：在 `ZoteroEnrichment` 上加一個「generic 入口」再讓 Zotero 路徑走原本的 code——否決，那是兩份政策。

### Proposal 以 citekey 或 DOI 定位，DOI 命中多筆為 ambiguous

148 筆摘要存檔本來就以 DOI 為鍵；DOI 相等是 `identity-is-judged-not-matched` 明列的識別碼例外，所以「DOI → citekey」可以由程式做（`two-kinds-of-edits`：程式編輯）。但 store 實測 37 組同題同年不同 DOI 的攣生（#456），且一筆 work 可有多個 DOI（#394）——反向命中 ≥2 筆時 core **拒絕並具名全部命中的 citekey**，分類 `ambiguous`，零寫入。命中 0 → `notFound`。兩鍵同時給 → 輸入語法錯，整批拒絕（與 #386 的失敗語意分兩類同形：語法錯整批零寫入、狀態不符逐筆略過並具名）。

### 雙摘要分鍵，core 不猜鍵名

一篇文章有兩個摘要時：第一個用 `abstract`，第二個由呼叫端具名——知道語言用 `abstract-<lang>`（如 `abstract-es`），不知道用 `abstract-2`；經 `FieldKey.normalized` 落地為 `abstract_es`／`abstract_2`。這是 `lossless-intake`（來源給兩個就收兩個）與 add-only（既有值一個都不動）唯一同時成立的形：接在同一個 `abstract` 裡結構不可還原；只收第一個是有損。core 不拼接、不自動編號、不猜語言。

### 兩面契約沿 akashic_enrich_from_zotero 那列

CLI `enrich --from <file.json> [--apply] [--include-absent-authors]`：乾跑預設，`--apply` 走 #298 的破壞性目標閘（篩選式批次寫入未指名目標 store 的知情同意）。MCP `akashic_enrich(proposals:, dry_run:, include_absent_authors:)`：`dry_run` 預設 true，**不設閘**——該閘擋的是篩選式批次，而 MCP 收的是逐筆顯式指名（citekey 或 DOI）的清單。`mcp-cli-parity` MCP 表加一列、`two-kinds-of-edits` 加一列（程式編輯）。

### 摘要來源只進報告不進 store

`Proposal` 可帶 `sourceDigest`（sha256）給報告用；`Result` 逐筆回顯，但不寫進 `Entry.references`——值域只收識別碼（`Entry.validateReferenceAttachment`）。要讓 work 的欄位攜帶來源是第 15 條邊的值域裁決（#450），本張不擴。

### Interface depth check

seam＝`AddOnlyEnrichment`（契約 `[Proposal] → Result`）；adapter 恰一個（Zotero）；深度＝政策＋分類＋歧義拒絕；刪除測試：拿掉它，兩面與 Zotero adapter 都失去政策——不是 pass-through。

## Implementation Contract

**Behavior**：呼叫端給一批 `Proposal`，每筆以 citekey 或 DOI 指名一筆 work，帶要補的 `fields`（含可選 `date`、`authors`）。core 對每筆算出「會補哪些鍵」（只補目前不存在的），乾跑只回報告；apply 時寫入並回同一份報告。既有值一個都不動。

**Interface / data shape**

- `AddOnlyEnrichment.Proposal`：`citekey: String?`、`doi: String?`（恰一個非 nil）、`fields: [String: String]`、`date: String?`、`authors: [String]`、`sourceDigest: String?`。
- `AddOnlyEnrichment.plan(entries: [Entry], proposals: [Proposal], includeAbsentAuthors: Bool) throws -> Result`；`Result.items: [Item]`，`Item { proposalIndex, citekey?, category, additions: [Addition], reason?, matches: [String] }`；`category` 封閉五值 `added`／`skipped`（全部鍵已存在）／`ambiguous`（DOI 命中 ≥2，`matches` 列全部 citekey）／`notFound`／`rejected`（如 `issn`、或欄位政策拒絕）；`Addition { key, valueSummary, kind }`，`kind` 封閉四值 `field`／`identifier`／`date`／`authors`（`identifier` 指 doi／pmid／isbn 走結構化欄位）。
- `AkashicService.enrich(proposals: [EntryDraft-like JSON], dryRun: Bool, includeAbsentAuthors: Bool) throws -> String`：一次 load、逐筆 apply、一次 rebuild（#455 的形）。
- CLI `akashic enrich --from <path> [--apply] [--include-absent-authors] [--json]`：`--from` 的 JSON 是 `[Proposal]`；人可讀輸出逐筆印分類與 additions，`--json` 原樣轉印 service payload。
- MCP `akashic_enrich`：`proposals`（object 陣列，同 `Proposal` 形）、`dry_run`（預設 true）、`include_absent_authors`（預設 false）。
- 雙摘要：`fields` 可同時含 `abstract` 與 `abstract-<lang>`／`abstract-2`；鍵經 `FieldKey.normalized`。

**Failure modes**

- 兩鍵同給、兩鍵皆無、`fields` 為空且無 date／authors、`FieldKey.normalized` 回 nil 的鍵 → 輸入語法錯，**整批拒絕零寫入**，錯誤指名第 N 筆。
- `ambiguous`／`notFound`／`rejected` → **該筆略過並具名**，其餘照常；報告逐筆列出。
- 寫入 I/O 失敗 → 逐筆收容進報告的 `writeFailures`，其餘筆照常，仍 rebuild（#455 的既有語意）。
- 沉默的只有一種：`skipped`（全部鍵已存在）——它在報告裡有分類，不是靜默。

**Acceptance criteria**

- `Tests/AkashicKitTests/AddOnlyEnrichmentTests.swift`：雙摘要分鍵（`abstract`＋`abstract-es` → `abstract`＋`abstract_es`，既有 `abstract` 存在時只補第二個）；DOI 命中 ≥2 → `ambiguous` 且 `matches` 含全部 citekey、零寫入；DOI 命中 1 → 對回 citekey；兩鍵同給整批拒絕；`issn` 拒；既有鍵不動。
- `Tests/AkashicMCPTests/ZoteroEnrichmentTests.swift` 12 支**零改動**綠——adapter 等價的驗收。
- `Tests/AkashicMCPTests/EnrichServiceTests.swift`：service 一次 load、dry-run 零寫入、apply 後 rebuild；`Tests/AkashicCLITests/EnrichCLITests.swift`：`--from` 乾跑、`--apply` 走閘、`--json` 同源。
- `bash .githooks/run-guards.sh` 全綠（`parity-table-drift` 認得新列）。

**Scope boundaries**

- In：core、adapter 化、兩面、兩張規則表、changelog、測試。
- Out：`Entry.references` 值域（#450）、DOI 攣生的判定（#459）、`import-zotero` pull 語意、批次專用 MCP tool、App 面。

## Risks / Trade-offs

- [adapter 化改動 Zotero 路徑的行為] → 12 支既有測試零改動是硬驗收；任一支紅即為政策漂移。
- [DOI 正規形不一致（`10.1037/x` vs `10.1037//x`）讓命中數算錯] → 比對走 `DOI` 型別的既有正規化，與 `IdentifierMigration.normalizedUnique` 同一條規則；測試含雙斜線案。
- [`abstract-2` 這種鍵名在 `FieldKey.normalized` 後與既有欄位撞名] → `_2` 後綴由呼叫端具名、core 不自動編號；撞名時是既有鍵存在 → `skipped`，不覆寫。
- [MCP 面一次收千筆 proposals 撐爆 context] → 報告走 `displaySafe` 與 `prefix(20)` 的既有預算（#236）；要全部用 CLI。
- [`--apply` 未指名目標 store] → #298 閘擋；MCP 面不設閘的理由與 `akashic_enrich_from_zotero` 同（逐筆顯式指名）。

## Migration Plan

無資料遷移、無 format bump（只新增 `fields` 鍵、不改形狀）。部署：merge 後 `akashic-mcp` 重啟即得新 tool；CLI 隨 binary。回滾：revert 該 PR，store 內已補的鍵是合法欄位，不需回退。

## Open Questions

- 148 筆摘要存檔的批次餵入腳本（把 `sources/` 的 digest 對回 DOI、組 `[Proposal]`）住 plugin skill 還是 CLI 子命令——本張不裁，先以 `enrich --from` 收 JSON 檔，腳本形狀由第一次實跑決定。
