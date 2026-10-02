# 2026-10-02 自證閘要以 `&&` 接上、查同一支 binary，片段要在 release 版找得到、不能是負控種的（#711 R1）

#711 R1 verify（40 則）裡屬於 #711 的部分。第一版的守衛只問「閘的文字在不在」，四席與 Codex 各自找到閘在而擋不住的寫法；另外兩列的閘片段在 release 版根本找不到，第 71 列的閘被 `audit-guards-mutations` 自己的錨字串滿足。

## 閘要接得上（R1 verify 第 2、13、27 列）

第一版在被量的指令前面任何地方看到 `LC_ALL=C grep -a -q` 就放行，fence 裡較早一行有閘也算。兩種寫法因此通過，而它們在舊 binary 上照樣印 `0`：

- `LC_ALL=C grep -a -q '死 verdict' "$(command -v akashic)"; akashic validate 2>&1 | grep -c '死 verdict'`——`;` 後面照跑。
- fence 裡一行 `grep … && echo …`、下一行數 binary 的輸出——閘失敗時下一行照跑。

**R1 的判準**（`ZeroInstanceRowsAudit.selfProofIssues`）：每個單位（fence 內一行、fence 外一段 inline code）先去掉行尾的 `#` 註解，再依 shell 的運算子切成「以 `&&`／`||`／`;`／`&` 接起來的管線」（引號內、`$( … )` 內、`2>&1` 裡的符號不算）。一條被量的管線，前面那一個命令必須**恰是**自證閘，**以 `&&` 接過來**，而且閘查的 binary 與管線的來源是**同一支**（`"$(command -v X)"` 取 X、路徑取最後一段）。較早一行的閘不再讓後面繼承。

**不支援其他 fail-stop 寫法**（`set -e`、`if … then`、`|| exit`）：量測區塊沒有用到，加進來只會讓判準變寬。要用它們，先改這支守衛。

`正對照` 仍然讓同一個 fence 區塊後面的計數繼承——它不靠控制流，讀的人看它是不是 0 就知道後面的 0 算不算數。**但只認行尾註解的開頭**（`# 正對照…`），而且那一行本身要是一條被量的指令；`# 這裡沒有正對照` 這種否定句第一版照樣算（R1 verify 第 21、24、27 列）。

順手關掉的寬鬆處（R1 verify 第 13、18、24、27 列）：

| 寫法 | 第一版 | R1 |
|---|---|---|
| 一個單位裡兩條計數，第二條沒有閘 | 只判第一條 | 每條各判 |
| `grep -E -c`、`grep -v x -c`、`grep --count`、`wc -l` | 不算計數 | 算 |
| `akashic --library X validate \| grep -c` | 不算被量的指令 | 算 |
| `"$(command -v akashic)" validate \| grep -c` | 不算 | 算 |
| 閘查 `akashic-guards`、量的是 `akashic` | 通過 | 紅（不同一支） |
| 閘寫在引號字串裡（`echo "… grep -a -q …";`） | 通過 | 紅（前一個命令不是閘） |

真的規則檔在 R1 判準下沒有新的紅：每一條都是同一行、`&&`、同一支。

## 閘的片段要在 release 版找得到（R1 verify 第 3、5、10 列）

第 34 列的 `隸屬 key「`、第 36 列的 `個 venue 上` 在原始碼裡自成一個 13 位元組的字串字面段。Swift 在最佳化建置裡把 15 位元組以內的字面段當成 small string 的 immediate 嵌進指令，位元組不連續地出現在 binary 裡——三席實測 `swift build -c release` 出來的 `akashic` 對這兩個片段 `LC_ALL=C grep -a -q` rc=1，其餘 27 個都找得到。使用者 `command -v akashic` 解析到的是 release 版，所以這兩列的量測在有這條檢查的 binary 上什麼都不印，而文字說「沒印東西＝舊 binary」。

- 第 34 列的閘改用 `位 person 引用`（同一則訊息的第二段，25 位元組的字面段），第 36 列改用 `一個 ISSN 只屬於一本刊`（同一則訊息裡的長字面段）。被量的 `grep -c` 樣式不動。
- **守衛擋這件事**（`selfProofNeedleIssues`）：每個查 `akashic`／`akashic-guards` 的閘，片段必須是那支 binary 原始碼裡某個 **≥16 位元組字串字面段的子字串**。判準是 DA 席指出的「片段是不是某個較長字面段的一部分」，不是片段本身的長度——`死 verdict` 只有 11 位元組，但它在較長的字面段裡，release 版找得到。字面段的切法：一般、多行（`"""`）、raw（`#"…"#`）字串；插值 `\( … )` 是段的邊界；常見逃脫（`\n`、`\t`、`\"`、`\\`、`\u{…}`）先解碼；註解不算。
- 「那支 binary 的原始碼」：`akashic` 是 `Sources/` 除了 `akashic-guards` 與 `akashic-mcp`（沒有逐 target 解析依賴——一個只在 App 模組裡的字面段會讓它誤過），`akashic-guards` 是它自己的目錄、不含負控 harness。終判是 release 版的實際 grep（下面）。
- **release 版實測**：`swift build -c release --product akashic`（另一個 scratch path），規則檔裡所有查 `akashic` 的閘片段（`text` 區塊除外，29 個）逐個 `LC_ALL=C grep -a -q`：**29 個全部找得到**。舊的兩個片段 `隸屬 key「`、`個 venue 上` 在同一個 binary 上 rc=1，與三席的實測相同。

## 閘不能是負控自己種進 binary 的（R1 verify 第 6、11 列）

第一版在 `audit-guards-mutations` 加了三格，錨在第 71 列第一個區塊的閘那一行（含 `抽取認不出`）。這個檔編進 `akashic-guards`，於是那行閘對沒有這兩條檢查的 binary 成立、印「有這兩條檢查」——#707 補記寫的「第一行找不到它」變成假的，而那正是 #711 要消除的形狀，由 #711 自己造出來。

- **第 71 列已退場的區塊標成 `text`**：它是紀錄、不是可執行的量測，守衛不掃語言標記是 `text` 的 fence。那個區塊前面加一段說明。
- **錨在它上面的三格改錨**：「區塊裡閘與正對照都拿掉」刪掉（R1 判準下只拿掉正對照就紅，與「閘在較早一行」那格重複）；「只剩正對照」（ROBUST）刪掉（較早一行的閘不再有作用，那格量不到東西）；「只剩閘」（ROBUST）改成須紅的「閘在較早一行」，錨到第 70 列的區塊。「某一列在共通段沒有 bullet 講它」那格的 expect 原本是「沒有任何 bullet 講它」——那是第 19 列自證閘的片段——改成同一則訊息的後半段。
- **守衛擋這件事**：對 `akashic-guards` 的閘，片段不得出現在負控 harness（`Sources/akashic-guards/` 底下檔名以 `Mutations.swift`／`MutationsData.swift` 結尾的檔，依 `swift-is-the-implementation-language` 的命名：守衛的負對照寫成 `*-mutations` 子命令）的任何字串字面段裡。只看 harness 檔是刻意的窄：一個正常守衛的訊息裡也出現同一段文字時，守衛分不出哪一個是「本來該在的地方」。
- 修完之後 `LC_ALL=C grep -a -c '抽取認不出' .build/debug/akashic-guards` 是 0，第 71 列的閘對新 binary 失敗（照它自己那一行的規則，下面的數不算數）。

## 第 19 列的閘指向 PATH 上沒有的 binary（R1 verify 第 12、33 列）

第 19 列寫 `"$(command -v akashic-guards)"`，而 `akashic-guards` 不裝進 PATH——閘必然失敗、什麼都不印，與舊 binary 分不開。改成與第 20、21、70、71 列一樣的 `.build/debug/akashic-guards`，閘與被量的指令都是。

## 負控格（`audit-guards-mutations`）

62/62 → **68/68**（56 須紅 ＋ 10 須綠 ＋ 2 後設檢查）。zi-rows 的變動：

| 格 | 注入 | 預期 |
|---|---|---|
| 閘與量測指令之間是 `;`（新） | 第 13 列的 `&&` → `;` | 紅，「與自證閘之間是 `;` 不是 `&&`」 |
| 閘查的 binary 與被量的不是同一支（新） | 第 13 列的來源 `akashic` → `akashic-guards`（閘不動，片段的兩條檢查照樣過） | 紅，只有綁定這一條 |
| 閘在較早一行（原 ROBUST「只剩閘」改須紅） | 第 70 列區塊拿掉正對照、第一行前插一行閘 | 紅，指名後面的計數 |
| 正對照寫成否定句（新） | 第 71 列第二個區塊 `# 正對照（…` → `# 這裡沒有正對照（…` | 紅 |
| 量測指令一條都沒掃到（新，R1 verify 第 14 列） | 整份檔的 `\| grep -c` → `\| grep -q` | 紅，「一條都沒掃到」 |
| 閘的片段只在短字面段裡（新） | 第 36 列的閘換回 `個 venue 上` | 紅，「不在 `akashic` 原始碼任何 ≥16 位元組的字串字面段裡」 |
| 閘的片段被負控 harness 種進 akashic-guards（新） | `PluginRootsMutations.swift` 多一行含第 19 列片段的字串（注入字串在**執行期**拼起來，否則本檔自己就種了它） | 紅，「出現在負控 harness」 |
| 閘與被量的都寫成路徑形式的同一支 binary（新 ROBUST） | 第 13 列改成 `.build/debug/akashic && .build/debug/akashic validate …` | 綠，輸出不變 |
| 閘與被量的指令之間的 `&&` 不留空白（新 ROBUST） | `…"&&akashic validate 2>&1\|grep -c …` | 綠，輸出不變 |
| 區塊裡閘與正對照都被拿掉（刪） | ——（錨在已退場的區塊上） | |
| 區塊裡只剩正對照（ROBUST，刪） | ——（較早一行的閘已不起作用） | |

## 負對照（守衛的 mutant）

每個 mutant 改 `ZeroInstanceRowsAudit.swift` 一處、重編 `akashic-guards`、跑 `audit-guards-mutations`，再以反向編輯還原並對照事先存下的副本逐位元組相同（七個都是）。

| mutant | 改了什麼 | 結果 |
|---|---|---|
| M1 | 閘與被量的管線之間不看運算子 | 67/68：「閘與量測指令之間是 `;`」那格紅 |
| M2 | 較早一行的閘讓同區塊後面的計數繼承（第一版的行為） | 67/68：「閘在較早一行」那格紅 |
| M3 | 閘不必查同一支 binary | 67/68：「閘查的 binary 與被量的不是同一支」那格紅 |
| M4 | 字面段長度下限從 16 改成 1 | 67/68：「閘的片段只在短字面段裡」那格紅 |
| M5 | 不查 harness 種片段 | 67/68：「閘的片段被負控 harness 種進 akashic-guards」那格紅 |
| M6 | 正對照收任意子字串（第一版的行為） | 67/68：「正對照寫成否定句」那格紅 |
| M7 | 空掃描放行 | 67/68：「量測指令一條都沒掃到」那格紅 |

每個 mutant 恰好讓它要打的那一格紅，其餘 67 格不變。

## 已知缺口清單的檔頭（R1 verify 第 19、22、28、31、36 列）

`.githooks/acknowledged-ci-gaps.txt` 的檔頭補三件事：第四欄是**淨數**（刪一個、加一個，數不變、守衛不出聲）；「CI 未覆蓋」數的是**磁碟上**的檔（`globFiles`，不是 `git ls-files`），工作樹裡一個未追蹤的暫存 `.swift` 就會讓本機 pre-push 轉紅並催人把第四欄改大——先確認多出來的都是追蹤中的檔；第四欄只驗形狀，記一個比宣告範圍還大的數等於關掉變大的檢查。三件都是記錄，沒有改程式：改成只數追蹤中的檔會動到 `trigger-coverage` 其他三條路徑共用的 `globFiles`；「記的數超過範圍內的檔數即紅」與使用者「縮小維持綠」的裁決衝突（檔被刪了，範圍會小於記錄值）。

## 仍然看不到的（誠實邊界）

- **片段不必是那條檢查獨有的**：片段也出現在另一則訊息裡時，只有那則訊息的 binary 照樣通過閘（R1 verify 第 38 列點名 `個 venue 上`、`分不出是哪一筆`、`的檔案寫入時會被拒——`、`條邊指向同一 venue` 各自還出現在一則相關訊息裡）。要人判斷。
- **以變數或檔案當來源的計數不算被量的指令**：只認 `"$out"`；`"$res"`、不加引號的 `$out`、`cat f | grep -c`、`grep -c x file` 都掃不到，掃不到就不會紅（R1 verify 第 21、27 列）。
- **fence 裡以 `\` 接續到下一行的管線**：第二行沒有來源，不算被量的指令（R1 verify 第 18 列）。
- **inline code 的切法是一對反引號**：同一行前面有落單的反引號時，哪一段算 code 會位移（R1 verify 第 18 列）。
- **正對照只驗寫了**，不驗那一行的期望值真的不是 0；它讓同一個區塊後面全部繼承，到區塊結束為止。
- **字面段的範圍是目錄，不是 target 的依賴**：見上。release 版的實際 grep 是終判。

## 驗證

在 R1 修正輪的樹上（#712 R1 的 commit 也在這棵樹上）：

- `swift build --build-system native -Xswiftc -warnings-as-errors` 與 `--build-tests` 乾淨。
- 完整 `swift test --build-system native`：最大的 bundle 4,760 個測試、1 個跳過、0 failures。
- `bash .githooks/run-guards.sh` rc=0；其中 `audit-guards-mutations` 68/68、`trigger-coverage-mutations` 59/59。
- `zero-instance-rows-audit` 對真的規則檔 rc=0：81 列、36 條數 binary 輸出的量測（39 → 36：第 71 列已退場的區塊標成 `text` 之後不掃，少了它的三條）。
- `LC_ALL=C grep -a -c '抽取認不出' .build/debug/akashic-guards` 是 0，第 71 列那行閘對新 binary 失敗；`沒有任何 bullet 講它` 只剩真的訊息那一處。
- `tools/list` 一行 56,242 bytes（這棵樹；本輪沒有動 `Server.swift`，增量 0）。
- 只跑 `zero-instance-rows-audit` 一次：使用者時間約 2.2 秒，其中本輪新加的兩段（判閘、查片段）約 0.47 秒；其餘是既有的「編號在不在 Sources」那一段。
