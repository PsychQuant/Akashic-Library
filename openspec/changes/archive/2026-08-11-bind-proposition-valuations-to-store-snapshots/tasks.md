## 1. TDD 失敗基線

- [x] 1.1 [P] 依 `Store snapshots SHALL carry trusted identity and content revision`、`Snapshot decoding and revision SHALL use the same stable capture` 與 `Store revision SHALL be deterministic and structurally framed` 建立 StoreIO RED tests，固定 strict incarnation、同 bytes 重排、canonical／excluded bytes 變動、length framing、雙趟漂移重試與有界拒絕；以精確 test filters 在尚無 `loadSnapshot()` 時編譯或 assertion 失敗驗證。
- [x] 1.2 [P] 依 `Affiliation ranges SHALL support fail-closed valid-day assessment` 與 `Valuation time roles SHALL remain nominally distinct` 建立完整格里曆日期、粗精度邊界、open end、unknown start/end、attested-only、矛盾 shape 與三種時間不可互換的 RED tests；以 Core／Proposition 精確 filters 先紅驗證。
- [x] 1.3 [P] 依 `Valuation contexts SHALL bind an immutable model view to a valid day`、`Canonical proposition models SHALL reject ambiguous identity keys`、`Projection SHALL preserve identity resolution and role direction` 與 `Evaluation SHALL preserve open-world uncertainty` 建立 context/model 拆配、organization duplicate、authored 重播與 affiliated 雙 valid-day RED tests；完整覆蓋 person／work／organization 的 literal、unknown identity、wrong-kind 精確 reason、三類 duplicate 的 backslash-heavy post-escape 固定總量上限，以及 malformed key 在 project／evaluate／answer／adjudicate 四條 API 的傳遞矩陣；以無 context fallback、錯誤 identity、顯示膨脹或任何漏傳 error 都不能通過的 compile/runtime assertions 驗證。
- [x] 1.4 [P] 依 `Valuation outcomes SHALL retain context and structured evidence`、`Yes-no questions SHALL expose a tri-valued answer space` 與 `Fact acceptance SHALL be gated from recorded assertions` 建立 evaluate → answer → adjudicate 的 trace/context identity、valuation mismatch 與 typed accepted/recorded time RED tests；以現行 bare truth／tuple API 無法滿足 assertions 驗證。

## 2. Store snapshot、revision 與 context

- [x] 2.1 依 `Capture stable canonical bytes once for both revision and decoding` 實作雙趟 `CapturedCanonicalStore` 與 bytes-based StoreVersion／StoreIncarnation／LibraryLoad 解碼，使被接受的同一份 bytes 同時驅動 model 與 digest；以 1.1 的 drift hook、quarantine inclusion 與 legacy `load()` 相容測試全綠驗證。
- [x] 2.2 依 `Store revision SHALL be deterministic and structurally framed` 與 `Observable behavior and interfaces` 實作 domain-separated、record-counted、UTF-8 path 排序及固定寬度 length-prefix 的 SHA-256 `StoreRevision`，並限制 identity/revision/snapshot production initializer；以 digest 形狀、重排相等、結構碰撞分離與內容變更測試驗證。
- [x] 2.3 依 `Keep StoreIO integration one-way` 與 `Bind evaluation through one immutable valuation context` 建立 `AkashicProposition -> AkashicStoreIO -> AkashicCore` 依賴、snapshot-only production model、organization dictionary 與不可拆配 `ValuationContext`；以 `swift package describe`、organization aggregate duplicate tests 與 API surface compile probes 驗證無循環、無 synthetic revision、無 implicit context。

## 3. 時間語意與命題結果

- [x] 3.1 依 `Separate valid recorded and accepted time with nominal types` 實作 strict `ValidDay`、`RecordedTime`、`AcceptedTime`，並依 `Treat authored as snapshot-scoped and affiliation as valid-time-scoped` 實作四態 `DateRange.assess(at:)`；以 1.2 的閏日、精度、unknown、attested 與 invalid-evidence matrix 全綠驗證。
- [x] 3.2 依 `Temporal affiliation propositions SHALL evaluate person affiliation timelines` 與 `Projection SHALL preserve identity resolution and role direction` 新增 `affiliated(person:organization:)`、predicate-specific projection 與 containment-not-affiliation 邊界；以 resolved/literal/wrong-kind/parent-relation/雙 valid-day tests 全綠驗證。
- [x] 3.3 依 `Return structured valuation evidence instead of bare truth values`、`Evaluation SHALL preserve open-world uncertainty`、`Failure modes` 與 `Scope boundaries` 實作 context-bound `Valuation`／typed trace，讓 authored 保留 snapshot-scoped open-world 行為、affiliated 對 temporal evidence fail closed；以 1.3、#205 regression 與 trace payload assertions 全綠驗證。
- [x] 3.4 依 `Valuation outcomes SHALL retain context and structured evidence`、`Yes-no questions SHALL expose a tri-valued answer space` 與 `Fact acceptance SHALL be gated from recorded assertions` 遷移 answer/result/assertion/adjudication，使成功 fact 與 notEstablished refusal 保存同一 valuation，且 mismatched proposition 被拒絕；以 1.4 全綠驗證。
- [x] 3.5 移除所有 context-free truth overload 並遷移 repo 內 Proposition 呼叫點，使 `Acceptance criteria` 所要求的同 snapshot 重播、跨 revision 區分、changing-validAt authored regression 與三種時間角色全部成立；以 repo-wide `rg`、warnings-as-errors `AkashicPropositionTests` 與 StoreIO tests 驗證。

## 4. Tractatus 對照與產物

- [x] 4.1 更新 4.05 YAML 的 #202 current evidence／history 與完成邊界，只將 snapshot revision、valid-time affiliation、typed context 與 trace 的直接證據寫入 partial 關係，並由 YAML 重產並排 Markdown；以 locator 檢查、精確 #202 reference、連續兩次 render SHA-256 相等、strict corpus validate 與 `render --check` 驗證。

## 5. 完成閘門

- [x] 5.1 執行 mutation probes：固定 revision、讓 hash/decode 二讀、忽略 validAt、把 unknown end 當無限、丟棄 answer/fact trace 與繞過 organization duplicate 各自必須使至少一項新增測試失敗；還原後 targeted warnings-as-errors tests 全綠，以證明 root contracts load-bearing。
- [x] 5.2 依 `Observable behavior and interfaces`、`Failure modes`、`Acceptance criteria` 與 `Scope boundaries` 執行 warnings-as-errors build、完整 Swift tests、Spectra analyze／strict validate、strict corpus validate／render check、source asset digest、`git diff --check`、scope／Git 狀態稽核及獨立 audit；所有閘門成功且未改動無關使用者檔案後才可封存本 change。
