<!--
Each task description MUST state:
- the behavior or contract being delivered (what is observably true when the
  task is complete), and
- the verification target that proves completion (test, CLI invocation,
  analyzer check, manual assertion, or content review).

File paths are supporting context for locating the work, never the task
itself. "Edit file X" is not a valid task — it is missing both behavior and
verification.
-->

## 1. Snapshot 結構完整性

- [x] 1.1 依 `Snapshot parse result retains ordered IDs and passages` 與 `Manifest inventory is the snapshot structure oracle` 落實 `Every edition SHALL have auditable provenance and reproduction rights`：先加入 digest-matching partial、duplicate、同類 reordered 與正文出現在序言之前的跨類 reordered snapshot，全部以 `volumes: []` 重現；執行 targeted `SourceManifestTests` 證明舊碼缺少 `source-mismatch` 而紅燈；再保留每段的全域原始位置、依位置產生 ordered IDs 並與 manifest inventory 精確比較，重跑測試至全部通過。

## 2. 臺灣正體中文欄位下限

- [x] 2.1 依 `Han-script presence is a structural floor, not semantic review` 落實 `Every aligned segment SHALL contain separate Traditional Chinese translation and interpretation`：先以不同的純英文 translation／interpretation fixture 證明舊碼假綠，再加入已指派 Unicode Han scalar 檢查，使用 `CorpusValidationTests` 驗證兩欄各自回報 `missing-translation`／`missing-interpretation`，並以 Unicode 17 Extension J、已指派相容表意文字與未指派 U+FA6E 正反例防止粗略 range 假綠／假紅；對 strict validation 揭露的 `5.101.l`、`5.101.m` 公式型譯文只補成忠實的「命題 p／q」，驗證正式 1,186 segments 全部通過。

## 3. Branch history 可解析性

- [x] 3.1 依 `Branch history resolves through local Git only` 落實 `Current evidence and historical context SHALL remain separate`：先加入格式合法但不存在 branch 的 fixture 並確認舊碼未回報 `unknown-branch`，再以本機 Git 與 cache 驗證 `refs/heads/`／`refs/remotes/` branch namespace；使用 UUID 正負向 `CorpusValidationTests` 證明不存在 branch、SHA、tag 與 `HEAD` 都 fail-closed，而非 `main` ancestor 的 local branch 及 remote-tracking branch 不需網路即可通過。

## 4. 完工閘門

- [x] 4.1 對三個 red-green cycle 做 mutation review，並執行 targeted tests、全部 `TractatusDocsTests`、fresh warnings-as-errors build、完整 Swift tests、strict validate、兩次 render byte comparison、render `--check`、41 份 `SHA256SUMS`、正式來源 aggregate SHA、`spectra validate close-tractatus-validation-audit-gaps`、`spectra analyze close-tractatus-validation-audit-gaps` 與 `git diff --check`；只有全部 exit 0、正式 snapshots／assets bytes 未改寫、corpus 只含 `5.101.l`／`5.101.m` 的兩筆最小譯文修正且 analyzer 無 Critical／Warning 才可封存。
