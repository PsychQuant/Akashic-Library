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

## 1. 來源結構與外部版本權利

- [x] 1.1 依 `Snapshot structure validation independent of corpus` 落實 `Every edition SHALL have auditable provenance and reproduction rights`：先在 `SourceManifestTests` 加入零卷、digest 正確但結構不可解析的 inline snapshots fixture，執行該測試確認舊碼未回報 `source-mismatch` 而紅燈，再讓 snapshot 結構解析不依賴 `volumes` 並重跑該測試至通過。
- [x] 1.2 依 `Exact external-reference token` 落實同一 requirement：先加入把 Pears／McGuinness 譯文塞入 `edition_references` 的 fixture，確認 production validator 未回報 `license-violation` 而紅燈，再以 owner record 的固定 canonical reference 驗證 external value，並以 targeted test 證明合法 534 筆仍通過、自由文字被拒絕。

## 2. 結構化專案證據

- [x] 2.1 依 `Structural locator classification` 落實 `Current evidence and historical context SHALL remain separate`：先在 `CorpusValidationTests` 加入 line comment、nested block comment、ordinary／multiline／raw string 中偽造 symbol/test declaration，以及 requirement substring 的獨立反例並確認舊碼假綠；再以忽略這些 prose 區域的窄詞法檢查和 exact requirement name 修正，重跑正負向 evidence tests 至通過。

## 3. Renderer 與 validator 共用圖資語法

- [x] 3.1 依 `Shared rich-text image parsing` 補強 `Every edition SHALL have auditable provenance and reproduction rights`：先加入中文譯文／解讀與含空白 `images/` path 的缺檔、未列 checksum fixtures，確認 renderer 會產生 `<img>` 但 validator 未回報錯誤；再讓 renderer／validator 共用 parser 並掃齊所有 rich-text 欄位，以 `CorpusValidationTests`、`RenderingTests` 與既有 snapshot 證明壞圖 fail-closed 且正式 generated Markdown bytes 不變。

## 4. Construction failure 的完整診斷

- [x] 4.1 依 `Incompleteness included in validation failures` 落實 `Validation SHALL be strict, deterministic, and actionable`：先擴充 `TractatusValidationCLITests`，在同次 `--allow-incomplete` 移除 `7.yaml` 並製造 `missing-translation`，斷言兩條 `incomplete:` 與 diagnostic 均存在而確認舊碼紅燈；再讓 validation failure 攜帶排序 gaps，重跑 CLI test 證明 exit 1、gaps 在前、diagnostics 在後且 strict output 不變。

## 5. 整合與完工閘門

- [x] 5.1 對五個 red-green cycle 做 mutation review，確認移除任一 production guard 都會使對應 regression test 失敗；以 targeted `TractatusDocsTests` 82 筆以上零失敗與 `git diff --check` 證明測試不是 source-text change detector，且正式 corpus／snapshots／assets 未被改寫。
- [x] 5.2 執行 fresh warnings-as-errors build、完整 Swift tests、strict validate、兩次 render SHA-256、render `--check`、41 份 `SHA256SUMS`、`spectra validate harden-tractatus-validation-boundaries` 與 `spectra analyze`；只有全部 exit 0、generated SHA 不變且 analyzer 無 Critical／Warning 才將 change 視為可封存。
