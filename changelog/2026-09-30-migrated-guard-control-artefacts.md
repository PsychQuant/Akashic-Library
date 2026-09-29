# 2026-09-30 migrated-guard-control 改看負控的實體；official-validate 補上負控（#689）

`akashic-guards migrated-guard-control` 要回答「每支在 `run-guards.sh` 裡跑的守衛，有沒有負控在驗它」。它先前把 `Sources/akashic-guards/` 底下**每個檔**都當成 harness 掃，只要守衛名以 `"<名>"` 的字面出現就算有負控。`main.swift` 的分派表寫的正是 `case "<名>":`，所以這個條件對每支已註冊的守衛都成立。#664 實作時在副本裡刪掉 `NetworkConfinementMutations.swift`，它仍報「無缺口」。

## 改了什麼

**判準改看負控的實體。** 一支子命令算是負控 harness，要同時滿足：

1. source 檔 `Sources/akashic-guards/<PascalCase>.swift` 存在；
2. `main.swift` 有 `case "<名>":` 分派它；
3. 它自己在 `run-guards.sh` 裡跑；
4. source 裡建一個 `Process`（`= Process()`）且指向 `.build/debug/akashic-guards`——它執行別的守衛。

守衛算有負控，是某支這樣的 harness 在自己的 source 或 `<PascalCase>Data.swift` 裡提到它（`"<名>"` 字面或 `akashic-guards <名>`；帶生成標記的資料檔只認 `guardRel:`，同先前）。輸出多一段逐守衛的對應表（`` `守衛` ← harness ``），讓漏掉的那條看得見。

第 4 條先前只要求出現 `Process()` 與 `akashic-guards` 兩個字串，本檔自己的程式碼就滿足它、`measured-claims-audit`（它的 `akashic-guards` 只在目錄路徑裡）也滿足，兩者都被當成 harness。改成上面的形狀後，會跑的 harness 是 7 支：`audit-guards-mutations`、`decision-matrix-mutations`、`network-confinement-mutations`、`oracle-precondition-control`、`plugin-roots-mutations`、`rule-prose-guards-mutations`、`trigger-coverage-mutations`。

**「實際在跑」也認命令替換。** `plugin_roots=$(.build/debug/akashic-guards plugin-roots)` 先前不在名單裡；現在在，涵蓋它的是 `plugin-roots-mutations`。

**一併移除**：Python harness 的兩條 glob 與 `MIGRATED` 表。#433 Step 5 之後樹裡沒有 Python harness，而第 3 條要求負控以 `akashic-guards <名>` 在 `run-guards.sh` 裡跑，Python 檔不可能滿足。

## 修好之後它指出的第一個缺口：official-validate

`official-validate`（#625）從寫成那天就沒有負控，先前被 `main.swift` 的分派算成「有」。新增 `akashic-guards official-validate-mutations`（`OfficialValidateMutations.swift`、`main.swift` 分派、`run-guards.sh` 一行）：每一格在暫存目錄放一支假的 `claude`，把一份預先寫好的 `--json` 報告印出來，放在 PATH 最前面。8 格：

| 格 | 預期 |
|---|---|
| 報告只有允許的那一條 warning | 綠 |
| 多一條不在允許清單的 warning | 紅，指名那一條 |
| 同一個欄位出現在別的 plugin | 紅（允許清單以 plugin 名稱定位） |
| 允許的那一條不再出現 | 紅（允許清單過期） |
| 報告有一條 error | 紅 |
| CLI 輸出不是 JSON | 紅 |
| marketplace 沒有 akashic-mcp | 紅 |
| PATH 上沒有 claude | 綠，且印出「已略過」 |

不依賴這台機器有沒有裝 claude CLI，所以 CI runner 上每一格也都跑得到。代價：真的 CLI 改了 `--json` 格式，這支不會知道，那一種由守衛自己的「輸出不是 JSON」路徑與本機 pre-push 擋。

## 負對照

- `AuditGuardsMutationsData.swift` 為 `migrated-guard-control` 加 4 格：刪掉 `NetworkConfinementMutations.swift`、拿掉 `main.swift` 對它的分派、從 `run-guards.sh` 拿掉它那一行、在命令替換裡跑一支沒有負控的假守衛。先加格子、用舊判準跑：前三格 rc=0（新格紅）；改判準之後 61/61。
- 在暫存目錄以 `swiftc` 各編一支拿掉一件判準的守衛（不要求分派、不認命令替換、harness 不限於 `run-guards.sh` 裡跑的），每一支只讓它對應的那一格回到 rc=0，其餘三格仍是 rc=1。
- `official-validate-mutations` 同樣以 `swiftc` 編三支弄壞的 `official-validate`（不檢查允許清單過期、所有 warning 都放行、忽略 error），harness 各自在對應的格紅。
- 受保護清單多 `OfficialValidateMutations.swift`，棘輪以 `protected-ratchet --accept` 更新（60 條）。
