# 2026-09-27 enrich 的來源行不再把計畫說成已發生（#542）

#542 的前兩項已在 2026-09-09 的 `8d965fc1`（PR #545）落地：payload 帶 `provenanceWritten`／`provenanceSkipped`，CLI 由 payload 現算那一行。但 issue 上沒有留下紀錄，第三項（釘住「CLI 那一行不得與 payload 矛盾」的測試）也沒有做。

補那支測試時，它第一次跑就抓到同一個病的反方向：
- **dry-run** 什麼都沒寫，payload 卻照樣帶 `provenanceWritten`（那是計畫值），CLI 因此印「已寫入 1 筆 reference」；
- `--apply` 而那一筆寫入失敗時，同樣會宣稱寫了。

#542 修的是「寫了卻說沒寫」，這裡是「沒寫卻說寫了」。

- payload 的鍵名本身說出事實，三種狀態三個鍵：
  - `provenancePlanned`：dry-run，`--apply` 時會寫；
  - `provenanceWritten`：`--apply` 且那一筆真的寫入；
  - `provenanceNotWritten`：`--apply` 但那一筆寫入失敗。

  消費端不必自己拿 `dryRun` 與 `writeFailed` 交叉推論。MCP 面同一個 payload，兩面同源。
- CLI 各印一種句子。原本「寫入與否於 --apply 時回報」那個分支已經到不了，改成「沒有補任何值，所以沒有 reference」。這是真的會發生的第四種情況：有 digest 但這筆沒有要補的欄位。
- 測試：`EnrichCLITests.testSourceLineAgreesWithPayload`（真 binary），涵蓋以下情形：
  - dry-run 的 CLI 行不得出現「已寫入」，payload 不帶 `provenanceWritten`、帶 `provenancePlanned`；
  - `--apply` 時 payload 的 `provenanceWritten` 與 store 裡真的有的 reference 相符；
  - 只有 digest 時印具名理由。
- 誠實邊界：`provenanceNotWritten` 那一格沒有專屬測試，要造出單筆寫入失敗需要注入 I/O 錯誤。

## R1 verify 之後（6 席，2 HIGH、5 MEDIUM）

- **兩個 HIGH 同一件事：MCP 面沒修到。**
  - `akashic_enrich` 的 proposals item schema 宣告 `additionalProperties: false`，卻只列 `sourceDigest`。照 schema 呼叫的 client 送不出 `sourceURL`／`sourceRetrieved`，三個 provenance 鍵在 MCP 面上實際出不來（DA 用 stdio 實測：違反 schema 送過去，server 其實收）。
  - tool 描述還寫著「sourceDigest 只回顯進報告、不進 store」，正是 #542 從 CLI 拿掉的那句舊話。
  - #542 抱怨的是「兩面都缺同一個欄位」，只修 CLI 那面等於只修一半。
  - 修法：schema 列齊五個來源欄位；描述改寫三欄規則並說出三個 provenance 鍵；CLI `--from` 的 help、解析器錯誤訊息的「可用的頂層鍵」、README 那一句同批改。`mcp-cli-parity` 的 `akashic_enrich` 列補上重新確認，並寫明「兩面同一個解析器」這句只對解析器成立、對 schema 不成立。
- **fallback 那一行說錯話**（logic、regression、DA）：只補 `date`／`authors` 時，那一行印「沒有補任何值」，上一行卻正列著 `+ date = 2020`。改成依 `additions` 分支：真的沒補才這樣說；補了 date／authors 就說它們不寫 reference。底層缺口（它們不產生 retrieval reference）早於本次改動，開 #655 追蹤。
- 測試：
  - `StdioE2ETests.testEnrichSchemaListsEverySourceField`（真 binary 的 `tools/list`）：schema 有五個來源欄位、描述不含舊句、說出 `provenanceWritten`。負控：Server.swift 換回 R1 前，6 個斷言失敗。
  - `EnrichCLITests.testSourceLineAgreesWithPayload` 補兩處：成功寫入時正面斷言「→ 已寫入 1 筆 reference（fields.abstract）」（R1 前只驗了 dry-run 那一行）；只補 date 時不得說「沒有補任何值」。
