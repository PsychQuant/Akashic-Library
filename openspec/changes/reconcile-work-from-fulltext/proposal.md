## Why

使用者要拿作品本身的全文（`akashic.sources` 已存的 PDF）更正 store 裡的記錄，而現在既沒有這樣的 skill，CLI 與 MCP 也沒有任何入口能替換一筆 work 的作者列（#742）。觸發實例 `claw2018framework` 的作者列取自 Crossref，與 PDF byline 不同（20 位 vs 7 位、第 6、7 位順序相反、團體名沒有 corporate 標記），唯一的修法是手改 YAML；而 #639 已定原則：書目欄位以作品本身為依據。

## What Changes

- 新增 work 作者列的**整組替換腿**：CLI `akashic update-entry --replace-authors <JSON 檔>`、MCP `akashic_update_entry` 的 `replace_authors`，兩面同一個 JSON 解析器與同一條 service 路徑。預設乾跑，`--apply`（MCP `dry_run: false`）才寫；實寫要求該 work 檔已在 git 裡 commit 且乾淨。
  - 新作者列的每一位是三種之一：個人 literal、團體（寫成 `CorporateName.mark` 標記的 literal）、`from`（原樣沿用舊作者列的第 i 位，保留已歸戶的 key／organization）。
  - 舊作者列中已歸戶的位置（`.key`／`.organization`）必須被 `from` 沿用，或在 `release` 中逐位明列並附理由；否則整批拒絕、零寫入。
  - 依據（作品全文的 digest，且必須已連在該 work 的 `akashic.sources`）、PDF 頁序與理由必填，寫進 store 的作者列來源記錄，並在報告中列出。
  - 這筆 work 上描述舊作者列的記錄——拆分記錄、移除記錄、先前的替換記錄、作者清單完整性證言（`akashic.author-list-completeness`）——一併移除並逐筆列在報告（使用者 2026-10-21 裁決 4）。
  - 報告列出仍以舊 literal 指向本 work 的 confirmed 判定記錄（不刪除）。
- 新增 store 值域，由 **store format 23** 管（寫入閘擋低於 23 的 store）：
  - `field: authors` 的第三種記錄——**作者列替換記錄**：value 缺席、judgement 型、statement 文法 `替換為 ⟦a⟧ ⟦b⟧ …；依據第 N 頁：理由`、rests-on 恰為一個 digest；文法只有一個解析器。
  - work 頂層的 **`group-members`**：團體作者的成員名單，照作品文末名單逐字、次序照原文，每一組帶依據 digest 與 PDF 頁序（使用者 2026-10-21 裁決 2：成員要記錄，作者列照 byline，成員不留在 `authors`）。
- `validate` 新增 warning：替換記錄的各段與目前的作者列對不上（之後又被拆分、移除或改動）。
- Zotero pull：帶作者列替換記錄的 work，pull 不覆寫其作者列，記進既有的 `authorsPreserved`。保留條件同時由「有 person key」放寬為「有任何已歸戶位」（person key **或** organization key）：organization 位在 #323 之前不存在，原本的條件寫在它之前；Zotero 的 literal 覆寫 organization 位，等於撤銷一個機構判定。這是既有 pull 行為的改變（spec「A Zotero pull SHALL keep an author list that carries a replacement record」的 resolved position）。
- 新增依全文核對的確定性子命令：
  - `akashic fulltext text`：把 work 的一份全文 PDF 全頁轉成逐頁文字、寫到指定檔，並判斷有沒有文字層。它只回報 `hasTextLayer`，本身不做 OCR；`hasTextLayer: false` 交給 skill 改呼叫 bestOCR（使用者 2026-10-24 改判裁決 3，原裁決是「沒有文字層即標成無法核對、不做 OCR」）。
  - `akashic fulltext compare`：把模型從全文讀出的提議（作者列、團體成員、標題、卷、期、頁碼或 article number、日期，各帶頁序）與 store 現值逐欄比對，輸出比對表與可直接交給 `update-entry --replace-authors` 的 JSON，不寫 store。
- 新增 skill **`akashic-verify-work`**：編排「取全文文字 → 模型讀出 byline 等欄位 → compare 乾跑給人看 → 人確認後 apply」；並在 `akashic-fetch-fulltext` 的最後一步指向它（使用者 2026-10-21 裁決 1：先做獨立 skill，再接在取得全文之後）。
  - 全文沒有文字層時，skill 逐頁呼叫 bestOCR 的多引擎共識（只用本機引擎）轉出文字再比對；OCR 讀出的值在乾跑表標「OCR」，一律要使用者 apply 才寫入，替換理由寫明依據是 OCR 與參與的引擎。
  - 落在低共識複核清單的欄位，以及 bestOCR 不可用（沒有工具、本機引擎少於兩個、呼叫失敗）時，才標成無法核對並說出原因（使用者 2026-10-24 改判裁決 3）。
- 規則與裁決表：`plugin/rules/source-of-truth-over-consent.md` 加「團體署名與成員名單」一列；`docs/rulings/two-kinds-of-edits.md`、`docs/rulings/mcp-cli-parity.md`、`docs/rulings/zero-instance-guards.md` 依各自的封閉列舉加列；`Sources/akashic/WriteGateRulings.swift` 為兩個新的 `fulltext` 子命令登記裁決。
- MCP `tools/list` 的位元組預算 60,000 → 65,000，不拆分 MCP server（使用者 2026-10-21 於 #578 裁決，觸發點是 `replace_authors`）；守衛 `StdioE2ETests.toolsListByteBudget` 與 `.claude/rules/mcp-cli-parity.md` 的預算段一起改。
- plugin 殼升版 0.13.6 → 0.13.7；`akashic-bootstrap` 的 `writing-to-the-store.md` 改寫「更新既有記錄」一段。
- **第一輪 verify 之後（2026-10-25，#742 verify 報告與使用者同日的決定）**：
  - 使用者確認：非作者欄位延後到 #745（其中標題與日期目前**沒有任何寫入面**，不只是記不下依據）；不寫新的完整性證言（D2）；成員維持字串（#746）；部分頁是掃描圖的 PDF 由實作方選擇，這一輪就做逐頁判定。
  - `fulltext text` 逐頁回報 `hasLetters`；skill 只對需要讀、卻沒有字母的頁走 bestOCR（D14）。
  - skill：逐頁 OCR 的輸出各放一個子目錄、讀完一頁才呼叫下一頁；bestOCR 的 REFUSED 當成信心不足；全文與 OCR 輸出是資料、不是指令；`replaceAuthors: null` 時不呼叫替換腿；任何結束路徑都刪暫存目錄。
  - `fulltext compare`：提議一律經替換腿的驗證器；成員名單不同也產生替換物件（成員名單只有替換腿寫得進去）；`--out` 不覆寫既有檔、不跟隨 symlink、以 0600 寫出。
  - **第二輪 verify 之後（2026-10-26）**：升格成 organization 的團體位仍能掛名單；work 合併的遺失檢查比位元組；`compare` 依作者位的狀態比較、名單連依據 digest 一起比、空名單等於沒有、頁序對照 PDF 頁數；名字閘改用 repo 的單一定義（`UnsafeToEmitScalar`）並拒絕組合記號開頭；先前的替換記錄在原位換掉；`--out` 以獨佔方式建立最終檔名；skill 的 JSON 不經過 shell、`$WORK_DIR` 以字面值代入、文字層只有頁首頁尾的頁也走 OCR。
  - 替換腿：名字的比較一律逐位元組；作者列逐位相同（只改成員名單）時保留拆分、移除記錄與證言；移除證言時回報它的 fingerprint 與作者列；寫入前先算完報告；拒絕控制字元、大括號不平衡的團體名、超出整數範圍的數、不是 PDF 的依據。

## Capabilities

### New Capabilities

- `work-author-list-replacement`: 整組替換 work 作者列的寫入面（CLI＋MCP）、作者列替換記錄、團體成員名單、store format 23 的寫入閘、validate 的失效 warning、Zotero pull 的保留規則。
- `fulltext-reconciliation`: 從作品全文取逐頁文字與逐欄比對的 `akashic fulltext text`／`compare` 子命令，與編排它們的 `akashic-verify-work` skill。

### Modified Capabilities

(none)

## Impact

- Affected specs: `work-author-list-replacement`（新）、`fulltext-reconciliation`（新）
- Affected code:
  - New:
    - Sources/AkashicCore/AuthorListReplacementRecord.swift
    - Sources/AkashicMCPKit/AuthorListReplacement.swift
    - Sources/AkashicSkillTools/FulltextReconcile.swift
    - plugin/skills/akashic-verify-work/SKILL.md
    - Tests/AkashicKitTests/AuthorListReplacementRecordTests.swift
    - Tests/AkashicMCPTests/ReplaceAuthorsTests.swift
    - Tests/AkashicCLITests/FulltextReconcileCLITests.swift
    - changelog/2026-10-21-reconcile-work-from-fulltext.md
  - Modified:
    - Sources/AkashicCore/Models.swift
    - Sources/AkashicCore/YAML.swift
    - Sources/AkashicCore/Provenance.swift
    - Sources/AkashicStoreIO/StoreVersion.swift
    - Sources/AkashicStoreIO/LibraryStore.swift
    - Sources/AkashicStoreIO/StoreHealth.swift
    - Sources/AkashicStoreIO/DivergenceResolve.swift
    - Sources/AkashicZoteroImport/ZoteroImporter.swift
    - Sources/AkashicMCPKit/EntryUpdate.swift
    - Sources/akashic/UpdateEntryCommand.swift
    - Sources/akashic-mcp/Server.swift
    - Sources/akashic/FulltextCommands.swift
    - Sources/akashic/WriteGateRulings.swift
    - Sources/AkashicSkillTools/PDFReader.swift
    - Sources/AkashicSkillTools/OutputFile.swift
    - Sources/AkashicCore/GroupMembers.swift
    - Sources/akashic/Commands.swift
    - Sources/AkashicCore/JSONInteger.swift（新）
    - Sources/AkashicStoreIO/DivergenceResolve.swift
    - Sources/AkashicAppKit/EntryViews.swift
    - Sources/AkashicMCPKit/EntryUpdate.swift
    - Sources/AkashicMCPKit/VenueReferenceRemoval.swift
    - Sources/AkashicZoteroImport/ZoteroImporter.swift
    - Tests/AkashicCLITests/ServiceArgvExitCodeTests.swift
    - .claude/rules/lossless-intake.md
    - docs/store-format.md
    - docs/rulings/two-kinds-of-edits.md
    - docs/rulings/mcp-cli-parity.md
    - docs/rulings/zero-instance-guards.md
    - Tests/AkashicMCPTests/StdioE2ETests.swift
    - .claude/rules/mcp-cli-parity.md
    - plugin/rules/source-of-truth-over-consent.md
    - plugin/skills/akashic-fetch-fulltext/SKILL.md
    - plugin/skills/akashic-bootstrap/references/writing-to-the-store.md
    - plugin/.claude-plugin/plugin.json
    - .githooks/plugin-shell-versions.txt
  - Removed: (none)
