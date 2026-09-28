# 2026-09-29 附加來源被刪除之後，doctor 與 App 裁決台都看得到、也處理得了（#609）

#605 讓 orphan 逐來源標記：某個 library 刪了條目，只標那個來源的 `orphaned_at`。但 `StoreHealth` 的 orphan 清單、`LibraryIndex` 的 `orphaned` 欄、App 的 orphan 裁決台都只看主來源。兩個形狀因此看不見：

- 主來源活著、某個附加來源（例如群組 library 那份）被刪——除了 `get_entry` 與當次匯入報告，沒有任何地方提醒。
- 沒有主來源、附加來源全部被刪（#605 R1 裁決後的合法狀態）——作品已從每一個連結的 library 消失，卻在每個 orphan 介面都看不見，也無法丟垃圾桶或脫鉤（#609 R2 補充）。

2026-09-29 量測正式 store：535 個 Zotero 來源（附加 3），主來源 orphan 0、有已刪除附加來源的 entry 0、只有附加來源的 entry 0。

## 改了什麼

- `AkashicCore/ZoteroLinkState.swift`：entry 與 Zotero 來源的連結狀態，封閉三值——完好／整筆 orphan（主來源已刪除，或沒有主來源而附加來源全部已刪除）／附加來源已刪除（主連結仍在）。`StoreHealth`、index、App 共用這一個判準。
- `StoreHealth.orphanedCitekeys` 改讀它（多收「只有附加來源、全部已刪除」）；新欄位 `orphanedAdditionalSourceCitekeys`，與前者不相交。
- `LibraryIndex` 的 `orphaned` 欄改讀同一個判準。
- doctor：MCP 多 `orphanedAdditionalSources`；CLI 多一行 `orphaned additional sources:`，`orphaned:` 那一行改讀 `health`（先前自己推導，是第二份判準）。
- App：總覽多一格「附加來源已刪除」（非零才顯示）；裁決台 Orphans 分兩節，新的一節提供「拿掉已刪除的來源…」——只拿掉已刪除的附加來源，主來源、活著的附加來源與書目欄位不動；理由必填（上限 4,096 位元組、不截斷），只出現在結果裡、不寫進 store；記錄檔要先 commit、乾淨（移除面一族的使用者裁決，2026-09-27；與 `AkashicService.assertRecordsRecoverable` 同一支 `filesNotSafelyRecoverable`）。原有的「移到垃圾桶」「轉純 Akashic」改用同一個判準，所以也作用在「只有附加來源、全部已刪除」的 entry。清單的 orphan 標籤同理，另加「來源已刪」標籤。
- `entityRelativePaths` 從 `AkashicService` 搬到 `LibraryStore`（App 的閘也要用；MCPKit 那支改成轉呼叫）。
- `docs/store-format.md` §2.6 加三值表；`mcp-cli-parity` 的 `akashic_doctor` 列、`two-kinds-of-edits` 加 App 裁決台 Orphans 一列。

## 測試與負控

- `ZoteroLinkStateTests`（3 支）：三值的九種形狀、健康事實的兩張清單不相交、index 的 `orphaned` 欄。
- `OrphanedAdditionalSourceTests`（7 支，App）：兩張清單、脫鉤與垃圾桶作用在「只有附加來源、全部已刪除」、拿掉已刪除的附加來源只動那幾個、不在 git 或未 commit 時拒絕且零寫入、理由必填、動作當下重驗形狀（活著的、整筆 orphan 的、不存在的、外部剛恢復的都拒絕）。

負控七組（反向編輯、`cmp` 確認還原），每組都讓對應的測試轉紅：裁決台的整筆 orphan 判準改回只看主來源、移除動作改成拿掉全部附加來源、拿掉 git 閘、拿掉理由檢查、形狀檢查放寬成「不是完好」、健康清單改回只看主來源、index 欄改回只看主來源。

## 誠實邊界

- 動作只在 App。CLI 與 MCP 沒有 orphan 裁決面（#605 之前就是如此），doctor 只列出。
- 同一個裁決台上，「與 Zotero 脫鉤」（#605 R1 使用者裁決）不要求理由、也不檢查 git；新的移除動作兩者都要。這個不一致記在 `two-kinds-of-edits` 那一列，要不要補是另一個裁決。
- 匯入報告的 `orphaned` 仍只列主來源這一趟被標上的 entry；附加來源被刪時列在 `secondarySourceOrphaned`，即使那讓整筆變成 orphan。
- App 的 SwiftUI 畫面（兩節清單、理由輸入框、結果提示）沒有自動化測試，只有 kit 層的測試與嚴格建置。
