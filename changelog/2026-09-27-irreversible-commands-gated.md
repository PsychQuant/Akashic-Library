# 2026-09-27 不可逆的命令要指名目標 store（#653、#650）

`DestructiveTargetGate` 防的是寫錯 store：沒有 `--library`、也沒有 `--yes`，就不寫。#580 把 `resolve-venues` 的全部寫入腿、`authorize-names --apply` 放進表內之後，verify 列出表外還有一批會寫 store 的命令沒有閘，#653 追蹤；其中 `rename` 沒有閘而 `rename-person` 有，另開 #650。

## 裁決（使用者 2026-09-27）

**只閘不可逆的**：`resolve-divergence`、`rename`、`migrate`、`migrate-provenance`。

判準與 `disambiguate-before-irreversible-writes` 的適用二類相同：看逆操作與正操作是否同級。
- 這四個命令的後果是合併加刪檔、全庫參照改寫、格式遷移。寫到錯的 store 上，要回去得靠 git 或備份。
- 其餘會寫 store 而沒有閘的命令，都是可逆或冪等的寫入、匯入、格式化、`resolve-people` 的逐 id 腿。寫錯了可以再寫回來，加閘只多摩擦、換不到東西。

所以那些命令沒有閘，是一個裁決，不是遺漏。

## 改了什麼

- **`destructiveCommands` 加四個命令名。**
- **有乾跑的命令只在不帶 `--dry-run` 時閘。** `migrate`、`migrate-provenance`、`resolve-divergence` 預設就寫，`--dry-run` 只預覽。乾跑什麼都不寫，閘它只會擋住使用者檢查自己要做什麼。
- **拒絕訊息的出路要說對。**
  - `assertTargetNamed` 多一個 `dryRunFlag` 參數。先前的出路只有兩種說法：「不帶寫入旗標就是預覽」，以及「這個寫入沒有 dry-run」。預設就寫的命令兩種都不適用：它沒有寫入旗標可以不帶，但有乾跑旗標可以加。現在它的訊息是「加 --dry-run 可以先看到會改什麼」。
  - `rename` 沒有乾跑，訊息維持「這個寫入沒有 dry-run」，不叫人去跑一個不存在的旗標。
- `DestructiveTargetGate` 的 doc 與 `mcp-cli-parity` 的 `--yes` 列都改寫成裁決。兩處都刻意不逐一點名其餘命令，因為清單會過期，判準不會。#580 R1 寫過「不閘的只有一類」，當場就被找到六個反例。

## 測試

`ResolveVerdictCLITests.testIrreversibleCommandsRequireANamedTarget`，用真 binary 跑：
- 四個命令在未指名目標時都被拒；
- 出路逐一核對（三個說「加 --dry-run」，rename 說「沒有 dry-run」）；
- `migrate --dry-run` 與 `migrate-provenance --dry-run` 不被閘擋。

負控兩組：
1. 把兩個命令檔還原成 HEAD（拿掉四個閘呼叫）：9 紅。四個命令的「拒絕」與「出路」各 4 條，另一條是 `migrate-provenance` 在沒有 digest 時 rc=0。
2. 只把出路改回舊的二選一：恰好紅 3 條，就是三個有乾跑的命令；rename 那條照綠，符合預期。

## 誠實邊界

- 閘只作用在 CLI。MCP 面沒有這四個能力的寫入 tool（`resolve-divergence`、`rename` 與兩個遷移命令都屬 CLI-only 表的維運例外），所以兩面沒有新的不對稱。
- `rename` 在閘之後仍然沒有乾跑。要先看影響範圍，只能先在副本上跑一次。補乾跑是另一件事，本輪不做。
