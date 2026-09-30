# 2026-10-01 同一筆記錄兩份並存時以 entities/ 那份為準：index、匯出、App，以及這一對改報 warning（#709）

兩個 commit。第一個（index）照使用者 2026-09-30 的裁決；第二個照同日稍後延伸的裁決（2026-10-01）：這一對的重複從 error 降為 warning、
匯出與 App 也以 entities/ 那份為準。本檔寫的是兩個 commit 之後的狀態，第一個 commit 當時的說法在被改掉的地方以劃線保留。

#631 寫一筆既有記錄時會把 `entries/<citekey>.yaml`／`people/<key>.yaml` 搬進 `entities/<id>.yaml`：先寫新檔、再刪舊檔。舊檔刪不掉時同一筆記錄留下兩份（#705 把這一筆記在 `writtenWithLegacyCopy`）。兩份一起進 index：work 撞 `entries.citekey` UNIQUE（改名留下的舊 citekey 則撞 `entries.uuid` PRIMARY KEY），整次重建失敗。寫入之後會重建 index 的呼叫因此全部以錯誤收場，`writtenWithLegacyCopy` 只能附在錯誤訊息裡；而只要 store 裡有一筆留下兩份，其他記錄的寫入也一樣失敗。person 的 people 表以 key 為主鍵、`INSERT OR IGNORE` 留下列舉順序的第一筆（#670），改名留下的舊 key 另成一列。

使用者 2026-09-30 裁決：index 重建以 `entities/` 那份為準、略過 legacy 拷貝並回報。代價（使用者看過）：有人手改過 legacy 那份時，index 看不到那次修改，只剩 validate 的警告。

使用者 2026-10-01 延伸：(1) 這一對造成的 UUID 共用與 citekey／person key 重複從 error 降為 warning——doctor 照常重建，`assertNoCrossRecordErrors`（rename、rename-person、resolve-divergence）不再因為它讓整個 store 停下；那一筆自己照舊寫不進去（#641）、validate 照舊報它。兩筆**不同**的記錄共用 citekey／key／UUID 照舊是 error。(2) 匯出與 App 也以 entities/ 那份為準，過濾只有一個 helper。

## 「同一筆記錄」的判準

只有一份，在 `LibraryStore.markLegacyCopiesShadowedByEntities`（`Sources/AkashicStoreIO/ShadowedLegacyCopy.swift`）：

> store 是 entities 佈局（format ≥ 2），一筆 work 從 `entries/` 讀進來（person 從 `people/`），而 `entities/` 讀進來的記錄裡有**同一種、同一個 id** 的一筆。

- **id，不是 citekey 或 key**：`entities/` 的檔名就是 id，load 已驗檔名與記錄的 id 相符；#631 的搬移把內容寫進 `entities/<它的 id>.yaml`，刪不掉時留下的是同一個 id 的舊檔；改名不換 UUID，留下的舊檔 citekey／key 是改名前的。反過來，兩筆**不同**的記錄共用 citekey 時 id 不同，不在此列——它們照舊是 `crossRecordIssues` 的 error，work 那一對照舊讓重建撞 UNIQUE。
- **同一種**：`entities/` 也住 organization、venue、divergence；work 與 person 共用一個 id 不是同一筆記錄（#631 的目的檔檢查當它是另一種記錄）。
- **format ≥ 2**：format 1 的 `entries/`、`people/` 是正典位置，不是殘留（同 #641 的 `annotateFileSituations`）。

**過濾只有一處**：`LibraryLoad.withoutShadowedLegacyCopies()`（同一個檔）。index 重建、三個匯出面（MCP `akashic_export`、CLI `export-bib`、`export-tables`）與 App 的 `AppState.load` 都呼叫它。它另守一件事：**過濾不讓任何一筆變得可寫**——留下的那一份在完整的 load 上若無法唯一定位（#627／#641；改名留下的一對共用 id、另一筆記錄的舊拷貝撞上它的 citekey／key），在視圖上也要無法唯一定位，所以沒有自己的 `unwritableReason` 時補一句說出是哪份拷貝擋著它。App 的裁決台以這個視圖定位，少了這一步它會放行 CLI／MCP 拒絕的寫入。驗證（validate、doctor 的 `crossRecordIssues`、App 的健康總覽）不用這個視圖——它們要照舊看到兩份。

load 在兩條路徑（讀磁碟的 `load()` 與唯讀快照的 `decodeCaptured`）都標：它只需要每筆記錄是從哪個檔讀進來的，不讀磁碟也不問 git。標記是 `FileSituation.shadowedLegacyFile`（被讀進來的那個 legacy 檔的相對路徑），與 #641 的 `unwritableReason` 同一個型別——load 對檔案處境的觀察，不參與相等、不序列化。

## 改了什麼

- **index 重建**（`LibraryIndex.rebuild`）：插入之前經 `withoutShadowedLegacyCopies()` 濾掉帶標記的 work 與 person。`IndexStats.entries`／`people` 與 `index_identity.entry_count` 算的是進了 index 的筆數；新欄位 `IndexStats.skippedLegacyCopies` 列出略過的每一份（kind、legacy 那份的鍵、id、legacy 檔、`entitiesFile`），由 `LibraryLoad.shadowedLegacyCopies` 從同一個標記導出。
- **#645 的記錄位元組**：legacy `people/` 在 entities 之後讀，先前會蓋掉 entities/ 那一份的位元組；現在帶標記的那筆還原成 entities/ 的——預算預警量的是之後會長的那個檔。這是同一個判準的第二個讀者（「兩份裡哪一份是這筆記錄」），不是另一條規則。
- **回報**：
  - 重建結果印出來的地方（CLI `import-zotero` 與 `migrate` 的「index rebuilt」那一行）加上「略過 N 份 legacy 拷貝」的附記；只給筆數，是哪幾筆由下一條逐筆說。
  - validate 既有的 #641 警告（「work／person「…」的檔案寫入時會被拒」）對有 legacy 拷貝的那一筆多一句「index 以 entities/ 那份為準、略過 legacy 拷貝——它的內容 index 看不到」（第二個 commit 起「index、匯出與 App 以 entities/ 那份為準……它的內容它們看不到」）。**沒有另開一族訊息**：這一句說的就是那則警告在講的那一對，而那則警告經 `crossRecordIssues` 已經到得了 CLI `validate`／`doctor`、MCP `akashic_doctor` 與 App——三面同一份來源，不必加 MCP 回應鍵（tools/list 只剩 3 bytes，加鍵要改說明）。
  - ~~同一對的「UUID … 被 2 筆 entry 共用」error 原本說「index 的 PRIMARY KEY 會靜默丟掉其中一筆」，對這一對不再是真的；改成「其中 legacy 拷貝由 index 略過、以 entities/<id>.yaml 為準」。其他共用 UUID 的情形（兩筆不同的記錄）訊息不變。~~ → 第二個 commit：這一對的「UUID … 共用」與「citekey／person key 重複」改為 **warning**，句尾說「同一筆記錄的 legacy 拷貝還在：index、匯出與 App 以 entities/ 那份為準，刪掉 legacy 那份之前這筆無法唯一定位」。「這一對」的判斷：UUID 那一則看那個 id 有沒有被標的拷貝；citekey／key 那一則要整組只有一個 id、而那個 id 有被標的拷貝——另一筆記錄的舊拷貝撞上某個 citekey 時整組有兩個 id，照舊是 error。兩筆不同的記錄共用 UUID 的 error 改說實話：「index 的 entries 以 UUID 為主鍵，兩筆都在時重建會失敗」（先前的「靜默丟掉」不對——entries 是一般的 INSERT）。
  - #641 的那句補充（第二個 commit 起）改說「index、匯出與 App 以 entities/ 那份為準」。
  - `writtenWithLegacyCopy` 每筆的附記（`LegacyCopyLeft.message`）原本說「刪掉之前 index 重建會撞重複」，改成「刪掉之前 index 以 entities/ 那份為準、略過 legacy 拷貝」（第二個 commit 起「index、匯出與 App」）；person 那一格原本沒有附記，現在也說同一句。
- **合併的新拒絕**（第二個 commit）：`resolve-divergence` 的候選有 legacy 拷貝就拒絕（`candidateLegacyCopies`，同一個判準、候選鍵換成 id 去對），在版控檢查之前、dry-run 與實跑共用。先前由這一對的 error 在 `assertNoCrossRecordErrors` 擋下；降為 warning 之後少了它，被併者只刪 `entities/<id>.yaml`（`doomedRelativePaths`），legacy 那份會在下一次 load 復活成唯一的一份。
- **匯出與 App**（第二個 commit）：`export-bib`（含 CSL-JSON）、`export-tables`（含 `--view`）、MCP `akashic_export` 在 load 之後經 `withoutShadowedLegacyCopies()`；App 的清單與裁決台（`AppState.entries`／`people`）同樣。App 的健康總覽、各寫入動作重讀磁碟的定位仍用完整的 load。
- **不變的**：
  - 那一筆本身照舊寫不進去——`unlocatableCitekeys`／`unlocatablePersonKeys` 仍收它（#641），load 仍把兩份都讀進來。
  - ~~`crossRecordIssues` 的 severity 不變：那一對的 UUID／citekey 重複仍是 error，所以 doctor 照舊不重建 index，改名與合併（`assertNoCrossRecordErrors`）照舊整個 store 停下——後者是 #35 專為「雙佈局並存」設的閘。~~ → 第二個 commit 改掉（見上）。#35 那道閘防的是「改寫時刪掉其中一份而留下另一份」；那一筆自己的改名由 #631 的前置擋（`entryWritePlan`／`personWritePlan` 看到兩份就拒絕，在任何寫入之前），合併由上面的新拒絕擋，所以把這一對移出那道閘不重開那個洞。
  - 工具說明沒有改：沒有一句說 work 的殘留會以錯誤收場（`legacyCopyNote` 的「錯誤時列在訊息前」仍然成立）。tools/list 51,997 bytes，改前改後相同（預算 52,000）。
- 文件：`mcp-cli-parity` 表下的 #705 段（「有記錄的後果」劃掉、補 #709；第二個 commit 再補一段）、`plugin/CHANGELOG.md`（新增 #709 一節、#705 的錯誤回應那一條加註）、#705 的兩份 changelog（誠實邊界第一條、R1 的「仍未處理」第 2、3、35 列）加補記。`docs/store-format.md` 沒有描述 index 對兩份的處置，不動；`zero-instance-guards` 第 40 列說的是 #641 的寫入封鎖，與本改動不矛盾，不動。

## 測試

先前以「兩份並存 → index rebuild 撞 UNIQUE」當前提的測試，改動之後第一次跑紅了 11 支（前提不再成立）。依它們原本要釘的東西分兩類處理：

- **要釘「寫了、不算失敗」的**：改斷言成功與結構化的鍵——`LegacyCopyCLITests.testTagOnALegacyWorkSucceedsWithTheKeyInItsJSON`（新，stdout 仍是一份 JSON、結束碼 0）、`testRenameFinishesAndReportsTheLegacyCopy`（結束碼 0，附記說的是 #709 之後的事）、`WrittenWithLegacyCopyTests.testResolvePeopleApplyDoesNotListItAsAWriteFailure`／`testEnrichDoesNotListItAsAWriteFailure`（回成功、沒有 `writeFailed`、算在 `applied`／`written`）。
- **要釘「寫了之後別的步驟失敗，報告不丟」的**：那條路徑還在，改用真的重複造出失敗——store 裡另放兩筆**不同**的記錄共用一個 citekey（#709 不替它們選一筆）：`LegacyCopyCLITests.testTagThatFailsAfterWritingStillReportsIt`、`WrittenWithLegacyCopyTests.testALaterRebuildFailureStillCarriesIt`（新）與兩支 import 的交接測試、`StdioE2ETests.testLegacyCopyLeftSurvivesALaterFailure`、`testImportRebuildFailureKeepsEveryLegacyCopyUntruncated`（真 binary、三十二筆）、`ImportZoteroReportSurfaceTests` 的三支 rebuild 失敗路徑。這幾支同時證明真的重複照舊讓重建失敗。

新增：

- `IndexPrefersEntitiesCopyTests`（store 層，10 支）：work 同 citekey 的一對（index 那個 id 只有一列、標題取 entities/ 那份、`skippedLegacyCopies` 具名、`entry_count` 一致）；改名留下的一對（只剩新 citekey、兩個 citekey 都仍無法唯一定位）；兩筆不同的記錄共用 citekey（一份 entities／一份 legacy，與兩份都在 entities/，都照舊失敗、沒有標記）；同一個 id 不同種（不標）；format 1（不標）；person 同 key（index 的名字取 entities/ 那份）；person 改名（舊 key 不進 index、仍寫不進去）；記錄位元組取 entities/ 那份；validate 的警告與 UUID error 的新措辭、error 級不變；真的共用 UUID 的訊息不變。
- `StdioE2ETests.testALegacyWorkLeftoverNoLongerBreaksTheIndex`（真 binary）：`akashic_tag` 對 legacy work 回成功、`writtenWithLegacyCopy` 是結構化的鍵；之後手改 legacy 那份的標題，再對**另一筆**記錄 `akashic_tag`——照常成功；index 那個 id 只有一列，標題是 entities/ 的「Legacy」而不是手改的「Hand edit」，tag 是只在 entities/ 那份的 `x`；再 tag 同一筆被拒（「無法唯一定位」），檔案沒寫。
- `ZoteroReportCLITests.testImportPrintsTheLegacyCopyLeftOnTheSuccessSide` 多兩個斷言：結束碼 0、「index rebuilt」那一行說「略過 1 份 legacy 拷貝」。

### 第二個 commit 的測試

- `IndexPrefersEntitiesCopyTests`（store 層，加到 19 支）：validate 那一支改斷言這一對的 UUID／citekey 是 warning、沒有 error、`fatalCrossRecordIssues` 是空的；person 同 key 的一對是 warning、兩個不同的 person 共用 key 是 error；兩筆不同的記錄共用 citekey 是 error（沿用的那一支多一個斷言）；兩筆不同的記錄共用 UUID 是 error、訊息說「重建會失敗」、重建確實失敗；另一筆 work 的 `renameEntry` 與另一個 person 的 `renamePerson` 在有一對時做完，有兩份的那一筆自己改名被拒、零寫入；合併的候選有 legacy 拷貝時兩個倖存者都被拒（訊息具名 legacy 檔）；視圖——改名留下的一對只剩新 citekey、仍無法唯一定位，另一筆記錄的舊拷貝撞上某個 person key 時視圖上那個人仍寫不進去，person 改名留下的新 key 在完整 load 上寫得進去、視圖不替它加封鎖；MCP 的 `akashic_export`（bib 與 CSL-JSON）只有 entities/ 那一份、`doctor()` 回 `indexRebuilt: true`。
- `LegacyCopyCLITests.testExportDoctorAndAnUnrelatedRenameUseTheEntitiesCopy`（真 binary）：`export-bib` 與 `export-tables` 的 `publication.csv` 只有一筆、標題是 entities/ 的；`doctor` 結束碼 0、`entries: 2`、輸出有「同一筆記錄的 legacy 拷貝還在」；另一筆記錄的 `rename` 結束碼 0。
- App（`AdjudicationTests`、`OrphanedAdditionalSourceTests`）：兩支原本斷言「兩份都讀到」的前提改成 App 只列一份、磁碟上兩份都在，寫入照舊被拒；新增 `testARenameLeftoverIsListedOnceAndStaysWriteBlocked`——改名留下的一對，App 只列新 citekey，裁決台的 accept 照舊具名拒絕、零寫入（過濾不讓它變得可寫）。
- 文字：`CrossRecordValidationTests` 與 `DuplicateCitekeys.swift` 說明裡的「靜默丟掉」更正；`LegacyCopyLeft.message` 的附記與對應的 CLI 斷言改成「index、匯出與 App」。

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
| NC10 | `LegacyCopyLeft.message` 的附記改回「刪掉之前 index 重建會撞重複」（第一個 commit 時的措辭；第二個 commit 改成「index、匯出與 App」、測試跟著改，以新措辭重跑同一格，同一支紅） | `LegacyCopyCLITests.testRenameFinishesAndReportsTheLegacyCopy` |

十格都紅，都以反向編輯還原、與位元組備份 `cmp` 相同，沒有一格是建置失敗。

第二個 commit，同一個做法，篩選多加 `AdjudicationTests|OrphanedAdditionalSourceTests`：

| # | 反向編輯 | 紅的測試 |
|---|---|---|
| NC11 | UUID 共用的一對改回 error | 5 支：validate 的措辭、MCP 的 export＋doctor、store 層的不相干改名、合併（error 先在 `assertNoCrossRecordErrors` 開火，訊息不同）、CLI 的 export／doctor／rename |
| NC12 | citekey 重複的一對改回 error | 同上 5 支 |
| NC13 | person key 重複的一對改回 error | 2 支：person 的 warning／error、不相干的 `renamePerson` |
| NC14 | 拿掉合併候選的 legacy 拷貝檢查 | `testMergeRefusesACandidateWithALegacyCopy`（落到版控檢查，訊息不再具名 legacy 檔） |
| NC15 | 視圖的 work 不補封鎖 | 2 支：`testTheViewKeepsTheKeptCopyWriteBlocked`、App 的 `testARenameLeftoverIsListedOnceAndStaysWriteBlocked`（accept 放行） |
| NC16 | 視圖的 person 不補封鎖 | `testTheViewKeepsAPersonBlockedByAnotherRecordsLeftover` |
| NC17 | MCP `export` 不經視圖 | `testTheMCPExportAndDoctorUseTheEntitiesCopy` |
| NC18 | CLI `export-bib` 不經視圖 | `testExportDoctorAndAnUnrelatedRenameUseTheEntitiesCopy` |
| NC19 | CLI `export-tables` 不經視圖 | 同上 |
| NC20 | App 不經視圖 | 3 支：兩支 App 的「只列一份」、改名留下的一對 |
| NC21 | 兩筆不同的記錄共用 UUID 的訊息改回「靜默丟掉」 | `testADistinctSharedUUIDStaysAnErrorWithAnAccurateMessage` |

十一格都紅，都以反向編輯還原、`cmp` 相同，沒有一格是建置失敗。NC18 與 NC19 落在同一支 CLI 測試（它先後檢查兩個匯出面）。

## 誠實邊界

- ~~**doctor 仍不重建、改名與合併仍整個 store 停下。** 那一對的 UUID／citekey 重複仍是 `crossRecordIssues` 的 error：doctor 見 error 不重建 index（#35），`assertNoCrossRecordErrors` 擋下全庫的 rename、rename-person、resolve-divergence——包括與這一筆無關的記錄。後者是 #35 為「雙佈局並存時改寫會刪掉其中一份而留下另一份」設的閘；#631 的前置檢查（`legacyCopyPresent`）現在也擋得住那個形狀，但要不要因此讓不相干的改名與合併通過，是另一個裁決，這次沒有動。裁決說的「其他記錄的寫入不再被牽連」對 index 重建成立，對這三個命令不成立。~~ → 第二個 commit 解掉（使用者 2026-10-01）。
- **person 改名留下的一對，新 key 那一份寫得進去。** #641 的 person 側不收「共用 id」（`unlocatablePersonKeys` 的 doc 逐條寫著理由），寫入封鎖只落在舊 key 的 legacy 那一份。這是既有行為，#709 沒有改。
- ~~**App 與其他讀 `load.entries` 的消費端照舊看到兩份**（App 的列表、匯出）。裁決只說 index；讀 load 的那些面各自對重複 citekey 有既有處置（#627／#669），不在這次範圍。~~ → 第二個 commit：匯出與 App 改用同一個視圖。**其他讀 load 的面沒有換**：`akashic_get_entry`／`get-entry`、`akashic_person`、`library list` 等以 citekey／key 在 `load.entries` 裡找一筆的讀取，遇到這一對時取 `first(where:)` 的那一筆——load 以 citekey 排序，同 citekey 的兩筆誰在前沒有保證，可能回 legacy 那份的舊內容。裁決點名的是匯出與 App，這幾個讀取面要不要也換成這個視圖是另一個決定。
- ~~**非 #709 那一對的「UUID 共用」訊息仍說「index 的 PRIMARY KEY 會靜默丟掉其中一筆」**……本改動只改了 #709 那一對的措辭，沒有碰它。~~ → 第二個 commit 改成「兩筆都在時重建會失敗」，`CrossRecordValidationTests` 與 `DuplicateCitekeys.swift` 的同一句說明一併更正。
- **MCP `akashic_doctor` 沒有 `skippedLegacyCopies` 鍵。** 那一份資訊經 `crossRecordIssues` 到達（#641 警告的補充與降為 warning 的 UUID／citekey 兩則）；做成結構化的鍵要在說明裡加字，tools/list 只剩 3 bytes。CLI `doctor` 也沒有另印一行，兩面一致。第二個 commit 起 doctor 在這種狀態下會重建，`entries`／`people` 是 index 的筆數（不含拷貝）。
- **只剩這一對的 store，`akashic validate` 結束碼是 0**（第二個 commit）：這一對全是 warning。只看結束碼的自動化看不到它；輸出照舊逐則列出。
- **與這一筆相關的改名照舊停下。** 不相干的改名照常，但被改名的記錄若被有兩份的那一筆引用（`cites`／`related`、作者位），改名要改寫那一筆，#631 的前置拒絕、整個改名零寫入——那一筆刪掉 legacy 那份之前本來就寫不進去。
- **另一筆記錄的舊拷貝撞上某個 citekey／key 時照舊是 error**（整組兩個 id）。index 與匯出不受影響（拷貝被濾掉），但 doctor 不重建、改名與合併停下，直到拷貝刪掉。這一格沒有另外裁決，照「兩筆不同的記錄共用 citekey 照舊是 error」處理。
- **快照那一條（`decodeCaptured`）的標記沒有專屬測試。** 兩條 load 走同一個 `load(from:)`，標記在 #641 的 `annotate` 分支之外、無條件呼叫；目前沒有從快照重建 index 的消費端。
- live store 沒有讀（任務限制）。2026-09-28 的量測（`zero-instance-guards` 第 40 列）是 legacy 殘留 `entries/` 0 個檔、`people/` 0 個檔——這條規則在 live store 上今天不會標任何一筆。

## 量測

- **完整套件**（`swift test --build-system native -Xswiftc -warnings-as-errors`，與 pre-push 同一組旗標）：第一個 commit 4,459 支、第二個 commit 4,469 支，都是 0 失敗、1 支 skip（單一 bundle `AkashicKitPackageTests.xctest`）。`swift build -Xswiftc -warnings-as-errors` 通過。
- **改動之後、改測試之前**：以兩份並存為前提的 11 支紅（`LegacyCopyCLITests` 2、`ImportZoteroReportSurfaceTests` 3、`StdioE2ETests` 2、`WrittenWithLegacyCopyTests` 4），都是「前提：index rebuild 撞重複」那一句不再成立；其餘相關組（`LegacyCopyLedgerTests`、`LoadTimeUnlocatableTests`、`CrossRecordValidationTests`、`EntitiesLayoutTests`、`ZoteroImportReportAfterWriteTests`、`ZoteroReportCLITests`）照綠。
- **守衛**：`run-guards.sh` rc 0。
- **tools/list**：51,997 bytes，兩個 commit 前後都相同（預算 52,000）。量法同 `StdioE2ETests.testToolsListResponseStaysWithinByteBudget`：真 binary 送 initialize 與 tools/list，數回應那一行的位元組。
