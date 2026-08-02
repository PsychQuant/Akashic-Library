# Akashic-Library — 總體架構與 Phase 1 設計

- 日期：2026-07-21
- 狀態：已與鄭澈逐節確認（brainstorming session）
- 本 spec 涵蓋：總體願景、架構決策記錄、**Phase 1（store 地基）詳細設計**
- Phase 2（MCP 整合）、Phase 3（App）各自另開 spec

## 1. 願景與定位

Akashic-Library 是一個原生（macOS / Swift）的文獻整合系統。核心命題：**文獻資料的
canonical store 由 Akashic 自己擁有**，Zotero 降級為擷取前端與同步來源之一。
Akashic 是比 Zotero 更全面的資料庫——差異化在衍生知識層（人物實體、引用圖譜、
筆記、embedding）與 git-first 的資料形態。

受眾定位：**自用優先，架構留發布餘地**。第一優先服務鄭澈的研究 workflow，
但不寫死個人路徑/帳號；未來可照 che-mcps pipeline（sign + notarize + marketplace）發布。

命名：**Akashic-Library**（阿卡夏紀錄＝記載一切知識的圖書館，本義使用）。
與 AI4o 的「阿卡夏」構成同一品牌家族（刻意）。

## 2. 架構決策記錄（ADR 摘要）

| # | 決策 | 選擇 | 備註 |
|---|------|------|------|
| 1 | 產品形態 | 全部都要：umbrella 治理 + 統一工具面 + 原生 App + 資料層 | 分三期，每期獨立 spec→plan→實作 |
| 2 | 資料主權 | **Akashic 自建 canonical store** | Zotero 降級為 sync 來源 |
| 3 | Store 形態 | **混合：metadata 檔案化（git）、附件外部化** | 純文字 canonical + 可重建衍生 index |
| 4 | Zotero 過渡 | **過渡期單向 pull**（Zotero→Akashic） | 使用者可繼續用 Zotero；新衍生知識只寫 Akashic |
| 5 | 人物一致性 | **人物升格 first-class entity**（key + aliases + ORCID/OpenAlex） | 漸進 resolve，絕不自動合併 |
| 6 | 受眾 | 自用優先、留發布餘地 | config 驅動、無寫死路徑 |
| 7 | 命名 | Akashic-Library | repo：`PsychQuant/Akashic-Library` |
| 8 | 歸屬與結構 | **PsychQuant + umbrella meta-repo（submodules）** | 首發布走 PsychQuant 安全稽核 gate |
| 9 | 推進路線 | **A：地基先行**（store → MCP → App） | 見第 4 節分期 |
| 10 | `.bib` 地位 | **降級為編譯產物**（從 store 匯出） | 資料庫本體是 per-entry YAML |
| 11 | 查詢與圖形 | **查詢 API 一級公民**；關係查詢（同作者/同期刊/引用/相關）＋圖形輸出（Mermaid/DOT） | 互動式視覺化留給 App（Phase 3） |

## 3. 總體架構

### 3.1 Umbrella 佈局

```
/Users/che/Developer/Akashic-Library/     ← umbrella meta-repo（remote: PsychQuant/Akashic-Library）
├── AkashicKit/                  ← 核心 Swift package（umbrella 本體內容）
├── mcps/                        ← MCP server submodules
│   ├── che-zotero-mcp           ← submodule（原 repo 不搬家；可同時被 che-mcps 引用）
│   └── che-biblatex-mcp         ← submodule（同上）
├── repos/                       ← 共用 library / 相關 repo submodules
│   └── biblatex-apa-swift       ← submodule（立為 canonical）
├── docs/
│   └── specs/                   ← 本 spec 與後續 spec
└── attachments/                 ← PDF pool（gitignored；要 Dropbox 備份可 symlink）
```

> **2026-08-02 更新（#37）**：資料**不再**住在本 repo 底下的 `library/`。store 的家是
> `~/.akashic/`（見 §4.1）。umbrella 的 `.gitignore library/` 保留作防呆，避免有人又在那建一個。

- `mcps/` 收工具面（MCP servers）、`repos/` 收共用程式庫；未來 App 若抽成獨立 repo 也進 `repos/`。
- **程式碼 repo ≠ 資料 repo**：`library/` 是 nested 獨立 git repo（remote 推 kiki830621
  private），umbrella gitignore 它——umbrella 未來公開發布時，個人文獻庫完全不在其 git 歷史裡。
- `biblatex-apa-swift` 現況是 che-mcps 資料夾內的鬆散 clone（未登記 submodule），且 macdoc
  另有 `bib-apa-swift` 家族＋一份重複 clone。本專案將 `PsychQuant/biblatex-apa-swift`
  立為唯一 canonical；macdoc 血脈的收斂列為後續工作（不在 Phase 1 scope）。

### 3.2 分期

| Phase | 內容 | Spec |
|-------|------|------|
| **1（本 spec）** | Store 格式定案 + AkashicKit + Zotero 單向 pull + `akashic` CLI | 本文件 |
| 2 | MCP 整合：store MCP 工具面、che-biblatex-mcp 上 marketplace、發布通道統一 | 另開 |
| 3 | AkashicApp（SwiftUI GUI），站在 AkashicKit 上 | 另開 |

## 4. Store 格式（資料層規格）

### 4.1 資料 repo 佈局

```
~/.akashic/                       ← store root ＝ akashic home ＝ private git repo 根（#37）
├── entries/<citekey>.yaml        ← 每筆文獻一檔
├── people/<person-key>.yaml      ← 人物實體
├── notes/<citekey>/*.md          ← 衍生筆記（自己的產出，git 追蹤）
├── config.yaml                   ← registry（files/current）；gitignored
└── index/<key>.sqlite            ← 衍生 index，依 registry key 命名；gitignored、可全刪重建
```

> **2026-08-02（#37）**：原本寫的是 `library/` 住在程式碼 repo 底下、index 走 in-store
> `.akashic/`。兩者都改了——store 搬到 `~/.akashic/`，index 搬出 canonical 樹。理由見
> `Sources/AkashicStoreIO/AkashicHome.swift` 的 doc comment。**未註冊**的 store（`--library`
> 直指）仍走 in-store `.akashic/index.sqlite` 回落。

附件不在資料 repo 內：pool 在 umbrella 的 `attachments/`（gitignored），
過渡期 Zotero 既有 PDF 留在 `~/Zotero/storage/` 只記 reference。

### 4.2 Entry 檔（`entries/<citekey>.yaml`）

Schema 對齊 biblatex 資料模型（`biblatex-apa-swift` 可 1:1 對映）。示意：

```yaml
id: 7c1f6c2e-…                    # 不可變 UUID（機器身分；citekey 改名不斷鏈）
citekey: cheng2025identifiability # 人類可讀、可改名
type: article                     # biblatex entry type
title: "Identifiability of polychoric models with latent elliptical distributions"
authors:
  - key: cheng-che                # 已解析 → 引用 people/ 的 person key
  - literal: "Hau-Hung Yang"      # 未解析 → 裸字串（漸進升格）
date: "2025"
fields:                           # 其餘 biblatex 欄位（journaltitle/volume/pages/doi/…）
  journaltitle: Psychometrika
  volume: "90"
  number: "2"
  doi: "10.…"
attachments:
  - zotero: "storage/ABCD1234/paper.pdf"   # Zotero reference（相對 ~/Zotero/）
  - pool: "2025/cheng2025identifiability.pdf"  # pool 相對路徑（絕不記絕對路徑）
provenance:                       # Zotero namespace——pull 管理、pull 可覆寫
  zotero_key: ABCD1234
  zotero_version: 123
  imported_at: 2026-07-21T00:00:00Z
akashic:                          # Akashic 自有 namespace——pull 絕不觸碰
  tags: [identifiability, polychoric]
  status: published
  relations:                      # 需要「存」的關係（可選）；同作者/同期刊由 metadata 推導、不存
    cites: [olsson1979maximum]    # 引用（citekey 或 UUID）；Phase 1 手動、Phase 2 OpenAlex 自動補
    related: [foldnes2019bivariate]  # 人工標記的相關文章
```

要點：

1. **雙 ID**：`id`（UUID，不可變）＋ `citekey`（可讀、可改名）。
2. **作者二態**：`key`（引用人物實體）或 `literal`（未解析字串）。
3. **欄位 namespace**：`provenance` 歸 pull 管、`akashic` 歸使用者/衍生工具管，
   pull 更新只動 biblatex 欄位與 `provenance`，永不覆寫 `akashic`。
4. 附件記 pool 相對路徑或 Zotero reference，換機器不斷鏈。

### 4.3 人物實體（`people/<person-key>.yaml`）

```yaml
key: chen-chun-houh
names:
  - "Chun-Houh Chen"
  - "陳君厚"
  - "C.-H. Chen"
orcid: "0000-…"          # 可選
openalex: "A123…"        # 可選
note: 中研院統計所        # 可選
```

- key 為 kebab-case 穩定字串；aliases 收在 `names`。
- Zotero 沒有這層——這是 Akashic「更全面」的具體差異點之一。

### 4.4 使用者設定

- `~/.akashic/config.yaml`：指向 library root（多 library 未來可擴充）。
- `library/.akashic/` 內 local config：attachment pool 路徑、Zotero 資料目錄路徑。
- 全部 config 驅動，無寫死路徑（發布餘地）。

## 5. AkashicKit（核心 Swift package）

單一 package、模組化拆分；Phase 2 的 MCP 與 Phase 3 的 App 都吃同一份。

| Module | 職責 |
|--------|------|
| `AkashicCore` | Entry / Person / Attachment 型別、schema 驗證、citekey+UUID 規則 |
| `AkashicStoreIO` | per-entry YAML 讀寫（atomic write）、library 掃描載入 |
| `AkashicEntity` | 人物解析原語：alias 比對、ORCID/OpenAlex 查核介面（只出候選，不自動合併） |
| `AkashicZoteroImport` | read-only 讀 `zotero.sqlite` → diff → 寫 entries |
| `AkashicExport` | 經 biblatex-apa-swift 出 `.bib`；CSL-JSON 輸出 |
| `AkashicIndex` | `.akashic/` SQLite index 重建（全文；embeddings 之後掛） |
| `AkashicQuery` | 結構化查詢 API（index 之上）：欄位篩選（作者 key/期刊/年份/tag/type）、關係查詢（同作者、同期刊、cites/cited-by、related）、組合條件 |
| `AkashicGraph` | 關係圖模型（節點＝entry/person/venue；邊＝authored-by / published-in / cites / related）、鄰域展開（某篇文章的 N 度關係圈）、匯出 Mermaid / DOT / GraphML |

- 依賴方向單向往下：`Export/Import/Index → StoreIO → Core`；`Query/Graph → Index`。
- **同作者/同期刊等關係由 metadata 推導**（index 建好即得，不另存）；只有引用（cites）
  與人工標記（related）是儲存的資料（entry 的 `akashic.relations`）。
- 圖形輸出走文字格式（Mermaid/DOT）：CLI 直接可用（`mmdc`/`dot` render），
  且 Claude artifact 原生渲染 Mermaid——Phase 2 MCP 接上後「畫出這篇的引用鄰域」零額外成本。
  互動式視覺化是 Phase 3 App 的事。
- `biblatex-apa-swift` 只被 `AkashicExport` 依賴——store 本體不綁任何 bib 格式。
- CLI `akashic` 是 AkashicKit 上的薄殼：`import-zotero` / `validate` / `export-bib` /
  `resolve-people` / `doctor`（檢查 index 一致性）/ `query`（結構化查詢，表格或 JSON 輸出）/
  `graph`（`--focus <citekey> --depth N`，輸出 Mermaid/DOT）。

## 6. 資料流

### 6.1 Zotero pull（核心流）

```
zotero.sqlite (read-only)
  → 讀全部 items + zotero item keys
  → 對照 store 內 provenance.zotero_key：
       新 key                     → 建新 entry（citekey 自動生成、UUID 配發）
       已有 key、Zotero 版本較新   → 只更新 biblatex 欄位 + provenance（akashic namespace 不動）
       store 有、Zotero 已刪       → 標記 orphaned（不自動刪，人工裁決）
  → 附件：記 Zotero 儲存路徑為 reference；可選 copy 進 pool
```

### 6.2 衍生流

entries 變動 → import 尾端或 `akashic doctor` 重建 index → `export-bib` 隨需產
`.bib`（整庫或 per-manuscript 子集）。所有衍生物可全刪重建；git 只追蹤
entries / people / notes。

### 6.3 查詢與圖形流

```
akashic query --author chen-chun-houh --year 2020..2026     → index 查詢 → 表格/JSON
akashic query --same-journal-as cheng2025identifiability     → 推導關係查詢
akashic graph --focus cheng2025identifiability --depth 2     → 鄰域展開 → Mermaid/DOT
```

查詢一律走 index（毫秒級）；圖形＝查詢結果的另一種輸出形態，同一套 `AkashicQuery` 底層。

### 6.4 人物解析流（漸進）

import 時 author 一律先進 `literal`；`akashic resolve-people` 列出高信心候選
（同 ORCID、alias 完全命中）→ 人工確認 → literal 升格為 key 引用。
**絕不自動合併**——同名不同人是學術書目的經典地雷。

## 7. 錯誤處理與邊界

- **`zotero.sqlite` 永遠 read-only**（沿用 che-zotero-mcp 紀律）；Zotero 開著也能安全讀（WAL snapshot）。
- **Atomic write**：entry 寫入走 temp file + rename，中斷不留半寫檔。
- **驗證失敗不靜默**：schema 不合的 entry 載入時列報告、標 quarantine，不默默略過。
- **Orphan 不自動刪**；**人物不自動合併**。
- **隱私**：第三方 PDF 永不進 git remote；資料 repo private；umbrella 公開化前不含任何個人資料。

## 8. 測試

TDD、80% 覆蓋紀律：

- `AkashicCore`：schema round-trip（entry → YAML → entry 無損）。
- `AkashicZoteroImport`：fixture sqlite 測四情境——新增 / 更新 / orphan / idempotency
  （連跑兩次 import，第二次零變更）。
- `AkashicExport`：golden `.bib` 檔比對（借力 biblatex-apa-swift 既有 APA 驗證）。
- `AkashicQuery` / `AkashicGraph`：fixture library 測欄位篩選、同作者/同期刊推導、
  cites 雙向（cites/cited-by 對稱）、鄰域深度截斷；Mermaid/DOT 輸出 golden 檔比對。
- CLI：integration test（temp library 全流程）。

## 9. Phase 1 交付物

1. Umbrella repo scaffold（`mcps/`、`repos/` submodules、gitignore、README）。
2. Store 格式規格書（本 spec §4 的正式版，放 `docs/`）。
3. AkashicKit 八模組 + 測試。
4. `akashic` CLI（import-zotero / validate / export-bib / resolve-people / doctor / query / graph）。
5. 實際跑通：鄭澈的 Zotero 全庫 pull 進 `library/`，git 首 commit。

## 10. 不在 Phase 1 scope

- MCP 工具面（Phase 2）；App（Phase 3）。
- macdoc `bib-apa-swift` 血脈收斂（後續獨立工作）。
- 雙向 sync、Zotero 斷奶、embeddings/語意搜尋（`AkashicIndex` 只留掛載點）。
- 引用圖譜遷移（che-zotero-mcp 的 graph_* 資料之後再接）。
- **OpenAlex 自動補 cites**（Phase 2，經 MCP 的 `academic_get_citations` 管道）；Phase 1 的 cites 靠手動標記。
- **Venue 實體層**（`venues/`，比照 people 的 alias 正規化）：Phase 1 同期刊查詢用
  journaltitle 字串比對，venue 升格實體是後續擴充（schema 已預留 literal→key 同構模式）。
- 互動式圖形視覺化（Phase 3 App）；Phase 1 只出 Mermaid/DOT/GraphML 文字格式。
