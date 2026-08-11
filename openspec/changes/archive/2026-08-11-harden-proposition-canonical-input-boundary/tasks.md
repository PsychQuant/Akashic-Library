## 1. TDD 失敗基線

- [x] 1.1 以 `Canonical proposition models SHALL reject ambiguous identity keys` 為契約，在 `PropositionTests` 新增 duplicate entry citekey、duplicate person key、兩類同時重複、正反序相等錯誤與唯一鍵成功案例；執行精確 test filters，確認舊 initializer 會產生至少一項 RED，並保存失敗輸出作為 false-green 證據。
- [x] 1.2 以 `Truth-bearing proposition operations SHALL reject malformed syntax` 為契約，新增 direct whitespace literal 橫跨 project／evaluate／answer／adjudicate，以及 malformed key 搭配同 malformed 手工 model 的回歸案例；執行精確 test filters，確認舊路徑會回 unprojectable／holds／fact 而非預期 error。

## 2. Canonical-input 實作

- [x] 2.1 依 `Reject duplicate model keys before dictionary construction` 決策，實作 aggregate、Equatable、LocalizedError 的 `PropositionModelValidationError` 與 throwing model initializer，使兩組重複鍵各自去重排序且不再有 first／last-wins；以 1.1 全部轉綠、正反序 error 完全相等及顯示訊息通過 `displaySafe` assertions 驗證。
- [x] 2.2 依 `Throw at the semantic boundary instead of inventing an invalid truth value` 與 `Validate once in projection and propagate errors defensively` 決策，讓 project 先驗證 proposition，evaluate／answer／adjudicate 逐層傳遞 `PropositionError`，且不新增 invalid truth／projection case；以 1.2 全部轉綠並確認四條路徑皆無法產生 semantic success 驗證。
- [x] 2.3 依 `Preserve open-world evaluation for valid canonical inputs` 決策，遷移所有合法 model 與 semantic 呼叫點使用 `try`，保持 unresolved、unknown identity、absence、answer mapping 與 AcceptedFact 的既有值；以完整 `AkashicPropositionTests` 全數通過及 repo-wide `rg` 無遺漏舊 non-throwing call site 驗證。

## 3. Tractatus 對照與產物

- [x] 3.1 逐筆更新 corpus 內四筆 #205 history 的完成邊界，加入 canonical-input source／具名測試的直接 evidence，且不把本次完整性修補誇大成有效時間、否定或完整邏輯實作；以機器擷取恰為四筆、所有 locator 可解析及 `tractatus-doc validate` 成功驗證。
- [x] 3.2 由更新後 YAML 重新產生並排 Markdown，使四筆對照完整呈現新 evidence／history；以連續兩次 render 位元組與 SHA-256 相等、`tractatus-doc render --check` 成功驗證。

## 4. 完成閘門

- [x] 4.1 執行兩個 mutation probes：暫時移除 project boundary validation，以及暫時恢復 duplicate last-wins；每個 mutation 都必須使至少一項新增測試失敗，還原後 targeted tests 必須全綠，藉此證明測試能攔截兩個 root cause。
- [x] 4.2 依 `Reject duplicate model keys before dictionary construction` 補強 aggregate error 顯示契約：typed payload 保留完整集合、canonical-equivalent spellings 選擇 byte-stable 代表、entry／person 各最多顯示前五筆且明示省略量，localized／一般／debug error rendering 都導向同一摘要，並讓 person／work 兩角色的 malformed validation 都受測試保護；以 Unicode 正反序與惡意大 payload 測試先 RED 後 GREEN、work validation 與 person 顯示消毒 mutation 各自轉紅、還原後 targeted warnings-as-errors tests 全綠驗證。
- [x] 4.3 依 Implementation Contract 的 `Observable behavior and interfaces`、`Failure modes`、`Acceptance criteria` 與 `Scope boundaries` 執行 warnings-as-errors build、完整 Swift tests、Spectra analyze／strict validate、strict corpus validate、完整 source/build-graph snapshot／asset digest、逐一涵蓋未追蹤 scope 的 no-index whitespace check 與 Git 狀態稽核；所有閘門須成功，且確認未執行 pull、merge、stage、commit 或 push、未改動 `.vscode/launch.json`，才可封存本 change。
