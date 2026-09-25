## Context

change `resolution-verdict-states`（#619、#636）加了第三個 verdict 欄位 `resolution-undecided`：查過、判不出來，可以帶 rests-on；它不抑制提名，不構成矛盾，配對判定之後保留為查證歷史。寫入面只開在 resolve-people 與 resolve-venues（`UndecidedVerdicts.swift` 的 `recordUndecidedAuthorships`／`recordUndecidedVenues`）。

store 層對 org 已經通用：
- `ResolutionLedger.record(undecided:holderKind:holder:literal:statement:restsOn:)` 對任何 holder kind 都成立；
- `LibraryStore.assertOrganizationWritable` 走同一道 `assertVerdictShapesWritable`（format ≥ 19）；
- `ResolutionLedger.undecidedChecks(in:holderKind:holder:literal:judgedKey:)` 對 org 的 references 可以直接用；
- CLI 的 org 計數行已經是四態：共用 `countsCore`，未決不另開 rule 桶。

org 族與 people／venues 不同的地方：
- **候選的 holder 有三種**：`OrgResolutionCandidate.Holder` 的 `.person`（affiliation）、`.organization`（parents）、`.work(citekey:authorIndex:)`（團體作者位）。`verdictHolderKind` 已經窮盡這三種。
- **候選 id 帶 literal**：列表的回程把手是 `holderKey::literal`；work holder 是 `citekey[i]::literal`（#378）。literal 是機構名稱，可能含 `=`、`:`、`@`。
- **兩面沒有共用程式**：MCP 走 `AkashicService.resolveOrganizations`（顯式 id）；CLI 的 `ResolveOrganizations` 是篩選式批次（`--apply`／`--reject` ＋ `--holder`／`--org`），自己跑 `OrgResolver.resolve`，不經 service。CLI 列表也不印 rowID。
- **歧義條目**：MCP 列表回的歧義條目只有 holder、literal、orgKeys，沒有 `id`。
- App 沒有 org 裁決台。

使用者 2026-09-25 的裁決（#643）：id 用 `rowID@orgKey=說明`；歧義條目開放，逐個 org 記。

## Goals / Non-Goals

**Goals:**

- resolve-organizations 兩面都有未決腿，契約與 people／venues 的未決腿相同：
  - 整批拒絕、逐筆略過；
  - 完全相同＝`alreadyRecorded`；
  - 三個上限；
  - 單獨呼叫；
  - format ≥ 19。
- 候選列與歧義條目都能被點名，三種 holder 都可以記。
- 揭露：
  - MCP 候選列與歧義條目帶 `undecidedChecks`；
  - CLI 列表逐列印出 rowID，並標出查過未決的次數。
- CLI 篩選式 `--apply` 排除查過未決的候選並另列，與 resolve-people（#624）同形。

**Non-Goals:**

- 沒有任何 org 命中的 literal：它不在列表裡，也沒有被判的 org 可以承載記錄。這是 residue，不在範圍內。
- 撤回未決記錄的寫入面（people／venues 也沒有）。
- App 的 org 裁決台（目前不存在）。
- 改動 org 的 apply／reject 語意。

## Decisions

### 未決 id 是 `<rowID>@<orgKey>=<說明>`，以已知 rowID 試切

rowID 與列表回傳的回程把手逐字相同，呼叫端從列表複製即可。解析步驟如下：

1. 找出字串中每一個符合 `@` ＋ StoreKey（`[a-z0-9][a-z0-9-]*`）＋ `=` 的位置。
2. 對每個位置試切：`@` 之前是 rowID 候選，StoreKey 是 orgKey，`=` 之後是說明。
3. 只收「前綴恰為列表中某一列的 rowID」的切法；列表是**這次呼叫當下**以同一份 load 跑 `OrgResolver.resolve` 得到的候選列與歧義條目。
4. 恰好一個切法成立 → 收下。零個 → 整批拒絕（格式錯，或 rowID 不在列表上）；多個 → 整批拒絕（有歧義，不猜）。

literal 或說明裡出現 `@`、`=`、`:` 都不會被切錯：只有同時對得上已知 rowID 與 StoreKey 的切法才算數。

替代方案：以第一個或最後一個 `=` 切。literal 可能含 `=`，說明也可能含 `=`，兩個方向都會切錯，否決。改用結構化參數（MCP 收 object 陣列、CLI 用分開的旗標）不會切錯，但與 people／venues 的字串形分岔，兩族的契約描述會變成兩份，否決。

### orgKey 必須屬於被點名的那一列

候選列只有一個 org，orgKey 必須等於它；歧義條目有 2+ 個 org，orgKey 必須是其中之一。不屬於那一列就整批拒絕，理由是輸入矛盾：那一列沒有提名這個 org，在那裡記未決等於替沒被提名的配對記查證。

替代方案：接受任何存在的 org。這會讓未決記錄出現在提名器從沒提過的配對上，而 `undecidedChecks` 的揭露只看得到被提名的配對，記下的東西永遠不會被看見。否決。

### 記錄落在被判的 org 上，value 以 holder kind 編碼

value 是 `<kind>:<holderKey> :: <literal>`：
- kind 取自 `Holder.verdictHolderKind`（person、org、work）；
- work holder 的 holderKey 是 citekey，不帶作者位索引（與 org apply／reject 的 verdict 同形，#483）。

同一筆 work 兩個作者位是同一個 literal 時，兩個 rowID 會寫出同一筆記錄。第二個 id 回報為本次寫入，不報成「已在」，與 people 腿 R2 的 `writtenThisCall` 同一個規則：以被判實體加記錄位元組為鍵。

### 程式放在新檔 `OrgUndecidedVerdicts.swift`，共用檢查抽成 helper

people／venues 的 `parseUndecidedSpecs` 綁死三段形 id，不能直接用。以下抽成 `UndecidedVerdicts.swift` 裡的共用 helper，三個腿共用一份：
- 上限；
- format 閘；
- rests-on 驗證；
- 說明空白與位元組上限的檢查。

org 的 id 解析與寫入放新檔。`UndecidedVerdicts.swift` 已經接近 250 行，再加一族會超過本 repo 單檔的慣常大小。

### 已判定的配對逐筆略過；揭露用既有的 `undecidedChecks`

「已判定」的判準：被判 org 對這個正規化配對已持有 confirmed 或 rejected，判斷沿用 `pairingIsDecided`。已判定的配對略過並具名，其餘逐筆略過的類別照 people 腿：
- work 不存在；
- citekey 無法唯一定位（#628）；
- 該位置已不是 literal。

揭露：
- MCP 候選列帶 `undecidedChecks`（整數）。
- MCP 歧義條目帶 `undecidedChecks`（物件，orgKey 對次數，只列非零）。歧義有多個 org，一個整數說不出查的是哪一個。
- 兩種列都新增 `id`。

### CLI 的排除在 CLI 側套用，判準來自同一個 ledger 函式

CLI 的 `ResolveOrganizations` 不經 service；排除用與 service 同一個 `ResolutionLedger.undecidedChecks`，不另寫判準：
- 篩選式 `--apply` 時，查過未決的候選移出套用集，另列並指路 MCP 的逐 id apply；
- 全數被排除時，零寫入並以非零結束（與 resolve-people 的 #624 同形）。

`--reject` 不排除：否決是一個判定，查過未決之後再否決是合法的後續。

替代方案：把 CLI 改成經 service。那會連帶改動 org CLI 的既有輸出與篩選語意，範圍超出本 issue，否決。

## Implementation Contract

- `AkashicService.resolveOrganizations` 新增 `undecided:restsOn:` 參數，組合規則如下：
  - 兩者都沒給 → 既有行為（列表／apply／reject）不變；
  - 給了 `undecided` → 單獨呼叫，與 apply 或 reject 同給即整批拒絕；
  - 給了 `rests_on` 而沒有 `undecided` → 拒絕。
- 整批拒絕、零寫入的條件：
  - 語法錯：沒有任何切法成立，或有多個切法成立；
  - id 重複；
  - 說明空白；
  - org 不存在；
  - orgKey 不屬於被點名的那一列；
  - digest 形狀不合；
  - store format < 19；
  - `rests_on` 沒有伴隨 `undecided`；
  - 超過上限：一次 200 個 id、20 個 digest，或單句說明超過 4,096 位元組。
- 逐筆略過並具名：
  - work 不存在；
  - citekey 無法唯一定位；
  - 位置不是 literal；
  - 配對已判定。
- no-op：完全相同的記錄已在 → `alreadyRecorded`。
- 寫入前每個被改寫的 org 都先過 `assertOrganizationWritable`，全部通過才寫。寫入或 index 重建失敗時，錯誤訊息列出已落地的 org key。
- 回應欄位：
  - `undecided`：逐筆的 id 與 literal；
  - `skipped`：逐筆的 id 與原因；
  - `alreadyRecorded`；
  - `organizationsRewritten`；
  - `restsOn`。
- MCP 列表：候選列與歧義條目帶 `id` 與 `undecidedChecks`；頂層帶 `undecidedTotal`，是有未決記錄的正規化配對數。
- CLI 新增 `--undecided`（可重複）與 `--rests-on`，走 service 的同一個函式。
  - 列表每列印出 rowID；有未決記錄的列標「查過未決 N 次」。
  - `--apply` 排除查過未決的候選，另列並指路以 id 點名的 MCP apply。
- 測試（`Tests/AkashicKitTests/OrgUndecidedLegTests.swift`、`Tests/AkashicCLITests/OrgUndecidedCLITests.swift`）：
  - 三種 holder 各寫一筆；
  - 歧義條目逐 org 記；
  - literal 含 `@` 與 `=` 的 rowID 切對；
  - 兩個切法都成立時拒絕；
  - orgKey 不屬於那一列時拒絕；
  - 已判定的配對略過；
  - format 18 拒絕；
  - CLI 篩選式 `--apply` 排除，全數排除時零寫入、非零結束；
  - 至少兩個負控：拿掉「前綴必須是已知 rowID」、拿掉 CLI 排除，對應的測試都要變紅。

## Risks / Trade-offs

- [rowID 取自呼叫當下的列表，兩次呼叫之間 store 變了，rowID 就可能不在列表上] → 視為語法錯而整批拒絕。訊息寫明「先不帶參數列出候選，取得當下的 id」。與 apply 的既有行為相同：apply 對不在列表上的 id 也是 notFound。
- [列表回傳的 rowID 刻意不消毒（回程把手要逐字），CLI 印出時要消毒] → CLI 印出時用 `displaySafe`。含控制字元的 literal 在 CLI 上複製回來會對不上，要改用 MCP。這一點寫進 CLI 的說明。
- [歧義條目新增 `id` 會改變 MCP 列表的 payload] → additive，既有欄位不動；`mcp-cli-parity` 的 resolve-organizations 列同步重新確認。
