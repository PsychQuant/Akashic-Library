# 2026-10-01 App 的寫入留下 legacy 拷貝時算成功，另以側欄提示列出要清的檔（#708）

#705 讓「寫進 `entities/`、搬移後的 legacy 拷貝沒刪掉」的那一筆在 CLI、MCP 與 import-zotero 都記在成功那一側（`writtenWithLegacyCopy`）。App 的寫入者沒有開收集範圍，同一件事在 App 擲 `StoreIOError.legacyCopyNotRemoved`，畫面上是「操作失敗」——同一件事兩種說法，正是 #705 要消除的狀態。

使用者 2026-09-30 裁決：App 的動作照常算成功，另以一個非阻斷的提示列出要清的 legacy 檔。

## 改了什麼

**範圍（`AppState.recordingLegacyCopies`）**：包住 `LegacyCopyLedger.collecting`。範圍裡留下的每一筆併進 `AppState.legacyCopyNotice`，結果經 `LegacyCopyLedger.get` 取出——`body` 成功就回傳、動作算成功；留下拷貝之後才因別的原因失敗（最常見的是 index 重建），拷貝照樣進提示，擲出的是 `LegacyCopyLeftBeforeFailure`，失敗提示先說寫了什麼、再說錯誤（與 CLI／MCP 的錯誤回應同一個順序）。

App 沒有 CLI 進入點或 MCP 分派那樣的單一出口，範圍開在各寫入點：

| 寫入點 | 範圍包住什麼 |
|---|---|
| `AppState.mutate`（狀態、標籤、加入／移出 library、加入／移除關係） | `writeEntry` 與之後的 index 重建 |
| `AppState.rename` | 只包 `renameEntry`。之後的重建失敗照舊是 `AppStateError.renamedButReloadFailed`——那個錯誤本身就說「改名已寫入磁碟」、帶著報告，view 靠它顯示部分成功的回執；包成 `LegacyCopyLeftBeforeFailure` 會讓 view 認不出它。留下的拷貝照樣在提示裡 |
| 裁決台 accept（`PeopleResolveModel.accept`） | entry 的寫入、person verdict 的寫入、index 重建（範圍寫在原處、不抽函式——源碼守衛以字面包含判定） |
| 裁決台「轉純 Akashic」（`OrphanModel.resolve`） | 寫入與重建（垃圾桶不經 `writeEntry`，範圍對它沒有作用） |
| 裁決台「拿掉已刪除的來源」（`OrphanModel.removeOrphanedAdditionalSources`） | 寫入與重建 |

**提示（`LegacyCopyNotice`，側欄最上面的 Section）**：列出每一筆的記錄（`work「citekey」`／`person「key」`）與要刪的 legacy 檔（相對 store root），每一列的完整說明放在 `.help`。說明文字取自 CLI／MCP 同一個來源——Section 的說明是 `LegacyCopyLeft.reportLines` 的第一行，每一列的完整說明是 `LegacyCopyLeft.message`；App 不另寫一份描述。非阻斷：不是 alert，動作照常完成。收起的方式有三種：

- 「知道了」按鈕（`AppState.dismissLegacyCopyNotice`），只收起提示、磁碟不動；
- 每次 `load()` 拿掉 legacy 檔已經不在的那幾筆——使用者刪掉 legacy 那份之後，提示不再叫他去清一個已經不在的檔；
- 切換檔案時清空（它列的是舊 universe 的相對路徑；切換失敗回滾時一併還原）。

App 既有的狀態提示（「外部變更已同步」）是 `AppState` 的一個屬性、由側欄的一個 Section 呈現；這裡沿用那個形狀，沒有另開一套橫幅機制。View 只收 `LegacyCopyNotice` 這個值型別（`swiftui-specialist` 的窄輸入），列是獨立的 `LegacyCopyNoticeRow`。

**其餘同步**：`LegacyCopyLedger` 的說明把 App 加進「開範圍的回報面」那份封閉列舉；`mcp-cli-parity` 的 #705 段把 App 的例外劃掉、補 #708 一段；#705 的 changelog 在 App 那一列與誠實邊界加註；`zero-instance-guards` 加第 74 列（源碼守衛）；`GitSpawnHygieneTests` 登記新的測試檔。

## 測試

`Tests/AkashicAppKitTests/AppLegacyCopyNoticeTests.swift`，9 支。刪不掉的造法同 `LegacyCopyLedgerTests`：legacy 檔受 git 追蹤、乾淨（寫入時會搬移它），所在目錄設成唯讀；以 root 執行、權限擋不住時 skip。

- **動作成功**：accept 寫 person 的 verdict，legacy 的 `people/<key>.yaml` 刪不掉——`accept` 不擲、提示列出那一筆（kind、key、id、legacy 檔、寫進去的檔、說明與 CLI／MCP 同一句）、verdict 在 `entities/`、作者位歸戶。person 的兩份不擋 index 重建，這是端到端「成功」的那一格。
- **範圍本身，work 那一半**：`recordingLegacyCopies { writeEntry }` 不擲、提示列出。
- **留下拷貝之後才失敗**（衍生層編輯、「轉純 Akashic」）：擲 `LegacyCopyLeftBeforeFailure`，`written` 是那一筆、`underlying` 不是 `legacyCopyNotRemoved`、顯示的文字以 `writtenWithLegacyCopy（` 開頭；提示照樣列出；內容已寫進 `entities/`。
- **改名**：擲的仍是 `renamedButReloadFailed`（回執不被包掉），提示列出的是新 citekey、legacy 檔是舊 citekey 那份。
- **提示的生命週期**：legacy 檔還在時 `load()` 不拿掉、刪掉之後拿掉；「知道了」收起。切換檔案時清空——另一個 store 在同一個相對路徑也有檔，load 的「拿掉已經不在的」救不了它。
- **源碼守衛**：`AkashicAppKit` 與 `AkashicApp/Sources` 裡每一個 `.writeEntry(`／`.writePerson(`／`.renameEntry(`／`.renamePerson(` 都在某個 `recordingLegacyCopies {` 的大括號裡（地板 6 個，空掃描不是通過）；掃描器的大括號配對另有一支測試。

「留下拷貝之後才失敗」的三支用「index 目錄唯讀」造出重建失敗，不靠 work 的兩份撞重複——index 日後怎麼處理兩份並存（另案），這些測試都成立。

## 負控

反向編輯一處 → 跑 `AppLegacyCopyNoticeTests`（NC4 另加 `LegacyCopyLedgerTests/testEveryScopeTakesItsResultThroughGet`）→ 以位元組備份還原、`cmp` 相同。每一次都先確認 `Executed 9 tests`（NC4 是 10）再數失敗。

| # | 反向編輯 | 紅的測試 |
|---|---|---|
| NC1 | 範圍不開（`body` 直接跑、`written` 恆空） | 7 支：兩支源碼守衛以外的全部 |
| NC2 | 收到的不併進提示 | 同上 7 支 |
| NC3 | 衍生層編輯的寫入移到範圍外 | 衍生層編輯那支、源碼守衛 |
| NC4 | 範圍的結果改用 `try result.get()` | 衍生層編輯、「轉純 Akashic」兩支，與 `testEveryScopeTakesItsResultThroughGet` |
| NC5 | `load()` 不拿掉已經不在的 | 提示生命週期那支 |
| NC6 | 切換檔案不清空 | 切換檔案那支（第一版照綠：`load()` 在新 root 下把那一列當成「已經不在」拿掉，遮住了缺的清空——補上「另一個 store 同一個相對路徑也有檔」之後才紅） |
| NC7 | 改名的範圍也包住重建 | 改名那支（回執被包成 `LegacyCopyLeftBeforeFailure`） |
| NC8 | accept 的寫入移到範圍外 | accept 那支、源碼守衛 |
| NC9 | 「轉純 Akashic」移到範圍外 | 那一支、源碼守衛 |

## 誠實邊界

- **work 的兩份仍讓 index 重建撞重複**（#705 記過的後果，index 那一半另案）。所以在 index 能容忍兩份並存之前，App 對 work 的寫入留下拷貝時是「失敗＋提示」：失敗提示先說寫了什麼、再說重建的錯誤，側欄列出要清的檔。「動作成功」今天只在 person 那一格端到端成立（accept 寫 verdict），與 CLI／MCP 的現況相同。
- **失敗時那一筆出現兩次**：失敗提示（alert，要按掉）與側欄提示（留到收起或刪檔）。刻意的——alert 按掉之後，要清的檔還得有地方看得到。
- **「拿掉已刪除的來源」今天走不到這一格**：它的可回溯閘在 entities 佈局下只認 `entities/` 裡的檔，只有 legacy 那份的記錄在寫入之前就被拒。範圍照樣包著（源碼守衛要求、閘日後改了也涵蓋），沒有端到端測試。
- **提示是 session 狀態**：不跨 App 重啟保存。重啟之後那筆記錄仍被 load 標成無法唯一定位，App 對它的寫入照樣被拒（#627／#641 的既有閘），只是不再有這份清單。
- **源碼守衛看字面包含**：它比執行期的範圍嚴（寫入搬進另一個函式、由範圍裡呼叫時它會紅）；反方向看不到範圍裡再開逃逸閉包去寫的形（範圍靠 task-local 傳遞，那時照舊擲 `legacyCopyNotRemoved`——大聲，不是安靜）。App 今天沒有這種寫法。
- **SwiftUI 的呈現沒有測試**：`AkashicApp/` 的 UI 不在 SwiftPM 測試範圍，測的是模型（`LegacyCopyNotice`）與狀態（`AppState`）；Section 與列的 view 由 `swift build` 編譯，沒有在執行中的 App 裡看過。
