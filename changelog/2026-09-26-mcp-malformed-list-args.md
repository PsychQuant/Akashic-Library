# 2026-09-26 MCP 的畸形清單／物件參數整個呼叫拒絕（#561）

`Server.swift` 的 `argList` 遇到非陣列就回 `[]`，遇到陣列裡的非字串元素則用 `compactMap` 丟掉。實例：
- `akashic_update_venue` 的 `authorize: "Psychometrika"`（少一層括號）變成 `[]`，結果零寫入，卻回報成功，三個結果桶全空；
- `["名A", 42]` 變成 `["名A"]`，繞過了「同一書寫系統送兩個名字就整批拒絕」那道閘；
- `akashic_add_venue` 的 `issn: "0003-1305"` 建出一筆沒有 ISSN 的 venue，沒有任何錯誤。

- `argList` 本身改成嚴格版：鍵不在時仍回 `[]`；鍵在但不是字串陣列，或陣列裡有非字串元素，就整個呼叫拒絕、零寫入。空陣列仍然合法，對這些參數來說「送了零個」與「沒送」同義。issue 點名四個參數，這裡是 34 個呼叫端一次改，因為病在函式本身，不在那四個參數。立場與同檔 `argFlag` 對畸形 boolean 的處理一致。
- `argDict` 同形：`create_entry` 的 `fields: {"volume": 12}` 先前被 `compactMapValues` 靜默丟掉那個欄位，這是 `lossless-intake` 說的「靜默是最糟的形式」。現在非物件或任何非字串值都拒絕，訊息點名是哪些鍵，並提示「數字請寫成字串」。
- 測試：真 binary `StdioE2ETests.testMalformedListAndDictArgumentsAreRefused`，涵蓋裸字串、陣列混數字、`add_venue` 的裸字串 issn（並確認沒有建出記錄）、`fields` 的數字值。負控：把 `argList` 還原成寬鬆版，4 個斷言失敗。
