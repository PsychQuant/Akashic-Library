# 2026-10-01 `resolve-venues` 的列表報出被正規化配對壓掉的候選（#712）

#559 R1 verify（requirements 第 12 則、logic 第 19 則）轉述 #554 R16 verify regression 第 23 列的建議：#554 R12 起，`resolve-venues` 的否決抑制以 `NameNormalization.matchingKey` 為鍵，所以對一個拼法的 `--reject`／`--demote` 會一併壓住**同一 work、同一 venue 的其他拼法**。那是提名面 recall 的收窄，而列表輸出不說——被壓住的候選是靜默消失的（`identity-is-judged-not-matched` §「提名是 recall」：靜默是 `lossless-intake` 明列為最糟的失敗形式）。這次補上，立場同 resolve-people 已否決段的「沉底而非隱藏」。

## 契約

列表（不帶任何寫入腿）多三個鍵，兩面（CLI 與 MCP `akashic_resolve_venues`）同一份：

| 鍵 | 內容 |
|---|---|
| `suppressed` | 被正規化配對的否決壓掉的候選，依 (citekey, venueIndex) 排序。每列 `citekey`、`venueIndex`、`literal`（被壓住的那條邊自己的字串）、`venueKey`、`rejectedLiterals`（壓住它的 rejected verdict 的拼法，依字串排序，至多 5 個，超過時該列多 `rejectedLiteralsTotal`）。**刻意沒有 `id`**：它不是可 apply 的候選（`candidates` 裡沒有這個 id，apply 會 notFound），給 id 會讓消費端以為可以送回去 |
| `suppressedTotal` | 全數。**永遠是分母**，不隨截斷變小 |
| `truncated` | `suppressed` 這一段被截（列數或位元組預算）。venue 列表的 `candidates`／`ambiguities` 沒有列數上限，所以它在這一腿只有這個意思；與 `repoint`／`demote` 那一腿的 `verdictsRetired` 的 `truncated` 同名，兩者不會出現在同一次回應 |

**永遠回這三個鍵**：沒有候選被壓時是空陣列與 `0`——「沒有」與「沒給你看」要分得開。

### 面級分工（與 `verdictsRetired` 同一個）

- **CLI**：全列（服務層參數 `suppressedLimit: nil`），沒有位元組預算——輸出進人的終端機，操作者要能列舉每一筆。venue 的 CLI 列表本來就是服務 JSON 的原樣輸出（沒有 resolve-people 那種人可讀排版），所以 issue 說的「計數行」就是 `suppressedTotal`，不另造一套文字格式。
- **MCP**：截 20 筆（`AkashicService.suppressedItemsCap`），並另受 `candidateByteBudget`（48 KiB）約束：吃不下的整列不印（同 resolve-people 的候選列，`id` 不能截斷的同一個理由換成「整列不印比印半列誠實」），`suppressedTotal` 與 `truncated` 揭露。位元組以 `jsonBytes` 實際量。
- 每列 `rejectedLiterals` 的個數另設上限（`suppressedLiteralsPerRow` = 5），因為每個都是 store 字串、`displaySafe` 逃脫後每個 scalar 最多 9 bytes；實務上同一 work 同一 venue 被否決的不同拼法不超過這條 work 的 literal 邊數。

## 判準：進 `suppressed` 的只有一類

> 一條 literal 邊被某筆 rejected verdict 以 `matchingKey` 壓住，而**壓住它的每一筆 rejected verdict 的 literal 都不與它自己的 literal 相等**（Swift `String ==`）。

換句話說：**若抑制仍比逐字配對（#554 R12 之前的行為），這個候選本來會列在 `candidates`**——R12 隱藏的正是這一批。程式裡的對應是 `VenueResolver.resolve` 的否決表從 `Set<RejectedPairKey>` 改成 `[RejectedPairKey: [String]]`（值是壓住這個鍵的每個原始 literal）：抑制只看「鍵在不在」，與先前逐位元相同；值只用來分辨「逐字相等的普通已否決」與「被正規化壓掉的」。

兩個邊界：

- **逐字相等的壓住者是普通的已否決**，列表一向不列，維持原樣。同一配對有兩個拼法被否決、候選逐字等於其中之一時，也是普通已否決（即使另一個拼法也壓得住它）。
- **歧義不進來**：抑制只作用於不歧義的提名（對到恰好一個 venue）；對到 2+ venue 的 literal 一向不被抑制、照列在 `ambiguities`。

### 為什麼是 `==` 而不是位元組相等（與 issue 的字面不同，請使用者確認）

issue 寫「by matchingKey 但不是 byte-exact literal」。我選 Swift 字串相等（canonical equivalence），理由有三：

1. **否決表是 `Set<ResolutionPairing>`**，合成的 `Hashable` 以 `String ==` 比 literal——只差 NFC／NFD 的兩筆 verdict 在進這個集合時就被收成一筆，位元組層的差別在 `resolve` 看到的輸入裡**已經不存在**。要做位元組判準得改簽章、拿 verdict 清單而不是集合。
2. **那一格不是 R12 收窄出來的**：R12 之前的比對（`rejected.contains(ResolutionPairing(…literal: literal…))`）也是 `==`，只差 NFC／NFD 的候選當時就壓得住。報它等於把「這次沒變的行為」報成「R12 隱藏的東西」。
3. **對讀的人沒有資訊**：報告會印出兩個看起來一模一樣的字串，卻說它們是被「另一個拼法」壓掉的。

代價：只差 NFC／NFD 的壓住不會列在 `suppressed`。這是有記錄的（`VenueResolverSuppressedTests.testCanonicallyEqualSpellingIsNotANarrowing` 釘住）。若使用者要位元組層，要改的是 `resolve` 的輸入（`rejectedPairings(venues:)` 的回傳型別），不是這一段。

## 沒有做的

- **不改抑制語意**：`candidates`／`ambiguities` 與改動前逐位元相同（`testReportingDoesNotChangeWhatIsSuppressed`、M3 負對照）。
- **不新增撤回面**：「撤回對某個拼法的 reject」仍然沒有工具面（verdict 沒有移除面）；這一段只是讓你看得到是誰壓住了誰。
- **`zero-instance-guards` 不加列**：這是列表欄位不是守衛——沒有東西被擋下，也沒有資料被判定。
- **resolve-people／resolve-organizations 不動**：issue 只問 venue。兩者的否決抑制同樣以 `matchingKey` 為鍵（person 側 R1-fix I1、organization 側 #647 R3），但它們的列表在同一情境（對一個拼法 reject、另一個拼法被壓）是否也沉默，這次**沒有檢查**；若沉默，是各自的 issue。

## 實作

| 檔 | 改了什麼 |
|---|---|
| `Sources/AkashicEntity/VenueResolver.swift` | 新型別 `VenueSuppressedCandidate`；`VenueResolutionReport` 多 `suppressed`；否決表改成值帶原 literal |
| `Sources/AkashicMCPKit/AkashicService.swift` | `resolveVenues` 多 `suppressedLimit` 參數（預設＝MCP 的上限，負數在任何寫入之前拒絕）；列表腿合併 `suppressedPayload`；`suppressedItemsCap`／`suppressedLiteralsPerRow` |
| `Sources/akashic/VenueCommand.swift` | CLI 傳 `suppressedLimit: nil`；`--help` 寫契約 |
| `Sources/akashic-mcp/Server.swift` | `akashic_resolve_venues` 的說明多一段，點名三個新鍵與每列的鍵（#672 守衛要求每個回應鍵出現在說明裡）；位元組見下 |
| `.claude/rules/mcp-cli-parity.md` | `akashic_resolve_venues` 列加「#712 重新確認，裁決不變、契約有改」 |
| `plugin/CHANGELOG.md` | MCP 回應多三個鍵 |

## 測試

| 測試 | 驗什麼 |
|---|---|
| `VenueResolverSuppressedTests`（7，純函數） | 另一個拼法被報、附壓住它的拼法；逐字相等不報；同一配對兩個拼法被否決時逐字相等者仍是普通已否決；NFC／NFD 不是收窄；否決是 per-work per-venue；歧義不被抑制故不報；報告不改變 `candidates`／`ambiguities` |
| `VenueSuppressedByNormalizationTests`（7，服務層） | 否決前後的列表（`suppressed` 空陣列＋`suppressedTotal` 0 → 1 列）；逐字否決不報；別的 work 的否決不波及；`--demote` 同樣壓住並同樣被報；MCP 面截 20 筆而 `suppressedTotal` 是全數、CLI（`suppressedLimit: nil`）全列；負上限拒絕；位元組預算吃不下的整列不印、`rejectedLiterals` 超過 5 個時帶 `rejectedLiteralsTotal` |
| `ResolveVenuesSuppressedCLITests`（4，真 binary） | `akashic resolve-venues` 列表帶這三個鍵與每列內容；沒有候選被壓時是 0；CLI 全列 25 筆而同一份 store 走服務預設被截 20 筆（證明 CLI 傳了 `nil`）；`--help` 寫了契約 |
| `ToolPayloadKeyGuardTests`（既有） | `suppressed`／`suppressedTotal` 出現在工具說明裡（既有的 `list` 情境永遠回這三個鍵，不需新增情境） |

## `tools/list` 位元組

量法同 `StdioE2ETests.testToolsListResponseStaysWithinByteBudget`（真 binary、`tools/list` 回應一行，不含換行）：

| | bytes | 說明 |
|---|---|---|
| 本分支起點（99ffcc0d） | 54,235 | 超過當時的預算 54,000，該測試在起點就是紅的——與本 change 無關 |
| 起點 ＋ d2ab548b（`akashic_import_zotero` 縮短，另一個工作線的 commit，cherry-pick 進來） | 53,939 | 本 change 的「前」 |
| 本 change 之後（`akashic_resolve_venues` 說明只加了新鍵那一段） | **54,515**（+576） | 預算已由使用者 2026-10-01 晚調到 60,000（fbf4a2f6，#578／#713 另案），餘 5,485 |

**中途有過一版為了守住 54,000 而縮短 `akashic_resolve_venues` 說明的做法**（淨 −143、53,796）：把拒絕類別的枚舉、「原因見 akashic validate」、各腿回報鍵的括號補充移回 CLI `--help`。預算調高後撤掉了——只講 MCP 的 client 執行不了 CLI，那些細節是它讀不到的契約（#578 的裁決理由，#713 是結構性的解法）。最終的 diff 對 Server.swift 只有新鍵的那一段：`suppressed`／`suppressedTotal`／`truncated` 與每列的鍵（#672 守衛要求每個回應鍵出現在說明裡）；既有的文字與各參數說明不動。

## 負對照

（M1–M8 跑在縮短說明的那一版上；預算調高、說明還原之後只有 M9 受 Server.swift 影響，M9 在最終版重跑過，結果相同：1 failure。）

每個 mutant 改一處、重編（含兩個 executable）、跑下面三個 test class（M9 跑 `ToolPayloadKeyGuardTests/testEveryPayloadKeyIsDescribedOrExempt`），再以反向編輯還原並以 `cmp` 對事先存下的副本確認逐位元組相同。三個 class 共 18 個測試（M9 是 1 個）。數字是 XCTest 的 failures：

| mutant | 結果 |
|---|---|
| M1 報告從不附加 `suppressed` | 21 failures，9 個測試紅 |
| M2 逐字相等的否決也報 | 21 failures，12 個測試紅 |
| M3 抑制被改（被壓住的候選仍列在 `candidates`）| 11 failures，11 個測試紅（證明報告不是靠改變抑制得來） |
| M4 CLI 忘了傳 `suppressedLimit: nil` | 2 failures，1 個測試紅（`testCLIListsEveryRowWhileTheServiceDefaultIsCapped`：只有真 binary 抓得到那一行轉送） |
| M5 `suppressedTotal` 數的是顯示的列數而不是全數 | 2 failures，2 個測試紅 |
| M6 位元組預算不生效 | 3 failures，1 個測試紅（`testByteBudgetDropsRowsThatDoNotFitAndSaysSo`） |
| M7 `rejectedLiterals` 恆為空 | 5 failures，5 個測試紅 |
| M8 `truncated` 恆為 false | 3 failures，3 個測試紅 |
| M9 回應鍵改名而說明沒改（`suppressedTotal` → `suppressedCount`） | 1 failure，`ToolPayloadKeyGuardTests` 紅（#672 守衛，鍵不在工具說明裡） |

M9 的第一版只是把說明裡的**一處**「suppressedTotal」拿掉，守衛仍綠——說明裡有兩處提到這個鍵，拿掉一處不算沒說明；那個 mutant 量不到任何東西，改成上面的「改名」才是守衛該抓的情境。

## 驗證（最終版）

`swift build --build-system native -Xswiftc -warnings-as-errors` 乾淨；完整 `swift test`：4719 個測試、1 個跳過、0 failures；`bash .githooks/run-guards.sh` rc=0。
