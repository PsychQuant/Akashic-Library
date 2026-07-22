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
- Phase 3：原生 App（另開 spec）。

## MCP（akashic-mcp）

marketplace 安裝：`claude plugin install akashic-mcp@psychquant-claude-plugins`。
Library 解析：`$AKASHIC_LIBRARY` → `~/.akashic/config.yaml`（`library: <path>`）。
工具面：7 讀（search/get_entry/relations/graph/export/people/doctor）+
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
