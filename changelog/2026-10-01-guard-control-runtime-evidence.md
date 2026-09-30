# 2026-10-01 migrated-guard-control 改看 harness 的執行紀錄判定負控（#707）

`akashic-guards migrated-guard-control` 回答「每支在 `run-guards.sh` 裡跑的守衛，有沒有負控在驗它」。#689 讓它看負控的實體，但判定仍讀原始碼文字：harness 的宣告（`<g>-mutations` 命名、`// negative-control-for:`）、argv 陣列字面、資料檔的 `guardRel:`／`guardArgv:`、`main.swift` 的 `case "…":`、`run-guards.sh` 裡的呼叫寫法。#689 的 R2 verify 做出四種掏空的寫法（#707 本文），R3 verify 又做出六種（#707 的 comment 第 3–8 種），全部回報「無缺口」：負控的實體還在，執行已經不在，文字看不出這件事。

## 改了什麼

### 執行紀錄（`Sources/akashic-guards/GuardRunLog.swift`，新檔）

`run-guards.sh` 在暫存目錄建一份紀錄（`mktemp -d`，結束時 `trap` 刪掉，不進 repo 樹），以 `AKASHIC_GUARD_RUN_LOG` 傳給每個行程。一行一個 JSON 物件，鍵排序；共同欄位 `v`（格式版本 1）、`event`、`run`（每個行程一個 UUID）、`self`（這個行程的子命令名，取自它自己的命令列）。

| event | 誰寫 | 多出的欄位 |
|---|---|---|
| `start` | `main.swift` 在分派之前（`recordGuardStart()`） | —— |
| `declare` | harness 在執行時呼叫 `declareNegativeControl(for:)` | `for`：守衛名 |
| `invoke` | `runGuardProcess(...)`：harness 執行守衛的唯一入口，在子行程結束後寫 | `target`、`exe`（實際執行的 binary，解開 symlink）、`argv`、`case`（標籤）、`expect`（`red`／`green`／`output`／`none`）、`rc`、`met` |
| `end` | `finishGuard(_:)`：`main.swift` 的每個分派都經過它結束 | `rc` |

`met`（預期有沒有成立）由 `runGuardProcess` 用觀察到的 rc 與 stdout 自己算，harness 只說它預期什麼；子行程根本沒跑起來（binary 不在、spawn 失敗，rc 是 127）時 `met` 一律是 false——一次沒有發生的執行不能被記成「守衛如預期變紅」。`runGuardProcess` 把紀錄的環境變數從子行程的環境拿掉：harness 在副本裡跑的守衛、被 harness 執行的 harness 都不寫紀錄；要讓子行程寫進某一份紀錄，得在 `env` 參數明寫（新的負控 harness 的迷你紀錄就是這樣）。環境變數未設定時這些函式什麼都不做；設定了卻寫不進去，行程以 74 結束（少一行會被讀成「沒有跑」）。

八支 harness 的執行都改走 `runGuardProcess`，每一次標上預期：`audit-guards-mutations`、`decision-matrix-mutations`、`network-confinement-mutations`、`official-validate-mutations`、`oracle-precondition-control`、`plugin-roots-mutations`、`rule-prose-guards-mutations`、`trigger-coverage-mutations`。stdout 與 stderr 分開收時，stderr 改寫進暫存檔而不是第二根 pipe（兩根 pipe 依序讀會互等，`main.swift` 的 `Verdict` 記過那次死鎖）。四支原本用 `// negative-control-for:` 註解宣告的，改成函式開頭呼叫 `declareNegativeControl`（`audit-guards-mutations` 九支、`decision-matrix-mutations`、`oracle-precondition-control`、`plugin-roots-mutations` 各一支）。

### 讀者（`MigratedGuardControl.swift`，重寫）

`migrated-guard-control --log <紀錄>` 放在 `run-guards.sh` 的最後一行，排在所有 harness 之後。

- **誰要負控**：紀錄裡每一筆 `start` 的子命令。`run-guards.sh` 用什麼路徑、什麼寫法呼叫都一樣。
- **誰有負控**：某支 harness 在這次執行裡宣告了它（命名慣例由紀錄裡的名字推出，或執行時的 `declare`）、以 rc=0 跑完、執行的是本支這一支 binary，而且至少一次如預期變紅（`expect=red`、rc≠0）。列舉命令 `plugin-roots` 本來就不會紅，它的格子是輸出比對（`expect=output`：在放了沒有 manifest 的雜目錄的副本上，stdout 逐字是該有的兩行）。
- **harness 自己就是負控**：這次確實讓別的守衛如預期變紅過的 harness，自己沒有負控時印 ℹ、不計入缺口（同 #689）。
- **也算缺口**：宣告了卻沒有一次讓那支守衛如預期變紅（宣告是空的）；harness 以 rc=0 跑完、卻有執行沒照它自己的預期（它沒有比對結果）；harness 沒以 rc=0 跑完卻出現在紀錄裡（`set -e` 下它的失敗被遮掉）；執行的不是這一支 binary；宣告自己、宣告這次沒跑的守衛。
- **紀錄本身**：讀不到、除了本支自己的 `start` 一筆都沒有、有一行不是這個格式、同一個 run 的 `start` 不是恰一筆、沒有本支這一次的 `start`（`--log` 不是它正在寫的那一份），都不判定、rc=1。

**文字判準的去留**：「誰有負控」那一邊不讀任何原始碼——#689 的四個實體條件、`// negative-control-for:` 註解、argv 字面與變數追蹤、資料檔欄位、「抽取認不出」的偵測全部拿掉。「誰要負控」那一邊留一個文字檢查：剝註解後的 runner 裡每一處 `akashic-guards <名>`（中間可以隔一個引號），紀錄裡都要有它的 `start`。留它是因為執行期看不到一種情形：runner 列了一支守衛，它卻沒執行（`if false`、heredoc 裡），或執行的 binary 不寫紀錄（舊的建置）——那支守衛不會出現在 `start` 裡，只有文字知道它本來該在。

### 其他

- `main.swift`：分派前 `recordGuardStart()`；每個 `exit(f())` 改成 `finishGuard(f())`；新增 `migrated-guard-control-mutations` 與內部 `spawn-probe`（`runGuardProcess` 對沒跑起來的子行程怎麼記；不在 `run-guards.sh` 裡，由前一支帶自己的紀錄檔執行）的分派。
- `TriggerCoverage.swift`：`codeOnly` 的本體抽成 `codeOnlyText(_:path:)`，讀者的 `--runner` 可以指向 repo 外的檔（行為不變）。
- `AuditGuardsMutationsData.swift`：`migrated-guard-control` 的 19 格移除。它們注入的是 `run-guards.sh` 的呼叫寫法、`main.swift` 的分派與 harness 的原始碼，對新判準是空轉。
- 受保護清單多 `MigratedGuardControlMutations.swift`（`protected-ratchet --accept`，62 條）。

## 第一次跑就報出來的

`oracle-precondition-control` 的「未毒化」那一次，我標成預期綠，實際 rc=1。它只讀那一次的通過數：`AKASHIC_SKIP_CASES` 下 `audit-guards-mutations` 的後設檢查收不到那一對刻意相同的 case，rc 本來就是 1（`AKASHIC_SKIP_CASES=1 .build/debug/akashic-guards audit-guards-mutations` 實測 rc=1、`negative control 9/10`）。標錯的是預期，改成 `.none`。這一條檢查（harness 跑完、卻有執行沒照它自己的預期）因此不是零實例。

## 負對照：`migrated-guard-control-mutations`（新 harness）

每一格都真的執行：掏空的原始碼以 `xcrun swiftc -Onone` 在暫存目錄編成 scratch binary，迷你 runner 以 bash 跑（守衛＋它的 harness），再讓讀者讀那次的紀錄。每份迷你紀錄開頭放四行固定的測試資料，替讀者本身作證（它自己的 `start` 永遠在它讀的紀錄裡）。改壞的紀錄從健康那一格的紀錄出發，一格改一處。

`akashic-guards migrated-guard-control-mutations`：27/27（2 格須綠、24 格須紅、1 格記錄端）。形狀的編號沿用 #707：本文的 1–4、comment 的 3–8。

| # | 格 | 形狀 | 怎麼做 | 預期 |
|---|---|---|---|---|
| 1 | 對照組 | —— | 出貨的 binary；runner 跑 `decision-matrix-drift` 與 `decision-matrix-mutations` | 綠，`decision-matrix-drift ← decision-matrix-mutations` |
| 2 | 只剩變數宣告 | 本文 1 | scratch：`PluginRootsMutations.swift` 七處 `guardArgv: consistency` 換成 `["protected-ratchet"]`，`let consistency = […]` 留著 | 紅，指名 `marketplace-consistency` |
| 3 | 宣告換行、巢狀陣列 | comment 3 | scratch：`OfficialValidateMutations.swift` 加 `let officialArgv =`／換行／`[["official-validate"]]`，真正執行的那一處換成 `plugin-roots` | 紅，指名 `official-validate` |
| 4 | 別的 harness 的宣告與死碼 | 本文 2 | scratch：`rule-prose-guards` 的負控不在 runner 裡；`DecisionMatrixMutations.swift` 加 `// negative-control-for: rule-prose-guards`、`let _deadDeclaration = […]`、一個沒人呼叫、裡面有 `declareNegativeControl` 與預期紅的 `runGuardProcess` 的函式 | 紅，指名 `rule-prose-guards`；`decision-matrix-drift` 照常有負控 |
| 5 | 分派改成 `exit(0)` | 本文 3 | scratch：`main.swift` 的 `case "decision-matrix-mutations":` 改成 `exit(0)` | 紅，指名 `decision-matrix-drift` |
| 6 | 守衛本體塞死碼冒充負控 | 本文 4 | scratch：`WorkflowRunScripts.swift` 加一個沒人呼叫的函式，裡面是 `Process()` 與 binary 路徑 | 紅，指名 `workflow-run-scripts`，而且不被當成「自己就是負控」 |
| 7 | `return 0` 後接 `#if false` | comment 4 | scratch：`NetworkConfinementMutations.swift` 本體先 `return 0`，其餘包進 `#if false … #endif` | 紅，指名 `network-confinement`、宣告是空的 |
| 8 | 呼叫放進 `"""` 字串 | comment 5 | scratch：`TriggerCoverageMutations.swift` 只 `return 0`，`Process()`、binary 路徑、`["trigger-coverage"]`、`runGuardProcess(…)` 全在一個 `"""` 字串裡 | 紅，指名 `trigger-coverage`、宣告是空的 |
| 9 | runner 的 `if false` | comment 6 | runner 把 harness 那一行包進 `if false; then … fi` | 紅，`decision-matrix-drift` 缺負控，且 runner 列了 `decision-matrix-mutations` 卻沒有它的 start |
| 10 | runner 的 heredoc | comment 6 | 同上，改成 `: <<'SKIP' … SKIP` | 同上 |
| 11 | 目錄放進變數 | comment 7 | runner 以 `B=.build/debug; "$B/akashic-guards" …` 跑同一對 | 綠（寫法換了，執行照樣被記下、照樣有負控） |
| 12 | 名字也放進變數 | comment 7 | `G=akashic-guards; ".build/debug/$G" workflow-run-scripts`，文字裡連子命令前的名字都沒有 | 紅，指名 `workflow-run-scripts`（文字看不到，執行期看得到） |
| 13 | 換一個路徑的同一支 binary | comment 8 | 出貨的 binary 複製到暫存目錄的 `release/`（`.build/release` 的替身），跑 `workflow-run-scripts` | 紅，指名 `workflow-run-scripts`（照樣被記下） |
| 14 | 不寫紀錄的舊 binary | comment 8 | 同名的 shell stub（`exit 0`）跑 `decision-matrix-drift` | 紅：runner 列了它卻沒有 start |
| 15 | 紀錄：harness 沒有 `end` | —— | 刪掉健康紀錄裡 `decision-matrix-mutations` 的 `end` | 紅：沒有結束紀錄、`decision-matrix-drift` 缺負控 |
| 16 | 紀錄：harness 以 rc=1 結束 | —— | 那筆 `end` 的 rc 改成 1（runner 以 `\|\| true` 遮掉的形狀） | 紅 |
| 17 | 紀錄：沒有宣告 | —— | 刪掉那支 harness 的 `declare` | 紅：順帶跑不算 |
| 18 | 紀錄：沒照自己的預期 | —— | 一筆預期紅的 `invoke` 改成 `met=false`、rc=0，harness 仍以 rc=0 結束 | 紅：它沒有比對結果 |
| 19 | 紀錄：不是這一支 binary | —— | 那支 harness 的 `invoke` 的 `exe` 換成別的路徑 | 紅 |
| 20 | 紀錄：宣告自己 | —— | 加一筆 `declare`，`for` 是它自己 | 紅 |
| 21 | 紀錄：宣告沒跑的守衛 | —— | 加一筆 `declare no-such-guard` | 紅 |
| 22 | 紀錄：`invoke` 沒有 `start` | —— | 加一筆 run 對不上任何 `start` 的 `invoke` | 紅：紀錄不可信，不判定 |
| 23 | 紀錄：一行不是 JSON | —— | 尾端加一行 `not json` | 紅：紀錄不可信，不判定 |
| 24 | 紀錄：空的 | —— | 空檔（讀者寫進自己的 `start` 之後，除了它一筆都沒有） | 紅：空掃描不是通過 |
| 25 | 紀錄：讀不到 | —— | `--log` 指向不存在的檔 | 紅 |
| 26 | 紀錄：不是這一次的 | —— | `--log` 是健康紀錄的副本，環境變數指向別處（讀者的 `start` 寫不進它讀的那一份） | 紅：沒有本支這一次的 start |
| 27 | 記錄端：沒跑起來的子行程 | —— | 不測讀者，測寫紀錄的共用函式：`spawn-probe` 帶自己的紀錄檔，以 `runGuardProcess` 執行一個不存在的 binary、預期紅 | 讀回的 `invoke` 是 rc=127、`met=false`（不會被算成「如預期變紅」） |

`swift run akashic-guards x` 沒有做成格子：它會在 pre-push 途中重建 repo 的 `.build`。它跑的是同一份原始碼，`start` 由程式碼寫，與第 13 格是同一件事；runner 文字裡也照樣有 `akashic-guards x`。

健康那一格的 runner 與紀錄也是其餘改壞紀錄各格的出發點；它沒有留下紀錄時，那十二格記為無從做起（紅），不是略過。

## 反向驗證（讀者拿掉一件判準）

在暫存目錄的 repo 副本裡，把 `MigratedGuardControl.swift` 的一件判準拿掉（K 改的是 `GuardRunLog.swift`）、以 `swiftc` 編成那個副本的 `.build/debug/akashic-guards`，再跑 `migrated-guard-control-mutations`。工作樹不動。未改的 27/27。

| mutant | 結果 | 不再符合預期的格 |
|---|---|---|
| A 不要求宣告 | 26/27 | 17 |
| B 不要求 harness 以 rc=0 跑完 | 25/27 | 15、16 |
| C 不查「沒照自己的預期」 | 26/27 | 18 |
| D 不比 binary | 26/27 | 19 |
| E 不做 runner 的文字檢查 | 24/27 | 9、10、14 |
| F 不要求本支這一次的 `start` | 26/27 | 26 |
| G 不驗紀錄形狀 | 25/27 | 22、23 |
| H 只有本支自己的 `start` 也算有紀錄 | 26/27 | 24 |
| I 宣告即算數（不必執行） | 24/27 | 7、8、19 |
| J 「誰要負控」改回只看 runner 文字 | 21/27 | 1、9、10、11、12、14 |
| K 記錄端：沒跑起來的子行程也算「如預期」（改的是 `GuardRunLog.swift` 的 `met`，不是讀者） | 26/27 | 27 |

I 沒有讓第 2、3 格回到綠：那兩支被掏空的 harness 換了受測的守衛，自己的格子對不上、沒有以 rc=0 結束，它們的紀錄本來就不算數（I 只放寬了「要執行」，沒放寬「要跑完」）。第 4、5、6、13 格沒有被任何 mutant 翻綠：它們在紀錄裡沒有任何可以被誤算成負控的東西——死函式沒跑、`exit(0)` 之前什麼都沒發生、守衛本體的 `Process()` 從沒執行、換路徑的 binary 照樣寫了 `start`。會把它們算成有負控的，只有讀原始碼的判準（#689 R2、R3 verify 以當時的 binary 實測，全部 rc=0「無缺口」）；那正是這次拿掉的東西，讀者的 mutant 重現不了它。

## 執行時間

`bash .githooks/run-guards.sh` 的牆鐘時間，2026-10-01 在同一台機器上量。兩份暫存副本：`03a8e729`（改動前，`git archive`）與這次的工作樹（`rsync`，不含 `.build`），各自以 `xcrun swiftc -Onone` 編出 `.build/debug/akashic-guards`，改動前、改動後交錯各跑兩次，四次 rc 都是 0：

| 輪 | 改動前 | 改動後 | 差 |
|---|---|---|---|
| 1 | 220.6 秒 | 233.1 秒 | +12.5 秒 |
| 2 | 202.3 秒 | 210.3 秒 | +8.0 秒 |

平均約 +10 秒（約 5%）。之後在工作樹本身（加了第 27 格記錄端之後）直接跑兩次 `bash .githooks/run-guards.sh`：206.8 秒、218.0 秒，rc 都是 0——落在上面兩輪「改動後」的範圍內，換句話說差在雜訊裡。新 harness 自己約 21–22 秒（單獨跑：scratch 平行建置約 8–10 秒、迷你 runner 平行約 9–11 秒），`audit-guards-mutations` 拿掉 19 格（75 → 56）省回一部分。同一台機器上同時有別的測試在跑，兩輪之間相差 18 秒，比改動本身的差還大——這兩個數是量級，不是精確值。CLAUDE.md 的 pre-push 耗時表沒有更新：差在 5% 左右，而那張表最後一欄的「整個 pre-push」本來就寫「未重量」。

## 誠實邊界

- **紀錄是一般檔案**。harness 直接打開 `AKASHIC_GUARD_RUN_LOG`、寫一行假的 `invoke`，讀者分不出那一行是不是 `runGuardProcess` 寫的。它擋的是遺忘與掏空，不是蓄意偽造。
- **宣告與預期是 harness 說的**。harness 讓守衛變紅的原因可以與注入無關（例如傳一個壞掉的參數）；讀者證明的是「它執行了、它紅了、harness 預期它紅」。紅的原因對不對，由 harness 自己的具名比對管：對不上時 harness 回非零，`run-guards.sh` 在讀者之前就停了。
- **runner 裡既不以 `akashic-guards <名>` 的文字出現、又不寫紀錄的呼叫**兩邊都看不到，例如 `env -u AKASHIC_GUARD_RUN_LOG "$G" x`（`G` 是 binary 的路徑）。
- **不經 `runGuardProcess` 的執行不算數**。harness 自己 spawn 的守衛不會有 `invoke`（方向是缺負控，看得見）；若它把紀錄的環境變數傳下去，那支守衛會寫 `start`、被當成 runner 跑的而被要求負控（同一個方向）。
- **`plugin-roots` 的例外**：它的負控是輸出比對而不是變紅。harness 對任何守衛都可以寫 `.exactOutput`，讀者不區分它用在哪一支——一支會紅的守衛若只拿到輸出比對，同樣算有負控。
- **scratch 建置需要 `xcrun swiftc`**。沒有的機器上七格掏空的原始碼無法建置，那七格記為沒跑起來、harness 回 1，不是略過。
