# 最後兩支 harness 遷完：生成腳本自我驗證抓到兩個會靜默的抽取缺陷

2026-08-27，#433 收尾（16/16）。`audit-guards-mutations`（835 行、52 個 case）＋
`oracle-precondition-control`（190 行）。兩支**必須同輪**：後者 monkey-patch 前者的
`with_copy`。

## 讓生成腳本自我驗證，而不是小心一點

52 個 case 的 mutation 字串以 `ast.literal_eval` 機械抽出——前三支 harness 已經用過這個
手法。這一次多做一件事：**抽出的 edits 套用結果必須與原 lambda 逐字相同**（`import` 該
模組、拿真檔案當輸入）。

那道驗證當場抓到兩個缺陷，而兩個都會安靜通過：

| 缺陷 | 為什麼安靜 |
|---|---|
| **丟掉 `count` 引數** | Python 的 `str.replace(old, new)` 換**全部**，帶 `count=1` 才換第一個。5 個 case 換錯範圍 |
| **鏈式 replace 只抽最外層** | `t.replace(A,B).replace(C,D)` 的第一個被丟掉。2 個 case 注入不完整，而守衛照跑、只是不紅——**失敗訊息看起來像「守衛對它是盲的」** |

第二個是差分測試先抓到的（Swift 版某格報「沒指名」），第一個是我為了修它而加自我驗證時
一併浮出來的。**手抄的錯誤率不可接受，而「更小心地手抄」不是解法**——把驗證加進生成器才是。

## per-path 分組：Python 只檢查「整體」有沒有改到東西

`edits` 是 `{path: fn}` 而 `fn` 可以是鏈式的，所以它檢查 `fn(before) != before`。抽取展開成
多個 edit 之後若逐步檢查，一個 no-op 的環節（實際存在：有一格 `a == b`）就會誤報「這個
case 無效」而整格消失。

## monkey-patch 換成環境變數 ＋ subprocess

Swift 沒有 monkey-patch。「可注入的 `withCopy` 參數」是更直接的對應，但 `main()` 的輸出要被
捕捉，那就得把 harness 裡所有 `print` 改成可注入的 sink——一次波及整支的重構，換到的東西
與 subprocess 相同。而 subprocess 跑的是**真的出貨路徑**。

三個變數（`AKASHIC_POISON_GUARD` / `AKASHIC_POISON_BASELINE` / `AKASHIC_SKIP_CASES`）
必須：帶 `AKASHIC_` 前綴、在被注入處具名、**未設定時完全沒有行為**。第三點有實測——
未設定時輸出與 Python 版逐位元相同。否則它們就是藏在出貨路徑裡的後門。

## 資料化引入一個自指缺陷

`zero-instance-rows-audit` 掃 `Sources/**/*.swift` 找編號，而其中一個 mutation 的內容正是
「一個刻意不存在於 `Sources/` 的編號」（`#9999`）——資料化之後那個編號**真的出現在
`Sources/` 裡了**，於是守衛說「找得到實作」而它只找到自己的測試資料。

兩版都改成排除由腳本生成的資料檔。判準是**結構的**（檔頭的生成標記）而非列舉檔名——
列舉會與下一個生成檔分岔。

## Step 5 前半：三個 case 退場，代價寫出來

它們注入的是守衛自己的 `.py` 原始碼。改用子命令跑之後那個注入不被讀——**在改 `guardRel`
的那一刻就失效，與刪不刪檔無關**。全 Swift 之後 source injection 結構上不可能（要改
compiled binary 就得重編譯，而 harness 在 temp copy 裡 build 整個 package 不可行）。

其中一個是 `PAIRED_IDENTICAL` 的一半，所以那一組不變式檢查（#413 的「理由欄的提及不得
改變任何事」）**一併失去**。負控 54 → 51 格。

## 一個我犯的錯，記在這裡

用 regex 批次移除三支 harness 的「跑 Python 版並比對」時**刪過頭，吃掉了函數的閉合**——
樹一度編譯失敗，而那會讓 22 支守衛**全部跑不了**。已還原。那三處要逐一精確改，不能批次。

Step 5 的後半（移除兩版並驗 → 刪 16 支 `.py` → `guard-python-compat` 退場）因此還沒做。
