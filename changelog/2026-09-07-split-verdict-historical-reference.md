# split-author 的判定持久化到 work 側：拆分記錄、format 16、孤兒 verdict 偵測（#450，Spectra change `split-verdict-historical-reference`）

`splitAuthors`（#443）把黏著的作者 literal 拆成 N 段，是作者位變更家族裡**唯一不可逆且沒有 store 記錄**的一腿——
同族的 `attributeToOrganizations`、`judgeAuthorships`、`demote` 都留 verdict。必填的理由與原文只進當次報告，un-split 所需
資訊只在 store repo 的 git 歷史；`literal-first-then-key` 的整套論證建立在「誤可逆」上，split 正是它的反例。
#450 的 decision（2026-09-03）：判定持久化到 work 側，作為第 15 條邊值域的顯式擴充。

## 拆分記錄住 work 側的 references，作為第 15 條邊值域的顯式擴充

- `Entry.references` 的合法 `field` 從 `{doi, pmid, isbn}` 加 `authors`：`value`＝被拆掉的原 literal（逐字）、
  `kind: judgement(statement: "拆為 ⟦a⟧ ⟦b⟧：理由", restsOn: [])`。**第一次承載已退役的值**：其他三格附著在當下存在的值
  （D2 以值定位、`identifierListContains` 驗值在場），這一格指向已不在記錄裡的值，所以 `Entry.validateReferenceAttachment`
  對 `authors` 明寫相反的例外——value 非空、kind 為 judgement、statement 經 `SplitRecordValue.parse`；**不**驗 value 在場。
  `default` 分支照舊拒絕其他 field，訊息列四個合法 field。例外只有 `authors`，不得類推。
- 替代方案「另開第 16 條邊」否決：多一條邊要進封閉列舉、多一套序列化，而 `ProvenanceReference` 的三槽已經裝得下。
- `Entry.splitRecords`（Core）是唯一的讀法：`StoreHealth` 掃描、未來 un-split 都經它。

## 各段至少一段仍在是它的一致性條件

- 「至少一段仍是本 work 的作者位」放在 `StoreHealth`（warning `staleSplitRecords`，owner 是 work），不在 decode 期：
  記錄合法，只是證據錨可能失效。「仍在」含已升格的 `.key`——升格不是消失，那一段的原 literal 記在 person 的
  confirmed verdict（`work:<citekey> :: <literal>`）裡（`testPartPresentViaConfirmedKeyIsNotStale` 釘住）。
- 各段全不在 → 一筆 warning 指名 work 與退役 literal，記錄保留供 un-split；`validate` exit 仍 0。

## rests-on 空值例外用第二個具名集合 firstOrderRulingFields

- `ProvenanceReference.firstOrderRulingFields = resolutionVerdictFields ∪ {authors}`，`init` 的空 rests-on 放行改查它
  （#232 D8「一階人為裁決」的一般化：原文逐字保存於 value 就是證據）。
- `resolutionVerdictFields` **不動**：`ResolutionLedger.verdicts`、死 verdict 掃描、`demoteVenues` 三處把它當 verdict 文法
  （`<kind>:<key> :: <literal>`）解析，塞進去會讓它們對拆分記錄解析失敗或誤判。`testResolutionParsersIgnoreSplitRecords`
  對 ledger 與死 verdict 掃描各斷言零 verdict，並以源碼掃描釘住 demote 走 ledger（唯一解析器）。

## statement 文法由 SplitRecordValue.parse 單一解析

- `Sources/AkashicCore/SplitRecordValue.swift`：`拆為 ⟦a⟧ ⟦b⟧…：理由`——段以 `⟦…⟧` 包（段內可含空白與冒號）、
  段數 ≥ 2、全形 `：` 之後為理由、理由非空。`init?` 與 `parse` 同一條規則（段含保留字元 `⟦⟧`、空段、理由空皆 nil），
  所以 `encoded` 的輸出必然解析回相等的值——與 `VerdictPairingValue` 同一條 grammar-in-string 的補救。
  spec 的表格四案逐字進測試；手改檔成一段 → decode 期 quarantine（`testMalformedStatementIsQuarantinedAtDecode`）。
- `splitAuthors` 對含 `⟦`／`⟧` 的段拒絕、整批零寫入（`testPartWithReservedBracketIsRefused`）。

## store format bump 16 與寫入閘、三 binary 部署順序

- `StoreVersion.supported = 16`；`assertEntryWritable` 對帶 `field: authors` reference 的 entry 加 ≥ 16 閘、訊息指名 16；
  `splitAuthors` 在**任何寫入之前**對全部計畫過閘（整批零寫入，`testSplitOnFormat15StoreIsRefusedWithZeroWrites`）。
- **non-additive，理由同 15**：format-15 binary 的 `Entry.validateReferenceAttachment` 沒有 `authors` case → 封閉 default →
  **整檔 quarantine**、rc=0，被拆過的 work 在舊 binary 上整筆消失。
- 三份 format 宣告同步 16（`StoreVersion.supported`、`plugin/.claude-plugin/plugin.json`、`mcpb/manifest.json`；
  `plugin-store-format-parity` 守衛認）；`docs/store-format.md` 與 README 各加 format 16 一列；`Format13GateTests`／
  `KnownLayerEvolutionTests` 的棘輪改名為 `…Sixteen`（函式名帶數字是刻意的）。
- **部署順序**（`format-bump-breaks-three-binaries`）：merge → release CLI／akashic-mcp／App 三 binary（只升一個仍整份拒讀）
  → 三者都到位後手動 `store.yaml` 的 `format: 16` → `akashic validate`；**marker bump 前不 push store repo**。
  無資料遷移；#443 已拆的 4 筆（store `32916ba`）不回填（原文與理由只在 git 歷史）。回滾：revert PR 並把 marker 退回 15——
  若已有拆分記錄寫入，format-15 binary 會 quarantine 那些 entry（可預期、可見），這是不回滾 marker 的理由。

## splitAuthors 寫記錄

- 在改寫 `authors` 的**同一次** `writeEntry` append 拆分記錄（同一份 entry、同一次寫入 ⇒ 永遠不會沒有記錄、也不會記兩次）；
  報告每列加 `recorded: true`。spec 的 `chen2020a` 例逐字進 `SplitAuthorTests.testSplitWritesTheRecordVerbatim`。
- doc comment 的「誠實邊界：原文與理由只進報告，不進 store」改寫為本 change 的裁決；報告的 `original`／`judgement` 仍是
  消毒顯示形，完整原值在 store 的記錄裡。

## 孤兒 verdict 偵測進 perRecordIssues

- `LibraryStore.orphanedSplitVerdictIssues(in:)`：person／organization 持有的 resolution verdict，其 value 指向
  `work:<citekey> :: <literal>`，而該 work 有一筆拆分記錄的 value 就是那個 literal → warning（`orphanedSplitVerdictPrefix`，
  owner 是持有者，訊息指名 work 與 literal）。**以 (citekey, literal) 為鍵**（`testSameLiteralOnDifferentWorkIsNotAnOrphan`）。
  同一支掃描也產各段全不在的 warning（`staleSplitRecordPrefix`）；`health(from:)` append（`testHealthActuallyCallsTheScan`）。
- 三面計數：MCP `doctor` 的 `recordIssues` 加 `orphanedSplitVerdicts`／`staleSplitRecords`；CLI `validate` 加兩行計數
  （`testBothFacesMentionOrphanedSplitVerdicts` 源碼掃描，#453 的同一形）；App 側欄「記錄」Section 加兩列（見誠實邊界）。
- `zero-instance-guards` 第 17 列（✅ 寫）：零的來源是**寫入面剛長出來**——形狀已經發生過 4 次、只是沒被記下；
  live store 2026-09-07 實測拆分記錄 0 筆、含「雷庚玲」的檔 4 個。severity warning（處置是人的重新消歧）。

## Interface depth check

seam＝`Entry.validateReferenceAttachment`（`authors` 例外）＋`SplitRecordValue.parse`；adapter 恰一個（`splitAuthors` 寫；
doctor 與未來 un-split 讀）；深度＝「已退役值的 reference」這個新語意；刪除測試：刪掉它，split 回到不可逆且不可偵測——不是 pass-through。

## 規則與文件

- `mcp-cli-parity` split-author 段：「store 不留原文與理由是本面的誠實邊界」劃掉、指向拆分記錄；
  `entity-backlink-completeness` 第 15 條邊值域加 `authors`（並明寫語意相反、例外只此一格）；
  `literal-first-then-key` #451 節「目前只能散文並讀」劃掉、改為可由 `Entry.splitRecords` 機械標註（第 5 筆起）。
- `bash .githooks/run-guards.sh` 全綠：parity 表 MCP 31｜CLI 46｜橫切 2、zero-instance 表 17 列、
  2 份宣告與 `StoreVersion.supported` 一致（format 16）、標題宣稱列數 3 處相符。

## un-split 另開 issue

**#513**：把拆分記錄合回原 literal 的操作面（輸入定位形狀、同 value 多筆記錄是否合法、留痕 vs 乾淨、任一段已升格即拒——
那是 demote 一族）。本 change 只保證 un-split 所需資訊在 store 內。

## 量測（2026-09-07）

- 新測試：`SplitRecordReferenceTests` 10、`OrphanedSplitVerdictScanTests` 7、`SplitAuthorTests` 4、
  `RecordIssuesSummaryTests` +1；既有 split 測試（`VenueServiceTests`）12 支零改動綠。
- `swift build -Xswiftc -warnings-as-errors` 綠；全套 `swift test` **2,379 支、0 失敗、1 skipped**（228 秒，2026-09-07 本機，branch `idd/450-split-verdict-historical-reference` off `8f9159d`——不含 #458 那 29 支）；三支 format 棘輪（`testSupportedFormatIsFifteen`／`testCurrentSupportedFormatIsExactlyFifteen`／README 缺列）在第一輪紅、改成 16 後綠。

## 誠實邊界

- 拆分記錄的 `value` 不驗在場，所以一筆**捏造**的拆分記錄（value 從未是作者位）decode 期擋不住——它會落在
  `staleSplitRecords`（各段全不在）或安靜通過（各段碰巧在）。守的是「拆分留痕」，不是「拆分記錄不可偽造」；
  偽造要靠 store repo 的 git 歷史抓。
- warning 級的 `validate` 對兩種掃描 exit 仍 0——「掃得到」不「叫醒」（#464 的同一條界線）。
- **App 面是 design 的 Out，但本 change 還是補了兩個計數**：design 寫 App 面 Out 時（2026-09-04）App 還完全不渲染
  `perRecordIssues`；#487（PR #512）在本 change 實作期間 merge 進 main，App 側欄「記錄」Section 自此逐族列計數。
  三面之中只有 App 少這兩族，正是 #453 那條「一面有計數另一面沒有」的分岔——所以 `RecordIssuesSummary` 加
  `orphanedSplitVerdicts`／`staleSplitRecords` 兩欄、`RecordIssuesSection` 加兩列（`testOrphanedSplitVerdictReachesTheAppSummary`
  釘住）。這是 base 移動帶來的整合，不是重新裁決 scope；archived artifacts 沒有跟著改（archive 目錄受保護）。
- design／tasks 把既有 split 測試寫成 `Tests/AkashicMCPTests/SplitAuthorTests.swift`（既有），實際既有測試在
  `VenueServiceTests`；本 change 以那個檔名新建了本輪的三支測試，artifact 的「既有」二字不準確。
