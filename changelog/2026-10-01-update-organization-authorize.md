# 2026-10-01 organization 的 `authorized` 有了寫入面：`update-organization`（#557）

使用者 2026-10-01 裁決：「新增 update-organization --authorize」——選形狀 2：新增 `update-organization` 面（CLI）與對應的 MCP 工具，先提供 `--authorize`，語意比照 `update-venue --authorize`；新命令兩面都在 `mcp-cli-parity` 落表。

## 為什麼

`Organization.authorized` 對齊 RDA 的 authorized access point，`doctor` 也把空的 authorized 算進 `no authorized name: N person / M organization`——而在此之前沒有任何面寫得進它：`addOrganization` 不收、`OrgBootstrap` 不寫、`authorize-names` 只管 person。2026-09-11 實測 live store 13 筆 organization、有 authorized 0 筆，`doctor` 那一行恆為真且修不掉，`displayName` 全部走 fallback（`names.current` 或裸 key）。

**`doctor` 那一行自此修得掉**：`update-organization <key> --authorize <名字>` 之後，那筆 organization 不再算在 `no authorized name` 的 organization 數裡（`OrganizationAuthorizeTests.testDoctorNameGapShrinks` 走服務層、`UpdateOrganizationCLITests` 走真 binary 的 `doctor`，都驗從 1 變 0）。

## 契約（CLI `update-organization <key> --authorize …`；MCP `akashic_update_organization`，`key` ＋ `authorize` 陣列）

- **`--authorize`**：與 `update-venue --authorize` 同一份邏輯。同 `WritingSystem` 原子替換，被換下的名字移出 authorized、留在 names（organization 沒有 variant，不會被標）；不同書寫系統之間是 append；不在 names 的以 canonical 形加進 names。相等看 `NameIdentity.canonical`。
- **沒有 `--unauthorize`**（R1 verify 之後拿掉，見文末）。
- 讀 store 之前整批拒絕（CLI 是用法錯誤 64）：沒給、空陣列、只有空白項（三者同一件事——「沒有要改的」：一次沒有變動的寫入仍會重新序列化整筆記錄、重建 index）、key 格式不合、同一次兩個同書寫系統的名字、名字含控制／格式／不可見字元或沒有任何字母或數字。
- 讀 store 之後整批拒絕、零寫入：key 有不只一筆記錄（#669／#670 的 `unlocatableOrganizationKeys`——寫進哪一筆是猜）、找不到、被換下的名字被 `field: authorized` 的 reference 指著（organization 的 reference 沒有移除面，訊息指路手改 YAML）。
- 給的名字都已是對外名稱：成功、報 `alreadyAuthorized`，**不寫檔、不重建 index**（#564 整合之後要加條件：對已是對外名稱的名字說「確認」會寫一筆記錄，同一句理由已是那個名字的最後一筆記錄時才不寫檔）。
- 子集與「每書寫系統至多一個」由 store 邊界擋（`writeOrganization` → `Organization.validate()` → `AuthorizedNames.validate`），寫入面不重造。organization 沒有 venue 那道名字內容的不變式（#554 D8）；新加進 names 的名字過入口的 vetting，那是入口的輸入檢查。
- 回報：`key`、`namesAdded`、`authorizedAdded`、`authorizedRemoved`、`alreadyAuthorized`、`authorizedRewritten`、`authorizeDropped`、`authorizedTotal`；有事才出現：`authorizedNotCurrent`、`indexRebuilt: false`／`indexRebuildError`／`indexNote`（見文末）。organization 沒有 variant，不報 `liftedFromVariant`。
- 判定記錄待 #564（2026-10-01 裁決名字分類面全部要留，另案落地、需要 store format bump）；在那之前不寫記錄。→ #564 已同日落地（`changelog/2026-10-01-name-classification-judgement.md`）：`--authorize` 必附 `--judgement`、寫判定記錄。

## 實作

替換的邏輯是 `Sources/AkashicMCPKit/AuthorizedDesignation.swift` 那一份（#559 從 `updateVenue` 搬出）；本次再把「同一次兩個同書寫系統的名字」的檢查原樣搬進同一檔（`refuseSameScriptClash`，訊息逐字不變），venue 與 organization 的入口共用。organization 的定位、寫入與報告在 `Sources/AkashicMCPKit/OrganizationUpdate.swift`；CLI 在 `Sources/akashic/UpdateOrganizationCommand.swift`。`vetVenueNamesReportingBlanks` 從 `private` 改成模組內可見，organization 的入口走同一個 vetting。

**目標 store 確認閘：不閘**（`WriteGateRulings` 的 `update-organization` 格）。理由與 `update-venue` 那一格同：逐筆指名一個 key、被換下的名字留在 names、可以再指定回來（同書寫系統替換，位置不變）、不刪任何名字或 reference（`--authorize` 新加進 names 的名字會留著，organization 沒有名字的移除面）。`update-venue` 整個命令要不要有乾跑、要不要閘待使用者裁決，這一格與它一起裁。

## 規則與文件

- `mcp-cli-parity`：MCP 表加 `akashic_update_organization` ↔ `update-organization` 一列（工具 34 → 35；R1 verify 之後列裡的 `unauthorize` 全部拿掉，並補 `authorizedNotCurrent`／`indexRebuilt` 與「沒有要改的」的新口徑）。一列同時裁決了兩面：CLI-only 表只收沒有 MCP 面的命令，把 `update-organization` 也放進那張表會與這一列矛盾（稽核程序說每個命令出現在「MCP 表的 CLI 對應欄**或**」CLI-only 表）。四步稽核：① `Server.swift` 35 個工具、與表零差集；②③ CLI 註冊型別 57 個，`UpdateOrganizationCmd` 解析成 `update-organization`（另有一個既有的 `<未解析>`：`S2Cmd` 被步驟 ② 的 `[A-Za-z]+` 切成 `Cmd`——字元類不含數字，與步驟 ① 修過的是同一個形狀；本次沒有動它）；④ 橫切 `ParsableArguments` 仍是 `LibraryOptions`／`FileConfigOptions`，本次沒有新增。
- `two-kinds-of-edits`：加 `update-organization --authorize` 一列（AI）；R1 verify 之後註明沒有撤回面與原因。
- README：CLI 清單加 `update-organization`、工具數 35；`docs/store-format.md` §3.1 補三個實體各自的指定面。

## 測試

| 測試 | 驗什麼 |
|---|---|
| `OrganizationAuthorizeTests`（14 個，服務層；首輪 12 個，R1 verify 之後拿掉撤回與 authorize＋unauthorize 同名兩個、補四個） | 寫得進、displayName 跟著換；同書寫系統替換與跨書寫系統 append；不在 names 的以 canonical 形加入；冪等但報 alreadyAuthorized；兩個同書寫系統整批拒絕；key 重複整批拒絕零寫入；notFound；沒有要改的（沒給、`[]`、空白項）與 key 格式早於開 store；空／空白不動檔案；已是對外名稱不動檔案；退役名不拒絕但報 `authorizedNotCurrent`；寫檔後 index 重建失敗回成功；被 reference 指著時指路手改 YAML；`doctor` 的 organization 缺口從 1 變 0 |
| `UpdateOrganizationCLITests`（2 個，真 binary） | `--authorize` 寫進 store、`doctor` 那一行從 1 變 0、`--unauthorize` 旗標不存在；用法錯誤 64（含只有空白項）、早於開 store |
| `NameDesignationStdioTests.testUpdateOrganizationReachesTheService`（真 binary、stdio） | 工具有註冊、有分派，`authorize` 到得了服務層；沒給、`[]`、`[" "]` 都整批拒絕且檔案位元組不變 |
| `ToolPayloadScenarios` 兩個情境（`authorize`、`authorize-retired`；首輪的 `unauthorize` 拿掉） | 每個回應鍵出現在工具說明裡（#672）；每個參數有情境宣告（#700） |
| `WriteGateRulingsTests`（既有） | 新命令在裁決表有一格 |
| 既有的兩個計數／集合測試 | `StdioE2ETests` 的工具數 34 → 35（兩處）、`PersonCLITests.testEveryCLIServiceConstructionPassesRegistryKey` 的 `expectedFiles` 加 `UpdateOrganizationCommand.swift`（它有帶 `key: store.key`）——全套第一輪抓到這兩個 |

全套第一輪另抓到一個 `DisplaySinkCoverageTests` 的紅：報告的名字先經一個 `shown` closure 消毒，源碼掃描看不穿 closure，當成未消毒送進輸出。改成與 venue 同形的 `.map { displaySafeInvisible($0, max: 200) }` 逐鍵寫出。

### 負對照

每個 mutant 改一處、重編（含兩個 executable）、跑相關 test class，再以反向編輯還原並以 `cmp` 對事先存下的副本確認逐位元組相同。數字是 XCTest 的 failures。

| mutant | 結果 |
|---|---|
| N1 MCP 分派的 case 標籤改名 | 4（stdio：Unknown tool） |
| N2 CLI 不註冊 `UpdateOrganizationCmd` | 10（CLI 測試全紅、裁決表有 CLI 沒有的命令） |
| N3 不擋重複 key | 2（`testDuplicateKeyIsRefused`） |
| N4 不寫檔 | 19 |
| N5 organization 入口不擋同書寫系統兩個名字 | 5（服務層與 CLI 的 64） |
| N6 裁決表那一格改名 | 3（CLI 有命令而表沒有、表有命令而 CLI 沒有、payload 腿對不到工具） |
| N7 工具說明少寫 `authorizedWithdrawn` | 1（`ToolPayloadKeyGuardTests`） |
| N8 organization 入口不擋 authorize＋unauthorize 同名 | 第一輪 0（**沒有測試**）→ 補 `testSameNameToAuthorizeAndUnauthorizeIsRefused` 後 1 |
| N9 共用的同書寫系統檢查一律放行 | 8（organization 3、venue 既有的三個測試 5）——搬家之後 venue 的測試仍在驗搬過去的那一份 |

## `tools/list` 位元組（首輪的數字量錯了，見下）

首輪寫「整行 52,277（#559 之後）→ 53,024（+747，新工具 776 bytes）」——三個數字互相矛盾（新工具 776 比總增量 747 還大），而且重量不起來：R1 verify 以真 binary（`.build/debug/akashic-mcp`，與 `testToolsListResponseStaysWithinByteBudget` 同一個位元組算法）量 HEAD 是 **53,403**，不是 53,024。預算 54,000 的餘裕因此是 597，不是 976。

## R1 verify 之後（2026-10-01，41 個 findings，本節是 #557 的部分）

**拿掉 organization 的 `--unauthorize`／MCP `unauthorize`（findings 3、4、25；7 是實質缺陷）。** 使用者的裁決只說「先提供 `--authorize`」，`--unauthorize` 是首輪實作者加的（#559 的裁決只針對 venue，#564 列舉的五個判定面裡 organization 也只有 `--authorize`）。更實質的是 finding 7（DA 席真 binary 重現）：venue 的撤回「回到誠實的未判定狀態」靠的是 venue 的 fallback 顯示名是 `names.entries.first`，而 organization 的 fallback 是 `names.current`（沒有時間欄位時取序列化順序**最後**一筆）——`--authorize` 不在 names 的名字會把它加進 names，`--unauthorize` 之後名字留著、authorized 回到空，剛加進去的名字成為 `displayName` 與匯出的 `name_current`。organization 又沒有任何名字的移除面，所以這一步沒有還原路。拿掉整條腿（CLI 旗標、MCP 參數、`authorizedWithdrawn`／`unauthorizeDropped` 兩個回應鍵、說明位元組、測試、parity／two-kinds／WriteGateRulings／plugin CHANGELOG 的對應文字），待使用者裁決——連同 organization 要不要有名字的移除面。`AuthorizedDesignation.unauthorize` 留著，只有 venue 的入口呼叫。

**沒有要改的（findings 13、16、26、28）。** 首輪的守衛只看 `authorize != nil || unauthorize != nil`：MCP 的 `authorize: []`、`[" "]` 與「都已是對外名稱」都走完 `writeOrganization` 加 `rebuild()`（檔案 mtime 變、人手編過的排版被重新序列化），而 CLI 把空陣列轉成 nil 所以擋得住——兩面不一致。現在：沒給、空陣列、只有空白項三者同一件事，看**過了 vetting 的結果**（`authorizeIn` 為空）讀 store 之前整批拒絕（CLI 用法錯誤 64）；給的名字都已是對外名稱時成功、報 `alreadyAuthorized`，**不寫檔、不重建 index**（以報告的桶判斷有沒有變：`namesAdded`／`authorizedAdded`／`authorizedRemoved`／`authorizedRewritten` 任一非空才寫）。只有空白項在 organization 這條單腿的面上是拒絕、不是 venue 那種「no-op 成功，回報 `authorizeDropped`」——venue 有十幾條腿，空白項只是其中一條沒說話；organization 只有這一條，沒說話就是沒有要改的。

**寫檔成功後 index 重建失敗（finding 1）。** 首輪 `try writeOrganization` 之後緊接 `try rebuild()`，重建擲錯時呼叫回失敗、報告消失，而重試只會得到 `alreadyAuthorized`。改用移除面一族的做法（`RemovalReportSupport.swift`）：呼叫回成功，報告多 `indexRebuilt: false`／`indexRebuildError`／`indexNote`。只改 `updateOrganization`；`AkashicService` 內另有二十餘處同形的 write 後 `try rebuild()`（多數寫入面的既有慣例），不在這一輪動——那是另一個規模的改動，記在這裡當作已知邊界。

**退役名（findings 6、17）。** `Organization.authorized` 的「從當前有效的名稱中指定」是慣例、`validate` 不擋，而 `update-organization` 是第一個寫得進它的面：`--authorize "Institute of Statistics"`（names 裡 1960–1993 已結束）成功、`displayName` 變成那個退役名，沒有任何訊號。不拒絕（沒有裁決要擋），報告多 `authorizedNotCurrent`（有事才出現）：指定的名字在 names 的每一段都已結束（`!range.isOpen`：有 `end`、`endedUnknown` 或只有 `attested` 觀測點，與 `names.current` 同一個判準）。新加進 names 的名字沒有時間欄位、是開放段，不會在這裡。

**誠實邊界（findings 14、27，沒有改）。** 入口的 vetting 對**本來就在 names 裡**、含不可見字元的名字也擋（先 vet 後查 names）：`add_organization` 照收 `Acme\u{200B}Institute`，之後對它 `--authorize` 會得到「含不可見字元」的拒絕，而 organization 沒有任何面改或刪名字，建議的出路（刪掉它）做不到，唯一的路是手改 YAML。改成「先 canonical 查找、找得到就不驗」會讓含不可見字元的名字進得了 authorized，而 organization 沒有 venue 的 D8 那道 store 不變式擋它——要不要放寬是使用者的裁決，不是這一輪順手改。live store 的 13 筆 organization 沒有量測過是否含這類名字。

**文字修正。** `WriteGateRulings` 的 `update-organization` 格、`mcp-cli-parity` 的列（原本同一格先寫「先提供 `authorize`」又把 `unauthorize` 當已提供）、`two-kinds-of-edits`、`docs/store-format.md` §3.1、`plugin/CHANGELOG.md`、`Organization.authorized` 的 doc 都改成沒有撤回面。

### 負對照（R1 verify 之後）

每個 mutant 改一處、重編（含兩個 executable）、跑 `OrganizationAuthorizeTests`＋`UpdateOrganizationCLITests`＋`NameDesignationStdioTests`（N4 另加 `ToolPayloadKeyGuardTests`），再以反向編輯還原並以 `cmp` 對事先存下的副本確認逐位元組相同。數字是 XCTest 的 failures。

| mutant | 結果 |
|---|---|
| N1 拿掉「過了 vetting 沒有名字就拒絕」（`guard !authorizeIn.isEmpty || true`） | 12 failures，4 個測試紅（argv 檢查、服務層不動檔案、CLI 的 64、stdio 三種形狀） |
| N2 沒有變動也寫檔（`guard changed \|\| true`） | 2 紅（`testAlreadyAuthorizedOnlyDoesNotRewriteTheFile`、`testIndexRebuildFailureAfterTheWriteIsReportedNotThrown` 的「重試不多出 index 鍵」）。第一版 N2 寫成 `changed && false`（＝永遠不寫）——那是另一個 mutant，23 failures；原意的「永遠寫」要 `\|\| true` |
| N3 index 重建失敗改成擲錯 | 1 紅（`testIndexRebuildFailureAfterTheWriteIsReportedNotThrown`） |
| N4 `authorizedNotCurrent` 永遠空 | 2 failures，1 個測試紅（`testRetiredNameIsAcceptedButReported`）；`ToolPayloadKeyGuardTests` 綠（該鍵不在 payload 就沒有東西要對描述） |

### `tools/list` 位元組（R1 verify 之後）

拿掉 organization 的 `unauthorize` 參數與兩個回應鍵名，補 `authorizedNotCurrent`／`indexRebuilt`／「沒有要改的」的說明：53,403 → **53,556**（實測，真 binary）。預算 54,000，餘裕 444。
