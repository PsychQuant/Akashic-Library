# App 面的改名不再丟掉遷移報告（#465）

`AppState.rename(from:to:)` 改回傳 `RenameReport`（`@discardableResult`），`EntryDetailView` 改名後彈出
「已改名」摘要——relations／歧異候選／消解判定三類連帶改寫各一行，零筆說零、超過五筆截斷但計數保留。

- **為什麼**：改名的副作用是全庫改寫（#71 relations、#232 verdict、#460 venue 側）。CLI `rename` 印三行，
  App 先前 `_ =` 把報告丟掉——使用者按下「改名」後看不到動了什麼。與 `lossless-intake` 執行細節 3
  同形：丟的不是資料，是事實。
- **形狀**：`RenameReport` 的三個欄位全部揭露（`RenameReport` 的 doc 明寫 `relationsRewritten` 只有 citekey、
  `verdictValuesRewritten` 是扁平 key 清單），措辭與 CLI 的三行同語意。摘要是 `EntryDetailView.describe`
  純函式，有單元測試。
- **測試**：`AppStateTests.testRenameThroughStateReturnsTheMigrationReport`（relations 與 verdict 兩類非空、
  歧異候選為空、store 真的改了）、`testRenameReportSummaryListsAllThreeFamiliesAndTruncates`。
- **不做**：完整逐項列表的 UI（diagnosis 的 Risks 段：屬 UI 設計，不在本張）。
