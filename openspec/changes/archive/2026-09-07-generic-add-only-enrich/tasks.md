## 1. core 住 AkashicCore、Zotero 版改 adapter

- [x] 1.1 （spec: Add-only enrichment has exactly one policy implementation）新增 `Sources/AkashicCore/AddOnlyEnrichment.swift`：`Proposal`（`citekey`／`doi` 二擇一、`fields`、`date?`、`authors`、`sourceDigest?`）、`Result`／`Item`（`category` 封閉五值 `added`／`skipped`／`ambiguous`／`notFound`／`rejected`，`matches`、`additions`）、`plan(entries:proposals:includeAbsentAuthors:)`。欄位政策**逐字**自 `ZoteroEnrichment.plan` 搬入（只補 nil 鍵、`issn` 拒、`doi`／`pmid`／`isbn` 走結構化欄位並保留殘留、`date` 空才補、`authors` 空且旗標開才補 literal、`type`／`title`／`venues`／`attachments` 不動）。驗證：`Tests/AkashicKitTests/AddOnlyEnrichmentTests.swift` 先寫 RED——既有鍵不動（`testExistingKeyIsNeverOverwritten`）、`issn` 拒（`testISSNIsRejected`）、doi 走結構化欄位且殘留保留（`testIdentifierGoesToStructuredFieldWithResidue`）——再 GREEN。
- [x] 1.2 （spec: Add-only enrichment has exactly one policy implementation——Zotero adapter is behaviourally equivalent）`Sources/AkashicZoteroImport/ZoteroEnrichment.swift` 改 adapter：找 item → 以既有 probe 產 `Proposal` → 委派 `AddOnlyEnrichment.plan`；刪掉自己的政策分支。驗證：`Tests/AkashicKitTests/ZoteroEnrichmentTests.swift` 22 支（#340 時 12 支，其後隨 #394 各輪成長；測的是「零改動綠」不是支數）**零改動**綠（`swift test --filter ZoteroEnrichmentTests`），且 `grep -c` 政策關鍵字（`issn`、`includeAbsentAuthors`）在 `ZoteroEnrichment.swift` 只剩委派處。

## 2. Proposal 以 citekey 或 DOI 定位，DOI 命中多筆為 ambiguous

- [x] 2.1 [P] （spec: Proposals locate a work by citekey or DOI）DOI 定位：以 `DOI` 型別正規形比對 `Entry.doi`；命中 1 → 對回 citekey；≥2 → `ambiguous` 並在 `matches` 列全部 citekey、零寫入；0 → `notFound`。驗證：`AddOnlyEnrichmentTests` 的 `testDOIMatchingTwoEntriesIsAmbiguousAndWritesNothing`（含 `10.1037/x` vs `10.1037//x` 雙斜線正規形案）、`testDOIMatchingOneEntryResolvesCitekey`、`testUnknownDOIIsNotFound`。
- [x] 2.2 [P] （spec: Proposals locate a work by citekey or DOI——both keys given is an input error）輸入語法錯整批拒絕：兩鍵同給、兩鍵皆無、`fields` 空且無 `date`／`authors`、`FieldKey.normalized` 回 nil 的鍵 → throw 指名第 N 筆、零寫入。驗證：`testBothKeysRejectWholeBatch`、`testEmptyProposalRejectsWholeBatch`、`testUnnormalizableKeyRejectsWholeBatch`。

## 3. 雙摘要分鍵，core 不猜鍵名

- [x] 3.1 [P] （spec: Two abstracts are stored under two keys）`fields` 同時含 `abstract` 與 `abstract-<lang>`／`abstract-2` 時各自落地為 `abstract`／`abstract_<lang>`／`abstract_2`（經 `FieldKey.normalized`），不拼接、不自動編號；既有 `abstract` 在時只補第二個並報第一個 `skipped`。驗證：`testTwoAbstractsLandUnderTwoKeys`（`abstract`＋`abstract-es` → `abstract`＋`abstract_es`）、`testSecondAbstractOnlyWhenFirstExists`。

## 4. 兩面契約沿 akashic_enrich_from_zotero 那列

- [x] 4.1 （spec: Dry run is the default and apply is gated on the CLI only）`Sources/AkashicMCPKit/AkashicService.swift` 新增 `enrich(proposals:dryRun:includeAbsentAuthors:) throws -> String`：一次 `load`、逐筆對可寫的 item `writeEntry`、I/O 失敗逐筆收容進 `writeFailures`、一次 `rebuild`；`dryRun` 時零寫入。驗證：`Tests/AkashicMCPTests/EnrichServiceTests.swift`——`testDryRunWritesNothing`、`testApplyWritesAndRebuildsOnce`、`testWriteFailureIsCapturedAndOthersProceed`。
- [x] 4.2 [P] `Sources/akashic-mcp/Server.swift` 註冊 `akashic_enrich`（`proposals` object 陣列、`dry_run` 預設 true、`include_absent_authors` 預設 false）→ 呼叫 4.1；不設 #298 閘（逐筆顯式指名）。驗證：`Tests/AkashicMCPTests/EnrichServiceTests.swift` 的 `testMCPToolDefaultsToDryRun`（stdio 驅動 `akashic-mcp` 或 service 層等價）；`grep -oE 'Tool\(name: "akashic_[a-z_]+"'` 數到 31。
- [x] 4.3 [P] （spec: Dry run is the default and apply is gated on the CLI only——CLI dry run writes nothing）`Sources/akashic/EnrichCommand.swift`（註冊進 `Sources/akashic/CLI.swift`）：`akashic enrich --from <file.json> [--apply] [--include-absent-authors] [--json]`；`--from` 讀 `[Proposal]` JSON；乾跑預設；`--apply` 走 `Sources/akashic/DestructiveTargetGate.swift`（加 `enrich` 一列）；`--json` 原樣轉印 service payload、人可讀逐筆印分類與 additions。驗證：`Tests/AkashicCLITests/EnrichCLITests.swift`——`testDryRunPrintsReportAndWritesNothing`、`testApplyWithoutTargetHitsGate`、`testJSONIsServiceResponseVerbatim`；`Tests/AkashicCLITests/PersonCLITests.swift` 的 service 建構計數 +1（#503 的既有形狀，改數字時在註解記本 change）。
- [x] 4.4 `.claude/rules/mcp-cli-parity.md` MCP 表加一列（`akashic_enrich` ↔ `enrich`，契約差異同 `akashic_enrich_from_zotero`：CLI `--apply` 走 #298 閘、MCP `dry_run` 不設閘）；`.claude/rules/two-kinds-of-edits.md` 裁決史加一列（generic enrich：程式編輯，只補不存在的鍵、來源給什麼收什麼、不判定）。驗證：`bash .githooks/run-guards.sh` 全綠（`parity-table-drift` 認得新列）。

## 5. 摘要來源只進報告不進 store

- [x] 5.1 [P] （spec: Source digests are reported, never stored on the work）`Proposal.sourceDigest` 在 `Item` 逐筆回顯（CLI 與 MCP 報告都印），寫入時**不**進 `Entry.references`。驗證：`AddOnlyEnrichmentTests.testSourceDigestIsReportedNotStored`——apply 後 `entry.references` 與 apply 前逐位元組相同、報告 item 帶該 digest。

## 6. 收尾

- [x] 6.1 `changelog/2026-09-XX-generic-add-only-enrich.md`：一份政策、adapter 化、DOI ambiguous、雙摘要分鍵、兩面契約、來源不進 store、Interface depth check（seam＝`AddOnlyEnrichment`、adapter 恰一個、刪除測試）、與 #450／#449／#455 的關係；`swift build -Xswiftc -warnings-as-errors`＋全套 `swift test` 綠。驗證：changelog 內容 review 對照 design.md 的六個 `###` decision 各有一段；pre-push 全套通過。
