## 1. Name equality used for judgement SHALL admit no false positives

實作 `NameIdentity.canonical(_ s: String) -> String` 與 `NameIdentity.same(_ a: String, _ b: String) -> Bool`（Implementation Contract 的前兩節）。

- [x] 1.1 依 **D1：判準的收錄條件是「必然」不是「通常」**，新增
  `Sources/AkashicCore/NameIdentity.swift`：`canonical(_:)` 做 NFC → trim 前後空白 →
  內部空白串收斂為單一 U+0020；**不做** NFKC、大小寫摺疊、連字號映射、字元刪除。
  另提供 `same(_:_:)`。檔頭鐵律寫明方向（判定用、零假陽性），並與
  `NameNormalization`（配對用、容許假陽性）互相指認。
  **驗收**：`NameIdentityTests.testCanonicalCollapsesWhitespaceOnly` 斷言三個變換各自
  生效，且 `testCanonicalIsIdempotent` 斷言 `canonical(canonical(x)) == canonical(x)`。

- [x] 1.2 依 **D2：大小寫摺疊刻意不收——這是本設計最容易被「順手加上」的一項**，加一條**反向**測試釘住它不被順手加上：
  `"Macdonald"` 與 `"MacDonald"` 在 `same` 下為 false。理由寫在測試 doc 內
  （拉丁上是機率判斷、CJK 上是 no-op——用假陽性風險換對主要書寫系統無用的便利）。
  **驗收**：`testCaseFoldingIsDeliberatelyExcluded` 通過。

- [x] 1.3 依 **D4：判準放 `AkashicCore` 的新檔，不放進 `NameNormalization`**
  ——兩者語意相反，放同檔會讓下一個人拿錯。在 `NameNormalization` 檔頭加一句交叉指認。
  **驗收**：`grep -c "NameIdentity" Sources/AkashicCore/NameNormalization.swift` ≥ 1。

## 2. 三個站點接上：`AuthorizedName.validateDisjointPartitions` 與 merge 去重（`DivergenceResolve`）

- [x] 2.1 `AuthorizedName.validateDisjointPartitions` 的互斥判定改用 `NameIdentity.same`。
  **驗收**：`testTrailingWhitespaceDoesNotEscapeDisjointCheck` —— `"謝叔蓉"` 與
  `"謝叔蓉 "` 分居兩分割時被報為重疊（先前穿透）。

- [x] 2.2 `DivergenceResolve` 的 merge 去重（`incoming` 的過濾）改用 `NameIdentity.same`。
  **驗收**：`testMergeDedupUsesJudgementCriterion` —— keeper 有 `"Li  Ming"`、doomed 有
  `"Li Ming"` 時不重複加入。

## 3. Near-duplicate names SHALL be surfaced rather than silently kept apart

實作 `AuthorizedName.validateNearDuplicates(names:ownerKey:) -> [ValidationIssue]`。

- [x] 3.1 依 **D3：近重複的處置是 warning 而非 error**，新增
  `AuthorizedName.validateNearDuplicates(names:ownerKey:)`：對 `names.all` 兩兩比較，
  `matchingKey` 相同**且** `NameIdentity.same` 為 false → 一條 `severity: .warning`，
  訊息列出兩個名字。**不擋寫入**——那兩個名字可能真的不同。
  **驗收**：`testNearDuplicateIsSurfacedAsWarning` —— `"Chang, Y-H."` 與
  `"Chang, Y‐H."`（U+2010）觸發 warning 且記錄仍可寫入。

- [x] 3.2 不相關的名字不得誤報。
  **驗收**：`testUnrelatedNamesDoNotTriggerNearDuplicate` —— `"鄭澈"` 與 `"Che Cheng"`
  零 warning（`matchingKey` 也不匹配）。

- [x] 3.3 把新檢查接進 `Person.validate()`（與既有兩條內容約束並列）。
  **驗收**：對含近重複的 person 跑 `validate()` 回傳含該 warning。

## 4. 對真 store 實測（D3 的 Risk 條目）

- [x] 4.1 對 `~/.akashic` 跑 `akashic validate`，記錄近重複 warning 的實際筆數。
  若數量大，該數字本身是 `#303` campaign 的發現而非本變更的缺陷——寫進結案摘要。
  **驗收**：結案摘要含實測筆數。

## 5. 收尾

- [x] 5.1 全套 `swift test` 通過。
- [x] 5.2 `spectra validate add-name-identity-criterion` 通過。
