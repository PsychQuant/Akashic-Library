# generic add-only 補值：一份政策、Zotero 版降為 adapter、citekey／DOI 定位（#458，Spectra change `generic-add-only-enrich`）

`enrich-from-zotero`（#340）把「只補不存在的鍵」做進了 `ZoteroEnrichment.plan`，但它只吃 Zotero item。#423／#455 之後
store 裡有以 DOI 為鍵的摘要存檔與其他非 Zotero 來源（Crossref／OpenAlex／人工查證），要補進 work 的 `fields` 沒有任何面
收得下——唯一的路是手改 YAML（`replace-endnote-and-zotero` 第 4 條要防的安靜失敗；2026-08-28 手改差點弄丟一筆 DOI）。
#458 的 decision（2026-09-03）：政策只能有一份，抽成 generic core，Zotero 版降為 adapter。

## core 住 AkashicCore、Zotero 版改 adapter

- 新增 `Sources/AkashicCore/AddOnlyEnrichment.swift`：`Proposal`（`citekey`／`doi` 二擇一、`fields`、`date?`、`authors`、
  `sourceDigest?`；Codable，頂層未知鍵拒絕）、`Category` 封閉五值（`added`／`skipped`／`ambiguous`／`notFound`／`rejected`）、
  `Addition.Kind` 封閉四值（`field`／`identifier`／`date`／`authors`）、`Outcome`（寫入計畫）、`Item`／`Result`、
  `plan(entries:proposals:includeAbsentAuthors:)`、`applied(_:to:)`。欄位政策**逐字**自 `ZoteroEnrichment.plan` 搬入。
- `ZoteroEnrichment` 改為 adapter：找 item → `ZoteroMapping.mappedFields`／`normalizedDate`（自 `applyBiblatexFields`
  抽出的前半，pull 與 adapter 同一份對映）產 `Proposal` → 委派 core → 把 `Item` 映回既有的 `Result` 六類。`Addition`／
  `Result`／`plan`／`applied` 的公開簽章不變。**`ZoteroEnrichmentTests` 12 支零改動綠**（全檔 54 支，含 pull 側）。
- **設計外的一步，記在這裡**：識別碼 tokenizer（`qualifiedCandidates`／`normalizedUniqueQualified`／`absorbsMultipleValues`
  一族）原本住 `AkashicStoreIO.IdentifierMigration`，而 core 要在 Core 重現 ISBN 的三態解析（全解／部分解／不解）就需要它。
  搬進 `AkashicCore.IdentifierTokenizer`，`IdentifierMigration` 的同名函式全部轉發（`IdentifierMigrationTests` 22 支零改動綠）。
  這件事 `IdentifierMigration` 自己的 doc 早就寫著：「刪它之前必須先把這兩個函式搬到 `AkashicCore`（識別碼解析不是遷移的職責）。
  追蹤：#427 的 follow-up」——#458 是第一個非遷移的常設呼叫端，搬家在這裡發生。design.md 說「core 需要的東西全在 Core」，
  那句話漏了 tokenizer；本 changelog 是那個落差的記錄。
- **RED 測試修過一個 fixture**：前一輪寫的 `testIdentifierGoesToStructuredFieldWithResidue` 用 `doi: "10.1000/x notadoi"` 期望
  「部分解析、殘留保留」——但多值吸收**按種類**裁決（DOI 刻意不吸收：附錄的 DOI 是一句假的身分宣稱），第三態只在 ISBN／ISSN 上
  存在；DOI 對整個字串是一個值、後綴含空白 → nil → `refused`。改用 `ZoteroEnrichmentTests` 同一個 ISBN fixture
  （`9781433832161 1-4338-3216`），另加 `testUnparseableIdentifierIsRefusedByName` 釘住 DOI 那條路是拒絕不是部分解析。

## Proposal 以 citekey 或 DOI 定位，DOI 命中多筆為 ambiguous

- DOI 相等是 `identity-is-judged-not-matched` 的識別碼例外，對回 citekey 由程式做（`two-kinds-of-edits`：程式編輯）。
  比對走 `Entry.canonicalDOIs`（`Models.swift` 的既有立場：「讀取請走 `canonicalDOIs`，不要自己比較」）與 `DOI` 型別的正規形
  （大小寫不敏感、剝 `https://doi.org/` 前綴）。
- 命中 ≥2 → `ambiguous`，`matches` 列全部 citekey、零寫入、不判定哪筆才對（#459 的攣生管線）；命中 0 → `notFound`；
  DOI 不是合法形狀 → `notFound` 並具名（不擴 design 列的四類輸入語法錯——那是封閉列舉，加第五類要顯式裁決）。
- **雙斜線案**：`10.1037/x` 與 `10.1037//x` 在 `DOI` 正規形下是兩個不同的 DOI（APA 一九九〇年代的官方形就是雙斜線），
  比對**不折疊**；`testDoubleSlashDOIIsADifferentDOIUnderTheNormalForm` 釘住提案 `10.1037//x` 只命中帶雙斜線的那筆。
- 輸入語法錯**整批拒絕零寫入**、指名第 N 筆：兩鍵同給、兩鍵皆無、`fields` 空且無 `date`／`authors`、`FieldKey.normalized`
  回 nil 或正規化後撞鍵。`InputError` 帶 `CustomStringConvertible`——字串內插也拿得到那句，不是 enum 預設印法（RED 抓到）。
- 同一批多筆指向同一筆記錄時**依序**計算：後面的提案看得到前面會補的鍵（`alreadyPresent`），service 把各筆 outcome 疊在同一份
  entry 上**寫一次**——否則第二次寫入拿舊 load 的 entry 蓋掉第一次補的值（`testSameTargetTwiceIsAppliedInOrderAndWrittenOnce`）。

## 雙摘要分鍵，core 不猜鍵名

- `fields` 同時含 `abstract` 與 `abstract-<lang>`／`abstract-2` 時各自落地（經 `FieldKey.normalized` 成 `abstract_es`／
  `abstract_2`），不拼接、不自動編號、不猜語言；既有 `abstract` 在時只補第二個、第一個報 `alreadyPresent`。spec 的
  Example「Spanish second abstract」逐字進測試。

## 兩面契約沿 akashic_enrich_from_zotero 那列

- `AkashicService.enrich(proposals:dryRun:includeAbsentAuthors:itemLimit:)`：一次 `load`、委派 core、逐筆 `writeEntry`
  （I/O 失敗逐筆收容進 `writeFailed`，其餘照寫）、一次 rebuild（rebuild 擲錯不吞報告，同 importZotero 的 R10 裁決）；
  `dryRun` 零寫入。payload：`dryRun`／`proposals`／`counts`（永遠完整）／`items`／`itemsTotal`／`truncated`／`written`／
  `indexRebuilt`／`writeFailed`，字串值全部 `displaySafe`。
- MCP `akashic_enrich`（tool 數 30 → 31）：`proposals` object 陣列、`dry_run` 預設 true、`include_absent_authors` 預設 false、
  畸形 boolean 顯式拒絕（#406 R1 的同一條理由）；items 截 20（`AkashicMCPServer.enrichItemLimit`，#236 的預算形）；不設 #298 閘。
- CLI `enrich --from <file.json> [--apply] [--include-absent-authors] [--json]`（`Sources/akashic/EnrichCommand.swift`）：乾跑預設、
  `--apply` 走 `DestructiveTargetGate`（封閉列舉加 `enrich` 一列，雙向稽核綠）、`--json` 原樣轉印 service payload、人可讀從同一個
  payload 渲染、不截 items。`PersonCLITests` 的 service 建構計數 22 → 23。
- **兩面同一個 JSON 解析器**：`AddOnlyEnrichment.decodeProposals(from:)`——CLI 讀檔、MCP 把 `Value` 編回 JSON 再解。頂層未知鍵
  整批拒絕（`abstract` 寫在頂層而非 `fields` 是最容易犯的錯，靜默略過會讓那筆看起來「補了」）；`source_digest` 與 `sourceDigest`
  都收。
- `.claude/rules/mcp-cli-parity.md` MCP 表加一列（30 → 31 工具；第二個有記錄的差異：MCP 截 20、CLI 不截——#388 的同一個論證）；
  `.claude/rules/two-kinds-of-edits.md` 裁決史加一列（程式編輯）。`run-guards.sh` 全綠（parity 表 MCP 31｜CLI 46｜橫切 2）。

## 摘要來源只進報告不進 store

- `Proposal.sourceDigest` 逐筆回顯在 `Item`、service payload、CLI 人可讀（「來源：…（只記在報告，不進 store）」）；
  `applied` 不碰 `Entry.references`（`testSourceDigestIsReportedNotStored`：apply 前後 `references` 相等）。
  值域擴張是第 15 條邊的裁決（#450），本 change 不擴。

## Interface depth check

seam＝`AddOnlyEnrichment`（契約 `[Proposal] → Result`）；adapter 恰一個（Zotero）；深度＝政策＋分類＋歧義拒絕＋依序疊加；
刪除測試：拿掉它，CLI／MCP 兩面與 Zotero adapter 都失去政策——不是 pass-through。

## 與相鄰 issue 的關係

- #450（第 15 條邊值域）：`sourceDigest` 不進 store 正是把那個問題留給它。
- #449（pages 回填）：同族——pages 是 `fields` 的一個鍵，走本面即可（`fields: {pages: "…"}`），不需要專用命令。
- #455（批次面）：service 的形（一次 load、一次 rebuild、I/O 失敗逐筆收容）逐字沿用。
- #427：tokenizer 搬家的 follow-up 在本 change 落地；`IdentifierMigration` 退場時整段轉發可刪。

## 量測（2026-09-06）

- 新測試：`AddOnlyEnrichmentTests` 17、`EnrichServiceTests` 8、`EnrichCLITests` 7、`StdioE2ETests` +2（tools 31）。
- 零改動綠：`ZoteroEnrichmentTests` 全檔 54、`IdentifierMigrationTests` 22。
- `swift build -Xswiftc -warnings-as-errors` 綠；全套 `swift test` **2,387 支、0 失敗、1 skipped**（230 秒，2026-09-06 本機）。
- `DisplaySinkCoverageTests` 第一輪抓到 3 條：`InputError.description` 內插 `reason`／`why`（含呼叫端給的欄位名）。裁決是
  **消毒在消費端、型別層標 exempt 並寫理由**——三個消費端（service／CLI／MCP handler）各自在 throw 站點 `displaySafe`，
  在 Core 先消毒會讓它們二次消毒（`displaySafe` 不冪等，它跳脫反斜線自身）。

## 誠實邊界

- adapter 對「core 拒絕提案」用 `preconditionFailure`：每筆提案恰有 citekey、鍵來自 `mappedFields`（已正規化且無撞鍵）、空提案
  先歸 `unchanged`，所以結構上不可達；若真的擲出，寧可大聲失敗也不把一批 citekey 歸錯類。這是一個沒有測試釘住的不變式。
- CLI 測試（`EnrichCLITests`）是先寫再實作，但 RED 沒有單獨跑過一次（與 `decodeProposals` 同一個 build）——RED→GREEN 的證據只在
  core／service／stdio 三層完整。
- 148 筆摘要存檔的批次餵入腳本（digest → DOI → `[Proposal]`）本 change 不裁，先以 `enrich --from` 收 JSON 檔（design 的 Open Question）。
