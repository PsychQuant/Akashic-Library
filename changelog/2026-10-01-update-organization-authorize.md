# 2026-10-01 organization 的 `authorized` 有了寫入面：`update-organization`（#557）

使用者 2026-10-01 裁決：「新增 update-organization --authorize」——選形狀 2：新增 `update-organization` 面（CLI）與對應的 MCP 工具，先提供 `--authorize`，語意比照 `update-venue --authorize`；新命令兩面都在 `mcp-cli-parity` 落表。

## 為什麼

`Organization.authorized` 對齊 RDA 的 authorized access point，`doctor` 也把空的 authorized 算進 `no authorized name: N person / M organization`——而在此之前沒有任何面寫得進它：`addOrganization` 不收、`OrgBootstrap` 不寫、`authorize-names` 只管 person。2026-09-11 實測 live store 13 筆 organization、有 authorized 0 筆，`doctor` 那一行恆為真且修不掉，`displayName` 全部走 fallback（`names.current` 或裸 key）。

**`doctor` 那一行自此修得掉**：`update-organization <key> --authorize <名字>` 之後，那筆 organization 不再算在 `no authorized name` 的 organization 數裡（`OrganizationAuthorizeTests.testDoctorNameGapShrinks` 走服務層、`UpdateOrganizationCLITests` 走真 binary 的 `doctor`，都驗從 1 變 0）。

## 契約（CLI `update-organization <key> --authorize … --unauthorize …`；MCP `akashic_update_organization`，`key` ＋ `authorize`／`unauthorize` 陣列）

- **`--authorize`**：與 `update-venue --authorize` 同一份邏輯。同 `WritingSystem` 原子替換，被換下的名字移出 authorized、留在 names（organization 沒有 variant，不會被標）；不同書寫系統之間是 append；不在 names 的以 canonical 形加進 names。相等看 `NameIdentity.canonical`。
- **`--unauthorize`**：#559 的撤回由同一份邏輯直接給出，兩面一起提供：必須是現有的 authorized，移出後留在 names；撤回先於指定。
- 讀 store 之前整批拒絕（CLI 是用法錯誤 64）：兩個都沒給（「沒有要改的」——一次沒有變動的寫入仍會重新序列化整筆記錄、重建 index）、key 格式不合、同一次兩個同書寫系統的名字、同一個名字既 `authorize` 又 `unauthorize`、名字含控制／格式／不可見字元或沒有任何字母或數字。
- 讀 store 之後整批拒絕、零寫入：key 有不只一筆記錄（#669／#670 的 `unlocatableOrganizationKeys`——寫進哪一筆是猜）、找不到、撤回的不是現有成員、被換下或撤回的名字被 `field: authorized` 的 reference 指著（organization 的 reference 沒有移除面，訊息指路手改 YAML）。
- 子集與「每書寫系統至多一個」由 store 邊界擋（`writeOrganization` → `Organization.validate()` → `AuthorizedNames.validate`），寫入面不重造。organization 沒有 venue 那道名字內容的不變式（#554 D8）；新加進 names 的名字過入口的 vetting，那是入口的輸入檢查。
- 回報：`key`、`namesAdded`、`authorizedAdded`、`authorizedRemoved`、`alreadyAuthorized`、`authorizedRewritten`、`authorizeDropped`、`authorizedWithdrawn`、`unauthorizeDropped`、`authorizedTotal`。organization 沒有 variant，不報 `liftedFromVariant`。
- 判定記錄待 #564（2026-10-01 裁決名字分類面全部要留，另案落地、需要 store format bump）；在那之前不寫記錄。

## 實作

替換與撤回的邏輯是 `Sources/AkashicMCPKit/AuthorizedDesignation.swift` 那一份（#559 從 `updateVenue` 搬出）；本次再把「同一次兩個同書寫系統的名字」的檢查原樣搬進同一檔（`refuseSameScriptClash`，訊息逐字不變），venue 與 organization 的入口共用。organization 的定位、寫入與報告在 `Sources/AkashicMCPKit/OrganizationUpdate.swift`；CLI 在 `Sources/akashic/UpdateOrganizationCommand.swift`。`vetVenueNamesReportingBlanks` 從 `private` 改成模組內可見，organization 的入口走同一個 vetting。

**目標 store 確認閘：不閘**（`WriteGateRulings` 的 `update-organization` 格）。理由與 `update-venue` 那一格同：逐筆指名一個 key、被換下或撤回的名字都留在 names、可以再指定回來、不刪任何名字或 reference（`--authorize` 新加進 names 的名字會留著，organization 沒有名字的移除面）。`update-venue` 整個命令要不要有乾跑、要不要閘待使用者裁決，這一格與它一起裁。

## 規則與文件

- `mcp-cli-parity`：MCP 表加 `akashic_update_organization` ↔ `update-organization` 一列（工具 34 → 35）。一列同時裁決了兩面：CLI-only 表只收沒有 MCP 面的命令，把 `update-organization` 也放進那張表會與這一列矛盾（稽核程序說每個命令出現在「MCP 表的 CLI 對應欄**或**」CLI-only 表）。四步稽核：① `Server.swift` 35 個工具、與表零差集；②③ CLI 註冊型別 57 個，`UpdateOrganizationCmd` 解析成 `update-organization`（另有一個既有的 `<未解析>`：`S2Cmd` 被步驟 ② 的 `[A-Za-z]+` 切成 `Cmd`——字元類不含數字，與步驟 ① 修過的是同一個形狀；本次沒有動它）；④ 橫切 `ParsableArguments` 仍是 `LibraryOptions`／`FileConfigOptions`，本次沒有新增。
- `two-kinds-of-edits`：加 `update-organization` 一列（AI）。
- README：CLI 清單加 `update-organization`、工具數 35；`docs/store-format.md` §3.1 補三個實體各自的指定面。

## 測試

| 測試 | 驗什麼 |
|---|---|
| `OrganizationAuthorizeTests`（12 個，服務層） | 寫得進、displayName 跟著換；同書寫系統替換與跨書寫系統 append；不在 names 的以 canonical 形加入；冪等但報 alreadyAuthorized；兩個同書寫系統整批拒絕；authorize＋unauthorize 同名；key 重複整批拒絕零寫入；notFound；沒有要改的與 key 格式早於開 store；撤回；被 reference 指著時指路手改 YAML；`doctor` 的 organization 缺口從 1 變 0 |
| `UpdateOrganizationCLITests`（2 個，真 binary） | `--authorize`／`--unauthorize` 寫進 store、`doctor` 那一行從 1 變 0；用法錯誤 64、早於開 store |
| `NameDesignationStdioTests.testUpdateOrganizationReachesTheService`（真 binary、stdio） | 工具有註冊、有分派，兩個參數都到得了服務層 |
| `ToolPayloadScenarios` 多兩個情境（`authorize`、`unauthorize`） | 每個回應鍵出現在工具說明裡（#672）；每個參數有情境宣告（#700） |
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

## `tools/list` 位元組

整行 52,277（#559 之後）→ 53,024（+747，新工具 776 bytes）。#559 與本次合計 51,997 → 53,024（+1,027）。預算 54,000。organization 的 `unauthorize` 佔其中 147 bytes（一個參數說明與說明裡的兩個回應鍵名；拿掉它們重編實測 52,877）。
