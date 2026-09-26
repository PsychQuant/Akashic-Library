# 2026-09-26 MCP 的畸形清單／物件參數整個呼叫拒絕（#561）

`Server.swift` 的 `argList` 遇到非陣列就回 `[]`，遇到陣列裡的非字串元素則用 `compactMap` 丟掉。實例：
- `akashic_update_venue` 的 `authorize: "Psychometrika"`（少一層括號）變成 `[]`，結果零寫入，卻回報成功，三個結果桶全空；
- `["名A", 42]` 變成 `["名A"]`，繞過了「同一書寫系統送兩個名字就整批拒絕」那道閘；
- `akashic_add_venue` 的 `issn: "0003-1305"` 建出一筆沒有 ISSN 的 venue，沒有任何錯誤。

- `argList` 本身改成嚴格版：鍵不在時仍回 `[]`；鍵在但不是字串陣列，或陣列裡有非字串元素，就整個呼叫拒絕、零寫入。空陣列仍然合法，對這些參數來說「送了零個」與「沒送」同義。issue 點名四個參數，這裡是 34 個呼叫端一次改，因為病在函式本身，不在那四個參數。立場與同檔 `argFlag` 對畸形 boolean 的處理一致。
- `argDict` 同形：`create_entry` 的 `fields: {"volume": 12}` 先前被 `compactMapValues` 靜默丟掉那個欄位，這是 `lossless-intake` 說的「靜默是最糟的形式」。現在非物件或任何非字串值都拒絕，訊息點名是哪些鍵，並提示「數字請寫成字串」。
- 測試：真 binary `StdioE2ETests.testMalformedListAndDictArgumentsAreRefused`，涵蓋裸字串、陣列混數字、`add_venue` 的裸字串 issn（並確認沒有建出記錄）、`fields` 的數字值。負控：把 `argList` 還原成寬鬆版，4 個斷言失敗。

## R1 verify 之後（6 席，0 HIGH、11 MEDIUM）

R1 的四席都指出同一件事：病不只在 `argList`。同檔還有別的讀取器繞過它、把畸形值折成預設值。最尖的一例是：`update_person`、`enrich_from_zotero`、`import_wos` 的 `dry_run: "true"`（字串）會被折成 false，呼叫端要的乾跑變成真的寫入。這正是 `argFlag` 的註解本來就點名的失敗。

- **本檔所有具型別的讀取器改成同一條規則**：鍵不在＝沒給；給了而型別不對，整個呼叫拒絕、零寫入，**JSON null 也算型別不對**。
  - `arg()`（字串）與 `argInt()`（整數）改成拋錯版。先前 `import_zotero` 的 `library_id: "5"` 會靜默落回預設的 Zotero 庫，把另一個庫匯進來。
  - `dry_run`、`csv`、`clear`、`clear_paginated` 的手寫讀取改走 `argFlag`。
  - `enrich_from_zotero` 的 `citekeys` 原本是手寫的寬鬆讀取器，改走 `argList`。
  - null 歸「型別不對」而不是「沒給」，理由與 `argFlag` 既有的立場相同：null 若被當成沒給、折成預設 false，乾跑就變成寫入。代價是用 null 表示「省略」的 client 會被拒；錯誤訊息點名是哪個鍵，拿掉它即可。
- `argDict` 的拒絕訊息補上總數（「共 N 個鍵不是字串」），仍只列前 10 個。
- 描述舊 null 行為的註解與四則「空陣列或 null」的錯誤訊息同步改寫。
- 上一節說 `argList` 的「送了零個」與「沒送」同義，這句太概括：對用 `argList` 讀的參數兩者結果相同；需要分辨的參數用 `argStrictList`，或在呼叫端先看鍵在不在。
- 呼叫點數：上一節寫 34，實際是 35（R1 verify INFO）。
- 已知邊界：MCP SDK 把形如 `data:…;base64,…` 的字串解成 `.data` 而不是 `.string`，這類值現在以「必須是字串」被拒。名字、citekey、路徑不會是這個形狀。
- 測試：`StdioE2ETests.testMalformedScalarArgumentsAreRefused`（真 binary）涵蓋以下情形，並比對 `entities/` 全部位元組前後相同：
  - `dry_run: "true"`、`dry_run: null`；
  - `citekeys` 混數字；
  - `library_id: "5"`；
  - 字串參數給數字與 null。
  負控：Server.swift 換回 R1 之前的版本，7 個斷言失敗。MCP 測試 367 支全綠。
