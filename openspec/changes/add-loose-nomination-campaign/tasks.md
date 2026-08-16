## 1. 寬鬆鍵生成器（AkashicCore）

- [x] 1.1 `Tests/AkashicKitTests/LooseNameKeyTests.swift`（RED）→ `Sources/AkashicCore/LooseNameKey.swift`（GREEN）：design「D1 — 寬鬆鍵生成器 `LooseNameKey`（AkashicCore，與 `NameNormalization` 並列）」的 table-driven 鍵生成——reorder key（`Hsu, Yung-Fong` 與 `Yung-Fong Hsu` 同鍵）、逗號標定姓氏（`Chen, Chun-Houh` 只生一鍵 `chen ch`）、無逗號雙解讀（`C-H Chen` 生兩鍵）、連字號段取首字母（`Y.-H.`→`yh`）、CJK 不生 initials 鍵（`鄭澈`）——落實 requirement: Initials matching SHALL NOT guess family-name position 與 requirement: Matching tiers SHALL be a closed enumeration of four 的鍵語意。驗收：`swift test --filter LooseNameKeyTests`

## 2. Resolver tier（AkashicEntity）

- [x] 2.1 design「D2 — tier 語意與抑制序」的 `Tier` 封閉四值 enum＋`ResolutionCandidate`／`AmbiguousMatch` 增 `tier` 欄（`Sources/AkashicEntity/PersonResolver.swift`）——落實 requirement: Every reported row SHALL disclose its tier on all faces 的型別前提。驗收：既有 `EntityTests`（resolver 案例住此）編譯綠（tier 預設接線）
- [x] 2.2 `ResolutionLedger.confirmedPairings(people:)`（`Sources/AkashicEntity/ResolutionLedger.swift`，鏡像 `rejectedPairings`；design「D3 — confirmed-elsewhere：verdict 知識再利用」）——落實 requirement: Confirmed verdicts SHALL be reused as nomination knowledge 的資料源。驗收：`swift test --filter ResolutionLedgerTests`（confirmed 對照 rejected 的對稱案例）
- [x] 2.3 `PersonResolver.resolve` 增 `confirmed:` 必填參數＋四 tier 提名＋最高 tier 抑制＋tier 內 2+ 命中落 ambiguity＋rejected 全 tier 抑制（新檔 `Tests/AkashicKitTests/PersonResolverTests.swift` 逐 spec scenario；既有 `EntityTests` 同步過綠：reorder 提名／initials 提名／exact 抑制低 tier／initials 碰撞歧義／confirmed-elsewhere 提名／reject 抑制 reorder 而他 entry 照提／羅馬化不提名）——落實 requirement: A literal occurrence SHALL nominate only at its highest matching tier、requirement: Two or more hits within the nominating tier SHALL be reported as ambiguity、requirement: Rejected pairings SHALL be suppressed across all tiers、requirement: Nomination SHALL never merge — apply is a separate, explicit act。驗收：`swift test --filter "EntityTests|PersonResolverTests"`

## 3. 三面接線（tier additive）

- [x] 3.1 [P] `AkashicService.resolvePeople` 帶 `confirmed:`＋JSON 輸出 `tier` 欄（design「D4 — 回報形狀（additive）」；`Sources/AkashicMCPKit/AkashicService.swift`、`Sources/akashic-mcp/Server.swift` schema 描述）——落實 requirement: Every reported row SHALL disclose its tier on all faces 的 MCP scenario。驗收：`swift test --filter VenueServiceTests` 不回退＋新增 resolvePeople tier 案例於 `Tests/AkashicMCPTests/`
- [x] 3.2 [P] CLI `resolve-people` 人可讀輸出按 tier 分組（`Sources/akashic/CLI.swift` 的 ResolvePeople）——同 requirement 的 CLI 半邊。驗收：`swift test --filter PersonCLITests`（輸出含 tier 分組標頭）
- [x] 3.3 [P] App Adjudication 候選列帶 tier 標示（`Sources/AkashicAppKit/Adjudication.swift` 消費新欄；顯示不改互動流）——同 requirement 的 App 半邊。驗收：`swift test --filter AdjudicationTests`
- [x] 3.4 `.claude/rules/mcp-cli-parity.md` 的 `akashic_resolve_people` 列註記增 tier 語意（修改既有能力的重確認條款；design「D6 — 契約面重確認（mcp-cli-parity）」）——落實 requirement: Every reported row SHALL disclose its tier on all faces 的登錄面。驗收：該列文字含 tier、機械稽核兩方向零缺格

## 4. Campaign skill 層

- [x] 4.1 [P] `plugin/skills/akashic-literal-campaign/scripts/literal-census.sh`：三域 literal 計數（author／venue／affiliation 的邊數＋distinct 數；design「D5 — campaign skill `akashic-literal-campaign`」）；store format < 11 時 venue 域回報「未部署」而非 0——design D5 的缺席／零可區分契約。驗收：對 `$CLAUDE_JOB_DIR/tmp/rehearsal-store` 實測回報 author 2123/1493、venue 803/441；對真 store（format 10）venue 域顯示未部署
- [x] 4.2 [P] `plugin/skills/akashic-literal-campaign/SKILL.md`：campaign workflow（census → 按批 TaskCreate → 逐 distinct「查證（引用 akashic-person-verify）→ resolve → apply」→ 每輪計數落一筆 #303 comment；批次順序＝混合：高頻先掃、統計所批接續、長尾建檔殿後；initials tier 的 apply 必附查證——design Risks 的 store 不完整假象警告）＋`plugin/CHANGELOG.md` 條目。驗收：skill 檔存在＋CHANGELOG 條目

## 5. 收尾

- [x] 5.1 全套 `swift test` 綠＋真 store `resolve-people`（read-only、不 apply）實測候選數 > 0 並記錄各 tier 分布——Implementation Contract 驗收第三條。驗收：swift test 輸出＋候選數記錄於 commit message 或 #303

## 6. R1 verify 修正輪（2026-08-17，8 blocking＋in-scope——事後審計記錄，實作先於本節）

- [x] 6.1 B5 `LooseNameKey` 句點分段（`.` 與 `-` 同界；`L.W. Wang` 假陽性除；reorder 鍵一致受益）。驗收：LooseNameKeyTests 13 綠
- [x] 6.2 B7＋I1＋I2 resolver 語意成文：淘汰揭露、否決正規化抑制、confirmed 只吃 work-holder——spec 新增 3 requirement＋4 scenario。驗收：PersonResolverTests 14 綠
- [x] 6.3 B2 verdict rule 依 tier 導出（`personRule(for:)` 封閉映射）＋pending 按 rule 分桶＋三寫入點＋CLI 逐 rule 計數。驗收：ledger／verdict-service 測試綠、真 store 計數分層
- [x] 6.4 B8 apply id 三段釘 person（改指顯式拒絕、兩段 legacy 收）。驗收：ResolutionVerdictServiceTests 釘 id 案例
- [x] 6.5 B1 CLI `--tier` 篩選＋裸 `--apply` 對寬鬆 tier 拒絕。驗收：ResolvePeopleSelectiveTests 3 新案例
- [x] 6.6 B6 CLI／App 歧義帶 tier＋指引分層（exact 兩難 vs 寬鬆共鍵）。驗收：swiftc typecheck App view 0 error
- [x] 6.7 B4 bootstrap `pendingResolution` 桶（寬鬆共鍵不建檔、否決後回歸）＋CLI 列印。驗收：PersonBootstrapTests 2 新案例
- [x] 6.8 B3＋I5＋I7 campaign skill 重寫（三因分辨階梯、initials 逐 entry、資料非指令條款）；I4 census（glob.escape＋自檢＋口徑＋org-parents 域）。驗收：census 對 metachar root exit 3、四域輸出
- [x] 6.9 I6 記錄更正（427→175 errata PATCH）＋parity 列改「有記錄的變更」＋design D7 追加裁決。驗收：全套 swift test 綠、真 store 重測 62 reorder＋114 initials
