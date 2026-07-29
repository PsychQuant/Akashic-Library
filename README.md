# Akashic-Library

原生（Swift / macOS）文獻整合系統。核心命題：**文獻資料的 canonical store 由 Akashic 自己擁有**——
metadata 檔案化（per-entry YAML、git 版控）、附件外部化、Zotero 降級為擷取前端（過渡期單向 pull）。

阿卡夏紀錄（Akashic records）＝記載一切知識的圖書館，本義使用。

## 結構

```
AkashicKit（Package.swift）      核心 Swift package：八模組 + akashic CLI
├── Sources/AkashicCore          Entry / Person 型別、schema 驗證、citekey+UUID 規則
├── Sources/AkashicStoreIO       per-entry YAML 讀寫（atomic）、library 掃描
├── Sources/AkashicEntity        人物解析原語（只出候選，絕不自動合併）
├── Sources/AkashicZoteroImport  read-only 讀 zotero.sqlite → diff → 寫 entries
├── Sources/AkashicExport        經 biblatex-apa-swift 出 .bib；CSL-JSON
├── Sources/AkashicIndex         .akashic/ SQLite index 重建
├── Sources/AkashicQuery         結構化查詢（欄位 + 關係：同作者/同期刊/cites/related）
├── Sources/AkashicGraph         關係圖模型、鄰域展開、Mermaid/DOT/GraphML
└── Sources/akashic              CLI：import-zotero / validate / export-bib /
                                 resolve-people / doctor / query / graph
mcps/                            MCP server submodules（che-zotero-mcp、che-biblatex-mcp）
repos/                           共用 library submodules（biblatex-apa-swift = canonical）
docs/                            spec 與 store 格式規格書
library/                         使用者資料（獨立 private git repo；本 repo gitignore）
attachments/                     PDF pool（gitignore；可 symlink 至 Dropbox）
```

## 狀態

- **Phase 1（完結）**：store 地基 — 格式規格、AkashicKit、Zotero 單向 pull、CLI。
  Spec：[docs/specs/2026-07-21-akashic-library-phase1-design.md](docs/specs/2026-07-21-akashic-library-phase1-design.md)
- **Phase 2（本階段）**：MCP 整合 — schema hash 機制、`akashic-mcp`（14 tools）、發布統一。
  Spec：[docs/specs/2026-07-22-akashic-library-phase2-mcp-design.md](docs/specs/2026-07-22-akashic-library-phase2-mcp-design.md)
- **Phase 3（本階段）**：原生 App — 管理工作台（人工裁決 GUI）+ Canvas 關係圖。
  Spec：[docs/specs/2026-07-22-akashic-library-phase3-app-design.md](docs/specs/2026-07-22-akashic-library-phase3-app-design.md)

## App（AkashicApp）

```bash
cd AkashicApp && xcodegen generate && xcodebuild -scheme AkashicApp build   # 或直接開 Xcode
```

管理工作台：Sidebar 健康總覽、列表＋詳情（biblatex 唯讀／衍生層可編／rename）、
裁決台三頁籤（People 逐候選、Orphans 三選——刪檔進垃圾桶可救回、Quarantine）、
原生 Canvas force-directed 關係圖（拖拉/縮放/雙擊展開）。
外部變更（CLI/MCP/git）由 file watcher 自動刷新。`akashic rename <old> <new>` CLI 同步提供。

## MCP（akashic-mcp）

marketplace 安裝：`claude plugin install akashic-mcp@psychquant-claude-plugins`。
Library 解析：`$AKASHIC_LIBRARY` → `~/.akashic/config.yaml`（`library: <path>`）。

多 library（#13，membership views）：`akashic library list/create/add/remove` 管理具名
成員集合（如 `sinica`、`psychology`），`akashic query --in-library <key>` 篩選；MCP 有
`akashic_libraries` tool 與 `akashic_search` 的 `library` 參數；App sidebar 可切換 view。
store 永遠是全集——library 只是視角，成員關係存在 entry 的 `akashic.libraries`（與 Zotero 脫鉤）。
⚠ 並發限制：對**同一 entry** 並發執行 membership 寫入（CLI 與 MCP 同時 `library add/remove`）
不保證安全——read-modify-write 無跨程序鎖，後寫者可能靜默蓋掉先寫者（跨程序鎖為 #7
store 硬化範疇）。`create` 為 exclusive-create（並發同 key 恰一方成功）。單一操作者依序使用不受影響。
工具面：15 tools——7 讀（search/get_entry/relations/graph/export/people/doctor）+ akashic_libraries（list/create/add/remove）+
7 寫（**只碰衍生層**：set_status/tag/link/resolve_people 逐候選/create_entry 庫外/add_person/import_zotero）。
biblatex 面向唯讀——過渡期歸 Zotero pull 管。並發（MCP 與 CLI 並用）：per-file atomic
write、last-wins、index 冪等重建（單人場景設計）。

## Build & Test

```bash
swift build
swift test
```

## Submodules

```bash
git submodule update --init          # mcps/ 為 private repo，外部 clone 可能無權限（optional）
```

`repos/biblatex-apa-swift` 是 AkashicExport 的必要依賴（SPM path dependency）。
