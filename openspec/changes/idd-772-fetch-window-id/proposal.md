## Why

`akashic fulltext fetch` 以視窗的前後順序（`--window N`）開新分頁、在記號不在時以 `--window N --tab-in-window T` 鎖分頁。前後順序在使用者點了另一個視窗時就變，所以 #768 加了一道無條件的停止：有別的 profile 的視窗（或讀不出 profile 的視窗）開著，`fetch` 在開頭、接續與每一眼都停（`otherProfileWindowOpen`）。2026-11-19 一批取全文時這道停止讓九篇沒有開始，使用者說它很擾人（#772 的 2026-11-19 留言）。

safari-browser v2.9.0（2026-11-06）出了 `--window-id`：以視窗的穩定 id 指定視窗，視窗被拉到前面也不變，id 不存在就失敗、不退回前景視窗；`open --new-tab --window-id W` 在那個視窗開分頁、不把 Safari 拉到前面。使用者 2026-11-19 09:24、09:25 的兩則決定：「我是覺得在別的是窗沒差，只要鎖定好固定視窗就好」「也不一定要在個人，只要固定視窗就好了嗎」。

## What Changes

- `fetch` 開頭選定一個視窗（`--window N` 在那一刻的那個視窗），記下它的 id；新分頁以 `open --new-tab --window-id <id>` 開，記號不在時的位置鎖改成 `--window-id <id> --tab-in-window T`。記號鎖（`--profile P --url-endswith '#akashic-…'`）照舊；「新分頁跑到別的視窗就停、不讀它」照舊。
- 拿掉 `otherProfileWindowOpen`：開頭、接續與執行當中都不再因為別的 profile 的視窗而停。
- profile 只是選視窗的一種方式：`--expect-profile` 改成選填，給了才在開頭比對，之後每一步不比；讀不出 profile 的視窗在沒有給 `--expect-profile` 時也可以用（記號鎖要 profile，讀不出時一律用位置鎖）。
- safari-browser 的最低版本 2.7.0 → 2.9.0：`documents --json` 的列沒有頂層的 `window_id`（v2.9.0 與 `--window-id` 同一個 commit 加的）就在開任何分頁之前停。檢查的是能力，不是版本字串（safari-browser 的開發建置印 `unknown`）。
- `fetch` 在認出自己的分頁時印一行 `own-tab: window-id <W> tab <T>[ mark <記號>]`，讓 skill 之後的讀與按鎖同一個視窗、同一個分頁（#781 第 2 輪 verify 第 3 列要用；沒有使用者裁決涵蓋這一行，是實作時定的）。
- 契約版本 11 → 12（新的 stdout 一行、少了一種結束碼 1、`--expect-profile` 改成選填），SKILL 第 0 步一起調。
- SKILL、`akashic-bootstrap/references/web-access.md`、`.claude/rules/web-access-via-safari-browser.md` 形狀 (b) 的鎖分頁段落改寫；SKILL〈人機分工〉批次中途停下的封閉清單從六種變五種。

## Non-Goals

- 不在真的 Safari 上跑（#772 Diagnosis Strategy 第 7 項：別的 profile 的視窗開著時 `open --new-tab --window-id` 是否落在指定的視窗，要使用者在場時量）。
- 不處理 #772 Expected 第 3 項（偽造列的限制，等含 safari-browser#355 的版本）。
- 不加「沒有指定視窗時以 profile 找視窗」：09:25 那一則的這個寫法是記錄者提的，使用者沒有逐項確認；`--window N` 仍是必填的選法。
- 不改 #781 的點擊程序（那是 `idd-781-fix2`）。

## Capabilities

### New Capabilities

- `fulltext-window-lock`: `fetch` 把每一個以位置認分頁的動作鎖在開頭選定的視窗（`--window-id`）、不因別的 profile 的視窗而停、profile 只用來選視窗、safari-browser 太舊時在開分頁之前停、印出自己的視窗 id 與記號

### Modified Capabilities

- `fulltext-division-of-labour`: 批次中途停下的封閉清單少了「別的 profile 的視窗開著」，從六種變五種

## Impact

- Affected specs: fulltext-window-lock（新）、fulltext-division-of-labour
- Affected code:
  - Modified: Sources/AkashicSkillTools/FulltextFetch.swift, Sources/akashic/FulltextCommands.swift, plugin/skills/akashic-fetch-fulltext/SKILL.md, plugin/skills/akashic-bootstrap/references/web-access.md, .claude/rules/web-access-via-safari-browser.md, Tests/AkashicKitTests/FulltextFetchPathTests.swift, Tests/AkashicKitTests/FulltextMarkLockTests.swift, Tests/AkashicKitTests/FulltextOwnTabTests.swift, Tests/AkashicKitTests/FulltextB37Tests.swift, Tests/AkashicKitTests/FulltextB39Tests.swift, Tests/AkashicKitTests/FulltextB41Tests.swift, Tests/AkashicCLITests/SkillToolsCLITests.swift, Tests/AkashicCLITests/FulltextAttemptCLITests.swift, Tests/AkashicCLITests/FulltextClickProcedureTests.swift, plugin/CHANGELOG.md, .githooks/plugin-shell-versions.txt
  - New: Tests/AkashicKitTests/FulltextWindowLockTests.swift, changelog/2026-11-19-fetch-window-id-772.md
