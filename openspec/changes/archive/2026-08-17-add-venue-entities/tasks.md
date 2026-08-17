## 1. Core 型別與序列化

- [x] 1.1 `Sources/AkashicCore/Venue.swift`：`Venue` 型別（design D1：單一 kind＋封閉 type；design D2：names 平面 list＋authorized、names 項選填時間段重用 Temporal）＋ `validate()`——落實 requirement: Venue entity shape 與 requirement: Venue name history timeline。驗收：`VenueTests.testUnknownTypeRejected`、`testNameTimelineSegments` RED→GREEN
- [x] 1.2 `Sources/AkashicCore/YAML.swift`：`venue:` 形狀 encode/decode（strict keys、canonical form）＋ `EntityKind` 加 `venue`——落實 requirement: Venue entity shape 的 round-trip scenario 與 requirement: Closed set of top-level shape labels 的解碼半邊。驗收：encode(decode(x))==x 測試
- [x] 1.3 `Entry.venues` 有序二態 ref list（design D3；元素 `- key:`／`- literal:`；非法元素整檔拒讀）——落實 requirement: Entry venues reference edge 的形狀半邊。驗收：`EntryVenuesTests` 兩態＋拒讀三向量

## 2. Store 層與 gate

- [x] 2.1 舊 binary 行為實測（design D5 的實測義務）：format-10 binary 對含 `venue:` 檔的 copy store 跑 enumerate／validate，行為記錄進 docs/store-format.md bump 論證——支撐 requirement: Store format gate 的 rationale 條款與 requirement: Closed set of top-level shape labels 的不靜默條款。驗收：實測輸出貼進完成記錄
- [x] 2.2 `Sources/AkashicStoreIO/StoreVersion.swift` supported=11＋`docs/store-format.md` v11 條目＋`Sources/AkashicStoreIO/LibraryStore.swift` venue 寫入 gate——落實 requirement: Store format gate（format 10 store 拒寫 scenario）。驗收：`testVenueWriteRefusedOnFormat10`
- [x] 2.3 `LibraryIndex` 反向索引 `idx_venues_key`＋編年排序查詢——落實 requirement: Entry venues reference edge 的反向現算條款（design D3）與 requirement: Chronological presentation 的資料面（design D7）。驗收：index 測試含空集合（零篇 ≠ 查無）

## 3. Migration 與 importer

- [x] 3.1 `Sources/AkashicStoreIO/VenueMigration.swift`（design D4：dry-run 預設、目標 store 回顯、tracked+clean、只加不改、idempotent）——落實 requirement: Venue backfill migration。驗收：`VenueMigrationTests` 二跑零變更＋部分已有不動
- [x] 3.2 importer 產生 `.literal` venue ref（design D4 對映：journaltitle／booktitle／publisher hint，不寫死 type）；fields 照舊——落實 requirement: Entry venues reference edge 的 literal-first scenario（Importer never guesses）。驗收：round-trip 斷言 literal 存在且 fields 未變
- [x] 3.3 copy store 演練：dry-run＋`--apply`＋validate＋idempotent 重跑——requirement: Venue backfill migration 的 additive-idempotent scenario 實證。驗收：回填記錄全數成功（估算 754，實測 803/803——store 於估算後成長；冪等重跑 0 planned）

## 4. 讀寫面（MCP＋CLI）

- [x] 4.1 `AkashicService`：`venue(key:)`（記錄＋沿革＋編年 list、零篇顯式——design D7）、`venues()`、`addVenue`、`resolveVenues`——落實 requirement: Chronological presentation（empty-venue scenario）與 requirement: Venue MCP and CLI parity 的單一路徑前提（design D6）。驗收：service 測試
- [x] 4.2 MCP 面（design D6 表）：`akashic_venue`／`akashic_venues`／`akashic_add_venue`／`akashic_resolve_venues`＋`akashic_add_organization`／`akashic_resolve_organizations`——落實 requirement: Venue MCP and CLI parity 與 requirement: Organization single-record MCP faces。驗收：stdio 煙測
- [x] 4.3 CLI 面（design D6 表）：`venue`／`venues`／`add-venue`／`resolve-venues`——落實 requirement: Venue MCP and CLI parity 的 CLI 半邊與 requirement: Chronological presentation 的讀取面。驗收：CLI 測試
- [x] 4.4 `.claude/rules/mcp-cli-parity.md` 兩表補齊全部新格＋機械稽核零缺格——requirement: Venue MCP and CLI parity 的 audit scenario 與 requirement: Organization single-record MCP faces 的登錄條款。驗收：稽核輸出
- [x] 4.5 `.claude/rules/entity-backlink-completeness.md` 封閉列舉加第 14 條邊＋稽核重跑——requirement: Entry venues reference edge 的 no-stored-article-list scenario 落 rule。驗收：表與 EntityKind.allCases 零差集

## 5. Skill 與收尾

- [x] 5.1 plugin/skills `akashic-venue-verify`（查證、異形正規化、consensus、verdict）——#304 scope「需要的 skill 都要做」；支撐 requirement: Venue MCP and CLI parity 的查證工作流。驗收：skill 檔＋plugin CHANGELOG
- [x] 5.2 全套測試綠＋演練 store validate 全綠＋docs/README v11 列——requirement: Store format gate 與 requirement: Venue entity shape 的整體驗收（design Migration Plan 步驟 1-2）。驗收：swift test 輸出
