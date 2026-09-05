# App 側欄「記錄」Section——per-record warning 終於在 App 上看得到（#487）

`SidebarView` 的「健康」Section 閘在 `health.hasFindings`，而它依 #416 只計 per-record 的 **error**（warning 一族是編目品質
提示，不該讓健康的 store 常態亮燈）。於是三族 per-record warning——#464 死 verdict、#453 本機缺承重存檔、#499 venue verdict
預算——在 App 上什麼都看不到；CLI `validate` 逐行、MCP `doctor` 進 `recordIssues` 都有。App 是取代 Zotero 的主要 UI。

- **純模型** `RecordIssuesSummary`（`Sources/AkashicAppKit/RecordIssuesSummary.swift`，與 `RenameReportSummary` 同形）：從
  `StoreHealth` 算五個數（總數、error、死 verdict、本機缺存檔、venue verdict 預算）與 `.help` 用的前幾則（`displaySafe`、
  預覽上限、超過的筆數以「另 N 則」說出）；全為零回 nil——沉默即健康。
- **獨立 View** `RecordIssuesSection`（`Sources/AkashicAppKit/RecordIssuesSection.swift`）：只收 `RecordIssuesSummary` 值
  （`swiftui-specialist` 的 narrow-inputs：`AppState` 其他變化不使它失效）；掛在 `SidebarView` 的「健康」之外、**自己的閘**，
  `hasFindings` 的語意不動。
- 測試（`RecordIssuesSummaryTests`，AppState 層＋純模型）：一筆死 verdict → 摘要非 nil、死 verdict 計 1、`hasFindings` 仍 false
  （這正是本 Section 存在的理由）；乾淨 store → nil；預覽上限與「另 N 則」；源碼掃描釘住掛載處不在 `hasFindings` 閘內。
  RED 先（型別不存在）再 GREEN。
- 三處「App 面未渲染」的句子（#464／#453／#499 的 changelog、`StoreHealth` doc、`zero-instance-guards` 第 13／15 列）同輪改成事實。
- 誠實邊界：`AkashicApp/` 的 UI target 不在 SwiftPM 測試範圍——view 只能靠 `AkashicAppKit` 建置與源碼掃描；可測的邏輯全在純模型。
