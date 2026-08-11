## Context

`AkashicProposition` 以公開 enum 表示封閉的原子命題，因此編譯器可以檢查 predicate 的窮盡性；代價是呼叫端仍可直接建立帶有 malformed key 或空白 literal 的 case。現行便利 factory 會驗證，但 `project`、`evaluate`、`answer` 與 `adjudicate` 沒有在真值信任邊界重做驗證。

`PropositionModel` 目前以 last-wins 建立兩個 dictionary。若 entry citekey 或 person key 重複，衝突證據會在 dictionary 建立時消失，而同一組陣列的排列順序可改變 truth value 與裁決結果。Store doctor 的跨記錄檢查不是本模組的 proof token：公開 initializer、測試 fixture 與未來記憶體內呼叫端都能繞過它。

這個 change 是後續 valuation context、顯式否定與有限真值函數的前置條件。那些能力都必須建立在唯一且合法的原子 valuation 上，否則只會把現有歧義永久封裝進更複雜的結果。

## Goals / Non-Goals

**Goals:**

- 讓所有產生投射、真值、答案或 accepted fact 的公開路徑只接受合法命題與無歧義模型。
- 讓 malformed syntax、model ambiguity 與 epistemic uncertainty 成為不同的錯誤層。
- 讓重複鍵錯誤內容與輸入排列順序無關，並一次呈現 entry 與 person 兩類衝突。
- 保留合法輸入下既有 authored、open-world 三值與 assertion／fact 分層。

**Non-Goals:**

- 不加入有效時間、store revision、snapshot identity 或持久化。
- 不加入顯式否定、作者清單完備性證言、`.fails` 產生規則或真值函數組合。
- 不修復或自動去除全域 store 的重複記錄。
- 不新增 CLI、MCP、codec、validated wrapper 或新的 proposition predicate。

## Decisions

### Throw at the semantic boundary instead of inventing an invalid truth value

`Proposition.project(in:)`、`evaluate(in:)` 與 `YesNoQuestion.answer(in:)` 改為 throwing API。malformed proposition 直接傳遞既有 `PropositionError`，不新增 `TruthValue.invalid`、`Projection.invalid`，也不把 syntax failure 塞入 `undetermined`。

替代方案是新增 `ValidatedProposition` wrapper，但 #203／#204 即將加入 expression 層；此時先建立 wrapper 會造成兩次型別遷移。另一個替代方案是在每個結果 enum 增加 invalid case，會把輸入契約錯誤錯置成語意結果，且迫使所有未來 operator 處理一個不是真值的分支。

### Reject duplicate model keys before dictionary construction

`PropositionModel.init(entries:people:)` 改為 throwing initializer。它先對原始陣列計數，將重複 entry citekey 與 person key 各自去重、排序，再以單一 aggregate `PropositionModelValidationError` 同時回報兩組鍵。只有兩組皆為空時，才以 `Dictionary(uniqueKeysWithValues:)` 建立索引。

不採 first-wins 或 last-wins，因為兩者都讓 truth value 依賴排列順序；也不只回報第一個衝突，因為那會逼呼叫端反覆修正與重試才能看見完整問題。

錯誤的兩個 machine-readable 陣列保留完整集合；Swift-equal 但 raw Unicode spelling 不同的重複鍵，以 UTF-8 byte order 選擇穩定代表，避免 machine payload bytes 隨輸入順序漂移。`LocalizedError` 顯示面則各類只列排序後前五筆，每筆套用 `displaySafe(max: 120)`，並明示總數與未顯示筆數。錯誤型別另以 `CustomStringConvertible` 讓一般 `Error` 插值與 debug rendering 導向同一摘要，不得反射完整 raw payload。如此既不犧牲程式化修復所需資訊，也不讓大量 caller-controlled keys 形成無界輸出。

### Validate once in projection and propagate errors defensively

`project` 是 proposition 進入模型語意的最上游，因此先執行 `try validate()`。 `evaluate` 只透過 throwing `project` 取得投射；`answer` 與 `adjudicate` 再逐層 `try` 傳遞。拿掉任一中介層的錯誤傳遞都會由 direct-case regression tests 捕捉。

`YesNoQuestion` 與 `Assertion` 的 initializer 暫時保持 non-throwing：它們只保存「被問了什麼」或「來源說了什麼」，不產生真值。真正產生答案或 accepted fact 時仍必經防禦性驗證。這也保留 assertion 與 fact 的既有分層，不把「已記錄」誤等同「可成立」。

### Preserve open-world evaluation for valid canonical inputs

合法但沒有 matching author identity 的 authored proposition 仍回 `undetermined(.noSupportingEvidence)`；unresolved literal 與 unknown identity 仍沿用既有 `UnprojectableReason`。本 change 只把 malformed key、空白 literal 與 duplicate model key 移出 epistemic result，不引入 closed-world assumption。

## Implementation Contract

### Observable behavior and interfaces

- `PropositionModel.init(entries:people:)` SHALL be `throws`.
- `PropositionModelValidationError` SHALL be `Error`、`Equatable`、`LocalizedError` 與 `CustomStringConvertible`，並同時保存 `duplicateEntryCitekeys: [String]` 與 `duplicatePersonKeys: [String]`。兩個陣列 SHALL 各自為去重後的升冪排序；Swift-equal 的 canonical-equivalent spellings SHALL 以 raw UTF-8 order 選出與輸入排列無關的代表。
- `PropositionModelValidationError.localizedDescription` SHALL 對 entry 與 person 衝突各自最多顯示排序後前五筆，每筆經 `displaySafe(max: 120)`，並明示該類總數與未顯示筆數；不得截斷兩個 machine payload 陣列。一般與 debug `Error` 字串顯示 SHALL 回傳同一摘要，不得反射 typed payload。
- 合法且唯一的 inputs SHALL 建立與現行內容相同的 `entriesByKey`／`peopleByKey`。
- `Proposition.project(in:)`、`evaluate(in:)`、`YesNoQuestion.answer(in:)` SHALL be `throws`；合法輸入的成功回傳型別不變。
- `adjudicate` SHALL 保留既有 signature，並原樣傳遞 `PropositionError`；只有合法且 truth 為 `.holds` 的 asserted assertion 能產生 `AcceptedFact`。

### Failure modes

- 直接建立的 whitespace-only literal SHALL 在 project、evaluate、answer 與 adjudicate 路徑得到 `PropositionError.emptyLiteral`，不得成為 `unresolvedSymbol` 或 `undetermined`。
- malformed key 即使同時出現在手工 person／entry／author model 中，也 SHALL 拋出 `PropositionError.malformedKey`，不得得到 `.holds`。
- 任何重複 entry citekey 或 person key SHALL 使 model construction 失敗；正序、反序與其他排列 SHALL 得到相等的 aggregate error。
- Localized error 與 Swift 預設 error rendering 中所有可見的 caller-controlled keys SHALL 經 `displaySafe` 後才進入訊息；每類最多顯示五筆，完整集合只留在 typed payload。

### Acceptance criteria

- 先新增 direct malformed case 與 duplicate-key order fixtures，並確認它們在舊實作下失敗。
- targeted `AkashicPropositionTests` SHALL 覆蓋四條 truth-producing 路徑、person／work 兩個角色、兩類 duplicate key、同時兩類重複、正反序、canonical-equivalent raw bytes、localized／一般／debug 顯示消毒與大量衝突的固定顯示上限，以及 malformed key 搭配同 malformed model。
- mutation check SHALL 證明移除 `project` 的 validation 或恢復 `uniquingKeysWith` 時至少一項新測試失敗。
- 既有合法 fixture 只需加入 `try`，其 Projection、TruthValue、Answer 與 AcceptedFact assertions SHALL 保持不變。
- warnings-as-errors build、完整 Swift test、Spectra analyze／strict validate、Tractatus corpus validate／render check 與 `git diff --check` SHALL 全數通過。

### Scope boundaries

In scope 僅限 proposition／model canonical-input validation、throwing error propagation、對應規格／測試與四筆 #205 Tractatus history 的直接證據更新。Out of scope 包含 #202 的時間與 revision、#203 的否定與反證、#204 的 formula／truth table、store 自動修復及公開 CLI／MCP。

## Risks / Trade-offs

- [Risk] 三個唯讀 API 與 model initializer 變成 source-breaking → 目前 repo 內使用點只在測試 target；同一 change 內完整遷移並以 `rg` 確認沒有漏網呼叫端。
- [Risk] 只在最下游 adjudicate 驗證，其他 API 仍會說出錯誤語意 → validation 放在 project，並為 project／evaluate／answer／adjudicate 各自建立 direct malformed regression。
- [Risk] aggregate error 直接回顯或大量列出惡意 key → `Equatable` payload 保留完整原值供程式處理，localized／一般／debug error rendering 全部導向每類只列前五筆、逐一套用 `displaySafe` 的摘要。
- [Risk] 修補時誤把合法缺席改判為 false → 保留並擴充 absence-is-undetermined 與 existing accepted-fact tests。

## Migration Plan

1. 先以 failing tests 固定 malformed 與 duplicate order 行為。
2. 實作 throwing model initializer 與 aggregate error，再遷移所有 model fixtures。
3. 實作 proposition validation／error propagation，再遷移 semantic call sites。
4. 更新規格、Tractatus evidence 與並排文件，執行完整閘門。
5. 若需回復，整體回復本 change；不得只把 initializer 改回 first／last-wins。

## Open Questions

（無）
