# 2026-10-01 index 重建遇到同一筆記錄兩份時以 entities/ 那份為準、略過 legacy 拷貝並回報（#709）

#631 寫一筆既有記錄時會把 `entries/<citekey>.yaml`／`people/<key>.yaml` 搬進 `entities/<id>.yaml`：先寫新檔、再刪舊檔。舊檔刪不掉時同一筆記錄留下兩份（#705 把這一筆記在 `writtenWithLegacyCopy`）。兩份一起進 index：work 撞 `entries.citekey` UNIQUE（改名留下的舊 citekey 則撞 `entries.uuid` PRIMARY KEY），整次重建失敗。寫入之後會重建 index 的呼叫因此全部以錯誤收場，`writtenWithLegacyCopy` 只能附在錯誤訊息裡；而只要 store 裡有一筆留下兩份，其他記錄的寫入也一樣失敗。person 的 people 表以 key 為主鍵、`INSERT OR IGNORE` 留下列舉順序的第一筆（#670），改名留下的舊 key 另成一列。

使用者 2026-09-30 裁決：index 重建以 `entities/` 那份為準、略過 legacy 拷貝並回報。代價（使用者看過）：有人手改過 legacy 那份時，index 看不到那次修改，只剩 validate 的警告。

## 「同一筆記錄」的判準

只有一份，在 `LibraryStore.markLegacyCopiesShadowedByEntities`（`Sources/AkashicStoreIO/ShadowedLegacyCopy.swift`）：

> store 是 entities 佈局（format ≥ 2），一筆 work 從 `entries/` 讀進來（person 從 `people/`），而 `entities/` 讀進來的記錄裡有**同一種、同一個 id** 的一筆。

- **id，不是 citekey 或 key**：`entities/` 的檔名就是 id，load 已驗檔名與記錄的 id 相符；#631 的搬移把內容寫進 `entities/<它的 id>.yaml`，刪不掉時留下的是同一個 id 的舊檔；改名不換 UUID，留下的舊檔 citekey／key 是改名前的。反過來，兩筆**不同**的記錄共用 citekey 時 id 不同，不在此列——它們照舊是 `crossRecordIssues` 的 error，work 那一對照舊讓重建撞 UNIQUE。
- **同一種**：`entities/` 也住 organization、venue、divergence；work 與 person 共用一個 id 不是同一筆記錄（#631 的目的檔檢查當它是另一種記錄）。
- **format ≥ 2**：format 1 的 `entries/`、`people/` 是正典位置，不是殘留（同 #641 的 `annotateFileSituations`）。

load 在兩條路徑（讀磁碟的 `load()` 與唯讀快照的 `decodeCaptured`）都標：它只需要每筆記錄是從哪個檔讀進來的，不讀磁碟也不問 git。標記是 `FileSituation.shadowedLegacyFile`（被讀進來的那個 legacy 檔的相對路徑），與 #641 的 `unwritableReason` 同一個型別——load 對檔案處境的觀察，不參與相等、不序列化。

## 改了什麼

- **index 重建**（`LibraryIndex.rebuild`）：插入之前濾掉帶標記的 work 與 person。`IndexStats.entries`／`people` 與 `index_identity.entry_count` 算的是進了 index 的筆數；新欄位 `IndexStats.skippedLegacyCopies` 列出略過的每一份（kind、legacy 那份的鍵、id、legacy 檔、`entitiesFile`），由 `LibraryLoad.shadowedLegacyCopies` 從同一個標記導出。
- **#645 的記錄位元組**：legacy `people/` 在 entities 之後讀，先前會蓋掉 entities/ 那一份的位元組；現在帶標記的那筆還原成 entities/ 的——預算預警量的是之後會長的那個檔。這是同一個判準的第二個讀者（「兩份裡哪一份是這筆記錄」），不是另一條規則。
- **回報**：
  - 重建結果印出來的地方（CLI `import-zotero` 與 `migrate` 的「index rebuilt」那一行）加上「略過 N 份 legacy 拷貝」的附記；只給筆數，是哪幾筆由下一條逐筆說。
  - validate 既有的 #641 警告（「work／person「…」的檔案寫入時會被拒」）對有 legacy 拷貝的那一筆多一句「index 以 entities/ 那份為準、略過 legacy 拷貝——它的內容 index 看不到」。**沒有另開一族訊息**：這一句說的就是那則警告在講的那一對，而那則警告經 `crossRecordIssues` 已經到得了 CLI `validate`／`doctor`、MCP `akashic_doctor` 與 App——三面同一份來源，不必加 MCP 回應鍵（tools/list 只剩 3 bytes，加鍵要改說明）。
  - 同一對的「UUID … 被 2 筆 entry 共用」error 原本說「index 的 PRIMARY KEY 會靜默丟掉其中一筆」，對這一對不再是真的；改成「其中 legacy 拷貝由 index 略過、以 entities/<id>.yaml 為準」。其他共用 UUID 的情形（兩筆不同的記錄）訊息不變。
  - `writtenWithLegacyCopy` 每筆的附記（`LegacyCopyLeft.message`）原本說「刪掉之前 index 重建會撞重複」，改成「刪掉之前 index 以 entities/ 那份為準、略過 legacy 拷貝」；person 那一格原本沒有附記，現在也說同一句。
- **不變的**：
  - 那一筆本身照舊寫不進去——`unlocatableCitekeys`／`unlocatablePersonKeys` 仍收它（#641），load 仍把兩份都讀進來。
  - `crossRecordIssues` 的 severity 不變：那一對的 UUID／citekey 重複仍是 error，所以 doctor 照舊不重建 index，改名與合併（`assertNoCrossRecordErrors`）照舊整個 store 停下——後者是 #35 專為「雙佈局並存」設的閘。
  - 工具說明沒有改：沒有一句說 work 的殘留會以錯誤收場（`legacyCopyNote` 的「錯誤時列在訊息前」仍然成立）。tools/list 51,997 bytes，改前改後相同（預算 52,000）。
- 文件：`mcp-cli-parity` 表下的 #705 段（「有記錄的後果」劃掉、補 #709）、`plugin/CHANGELOG.md`（新增 #709 一節、#705 的錯誤回應那一條加註）、#705 的兩份 changelog（誠實邊界第一條、R1 的「仍未處理」第 2、3、35 列）加補記。`docs/store-format.md` 沒有描述 index 對兩份的處置，不動；`zero-instance-guards` 第 40 列說的是 #641 的寫入封鎖，與本改動不矛盾，不動。

## 測試

先前以「兩份並存 → index rebuild 撞 UNIQUE」當前提的測試，改動之後第一次跑紅了 11 支（前提不再成立）。依它們原本要釘的東西分兩類處理：

- **要釘「寫了、不算失敗」的**：改斷言成功與結構化的鍵——`LegacyCopyCLITests.testTagOnALegacyWorkSucceedsWithTheKeyInItsJSON`（新，stdout 仍是一份 JSON、結束碼 0）、`testRenameFinishesAndReportsTheLegacyCopy`（結束碼 0，附記說的是 #709 之後的事）、`WrittenWithLegacyCopyTests.testResolvePeopleApplyDoesNotListItAsAWriteFailure`／`testEnrichDoesNotListItAsAWriteFailure`（回成功、沒有 `writeFailed`、算在 `applied`／`written`）。
- **要釘「寫了之後別的步驟失敗，報告不丟」的**：那條路徑還在，改用真的重複造出失敗——store 裡另放兩筆**不同**的記錄共用一個 citekey（#709 不替它們選一筆）：`LegacyCopyCLITests.testTagThatFailsAfterWritingStillReportsIt`、`WrittenWithLegacyCopyTests.testALaterRebuildFailureStillCarriesIt`（新）與兩支 import 的交接測試、`StdioE2ETests.testLegacyCopyLeftSurvivesALaterFailure`、`testImportRebuildFailureKeepsEveryLegacyCopyUntruncated`（真 binary、三十二筆）、`ImportZoteroReportSurfaceTests` 的三支 rebuild 失敗路徑。這幾支同時證明真的重複照舊讓重建失敗。

新增：

- `IndexPrefersEntitiesCopyTests`（store 層，10 支）：work 同 citekey 的一對（index 那個 id 只有一列、標題取 entities/ 那份、`skippedLegacyCopies` 具名、`entry_count` 一致）；改名留下的一對（只剩新 citekey、兩個 citekey 都仍無法唯一定位）；兩筆不同的記錄共用 citekey（一份 entities／一份 legacy，與兩份都在 entities/，都照舊失敗、沒有標記）；同一個 id 不同種（不標）；format 1（不標）；person 同 key（index 的名字取 entities/ 那份）；person 改名（舊 key 不進 index、仍寫不進去）；記錄位元組取 entities/ 那份；validate 的警告與 UUID error 的新措辭、error 級不變；真的共用 UUID 的訊息不變。
- `StdioE2ETests.testALegacyWorkLeftoverNoLongerBreaksTheIndex`（真 binary）：`akashic_tag` 對 legacy work 回成功、`writtenWithLegacyCopy` 是結構化的鍵；之後手改 legacy 那份的標題，再對**另一筆**記錄 `akashic_tag`——照常成功；index 那個 id 只有一列，標題是 entities/ 的「Legacy」而不是手改的「Hand edit」，tag 是只在 entities/ 那份的 `x`；再 tag 同一筆被拒（「無法唯一定位」），檔案沒寫。
- `ZoteroReportCLITests.testImportPrintsTheLegacyCopyLeftOnTheSuccessSide` 多兩個斷言：結束碼 0、「index rebuilt」那一行說「略過 1 份 legacy 拷貝」。

## 負控

反向編輯一行 → `swift test --filter` 跑本改動相關的六組（`IndexPrefersEntitiesCopyTests|LegacyCopyCLITests|WrittenWithLegacyCopyTests|StdioE2ETests/test(ALegacyWorkLeftover|LegacyCopy|ImportRebuild)|ZoteroReportCLITests|LegacyCopyLedgerTests`，六組的 `Executed N tests` 行都在才數失敗）→ 反向編輯還原、與位元組備份 `cmp` 相同。

| # | 反向編輯 | 紅的測試 |
|---|---|---|
| NC1 | `LibraryIndex.rebuild` 的 work 不濾（`let entries = load.entries`） | 8 支：store 層 work 的兩支、真 binary 的 `testALegacyWorkLeftoverNoLongerBreaksTheIndex`、CLI 的 tag 與 rename、CLI import 的「index rebuilt」、服務層 resolve-people 與 enrich |
| NC2 | 判準永遠不標（`guard format >= 2, false`） | 12 支：NC1 那 8 支，加 person 的兩支、記錄位元組、validate 的措辭 |
| NC3 | 判準不看 id（`entities/` 有任何 work 就標每一筆 legacy work） | `testDistinctRecordsSharingACitekeyStillFailTheRebuild`——真的重複被當成拷貝，重建不再失敗 |
| NC4 | 拿掉 format ≥ 2 的限制 | `testFormatOneStoresDoNotApplyTheRule` |
| NC5 | 不看種類（work 的 id 也比對 entities/ 的 person） | `testTheSameIDOfAnotherKindIsNotACopy` |
| NC6 | 記錄位元組不還原 | `testRecordBytesFollowTheEntitiesCopy` |
| NC7 | #641 警告不補那一句 | `testValidateStillReportsBothCopiesAndSaysWhichOneTheIndexTakes` |
| NC8 | UUID error 改回「靜默丟掉」 | 同上（兩個斷言） |
| NC9 | 「index rebuilt」的附記永遠是空字串 | `ZoteroReportCLITests.testImportPrintsTheLegacyCopyLeftOnTheSuccessSide` |
| NC10 | `LegacyCopyLeft.message` 的附記改回「刪掉之前 index 重建會撞重複」 | `LegacyCopyCLITests.testRenameFinishesAndReportsTheLegacyCopy` |

十格都紅，都以反向編輯還原、與位元組備份 `cmp` 相同，沒有一格是建置失敗。

## 誠實邊界

- **doctor 仍不重建、改名與合併仍整個 store 停下。** 那一對的 UUID／citekey 重複仍是 `crossRecordIssues` 的 error：doctor 見 error 不重建 index（#35），`assertNoCrossRecordErrors` 擋下全庫的 rename、rename-person、resolve-divergence——包括與這一筆無關的記錄。後者是 #35 為「雙佈局並存時改寫會刪掉其中一份而留下另一份」設的閘；#631 的前置檢查（`legacyCopyPresent`）現在也擋得住那個形狀，但要不要因此讓不相干的改名與合併通過，是另一個裁決，這次沒有動。裁決說的「其他記錄的寫入不再被牽連」對 index 重建成立，對這三個命令不成立。
- **person 改名留下的一對，新 key 那一份寫得進去。** #641 的 person 側不收「共用 id」（`unlocatablePersonKeys` 的 doc 逐條寫著理由），寫入封鎖只落在舊 key 的 legacy 那一份。這是既有行為，#709 沒有改。
- **App 與其他讀 `load.entries` 的消費端照舊看到兩份**（App 的列表、匯出）。裁決只說 index；讀 load 的那些面各自對重複 citekey 有既有處置（#627／#669），不在這次範圍。
- **非 #709 那一對的「UUID 共用」訊息仍說「index 的 PRIMARY KEY 會靜默丟掉其中一筆」**，而 `entries` 是一般 `INSERT`，兩筆不同的記錄共用 UUID 時重建其實是失敗、不是靜默丟掉。這一句早於本改動就不對；本改動只改了 #709 那一對的措辭，沒有碰它。
- **MCP `akashic_doctor` 沒有 `skippedLegacyCopies` 鍵。** 那一份資訊經 `crossRecordIssues` 的 #641 警告到達（「index 以 entities/ 那份為準」）；做成結構化的鍵要在說明裡加字，tools/list 只剩 3 bytes。CLI `doctor` 也沒有另印一行，兩面一致。
- **快照那一條（`decodeCaptured`）的標記沒有專屬測試。** 兩條 load 走同一個 `load(from:)`，標記在 #641 的 `annotate` 分支之外、無條件呼叫；目前沒有從快照重建 index 的消費端。
- live store 沒有讀（任務限制）。2026-09-28 的量測（`zero-instance-guards` 第 40 列）是 legacy 殘留 `entries/` 0 個檔、`people/` 0 個檔——這條規則在 live store 上今天不會標任何一筆。

## 量測

- **完整套件**（`swift test --build-system native -Xswiftc -warnings-as-errors`，與 pre-push 同一組旗標）：4,459 支，0 失敗、1 支 skip（單一 bundle `AkashicKitPackageTests.xctest`）。`swift build -Xswiftc -warnings-as-errors` 通過。
- **改動之後、改測試之前**：以兩份並存為前提的 11 支紅（`LegacyCopyCLITests` 2、`ImportZoteroReportSurfaceTests` 3、`StdioE2ETests` 2、`WrittenWithLegacyCopyTests` 4），都是「前提：index rebuild 撞重複」那一句不再成立；其餘相關組（`LegacyCopyLedgerTests`、`LoadTimeUnlocatableTests`、`CrossRecordValidationTests`、`EntitiesLayoutTests`、`ZoteroImportReportAfterWriteTests`、`ZoteroReportCLITests`）照綠。
- **守衛**：`run-guards.sh` rc 0。
- **tools/list**：51,997 bytes，改前改後相同（預算 52,000）。量法同 `StdioE2ETests.testToolsListResponseStaysWithinByteBudget`：真 binary 送 initialize 與 tools/list，數回應那一行的位元組。
