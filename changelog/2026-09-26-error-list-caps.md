# 2026-09-26 錯誤訊息裡的清單有筆數上限（#562）

`AkashicService` 有幾處錯誤訊息把一整串 citekey、欄位名或 id 接起來，每一項有字數上限，但**項數沒有**。一次送幾千個不存在的 citekey，錯誤訊息就等比變長；而錯誤訊息和一般輸出一樣會進 LLM context。#236／#388 對輸出設了預算（MCP 48 KB、items 截 20 筆並揭露 `truncated`），錯誤訊息一直不在那張清單上。

- 這幾處改走既有的 `listCapped`：只列前 10 項，超過時附「…（共 N 項）」。
  - `export` 指名的 citekey 查無；
  - `create_entry` 的非法欄位名；
  - 三處 index rebuild 失敗的報告：resolve-people 的 writeFailed、confirmWriteFailed 與未套用；import-zotero 的 writeFailed；enrich 的已落地清單。
- 判準照 issue 最後一節的現算法：`displaySafe…(…, max: N) }.joined(separator` 在 `AkashicService.swift` 裡已經沒有命中。其餘 `joined` 是固定列舉（tier、EntityKind）、已截斷的註冊表 key，或每桶已經 `listCapped` 的書寫系統衝突，都不是這個形狀。
- 同批修 `Server.swift` 的 `argDict`（#561）：非字串值的鍵名清單原本是先組成一個字串再插值，消毒守衛認不出它，現在改成守衛認得的「逐項 `displaySafeInvisible` 再 `joined`」寫法，前 10 個鍵。
- 分隔符從 `", "`／`"; "` 統一成 `"、"`（`listCapped` 的既有分隔）。沒有測試或呼叫端依賴舊分隔。
- 測試：`ExportBoundaryTests.testMissingCitekeyListIsCappedWithTotal`（25 個不存在的 citekey → 列到第 10 個、不列第 11 個、揭露「共 25 項」）。負控：把 export 那處改回無上限，2 個斷言失敗。
