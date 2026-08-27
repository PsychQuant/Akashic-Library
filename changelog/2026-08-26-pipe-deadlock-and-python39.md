# 三次 push 失敗、三個被推翻的假設，根因是兩行

2026-08-26。#428 的 push 連續失敗三次，每次都掛在
`PrePushHookTests.testHookScrubsRepositoryLocalGitEnvironmentAndRunsWarningsAsErrors`。

## 我提出的三個假設，全部被自己的量測推翻

| 假設 | 怎麼被推翻 |
|---|---|
| push 期間我編輯了檔案 | 第二次工作樹**全程乾淨**，仍失敗 |
| 某支守衛在 HEAD 上是紅的 | **21 支全綠**，含兩支最慢的（1648s／958s） |
| 並發／暫存目錄碰撞 | **完全乾淨的機器**，仍失敗 |

三次的耗時各不相同（**2857／911／1173 秒**），而確定性缺陷不會這樣表現 ——
那個變異本身把我推向錯的方向三次。

## 真因一：pipe 死鎖（讓症狀無法診斷）

```swift
process.standardOutput = Pipe()
process.standardError  = Pipe()
```

**而測試從不讀那兩個 pipe。** 實測：

| | |
|---|---|
| macOS pipe buffer（`sysctl net.local.stream.recvspace`） | **8192 bytes** |
| hook 實際輸出 | **29714 bytes** |
| 測試讀取 pipe 的次數 | **0** |

hook 寫滿 8 KB 就**阻塞在 write**，測試在 `waitUntilExit()` 等它 —— 互等。

這解釋了為什麼**內層 hook 的輸出完全不出現在任何 log 裡**：它在那個沒人讀的
pipe 裡。也就是說，**症狀本身把診斷所需的資訊藏了起來**。

修法是在 `waitUntilExit()` **之前**先 `readDataToEndOfFile()`，並在失敗時把 hook 的
輸出印進 assertion 訊息 —— 那一步讓下一次診斷從三小時變成一次執行。

**它以前會過**：hook 的輸出隨守衛數量成長（現在 21 支），在某個時點越過 8 KB。

## 真因二：我在 R8 寫了 Python 3.12 才有的語法

修好 pipe 之後測試**真的跑完了**（993 秒），而 993 ≈ 我掃描裡
`trigger-coverage-mutations` 結束的 981 秒 —— 也就是掛在**下一支**。

```
$ PATH=/usr/bin:/bin python3 plugin/tests/measured-claims-audit.py
  SyntaxError: EOL while scanning string literal
```

`PrePushHookTests` 把 `PATH` 設成 `/usr/bin:/bin` —— 那裡的 `python3` 是 macOS 內建的
**3.9.6**，而我的終端機是 homebrew 的 **3.12+**。我在 R8 為了修「散文計數」那個負控
寫了**多行 f-string**（PEP 701，3.12 才有）。

於是有一個完全安靜的失效模式：**守衛在我的終端機永遠通過，在 hook 裡是 SyntaxError。**

## 兩件事值得單獨記

**一、排除法讓我一直在觀察行為，而缺陷在結構裡。** 三個假設各讓我跑一個更貴的實驗
（重跑守衛 59 分鐘、清空機器再推 30 分鐘），而**沒有一個讓我去讀那六行測試碼**。
答案從第一次失敗起就在檔案裡。

**二、我為 #431 量的那個數字是錯的。** 我量到那支測試「3165 秒、佔套件 94%」並據此
開了 issue —— 而那不是它在做事，**是它在等一個永遠不會清空的 buffer**。修好之後
它是 993 秒（在真的跑守衛）。#431 的前提因此要重算。

## 新守衛：`guard-python-compat.py`

每支守衛都必須在 **hook 實際使用的那個 Python** 下解析得過。實測目前 16 支全過
（我那兩行是唯一的破口）。

**它刻意只做便宜的那一半**：`py_compile` 保證解析得過，不保證執行期相容
（3.10+ 的 stdlib API 仍可能在 3.9 下跑掛）。那要靠實際執行才抓得到，
而實際執行 21 支要一小時 —— 限制寫在檔頭。

負控：注入一個多行 f-string 的 probe → 轉紅。觸發點：pre-push（**最先跑**，它便宜）
＋ `plugin-guards.yml`。`trigger-coverage` 零缺口。
