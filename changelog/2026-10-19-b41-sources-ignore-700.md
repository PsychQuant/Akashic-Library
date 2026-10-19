# 2026-10-19 b41：b40 verify 對 #700（sources 區塊的判讀、等鎖逾時的空檔）與 #692（web-access.md 的探測說明）的修正

b40 verify（六席，驗 `5f140579`）對 #700 與 #692 的 findings。#692 這一輪通過，只剩兩則 INFO；#700 有一則 MEDIUM。
MEDIUM 有修正前會紅的回歸測試與負控；LOW 逐則處理（第 7 節），INFO 順手修或只讀。下面的編號是 findings 檔的索引。

## 1. #700 MEDIUM（0，同 18、21）：等鎖逾時之後刪掉新建的空檔，可能刪到別人剛寫好區塊的檔

**問題**：b39 讓 `appendSourcesIgnoreUnderLock(create: true)` 在等鎖逾時之後，以「仍是空的、路徑仍指著同一個 inode」為據 `unlink` 這一步以 `O_EXCL`
建的 `.gitignore`（b38 verify INFO 23：先前留下一個空檔，`lockTimedOut` 說的「沒有寫」不成立）。那時**沒有持鎖**：檢查與刪除不是原子的。
而新建的檔拿不到鎖，唯一的原因是另一個程序在我們建好之後打開了同一個檔、先取到 `LOCK_EX`——它正要把區塊寫進去（devil's advocate：這個清理
唯一真的觸發得了的情境，正是它會造成傷害的那一個；沒人持鎖就不會逾時）。它在我們的檢查之後寫進區塊時，寫進的是一個已經不在路徑上的
inode，照樣回報成功，磁碟上沒有 `.gitignore`。

**修正**：逾時就不刪，照實說——新的 `SourcesIgnoreProblem.lockTimedOutAfterCreating`：「這一次新建了它（空的），之後另一個程序持有它的鎖…新建的
檔留著：持鎖的程序打開了同一個檔、可能正要把區塊寫進去，沒有鎖時刪掉它會刪到對方寫好的檔」。首句與處置同 `lockTimedOut`（「沒有讀到」、
「沒有區塊才加」）。空的 `.gitignore` 對 git 無害，下一次先看把它當既有的檔附加。`removeIfStillOurEmptyFile` 拿掉。寫入失敗時的 `unlink`
（`writeFailed`、新建且一個位元組都沒寫進去）不動：那時持著 `LOCK_EX`，之後取到鎖的程序會發現路徑不再指著它的檔而重看。

**測試**：`testACreatedGitignoreIsNotDeletedWhileAnotherHolderHasItsLock`——試鎖的注入點在第一次被呼叫時（我們已經建好檔）以另一個 open file
description 打開同一個檔、取真的 `flock(LOCK_EX)`（B），我們等 0.2 秒逾時；B 在 `ensureLayout` 回來之後寫進區塊。斷言 B 寫的區塊在路徑上。
`testACreatedGitignoreIsRemovedWhenItsLockTimesOut` 改成 `testACreatedGitignoreIsLeftInPlaceWhenItsLockTimesOut`（空檔留著、原因說它留著、
下一次照常附加）。

**負控**（反向編輯還原，檔案雜湊與修改前相同）：逾時分支加回「仍是空的、同一個 inode 就 unlink」→ 上面兩支紅（3 則）。

## 2. #700 LOW（5、6、8、9、10）：「判成已在 ⇒ git 排除」的三族反例

三族都是「判成已在而 git 不排除」，`store-source` 寫入前的 `git check-ignore` 仍擋（fail-closed），外流路徑只剩手動 `git add`。

- **NUL**（5、6、8）：git 把 `.gitignore` 的一行當 C 字串讀，第一個 NUL 之後不算。`!sources/\0junk` 對 git 是 `!sources/`，判讀卻整行比對、
  判成碰不到 `sources`。`ruleState` 每一行先在第一個 NUL 截斷（沒有 NUL 時才去緊接換行的 CR），規則行與否定行都是。同一個根因在規則行那一邊
  是多報（`sources/\0x` git 排除而判成不在，b39 第 5 節記過），這一輪一起消掉。
- **星號串**（9）：git 的 wildmatch 把連續的 `*` 收成 `**`，`***/sources` 與 `**/sources` 相同、可以是零層；`negationReachesSources` 只剝字面的
  `**/`。換成 `globCanMatch`（下一節），兩個以上的 `*` 都可以跨 `/`、之後接 `/` 時可以是零層。git 只在 `**` 前面是開頭或 `/` 時這樣算，這裡一律
  這樣算——只會多算符合，用在否定規則上是多報（`!s**/ources` git 不放回、判成不在，列進保守的一邊）。
- **只排除內容的規則加 `sources/.gitignore`**（10）：`sources/*` 這類規則不排除 `sources` 這個目錄，git 進得了它、會讀 `sources/.gitignore`，那一份對
  底下的路徑比根目錄的優先（git 2.55 實測：`sources/.gitignore` 是 `!*` 時 akashic 寫的每一個路徑都不被排除）。判讀不讀那一份：規則只排除內容
  而 `sources/.gitignore` 在（`lstat`；symlink、目錄也算在，判斷不了也算在）就不算已在——新的 `contentRuleWithNestedGitignore`（`file add` 拒絕、
  `doctor` 與兩個匯入報 warning）。排除目錄本身時 git 不讀它，不受影響。保守：只有註解的那一份 git 照樣排除，判成不在（多報）。

**宣稱的範圍**（寫在 `store-format.md`、零實例第 87 列、量測文件第 87 列、`mcp-cli-parity` 的 `akashic_doctor` 列、測試的說明）：判成已在 ⇒ git 排除
**akashic 寫進 `sources/` 的每一個路徑**（`sources/index.jsonl`、兩個十六進位字元的存檔子目錄與裡面的存檔與 `.…incoming-…` 暫存檔）；只說 store
根目錄的 `.gitignore` 與 `sources/.gitignore`（排除目錄本身時 git 不進 `sources/`；存檔子目錄被放回來時判成不在，所以更深的 `.gitignore` 不必讀）；
不說 akashic 沒寫的路徑（`sources/.gitkeep`）與已經被追蹤的檔；git 的其他排除來源（`core.excludesFile`、`.git/info/exclude`）只會多排除。

## 3. #700 LOW（2、7、11）、INFO（15、19）：只排除內容的規則之後接任何否定規則都算撤銷

**問題**：`ruleState` 對 `sources/*` 這類內容形規則，把標記之後任何一行非空的否定規則都當成放回來。`sources/*` 加 `!sources/.gitkeep`（保留空目錄的
慣用寫法）git 排除 akashic 寫的每一個路徑、只放回 `.gitkeep`，`file add` 卻拒絕、`doctor` 與匯入每次都報，處置句「刪掉否定規則或移到區塊之前」
會讓使用者放棄那個寫法，「把它放了回來」對這種形狀為假。b37 放行的 store 因此被拒，摘要沒有寫出來。

**修正**：判讀改成看 akashic 寫的路徑。三件事各自記「最後一條符合它的規則是排除」：`sources` 這個目錄本身（目錄形規則排除它，排除了底下全部排除）、
`sources/index.jsonl`、存檔子目錄（內容形規則排除這兩件；子目錄排除了，裡面的檔就排除）。生效＝目錄本身被排除，或兩件內容都被排除。否定規則
只撤銷它碰得到的那幾件（`negationReach`）：照 git 的語意，結尾的 `/` 只限目錄、不含 `/` 的比最後一段名字、含 `/` 的錨定比整條路徑；比對是
`globCanMatch`——git 的 wildmatch（`WM_PATHNAME`、ASCII 不分大小寫）對「這段文字的某一個實例」的位元集合模擬，存檔子目錄的兩個字元是十六個字元之一，
整行只走一遍（`[…]` 字元類照舊當成都碰得到）。子目錄被放回來時不算生效，即使 `sources/**` 仍排除裡面的檔——git 會進那個子目錄、讀它的 `.gitignore`。
`negationReachesSources` 與 `globMatches` 由它取代。

保守（判成不在而 git 可能排除）的形狀現在是：規則寫在標記之前、`[…]` 字元類、`core.ignorecase`（區分大小寫的 repo）、不在開頭也不在 `/` 之後的 `**`、
否定之後以別種寫法重新排除（`/sources`、`!**/*/`、`*`——INFO 15；目錄形區塊之後接 `*`、`!*/`、`!*.md` 那一種〔LOW 7 的 b〕git 放回了存檔子目錄，
照新的範圍判成不在是對的）、只排除內容而 `sources/.gitignore` 只有註解。

**訊息**（INFO 19、20）：`ruleNegatedLater` 的原因說出碰得到哪幾個路徑、只碰得到別的檔的否定規則不算、判讀在哪裡保守；處置改成「store 在 git 工作樹裡時
可用 `git check-ignore -v sources/index.jsonl sources/00/` 看——少了哪一個就是區塊之後的否定規則把它放了回來：刪掉那一行或把它移到區塊之前；兩個都列出、
這裡仍判成不生效時是判讀保守。兩種情形都可以在檔尾補一行頂格的 `sources/`」。首句改成「.gitignore 的 sources 排除區塊之後有否定規則，不能確定它生效」——
先前首句說「沒有生效的區塊」、處置說「區塊已在」，同一則訊息兩句相反。`import-zotero` 的 `--help` 補「區塊已在、只是被否定規則或 `sources/.gitignore` 擋住時
doctor 不補，問題還在就照報」（INFO 20：先前說「處置之後跑 doctor 就補上區塊」，對這一格不成立）。

**量測**：Python 鏡射（量測文件第 87 列的腳本，同一個演算法）與 git 2.55、2.54 對 5,500 個隨機 `.gitignore`（區塊前後混入規則行、53 種否定寫法與隨機 glob、
註解、CRLF、行尾空格；一成帶 `sources/.gitignore`）對照，判成已在而 git 不排除的 **0** 個；八種規則行 × 53 種否定的逐一掃描，多報 12 組，全是 `[…]` 與
`s**/ources`。Swift 與鏡射對 6,000 個隨機形狀逐一同答（暫時的測試，沒有 commit）。

## 4. #700 LOW（3）：`changedWhileChecking` 沒讀到穩定的內容，卻斷言「沒有生效的區塊」、叫人無條件再貼

`changedWhileChecking` 的兩條來路——先看因 `ELOOP` 反覆重看、從沒讀到內容；或附加的迴圈中檔案一直被別的程序改，而別的程序很可能正在加區塊——都沒有
穩定的讀取。首句改成「.gitignore 一直在變、沒有讀到穩定的內容，不知道裡面有沒有生效的 sources 排除區塊」，處置改成「重跑；仍不行就自己打開它看，沒有
區塊才加上下面這段（區塊已在就不用加）」。`headline` 的 switch 拿掉 `default`，逐格歸類（新增一格時編譯器逼人選一類）。

**測試**：`testUnreadAndLockTimedOutDoNotClaimThereIsNoBlock`（只釘 7 種）換成 `testEveryProblemsHeadlineAndRemedyAgreeWithWhatWasRead`：17 種原因全部，
分成「沒有讀內容／沒有讀到穩定的內容」「讀過、區塊在而不能確定生效」「其餘」三類各自斷言首句與處置，`file add` 的拒絕同一個首句；歸類的 switch
沒有 `default`，`all` 與 0..<17 做集合比對。

## 5. #700 LOW（4）：`ruleNegatedLater` 在兩個匯入沒有測試

`ServiceTests.testBothImportsWarnWhenALaterNegationUndoesTheBlock`（`akashic_import_wos` 的 `dry_run` 與實跑、`akashic_import_zotero`，回應的
`gitignoreWarning` 與 `warningLines` 逐字相同、`.gitignore` 不變）與 `ZoteroReportCLITests.testImportWarnsWhenALaterNegationUndoesTheBlock`（CLI
`import-zotero` 以 0 結束、stderr 開頭就是那則 warning）。

## 6. #700 LOW（1）、INFO（17）：`store-format.md` 的規範段

「讀不懂的 `.gitignore` MUST NOT 被改寫」那一段把兩種條件分開寫（同 b39 改過的三個 `--help`）：**沒有生效的區塊、而**它不是 UTF-8 文字、有其他硬連結、
沒有寫入權限、有標記沒有規則、規則可能被之後的否定規則放回來、規則只排除內容而 `sources/.gitignore` 在——已有生效的區塊時不論編碼、硬連結、權限都什麼都
不做；**不論有沒有區塊**：讀不到、symlink、symlink 打不開、不是一般檔、大到 git 不讀、等鎖逾時。同一段的「`sourcesRuleLines` 是封閉列舉」改指
`sourcesDirectoryRuleLines` 與 `sourcesContentRuleLines`，那份沒有程式讀的聯集拿掉（INFO 17）。

## 7. findings 逐則

| index | 處置 |
|---|---|
| 0、18、21（#700） | 第 1 節 |
| 1（#700） | 第 6 節 |
| 2、7、11、15、19（#700） | 第 3 節。7 的 b（目錄形區塊之後接 `*`、`!*/`、`!*.md`）：git 放回了存檔子目錄，照新的範圍判成不在是對的；訊息不再斷言「放了回來」，並給出一定有效的處置（檔尾補 `sources/`）。15 的「否定之後以別種寫法重新排除」照舊保守，列進保守的形狀與訊息 |
| 3（#700） | 第 4 節 |
| 4（#700） | 第 5 節 |
| 5、6、8、9、10（#700） | 第 2 節 |
| 12（#692，INFO） | 已修：web-access.md 的「CLI 的契約每改一次，探測就多一條真呼叫」限縮成「`url`、`origin`、`check` 這三個 `web-read` 子命令的契約每改一次」，並寫明 `web-read landing`（b34、b35 改過）沒有探測 |
| 13（#692，INFO） | 已修：b39 changelog 第 2 節「再比對輸出文字要依賴語系」劃線更正——兩條路徑都印 ASCII 的 `READ-PAUSE`、以 2 結束，`grep -F` 與語系無關；不分的理由是兩條路徑同樣停下、都不給 `READ-OK`、不寫出文字 |
| 14、16、22 的 1（#700，INFO） | 已修文件：b39 changelog 第 4 節 19 列與 plugin/CHANGELOG 那一段補更正——59,173 是那一批的 base，整合之後的 main（`04131a49`）以真 binary 重量是 **59,171**（同一批 #564 的 −2），餘裕約 829。#700 的 `### Blocking` 那一句的數字要由主 session 改 |
| 17（#700，INFO） | 第 6 節 |
| 20（#700，INFO） | 第 3 節（首句、`import-zotero` 的 `--help`） |
| 22 的 2、3（INFO） | 不在這裡：issue 本文的日期與歸屬說明是 GitHub 上的事，交主 session |
| 23（INFO） | 記錄，沒有缺陷 |

## 8. 同一個判斷的其他路徑（逐一查過）

- 判讀只有 `judgeSourcesIgnore`／`ruleState` 一份：先看（`inspectSourcesIgnoreOnce`）與鎖內重看（`appendSourcesIgnoreUnderLock`）都呼叫它，兩處都在判讀之前
  問一次 `sources/.gitignore`、都接上新的一格。`file add`（`.refuse`）、`doctor`、CLI `import-zotero`、MCP 兩個匯入（`.report`，含 `dry_run`）都經 `ensureLayout`。
- 首句的兩個出口（`warningLines`、`StoreIOError.sourcesIgnoreNotWritten`）都讀 `headline`。
- `store-source` 的拒絕訊息（`assertSourcesExcluded`）補一句「規則只排除內容而 sources/ 裡另有 .gitignore 時它不改」；它自己以 `git check-ignore` 驗，判讀不受影響。
- 量測文件第 87 列的 Python 腳本是同一個判斷的第二份：照同一個演算法改寫（NUL、三件事、位元集合的 wildmatch、`sources/.gitignore`），與第 3 節的鏡射逐字同一份邏輯。
  live registry 重量：`main 913 file utf8 block writable`（不變）。
- 等鎖逾時：`lock(_:_:)` 只有一份；`unlink` 只剩持著 `LOCK_EX` 的寫入失敗那一處。repo 裡另外兩處 `flock`（`S2Throttle`、`FulltextAttemptLedger`）不刪檔，不在這一輪。
- 三個 CLI 說明（`file add`、`doctor`、`import-zotero`）補「規則只排除內容而 sources/ 裡另有 .gitignore」；`file add` 補「拿不到這一次新建的 .gitignore 的鎖——那時新建的空檔留著」。
  MCP 說明（`Server.swift`）沒有動。

## 9. 測試與負控

- `GitignorePreservationCLITests`：`testThePresentJudgementAgreesWithGitCheckIgnore` 改成對照 akashic 寫的路徑（`index.jsonl`、四個存檔子目錄 `00`、`ab`、`c3`、`f9`
  與每個子目錄裡的存檔與暫存檔），規則行 16 種（加 NUL 兩種與 `sources/*`）、否定 61 種、`sources/.gitignore` 3 種是若且唯若，保守的 7 種單向；
  `testANegationAfterTheRuleIsJudgedTheWayGitReadsIt` 同一份語料與 `globCanMatch` 的幾個邊界；`testRuleLinesAreCutTheWayGitCutsThem` 加 NUL；真 binary 的
  `testAGitkeepExceptionAfterAContentRuleIsNotRefused`、`testANestedGitignoreUnderAContentRuleIsNotTrusted`；`testDoctorAndFileAddReportARuleThatALaterNegationUndoes`
  加「首句不說沒有生效的」；help 的測試加兩種新條件。第 1、4、5 節的測試見各節。
- 負控（每一則反向編輯還原，檔案雜湊與修改前相同）：
  1. 逾時分支加回 unlink → 2 支、3 則紅（第 1 節）；
  2. 拿掉 NUL 截斷 → 3 支、12 則紅；
  3. `**` 只認恰好兩個 `*` → 2 支、8 則紅；
  4. 內容形之後任何否定都撤銷 `index.jsonl`（b39 的行為）→ 3 支、20 則紅（含真 binary 的 `.gitkeep`）；
  5. 判讀不看 `sources/.gitignore` → 3 支、10 則紅；
  6. `changedWhileChecking` 的處置改回無條件再貼 → 1 支、2 則紅；
  7. 先看把 `ruleNegatedLater` 當成已在 → 兩個匯入的測試 2 支、3 則紅。

## 10. 給使用者

1. **行為改變（放寬）**：`.gitignore` 的區塊是 `sources/*` 這類只排除內容的寫法、之後接 `!sources/.gitkeep` 之類只碰得到別的檔的否定規則時，`file add` 自此照常註冊、
   `doctor` 與匯入不再報（b39 起拒絕／報）。
2. **行為改變（收緊，先前放行）**：區塊只排除內容而 `sources/` 裡另有 `.gitignore` 時，`file add` 拒絕、`doctor` 與兩個匯入報 warning（git 會讀那一份，它比根目錄的優先）；
   `!sources/` 後面接 NUL、`!***/sources` 這類否定規則也報。排除目錄本身的 `sources/`（程式寫的區塊、live registry 的那一個）不受影響。這一項與 symlink 那一項同型
   （先前放行、現在拒絕），要不要列進 #700 的使用者驗收項，交主 session。
3. 這一次新建的 `.gitignore` 拿不到鎖時，空檔留著（先前刪掉），訊息說出它留著。
4. `tools/list`：59,171 → 59,171 bytes（±0）。

仍待使用者裁決（沒有動）：#700 的 MCP `akashic_import_wos` `dry_run` 照建佈局與區塊、symlink 的 `.gitignore` 一律拒絕／報、兩個匯入的 MCP 說明要不要為
`gitignoreWarning` 加字；#692 的 `www.google.com` 整個主機當驗證服務。
