# 2026-09-29 活著的 Zotero 來源有了移除面；沒記 library_id 的附加來源出聲；多筆宣稱的來源復原時 orphan 標記照清（#680、#679、#682）

三張 issue 都出自 #610（同一個 Zotero 來源被多筆 entry 宣稱）的 b11b 驗證：#610 讓「宣稱者的重複」被說出來，卻把處置留成「手改 YAML」，並留下兩個沒被檢查的邊角。

## #682：多筆宣稱的來源，Zotero 端復原時 orphan 標記照常清除

**問題**：被兩筆以上 entry 宣稱的來源，#610 讓匯入在路由前就 `continue`，連 orphan 標記的清除也一起略過。Zotero 端之後復原那個 item，兩筆的 `orphanedAt` 都還在，App 的 Orphans 頁把它們列成「已刪除」，而那一頁的動作是破壞性的（移到垃圾桶、脫鉤）。歧義只出現在跨記錄 warning，App 看不到。

**裁決**（整合者代裁，使用者可翻，見「代裁」）：orphan 標記說的是「Zotero 那個 item 在不在」，判它不需要先判定哪一筆是正主。所以匯入端**書目欄位與 version／hash 照舊不動**，但各宣稱者身上這個來源的標記照清。issue 給的另一個出路（Orphans 清單標歧義、停用破壞性動作）沒採：那是把一個可以直接算出來的事實留給人的手。

**改了什麼**：
- `ZoteroImporter.run`：多筆宣稱的分支（composite 與 legacy 的 `?:<key>` 桶）呼叫 `clearOrphanMarks`。宣稱者身上的來源由 `ZoteroSourceClaims.claims(of:)` 找（宣稱者的定義仍只有一處）；沒有標記就不寫；清掉的主來源進 `orphanCleared`、附加來源進 `secondarySourceRestored`（與 #605 的既有分工同一條）；`ambiguousSourceClaims` 照舊列出。
- 舊檔那一桶只在歸屬沒有爭議（沒有別的 library 持有同一個裸 key）時才清，與單一舊檔的認領同一條件。
- `ZoteroSourceClaims` 新增 `sources(of:)`（一筆 entry 的全部來源，含沒記 library_id 的附加來源）與 `claims(of:)`（其中算宣稱的），`claimants` 改由 `claims(of:)` 組出。
- CLI 標題行、MCP 描述、`docs/store-format.md` §2.5.3、`mcp-cli-parity` 的 `akashic_import_zotero` 列同步。

**反方向（多筆宣稱而 Zotero 端刪了 item）**：照實作現況，各宣稱者**都會**被標——orphan 偵測迴圈逐筆看每一筆自己的來源，完全不看宣稱者的數量。這一半沒有缺口，只是先前沒有測試釘住；現在 pin 在 `testRestoredItemClearsOrphanMarksOnEveryClaimant…` 的前半（`gone.orphaned` 兩筆都在）。

## #679：沒記 library_id 的附加來源，validate 報 warning

**問題**：附加來源沒記 `library_id` 時，`secondaryByComposite`、`claimedLibrariesByBareKey`、`ZoteroSourceClaims.claimants` 都略過它，所以再匯入時同一個 Zotero 條目（沒有別的 entry 宣稱它時）會另建一筆 twin；decode 接受、`Entry.validate()` 不檢查。`ZoteroSourceClaims` 的註解說這個形狀「由合併閘保證」不會出現——合併閘只保證**合併**不會把被併者的這種來源新收成附加來源，管不到手改與舊檔。

**改了什麼**：
- `Entry.validate()` 對它報 **warning**（不 decode 拒收——拒收會讓既有的檔整個被隔離）：每筆 entry 一則、至多列 5 個來源鍵（`?:<zotero_key>`，也是 #680 的定位鍵）、超過說總數；訊息說出後果（沒有別的 entry 宣稱那個條目時，再匯入會另建 twin；b13f R1 verify 起是有條件的說法）與兩條出路（補真正的 `library_id`、或用 #680 的面移除）。來源鍵經 `displaySafeInvisible`。
- `ZoteroSourceClaims` 與 `ZoteroImporter` 的註解不再說「由合併閘保證」，照實說。`docs/store-format.md` §2.5.3 加一條。
- 警告說的後果用行為釘住（`AdditionalSourceWithoutLibraryReimportTests`：再匯入確實另建一筆），警告與行為不會分岔。
- 2026-09-29 唯讀量測 live store：work 2,569、主來源 532（沒記 library_id 0）、附加來源 3（沒記 library_id 0）、被 ≥2 筆宣稱的來源 0——零實例。`zero-instance-guards` 的一列見整合者報告（不在本次改動裡加）。

## #680：`update-entry --remove-zotero-source`（MCP `remove_zotero_sources`）

**問題**：活著的 Zotero 來源（主來源或附加來源）沒有移除面。#610 對「其中一筆記錯了」的處置、#679 對「沒記 library_id」的出路，都只能手改 YAML（`replace-endnote-and-zotero` 第 4 條）；App 的裁決台只處理已在 Zotero 端刪除的來源。

**放在哪**：`update-entry` 的第三條腿（不新增工具，MCP 工具數不變）。名字刻意帶 `zotero`：`--add-source` 寫的是 `akashic.sources` 的副本 digest，`--remove-zotero-source` 不是它的逆操作（那個由 #677 追蹤）。

**契約**（移除面一族，使用者 2026-09-27 裁決）：`<來源鍵>=理由`；理由必填、至多 4,096 位元組、只進報告（`zoteroSourceRemovals`，全文）、不寫進 store、不改 store format；實跑要求 work 檔已 commit、乾淨（`assertRecordsRecoverable`）；預設乾跑，乾跑不需要 git。來源鍵是跨記錄警告與 `ambiguousSourceClaims` 用的同一種：`<library_id>:<zotero_key>`，沒記 library_id 的是 `?:<zotero_key>`；`05:K` 與 `5:K` 同一個來源。每個來源鍵都要在這筆 work 命中，否則整批拒絕、零寫入（訊息列出這筆現有的來源）；同來源兩次、形狀錯、理由空白或過長、一次超過 200 個同樣整批拒絕。三條腿兩兩不組合。

**移除主來源而附加來源仍在**：附加來源**不升格**（升格會把書目欄位的改寫權交給另一個 library，與 App 的「與 Zotero 脫鉤」同一條既有裁決），沒有主來源、只有附加來源是合法狀態；連結狀態照 `Entry.zoteroLinkState` 的既有定義具名（`zoteroLinkState.before／after`，那個定義沒動）；`primaryRemovedNote` 說明。同一筆 work 的主來源與附加來源恰好同一個來源時兩處都拿掉。

**跨面**：CLI `--remove-zotero-source`、MCP `remove_zotero_sources`（兩面同一個 `AkashicService.updateEntry`，同一個 payload）；`mcp-cli-parity` 的 `akashic_update_entry` 列、`two-kinds-of-edits` 加一列（AI 欄）、`WriteGateRulings` 的 `update-entry` 格（整個命令一格，第三條腿不新增格，註解更新）。跨記錄 warning（#610）與 #679 的 warning 的出路都改指這條腿，並給出可貼上的定位鍵。`docs/store-format.md` §2.5.3 與 `EntryUpdate.swift` 檔頭同步。MCP `tools/list` 最終實測 45,888 bytes（預算 49,000；b13f R1 verify 重量。先前寫的 44,712 是 #680 單獨落地那一刻的數字，與整合後不在同一棵樹上，見 `2026-09-29-b13f-verify-r1.md`）。

## 測試與負控

新增 28 支測試函式：`ZoteroSourceRoutingTests` 5（#682：兩筆主來源、主＋附加、legacy、legacy 歸屬有爭議保留標記、沒標記不寫檔）；`AdditionalSourceWithoutLibraryTests` 7（#679：warning 內容、不誤傷、上限、消毒、`perRecordIssues`、宣稱者定義、再匯入後果）；`EntryZoteroSourceRemovalTests` 13（#680 服務層）；`ZoteroSourceRemovalReimportTests` 1（`reimportNote` 說的後果）；`UpdateEntryCLITests` 2、`ServiceArgvExitCodeTests` 5 個斷言、`StdioE2ETests` 的 dispatch 斷言（真 binary）。另修 `ZoteroSourceRoutingTests` 兩處舊斷言（出路改指移除面）。

**先紅後綠**：#682 的 3 支在實作前紅（「沒標記不寫檔」先就綠——它釘的是不得順手改寫檔案；「legacy 歸屬有爭議保留標記」實作後才補）；#679 的 4 支在實作前紅（「不誤傷」與「再匯入後果」先就綠——後者釘的是既有行為，警告要說的後果本來就是真的）；#680 在實作前編譯失敗（簽章不存在）。

**負控**（反向編輯、`cmp` 確認還原，全部轉紅）：
- #682：多筆宣稱分支不呼叫清除 → 2 支紅；legacy 分支不呼叫 → 1 支紅；legacy 不看「別的 library 持有」 → 1 支紅；清除略過附加來源 → 1 支紅。
- #679：報告 library_id 有的那些 → 5 支紅；不設 5 個的上限 → 1 支紅；來源鍵不消毒 → 1 支紅；severity 改 error → 1 支紅。
- #680：移除主來源時升格附加來源 → 2 支紅；同筆的主＋附加只拿一處 → 1 支紅；拿掉 git 閘 → 1 支紅；乾跑也過閘 → 2 支紅；拿掉「來源不在這筆」的檢查 → 2 支紅；連結狀態的 after 用 before → 2 支紅；`reimportNote` 一律出現 → 1 支紅；來源鍵不驗 ASCII 數字 → 1 支紅（輸入測試逐項釘「為什麼被拒」的訊息片段，形狀錯不能靠「這筆沒有」兜住）。

## 誠實邊界

- **移除之後再匯入會不會另建一筆，依移除之後還有沒有別的 entry 宣稱這個來源而定**（b13f R1 verify 更正：首版無條件說「會新建一筆」，在雙宣稱與 `?:` 附加來源兩個形狀為假）：
  沒有任何 entry 宣稱它、Zotero 端仍有那個條目時才另建一筆；另一筆仍宣稱它則匯入路由到那一筆、不新建；`?:` 附加來源本來就不是宣稱者、移除它不改變匯入行為。
  本面不做「移到另一筆 work」；要讓它落在另一筆上，那筆要先宣稱這個來源（攣生合併，或手改 YAML）。報告的 `reimportNote`／每個來源的 `reimportEffect` 逐來源說出來。
- **沒有具名逆操作**：被移除的來源只在 git 的移除前副本與報告裡；重新匯入不會接回這一筆。
- **legacy 桶的 orphan 標記只在歸屬沒有爭議時才清**：別的 library 持有同一個裸 key 時保守留著（清錯的代價是 Orphans 頁少列一筆真的已刪除的）；那是 #607 對舊檔的既有立場，不是本次新增的限制。
- **警告只在讀取面出聲**：#679 的 warning 是 per-record warning，`validate` exit 仍 0（「掃得到」不「叫醒」，同 #464 一族）。
- **`zero-instance-guards` 一列沒有加**（多個 agent 會撞列號）：情形／裁決／理由／量測腳本在整合者報告。

## 代裁（使用者可翻）

1. **#682 採「匯入端仍清標記」而非「Orphans 清單標歧義並停用破壞性動作」**：理由見上；翻的方式是把 `clearOrphanMarks` 的兩處呼叫拿掉，並在 App 的 Orphans 清單加歧義標示。
2. **移除主來源時附加來源不升格**：沿用 App 的「與 Zotero 脫鉤」既有裁決，沒有另問使用者。
3. **`--remove-zotero-source` 放在 `update-entry` 的第三條腿**，而非獨立命令或 `library` 一族：brief 的優先建議；代價是 `update-entry` 一個命令承載三種不同的判定與落地，三條腿靠「兩兩不組合」隔開。
4. **來源鍵重用 `ZoteroSourceClaims.key` 的形**（含 `?:`），而非另立定位語法：這是移除面能處理 #679（沒記 library_id 的附加來源）的前提。
