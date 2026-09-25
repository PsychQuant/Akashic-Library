## 1. 欄位與三把鍵（AkashicCore／AkashicEntity）

- [ ] 1.1 `resolutionVerdictFields` 擴成三值、`ResolutionLedger.VerdictKind` 加 `.undecided`，`validateReferenceAttachment` 接受帶或不帶 rests-on 的 `resolution-undecided`、拒絕文法錯的 value；驗證：`UndecidedVerdictTests` 的載入與拒收兩例，以及 `swift build -Xswiftc -warnings-as-errors` 對新 case 逼出的每個 exhaustive switch 都有顯式分支（spec「Verdict fields SHALL be a closed set of three」「Only undecided verdicts SHALL carry evidence digests」；design「verdict 欄位擴成封閉三值，新增 resolution-undecided」「未決記錄允許帶 rests-on，confirmed／rejected 仍不帶」）
- [ ] 1.2 新增 `VerdictRecordKey.swift`：`verdictPairingKey`、`verdictRecordKey`（confirmed／rejected 含 `nominated`／`judged` 層級；undecided 用 `byteExactKey`）、層級導出函式（只有 `author-judged-per-work` 與 `author-organization-judged` 是 judged）；驗證：`VerdictRecordKeyTests` 覆蓋 spec 的 Record-key equality 表四列、legacy 無尾註一例與 `author-organization-judged` 一例；同步更新 `SplitRecordReferenceTests`（釘三值欄位）與 `ByteExactKeySiteInventoryTests`（新檔進使用清單），並附負控（把層級從記錄鍵拿掉，同配對異層級那例必紅）（spec「Confirmed and rejected verdicts SHALL belong to one of two judgement classes」「Verdict identity SHALL be defined by three named keys」；design「判定層級是封閉二值，由 rule 導出」「三把具名的鍵取代單一相等定義」）
- [ ] 1.3 `ResolutionLedger`：`appendIfAbsent` 改用記錄鍵；`supersede` 退役相反 field 的兩個層級、不動 undecided；新增 `record(undecided:)` 唯一產生器（補 `[rule: checked-undecided]`）與 `pairingState`；`confirmedPairings` 在並存時回 judged rule；驗證：`ResolutionLedgerTests` 新增並存寫入、退役不碰 undecided、judged 優先三例（spec「A pairing's state SHALL be derived as decided, undecided, or pending」；design「狀態推導：decided 大於 undecided 大於 pending」）
- [ ] 1.4 `ResolutionLedger.counts` 改四態（undecided 以候選配對狀態計、不再算進 pending）；驗證：`ResolutionLedgerTests` 的「checked pairing leaves pending」例，以及既有計數測試改寫後全綠（spec「Calibration counts SHALL distinguish undecided from pending」；design「四態計數」）

## 2. 使用點指派（StoreHealth／StoreIO／合併）

- [ ] 2.1 以 grep 盤點 `verdictEqualityKey`、`resolutionVerdictFields`、`VerdictKind`、`resolutionConfirmedField` 全部使用點，依 design 的指派表逐處改寫，指派表貼進 commit body；驗證：盤點輸出的每一行在指派表都有對應列（行數相等），且 `where v.kind == .confirmed` 類過濾逐一在表上註明「不變」或「改」（design「三把具名的鍵取代單一相等定義」）
- [ ] 2.2 [P] `StoreHealth`：#486 矛盾掃描改用配對鍵且不分層級、D64 重複掃描改用記錄鍵、死 verdict 掃描與 venue 預算納入 undecided；驗證：`JudgedCoexistenceTests` 的「nominated confirmed ＋ judged rejected 報矛盾」與「兩層級並存 D64 不報」，`zero-instance-guards` 第 13／14／16／28 列的量測指令在 live store 重跑數字不變（spec「Verdict identity SHALL be defined by three named keys」）
- [ ] 2.3 [P] 合併收攏（`DivergenceResolve` 的 `dedupKey`、`mergedPersonKeeper`、`migrateWorkHolderVerdicts`、`rewrittenVerdicts`）改用記錄鍵，D31／D34 矛盾閘改用配對鍵；驗證：`JudgedCoexistenceTests` 的 person 合併與 work 合併兩例（合併後兩筆並存仍在、指向倖存者），既有 `DivergenceResolve` 測試全綠（spec「Merge and rename SHALL preserve coexisting records」）
- [ ] 2.4 [P] rename（`LibraryStore.migratedVerdicts`、`verdictsStillPointingAt`）：D60 閘對三值 holder 一律生效，D62 仍只折整筆位元組相等；驗證：`JudgedCoexistenceTests` 的 rename 例（並存與兩筆異 statement 的 undecided 在 rename 後都在），以及「目的鍵已有 undecided 時 rename 具名拒絕」一例（spec「Merge and rename SHALL preserve coexisting records」）

## 3. 寫入面

- [ ] 3.1 `judgeAuthorships`：作者位已歸同一人且只有 nominated confirmed 時寫 judged confirmed 並存（回應 `coexistsWith: nominated`），refute 對 nominated rejected 同理；並存寫入要求 store format ≥ 19；驗證：`JudgedCoexistenceTests` 的 judge-after-apply、refute-after-reject、format 18 拒絕三例，並改寫 `JudgedAuthorshipServiceTests` 中斷言「略過、升級見 #636」的舊例（spec「Per-work judgement SHALL coexist with an earlier nominated verdict」；design「並存的寫入面：judge／refute 在已同向判過的配對上寫入」）
- [ ] 3.2 `AkashicService` 新增 resolve-people 與 resolve-venues 的 undecided 腿（整批拒絕、逐筆略過、`alreadyRecorded` no-op、單獨呼叫、`rests_on` 須伴隨 undecided、format ≥ 19）；驗證：`UndecidedVerdictTests` 逐條覆蓋 spec 的六種整批拒絕與四種逐筆略過，另附負控（拿掉「已 decided 略過」即紅）（spec「Undecided verdicts SHALL be written only through an explicit per-id leg」；design「未決的寫入面」）
- [ ] 3.3 CLI `--undecided`／`--rests-on`（`Commands.swift` 的 resolve-people、`VenueCommand.swift` 的 resolve-venues）與 MCP `undecided`／`rests_on`（`Server.swift`）接到同一個 service 函式，help 寫明 rests-on 套整次呼叫；驗證：真 binary 端到端（假 HOME、scratch store、format 19）各跑一次兩個命令，stdout 與 MCP stdio 回應逐筆列出寫入的 digest（spec「Undecided verdicts SHALL be written only through an explicit per-id leg」）

## 4. 提名、批次 apply、呈現

- [ ] 4.1 `PersonResolver`／`VenueResolver` 的候選列與歧義條目帶 `undecidedChecks`，MCP 列表加 `counts.undecided` 與 `undecidedTotal`，CLI 列表標「查過未決 N 次」；驗證：`UndecidedVerdictTests` 的列表揭露例（CLI 文字與 MCP JSON 各一）（spec「Nomination SHALL disclose undecided checks and filtered apply SHALL exclude them」；design「提名與批次 apply 對未決的處理」）
- [ ] 4.2 CLI 篩選式 `--apply`（只有 resolve-people 有；resolve-venues 兩面都只收 id）排除帶 undecided 的候選並另列、全數排除時零寫入非零結束、tier 閘看排除後的集合；MCP 逐 id apply 照寫；驗證：`UndecidedVerdictTests` 的 Filtered apply skips 與 MCP per-id apply writes 兩例，外加負控（拿掉排除即紅）（spec「Nomination SHALL disclose undecided checks and filtered apply SHALL exclude them」）
- [ ] 4.3 `akashic person`／`akashic venue` 檢視面逐筆印出 undecided 記錄（statement 與 rests-on，經 `displaySafe` 消毒）；驗證：`PersonCLITests` 新增一例，且 `SanitizationBoundaryTests`／`DisplaySinkCoverage` 守衛綠（design「狀態推導：decided 大於 undecided 大於 pending」）

## 5. format 閘、文件、收尾

- [ ] 5.1 `StoreVersion.supported` 升到 19（連同 `Format13GateTests`、`KnownLayerEvolutionTests`、`AdditionalProvenanceFormatGateTests` 三處 pin、`README.md` 的 format 列、`plugin/.claude-plugin/plugin.json`），`docs/store-format.md` 記錄 undecided 欄位、三把鍵與層級、部署順序；驗證：`StoreVersionTests` 的「format 18 binary 拒開 19」例，`bash .githooks/run-guards.sh` rc=0（含 `measured-numbers-audit`）（spec「Store format 19 SHALL gate the new verdict shapes」；design「store format 18 → 19」）
- [ ] 5.2 [P] 規則文件：`entity-backlink-completeness` 的 #280 注記改寫成三段載體分工，`mcp-cli-parity` 的 resolve-people／resolve-venues 列補 undecided 腿與 org 族缺席（附 follow-up issue 編號），`two-kinds-of-edits` 加 undecided 一列（AI 編輯），`zero-instance-guards` 第 14／28 列改寫鍵的描述；驗證：`parity-table-drift` 與 `zero-instance-rows-audit` 守衛綠，並對四份文件做內容審閱（每處改動都引本 change 名）
- [ ] 5.3 [P] `plugin/skills/akashic-disambiguate/SKILL.md` 把「判不出來」的出口從「只寫在報告」改成寫 undecided 並附 rests-on；驗證：skill 文字審閱，且 `rule-coverage` 守衛綠
- [ ] 5.4 收尾：`swift build -Xswiftc -warnings-as-errors`、`swift build --build-system native --product akashic`、全套 `swift test` 0 失敗、守衛 rc=0（PATH 先放 Python 3.13）；驗證：三個命令的輸出摘要與 `Executed N tests` 行貼進 Implementation Complete comment
