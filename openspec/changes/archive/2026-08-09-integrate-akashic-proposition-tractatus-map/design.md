## Context

目前工作區的 Tractatus 正典與工具尚未提交，main 又比 origin/main 落後兩個 commit。遠端 e16c6f6 是已合併的命題語意垂直切片；另一個遠端 commit 與本變更無關。直接 pull 或 merge 會把使用者既有修改與無關變更一起帶進來，也違反本次已確認的 Git 邊界。

e16c6f6 新增三個 AkashicProposition 原始碼檔、一個 18 項測試檔與三行 SwiftPM 宣告。現有 Tractatus 語料仍有 24 筆 aspirational 關係，而且多數沒有 issue 歷史；其中命題 5 的真值函數願景與新垂直切片只有部分重疊。獨立稽核另發現兩個必須明載但不應偷偷改寫來源 blob 的 fail-closed 邊界：public enum case 可繞過 `makeAuthored` 的引數驗證，而 `PropositionModel` 對重複 key 採 last-wins，使輸入順序可能改變 valuation。這次必須同時避免三種錯誤：漏記已存在的能力、把三值單一 predicate 求值誇大成完整真值函數演算，以及把已知完整性缺口藏在逐位元整合之下。

## Goals / Non-Goals

**Goals:**

- 在不改動 Git 分支與索引的前提下，逐檔物化並核對 e16c6f6 的命題語意切片。
- 用正式規格固定現有公開型別、投射失敗、開放世界三值語意、問句答案空間與裁決閘門。
- 只更新能由目前原始碼、測試與規格直接證成的逐條 Tractatus 關係。
- 讓每筆 aspirational 關係至少連到一個已建立並完成 IDD diagnosis 的 issue。
- 為有效時間／store revision、明確否定、真值函數組合，以及命題建構／model identity 完整性保留四個誠實的開放工作。

**Non-Goals:**

- 不執行 pull、merge、rebase、stage、commit 或 push，不帶入 e16c6f6 以外的遠端檔案。
- 不新增 proposition persistence、codec、store schema、migration 或第二份 canonical state。
- 不把初始 authored predicate 擴張成通用三元組或完整 predicate registry。
- 不聲稱 authored 現在能產生 fails，也不把「沒有找到」壓成 false。
- 不在本變更實作有效時間、store revision、明確否定或真值函數組合。
- 不在本變更修改 e16c6f6 的 public enum API、投射／求值 refusal enum 或 `PropositionModel` 重複 key 行為；這些完整性修正須由獨立 issue 與後續 Spectra change 處理。
- 不用新 issue 取代已關閉 issue 的歷史；新 issue 只追蹤明確尚未完成的後續邊界。

## Decisions

### 以 commit blob 為整合基準而非 Git 合併

三個原始碼檔與測試檔 SHALL 直接對照 e16c6f6 的 Git blob；本機內容需逐檔具有相同 SHA-256。Package.swift 只加入該 commit 的 AkashicProposition target 與 test target 宣告，並保留目前工作區既有 Tractatus target 修改。替代方案是 merge origin/main，但它會同時帶入無關 commit 並重排使用者未提交狀態，因此否決。

### 命題語意以封閉垂直切片規格化

proposition-semantics 規格 SHALL 描述已存在的封閉 Proposition.authored、EntityRef、Projection、TruthValue、YesNoQuestion、Assertion、AcceptedFact 與 adjudicate 邊界。它不建立通用 subject-predicate-object registry。封閉 enum 讓新增 predicate 時編譯器迫使投射與問答一起更新；三值型別則使 undetermined 無法被靜默當成 false。

### 只以直接證據更新逐條關係

語料狀態只在目前程式碼、具名測試或正式 requirement 能直接支持時由 aspirational 提升為 partial 或 implemented。單一 authored predicate 的三值求值可以支持命題、投射、問答與「未定不等於假」；它不能支持完整 truth-functional composition、有效時間、store revision 或明確否定。e16c6f6 以 history commit 保留理解演進，current evidence 仍只指向工作區路徑與穩定 locator。

### 願景關係以已診斷 issue 作追蹤契約

validator SHALL 要求每筆 aspirational relation 的 history 至少有一個完整 GitHub issue URL，且路徑須恰為 owner／repo／issues／正整數，不接受額外 path component、0 或負數；同一個精確工程缺口可以被多筆相關命題共同引用。issue 由使用者指定的 IDD 2.20.0 issue 與 diagnose 流程建立並維持開啟。CI 離線只驗 URL 與結構；完成稽核另透過 GitHub 確認 issue 存在、保持開啟且已有 diagnosis，避免把網路狀態變成 corpus build 的非決定性依賴。

### 來源 blob 的完整性缺口另案追蹤

四個遠端檔案仍須與 e16c6f6 逐位元相同，不能為了順手修復而改寫其 observable API。public enum validation bypass 與 duplicate model-key last-wins 都影響同一條「不合法或歧義輸入不得產生可接受 valuation」完整性邊界，因此以一個獨立 bug issue 建立 root-cause diagnosis；本變更只記錄限制，不聲稱已修復。替代方案是直接更動 blob 並新增 refusal cases，但會違反本次可稽核的 commit materialization 契約，故否決。

## Spec-to-test 對照

| Requirement | 直接覆蓋的 `PropositionTests` |
| --- | --- |
| Authored propositions SHALL use a closed typed representation | `testMalformedKeyIsRejectedAtConstruction`、`testEmptyLiteralIsRejected`、`testWellFormedPropositionIsAccepted`、`testDirectionIsPartOfIdentity` |
| Projection SHALL preserve identity resolution and role direction | `testUnresolvedSymbolIsNotProjectable`、`testUnknownIdentityIsNotProjectable`、`testReversedArgumentsReportWrongEntityKind`、`testFullyResolvedProjects` |
| Evaluation SHALL preserve open-world uncertainty | `testUnprojectableNeverClaimsTruth`、`testSupportingEvidenceHolds`、`testLookalikeLiteralIsUndeterminedNotTrue`、`testAbsenceIsUndeterminedNotFalse`、`testAuthoredNeverReturnsFails` |
| Yes-no questions SHALL expose a tri-valued answer space | `testAnswerSpaceIncludesUndetermined`、`testAnswerMapsTruthWithoutFlattening` |
| Fact acceptance SHALL be gated from recorded assertions | `testAdjudicationRefusesUndetermined`、`testQuestionedStanceCannotBecomeFact`、`testAdjudicationAcceptsEstablishedAssertion` |

## Implementation Contract

### Observable behavior and interfaces

- SwiftPM 提供 AkashicProposition library target 與 AkashicPropositionTests test target。
- Proposition 初始只提供 authored(person:work:)；引數以 EntityRef.key 或 EntityRef.literal 表達。
- Proposition.makeAuthored 在 key 格式不合法或 literal 只有空白時拋出 PropositionError。
- Proposition.project(in:) 回傳 projected 或帶具體原因的 unprojectable；角色方向與 entity kind 不可交換。
- Proposition.evaluate(in:) 回傳 holds、fails 或 undetermined。現有 authored 規則只在作者 identity 正面吻合時 holds；找不到支持、字面尚未歸戶或無法投射時一律 undetermined，且目前沒有路徑產生 fails。
- YesNoQuestion 的答案空間固定為 yes、no、undetermined，answer(in:) 不得壓平成 Bool。
- Assertion 與 AcceptedFact 為不同型別；只有 stance 為 asserted 且求值為 holds 的 assertion 能由 adjudicate 產生 AcceptedFact。
- Tractatus validator 遇到 aspirational relation 缺少 issue history 時，回報可排序且具 record ID 的診斷並以非零狀態結束。
- strict corpus 驗證與 render --check 對更新後的 534 筆 record 成功，產生文件由 YAML 唯一決定。

### Failure modes

- blob 內容與 e16c6f6 不同時，整合驗收失敗，不以近似重寫取代來源 commit。
- 無效命題引數在具名建構邊界拋出 PropositionError。
- 無法投射、缺少支持或未歸戶字面值保留為具原因的 undetermined；不得回傳 false 或 AcceptedFact。
- aspirational relation 沒有路徑恰為 owner／repo／issues／正整數的完整 GitHub issue URL 時 corpus validation 失敗；issue 的即時遠端狀態不在離線 validator 內查詢。
- 無法合理對照的新能力維持 aspirational、analogy_only、not_applicable 或其他誠實狀態，並由 issue／理由說明，不得為提高覆蓋率而虛構 implementation evidence。

### Acceptance criteria

- 四個新增檔案分別與 e16c6f6 對應 blob 的 SHA-256 完全相等；Package.swift 具有兩個 target 宣告且保留 Tractatus 宣告。
- AkashicPropositionTests 的 18 項測試全部通過。
- 新的 aspirational-history 負向 fixture 在修正前失敗、修正後通過，涵蓋缺漏、不完整 URL、額外 path component、0、負數與錯誤 kind；正式語料中每筆 aspirational relation 都有 issue history。
- 四個後續工程邊界經 IDD 建 issue 與 diagnose，完成稽核時仍為 open；第四案明確涵蓋 direct enum construction validation bypass 與 duplicate model-key order dependence。
- 精準 mapping 稽核列出每筆被更新的 proposition ID、舊／新狀態、直接 evidence 與 history。
- warning-as-errors build、完整 Swift 測試、strict validate、連續兩次 deterministic render、render check、source asset digest、Spectra validate 與 git diff --check 全部通過。

### Scope boundaries

本變更只物化 e16c6f6 的命題語意切片、補規格與測試契約、更新 Tractatus 對照及建立後續 issue。它不授權 Git 寫入操作、遠端發佈、store migration、額外 predicate、持久化格式或後續 issue 的功能實作。

## Risks / Trade-offs

- [Risk] 手動物化 commit 容易抄寫漂移 → 以每檔 SHA-256 與 Git blob 逐一比對，任何差異都阻擋驗收。
- [Risk] Package.swift 同時含使用者既有修改 → 只套用三行語意 target 差異，完整保留其他工作區內容。
- [Risk] 新型別被過度解讀成完整邏輯引擎 → 正式 spec 與逐條 status 明載 authored-only、open-world 與 no-fails 邊界。
- [Risk] 多筆 aspirational 關係共用 issue 失去細節 → 只讓同一精確工程缺口共用 issue，每筆 relation 仍保留命題特定 claim 與 rationale。
- [Risk] issue 遠端狀態使 CI 不穩定 → YAML validator 只做離線結構檢查，遠端 open／diagnosed 狀態留給一次性完成稽核。
- [Risk] 歷史 commit 被誤當 current evidence → commit 只放 history；current evidence 持續以本機 path 加穩定 locator 驗證。

## Migration Plan

1. 先以失敗測試固定 aspirational issue-history 契約。
2. 物化 e16c6f6 的四個檔案並合併最小 Package.swift 宣告，逐檔核對 digest。
3. 建立並診斷四個後續 issues，取得穩定 URL；完整性 issue 不在本次改寫來源 blob。
4. 依直接證據更新受影響 relation 與全部 aspirational history，重新產生 Markdown。
5. 執行完整驗收；失敗時只回復本變更新增內容，不改動使用者既有 Git 狀態。

## Open Questions

無。持久化、有效時間、明確否定與真值函數組合已明定為後續 issue，不阻擋本垂直切片的精準整合。
