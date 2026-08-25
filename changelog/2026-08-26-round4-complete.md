# 第四輪收尾：三個「跟隨上游」的方向，以及一個負控找到的空守衛

2026-08-26。第四輪 verify 的 5 個 HIGH 全部修完。前兩條記在
`2026-08-26-whitelist-was-the-wrong-category.md`，本篇記後三條。

## ③ App 是第三個讀取面——而它根本編譯不過

`entity-backlink-completeness` 執行細節 2 明文列 CLI／MCP／**App**。我修了兩個。

驗證時才發現更深的事：

```
$ xcodebuild -scheme AkashicApp build
EntryViews.swift:65: error: 'WorkType' does not conform to 'StringProtocol'
** BUILD FAILED **
```

**App 從 #325 起就編譯不過**（該行最後一次改動是 #181，遠早於 #325）。而
`swift build`／pre-push／`ci.yml`／14 支 plugin 守衛——**四道防線一個都不涵蓋它**
（它是獨立的 xcodeproj，不在 `Package.swift` 裡）。

**一個編不過的 target，它顯示什麼都不會有人注意到。** 「沒有覆蓋」這件事另開 #427；
那一行依 Step 4 的「前置依賴」先修，否則驗不了自己的改動。

### 守衛問了 entity kind，沒問 surface

`EntrySurfaceTests` 第一版只讀 `AkashicService.swift` **一個檔**。它的 doc comment
自己寫著「修 venue 那次我沒有問『這一族還有誰』」——而本輪對 entity kind 問了、
對 **surface** 沒問。**同一個形狀第三次重演**。

改成逐面檢查（三個面的慣用寫法不同：service 與 App 讀 `entry.<欄位>`，CLI 讀 JSON 鍵）。

**誠實邊界**：守衛讀的是**原始碼字面**，不是編譯。它抓得到「忘了顯示」，
抓不到「顯示了但編不過」。

## ④ 「有就跟隨、沒有就保留」不是一個立場

把 doi/pmid/isbn 提升進結構化欄位時只寫了 `if let`——於是 Zotero 這次沒給時值原封不動。
那既不是 follow（`fields` 是整份替換）也不是 preserve（`venues` 與 `authors` 各有
**顯式**的守衛與回報），**而且沒有一行程式碼說那是刻意的**。

後果是**過期值安靜留著**：使用者在 Zotero 清掉一個掛錯篇的 DOI，重跑 pull 之後 store
仍帶著它，而 `export-bib` 繼續印、`import-wos` 拿它當身分證。

改成兩個方向都跟隨——那是**恢復**提升之前的行為（DOI 住 `fields` 時整份替換本來就會
清掉它）。同時把 `fieldsRemovedByPull` 這個既有回報通道接回來：識別碼搬出 `fields`
之後，那個減法看不到它們，於是同一件事從有回報變成零回報。

**本輪 4 個修復裡，那是唯一拆掉既有回報通道的一個。**

## ⑤ 寫入仍在守衛之前

R3 為 venue 寫入具名過這個形狀（「一次失敗的部分寫入會讓兩邊都不對」），
而形狀升級這一格當時沒跟著改：順序仍是「升級寫檔 → load → 守衛」，於是守衛擋下時
**檔案已經被改過**，而 `report`（含 `shapeUpgraded`）隨例外被丟棄。

改成**一律模擬、守衛過了才寫**。乾跑與 apply 因此走同一條路徑，差別只剩最後那一步。

## 負控找到一個空守衛

移除那個寫入區塊之後，**沒有任何測試會紅**——「守衛擋下時不該寫」的測試不會紅
（本來就沒寫），而「apply 應該要寫」的測試**不存在**。

也就是說我剛加的區塊在**正向上完全沒被測到**。補上斷言之後雙向都有守衛：
移除寫入 → 一支紅；把寫入移回守衛之前 → 另一支紅。

**這是負控第一次抓到「守衛本身是空的」**，而不是「守衛的判準錯了」。

## 今天累計的六種「測試沒測到它以為在測的東西」

1. fixture 用了形狀不合法的值（`10.1/abc`）
2. mutation 粒度太粗（把兩個獨立修改綁成一個）
3. mutation 沒有真的改變行為（只改 `.map` 來源）
4. 因果鏈被截斷（`==` 失敗就不寫檔，於是殘留測不到）
5. 守衛判準太窄，對**正確實作**報紅（canonical accessor）
6. **mutation 只替換了第一個出現處**（`entry.canonicalDOIs` 出現兩次）
7. **守衛在正向上是空的**（移除被守衛的行為，沒有任何測試會紅）

前四種讓守衛漏，第五種讓守衛誤傷，第六種讓**負控**失效，第七種讓守衛從一開始就沒有內容。
