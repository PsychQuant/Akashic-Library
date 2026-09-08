# 守衛引用已刪除的檔：四個實例、三種嚴重度（#521，sister bug from #518）

`989ac64`（#433 Step 5「Python 歸零」）刪掉那些 `.py`，而**刪除端沒有掃描讀取端**。四處讀者各自留著。

## 兩次計數都錯：立案寫「2 支」，第一版修完寫「三處」

| # | 位置 | 有守衛嗎 | 實際行為 |
|---|---|---|---|
| 1 | `MeasuredClaimsAudit.swift:194` | ❌ | **真的靜默** |
| 2 | `MigratedGuardControl.swift:54-56` | ✅ `fileExists` | 死碼，無害 |
| 3 | `census-parity.yml:131,137` | ❌ | **大聲失敗，但擋在別的檢查前面** |
| 4 | `ci.yml:94` | ❌ | 同上，**而它擋住的是 AkashicApp** |

> **第 4 處是 R1 verify 找到的**（security 與 regression 兩席獨立命中）。本檔第一版寫「三處讀者各自留著」——**一個漏了一處的封閉列舉**，而這正是本 issue 要消滅的形狀。`ci.yml` 的 job 在 macos-15，那一行在 `run: |` 區塊的第二行，`bash -e` 下失敗會讓整個 step 掛掉；它後面還有四步——測試數下限／Tractatus／**AkashicApp（`swift test` 涵蓋不到的那塊，#101 的立案理由）**／端對端 load.sql。改指 Swift 子命令（該 job 第 4 步已 `swift build`）。

**實例 1 是唯一真正靜默的。** `rawFile` 對不存在的檔回空字串 → `components(separatedBy:)` 得 `[""]` → 走訪它的迴圈零次迭代。修正前的實跑（標題後直接接下一項，中間一行都沒有）：

```
③ 「3 格全是 warn_case（…）」
④ 「run: 的分類：總數 ＝ 單行 ＋ block」
```

**標題印了，本體一行都沒有**，沒有 ✓ 沒有 ✗，rc 仍是 0。比檢查失敗更壞——失敗會被看見。

**而它驗的命題仍為真**：那三格的資料隨 #433 搬進 `TriggerCoverageMutationsData.swift`，實測 `expect: "一次都沒出現過"` 恰 3 處且**全部 `isWarn: true`**。所以處置是**指向新來源**而不是退場。

> **標題不寫死行號**（R1 verify，四席 ＋ Codex 獨立命中）。本檔第一版與守衛標題都寫「行 62／106／142」，而**同一個 commit** 在該資料檔頂端插入 12 行負控 case，把三格推到 74／118／154——標題與它自己下一行的輸出當場矛盾，而行號那一半**零斷言**。同一個宣稱一度有三組數字（規則檔、守衛標題、實際輸出）。現在標題陳述的是不變量（「恰 3 格且全是 warn」），行號由逐格輸出印實際值。

**實例 2 有守衛，所以不是同一回事。** `if fileExists(...)` 把不存在的檔排除在 `harnesses` 外，實跑 rc=0、無缺口。這是 #433 沒掃乾淨的死碼，`no-compat-fallback` 的退場即刪。

**實例 3 方向相反。** 兩個 step 跑已刪的 `.py`，`python3 <不存在的檔>` 回非零；整份 workflow 無 `continue-on-error`、無 `if:`，三個 step 同一個 job 循序排列，而 `run-guards.sh`（所有守衛的 CI 覆蓋**唯一**來源）在後面。job 會在那裡死掉，覆蓋永遠到不了。

**刪除而非改指 Swift 子命令**：`run-guards.sh` 已經跑那兩支（行 53 與 94），而它們獨立存在的理由——「ubuntu 那台缺 toolchain，6 個 swift-gated case 在 CI 哪裡都跑不到」——隨 #435 刪掉 ubuntu workflow 一起消失了。留著等於第二份會分岔的清單。

## Expected 2：偵測機制

`trigger-coverage` 的路徑字面掃描補上「檔案不存在」那一半（#518 刻意留的另一半，該處註解寫著「那一半是 #521，不是防呆」）。

**它上線後第一次執行就抓到實例 1 與 2 那兩處真的死引用**——RED 由真實 bug 驅動，不是構造出來的。

## 修完之後新檢查又報一條，而那條是對的

`MeasuredClaimsAudit` 改指向 `TriggerCoverageMutationsData.swift` 之後，那成了一條**真依賴**而它不在受保護集合。補進 `DATA`（受保護 54 → 55）。這同時補上 #518 regression 席指出的不對稱：`MarkerParityMutationsData.swift` 早在表裡，它的姊妹檔卻不在——**而那一輪的 diff 就改了它**。

## `rawFile` 一般化的誠實結果

**11 個直接呼叫點**掃完（本檔第一版寫「五個」——漏了 6 個，全在 `TriggerCoverage.swift` 內；R1 verify 的 requirements 席重掃）。結論不變：**只有實例 1 是真靜默**。代表性的四個：

- `LiteralScalarParity:60` → `guard let … else { return fail(…) }`，**會紅**
- `MeasuredClaimsAudit:247` → `check(r5.count == 1, …)`，**會紅**
- `MeasuredClaimsAudit:134` → 讀自己，必然存在
- `MigratedGuardControl:77` → 路徑由 `globFiles` 產生，必然存在

所以**不加儀式性守衛**。只修 `LiteralScalarParity` 一個**指錯原因**的訊息：來源檔不見時它原本說「抽取式與宣告寫法脫節了」，會讓人去改抽取式。訊息指錯原因比不出聲好一點，但只好一點。

靜態的那一半由新檢查涵蓋（守衛程式碼裡的路徑字面），這比在每個呼叫點加防禦更嚴——它不需要有人記得加。

## 量測

| | 修正前 | 修正後 |
|---|---|---|
| `measured-claims-audit` 檢查 ③ | **零行輸出**、rc=0 | 三格逐行 ✓ ＋ 格數 ✓ |
| 受保護檔 | 54 | **55** |
| 逐對缺口 | 0 | **0** |
| 負控 case | 31 | **37，全綠**（R1 +1、R2 +1、R3 +4） |
| 兩份 workflow 的 `run:` 指向不存在的檔 | **3** | **0** |
| `run-guards.sh` | — | **exit 0，零個 ✗** |

負控承重已反證：停用「檔案不存在」那個分支 → 32 掉到 31，且掉的正是該 case；還原回 32。

## 誠實邊界

**實例 3 與 4 都無法在 CI 上驗證。** GitHub Actions 帳務擱置（CLAUDE.md 記載 runner 不啟動、`steps=0`），所以「job 現在到得了後面那些 step」只由**讀 YAML ＋ 本機模擬**支持：兩份 workflow 的**每個 `run:` 區塊逐行**核對（不只帶檔名的那幾行——第一版寫「三個 `run:`」是低報，實際 census-parity 有 5 個）、指向的檔都存在或是有效的 `akashic-guards` 子命令、YAML parse 通過、step 序列印出來看過。**沒有一次真的 CI 執行**。

**這個家族的文件面實例不只一個**（本檔第一版寫「一個」，R1 verify 的 requirements 席數出至少四處）。本輪修掉三處**與本 diff 直接相關**的：`.githooks/run-guards.sh:57`（名指已刪的 `.py`、寫「30 個 case」而本輪剛改成 32、並描述一個已退場的兩版並驗機制）、`census-parity.yml` 的死 `paths:` 條目與「與上一步重疊」的陳舊註解、`plugin/rules/assertions-must-be-measured.md` 的宣稱本體（它寫著舊行號，使同一宣稱有三組數字）。

**刻意不修的**：`CLAUDE.md:410` 用現在式寫「**現在**有守衛在量（`plugin/tests/trigger-coverage.py`）」。它不是 #521 造成的，掛在本 issue 的 commit 下會誤植歸屬——已在 #518 的 closing summary 與本 issue 的診斷具名。

**本輪刻意不動的**：掃描範圍（`*Data.swift` 是否納入）、`PATH_ROOTS` 白名單、`PROTECTED.count` 的 floor——那三項是 #522 的裁決，兩張共享 `TriggerCoverage.swift` 的同一道檢查，界線不守住會互相覆蓋。

## R1 verify 對這道新檢查本身的兩個更正

**(1) 訊息宣稱「讀」，而它只證明了「提到」**（Codex 跨模型席；四席 Claude 全部沒看到）。這道掃描找到的是**路徑字面**，它沒有證明那個字面流進 `rawFile` 或任何讀取 API——**本 issue 自己的負控就是反例**：第一版注入 `_gone = ROOT / "…"`，那一個字都沒讀，而訊息卻說「`rawFile` 會回空字串，讀它的檢查會靜默通過」。

更糟的是那條規則會**禁掉一個這個 repo 真的用過的形狀**：`MigratedGuardControl` 原本的 `fileExists("plugin/tests/oracle-precondition-control.py")` 是一個合法的 absence probe，而新規則會把它判紅。

修法兩半：訊息改成只陳述觀察到的事（「引用了 X，而那個檔不存在」），並對**同一行**寫著 `fileExists(...)` / `.exists()` 之類的 absence probe 豁免。實測兩種同行形狀都豁免、真的死引用仍紅。**豁免只看同一行是實測過的限制**——先賦值再檢查不會豁免，跨行判斷需要資料流分析；訊息因此明寫「用 `fileExists(...)` 之類的形狀寫」，那條出路是可執行的（對照 #518 那條「或確認那不是真的依賴」，它沒有任何落點）。

**(2) 負控注入的不是真的讀取形狀**（同席）。第一版只建一個 `Path`，所以它驗到的其實是「任意不存在的路徑字面會被拒絕」而非「守衛讀取不存在的來源會被拒絕」——**把過寬的行為固化成預期**。改成 `.read_text()`，並在同一格順便注入一個同行 absence probe：harness 的第三段判準（不得有無關缺口）因此成為豁免的負控。

**另外三處是我自己的散文在對自己的工作說錯話**：`TriggerCoverage.swift` 有四處「顯式 19／受保護 54」因本輪新增第 20 條而全部差一；該檔的 doc block 還寫著「檔案不存在時直接跳過——那一半是 #521」，與本輪改成 `fails` 的程式碼直接矛盾；`MeasuredClaimsAudit` 的註解把空來源分支寫成「本次修正的核心」，而 `found == 3` 本身就擋得住那個零次迭代——它買到的是更準確的診斷，不是唯一的防線。

## R2 verify：第一輪的修法自己引入了一個 false negative

R1 修完之後跑 R2 delta 複驗（Codex 跨模型席）。**判 FAIL，八項**——其中第一項是我在修 R1 時**新造**的缺陷，方向正是這道檢查要防的那個。

**absence probe 豁免套在「整行」而不是「這個字面」。** R1 加豁免時問的是「這一行有沒有 probe token」，於是：

```swift
let dead = rawFile("plugin/tests/deleted.py"); let ok = fileExists("某個存在的檔")
```

掃描 `deleted.py` 時整行含 `fileExists(` → **直接跳過**。真正的死引用被同行一個**無關**的 probe 消音了。`.exists()` 更寬——`database.exists()` 這種與檔案無關的 API 也算。而它可能只是排版巧合，不必是惡意規避。

修法是把豁免綁到**這一次 match 的字面**：看它前後**緊鄰**的文字（去掉所有空白與換行後比對），要求它確實是 `fileExists(…)`／`os.path.exists(…)`／`Path(…)` 的引數，或緊接 `.exists()`／`.is_file()`。實測五格：

| 注入（都在真的守衛檔裡） | 期望 | 實測 |
|---|---|---|
| 真讀取 ＋ 同行無關 `fileExists(存在的檔)` | 紅 | **1** ✓ |
| 真讀取 ＋ 同行 `database.exists()` | 紅 | **1** ✓ |
| `fileExists("不存在")` 同一行 | 豁免 | **0** ✓ |
| `fileExists(\n  "不存在"\n)` **跨行** | 豁免 | **0** ✓ |
| 純死引用 | 紅 | **1** ✓ |

> **跨行那一格是順帶修好的第二個錯**：R1 的訊息承諾「用 `fileExists(...)` 之類的形狀寫就會豁免」，而當時的整行比對對跨行寫法**做不到**——訊息承諾了程式碼沒有的東西。綁到字面之後（前綴去空白比對）跨行自然成立。訊息也拿掉「之類」這種泛稱，改成逐一列出支援的形狀。
> **「自然成立」這句在 R3 被推翻了一半**：當時的窗是**先取 40 個原始字元再剝空白**，所以只有縮排不超過窗的短跨行成立。見下方 R3 第 2 項。

**負控補上這個洞**：新增一格「同行的無關 absence probe 不得消音真正的死引用」，注入一行兩件事（真讀取指向不存在的檔 ＋ 指向存在檔的 probe），正確行為是恰好一條缺口。承重已反證——把豁免改回整行 → 33 掉到 32，掉的正是該格。

### 其餘七項

**「幾乎總是遷移殘骸」是沒有分母的頻率宣稱**。四個實例全來自同一輪 #433 遷移，不是四個獨立事件，推不出一般頻率。改成有界可證的說法：「#521 找到的四處實例全部是 `989ac64` 遷移後留下的引用」。

**還有三處舊數字沒改到**（`9/54，17%`／`10/19`／`顯式嚴格更優 19 個檔`），**這同時推翻了本檔上一版「四處……全部差一」的宣稱**——那句話說「都修好了」，而實際只修了四處中的一部分。

**`LiteralScalarParity` 仍會把「存在但讀不出來」誤報成空白檔**。`rawFile` 回空字串有四種原因，而 `fileExists` 只排除了第一種——權限不足、非法 UTF-8、路徑其實是目錄，三者都會走到「是空的」那句。沒有換讀取 API（那要動 `rawFile` 的簽章），所以訊息把不確定說出來。

**`run-guards.sh` 的註解相鄰兩行互相矛盾**：R1 只改了前半句（「兩版並驗機制已退場」），留著後半句還在描述那個機制（「對每個 case 同時跑兩版並要求輸出逐字相同」）。整段重寫。

**本檔標題還寫著「三個實例」**，而正文與表格已經是四個。

**負控只鎖住 `.exists()` 那一支**——`fileExists(`／`os.path.exists(`／`Path(...).is_file()` 任何一支單獨壞掉都不會被抓到。本輪補了核心洞那一格；其餘三支仍無專屬負控，記在此處而不假裝涵蓋。

### Codex 逐項判過的（通過，記錄以免被讀成沒查）

檢查 ③ 的標題與行號、`found == 3` 的硬編碼（它被 `found == 3` 自己斷言，新增第 4 格會紅、不會靜默過期；與第 ④ 列「不寫死 19／13」不矛盾——那一列守的是恆等式而非固定人口）、`isWarn` 的 `hasPrefix`、`ci.yml` 的 `.build/debug/akashic-guards`（同 job 前面有無條件的 debug `swift build`）、以及「引用了」這個措辭本身。

## R3 verify：修復輪第四次帶進新缺陷，而這次是同一個缺陷換位置

R2 修完之後跑 R3 delta 複驗（Codex 跨模型席）。**判 FAIL**。其中兩項我在跨模型席回覆落地**之前**用自己的探針獨立命中，另外三項只有它看到。

**這是連續第四輪「修復輪的新產出含新缺陷」**（#518 R1→R2 兩次散文、#521 R1→R2 一次程式碼、本輪一次程式碼）。四次同源即模式，不是個案——而本輪最尖的一項，是 R2 那個缺陷**換了一個位置再犯**。

### 1（HIGH）· 裸的 `exists(` 把「過寬比對」從整行搬到了 callee 尾綴

R2 把豁免從**整行**綁到**字面**，但前綴清單裡留了一支裸的 `pre.hasSuffix("exists(")`——它以**任意接收者**結尾都算數：

```swift
let dead = database.exists("plugin/tests/gone.py")   // 實測 0 缺口 ＝ 被消音
```

R2 的註解裡就寫著「`database.exists()` 也算，那是我自己引入的 false negative」——**而修法把那個例子留在了條件裡**。

**全樹量過**（2026-09-08）：`fileExists(` 21 處、`Path(` 11 處、`os.path.exists(` 3 處，而裸 `exists(` **零合法實例**（唯二命中在 `TriggerCoverage.swift` 自己的註解裡，`codeOnly()` 已剝掉；另一處 `f.exists()` 無引數，本來就不是 match）。它冗餘於 `os.path.exists(`（後者本來就以小寫 `exists(` 結尾），對 `fileExists(` 則不冗餘（`E` 是大寫、`hasSuffix` 區分大小寫）。**一個零實例的放寬，換到的只有 false negative。**

前綴清單因此收成**封閉列舉、恰三個**（`PROBE_PREFIXES`）。

### 2（MEDIUM）· 40 字元窗是在剝空白**之前**取的

`suffix(40)` 取的是 40 個**原始** Character，之後才 `filter { !$0.isWhitespace }`。所以縮排夠深的跨行 probe，窗裡全是空白，`pre` 變成空字串：

```swift
let absent = fileExists(
                                        "plugin/tests/gone.py"   // 縮排 40 格
)
```

實測 **1 條缺口**——一個合法的 absence probe 被報成死引用，而報告文字正叫你用那個形狀寫。方向是報紅不是消音，但它讓 R2 那句「跨行自然成立」只在短跨行為真。

改成 400 並用 `NSRange` 界定，順帶收掉「每次 match 都建整個前綴字串」的 **O(n²)**。**400 是條件不是保證**，這句寫進註解：token 與字面之間若隔了 400 個以上的原始字元仍不豁免。

### 3（HIGH，只有跨模型席看到）· `hasSuffix` 沒有 identifier 邊界

`profileExists(` 以 `fileExists(` 結尾、`XPath(` 以 `Path(` 結尾。實測**兩者都得 0 缺口**——一個名字碰巧以允許 token 結尾的自家函式，就能消音死引用。

修法是前綴命中後再看 token 前一個字元不是 identifier 字元。**而同席同時指出那個修法自帶的陷阱**：邊界不能在剝光空白的字串上判——`if fileExists(` 剝完是 `iffileExists(`，前一個字元變成 `if` 的 `f`，**最常見的合法形狀會被判掉**。

所以前綴側改成只剝**尾端**空白（token 與字面之間本來就只能是空白，夾別的東西 `hasSuffix` 自然不成立）；後綴側維持全剝，因為它的 token 以 `.`／`)` 開頭，identifier 撞不進去。**這個不對稱有理由，不是疏漏。**

### 4（LOW）· `rawFile` 的「四種原因」是錯的窮舉

R2 在 `LiteralScalarParity` 的訊息裡寫「權限、非 UTF-8、或它其實是目錄」，讀起來像封閉列舉而它不是：`rawFile` 把**所有**讀取錯誤折成空字串（一般 I/O 錯誤、檢查與讀取之間檔案被換掉、非 regular file…），`fileExists` 也消不掉 TOCTOU；而該分支查的是 `trimmingCharacters(...).isEmpty`，還涵蓋「成功讀到只有空白」——那甚至不是 `rawFile` 回空字串。訊息改成明寫不窮舉。

### 5（INFO）· R2 那張「五格實測」表無法由 diff 驗證，本輪把它變成常駐

Codex 指出 R2 的表是一次性手跑，diff 裡看不到執行輸出，也沒有對應的常駐 case。本輪新增**四格**負控（33 → 37），每一格都反證過承重——把修法的對應那一半各退回一次，恰好那一格紅、其餘 36 綠：

| 新增負控 | 退回哪一半會紅 | 實測 |
|---|---|---|
| 任意接收者的 `.exists("死引用")` 不得豁免 | 放回裸 `exists(` | 36/37，`rc=0 沒指名` |
| 縮排 50 格的跨行 probe 仍須豁免 | 窗改回 40 | 36/37，`另有 1 條無關缺口` |
| `profileExists(` 不得豁免 | 拿掉邊界檢查 | 36/37，`rc=0 沒指名` |
| `if` 緊接的 probe 仍須豁免 | 邊界改在全剝字串上判 | 36/37，`另有 1 條無關缺口` |

`XPath(`（同型、命中 `Path(`）**刻意不另開一格**：它與 `profileExists(` 走同一個謂詞，分兩格會讓計數多一而事實沒多一件——`zero-instance-guards` 第 5 列（對自己的覆蓋率說謊）管的正是這個。改成把涵蓋範圍寫出來。

### 6（無 finding）· 非 BMP 字元不會讓 NSRange 切錯

跨模型席逐項查過：`NSRegularExpression` 的 `NSRange` 與 `NSString.substring` 都以 UTF-16 offset 計，match 邊界不會落在 surrogate pair 中間；轉成 Swift `String` 之後才改以 Character 操作。守衛原始碼裡大量 CJK 註解不構成風險。記在這裡，以免日後被讀成沒查。

### 誠實邊界：豁免的五種形狀，仍只有兩種有專屬的正向負控

| 形狀 | 專屬正向負控 |
|---|---|
| `os.path.exists("不存在")` 前綴 | ✅（R3 的跨行格與 `if` 格） |
| `.exists()` 後綴 | ✅（R1 的複合格） |
| `fileExists("不存在")` 前綴 | ❌ |
| `Path("不存在")` 前綴 | ❌ |
| `.is_file()` 後綴 | ❌ |

三支若單獨打錯字，不會有任何 case 變紅。**不補**：它們與已覆蓋的兩支走同一個謂詞，補進來是近似重複而非新事實（同 `XPath(` 的理由）。R2 的誠實邊界寫「其餘三支仍無專屬負控」——本輪把它從三支縮到三支中的**不同三支**（`os.path.exists(` 換出、`fileExists(` 換入），這一格因此仍然開著，不假裝關掉。

**另一個仍開著的**：本輪四項修正全部只在本機驗證，CI 帳務仍擱置（同本檔上方的既有邊界）。
