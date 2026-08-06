## 1. 型別與驗證

- [x] 1.1 在 `Sources/AkashicCore/Provenance.swift` 定義 `ProvenanceReference`，落實 `A provenance reference SHALL record both the retrieval path and the retrieved content`：擷取型帶 `url` / `retrieved` / `status` / `mediaType` / `content`，判斷型帶 `judgement` / `restsOn`。依 `D6：判斷型 reference 是獨立的種類，不是缺欄位的擷取型`，兩者在建構層即互斥。行為：判斷型無法帶 `content`。驗證：`Tests/AkashicKitTests/ProvenanceTests.swift` 斷言判斷型帶 `content` 無法通過驗證。
- [x] 1.2 先寫失敗測試，涵蓋 design.md「Failure modes」表的七種情況各一例，其中兩例對應 `A reference SHALL be able to record a judgement that is not a retrieval`。行為：每種錯誤各有可辨識的錯誤值，不共用泛用錯誤。驗證：測試逐項斷言錯誤內容指名了出問題的欄位或值，僅斷言「有拋錯」不算通過。
- [x] 1.3 實作驗證邏輯直到 1.2 全綠。行為：擷取型缺 `content` 拒收、判斷型帶 `content` 拒收。驗證：`swift test --filter ProvenanceTests` 全數通過。

## 2. YAML 編解碼

- [x] 2.1 先寫 round-trip 測試：一筆含兩種 reference 的記錄，encode 後 decode 回來與原值相等。行為：輸出順序確定（同一份資料每次 encode 位元組相同），避免假 diff。驗證：同一值連續 encode 兩次結果相同。
- [x] 2.2 在 `Sources/AkashicCore/YAML.swift` 實作 `references` 編解碼，依 `D1：provenance 掛在欄位層，不是記錄層`——清單住頂層、每筆自報 `field`。沿用既有慣例：排序後輸出、未知欄位 tolerant-preserve、encode 後 canary 自檢。行為：2.1 的 round-trip 成立。驗證：`swift test --filter ProvenanceTests` 與既有 YAML 測試皆綠。
- [x] 2.3 加向後相容測試，落實 `Existing records SHALL remain loadable` 與 `D7：既有 `TemporalValue.source` 不動`：無 `references` 的既有記錄載入後寫回位元組相同；帶 `TemporalValue.source` 的記錄該值原樣保留且未被轉成 reference。行為：本變更對既有檔案零影響。驗證：測試以真實形狀的既有記錄字串比對完整輸出，而非只比欄位數。

## 3. 記錄整合

- [x] 3.1 [P] `Sources/AkashicCore/Models.swift` 的 `Person` 加 `references` 欄位並接上 2.2 的編解碼。行為：person 記錄可攜帶 reference 且 round-trip 成立。驗證：既有 `swift test` 全綠、無回歸。
- [x] 3.2 [P] `Sources/AkashicCore/Organization.swift` 的 `Organization` 同上。行為與驗證同 3.1。
- [x] 3.3 實作 `field` / `value` 存在性驗證，落實 `A reference SHALL be attachable to a named field`，並依 `D2：collection 內的欄位用「值」定位，不用索引`。行為：指名不存在的欄位或值時拒絕載入，錯誤同時指名欄位與值。驗證：1.2 對應的兩個測試轉綠。

## 4. 存檔儲存

- [x] 4.1 先寫存檔路徑測試，落實 `Retrieved content SHALL be addressed by the digest of its bytes` 與 `D4：存檔住 store 內的 `sources/`，two-char 分片`：路徑為 `sources/<前2字元>/<其餘>`、無副檔名，同一 digest 兩次寫入只有一份檔案。行為：內容定址，相同位元組不重複儲存。驗證：測試注入假 home，斷言檔案數與路徑。
- [x] 4.2 在 `Sources/AkashicStoreIO/LibraryStore.swift` 實作存檔讀寫入口直到 4.1 綠，依 `D3：SHA-256 於原始位元組，不正規化`。行為：位元組原樣寫入、原樣讀回，不做任何轉換。驗證：寫入含 CRLF 與非 UTF-8 位元組的內容後讀回，位元組相同。
- [x] 4.3 `ensureLayout()` 建立 `sources/` 並把排除規則以標記區塊寫入 store 的版控忽略檔，落實 `Stored content SHALL NOT be tracked by the version-control remote` 的寫入面。行為：重跑不重複寫入（idempotent）。驗證：連續呼叫兩次後，忽略檔內該區塊只出現一次。
- [x] 4.4 實作寫入前的排除驗證，落實 `Stored content SHALL NOT be tracked by the version-control remote` 的驗證面，依 `D5：版控排除是 fail-closed 的驗證，不是文件慣例`。行為：store 是 git repo 時以 git 自身判定確認排除生效，未生效拒絕寫入；非 git repo 跳過並記錄跳過事實。驗證：以臨時 store 構造「忽略規則被移除」的情境，斷言寫入被拒且錯誤說明如何修復。
- [x] 4.5 實作 digest 無對應存檔時的回報。行為：載入成功，並以與格式錯誤不同的條件回報內容未在本機——clone 後必然缺席的存檔不被當成損毀。驗證：測試斷言載入成功且缺席條件可與格式錯誤區分。

## 5. 文件與邊界紀錄

- [x] 5.1 `docs/store-format.md` 補 `references` 形狀、`sources/` 佈局與排除規則、以及「digest 缺席是預期狀態」。行為：讀者能從文件判斷一筆 reference 是否完整。驗證：文件含擷取型與判斷型各一個完整範例，且欄位與實作一致。
- [x] 5.2 在 `docs/design-principles-and-philosophy.md` 記錄 `Stored content SHALL NOT occupy the canonical entity namespace` 的兩個獨立理由，特別是內容定址與 entity 判準「名稱改變後仍應被視為同一物」正好相反這一點。行為：日後有人提議把存檔升格為 entity 時，文件能直接回答。驗證：該節同時載明形狀判準與內容定址判準。
- [x] 5.3 對 design.md `Implementation Contract` 逐項收尾：核對 `Behavior` 的每條敘述、`Interface / data shape` 的 YAML 與 Swift 形狀、`Failure modes` 表七列、以及 `Acceptance criteria` 的七項；確認實作未逾越 `Scope boundaries` 的 Out of scope 清單。行為：契約的每一項都有對應的測試或明確的未做紀錄。驗證：逐項列出契約條目與對應測試名稱，缺對應者標明理由，不留空白。
