# 2026-09-30 守衛稽核的 R2 verify 修正（#689、#690）

R2 verify 六席（requirements、logic、security、regression、devil's advocate、Codex）。本檔記 #689 與 #690 的處置、每一個 mutant 與結果。#702 的 finding（7–9、15–16、19–22、26）由另一條 branch 處理，不在這裡。finding 編號是那一輪合併清單的編號。

## #690：trigger-coverage

### 兩格負控的 workflow 注入改成 Actions 收的設定（finding 1，Codex MEDIUM）

R1 加的兩格都讓同一個事件同時有 `paths` 與 `paths-ignore`，GitHub Actions 不收這種設定。通過那兩格只證明自製的解析器怎麼讀一份不合法的設定。

- 「另一個 workflow 的 paths 涵蓋 `Sources/**` 卻不跑守衛」：把 `ci.yml` 的事件篩選整段（`paths-ignore:` 與它的五條）換成單一的 `paths: Sources/**`。
- 「跑守衛的 workflow 以 `paths-ignore` 排除宣告範圍的一部分」：`census-parity.yml` 的 `push` 照舊只有 `paths`，`pull_request` 從 `paths: *parity_paths` 改成只有 `paths-ignore: Sources/AkashicS2/**`。兩個事件各一個鍵，是合法設定；只動 `Sources/AkashicS2/` 的 PR 真的不觸發這個 workflow。守衛不分事件，看到 `paths-ignore` 排除它就算未覆蓋，這一格要驗的正是這個判斷。

Codex 另外建議用否定樣式（`paths:` 裡的 `!Sources/AkashicS2/**`）。沒有採用，理由是守衛的 `pathsMatch` 以 `fnmatch` 比對，不認 `!` 開頭的否定樣式：那一行會被當成一個比不到任何檔的樣式而忽略，於是被否定的那一片會被判成有覆蓋。兩個 workflow 檔今天沒有否定樣式（2026-09-30 `grep -nE "^\s*-\s*[\"']?!" .github/workflows/*.yml` 零命中），所以是零實例；要不要讓守衛認它，留給 orchestrator 決定是否開 issue。

### 已知缺口清單的格式閘與比對（findings 3、11、24，regression MEDIUM；12、25，LOW）

R1 的三格只走到欄數（少一欄）、過期、列管三件事。拿掉第三欄的 `#<issue>` 格式檢查、或比對時只比守衛不比樣式，負控仍 44/44；第三欄寫 `TODO` 的一行會把缺口放過。

- 第三欄改用 `\A#[0-9]+\z`（先前是 `^#[0-9]+$`，ICU 的 `$` 在行尾 `\r` 前也匹配）。
- CRLF：以 `\n` 切行之後去掉行尾那一個 `\r`。先前 CRLF 空行被當成一欄的條目（誤紅），第三欄是 `#690\r` 照收。
- 同一個守衛、同一個樣式列兩次：第二行是格式不對，訊息說出兩個行號。先前第二條永遠命中不到，被報成「已經沒有缺口——把它從清單拿掉」，而缺口其實還在。
- 條目對不到任何宣告（守衛檔不在、或樣式不逐字相同）：訊息說「對不到任何宣告」，不再說「已經沒有缺口」。這一條不在 finding 的要求裡，是新的「樣式不同」那一格需要一句真話才加的；finding 25 另外指出的「條目指向已刪除的守衛也說已經沒有缺口」一併由它處理。
- `.githooks/acknowledged-ci-gaps.txt` 的檔頭補上重複、對不到宣告、CRLF 三句。

新增五格，`trigger-coverage-mutations` 從 44/44 到 49/49：

| 格 | 注入 | 預期 |
|---|---|---|
| 第三欄不是 `#<issue>` | 拿掉 `Sources/**`，兩支守衛列進清單、第三欄寫 `TODO` | rc=1，兩行格式不對，兩條缺口照報 |
| 第一或第二欄空 | 一行第一欄空、一行第二欄空 | rc=1，兩行格式不對，沒有別的缺口 |
| 樣式與宣告不同 | 拿掉 `Sources/**`，`NetworkConfinement` 列成 `Sources/**/*.swift`、`ZeroInstanceRowsAudit` 列正確的樣式 | rc=1，`NetworkConfinement` 的缺口照報、那一條「對不到任何宣告」 |
| CRLF | 拿掉 `Sources/**`，兩條正確的條目與一個空行都用 CRLF | rc=0，兩條 `⊘`，訊息是「#690 追蹤」、不夾 `\r` |
| 重複 | 拿掉 `Sources/**`，`NetworkConfinement` 列兩次 | rc=1，「重複」 |

### 文字（findings 6、13、21；14）

- `TriggerCoverage.swift` 的 doc comment 說機制的保留記在 `zero-instance-guards` 第 48 列，那是 ISSN 角色那一列（#587）。改成第 70 列。
- 第 70 列的量測先前只有 `grep -cE '^[✗⊘] .*宣告 `'`，#690 之前的 binary、守衛以 rc=2 中止，都印 0。改成先存輸出、印 rc，再數 `✓` 行當正對照（2026-09-30：3），`✓` 是 0 時 `✗⊘` 的 0 不算數。第 70 列的理由欄補一句 R2 的處置，並寫明 `#<issue>` 只驗格式、不驗 issue 存在或仍開著。

## 負對照（mutant）

在暫存目錄複製 `Sources/akashic-guards/`、改一處、以 `swiftc -Onone` 編成另一支 binary，放進一份只含 harness 所需子樹的 repo 副本，在那裡跑 harness。工作樹不動：每個 mutant 的原始碼與工作樹以 `diff -rq` 比對，恰好只有被改的那一個檔不同。

| mutant | 改了什麼 | 結果 |
|---|---|---|
| M1 | 第三欄的 `#<issue>` 檢查恆真 | 48/49，只有「第三欄不是 `#<issue>`」失敗（rc=0，缺口被放過） |
| M2 | 拿掉第一欄非空的檢查 | 48/49，只有「第一或第二欄空」失敗（多一條對不到宣告的缺口） |
| M3 | 拿掉第二欄非空的檢查 | 48/49，同一格失敗 |
| M4 | 比對時只比守衛、不比樣式 | 48/49，只有「樣式與宣告不同」失敗（rc=0） |
| M5 | 不去掉行尾的 `\r` | 48/49，只有「CRLF」失敗（CRLF 空行與條目被報成格式不對） |
| M6 | 不檢查重複 | 48/49，只有「重複」失敗 |
| M7 | 對不到宣告的條目也說「已經沒有缺口」 | 48/49，只有「樣式與宣告不同」失敗 |
| M8 | 範圍檢查裡「workflow 有跑這支守衛」恆真 | 48/49，只有重建的 `ci.yml` 那格失敗（rc=0） |
| M9 | 範圍檢查不看 `paths-ignore` | 48/49，只有重建的 `pull_request` 那格失敗（rc=0） |

每個 mutant 都在它自己的副本裡；「還原」是工作樹本來就沒被改過，以 `diff -rq` 確認。

**修正前的守衛跑新格**（同一個方法：把 `TriggerCoverage.swift` 與 `MigratedGuardControl.swift` 換回 `2e9d5c67` 的版本、資料檔用這一輪的）：
`trigger-coverage-mutations` 46/49，紅的是「樣式與宣告不同」（訊息說「已經沒有缺口」）、「CRLF」「重複」；「第三欄不是 `#<issue>`」與「欄位空」兩格在修正前就綠——它們釘的是本來就在的條件（M1–M3 證明它們有用），不是新行為。
（#689 那一半的新格見下一個 commit。）
