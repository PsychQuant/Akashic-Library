<!-- Traceability. spec 依規定為英文（normative SHALL/MUST）、tasks 依 locale 為繁中，
     故此處以逐字的 requirement 名稱與 design 標題建立對應，供實作者與分析器查核。 -->

## 0. 追溯對照（Traceability）

| Spec requirement（逐字） | Tasks |
| --- | --- |
| A person record SHALL be able to record that the person is deceased | 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7 |
| Recorded precision SHALL be preserved exactly as written | 1.1, 1.4 |
| The absence of a death date SHALL be read as right-censored, not as living | 4.1 |
| A death date SHALL NOT alter any derivation that describes affiliation | 2.1 |
| Academic activity SHALL NOT be recorded as a stored field | 5.1 |
| A deceased person retaining an open affiliation SHALL be reported and SHALL NOT be corrected | 2.2, 2.3, 2.4, 2.5 |
| Adding the death field SHALL NOT change the supported store format version | 4.2, 5.1 |
| The relational export SHALL expose the death date and SHALL state what its status column describes | 3.1, 3.2, 4.3 |

| Design 決策（逐字標題） | Tasks |
| --- | --- |
| 決策 1：範圍取「只記逝世」，不加出生 | 5.1 |
| 決策 2：平的字串欄位，不是複合值——方向決定可逆性 | 1.2 |
| 決策 3：不 bump store format | 4.2, 5.1 |
| 決策 4：`died` 的缺席是**右設限**，不是表達力缺口 | 4.1 |
| 決策 5：活躍度什麼都不加——刪除測試 | 5.1 |
| 決策 6：隸屬狀態欄位不改名，改為新增逝世欄並把語意寫進匯出 schema | 3.1, 3.2 |
| 決策 7：逝世不參與隸屬狀態推導；矛盾只報告不自動修 | 2.1, 2.4 |
| 決策 8：provenance 機制落地前，逝世來源一律寫進既有的 person note 欄位 | 4.2 |
| 決策 9：概念用 deceased，欄位名用 `died` | 4.1, 4.3 |

| Implementation Contract 小節 | Tasks |
| --- | --- |
| behavior | 1.3, 2.5, 3.1 |
| interface / data shape | 1.2, 1.3, 1.5, 2.3, 3.1 |
| failure modes | 1.4, 1.6, 1.7, 2.4 |
| acceptance criteria | 5.2 |
| scope boundaries | 5.1 |

## 1. 模型與 codec（TDD：先紅後綠）

- [x] 1.1 寫出**會失敗**的測試（`Tests/AkashicKitTests/PersonDeceasedTests.swift`）：(a) 帶 `died` 的 person 記錄寫入後載回值不變且未被 quarantine；(b) `2004` / `2004-11` / `2004-11-18` 三種精度載回後與寫入 byte 相同，明確斷言年精度**未**被補成 `2004-01-01`。驗證目標：`swift test` 對這批測試全部紅燈（`died` 尚不存在，編譯失敗即為紅燈）。 （Requirement: A person record SHALL be able to record that the person is deceased；Recorded precision SHALL be preserved exactly as written）
- [x] 1.2 `Person` 新增 `died` 屬性（optional 字串，語意為 ISO 8601 前綴），位置在既有識別碼類欄位之後、`profile` 之前。驗證目標：專案可編譯。
- [x] 1.3 person 的 YAML encode 在 `profile` 之前輸出 `died` 鍵；缺席時**不輸出任何鍵**（不得輸出空字串或 null 佔位）。驗證目標：1.1(a) 轉綠，且新增一個測試斷言無 `died` 的記錄其輸出不含 `died` 字樣。
- [x] 1.4 person 的 YAML decode 以既有形狀檢查機制讀取 `died`（純量）；值為 sequence 或 mapping 時以**點名該欄位**的錯誤拒絕。驗證目標：1.1(b) 轉綠，且新增一個測試對非純量輸入斷言拋錯且訊息含欄位名。
- [x] 1.5 `died` 登記進 person 的 known-keys 集合。驗證目標：新增回歸測試——載入帶 `died` 的記錄後原樣寫回，斷言輸出中 `died` 鍵**恰出現一次**（未登記時 tolerant-preserve 會使其重複輸出而讓測試失敗）。
- [x] 1.6 `died` 納入歧異合併的欄位遺失檢查（`LibraryStore.fieldsLostByMerging`），並把 `personFieldsCoveredByMergeCheck` 由 9 改為 10。**實作時發現的必要步驟**：既有的反射 anti-rot 測試（`testPersonFieldCoverageOfMergeCheck`）會在新增儲存屬性時失敗，訊息明言「否則新欄位會在合併時靜默消失」。驗證目標：該測試轉綠，且新增一個測試證明合併兩筆記錄時倖存者若會丟失 `died` 會被擋下。
- [x] 1.7 `died` 納入 `PersonYAML.encode` 語意 canary 的欄位指認清單。**實作時發現的必要步驟**：`Equatable` 自動合成使偵測本身有效，但指認清單是手寫的，漏列會讓 `died` 不符時的錯誤訊息退化成「未知欄位 key 序列不符」——偵測對而診斷錯。驗證目標：內容審查——canary 的 `bad.append` 序列含 `died`。

## 2. 推導與驗證的契約（TDD）

- [x] 2.1 契約測試釘住「`died` 不影響隸屬狀態推導」：person 隸屬 `1990-09` 至 `2004-11`、`died` 為 `2004-11-18`，匯出後 status 欄仍為 `retired`。驗證目標：測試通過，且以 git diff 確認 `Sources/AkashicExport/RelationalExport.swift` 的 status 推導運算式逐字未改。 （Requirement: A death date SHALL NOT alter any derivation that describes affiliation）
- [x] 2.2 寫出**會失敗**的診斷測試：store 內有一筆帶 `died` 且至少一段 affiliation 仍開放的記錄時，該記錄的 key 出現在報告中。驗證目標：紅燈（查詢尚未存在）。 （Requirement: A deceased person retaining an open affiliation SHALL be reported and SHALL NOT be corrected）
- [x] 2.3 `LibraryStore` 新增查詢，回傳「有 `died` 且至少一段 affiliation 開放」的記錄 key 清單（依字典序），比照既有兩個同型報告函式的形狀。驗證目標：2.2 轉綠。
- [x] 2.4 該診斷**只報告不修正**：跑完診斷後該 person 檔案內容與跑之前 byte 相同；該記錄不進 quarantine、不阻擋 `load()`。驗證目標：新增測試涵蓋這三項斷言。
- [x] 2.5 `akashic doctor` 輸出含該項報告，無命中時不輸出該項（避免噪音）。驗證目標：對含命中記錄的暫存 store 執行 doctor，輸出含該 key；對無命中的 store，輸出不含該項標題。

## 3. 匯出層

- [x] 3.1 匯出的 `researcher` 表新增 `died` 欄（位置在既有欄位之後）：有記錄者填日期、無記錄者為 NULL。驗證目標：測試斷言欄位清單含 `died`，且兩種記錄的值各自正確。 （Requirement: The relational export SHALL expose the death date and SHALL state what its status column describes）
- [x] 3.2 「status 欄描述的是**隸屬**，不是活躍或在世」寫進**匯出的 schema 說明**，不再只存在於原始碼註解。驗證目標：測試斷言匯出 schema 中該欄位的說明文字含「隸屬」。

## 4. 文件

- [ ] 4.1 `docs/store-format.md` 的 person 欄位段落新增 `died`，涵蓋四項：ISO 8601 前綴精度；缺席語意為**右設限**（既非「在世」斷言、亦非「不適用」——死亡是必然事件）；缺席**不容其他讀法**（死亡是邊界銳利的事件，不像機構的結束會牽涉合併/吸收所帶來的同一性問題，後者屬歧異記錄的範疇）；唯一不可表達的一格（已觀察到死亡但區間無界，屬 issue 63）。散文用 "deceased"、欄位名用 `died`。驗證目標：內容審查——四項各有對應文字。 （Requirement: The absence of a death date SHALL be read as right-censored, not as living）
- [ ] 4.2 同一文件明寫「本變更為 additive、依 §5.0 準則**不 bump format**」及其理由，並與 issue 81 的欄位語意變更對照；另記載硬要求——provenance 機制（issue 66）落地前，逝世來源一律寫進 person 的 note 欄位。驗證目標：內容審查，且 §5.0 的版本對照表**未**新增列。 （Requirement: Adding the death field SHALL NOT change the supported store format version）
- [ ] 4.3 `README.md` 對 person 欄位與 doctor 報告項目的敘述同步 `died`。驗證目標：內容審查——README 敘述與實作一致。

## 5. 收尾驗證

- [ ] 5.1 確認 scope 未擴張：`StoreVersion.supported` 值與變更前相同；**未**新增任何表示學術活躍度的欄位、推導函式或匯出欄；**未**新增 `born` 欄位。驗證目標：測試直接斷言版本常數值，並以 git diff 確認 `Sources/AkashicStoreIO/StoreVersion.swift` 未被修改、且全 diff 不含 activity / active / born 相關的新增識別字。 （Requirement: Academic activity SHALL NOT be recorded as a stored field）
- [ ] 5.2 全測試套件通過，無新增 quarantine、無既有測試回歸。驗證目標：`swift test` 全綠，並記錄變更前後的測試數量。
