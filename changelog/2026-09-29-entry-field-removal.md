# 2026-09-29 錯的 `fields` 值刪得掉了（#544）

21 筆 work 的 `abstract` 不是摘要，是 Crossref 的錯誤頁（「This DOI is not currently attached to any metadata records…」）。
2026-09-29 唯讀量測 live store：恰 21 筆含這段樣板，都以它開頭，其中 0 筆帶 `fields.abstract` 的來源 reference。
同族另有兩筆（#544 的 comment）：`anon2014entry` 的 `journaltitle` 是補助計畫名稱「科技部大專生研究計畫」、`anon2011entry`
的 `publisher` 是總統令字號「華總一義字第10000015611號」，兩筆各自推導出一條永遠歸不了戶的 literal venue 邊。

根因不在資料，在寫入面：**沒有任何面刪得掉一個 `fields` 的值**。`enrich` 只補不存在的鍵、`create-entry` 是建檔、
`import-zotero` 整份替換 `fields` 但只對 Zotero 來源的記錄有效，唯一的路是手改 YAML。

## 改了什麼

**新的寫入面，兩面同契約**：CLI `update-entry <citekey> --remove-field <鍵>=理由 [--apply]`，MCP `akashic_update_entry`
（`citekey`、`remove_fields`、`dry_run`），同走 `AkashicService.updateEntry`（`Sources/AkashicMCPKit/EntryUpdate.swift`）。
MCP 工具 32 → 33。

- **它是判定**：「這段文字不是這篇的摘要」要讀內容才知道。理由必填、至多 4,096 位元組。
- **理由只進報告**（`fieldRemovals`，全文不截斷），不寫進 store、不改 store format，實跑要求那筆 work 檔已 commit、乾淨
  （`assertRecordsRecoverable`）。這是使用者 2026-09-27 對移除面一族（#588／#572／#586）的裁決。#544 的 body 寫的是
  「留記錄、形狀取自 #450」，那是 09-09 的預期，早於裁決；這裡照裁決。
- **預設乾跑**：CLI `--apply`、MCP `dry_run: false` 才寫，比照 `enrich`（#614 要求同一個工具的另一條腿乾跑預設，一個工具
  一種預設）。乾跑不需要 git；乾跑也跑寫入前的內容檢查（`preflightWrite`，唯讀），所以乾跑說可以時實跑不會在內容閘上被拒。
  CLI 的 `--apply` 過目標 store 確認閘（`WriteGateRulings` 的 `update-entry` 格）。
- **指向被移除鍵的 `fields.<鍵>` reference 一併刪除**，逐鍵回報筆數（`referencesRemoved`）。留著它，那筆 reference 的語意會
  從「值出自這份來源」安靜地翻成 #517 的負結果「查過了、這份來源沒給」，而那不是任何人判定過的事。與 #588 `remove_issn`
  刪掉 `field: issn` provenance 是同一個處置。
- 被移除的值在報告裡只印前 300 字與位元組數（`value`／`valueBytes`），全文在 git 的移除前副本裡。
- 整批拒絕、零寫入：缺 `=`、鍵空白、理由空白或過長、同一鍵兩次、鍵不在 `fields` 裡（逐字比）、一次超過 200 個。
  work 不存在或無法唯一定位（`unlocatableCitekeys`）時拒絕。
- 由被移除的值推導出來的 literal venue 邊**不動**，列在 `venueEdgesFromRemovedValues` 並指向
  `resolve-venues --drop-venue`（#572）——刪邊是另一個判定。欄位移除之後 `migrate-venues` 不會再推導出它們。
- 主來源是 Zotero 的記錄附 `zoteroNote`：日後 pull 若更新這筆（Zotero 端有改、或對映演進）會整份替換 `fields`、把值帶回來。

**上游**：`akashic-venue-works` 的 `ndjson-abstracts-to-proposals.py` 對以 Crossref 無 metadata 樣板開頭的摘要略過並具名
（`crossref-no-metadata`）。這是既有檔的 bug 修正（它把 HTTP 200 的錯誤頁當成摘要），不是新功能。

## 為什麼這不違反 `lossless-intake`

那條規則管的是**進來的那一刻**：來源給了什麼就收什麼，匯入時不得靜默丟棄。本面是事後的更正——一個人讀過值之後判定它不是
來源給這個欄位的資料。#544 的 21 筆本身就是那條規則的反面：收了不是來源給的東西（錯誤頁被當成摘要）。那條規則在意的兩件事，
本面都守著：**不靜默**（理由必填、逐欄回報、值的前段印在報告裡），**不讓資訊不可回復**（移除前的檔在 git，實跑前驗過）。

## 測試與負控

- `EntryFieldRemovalTests` 10 支：乾跑零寫入且不需要 git；實跑刪值與它的 `fields.<鍵>` reference、別的 reference 與欄位不動、
  理由全文、值只印前段；未 commit 拒絕零寫入；不在 git 裡拒絕；九種輸入錯整批拒絕零寫入（含「第一筆合法、第二筆壞」）；
  不存在與無法唯一定位拒絕；venue 邊具名但不動；同值仍可推導時不列；Zotero 來源附註。
- `UpdateEntryCLITests` 2 支（真 binary）：預設乾跑且乾跑不經閘；`--apply` 未指名目標被閘擋、指名之後照常寫。
- `StdioE2ETests.testUpdateEntryDefaultsToDryRun`（真 binary）：不帶 `dry_run` 是乾跑；`remove_fields` 給成字串整個拒絕。
- `ServiceArgvExitCodeTests.testUpdateEntryArgvChecks`：四種參數錯 exit 64、早於開 store。
- `plugin/tests/ndjson-abstracts-to-proposals.py`：fixture 多一列錯誤頁，略過理由 `crossref-no-metadata`。
- 負控（反向編輯、`cmp` 確認還原）：拿掉 reference 的連帶刪除、拿掉 git 閘、乾跑也寫、拿掉 venue 邊提示、理由截在 200、
  同鍵兩次放行、鍵不存在放行、MCP 的 `dry_run` 預設改 false、拿掉 CLI 的閘、CLI 預設改實跑、拿掉 adapter 的略過——
  每一個都讓對應的測試轉紅。

## 誠實邊界

- 本面不回頭改 live store：那 21 筆與兩筆的移除要使用者跑（先 commit store，`update-entry … --apply`，再 commit 並把理由寫進
  commit message）。兩筆的 literal venue 邊另用 `resolve-venues --drop-venue` 刪。
- 被移除的 `fields.<鍵>` reference 沒有工具面取回，只在 git。
- 鍵逐字比對：打錯大小寫就是「沒有這個鍵」，不猜。
- adapter 的略過只認這一個樣板的開頭；別的錯誤頁樣式照樣會被當成摘要，要讀過才知道。

## 規則

`mcp-cli-parity` 加 `akashic_update_entry` 一列（33 工具）；`two-kinds-of-edits` 加一列（AI 編輯，store 內不留 verdict
是有記錄的不兌現）；`WriteGateRulings` 加 `update-entry` 一格（過閘）；`docs/store-format.md` §3.5 記移除端。
