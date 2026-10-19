# 2026-10-20 b43：b42 verify 對 #700（否定規則那一格的查法、`file add` 拒絕被 400 字截斷、新建的 `.gitignore` 寫入失敗時以路徑刪）的修正

b42 verify（六席，驗 `64c9cde7`，與 #692 同一批）對 #700 的 findings：MEDIUM 3、LOW 7、INFO 13。#692 這一輪沒有自己的 findings，它的檔案沒有動。
三則 MEDIUM 都有修正前會紅的回歸測試與負控；LOW 與 INFO 同族、便宜的順手修，其餘逐則寫理由（第 10 節）。下面的編號是 findings 檔的索引。

## 1. MEDIUM 0（同 LOW 3、6；devil's advocate 19 校準）：`ruleNegatedLater` 的處置教了一個不成立的查法

**問題**：b41 為了 b40 INFO 19／20 改寫的處置說「可用 `git check-ignore -v sources/index.jsonl sources/00/` 看——它只列出被排除的，少了哪一個就是區塊之後的否定規則
把它放了回來……兩個都列出、這裡仍判成不生效時是判讀保守」。git 2.55、2.54 實測，三處不成立：

- `-v` 也列出**最後符合的是否定規則**的路徑（那一行的規則以 `!` 開頭）。區塊之後接 `!*`：兩個路徑都列出（`.gitignore:4:!*`），git 一個都不排除；`sources/*` 之後接
  `!*.jsonl`：`index.jsonl` 以 `!*.jsonl` 列出而沒被排除。照字面讀，真的漏了的狀態被說成「判讀保守」。
- 一個存檔子目錄代表不了其他的：`sources/*` 之後接 `!sources/ab/`（或 `!sources/f*`），`index.jsonl` 與 `00` 都被排除、`ab`（`ff`）被放回來。
- 結尾帶 `/` 的目錄參數不可靠（放回的是那個目錄本身時不列出）。

**修正**：處置改成「可用 `git check-ignore sources/index.jsonl sources/00/x` 看（不加 `-v`）：它只印出被排除的路徑，沒印出來的那一個沒被排除；兩個都印出來只說明這兩個
路徑，其他存檔子目錄要換成 `sources/<hh>/x` 逐一看。加 `-v` 時每一行是一個路徑與最後符合它的規則（檔名:行號:規則），規則以 `!` 開頭的就是放回它的那一行（放回的是上層目錄時，
那個路徑可能不在輸出裡）：刪掉那一行或把它移到區塊之前。最直接的做法是在檔尾補一行頂格的 `sources/`……」。「判讀保守」那一句拿掉。原因（`reason`）裡「判讀是保守的：
`[…]` 字元類一律算碰得到……」說的是判讀本身，成立，留著。

**同一個查法的其他地方**：`plugin/skills/akashic-bootstrap/references/writing-to-the-store.md` 叫人在存檔之前跑 `git check-ignore -v sources/`——被否定規則放回來時同樣
印出一行。改成不加 `-v` 的 `git check-ignore` 對實際要寫的路徑，並說出 `-v` 的 `!` 行是什麼意思（plugin 殼 0.13.5 → 0.13.6）。b41 changelog 第 3 節與第 1 節、
`plugin/CHANGELOG.md` 的 b41 那一段劃線更正、指到這裡。`docs/skill-evals/` 底下的舊版快照是那次評測的原樣，沒有改。

**測試**（`GitignoreRemedyCLITests`，七種判成 `ruleNegatedLater` 的形狀，都在真的 git 工作樹裡，`/usr/bin/git`、剝掉 `GIT_*`、不讀使用者與系統設定）：
- `testTheNegationRemedysCommandPrintsExactlyTheExcludedPaths`：從處置文字裡取出那一條指令**照跑**，它印出的路徑恰好是被排除的那幾個——對照是
  `git ls-files --others --exclude-standard`（`git add` 會收進去的檔）。修前的指令帶 `-v`，四種形狀印出沒被排除的路徑。
- `testTheNegationRemedysReadingOfGitHoldsForEveryShape`：`-v` 的每一行，規則以 `!` 開頭 ⇔ 那個路徑沒被排除；沒出現在 `-v` 輸出裡的路徑都沒被排除；語料裡有「點名的
  兩個都被排除、別的存檔子目錄沒有」的形狀；檔尾補 `sources/` 之後每一種都全部排除、判讀也照算已在。

## 2. MEDIUM 1（同 LOW 9）：`file add` 的拒絕把處置截掉了

**問題**：`StoreIOError.sourcesIgnoreNotWritten` 把首句、原因、「.gitignore 沒有改寫」與處置接成一行，CLI 頂層逐行截 400（`displaySafeErrorMultiline`）。b41 把
`ruleNegatedLater` 的原因與處置加長之後那一行 406 字，截在「git check-i…（已截斷）」，「不要再貼一份」不在輸出裡、緊接著卻是整段區塊——讀起來像在邀人再貼一份。
`contentRuleWithNestedGitignore` 那一行 394 字。沒有測試把拒絕經過這個 sink 量過。

**修正**：拒絕分三行——首句與原因；這一次對 `.gitignore` 做了什麼與佈局建了沒有；處置。**同一個 sink 的另一條路**：MCP `akashic_import_wos` 的 index rebuild 失敗時，
warning 接在錯誤訊息後面、經同一個 400 字的出口，而 warning 的說明、匯入那一句、處置也接成一行（`ruleNegatedLater` 約 650 字）——`warningLines` 改成說明、匯入那一句
（有的話）、處置各自一行。`doctor` 直接印、MCP 成功回應的 `gitignoreWarning` 不截，兩處只是分行。實測（真 binary）否定規則那一格 `file add` 三行 340／29／312 字，
`sources/.gitignore` 那一格 297／29／135 字；`doctor` 的前兩行 329／312、286／135。

**測試**：`testEveryComposedLineFitsTheSinkAndKeepsTheRemedy`（每一種原因 × 兩種 `layoutWritten`：加上 `Error: ` 之後每一行 ≤ 400、處置整句都在；匯入的 warning 以最長的
動作名 `akashic_import_zotero` 加匯入那一句，每一行 ≤ 400）、`testFileAddShowsTheWholeRemedy`（真 binary：兩種最長的拒絕，處置整句在輸出裡、沒有「（已截斷）」）。
`ZoteroReportCLITests` 與 `testAWedgedLockHolderDoesNotHangTheFirstLook` 原本在第一行找匯入那一句與處置，改成在各自那一行找。

## 3. MEDIUM 2：新建的 `.gitignore` 寫入失敗時以路徑 `unlink`

**問題**：`appendSourcesIgnoreUnderLock(create: true)` 寫入失敗、截回空的之後 `unlink(path)`——inode 只在取到鎖時比過一次。鎖約束不到不用 `flock` 的程式（編輯器、
`git checkout`、`mv`）：寫入期間路徑被原子換成使用者的檔，刪的就是使用者的檔（devil's advocate 以攔 `write` 的方式實測：換上去的 `*.srt`、`*.mp3` 兩條規則被刪，
訊息還說「沒有改寫」）。b41 第 1 節把這個 `unlink` 列為「不動」，理由只對持鎖的 akashic 程序成立。

**修正**：新建的檔一律不以路徑刪——「仍是我們的檔」與 `unlink` 之間不是原子的，比對 inode 只縮小窗口；同 `lockTimedOutAfterCreating`，留著、照實說。新的原因
`writeFailedAfterCreating(errno:)`：「這一次新建了它，寫入區塊時失敗（…）——寫進去的部分已截回、新建的檔留著（空的）：不以路徑刪它，寫入期間別的程式可能已把路徑換成
別的檔」。首句、處置同 `writeFailed`。空的 `.gitignore` 對 git 無害，下一次先看把它當既有的檔附加。`file add --help` 補「寫入失敗也留著空檔」。

**測試**：`testAFailedWriteDoesNotDeleteTheFileThatReplacedTheCreatedOne`（注入的寫入在回 `ENOSPC` 之前把路徑 `rename` 成使用者的檔：使用者的檔要留著）、
`testAFailedWriteLeavesTheCreatedFileEmpty`（寫了 10 個位元組才失敗：截回空的、留著、下一次照常附加）；`testACreatedFileThatGotNothingIsRemoved` 改成
`testACreatedFileThatGotNothingIsLeftEmpty`。

## 4. LOW 5、INFO 13、16：新建了空檔的兩格說「沒有改寫」

`lockTimedOutAfterCreating`（與第 3 節的新格）的原因說「這一次新建了它（空的）」，同一則訊息的尾句卻是「.gitignore 沒有改寫」（拒絕）、「doctor 沒有改寫它」（warning）。
新的 `SourcesIgnoreProblem.effect`（`untouched`／`createdEmpty`／`partiallyWritten`，switch 逐格、沒有 `default`）決定兩個出口的那一句：新建了空檔的說
「.gitignore 是這一次新建的空檔（沒有寫入內容）」「doctor 新建了它（空的）、沒有寫入內容」。`leavesGitignoreUntouched` 改由它導出（意思不變：沒有寫進內容）。
測試 `testACreatedEmptyGitignoreIsNotCalledUntouched`，並釘住 `createdEmpty` 恰好是這兩格。

## 5. LOW 8：先看取到 `LOCK_SH` 之後不重看路徑

`inspectSourcesIgnoreOnce` 取到共享鎖之後沒有比對路徑——等鎖期間檔案被刪掉或換掉時讀的是已經不在路徑上的 inode，判成要附加，再以路徑問寫入權限得到 `ENOENT`，
報「沒有寫入權限（errno 2）……給它寫入權限後重跑」。取到鎖之後以 `lstat` 比對 device／inode，不同就重看（同鎖內重看那一步）。b41 changelog 第 1 節那句
「之後取到鎖的程序會發現路徑不再指著它的檔而重看」只對 `LOCK_EX` 那一步成立，劃線更正。測試 `testAFirstLookThatWaitedForTheLockRereadsWhenThePathChanged`
（試鎖的注入點在第一次 `LOCK_SH` 時刪掉檔案：修前報 `notWritable(errno: 2)`，修後重看、照常新建）。

## 6. INFO 12：看不到 `sources/.gitignore` 也算在，訊息卻說它在

`sourcesHasOwnGitignore` 對 `ENOENT`／`ENOTDIR` 以外的 `lstat` 錯誤判成在（保守，方向對），`contentRuleWithNestedGitignore` 的首句與原因卻斷言「sources/ 裡另有 .gitignore」。
首句改成「……sources/ 裡另有 .gitignore（或看不到它在不在），不能確定它生效」，原因補「看不到它在不在——例如 sources/ 沒有讀取權限——也算在」，處置補「看不到它時先給 sources/
讀取權限」。只改文字，判讀不變。

## 7. INFO 20：只有 `index.jsonl` 被放回來時，`store-source` 先寫存檔再拒絕

內容形的規則加 `!sources/index.jsonl`：存檔與子目錄仍被排除、index 沒有。`storeSource` 寫完存檔才在附加 index 那一步（`appendIndexEntry`）問 index 被不被排除——
拒絕了，存檔已經在磁碟上（孤兒，`auditSourceIndex` 才看得到）。匯入那一句「sources/ 沒被排除之前 store-source 拒絕寫入」與 `store-format.md` 對這一格不精確。
要附加 index 時（這個 digest 還沒記過），寫存檔之前先驗 index；已記過的不附加、不問（不因此拒絕一次本來成功的重存）。附加那一步照舊再驗一次。
`preflightStoreSource`（`copy-zotero-attachments` 用）本來就三條都先驗，不變。測試 `SourcesIndexExclusionOrderTests`（拒絕時 `sources/` 底下沒有任何檔；已記過的 digest
照常重存）。

## 8. INFO 10：零實例第 87 列的觸發條件

第 87 列的觸發句只說「`.gitignore` 不是 UTF-8 一般檔、又沒有區塊的數應恆為 0」，量測腳本的拒絕狀態另有 `rule-negated`（b38 起）與 `nested-gitignore`（b40 起）——
兩份描述分岔。觸發句改成指向量測文件第 87 列的封閉清單、不複述。同一則的後半說「只有 git 2.55 可用，b41 寫的 2.54 那一半無法重驗」：本機 `/usr/bin/git` 是
2.54.0（Apple Git-157），`testThePresentJudgementAgreesWithGitCheckIgnore` 與這一輪的新測試都跑它；PATH 上的 `git` 是 2.55.0。

## 9. 同一個判斷的其他路徑（逐一查過）

- **處置的查法**：處置文字只有 `SourcesIgnoreProblem.remedy(rerun:)` 一份，`warningLines` 與 `file add` 的拒絕都讀它；repo 裡另一處叫人跑 `git check-ignore -v` 的是
  `writing-to-the-store.md`（第 1 節，已改）；`docs/skill-evals/` 的舊版快照不動。`store-source` 自己以 `git check-ignore -q` 驗，不受影響。
- **400 字的 sink**：`sourcesIgnoreNotWritten` 只有 `file add`（`ensureLayout` 的 `.refuse`，`FileCommands`）擲；`.report` 的四個呼叫端（`doctor`、CLI `import-zotero`、MCP 兩個
  匯入）都讀 `warningLines`。會經 400 字出口的只有 `file add` 的拒絕與 MCP `akashic_import_wos` 的 rebuild 失敗那條（第 2 節，兩處都改）。MCP `akashic_import_zotero`
  的 rebuild 失敗把 warning 放進 JSON payload（換行逃成 `\n`、整個值在一行），那一條 payload 的每一行都受 400 字的出口截——這是那個錯誤出口對整份報告的既有限制
  （其他長值同樣），不是這則 warning 才有的，這一輪沒有動。App 不經 `ensureLayout`。
- **以路徑刪新建的檔**：`SourcesIgnoreBlock.swift` 只剩零處 `unlink`（等鎖逾時 b41 拿掉、寫入失敗這一輪拿掉）。repo 裡另外兩處 `flock`（`S2Throttle`、`FulltextAttemptLedger`）
  不刪檔。`SourceStore` 的暫存檔清理刪的是這一次以 `O_EXCL` 建的暫存名、不是使用者會換上來的路徑，不在這一輪。
- **取到鎖之後比對路徑**：`appendSourcesIgnoreUnderLock`（`LOCK_EX`）本來就比；`inspectSourcesIgnoreOnce`（`LOCK_SH`）補上（第 5 節）。
- **新建了空檔的說法**：兩個出口（`warningLines`、`sourcesIgnoreNotWritten`）都改讀 `effect`。
- **`store-source` 的排除驗證順序**：`storeSource(chunks:)` 是兩個入口共用的唯一一條；`preflightStoreSource` 本來就先驗三條。

## 10. findings 逐則

| index | 處置 |
|---|---|
| 0、3、6、19 | 第 1 節 |
| 1、9 | 第 2 節 |
| 2 | 第 3 節 |
| 5、13、16 | 第 4 節 |
| 8 | 第 5 節 |
| 12 | 第 6 節 |
| 20 | 第 7 節 |
| 10 | 第 8 節 |
| 4、7、21 | 不在這裡：#700 `### Blocking` 的驗收項措辭是 GitHub 上的事，交主 session。7 建議的程式改動（含 `[` 的錨定規則逐段比對）就是驗收項 (4) 等使用者決定的行為，沒有動 |
| 11 | 不在這裡：要不要把 `.gitignore` 的裁決移到另一張 issue 是主 session 與使用者的事 |
| 15 | 沒有動：大 `.gitignore` 的 CPU 是線性的、上界是 git 自己的 100 MiB；「三件都已不排除就提早結束」不成立——之後的規則行會把它們重新排除 |
| 17 | 沒有動：#692 的 `web-access.md`，這一輪不碰 #692 的檔 |
| 14、18、22 | 記錄，沒有缺陷 |

## 11. 測試與負控

- 新測試：`GitignoreRemedyCLITests`（8 支）、`SourcesIndexExclusionOrderTests`（2 支，其中「已記過的 digest 照常重存」修前也綠，防過度收緊）。修前（`7ba4d695` 的程式碼）
  跑同一組斷言（扣掉只能以新的原因寫的 `testAFailedWriteLeavesTheCreatedFileEmpty`，其餘把新原因的斷言換成看檔案）：7 支全紅、19 則失敗；`SourcesIndexExclusionOrderTests`
  1 支紅（拒絕時留下 `sources/0c/…` 那個存檔）、1 支綠（防過度收緊的那一支）。
- 負控（每一則反向編輯還原，檔案雜湊與修改前相同）：
  1. 處置改回 b41 的 `-v` 查法 → 2 支、7 則紅；
  2. 拒絕接回一行 → 2 支、10 則紅；
  3. warning 的匯入那一句與處置接回第一行 → 1 支、2 則紅；
  4. 寫入失敗時加回 `unlink(path)` → 3 支、3 則紅；
  5. 拿掉 `LOCK_SH` 之後的路徑比對 → 1 支、2 則紅；
  6. 拿掉 `store-source` 寫存檔之前的 index 驗證 → 1 支、1 則紅；
  7. `effect` 把新建了空檔的兩格歸成 `untouched` → 1 支、1 則紅。

## 12. 給使用者

1. **行為改變**：這一次新建的 `.gitignore` 寫入失敗時，空檔留著（先前刪掉）——與 b41 的等鎖逾時同一個理由。訊息說它留著。
2. **行為改變**：`.gitignore` 只把 `sources/index.jsonl` 放回來時，`store-source` 在寫存檔之前就拒絕（先前同樣拒絕，但先寫了存檔）。
3. **行為改變（放寬一個假拒絕）**：先看在等鎖時 `.gitignore` 被刪掉或換掉，取到鎖之後重看——先前報「沒有寫入權限（ENOENT）」。
4. 訊息：`file add` 的拒絕分三行、warning 分行；否定規則那一格的查法改寫。拒絕與報 warning 的條件都沒有變，#700 `### Blocking` 的四項收緊不受這一輪影響。
5. 收緊清單（finding 4、7、21）：#700 `### Blocking` 現在那一項（b42 更正措辭）已列四種。補一點給主 session 改措辭時參考：第 (1) 種（只排除內容、`sources/.gitignore` 存在）
   也包含 `lstat` 看不到它在不在（例如 `sources/` 沒有讀取權限）的情形——第 6 節只改了訊息，判讀照舊算在。
6. `tools/list`：59,159 → 59,159 bytes（±0；MCP 說明沒有改）。

仍待使用者裁決（沒有動）：#700 `### Blocking` 的四項——MCP `akashic_import_wos` 的 `dry_run` 照建佈局與區塊、symlink 的 `.gitignore` 一律拒絕／報、兩個匯入的 MCP 說明要不要
為 `gitignoreWarning` 加字、b41 的四種收緊（含 `[` 的錨定否定規則）要不要接受。
