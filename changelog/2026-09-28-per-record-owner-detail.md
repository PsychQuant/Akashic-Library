# 2026-09-28 被截掉的 validate 明細有出口了：單筆完整明細（#581）

組合式的六族——venue 名字內容、venue 的 names／authorized／variant 近重複、person 近重複、同一 venue 多條 key 邊、同一 work 多個 confirmed literal、重複的判定記錄——在產生訊息那一步就每筆記錄至多列 20 則（`Entry.perRecordWarningCap`），其餘一句「則數已達上限：另有 N 個未列出」。這個上限三個面共有：CLI `validate` 不加面級截斷，但讀的是同一份 `perRecordIssues`，所以被截的那幾則在 CLI、MCP、App 都拿不到，唯一的出路是手讀 YAML。#554 R24（D66）把七處「完整逐行」的假承諾改成誠實措辭，但沒有給出口；這張 issue 就是那個缺口。

## 裁決（使用者 2026-09-28）

出口是**單筆完整明細**，不是全庫的完整列舉模式。上限存在的理由是讀取路徑對整份未信任 store 的求值界限；呼叫端指名一筆之後，輸出的上界就是那一筆自己的組合數，不重開那個洞。對整份 store 放寬仍然不做。

## 改了什麼

**CLI**：`akashic validate --owner <kind>:<key>`。對指名的那一筆不套列出上限，逐行列出它的 per-record 問題（含掃描族裡 owner 是它的那幾則，例如死 verdict、重複判定記錄），末行說明這是完整明細、跨記錄檢查與 quarantine 不在範圍內。這一筆有 error 時非零退出。不帶 `--owner` 的 `validate` 在有記錄被截時多印一行「被截的記錄: N」並指向 `--owner`。

**MCP**：`akashic_doctor` 多一個 `owner` 參數，同一套定址。帶它時回那一筆的完整明細：`total`／`errors`／`issues`／`truncated`／`scope`。輸出進 LLM context，所以仍受 48 KiB 位元組預算（`candidateByteBudget`）、每則截 1,000 字元，截掉時 `truncated` 為 true、`total` 是完整則數。owner 模式唯讀，不重建 index。

**定址**：`<kind>:<key>`，kind 是 work／person／organization／venue／divergence 之一，必填、不猜。2026-09-28 實測 live store 跨 kind 同 key 有 2 個（organization 與 venue 共用 `american-psychological-association`、`american-educational-research-association`），省略 kind 就得在兩筆之間挑一筆。issue 的裁決原文說「person 與 organization 的 key 會撞、實測 2」——重量後撞的是 organization 與 venue，person 與任何 kind 都是 0。其餘拒絕：kind 不在值域（大小寫不折疊）、key 不合 StoreKey（divergence 要 UUID，大小寫都收、正規化成大寫）、找不到（有 quarantine 檔時指路）、同 kind 同 key 兩筆以上（列出各筆的檔名 UUID）。CLI 上，只看字串就判得出來的錯是用法錯誤（exit 64），找不到與重複是執行期失敗（exit 1）。

**不放寬的三樣**：近重複的組內 5,000 對與整筆 100,000 對求值上限（那是 CPU 的界限，觸頂時概括句照樣出現，且改說「單筆完整明細不套每筆 20 組的列出上限」——照抄「每筆記錄最多列 20 組」在完整明細裡是假話）；訊息內部的列舉上限（一組列 3 對、一則列 5 個拼法）；MCP 面的位元組預算。

**實作**：per-record 的組裝抽成 `LibraryStore.perRecordIssues(from:listing:only:)`，`health(from:)` 以 `(.capped, nil)`、單筆明細以 `(.full, owner)` 呼叫同一份——族序、掃描清單、error 先排只有一份。`PerRecordListing`（`.capped`／`.full`）傳進 `Entry.validate`、`Person.validate`、`Venue.validate`、`AuthorizedNames.validateNearDuplicates`、`duplicateVerdictRecordIssues`，寫入閘照舊用預設值。定址在 `RecordAddress.parse`，兩面共用。

**App**：側欄「被截的記錄」的說明與記錄摘要的 help 改成指向 `validate --owner`，不再說「只能讀 YAML」。App 本身沒有加單筆明細的面。

## 誠實邊界

- 同 kind 的重複 key 只有 citekey 與 person key 有跨記錄檢查；venue 與 organization 的重複 key 沒有任何檢查會報（兩筆照常載入）。在這兩個 kind 上，owner 的拒絕是那個重複唯一會出聲的地方，而且只在有人剛好指名那個 key 時出聲。拒絕訊息照實說「目前沒有跨記錄檢查報」。首版的訊息寫成「不帶 --owner 的 validate 會列出」，對這兩個 kind 為假，同輪改掉。補上跨記錄檢查不在本張的範圍，要另開 issue。
- library 不在定址的值域：它不是 `EntityKind`，也沒有有列出上限的族，不帶 owner 的 `validate` 本來就逐則全列。
- MCP 的完整明細仍可能被位元組預算截；要一則不漏看用 CLI。

## 測試

- `PerRecordFullListingTests` 9 支：六族各自在 `.full` 下列滿、`.capped` 照舊截；求值上限不跟著放寬且概括句不說假話；單筆明細與全庫依 (族名, key) 篩出的那段逐則相同；定址的拒絕；跨 kind 同 key 以 kind 區分；找不到與同 kind 重複的拒絕（venue 說沒有跨記錄檢查、citekey 指路 validate）。
- `RecordIssueDetailTests` 3 支（MCP）：25 個配對全列、`truncated` false；300 則長訊息被位元組預算截、`total` 完整；定址拒絕。
- `ValidatePerRecordCapCLITests` 3 支（真 binary）：不帶 `--owner` 的契約加上指路行；`--owner organization:acme` 25 則全部具名、沒有概括句；缺 kind exit 64、找不到 exit 1。
- `AuthorizedNameTests` 的機械守衛跟著組裝點搬家。
- 負控 7 項（逐一拿掉守衛、確認轉紅、反向替換還原、與備份位元組相同）：`.full` 的列出上限（6 支紅）、同 kind 重複 key 的拒絕（1）、掃描族以 owner 篩（2）、MCP 位元組預算（1）、kind 必填（3，含 CLI 與 MCP 各一）、概括句措辭（1）、指路行（1）。
- 沙箱實跑：scratch store 一筆 25 個尾隨空白名字的 venue，`validate` 列 20 則加概括句與指路行，`validate --owner venue:beta` 列 25 則、無概括句；MCP `akashic_doctor` 帶 `owner` 回 25 則、`truncated` false、不帶 kind 回 `isError`。

## 規則

`mcp-cli-parity`：CLI-only 表 `validate` 列把「不加完整列舉模式……要全部只能讀 YAML——缺口記成 #581」劃掉、寫入本裁決；MCP 表 `akashic_doctor` 列寫入 `owner` 的兩面契約（CLI 面是 `validate --owner` 而不是 `doctor --owner`，理由是 CLI `doctor` 本來就不印 per-record 家族）與面級截斷的有記錄差異。`zero-instance-guards` 加第 38 列（同 kind 同 key 兩筆以上時拒絕，零實例；合併時由 37 重編為 38，venue／organization 的跨記錄檢查記在 #669），附 bullet 與量測腳本。`docs/store-format.md` 家族計數那段補出口。`two-kinds-of-edits` 不加列：`validate` 與 `akashic_doctor` 是讀取面。
