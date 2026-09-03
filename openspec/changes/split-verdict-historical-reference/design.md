## Context

`splitAuthors`（#443，PR #448）把一個黏著的作者 literal（實測 4 筆「某人與雷庚玲」）拆成 N 個作者位。它是作者位變更家族裡唯一**不可逆且沒有 store 記錄**的一腿：`attributeToOrganizations` 的 verdict 進 org 的 references、`judgeAuthorships` 逐字寫入、`demote`（#418）從 confirmed verdict 逐字取回原字串、取不到寧可拒絕。split 的 judgement 與原文只進當次報告（消毒顯示形），un-split 所需資訊只在 store repo 的 git 歷史。R1／R2 verify 把這判為誠實邊界——前提是持久化的值域問題被顯式裁決過，而 #450 的 spectra-discuss（2026-09-03）就是那個裁決，本 design 原封搬入。

三件由程式事實逼出的形狀：(a) `Entry.validateReferenceAttachment` 在 **decode 時**跑（YAML 解碼路徑），format-15 binary 讀到 `field: authors` 會整檔 quarantine，所以只能是 format bump 加寫入閘（#394 §6 識別碼 reference 需 format 13 的同一形）；(b) judgement 的空 rests-on 只對 resolution 兩欄位放行（#232 D8「一階人為裁決」）——拆分同樣是一階裁決、原文逐字保存於 value 就是證據，但把 `authors` 塞進 `resolutionVerdictFields` 會讓另外三處把它當 verdict 文法解析，故用第二個集合；(c) `ProvenanceReference` 只有 field／value／kind 三槽，各段沒有結構化位置，只能寫在 statement——那是 #232 D3 自認過的 grammar-in-string，補救方式與 `VerdictPairingValue` 相同：單一解析器。

第 15 條邊（`Entry.references`）與 resolution verdict 的 rests-on 例外，其正典要求目前住在**尚未 archive** 的 change `first-class-identifiers` 與 `resolution-judgement-ledger` 的 spec delta 裡，`openspec/specs/` 的 `entry-source-reference`／`provenance-reference` 主檔尚未含它們。本 change 因此以**新 capability** `split-record-reference` 自足地寫下 `authors` 那一格的全部要求，不對主檔做 MODIFIED delta；兩份主檔的既有要求不變。

## Goals / Non-Goals

**Goals:**

- split 的判定持久化到 work 側：`Entry.references` 收 `field: authors`、value＝原 literal 逐字、`kind: judgement(statement: "拆為 ⟦a⟧ ⟦b⟧：<理由>", restsOn: [])`，由 `splitAuthors` 在寫 entry 的同一步 append。
- 驗證對 `authors` 明寫例外：不要求 value 在場，要求 statement 各段至少一段仍是該 work 的作者位。
- rests-on 空值例外走第二個具名集合 `firstOrderRulingFields`；statement 文法由 `SplitRecordValue.parse` 單一解析。
- store format bump 16，三 binary 同步；已拆的 4 筆不回填。
- 孤兒 verdict 偵測進 `StoreHealth.perRecordIssues`（warning），`zero-instance-guards` 加一列。

**Non-Goals:**

- un-split 操作面（另開 issue；本張只保證 un-split 所需資訊在 store 裡）。
- 回填 store `32916ba` 已拆的 4 筆（原文與理由已不在 store，只在 git 歷史）。
- 對 `entry-source-reference`／`provenance-reference` 主檔做 MODIFIED delta（要求住在未 archive 的 change 裡，見 Context）。
- 讓 work 的其他欄位（title／date／`fields.*`）攜帶來源——那是第 15 條邊更大的值域問題，本張只加 `authors` 這一格。

## Decisions

### 拆分記錄住 work 側的 references，作為第 15 條邊值域的顯式擴充

拆分沒有「被判定的另一方」，唯一候選是 work 自己；`literal-first-then-key` 的論證要求誤可逆，而 split 正是唯一不可逆的一腿。代價：第 15 條邊第一次承載「已退役的值」——現有 reference 全附著在當下存在的值（D2 以值定位、`identifierListContains` 驗值在場），拆分記錄指向的是已不在記錄裡的值。所以不能硬套「值必須在場」，要為它明寫相反的例外。替代方案「另開第 16 條邊」否決：多一條邊要進封閉列舉、多一套序列化，而 `ProvenanceReference` 的三槽已經裝得下。

### 各段至少一段仍在是它的一致性條件

`authors` 的 reference 驗證：value 不要求在 `authors` 內；statement 解析出的各段至少一段仍是該 work 的作者位（`.literal` 或已升格的 `.key` 對應的 confirmed literal）。全部段都不在時，就是本張要偵測的孤兒形——留在 store 但由 doctor 報 warning，不在 decode 期拒收（記錄合法，只是證據錨已失效）。

### rests-on 空值例外用第二個具名集合 firstOrderRulingFields

`resolutionVerdictFields` 被三處當 verdict 文法（`<kind>:<key> :: <literal>`）解析——`ResolutionLedger.verdicts`、死 verdict 掃描、demote 的逐字取回。把 `authors` 塞進去會讓它們對拆分記錄解析失敗或誤判。第二個集合 `firstOrderRulingFields = resolutionVerdictFields ∪ {authors}` 只供「空 rests-on 放行」用，其他三處不改。

### statement 文法由 SplitRecordValue.parse 單一解析

文法 `拆為 ⟦a⟧ ⟦b⟧…：<理由>`：段以 `⟦…⟧` 包（段內可含空白與冒號）、段數 ≥2、`：`（全形）之後為理由、理由非空。寫入端（`splitAuthors`）與讀取端（驗證、孤兒掃描、未來 un-split）都只經 `parse`／`encoded`；與 `VerdictPairingValue` 同一條補救。

### store format bump 16 與寫入閘

`assertEntryWritable` 對帶 `field: authors` reference 的 entry 加 ≥16 閘（同 #394 識別碼 reference 的 ≥13 閘形）；`StoreVersion.supported` 升 16；CLI／akashic-mcp／App 三 binary 同步（`format-bump-breaks-three-binaries`：只升一個仍整份拒讀，部署順序見 changelog）。`store-marker-parity` 守衛認的兩份宣告一起改。

### 孤兒 verdict 偵測進 perRecordIssues

某 person／organization 持有的 resolution verdict（`work:<citekey> :: <literal>`）其 literal 等於該 work 某筆拆分記錄的 value → 該 verdict 的錨已被拆分退役。以 warning 級 `OwnedIssue` 併入 `perRecordIssues`（`orphanedSplitVerdictPrefix`／`orphanedSplitVerdicts`，鏡射 #464／#453 的形），owner 是持有者、訊息指名那筆 work。`zero-instance-guards` 加一列（零實例：4 筆已拆記錄沒有拆分記錄，所以今天必為零——零的來源是「記錄還沒開始寫」，要釘住）。

### Interface depth check

seam＝`Entry.validateReferenceAttachment`（`authors` 例外）＋`SplitRecordValue.parse`；adapter 恰一個（`splitAuthors` 寫；doctor 與未來 un-split 讀）；深度＝「已退役值的 reference」這個新語意；刪除測試：刪掉它，split 回到不可逆且不可偵測——不是 pass-through。

## Implementation Contract

**Behavior**：`resolve-people --split-author <citekey>:<index>:<sep>=<理由>`（與 MCP `split_author`）拆分成功後，該 work 的 `references` 多一筆 `{field: authors, value: <原 literal>, judgement: "拆為 ⟦a⟧ ⟦b⟧：<理由>"}`；`akashic get-entry` 與 MCP `akashic_get_entry` 原樣呈現它；`validate`／`doctor` 對「拆分記錄的各段全部不在作者位」與「某 verdict 的 literal 已被拆分退役」各報一種 warning。

**Interface / data shape**

- `ProvenanceReference.firstOrderRulingFields: Set<String>` ＝ `resolutionVerdictFields ∪ ["authors"]`；judgement 的 `restsOn` 為空只在 `field ∈ firstOrderRulingFields` 時合法。
- `SplitRecordValue { parts: [String], reason: String }`；`static func parse(_ statement: String) -> SplitRecordValue?`；`var encoded: String`（`拆為 ⟦a⟧ ⟦b⟧：理由`）；round-trip 逐字。
- `Entry.validateReferenceAttachment`：`field == "authors"` → value 必須非空、kind 必須是 judgement、statement 必須 `parse` 成功且 `parts.count ≥ 2`；**不**要求 value 在場；至少一段在場的檢查放在 `StoreHealth`（warning），不在 decode 期。
- `LibraryStore.assertEntryWritable`：entry 含 `field: authors` reference 且 store format < 16 → 拒寫，訊息說明要先 bump。
- `StoreVersion.supported = 16`；`docs/store-format.md` 記 16 的差異；`plugin/.claude-plugin/plugin.json` 與 `Package.swift` 的宣告同步。
- `AkashicService.splitAuthors`：寫入拆分記錄與改寫 `authors` 在同一次 `writeEntry`；報告多一欄 `recorded: true`。
- `StoreHealth.orphanedSplitVerdictPrefix = "拆分後的孤兒 verdict"`；`orphanedSplitVerdicts` 計算屬性；`LibraryStore.orphanedSplitVerdictIssues(in:)` 掃 person／organization 的 resolution verdict 對照全庫拆分記錄；另一種 warning `拆分記錄的各段都已不在作者位`（同一前綴族，訊息分開）。

**Failure modes**

- statement 解析失敗、段數 <2、理由空、value 空 → decode 期 quarantine（同其他 reference 形狀錯誤的既有語意）。
- format < 16 寫入 → `assertEntryWritable` 拒寫、零寫入。
- 孤兒 verdict／各段全不在 → warning，`validate` exit 仍 0（「掃得到」不「叫醒」，#464 的同一條界線）。
- 舊 binary（format 15）讀到 format 16 的 store → 整份拒讀（既有 format 閘語意，三 binary 同步部署）。

**Acceptance criteria**

- `Tests/AkashicKitTests/SplitRecordReferenceTests.swift`：`SplitRecordValue` round-trip 與拒絕案（段 <2、空理由、缺 `⟦⟧`）；`authors` reference 的 decode 接受／拒絕；format 15 store 寫入被拒、format 16 通過；spec 的例（`chen2020a`：`某人與雷庚玲` → `某人`／`雷庚玲` ＋ 一筆記錄）。
- `Tests/AkashicMCPTests/SplitAuthorTests.swift`（既有）補斷言：拆分後 `references` 多一筆且 value 逐字等於原 literal。
- `Tests/AkashicKitTests/OrphanedSplitVerdictScanTests.swift`：持有 `work:chen2020a :: 某人與雷庚玲` 的 person 在該 work 拆分後 → 1 筆 warning、owner 是那個 person、訊息指名 `chen2020a`；各段全不在 → 另一種 warning；乾淨 → 0；拿掉 `health(from:)` 的 append 即紅。
- `bash .githooks/run-guards.sh` 全綠（`store-marker-parity` 兩份宣告一致為 16、`zero-instance-rows-audit` 讀到新列）。

**Scope boundaries**

- In：值域擴充（僅 `authors`）、`firstOrderRulingFields`、`SplitRecordValue`、format 16、`splitAuthors` 寫記錄、孤兒與各段全不在兩種 warning、規則表、docs、changelog。
- Out：un-split 面、回填 4 筆、其他欄位的來源、`resolutionVerdictFields` 的語意。

## Risks / Trade-offs

- [format bump 打死三個 binary] → 部署順序寫進 changelog：先 release 三 binary、再 `migrate`（本張無資料遷移，只 bump marker）、再 validate；`format-bump-breaks-three-binaries` 的六步。
- [statement 內的 literal 含 `⟧`] → `⟦⟧` 是文法保留字元，`splitAuthors` 對含它的段拒絕（與 `=` 在分隔符文法的既有處置同形）；測試釘住。
- [孤兒偵測誤報：literal 相等但指的是另一筆 work] → verdict 的 holder 是 citekey，比對以 (citekey, literal) 為鍵，不只比 literal。
- [第 15 條邊「已退役值」的語意被其他欄位類推] → spec 的 requirement 明寫只有 `authors` 一格；`validateReferenceAttachment` 的 `default` 分支照舊拒絕其他 field。

## Migration Plan

無資料遷移。部署：三 binary 同步 release → store marker bump 16（`akashic migrate` 的既有 bump 路徑）→ `validate`。回滾：revert PR 並把 marker 退回 15——若已有拆分記錄寫入，format-15 binary 會 quarantine 那些 entry（可預期、可見），這是不回滾 marker 的理由。

## Open Questions

- un-split 面的形狀（收 citekey＋記錄 index？把各段合回原 literal 並刪除多出的作者位）——另開 issue 時裁。
