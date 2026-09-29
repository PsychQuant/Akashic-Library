# 2026-09-29 只被觀測到的隸屬，讀取面不再說「曾隸屬」（#663）

#661 定下匯出端的立場：只被觀測到的隸屬段（`attested`，沒有 `end`，不是 `ended-unknown`）說不出來，`researcher.status` 是 `undetermined`，不是 `retired`。CLI、MCP、App 三個讀取面沒有跟上，各自寫 `current ?? latestPastSegment`，措辭都是過去式：

- CLI 印「曾隸屬:X（觀測:2021）」；
- MCP 的 resolve-people 歧義條目送 `formerAffiliation` 加 `formerAffiliationAttested`；
- App 裁決台印「曾隸屬:X（觀測:2021）」。

「曾隸屬」是一個離開的斷言，而 `attested` 只是「這幾個時點觀測到成立」——那正是 `Temporal.swift` 警告過的錯誤：把被看到過誤當成離開了。

混合情形更明顯。`latestPastSegment` 的分層規則讓有 `end` 的段勝過觀測段，所以 NTU 2000–2010 加上 2015 年在 ISS 的觀測，三個面只顯示「曾隸屬 NTU（2000–2010）」，2015 年的觀測整個不見；匯出端對同一個人說 `undetermined`。

根因是 `entity-backlink-completeness` 執行細節 2（一個讀取面只能有一條實作路徑）在這裡沒有成立：匯出端的 `researcherStatus` 是 `AkashicExport` 裡的一個內部函式，其他面沒有共用它，所以「同一個人的現況怎麼說」有四份各自維護的推導。

## 改了什麼

**推導收成一份：`TimelineOf.standing`（`Sources/AkashicCore/TimelineStanding.swift`，新檔）。**

回傳三個各自獨立的欄位加一個導出的 `status`：

| 欄位 | 是什麼 | 措辭 |
|---|---|---|
| `current` | 開放的段（沒有 end、不是 ended-unknown、沒有觀測點）中最近的一段 | 隸屬 |
| `lastEnded` | 宣稱已結束的段（有已知 end，或 ended-unknown）中最近的一段 | 曾隸屬 |
| `lastObserved` | 只被觀測到的段中最近的一段 | 觀測到隸屬（不是曾隸屬） |

`status` 不另存，由三個欄位導出：有現職是 `current`；沒有現職但有觀測段是 `undetermined`（混合情形也是，#661 刻意的保守裁決）；其餘是 `retired`；沒有隸屬資料時 `standing` 是 `nil`。匯出端的 `RelationalExport.researcherStatus` 刪除，`researcher.status` 讀 `standing?.status.rawValue`，輸出逐值不變（`RelationalExportTests` 的既有斷言原封不動通過）。

`Temporal.swift` 的 `latestPastSegment` 拆成兩個內部成員 `latestEndedSegment`（層 1–2）與 `latestObservedSegment`（層 3），`latestPastSegment` 仍是 `latestEndedSegment ?? latestObservedSegment`，分層挑選的規則還是一份，既有的 `OrgBootstrapResolveTests`（#236 R3／R4 的十幾條）原封不動通過。新檔放在欄位棘輪掃描的六個型別檔之外，所以 `BacklinkRatchetData` 不必多裁決欄位（新成員是 computed，不序列化，不是關係邊）。

**三個讀取面的措辭：**

| 形狀 | CLI／App | MCP（歧義條目 `people[ref]`） |
|---|---|---|
| 現職 | `隸屬:X` | `currentAffiliation` |
| 只有已結束（有 end 或 ended-unknown） | `曾隸屬:X（1990–1995）`；ended-unknown 是「已結束・時點未知」 | `formerAffiliation` ＋ `formerAffiliationEnd`（ended-unknown 是 `"unknown"`） |
| 只被觀測到 | `觀測到隸屬:X（2011、2014）`（App 只印最近的一個觀測點） | `observedAffiliation` ＋ `observedAffiliationAt`（最近的一個觀測點） |
| 混合 | 兩者都印：`曾隸屬:NTU（2000–2010）  觀測到隸屬:ISS（2015）` | 兩組都送 |

**MCP 的鍵。** 舊鍵 `formerAffiliationAttested` 退場，不沿用；`formerAffiliation` 的意思收窄成「宣稱已結束」——先前它也被送給只被觀測到的人，那是同一個鍵名在改動前後指不同的事，所以寫進 `mcp-cli-parity` 的 `akashic_resolve_people` 那一列（「#663 重新確認」）。讀舊鍵的呼叫端得到缺席，而不是一個換了意思的值。manifest 描述改一句，多 67 bytes（`tools/list` 現為 45,956 bytes，預算 49,000）。

**文件。** `docs/store-format.md` §3 attested 加第 4 條：讀取面與 `status` 讀同一個推導；沒有現職時 `status` 是 `undetermined` 若且唯若讀取面看得到「觀測到隸屬」，不得把後者說成「曾隸屬」。

## 裁決（代裁，使用者可以翻）

1. **措辭是「觀測到隸屬:X（觀測點）」**，沿用既有的 `隸屬:`／`曾隸屬:` 的冒號形式。issue 建議的形式是「觀測到隸屬 X（2021）」，差別只在標點。CLI 印最多四個觀測點（與先前 `rangeLabel` 同），MCP 與 App 只印最近的一個（與先前同）。
2. **混合情形只要有觀測段就顯示它**，即使那個觀測早於另一段的結束。理由：匯出端對所有混合情形一律 `undetermined`（#661），讀取面若只在觀測較晚時才顯示，就會出現匯出說說不出來而讀取面只說「曾隸屬」的人。「`undetermined` ⟺ 看得到觀測段」由 `TimelineStandingTests.testExportStatusIsTheStandingStatus` 與三個面的四種形狀測試守住。
3. **MCP 沒有新增 `status` 鍵。** 措辭本身就帶著它（有 `observedAffiliation` 即 undetermined），多一個鍵只是第二份會分岔的描述。
4. **`latestObservedSegment` 用嚴格的判準**（有觀測點、沒有 end、不是 ended-unknown），與匯出端原本的 `observedOnly` 是同一個。有 end 又帶觀測點是 store 拒收的矛盾組合，仍歸「已結束」那一層。
5. **App 的 `discriminators(for:).affiliation` 仍是單一字串**，混合情形兩段以兩個空格隔開；`discriminatorLine` 對它的截斷上限從 80 放寬到 160，否則混合情形的觀測段會被截掉。
6. **加了一個單一路徑守衛**：`testNoReadSurfaceCallsLatestPastSegmentDirectly` 掃 `Sources/`，除了定義它的兩個檔與欄位棘輪的資料檔，不得有任何檔提到 `latestPastSegment`。第四個讀取面若又寫 `current ?? latestPastSegment`，這裡會紅。

## 測試與負控

新測試：

- `TimelineStandingTests`（10 個）：空、現職、只被觀測到、只有已結束（含 ended-unknown）、混合、現職加觀測段六種形狀的 `standing`；`latestPastSegment == lastEnded ?? lastObserved` 的不變式；匯出 `researcher.status` 與 `standing.status` 逐形狀相等；單一路徑守衛與它的正控（掃描函式真的認得違規）。
- `AffiliationStandingPayloadTests`（MCP，6 個）：五種形狀的鍵集合，以及舊鍵不出現。
- `ResolveAmbiguityCLITests` 加 4 個（走真 binary）、`AdjudicationTests` 加 1 個並加強 1 個。

跑過的 suite：新增的四個、`RelationalExportTests`、`OrgBootstrapResolveTests`，加上 `SanitizationBoundaryTests`、`DisplaySinkCoverageTests`、`PackageManifestTests`、`StoreHealthSurfaceTests`、`WriteGateRulingsTests`、`DestructiveTargetGateTests`、`StdioE2ETests`、`ServiceTests`。全套 `swift test`：4,013 個測試、1 個跳過、0 失敗；`run-guards.sh` rc=0（含 parity 表、欄位棘輪、零實例表對帳）。

負控八組（反向編輯，還原後 `cmp` 確認逐位元組相同）：

1. `status` 永遠不回 `undetermined`：紅（`TimelineStandingTests` 與 `RelationalExportTests`，7 處）。
2. `latestPastSegment` 丟掉觀測層：紅（不變式測試，2 處）。
3. CLI 不印觀測段：紅（4 處）。
4. MCP 不送觀測段：紅（5 處）。
5. MCP 復活舊鍵 `formerAffiliationAttested`：紅（5 處）。
6. App 不印觀測段：紅（5 處）。
7. 在 CLI 原始碼加一行提到 `latestPastSegment`：單一路徑守衛紅。
8. 匯出端改回本地推導（不看觀測段）：紅（3 處）。

## 誠實邊界

- live store 目前沒有任何只被觀測到的隸屬（2026-09-29 唯讀量測：person 4,575 筆，現職 116、只有已結束 46、只被觀測到 0、混合 0），所以這個變更今天不改變任何一個真實輸出；措辭與鍵是替第一筆出現的資料準備的。
- 只處理三個讀取面對隸屬的**顯示**。`akashic person` 的完整時間軸列印、`akashic_person` 的時間軸列，本來就逐段列出每一段與它的時間欄位，沒有「現況」的推導，不在這張的範圍。
- `AkashicApp/`（XcodeGen 專案，不在 `Package.swift` 內）沒有引用被改的成員；本次只編了 `AkashicAppKit`，沒有跑 XcodeGen 專案。
- `formerAffiliation` 收窄語意是一個對 MCP 呼叫端可見的變更。這個 repo 內沒有任何 skill 或 plugin 文件讀這幾個鍵（grep 過 `plugin/`、`plugins/`），但外部消費端讀舊鍵會得到缺席。
