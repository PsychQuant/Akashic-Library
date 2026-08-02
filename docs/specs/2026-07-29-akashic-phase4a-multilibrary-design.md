# Akashic Phase 4a — 多 library（membership views）設計

> **Superseded（2026-08-02，#23 / #30）**：本文件多處寫「strict decode：未知欄位仍拒」——那是 v1.2 的行為。**v1.3 起開放層（entry / person / library 頂層 + `akashic` nested）容忍未知欄位並逐字保留**；strict 只留在 `authors` / `attachments` / `provenance` / `akashic.relations`。以 `docs/store-format.md` §5 為準。

日期：2026-07-29　狀態：#13 實作中（issue #13 decision comment 為裁定來源）

## 理念定錨

Akashic＝阿卡夏記錄＝**記錄一切**：canonical store 是全集、不分割。「library」（如中研院、心理學）是**成員集合視角**——差別只在「要不要把這篇文章加入該 library」，不是把資料拆進不同 root。people／graph／index 天然共用。**與 Zotero 脫鉤**：membership 只存在 akashic 衍生層，Zotero pull 永不讀寫。目前單一使用者；多使用者留未來（不在本輪）。

## Store format v1.2（對 v1.1 的 additive 變更）

### 1. Entry 衍生層新欄位

```yaml
akashic:
  status: reading
  tags: […]
  libraries: [sinica, psychology]   # 新增：所屬 library keys；預設 []＝只屬全集 view
  relations: {…}
```

- `libraries` 元素必須符合 `StoreKey` 格式（`\A[a-z0-9][a-z0-9-]*\z`）；write 時驗證，違者拒寫。
- 空陣列不序列化（與 tags 同慣例）；strict decode：未知欄位仍拒。
- **衍生層歸屬**：`akashic` namespace → Zotero pull 的 update/restore 不動它（既有分離保證）。

### 2. `libraries/` registry（新頂層目錄）

```
library-root/
  entries/
  people/
  libraries/            # 新增
    sinica.yaml
    psychology.yaml
```

`libraries/<key>.yaml`（metadata-only；成員關係在 entry 上，不在此檔）：

```yaml
key: sinica
name: 中研院
description: 選填
```

- key＝檔名 stem＝StoreKey 格式；load 時語意驗證（格式不符或 stem 不符 → quarantine，沿 #11 慣例）。
- strict decode（未知欄位拒）。

### 為什麼 per-entry 而非 central 成員清單

membership 跟著 entry 走：citekey rename 免第三處遷移（rename 的 relations 遷移機制不需擴展）、與 status/tags 同一寫入邊界與 merge 行為、Zotero 脫鉤自動成立。registry 檔只承載顯示 metadata，兩檔同時改的衝突面最小。

## 三面 surface

| 面 | 新增 |
|----|------|
| CLI | `akashic library list` / `create <key> --name <名> [--description]` / `add <key> <citekey>` / `remove <key> <citekey>`；`akashic query --in-library <key>`（`--library` 已是 root 路徑 flag） |
| MCP | `akashic_libraries` tool（action: list/create/add/remove——衍生層寫入邊界內）；`akashic_search` 加選填 `library` 參數 |
| App | Sidebar「Libraries」區：全部＋各 library 切換（AppState.filterLibrary）；detail 唯讀顯示所屬 libraries。**App 端 membership 編輯留 follow-up**（本輪 view/filter only） |

## 查詢語意

- `library` 篩選＝`akashic.libraries` 含該 key 的 entries（index `entry_libraries(entry_uuid, library_key)` 表）。
- 未指定 library＝全集（既有行為零變化；536 entries 零遷移）。
- 篩選與既有 author/year/journal/tag 篩選可疊加（AND）。

## 相容性

- 舊檔（無 `libraries` 欄位）decode 為 `[]`——additive。
- **注意**：新檔（含 `libraries`）在 Phase 3 以前的 binaries 下會因 strict decode 被 quarantine；單機單使用者、三面同 repo 同版釋出，可接受（store-format 版本備註記載）。
- 刪 library：registry 檔移除後，殘留在 entry 上的 key 成 dangling reference——`doctor`/load 不視為錯誤（同 relations 可指庫外的慣例），CLI `library list` 只列 registry 檔。
