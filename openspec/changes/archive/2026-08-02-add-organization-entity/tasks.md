## 0. 前置

- [x] 0.1 確認 `add-entity-shape-label` 已 apply 且合併——本 change 依賴它的裸標籤判別與封閉標籤集合。未完成前不得開始 1.2。

## 1. 機構形狀

實現 `An organization SHALL be a record shape of its own`，依 design 決定
「F1：organization 是第三種形狀，標籤為 `organization:`，identity 欄位沿用 `key`」。

- [x] 1.1 先寫失敗測試（RED）：`Tests/AkashicKitTests/OrganizationTests.swift` 斷言一筆機構記錄可寫出、載入、且 encode 後逐位元穩定；此時型別尚不存在，測試無法編譯即為紅燈。
- [x] 1.2 實現 `An organization SHALL be a record shape of its own`：把 `organization` 加進封閉標籤集合，並新增 `Sources/AkashicCore/Organization.swift`，欄位為 `key`、`id`、`names`（含變體與各自的效期）、`founded`、`dissolved`、`parents`、`note`。**不得**有 citekey、authors、ranks。`key` 與 person 同名是可以的——標籤已經負責判別。
- [x] 1.3 在 `Sources/AkashicCore/YAML.swift` 加機構的編解碼，沿用既有慣例：未知欄位 tolerant-preserve、encode canary 自檢、`key` 走 StoreKey 驗證。
- [x] 1.4 在 `Sources/AkashicStoreIO/LibraryStore.swift` 的 entities 載入迴圈加入機構分支——判別依 `organization:` 標籤。加測試斷言帶 `key` 但標籤為 person 的記錄仍載入為 person，證明同名 identity 欄位不造成歧義。
- [x] 1.5 加測試：機構改名後，既有的人指向它的參照**不需重寫**仍然有效（參照走 identity 而非名稱）。

## 2. 隸屬的指涉化

實現 `An affiliation SHALL be either a reference or a literal`，依 design 決定
「F2：隸屬的值升成 sum type，`Timeline` 泛型化」與「F4：歸戶偏向過度切分」。

- [x] 2.1 把 `Sources/AkashicCore/Temporal.swift` 的 `Timeline` 泛型化為 `Timeline<V>`，保留 `Timeline` 作為 `Timeline<String>` 的 typealias，使職級／行政職／聘任／領域／聯絡資訊的呼叫端逐字不變。
- [x] 2.2 實現 `An affiliation SHALL be either a reference or a literal`：隸屬維度的值型別改為指涉或字面的 sum type，沿用 `Author` 的既有形狀。**不得**加「是否已歸戶」的旗標欄位——未歸戶由缺席本身表達。
- [x] 2.3 實現 `Resolution SHALL be biased toward splitting`：既有字串遷移時全部成為字面值，零自動合併。加測試斷言兩個相近但不相同的字串遷移後仍是兩筆。
- [x] 2.4 實現 `Existing temporal dimensions SHALL be unaffected`：加回歸測試——帶滿五個維度的 person 記錄 load → encode 逐位元相同，且 `Timeline` 的順序無關相等性未被泛型化破壞（此性質由 encode canary 抓出，見 `Temporal.swift` 的既有註解）。

## 3. 兩個 predicate 分離

實現 `Membership and containment SHALL be distinct predicates`，依 design 決定
「F3：person→org 與 org→org 是兩個 predicate，不合併」。

- [x] 3.1 實現 `Membership and containment SHALL be distinct predicates`：機構的上級關係記在機構自己的 `parents` 時間軸上，與人的 `affiliations` 是不同欄位、不同形狀。**不得**抽出共用的隸屬關係型別。
- [x] 3.2 加測試斷言 work 形狀上**沒有**任何機構欄位——嘗試記錄論文的機構隸屬時無處可放，由形狀本身擋下。此測試是 D5 的迴歸防線。
- [x] 3.3 在 `Organization.swift` 的 `parents` 欄位處加註解，說明為什麼它不與人的隸屬共用型別（中文「隸屬」與英文 affiliation 的表層文法相同、深層文法不同）。

## 4. 匯出與格式

- [x] 4.1 依 design 決定「F5：匯出層新增機構表，字面值以 NULL 表達」：`Sources/AkashicExport/RelationalExport.swift` 新增機構表；`researcher_timeline` 的隸屬列新增可空機構外鍵。**不加**歸戶旗標欄位——外鍵為 NULL 即未歸戶，與既有的作者外鍵語意一致。
- [x] 4.2 懸空參照（隸屬指向不存在的機構）比照懸空作者處理：外鍵留 NULL，不憑空造識別碼；並由 doctor 回報。加測試。
- [x] 4.3 依 design 決定「F6：bump store format」：`Sources/AkashicStoreIO/StoreVersion.swift` 的格式再進一階，並加測試確認舊格式上限的檢查會要求升級。

## 5. 收尾

- [x] 5.1 跑完整測試套件，確認零回歸。
- [x] 5.2 對真實 store 跑 validate 與 doctor，確認 536 筆 work 記錄照舊全部通過。
- [x] 5.3 實測一次端到端：建一筆機構、把一個人的隸屬指向它、匯出、確認外鍵非空；再把另一個人的隸屬留成字面值、確認該列外鍵為 NULL 且可被 `IS NULL` 查出。
