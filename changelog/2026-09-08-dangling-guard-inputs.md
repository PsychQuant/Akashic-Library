# 守衛引用已刪除的檔：三個實例、三種嚴重度（#521，sister bug from #518）

`989ac64`（#433 Step 5「Python 歸零」）刪掉那些 `.py`，而**刪除端沒有掃描讀取端**。三處讀者各自留著。

## 立案寫「實測 2 支」，那個計數對但分類錯

| # | 位置 | 有守衛嗎 | 實際行為 |
|---|---|---|---|
| 1 | `MeasuredClaimsAudit.swift:194` | ❌ | **真的靜默** |
| 2 | `MigratedGuardControl.swift:54-56` | ✅ `fileExists` | 死碼，無害 |
| 3 | `census-parity.yml:131,137` | ❌ | **大聲失敗，但擋在別的檢查前面** |

**實例 1 是唯一真正靜默的。** `rawFile` 對不存在的檔回空字串 → `components(separatedBy:)` 得 `[""]` → 走訪它的迴圈零次迭代。修正前的實跑：

```
③ 「3 格全是 warn_case（行 209／246／315）」
④ 「run: 的分類：總數 ＝ 單行 ＋ block」
```

**標題印了，本體一行都沒有**，沒有 ✓ 沒有 ✗，rc 仍是 0。比檢查失敗更壞——失敗會被看見。

**而它驗的命題仍為真**：那三格的資料隨 #433 搬進 `TriggerCoverageMutationsData.swift`，實測 `expect: "一次都沒出現過"` 恰 3 處且**全部 `isWarn: true`**。所以處置是**指向新來源**而不是退場，行號 209／246／315 → 62／106／142。並加一句「來源讀不到就出聲」——沒有它，下次搬家會重演同一個失效。

**實例 2 有守衛，所以不是同一回事。** `if fileExists(...)` 把不存在的檔排除在 `harnesses` 外，實跑 rc=0、無缺口。這是 #433 沒掃乾淨的死碼，`no-compat-fallback` 的退場即刪。

**實例 3 方向相反。** 兩個 step 跑已刪的 `.py`，`python3 <不存在的檔>` 回非零；整份 workflow 無 `continue-on-error`、無 `if:`，三個 step 同一個 job 循序排列，而 `run-guards.sh`（所有守衛的 CI 覆蓋**唯一**來源）在後面。job 會在那裡死掉，覆蓋永遠到不了。

**刪除而非改指 Swift 子命令**：`run-guards.sh` 已經跑那兩支（行 53 與 94），而它們獨立存在的理由——「ubuntu 那台缺 toolchain，6 個 swift-gated case 在 CI 哪裡都跑不到」——隨 #435 刪掉 ubuntu workflow 一起消失了。留著等於第二份會分岔的清單。

## Expected 2：偵測機制

`trigger-coverage` 的路徑字面掃描補上「檔案不存在」那一半（#518 刻意留的另一半，該處註解寫著「那一半是 #521，不是防呆」）。

**它上線後第一次執行就抓到實例 1 與 2 那兩處真的死引用**——RED 由真實 bug 驅動，不是構造出來的。

## 修完之後新檢查又報一條，而那條是對的

`MeasuredClaimsAudit` 改指向 `TriggerCoverageMutationsData.swift` 之後，那成了一條**真依賴**而它不在受保護集合。補進 `DATA`（受保護 54 → 55）。這同時補上 #518 regression 席指出的不對稱：`MarkerParityMutationsData.swift` 早在表裡，它的姊妹檔卻不在——**而那一輪的 diff 就改了它**。

## `rawFile` 一般化的誠實結果

五個呼叫點掃完，**只有實例 1 是真靜默**：

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
| `census-parity.yml` 的 `run:` 指向不存在的檔 | **2** | **0** |
| `run-guards.sh` | — | **exit 0，零個 ✗** |

負控承重已反證：停用「檔案不存在」那個分支 → 32 掉到 31，且掉的正是該 case；還原回 32。

## 誠實邊界

**實例 3 無法在 CI 上驗證。** GitHub Actions 帳務擱置（CLAUDE.md 記載 runner 不啟動、`steps=0`），所以「job 現在到得了 `run-guards.sh`」這件事只由**讀 YAML ＋ 本機模擬**支持：三個 `run:` 逐一核對指向的檔都存在、YAML parse 通過、job 的 step 序列印出來看過。**沒有一次真的 CI 執行**。

**這個家族還有一個文件面的實例，本輪不修**：`CLAUDE.md:410` 用現在式寫「**現在**有守衛在量（`plugin/tests/trigger-coverage.py`）」，而該檔同在 `989ac64` 刪除。它不是 #521 造成的，掛在本 issue 的 commit 下會誤植歸屬——已在 #518 的 closing summary 與本 issue 的診斷具名。

**本輪刻意不動的**：掃描範圍（`*Data.swift` 是否納入）、`PATH_ROOTS` 白名單、`PROTECTED.count` 的 floor——那三項是 #522 的裁決，兩張共享 `TriggerCoverage.swift` 的同一道檢查，界線不守住會互相覆蓋。
