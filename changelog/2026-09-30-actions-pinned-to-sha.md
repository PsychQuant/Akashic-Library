# 2026-09-30 GitHub Actions 釘到 commit SHA（#706）

`ci.yml` 與 `census-parity.yml` 以版本標籤引用 `actions/checkout@v4`、`actions/cache@v4`。標籤可以被移動；#690 讓 `census-parity.yml` 在所有 `Sources/**` 的 PR 上都跑，暴露面變大（#690 R1 verify security 席）。

## 改了什麼

- 兩個 workflow 的四個 `uses:` 改成 `owner/action@<SHA> # vX.Y.Z`。SHA 是 2026-09-30 以 `gh api repos/<owner>/<action>/commits/v4 --jq .sha` 解析，版本註解是指向同一個 commit 的版本標籤：
  - `actions/checkout` v4 → `11d5960a326750d5838078e36cf38b85af677262`（v4.4.0）
  - `actions/cache` v4 → `0057852bfaa89a56745cba8c7296529d2fc39830`（v4.3.0）
- 更新方法寫在 workflow 註解裡。使用者 2026-09-30 裁決：手動更新，不加 Dependabot。
- 新測試 `WorkflowActionPinningTests`：`.github/workflows/` 裡每一個 `uses:` 都要是 40 位 SHA 加行尾版本註解；掃不到任何 workflow 或任何 `uses:` 行時失敗，不當成通過。
- `TractatusInterfaceTests.testCICheckoutFetchesFullHistoryForStrictCorpusEvidence` 原本以 `actions/checkout@v4` 字面定位 checkout 那一步，改成只比對到 `@`。

負控：把 `ci.yml` 的 `actions/cache@<SHA> # v4.3.0` 改回 `actions/cache@v4` → `WorkflowActionPinningTests` 紅（指名 `ci.yml:72`）；以備份還原、`cmp` 一致。

## fork PR 核准設定

2026-09-30 讀 `repos/PsychQuant/Akashic-Library/actions/permissions/fork-pr-contributor-approval` 得 `first_time_contributors`（首次貢獻者的 fork PR 要核准才跑）。使用者裁決維持不改：`pull_request` 事件下 fork PR 的 workflow 只拿到唯讀 token、拿不到 secrets，兩個 workflow 也已設 `permissions: contents: read`、checkout 不留憑證。

## 誠實邊界

- 釘住的是 action 本身的 commit；action 在執行時自己下載的東西（例如 cache 的後端）不在這個範圍。
- 手動更新代表沒有任何機制提醒有新版本；測試只擋「退回標籤」，不擋「SHA 過舊」。
