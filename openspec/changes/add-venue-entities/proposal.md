## Why

發表載體（期刊／會議／出版社）目前只以裸字串存在（`fields["journaltitle"]` 等，371 個 distinct 期刊、754 篇 work），無法歸戶、無法反查、無法消歧——「這本期刊有哪些文章」在庫裡連問都問不出來。#304 審議（2026-08-16）五項裁決定案：venue 族（期刊＋會議＋出版社）一次到位成為一級 entity，二態 ref（`.key`／`.literal`）依 `literal-first-then-key` 規則進庫，呈現面提供編年文章 list、儲存面攜刊名沿革 timeline。

## What Changes

- **新 EntityKind `venue`**（單一 kind＋封閉 `type` 欄位：`journal`／`conference`／`publisher`）——新頂層形狀標籤 `venue:`，names 採平面 list＋`authorized`（同 organization 模式，不巢狀——#227 不對稱設計延伸）
- **Entry 新增 `venues:` ref 邊**（有序 list，元素二態 `.key`／`.literal`）——正典側為作品側（#300 六理由同構）；反向（venue → 文章編年 list）一律現算（裁決五a）
- **刊名沿革 timeline**：venue 記錄的 `names` 各項可攜時間段（機制同 affiliations 時間軸；裁決五b）——期刊改名史為一級知識
- **literal-first 匯入**：importer（WoS／Zotero）從 `journaltitle`／`booktitle`／`publisher` 欄位產生 `.literal` venue ref；欄位字串保留不刪（lossless-intake）；既有 754 works 回填 migration（dry-run 預設）
- **消歧機制**：`resolve-venues`（CLI＋MCP 兩面）——WoS 全大寫異形（`JOURNAL OF ...` vs `Journal of ...`）為第一天需求
- **MCP／CLI／skill 面**（使用者拍板「需要的都要做」）：`akashic venue`／`akashic_venue`（編年呈現）、`akashic venues`／`akashic_venues`（列舉）、`resolve-venues` 兩面、venue 消歧 skill；**org MCP 面一併裁決**（#304 parity 表移轉：`akashic_add_organization`、`akashic_resolve_organizations`）
- **store format bump**（10 → 11，non-additive）：新頂層形狀對舊 binary 的行為需實測定論；refuse-if-newer 依既有機制
- **Breaking**：無既有 API 破壞；store format bump 依部署程序（binary 先升、真 store 後遷）

## Non-Goals

- 不刪除 `fields` 內的 journaltitle 等字串欄位（lossless；ref 是升格不是取代）
- 不在本 change 內完成 371 期刊的實際消歧（那是 #303 campaign 的執行；本 change 交付機制）
- 不處理 series／叢書等其他載體類——`type` 封閉列舉三值，擴充須修 spec
- 不改動 person／organization 的既有形狀

## Capabilities

### New Capabilities

- `venue-entity`: venue 一級實體——形狀（id/key/names/type/沿革 timeline）、二態 ref 邊、literal-first 生命週期、編年呈現、消歧與 verdict

### Modified Capabilities

- `entity-shape-label`: 頂層形狀標籤封閉集合加入 `venue:`
- `organization-entity`: org 單筆建檔與消歧的 MCP 面（#304 parity 移轉裁決落地）

## Impact

- Affected specs: `venue-entity`（新）、`entity-shape-label`（修）、`organization-entity`（修）
- Affected code:
  - New: Sources/AkashicCore/Venue.swift、Sources/AkashicStoreIO/VenueMigration.swift
  - Modified: Sources/AkashicCore/Models.swift、Sources/AkashicCore/YAML.swift、Sources/AkashicStoreIO/LibraryStore.swift、Sources/AkashicStoreIO/StoreVersion.swift、Sources/AkashicMCPKit/AkashicService.swift、Sources/AkashicMCPKit/Server.swift（經 akashic-mcp target）、Sources/akashic/Commands.swift、Sources/akashic/CLI.swift、docs/store-format.md、.claude/rules/entity-backlink-completeness.md、.claude/rules/mcp-cli-parity.md、plugin/skills（venue 消歧 skill）
  - Removed: （無）
