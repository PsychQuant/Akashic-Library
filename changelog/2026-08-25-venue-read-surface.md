# 寫進磁碟 ≠ 看得見——venue 讀取面的兩個缺口（#394 verify）

2026-08-25 上午。使用者自己發現的：`akashic venue psychological-methods` 不顯示 ISSN，
而磁碟上明明寫著 `issn: [1082-989X]`。ensemble 把它列為 MEDIUM，實際上它是一族的兩個。

## 缺口一：ISSN（39 個 venue）

§8 的遷移把 ISSN 從 work 移到 venue，**寫入面做完了、讀取面沒動**。於是：

```
$ akashic venue psychological-methods --json | jq keys
["authorized","key","names","type","workCount","works"]     ← 沒有 issn
$ grep -A1 '^issn:' <該 venue 的 yaml>
issn:
- 1082-989X                                                  ← 磁碟上有
```

**「庫裡有這個號」與「查不到這個號」在使用者眼中完全一樣。** 這是
`lossless-intake` 執行細節 3 的形狀換一個位置：那條說「丟棄必須可見」，這裡是
「持有必須可見」——兩者的失敗都是**輸出無法區分兩種不同的世界狀態**。

## 缺口二：resolution verdict（person 早就有，venue 沒有）

補 ISSN 時順手比對 person 那面，發現它有一個 `verdicts` 鍵——`references` 的投影
（`entity-backlink-completeness` 第 13 條邊）。venue 的 verdict 落在**被判定的 venue
記錄**上，同一條邊、同一個機制，而讀取面沒有那一格。

補上之後：

```
psychological-methods（periodical）
  ISSN：1082-989X
  歸戶判定（8）：
    [resolution-confirmed/stale] 「Psychological Methods」← bockenholt2001hierarchical
    …
```

`observed`／`stale` 的判定與 person 同構，只是看的邊不同：person 看 `authors` 還在不在，
venue 看 `venues`。8 條全是 `stale` 是**正確的**——判定已套用，literal 已升格成 key。

## 真正的修法不是補這兩個欄位

補欄位只解決已知的兩個。**沒有任何東西在問「型別有的，讀取面給了嗎」**——下一個
新增的 venue 欄位會再漏一次。

所以加 `VenueSurfaceTests`：反射取 `Venue` 的全部序列化欄位，逐一要求
`venue(key:)` 讀到它，或落在**具名附理由**的封閉豁免集合（目前只有 `id`：內部 UUID
身分，任何 entity 的讀取面都不輸出）。這是 `StoreHealthSurfaceTests`（#263）的同一
個模式，理由也相同：人工清單會與型別分岔。

**CLI 與 MCP 兩面同源**，所以補在 service 的 payload 就兩面都有——`entity-backlink-completeness`
執行細節 2 要求的「一個 entity kind 的讀取面只能有一條實作路徑」在 venue 這格本來就成立。

## 守衛自己踩過的三個坑（全部記下來）

**一、`record.key` vs 查找用的 `key`。** 守衛第一次跑就報 `Venue.key 沒有被讀到`
——因為 payload 用的是使用者輸入的區域變數。今天兩者必然相同（精確比對），但輸出
該反映**記錄**而不是輸入；若查找哪天放寬（大小寫、正規化），回顯輸入會讓使用者
以為庫裡存的是他打的那個寫法。改成 `record.key`。

**二、`.prefix(4500)` 的魔術數字在同一輪內就失效。** 加上 verdicts 投影之後
`record.unknownFields` 掉出視窗，守衛開始報一個**不存在的**缺口。改成括號配對取
完整函式 body。**假紅比漏報更貴**——維護者會學會「這支有時候會紅」，而那個習慣會
套用到所有守衛（`zero-instance-guards` 第 6 列的立場）。

**三、第一次負控是假的。** 我把 `record.issn.map` 改成 `[String]().map` 就宣稱做了
mutation，而 `if !record.issn.isEmpty` 那行仍含 `record.issn`，子字串比對照樣命中
——守衛沒紅，而我差點把它讀成「守衛不靈」。真正的負控是移除**整個區塊**：那時它
正確轉紅。

順帶加了「守衛的守衛」：斷言括號配對真的停在函式結尾（`body` 不得含下一個函式的
簽章、不得是大半個檔案）。吃過頭的話，別的函式偶然提到 `record.<field>` 就會讓整份
守衛 vacuous pass——那正是它要防的形狀，只是換到自己身上。

## 一個插錯位置的編輯（沒造成損害，但值得記）

還原負控時，我用 `if !record.unknownFields.isEmpty {` 當錨點插回 ISSN 區塊——而那個
字串在檔案裡**不只一處**，`replace(..., 1)` 把它插進了 `person(key:)`。編譯**立刻**
失敗（`value of type 'Person' has no member 'issn'`），所以零損害。

記在這裡是因為它與本篇主題同形：**一個看起來夠特別的錨點，沒有被驗證是唯一的。**
後續的編輯改用「錨點必須唯一」的斷言（`assert t.count(anchor)==1`）。

## 尚未修

`Organization` **完全沒有單筆讀取面**——只有 `add-organization` 與
`resolve-organizations`。所以 `ror` 不是 payload 漏欄位，是整個面不存在。補它要先走
`mcp-cli-parity` 的兩面裁決，屬於另一個變更。
