## Problem

#802 第 1 輪在 `fulltext-gate-look` 的 `An unreadable same-site tab with a human-check marker at a login path SHALL pause the run` 插進一句：「The marker found is the one the service-marker check returns, and that check prefers a marker that pauses the whole run……」。緊接的下一句原本寫「When the marker is found and the path does not have the look of a login page …… waiting for human verification (exit 8) ……」。插入之前，「the marker」只能指第一句的 `cloudflare-challenge` 或 `perimeterx-press-and-hold`；插入之後，它可以讀成指剛定義的「回傳的那個標記」，而那個標記可能是整批暫停的標記，句子卻接著說 exit 8，與前一句的 exit 6 衝突。#802 verify 第 2 輪（Codex 那一席）找到，第 1 輪漏掉。

## Root Cause

插入的句子定義了一個比原本更寬的「the marker」，下一句的指涉沒有跟著收窄。程式沒有錯：`judgeUnreadable` 只在 `hit.response == .humanVerification` 時走等人驗證，整批暫停的標記走 `stop(for:)` 得 6。

## Proposed Solution

下一句改成明寫標記：「When the service-marker check returns `cloudflare-challenge` or `perimeterx-press-and-hold` and the path does not have the look of a login page ……」。其餘文字、Scenario 與 Example 原樣保留。

## Non-Goals

- 不改程式、測試、SKILL、plugin 殼；契約版本不變（main 上是 13）。
- 不新增 Scenario、Example 或 SHALL：這一句描述既有行為，改的只是指涉。
- 不改 `openspec/changes/archive/` 底下的封存檔（封存是歷史）。

## Success Criteria

- 主規格那條 requirement 裡「When the marker is found and the path does not have the look of a login page」不再出現，改成明寫兩個標記的那一句。
- 這條 requirement 的四個 Example 標題與內容不變，`spec-change.py links` 回 ok。

## Impact

- Affected specs: fulltext-gate-look
- Affected code:
  - Modified: openspec/specs/fulltext-gate-look/spec.md（經 archive 併回）, changelog/2026-11-16-fulltext-gate-look-wording-802.md
  - New: (none)
  - Removed: (none)
