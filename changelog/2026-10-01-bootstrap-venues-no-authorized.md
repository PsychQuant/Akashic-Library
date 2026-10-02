# 2026-10-01 `bootstrap-venues` 建檔不再寫 `authorized`（#563）

使用者 2026-10-01 裁決：「新建檔留空，既有 470 筆不動」。

## 改了什麼

`VenueBootstrap.makeVenues` 先前對每一筆新 venue 寫 `authorized: [names[0]]`——`names[0]` 是同一組寫法依字母序排的第一個（`Psychometrika`／`PSYCHOMETRIKA` 會取到 WoS 的全大寫形）。「這個名字是本刊的對外形」是判定，而門檻建檔是提名不是判定（`two-kinds-of-edits` 的 bootstrap 列）：一個不做判定的操作成了判定形狀欄位的寫入者，是 #471 對 `variant` 修掉的同一形狀。#554 補了判定面（`update-venue --authorize`），這個寫入者還在，每跑一次 `bootstrap-venues` 就多生一批機械值。

現在建檔時 `authorized` 留空，與 `add-venue` 的 #227（「建檔不機械偽造」）一致。三個 bootstrap 自此都不寫 authorized：`bootstrap-people` 本來就不寫（`PersonBootstrap.personsFor` 的註解，#227），`OrgBootstrap` 也不寫。

## 沒有改的

- **既有的 470 筆機械值不動**。#600 裁決不跑全量 campaign、按需判定（`akashic-verify-venue` 的對外形步驟，#566）；撤掉它們不在本次範圍。
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

## R1 verify 之後（2026-10-01，41 個 findings，本節是 #563 的部分）

- **「合併端的『提醒不擋』不變」沒有看倖存者為空的那一格（finding 31）。** 合併的降級提醒句 `demotionWarning` 對被併者的 authorized 一律附「倖存者同書寫系統的對外形不變」。#563 之後空的 authorized 是新建 venue 的常態：倖存者在那個書寫系統上沒有 authorized 時，那句話是空話（沒有對外形可言）。現在句尾看倖存者在**那個名字的書寫系統**上有沒有 authorized：有才說「不變」，沒有就說「倖存者沒有這個書寫系統的對外形」（倖存者只有漢字 authorized、被併者的 authorized 是拉丁名，同樣說沒有）。行為不變（仍是提醒不擋），只是不再說一句假話。`DivergenceResolve` 那段 doc 的 479/479 前提標為「只對 #563 之前建的 venue 成立」：之後新建的 venue 若有非空 authorized，必然是人用 `--authorize` 下的判定；store 仍分不出兩者，所以這一格維持提醒不擋、觸發條件不變。
- **docs/store-format.md §3.1「缺席合法，由 `doctor` 報告」對 venue 不成立（findings 8、15）。** `doctor` 只數 person 與 organization；#563 之後每個新建的 venue 都落在這個沒有掃描面的狀態。§3.1 改成照實寫，並點名按需判定（#600 裁決不跑全量 campaign）時要自己掃 YAML 才列得出還沒指定的 venue。首輪的 changelog 已經承認 doctor 不數 venue，文件沒跟上。
- **`bootstrap-venues` 的輸出沒告訴操作者（finding 15）。** 乾跑與 `--apply` 各多一句：新建的 venue 不指定對外形（authorized 留空）、指定走 `akashic update-venue <key> --authorize "<名字>"`、doctor 不會報空的 venue authorized。
- **仍寫「bootstrap 寫 authorized」的現在式文字（findings 8、22、29）。** `VenueAuthorizedWriteTests` 的 setUp 註解（「bootstrap 機械取第一個名字、addVenue 留空」）、`DivergenceResolveVenueTests` 的註解（「唯一的寫入者是 VenueBootstrap」）、`DivergenceResolve` 兩處「#564 另裁（要不要留）」——#564 已於 2026-10-01 裁決要留，改成過去式或寫明已裁決。
- **spec 分岔記錄，未改 spec（finding 29）。** `openspec/specs/authorized-name/spec.md` 寫「沒有指定 authorized 時解析 SHALL 回 stable key、SHALL NOT fall back to name order」，而 `Venue.displayName` 自 #475 起就在沒有 authorized 時取 names 的第一段。#563 讓這個 fallback 成為每個新建 venue 的預設路徑，分岔的母體變大；輸出不變（`VenueBootstrapTests` 斷言 displayName 等於 names 第一段）。規範文字的改動要走 Spectra，不是這一輪順手改；`VenueBootstrap.makeVenues` 的註解補了這一點。

### 負對照（R1 verify 之後）

每個 mutant 改一處、重編（含兩個 executable）、跑相關 test class，再以反向編輯還原並以 `cmp` 對事先存下的副本確認逐位元組相同。

| mutant | 結果 |
|---|---|
| P1 降級提醒句一律說「對外形不變」 | 2 failures，1 個測試紅（`testDemotionWarningSaysSoWhenTheSurvivorHasNoOutwardFormInThatScript`） |
| P2 判斷倖存者有沒有對外形時不看書寫系統（只看 authorized 非空） | 1 failure（同一個測試的漢字 authorized 那一半） |
| P3 `--apply` 的提示拿掉 | 1 failure（`testApplyLeavesAuthorizedEmpty`） |
