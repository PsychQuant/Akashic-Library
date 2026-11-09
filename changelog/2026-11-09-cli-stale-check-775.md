# 2026-11-09 `akashic` CLI 過期時，開 session 就說出來（#775）

#768 合併之後，`akashic-fetch-fulltext` SKILL 第 0 步要求 `fulltext-contract 8`，而本機的 `akashic` CLI 是 10 月底建置的、只印 6，也不認得 `--version`（回 64）。這件事是有人主動去問才發現的：開 session 時沒有任何訊息，第一個訊號會是 SKILL 第 0 步拒絕執行，或者用舊 CLI 跑了。

safari-browser 的 plugin 已有一個 SessionStart hook 解決同一件事（`hooks/check-cli.sh`）。這一輪比照它，給 akashic-mcp plugin 加上同樣的檢查。

## 改了什麼

- **`akashic --version`**：印建置時的 commit。值住在受追蹤的佔位檔 `Sources/akashic/BuildVersion.swift`，平常是 `unknown`；`scripts/stamp-version.sh` 在建置期間把它改寫成 `git describe --always --dirty --abbrev=12 --exclude='*'`（裸的 `<hash>[-dirty]`），建完還原——命令成功、失敗、收到 INT／TERM／HUP／QUIT 都還原。排除所有 tag，是因為這個 repo 的 tag（`akashic-mcp-v*`、`idd-*-baseline`、`idd-*-verified`）都不描述 CLI 的建置；不排除時 main 會被描述成 `idd-700-verified-51-g<hash>`。
- **akashic-mcp plugin 的 SessionStart hook**（`plugin/hooks/check-cli.sh`、`hooks.json`）：
  - 找不到 CLI（PATH 上沒有，`$HOME/bin/akashic` 也不存在）→ 印建置指令；沒有原始碼時先印 clone 指令。只在 `$HOME/bin` 找到時多說一句「不在 PATH 上」。
  - **契約**：要求的數字從 plugin 內 `akashic-fetch-fulltext/SKILL.md` 第 0 步那一行抽出（只寫在那裡，不在 hook 裡另寫一份）；CLI 印的比它小、或 CLI 沒有 `fulltext contract` → 兩個數字都說出來；SKILL 抽不到 → 說「沒有比對」，不當成通過。這一項不需要原始碼 checkout。
  - **落後原始碼**：原始碼目錄是 `$AKASHIC_SOURCE_DIR`（預設 `$HOME/Developer/Akashic-Library`），基準是 `origin/main`（上次 fetch 時，不連網），沒有這個 ref 才用 HEAD。建置的 commit 在基準的歷史裡 → 數之後動到 package 原始碼（`Sources`、`Package.swift`、`Package.resolved`、`repos/biblatex-apa-swift`）的 commit；不在歷史裡但 package 原始碼相同（squash merge 的常態）→ 視為最新；其他情形說明原因、改比檔案時間。沒有戳記（`unknown`）與比這一輪舊的 CLI 直接比檔案時間。
  - 每個 session 都會跑：不連網（`GIT_NO_LAZY_FETCH=1`）、不自動安裝、不覆蓋現有 binary；`--version` 與 `fulltext contract` 各約 4 秒上限，`--version` 逾時就不再探契約；任何失敗都 exit 0、不寫 stderr。
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
