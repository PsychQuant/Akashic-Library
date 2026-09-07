## 1. statement 文法由 SplitRecordValue.parse 單一解析

- [x] 1.1 [P] （spec: The split statement grammar SHALL have exactly one parser）新增 `Sources/AkashicCore/SplitRecordValue.swift`：`parts`／`reason`、`parse(_:)`（`拆為 ⟦a⟧ ⟦b⟧…：理由`，段 ≥2、理由非空、括號平衡）、`encoded`；段含 `⟦`／`⟧` 拒絕。驗證：`Tests/AkashicKitTests/SplitRecordReferenceTests.swift` 的 `testSplitRecordValueRoundTripsVerbatim`、`testSplitRecordValueRejectsMalformed`（表格四案）。

## 2. 拆分記錄住 work 側的 references，作為第 15 條邊值域的顯式擴充

- [x] 2.1 （spec: A work record SHALL be able to carry a split record for a retired author literal）`Sources/AkashicCore/Provenance.swift` 的 `Entry.validateReferenceAttachment` 收 `field: authors`：value 非空、kind 為 judgement、statement 經 `SplitRecordValue.parse` 成功；其他 field 照舊拒絕且訊息列四個合法 field。驗證：`SplitRecordReferenceTests.testAuthorsReferenceDecodes`、`testUnknownFieldStillRejectedAndMessageListsFour`。
- [x] 2.2 [P] （design: 各段至少一段仍在是它的一致性條件；spec: The split record refers to a retired value and SHALL be validated by presence of its parts, not of its value）`authors` 的 reference **不**要求 value 在作者位內（decode 期只驗形狀）；「至少一段仍在」放進 `StoreHealth`（各段全不在 → warning，記錄仍載入）。驗證：`testRetiredValueIsAcceptedOnLoad`、`OrphanedSplitVerdictScanTests.testAllPartsGoneIsAWarningNotARejection`。
- [x] 2.3 [P] （design: rests-on 空值例外用第二個具名集合 firstOrderRulingFields；spec: An empty rests-on SHALL be admissible for first-order rulings through a second named set）`ProvenanceReference.firstOrderRulingFields = resolutionVerdictFields ∪ {"authors"}`，空 rests-on 放行改查它；`resolutionVerdictFields` 不動，`ResolutionLedger.verdicts`、死 verdict 掃描、demote 對 `authors` reference 不解析。驗證：`testEmptyRestsOnAcceptedForAuthors`、`testResolutionParsersIgnoreSplitRecords`（ledger 與死 verdict 掃描各斷言零 verdict；demote 沒有可獨立呼叫的 seam，以源碼掃描釘住它走 ledger）。

## 3. store format bump 16 與寫入閘

- [x] 3.1 （spec: The split record SHALL be governed by store format 16）`Sources/AkashicStoreIO/StoreVersion.swift` 的 `supported` 升 16；`Sources/AkashicStoreIO/LibraryStore.swift` 的 `assertEntryWritable` 對帶 `authors` reference 的 entry 加 ≥16 閘、訊息指名 16；`docs/store-format.md` 記 16；`plugin/.claude-plugin/plugin.json` 與 `mcpb/manifest.json` 的宣告同步（`plugin-store-format-parity` 認的兩份；README 摘要表也要一列，`FormatDocSyncTests` 釘）。驗證：`SplitRecordReferenceTests.testFormat15StoreRefusesSplitRecord`、`testFormat16StoreAcceptsSplitRecord`；`bash .githooks/run-guards.sh` 的 `plugin-store-format-parity` 報「2 份宣告與 StoreVersion.supported 一致（format 16）」。

## 4. splitAuthors 寫記錄

- [x] 4.1 （spec: A work record SHALL be able to carry a split record for a retired author literal——Splitting a glued literal writes the record alongside the new positions）`Sources/AkashicMCPKit/AkashicService.swift` 的 `splitAuthors`：在改寫 `authors` 的同一次 `writeEntry` append `{field: authors, value: 原 literal, judgement: SplitRecordValue(parts:reason:).encoded, restsOn: []}`；段含 `⟦⟧` 拒絕；報告加 `recorded: true`。驗證：`Tests/AkashicMCPTests/SplitAuthorTests.swift`（新檔；既有 #443 split 測試在 `VenueServiceTests`） `testSplitWritesTheRecordVerbatim`（spec 的 `chen2020a` 例：value 逐字、statement 逐字）、`testPartWithReservedBracketIsRefused`。

## 5. 孤兒 verdict 偵測進 perRecordIssues

- [x] 5.1 （spec: A verdict whose literal has been retired by a split SHALL be reported as an orphan）`Sources/AkashicStoreIO/StoreHealth.swift`：`orphanedSplitVerdictPrefix`／`orphanedSplitVerdicts`；`LibraryStore.orphanedSplitVerdictIssues(in:)` 掃 person／organization 的 resolution verdict，以 (citekey, literal) 對照全庫拆分記錄，warning 指名那筆 work；另一種 warning「拆分記錄的各段都已不在作者位」同前綴族；`health(from:)` append。驗證：`Tests/AkashicKitTests/OrphanedSplitVerdictScanTests.swift` 的 `testRejectedLiteralLaterSplitIsAnOrphan`、`testSameLiteralOnDifferentWorkIsNotAnOrphan`、`testCleanStoreReportsNothing`、`testHealthActuallyCallsTheScan`（拿掉 append 即紅）。
- [x] 5.2 [P] 兩面計數：`AkashicService.doctor()` 的 `recordIssues` 加 `orphanedSplitVerdicts` 計數；`Sources/akashic/Commands.swift` 的 `validate` 加計數行。驗證：`OrphanedSplitVerdictScanTests.testBothFacesMentionOrphanedSplitVerdicts`（源碼掃描，#453 的同一形）。
- [x] 5.3 [P] `.claude/rules/zero-instance-guards.md` 加一列（✅ 寫；零的來源是「記錄還沒開始寫」——4 筆已拆記錄沒有拆分記錄——要釘住）；表頭列數同步；表下方附重跑指令。驗證：`bash .githooks/run-guards.sh` 的 `zero-instance-rows-audit` 讀到新列數且找得到實作（#450 在 Sources/）。

## 6. 規則與文件、Interface depth check

- [x] 6.1 [P] `.claude/rules/mcp-cli-parity.md` split-author 段：把「store 不留原文與理由是本面的誠實邊界」改為自本 change 起不成立、指向拆分記錄；`.claude/rules/entity-backlink-completeness.md` 第 15 條邊的值域描述加 `authors`；`.claude/rules/literal-first-then-key.md` 的 #451 節「目前只能散文並讀」改為可由拆分記錄機械標註。驗證：`bash .githooks/run-guards.sh` 全綠（`parity-table-drift`、`backlink-field-ratchet`、`measured-numbers-audit`）。
- [x] 6.2 `changelog/2026-09-XX-split-verdict-historical-reference.md`：六個 decision（值域擴充、各段至少一段仍在、`firstOrderRulingFields`、單一解析器、format 16 與三 binary 部署順序、孤兒偵測）各一段，Interface depth check（seam＝`validateReferenceAttachment`＋`SplitRecordValue.parse`、adapter 恰一個、刪除測試），un-split 另開 issue 的編號。驗證：內容 review 對照 design.md 的每個 `###` 各有一段；`swift build -Xswiftc -warnings-as-errors`＋全套 `swift test` 綠；pre-push 通過。
