## Why

`docs/design-principles-and-philosophy.md` §2 的標題「世界的基本可記錄單位是**事態**，而不是欄位集合」逐字使用 Tractatus 的 **Sachverhalt**，但文件從未點名來源，也從未把「什麼算 entity」寫成可檢驗的判準。

結果是實測到的失誤：2026-08-02 討論「View 中研院」時，AI 從 §3 挑了「有身分、有名字、會變」三條就推論「所以 view 是 entity」，並據此開了 #54 主張 `entities/<uuid>.yaml` 加 `type: view`。使用者當場糾正「view 不是 entity 吧，他是 index 吧，你搞混了」。

那三條**太鬆**——index 的 schema 版本也有身分、也會變。文件缺的不是資訊，是**一條會擋下這個推論的規範**。

## What Changes

- `docs/design-principles-and-philosophy.md` §3 新增規範：**形式概念 MUST NOT 成為 entity**，並給出可操作的判準（能不能成為關係的端點）。
- 同檔新增一節，記錄 §2 / §4 / §7 的 Tractatus 出處（Sachverhalt、形式概念 vs 真正的概念、saying/showing），以及 view 在後期維根斯坦是 **Aspektsehen（看作）**。
- 新增 `docs/explainers/entity-vs-view.md`：把「為什麼 view 不是 entity」寫成 explainer（規格說 what、explainer 說 why，沿用 #52 建立的分工）。
- §7 加一行指路，指向新 explainer。

## Non-Goals

- **不實作 view 機制**。#54 追蹤那件事（判準放 `config.yaml`、外延進 index）；本 change 只補判準與文件。
- **不改任何 code**。純文件變更，`Sources/` 零影響。
- **不把 `libraries/` 併進 `entities/`**。那是 #35 的收尾，且 library 的定義是 §7 的 Adjudication 層（人工裁決的成員關係），與本 change 的形式概念邊界無關。
- **不引入形式化的 entity 判定演算法**。判準是給人讀的規範，不是 lint rule——把它做成自動檢查需要先有 schema，而 schema 本身就是被這條規範約束的對象。

## Capabilities

### New Capabilities

- `entity-boundary`: 定義什麼算 first-class entity、什麼不算，並禁止形式概念進入 canonical entity namespace。

### Modified Capabilities

(none)

## Impact

- Affected specs: `entity-boundary`（新增）
- Affected code:
  - New: `docs/explainers/entity-vs-view.md`
  - Modified: `docs/design-principles-and-philosophy.md`
  - Removed: (none)
