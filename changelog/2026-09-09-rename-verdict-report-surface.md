# rename／verdict 的報告面：把安靜的東西變成看得見的（#496 #490 #495 #498 #494 #488 #497 #492）

八張都在 `RenameReport`／`PersonRenameReport`／`ResolveReport` 這一族的**報告面**上。共同點是：
操作本身做對了，而它做了什麼沒有說出來。

## 三張 issue 的前提在做之前就已經過期

這一輪最值得記的不是修了什麼，是**三張 issue 描述的世界已經不存在**：

| # | issue 說 | 實際 |
|---|---|---|
| #490 | 「App 面是 `EntryViews.swift` 的 `describe`」 | #465 因為 `LocalizedError` 不能綁 MainActor 隔離的 `View`（Codex R2），已抽成獨立的 `RenameReportSummary` |
| #494 | 「person 腿只有 encode，沒有 `assertPersonWritable`」 | #463 的 DA-3 輪就補了；程式碼註解自陳「person 腿是 DA-3 補的」，連指定的三支測試都存在且綠 |
| #488 | 「`renameEntry` 沒有 organizations 迴圈」 | #463（PR #493）補了 |

**照 Expected 逐字實作會得到一個指向不存在檔案的守衛。** 這直接決定了 #490 的形狀：欄位清單
來自**反射**（型別是唯一來源），錨點找不到**必須紅而不是跳過**——一個「找不到就 return」的守衛，
在它最需要出聲的那一刻恰好會安靜通過。

#494 因此變成「查證後關閉」，#488 只留下它的 Expected（後置條件）。

## #495／#498／#497：三個欄位，三種「沒說出來」

- **#495 收攏丟列**：`migratedVerdicts` 遇到同 (field, value) 時 `changed = true; continue`——丟掉
  那一列而報告沒有欄位承載它。merge 側自 #461 起就有，rename 側是靜默的，而 #463 把這一面擴到
  organization 與 venue（7 個呼叫端），靜默的那一側跟著變大。描述用 merge 側**同一個**
  `describeCollapsedVerdict`：兩條路徑執行的是同一條不變式（store 永不持有重複 verdict）。
- **#498 持有記錄不帶 kind**：跨型別同名鍵實測 2 個。**不用 `"organization:some-org"` 字串形**
  ——那個記法在 verdict value 裡已經是另一個意思（`person:foo` 說的是「這條判定**是關於**誰」，
  而本清單說的是「**哪一筆記錄**被改寫」）。同一個記法兩個軸，是新的混淆而不是修好舊的。
- **#497 quarantine 邊界**：遷移網格只走 `load()` 解析得出的記錄。**刻意不掃 quarantine 檔的內文**
  找舊鍵——行級比對會漏掉被 YAML 折行的長 value（本 repo 量過的形狀）。「沒掃到」可以誠實斷言，
  「掃過且沒有」不行；那句全稱斷言（「無其他記錄引用此 key」）因此改成有條件的。

## #488 的後置條件：問結果，不問機制

三個遷移迴圈各自正確**不蘊含**整體正確。這一族「補了兩腿漏第三腿」漏了兩輪，而**逐腿的測試在
新的一腿長出來時不會紅**——因為沒有測試知道那一腿存在。

改成：遷移完的**整份**快照裡不得再有 (holderKind, oldKey) 的 verdict。在三個寫入閘之前跑，
失敗零寫入。負控（關掉 organization 腿）實測擲出具名錯誤：

```
inconsistentStore(action: "rename", issues: ["改名會留下 1 條指向舊鍵「old2020a」的 verdict…
這表示遷移少了一腿——請補上對應的 holder 迴圈，不要繞過本檢查。",
"  · organization「some-org」的 resolution-confirmed"])
```

**誠實邊界**：quarantined 記錄不在 `load` 裡，它持有的 verdict 既不會被遷移也不會被這條看到
——那是「讀不到」不是「已處理」。#464 的掃描掃既成事實，本條擋新增。

## 守衛立刻兌現

#490 落地之後，#495 與 #497 的新欄位**無法只加一半**——兩面反射斷言會紅。#498 的型別變更同理。

## #492：成功與部分成功用同一個回執

`reindexAndReload()` 失敗時改名**已經**寫進磁碟，而 `attempt` 的契約是「錯誤就是一句話」。
選 issue 兩個候選中的第二個（rename 走自己的錯誤路徑）：改 `attempt` 的簽名要動同檔 8 個呼叫點
去服務一個操作。警語放**最前面**（放最後會被四行摘要推下去、在短 alert 裡看不到），標題也變。
部分成功時選新 key——清單是舊快照所以顯示「找不到記錄」，那正是實情；停在舊 key 會顯示一筆
磁碟上已不存在的記錄，那是說謊。

## #496：format 閘不再借 `invalidKey`

`invalidKey` 的框架是「「<key>」不符合 `\A[a-z0-9][a-z0-9-]*\z`」。七個 format 閘借用它，於是對一個
**完全合法**的 key 說出一句假話。後果不只是難看：MCP 消費端讀到「不符合 regex」會去清洗 key，
而 key 沒有問題——問題是 store 的 format 太舊。

## 過程中的兩個自我更正

- 負控 runner 用 `grep -c '^Test Case.*failed'` 數失敗，而 **mutation 編不過時也回 0**——沒跑的
  守衛與通過的守衛輸出一樣。改成先驗 `Executed N tests` 存在。
- 用 `rfind("}")` 把測試附加到檔尾，落進了**另一個 class**。測試照跑照過，只有輸出裡的 class
  名字洩漏了。

兩件都是本輪一直在抓的同一個形狀：**檢查通過了，但通過的理由不是我以為的那個**。

PR #533。
