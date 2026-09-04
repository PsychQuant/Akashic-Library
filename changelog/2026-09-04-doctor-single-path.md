# CLI doctor 改讀 `StoreHealth`——第四條讀取路徑收斂（#504）

CLI `akashic doctor` 先前**完全不走** `store.health(from:)`：自己算 `load.crossRecordIssues()`、`store.layoutResidue()`、
`store.auditSourceIndex()` 並自行渲染。#263 抽出 `StoreHealth` 時這一段因為要排在 fatal cross-record 早退之前而留在
原位；MCP `doctor()`、CLI `validate`、App 都走 health——doctor 是第四條路徑，`entity-backlink-completeness` 執行細節 2
的分岔形。後果實在：#453 的本機缺存檔掃描與 #464 的死 verdict 都進了 `perRecordIssues`，CLI doctor 一個都看不到。

（issue 引的 `Commands.swift:179` 其實是 `validate` 的 `run()`；「doctor 對 audit 呼叫兩次」不對，真相是「doctor 一次都
沒經 health」。）

- `Doctor.run`：`load()` 之後立刻 `let health = store.health(from: load)`；cross／fatalCross／殘留／sources audit 全部改讀
  `health.*`，渲染文字逐字不變；早退順序不變（`health(from:)` 本來就在早退前算得出）。
- 一個語意差異，記下：`health(from:)` 對 `layoutResidue()` 的錯以 `try?` 吞掉（報告不得消失，#224 F1）——doctor 先前對它
  是 throw；改後與 MCP 面同語意，殘留掃描失敗不再中止 doctor。
- `sourcesAuditError` 的降級訊息改讀 `health.sourcesAuditError`（已 displaySafe，標 exempt）。
- 守衛：`Tests/AkashicCLITests/DoctorSinglePathTests.swift` 源碼掃描——`Doctor.run` 含 `health.crossRecordIssues`／
  `layoutResidue`／`sourcesAudit`／`sourcesAuditError`，且不再直接呼叫 `auditSourceIndex()`／`layoutResidue()`／
  `crossRecordIssues()`。RED 先（三個直接呼叫都被抓到）再 GREEN。
- **不做**：doctor 順手印 per-record 的計數（死 verdict、本機缺存檔）——那是 #416／#487 那族的呈現裁決；本張只收斂路徑。
