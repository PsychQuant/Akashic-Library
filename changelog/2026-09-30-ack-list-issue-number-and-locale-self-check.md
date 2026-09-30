# 2026-09-30 已知缺口清單的 issue 號不收 `#0`；零實例列的自證 grep 改 `LC_ALL=C`（#710）

#689／#690 R3 verify 留下的兩個 LOW。

## 已知缺口清單的 issue 號（#710 第 1 項）

`.githooks/acknowledged-ci-gaps.txt` 第三欄原本以 `\A#[0-9]+\z` 驗格式，`#0`、`#0000` 與任意長的數字都收，「每一條附 issue 號」可以用占位字串滿足。

- `TriggerCoverage.swift` 的 `acknowledgedCIGaps()` 改用 `\A#[1-9][0-9]{0,6}\z`：不以 0 開頭、至多 7 位。訊息改成「第三欄是 #<issue>：不以 0 開頭、至多 7 位」。
- 7 位是寬鬆的上限，不是量出來的界線：2026-09-30 本 repo 最大的 issue 號是 710（`gh issue list --state all --limit 1 --json number`）。它只擋得住明顯的占位，`#1`、`#999` 照收。
- 清單檔頭與 doc comment 各補一句，寫明只驗形狀、不查 issue 存不存在。

邊界輸入（以同一條 regex 在 `NSRegularExpression` 上逐一比對）：

| 輸入 | 結果 |
|---|---|
| `#0`、`#0000`、`#01` | 不收 |
| `#1`、`#690`、`#1234567` | 收 |
| `#12345678` | 不收（8 位） |
| `#690\r`、`#６９０`（全形）、`690`、`# 690` | 不收 |

### 新增的負控格

`trigger-coverage-mutations` 從 49/49 到 52/52。三格的形狀與 R2 的「第三欄寫 `TODO`」那格相同：拿掉 `census-parity.yml` 的 `Sources/**`，兩支讀整個 `Sources/` 的守衛列進清單、兩行寫同一個占位號。被收下的話兩條缺口都會被當成已知缺口放過（rc=0）。

| 格 | 第三欄 | 預期 |
|---|---|---|
| `#0` | `#0` | rc=1，兩行格式不對，兩條缺口照報 |
| `#0000` | `#0000` | 同上 |
| 8 位數 | `#12345678` | 同上 |

一種占位一格，不合成一格：「`#0` 收、`#0000` 不收」與反過來兩種改壞法都寫得出來（M3、M4）。合成一格（一行 `#0`、一行 `#0000`）時只有一行被收，rc 仍是 1，而兩條訊息都在（`⊘` 行也含那段文字），那一格會照綠。

### 負對照

先加格、後改 regex。每個 mutant 在工作樹裡改 `TriggerCoverage.swift` 那一個字串、`swift build --product akashic-guards`、跑 `.build/debug/akashic-guards trigger-coverage-mutations`，再以反向編輯還原，並以 `cmp` 對事先存下的副本確認逐位元相同。四個 mutant 紅的格各不相同，所以每次都是重編過的 binary 在跑。

| mutant | 第三欄的 regex | 結果 |
|---|---|---|
| M1（改前的寫法） | `\A#[0-9]+\z` | 49/52，三格新格全紅（rc=0，缺口被放過） |
| M2 | `\A#[1-9][0-9]*\z`（不設上限） | 51/52，只有 8 位數那格紅 |
| M3 | `\A#(?:0\|[1-9][0-9]{0,6})\z` | 51/52，只有 `#0` 那格紅 |
| M4 | `\A#(?:0{2,}\|[1-9][0-9]{0,6})\z` | 51/52，只有 `#0000` 那格紅 |

還原後重編：52/52，`trigger-coverage` 對工作樹 rc=0。

## 零實例列的自證 grep（#710 第 2 項）

零實例列的量測以 `grep -a -q '<中文字串>' <binary> && akashic validate 2>&1 | grep -c …` 先確認 binary 有那條檢查。macOS 的 `/usr/bin/grep`（BSD grep 2.6.0）在 UTF-8 locale 下對 binary 比不到中文，照抄的人會把新 binary 讀成舊 binary。

### 實測（2026-09-30，這一輪建的 `.build/debug/akashic`）

```bash
LANG=en_US.UTF-8 /usr/bin/grep -a -q '死 verdict' .build/debug/akashic; echo $?            # 1
LANG=en_US.UTF-8 LC_ALL=C /usr/bin/grep -a -q '死 verdict' .build/debug/akashic; echo $?   # 0
```

同一個 binary 以 `grep -a -c` 量：`死 verdict` 不設 `LC_ALL` 印 0、設了印 3；`沒有合併管線` 0 與 2；`person／organization 的記錄檔逼近讀取上限` 0 與 1；`附加 Zotero 來源沒記 library_id` 0 與 1；`重複的判定記錄` 0 與 2。純 ASCII 的 `library_id` 在 UTF-8 locale 下照樣找得到（rc=0），問題只在多位元組字串。`&&` 後面那個 `grep -c` 讀的是 `validate` 的文字輸出，UTF-8 locale 下正常（兩行含 `死 verdict` 的文字印 2）。

### 改了哪些

列舉方式：`grep -n 'grep -a' .claude/rules/zero-instance-guards.md`，另以 `grep -rnE 'grep [^|]*(\$\(command -v|\.build/debug/|~/bin/)'` 掃整棵樹（排除 `.build/`、`repos/`、`changelog/`）的 `.md`、`.sh`、`.swift`、`.yml`。對 binary 比中文的自證只在 `zero-instance-guards.md`，共 7 處，第 71 列那 2 處本來就有 `LC_ALL=C`，其餘 5 處加上：

| 位置 | 字串 |
|---|---|
| 第 13 列量測段 | `死 verdict` |
| 第 24 列量測段 | `沒有合併管線` |
| 第 31 列量測段 | `person／organization 的記錄檔逼近讀取上限` |
| 第 56 列量測段 | `附加 Zotero 來源沒記 library_id` |
| 第 56 列的表格格子（理由欄的「觸發條件可檢查」） | 同上 |

- 第 56 列量測段描述自證閘的那一句（「前綴的 `grep -a -q … &&` 是自證閘」）一併改成 `LC_ALL=C grep -a -q … &&`。
- 第 13 列是自證的正典（其餘各列寫「同第 13 列的自證」），量測段補一句 `LC_ALL=C` 不能省的理由與上面的實測。
- 第 70 列量測段的負控計數補上本輪的 52/52（2026-09-30 R2 的 49/49 保留）。

把改過的 4 個不同的閘從規則檔抽出來、`"$(command -v akashic)"` 換成這一輪的 binary，在 `env -i PATH=/usr/bin:/bin LANG=en_US.UTF-8 /bin/zsh -c` 裡跑：加 `LC_ALL=C` 的四個 rc=0，拿掉 `LC_ALL=C` 的四個 rc=1。

負對照（閘不是對什麼都成立）：同樣四個 `LC_ALL=C grep -a -q` 對 `/bin/ls` 全部 rc=1。PATH 上那支 2026-09-25 建的 `akashic` 是真的舊 binary：`死 verdict` rc=0、`附加 Zotero 來源沒記 library_id`（#679，2026-09-29 才加）rc=1，閘分得出它比 #679 舊；不加 `LC_ALL=C` 時兩個都是 rc=1。

## 驗證

- `swift build --build-system native -Xswiftc -warnings-as-errors`：通過。
- `swift test --build-system native`：`Executed 4404 tests, with 1 test skipped and 0 failures`。
- `bash .githooks/run-guards.sh`：rc=0（`trigger-coverage-mutations` 52/52）。

## 誠實邊界

- **沒有記錄列管當時的缺口大小。** issue 的 Expected 1 說「考慮把當時的未覆蓋數寫進條目，變大時要求重新確認」。那要把清單從三欄改成四欄、改掉每一格既有負控的注入，還要先定義「缺口大小」——宣告範圍裡未覆蓋的檔數會隨新增檔案變動，不只隨 CI 的覆蓋變動。不是一行的事，這一輪沒做；缺口變大時 rc 仍為 0。
- **issue 號只驗形狀。** `#1`、`#999` 照收，issue 存不存在、還開不開著不查（守衛離線跑），那一半仍靠第 70 列的觸發條件。
- **issue 點名的第 15、28 列沒有改**：它們的量測只有 `akashic validate 2>&1 | grep -c …`，寫著「同第 13 列的自證」卻沒有 `grep -a -q` 閘，沒有東西可加 `LC_ALL=C`。同樣只寫「同第 13 列的自證」而沒有閘的列還有很多（第 17、23、25–27、33–36、40、42、46、47 列等），補閘不在本 issue。
- 歷史 changelog 裡的同型寫法（例如 `changelog/2026-09-11-venue-authorize.md` 的 `grep -a -c '<這輪新加的字串>' .build/debug/akashic`）是當時的紀錄，沒有改。
- 第 56 列表格格子裡的指令也改了。那是一條可照抄的量測指令，不改的話同一列會留一份讀錯的副本；表格的列數、裁決與理由都沒動。
