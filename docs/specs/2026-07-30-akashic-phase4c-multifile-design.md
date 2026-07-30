# Akashic Phase 4c：多「檔案」（多實體 store root）設計

2026-07-30。Issue #18；Clarity 三疑點經鄭澈裁定（decision comment）。

## 需求定錨

- 「檔案」＝**多個實體 store root**：各自獨立資料夾（可各自為 git repo）的完整庫。
- **互不相通**：每個檔案自成 universe——entries／libraries／people／graph／index 各自獨立。不跨檔案共用 people、不允許跨檔案 relations、不提供跨檔案聯集查詢。
- 場景不限制：核心需求就是「能分開」。
- 與 #13 的關係：「store 是全集」降為**檔案內**成立；libraries（membership views）與檔案正交——每個檔案內都可有自己的 libraries。

## Config schema v2（`~/.akashic/config.yaml`，向後相容）

```yaml
library: /path/to/legacy      # 既有欄位，保留（legacy fallback）
files:                        # 新：具名檔案 registry（key 走 StoreKey 規則）
  main: /path/A
  work: /path/B
current: work                 # 新：目前選用的檔案 key
```

- 三欄皆 optional。只有 `library:` 的舊 config 行為完全不變。
- `files` 的 key 必須符合 `StoreKey`（`\A[a-z0-9][a-z0-9-]*\z`）；malformed key 在 parse 時擲錯（config 是使用者自己的檔案，錯了要早叫）。
- `current` 指向不存在的 key → resolution 擲 `invalidCurrent`（不靜默 fallback——指了就要有）。

## Resolution 順序（`LibraryLocator.resolve`）

```
explicit（CLI --library / API 參數）
  → $AKASHIC_LIBRARY
  → config.current + config.files[current]
  → config.library（legacy）
  → notConfigured error
```

explicit 與 env 維持最高優先（自動化與測試的 escape hatch 不變）。

## 三面

| Surface | 介面 | 語意 |
|---|---|---|
| CLI | `akashic file list / add <key> <path> / remove <key> / use <key>` | `add` 註冊＋`ensureLayout`（冪等，路徑不存在即建立完整 layout）；`use` 寫 `current`；`remove` **只除名不刪資料**，若 remove 的是 current 則清空 current（回落 legacy `library`）；`list` 列 registry＋標記 current |
| MCP | `akashic_files`（action: list / use） | `use` 在 server session 內切換 active root（重建 store 參照＋index freshness 跟隨新 root）；不持久化寫 config（server 是讀者）——**設計決策：MCP 的 use 是 session-scoped**，持久預設由 CLI／App 管 |
| App | Sidebar「檔案」picker | 讀 config registry；切換＝AppState root 重指＋全狀態 reload（selection／filterLibrary 清空）；App 的切換同樣 session-scoped（不寫 config） |

## Config 寫回（CLI `file add/use/remove`）

整檔 read-modify-write：parse 成 `AkashicConfig` → 修改 → 重新序列化（`library` → `files`（key 排序） → `current` 順序）。本 schema 之外的未知頂層欄位**保留原行**（不破壞使用者手寫內容）。

## 不做（互不相通裁定）

- 跨檔案搜尋／聯集視圖／跨檔案 relations／people 共用——未來要做是新設計題（新 issue）。
- 檔案間搬移 entries——初版不做（可手動搬 YAML，store 契約自癒）。
