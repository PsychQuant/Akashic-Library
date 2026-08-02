## Why

「中研院」目前是一個**字串**——存在 `PersonProfile.affiliations` 的時間軸裡，型別是 `TemporalValue.value: String`。`AkashicCore` 裡 organization 這個概念是零（已查證）。

但它是世界裡的東西：它有身分、有歷史（改名、合併）、有東西指向它（它僱人、它含各所、它出版）。把它存成字串的後果：

- 「2010 年誰在中研院」只能靠字串比對，而「中央研究院」／「中研院」／`Academia Sinica` 是同一個機構的三種寫法。
- 機構自己的歷史無處可放——改名之後，舊記錄指向的字串就成了孤兒。
- 「統計所隸屬中研院」這種機構之間的關係完全無法表達。

而這個問題在同一個 repo 裡**已經解過一次**：`Author` 是 `.key(String) | .literal(String)` 的 sum type，`RelationalExport` 把理由寫下來了——「不需要『是否已歸戶』的旗標欄位，**缺席本身就是資訊**」。同一帖藥沒有推廣到隸屬，是目前最大的結構債。

依 `add-formal-concept-boundary` 的判準：organization 通過形狀選擇測試——它沒有 citekey、沒有作者、沒有職級，它有成立年、上級機構、名稱變體。第三種形狀。

## What Changes

1. **organization 成為第三種記錄形狀**，住在 canonical entity namespace，由 `organization:` 標籤標示（依 `add-entity-shape-label` 建立的機制）。
2. **隸屬的值從字串升成指涉或字面**，沿用 `Author` 的既有模式。遷移時現有字串全部成為字面值——無損，且「尚未歸戶」由缺席本身表達，不加旗標欄位。
3. **person→org 與 org→org 是兩個 predicate、兩個欄位**，不合併成一個共用的隸屬關係。work **不得**取得機構欄位。
4. 關聯式匯出新增機構表，隸屬時間軸的值改為可作外鍵，字面值以 NULL 表達。

## Non-Goals

- **不引入通用邊表**，不引入 predicate 的 meta-schema。依 `add-formal-concept-boundary` 的 D5。
- **不做機構的自動辨識或爬取**。歸戶是獨立操作，本 change 只提供型別與判別。
- **不改 work 的任何欄位**。一篇論文看似有機構隸屬，那是作者當時隸屬的簡寫，是衍生物。
- **不合併 `libraries/`**，不改 person 的其餘維度（職級、行政職、聘任、領域仍是字串時間軸）。
- **不強制歸戶**。字面值是合法的長期狀態，與未歸戶作者同理。

## Capabilities

### New Capabilities

- `organization-entity`: 機構作為第三種記錄形狀，及隸屬的指涉化

### Modified Capabilities

(none)

## Impact

- Affected specs: organization-entity
- Affected code:
  - New: `Sources/AkashicCore/Organization.swift`、`Tests/AkashicKitTests/OrganizationTests.swift`
  - Modified: `Sources/AkashicCore/Temporal.swift`、`Sources/AkashicCore/YAML.swift`、`Sources/AkashicStoreIO/LibraryStore.swift`、`Sources/AkashicStoreIO/StoreVersion.swift`、`Sources/AkashicExport/RelationalExport.swift`
  - Removed: (none)
