# 2026-09-30 migrated-guard-control 改看負控的實體；official-validate 補上負控（#689）

`akashic-guards migrated-guard-control` 要回答「每支在 `run-guards.sh` 裡跑的守衛，有沒有負控在驗它」。它先前把 `Sources/akashic-guards/` 底下**每個檔**都當成 harness 掃，只要守衛名以 `"<名>"` 的字面出現就算有負控。`main.swift` 的分派表寫的正是 `case "<名>":`，所以這個條件對每支已註冊的守衛都成立。#664 實作時在副本裡刪掉 `NetworkConfinementMutations.swift`，它仍報「無缺口」。

## 改了什麼

**判準改看負控的實體。** 一支子命令算是負控 harness，要同時滿足：

1. source 檔 `Sources/akashic-guards/<PascalCase>.swift` 存在；
2. `main.swift` 有 `case "<名>":` 分派它；
3. 它自己在 `run-guards.sh` 裡跑；
4. source 裡建一個 `Process`（`= Process()`）且指向 `.build/debug/akashic-guards`——它執行別的守衛。

守衛算有負控，是某支這樣的 harness 在自己的 source 或 `<PascalCase>Data.swift` 裡提到它（`"<名>"` 字面或 `akashic-guards <名>`；帶生成標記的資料檔只認 `guardRel:`，同先前）。輸出多一段逐守衛的對應表（`` `守衛` ← harness ``），讓漏掉的那條看得見。

第 4 條先前只要求出現 `Process()` 與 `akashic-guards` 兩個字串，本檔自己的程式碼就滿足它、`measured-claims-audit`（它的 `akashic-guards` 只在目錄路徑裡）也滿足，兩者都被當成 harness。改成上面的形狀後，會跑的 harness 是 8 支：`audit-guards-mutations`、`decision-matrix-mutations`、`network-confinement-mutations`、`official-validate-mutations`、`oracle-precondition-control`、`plugin-roots-mutations`、`rule-prose-guards-mutations`、`trigger-coverage-mutations`。（這一句先前寫 7 支、少了同一輪下面才新增的 `official-validate-mutations`，R1 verify 指出後更正。）

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

## R1 verify 修正（2026-09-30）

六席（requirements、logic、security、regression、devil's advocate、Codex）。與本 issue 有關的有四個 MEDIUM、七個 LOW。

### 判準改成「宣告＋受測對象」

上面寫的判準是「某支 harness 的 source 或資料檔**提到**守衛名」。R1 verify 在副本裡重現兩個假綠：

- 刪掉 `TriggerCoverageMutations.swift`、`TriggerCoverageMutationsData.swift`、`main.swift` 的分派與 `run-guards.sh` 那一行，仍印「無缺口」。`plugin-roots-mutations` 為了驗 plugin 根而跑 `trigger-coverage`，被算成它的負控。`plugin-roots` 同樣被 `rule-prose-guards-mutations`（只為了取根目錄清單而跑它）抵免。#689 的 Expected 是「刪掉某支守衛的 mutations 檔時，本守衛要失敗」，這對有第二個順帶提及者的守衛不成立。
- `TriggerCoverageMutationsData.swift` 的檔頭是「本檔曾由腳本生成」，對不上「本檔由腳本生成」的標記，整檔走一般分支，於是它注入 runner 的 `.build/debug/akashic-guards plugin-store-format-parity` 被讀成 `trigger-coverage-mutations` 驗了那支守衛。把 `AuditGuardsMutationsData.swift` 裡那支守衛的六格改名後仍印「無缺口」。

現在守衛有負控，要某支 harness **宣告**它、而且它的 source 文字裡有**執行它的寫法**（受測對象）。這是文字層的判定，認的是寫法、不是 harness 執行時真的跑了什麼（R2 verify 更正：這一句先前寫「以它為受測對象」，讀起來像驗了執行；見文末〈R2 verify 修正〉的誠實邊界）：

- **宣告**：命名慣例 `<g>-mutations` 宣告 `<g>`；另外在 harness 的 source 寫一行從行首開始的 `// negative-control-for: <g>, <g>`。`audit-guards-mutations`（十支）、`decision-matrix-mutations`（`decision-matrix-drift`）、`oracle-precondition-control`（`audit-guards-mutations`）、`plugin-roots-mutations`（`marketplace-consistency`）各加了這一行。宣告的名字不在 `run-guards.sh` 裡跑是缺口。
- **受測對象**：harness 自己 source 裡的 argv 陣列字面（第一個元素是守衛名，或 `[BIN, "<g>", …]`），以及資料檔的 `guardRel:`、`guardArgv:` 欄位。資料檔的注入內容（`a:`／`b:`／`old:`／`new:`／`expect:`）不算。「本檔由腳本生成」的標記不再用。
- 宣告了卻沒有以它為受測對象，宣告是空的，也是缺口。

`plugin-roots-mutations` 另外跑 `trigger-coverage`、`protected-ratchet`、`rule-coverage`，驗的是 plugin 根看不看得見，不宣告這三支；它們各有自己的 harness。改完之後的對應表，每支守衛只剩宣告它的那一支 harness（例如 `trigger-coverage ← trigger-coverage-mutations`、`plugin-store-format-parity ← audit-guards-mutations`）。

### `run-guards.sh` 裡認不出的寫法要出聲

「實際在跑」的抽取只認行首與 `$(`。`if ! …; then`、`a && …`、`timeout 60 …` 照樣會執行，卻不在名單裡、也就不被要求負控（logic、security 兩席實測）。現在剝註解後每一處 `.build/debug/akashic-guards <子命令>` 都要被抽取認得，認不得的逐處列出、rc=1。方向是誤報，看得見。

### official-validate-mutations

- 「PATH 上沒有 claude」那一格原本把 PATH 設成 `/usr/bin:/bin`，在那兩處裝了 claude 的機器上會被判無效、整支 harness rc=1（Codex、regression 兩席）。現在每一格的 PATH 只有這一格自己造的 bin 目錄；假 `claude` 用的 `/bin/sh`、`/bin/cat`、`/bin/pwd` 都寫絕對路徑。
- 假 `claude` 先前不看引數，把守衛的引數改成 `["plugin","validate","/nonexistent"]` 仍 8/8。現在它只在收到 `plugin validate --json <repo 根>` 時才印報告，否則 exit 2、印一句不是 JSON 的話。
- 報告的 `contents[]` 先前每一格都是空的，守衛只讀 manifest 也全綠。加一格「`contents[]` 裡有一條 error」。
- 腳本不再把路徑內插進單引號，改以 `${0%/*}` 找旁邊的報告。
- 結尾「2 格須綠」改成由格子現算。

### 負對照

- `AuditGuardsMutationsData.swift` 為 `migrated-guard-control` 加 7 格：刪掉 `trigger-coverage` 專屬的負控（四處）、刪掉 `plugin-roots` 專屬的負控（三處）、讓 `trigger-coverage-mutations` 宣告只在資料檔注入內容裡出現的守衛、宣告一支不在 runner 裡跑的守衛、負控的 source 不指向 `.build/debug/akashic-guards`、負控的 source 不建 `Process`、runner 用 `if ! …; then` 呼叫守衛。68/68。
- 反向編輯（在暫存目錄複製 `Sources/akashic-guards/`、改一處、以 `swiftc` 編成另一支 binary，工作樹不動）：不看宣告只看受測對象、資料檔的一般提及也算受測對象、認不出的寫法不報、不檢查 binary 路徑、不檢查 `Process`、宣告不在 runner 裡的守衛時略過。六個 mutant 各自只讓它對應的那一格回到 rc=0。
- `official-validate` 的三個 mutant：丟掉 `--json`、指向不存在的路徑（兩者都讓 9 格裡 6 格失敗）、只讀 manifest（`contents[]` 那一格回到 rc=0）。

### 不修的

- `main.swift` 若寫成 `case "a", "b":`，`isDispatched` 會判成沒有分派。方向是誤報（要求負控，看得見），`swiftGuards()` 用的也是同一條，不在這次改。
- 誠實邊界不變：它驗的是「有一支會跑的 harness 宣告並執行它」，不是「那支 harness 有效」。受測對象的判定是文字層的，source 裡一個第一個元素恰好是守衛名、卻不是 argv 的陣列字面也會被當成受測對象；宣告這道閘在它前面。（R2 verify 更正：「宣告並執行它」說過頭，應是「宣告它、source 裡有執行它的寫法」，見下節。）

## R2 verify 修正（2026-09-30）

六席。與本 issue 有關的：Codex 一個 MEDIUM（雙空格、TAB 的呼叫兩個檢查都看不到）、DA 一個 MEDIUM（「宣告＋受測對象」只是文字層）、另有五個 LOW。逐條處置、mutant 與結果見 `changelog/2026-09-30-guard-audit-r2-fixes.md`；這裡只記判準改了什麼與誠實邊界。

- **抽取的分隔是任意個空白或 TAB**；「認不出」的偵測改成獨立找 `.build/debug/akashic-guards` 的每一處出現（只找路徑），每一處都要落在被抽取認得的呼叫裡，例外只有 `[ ! -x … ]` 存在檢查與整行只有一個 `echo "…"`（引號裡沒有 `$` 與反引號）。R1 的偵測與抽取共用同一條只認一個空格的 regex，兩個檢查共用一個失敗條件。
- **賦給變數的 argv 陣列字面**（`let consistency = ["marketplace-consistency"]`）要那個變數在同一檔出現在執行的位置（`guardArgv: x`、`arguments = x`、`exec(x`）才算受測對象。
- **「自己就是負控」的豁免**只給出現在對應表裡、以某支它宣告的守衛為受測對象的 harness，不再只看四個文字條件。

### 誠實邊界（R2 起）

本守衛認的是 **source 文字裡的執行寫法**，不是 harness 執行時實際跑了哪些守衛。DA 席在真實 harness 上做出四個掏空的形狀，現況：

1. case 表重構後只剩變數宣告（七處 `guardArgv: consistency` 全換掉、`let consistency = [...]` 留著）——R2 起擋下。
2. 在別的 harness 加 `// negative-control-for: <g>` 與一行死碼：`let _dead = ["<g>"]` 的形狀 R2 起擋下；寫成直接執行的字面（`_ = exec([BIN, "<g>"])`）放在沒人呼叫的函式裡**仍然通過**。
3. `main.swift` 把 `case "<g>-mutations":` 的分派改成 `exit(0)`——**仍然通過**（`isDispatched` 只找 `case "…":` 字面）。
4. 一般守衛在自己的 source 塞 `let p = Process()` 與一個含 binary 路徑的字串，被當成「自己就是負控」豁免——R2 起擋下。

2 的後半與 3 要執行期的證據（每支 harness 印出它實際跑了哪些守衛、由本守衛比對），那是另一個設計，另開 issue 追蹤，不在本輪。
