# 一個在自己的 issue 開著的期間又漂了一版的數字

2026-08-26，#408。

`plugin/.claude-plugin/plugin.json` 的 `description` 結尾寫著 **Store format 10**。
issue 立案時（2026-08-21）實測 store 已在 **12**——落後兩版。

**修它的時候實測是 13。** 也就是說：在這張 issue 開著、具名指出「沒有任何東西在比對
這兩者」的那五天裡，**它又漂了一版**。三次漂移、零次被發現。

## 為什麼是守衛而不是刪掉那個數字

issue 的 Expected 給了兩個選項，第二個是「不宣告版號」——理由是「若版號會漂移而沒有
東西檢查它，宣告一個過期數字比不宣告更糟」。那句話是對的，但它的前提（「沒有東西檢查」）
正是可以修掉的部分。

判準取自 #407：那一輪從 `Sources/` 拔掉四份寫死清單，理由是**那些副本沒有獨立價值**
（值域的唯一來源是 enum 自己）。這裡不同——marketplace 讀者藉這個數字知道這個 MCP
認得哪個 store 世代，而那是 description 第一行就該講的事。

**有價值的副本要接上唯一來源，沒價值的副本才刪掉。** 兩者都能消除分岔，選哪個看那份
副本本身值不值得存在。

## 守衛刻意不寫死 13

寫死就是製造**第三份**副本，而它會與另外兩份分岔——那正是本 repo 反覆記過的形狀
（CLAUDE.md 的「一份規格的兩個副本必然分岔」、`entity-backlink-completeness` 的表錯過
三次、耗時表在同一天內過期）。守衛從 `StoreVersion.swift` 現讀。

## 雙向負控

| 改哪一邊 | 結果 |
|---|---|
| plugin.json 改成 11 | ✗ 轉紅 |
| `StoreVersion.supported` 改成 14（模擬 bump 忘了同步）| ✗ 轉紅 |

第二個方向才是真正會發生的：**format bump 是主動行為，而 plugin.json 不在任何人 bump
時會打開的檔案清單裡**。

## 觸發點

pre-push ＋ `plugin-guards.yml`（**ubuntu 側**——它只讀兩個檔的文字，不需要 build，
不該啟動 10× 計費的 macOS runner）。兩個受保護檔（`plugin/**` 與
`Sources/AkashicStoreIO/StoreVersion.swift`）本來就在該 workflow 的 paths 裡。

`trigger-coverage.py` 實測零缺口，21/21 支守衛都有觸發點涵蓋。
