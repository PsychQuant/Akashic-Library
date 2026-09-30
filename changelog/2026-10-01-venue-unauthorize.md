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
- 報告多兩個鍵：`authorizedWithdrawn`（每列 `{name, index}`：被撤回的 store 拼法與它在呼叫前 authorized 裡的位置；首輪是字串陣列，R1 verify 之後改）、`unauthorizeDropped`；撤回改變預設顯示名時多 `displayNameChanged`（見文末）。
- **不設 git 閘**：使用者沒有裁決要閘；名字與分類都留在 names。首輪寫的理由「逆操作是 `--authorize`、沒有資訊只剩 git 那一份」是錯的（見文末）——撤回再指定回來，名字與分類回得來，authorized 內的順序回不來。

## 判定記錄

撤回是判定（`two-kinds-of-edits` 的 AI 欄）。#564 已於 2026-10-01 裁決名字分類面全部要留判定記錄（含撤回），另案落地（需要 store format bump）；在那之前本面不寫記錄。替換與撤回的邏輯寫成純值運算（見下），報告的各桶就是那筆記錄要記的內容，落地時由呼叫端依報告寫 reference，不必改替換與撤回本身。

## 實作

替換（#554）與撤回搬進 `Sources/AkashicMCPKit/AuthorizedDesignation.swift` 一份：`authorize(_:)` 原樣從 `updateVenue` 搬出（訊息逐字不變，既有的 `VenueAuthorizedWriteTests` 89 個測試照綠），`unauthorize(_:)` 是新的。#557 的 organization 用同一份。同一個名字既 `authorize` 又 `unauthorize` 的檢查是 `AkashicService.refuseAuthorizeUnauthorizeOverlap`，venue 與 organization 的入口共用。

連帶改的文字：`edit_name_segment` 移除最後一段、名字還在 authorized 時的拒絕訊息多指一條路（`--unauthorize`）；`docs/store-format.md` 兩處；`WriteGateRulings` 的 `update-venue` 那一格的理由補上這條腿（裁決不變：不閘）。

## 沒有做的

#559 的補記（#554 R16 verify regression 第 23 列）建議在 `resolve-venues` 不帶參數的列表裡報「因正規化配對被抑制的候選數」。那是 `VenueResolver` 的否決抑制（`--reject`／`--demote` 以 `matchingKey` 壓住同 work 同 venue 的其他拼法），與 authorized 的撤回是兩件事：要新增列表的回應鍵、MCP 說明（位元組預算）與 CLI 輸出，不是順手的改動。本次不做。**處置待辦：另開 issue 追蹤**（R1 verify 第 12／19 列：#559 一旦 close，留在那則補記裡的待辦就沒有可掃描的位置，`blocked-issues-must-be-scannable` 同型）；issue 號由開立的人補進這一行。

## 測試

| 測試 | 驗什麼 |
|---|---|
| `VenueUnauthorizeTests`（首輪 12 個；R1 verify 之後 14 個，服務層） | 移出、留在 names、不標 variant；canonical 相等與 store 拼法；非成員（在 names 未指定／不在 names）整批拒絕且同一次的 add_names 不寫；「現有：無」；authorize＋unauthorize 同名（服務與 argv 兩層）；空白項；被 reference 指著；撤回先於指定；與 add_variant 同名；只撤回指名的書寫系統；`authorize` 指定回來（名字與分類回來、位置不回來）；報告帶原 index（一次撤回多個以呼叫前的清單算）；撤回預設顯示名時報 `displayNameChanged`；單獨呼叫的腿不與它組合 |
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

首輪寫「整行 51,997 → 52,277（+280）」。首輪自己的三份 changelog 位元組數字互相對不起來，R1 verify 以真 binary 重量 #557 之後的 HEAD 是 53,403（不是 53,024），所以這一行的基準也不可信。**最終數字（R1 verify 之後，真 binary，同 `testToolsListResponseStaysWithinByteBudget` 的算法）：53,692**，預算 54,000，餘裕 308。

## R1 verify 之後（2026-10-01，41 個 findings，本節是 #559 的部分）

**「逆操作是 `--authorize`」不成立（findings 5、9、11、18、23；五席獨立抓到，DA 席真 binary 重現）。** `authorize` 只有同書寫系統**替換**才把新指定插回第一個被動到的位置（#554 R3 第 2 列，理由正是 `displayName` 取 `authorized.first`）；對「不在 authorized 裡」的名字一律接在尾端。所以 venue `psy`，names＝[Psychometrika, PSYCHOMETRIKA, 心理計量學]、authorized＝[Psychometrika, 心理計量學] → `--unauthorize Psychometrika` → `--authorize Psychometrika` 得到 authorized＝[心理計量學, Psychometrika]，預設顯示名從 Psychometrika 變成 心理計量學。首輪的文字依賴「完全可逆」這個前提：兩份規則檔、兩份 changelog、`WriteGateRulings` 的 `update-venue` 格、`--help`、plugin CHANGELOG 都寫「逆操作是 `--authorize`」、「再用 `--authorize` 可指定回來」，並以此當作不設 git 閘的理由。

處置（orchestrator 的決定：**不加 git 閘**——使用者沒有裁決要閘，而名字與分類確實都回得來）：
- **文字改成誠實版本**：名字與分類（未標）回得來，位置回不來；不是精確逆操作。上述每一處都改了。
- **報告帶撤回前的位置**：`authorizedWithdrawn` 的每一列是 `{name, index}`（index 以**呼叫前**的 authorized 算、0 起算，一次撤回多個時不因先撤回哪一個而位移）。遺失的資訊（authorized 內的順序）因此在報告裡有一份，不只在 git。
- **預設顯示名改變時說出來**：`displayNameChanged: {before, after}`（與 `edit_name_segment` 面同一個鍵、同一個形狀；只在有 `unauthorize` 的呼叫裡算——其他腿的顯示名變化是呼叫端自己要的，`authorize` 就是在指定顯示名）。涵蓋的情形比 orchestrator 列的「撤回 authorized 的第一個而清單有 ≥2 個」多一格：撤回**最後一個**時顯示名退到 names 的 fallback，也可能改變（venue 的 fallback 是 names 第一段，例如 Psychometrika → PSYCHOMETRIKA）。比較的是撤回前後的 `venue.displayName`，所以判準是「真的變了」，不是位置的代理。
- **沒有做**：不記住位置讓 `authorize` 插回原位（那會改變 `authorize` 的語意：「不在 authorized 裡的名字接在尾端」是 #554 的既有契約，且沒有地方存那個位置）。

**同一份查找只寫一次（finding 30）。** `AuthorizedDesignation.storedSpelling` 與 `updateVenue` 裡給 `add_names`／`add_variant` 用的 `resolveSpelling` closure 是同一條相等與查找寫了兩次。現在只有 `AuthorizedDesignation.storedSpelling(_:in:)` 一份（static，吃 names 的條目），instance 版與 closure 都呼叫它。finding 30 的另一半（venue 與 organization 入口檢查先後不同：venue 先查 authorize／unauthorize 重疊再查同書寫系統衝突，organization 反過來）隨 organization 的 `unauthorize` 拿掉而不存在——organization 只剩同書寫系統衝突一個檢查。

**stdio 測試的讀取迴圈（findings 10、20）。** `NameDesignationStdioTests.readResponse` 照 `DepthGuardIdTests` 的 `availableData` 迴圈：server 靜默時讀取阻塞、20 秒期限輪不到檢查；server 崩潰（EOF）時 `availableData` 回空、空轉到期限後 `XCTSkip`——把崩潰記成跳過，這組測試存在的理由（分派漏接參數時呼叫照樣回成功）就靜默消失。改用 `StdioE2ETests.readLine`（#578 R1 為同一個問題加的：non-blocking、有期限、EOF 與逾時都丟錯），server 結束是**失敗**。`DepthGuardIdTests` 的同形寫法是既有的，不在這一輪動。

**沒有做、待 issue 的（findings 12、19）。** 同上「沒有做的」一節：否決抑制被靜默壓掉的候選數，另開 issue。

### 負對照（R1 verify 之後）

每個 mutant 改一處、重編（含兩個 executable）、跑相關 test class，再以反向編輯還原並以 `cmp` 對事先存下的副本確認逐位元組相同。

| mutant | 結果 |
|---|---|
| M1 撤回報告的 index 一律 0 | 2 failures，1 個測試紅（`testIndexesAreReportedAgainstTheListBeforeTheCall`：位置 1 與 2）；其他測試的位置本來就是 0，所以只有多名字的那個抓得到 |
| M2 `displayNameChanged` 永遠不出 | 2 failures，2 個測試紅（撤回最後一個、撤回第一個而還有別的名字） |
| M3 共用的查找一律回 nil（證明兩條路都走同一份） | 117 個測試裡 37 failures（36 個測試紅）：`VenueAuthorizedWriteTests`（`add_names`／`add_variant`／authorize 路徑）、`VenueUnauthorizeTests`（撤回路徑）、`OrganizationAuthorizeTests`（organization 的 authorize）同時紅 |
| M4 stdio 測試的 server 一啟動就結束（`/usr/bin/true`） | 2 failures（2 個測試 `failed`，訊息「對端關閉，未收到完整的一行（已收 0 bytes）」）。XCTest 另附一行「Test skipped: threw error」——那是 setUp 丟錯的附帶記錄，測試結果是 failed，不是只有跳過；首輪的寫法在這個情境是只有 `XCTSkip` |
