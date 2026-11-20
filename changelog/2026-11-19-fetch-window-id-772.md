# #772：`fetch` 鎖在開頭選定的視窗（`--window-id`），別的 profile 的視窗開著不再停（plugin 殼維持 0.13.17，契約版本 11 → 12）

使用者 2026-11-19 09:24：「我是覺得在別的是窗沒差，只要鎖定好固定視窗就好」；09:25：「也不一定要在個人，只要固定視窗就好了嗎」（#772 的兩則 Decision comment）。規格：Spectra change `idd-772-fetch-window-id`（新 capability `fulltext-window-lock`；`fulltext-division-of-labour` 批次中途的停止拿掉別的 profile、加上 safari-browser 太舊；`fulltext-gate-look` 契約 11 → 12）。

## 程式

- `Sources/AkashicSkillTools/FulltextFetch.swift`：
  - 開頭以 `--window N` 選定視窗、讀它的 id（`documents --json` 的頂層 `window_id`）；之後新分頁是 `open --new-tab --window-id <id>`，記號不在時的位置鎖是 `--window-id <id> --tab-in-window <T>`。不再送 `--window N` 給 safari-browser。記號鎖（`--profile P --url-endswith '#akashic-…'`）與「新分頁跑到別的視窗就停、不讀它」照舊。
  - 拿掉 `otherProfileWindowOpen` 與 `windowsAtStart`：開頭、接續、執行當中都不再因為別的 profile 的視窗（或讀不出 profile 的視窗）而停。
  - profile 只用來選視窗：`--expect-profile` 給了才在開頭比一次（讀不出 profile 也拒絕）；沒給時讀不出 profile 的視窗可以用（記號鎖要 profile，那時一律用位置鎖）。視窗沒有任何列才是 `Safari window N not found`。
  - `documents --json` 的列沒有頂層的 `window_id`（safari-browser v2.9.0 與 `--window-id` 同一個 commit 加的）就在開任何分頁之前停（結束碼 1，`safari-browser 2.9.0 or later is needed`）。檢查的是欄位，不是 `--version`：safari-browser 的開發建置印 `unknown`。
  - 認出自己的分頁時（開新分頁、接續；接續時等分頁通過檢查之後才印，被拒的分頁不印）stdout 印 `own-tab: window-id <W> tab <T> mark <記號>`（記號不在時沒有 ` mark …`）。這一行給 skill 之後的讀與按鎖同一個視窗與分頁；**沒有使用者裁決涵蓋它**，是實作時定的（#781 第 2 輪 verify 第 3 列要用）。
  - 契約版本 11 → 12。
- `Sources/akashic/FulltextCommands.swift`：`--expect-profile` 選填（給了不得是空的）；說明文字寫 `--window-id` 與 `own-tab:`。

## 文件

- SKILL：第 0 步要求 12；第 1 步要 safari-browser 2.9.0（`open --help` 有 `--window-id`）；第 2 步、第 3 步的命令與 `--expect-profile` 那一點；`fetch` 跑的時候那一段（別的視窗不影響、`--window-id`、沒有實測的部分、`own-tab:` 一行）；位置鎖那一句；safari-browser 的最低版本 2.7.0 → 2.9.0；結束碼 1 那一列（拿掉別的 profile，加上 safari-browser 太舊）；〈人機分工〉批次中途停下的六種（拿掉別的 profile 的視窗、其餘重新編號，加上 safari-browser 太舊）。
- `akashic-bootstrap/references/web-access.md` 第 11 行與 `.claude/rules/web-access-via-safari-browser.md`〈使用紀律〉與形狀 (b) 的段落跟著改。

## #735

#735 記的是「視窗順序變了，位置鎖讀到別的分頁」。`--window-id` 拿掉了其中**視窗**那一半：一眼與命令之間使用者把另一個視窗拉到前面，命令仍到開頭選定的視窗（`FulltextWindowLockTests.testAWindowRaisedBetweenALookAndACommandDoesNotChangeTheTarget`）。**同一個視窗裡**左邊開關分頁、`--tab-in-window T` 在一眼與命令之間指到別的分頁的那一半沒有變，SKILL 仍列為擋不住的情形。#735 要不要因此收窄或關閉，由維護者決定。

## 沒有做的

- 沒有在真的 Safari 上跑（#772 Strategy 第 7 項）：別的 profile 的視窗開著時 `open --new-tab --window-id` 的新分頁是否一定落在指定的視窗、每一道讀取是否都留在那個視窗，要使用者在場時量。
- #772 Expected 第 3 項（偽造列的限制）等含 safari-browser#355 的版本。
- 「沒有指定視窗時以 profile 找視窗」沒有做：09:25 那一則的這個寫法是記錄者提的，使用者沒有逐項確認；`--window N` 仍必填。
- plugin 殼沒有升版：0.13.17 還沒推上 main，照 `.githooks/plugin-shell-versions.txt` 的規則重算那一列的摘要。
