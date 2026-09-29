# 2026-09-29 工具描述對回應鍵的守衛擴到全部工具（#672）、Zotero 匯入與 App 提示的殘項（#684）

## #672：工具描述必須提到回應的每一個鍵

**問題。** MCP 呼叫端（LLM）讀不到 CLI `--help`：`tools/list` 的說明是它決定「回應要讀哪些鍵」的唯一依據。#578 把描述精簡之後，多數工具的回應鍵只剩一句「見 CLI help」。守衛 `ServiceTests.testToolDescriptionCoversEveryTopLevelPayloadKey` 只掃 `akashic_resolve_people`，而且掃的是原始碼裡宣告後的前 3,000 字元——描述與 payload 分岔時，其餘 32 個工具沒有任何東西會紅。

**守衛（新，`ToolPayloadKeyGuardTests`）。**

1. 說明文字取自**真 binary 的 `tools/list`**，不讀原始碼：字串插值與 `+` 串接在原始碼裡不是呼叫端看到的樣子。
2. payload 鍵取自**真實呼叫**：`ToolPayloadScenarios` 的 88 個情境在 fixture store 上走各工具的主要腿（乾跑／實跑、各寫入腿、各 action），回應 JSON 的頂層鍵（陣列則取元素鍵）取聯集。fixture 是一份建好並 commit 的樣板，每個情境複製一份，整組約 15 秒。
3. 每個鍵要以**識別字邊界**出現在該工具的說明裡（子字串不算：`namesTotal` 出現不代表 `names` 被說明了）。
4. 刻意不寫的鍵在 `ToolPayloadKeyExemptions` **逐鍵具名、附理由**，理由是封閉的三種：`echo`（回顯呼叫端給的值）、`advisory`（給人讀的固定說明句）、`standard`（CSL-JSON 的標準欄位）。目前 34 個鍵，全在表裡逐一列出，沒有萬用豁免。豁免本身也被守衛：鍵必須真的出現在 payload、且真的沒被說明提到，否則紅（不留過期的豁免）。
5. 工具清單與情境必須一致（新增工具要同時加情境）；情境若擲錯或回的形狀不是預期（fixture 漂移），守衛紅，不悄悄少掃。

**說明的範圍**是 `description` 加各參數的 `description`——呼叫端讀得到的就是這兩處。只認 `description` 會逼參數說明裡已經寫著的回報鍵（`add_names` 的「回報 namesAdded…」）在描述裡再寫一遍，而 #578 的預算裝不下重複（見「代裁」）。

**補進說明的鍵。** 守衛第一次跑就報出 27 個工具、約 125 個沒被提到的鍵（`get_entry` 的 `authors`／`fields`／`venues`、`import_zotero` 的 11 個報告鍵、`doctor` 的 `quarantined`／`crossRecordIssues`／`indexRebuilt`、`update_venue` 的各個 `*Total`、三個 resolve 工具各寫入腿的回應鍵……）。每個只寫「鍵名＋一句意思」，意思逐鍵對照 service 的 payload 建構碼與樣本回應寫的。`tools/list` 從 45,888 增到 **48,262 bytes**（預算 49,000）。

**負控。**

- 從 `akashic_update_entry` 的描述拿掉 `sourcesTotal` → 守衛紅（「akashic_update_entry：sourcesTotal」）；還原後 `cmp` 一致。
- 在 `venues()` 的 payload 加一個沒有說明的鍵 `zzGuardProbe` → 守衛紅（「akashic_venues：zzGuardProbe」）；還原後 `cmp` 一致。
- 豁免表加一個已經寫進說明的鍵（`itemsTotal`）與一個 payload 沒有的鍵 → `testEveryExemptionIsLive` 兩條都紅；還原後 `cmp` 一致。
- `testGuardGoesRedWhenADescriptionDropsAKey` 對判定函式本身做同一件事（純函式、不重建 binary）。

舊的 `testToolDescriptionCoversEveryTopLevelPayloadKey` 由新守衛取代（`resolve_people` 的列表與各寫入腿都在情境裡），原處留一段指路註解。`mcp-cli-parity.md` 的位元組預算段落後面加了這條守衛的說明，並說明它與預算是同一件事的兩個約束。

### 誠實邊界

- **只涵蓋情境走得到的鍵。** 只在特定 store 狀態才出現的鍵沒有涵蓋：`akashic_doctor` 的 `sourcesAuditError`、`akashic_import_zotero` 的 `authorsPreserved`／`quarantineConflicts`／`writeFailed`、各寫入工具在 I/O 失敗時的 `writeFailed`、`akashic_files` 的 `legacy_library`，以及 `akashic_files` 的 `use` action（需要 registry）。這些鍵要嘛已經在描述裡（`writeFailed`），要嘛沒有；守衛不知道。
- **識別字邊界擋不住通用字。** `type`、`key`、`names`、`count`、`total`、`first` 這類鍵，說明裡任何一處出現同一個英文字都算數（例如 `venue.type` 被「biblatex entry type」滿足）。這是比對方式的固有限制；要擋它得要求「鍵名出現在程式碼樣式裡」，而說明是純文字，沒有那個標記。
- **陣列回應只守元素鍵的聯集**（`search`、`relations`、`people`、`libraries list`、`export` 的 CSL-JSON），不守每一列是否都帶同一組鍵。
- **預算餘量只剩約 580 bytes**（見下）。往後每新增一個回應鍵，說明就要長，預算不許長：新鍵的那句話要從別處省，或回 #578 重新裁決預算。

## #684：#609／#610 的三個低優先殘項

### 1. `akashic_import_zotero` 的 `ambiguousSourceClaims` 沒有上限

**根因。** #610 讓匯入回報「同一個 Zotero 來源被多筆 entry 宣稱」，值是來源鍵到宣稱者 citekeys 的字典。MCP 面把它原樣放進回應；其他 MCP 面（`akashic_enrich` 的 items、`resolve_*` 的候選列）都截 20 筆並揭露總數，這一個沒有——一個大量 entry 宣稱同一來源的 store 會讓單次回應膨脹。

**改了什麼。**

- `AkashicService.importZotero` 多一個 `claimLimit: Int? = nil`（比照 `enrich` 的 `itemLimit`），由 server 傳入 `AkashicMCPServer.ambiguousClaimsLimit`（20）。
- 至多 20 個來源（依來源鍵排序）、**每個來源至多 20 個宣稱者**（依 citekey 排序）；多兩個鍵 `ambiguousSourceClaimsTotal`（完整的來源數）與 `ambiguousSourceClaimsTruncated`（來源被截、或任一來源的宣稱者被截即 true）。三個鍵同進同出：沒有歧義時都不出現。
- index rebuild 失敗時錯誤訊息裡的報告是同一個 payload，同一個上限。
- `claimLimit < 1` 在動 store 之前拒絕（0 不是「全部」也不是「一個都不要」）。
- **CLI 逐行全列**——有記錄的兩面差異，寫進 `mcp-cli-parity.md` 的 `akashic_import_zotero` 列（同時把那一列原本寫的「兩面都沒有筆數上限……出現時比照 D30 重開」劃掉，那句在這次之後為假）。
- MCP 工具描述補上上限與兩個新鍵。

**測試。** `ImportZoteroReportSurfaceTests` 新增 7 條：上限之內全列且仍給總數與 `false`、超過上限依鍵排序截並揭露、沒給上限＝全列、單一來源的宣稱者被截也算截斷、沒有歧義三個鍵都不出現、rebuild 失敗路徑同一個上限、`claimLimit < 1` 拒絕且零匯入。`StdioE2ETests.testImportZoteroCapsTheAmbiguousClaimsAtTheServer` 走真 binary、22 個來源各被兩筆 entry 宣稱，斷言回 20 個、總數 22、截斷 true——釘住 `Server.swift` 沒有漏掉 `claimLimit:` 那個引數（漏掉的話 service 層測試全綠而 MCP 面無上限）。

**負控。**

- server 分派拿掉 `claimLimit:` → e2e 測試紅（22 ≠ 20、截斷旗標 false）。
- payload 建構碼忽略來源上限 → 三條 service 測試與 e2e 紅。
- payload 建構碼不截宣稱者 → 宣稱者測試紅。
- 全部以反向編輯還原，`cmp` 一致。

### 2. index 的 `orphaned` 欄語意改了沒 bump

**沒有改碼。** `LibraryIndex` 的 `entries.orphaned` 欄在 #609 之後由 `Entry.zoteroLinkState == .orphaned` 判定（也涵蓋「沒有主來源而附加來源全部已刪除」），`schemaVersion` 仍是 5。2026-09-29 量測：全 `Sources/` 讀這一欄的地方是 **0**（SQL 的選／篩／排序與 row 字典取值皆無；寫入只有建表一行與 rebuild 的 bind），positive control 通過。沒有讀者就不 bump——bump 只會讓每個使用者的 index 白重建一次。

觸發條件與量測寫成零實例列的提案，放在修正報告裡交整合者加（多個 agent 同時動 `zero-instance-guards.md` 會撞列號）。

### 3. `OrphanView` 疊了三個 `.alert`

**根因。** 確認（拿掉已刪除的附加來源）、結果（已拿掉）、失敗（操作失敗）各一個 `.alert`，各綁一個獨立的 `@State`。「確認」按鈕的動作在關掉自己的同時讓另外兩個之一亮起：同一個 view 上的兩個 `.alert` 修飾子互相搶著呈現，SwiftUI 對「一個提示的按鈕動作裡再彈另一個」沒有保證；而且沒有任何測試。

**改了什麼**（先載入 `apple-xcode-skills:swiftui-specialist`；用的是非 soft-deprecated 的 `alert(_:isPresented:presenting:actions:message:)`，`@State` 都是 `private`）：

- `OrphanAlert`（enum：`confirmRemoval`／`removed`／`failed`，標題跟著 case 走）與 `OrphanAlertState`（現在顯示的提示＋排隊中的下一個）在新檔 `OrphanAlert.swift`。`OrphanView` 只剩一個 `.alert`。
- **為什麼有 `queued`**：SwiftUI 在按鈕動作**之後**才把 `isPresented` 設成 false。若「拿掉」按鈕的動作直接把狀態換成結果提示，緊接著的關閉會把它抹掉——使用者按了「拿掉」卻看不到結果。所以動作裡的 `show` 在畫面上有提示時只排隊；關閉之後由 `.onChange` 在下一個 runloop 呼叫 `presentQueued()`，讓 `isPresented` 真的走一次 false → true。
- `OrphanModel.confirmRemoval` 收下按「拿掉」之後的全部狀態轉換（成功：清理由草稿、排 `.removed`；失敗：**保留**草稿、排 `.failed`），`OrphanModel.attempt` 收下其他兩個動作（轉純 Akashic、垃圾桶）的失敗顯示。這些先前在 view 的閉包裡，沒有 SwiftUI 就測不到。
- `PendingRemoval` 從 `OrphanView` 的巢狀型別移到頂層（`OrphanAlert` 的關聯值要用它）。
- `SanitizationBoundaryTests` 的「Error → 文字入口」計數表同步：`AdjudicationViews.swift` 的 `errorMessage = displaySafeErrorMultiline(error)` 3 → 2，`OrphanAlert.swift` 新增 2 處。

**測試。** `OrphanAlertStateTests` 9 條（初始、閒置時立刻顯示、有提示時排隊不取代、**按鈕動作後的關閉不抹掉排隊中的下一個**、失敗走同一條路、取消回到閒置、後來的排隊取代先前的、`presentQueued` 只在該動時才動、三種提示的標題不同）；`OrphanedAdditionalSourceTests` 加 3 條用真的 `OrphanModel` 與 git fixture：成功排 `.removed` 且報告帶來源鍵與理由全文、草稿清掉，失敗排 `.failed`（記錄檔沒 commit）且草稿保留，`attempt` 成功不動提示、失敗立刻顯示。

**負控**（`OrphanAlert.swift` 反向編輯，每項還原後 `cmp` 一致）：`dismissed()` 連排隊中的一起清 → 4 條紅；`show` 直接取代目前的提示 → 7 條紅；失敗也清草稿 → 失敗測試紅；`presentQueued` 不看畫面上有沒有提示 → no-op 測試紅。

### 誠實邊界

- **畫面上的行為沒有驗證。** 這個 session 沒有 UI 可跑，`AkashicApp/` 也沒有 UI 測試基礎設施。我能保證的是狀態轉換（有測試）與型別檢查（嚴格建置通過）；「SwiftUI 在按鈕動作之後才設 isPresented=false」是從既有的 SwiftUI 行為推得的，`presentQueued` 延後一個 runloop 是為了讓 false → true 真的發生，兩者都沒有在真的畫面上看過。第一次手動點過「拿掉已刪除的來源」（成功一次、失敗一次）才算數。
- 垃圾桶的 `confirmationDialog` 不是 `.alert`，沒有併進去；它按下後若失敗，錯誤走 `attempt` 立刻顯示，與確認對話框的關閉同時發生——和先前一樣，沒有處理。
- `ambiguousSourceClaims` 之外的清單（`created`／`updated`／`orphaned`／`writeFailed`……）在 MCP 面仍沒有上限，與 #684 的範圍一致，沒動。

## 位元組預算

`tools/list`：**45,888（開工時）→ 48,419 bytes**（#672 補回應鍵 +2,374、#684 補上限說明 +157），預算 49,000，餘量 581 bytes。量法與 `StdioE2ETests.testToolsListResponseStaysWithinByteBudget` 相同（真 binary、回應那一行）。

## 與 #664 合併（2026-09-29）

rebase 到 #664 之後，守衛的「每個工具都有情境」檢查立刻抓到 `akashic_s2` 沒有情境——這正是它要擋的形狀。補了兩條情境（`Tests/AkashicMCPTests/ToolPayloadScenariosS2.swift`）：

- 分頁端點（references）：base URL 覆寫到本機、請求由 `S2ToolStub` 攔截，不連網、不讀 keychain。
- `status`：回 `{keychain, throttle, host}`，這三個鍵先前不在描述裡，已補進 `akashic_s2` 的說明。

`S2Tool.run` 是 async，情境閉包是同步的，以 semaphore 等結果。負控：從描述拿掉這三個鍵名，`testEveryPayloadKeyIsDescribedOrExempt` 轉紅；還原後轉綠。
