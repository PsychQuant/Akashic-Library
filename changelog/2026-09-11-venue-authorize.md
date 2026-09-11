# venue 的 `authorized` 有了判定型寫入面——而它不是 append，這是端到端測出來的（#554）

## #471 只修了一半

`Venue` 有兩個對 `names` 的互斥標記：`authorized`（對外形）與 `variant`（異寫）。#471 補了
variant 的寫入面。`authorized` 那一半原封不動：唯一寫入者是 `VenueBootstrap` 取第一個名字的
慣例，實測 479/479 筆恰是 `[names[0]]`（`addVenue` 則**不寫**，走 #227「建檔不機械偽造」）。

#553 讓它變尖銳：攣生合併把被併記錄的 authorized 降成倖存者的 variant，工具逐筆提醒，
但沒有面能改回來。

## Plan 的前提在真 binary 上死掉

Plan 照 `add_variant` 寫成 append。四條測試綠、負控紅。然後對副本跑 JRSS-B：

```
Error: 在書寫系統 latn 有 2 個 authorized（…）——那是未決的問題，不是指定；請選一個
```

`AuthorizedNames.validate` 有「**每書寫系統至多一個**」的內容約束。470 筆 venue 已有一個
latin authorized——對它們，append 第二個 latin 名**必被擋**。而那 470 筆正是立案事實。
**測試綠是因為 fixture 的 authorized 是空的**：它涵蓋了「尚無 authorized」與「跨書寫系統」，
剛好漏掉唯一重要的那格。

要換掉機械值需要**替換**：X 成為對外形、同書寫系統的舊指定 Y 降成 variant。命名回到
`authorize`——叫 `add_*` 會說謊。跨書寫系統（加中文刊名）仍是 append。

## 兩個判定一次說完，兩個都印

替換是兩個判定（X 是對外形、Y 是異寫）。報告的 `authorized` 與 `demotedToVariant` 各印
一個。Y **不刪**——它仍是這本刊的一個名字。X 若原本在 variant（被 #553 降過去的），從那個
分割移出：一個名字不能同時在兩個分割，而它現在是對外形。

**同一次呼叫把同一個字串既送 `add_variant` 又送 `authorize`**，是兩句矛盾的話——第一版
讓 `authorize` 那段後跑、靜靜贏了。改成入口拒絕。那是**輸入**驗證（呼叫端的兩個參數
矛盾），不是分割互斥的第二份副本（那仍由 `Venue.validate()` 擋、不重造，#471 的既有裁決）。

## 第二次端到端又紅——這次是我的 binary

改成替換語意後測試 7/7 綠、四個 mutation 負控乾淨，真 binary 卻說「authorized 含不在
names 內的名字」。隔離半天，最後是：**`swift test` 不重編 `akashic` executable target**，
`.build/debug/akashic` 是改 service 之前的版本。`swift build` 印 `Build complete! (0.17s)`
是快取；`swift build --product akashic` 花 3.31s 才是真的重編。

驗法：`grep -a -c '<這輪新加的字串>' .build/debug/akashic`——版號不會說謊但也不會說話，
新字串在不在才是證據。

## 落地

- `updateVenue` 加 `authorize: [String]?`；CLI `--authorize`、MCP `authorize`，兩面同批
- 7 條測試（append／冪等／矛盾拒絕／空白跳過／**同書寫系統替換**／**從 variant 拉回**／
  **跨書寫系統 append**），4 個 mutation 負控全部乾淨地紅
- `mcp-cli-parity` 的 `akashic_update_venue` 列補記，含「為什麼不是 append」

## 不做

479 筆的回填——那是 479 次「哪個名字對外」的判定，一輪 venue authorize campaign 的量級。
本 change 只開面。
