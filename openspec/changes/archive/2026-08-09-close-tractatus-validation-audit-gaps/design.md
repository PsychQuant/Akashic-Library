## Context

`SourceManifestValidator` 目前把 snapshot 解析成以 proposition ID 為 key 的 dictionary；只要 dictionary 非空，就視為結構可解析。當 construction mode 尚無 corpus volume 時，沒有後續逐筆 fidelity 迴圈，因此只含一個合法 heading 的 digest-matching snapshot 會通過。dictionary 同時遺失 heading 順序並覆蓋重複 key。即使初步分別保留序言與正文順序，先串接序言再串接正文仍會把兩種 heading 的全域實際位置正規化，讓正文出現在序言之前的 snapshot 假綠。

`CorpusValidator.validateHistory` 對 commit 會呼叫 Git，但對 branch 只檢查字元集合。把 branch 改成任意 `rev-parse <reference>^{commit}` 仍不足，因為 SHA、tag 與 `HEAD` 也能 peel 成 commit。`validateChineseContent` 只拒絕空值、placeholder、相同欄位與三種樣板，純英文 filler 仍能滿足目前條件；以粗略碼位區間補強則會漏收 Unicode 17 Extension J，也會納入相容表意文字區塊中的未指派 gap。

## Goals / Non-Goals

**Goals:**

- 在任何 corpus construction 狀態下，都以 manifest inventory 精確驗證 inline snapshot 的完整、有序且唯一 passage 結構。
- 讓不存在或不屬於 local／remote-tracking branch namespace 的 history reference 無法通過 strict validation。
- 讓 `translation_zh_tw` 與 `interpretation_zh_tw` 至少具有可機械驗證、排除未指派碼位的漢字內容下限。
- 保持正式 snapshots 與 source assets bytes 不變；只修正 strict validation 揭露的兩個公式型中文譯文，並由正典 YAML 重產 generated Markdown。

**Non-Goals:**

- 不以程式自動判定翻譯是否哲學正確，也不宣稱 Unicode 漢字檢查能區分所有正體／簡體用字。
- 不要求歷史 commit 或 branch 必須是目前 `main` 的 ancestor；`rejected` history 合法地容許未合併脈絡。
- 不 fetch 遠端 refs，不依賴網路，不更改 Git branch 或 commit 狀態。

## Decisions

### Snapshot parse result retains ordered IDs and passages

parser 回傳每個 passage 的 ID、文字與其在同一原始 snapshot 中的 `String.Index`，再依絕對位置產生 `orderedIDs` 與 `passagesByID`。序言與正文等不同 heading grammar 必須先合併位置再排序，不能以 parser 類別決定先後。如此可分別偵測缺漏／額外、重複、同類重排與跨類重排。替代方案是在 dictionary 完成後只比較 key set，或固定先串接序言再串接正文；兩者都會遺失真實全域順序，因此拒絕採用。

### Manifest inventory is the snapshot structure oracle

每個 inline edition 的預期順序直接取 `manifest.scope.inventory`。主 validator 已以固定 fingerprint 驗證該 inventory，因此 source validator 不另維護第二份 534-ID 常數。替代方案是從已載入 volumes 推導；零卷時沒有 oracle，正是目前假綠的來源。

### Branch history resolves through local Git only

branch reference 只可對應 `refs/heads/<reference>` 或 `refs/remotes/<reference>`，也接受已寫成這兩種完整 ref 的值；其他 `refs/` namespace 直接拒絕。每個候選再以本機 Git 驗證能 peel 成 commit，並保留每個 reference 的 cache。解析失敗回報 `unknown-branch`；不 fetch、不檢查 ancestor。任意 commit-ish 解析會讓 SHA、tag 與 `HEAD` 冒充 branch，因此否決；只接受 `refs/heads/` 則會拒絕合法 remote-tracking branch，也不採用。

### Han-script presence is a structural floor, not semantic review

兩個 `zh_tw` 欄位各自必須含至少一個已指派的 Unicode 漢字 scalar。判定以 `isUnifiedIdeograph` 為核心，明確接受 U+3007；相容表意文字只在對應區塊且 `isIdeographic` 為真時接受，以排除未指派 gap；另精確涵蓋 Unicode 17 Extension J 的 U+323B0...U+33479，讓較舊 Unicode runtime 仍具相同下限。此規則能拒絕純英文、純 placeholder filler 與未指派 scalar，又不假裝自動評分正體字或哲學品質。正體用字與論旨忠實度仍由逐句人工稽核與 corpus review 負責。

正式語料中的 `5.101.l` 與 `5.101.m` 原本只以公式字母 `p`／`q` 表達工作譯文。它們保留全部公式內容，但分別改寫成「命題 p」與「命題 q」，使欄位確實是中文工作譯文，而不是為通過驗證任意塞入無關漢字。generated Markdown 必須由這兩筆 YAML 變更決定性重產。

## Implementation Contract

- `SourceManifestValidator.validate` 在 digest-matching inline snapshot 的 ordered passage IDs 與 `manifest.scope.inventory` 不完全相等時，必須在任何 `volumes` 數量下回傳 edition-level `source-mismatch`。缺漏、額外、重複、同類亂序與序言／正文跨類亂序皆屬不相等。
- 正式兩份 inline snapshots 的 534 筆結構必須繼續通過，corpus fidelity 比對仍使用相同 passage text。
- `CorpusValidator.validateEvidence` 遇到格式合法但本機 Git 無法解析的 branch reference，或 reference 實為 SHA、tag、`HEAD` 或其他非 branch namespace 時，必須回傳 `unknown-branch`；可解析的 local 或 remote-tracking branch 必須通過。
- `CorpusValidator.validateAlignment` 遇到不含任何已指派 Han ideograph 的 `translation_zh_tw` 或 `interpretation_zh_tw` 時，分別回傳 `missing-translation` 或 `missing-interpretation`；Unicode 17 Extension J 與已指派相容表意文字必須通過，未指派相容區塊 gap 必須失敗。
- regression tests 必須先在舊 production code 上以預期 diagnostic 缺失而失敗，再以最小 production 修正轉綠；正式 corpus 若被新規則正確拒絕，必須修正實際欄位內容，不得放寬 validator。
- 驗收命令包含 targeted SourceManifest／CorpusValidation tests、全部 Tractatus tests、strict validate、render `--check`、正式 snapshot 與 generated SHA-256 比對。

## Risks / Trade-offs

- [Risk] 純公式可能沒有漢字可寫。→ [Mitigation] 本次 strict validation 實際找出 `5.101.l`、`5.101.m`；以「命題 p／q」作最小且忠實的中文表述。若未來確有不能中文化的純公式需求，必須以新的顯式 schema 狀態與規格情境處理，不以任意英文 filler 放寬。
- [Risk] Git branch 名稱可能被遠端刪除。→ [Mitigation] 歷史承重引用優先使用 immutable commit；branch 僅保存可在目前 checkout 稽核的討論脈絡。
- [Risk] 額外結構診斷與 corpus fidelity 診斷同時出現。→ [Mitigation] 保持 deterministic sorting，結構不符時停止該 edition 的逐筆重建，避免大量衍生噪音。
