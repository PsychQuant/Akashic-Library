# 2026-10-15 b39：b38 verify 對 #692、#700 的修正

b38 verify（R7，六席）對 #692（`web-read`、web-access.md）與 #700（`.gitignore` 的 sources 區塊）的 findings 與使用者 2026-10-15 對 #700 的裁決。
MEDIUM 三則全處理（兩則程式、一則揭露），各有修正前會紅的回歸測試，程式的兩則有負控；LOW 逐則處理（第 4 節），INFO 只讀或順手修。
下面的編號是 findings 檔的索引（R7 的合併報告把同一件事合成一條，這裡逐則列）。

## 1. #700 MEDIUM（0、9、11、15、17）：規則之後的否定規則

**問題**：`hasRuleLine` 只找標記之後有沒有一行規則，不看它後面的行。git 對同一個 `.gitignore` 以**最後一條**符合的規則為準，所以區塊之後接一行
`!sources/`（或 `!sou*/`、`!*`、`!*/`、`!/sources`，或區塊裡 `sources/` 之後的否定）時 git 不排除 `sources/`，而判讀說「區塊已在」：`doctor` 不出聲、
`file add` 照常成功、兩個匯入不警告。b37 寫的「若且唯若 git 排除」只對它的語料成立——語料只變動單一規則行。`store-source` 寫入前的 `git check-ignore`
照舊擋住寫入（fail-closed），剩下的外流路徑是手動複製進 `sources/` 之後 `git add`。

**實測**（git 2.55，2026-10-15，`git check-ignore -q`，`sources/x`、`sources/ab/cd`、`sources/.gitkeep` 三個路徑）：區塊之後接 `!sources/`、`!sou*/`、`!*`、
`!*/`、`!/sources`、`!sources`、`!/*`、`!**`、`!**/`、`!**/sources`、`![s]ources`、`![^a]ources`、`!s?urces`、`!sources/ `（行尾空格）、`!sources/\r` 都把三個路徑
放回來；`!sources/x`、`!sources/*`、`!sources/**`、`!/sources/**/`、`!*/**`、`!.gitkeep`、`!x`、`!foo/`、`  !sources/`（行首空白）、`\!sources/`、單獨一個
`!`、`!sources\ `（跳脫的行尾空格）都不放回——git 不進被排除的目錄，裡面的檔放不回來。`!sources/` 之後再一行 `sources/` 又排除。規則是只排除內容的
`sources/*` 時，`!sources/x` 放回 `sources/x`、`!.gitkeep` 只放回 `sources/.gitkeep`。

**修正**：`hasRuleLine` 換成 `ruleState`，逐行照 git 的順序走：規則行排除；行首就是 `!` 的行，去掉 `!`、照 git 的 `trim_trailing_spaces` 去行尾
（跳脫的空格保留）之後：

- 排除的是**目錄**（`sources/`、`/sources/`、`sources`、`/sources`）：只有符合根目錄 `sources` 這個目錄本身的否定規則撤銷它（`negationReachesSources`：
  結尾 `/` 只限目錄；不含 `/` 的比名字；含 `/` 的錨定、開頭的 `**/` 可以是零層，之後還有 `/` 就碰不到根目錄的 `sources`）。名字的比對是 git
  wildmatch 的子集（`*`、`?`、反斜線），ASCII 不分大小寫（macOS 的 repo 預設 `core.ignorecase=true`）；`[…]` 不模擬，當成符合。
- 排除的是**內容**（`sources/*` 等）：任何一行非空的否定規則都撤銷它（這裡不知道裡面有哪些檔名）。
- 否定之後再一行規則行，重新排除。

被放回來時是新的 `SourcesIgnoreContent.ruleNegatedLater` ／ `SourcesIgnoreProblem.ruleNegatedLater`：`file add` 拒絕、`doctor` 與兩個匯入報 warning；
原因說出是否定規則與「最後一條為準」，處置是「刪掉區塊之後放回 sources/ 的否定規則（或移到區塊之前）」、**不要再貼一份**（區塊已在）。`.gitignore` 不改
——使用者寫的否定規則可能是刻意的，替他在最後補一份區塊等於推翻它。

宣稱收窄：判成已在 ⇒ git 排除（列出的每一種形狀）；反方向只對語料裡「若且唯若」那一組成立。保守（判成不在而 git 可能排除）的形狀明列：規則寫在標記
之前（先前就是 `markerWithoutRule`）、`[…]` 字元類、只排除內容的規則之後接一行碰不到 `sources/x` 的否定、`!SOURCES/`（取決於 `core.ignorecase`）。
方向都是多報。

**同一個判斷的其他路徑**（逐一查過）：`judgeSourcesIgnore` 只有 `ruleState` 一份，先看（`inspectSourcesIgnoreOnce`）與鎖內重看
（`appendSourcesIgnoreUnderLock`）共用它，兩處都接上新的一格；`file add`（`.refuse`）、`doctor`、CLI `import-zotero`、MCP 兩個匯入（`.report`）都經
`ensureLayout`；`store-source` 的拒絕訊息（`assertSourcesExcluded`）補一句「區塊之後有 ! 開頭的否定規則把 sources/ 放回來時它不改」。量測文件第 87 列的
Python 腳本是同一個判斷的第二份，照同一個演算法改寫，對測試的 34 種形狀與 Swift 逐一同答；live registry 重量：`main 913 file utf8 block writable`（不變）。
文件：零實例第 87 列、量測文件第 87 列、`store-format.md`、`mcp-cli-parity.md` 四列（doctor、兩個匯入、`file add`）、本檔與 b37 changelog 的「若且唯若」
劃線改寫。

**測試**（`GitignorePreservationCLITests`）：

- `testANegationAfterTheRuleIsJudgedTheWayGitReadsIt`：29 種否定規則的形狀（上面實測的那些）與 5 種保守的形狀，判讀本身。
- `testThePresentJudgementAgreesWithGitCheckIgnore`：語料加這 29 種（若且唯若）與 5 種保守的（單向：判成不在），每一種在暫存的 git repo 以
  `git check-ignore` 對照；說明改寫成實際涵蓋的命題。
- `testDoctorAndFileAddReportARuleThatALaterNegationUndoes`（真 binary）：區塊加 `!sources/`，`doctor` 報、說出否定規則、不叫人再貼；`file add` 拒絕；
  `.gitignore` 位元組不變。

**負控**（反向編輯還原）：否定規則那兩行改成不生效 → 上面三支紅（3 支、48 則）。

## 2. #692 MEDIUM（1、4、10、13）：〈開始前〉探測攔不下 `web-read url` 的舊契約

**問題**：b37 改了 `web-read url` 的契約（不修剪網址檔、擋塞進名稱的 IP、頂層名稱收 `xn--`）卻只為 `check` 補了探測；`url` 的探測只呼叫一條 happy path，
b34 以來每個 binary 都放行。使用者 2026-10-05 的裁決是「舊 CLI 在開始前的探測就停」，而開分頁、導航、取 API 三個區塊靠 `web-read url` 擋住送出去的網址。

**修正**：〈開始前〉第 4 點多一條真呼叫——三個網址檔（前導空白、開頭的 UTF-8 BOM、`app-127-0-0-1.nip.io`），`web-read url` 的結束碼依序要是 1、1、4，
不符就停、說出是 `web-read url` 的契約。說明那一段寫出「CLI 的契約每改一次，探測就多一條真呼叫」與「探測只認得這裡列的契約」。實測（bash 與 zsh 都跑）：
使用者機器上裝的 `akashic`（10-08，b37 之前）得 `000`、`f2a321e4` 得 `104`（BOM 放行，見第 4 節的 5）、這一輪的 binary 通過。

**測試**（`WebAccessReadContractTests`，從文件抽出區塊實跑）：`testTheStartProbeStopsACLIWithAnOldUrlContract`——三個替身各缺一條（修剪網址檔、拿掉開頭的 BOM、
放行塞進名稱的 IP），其餘轉給真 binary，每一個都以 1 停下並說出原因；`testTheStartProbePassesWithTheCurrentCLI` 照舊（真 binary 通過整個探測）。

**負控**：探測的判定改成 `true ||` → 新測試紅（3 個替身、6 則）；還原後與修改前的文件逐位元組相同（`cmp`）。

**沒有改**：security 席另指出 `check` 那一條的 2 也是「讀回的文字不能用」的結果、證不到「沒有訊號 → 2」那條路徑本身。探測要的安全性質是「驗證服務上
不給 `READ-OK`、不寫出文字」，兩條路徑都滿足；~~再比對輸出文字要依賴語系（中文字的比對），換到的只是分辨兩種同樣停下的路徑~~（b40 verify INFO 13：
這個理由不成立——兩條路徑都印 ASCII 的 `READ-PAUSE`、以 2 結束，差別只在後面的中文原因句，`grep -F` 逐位元組比對，與語系無關）→ 兩條路徑同樣停下、
都不給 `READ-OK`、不寫出文字，探測要的性質兩條都滿足，不需要分；這一輪不加。

## 3. #700 MEDIUM（2）與使用者 2026-10-15 裁決：等鎖的 10 秒上限保留

**揭露**：b37 把 `flock` 的等待改成 `LOCK_NB` 每 20 ms 試一次、至多 10 秒（`lockTimedOut`：`file add` 拒絕、`doctor` 與兩個匯入報 warning），**改了使用者
2026-10-05 的裁決**——「非 akashic 程序長時間持 flock 時 akashic 會一直等，只記錄」。b37 changelog 把它列在「已修」、〈給使用者〉沒有列。使用者 2026-10-15
裁決**保留 10 秒上限**，並要求這一輪三件事，全做：

- **揭露**：本節；b37 changelog 第 4 節補一句更正；零實例第 94 列與量測文件第 94 列補記（見第 4 節的 6）。
- **單調時鐘**（3）：期限改用 `ContinuousClock`（先前 `Date()`，等待期間系統時間往回撥，上限跟著拉長）；`EINTR` 也看期限（先前直接重試、不看期限）。
  `EINTR` 在 `LOCK_NB` 下造不出來，新增測試注入點 `SourcesIgnoreIO.tryLock`（換掉 `flock` 本身；`lockWait` 照舊）。
- **「沒有讀」的首句**（18）：讀不到與等鎖逾時沒有讀內容，首句改成「.gitignore 沒有讀到，不知道裡面有沒有生效的 sources 排除區塊」（`SourcesIgnoreProblem.headline`，
  warning 與 `file add` 的拒絕共用），處置改成「…自己打開它看，沒有區塊才加上下面這段（區塊已在就不用加）」——不再叫人無條件貼第二份。其餘各格讀過內容，
  或 git 本來就不讀那個檔，「沒有生效的」照舊。

**同一個判斷的其他路徑**：`lock(_:_:)` 只有一份，先看（`LOCK_SH`）與附加前（`LOCK_EX`）共用。repo 裡另外兩處 `flock`（`S2Throttle`、`FulltextAttemptLedger`）
是阻塞鎖、沒有上限，屬 #664、#613，不在這一輪。首句的兩個出口（`warningLines`、`StoreIOError.sourcesIgnoreNotWritten`）都改讀 `headline`。

**測試**：`testTheLockDeadlineDoesNotUseTheWallClock`（`lock` 的本文不讀 `Date(`、用 `ContinuousClock`）；`testAnInterruptedLockAttemptStillHonoursTheDeadline`
（試鎖一直回 `EINTR`、上限 0.2 秒：照樣報 `lockTimedOut`；修前永遠不返回，5 秒逾時）；`testUnreadAndLockTimedOutDoNotClaimThereIsNoBlock`（兩格的首句與
處置、`file add` 拒絕的首句；讀過內容的五格照舊）；`testUnreadableGitignoreIsNeitherRewrittenByFileAddNorByDoctor` 多斷言真 binary 的 `file add` 與 `doctor`
說「沒有讀到」。

## 4. LOW 與 INFO

| index | 處置 |
|---|---|
| 0、9、11、15、17（#700） | 第 1 節 |
| 1、4、10、13（#692） | 第 2 節；13 的後半（`check` 探測分不出兩種 2）不改，理由在第 2 節 |
| 2（#700） | 第 3 節 |
| 3（#700） | 第 3 節（使用者裁決） |
| 5、8、12、16、27（#692） | 已修：`web-read url` 以 `Data` 讀網址檔、`String(decoding:)` 解碼（不拿掉開頭的 BOM），解碼再編碼要逐位元組相同（不是合法 UTF-8 照舊 `URL-FAIL`）。開頭的 BOM 因此是形狀不合（1）；訊息與 `--help`、web-access.md 那一格寫明。同一個讀法用在 `readTrimmed`（`landing` 與 `check` 讀主機檔，修剪的集合不含 U+FEFF：BOM 留著、主機判成認不出）——這幾個檔由 CLI 自己寫，不會有 BOM，行為不變。`testUrlModeKeepsALeadingByteOrderMark`。探測多一條 BOM（第 2 節） |
| 6（#700） | 已修：零實例第 94 列與量測文件第 94 列補記等鎖上限（10 秒、`lockTimedOut`、單調時鐘、逾時不留空檔、觸發條件、改了先前的裁決）；b37 changelog 第 4 節「第 87、89、93 列」那句補更正 |
| 7（#700） | 已修：`file add`、`doctor`、`import-zotero` 的說明把兩種條件分開——「沒有生效的區塊而…」（非 UTF-8、硬連結、沒有寫入權限、有標記沒有規則、規則被否定）才不改／拒絕，「不論有沒有區塊」（讀不到、symlink、不是一般檔、大到 git 不讀、等鎖逾時）都不改／拒絕；`file add` 寫明已有生效的區塊時「不論它是什麼編碼、有沒有其他硬連結」都什麼都不做。`testTheHelpSeparatesConditionsThatNeedNoBlockFromUnconditionalOnes` |
| 14（#700） | 記錄、不改程式：b37 把 `LibraryIndex.rebuild` 的換位改成 `rename(2)`，換位之後 index 檔的模式與 xattr 是新建的那一份（先前 `replaceItemAt` 保留原檔的；regression 席以 scratch 程式量到 `0600` 與備份排除的 xattr 在重建後消失）。index 是衍生層、每次重建都換；手動對它 `chmod 600` 或設備份排除的人要知道這些設定不會留下來。devil's advocate 量到這個改動有因果（沒有它，6 個 `doctor` 同時跑 25 輪舊 binary 4／150 失敗、新的 0／150）。要不要在換位前把原檔的模式帶過去，沒有人裁決過，這一輪不改；沒有開 issue（只讀不寫 GitHub） |
| 18（#700） | 第 3 節 |
| 19（#700，INFO） | 不改：兩個匯入的 MCP 說明要不要為 `gitignoreWarning` 加字，待使用者裁決（#700 的 Blocking）。這一輪 `tools/list` 59,173 → 59,173 bytes（±0；`Server.swift` 沒有動）。**更正**（b40 verify INFO 14、16、22）：59,173 是這一輪的 base；整合之後的 main（`04131a49`）以真 binary 重量是 **59,171**——同一批的 #564 少了 2 bytes（見 `2026-10-15-b39-name-classification-564.md`），餘裕約 829 而不是 827 |
| 20（INFO） | 不在這一輪：b36 LOW 23 屬 #705（已 verified），處置交給那張 issue |
| 21、28（INFO） | 驗證過、沒有缺陷，不動 |
| 22（INFO） | 已修說明：`lock` 的 doc 與 `store-format.md` 寫明 `EWOULDBLOCK` 以外的錯誤（`ENOTSUP`、`ENOLCK` 之類）一律不鎖、照常往下；行為不變 |
| 23（INFO） | 已修：新建的 `.gitignore`（`O_EXCL`）拿不到鎖時，仍是空的、路徑仍指著它就刪掉，`lockTimedOut` 說的「沒有寫」才成立。`testACreatedGitignoreIsRemovedWhenItsLockTimesOut`（注入一直 `EWOULDBLOCK`） |
| 24（INFO） | 不改：`rename(2)` 失敗時的錯誤沒有 errno 的說明文字。先前的 `replaceItemAt` 同樣不透明，不是退步；要造出 rename 失敗而 temp 已建好的情形才測得到，這一輪不加 |
| 25（INFO） | 不改：symlink 的 `.gitignore` 一律拒絕／報，是待使用者裁決的一項（#700 的 Blocking） |
| 26（INFO） | 不改：MCP `gitignoreWarning` 的處置句與 CLI 共用，屬 `gitignoreWarning` 的 MCP 文字那一項裁決 |

**合併負控**（第 3、4 節的 Swift 幾則，反向編輯還原、與修改前逐位元組相同）：期限改回 `Date()` 而 `EINTR` 直接重試、逾時不刪空檔、兩格首句改回「沒有生效的」、
`readExactly` 改回 `String(contentsOfFile:)`、`file add` 的說明拿掉「沒有生效的區塊而」→ 8 支、18 則紅（`testTheLockDeadlineDoesNotUseTheWallClock`、
`testAnInterruptedLockAttemptStillHonoursTheDeadline`、`testACreatedGitignoreIsRemovedWhenItsLockTimesOut`、`testUnreadAndLockTimedOutDoNotClaimThereIsNoBlock`、
`testUnreadableGitignoreIsNeitherRewrittenByFileAddNorByDoctor`、`testUrlModeKeepsALeadingByteOrderMark`、`testTheStartProbePassesWithTheCurrentCLI`、
`testTheHelpSeparatesConditionsThatNeedNoBlockFromUnconditionalOnes`）。

## 5. 沒有改的

- 零實例表沒有新增列：否定規則是第 87 列（「區塊已在」的判讀）的修正，等鎖上限是第 94 列（先看、後寫之間的窗口）的補記，BOM 與 `url` 的探測是第 93 列（開分頁前的網址形狀）的
  修正。補記寫在那幾列與量測文件。
- MCP 說明（`Server.swift`）沒有動。
- 規則寫在標記之前、`[…]` 字元類、`sources/` 加一個 NUL 這幾種 git 排除而判成不在的形狀（devil's advocate 量到）：方向是多報，照舊。

## 6. 給使用者

1. 第 3 節：等鎖的 10 秒上限照 2026-10-15 的裁決保留；它改了 2026-10-05 的「只記錄」，這一次寫進 changelog、零實例表與 `store-format.md`。
2. 新的拒絕／warning：`.gitignore` 的 sources 區塊之後有一行把 `sources/` 放回來的否定規則（`!sources/`、`!*` 之類）時，`file add` 拒絕、`doctor` 與兩個匯入
   報 warning（先前不出聲）。live registry 沒有這種 store。
3. 需要新的 `akashic` CLI：〈開始前〉的探測多一條 `web-read url` 的真呼叫，b38 以前的 CLI 都會在那裡停下。

仍待使用者裁決（沒有動）：#692 的 `www.google.com` 整個主機當驗證服務；#700 的 MCP `akashic_import_wos` `dry_run` 照建佈局與區塊、symlink 的
`.gitignore` 一律拒絕／報、兩個匯入的 MCP 說明要不要為 `gitignoreWarning` 加字。
