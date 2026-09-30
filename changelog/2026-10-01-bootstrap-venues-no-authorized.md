# 2026-10-01 `bootstrap-venues` 建檔不再寫 `authorized`（#563）

使用者 2026-10-01 裁決：「新建檔留空，既有 470 筆不動」。

## 改了什麼

`VenueBootstrap.makeVenues` 先前對每一筆新 venue 寫 `authorized: [names[0]]`——`names[0]` 是同一組寫法依字母序排的第一個（`Psychometrika`／`PSYCHOMETRIKA` 會取到 WoS 的全大寫形）。「這個名字是本刊的對外形」是判定，而門檻建檔是提名不是判定（`two-kinds-of-edits` 的 bootstrap 列）：一個不做判定的操作成了判定形狀欄位的寫入者，是 #471 對 `variant` 修掉的同一形狀。#554 補了判定面（`update-venue --authorize`），這個寫入者還在，每跑一次 `bootstrap-venues` 就多生一批機械值。

現在建檔時 `authorized` 留空，與 `add-venue` 的 #227（「建檔不機械偽造」）一致。三個 bootstrap 自此都不寫 authorized：`bootstrap-people` 本來就不寫（`PersonBootstrap.personsFor` 的註解，#227），`OrgBootstrap` 也不寫。

## 沒有改的

- **既有的 470 筆機械值不動**。它們留給 #600 的 authorize campaign 逐本判定；撤掉它們不在本次範圍。
- **顯示名不變**：`Venue.displayName` 在沒有 authorized、時間軸不帶時間宣稱時取 names 的第一段，而 bootstrap 建檔時的第一段就是先前寫進 authorized 的那個字串。`VenueBootstrapTests` 斷言兩者相同。
- **合併端的「提醒不擋」不變**（`resolve-divergence` 對被併 venue 的 authorized）：既有的機械值仍分不出是不是人確認過的。

## `doctor` 會不會多一行恆為真的診斷

不會。`doctor` 的 `no authorized name: N person / M organization`（`LoadResult.recordsWithoutAuthorizedName`）只數 person 與 organization，不數 venue；`Venue.validate()` 對空的 authorized 也不報任何東西（`add-venue` 建的 15 筆本來就是空的）。所以這一改不多出任何診斷，也沒有「修不掉的輸出」。

## 測試

| 測試 | 驗什麼 |
|---|---|
| `VenueBootstrapTests.testMakeVenuesKeepsAllWritingsAndLeavesAuthorizedEmpty`（改名自 `…AndSetsAuthorized`） | authorized 是空的；displayName 等於 names 的第一段 |
| `VenueNameInvariantTests.testBootstrapStoresCanonicalNames` | 同上，canonical 形的名字 |
| `BootstrapVenuesPendingCLITests.testApplyLeavesAuthorizedEmpty`（新） | 真 binary `bootstrap-venues --apply`，讀回 store：authorized 空、displayName 對；磁碟上的 YAML 沒有 `authorized:` 鍵 |

### 負對照

把 `makeVenues` 改回 `authorized: [c.names[0]]`、重編、跑上面三個 test class，再以反向編輯還原並以 `cmp` 對事先存下的副本確認逐位元組相同。

| mutant | 結果 |
|---|---|
| 改回 `authorized: [c.names[0]]` | 3 個測試紅（4 個斷言：兩個單元測試各 1、CLI 測試 2——store 的值與磁碟上的鍵） |
| 還原後 | 69 個測試全綠 |

## 規則與文件

- `two-kinds-of-edits`：bootstrap 列補 #563 的註；`resolve-divergence` 列的「唯一寫入者當時是 `VenueBootstrap`」補一句「#563 起不再寫」。
- `mcp-cli-parity`：CLI-only 表 `bootstrap-venues` 列記「#563 重新確認，裁決不變、契約有改」。
- `Venue.displayName`、`DivergenceResolve` 的 doc 與 `updateVenue` 的註解各補一句，說清楚 bootstrap 寫 authorized 是 #563 之前的事。
