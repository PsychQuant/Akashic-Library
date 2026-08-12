## 1. 命題語意垂直切片

- [x] 1.1 依「以 commit blob 為整合基準而非 Git 合併」物化 e16c6f6 的三個 AkashicProposition 原始碼檔、測試檔與最小 SwiftPM target 宣告，使工作區可建置該模組且不改變 Git 分支／索引；以四檔本機 SHA-256 對 Git blob digest 的逐檔相等檢查與 swift test --filter AkashicPropositionTests 驗證。
- [x] 1.2 依「命題語意以封閉垂直切片規格化」確認 Authored propositions SHALL use a closed typed representation、Projection SHALL preserve identity resolution and role direction、Evaluation SHALL preserve open-world uncertainty、Yes-no questions SHALL expose a tri-valued answer space、Fact acceptance SHALL be gated from recorded assertions 五項契約皆由具名測試覆蓋；以 18 項 PropositionTests 全數通過及 spec-to-test 對照表驗證，且不得把 authored-only 誇大成完整邏輯引擎。

## 2. 願景追蹤驗證

- [x] 2.1 以 TDD 先新增缺少 issue history 的 aspirational fixture 並確認舊 validator 假綠，再實作 Every proposition SHALL state at least one explicit project relation 的 issue 追蹤契約，使缺漏時回報 invalid-relation；以負向測試轉綠、合法完整 GitHub issue URL fixture 通過及診斷包含 proposition ID 驗證。

## 3. IDD 後續邊界

- [x] 3.1 依「願景關係以已診斷 issue 作追蹤契約」與「來源 blob 的完整性缺口另案追蹤」，使用使用者指定的 IDD 2.20.0 idd-issue 與 idd-diagnose，為有效時間／store revision、明確否定／否定答案、真值函數組合，以及 direct enum validation bypass／duplicate model-key order dependence 先查重後各自建立並診斷四個 open issues；以 GitHub 回讀確認每個 issue 存在、保持 open 且具有 diagnosis。

## 4. 正典資料與並排文件

- [x] 4.1 依「只以直接證據更新逐條關係」稽核全部 534 筆 records，僅對 Proposition、Projection、TruthValue、YesNoQuestion、Assertion／AcceptedFact 能直接證成的命題更新 status、evidence 與 e16c6f6 history，並替每筆 aspirational relation 加入相符 issue history；以逐筆變更清單、strict validate 的 534／2399／1186／534 計數及零缺漏 issue trace 驗證。
- [x] 4.2 由更新後 YAML 重新產生並排 Markdown，使人讀文件完整呈現新 evidence 與 history；以連續兩次 render 位元組相等、SHA-256 相等及 render --check 成功驗證。

## 5. 完成稽核

- [x] 5.1 依 Implementation Contract 的「Observable behavior and interfaces」、「Failure modes」、「Acceptance criteria」與「Scope boundaries」執行 warnings-as-errors build、完整 Swift 測試、strict corpus validation、source snapshot／asset digest、Spectra analyze／validate、git diff --check 與 Git 狀態稽核；所有閘門須成功，且確認未執行 pull、merge、stage、commit 或 push、未改動 .vscode/launch.json，才可封存本變更。
