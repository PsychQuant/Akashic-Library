# 2026-09-29 存進 store 的全文連得回條目了（#614）

store-format §2.4.1 讓 work 以 `akashic.sources` 攜帶 digest 清單，宣告「這些已儲存的內容是本作品的副本」（#223）。
但**沒有任何 CLI 或 MCP 入口寫得進它**：`store-source` 只把位元組與取得記錄存進 `sources/`，`enrich` 的 `sourceDigest`
寫的是欄位層級的 reference（值 ← 證據，不是作品 ← 副本），`link` 只管 cites／related。`akashic-fetch-fulltext`（#613）
取回並驗證過的 PDF 因此只能停在 `sources/`，它是哪一篇只記在回報表裡；替代路徑只剩寫一支走編碼器的一次性 Swift 程式。

## 改了什麼

**`update-entry` 的第二條腿，兩面同契約**：CLI `update-entry <citekey> --add-source <digest> [--apply]`，
MCP `akashic_update_entry` 的 `add_sources`，同走 `AkashicService.updateEntry`（`Sources/AkashicMCPKit/EntryUpdate.swift`）。

- **落地不是判定**：「這份 PDF 是這篇」在上游判（`akashic-fetch-fulltext` 的驗證：頁數、首頁標題、DOI），證據隨
  `store-source` 的 note 記在 `sources/index.jsonl`。本面收已判定的 (citekey, digest)，`two-kinds-of-edits` 的程式欄。
- digest 必須合法：`isValidDigest`，空內容的 digest 以 #654 的原句拒絕（訊息說「0 byte」而不是「形狀錯」）。
- **每個要新加的 digest 都要已經在本機 `sources/`、而且 index 有它的取得記錄**（已連過的是 no-op、不檢查——別台 clone 上
  `sources/` 本來就可能不在）。新的 `LibraryStore.sourcePresence(digests:)`
  逐個回報四種狀態：在且有記錄／本機沒有／孤兒 blob（有位元組、沒有取得記錄）／shard 讀不到（讀不到不等於缺席，#265）。
  index 有無法解析的行、而這個 digest 不在可解析的行裡時擲錯——它的條目可能就在壞掉的那一行（與 `storeSource`
  對同一情形 fail-closed 同一條理由）。`scanIndex` 多回傳每個 digest 第一列的字串欄位，三個消費端共用一份解析。
- 本機沒有、孤兒 blob、shard 讀不到、index 壞到判不出來、同一次重複、一次超過 200 個——**整批拒絕、零寫入**，逐個說原因。
- **add-only、冪等**：已在 `akashic.sources` 的列在 `sourcesAlreadyPresent`，沒有新東西就不寫；新的追加在後、既有的不動。
- 走編碼器（`writeEntry`；format ≥ 9 的閘在那裡），乾跑也跑 `preflightWrite`（唯讀）。**預設乾跑**，`--apply`／
  `dry_run:false` 才寫；CLI 的 `--apply` 過目標 store 確認閘（`update-entry` 那一格已裁決過閘）。
- 報告逐個帶 index 的取得記錄（`origin`、`mediaType`、`retrieved`、`acquisition`、`note`），乾跑時用來確認是哪份內容。
- **不與 `--remove-field` 組合**：一個是判定（理由只進報告、要 git 閘）、一個是落地，混在一次呼叫裡報告與閘的語意也混在一起。

`akashic-fetch-fulltext` 的 SKILL.md 從「還不能」改成第 5 步「連結回記錄」：只連驗證通過（或經人確認）的那幾篇，先乾跑再實寫。

## 測試與負控

- `EntrySourceLinkTests` 8 支：乾跑帶取得記錄且零寫入；實寫走編碼器、冪等（第二次位元組不變）、追加在後、其餘欄位不動；
  已連過的 digest 在本機沒有位元組時仍是 no-op；
  本機沒有拒絕；孤兒 blob 拒絕；index 壞掉時判不出來拒絕、可解析的行上的仍判得出來；五種輸入錯整批拒絕零寫入
  （大寫 hex、URL、空內容 digest、重複、第二筆本機沒有）與兩腿組合拒絕；無法唯一定位拒絕。
- `UpdateEntryCLITests.testAddSourceLinksStoredContent`（真 binary）：乾跑印取得記錄且不寫、`--apply` 寫、再跑是 no-op。
- `StdioE2ETests.testUpdateEntryDefaultsToDryRun` 多一段：`add_sources` 接到服務。
- `ServiceArgvExitCodeTests.testUpdateEntryArgvChecks` 多四格：digest 形狀、空內容 digest、重複、兩腿組合，exit 64。
- 先寫測試：新簽章編不過，再加一個忽略參數的簽章，七支全紅，才實作。
- 負控（反向編輯、`cmp` 確認還原）：拿掉存在性閘、拿掉冪等過濾、乾跑也寫、報告不帶取得記錄、兩腿放行組合、拿掉空內容
  digest 的專屬訊息、拿掉 index 壞掉時的擲錯、MCP 不接 `add_sources`、CLI 送錯的 digest——每一個都讓對應的測試轉紅。

## 誠實邊界

- 「必須在本機」只是寫入當下的閘。`sources/` 不進 git，別台 clone 讀到這條連結時內容可能不在——那照常載入、可回報缺席
  （§2.4.1；`akashic validate` 的「本機缺承重存檔」）。
- **沒有移除腿**：連錯了只能手改 YAML。issue 只要求 add-only；移除面要不要有、要不要套移除面一族的裁決，另裁。
- 驗證的證據只以 `store-source` 的 note 記在 index，store 裡沒有一筆「這份是這篇」的判定記錄——`akashic.sources`
  沒有放判定的位置，加它要改 store format。
- `entity-backlink-completeness` 的關係邊封閉列舉（15 條）沒有 `Entry.akashic.sources → sources/ 的內容` 這一條；它自
  #223（format 9）就存在，本 change 只是第一次有了寫入面。表要不要補一列留給整合者裁決。

## 規則

`mcp-cli-parity` 的 `akashic_update_entry` 列補 #614 那一段；`two-kinds-of-edits` 加一列（程式編輯）；
`WriteGateRulings` 的 `update-entry` 格註解補 `--add-source`；`docs/store-format.md` §2.4.1 記寫入端。
