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
- **Phase 4a**：多 library（membership views）— canonical store 仍是全集不分割，
  library 只是成員集合視角；people / graph / index 共用（#13）。
  Spec：[docs/specs/2026-07-29-akashic-phase4a-multilibrary-design.md](docs/specs/2026-07-29-akashic-phase4a-multilibrary-design.md)
- **Phase 4c**：多「檔案」（多實體 store root）— 每個檔案自成 universe，
  互不相通、不跨檔案共用 people 或 relations（#18）。
  Spec：[docs/specs/2026-07-30-akashic-phase4c-multifile-design.md](docs/specs/2026-07-30-akashic-phase4c-multifile-design.md)

> 上面是**功能**分期。與之正交的還有一份 store 讀取契約的設計：
> [YAML 輸入 profile](docs/specs/2026-08-01-akashic-yaml-input-profile-design.md)（#33，
> 設計定案、實作待 #25 merge）——收窄 store 接受的 YAML 語法子集，讓未知欄位容忍層
> 只需處理「未知的 key」而非「YAML 的全部語法」。

### Store 格式版本

store 是跨 binary（CLI / MCP / App）的契約。格式版本記載於
[docs/store-format.md](docs/store-format.md) §5——**store 檔案本身尚未自我聲明版本**
（version marker 與 refuse-if-newer 防線見 #24）。下表只記各版本的要點：

| 版本 | 要點 |
|------|------|
| v1.1 | provenance hash 欄位 |
| v1.2 | `akashic.libraries` + `libraries/` registry（#13）；未知欄位 **strict → throw** |
| v1.3 | tolerant-preserve（#23）：**開放演化層**（entry / person / library 頂層、`akashic` namespace）的未知欄位改為容忍 + 原樣保留寫回，取代 v1.2 的 throw |

**v1.3 的三個限定，比表格本身重要**：

**1. tolerant 只涵蓋開放演化層。** `authors` 元素、`attachments` 元素、`provenance`、
`akashic.relations` 仍是 **strict 保留層**（closed shape，未知欄位＝decode 錯誤）。
§5 特別註記 `attachments` 那層加新欄位會**原地重演 #23 的失敗模式**。

**2. 讀取面同時嚴格化——升級方向也會咬人。** 部分 v1.2 讀得動的病態檔案在升級後轉為
quarantine，這是刻意的 fail-closed 遷移（詳見 §5「known 欄位的形狀演化」「有損字元
守衛」「顯式 complex key」三個 bullet）：

| 新增拒收 | 觸發條件 |
|---|---|
| known 欄位形狀不符、無法解析的時間戳 | 無條件 |
| tagged-shadow 鍵、merge/value tag 面的鍵 | 無條件 |
| `fields` 的字串面撞名、非隱式 tag 鍵、字串面 `<<`/`=` | 無條件 |
| NEL (U+0085) 內容字元 | 無條件 |
| **顯式 complex key（`? key`）** | 無條件（R11 新增，DoS 防線） |
| LF 檔內的裸 CR | 無條件 |
| **CR / CRLF 行尾** | **僅當檔案含未知欄位**（走區塊切分路徑） |
| **encode 可拒寫** | canary fail-closed；CLI `import-zotero` / `resolve-people --apply` 單筆失敗即非零退出 |

最後兩列是三個 binary 與任何包 CLI 的 script 都要知道的契約變更：**CRLF 使用者不能只看
「LF 檔內的裸 CR」就以為自己安全**（觸發條件恰恰是本 PR 要服務的情境——較新 binary 寫出
的、含未知欄位的檔），而**寫入自 v1.3 起可能失敗**，多檔寫入者必須收容。

**3. 有兩條 carve-out，但它們不是「放寬」。** §5 從 v1.3 新增的嚴格化裡挖回了兩塊 v1.2
既有行為，方向是**避免回歸**，不是 v1.3 開始接受 v1.2 拒收的東西：

- **collection 形狀**的 known 欄位遇 null 視同不存在（`akashic:` 空值行）。**scalar 欄位
  不適用**——`title:` → `""`、`title: Null` → `"Null"`，走字串面。把 null-as-absent 套到
  scalar 是 R8-verify 標為 CRITICAL 的東西（會讓 Zotero 無標題 item 永遠寫不進 store）。
  具名例外只有 `provenance.imported_at` / `orphaned_at` 兩個 Optional 日期。
- **全檔無 LF** 的 classic-Mac lone-CR 檔照常無損載入（CR 是行尾慣例，由 libyaml 正規化）。
  注意這與上表最後第二列不衝突：檔內**有** LF 時，不接 LF 的裸 CR 只能是內容，拒收。

**為什麼要看這段**：舊 binary 讀新 store 的行為由**格式**版本決定；而新 binary 讀舊
store 的行為由第 2、3 點決定。在 #24 落地之前 store 端沒有版本訊號，唯一可用的判斷依據
是消費端的 binary 版本——升級 store 格式前先確認所有消費端（含 marketplace 上的
`akashic-mcp`）都已跟上。

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
工具面：17 tools——8 讀（search/get_entry/relations/graph/export/people/person/doctor）+ akashic_files（list/use——多檔案切換）+ akashic_libraries（list/create/add/remove）+
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
