# 2026-09-30 enrich 的來源欄位走 #674 的 retrieval 形狀檢查；references 空陣列兩面都拒絕（#695）

#674 讓 person 與 venue 的 `references` 寫入面共用一個解析函式，並收緊擷取型（retrieval）的形狀：`status` 必填、`url` 只收 http／https 且不含帳密、`retrieved` 是 ISO 8601。留下兩處沒對齊：`enrich` 的 `sourceURL`／`sourceRetrieved`／`sourceStatus` 寫的也是 retrieval reference，卻只驗長度；`"references": []` 在 person 是 no-op、在 venue 是錯。

使用者 2026-09-30 裁決：enrich 的來源欄位**共用同一個解析函式**；空陣列**兩面都拒絕**。

## 改了什麼

### 擷取型的形狀只剩一份

- 新檔 `Sources/AkashicCore/RetrievalWriteShape.swift`。`firstIssue(url:retrieved:status:statusRequired:names:echo:)` 驗四件事，先後固定：status 範圍（100–599）→ 缺 status（不預設 200）→ url（http／https、主機非空、不含帳密，不回顯原值）→ retrieved（ISO 8601）。`isValidRetrievedInstant`、url 的判斷與 `looksLikeURLScheme` 從 `ReferenceWriteParsing.swift`（AkashicMCPKit）逐字搬來，那裡的副本刪除。
- 搬到 Core 的理由：`AddOnlyEnrichment`（enrich 的提案驗證）住在 Core，看不到 MCPKit。兩個呼叫點：
  1. `AkashicService.parseReferenceObjects`（person／venue 的 references，#674）。
  2. `AddOnlyEnrichment.validate`（enrich 的每一筆提案，CLI `enrich --from` 與 MCP `akashic_enrich` 共用的解碼與驗證）。
- 兩個面的差異只在參數：
  - `names`：訊息指名呼叫端的鍵（`references[0].url` 或 `sourceURL`），離線來源的出路不同（references 改用 judgement 型；enrich 只給 `sourceDigest`）。
  - `statusRequired`：references 在「純擷取型」時為真（有 url、retrieved、media type 或 content，而沒有 statement／rests_on）；enrich 在給了 url、retrieved 或 media type 時為真。**只給 `sourceDigest` 不觸發**——那是回顯、不是在寫 reference（#517），`akashic-venue-works` 的摘要提案就是這個形。
  - `echo`：references 的訊息直接進 `ServiceError`（自帶消毒），回顯的值在這裡逃一次；enrich 的理由進 `InputError`，由消費端在擲出站點逃一次，回顯原樣、只截 80 個 scalar，否則逃兩次。
- enrich 的空字串視同沒給，與 `retrievalKind`／`missingSourceFields` 的既有判準一致；只有空白的 url 不是空字串，照樣被拒（先前它會以 url `"  "` 寫進 store）。
- 失敗語意沿用 enrich 輸入錯的既有做法：`InputError.invalidProposal`，整批拒絕、零寫入、指名第幾筆。CLI 是執行期失敗 1（提案檔是 argv 以外，`RuntimeFailure` 第 2 條）。

**改變的行為**：給了 url／retrieved 卻沒給 status，先前是值照補、reference 不寫、理由進 `provenanceSkipped`（#542 R2），現在整批拒絕。MCP 的 `sourceStatus` 說明原本寫著「省略即不寫 reference」，那個出口改成只給 `sourceDigest`。`WorkFieldProvenanceTests.testMissingStatusWritesNoReferenceAndSaysWhy` 釘的是舊行為，改寫成 `testMissingStatusIsRefusedNotFabricated`。

### 空陣列

- 拒絕從 `parseVenueReferences` 搬進 `parseReferenceObjects`，兩面同一句：「references 是空陣列——沒有要附的 reference 就不要給這個鍵」（先前 venue 說「這個參數」）。person 側的 CLI 經 `checkUpdatePersonFields` 在 `validate()` 呼叫同一個函式，所以是用法錯誤 64；venue 側本來就是 64。
- `ReferenceWriteContractTests.testEmptyArrayIsStillANoOpForPersonAndRefusedForVenue` 釘的是 #674 有記錄的差異，改成 `testEmptyArrayIsRefusedOnBothFacesWithTheSameSentence`（四個入口、同一句）。

### 描述與規則

- MCP：`akashic_enrich` 的總述與三個 source 鍵、`akashic_update_person` 的描述、`akashic_update_venue` 的 `references` 描述。CLI：`enrich --from`、`update-person --fields`、`update-venue --references` 的 help。
- `mcp-cli-parity` 三列（`akashic_update_person`、`akashic_update_venue`、`akashic_enrich`）加「#695 重新確認，裁決不變、契約有改」；`update_person` 列裡「空陣列是有記錄的差異」與「enrich 仍是各自的契約」兩句劃掉。`zero-instance-guards` 第 66 列的誠實邊界（「enrich 沒有跟著收緊」）劃掉。`docs/store-format.md` 兩處同步。`plugin/CHANGELOG.md` 記下兩個不相容的改變。

## 測試

- `EnrichRetrievalShapeTests`（AkashicKitTests，7 支）：20 格形狀錯各自整批拒絕並說出鍵與錯的種類（ftp、file、無 scheme、javascript:、前導空白、只有空白、缺主機、帳密兩種、retrieved 四種、status 三種、缺 status 四種組合）；帳密不回顯；一筆壞的讓前面合法的那筆也不產生計畫、指名第 2 筆；缺 status 先於 url／retrieved 報；蛇形別名走同一道檢查；合法形狀（port、IPv6、大寫 scheme、帶時區、404）照寫；只給 digest、給 digest 加 status 沒給 url 仍是略過並具名。
- `EnrichRetrievalShapeServiceTests`（AkashicMCPTests，2 支）：同一個形狀錯，`enrich`（dry-run 與 apply）與 person 的 `references` 說出**同一句**核心訊息、零寫入——「同一種記錄只剩一份寫入契約」的量法；合法的一筆寫進去且 reference 帶著送來的值。
- `EnrichCLITests.testMalformedSourceShapeRefusesTheWholeFile`：真 binary，三種壞提案（ftp、帶帳密的蛇形別名、缺 status）各讓整個檔零寫入、exit 1、不回顯帳密。
- `StdioE2ETests.testEnrichSourceShapeAndEmptyReferencesAreRefused`：真 binary 的 MCP 面，enrich 的 ftp、person 與 venue 的 `references: []`，零寫入。
- `ServiceArgvExitCodeTests.testReferencesContractIsAUsageErrorOnBothFaces` 多兩格：兩面的 `[]` 都是 64、同一句。

修之前（RED）：新增與改寫的 13 支裡 10 支紅（86 個斷言失敗；同批另跑 12 支既有的 `ReferenceWriteContractTests`，全綠）。綠的三支釘的是應保留的既有行為（合法形狀照寫、只給 digest 照舊略過）。

完整套件與守衛的結果見〈量測〉。

## 負控

反向編輯、`cmp` 對照備份確認還原（不用 `git checkout`）：

| 反向編輯 | 應紅的測試 | 結果 |
|---|---|---|
| NC1：`AddOnlyEnrichment.validate` 的 `if let why = RetrievalWriteShape.firstIssue(` 改成 `if false, let why = …`（enrich 不驗形狀） | enrich 的核心、service、CLI、MCP 測試 | 跑 12 支，紅 9 支（78 個斷言）：`EnrichRetrievalShapeTests` 5 支、服務層的同句測試、CLI 的整檔拒絕、MCP 真 binary、`testMissingStatusIsRefusedNotFabricated`。綠的 3 支是應保留的既有行為（合法形狀照寫、只給 digest 照舊略過、服務層合法照寫） |
| NC2：`parseReferenceObjects` 的 `guard !raw.isEmpty` 改成 `guard raw.isEmpty \|\| true`（空陣列放行） | 兩面的空陣列測試 | 跑 19 支，紅 3 支（16 個斷言）：`testEmptyArrayIsRefusedOnBothFacesWithTheSameSentence`、CLI 的用法錯誤 64、MCP 真 binary |
| NC3：`RetrievalWriteShape.firstIssue` 的 `if status == nil, statusRequired` 改成 `…, statusRequired, false`（共用函式不再報缺 status） | 兩個面的缺 status 測試**同時**紅 | 跑 22 支，紅 4 支（15 個斷言）：enrich 的兩支、`ReferenceWriteContractTests.testMissingStatusIsReportedBeforeAMalformedURLOrRetrieved`、服務層同句測試的 enrich 與 person 兩半。一個反向編輯讓兩個面一起紅，是「同一個函式」的量法 |

三個反向編輯各自以反向字串替換還原，與備份 `cmp` 相同；還原後同一組 43 支測試全綠。

## 量測

- **完整套件**：4,345 支，0 失敗、1 支 skip。**守衛**：`run-guards.sh` rc 0（parity 表 MCP 34、CLI 56、橫切 2；zero-instance 裁決表 70 列）。
- **tools/list**：50,350 bytes（改前 50,232，多 118；預算 52,000）。量法：真 binary 送 initialize 與 tools/list，數回應那一行的位元組，同 `StdioE2ETests.testToolsListResponseStaysWithinByteBudget`。
- **live store**（2026-09-30 唯讀，以 PyYAML 解析 `entities/*.yaml`，沒有寫入）：7,649 筆記錄、讀不到的檔 0。帶 `url` 的擷取型 reference 33 筆，全在 work 上、全是 `fields.<鍵>`（`enrich` 寫的）。scheme 全是 `https`、無帳密、`retrieved` 全是裸日期、status 全是 200，**會被新檢查拒的 0 筆**。person、venue、organization 的擷取型 reference 0 筆。
- 空陣列沒有 store 面的量測：它是寫入參數，不進 store。

## 誠實邊界

- 只給 `sourceDigest` 仍是回顯。依 #674 字面的「任何擷取側欄位在場就要 status」，它應該被拒；不拒是因為它不寫 reference，而摘要提案靠它（#517）。
- 給了 status 而 url 或 retrieved 缺席，仍是值照補、reference 不寫、理由進 `provenanceSkipped`（#542 R2），沒有改成拒絕。person／venue 的 references 對同一個形狀是拒絕（平面 init 要四欄）。裁決只點名 status 必填與三項形狀，「不齊就拒絕」沒有裁，留著。
- 錯誤訊息的鍵用駝峰名。提案檔寫蛇形（`source_url`）時，訊息說的是 `sourceURL`。
- `references` 面缺 status 的訊息，離線來源的出路從「離線來源改用 judgement 型」改成與 url 那句相同的「離線來源（本機檔案、掃描檔）改用 judgement 型（statement＋rests_on 指向存檔）」。一份 `Names` 只帶一個出路。
- status 的範圍檢查在 references 面移到 `rests_on` 的型別檢查之後。兩個都錯時，先報的從 status 變成 rests_on；單一錯誤的訊息不變。

## R1 verify 之後

第一輪驗證的處置與負控詳見 `2026-09-30-b22-r1-fixes-705-695.md`。摘要：

- **帳密檢查可被 grapheme cluster 繞過（兩席 MEDIUM，DA 以真 binary 寫進 store）**：`@` 後面緊跟組合符號、ZWJ 或 VS16 時，Swift 的 `Character` 把兩者合成一個，`contains("@")` 為 false。三個入口共用的 `urlIssue` 改在 Unicode scalar 上切 authority、找 `@`；主機含反斜線另行拒絕。
- **字元規則**：url 整串拒絕控制字元、格式字元（方向控制、零寬字元）與空白；media type 拒絕這類字元與前後空白。判準與輸出閘同一份（`UnsafeToEmitScalar.contains`）。retrieved 的文法本來就擋這些，補了測試；`+0800` 的訊息改說「偏移要帶冒號」。
- **「一份寫入契約」的措辭**：共用的是**形狀**函式。「要不要 status」由兩個面各自判定、刻意不同（enrich 的 `provenanceSkipped` 出口與只給 digest 的回顯）；上方〈誠實邊界〉前兩條說的就是這件事，對照表在那份 changelog。`mcp-cli-parity` 三列的 #695 註記同批更正。
- `plugin/CHANGELOG.md` 的 #674 一節那句「enrich 沒有跟著收緊（#695，待裁決）」後面加上日期與指向 #695 一節的說明。
