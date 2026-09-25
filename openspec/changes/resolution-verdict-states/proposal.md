## Why

「這個 literal 是不是這個 person／venue」這個配對問題，store 目前只寫得下兩種答案：「是」與「不是」。有兩種真實狀態寫不進去：

1. **查過但判不出來（#619）。** #616／#618 依使用者 2026-09-24 的裁決，把判不出來的出口改成讓 literal 留著，查過的來源只寫在報告裡。結果「查過」與「從沒查過」在 store 裡是同一個觀察（`pending`），下一輪要整套重查。#280 的注記仍寫「未判定 → divergence restsOn……這是設計不是缺口」，但對 literal→key 配對，那一格其實沒有載體。
2. **先 apply、後補逐篇判定（#636）。** 同一配對已有一筆以 `--apply` 寫下的 confirmed 時，`--judge` 的判定會被 `appendIfAbsent` 當成重複丟掉。#627 R5 起改成具名略過，但查證理由仍無處可寫。原因是 verdict 以「配對」去重，rule 不參與相等。

使用者 2026-09-25 的三個裁決定了方向：#619 **加一種「未決」載體**；#636 **兩筆並存**；兩者**併進同一份 change**。兩者要改的是同一件事，也就是「一個配對可以持有哪些判定記錄，哪兩筆算同一筆」。

## What Changes

- **verdict 欄位從封閉對擴成封閉三值**：新增 `resolution-undecided`，意思是「查過、判不出來」。value 沿用 `<kind>:<key> :: <literal>` 文法；judgement 型，statement 必填；**允許帶 rests-on**。confirmed／rejected 維持不帶 rests-on（#280 裁決不變）。#232 的「僅此二值，不得類推第三個」以本 change 顯式裁決改寫。
- **verdict 記錄的相等拆成三把具名的鍵，取代單一的 `verdictEqualityKey`**：
  - **配對鍵**：不含 field、不含判定層級。用在 #486 矛盾掃描、狀態推導、退役相反判定。
  - **記錄鍵**：寫入去重、合併收攏、D64 重複掃描都用這把。confirmed／rejected 的記錄鍵是 field ＋ 配對 ＋ **判定層級**，層級只有 `nominated` 與 `judged` 兩值，由 rule 導出。undecided 的記錄鍵是整筆位元組相等。
  - **既有的 `verdictEqualityKey`** 保留原語意，只在需要「同 field 同配對」時使用。

  各使用點逐一指派（變更前量：含註解 35 行、8 個檔，程式行 13 行、5 個檔），不得一刀切換。
- **#636 並存**：同一配對可同時有 `nominated` 與 `judged` 兩筆 confirmed（rejected 同理）。`--judge`／`--refute` 對「已由提名路徑判過同一方向」的配對改為**寫入**判定記錄，不再略過；作者位不動。confirmed-elsewhere 提名的血統依 exact、judged、其餘的順序揭露（R1 verify 更正）。
- **#619 未決**：
  - resolve-people 新增 `--undecided`／`undecided` 腿，resolve-venues 同樣新增。收 `id=查了什麼、為何判不出來`，並可附 `--rests-on`／`rests_on`（sha256 digest）。
  - 同一配對可累積多筆未決記錄。已判定（有 confirmed 或 rejected）的配對寫未決時，該筆具名略過。
- **狀態推導**：配對狀態為 decided > undecided > pending。未決記錄在配對被判定後**保留**，作為查證歷史，不退役、不構成矛盾。
- **四態計數**：`counts{confirmed, rejected, undecided, pending}`。`pending` 不再含查過未決的配對；MCP 另給 `undecidedTotal`。
- **提名與批次**：帶未決記錄的候選列標「查過未決」並揭露次數。CLI 篩選式 `--apply` 排除它們、另列並指向 `--judge`；MCP 逐 id apply 照寫。這個不對稱與 #624 的淘汰而得、tier 閘同型。
- **BREAKING**：store format 18 → 19。舊 binary 讀到 `resolution-undecided` 會 quarantine 整檔，而且舊 binary 的合併會把並存的兩筆 confirmed 收攏成一筆。三個 binary（CLI、akashic-mcp、App）必須同步部署。
- 規則文件同步：`entity-backlink-completeness` 的 #280 注記改寫；`mcp-cli-parity` 的 resolve-people／resolve-venues 列補新腿；`two-kinds-of-edits` 加一列。

## Capabilities

### New Capabilities

- `resolution-verdict-states`: 配對判定的封閉三值（確認、否決、未決），記錄相等的三把鍵與判定層級，並存與累積的語意，狀態推導與四態計數，提名與批次 apply 對未決的處理，以及寫入面與 store format 閘。

### Modified Capabilities

(none)

## Impact

- Affected specs: resolution-verdict-states（新）
- Affected code:
  - New:
    - Sources/AkashicCore/VerdictRecordKey.swift
    - Tests/AkashicKitTests/VerdictRecordKeyTests.swift
    - Tests/AkashicKitTests/UndecidedVerdictTests.swift
    - Tests/AkashicMCPTests/JudgedCoexistenceTests.swift
  - Modified:
    - Sources/AkashicCore/Provenance.swift
    - Sources/AkashicCore/Venue.swift
    - Sources/AkashicEntity/ResolutionLedger.swift
    - Sources/AkashicEntity/PersonResolver.swift
    - Sources/AkashicEntity/VenueResolver.swift
    - Sources/AkashicStoreIO/StoreHealth.swift
    - Sources/AkashicStoreIO/LibraryStore.swift
    - Sources/AkashicStoreIO/DivergenceResolve.swift
    - Sources/AkashicStoreIO/StoreVersion.swift
    - Sources/AkashicMCPKit/AkashicService.swift
    - Sources/AkashicMCPKit/UpdatePerson.swift
    - Sources/akashic/Commands.swift
    - Sources/akashic/VenueCommand.swift
    - Sources/akashic/DivergenceCommands.swift
    - Sources/akashic-mcp/Server.swift
    - docs/store-format.md
    - .claude/rules/entity-backlink-completeness.md
    - .claude/rules/mcp-cli-parity.md
    - .claude/rules/two-kinds-of-edits.md
    - plugin/skills/akashic-disambiguate/SKILL.md
  - Removed: (none)
