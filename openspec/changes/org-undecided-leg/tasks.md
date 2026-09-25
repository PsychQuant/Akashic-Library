## 1. 共用檢查與解析

- [ ] 1.1 把未決腿共用的檢查抽成 `UndecidedVerdicts.swift` 的 helper：上限（200／20／4,096）、format ≥ 19 閘、rests-on 形狀驗證、說明空白檢查；people 與 venues 兩腿改呼叫它，行為不變。驗證：既有的 `UndecidedServiceTests`、`ResolutionVerdictStatesR1Tests`、`ResolutionVerdictStatesR2Tests`、`UndecidedCLITests` 全數通過（design「程式放在新檔 `OrgUndecidedVerdicts.swift`，共用檢查抽成 helper」）
- [ ] 1.2 新檔 `OrgUndecidedVerdicts.swift` 實作 org 未決 id 的解析：在每個 `@<StoreKey>=` 位置試切，前綴必須等於同一次 `OrgResolver.resolve` 產出的 rowID（候選列或歧義條目），恰一個切法才收；orgKey 必須屬於被點名的那一列。驗證：`OrgUndecidedLegTests` 的 split 表三列（收下、無已知 rowID、兩個切法）、literal 含 `@` 與 `=`、orgKey 不在那一列，全部符合 spec（spec「An undecided id SHALL be split only where the prefix is a known row id」「The named organization SHALL belong to the named row」；design「未決 id 是 `<rowID>@<orgKey>=<說明>`，以已知 rowID 試切」「orgKey 必須屬於被點名的那一列」）

## 2. service 寫入面與列表揭露

- [ ] 2.1 `AkashicService.resolveOrganizations` 新增 `undecided:restsOn:`：單獨呼叫（與 apply／reject 組合整批拒絕、rests_on 無 undecided 拒絕），三種 holder 的 value 以 `verdictHolderKind` 編碼，逐筆略過四類、`alreadyRecorded`、同一次呼叫的第二個相同記錄報成本次寫入（鍵含被判 org）、寫入前逐個 `assertOrganizationWritable`、失敗時列出已落地的 org。驗證：`OrgUndecidedLegTests` 的三種 holder 各一筆、歧義逐 org、已判定略過、format 18 拒絕、組合拒絕（spec「resolve-organizations SHALL provide an explicit undecided leg on both faces」；design「記錄落在被判的 org 上，value 以 holder kind 編碼」「已判定的配對逐筆略過；揭露用既有的 `undecidedChecks`」）
- [ ] 2.2 MCP 列表的候選列與歧義條目帶 `id`；候選列 `undecidedChecks` 為整數、歧義條目為 orgKey 對次數的物件（只列非零），頂層 `undecidedTotal`。驗證：`OrgUndecidedLegTests` 寫入一筆未決後列表對應列的 `undecidedChecks` 為 1、歧義條目的物件只含被記的 org（spec「The listing SHALL disclose undecided checks and give every row an id」）

## 3. 兩面接線

- [ ] 3.1 MCP `akashic_resolve_organizations` 新增 `undecided`／`rests_on`（`argStrictList`，rests_on 允許空陣列），描述寫明 id 形狀、試切規則、整批拒絕與逐筆略過的類別與上限。驗證：以 stdio 驅動真 binary，寫入一筆、組合拒絕、`rests_on: []` 與省略同義
- [ ] 3.2 CLI `resolve-organizations` 新增 `--undecided`／`--rests-on`，走 service 同一個函式；列表每列印出 rowID，有未決的列標「查過未決 N 次」。驗證：`OrgUndecidedCLITests` 以真 binary 寫入一筆後列表出現標記與 rowID
- [ ] 3.3 CLI 篩選式 `--apply` 排除查過未決的候選（判準用 `ResolutionLedger.undecidedChecks`），另列並指路以 id 點名的 MCP apply；全數被排除時零寫入、非零結束；`--reject` 不排除。驗證：`OrgUndecidedCLITests` 兩個候選一個查過未決時只套用另一個、全數查過未決時零寫入且非零結束（spec「Filtered CLI apply SHALL exclude checked candidates」；design「CLI 的排除在 CLI 側套用，判準來自同一個 ledger 函式」）

## 4. 負控、文件與收尾

- [ ] 4.1 負控：拿掉「前綴必須是已知 rowID」與拿掉 CLI 排除，對應測試各自變紅後還原。驗證：記錄兩次紅與還原後檔案位元組相同
- [ ] 4.2 規則文件：`mcp-cli-parity` 的 resolve-organizations 列改為兩面都有未決腿（並記 CLI 排除與 MCP 逐 id 照寫的面不對稱）、`two-kinds-of-edits` 的未決列納入 resolve-organizations；新增 `changelog/2026-09-25-org-undecided-leg.md`。驗證：守衛 `bash .githooks/run-guards.sh` rc=0（含 parity-table-drift）
- [ ] 4.3 全套 `swift test --build-system native` 零失敗、`swift build -Xswiftc -warnings-as-errors` 通過。驗證：log 的 `Executed N tests … 0 failures` 與 guards rc=0
