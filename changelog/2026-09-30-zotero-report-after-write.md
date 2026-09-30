# 2026-09-30 import-zotero 的「已覆寫／已拿掉」清單只記寫進去的那一筆（#702）

`ZoteroImporter` 主來源的更新分支，在寫入之前就把該筆記進 `authorsPreserved`、`authorsOverwritten` 與 `fieldsRemovedByPull`。目的檔被隔離（`quarantineConflicts`）或寫入擲錯（`writeFailed`）的那一筆因此同時出現在失敗清單與「作者已覆寫、欄位已拿掉」清單，而那一筆沒有寫。#696 R1 起 MCP 回應也帶這兩個鍵，兩個面都看得到這個誤報。

## 改了什麼

- `ZoteroImporter.run` 的主來源更新分支：拿掉的欄位、拿掉的識別碼、作者是保留還是覆寫，先算進區域變數，`guardedWrite` 成功之後才進報告。改寫的內容與寫入的時機都沒變，只改報告記下的時機。
- 附加來源、新建、orphan 標記、清除 orphan 標記這幾個分支本來就在寫入成功之後才記，沒有同形的問題，不動。
- `ImportReport` 三個欄位的說明、`AkashicService.importReportCappedLists` 的說明、`mcp-cli-parity` 的 `akashic_import_zotero` 列（第 (c) 點劃掉、列末加 #702 一段）、`plugin/CHANGELOG.md` 同步改寫。

## 測試與負控

`ZoteroImportReportAfterWriteTests.swift` 加兩支，各讓一筆寫不進去、另一筆寫得進去：

- 隔離：文章的 `entries/<citekey>.yaml` 放一份讀不出來的 legacy 殘留，load 隔離它，importer 拒寫這個 citekey。斷言文章只在 `quarantineConflicts`，不在 `authorsOverwritten`，`fieldsRemovedByPull` 只算寫進去的書；書照常在 `authorsPreserved`。
- 寫入擲錯：書的檔案帶一個 encode 平移不變式會拒寫的未知欄位（`testWriteFailureContainedPerItem` 同一個手法）。斷言書只在 `writeFailed`，不在 `authorsPreserved`；文章照常在 `authorsOverwritten`。

修之前兩支都紅（4 個斷言，失敗的那一筆出現在清單裡、`annotation` 算成 2），修之後綠。

負控（反向編輯、`cmp` 確認還原）：欄位移回寫入之前記 → 兩支紅；`authorsPreserved` 移回寫入之前 → 寫入擲錯那支紅；`authorsOverwritten` 移回寫入之前 → 隔離那支紅；寫入成功後不記 `authorsPreserved` → 隔離那支紅（正面也釘住，「一律不記」過不了）。

## 誠實邊界

- 識別碼被拿掉（`fieldsRemovedByPull` 的 `doi`／`pmid`／`isbn`）在寫入失敗時不記，這一半沒有專屬測試；它與 `fields` 的減法在同一個 `if` 裡，成功那一半由既有的 `testClearingAnIdentifierUpstreamIsReported` 釘住。
- `residualFields` 仍在每個 Zotero 條目讀進來時就計數，不論這一趟有沒有寫（含未變動與被多筆宣稱而略過的條目）。它的說明是「以原名入庫的欄位」，對寫入失敗的那一筆不精確。它的語意是「讀到的條目帶哪些未對映欄位」，改成只算寫入成功的會連未變動的條目一起拿掉，不在這次範圍。

## R1 verify 修正（2026-09-30）

六席（requirements、logic、security、regression、devil's advocate、Codex）。與本 issue 有關的兩個 LOW；Codex 與 security 席沒有發現。

### 識別碼那一半補上測試

logic 席與 DA 席實測：把識別碼的記錄移回 `guardedWrite` 之前，三支相關測試都照綠。`testWriteFailureIsNotReportedAsPreservedOrPruned` 的書另帶一個 Zotero 沒給的 DOI（pull 會把它清掉），而那一筆寫不進去，`fieldsRemovedByPull` 必須不含 `doi`。反向編輯（識別碼的記錄移回寫入之前）時這一支紅，量到 `["annotation": 1, "doi": 1]`。上面〈誠實邊界〉第一條因此不再成立。

### 寫了之後才擲錯的那一筆

DA 席指出：`LibraryStore.writeEntry` 先寫 `entities/<id>.yaml`，**之後**才刪 #631 搬移的 legacy 檔。刪不掉時內容已經寫進去，`guardedWrite` 卻回 false，三個清單都不記——方向從誤報變成漏報，issue 與本檔的前提「寫入擲錯的那一筆沒有寫」在這個角落不成立。

- `writeEntry`／`writePerson` 刪 legacy 檔失敗時改擲 `StoreIOError.legacyCopyNotRemoved`（先前是 Foundation 的原始錯誤）。訊息說已寫入哪個檔、哪個 legacy 檔沒刪、原因，以及「同一筆記錄現在有兩份，load 會把它標成無法唯一定位」。`atomicWrite` 本身在搬進目的檔之後沒有會擲錯的步驟，所以這是寫入之後唯一會擲錯的地方。
- `ZoteroImporter.guardedWrite` 遇到它時回 true：那一筆照寫入成功記（`updated`、`authorsOverwritten`、`fieldsRemovedByPull`），`writeFailed` 同時帶那句訊息。`ImportReport.writeFailed` 的說明寫明這個例外；CLI `import-zotero` 那一行的標題從「單筆寫入失敗，已略過續跑」改成不說「已略過」。
- 新測試 `testWriteThatLandsBeforeLegacyRemovalFailsIsReportedAsWritten`：文章只剩一份受 git 追蹤的 legacy 檔，`entries/` 設成唯讀，import 之後內容在 `entities/`、legacy 檔還在，文章在三個清單裡，`writeFailed` 的訊息以「已寫入」開頭。以 root 執行、權限擋不住刪檔時 skip。
- 反向編輯：`guardedWrite` 把它當成沒寫 → 新測試紅（三個清單空）；`writeEntry` 刪 legacy 失敗時擲原始錯誤 → 新測試紅。

**範圍**：`legacyCopyNotRemoved` 對所有經 `writeEntry`／`writePerson` 的寫入者都會擲，它們的錯誤訊息因此說得出「已寫入」；但只有 import-zotero 的報告改成照寫入成功記。其餘寫入者（resolve-people、enrich 等）遇到它時仍把那一筆算成失敗，沒有在這一輪逐一檢查。

### residualFields 的說明

`ImportReport.residualFields` 的說明補上計數的時機（讀進每個條目時，不論寫沒寫），與上面〈誠實邊界〉第二條一致。
