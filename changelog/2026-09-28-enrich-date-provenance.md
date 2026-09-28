# 2026-09-28 enrich 補進去的日期記得出處；作者不記，並說出為什麼（#655）

`akashic enrich` 在來源四欄（`sourceDigest`／`sourceURL`／`sourceRetrieved`／`sourceStatus`）齊備時，替每個補進去的欄位寫一筆 retrieval reference（#517）。但那只涵蓋 `fields` 的鍵與 DOI／PMID／ISBN：從某份存檔補進 `date` 的提案，store 記得值、不記得它出自哪裡；補進去的 `authors` 也一樣，而且報告一句不說。#542 R1 verify 實測到這個缺口，當時只把 CLI 那一行改成說實話。

## 裁決（使用者 2026-09-28）

- **`date` 在第 15 條邊（`Entry.references`）開新的一格 `date`**，不借 `fields.date`。`fields["date"]` 是 `lossless-intake` 收下的另一個格子（2026-09-28 實測 live store 2,563 筆 work 裡 0 筆，但隨時可能出現）；無前綴的 `date` 只能指頂層那一個，與 `fields.type`／頂層 `type:` 同形。
- **語意逐條比照 `fields.<鍵>`**：不收 value（D2：純量）；不驗 `date` 在場。`date` 在場＝值出自這份來源；`date` 缺席 ＋ 一筆 retrieval＝查過了、這份來源沒給；`date: n.d.` ＋ 一筆 reference＝「這筆作品沒有日期」這件事出自這份來源。後兩者不同：`n.d.` 是關於作品的斷言，缺席是關於來源的。kind 收 retrieval 或帶 digest 的 judgement（空 rests-on 在平面 init 就被擋）。
- **這是值域擴充，所以 store format 19 → 20。** format-19 binary 的 `Entry.validateReferenceAttachment` 沒有 `date` case，讀到會走封閉 default、整檔 quarantine。
- **`authors` 不寫 reference。** `field: authors` 那一格已經有主人：作者位記錄（拆分 `拆為 …`、移除 `移除：…`），value 是**已退役**的 literal、kind 只收 judgement。`enrich` 補進去的作者是**在場**的值、來源是一次取得。讓同一個 field 承載兩種相反的語意，讀它的每一處（附著驗證、`staleSplitRecords`、`contradictedRemovalRecords`、un-split）都得先猜是哪一種，那正是 `fields.` 前綴消掉的歧義。理由寫在 `AddOnlyEnrichment` 的型別文件，報告裡逐字說出來。

## 改了什麼

- **核心**（`AddOnlyEnrichment`）：來源齊備且補了 `date` 時多一筆 `field: date` 的 retrieval，與 `fields.<鍵>`、識別碼同一次寫入。`plan` 收一個 `dateReference`（`.writable`／`.unavailable(reason:)`）：core 不讀 store，由呼叫端讀過 marker 後告訴它這一格寫不寫得進去。
- **item 多一個鍵 `provenanceOmitted`**（欄位 → 理由）：來源齊備、值補了、reference 刻意不寫的欄位。封閉兩鍵：`authors`（一律）、`date`（store format 低於 20 時，值照補、理由說出 store 的 format 與門檻）。它與 `provenancePlanned`／`provenanceWritten`／`provenanceNotWritten` **正交**。刻意不借 `provenanceNotWritten`：那個鍵的語意是「apply 時那一筆寫入失敗」（#542 的「鍵名本身說出事實」），刻意不寫與寫入失敗是兩件事。
- **service**（`AkashicService.enrich`，CLI 與 MCP 共用）在**寫入之前**讀 marker。低於門檻時讓 core 省略那一格，而不是讓寫入閘在 apply 時擋下整筆：那會連同值與其他欄位一起 `writeFailed`，dry-run 還說「會寫」。
- **寫入閘**（`assertEntryWritable`）：format < 20 拒寫帶 `field: date` 的 entry。這道閘是其餘寫入者的底線。門檻是一個常數 `StoreVersion.workDateReferenceFormat`，閘、service、MCP 描述、CLI help 都讀它，數字只寫一次。
- **CLI**：逐欄印「來源未記：<欄位>——<理由>」；只補了不寫 reference 的欄位時，那一行說「補進去的值都不寫 reference，逐欄理由見下」。
- **MCP**：`akashic_enrich` 的描述與 `date`／`authors` 的 schema 描述說出新行為與 `provenanceOmitted`。
- `StoreVersion.supported` 19 → 20；`plugin/.claude-plugin/plugin.json`、`mcpb/manifest.json` 的 `Store format 20.`；`docs/store-format.md` 的 format 表加第 20 列，§3.5 新增「work 的 `references`」一節，列出可附著的格、純量格的三種讀法、`date` 不借 `fields.date` 的理由、`authors` 不收 enrich 來源的理由。這一節在此之前不存在，#517 的 `fields.<鍵>` 也沒寫進去。README 的 format 表與 enrich 段同步。
- `openspec/specs/add-only-enrichment` 的「Source digests are reported, never stored on the work」自 #517 起就是假的，換成現況的 Requirement（三個 Scenario：date 帶來源、authors 不帶、低 format 值照補）。同 #517 對 `provenance-reference` 的處置，沒有走 spectra change；`spectra validate --specs` 全部 valid。

## 測試

- `WorkDateProvenanceTests`（7 支）：`date` 在場、缺席、`n.d.` 三種讀法都寫得進；帶 value 拒絕；離線來源走帶 digest 的 judgement，空 rests-on 拒絕；`date` 與 `fields.date` 是兩格、可並存；`title` 仍拒，訊息列得出含 `date` 的值域。
- `WorkDateReferenceFormatGateTests`（4 支）：門檻是 20 且不超過 supported；format 19 拒寫而訊息的數字來自常數；format 19 照收 `fields.<鍵>`；format 20 寫得進、讀得回、沒有 quarantine。
- `EnrichmentDateAuthorsProvenanceTests`（6 支）：來源齊備寫 `date`；`.unavailable` 值照補、理由原樣；`authors` 不寫而理由點名佔用者，硬寫一筆同名 retrieval 也過不了值域；來源不齊只報 `provenanceSkipped`；沒給來源什麼都不說；`date` 已有值時沒有 reference、也沒有省略。
- `EnrichDateProvenanceServiceTests`（3 支）：format 20 dry-run 說會寫、apply 真的寫；format 19 值照補、寫入不失敗、dry-run 就說出理由；`authors` 的理由進 payload。
- `EnrichCLITests.testSourceLineAgreesWithPayload` 改寫（真 binary）：只補 date 時說會寫 1 筆；只補 authors 時逐欄印理由；store 退到 format 19 時 dry-run 就印出 format 與門檻。
- `StdioE2ETests.testEnrichWritesDateReferenceAndNamesWhyAuthorsHaveNone`（真 `akashic-mcp`）：apply 後 `provenanceWritten` 是 `["date"]`、`provenanceOmitted.authors` 點名 `field: authors`、store 裡只有那一筆 reference；`testEnrichSchemaListsEverySourceField` 補斷言描述說出 `provenanceOmitted`。
- `Format13GateTests`、`KnownLayerEvolutionTests` 的 supported 釘改成 20。
- **負控**（改壞、跑、以反向編輯還原、`cmp` 對備份逐位元組相同）：
  - 拿掉 format-20 寫入閘 → `testFormat19RefusesDateReference` 紅。
  - 拿掉 `date` 格的 value 檢查 → `testDateReferenceTakesNoValue` 紅。
  - 拿掉整個 `date` 格 → 8 支紅（三種讀法、judgement、兩格並存、enrich 的落地、format 20 讀回）。
  - service 的事前判斷一律 `.writable` → service 測試與 CLI 測試的 format 19 段紅。
  - 拿掉 `authors` 的省略理由 → 核心、service、CLI、stdio 各一支紅。

**真 binary 對照**（沙箱 store，`AKASHIC_HOME` 另設）：format 20 的 store 上 `enrich --apply` 寫出 `field: date` 的 retrieval。把同一份 store 的 marker 改回 19、交給 PATH 上的 format-19 世代 binary（`~/bin/akashic`）：`validate` 報那一筆 quarantine、rc=1，`query` 印「（無結果）」、rc=0，那筆 work 消失。新 binary 對 format 19 的 store：date 照補、沒有 reference、逐欄印理由，舊 binary 讀那份 store `validate` rc=0。

## 升級前置（部署由使用者執行）

1. **先升三個 binary**：CLI（`akashic`）、`akashic-mcp`、App，全部換成 v20 世代。任何一個還是 v19，就不要進第 2 步：那個 binary 讀到 `field: date` 會把那筆 work 整檔 quarantine，而且查詢面不報錯。
2. **再把 live store 的 marker 改成 20**：`store.yaml` 的 `format:` 手改成 `20`。2026-09-28 實測 live store 是 **format 18**。v20 世代的 binary 也懂 19 的形狀，所以直接從 18 改成 20 即可，不必停在 19。
3. marker 改好之前不要 push store repo（同 15～19 的理由：寫入閘讀 marker、不讀 binary 能力，已寫入的記錄只有 marker 防得住其他 clone 的舊 binary）。
4. **順序會影響資料**：在 marker 到 20 之前跑 `enrich`，date 會照補但不留來源；升級之後重跑也補不上，因為 date 已經在，add-only 不再動它。要記來源就先升級再補。

## 誠實邊界

- **`authors` 的來源仍然沒有地方記。** 不寫是裁決，不是遺漏；若日後要記，要另開一格，並替會被拆、被移除、被升格而位移的作者位設計定位。那是另一張 issue 的事。
- **#517 的 `fields.<鍵>` 那一格至今沒有自己的 format 閘。** `assertIdentifierReferencesWritable` 只認三個識別碼欄位，format < 17 的 store 仍寫得進 `fields.<鍵>` 的 reference，而早於 #517 的 format-16 binary 讀到會 quarantine。它沒出事是因為 #517 落地一小時後 format 17 就 bump 了，那是順序的巧合。本次的 `date` 格不依賴巧合，那個既有缺口不在 #655 範圍，另案。
- 「format-19 binary 會 quarantine」除了依程式碼推得（HEAD 的 `default` 分支），也用 PATH 上的 format-19 世代 binary 實跑過一次（見上方真 binary 對照）；它不是在乾淨 checkout 的 HEAD 上重編出來的 binary。
- `provenanceNotWritten` 那一格仍沒有專屬測試（要造出單筆寫入失敗需要注入 I/O 錯誤），同 #542 的既有邊界。

## 規則

- `entity-backlink-completeness`：第 15 條邊的值域加 `date`，「兩次擴充」改為「三次擴充」並補 #655 的四點。
- `mcp-cli-parity`：`akashic_enrich` 列補 #655 的重新確認（裁決不變、契約有改：`date` 的 reference、`authors` 不寫、`provenanceOmitted` 兩面同一條 service 路徑）；#542 那句「date／authors 不產生 reference」劃掉並指向本列末。
- `two-kinds-of-edits`：`enrich` 列補 #655 的重新確認：種類不變，`date` 的來源是 retrieval；`authors` 那一格只收 judgement，一個決定論式的補值面寫不進去。
- `zero-instance-guards`：**不加列**。新增的是 format bump 的寫入閘，15～19 的同形閘都沒有列；那張表管的是零實例的守衛、欄位、Requirement 與半吊子路徑，format 閘是版本機制本身。
