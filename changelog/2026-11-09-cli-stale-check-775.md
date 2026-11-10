# 2026-11-09 `akashic` CLI 過期時，開 session 就說出來（#775）

#768 合併之後，`akashic-fetch-fulltext` SKILL 第 0 步要求 `fulltext-contract 8`，而本機的 `akashic` CLI 是 10 月底建置的、只印 6，也不認得 `--version`（回 64）。這件事是有人主動去問才發現的：開 session 時沒有任何訊息，第一個訊號會是 SKILL 第 0 步拒絕執行，或者用舊 CLI 跑了。

safari-browser 的 plugin 已有一個 SessionStart hook 解決同一件事（`hooks/check-cli.sh`）。這一輪比照它，給 akashic-mcp plugin 加上同樣的檢查。

## 改了什麼

- **`akashic --version`**：印建置時的 commit。值住在受追蹤的佔位檔 `Sources/akashic/BuildVersion.swift`，平常是 `unknown`；`scripts/stamp-version.sh` 在建置期間把它改寫成 `git describe --always --dirty --abbrev=12 --exclude='*'`（裸的 `<hash>[-dirty]`），建完還原——命令成功、失敗、收到 INT／TERM／HUP／QUIT 都還原。排除所有 tag，是因為這個 repo 的 tag（`akashic-mcp-v*`、`idd-*-baseline`、`idd-*-verified`）都不描述 CLI 的建置；不排除時 main 會被描述成 `idd-700-verified-51-g<hash>`。
- **akashic-mcp plugin 的 SessionStart hook**（`plugin/hooks/check-cli.sh`、`hooks.json`）：
  - 找不到 CLI（PATH 上沒有，`$HOME/bin/akashic` 也不存在）→ 印建置指令；沒有原始碼時先印 clone 指令。只在 `$HOME/bin` 找到時多說一句「不在 PATH 上」。指令的第一行寫明要不要重建由使用者決定；路徑加 shell 引號，`install` 前先 `mkdir -p`。
  - **契約**：要求的數字從 plugin 內 `akashic-fetch-fulltext/SKILL.md` 第 0 步那一行抽出（只寫在那裡，不在 hook 裡另寫一份）；CLI 印的比它小 → 兩個數字都說出來；CLI 沒有 `fulltext contract`（或執行失敗）→ 說讀不到，並說出要求的數字；SKILL 抽不到 → 說「沒有比對」，不當成通過。這一項不需要原始碼 checkout。
  - **落後原始碼**：原始碼目錄是 `$AKASHIC_SOURCE_DIR`（預設 `$HOME/Developer/Akashic-Library`），基準是 `origin/main`（上次 fetch 時，不連網），沒有這個 ref 才用 HEAD。「package 原始碼」是 `Sources`、`Package.swift`、`Package.resolved`、`repos/biblatex-apa-swift`。判定看內容：這次建置與基準的 package 原始碼相同 → 最新（squash merge 之後就是這樣）；不同而建置是基準的祖先 → 落後；不同而基準是建置的祖先 → 最新；兩者分岔 → 基準上不在這次建置歷史裡的 commit，有沒有哪一個動過那些內容不同的檔，有就落後。落後時印 commit 數與基準上最後一個動到 package 原始碼的 commit 的 hash、日期。checkout 裡沒有建置的 commit、看不到兩者的共同歷史、git 讀不出來 → 說明原因、改比檔案時間；沒有戳記（`unknown`）也比檔案時間。比這一輪舊的 CLI（`--version` 回 64）：基準上已經有 `BuildVersion.swift` → 必定落後，還沒有 → 比檔案時間。
  - 每個 session 都會跑，輸出進的是模型的 context：hook 自己不 fetch（另設 `GIT_NO_LAZY_FETCH=1`，git 2.45 起才有這個變數）、不自動安裝、不覆蓋現有 binary；`--version` 與 `fulltext contract` 各約 4 秒上限，`--version` 逾時就不再探契約，`hooks.json` 另給整支 30 秒上限；任何失敗都 exit 0、不寫 stderr。以 `bash -p` 執行、清掉繼承的 `GIT_*`，`PATH` 只看以絕對路徑寫的項目；git 不用 `git log`、`git diff`（不執行 gpg 與外部 diff），每次呼叫都關掉 `core.fsmonitor` 與 replace ref；不印 commit subject。
- **`akashic-fetch-fulltext` SKILL 第 0 步**：錯誤訊息裡的建置指示改經戳記腳本，並以 `install -m 755` 放回原位（換新的 inode；原地 `cp` 覆寫已簽章的 binary，下次執行會被系統終止）。
- **`.claude/rules/swift-is-the-implementation-language.md`**：例外 1 由四個檔改成六個。`check-cli.sh` 含判斷，照「含判斷者移進 Swift」本該移植；它是具名例外，理由是它判斷的對象就是 `akashic` binary 本身（使用者 2026-11-09 裁決）。
- **`docs/rulings/mcp-cli-parity.md`**：CLI-only 表加「根層旗標 --version」一列——它不是 subcommand 也不是 `ParsableArguments`，機械稽核枚舉不到。

## 使用者的裁決（2026-11-09，#775 的 decision comment）

- 戳記照 safari-browser 用受追蹤佔位檔，不用連結期 section。
- 比對基準用 `origin/main`，沒有才用 HEAD。（診斷時本機主 checkout 的 main 落後 origin/main 308 個 commit。）
- 修改例外 1，收這兩支 shell。
- 契約數字由 hook 從 SKILL 抽出。

## 誠實邊界

- **過報**：只動 akashic-mcp、App、guards 的 commit 也算「落後」，訊息因此寫「動到 package 原始碼」。
- **建置期間佔位檔是被改著的**：同一個工作樹裡別的工作線在那幾分鐘內 commit，可能把戳記值掃進去；戳記值是 hash，被 commit 了看得出來。
- **`origin/main` 沒有 fetch 就是舊的**：訊息寫明基準是「上次 fetch 時」。
- **沒有原始碼 checkout 的使用者**只得到契約比對，得不到落後幾個 commit；CLI 的發布管道是 #633。
- `akashic-discovery` 的 `akashic-work-references` 同樣依賴 CLI 的 `references` 契約（要恰好 10），不在這一輪：#776。

## 驗證

- `CLIVersionTests`（1）、`StampVersionTests`（8）、`CheckCLIHookTests`（18）全綠。hook 的八個負對照（不用 origin/main、計數不限 package 原始碼、squash 後同內容不當最新、契約不比、逾時仍探契約、不看 `$HOME/bin`、檔案時間不比、dirty 不說）與戳記腳本的兩個（不排除 tag、拿掉 TERM 的 trap）都讓對應的測試轉紅。
- `CheckCLIHookTests.testRealSkillRequirementMatchesTheCLIConstant` 用真的 SKILL 與 CLI 自己的 `fulltext contract`，同時釘住「hook 抽得到 SKILL 的數字」與「那個數字等於 `FulltextFetch.contractVersion`」：升契約版本卻忘了改 SKILL 第 0 步，這支會紅。
- **第一版在實機跑出整排亂碼，而 18 支測試全綠。** UTF-8 locale 下 bash 會把緊接在變數名後面的全形標點當成名字的一部分：`$HAVE，` 被讀成變數 `HAVE，`，印出半個字元。測試給 hook 的環境沒有 `LANG`、跑在 C locale，所以沒抓到；Claude Code 跑 hook 的環境是 `LANG=C.UTF-8`。修法：hook 的程式碼行一律寫 `${名字}`；測試固定在 `LANG=C.UTF-8` 下跑，所有 hook 測試共用的斷言另加「輸出不得有 U+FFFD」（改 hook 之前，同一組 18 支在這個環境下出現 21 個失敗）。
- 實機（`~/bin/akashic` 只讀、這一輪沒有覆蓋它）：
  - 2026-11-09 晚，對當時的 `~/bin/akashic`（2026-10-28 建置）與本機原始碼實跑 hook，印出「fulltext 契約是 6，要求 ≥ 8」與「binary 2026-10-28，origin/main 最後一次動到 package 原始碼是 2026-11-09」並附重建指令——正是本 issue 描述的情境。
  - 2026-11-10 rebase 到 #613 b49 之後（b49 把契約升到 9），`~/bin/akashic` 已由另一條工作線以 b49 的程式碼重建（00:50，印 `fulltext-contract 9`，不認得 `--version`，因為不是從本 branch 建置的）。hook 只印一行 ✓：契約 9 ≥ 9；不認得 `--version` 改比檔案時間，binary（00:50）晚於 origin/main 最後一次動到 package 原始碼（23:40）。
  - 以本 branch 經戳記腳本建置的 CLI（裝在暫存目錄）：`--version` 印出與 HEAD 相同的 12 位 hash，建完工作樹乾淨、佔位檔已還原；hook 讀到版本，說明它「比 origin/main 新」並改比檔案時間。

## verify r1 之後的修正（2026-11-10）

PR #783 的第一輪 verify（四席審查、Devil's Advocate、Codex）判 FAIL：三個 blocking、十項要在本輪修。上面〈改了什麼〉已改成修正後的行為，這一節記修了什麼、為什麼。

**Blocking 1：比不出祖先關係時安靜地漏報。** 先前只要建置的 commit 不是基準的祖先，就改比檔案時間；binary 的時間比基準上最後一次修改新，就只印 ✓。兩個實例：從還沒 rebase 的分支建置而基準又前進；比 #775 舊的 CLI（`--version` 回 64）在 #775 合併之後重建自不含它的分支。

- 落後與否改看內容。~~祖先與非祖先走同一段程式：先數基準上「不在這次建置的歷史裡、又動到 package 原始碼」的 commit，是 0 就是最新；不是 0 再看從共同祖先到基準之間基準改過的檔，在這次建置裡是不是同一份內容。~~ 基準改了又改回來也不再算落後。（verify r2 更正：比淨差異會漏掉「squash 之後又被 revert」，判定改寫了，見下一節 B1。）
- `probe` 傳回 CLI 的結束碼：64 而基準已經有 `BuildVersion.swift` → 必定落後；逾時與其他失敗不印 ✓，各有自己的一行。逾時只由一個計時器判定（先前兩個計時器互搶，系統忙的時候逾時會被當成「舊 CLI」，還照樣探第二次）。

**Blocking 2：git 呼叫吃使用者的設定與繼承的環境。** `log.showSignature=true` 時簽章文字排在格式那一行前面，檔案時間讀不到數字、警告安靜消失，每個 session 還呼叫一次 gpg；`diff.trustExitCode` 加外部 diff 時 `git diff --quiet` 會執行它，回 0 就被當成「原始碼相同」；繼承的 `GIT_DIR` 讓根目錄檢查通過而比到別的 repo。

- 不再用 `git log` 與 `git diff`，只用 plumbing（`rev-parse`、`merge-base`、`rev-list`、`diff-tree`、`cat-file`）。~~那些設定 plumbing 讀不到，所以不是逐一關掉，是沒有地方生效。~~（verify r2 更正：這句不成立，`diff-tree` 會執行 `core.fsmonitor` 設定的程式，見下一節 B2。）
- 開頭清掉所有繼承的 `GIT_*`。`PATH` 只看絕對路徑的項目（`.` 與空項指的是專案目錄），使用者的 `PATH` 只用來找 `akashic` 與 `git`，其餘工具只從 `/usr/bin`、`/bin` 找。整支在 C locale 下跑。
- 不印 commit subject（那是別人寫的字，squash 時就是 PR 標題），只印 hash 與日期。

**Blocking 3：兩次重疊的戳記建置把戳記值留在受追蹤的佔位檔。** 第二次把第一次寫進去的值當成原檔備份，建完「還原」回去。

- 戳記腳本在佔位檔不是佔位值時拒絕執行（結束碼 3）；戳記寫不進去時中止（結束碼 4）。兩者都不執行被包的命令。被 SIGKILL 的建置留下戳記值時同樣被拒，訊息說怎麼處理。

**其餘**

- `hooks.json` 改用 exec form（`"args": []`）並加 `"timeout": 30`。官方 hooks 文件寫：hook 引用路徑佔位符時設 `args`，每個元素原樣當成一個參數、不經 shell。plugin 路徑有空白或引號都不必處理，比 shell form 加引號穩。command hook 的預設上限是 600 秒。
- 提示的第一行寫明「把狀況告訴使用者，要不要重建由使用者決定；不要自己執行下面的指令」。SessionStart 的 stdout 進的是 Claude 的 context，畫面上不一定看得到；這一輪沒有改用 JSON 的 `systemMessage`。
- 指令裡的路徑用單引號包（內含的單引號寫成 `'\''`）。不用 `printf %q`：bash 3.2 的 `%q` 在 UTF-8 locale 下會把中文路徑印成不完整的位元組（2026-11-10 實測）。`install` 前加 `mkdir -p`；CLI 就是原始碼目錄的 `.build/release/akashic` 時不印 `install`。
- 原始碼目錄存在但不是 repo 的根目錄 → 說出來，不對已存在的目錄印 `git clone`。README 的環境變數表加 `AKASHIC_SOURCE_DIR`。
- symlink 的 CLI 比它指向的檔的時間（`stat -L`）。
- 戳記腳本：package 路徑下的未追蹤檔算 `-dirty`（`git describe --dirty` 不看未追蹤檔，SwiftPM 卻會編譯它們）；白名單在 C locale 下直接比字串（先前經過 `$(…)`，值裡的換行被吃掉而過得了檢查）。兩支腳本各有一行 `COMPILED_PATHS=(…)`，由 `StampVersionTests` 比對是否逐字相同。

**新的誠實邊界**

- 內容以檔為單位比：分支的前半被 squash 合併之後又改了同一個檔，會被報成落後。
- 建置不是基準的祖先時，印出的 commit 數含 squash 的 commit，實際缺的可能較少；訊息會說。
- 被包的命令自己收不到 INT／QUIT：bash 讓背景命令忽略這兩個訊號，bash 3.2 在子 shell 裡 `trap - INT QUIT` 也還原不了（2026-11-10 實測）。Ctrl-C 由戳記腳本接住、改送 TERM 給命令，再還原佔位檔；`StampVersionTests.testTheWrappedCommandItselfIgnoresInterrupts` 釘住現況。
- ~~戳記腳本的「拒絕非佔位值」是先查再寫：兩次建置在同一瞬間啟動時都查得過。照程式讀，那時兩邊備份的都是佔位值，結束後檔案仍回到佔位值，代價是其中一個 binary 可能印 `unknown`；這個情形沒有實測。~~（verify r2 更正：這個推論是錯的。檢查與備份之間隔著幾次 git 查詢，另一次建置在這段時間寫入的話，備份到的是戳記，戳記會留在受追蹤的檔裡，見下一節 B3。）
- 檔案時間的比對用 BSD 的 `stat -f %m` 與 `date -r <秒>`（macOS）；其他平台沒有測過。

**驗證**

- `CLIVersionTests`（1）、`StampVersionTests`（20）、`CheckCLIHookTests`（36）全綠。動手修之前，當時的 54 支在舊實作上跑：26 支紅（hook 20、戳記腳本 6），其中兩支的訊息直接是「hook 執行了原始碼 repo 設定的外部 diff」「hook 呼叫了 gpg」。
- 14 個負對照，每個把一處修正改回去、跑對應的測試、再從快照還原：非祖先改回比檔案時間、只數 commit 不看內容、不把 64 當證據、`probe` 吞掉結束碼、不清 `GIT_*`、改回 `git log`、改回 `git diff --quiet`、`PATH` 不過濾、`stat` 不跟 symlink、逾時仍印 ✓、不檢查佔位值、寫入失敗照樣建置、未追蹤檔不算 dirty、白名單不設 C locale。全部讓對應的測試轉紅。
- 最後一個負對照第一次**沒有**轉紅，查出來是測試的問題：Foundation 的 `Process` 把參數與環境變數轉成分解形，測試放進環境變數的 `abé`（`61 62 c3 a9`）到了腳本手上是 `e` 加 U+0301（`61 62 65 cc 81`），在任何 locale 下都會被擋。改成傳八進位跳脫、由假 git 印出位元組之後，負對照轉紅。
- `claude plugin validate plugin` 通過，沒有關於 hooks 的警告。
- 實機（`~/bin/akashic` 只讀，沒有覆蓋它）：2026-11-10 對 00:50 建置的 `~/bin/akashic`（不認得 `--version`）與本機原始碼跑新的 hook，印一行 ✓、不到 1 秒、stderr 沒有輸出。`origin/main` 還沒有 `BuildVersion.swift`，所以走檔案時間，binary 較新。帶著指向別的 repo 的 `GIT_DIR`、以 `.` 開頭的 `PATH` 重跑，結果相同。

**沒有在這一輪處理**（r1 的 follow-up，各有 issue）：`akashic-work-references` SKILL 仍叫人裸 `swift build`（併入 #776）；只改 `plugin/**` 的 push 在 CI 不跑 `CheckCLIHookTests`（#784）；official-validate 守衛只對 marketplace 根跑（#785）；hook 的 `PATH` 與 Bash 工具的 `PATH` 可能不同（#786）。

## verify r2 之後的修正（2026-11-10）

第二輪 verify 審的是上一節的三個修正 commit，判 FAIL：三個 blocking 都落在上一輪新寫的程式與句子上，另有一個上一輪造成的迴歸。報告在 PR #783。上面〈改了什麼〉已改成修正後的行為。

**B1：PR 被 squash 合併之後又在 main 上被 revert，從 PR 分支建的 binary 被判成最新。** 上一輪比的是「共同祖先到基準」的淨差異；被撤回的檔淨差異是空的，而 binary 裝的是 main 已經撤掉的程式碼。只撤回其中一個檔時也一樣。

- 判定改成四步：這次建置與基準的 package 原始碼內容相同 → 最新；建置是基準的祖先 → 落後；基準是建置的祖先 → 最新；兩者分岔 → 基準上不在這次建置歷史裡的 commit，有沒有哪一個在那些內容不同的檔上與它的任何一個 parent 不同，有就落後。
- 最後一步怎麼問 git，試了三種。審查建議的 `diff-tree --stdin` 對讀不到的 commit 與無法辨識的輸入都回結束碼 0、輸出是空的，失敗會被讀成「沒有動過」。帶著 `建置..基準` 的範圍問 `rev-list -- <檔>`，git 只拿 merge 跟不在建置歷史裡的 parent 比：基準把建置的一個祖先 merge 進來、解衝突時把檔退回舊內容，那個 merge 就不算動過（實測漏報）。定案的做法是兩份清單取交集：`rev-list 建置..基準`（不在建置歷史裡的 commit）與 `rev-list --full-history 基準 -- <檔>`（基準整段歷史裡動過那些檔的 commit）。兩者都看結束碼，交集在記憶體裡算。
- 內容不同的檔名原樣當成 pathspec（`--literal-pathspecs`）；被 git 加了引號的檔名還原不回去、檔超過 200 個時參數也放不下，這兩種情形改用整個 package 路徑，只會多報。
- 在 27 種歷史形狀的小 repo 上對過答案：squash 後 revert、部分撤回、cherry-pick、真的 merge、`-s ours`、merge 解衝突退回舊內容（三種）、併入無關的歷史、改名、刪了又建回來、基準改了又改回去、檔名含空白／中文／引號／glob 字元。

**B2：`core.fsmonitor` 設定的程式會被執行。** `diff-tree` 會讀 index，讀 index 會執行它，寫在 repo 或全域設定都算；設成 `true` 時還會啟動常駐的 daemon。上一節那句「那些設定 plumbing 讀不到」因此不成立。

- 每一次 git 呼叫都帶 `-c core.fsmonitor=false`，另帶 `--no-replace-objects`（replace ref 會讓 hook 讀到被換過的歷史）與 `-c core.quotePath=false`（檔名裡的非 ASCII 字元原樣印）。`diff-tree` 加 `--ignore-submodules=none`：`submodule.<名字>.ignore=all` 會讓它不列 gitlink 的變更，submodule 是唯一的更新時被讀成「內容相同」（Codex 點名的 `diff.ignoreSubmodules` 實測對 `diff-tree` 沒有作用）。
- 檔頭改成逐項列出關掉了什麼，不再宣稱某一類設定都讀不到。

**B3：戳記腳本在檢查與備份之間隔著 `git describe` 與 `git status`。** 另一次建置在這段時間寫入戳記的話，這一次備份到的就是戳記，建完「還原」回去的也是戳記，兩邊都回 0。上一節「新的誠實邊界」對這個窗口的推論是錯的。

- 備份之後再查一次備份本身：放回去的就是那份備份，所以查的是它。
- 戳記過的檔多一行標記（`stamp-version:stamped`），佔位檔沒有。沒有 git、不在 repo 根目錄時寫進去的戳記值也是 `unknown`，只看值分不出它與佔位檔；被中斷的建置留下這種戳記時，之後每一次建置都會是 `-dirty`。

**上一輪造成的迴歸**：hook 把 `PATH` 收窄成系統目錄，被探測的 CLI 也繼承了。PATH 上的 `akashic` 是一支包裝腳本（用裸名呼叫使用者 PATH 上的另一個程式）時，被報成「執行失敗（結束碼 127）」並建議 `install`，照做會用 binary 蓋掉那支腳本。現在 CLI 用使用者的 PATH（只含絕對路徑的那一份）執行；組內的計時器因此改用 `/bin/sleep`，不從那份 PATH 找。

**其餘**

- shebang 改成 `#!/bin/bash -p`：不讀 `BASH_ENV`、不匯入環境裡的函式、不吃 `SHELLOPTS`（verify 實測：被換成函式的 `sleep` 會讓正常的 CLI 被報成卡住）。`hooks.json` 是 exec form，Claude Code 直接執行這個檔，shebang 的參數會生效；測試也改成直接執行它，不經 `/bin/bash <檔>`。
- `PATH` 的過濾移到第一個外部命令之前（沒有 `CLAUDE_PLUGIN_ROOT` 時，算它的預設值會呼叫 `dirname`）。
- 逾時改看組內計時器動手前留下的標記檔，不再用「結束碼 137 而且超過 3 秒」去猜。
- 路徑含控制字元時，指令裡不印路徑（刪掉控制字元再印，印出來的是另一條路徑）。
- CLI 是建置產物的 hardlink 時仍然印 `install`（重建寫出的是新檔，hardlink 留在舊的 inode）。
- 檔案時間這條路讀不到資料時說出來；原始碼 repo 還沒有 commit 時也說出來。
- 戳記腳本：describe 說乾淨之後，package 路徑下 `git status` 還有任何一列就算 `-dirty`（未追蹤檔，以及裡面有未追蹤或改過的檔的 submodule）；讀不出狀態也算。
- 訊息：基準的標籤改成「上次 fetch 的 origin/main」（先前的全形括號後面多一個空白）；契約那兩行改成陳述句；看不到共同歷史時提到 shallow clone；git 拒絕讀取（例如擁有者不同）時不再只說「不是 repo 的根目錄」。
- 文件：`.claude/rules/swift-is-the-implementation-language.md` 例外 1 對 hook 的描述、README 的 `AKASHIC_SOURCE_DIR`、plugin CHANGELOG 跟著改。`hooks.json` 的 exec form 需要 Claude Code 2.1.139 以上（上游 CHANGELOG 該版加入 `args`）；更舊的版本遇到這個欄位會怎樣沒有查證。

**新的誠實邊界**

- 分岔時會過報：基準上有 commit 動過某個檔（即使後來改回去），而分支自己也改了那個檔，就報落後。
- 「不連網」指的是 hook 自己不 fetch。原始碼目錄是 partial clone 而 git 早於 2.45 時，擋 lazy fetch 的環境變數沒有作用（#790）。PATH 上以絕對路徑寫的目錄裡的 `git`、`akashic` 仍會被執行，那是使用者自己的 PATH。
- 戳記腳本沒有鎖：兩次建置都在對方寫入之前備份到佔位檔時，檔案最後仍是佔位值，但後編譯的那個 binary 可能印 `unknown`；收到訊號時不等被包的命令結束就還原（#789）。它是使用者自己啟動的建置，`git describe`、`git status` 照使用者的 git 設定執行，不像 hook 那樣隔離。
- 原始碼目錄不存在時只比契約，不說沒有比新舊；原始碼目錄不在 main 上時，提示裡的 `git pull` 拉的是那個分支（#788）。
- 沒有處理的三件小事：被 `.gitignore` 忽略但 SwiftPM 仍會編譯的檔不算 `-dirty`；以 `-` 開頭的相對 `AKASHIC_SOURCE_DIR` 印進指令時會被當成選項；沒有 Command Line Tools 的機器上 `/usr/bin/git` 會跳系統對話框。

**驗證**

- `CLIVersionTests`（1）、`StampVersionTests`（26）、`CheckCLIHookTests`（55）全綠。先放測試、後換腳本：當時的新測試與改過斷言的測試裡，24 支（hook 17、戳記腳本 7）在上一輪的腳本上是紅的；檔名當成 pathspec 的兩支在舊腳本上是綠的（它們守的是這一輪才有的程式），由負對照驗。換上新腳本之後又改了一支的預期（squash 之後的計數）、加了一支（釘住已知的過報），這兩支沒有在舊腳本上跑過。
- 33 個負對照，每個把一處修正改回去、跑對應的測試、再從快照還原，全部讓指定的測試轉紅：分岔時改回帶範圍的問法、改回淨差異、不先比內容、不認「基準是建置的祖先」、計數拿掉 `--full-history`、檔名當成 glob、加了引號的檔名照樣當 pathspec、不關 fsmonitor、不關 replace ref、拿掉 `--ignore-submodules=none`、拿掉 `GIT_NO_LAZY_FETCH`、探測沿用收窄的 PATH、shebang 拿掉 `-p`、不看逾時標記、`dirname` 用過濾前的 PATH、不查 hardlink、控制字元照刪、兩處「沒有比對」不出聲；戳記腳本的不查備份、不查標記、兩處檢查都拿掉、只算未追蹤檔、不帶 `--ignore-submodules=none`、status 失敗當成乾淨；另重跑上一輪仍適用的 8 個。
- hook 的測試改成直接執行 hook（`hooks.json` 是 exec form），不經 `/bin/bash <檔>`：這樣 shebang 的 `-p` 才測得到。
- 這一輪新增的測試裡有三支是第一次實際驗到檔頭的宣稱：真的 partial clone（不帶 tree、不 checkout）加上會留記錄的 upload-pack，確認 hook 不讓 git 去抓缺的物件；`core.fsmonitor` 指向會留記錄的程式（repo 與全域設定都設）；`BASH_ENV` 與環境裡匯入的函式。
- 三個量出來、決定了做法的事實（2026-11-10，git 2.54／2.55）：`diff-tree --stdin` 對不存在的 commit 與無法辨識的輸入回結束碼 0；`diff-tree` 帶不帶路徑都會執行 `core.fsmonitor` 設定的程式，`rev-parse`、`rev-list`、`merge-base`、`cat-file` 不會；`rev-list --full-history 建置..基準 -- <檔>` 在「基準 merge 了建置的祖先並退回舊內容」的形狀數到 0。
- 實機（`~/bin/akashic` 只讀，沒有覆蓋它）：對 00:50 建置的 `~/bin/akashic` 與本機原始碼跑新的 hook，印一行 ✓、0.3 秒、stderr 沒有輸出；帶著 `GIT_DIR`、`BASH_ENV`、以 `.` 開頭的 `PATH` 重跑，輸出相同，`BASH_ENV` 沒有被讀。
- 27 種歷史形狀與 33 個負對照用的腳本是這一輪的暫存工具，沒有進 repo；其中有對應 Swift 測試的形狀是 squash 後 revert、部分撤回、兩種 merge 解衝突、基準改了又改回去（祖先與分岔各一）、檔名含 glob 字元與引號、只動 submodule。
