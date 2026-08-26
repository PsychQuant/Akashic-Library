# 第一支守衛改用 Swift：遷移紀律暴露了一個既有的分岔

2026-08-26，#433 A 批 1/3。`zero-instance-rows-audit`（70 行，最小的一支）。

## 為什麼要遷移

hook、CI、開發終端機**各自解析到不同的 Python**（系統 3.9.6／homebrew 3.12+／
Xcode 帶的 3.9／外層 pre-push 的 3.13）。我在守衛裡寫了多行 f-string（PEP 701，
3.12+），它在**每一個我手動驗證的環境都通過**，只在 hook 的內層是 `SyntaxError`
——三次 push 失敗、三個被自己量測推翻的假設、約三小時排除法。

使用者裁決（2026-08-26）：改 Swift，Python 版打 tag 保留。

## 四步紀律走完

| 步 | 結果 |
|---|---|
| 1. 乾淨樹同 verdict | ✅ **輸出逐字相同** |
| 2. 既有負控下兩版都紅 | ✅ |
| **3a. 同一批 mutation 逐一比對** | ✅ 四個 mutation，輸出**全部逐字相同** |
| **3b. 各自對照明說的契約** | ✅ 契約與三條誠實邊界逐字搬進 Swift doc |
| 4. 刪 Python | ⬜ **整批通過後**（oracle 要能跑，不只能取回）|

## 3a 暴露了一個**既有的**契約／實作分岔

mutation「把某列引的編號改成 `Sources/` 裡沒有的」→ **兩版都綠**。

查了才明白：那一列引用**多個**編號，而實作是「**全部**都找不到才算失敗」
（`len(absent) == len(issues)`）。而契約寫的是**單數**：

> 那個編號必須出現在 `Sources/` 底下

**兩版一致地給了同一個答案，而那個答案照實作是對的。**

這正是 radical translation 那一節（#433 的方法論註記）在講的事：
**stimulus-synonymy 建立起來了，但它不告訴我判準本身合不合理** —— 若 Python 版的
判準有缺陷，Swift 版會忠實地複製它。

**而第 3b 步是唯一問得出這件事的步驟。** 只做 3a（比對行為）的話，這個分岔會被原封
不動搬進 Swift 而沒有人知道。**遷移不引入它，但它是唯一會讓它現形的時刻。**

本次選擇跟隨**實作**並在註解裡保留契約原文，讓落差看得見。

## 骨架

單一 `akashic-guards` executable ＋ 子命令（21 個 target 太重）。

- **無依賴** —— 守衛要能在一個建不起來的樹上仍然跑得動
- **未知子命令回 64，不預設通過** —— 打錯的名字若靜默回 0，`run-guards.sh` 會照樣
  往下跑而那一格等於不存在
- **`repoRoot` 由 cwd 決定**，不寫死 —— #433 的 oracle 比對要在 worktree 裡跑

## trigger-coverage 要補三處，而我一開始就查了三處

它以**檔名**辨識守衛，而 Swift 版是子命令。三個讀取路徑各補一次：

1. `HOOK`（純子字串比對）
2. workflow 的**直接**呼叫（`invoked()` 解析 `run:` 行）
3. 經 `run-guards.sh` 的**間接**呼叫

**#432 就是因為只改對一種而讓 CI 側漏了 90 格。** 那次的教訓在這次生效了 ——
不是靠記得，是靠**把「同一個 indirection 有幾種讀法」當成第一個要問的問題**。

翻回 `X.py` 而非新增 Swift 清單：`plugin/tests/X.py` 在整個遷移期間都是那支守衛的
**身分**，直到它被刪除。刪除後這行對它自然失效，而 `GUARDS` 也不再列出它 —— 不留孤兒。

## 附帶：`| head -1` 又吞了一次 exit code

驗證「未知子命令不預設通過」時看到 `rc=0`，以為守衛沒生效。實際是 `head -1` 回報的是
管線最後一個命令。真實 rc 是 **64**。

**今天第三次踩同一個坑**（`| tail -5` 吞過 push 失敗、`| tail -2` 讓我漏看 88 個缺口）。

---

## A 批 2/2：`decision-matrix-drift`（171 行）

同樣走完四步。**六個情境**（乾淨樹 ＋ 五個 mutation）輸出**逐字相同**。

### 逐字相同不是免費的

首次比對時 exit code 五個全對，但**失敗路徑的格式有差**：

| Python | Swift（第一版）|
|---|---|
| `['不跑（現況）']` | `["不跑（現況）"]` |
| `('--no-verify', '不跑', '主repo')` | `"--no-verify\|不跑\|主repo"` |
| `None` | `nil` |

取捨很實：

- **放寬成「rc 相同 ＋ 我看訊息實質一致」** → 把 judgment 帶回 oracle。而今天反覆
  證明 judgment 會讓錯誤通過（三個假設全部被自己的量測推翻）
- **讓 Swift 逐字模仿 Python 的 repr** → oracle 保持**機械**（一個 `diff` 就是判定），
  但 Python 刪掉後那個格式沒有存在理由

選後者，**並寫下退場條件** —— 那正是 `no-compat-fallback` 要求的形狀：

```
ls plugin/tests/decision-matrix-drift.py 2>/dev/null | wc -l   # → 0 即可刪 pyList/pyTuple
```

### 一個 Swift 沒有內建等價物的地方

Python 的 `f'{s:<n}'` 對**全形字元**按碼點數補空白。Swift 沒有這個行為，而
「看起來對齊」不夠 —— 第 3a 步要求逐字相同。所以 `pad()` 逐字複製那個語意
（`s.count` 而非顯示寬度）。

**這類差異只有在要求逐字相同時才會浮出來。** 若當初放寬成「實質一致」，
這個對齊差異會被當成無關緊要而留著 —— 然後在下一支守衛的比對裡變成噪音。

### A 批完成，而它只有 2 支不是 4 支

原判準（「grep 不到 `subprocess`」）**量錯了東西**。正確的問法是「它依賴 Python 的什麼」：

| 依賴形態 | 例 | 可遷移？ |
|---|---|---|
| 只用 Python 當實作語言 | `zero-instance-rows-audit`、`decision-matrix-drift` | ✅ |
| spawn Python 當**被測對象** | `guard-python-compat` | ⚠️ 遷移後**退場**，不是改寫 |
| **`exec` Python 原始碼**當 oracle | `literal-scalar-parity` | ❌ 要先改被守衛的對象 |

`literal-scalar-parity` 的 oracle 是「把 `literal-census.sh` 內嵌的 `_scalar` 抽出來
`exec`」。Swift 版只有兩條路，兩條都不能走：spawn Python（把版本依賴搬回來）或
重打一份（違反那支守衛自己的契約：「一份規格的兩個副本必然分岔」）。

**`exec` 一段 Python 原始碼比開子行程更深地綁在 Python 上，卻不會被那個 grep 抓到。**
