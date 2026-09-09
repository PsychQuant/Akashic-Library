# venue variant 家族：寫入面、severity、降級指示、顯示名回退（#471 #472 #473 #474 #475）

#422 verify 留下的六張裡的五張。第六張（#476）**刻意不做**——它的前置「取得刊頭或官方沿革」未
成立，改版年份目前是從 URL 路徑 `bulletin_ns/20073/` **推**的，不是查到的。

## #472 —— 遷移的「下一步」是一道降級指示

三支遷移各自寫死自己那一代的目標（`migrate-person-identity` 10、`migrate-venues` 11、
`migrate-venue-variants` 14）而**從不讀 marker**。store 今天是 format 16，所以無條件印「手動把
format 改成 14」是一道**降級指示**：format-14 binary 讀到帶 `field: paginated` 的 venue 會整檔
quarantine（#422 verify DA 6 實測 406 → 373、rc=0）——照做等於手動重新開啟 format 15 存在的理由
所要防的那個安靜失敗。

`StoreVersion.bumpHint(target:current:)` 三種回覆分得開：**要升**／**不要改它**（並說出為什麼調
回去會壞）／**讀不到**（marker 壞了——那時不猜，把決定交回人）。

**issue 只點名兩支，第三支（`PersonIdentityMigration`）同型**——`no-compat-fallback` 記過
「同型缺陷成對出現，而 issue 只記了先被看見的那一個」。三支一起改。

測試釘住兩件事：今天的 store 上四條分支一條都不得印「改成 10」；三支的目標**都低於 supported**
——那是缺陷的前提，釘住它讓「哪天某支追上 supported」時有人看到。

## #473 —— 孤兒 `variant` 提到 error

先前是 warning 而同一段註解宣稱「同 `authorized` 的既有立場」，而那邊是 error。**不是註解說謊
就是程式說謊**，而註解說的原則是對的（兩個分割都是**對 `names` 的標記**）。

第二個理由更硬：`VenueResolver.resolve` 的提名**只從 `names.entries` 建 aliasMap**，所以提名正確性
依賴 `variant ⊆ names`；而 `writeVenue` 只擋 error——warning 級的話孤兒寫得進去、提名靜默少一個
候選。實測 live store 孤兒 variant **0 筆**，提級不拒絕任何既有記錄。

**decode 期 vs 寫入期的不對稱：記下差異與後果，不替它發明原則。** person 的分割互斥在 decode 就
fail-closed（整檔 quarantine），venue 的兩條都在寫入期。後果不同——decode 期拒絕會讓那筆 venue
從目錄裡**整個消失**，而一個分割標錯的 venue 仍然是一本可用的刊物。本輪不統一。

## #471 —— `variant` 的寫入面

在此之前 variant **兩面都沒有寫入面**，唯一的寫入者是遷移——而它用的是「`authorized` 的補集」。
**一個不做判定的操作成了唯一的判定寫入者**，正面撞上 `identity-is-judged-not-matched`：
「這個名字是那個名字的異寫」是判定，不是「不在對外清單裡」的推論。

依 `mcp-cli-parity` 選 Expected 1（補兩面）而非 2（記有理由缺席）——缺席的理由只會是「還沒人要」，
而那個缺席本身正在製造錯誤的判定。**不在 `names` 的一併 append 進 `names`**：與其讓呼叫端先
`add_names` 再 `add_variant`（兩步之間有一個不一致的狀態），不如一次做完。

分割互斥與孤兒檢查由 `Venue.validate()` 擋，寫入面**不重造一份**。

## #475 —— 顯示名的回退

`TimelineOf.current` 在全段無 `start` 時取的是**序列化最後一筆**——那是實作細節，沒有人裁決過它
該當顯示名。實測三筆 unclassified venue 因此顯示成「維基百科」「SEP」「…Academia Sinica NEW SERIES」。

裁決候選 (b)：取**序列化第一筆**。理由不是「第一筆比較好」，是**它是唯一一個有人選過的位置**
——`add-venue --names A B` 的 A 是使用者先打的那個，而 `VenueBootstrap` 建檔時設
`authorized: [names[0]]`。**時間軸真的帶沿革時仍走 `current`**——那時「當前有效名稱」是關於世界的
事實，不是排列的副產品。

修後實測：SEP → `The Stanford Encyclopedia of Philosophy`、bulletin →
`Bulletin of the Institute of Mathematics, Academia Sinica`。

## #474 —— `zero-instance-guards` 的第三類

顯式擴入「保留位置的 Requirement」並加第 22 列。**失敗的意義是第三種**：

| 類 | 失敗長什麼樣 |
|---|---|
| 守衛 | 漏報 |
| 欄位 | 模型說了一句它沒打算說的話 |
| **Requirement** | **有人把它當死重刪掉**，然後那個形狀到達時沒有位置可落 |

保留而不刪的理由是那個現象是真的（JRSS Series B／C、bulletin 新舊系列都是 store 今天表達不了的
實例）；零實例的成因也具名：異寫法佔著它的位置。實測 venue 406 筆、`names` 帶時間欄位 **0** 筆。

PR #537。
