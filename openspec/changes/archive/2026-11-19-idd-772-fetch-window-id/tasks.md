## 1. 測試先寫（在 e731cc2a 上看它們失敗）

- [x] 1.1 測試用的 `documents --json` 每一份假答案都加上頂層的 `window_id`（safari-browser v2.9.0 的形狀）；舊程式不讀它，所以這一步不讓任何測試變紅
- [x] 1.2 假瀏覽器認得 `--window-id`（`FakeBrowser.target`、`openTargetFlags`），與真的 safari-browser 一樣以 id 解析視窗
- [x] 1.3 （Requirement: The fetch command SHALL lock every position-based action to the window chosen at the start）新分頁、位置鎖的引數向量改成 `--window-id 9005`；新增「視窗在一眼與命令之間被拉到前面」的測試
- [x] 1.4 （Requirement: The fetch command SHALL NOT stop because a window of another profile is open）別的 profile 的視窗那幾支測試改成「不停」，仍斷言不印那個 profile 與它的網址
- [x] 1.5 （Requirement: The profile SHALL only choose the window）`--expect-profile` 可省略；讀不出 profile 的視窗在沒給時可用；給了而不符照舊拒絕
- [x] 1.6 （Requirement: The fetch command SHALL refuse a safari-browser without window ids before opening anything）列沒有頂層 `window_id` 就在開分頁之前停
- [x] 1.7 （Requirement: The fetch command SHALL print the window id and the mark of its tab）`own-tab:` 一行
- [x] 1.8 （Requirement: The skill SHALL require the window-id contract；MODIFIED: mid-run stops）SKILL 的字串測試
- [x] 1.9 驗證：帶標記的新測試在 e731cc2a 的程式與 SKILL 上都失敗，commit

## 2. 程式 [after: 1.9]

- [x] 2.1 `FulltextFetch.swift`：位置鎖與新分頁改用 `--window-id`；拿掉 `otherProfileWindowOpen` 與 `windowsAtStart`；profile 只在開頭比；讀不出 profile 的視窗可用；檢查頂層 `window_id`；`own-tab:` 一行；契約 12；檔頭與註解
- [x] 2.2 `FulltextCommands.swift`：`--expect-profile` 選填（給了不得是空的）；說明文字

## 3. 文件 [after: 2.2]

- [x] 3.1 SKILL：第 0 步要求 12；safari-browser 2.9.0；第 3 步鎖分頁的段落；〈人機分工〉批次中途停下拿掉別的 profile、加上 safari-browser 太舊；結束碼 1 那一列；#735 的處置
- [x] 3.2 `akashic-bootstrap/references/web-access.md` 與 `.claude/rules/web-access-via-safari-browser.md` 形狀 (b) 的段落
- [x] 3.3 `plugin/CHANGELOG.md`、`changelog/2026-11-19-fetch-window-id-772.md`、`.githooks/plugin-shell-versions.txt` 0.13.17 那一列的摘要

## 4. 驗證 [after: 3.3]

- [x] 4.1 `swift build -Xswiftc -warnings-as-errors`、全套 `swift test`、`bash .githooks/run-guards.sh`、`spectra validate idd-772-fetch-window-id` 都通過
