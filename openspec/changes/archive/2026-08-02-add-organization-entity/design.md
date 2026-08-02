## Context

本 change 依賴 `add-entity-shape-label`：形狀由頂層的裸標籤標示，標籤取自封閉集合。新增第三種形狀是那個封閉集合的第一次擴充，也是它的第一個真實測試。

同時本 change 受 `add-formal-concept-boundary` 的 D5 約束：predicate 以欄位形式住在適用的形狀上，不得引入通用邊表或 predicate 的 meta-schema。

已驗證的現況：`PersonProfile.affiliations` 是 `Timeline`，其元素 `TemporalValue.value` 是 `String`；`AkashicCore` 內零個 organization 概念；`Author` 已經是 `.key | .literal` 的 sum type，`RelationalExport` 已記錄「缺席本身就是資訊」的理由。

## Goals / Non-Goals

**Goals:**

- 讓機構可以被指涉，而不是只能被拼寫。
- 讓機構自己的歷史（改名、上級機構變更）有地方放。
- 讓「尚未歸戶」是一個可查詢的狀態，而不是一個需要旗標的例外。
- 在不引入通用邊表的前提下表達機構之間的包含關係。

**Non-Goals:**

- 不做自動歸戶或機構爬取。
- 不改 work 的欄位。
- 不改 person 的其餘時間軸維度。
- 不強制既有字面值必須歸戶。

## Decisions

### F1：organization 是第三種形狀，標籤為 `organization:`，identity 欄位沿用 `key`

封閉標籤集合由 `work`、`person` 擴充為 `work`、`person`、`organization`。

**identity 欄位就叫 `key`，與 person 相同。** 這在 `add-entity-shape-label` 之前是不可行的——當時形狀要靠欄位組成判別，同名的 identity 欄位會讓兩個形狀無法區分，於是必須發明 `orgkey` 之類的名字。改用標籤之後，判別由標籤負責，`key` 可以回歸單一職責：一個實體的人類可讀鍵。**這是標籤方案在第一次擴充就付現的收益**——不必為了判別而扭曲欄位命名。

機構形狀的欄位：`key`、`id`、`names`（多語言與縮寫變體，各自帶效期）、`founded`、`dissolved`、`parents`（上級機構時間軸）、`note`。**沒有** citekey、沒有 authors、沒有職級——它通過形狀選擇測試。

**替代方案（已否決）：不新增形狀，把機構繼續當字串。** 那正是本 change 要解決的問題：機構的歷史無處可放、名稱變體無法歸一、機構之間的包含關係無法表達。

### F2：隸屬的值升成 sum type，`Timeline` 泛型化

`TemporalValue.value` 對隸屬維度改為 `.key(orgkey) | .literal(String)`，其餘維度（職級、行政職、聘任、領域）維持字串。

實作上把 `Timeline` 泛型化為 `Timeline<V>`，並保留 `Timeline` 為 `Timeline<String>` 的 typealias，使其餘維度的呼叫端逐字不變。

**替代方案（已否決）：在 `TemporalValue` 加一個 `ref: UUID?` 欄位，與 `value` 並存。** 這正是 `RelationalExport` 明文否決過的旗標欄位設計——兩個欄位可以互相矛盾，而且「已歸戶」變成需要額外判斷的狀態，而不是型別本身就說清楚的事。

**替代方案（已否決）：另建一個 `AffiliationTimeline` 結構。** 會複製 `overlappingPairs` 與排序邏輯，而那些邏輯與值型別無關。泛型化只加一個型別參數。

**保留 `Timeline` 的順序無關相等性**——那是 `PersonYAML` encode canary 抓出來的性質，泛型化不得破壞它。

### F3：person→org 與 org→org 是兩個 predicate，不合併

| 關係 | 深層文法 | 欄位 |
|---|---|---|
| 某人 隸屬 機構 | 僱用／成員，有任期、可中斷、可重複 | `Person.profile.affiliations` |
| 子機構 隸屬 上級機構 | 部分-整體，通常隨機構存續 | `Organization.parents` |
| 論文 隸屬 機構 | 不存在 | 無此欄位 |

中文的「隸屬」與英文的 `affiliation` 都只有一個詞，但它們是兩個 predicate（PI 664 表層／深層文法）。合併成一個共用關係就是把定義域攤平，等同於 D5 否決的通用邊表的縮小版。

第三列尤其要守住：一篇論文看起來有機構隸屬，那是作者當時隸屬的簡寫——**衍生物，不得存進正典**。它的正確位置是匯出層的一個 join。

### F4：歸戶偏向過度切分

既有字面值遷移時**全部**成為 `.literal`，不做任何自動合併。之後的歸戶操作若不確定兩個字串是否同一機構，預設切成兩個機構而非合併。

理由沿用 #34 的判準：過度切分可回復（之後合併即可，兩邊的歷史都還在），過度合併不可回復（合併時哪些記錄原本屬於誰的資訊已經消失）。

### F5：匯出層新增機構表，字面值以 NULL 表達

新增 `organization` 表；`researcher_timeline` 的隸屬列新增可空的機構外鍵欄位。**不加「是否已歸戶」旗標**——外鍵為 NULL 就是未歸戶，與 `publication_author.researcher_id` 的既有語意一致，而且 `IS NULL` 直接就是查詢。

### F6：bump store format

新增的形狀讓舊 binary 讀到帶 `organization:` 標籤的檔案時判定為「不認得的形狀」並 quarantine。既有的 refuse-if-newer 把它變成一句「請升級」，而那是正確訊息。本 change 在 `add-entity-shape-label` 之後，因此格式再往上一階。

## Implementation Contract

**Behavior**：機構可以作為獨立記錄存在並被人的隸屬時間軸指涉；未指涉的隸屬以字面值保留；機構之間的包含關係記在機構自己身上；work 無法取得機構欄位。

**Interface / data shape**：

- 新型別：機構記錄與其 YAML 編解碼。
- `Timeline` 泛型化，`Timeline<String>` 的既有呼叫端不變。
- 隸屬維度的值型別由字串變為指涉或字面的 sum type。
- 匯出新增機構表；隸屬列新增可空外鍵。
- store format marker 再進一階。

**Verification**：

- 一筆機構記錄可寫出、載入、且 encode 後逐位元穩定。
- 一筆人的隸屬以字面值載入，未歸戶狀態由缺席表達，無旗標欄位。
- 一筆人的隸屬指向存在的機構時，匯出的外鍵非空；指向不存在的機構時比照懸空作者處理，不憑空造識別碼。
- 既有 536 筆 work 記錄逐字不變仍全部載入。
- 其餘四個時間軸維度的行為與相等性語意（含順序無關）不變。
- 嘗試在 work 上記錄機構隸屬時，沒有欄位可用——由形狀本身擋下，不需要額外檢查。

**Out of scope**：自動歸戶；機構名稱的正規化規則；work 的任何欄位；通用邊表；#54 的 view 機制。
