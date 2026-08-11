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

## 1. 型別與命令邊界

- [x] 1.1 落實「單一深介面：`TractatusDocs`」：在 `Package.swift` 新增 `TractatusDocs` library、`tractatus-doc` executable 與 `TractatusDocsTests`，讓 executable 只負責參數解析、所有 corpus 行為由 library 擁有；以 `swift build -Xswiftc -warnings-as-errors` 與一個可執行的 `swift run tractatus-doc --help` 驗證。
- [x] 1.2 落實「分卷 YAML 與命題／句段雙層模型」及 `Corpus records SHALL use stable hierarchical identifiers`：在 `Sources/TractatusDocs/Corpus.swift` 建立封閉型別、嚴格 unknown-key decode、數字階層 ID 與多版本 alignment shape；以 `CorpusValidationTests` 驗證合法 many-to-many fixture、unknown key、invalid ID 與非字典序命題排序。
- [x] 1.3 落實「正典邊界與來源版本」及 `Every edition SHALL have auditable provenance and reproduction rights`：解析 edition role、bibliography、revision、digest、copyright 與 inclusion mode，inline 必須有 snapshot、external reference 禁止全文；以 `SourceManifestTests` 驗證 digest match、digest mismatch 與 `license-violation`。

## 2. 完整性與證據驗證

- [x] 2.1 落實「Fail-closed 完整性與來源誠信驗證」的 scope／樹狀結構層，滿足 `The corpus SHALL declare an exact authorial scope`：驗證序言與命題 1–7 inventory 完全相等、ID 唯一、parent 存在、無 Russell 導論／索引；以 `CorpusValidationTests` 覆蓋 `missing-proposition`、`extra-proposition`、`duplicate-id`、`missing-parent`。
- [x] 2.2 落實 `Alignment SHALL cover every inline source unit exactly once` 與 `Every aligned segment SHALL contain separate Traditional Chinese translation and interpretation`：檢查每個 inline index 恰好一次、2↔1／1↔2 確為版本句界而非任意切字、中文工作譯文與解讀分欄且無裝飾過的 placeholder；以 `CorpusValidationTests` 覆蓋 `alignment-gap`、`alignment-duplicate`、`alignment-granularity`、`missing-translation`、`missing-interpretation`。
- [x] 2.3 落實「雙軸專案關係與證據」及 `Every proposition SHALL state at least one explicit project relation`：驗證 status／mode 封閉集合、claim／rationale、`not_applicable` 理由與其他狀態的 current evidence；以 `CorpusValidationTests` 覆蓋全部 enum、`invalid-relation` 與 `missing-evidence`。
- [x] 2.4 落實「`main` 現況與歷史脈絡分層」及 `Current evidence and historical context SHALL remain separate`：current evidence 驗證 project-relative path 與穩定 symbol，history 驗證 disposition 與本機 Git commit，並拒絕 generated file 作承重證據；以 `CorpusValidationTests` 覆蓋 `broken-path`、`missing-symbol`、`unknown-commit`。
- [x] 2.5 落實 `Validation SHALL be strict, deterministic, and actionable` 的 `Observable commands` 與 `Error contract`：`validate` 支援 strict 與 `--allow-incomplete`，錯誤以 `path:record-id:error-code: message` 聚合排序且不洩漏絕對路徑，並拒絕卷檔名互換、裝飾過的 TODO／TBD 與正規化後的禁止證據路徑；以 executable integration test 與兩次相同輸入的 stdout/stderr byte comparison 驗證 exit status、計數與排序。

## 3. 決定性文件產生

- [x] 3.1 落實「決定性四欄 Markdown」及 `Markdown rendering SHALL be derived and byte-deterministic`：`Sources/TractatusDocs/Rendering.swift` 固定輸出德文、Ogden／Ramsey、Pears／McGuinness、臺灣正體中文四欄，external edition 顯示版本參照，並呈現句段解讀、project relations、evidence 與 history；以 `RenderingTests` snapshot、HTML escaping 與連續兩次 SHA-256 相同驗證。
- [x] 3.2 完成 `render` 的原子寫入與 `render --check` 無寫入 drift 偵測：相同內容 exit 0、不同內容回報 `generated-drift` 且原檔 bytes 不變；以 `RenderingTests` 的 temp-directory fixture 驗證成功、drift 與 I/O failure。

## 4. 正典來源與逐卷語料

- [x] 4.1 建立 `docs/tractatus/sources.yaml`、兩份允許 inline 的離線 source snapshots、圖式資產與 `docs/tractatus/README.md`，使 digest、scope inventory、獻詞／題辭 metadata、Pears／McGuinness external-reference 規則可離線稽核；以 `SourceManifestTests`、圖資 `SHA256SUMS` 與 `swift run tractatus-doc validate --root docs/tractatus --allow-incomplete` 驗證來源層零錯誤。
- [x] [P] 4.2 完成 `docs/tractatus/corpus/preface.yaml` 的全部序言段落：每個來源單位皆對齊、具臺灣正體中文工作譯文與逐句哲學解讀，每段至少一筆誠實 project relation；以 incomplete validate 不回報 `preface.*` 缺漏或內容錯誤，並人工比對 source snapshot。
- [x] [P] 4.3 完成 `docs/tractatus/corpus/1.yaml` 的全部命題與句段，包含工作譯文、解讀、status／mode、current evidence 與必要 history；以 incomplete validate 不回報 `1*` 缺漏、alignment 或 evidence 錯誤，並人工比對 source snapshot。
- [x] [P] 4.4 完成 `docs/tractatus/corpus/2.yaml` 的全部命題與句段，對 object／Sachverhalt／Bild 的術語選擇保持一致且不把 Akashic entity 冒充 simple object；以 incomplete validate 不回報 `2*` 錯誤，並在 generated preview 人工檢查代表命題 2.01、2.12、2.202。
- [x] [P] 4.5 完成 `docs/tractatus/corpus/3.yaml` 的全部命題與句段，對 sign／symbol／logical syntax／projection 的翻譯與專案對照附可解析證據；以 incomplete validate 不回報 `3*` 錯誤，並人工檢查 3.1431、3.1432、3.323、3.333。
- [x] [P] 4.6 完成 `docs/tractatus/corpus/4.yaml` 的全部命題與句段，區分 proposition、picture、sense、truth condition、saying／showing 與 query；以 incomplete validate 不回報 `4*` 錯誤，並人工檢查 4.01、4.0141、4.022、4.126。
- [x] [P] 4.7 完成 `docs/tractatus/corpus/5.yaml` 的全部命題與句段，對 truth-functions、logical space、推論與未來非邏輯必然性的關係避免把 Git branch 當 possible world；以 incomplete validate 不回報 `5*` 錯誤，並人工檢查 5.1361、5.4733、5.53。
- [x] [P] 4.8 完成 `docs/tractatus/corpus/6.yaml` 的全部命題與句段，明載科學、倫理、價值、神祕與語言界線對 Akashic 的不適用、拒絕或刻意不遵循處；以 incomplete validate 不回報 `6*` 錯誤，並人工檢查 6.36311、6.37、6.4、6.5、6.54。
- [x] [P] 4.9 完成 `docs/tractatus/corpus/7.yaml` 的唯一命題與句段，將沉默界線解讀為專案表示邊界而非禁止保存未知資料；以 incomplete validate 不回報 `7` 錯誤，並人工檢查其 relation rationale 未過度延伸。

## 5. 全書閘門與交付

- [x] 5.1 落實「分階段建構，最後啟用全書閘門」：全部卷完成後執行 strict validate，確認無 placeholder、inventory 差異、alignment 缺口、license 問題或失效證據；以 `swift run tractatus-doc validate --root docs/tractatus` exit 0 與完整計數作證。
- [x] 5.2 由 strict-valid YAML 產生並提交 `docs/tractatus/generated/tractatus-project-map.md`，確認四欄順序、外部版本參照、逐句解讀與命題關係皆可讀；以兩次 render SHA-256 相同及 `render --check` exit 0 驗證。
- [x] 5.3 落實 `Continuous integration SHALL enforce the complete corpus and generated output`：在 `.github/workflows/ci.yml` 的 Swift tests 後加入 strict validate 與 render check，且不使用網路抓原典；以 workflow YAML 檢查與本機執行兩條同型命令驗證。
- [x] 5.4 依 `Acceptance criteria` 與 `Scope boundaries` 執行全套完成稽核：`swift build -Xswiftc -warnings-as-errors`、`swift test`、strict validate、render check、`spectra validate add-tractatus-project-map` 全部成功，逐項核對 spec 十項 requirements 均有正式語料或測試作直接證據，並確認沒有修改 Akashic store、MCP 或 App 行為。
