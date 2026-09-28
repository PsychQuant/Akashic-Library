# 2026-09-28 venue／organization 的 key 重複時，以 key 定位的寫入面不再猜寫進哪一筆（#670）

#669 讓 venue／organization 的重複 key 成為跨記錄 error：改名與合併（`assertNoCrossRecordErrors`）因此先停，讀取端不再崩潰。另外兩個以 key 定位寫入的面在重複時整批拒絕：attribute-org 與 migrate-identifiers。

其餘寫入面不看跨記錄 error，仍安靜地寫進第一筆（依列舉順序，不是判定）：

- resolve-venues 的 apply／reject／repoint／demote／undecided（verdict 寫進 venue）
- update-venue
- resolve-organizations 的 apply／reject／judge／undecided（verdict 寫進 organization，上級機構那一格的 holder 也是 organization）

2026-09-28 live store 同 kind 重複 key 0 組，零實例。

## 改了什麼

比照 #627／#628／#641 對 citekey 與 person key 的「無法唯一定位」：

- **`unlocatableVenueKeys`／`unlocatableOrganizationKeys`**（`Collection<Venue>`／`Collection<Organization>` 的 accessor，與 `unlocatableCitekeys` 同檔）。只有一類：同 key 兩筆以上。venue 與 organization 只住在 `entities/`、沒有 legacy 殘留，所以沒有 `FileSituation` 那一半。理由字串 `UnlocatableReason.venue`／`.organization`。
- **呼叫端顯式點名的腿整批拒絕、零寫入**：
  - update-venue
  - resolve-venues 的 reject、demote，以及 repoint（兩端任一重複都拒絕：新的一端寫 confirmed、舊的一端寫 rejected）
  - resolve-organizations 的 apply／reject
- **store 狀態不符時逐筆略過的腿，這一類也具名略過**：
  - resolve-venues 的 apply（D33 的既有契約，`skippedUnlocatable`）
  - 三個 resolve 族的 undecided
  - resolve-organizations 的 judge
  - CLI resolve-organizations 的篩選式批次：排除並另列，逐列說出是 work、person 還是 organization 那一格
- **列表**：resolve-venues 的候選列帶 `unlocatableVenueKey`，resolve-organizations 的帶 `unlocatableOrganizationKey`（與既有的 `unlocatableCitekey`／`unlocatablePersonKey` 並列，旗標名說出是哪一格）。
- **resolve-organizations 的「無法唯一定位」改成窮盡 switch**：原本 `.organization` holder 一律回 false（「organization 只住在 entities/」）。那只對 #641 的檔案狀態那一半為真，對重複 key 不成立。CLI 那份原本是兩個 `if case` 加一個預設的 false，同步改寫。
- **index 重建對重複的 venue／person key 留第一筆**（`INSERT OR IGNORE`）：在此之前 PRIMARY KEY 擲錯，而寫入面在檔案落地**之後**才重建 index，所以對同一個 store 裡不相干記錄的一次合法寫入會回報失敗、index 停在舊的。index 是衍生層，留第一筆與 #669 讀取端的處置一致。`doctor` 在有跨記錄 error 時本來就不重建，行為不變。
- `mcp-cli-parity` 的 update_venue、resolve_venues、resolve_organizations 三列加註；`zero-instance-guards` 第 42 列原本把這一格記為「另案 #670」，改成說明已補上。

**MCP 描述**：兩個 resolve 工具的描述在本輪沒有提到新的兩個列表旗標（#578 當時正在精簡那個檔）。#578 合進來時一併補上：resolve_venues 列 `unlocatableVenueKey`、reject／repoint／demote 的拒絕含 venue；resolve_organizations 列 `unlocatableOrganizationKey`。

## 測試

`DuplicateKeyWriteRefusalTests`（兩筆同 key 不同 UUID 的 venue／organization）：

- venue 的候選列有 `unlocatableVenueKey`；apply 以 `skippedUnlocatable` 具名略過、entry 不動；reject、repoint、demote、update-venue 都整批拒絕、零寫入；undecided 具名略過。
- organization 的候選列有 `unlocatableOrganizationKey`；apply、reject 整批拒絕；judge、undecided 具名略過；零寫入。

負控：兩個 accessor 改回空集合，5 支全紅（14 個斷言失敗）；還原後綠。

`testVenueApplySkipsTheCandidateByName` 第一次跑時紅在 index 重建的 `UNIQUE constraint failed: venues.key`，而不是斷言——index 那一項就是這樣找到的。
