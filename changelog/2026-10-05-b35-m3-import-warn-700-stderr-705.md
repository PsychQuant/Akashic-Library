# 2026-10-05 b35：匯入遇到讀不懂的 `.gitignore` 改成警告後繼續（#700）；結束碼 0 而之後的寫入沒套用時 stderr 多印一行（#705）

兩則都是使用者 2026-10-05 的裁決，原文在各 issue 最新一則 Decision comment。#700 只處理裁決第 1 項（第 2 項「symlink 一律不改寫、硬連結拒絕、
唯讀拒絕、含 NUL 算非文字、100 MiB 以上不讀不寫」是接受現狀，沒有程式改動）。

## 1. #700：匯入改成警告後繼續

**裁決**：兩個匯入（含 `dry_run`）遇到讀不懂的 `.gitignore` 先前拒絕，改成警告後繼續（同 `doctor`）。匯入本身不寫 `sources/`，擋住第三方存檔進版控的
防線仍在 `store-source`。

**`ensureLayout` 的呼叫者與各自的政策**（`SourcesIgnorePolicy`，2026-10-05 全部呼叫者；`grep -rn "ensureLayout\|openOrCreateStore" Sources`）：

| 寫入面 | 之前 | 之後 |
|---|---|---|
| CLI `file add`（`FileCommands.swift`，直接呼叫、預設參數） | `.refuse` | `.refuse`（不變） |
| CLI `doctor`（`openOrCreateStore(sourcesIgnore: .report)`） | `.report` | `.report`（不變；文字改由共用函式產生，位元組不變） |
| CLI `import-zotero`（`openOrCreateStore`） | `.refuse`（預設） | **`.report`**，warning 印到 stderr |
| MCP `akashic_import_zotero`（`AkashicService.importZotero`） | `.refuse`（預設） | **`.report`**，回應鍵 `gitignoreWarning` |
| MCP `akashic_import_wos`（`AkashicService.importWoS`，含 `dry_run`） | `.refuse`（預設） | **`.report`**，回應鍵 `gitignoreWarning` |

檢查過、不經 `ensureLayout` 的：CLI `import-wos`（`openStore`，開既有 store、不建佈局、不碰 `.gitignore`——早於 #700 的有記錄差異，不變）；
`store-source`（CLI 與 MCP，`openStore`／既有 store）；MCP `akashic_doctor`（不建佈局）、`akashic_files`；App（`AkashicAppKit` 沒有呼叫者）。
`ensureLayout` 的預設參數仍是 `.refuse`（fail-closed 的預設，`file add` 靠它）。

**一份文字**：`SourcesIgnoreProblem.warningLines(by:note:)`——一行說明（`⚠ .gitignore 沒有 sources 排除區塊，<命令> 沒有改寫它：<原因>。<處置>：`）
加上要自己加的那段（每行縮排四格）。`doctor` 印到 stdout（與先前逐位元組相同）；`import-zotero` 印到 stderr，在讀 zotero.sqlite 之前印（之後的
失敗吞不掉它）；MCP 的兩個匯入以換行接起來放進 `gitignoreWarning`。匯入多一句 `SourcesIgnoreProblem.importContinuedNote`：「匯入照常完成（匯入
不寫 sources/）；store 在 git 工作樹裡時，sources/ 沒被排除之前 store-source 拒絕寫入。」（`store-source` 的 git 驗證在 store 不在 git 工作樹裡時
跳過——那時沒有版控可言，句子照實說條件。）

**MCP 的鍵**：`gitignoreWarning`，只在 `.gitignore` 有問題時出現；`akashic_import_zotero` 在 index rebuild 失敗時錯誤訊息裡的報告也帶它，
`akashic_import_wos` 在 rebuild 失敗時錯誤訊息末尾附上同一則。MCP 的 `akashic_doctor` 沒有既有的鍵可沿用（它不建佈局、不看 `.gitignore`），
所以鍵名是新的。**說明沒有改**：`tools/list` 58,949 → 58,949 bytes（±0）。payload 鍵守衛（`ToolPayloadKeyGuardTests`）以 advisory 具名豁免這個鍵——
理由與 `mcp-cli-parity` 那兩格先前的「有記錄的缺席：MCP 說明不寫這些拒絕」同一個：位元組預算，值自己說出原因並附要加的那段；匯入照常完成，呼叫端
不依它分支。兩個新的 payload 情境（兩個匯入各一個，換上 Latin-1 `.gitignore`）讓豁免是活的（`testEveryExemptionIsLive`）。

**誠實邊界**：MCP 的匯入在 `.gitignore` 那一步之後自己擲錯（zotero.sqlite 讀不出來之類）時，回應只有那個錯誤、沒有這則 warning——佈局已建好、
`.gitignore` 沒動，下一次匯入會再說。CLI 不受影響（warning 在讀 db 之前就印了）。

**測試**：

- `ServiceTests.testImportWoSWarnsAndContinuesWithoutRewritingAnUndecodableGitignore`（取代 `…RefusesWithoutRewriting…`）：Latin-1 `.gitignore`，
  `dry_run` 帶同一則 warning、不寫 entry；實跑帶 warning、建一筆、`.gitignore` 逐位元組不變。
- `ServiceTests.testStoreSourceIsStillRefusedAfterAnImportWarnedAboutTheGitignore`：store 是 git 工作樹，匯入警告後照常完成，接著
  `storeSource` 以「sources/ 未被版控忽略」拒絕、`sources/` 沒有任何位元組、`.gitignore` 仍不動。
- `ZoteroReportCLITests.testImportWarnsOnStderrAndContinuesThenStoreSourceIsStillRefused`（真 binary）：`import-zotero` 以 0 結束、`created: 1`、
  warning 在 stderr 第一行（不在 stdout）、附上那段、`.gitignore` 不變；接著 `store-source` 非零結束、stderr 說「sources/ 未被版控忽略」、不留位元組。
- `ZoteroReportCLITests.testImportWithAWellFormedGitignorePrintsNothingOnStderr`（負面：正常的 `.gitignore` 時 stderr 是空的）。
- `ToolPayloadScenarios` 兩個 `undecodable gitignore` 情境。
- `GitignoreConcurrencyCLITests.testConcurrentImportsAreNotRefusedOverTheGitignore` 多斷言沒有假警告（`⚠ .gitignore`）——匯入不再拒絕，
  假拒絕那條斷言留著當回歸。

**負控**（反向編輯還原）：NC1 兩個 MCP 匯入與 CLI `import-zotero` 改回 `.refuse` → `testImportWoSWarnsAndContinues…`、`testStoreSourceIsStillRefused…`、
`testImportWarnsOnStderr…`、`ToolPayloadKeyGuardTests` 的 `testEveryExemptionIsLive` 與 `testEveryToolHasWorkingScenarios` 紅（5 支、10 則）。

## 2. #705：結束碼 0 時 stderr 的那一行

**裁決**：結束碼為 0、但同一個操作後續的寫入沒套用時，stderr 多印一行說明（結束碼 0 時使用者最可能不看 JSON）。

**哪些命令走得到這一格**：要在一次 CLI 呼叫裡寫同一筆兩次、第二次被 #631 拒絕（`legacyCopyLeftEarlierInThisOperation`，寫入前置標上
`laterWriteRefused`），而且那個拒絕被接住、命令仍以 0 結束。2026-10-05 逐一看過寫入者：

- `import-zotero`：**走得到**。同一趟先清 orphan 標記、再更新書目欄位（或主來源、附加來源各一步）寫同一筆；`ZoteroImporter.guardedWrite` 接住
  第二步的拒絕、不進 `writeFailed`（使用者 2026-09-30 裁決 (a)），結束碼由其他項決定。
- 逐筆收容的其他寫入者（`resolve-people`／`resolve-organizations` 的 apply 與 reject、`enrich`、`enrich-from-zotero`、`copy-zotero-attachments`、
  `migrate-provenance`）：一次呼叫裡同一筆只寫一次——resolve 族以改寫後的整組 person／entry 各寫一次，`enrich` 與 `enrich-from-zotero` 的核心
  計畫對同一個 citekey 的第二筆提案看得到第一筆會補的鍵（`--citekeys a,a` 的第二筆歸 `unchanged`），附件複製以 work 為單位。走不到。
- 多檔寫入者（rename、合併、bootstrap、`authorize-names`、移除面一族）：寫入前逐筆 preflight，每筆只寫一次；第二次寫入被拒時擲錯、以非零結束，
  走既有的 `stderrText`。
- 印 service JSON 的寫入命令（`update-person`、`update-entry`、`tag`、`link`、`set-status`、`resolve-venues`、`enrich --json`）：每筆只寫一次。

**做法**：一個函式 `LegacyCopyReport.successStderrLine(notApplied:stdoutIsJSON:)`，進入點 `AkashicCLI.main` 在命令成功之後呼叫——每一個命令都經過那裡，
今天走不到的命令日後走到時也會印，不必各自接。計數沿用 `printLines`／`printTrailer`／`payload` 三處共用的 `notAppliedOnStdout`。那一行說：
幾筆、清單在 stdout 的哪裡（文字輸出：`writtenWithLegacyCopy` 段、列尾寫「同一個操作之後對這一筆的寫入沒有套用」的那幾列；JSON 輸出：
`writtenWithLegacyCopy` 各列的 `laterWriteNotApplied`、筆數在 `writtenWithLegacyCopyNotApplied`）、要重跑——與非零結束的第一行同一句
（抽成 `LegacyCopyReport.rerunAdvice`，`stderrText` 改用它，輸出的位元組不變）。沒有沒套用的就回 nil、不印。非零結束照舊走 `stderrText`，兩條不會同時出現。

**測試**：

- `ZoteroReportCLITests.testAnExitZeroImportWithANotAppliedLaterWriteSaysSoOnStderr`（真 binary）：一筆 legacy work（`entries/` 唯讀、已 commit、
  帶 orphan 標記、Zotero 升了版）——同一趟先清標記（寫了、拷貝刪不掉），接著的書目更新被拒；以 0 結束，stderr 恰好一行，說 1 筆、清單在
  stdout 的 `writtenWithLegacyCopy` 段、確認 entities/ 那份是新的之後刪掉 legacy 那份再重跑；那一行不在 stdout。
- `ZoteroReportCLITests.testAnExitZeroImportWhoseWritesAllAppliedPrintsNothingOnStderr`（負面：沒有 orphan 標記、只寫一次，留下拷貝但沒有之後被拒的
  寫入——stderr 是空的）。
- `LegacyCopyStderrTextTests` 三支：沒有沒套用的回 nil；文字輸出的一行（恰好一行、筆數、`rerunAdvice` 與非零結束同一句）；JSON 輸出點名三個鍵。

**負控**（反向編輯還原）：NC2 進入點不印那一行（`if false, let line = …`）→ `testAnExitZeroImportWithANotAppliedLaterWriteSaysSoOnStderr` 紅（4 則）、
負面那一支照綠；NC3 `successStderrLine` 對 0 筆也回一行（`notApplied >= 0`）→ `testTheExitZeroLineIsAbsentWhenEverythingApplied`、
`testAnExitZeroImportWhoseWritesAllAppliedPrintsNothingOnStderr`、`testImportWithAWellFormedGitignorePrintsNothingOnStderr` 紅（3 支、4 則）。

## 文件

- `docs/store-format.md`：讀不懂的 `.gitignore` 那一段——拒絕只剩 `file add`，`doctor` 與兩個匯入報 warning（三處同一份文字），匯入改成 warning 的理由。
- `.claude/rules/mcp-cli-parity.md`：`akashic_import_zotero`、`akashic_import_wos` 兩列各加「#700 b35 重新確認」（`import_zotero` 那一列先前的「有記錄的缺席：
  MCP 說明不寫這些拒絕」劃掉，改寫成 `gitignoreWarning` 的缺席與誠實邊界）；#705 R3 段落「唯一的訊號是 stdout 那一行」劃掉，新增「#705（使用者 2026-10-05 裁決）」一段。
- `import-zotero --help` 的 discussion 改成照常匯入、warning 在 stderr。`WriteGateRulings` 的 `import-zotero`／`import-wos` 兩格沒有提到 `.gitignore`，不動。
- 原始碼的註解：`SourcesIgnoreBlock.swift` 檔頭與 `SourcesIgnorePolicy` 的兩個 case 列出呼叫者，`ensureLayout` 與 `StoreIOError.sourcesIgnoreNotWritten`、
  `openOrCreateStore` 的 doc 同步。
- `plugin/CHANGELOG.md` 一則。
- `.claude/rules/zero-instance-guards.md` 第 87 列與它的量測段提到「寫入類命令／`import-zotero` 會拒絕」——本輪不動那個檔（另一條工作線在重整它），
  建議的新文字交給整合。

## 驗證

建置（`--build-system native`、`-warnings-as-errors`，含 `--build-tests`）乾淨。`tools/list` 以真 binary 量 58,949 bytes（基準 e058d1d4 同為 58,949）。
全套 `swift test`（分離執行）：5097 支、1 支略過、0 失敗。守衛（`.githooks/run-guards.sh`）：rc 0。
