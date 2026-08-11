## Context

`tractatus-doc` 已能驗證完整正典並產生決定性並排文件，但完工稽核以最小 fixture 證明五條 fail-closed 邊界仍可假綠。共同根因不是正典資料錯誤，而是 validator 在「尚無 corpus」、「文字碰巧包含 locator」、「renderer 與 validator 各自解析 rich text」、「external reference 值未限縮」及「失敗只攜帶 diagnostics」等分支使用了較窄的近似條件。

這些分支跨 `SourceManifestValidator`、`CorpusValidator`、validation engine、renderer 與 CLI error boundary，且包含受著作權版本的防重製契約，因此需要在寫測試前固定共享語法與 failure shape。

## Goals / Non-Goals

**Goals:**

- 讓來源結構、權利、evidence、圖資與 construction diagnostics 在 strict 與 `--allow-incomplete` 中一致 fail-closed。
- 每個缺口都由真實 decoder／validator／CLI 的回歸測試先證明紅燈，再用最小 production change 修正。
- 保持正式 534 筆 corpus、既有 YAML schema、產生 Markdown bytes 與 public command names 不變。

**Non-Goals:**

- 不修改《邏輯哲學論》的譯文、哲學解讀或 project relation 判斷。
- 不新增 Pears／McGuinness 全文，也不新增任何線上抓取流程。
- 不把簡化詞法檢查器擴張成完整 Swift parser 或完整 CommonMark parser。
- 不修改 Akashic canonical store、App、CLI、MCP 或 index 行為。

## Decisions

### Snapshot structure validation independent of corpus

Inline snapshot 的 digest 與 authorial structure 是來源本身的不變量，必須在逐卷 fidelity comparison 之前獨立驗證。`SourceManifestValidator` 會先為每個 inline edition 解析固定序言與命題結構，即使 `volumes` 為空也執行；解析成功後才對目前已載入的 records 做逐筆回組比對。

替代方案是保留 `volumes.isEmpty` 快速返回，但這會把 construction mode 變成來源誠信繞過，因此拒絕。

### Exact external-reference token

Pears／McGuinness 欄位只保存 record 的固定版本參照：編號命題使用自身 ID，序言使用固定 `Preface paragraph N`。任何其他值都不是可稽核的 proposition reference，必須回報 `license-violation`；不得以長度、單字數或內容猜測是否為全文，避免可繞過的啟發式判斷。

替代方案是只禁止 `texts[edition]` 或只限制最大長度；前者已有實證繞過，後者仍可分段重製，因此拒絕。

### Structural locator classification

Evidence locator 先依 kind 檢查路徑，再在去除 Swift 註解與字串內容的詞法視圖上解析 declaration。`symbol` 只接受 Swift declaration identifier，`test` 只接受 `Tests/` 下的具 test 前綴函式 declaration，`requirement` 必須等於完整 `### Requirement: NAME` 的 NAME，不再使用 substring。Markdown heading 仍要求整行相等。

此方案不宣稱理解完整 Swift AST；它只建立足以排除註解、字串與較長名稱假陽性的窄結構契約。替代方案是引入 SwiftSyntax，會顯著增加依賴與建置成本，超出本修正範圍。

### Shared rich-text image parsing

Renderer 與 validator 共用同一個 Markdown image reference parser。Parser 回傳原始 alt、`images/` 相對路徑與 match range，支援既有語法中的空白但不接受跨行或右括號；renderer 以相同 match 產生已 HTML escape 的 `<img>`，validator 則掃描所有會經 rich rendering 的來源單位、中文譯文／解讀、relation claim／rationale、evidence note 與 history note。

替代方案是複製同一條 regex 到兩處；即使當下相同，未來仍可能再次漂移，因此拒絕。

### Incompleteness included in validation failures

Construction gaps 與 diagnostics 是兩個排序集合。成功時輸出 gaps 後接 validated summary；失敗時 `TractatusValidationFailure` 也攜帶排序後的 `incomplete:` 行，error description 先列 gaps、再列 diagnostics。既有只傳 diagnostics 的 initializer 保留預設空 gaps，避免影響其他呼叫端。

替代方案是在 CLI 重新掃檔案推導 gaps，會重複 validation engine 邏輯且可能產生不同排序，因此拒絕。

## Implementation Contract

- **Behavior:** malformed inline snapshot 在零卷 construction fixture 仍非零退出；external reference 非固定 record reference 回報 `license-violation`；註解／字串中的假 symbol/test 與 requirement substring 回報 `invalid-evidence`；所有 rich-text 壞圖依缺檔或 checksum 狀態回報 `broken-path`／`digest-mismatch`；混合缺卷與內容錯誤的 CLI output 同時列出 gaps 與 diagnostic。
- **Interface / data shape:** `tractatus-doc validate`、`--root`、`--allow-incomplete` 與 YAML keys 不變。`TractatusValidationFailure.errorDescription` 在 construction failure 時新增零到多行 `incomplete: KIND VALUE` 前綴；strict failure 沒有此前綴。
- **Failure modes:** 所有新增拒絕都維持 exit 1、project-relative path、單行 escaping 與決定性排序。正常正式 corpus 的 summary 與 generated Markdown SHA-256 必須不變。
- **Acceptance criteria:** 五個獨立 regression tests 必須先在舊 production code 上以預期 false negative 失敗，再於修正後通過；TractatusDocsTests、完整 Swift tests、warnings-as-errors build、strict validate、兩次 render digest、render check、41 份資產 digest 與 Spectra validate 全數 exit 0。
- **Scope boundaries:** production edits限於 Tractatus 文件工具與其測試；不修改 corpus YAML、source snapshots、source assets、Akashic runtime modules 或 GitHub issues #198–#200 的需求範圍。

## Risks / Trade-offs

- [詞法 sanitizer 誤判 Swift raw string 或巢狀註解] → 以逐字 state machine 處理行註解、巢狀區塊註解、普通／多行／raw strings，並加入註解與字串反例。
- [External reference 規則過窄] → 以固定 scope inventory 與現有 534 筆 exact-reference 契約為唯一來源，不接受自由文字 fallback。
- [Rich-text parser 改變正式輸出] → 先鎖定現有 rendering snapshot 與 generated SHA，修正後要求 byte-identical。
- [Failure output 改變既有排序] → gaps 與 diagnostics 各自排序，strict path 保持原輸出；CLI fixture 同時斷言順序與內容。
- [五個修正互相遮蔽] → 每個行為使用獨立 fixture 與測試名稱，逐一完成 red-green cycle 後再跑整組。
