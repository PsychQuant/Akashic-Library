# 第七輪：借了 tokenizer，沒借它的紀律

2026-08-26。3/3 席 FINDINGS，20 個 findings、**3 個 CRITICAL**。base rate **7/7**
（52 → 5 → 6 → 5 → 5 → 19 → 20）。

## ① 部分成功：解不出的號被靜默刪除

R6 讓 `followUpstream` 回傳 `(values, parsed)`，用 `parsed` 決定要不要把原字串移出
`fields`。而多值路徑用的是 `normalizedUniqueQualified(...).values` —— **`.values` 這個
accessor 把 `unparseable` 整個丟掉**。

於是「一個 token 解得出、另一個解不出」時 `parsed` 為 `true`，原字串被整個移除，
**解不出的那個號從 store 徹底消失**。

### 根因不是「沒想到」，是「借了一半」

同一個 helper 的另一個呼叫端對這個形狀有**明文裁決**，逐字寫在 `IdentifierMigration`：

> 全部 token 都解析失敗以外的情形：只要有任何一個 bad，就**不移除殘留**
> ——殘留是那些解不了的值唯一的棲身處。

而我在 R5 的註解裡寫「走 `IdentifierMigration` 既有的 tokenizer……這裡沒有理由再造一個」
—— **我借了 tokenizer，沒借這條紀律**。

**那個裁決不在函式簽章裡，在它旁邊的註解裡。** 重用一段程式碼時，真正要一起重用的
往往是那些寫下來的裁決，而它們不會跟著型別系統走。

頻率差讓它更嚴重：`migrate-identifiers` 只跑一次，`import-zotero` 是**預設的匯入面**，
新建與更新兩條路徑都走這裡。

## ② 第四份副本在另一個 repo，而那才是使用者看到的那份

R6 把 DECLARERS 從兩份補成三份，changelog 標題寫「副本有三份不是兩份」。

第七輪實測有**第四份**：`psychquant-claude-plugins/.claude-plugin/marketplace.json`，
仍寫 **10**（差三版）。那段 description 與 `plugin.json` **逐字相同、只有數字不同**。

**最尖的地方是它與守衛自己給的理由直接矛盾**：DECLARERS 第一列的註解寫 plugin.json 是
「marketplace 顯示」—— 而 `/plugin marketplace` 顯示的是 marketplace.json。
**我保護的兩份都不是使用者看到的那份，而使用者看到的那份是壞的。**

跨 repo 讀不到，但「讀不到」不等於「可以不提」。成功訊息現在具名說出涵蓋不到什麼。

## ③ merge blocker 我只記錄、沒解除

第六輪抓到 #428 的守衛寫死 `AkashicApp/Sources/EntryViews.swift` 而 #429 搬走它。
我把它記在兩個 PR 的 Blocking comment，然後在總結裡寫「最重的三條全部已修」。

**那句話不精確**：三條裡有一條我只是**記錄**了。第七輪的 DA 席實際 merge 後跑測試，
拿到 `NSCocoaErrorDomain Code=260`。

修法是 `Surface.path` 收候選清單（擇一存在者），而不是改成新路徑 —— 後者會在
merge 順序反過來時再壞一次。

**比一條紅測試更糟的那半**：紅了之後最省事的修法是把 App 那一列刪掉，
而三個讀取面的守衛就靜靜退回兩個。錯誤訊息因此明寫「**不要刪掉這一列**」。

## 一個附帶的量測（#431）

使用者問「為什麼這個要跑很久」，量下去發現：

| | 秒 |
|---|---|
| `PrePushHookTests.testHookScrubs…` | **3165.7** |
| 其餘 2212 支加總 | **≈193** |

**一支測試佔套件的 94%。** 已開 #431。

而它立刻有了用處：本輪用 `swift test --skip PrePushHookTests` 拿到 **209 秒**的回饋
（而非 55 分鐘），涵蓋面不變 —— 被跳過的那一格由 push 時的 pre-push 接住（它就是在
測那個 hook）。**沒量過的話，「跳過一支測試」只是抄近路。**
