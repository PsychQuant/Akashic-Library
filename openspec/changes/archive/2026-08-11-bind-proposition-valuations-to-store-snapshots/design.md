## Context

目前 `LibraryStore.load()` 會先後讀取 store marker、列舉四個 canonical 目錄，再逐檔解碼；`PropositionModel` 只保存 entry／person dictionary，`evaluate` 又只回裸 `TruthValue`。因此一次答案無法回答「由哪一個 store 化身、哪一版內容、在哪一天、根據哪段證據得出」，也無法保證 revision 雜湊與實際解碼的 model view 是同一份 bytes。

`StoreIncarnation` 已明確只表示 store 身分，不表示內容新舊；`StoreVersion` 只表示 schema format。`DateRange` 則保留 `YYYY`／`YYYY-MM`／`YYYY-MM-DD` 的來源精度，不能用單純字典序把粗精度邊界猜成確定日期。#205 已讓原子 proposition 與 entry／person model keys fail closed，本 change 必須延續該邊界，並為 #203／#204 提供共用 context 與 evidence result。

## Goals / Non-Goals

**Goals:**

- 讓 StoreIO 產生不可由 production caller 偽造的 store identity、內容 revision 與 immutable library snapshot。
- 讓 revision 由實際拿去解碼的同一份 captured bytes 決定，且不受檔案列舉順序影響。
- 讓所有 truth-bearing proposition API 強制使用 snapshot-bound、valid-day-bound context。
- 讓 valuation、question answer、adjudication refusal 與 accepted fact 保存同一份 context 及結構化證據。
- 以 `affiliated(person:organization:)` 落實第一個 valid-time predicate，同時保留 authored 的 snapshot-scoped、unknown-not-false 語意。
- 以名目型別分開 valid、recorded 與 accepted 三種時間角色。

**Non-Goals:**

- 不建立歷史 snapshot repository、transaction-time 資料庫或跨檔原子寫入協定。
- 不以 Git branch、Git commit、路徑、mtime 或 `StoreVersion` 代替內容 revision。
- 不加入 implicit now、mutable current-store fallback、CLI／MCP DTO 或 AcceptedFact codec。
- 不加入 #203 的否定／完備性證言，也不加入 #204 的 formula／truth-table API。
- 不宣稱一次檔案系統 capture 等同完整 reality model；它只識別這次載入的 model view。

## Decisions

### Capture stable canonical bytes once for both revision and decoding

StoreIO 新增 `StoreIdentity`、`StoreRevision`、`StoreSnapshotID`、`LibrarySnapshot` 與 `LibraryStore.loadSnapshot()`。這些 identity/revision 型別只公開讀取值，不公開 production initializer；可信建構只能來自 StoreIO。

內部 `CapturedCanonicalStore` 收集：

- `store.yaml` 的存在狀態與原始 bytes；
- 必須存在且可嚴格解析為 UUID 的 `incarnation` 原始 bytes；
- loader 實際會讀取的 `entities/`、`entries/`、`people/`、`libraries/` 下非隱藏 YAML 原始 bytes。

`.akashic/`、`sources/`、隱藏檔與非 YAML 不納入，因它們不參與 `LibraryLoad`。會被 quarantine 的 YAML 仍納入 revision，否則同一 snapshot ID 可能對應不同的載入警告或缺漏。`loadSnapshot()` 最多執行三次 capture pass，保留前一份並比較完整 path inventory 與 bytes；只要相鄰兩次完全相同，就接受較後一份（例如 `A → B → B` 於第三次接受 `B`），三次皆持續漂移則拋出 `StoreSnapshotError.changedDuringCapture`。通過後只從被接受的記憶體 bytes 解析 store format、incarnation 與所有 records，並從完全相同 bytes 計算 revision；接受後不再讀磁碟。

revision 使用 CryptoKit SHA-256，格式為 `sha256:` 加 64 位小寫十六進位。輸入以版本化 domain separator、record count、全域 UTF-8 path bytes 排序，再對每筆寫入固定寬度 big-endian path length、path bytes、content length、content bytes。identity 不混入內容 digest；`StoreSnapshotID(store:revision:)` 才同時區分「哪個 store」與「哪份內容」。

替代方案「先 `load()`、再重讀檔案算 hash」會留下 hash/model TOCTOU；以 Git commit 或 mtime 作 revision 既漏掉未提交內容，也可能在 bytes 不變時漂移，因此拒絕。單次 capture 也無法偵測多檔載入中的變動，故採有界雙趟穩定檢查。

### Keep StoreIO integration one-way

依賴方向採 `AkashicProposition -> AkashicStoreIO -> AkashicCore`。StoreIO 擁有 filesystem capture 與可信 snapshot factory；Proposition 從 `LibrarySnapshot` 建立 model/context。StoreIO 不 import Proposition，因此不形成循環，也不需要新增一個只能轉送資料的 adapter target。

`StoreVersion` 與 `StoreIncarnation` 會抽出 internal bytes parser，現有 filesystem API 轉呼叫它；`LibraryStore` 的載入迴圈則抽成可從 captured bytes 解碼的 helper。舊 `load()` 保持相容，但 production proposition context 只接受 `LibrarySnapshot`。

### Bind evaluation through one immutable valuation context

`PropositionModel(snapshot:)` 從 snapshot 的 entries、people、organizations 建立三組唯一 dictionary，並保存 `StoreSnapshotID`。既有 raw-array initializer 降為 module-internal 測試／組裝面，production caller 無法替 synthetic model 任填 revision。duplicate organization key 延續 #205 的 aggregate、排序穩定、顯示有界拒絕。

`PropositionModel.context(validAt:)` 是唯一公開 context factory。`ValuationContext` 公開 `snapshotID` 與 `validAt`，內部保存不可變 model；不提供 public memberwise initializer，所以 snapshot ID、日期與 model 不能拆配。`project`、`evaluate`、`answer` 不保留無 context overload，也不查系統時間或重新讀取 mutable store。

替代方案讓每次 evaluate 同時接 `model + revision + validAt`，會允許 caller 把任意 revision 貼到另一個 model；把 validAt 設為預設現在則無法重播。兩者都拒絕。

### Separate valid recorded and accepted time with nominal types

`ValidDay` 是 `AkashicCore` 的嚴格 Gregorian day value，只接受真實存在的 ASCII `YYYY-MM-DD`，不接受年／月精度、非法閏日或隱式現在。它也提供穩定的全序供 temporal evaluator 使用。

`RecordedTime` 與 `AcceptedTime` 是 `AkashicProposition` 的不同名目型別；第一個 vertical slice 同樣接受嚴格完整日，保留原字串。三者不是 typealias、沒有隱式 `String` 轉換：Assertion 只收 `RecordedTime`，adjudication 只收 `AcceptedTime`，context 只收 `ValidDay`。

日後若 recorded／accepted 需要時區時間戳，可各自擴充 parser，而不改變 valid-time predicate 的日精度。現在先採共同的日精度，避免把未定義的 timezone／precision 政策混入本 change。

### Treat authored as snapshot-scoped and affiliation as valid-time-scoped

`Proposition` 新增封閉 case `affiliated(person:organization:)`；`Projection` 以不同 case 表示 authored person/work 與 affiliated person/organization，維持 role direction 與 entity kind 檢查。

Core 新增 `DateRange.assess(at: ValidDay) -> TemporalContainment`，回傳 definitelyContains、definitelyExcludes、indeterminate 或 invalidEvidence，而不是 Bool。規則如下：

- bounded start/end 為 inclusive；完整日端點可直接比較。
- 年／月精度端點展開為「可能日集合」；只有所有合法展開都包含 query day 才為 definitelyContains，落在可能邊界則為 precision indeterminate。
- `start == nil` 不等於負無限；固定 valid day 下回 unknown-start indeterminate。
- `end == nil && !endedUnknown` 是 open end；query 明確晚於 start 的最晚可能日後可成立。
- `endedUnknown` 不延伸到無限遠；除非 query 正是確定的完整 start day，其他未被端點排除的日期回 unknown-end indeterminate。
- attested-only 只在某個完整 `YYYY-MM-DD` 與 query 相等時成立；相容的粗精度 observation 回 precision indeterminate。
- attested 與 start/end/endedUnknown 混用、非法端點、end 必然早於 start 都是 invalidEvidence。

affiliated 只有在 person 與 organization 投射成功、且至少一筆 resolved matching organization segment definitelyContains 時回 holds。matching literal、粗精度邊界、endedUnknown、invalid temporal evidence 或只有不相符／已排除 segments 都維持具名 undetermined；沒有 affiliation completeness witness，因此本 change 不產生 fails。organization parent/containment 永遠不能替代 person affiliation。

authored 不讀 temporal timeline，但仍必須經完整 context 求值；trace 明載 scope 為 snapshot-scoped/time-invariant，並保留 caller 指定的 validAt，避免有效時間被無聲丟棄。

### Return structured valuation evidence instead of bare truth values

`Valuation` 保存 proposition、`TruthValue`、完整 `ValuationContext` 與 `EvidenceTrace`。trace 以封閉型別保存 predicate scope、projection identity、author slot 或完整 affiliation segment（含 `DateRange`、source、note）、temporal assessment、snapshot quarantine warnings 及最終 undetermined/refusal 原因；它不靠人讀字串決定語意。

`YesNoQuestion.answer(in:)` 回具名 `AnswerResult(answer:valuation:)`。`adjudicate` 消費既有 `Valuation` 而不重新求值，先驗 assertion/valuation proposition identity，再驗 stance 與 `.holds`；成功的 `AcceptedFact` 保存同一 valuation，`notEstablished` refusal 也攜帶同一 valuation。如此 answer、fact 與 refusal 都不會在最需要稽核時降格成裸 truth。

替代方案讓 adjudication 重新讀 store 或重新 evaluate，會讓 assertion 的裁決與先前顯示給使用者的 evidence 分叉；只保存 context descriptor 則不足以在 process 內重播。故 context 內部保留 immutable model，公開面仍只曝露 snapshot ID 與 valid day。

## Implementation Contract

### Observable behavior and interfaces

- `LibraryStore.loadSnapshot()` SHALL 以 strict incarnation 與 stable captured canonical bytes 產生 `LibrarySnapshot`；相同 store bytes SHALL 得到相同 revision，canonical bytes 改變 SHALL 得到不同 revision。
- `StoreRevision.digest` SHALL 符合 `sha256:[0-9a-f]{64}`；StoreIO 以外的 production caller SHALL NOT 能任填 identity、revision 或 snapshot。
- `ValidDay`、`RecordedTime`、`AcceptedTime` SHALL 為不可互換的 public value types，且 SHALL 拒絕不是真實 Gregorian 完整日的輸入。
- `PropositionModel(snapshot:)` SHALL 拒絕 entry、person 或 organization 的重複 identity keys；三類衝突 SHALL 一次聚合且各自排序。
- truth-bearing API SHALL 只提供 `project(in: ValuationContext)`、`evaluate(in: ValuationContext) -> Valuation`、`answer(in: ValuationContext) -> AnswerResult` 與 consume-existing-valuation 的 adjudication 路徑。
- `Valuation`、`AnswerResult`、`AcceptedFact` 與 `AdjudicationRefusal.notEstablished` SHALL 保存同一 snapshot ID、valid day 與 evidence trace。
- authored 的合法正面、absence、literal 與 wrong-kind 行為 SHALL 維持 #205 之後的 open-world 契約；其 trace SHALL 明示 snapshot-scoped/time-invariant。
- affiliated SHALL 只從 `Person.profile.affiliations` 的具方向 resolved identity 與 `ValidDay` 判定；containment SHALL NOT 滿足 affiliation。

### Failure modes

- 缺席、不可讀或 malformed incarnation SHALL 拒絕 snapshot，不得退回 path identity。
- capture 在有界重試內持續變動 SHALL 拋 `changedDuringCapture`，不得回傳混合 revision/model。
- malformed proposition、duplicate model identity 與 invalid temporal evidence SHALL 與 epistemic `undetermined(noSupportingEvidence)` 分層，不得偽裝成彼此。
- 粗精度邊界、unknown start/end、非精確 attestation 與 unresolved OrgRef SHALL fail closed 為具名 undetermined，不得猜成 holds 或 fails。
- adjudication 收到不同 proposition 的 valuation SHALL 拒絕；非 asserted stance 或非 holds valuation SHALL 不產生 `AcceptedFact`。

### Acceptance criteria

- StoreIO tests SHALL 證明路徑建立順序不影響 revision、canonical bytes 變更會改 revision、`.akashic`／`sources` 變更不會改 revision、quarantined YAML 與 marker 變更會改 revision，以及兩趟漂移會重試或有界拒絕。
- Time tests SHALL 證明非法日期／閏日拒絕、粗精度 start/end、open end、endedUnknown、attested-only 與矛盾 shape 的四態結果。
- Proposition tests SHALL 證明同 snapshot/context 重播完全相等、跨 revision 可區分、同 affiliation 在兩個 valid day 得到 holds 與 undetermined，且 authored changing-validAt 只改 context、不改 truth。
- Propagation tests SHALL 證明 evaluate → answer → adjudicate 的 context／trace identity 不遺失，並證明三種時間角色不能在 compile-time API 互換。
- #205 malformed／duplicate mutation coverage、warnings-as-errors 全測試、Spectra strict validate/analyze、strict corpus validate、render check、asset digest 與 `git diff --check` SHALL 全數通過。

### Scope boundaries

In scope 是可信 snapshot identity/revision、typed time、context-bound valuation、affiliation temporal vertical slice、結果傳遞及 4.05 對照。Out of scope 是歷史 snapshot 儲存、跨檔 writer transaction、否定／完備性證言、任意 formula、CLI/MCP/codec 與通用時態邏輯。

## Risks / Trade-offs

- [Risk] 雙趟 capture 仍不是 filesystem transaction，檔案可能在兩次相同觀測之間變動又復原 → 以相同 bytes 同時計算 digest／解碼並明載 residue；真正跨檔原子性留給 generation manifest 或 writer lock。
- [Risk] 每次 snapshot 讀兩遍 canonical store，對大型 library 有成本 → snapshot 建立時計算一次，後續不同 valid day 共用 immutable model，不在每次 evaluate 重掃。
- [Risk] source-breaking API 遷移漏掉 caller → repo-wide `rg` 加 compile gate；目前 proposition caller 限於專用測試 target。
- [Risk] trace 保存 caller-controlled 文字形成顯示風險 → trace 是 typed data、不自行 render；任何未來顯示面仍須走 `displaySafe`，並以 security regression 釘住。
- [Risk] temporal precision 規則被誤當 closed-world falsity → 所有 absence／排除結果維持 undetermined，只有後續正面反證能力才能產生 fails。

## Migration Plan

1. 先封存 #205，使 canonical model requirement 成為 base spec。
2. 以 RED tests 固定 snapshot digest、typed time、temporal containment 與 result propagation。
3. 實作 StoreIO stable capture／snapshot，再把 Proposition target 單向依賴 StoreIO。
4. 遷移 model/context/evaluate/answer/adjudicate 與全部 fixture，不保留 implicit overload。
5. 加入 affiliated vertical slice、trace 與 Tractatus 4.05 evidence，執行完整閘門。
6. 若需回復，整體回復本 change；不得只恢復 context-free overload 或 synthetic revision，否則可重播契約會失真。

## Open Questions

（無）
