# Akashic Store 格式規格書（v1，Phase 1）

Akashic library 的 canonical store 格式。本文件是 spec §4 的正式版；
實作＝`AkashicCore`（型別/YAML/citekey）＋ `AkashicStoreIO`（讀寫）。

原則：**檔案是本體，資料庫是 cache**。`entries/`、`people/`、`notes/` 是 canonical、
git 追蹤；`.akashic/` 下一切可全刪重建。

## 1. Library 佈局

```
<library-root>/
├── entries/<citekey>.yaml    每筆文獻一檔
├── people/<person-key>.yaml  人物實體
├── notes/<citekey>/*.md      衍生筆記（自己的產出）
└── .akashic/                 衍生物（index.sqlite 等）；gitignored、可重建
```

附件不在 library 內：PDF 進外部 attachment pool 或留在 Zotero storage，
entry 只記 reference（見 §2.4）。

## 2. Entry 檔（`entries/<citekey>.yaml`）

### 2.1 範例（全欄位）

```yaml
id: 7C1F6C2E-1A2B-4C3D-9E8F-000000000001
citekey: cheng2025identifiability
type: article
title: Identifiability of polychoric models with latent elliptical distributions
authors:
  - key: cheng-che              # 已解析 → people/cheng-che.yaml
  - literal: Hau-Hung Yang      # 未解析裸字串
date: 2025-04-01
fields:                          # 其餘 biblatex 欄位（字串→字串）
  journaltitle: Psychometrika
  volume: "90"
  number: "2"
  doi: 10.1017/psy.2025.1
attachments:
  - zotero: storage/ABCD1234/paper.pdf    # 相對 Zotero 資料目錄
  - pool: 2025/cheng2025identifiability.pdf  # 相對 attachment pool
provenance:                      # Zotero namespace——pull 管理、可覆寫
  zotero_key: ABCD1234
  zotero_version: 123
  imported_at: 2026-07-22T00:00:00Z
  orphaned_at: 2026-08-01T00:00:00Z        # 僅 Zotero 端已刪時出現
akashic:                         # Akashic namespace——pull 絕不觸碰
  tags: [identifiability, polychoric]
  status: published
  relations:
    cites: [olsson1979maximum]   # citekey 或 UUID；庫外引用允許
    related: [foldnes2019bivariate]
```

### 2.2 必要欄位

`id`（UUID，不可變）、`citekey`、`type`、`title`。其餘皆可省略；空集合不寫出。

### 2.3 雙 ID 與 citekey 規則

- `id`：UUID，配發後永不變。citekey 改名不斷鏈（index/graph 內部以 UUID 對齊）。
- `citekey`：`^[a-z0-9][a-z0-9-]*$`。自動生成規則（2026-07-22 定案）：
  **小寫第一作者姓 + 年份 + 標題首個實詞**（如 `cheng2025identifiability`）。
  - 姓：ASCII 摺疊（Müller→muller）；單欄姓名取最後一個 token；CJK 無 ASCII → `anon`。
  - 年：date 中第一組 4 位數字；無 → `nd`。
  - 首實詞：跳過冠詞/介系詞 stopwords；CJK 標題無 ASCII 實詞 → `entry`。
  - **衝突**：年份後插 `b`、`c`…（`cheng2025bidentifiability`）；26 個用盡後 `-2`、`-3`。

### 2.4 附件 reference

一律相對路徑，不記絕對路徑（換機器不斷鏈）：
- `zotero:`＝相對 Zotero 資料目錄（`storage/<attachmentKey>/<檔名>`）。
- `pool:`＝相對 attachment pool root。
Phase 1 的 Zotero pull 只記 `zotero:` reference、不搬檔。

### 2.5 Namespace 契約（CRITICAL）

| 區塊 | 擁有者 | pull 行為 |
|------|--------|-----------|
| biblatex 面向（type/title/authors/date/fields/`zotero:` 附件） | Zotero（過渡期） | 版本較新時覆寫 |
| `provenance` | pull 機制 | 覆寫 |
| `akashic`、`pool:` 附件、`id`、`citekey` | Akashic/使用者 | **絕不觸碰** |

特例：**已解析的作者**（`key:` 形式）是使用者確認過的衍生知識——pull 更新時
若 entry 含任何 `key:` 作者，整個 authors 欄保持不動（import report 列於
`authors preserved`）。`akashic.tags` 只在**建檔**時從 Zotero seed 一次。

### 2.6 Orphan 語意

Zotero 端刪除 ≠ Akashic 刪除。pull 只在 `provenance.orphaned_at` 蓋時間戳，
檔案保留，人工裁決（刪檔或抹掉 provenance 轉為純 Akashic entry）。

## 3. 人物檔（`people/<person-key>.yaml`）

```yaml
key: chen-chun-houh          # kebab-case 穩定字串
names:                       # aliases；第一個是顯示名
  - Chun-Houh Chen
  - 陳君厚
  - C.-H. Chen
orcid: 0000-0002-…           # 可選
openalex: A5017…             # 可選
note: 中研院統計所            # 可選
```

解析紀律：**絕不自動合併**。`akashic resolve-people` 只列 alias 完全命中的
高信心候選（同 alias 對到 2+ 人＝歧義、不出候選），`--apply` 是顯式第二步。

## 4. 衍生物

- `.akashic/index.sqlite`：查詢/圖形用 index，`doctor`/import 尾端全刪重建。
- `.bib`／CSL-JSON：`export-bib` 匯出的**編譯產物**（ADR #10），不是資料本體。
- 同作者/同期刊等關係由 metadata 推導；只有 `akashic.relations`（cites/related）
  是儲存的關係資料。

## 5. 版本與相容

本格式為 v1。未來欄位新增採「未知欄位＝decode 錯誤」的嚴格策略（Phase 1）；
放寬為 tolerant-preserve 屬 Phase 2 議題（涉及 round-trip 保真）。
