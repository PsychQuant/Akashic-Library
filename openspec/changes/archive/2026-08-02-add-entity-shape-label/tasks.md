## 1. 標籤的判別

實現 `Record shape SHALL be carried by a bare label` 與
`Shape labels SHALL be drawn from a closed set`，依 design 決定
「E1：形狀名是裸標籤，不是後設欄位的值，也不是完全省略」與
「E2：標籤取自封閉集合，缺席或不認得一律 quarantine」。

- [x] 1.1 先寫失敗測試（RED）：`Tests/AkashicKitTests/EntityShapeLabelTests.swift` 建五個案例——恰一個已知標籤、不認得的標籤（`view:`）、無標籤（內容為 `type: view` 的 #54 實測檔）、標籤帶值（`person: true`）、多標籤。確認無標籤那例目前**通過**（重現缺陷）。
- [x] 1.2 在**專案自己的編碼路徑**上確認裸鍵的往返穩定。已用 Yams 預設的 compose/serialize 實測：`person:` 解析為空字串 scalar，emit 回來仍是 `person:`，逐字穩定。本任務只需在既有 encode 選項（含 canary 自檢）下再驗一次，因為專案的編碼路徑與預設不同。**此為 1.3 的前置**：形狀標籤若在往返中變形，逐位元穩定性就守不住。
- [x] 1.3 實現 `Record shape SHALL be carried by a bare label`：改寫 `Sources/AkashicCore/YAML.swift` 的 `EntityKind.peek`，判別依據從 `type` 的值改為頂層的裸標籤鍵；標籤帶值時擲錯。維持既有的 BOM 剝除與 alias 預算檢查順序不變——那道守衛必須仍是 entities 佈局的第一個動作。
- [x] 1.4 實現 `Shape labels SHALL be drawn from a closed set`：已知標籤集合定義為封閉列舉；不認得的標籤與缺席標籤擲出**兩種不同**的錯誤，`Sources/AkashicStoreIO/LibraryStore.swift` 的 entities 載入迴圈轉成 quarantine，理由分別指名「不認得的形狀 `<名稱>`」與「缺少形狀標籤」。不認得的標籤若是本專案在別處處理的東西（例如 `view`），理由還須指出它該放哪——只說「不認得」等於只證明了它在這個位置沒有意義，讀者還需要知道它在哪個位置有意義。
- [x] 1.5 確認單一無法判別的檔案不中斷整批載入（沿用既有 quarantine 語意），補測試斷言其餘檔案仍載入成功。
- [x] 1.6 依 design 決定「E6：標籤只在 format 3 起強制；舊格式讀取時以欄位組成回退（實作時發現）」：`peek` 增加嚴格度參數，format ≤ 2 時缺標籤以欄位組成回退（citekey → work、key → person），format ≥ 3 時缺標籤即 quarantine。不認得的標籤／標籤帶值／多個互不從屬／與 `type:` 矛盾這四種在兩個格式下都 quarantine。加測試涵蓋兩種格式下的缺標籤行為差異。
- [x] 1.7 跑 1.1 的五個案例（GREEN）。

## 2. 多標籤與 `type:` 的收窄

實現 `A record MAY carry more than one shape label` 與
`The bibliographic type SHALL NOT name a shape`，依 design 決定
「E3：標籤可多個，但只寫最具體的」與「E4：`type:` 收窄為書目類型」。

- [x] 2.1 實現 `A record MAY carry more than one shape label`：標籤解析為集合而非單值；多個已知標籤時以最具體者決定 decoder，可推導的上位標籤回報為冗餘。目前封閉集合（`work`、`person`）無層級關係，因此以測試用的假層級驗證此行為。
- [x] 2.2 實現 `The bibliographic type SHALL NOT name a shape`：`type:` 不再參與形狀判別；person 的 encode 不再輸出 `type: person`，但 `type` 保留在 `knownPersonKeys` 內——移出去會讓既有檔案的該欄位被 tolerant-preserve 當成未知欄位保存並重新寫出，與本 change 的目的相反。
- [x] 2.3 實現矛盾即 quarantine：標籤與 `type:` 指向不同形狀時 quarantine，不得挑一邊。加測試。
- [x] 2.4 確認 work 的 `type:` 值域仍開放——加回歸測試斷言未見過的書目類型（例如 `dataset`）正常載入，不引入白名單。

## 3. 遷移與格式

實現 `Existing records SHALL be migrated without loss` 與
`The store format version SHALL be raised`，依 design 決定「E5：bump store format 到 3，並補標籤到既有檔案」。

- [x] 3.1 實現 `Existing records SHALL be migrated without loss`：在 `Sources/AkashicStoreIO/StoreMigration.swift` 加補標籤遷移，沿用既有的順序紀律——全量預檢（含 encode 預演）、再寫、後刪、最後 bump format。既有標籤者跳過，使重跑為冪等。
- [x] 3.2 加測試：遷移在寫入階段中斷後，無記錄遺失，且重跑可完成而不重複已完成的工作。
- [x] 3.3 實現 `The store format version SHALL be raised`：`Sources/AkashicStoreIO/StoreVersion.swift` 的目前格式由 2 改為 3，且僅在遷移全部步驟成功後才寫入。
- [x] 3.4 加測試：format 3 的 store 被以 format 2 為上限的檢查拒絕並要求升級，且不產生與真正原因無關的 per-file 錯誤。
- [x] 3.5 確認 legacy `entries/` 與 `people/` 的載入路徑**未被觸及**——它們用目錄判別形狀，本來就是對的。驗證方式：這兩個迴圈的 diff 為空。

## 3b. 規範文件的同步（實作 change 1 時發現）

- [x] 3b.1 `docs/design-principles-and-philosophy.md` §4 現行條文寫著「它們的差異由 record 內的 **type**、relations 與 validation grammar 表達，而不是由資料夾表達」。本 change 把形狀判別從 `type:` 的值改成裸標籤，該句因此過時。改寫為：差異由 record 內的**形狀標籤**、relations 與 validation grammar 表達；並保留「不是由資料夾表達」這半句——§4 的「路徑不得編碼 entity type」仍然成立，且正是本 change 否決目錄分段方案的理由之一。
- [x] 3b.2 在 §4 同處加一句說明標籤與 `type:` 的分工：標籤標形狀（封閉集合），`type:` 是 work 專屬的書目類型（開放值域）。避免讀者以為 `type:` 被廢除。
- [x] 3b.3 確認 §11 的判別測試敘述（change 1 寫入，刻意不綁定標示機制）在本 change 之後**仍然逐字成立**，不需修改。若需要修改，代表 change 1 的判準寫得不夠機制無關，應回頭修 change 1 而非在此打補丁。

## 4. 收尾與驗收

- [x] 4.1 跑完整測試套件，確認新增測試通過且既有測試零回歸。
- [x] 4.2 對真實 store 的 536 筆記錄跑遷移，逐檔比對確認除新增的標籤行外逐位元相同（沿用 #35 用 blob SHA 多重集驗證的做法）。
- [x] 4.3 遷移後對真實 store 跑 validate 與 doctor，確認 536 筆全部通過、輸出與變更前一致。
- [x] 4.4 把 #54 的實測檔（`type: view`）與一個帶 `view:` 標籤的檔各丟進暫時 store 跑 validate，確認兩者都被 quarantine，且理由不同、都可操作——這是本 change 的驗收動作。
