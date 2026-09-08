# 守衛引用已刪除的檔：三個實例、三種嚴重度（#521，sister bug from #518）

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
| 負控 case | 31 | **32，全綠** |
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
