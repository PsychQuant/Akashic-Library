# 2026-10-02 名字分類的修正輪：記錄只對最後一筆去重、person 的 names 要理由、已撤回的名字可以連同記錄刪、一次至多 200 個名字（#557、#559、#563、#564、#566）

#564（store format 22，`changelog/2026-10-01-name-classification-judgement.md`）與同批 #557／#559／#563／#566 的 R1／R2 verify（b26 F1 41 列、F2 43 列）找到三個程式錯誤與四件要裁決的事。使用者 2026-10-02 四件都選建議方案（#564 的 Decision 留言）；這份記錄兩者一起落地。

## 使用者的四點裁決

| # | 問題 | 落地 |
|---|---|---|
| 1 | `update-person` 的 `fields.names` 全量替換能不附理由、不留記錄地改 authorized（F2 第 0／2／5／11／20 列） | 替換讓名字**進**或**出** authorized 時 `--judgement`（MCP `judgement`）必填，比照 venue 寫 `field: authorized` 的記錄：進的「指定」、仍在的「確認」（附了理由時）、出的「撤回」；只動 variant 的不必。person 從此有單筆的名字分類面（第六個面）。替換拿掉有記錄的名字、或讓對外形整個離開 names，具名拒絕並指出口 |
| 2 | 記錄錨定 names 而且刪不掉：`--authorize` 打錯字的名字、`authorize-names` 採用的錯拼法，沒有工具能修（F2 第 4／9／32 列） | **最後一筆記錄是「撤回」的名字，連同它的記錄一起刪**：venue 擴充 `--edit-name-segment` 的 remove（報告 `judgementRecordsRemoved`）；organization 與 person 各多一條 `--remove-name '<名字>=<理由>'`（MCP `remove_names`）。比照移除面一族：理由必填、只進報告；檔案要先 commit 乾淨，歷史留在 git。最後一筆不是撤回的拒絕，出口是先撤回、再刪 |
| 3 | 兩筆 person 攣生各跑過一次 `authorize-names`（理由不同）後合併被拒，沒有工具能把記錄帶過去（F2 第 8 列） | 分類一致時被併者的名字分類記錄逐位元組搬到倖存者（`personReferenceCarry`，比照 venue 的 `venueReferenceCarry`），preview 與實跑同一份 `referencesCarried`；不一致時拒絕並指出口 |
| 4 | 一次 `--add-variant` 帶 1,500 個名字，同一句理由被複製成 1,500 筆記錄（6,167,788 位元組），沒有工具能移除（F2 第 7 列） | 名字分類的寫入面一次至多 200 個名字（venue 三條腿合計、organization `authorize`、person `fields.names` 兩個分割合計、`remove_names`），取其他寫入腿的一次上限 `maxSpecsPerCall`，不另立數字；超過整批拒絕、零寫入 |

## 三個程式錯誤

- **去重比的是整份歷史**（F1 第 1／2／5／13 列、F2 第 3 列，五席同指）：`NameClassificationRecord.append` 對整份 `references` 以位元組去重。「指定 R → 撤回 S → 再以 R 指定」的第三筆與第一筆相同而被丟掉——名字回到了 authorized，記錄卻以撤回結尾，回報 `judgementsRecorded: 0`；organization 的「換下再換回」同形。改成只比**同一個名字、同一個分割的最後一筆**：與上一筆相反的動作是一次新的轉移。`judgedAuthorizedDemotions` 的「最後一筆是撤回卻仍在 authorized 只可能是手改」因此回到真話。
- **`venueReferenceCarry` 的位元組早退排在分類檢查之前**（F2 第 1 列，Codex）：兩邊各持一筆位元組相同的「variant 指定：R」、倖存者之後把名字抬進 authorized 又撤回時，被併者的 variant 分類被合併安靜地拿掉。分類檢查移到前面。
- **理由以 Grapheme_Extend 字元開頭時，記錄變成一般 reference**（F2 第 6／33 列）：`parse` 用 `String.hasPrefix`，在 Character 上比——U+0301、ZWNJ、CGJ 一類與全形冒號併成同一個字，前綴比不上；帶 `rests_on` 時寫成一筆一般的 `field: authorized` reference，`--remove-reference` 刪得掉、合併端看不見，回報卻說寫了一筆記錄。`parse` 改在 scalar 上比；入口另以 `NameClassificationRecord.reasonIssue` 拒收開頭是組合符號、格式或不可見字元、或沒有任何字母數字的理由（F2 第 19／34 列：U+2060、U+FEFF、U+3164 這類理由滿足了「必填」的字面）。venue、organization、person 與 `authorize-names` 共用。

## 其他（MEDIUM／LOW）

- **MCP `akashic_update_organization` 對已拿掉的 `unauthorize` 具名拒絕**（F1 第 3／6／9／21 列）：server 對多餘的鍵一律忽略，帶它的呼叫照做 `authorize`、撤回被安靜丟掉並回報成功；CLI 是未知旗標、exit 64。現在兩面都拒。
- **`bootstrap-venues` 的後續指令補 `--judgement "<理由>"`**（F1 第 0／4 列）：`--authorize`／`--add-variant` 的兩個提示寫在 #564 整合之前，照抄得 exit 64。沒有候選或沒有新建 venue 時不再說「新建的 venue」（F1 第 17／23／28 列）；`--help` 多一段說明。
- **MCP 描述寫回 #564 整合時為舊預算（54,000）刪掉的拒絕類別**（F2 第 10／12／16／21／24／31 列）：`resolve-people`／`resolve-venues`／`resolve-organizations` 的 `undecided`、`drop_venue`（4,096 位元組、一次 200 條）、`repoint`、`update_venue` 的 `unauthorize`、`remove_reference`，以及「resolve_venues 對沿革各段都配對」。CLI help 補上同樣缺的：`--drop-venue` 的兩個上限、兩個 `--undecided` 的整批拒絕類別、`--remove-reference` 與 `--edit-name-segment` 的 #564 處置。
- `update-venue`：報告多 `variantConfirmed`（F2 第 18 列）；寫檔之後 index 重建失敗不讓呼叫失敗，報告帶 `indexRebuilt: false`（F1 第 12／18／20／30 列：撤回的原位置與 `displayNameChanged` 只在報告裡）；`displayNameChanged` 改用 `displaySafeInvisible`（F1 第 31 列）。
- organization：`authorizedNotCurrent` 只在機構另有現行名稱時出現（F1 第 10／22／35 列：已解散的機構指定它最後的名字是對的；只有觀測點的段不是「已結束」，訊息不再這樣說）；index 重建失敗的 `indexNote` 改說「以同一句理由重試會多寫一筆確認」（F1 第 30／38 列）；`authorizedRewritten` 補測試（F1 第 7 列）。
- 名字的位元組上限 65,536（`AddOnlyEnrichment.maxValueBytes`，同 `edit_name_segment`），在 canonical 之前擋；被換下的名字在撤回句裡截 200 個 scalar（F1 第 19／27 列）。
- `validatePartitionReference` 的名字集合在迴圈外建一次 `Set`（F2 第 29 列：先前 O(記錄數×名字數)）。
- `resolve-divergence --dry-run` 印出 `referencesCarried`（F2 第 27 列：preview 一直有算，dry-run 的渲染路徑沒接）。
- `authorize-names --apply` 沒有寫任何名字時不再印「已寫入」（F2 第 17 列）。
- 文字：venue 的 `--remove-reference` 與通用 references 的拒絕訊息指出刪名字的出口（F2 第 4／25 列）；`#600 的 authorize campaign` 的殘句改成按需判定（F1 第 24 列、F2 第 13／30 列）；plugin/CHANGELOG.md 的 #557／#559 兩節與兩份舊 changelog 的「不留記錄」「不寫檔」補上 #564 之後的條件（F1 第 8／15／32 列）；`changelog/2026-10-01-venue-unauthorize.md` 的佔位改成 #712（F1 第 26 列）；Spectra change 的 tasks／design 的 53,500 改註預算 60,000（F2 第 14 列）；`akashic-verify-venue` 補 MCP 優先、錯誤訊息裡的記錄文字是資料、`referencesTruncated`、打錯字的出口（F2 第 15／22／23 列）。

## 規則與文件

- `two-kinds-of-edits`：新增兩列（person `fields.names` 的名字分類、`--remove-name`）；`update-person` references 列、`--edit-name-segment` 列、bootstrap 列改寫。
- `mcp-cli-parity`：`authorize-names` 列那句「person 的單筆名字分類面不存在」劃掉並說明為什麼為假；`akashic_update_person`、`akashic_update_organization`、`akashic_update_venue`、`akashic_venue` 各補一段重新確認。`update-venue` 對 no-op 呼叫照樣寫檔、organization 不寫，記成有記錄但未改的差異（F1 第 16／29 列，與 `update-venue` 要不要乾跑那一格一起裁）。
- `zero-instance-guards`：第 78 列改寫（person 合併、「只可能是手改」的前提），新增第 82 列（G1 原編第 79 列，整合時重編）（三道入口閘：一次 200 個名字、理由形狀、person 的理由要求；live store 每筆記錄的名字數最多 person 5、venue 4、organization 3，最長的名字 129 位元組，名字分類記錄 0 筆）與量測腳本。
- `docs/store-format.md` §3.5：第六個面、理由形狀、一次 200 個名字、刪名字連同記錄（normative）、去重只比最後一筆、person 合併、誠實邊界第 5 條（判斷只看文法，F2 第 28 列）。
- Spectra change `name-classification-judgement`：proposal、design（新增〈修正輪〉一節）、tasks（第 5 節）、spec delta（authorized-name 兩個新 Requirement、divergence-record 一個新 Requirement 與一句收緊）。

## `tools/list` 位元組

真 binary（`akashic-mcp` stdio，`tools/list` 回應整行）：**57,213**（預算 60,000，`StdioE2ETests.testToolsListResponseStaysWithinByteBudget`）。寫回的拒絕類別約 1.3 KB；新參數（person 的 `judgement`／`rests_on`／`remove_names`、organization 的 `remove_names`）與說明約 2 KB，已壓過一輪。

## 負控（每一個 MEDIUM 一個；反向編輯還原）

| # | 突變 | 變紅的測試 |
|---|---|---|
| NC1 | `append` 改回對整份 references 位元組去重 | `NameClassificationCorrectionTests` 的 `testRedesignationAfterWithdrawalWithTheSameReasonIsRecorded`、`testOrganizationReplaceThenRestoreRecordsTheRestoredDesignation`（17 個中 5 個失敗） |
| NC2 | `venueReferenceCarry` 的位元組早退放回分類檢查之前 | `NameClassificationMergeTests.testByteIdenticalRecordWithDisagreeingClassificationStillRefuses`（preview 與實跑都沒拒、合併照做） |
| NC3 | 入口不跑 `reasonIssue` | `testReasonStartingWithACombiningMarkIsRefused`、`testInvisibleOnlyReasonIsRefused` |
| NC4 | MCP 不拒 `unauthorize` | `NameDesignationStdioTests.testUpdateOrganizationRefusesTheRemovedUnauthorizeKey`（authorize 照做、檔案被改寫） |
| NC5 | `bootstrap-venues` 的 `--authorize` 提示拿掉 `--judgement` | `BootstrapVenuesPendingCLITests.testApplyLeavesAuthorizedEmpty` |
| NC6 | person 的 names 腿 authorized 有改而沒理由時不拒 | `testPersonAuthorizedChangeNeedsAReason` |
| NC7 | `nameSegmentRemovalBlocker` 改回「有記錄就擋」 | `testVenueWithdrawnTypoIsRemovedWithItsRecords` |
| NC8 | venue 的 200 個名字上限拿掉 | `testClassificationCallsAreCappedAtTwoHundredNames` |
| NC9 | `personReferenceCarry` 一律算失去 | `testPersonTwinRecordsWithAgreeingClassificationAreCarried`、`testPersonMergeKeepsItsOwnRefusals` |
| NC10 | `drop_venue` 的描述拿掉寫回的兩個上限 | `NameDesignationStdioTests.testRestoredRefusalCategoriesAreInToolsList` |
| NC11 | organization／person 的 `remove_names` 不刪記錄 | `testOrganizationRemoveNamesOnlyTakesWithdrawnNames`、`testPersonWithdrawnNameIsRemovedWithItsRecords`（寫入閘以孤兒記錄拒絕） |

## 真 binary 驗證（暫存 store，format 22）

- `update-venue tg --authorize X --judgement 官網確認` → `--unauthorize X --judgement 查錯了` → 再 `--authorize X --judgement 官網確認`：三次各 `judgementsRecorded: 1`，YAML 三筆、最後一筆「指定：官網確認」。
- 理由 `́原因`（帶 `--rests-on`）：exit 64、零寫入；`--add-variant` 201 個名字：exit 64。
- 打錯字的 `Psychometrka`：`--authorize` 正確名字換下它（寫撤回）→ commit → `--edit-name-segment` remove：`judgementRecordsRemoved: 2`，名字與記錄都不在了。
- person：`fields.names` 不附理由 exit 1 並說出口；附理由寫記錄；替換拿掉有記錄的名字被拒、指向 `--remove-name`；移到 variant 之後未 commit 被 git 閘拒，commit 之後 `--remove-name` 刪掉名字與 2 筆記錄。
- MCP：`akashic_update_organization` 帶 `unauthorize` 回 isError、具名；`remove_names` 刪掉被換下的打錯字名字（1 段、2 筆記錄）。
- person 攣生（兩批理由不同）：`resolve-divergence --dry-run` 印「reference 將隨合併遷移到倖存者：1 筆」。

## 沒有做的（各有理由）

- **`authorize-names` 不設 200 的上限**：它每個 person 至多寫三筆（每書寫系統一個對外形），上限防的是單筆記錄被同一句理由灌爆；設了會讓新 store 上超過 200 人的正常批次跑不了。這是我的判斷，使用者可翻。
- **`update-venue` 的 no-op 呼叫照樣寫檔**（F1 第 16／29 列）：只記成有記錄的差異；要改得連同 `update-venue` 整個命令要不要乾跑一起裁。
- **`akashic-verify-venue` 裡的 Python 進度量測腳本**（F2 第 26 列）：照 `swift-is-the-implementation-language` 應該是 `akashic` 子命令；那是新的 CLI 面，不在這一輪。
- **需要外部寫入的**（F1 第 11／14／25／33 列、F2 第 35／41 列）：開 issue 承接 organization 的兩項待裁、spec 與 `Venue.displayName` 的分岔、更新三張 issue 的 body、plugin `binary_version` 落後於 format 22——都是 GitHub 上的寫入，交給使用者。
