## 1. A destructive command SHALL NOT act on a store the caller did not name

實作 `DestructiveTargetGate`（Implementation Contract 的第一節）。

- [x] 1.1 依 D1：採 (a)+(c)，否決 (b)——**用事故本身當判準**，新增
  `Sources/akashic/DestructiveTargetGate.swift`：
  `assertTargetNamed(command:explicitLibrary:yes:resolved:)`——`explicitLibrary != nil`
  或 `yes == true` 即通過，否則擲錯。錯誤訊息必須含命令名、**解析到的 store 絕對
  路徑**、「與你目前所在的目錄無關」這句話、以及兩條出路。
  **不查 CWD**、不改 `LibraryLocator` 的解析。
  **驗收**：`DestructiveTargetGateTests.testRefusalNamesTheResolvedStore` 斷言訊息含
  路徑與那句話。

- [x] 1.2 依 **D4：兩條出路，都要顯式**，`LibraryOptions` 新增 `--yes` 旗標，help
  文字明寫它的意思是「我已確認目標是 registry 解析到的那個」。
  **驗收**：`akashic migrate-person-identity --help` 列出 `--yes` 且文字含「已確認」。

- [x] 1.3 六個命令在**任何寫入之前**呼叫閘門，且**只在 `apply == true` 時**呼叫
  ——dry-run 不得被擋（它不寫東西，且正是使用者用來確認目標的手段）。
  **驗收**：`testDryRunIsNotGated` 斷言不帶 `--apply` 時零拒絕。

## 2. The set of destructive commands SHALL be enumerated, not inferred

- [x] 2.1 依 D3：破壞性是**封閉列舉**，不是判準，`destructiveCommands` 逐一點名六個
  命令（`migrate-person-identity`／`migrate-venues`／`bootstrap-people`／
  `bootstrap-organizations`／`resolve-people`／`resolve-organizations`），並在該處寫明
  為何不能用名字猜（`rename` 與 `resolve-divergence` 都不以 `migrate` 開頭卻同樣不可逆）。
  **驗收**：`testEnumerationIsClosed` 通過。

- [x] 2.2 機械稽核測試（雙向）：掃 `Sources/akashic/*.swift` 找所有帶 `var apply = false`
  的 struct、取其 `commandName`，斷言每個都在列舉內；反向斷言列舉的每個名字都對得到
  一個真實 subcommand。
  **驗收**：`testEveryApplyCommandIsEnumerated` 與 `testEveryEnumeratedNameExists` 通過。

## 3. 面不對稱的記錄

- [x] 3.1 依 **D2：面不對稱——只擋 CLI，不擋 MCP**，在閘門型別的 doc 內寫明理由
  （CLI 的 `--apply` 是篩選式批次掃蕩、MCP 的 apply 收逐 id 顯式清單），並引 parity 表
  對同一組命令已記錄的同型先例（tier 閘）。
  **驗收**：`grep -c "per-id\|逐 id" Sources/akashic/DestructiveTargetGate.swift` ≥ 1。

## 4. 收尾

- [x] 4.1 全套 `swift test` 通過。
- [x] 4.2 **行為探針**：在非 store 目錄執行 `migrate-person-identity --apply`（不帶
  `--library`），確認被拒絕且訊息說出真 store 路徑——重現事故的形狀並確認它現在擋得住。
- [x] 4.3 `spectra validate gate-destructive-store-target` 通過。
