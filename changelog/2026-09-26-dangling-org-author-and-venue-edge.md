# 2026-09-26 懸空的團體作者與 venue 邊出聲（#579、#652）

work 有三種參照邊：`.key` 作者、`.organization` 作者、`venues[].key`。先前只有第一種有懸空檢查（`crossRecordIssues` 的「作者 key 沒有對應的 people 檔」），另外兩種在 `validate`、`doctor`、App 都不出聲。

- `crossRecordIssues` 補上兩種檢查：「團體作者 key 沒有對應的 organization 檔」與「venue key 沒有對應的 venue 檔」，都是 warning，理由與懸空作者相同。這個函式是三個面共用的，所以三個面都拿得到。
- 若 key 本身不是合法的 StoreKey，三種訊息都另外註明「不可能對應任何記錄——手改或舊 binary 寫的」。記錄自身的 key 在 load 時已經驗過，所以這種邊不是「目標還沒建」，而是永遠建不出來。#579 要的「非法 key 出聲」就是這一句。
- #579 另外提議用 error 級、與記錄 key 的 quarantine 對齊，這裡不採。quarantine 會讓一條壞掉的邊把整篇作品藏起來。
- **live store 有 2 筆**：`anon1954technical` 的 `organization: American Psychological Association` 與 `anon2014pisa` 的 `organization: OECD`。它們是 2026-08-20 #340 批次手寫的，payload 是名稱而不是 key。處置交給人：
  - 建立 org 記錄後改 key；或
  - 改回 `literal:`，交給 `resolve-organizations`。
  - 目前沒有把 `.organization` 退回 literal 的工具面，只能手改 YAML。
- `zero-instance-guards` 加第 33 列。
- 測試：
  - `CrossRecordValidationTests.testDanglingCorporateAuthorAndVenueEdgeAreWarnings`
  - `CrossRecordValidationTests.testInvalidStoreKeyEdgeSaysItCanNeverResolve`
  - 負控：關掉兩個迴圈與非法說明，兩支都失敗。
- **R2 verify**：MCP `doctor` 只送前 20 則跨記錄問題，而新警告排在 60 則 DOI／標題重複之後，那個面永遠送不出去。現在參照完整性的警告（懸空的作者、團體作者、venue、歧異候選、library）排在重複提示之前，`testReferenceIntegrityWarningsComeBeforeDuplicateNoise` 釘住這個順序（負控：排回去就失敗）。上面「三個面都拿得到」那句，在此之前對 MCP 面不成立。
