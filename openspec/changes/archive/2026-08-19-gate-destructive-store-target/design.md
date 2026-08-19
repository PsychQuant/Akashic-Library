## Context

`LibraryOptions`（`Sources/akashic/CLI.swift`）省略 `--library` 時走
`LibraryLocator.resolveDetailed()`，其輸入面只有 `{explicit, environment, configURL}`
——**CWD 在結構上無法影響解析**（`currentDirectoryPath` 全檔零出現）。

六個帶 `--apply` 的 subcommand 實測：

| 命令 | MCP 面 |
|---|---|
| `migrate-person-identity` | 無（CLI-only）|
| `migrate-venues` | 無 |
| `bootstrap-people` | 無 |
| `bootstrap-organizations` | 無 |
| `resolve-people` | **有** |
| `resolve-organizations` | **有** |

## Goals

- 破壞性寫入不會打到呼叫者沒指名的 store
- 拒絕訊息**說出實際目標**——事故的核心是「以為在 scratch，其實在真 store」

## Non-Goals

**In scope**：閘門型別、封閉列舉、六個命令接上、機械稽核。

**Out of scope**：CWD 感知層（見 D1）、`LibraryLocator` 的解析語意（#105 不動）、
MCP 面（見 D2）、非破壞性命令（讀錯 store 的代價是錯答案，不是壞資料）。

## Decisions

### D1：採 (a)+(c)，否決 (b)——**用事故本身當判準**

`## Expected` 的三個方向架構上互斥。判準不是「哪個比較好」而是**哪個防得住已經發生
過的那次**：

| 方向 | 對該事故 |
|---|---|
| (a) 無顯式目標即拒絕 | **防得住** |
| (b) CWD 感知層 | **防不住**——事故發生在 scratch 目錄，而它**不在任何已註冊 store 內**；CWD 感知找不到 store 只能退回 registry，行為與現況相同 |
| (c) 回顯 + `--yes` | **防不住**——issue 的 `## Actual` 記錄即時緩解就是回顯，而回顯**不是同意閘** |

(b) 另外要推翻 #105 的既有裁決，代價更高而收益為零。

(c) 不單獨採用，但它的內容（回顯目標）**併入 (a) 的拒絕訊息**——那正是事故最缺的東西。

### D2：面不對稱——只擋 CLI，不擋 MCP

`resolve-people`／`resolve-organizations` 有 MCP 面，而 #310 的裁決記載：

> MCP 面的 active store 是 session 狀態……任何以「本次呼叫有沒有顯式指定 store」為
> 判準的機制，在 MCP 面**恆為否**。

但那個約束**只在閘門要作用於 MCP 時才綁**。本閘門不作用於 MCP，理由不是規避而是
**兩面的動作形狀不同**：

- CLI 的 `--apply` 是**篩選式批次掃蕩**（`--holder` / `--org` 收窄，其餘全掃）
- MCP 的 apply 收**逐 id 顯式指名**的清單

parity 表對同一組命令**已有同型的先例**：「tier 閘只在 CLI 篩選式批次（MCP per-id
顯式＋tier 可見，刻意不閘）」。所以這不是臨時挖的洞，是已裁決過的形狀再次適用。

### D3：破壞性是**封閉列舉**，不是判準

型別層零 destructive marker——38 個 subcommand 完全等價。任何「用名字猜」的規則都會
在邊界上出錯：`rename` 與 `resolve-divergence` 都不以 `migrate` 開頭，卻同樣不可逆。

所以逐一點名，並加**機械稽核**：帶 `--apply` 的命令若不在列舉內即失敗。稽核比告誡
可靠——本 repo 的封閉列舉錯過三次的教訓（見 `entity-backlink-completeness`）。

### D4：兩條出路，都要顯式

拒絕不是終點。訊息給：

- `--library <path>` —— **推薦**，因為它同時消除了歧義
- `--yes` —— 知情地沿用 registry 解析

`--yes` 存在的理由：常用工作流不該被迫每次打完整路徑。它的安全性來自**拒絕訊息已經
先說出目標**——使用者是在看過目標之後才加上它的。

## Risks

- **`--yes` 被反射性加上** —— 真實風險。緩解：`--yes` 的 help 文字明寫它的意思是
  「我已確認目標是 registry 解析到的那個」，且執行時仍回顯目標。
- **列舉漏掉未來的命令** —— 由 D3 的機械稽核接住。

## Implementation Contract

### `DestructiveTargetGate`

- `static let destructiveCommands: Set<String>` —— 封閉列舉，六個命令名
- `static func assertTargetNamed(command:explicitLibrary:yes:resolved:) throws`
  - `explicitLibrary != nil` 或 `yes == true` → 通過
  - 否則擲錯，訊息含：命令名、**解析到的 store 絕對路徑**、「與你目前所在的目錄無關」
    這句話、兩條出路
- **不查 CWD**、不改解析——它只判斷「呼叫者有沒有指名」

### `LibraryOptions`

- 新增 `--yes` 旗標（help 文字見 Risks）

### 六個命令

- 在**任何寫入之前**呼叫 `assertTargetNamed`，且**只在 `apply == true` 時**呼叫
  ——dry-run 不該被擋（它不寫東西，而且正是使用者用來確認目標的手段）

### 機械稽核測試

- 掃 `Sources/akashic/*.swift` 找所有 `var apply = false` 的 struct，取其
  `commandName`，斷言每個都在 `destructiveCommands` 內
- 反向：`destructiveCommands` 的每個名字都要對得到一個真實 subcommand
