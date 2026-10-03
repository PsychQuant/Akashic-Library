## 1. 記錄的形狀、附著與寫入閘（AkashicCore／StoreIO）

- [x] 1.1 先寫 `NameClassificationRecordTests`（紅）：三動作的解析與組句、前綴不符或理由空白回 nil；person／organization／venue 的附著驗證——名字分類記錄錨定 names（撤回後仍載入）、value 不是記錄的名字拒收、空 rests-on 的非文法判斷型拒收、`field: variant` 在 person／organization 拒收、venue 的 `field: variant` 擷取型拒收、`field: authorized` 的既有擷取型與帶 rests-on 的一般判斷型維持舊語意。驗證：`swift test --filter NameClassificationRecordTests` 先紅後綠（spec「A name-classification record SHALL be anchored to the record's names」；design「判定記錄沿用 ProvenanceReference 的 judgement，statement 以封閉三動作前綴區分」「記錄錨定在 names，不在分割」「名字分類記錄進 firstOrderRulingFields，理由必填、證據可空」）
- [x] 1.2 實作新檔 `NameClassificationRecord`（單一解析器、組句、`isRecord`、位元組去重的 append）、`ProvenanceReference.firstOrderRulingFields` 加 `authorized`／`variant`、三個 `validateReferenceAttachment` 的名字分類分支。驗證：1.1 全綠；`SplitRecordReferenceTests` 釘住的集合改成新集合；`ByteExactKeySiteInventoryTests` 的清單加新檔
- [x] 1.3 store format 22 與寫入閘：`StoreVersion.supported = 22`、`nameClassificationRecordFormat = 22`，person／organization／venue 的寫入閘在帶名字分類記錄而 format < 22 時具名拒絕。先寫測試（format 21 的三種記錄寫入被拒、訊息含 22；format 22 寫得進去），再實作；釘住 21 的既有測試、plugin.json、mcpb/manifest.json、README、docs/store-format.md 改成 22。驗證：`swift test --filter NameClassificationRecordTests` 與 `PluginStoreFormatParity` 守衛綠（spec「Writing a name-classification record SHALL require store format 22」；design「store format 22 與寫入閘」）

## 2. 五個名字分類面寫記錄（MCPKit／CLI／MCP）

- [x] 2.1 先寫 `NameClassificationJudgementTests`（紅）：venue `authorize`／`unauthorize`／`add_variant` 缺理由整批拒絕零寫入、各寫恰好一筆且形狀正確、對既有值寫確認、同書寫系統被換下的名字與被抬出 variant 的名字各寫一筆撤回（理由由程式組句）、撤回之後記錄留存、第二次同一句確認不重寫（`judgementsRecorded` 為 0）、`paginated` 與名字分類同一次呼叫拒絕、rests_on 超過 20 或不合法拒絕；organization 的 `authorize` 腿同一組（被換下的舊指定寫撤回；沒有要指定的名字時以「沒有要改的」拒絕，理由單獨出現也一樣）；organization 沒有 `unauthorize` 腿（#557 R1 verify 之後拿掉，待使用者裁決）。驗證：`swift test --filter NameClassificationJudgementTests` 先紅後綠（spec「Every name-classification judgement SHALL leave a judgement record」「Venue name-classification legs SHALL require a reason and SHALL NOT share a call with the paginated judgement」「The organization authorize leg SHALL require a reason」；design「一次呼叫的理由套用到該次每一筆記錄；連帶的撤回由程式組句」「venue 沿用 judgement／rests_on，與 paginated 不同一次呼叫」「位元組完全相同的記錄不重寫」）
- [x] 2.2 實作：`AuthorizedDesignation` 的報告帶出被誰換下，另產生記錄；`updateVenueArguments`／`updateOrganizationArguments` 在讀 store 之前檢查理由與組合；`updateVenue`／`updateOrganization` 追加記錄並回報 `judgementsRecorded`。既有呼叫這三條腿的測試補上 judgement。驗證：2.1 全綠、既有 `VenueAuthorizedWriteTests`／`VenueUnauthorizeTests`／`VenueVariantWriteTests`／`OrganizationAuthorizeTests` 綠
- [x] 2.3 [P] `authorize-names --apply` 必附 `--judgement`（早於開 store 的用法錯誤），每個寫入的名字各一筆 `指定：理由`；不再寫 store marker。先寫測試（缺理由拒絕、記錄形狀、format 18 且無人可寫時 marker 不動），再改 `AuthorizedNameMigration.run` 與 `AuthorizeNames`。驗證：`swift test --filter AuthorizedNameTests` 與新 CLI 測試綠（design「authorize-names 的理由是整批一句」「authorize-names 不再替使用者升 marker」）
- [x] 2.4 兩面接線：CLI `update-organization --judgement／--rests-on`、`update-venue` 三條腿與 `--judgement`／`--rests-on` 的 help 改寫；MCP `akashic_update_organization` 加 `judgement`／`rests_on`，兩個工具說明提到 `judgementsRecorded`。驗證：stdio 真 binary 各一個 venue 面與 organization 面寫入記錄、`ToolPayloadKeyGuardTests` 與 `ToolPayloadLegTests` 綠、`tools/list` 以真 binary 量測不超過 53,500 bytes（當時；預算之後調到 60,000，#578／#713，修正輪實測 57,213）

## 3. 合併與保留

- [x] 3.1 先寫 `NameClassificationMergeTests`（紅）：被併者帶記錄的 authorized 會被降級時 preview 與實跑都拒絕（`wouldDemoteJudgedAuthorized`）、機械值維持提醒、分類一致的記錄逐位元組搬到倖存者並列在 `referencesCarried`、分類不一致以 `wouldLoseFields` 拒絕。驗證：`swift test --filter NameClassificationMergeTests` 先紅後綠（spec「A venue merge SHALL NOT demote an authorized name that carries a name-classification record」；design「venue 合併：帶記錄的 authorized 降級改為拒絕」「venue 合併：名字分類記錄在分類一致時隨合併搬移」「person 合併維持現狀」）
- [x] 3.2 實作合併：`validateVenuePreconditions` 對帶記錄的降級擲新錯誤、`venueReferenceCarry` 以合併後的分類判斷名字分類記錄搬或不搬、`fieldsLostByMerging` 對不一致的記錄說出名字與兩邊分類；`authorizedDemotedByMerging` 的 doc 改寫觸發條件。驗證：3.1 全綠、既有 `VenueMergeReferencesAndISSNRolesTests` 與 `DivergenceResolveVenueTests` 綠
- [x] 3.3 [P] 名字分類記錄只由名字分類面寫入與保留：`update-person` 的 references 拒收名字分類記錄；venue `--remove-reference` 拒收 `variant` 並不刪名字分類記錄；`authorize`／`unauthorize` 的 pinned 檢查只看名字分類記錄以外的 reference；`repair-venue-names` 把指著拼法的名字分類記錄算 pinned；`--edit-name-segment` 移除名字最後一段時被名字分類記錄擋。先寫測試再實作。驗證：`NameClassificationJudgementTests` 的 ownership 情境綠（design「名字分類記錄只由名字分類面寫入與保留」）

## 4. 負控、規則、文件與收尾

- [x] 4.1 負控：每個行為一個 mutant（不寫記錄、不要求理由、附著不錨定 names、寫入閘放行、合併不拒、合併一律搬、remove-reference 放行），各自讓對應測試變紅，反向編輯還原並以 `cmp` 確認位元組相同。驗證：changelog 的負控表
- [x] 4.2 規則與文件：`two-kinds-of-edits` 五個面的列改寫（記錄自此保留，舊的「待 #564」改成日期註記）、`mcp-cli-parity` 的 `akashic_update_venue`／`akashic_update_organization`／`authorize-names` 列、`zero-instance-guards` 加一列（合併拒絕與寫入閘，live store 0 筆記錄）並補「各列共通的東西」；docs/store-format.md 記錄文法、format 22 與部署順序；新增 `changelog/2026-10-01-name-classification-judgement.md` 與 plugin/CHANGELOG.md 條目。驗證：`bash .githooks/run-guards.sh` rc=0
- [x] 4.3 全套 `swift test --build-system native` 零失敗、`swift build --build-system native -Xswiftc -warnings-as-errors` 通過。驗證：log 的 `Executed N tests … 0 failures`

## 5. 修正輪（R1 verify b26 F1／F2；使用者 2026-10-02 裁決）

- [x] 5.1 去重只比同一個名字同一個分割的最後一筆（`NameClassificationRecord.append`）；撤回之後以同一句理由再指定會寫、organization 換下再換回會寫。驗證：`NameClassificationCorrectionTests` 先紅後綠
- [x] 5.2 `venueReferenceCarry` 的分類一致檢查移到位元組去重之前。驗證：`NameClassificationMergeTests.testByteIdenticalRecordWithDisagreeingClassificationStillRefuses`
- [x] 5.3 理由的形狀（`reasonIssue`：開頭不得是組合符號、格式或不可見字元，要有字母或數字），`parse` 比 scalar 前綴；venue／organization／person／`authorize-names` 共用。驗證：`NameClassificationCorrectionTests`
- [x] 5.4 person 的 `fields.names` 動到 authorized 要理由並寫記錄（裁決第 1 點）；CLI `update-person --judgement／--rests-on`、MCP `judgement`／`rests_on`
- [x] 5.5 刪已撤回的名字連同記錄（裁決第 2 點）：venue `--edit-name-segment` remove、organization／person `--remove-name`（MCP `remove_names`），git 閘、理由只進報告
- [x] 5.6 person 合併搬分類一致的記錄（裁決第 3 點，`personReferenceCarry`；preview 與實跑同一份 `referencesCarried`，CLI dry-run 印出來）
- [x] 5.7 一次至多 200 個名字（裁決第 4 點）；單一名字至多 65,536 位元組；被換下的名字在撤回句裡截 200 個 scalar
- [x] 5.8 MCP `akashic_update_organization` 對已拿掉的 `unauthorize` 具名拒絕；MCP 描述把 #564 整合時刪掉的拒絕類別寫回（預算 60,000）；`bootstrap-venues` 的後續指令補 `--judgement`
- [x] 5.9 負控、規則（`two-kinds-of-edits`、`mcp-cli-parity`、`zero-instance-guards`）、docs/store-format.md §3.5、changelog 與 plugin/CHANGELOG.md


## 6. 修正輪二（R2 verify b29 V1，2026-10-03）

- [x] 6.1 合併搬記錄按位置接（`appendCollecting`，person 與 venue），合併後尾端與分類矛盾的保險（`wouldContradictClassificationTail`，preview 與實跑同一份）。驗證：`NameClassificationMergeTests` 的 R2 一節先紅後綠
- [x] 6.2 person 合併的錨定（記錄的名字要在合併後的 names 裡）與 canonical 的分類比較。驗證：`testPersonRecordOnAWhitespaceTwinSpellingRefusesInPreviewAndApply`
- [x] 6.3 person `fields.names`：沒有記錄的對外形離開 names 放行、format < 22 的拒絕說出寫入閘、上限只數 authorized。驗證：`NameClassificationR2Tests`
- [x] 6.4 刪名字：依處境的出口、venue variant 的工具面出口、person 不刪到沒有名字、organization 逐段回報、線性刪除。驗證：`NameClassificationR2Tests`
- [x] 6.5 理由開頭以性質判；合併預覽印 statement、不排序；文字更正。負控、規則、文件、changelog
