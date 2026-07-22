# Akashic-Library Phase 2 — MCP 整合設計

- 日期：2026-07-22
- 狀態：已與鄭澈逐節確認（brainstorming session）
- 前置：Phase 1 已完結（#1 closed，PR #8；store + AkashicKit + CLI 落地 main，實庫 536 entries）
- 本 spec 涵蓋：schema 前置（#2+#3）、akashic-mcp server、發布統一

## 1. 決策記錄

| # | 決策 | 選擇 |
|---|------|------|
| 1 | 與 follow-ups 的順序 | **schema 類（#2、#3）併入 Phase 2 前置**；#4–#7 留 backlog |
| 2 | MCP 形態 | **新獨立 akashic-mcp**；che-zotero-mcp 過渡期並存、斷奶後淡出 |
| 3 | 寫入範圍 | **衍生層寫入**：akashic namespace、resolve apply、import 觸發、庫外新 entry；biblatex 面向唯讀（歸 pull 管） |
| 4 | 實作路線 | **A：in-repo executable target**（共用 AkashicKit，零抽離） |
| 5 | 命名 | **`akashic-mcp`**（Akashic 品牌家族，不用 che-* 前綴） |
| 6 | 發布 | che-mcps sign+notarize pipeline → psychquant marketplace；**che-biblatex-mcp 一併補上 marketplace**（發布通道統一） |

Out of scope：embeddings/語意搜尋、App（Phase 3）、Zotero 斷奶、#4 citekey rename、#6 structured creator names、#7 store 硬化（backlog）。

## 2. 架構

```
Akashic-Library repo（既有，單 repo）
├── Sources/akashic-mcp/        ← 新 executable target（swift-sdk MCP）
├── Sources/akashic/            ← CLI（不動）
└── AkashicKit 8 modules        ← #2/#3 前置動 Core/StoreIO/ZoteroImport
```

三段推進：**(1)** schema 前置 → **(2)** akashic-mcp（TDD）→ **(3)** 發布統一。

## 3. Schema 前置（#2 + #3）：hash-based update

### 3.1 機制

`provenance` 新增兩欄（strict known-key set 同步擴充；舊檔缺欄位＝合法 optional，不 quarantine）：

```yaml
provenance:
  zotero_key: ABCD1234
  zotero_version: 123
  library_id: 1              # 新：Zotero libraryID
  zotero_hash: "a1b2c3…"     # 新：mapping 產出的 biblatex 面向 hash（FNV/SHA 皆可，定一種）
  imported_at: …
```

**update 條件**：`item.version > stored_version OR mapping_hash(item) ≠ stored_zotero_hash`。

hash 涵蓋：mapped type/title/normalized date/mapped fields/author displays/attachment refs——即 pull 管的整個 biblatex 面向。一個機制同時解：

1. **#2 date 正規化**——正規化邏輯改變 → hash 變 → 既有 entries 下次 import 自動更新（不需 migration 指令）。
2. **#3 本機未同步修改**——Zotero 內容變但 version 沒 bump → hash 變 → 抓到。
3. **未來 mapping 演進**——fieldMap 改版自動全量 re-apply，不留新舊格式並存。

（akashic namespace 保護、resolved-author 保護、quarantine guard 等 Phase 1 契約全部不變。）

### 3.2 date 正規化規則（#2）

Zotero raw date → 正規化：抓 ISO-ish 前綴（`YYYY[-MM[-DD]]`），`00` 月/日截斷（`1989-00-00 1989` → `1989`）；`2025-04-01` 保留全形；解析不了 → 保留原字串、import report `unnormalizedDates` 列出。citekey 年份抽取不受影響。

### 3.3 libraryID 與附件（#3）

- `ZoteroReader` 讀 `items.libraryID`；**預設只拉 personal library（libraryID = 1）**；`--library-id` CLI/tool 參數可覆蓋。
- fixture schema 補 `libraryID` 欄 + group library 測項。
- linked attachments（非 `storage:` 前綴）：從靜默忽略改為 report 計數（`skippedLinkedAttachments`）。

### 3.4 驗收

實庫全量 re-import：預期一次性大量 update（hash 初建 + date 正規化生效），第二次 import 回到零變更（idempotent 恆成立）。

## 4. akashic-mcp 工具面（14 tools）

| 類 | Tool | 說明 |
|---|---|---|
| 讀 | `akashic_search` | 欄位篩選（author/journal/tag/type/year range） |
| 讀 | `akashic_get_entry` | citekey → 完整 entry（含 akashic namespace） |
| 讀 | `akashic_relations` | citekey + kind ∈ {same-journal, same-author, cites, cited-by, related} |
| 讀 | `akashic_graph` | focus/depth/format（mermaid/dot/graphml 文字） |
| 讀 | `akashic_export` | citekeys 子集或全庫 → bib／csl-json |
| 讀 | `akashic_people` | 人物列表／查詢 |
| 讀 | `akashic_doctor` | stats + quarantine + unresolved 報告 |
| 寫 | `akashic_set_status` | akashic.status |
| 寫 | `akashic_tag` | tags 增刪 |
| 寫 | `akashic_link` | relations 增刪（cites/related） |
| 寫 | `akashic_resolve_people` | 列候選＋**逐候選 apply**（#5 的 MCP 面兌現；CLI 面留 backlog） |
| 寫 | `akashic_create_entry` | 庫外手動文獻（無 provenance，citekey 自動生成） |
| 寫 | `akashic_add_person` | 建人物實體 |
| 寫 | `akashic_import_zotero` | 觸發 pull，回完整 report |

- **寫入邊界**：只碰衍生層。biblatex 面向與 Zotero 來源 entry 的 title/authors/fields **無**寫入工具。
- **Library 解析**：同 CLI（`AKASHIC_LIBRARY` env → `~/.akashic/config.yaml`）；mcpb user_config 可帶路徑。
- **Index freshness**：每次 tool call 比對 `entries/` 最新 mtime vs index mtime，stale 就地重建；寫入工具尾端自動重建。
- **併發**（MCP 與 CLI 並用）：per-file atomic write、last-wins、index 冪等重建；單人場景足夠，README 註明。

## 5. 發布統一

- **akashic-mcp**：release 從 Akashic-Library repo 出；`make release-signed` 模式（`DEVELOPER_ID` + `NOTARY_PROFILE=che-mcps-notary`）→ universal binary + mcpb → `psychquant-claude-plugins` plugin shell（wrapper auto-download、SessionStart 檢查、`.mcp.json`）。
- **che-biblatex-mcp**：補 plugin shell + marketplace entry（用既有 binary release，不動 code）。
- repo 維持 private（自用優先；wrapper 下載對本人 gh auth 可用）。公開發布是未來獨立決定（屆時走 PsychQuant 安全稽核 gate）。

## 6. 測試

- hash-update 四情境：version bump／hash 變（含 date 正規化觸發）／都沒變（unchanged）／初次 hash 補建。
- libraryID 過濾（fixture 加 group library items）。
- MCP tool handlers 對 temp library fixture 的 unit tests（QueryFixture 模式）＋一條 end-to-end（server 起動 → tool 呼叫 → store 變更驗證）。
- 全套件維持綠（Phase 1 的 97 tests 不得回歸）。

## 7. 交付物

1. Schema 前置：hash 機制 + date 正規化 + libraryID + linked-attachment 報告；實庫全量 re-import 驗收（§3.4）。
2. `akashic-mcp` executable target（14 tools）+ 測試。
3. 發布：akashic-mcp signed/notarized + marketplace 上架；che-biblatex-mcp 補 marketplace。
4. docs：store-format v1.1（provenance 新欄位、date 正規化規則）、README 更新（MCP 使用方式）。
