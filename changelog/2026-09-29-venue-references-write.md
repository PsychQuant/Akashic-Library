# 2026-09-29 venue 的 ISSN 帶得了角色、venue 的 references 有寫入面（#587）

## 問題

查證取得的 ISSN 寫得進 venue（`add_issn`／`add_venue.issn`，#394），但它的**角色**與**來源**進不了 store。兩個缺口都在寫入面，模型層早就準備好了：

- `issn[].qualifier`（print／electronic／linking）自 format 13 就在，`ISSN.init` 卻把角色一律設成 nil，兩個寫入面都不走 `withQualifier`。live store 2026-09-29 實測 59 個號、9 個帶角色（print 4／electronic 4／linking 1），全來自 `migrate-identifiers`——按需補這條路寫出來的每一筆都比遷移資料少一格。
- `Venue.validateReferenceAttachment` 早有 `case "issn"`（#394 §5：reference 要帶 value 指名支持哪一個號），但 `akashic_update_venue` 沒有 `references` 參數。venue 的 references 只有 verdict 一族、`paginated` 判定、合併與 rename 的遷移在寫；沒有任何工具面寫得進 `{field: issn, value, kind: retrieval}`。

`akashic-verify-venue` 自 #556 起要 LLM 把查到的號寫進 venue，而角色與來源只能留在查證報告裡；同檔「承重頁面存檔」一段曾寫「寫入 venue 的 references」，那條指令執行不了。#556 R2 verify 另補兩點：`add_venue.issn` 同樣記不下角色（建檔那一刻正是 print 與 electronic 一起抄回來的時刻），ISSN 的空白項靜默略過、沒有 dropped 桶。

## 改了什麼

**ISSN 的角色**（`add_issn`／`add_venue.issn`，兩面同一個解析函式 `parseISSNItems`）：一項是 `NNNN-NNNN`，或 `NNNN-NNNN (print|electronic|linking)`。

- 寫法取遷移讀的那種（`1939-1455(Electronic)`），切法是 `IdentifierTokenizer` 的同一套；新增的 `IdentifierTokenizer.singleQualified` 比遷移嚴：恰好一個號、至多一個緊跟的註記，括號的開、閉與註記三個計數都要等於「這個號有沒有註記」。前置的註記、兩個註記、未閉合、一項兩個號，都拒絕。
- 角色必須是 ISSN 標準的三個之一（`ISSNMedium(loose:)`，大小寫不拘），入庫寫封閉值域的寫法（`print`）。遷移對認不出的寫法（`Online`）保留原值並在 validate 報 warning；寫入面收的是呼叫端這一次說的話，不寫一個 validate 會報的值。
- 整串先試 `ISSN(_:)`，它本來就收的寫法（`0003 066X`、`1935990x`）照收。
- 已在的號沒有角色、這次帶了：補上（填一個缺席的格），報在 `issnMediumRecorded`。已記的角色與這次不同（含認不出的舊寫法）、或同一次呼叫同一個號兩個角色：整批拒絕、零寫入——改寫既有角色不在本面。
- 報告多三個桶：`issnAlreadyPresent`（本來就在、沒有新資訊，先前靜默略過）、`issnMediumRecorded`（號 → 角色）、`issnDropped`（整項空白）。`add_venue` 多後兩個。
- `add_issn` 與 `remove_issn` 同一個號的矛盾檢查改認解析後的號：先前用 `ISSN($0)` 比，帶角色的寫法對它是 nil，矛盾會漏過去。

**venue 的通用 `references`**（CLI `update-venue --references '<JSON 陣列>'`／MCP `akashic_update_venue.references`，同走 `updateVenue`）：

- append-only，以 `byteExactKey` 略過位元組相同的（同一次呼叫裡的重複也算），報 `referencesAdded`／`referencesAlreadyPresent`。物件鍵名與 `update_person` 的 references 相同（`media_type`／`statement`／`rests_on`）。
- 形狀驗證走 `ProvenanceReference` 的平面 init（YAML decode 的同一個入口）：擷取型四欄必要、兩種互斥、判斷型 rests-on 非空、digest 形狀、空內容的 digest。寫入面只多四件事：鍵名嚴格（不認得的鍵拒收）、`kind` 要與給的欄位一致、歸屬（三個 verdict 欄位只經 `resolve-venues`、`paginated` 只經 `paginated`／`clear_paginated`——那兩條路同時改記錄的值與判定史）、上限（一次 200 筆、statement 4,096 位元組、rests_on 20 個、其餘字串 65,536 位元組）。
- `status` 必填，不預設 200（#542 R2 對 `enrich` 裁掉過同一個預設）；boolean 與非整數拒收——MCP 的 JSON `true` 經 `valueToAny` 是 NSNumber，不得被當成 1。
- `field: issn` 的 value 以正規形入庫、必須是一個合法的號（帶角色的寫法在這裡拒收，角色走 `add_issn`）；`names`／`authorized` 的 value 以記錄上的拼法入庫（相等看 canonical）——只差 NFC／NFD 或空白的兩筆否則是位元組不同的兩筆，#582 的重複 reference 掃描會報它們。
- 附著（那個號、那個名字在不在記錄上）在合進記錄之後以 `validateReferenceAttachment` 驗——載入的同一個驗證。所以同一次呼叫 `add_issn`／`add_names` 加的也可以被指向。寫入時的 canary 本來也擋得住，先驗是為了讓錯誤說出是 `references` 這個參數。
- 指向同一次 `remove_issn` 的號：兩句矛盾的話，在讀 store 之前拒絕。
- 任一筆不合，整批拒絕、零寫入，同一次呼叫的其他參數也不寫。只看參數的部分在 `updateVenueArguments`，CLI 的 `validate()` 在開 store 之前呼叫它（用法錯誤 64）。

**檔案**：`Sources/AkashicMCPKit/VenueReferenceWrites.swift`（新，兩個解析函式）、`AkashicService.swift`（`addVenueArguments`／`addVenue`／`updateVenueArguments`／`updateVenue`）、`Sources/AkashicCore/IdentifierTokenizer.swift`（`singleQualified`）、`Sources/akashic/VenueCommand.swift`（`--references`、兩個 help）、`Sources/akashic-mcp/Server.swift`（`references` 參數、`argObjectList`、三段描述）、`Sources/akashic/WriteGateRulings.swift`（`update-venue` 那一格的理由提到 references 與角色；裁決不變）。

## 測試與負控

- `VenueReferenceWriteTests` 18 支（服務層）：角色寫入、建檔帶角色、補角色、本來就在的回報、角色衝突整批拒絕、八種壞形狀、既有寫法照收、空白項回報、帶角色的加與移除矛盾；reference 寫入（retrieval／judgement）、同一次呼叫號＋角色＋來源、名字定位值存記錄上的拼法、位元組去重、verdict 與 `paginated` 拒收、27 種壞 reference 各自說出自己的理由且零寫入（比整個 entities 目錄的位元組）、指向被移除的號、只看參數的檢查不碰 store。
- `UpdateVenueReferencesCLITests` 2 支（真 binary）：CLI 面落地與回讀；六種 argv 錯誤是 64、早於開 store。
- `StdioE2ETests/testVenueReferencesAndMediumReachTheService`（真 binary）：MCP 面落地、`akashic_venue` 回讀帶 `medium`、非陣列與非物件元素拒絕、JSON `true` 的 status 拒絕。
- 負控（改壞 → 跑 → 反向編輯還原、`cmp` 逐位元組相同）17 組全部轉紅：角色不寫、不補角色、衝突不拒、`singleQualified` 的三個計數、kind 一致性、verdict 歸屬、`paginated` 歸屬、位元組去重、附著驗證（第一次沒紅——canary 以同一句話擋下；補上「references 附不上」的斷言後轉紅）、空白項回報、號正規化、帶角色的矛盾、status 的 boolean、references 對 remove_issn 的矛盾、名字定位值的拼法、MCP 的物件陣列解析、CLI `validate()` 的 JSON 解析。

## 誠實邊界

- **venue 的 reference 沒有移除面**：`--remove-issn` 的連帶刪除之外，寫錯的只能手改 YAML（person 側同）。
- **改寫既有角色沒有面**：已記的角色（含遷移留下的 `Online` 這種認不出的寫法，validate 會報）與這次不同時拒絕；要改只能 `remove_issn` 再 `add_issn`，而移除會連帶刪掉那個號的 references。live store 認不出的角色 0 筆。
- **與 `update_person` 的 references 有三處不同**：`status` 必填、鍵名嚴格、有上限。person 側不動（改它是改既有呼叫端的契約），要對齊另案。
- 同一次呼叫裡同一個號寫了兩次（`0003-066x` 與 `0003-066X`）照舊合成一筆、不另回報。
- `add_venue` 不收 `references`：建檔之後用 `update_venue` 附。
- 來源要有原始位元組的存檔才寫得進去；WebFetch 回的是模型改寫稿（#591），所以 `akashic-verify-venue` 這一格多半仍只能把來源留在報告裡。
- 沒有 store format bump：`issn[].qualifier` 與 `field: issn` 的 reference 都是 format 13 的既有格（`field: issn` 的寫入閘照舊擋 format < 13）。

## 規則與文件

- `mcp-cli-parity`：`akashic_update_venue`、`akashic_add_venue` 兩列補 #587 的契約變更（裁決不變），含與 `update_person` 的差異。
- `two-kinds-of-edits`：加一列 `update-venue --references`（AI 判定型，沒有具名逆操作）。
- `docs/store-format.md` §3.5 新增「venue 的 `references`：可附著的格與寫入面」，含 ISSN 角色的寫入規則。
- `akashic-verify-venue`：報告第 4 項的角色、寫法（帶角色的 `add_issn`、`references` 附來源）、誠實邊界與「承重頁面存檔」改寫——卡住的是原始位元組，不是寫入面；`akashic-venue-works` 兩處 #587 的歷史註記補上「之後寫得進去」。
