## Problem

`entities/<uuid>.yaml` 的形狀判別靠 `type:` 欄位，而它接受任何字串：

```swift
let t = map["type"]?.scalar?.string
return t == "person" ? .person : .work
```

實測後果：一個內容為 `type: view` / `title: 中研院的人` 的檔案**通過** `akashic validate`（回報「1 entries 全部通過」），並被 `akashic doctor` 計為一篇著作。一個形式概念被靜默收編成正典實體，不會壞、不會報錯。

## Root Cause

`type:` 這一個 key 同時裝著兩個邏輯層次的東西：

| 值 | 是什麼 | 弄錯的後果 |
|---|---|---|
| `person` | **形式種類**——決定哪些欄位存在、用哪個 decoder | 結構錯誤，整份檔形狀錯，改不動 |
| `article` | **書目類型**——固定形狀裡的一個值，值域開放（實測 9 種且會再長） | 事實錯誤，改一個欄位即可 |

兩者在檔案裡是平輩，所以 `type: view` 看起來是一個自然的第三個兄弟——記法在邀請這個錯誤。而 `? :` 的全稱後備把封閉集合偷偷變成開放集合：任何字串都是實體。

歷史成因：legacy 佈局用**目錄**判別形狀（`entriesDir` 的載入迴圈直接呼叫 EntryYAML 的 decode，完全沒有 peek）。#35 把 `people/` 與 `entries/` 併成 `entities/` 以取得 UUID 身分，判別子因此被逼進檔案裡，成為一個後設欄位的值。

## Proposed Solution

**把形狀名從「某個 slot 的值」改成「一個裸標籤」。** 不設立叫 `kind` 或 `type` 的後設欄位；形狀名本身作為一個沒有值的頂層鍵出現：

```yaml
person:
key: chen-junhou
names: [鄭清水]
```

1. 標籤取自**封閉集合**（目前 `work`、`person`）。不認得的標籤 → quarantine，不猜。
2. 每筆記錄**至少一個**標籤，且標籤的值必須為空。缺標籤或值非空 → quarantine。
3. 標籤可以有多個，用以表達本體的層級與交集。**只寫最具體的那些**——可由 schema 推導的上位標籤不寫進檔案。
4. `type:` 保留為 work 專屬的書目類型欄位，值域維持開放，不再參與形狀判別。
5. store format bump 到 3。向前相容由既有的 refuse-if-newer 負責（#24）。

## Non-Goals

- **不引入 `kind:` 欄位**。見 design 的 E1：它把「種類」物化成 schema 裡的一個可查詢欄位。
- **不改用「欄位組成判別、完全不放標籤」**。曾經是本 change 的方向，已否決：見 design 的 E1。
- **不引入層級推導機制**。上位標籤的推導是將來的事；本 change 只確立標籤可以有多個、且只寫最具體的。
- **不改 legacy 佈局的載入路徑**。`entries/` 與 `people/` 仍由目錄判別，那本來就是對的。
- **不動 `type:` 的書目值域**，不引入書目類型白名單。

## Success Criteria

- 內容為 `type: view` 的 `entities/<uuid>.yaml` 被 quarantine，理由指出缺少形狀標籤，而非通過 validate。
- 帶 `view:` 標籤的檔案被 quarantine，理由指出 `view` 不是已知形狀——**具名**的錯誤。
- 既有 536 筆 work 記錄在補上 `work:` 標籤後全部載入成功，其餘內容逐字不變。
- 一筆帶兩個標籤的記錄能載入，並以最具體的那個決定 decoder。
- 標籤值非空（例如 `person: true`）的記錄被 quarantine。
- 舊 binary 面對 format 3 的 store 回報升級要求，而非誤判。

## Impact

- Affected specs: entity-shape-label
- Affected code:
  - Modified: `Sources/AkashicCore/YAML.swift`、`Sources/AkashicStoreIO/LibraryStore.swift`、`Sources/AkashicStoreIO/StoreVersion.swift`、`Sources/AkashicStoreIO/StoreMigration.swift`
  - New: `Tests/AkashicKitTests/EntityShapeLabelTests.swift`
