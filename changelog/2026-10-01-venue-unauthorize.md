# 2026-10-01 venue 的 `authorized` 有了撤回面：`update-venue --unauthorize`（#559）

使用者 2026-10-01 裁決：「加 --unauthorize」——逐名撤回，必須是現有 authorized 成員，移出後留在 names（未標）。比照 `clear_paginated`（#500）與 `demote`（#418）的「撤回回到誠實的未判定狀態」。

## 為什麼

#554 的 `--authorize` 是同書寫系統替換：只能把對外形換成另一個名字，回不到「不作任何宣稱」（`venue-entity` spec 的未標）。只有一個名字的 venue（例如 `journal-of-the-royal-statistical-society-7`），authorized 一旦在就永遠在；「bootstrap 給的 `names[0]` 其實是 WoS 的全大寫形，正確的對外形我還不知道」這句話寫不出來，只能手改 YAML。`add-venue` 建的 venue 天生就在空 authorized 的狀態，bootstrap 建的回不去（#563 之後新建的也不再有這個問題）。

## 契約（CLI `--unauthorize <name>`，可重複；MCP `akashic_update_venue` 的 `unauthorize` 陣列）

- 每個名字都必須是現有的 authorized 成員，相等看 `NameIdentity.canonical`（與 `--authorize` 同一條：尾隨空白、NFD 的輸入撤回 store 裡那一筆）。移出 authorized、**留在 names、不標 variant**。
- 整批拒絕、零寫入（同一次呼叫的其他參數也不寫）：
  - 不是現有成員（訊息列出現有的對外形，空的時候說「現有：無」）；
  - 同一個名字又在 `authorize`——兩句矛盾的話，讀 store 之前就擋（CLI 是用法錯誤 64）；
  - 被 `field: authorized` 的 reference 指著——撤回後它們成孤兒，訊息指路 `--remove-reference`（`--authorize` 換下舊指定那一格同一條紀律）。
- 整項空白是「沒說話」：不寫、回報在 `unauthorizeDropped`。
- **撤回先於 `authorize`**：成員資格看呼叫前的 authorized，「撤回 A、指定 B」在同一次呼叫裡不因順序而變；A 報在 `authorizedWithdrawn`，不在 `authorizedRemoved`（它不是被 B 換下來的）。
- 與 `add_variant` 給同一個名字不是矛盾：那是明說「它不是對外形、它是異寫」，照做。
- `remove_reference`／`edit_name_segment` 單獨呼叫，不與它組合（`otherLegs` 多一格）。
- 報告多兩個鍵：`authorizedWithdrawn`（被撤回的 store 拼法）、`unauthorizeDropped`。
- **不設 git 閘**：逆操作是 `--authorize`，名字一直在 names，沒有資訊只剩 git 那一份。

## 判定記錄

撤回是判定（`two-kinds-of-edits` 的 AI 欄）。#564 已於 2026-10-01 裁決名字分類面全部要留判定記錄（含撤回），另案落地（需要 store format bump）；在那之前本面不寫記錄。替換與撤回的邏輯寫成純值運算（見下），報告的各桶就是那筆記錄要記的內容，落地時由呼叫端依報告寫 reference，不必改替換與撤回本身。

## 實作

替換（#554）與撤回搬進 `Sources/AkashicMCPKit/AuthorizedDesignation.swift` 一份：`authorize(_:)` 原樣從 `updateVenue` 搬出（訊息逐字不變，既有的 `VenueAuthorizedWriteTests` 89 個測試照綠），`unauthorize(_:)` 是新的。#557 的 organization 用同一份。同一個名字既 `authorize` 又 `unauthorize` 的檢查是 `AkashicService.refuseAuthorizeUnauthorizeOverlap`，venue 與 organization 的入口共用。

連帶改的文字：`edit_name_segment` 移除最後一段、名字還在 authorized 時的拒絕訊息多指一條路（`--unauthorize`）；`docs/store-format.md` 兩處；`WriteGateRulings` 的 `update-venue` 那一格的理由補上這條腿（裁決不變：不閘）。

## 沒有做的

#559 的補記（#554 R16 verify regression 第 23 列）建議在 `resolve-venues` 不帶參數的列表裡報「因正規化配對被抑制的候選數」。那是 `VenueResolver` 的否決抑制（`--reject`／`--demote` 以 `matchingKey` 壓住同 work 同 venue 的其他拼法），與 authorized 的撤回是兩件事：要新增列表的回應鍵、MCP 說明（位元組預算）與 CLI 輸出，不是順手的改動。本次不做，留在 #559 的那則補記裡。

## 測試

| 測試 | 驗什麼 |
|---|---|
| `VenueUnauthorizeTests`（12 個，服務層） | 移出、留在 names、不標 variant；canonical 相等與 store 拼法；非成員（在 names 未指定／不在 names）整批拒絕且同一次的 add_names 不寫；「現有：無」；authorize＋unauthorize 同名（服務與 argv 兩層）；空白項；被 reference 指著；撤回先於指定；與 add_variant 同名；只撤回指名的書寫系統；`authorize` 指定回來；單獨呼叫的腿不與它組合 |
| `UpdateVenueUnauthorizeCLITests`（2 個，真 binary） | `--unauthorize` 寫進 store；非成員非零結束；矛盾是用法錯誤 64、早於開 store |
| `NameDesignationStdioTests.testVenueUnauthorizeReachesTheService`（真 binary、stdio） | MCP 分派把 `unauthorize` 交給服務；少一層括號整個呼叫拒絕 |
| `ToolPayloadScenarios` 多一個 `unauthorize` 情境 | 新的兩個回應鍵出現在工具說明裡（#672） |

### 負對照

每個 mutant 改一處、重編（含兩個 executable）、跑上面三個 test class，再以反向編輯還原並以 `cmp` 對事先存下的副本確認逐位元組相同。

| mutant | 結果（15 個測試；數字是 XCTest 的 failures） |
|---|---|
| M1 非成員不擋（`guard !hits.isEmpty \|\| true`） | 7（服務層非成員、CLI 非零結束） |
| M2 拿掉 authorize／unauthorize 同名檢查 | 4 紅（服務兩層、CLI 的 64） |
| M3 MCP 分派漏接 `unauthorize` | 2 紅（stdio 測試：回應沒有撤回、store 沒變） |
| M4 CLI `run()` 漏傳 `--unauthorize` | 4 紅（CLI 測試） |
| M5 撤回排在指定之後 | 1 紅（`testWithdrawAndAuthorizeInOneCall`：撤回找不到已被換掉的名字） |
| M6 拿掉被 reference 指著的檢查 | 1 紅（錯誤改由寫入閘擲出、不說出路） |
| M7 撤回時順手標 variant | 3 紅（服務與 CLI 的「不標 variant」、與 add_variant 同名時撞近重複） |

## `tools/list` 位元組

`akashic_update_venue` 多一個參數說明：整行 51,997 → 52,277（+280）。預算 54,000（`StdioE2ETests.testToolsListResponseStaysWithinByteBudget`）。
