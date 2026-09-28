## Summary

歧異記錄（divergence record）加一個移除面：一筆問題本身不成立、或不再需要延後判定時，可以帶理由把那筆記錄刪掉，而不必手改 YAML（#586）。

## Motivation

歧異記錄有記錄面（record-divergence）、讀取面（divergences）與合併面（resolve-divergence），沒有移除面。一筆記錄在合併那一步撞牆（候選 shape 是 organization，合併管線擲 unsupportedShape——`zero-instance-guards` 第 24 列裁「暫不做」的那個）、或記錯了（問題不成立、候選寫錯），唯一的出路是手改 YAML，那是 `replace-endnote-and-zotero` 第 4 條要防的形狀。

既有 spec 的「Deleting a record without rewriting its references SHALL NOT be offered」指的是**被併的候選實體**：刪掉它們而不改寫參照會留下懸空的引用。歧異記錄本身沒有任何記錄指向它（`entity-backlink-completeness` 的第 9、10 條邊都是從它指出去），刪掉它不留下懸空引用。但 `resolve-divergence` 的程式註解把那句讀成「放棄一筆歧異只能手改」——這個歧義要在 spec 裡顯式消解，而不是讓實作自己推論。

使用者 2026-09-27 對移除面一族（#572／#586／#588）的裁決：理由只進報告與 git 歷史，移除前要求那筆記錄檔已 commit，不改 store format。

## Proposed Solution

在 `divergence-record` spec 加一條 Requirement：dismissing 一筆記錄 SHALL 只刪那筆記錄、SHALL NOT 碰任何候選實體與參照；理由必填、只進報告；刪除前 SHALL 確認那個檔在版本控制裡有副本（tracked、clean）；SHALL 提供乾跑。

實作兩面同契約：CLI `dismiss-divergence <id> --reason … [--dry-run]`，MCP `akashic_dismiss_divergence`（`id`、`reason`、`dry_run`）。`mcp-cli-parity` 加一列、`two-kinds-of-edits` 加一列（AI 編輯：「這個問題不成立」是判定）；`resolve-divergence` 的程式註解改寫，指向本面。

## Non-Goals

- 不提供「刪候選實體」或「只合併不刪」——那是既有 Requirement 禁止的操作，本 change 不動它。
- 不把理由寫進 store（使用者裁決）；不改 store format。
- organization 攣生的合併管線（`zero-instance-guards` 第 24 列）不在範圍——本面只提供「撞牆之後的出路」。

## Impact

- Affected specs: divergence-record（新增一條 Requirement）
- Affected code:
  - New: Sources/AkashicMCPKit/DivergenceDismissal.swift, Tests/AkashicMCPTests/DivergenceDismissalTests.swift
  - Modified: Sources/akashic/DivergenceCommands.swift, Sources/akashic/CLI.swift, Sources/akashic-mcp/Server.swift, Tests/AkashicMCPTests/StdioE2ETests.swift, .claude/rules/mcp-cli-parity.md, .claude/rules/two-kinds-of-edits.md, .claude/rules/zero-instance-guards.md
