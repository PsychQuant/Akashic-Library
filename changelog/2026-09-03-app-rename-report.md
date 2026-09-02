# App 面的改名不再丟掉遷移報告（#465）

`AppState.rename(from:to:)` 改回傳 `RenameReport`（**不標 `@discardableResult`**——那會把「報告可以被安靜丟掉」
重新合法化，而那正是本張的 root cause；不要報告的呼叫端寫 `_ =`），`EntryDetailView` 改名後彈出「已改名」
回執：第一行「✓ old → new」，接著 relations／歧異候選／消解判定三類各一行，零筆說零、>5 筆截斷但計數保留。

- **為什麼**：改名的副作用是全庫改寫（#71 relations、#232 verdict、#460 venue 側）。CLI `rename` 印三行，
  App 先前 `_ =` 把報告丟掉——使用者按下「改名」後看不到動了什麼。`entity-backlink-completeness`
  執行細節 2 的形狀：三面走同一條 `renameEntry`，App 這面把輸出丟了。（不引 `lossless-intake`：那條
  明文不適用於 App 顯示。）
- **回執要說改成了什麼**：沒改就不能按（`disabled` ＋ `performRename` 再擋一次），否則一次不編輯的點擊
  會得到與真改名同形的「已改名／0／0／0」（verify DA）。
- **消毒與 CLI 同立場**：`describe` 對每個 key 套 `displaySafe(max: 200)`；`DisplaySinkCoverageTests` 對這條
  路徑結構上不可見（#485 記著）。
- **三個 alert 掛在 if／else 之外**：回執看不看得到不綁在記錄找不找得到上。
- **alert 串 alert，未實機量測**：「已改名」是在「改名 citekey」alert 的按鈕閉包裡被要求呈現的。本 repo 有
  兩個既有先例同形（同檔「操作失敗」自 #11 起、`AdjudicationViews` 的 dialog→alert），且用衍生 binding
  （被丟棄時下次 body 求值會重新算出「想呈現」）。接線寫在 `EntryViews.swift` 的三個 `.alert`，**未經執行
  驗證**；量到負結果時才把設定延到下一個 runloop。
- **部分成功不再只剩「操作失敗」**：`renameEntry` 已寫入而 `reindexAndReload` 失敗時，
  `AppStateError.renamedButReloadFailed` 帶著報告、訊息明說「已寫入磁碟」。根治（兩條分支都不丟、`attempt`
  的簽名）屬 follow-up。
- **測試**：`AppStateTests.testRenameThroughStateReturnsTheMigrationReport`（relations 與 verdict 兩類非空、
  歧異候選為空、store 與持久化的 verdict holder 真的改了）、`testRenameReportSummaryListsAllThreeFamiliesAndTruncates`
  （含 `from:to:` 首行）。
- **不做**：完整逐項列表的 UI（屬 UI 設計）；**organizations 持有的 verdict 本版不遷移**——`renameEntry`
  沒有 org 迴圈（#463 的格，live store 9 條），回執的「消解判定」只涵蓋 person／venue 持有的；使用者面字串
  刻意不標這個邊界（會製造 App／CLI 分岔且 #463 落地當天過期），邊界寫在 `AppState.rename` 的 doc 與這裡。
