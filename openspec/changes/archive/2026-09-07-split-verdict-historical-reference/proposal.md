## Why

`splitAuthors`（#443，PR #448）把一個黏著的作者 literal 拆成 N 個作者位，是作者位變更家族裡**唯一不可逆且沒有 store 記錄**的一腿——同族的 `attributeToOrganizations`、`judgeAuthorships`、`demote`（#418）都留 verdict。必填的 judgement 與原文只進當次報告（消毒顯示形），un-split 所需資訊只在 store repo 的 git 歷史。`literal-first-then-key` 的整套論證建立在「誤可逆」上，而 split 正是它的反例。#450 的 decision（2026-09-03）裁定：split 的判定持久化到 work 側，作為第 15 條邊（`Entry.references`）值域的顯式擴充；並偵測拆分後錨失效的孤兒 verdict。

## What Changes

- **第 15 條邊值域擴充**：`Entry.references` 的合法 `field` 從 `{doi, pmid, isbn}` 加 `authors`。一筆拆分記錄的形狀：`field: authors`、`value` ＝被拆掉的原 literal（逐字）、`kind: judgement(statement: "拆為 ⟦a⟧ ⟦b⟧：<理由>", restsOn: [])`，由 `splitAuthors` 在寫 entry 的同一步 append。
- **驗證規則對 `authors` 明寫例外**（`Entry.validateReferenceAttachment`）：不要求 value 在場（它記的是已退役的值），改要求 statement 各段至少一段仍是該 work 的作者位；全部段都不在時就是本張要偵測的孤兒形。
- **rests-on 空值例外走第二個具名集合** `ProvenanceReference.firstOrderRulingFields`（含 `authors`），不動 `resolutionVerdictFields`——後者被另外三處當 verdict 文法解析。
- **statement 文法單一解析器** `SplitRecordValue.parse`（`拆為 ⟦a⟧ ⟦b⟧：理由`），與 `VerdictPairingValue` 同一條 grammar-in-string 的補救。
- **store format bump 16**：`LibraryStore.assertEntryWritable` 對帶 `authors` reference 的 entry 加 ≥16 閘；`StoreVersion.supported` 升 16；CLI／akashic-mcp／App 三 binary 同步（`format-bump-breaks-three-binaries` 的部署順序）。已拆的 4 筆（store `32916ba`）不回填。
- **孤兒 verdict 偵測**進 `StoreHealth.perRecordIssues`（warning，`orphanedSplitVerdictPrefix`／`orphanedSplitVerdicts` 鏡射 #464／#453 的形）：某 person／organization 持有的 resolution verdict 其 literal 已被某 work 的拆分記錄退役 → 對該持有者報 warning、指名那筆 work。`zero-instance-guards` 加一列。
- `mcp-cli-parity` 的 split-author 段更新誠實邊界（「store 不留原文與理由」自本 change 起不成立）；`entity-backlink-completeness` 第 15 條邊的值域描述更新；`literal-first-then-key` 第 #451 節的「目前只能散文並讀」註記更新為可機械標註。
- un-split 操作面**另開 issue**，本張不做。

## Capabilities

### New Capabilities

- `split-record-reference`: work 側的拆分記錄——第 15 條邊值域加 `authors`、已退役值的 reference 語意（各段至少一段仍在）、`firstOrderRulingFields`、`SplitRecordValue` 單一解析器、format 16 閘、孤兒 verdict 偵測。

### Modified Capabilities

（none）——第 15 條邊（work 的 references）與 resolution verdict 的空 rests-on 例外，其正典要求目前住在尚未 archive 的 change first-class-identifiers 與 resolution-judgement-ledger 的 spec delta 裡，openspec/specs/ 的 entry-source-reference 與 provenance-reference 主檔尚未含它們；本 change 以新 capability 自足地寫下 authors 那一格的全部要求，不對主檔做 MODIFIED delta，兩份主檔的既有要求不變。

## Impact

- Affected specs: `split-record-reference`（新）
- Affected code:
  - New: `Sources/AkashicCore/SplitRecordValue.swift`、`Tests/AkashicKitTests/SplitRecordReferenceTests.swift`、`Tests/AkashicKitTests/OrphanedSplitVerdictScanTests.swift`、`changelog/2026-09-XX-split-verdict-historical-reference.md`
  - Modified: `Sources/AkashicCore/Provenance.swift`（`firstOrderRulingFields`；`Entry.validateReferenceAttachment` 的 `authors` 例外）、`Sources/AkashicStoreIO/StoreVersion.swift`（supported 16）、`Sources/AkashicStoreIO/LibraryStore.swift`（`assertEntryWritable` ≥16 閘）、`Sources/AkashicStoreIO/StoreHealth.swift`（孤兒掃描）、`Sources/AkashicMCPKit/AkashicService.swift`（`splitAuthors` 寫記錄；doctor 計數）、`Sources/akashic/Commands.swift`（validate 計數行）、`.claude/rules/zero-instance-guards.md`、`.claude/rules/mcp-cli-parity.md`、`.claude/rules/entity-backlink-completeness.md`、`.claude/rules/literal-first-then-key.md`、`docs/store-format.md`（format 16）、`plugin/.claude-plugin/plugin.json` 與 `mcpb/manifest.json` 的 format 宣告（`plugin-store-format-parity` 守衛認的那兩份）、`README.md`（format 16 摘要列，`FormatDocSyncTests` 釘）、`Tests/AkashicKitTests/Format13GateTests.swift` 與 `KnownLayerEvolutionTests.swift`（棘輪 15 → 16）、`Tests/AkashicMCPTests/SplitAuthorTests.swift`（新檔；既有 #443 split 測試在 `VenueServiceTests`，零改動）
  - Removed: （none）
- 相鄰：#443（原形）、#451（量測註記等本張）、#394（第 15 條邊）、#232（verdict 文法與 D8）、#418（demote 逐字取回先例）、#464／#453（perRecordIssues 掃描形）。
