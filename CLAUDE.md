<!-- SPECTRA:START v1.0.2 -->

# Spectra Instructions

This project uses Spectra for Spec-Driven Development(SDD). Specs live in `openspec/specs/`, change proposals in `openspec/changes/`.

## Use `/spectra-*` skills when:

- A discussion needs structure before coding → `/spectra-discuss`
- User wants to plan, propose, or design a change → `/spectra-propose`
- Tasks are ready to implement → `/spectra-apply`
- There's an in-progress change to continue → `/spectra-ingest`
- User asks about specs or how something works → `/spectra-ask`
- Implementation is done → `/spectra-archive`
- Commit only files related to a specific change → `/spectra-commit`

## Workflow

discuss? → propose → apply ⇄ ingest → archive

- `discuss` is optional — skip if requirements are clear
- Requirements change mid-work? Plan mode → `ingest` → resume `apply`

## Parked Changes

Changes can be parked（暫存）— temporarily moved out of `openspec/changes/`. Parked changes won't appear in `spectra list` but can be found with `spectra list --parked`. To restore: `spectra unpark <name>`. The `/spectra-apply` and `/spectra-ingest` skills handle parked changes automatically.

<!-- SPECTRA:END -->

## Parked change 不進版本控制（#72）

> 上面那段由 Spectra 自動維護，這段是本 repo 的規則。

`spectra park` 把 change 移到 **`.git/spectra-app/changes/`**。`.git/` 底下的內容 git 從不追蹤（那是它自己的目錄），所以：

- 連 `.gitignore` 規則都不需要——它根本沒進入候選集合，`git check-ignore` 也不回報任何東西
- **parked change 的全部設計產出只存在於單一台機器上**
- `spectra list --parked` 與 `spectra status` 都正常回報（artifacts 全部 `done`），從工具的角度看不出任何異常

生命週期裡因此有一個裸露窗口：

```
propose ──→ park ──────────────→ apply ──→ archive
            └── 不在版控 ─────────┘        └─ 進版控 ─┘
```

**規則**：park 只用於「今天不做、而且丟了也無所謂」的東西。任何要保留的設計——尤其是對應著仍開啟 issue 的——**不要停在 parked 狀態**。要暫時挪開就 `spectra unpark <name>` 搬回 `openspec/changes/`（那裡是 tracked）再 commit；`openspec/changes/` 裡有未完成的 change 不是問題，那本來就是它的用途。

實際踩過：三個 change、18 檔、124 KB 的設計工作曾同時停在 parked（#72）。park 位置本身屬 Spectra.app 的行為，不在本 repo 可修範圍。

## Rules

`.claude/rules/` 下是本 repo 的規則，寫給會照著執行的人與模型看。

| 規則 | 一句話 |
|---|---|
| [lossless-intake.md](.claude/rules/lossless-intake.md) | 匯入不得有損——來源給了什麼就收什麼；不收的只有秘密與隱私邊界兩類，且丟棄必須報出來 |
| [mcp-cli-parity.md](.claude/rules/mcp-cli-parity.md) | 新增 MCP 工具時必須同時裁決 CLI 面——封閉裁決表 + 機械稽核，缺口不得安靜累積 |
