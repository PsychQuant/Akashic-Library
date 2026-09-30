## Why

名字分類的判定面（person 的 `authorize-names`、venue 的 `--add-variant`／`--authorize`／`--unauthorize`、organization 的 `--authorize`，共五個面）都是判定型寫入（`two-kinds-of-edits` 的 AI 欄），卻都不留判定記錄：寫了什麼、為什麼、依據什麼，在 store 裡查不到。對既有 authorized 說「確認」更是零寫入零記錄。後果落在合併端：`DivergenceResolve.authorizedDemotedByMerging` 分不出「人確認過的對外形」與 bootstrap 的機械值，只能一律提醒不擋。使用者 2026-10-01 裁決（#564）：名字分類的判定面一律留 judgement 記錄，含確認既有值；代價是升 store format。

## What Changes

- 新增名字分類的判定記錄：`references` 裡一筆 `field: authorized` 或 `field: variant` 的 judgement，value 是名字，statement 是 `指定：理由`／`確認：理由`／`撤回：理由`（封閉三值，單一解析器），證據 digest 可空。
- 五個面（person `authorize-names`；venue `update-venue --add-variant`／`--authorize`／`--unauthorize` 與 MCP `akashic_update_venue` 的同名參數；organization `update-organization --authorize` 與 MCP `akashic_update_organization` 的 `authorize`）每次指定、確認、撤回（venue）、標異寫都寫一筆記錄；同書寫系統替換時被換下的名字、被抬出 variant 的名字，也各寫一筆撤回。**BREAKING**：這些面自此必附理由（venue 沿用 `judgement`／`--judgement`；organization 的 `authorize` 新增 `judgement`／`rests_on`；`authorize-names --apply` 新增 `--judgement`），缺理由整個呼叫拒絕、零寫入。organization 沒有撤回腿：`update-organization --unauthorize` 與 MCP `unauthorize` 於 #557 R1 verify 之後拿掉（使用者對 #557 只說「先提供 --authorize」，撤回腿未經裁決，待使用者裁決），所以五個面裡 organization 只有 `--authorize`。
- 對既有 authorized／variant 再說一次指定，寫一筆「確認」（先前是無聲的 no-op）；與既有記錄位元組完全相同的不重寫。
- 記錄錨定在 `names`，不在分割：撤回之後名字離開 authorized，記錄照樣載入，判定史保留。
- **BREAKING**：store format 21 → 22。寫入名字分類記錄要求 format ≥ 22，否則具名拒絕；舊 binary 讀到這種記錄會整檔 quarantine。部署順序：三個 binary（CLI、`akashic-mcp`、App）全部升級之後，由使用者手動把 store marker 升到 22。
- venue 合併：被併者的 authorized 若會被降級、而它帶有名字分類記錄，改為拒絕合併（preview 與實跑都拒）並指路；機械值維持提醒。其餘被併者的名字分類記錄，在合併後分類一致時隨合併搬到倖存者，不一致時照「會遺失」拒絕。
- 名字分類記錄只由名字分類面寫：`update-person` 的 `references` 不收、venue 的 `--remove-reference` 不刪；`authorize`／`unauthorize` 換下或撤回名字時不再被這種記錄擋住（它們不是孤兒）。
- `authorize-names --apply` 不再把 store marker 寫成 `supported`（在 format 22 之下它會安靜地替使用者升 marker）。

## Non-Goals

見 design.md 的 Goals / Non-Goals。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `authorized-name`: 名字分類的判定必留記錄、記錄的形狀與錨定、format 22 的寫入閘
- `venue-entity`: venue 的 `variant` 分割的判定記錄與 venue 名字分類面的理由要求
- `organization-entity`: organization `authorize` 腿的理由要求與記錄（organization 沒有撤回腿）
- `divergence-record`: venue 合併對帶判定記錄的 authorized 降級改為拒絕、名字分類記錄的搬移規則

## Impact

- Affected specs: authorized-name, venue-entity, organization-entity, divergence-record
- Affected code:
  - New: Sources/AkashicCore/NameClassificationRecord.swift, Tests/AkashicKitTests/NameClassificationRecordTests.swift, Tests/AkashicMCPTests/NameClassificationJudgementTests.swift, Tests/AkashicKitTests/NameClassificationMergeTests.swift, changelog/2026-10-01-name-classification-judgement.md
  - Modified: Sources/AkashicCore/Provenance.swift, Sources/AkashicCore/Venue.swift, Sources/AkashicCore/VenueNameRepair.swift, Sources/AkashicStoreIO/StoreVersion.swift, Sources/AkashicStoreIO/LibraryStore.swift, Sources/AkashicStoreIO/DivergenceResolve.swift, Sources/AkashicStoreIO/AuthorizedNameMigration.swift, Sources/AkashicMCPKit/AuthorizedDesignation.swift, Sources/AkashicMCPKit/AkashicService.swift, Sources/AkashicMCPKit/OrganizationUpdate.swift, Sources/AkashicMCPKit/UpdatePerson.swift, Sources/AkashicMCPKit/VenueReferenceRemoval.swift, Sources/AkashicMCPKit/VenueNameSegmentEdit.swift, Sources/akashic/Commands.swift, Sources/akashic/VenueCommand.swift, Sources/akashic/UpdateOrganizationCommand.swift, Sources/akashic-mcp/Server.swift, plugin/.claude-plugin/plugin.json, mcpb/manifest.json, README.md, docs/store-format.md, plugin/CHANGELOG.md, .claude/rules/two-kinds-of-edits.md, .claude/rules/mcp-cli-parity.md, .claude/rules/zero-instance-guards.md
