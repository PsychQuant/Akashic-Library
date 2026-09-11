# venue 的 `authorized` 有了判定型寫入面——而它不是 append，這是端到端測出來的（#554）

## #471 只修了一半

`Venue` 有兩個對 `names` 的互斥標記：`authorized`（對外形）與 `variant`（異寫）。#471 補了
variant 的寫入面。`authorized` 那一半原封不動：唯一寫入者是 `VenueBootstrap` 取第一個名字的
慣例，立案時實測 479/479 筆恰是 `[names[0]]`（494 筆 venue，#553 合併前；合併併掉 9 組後
485 筆、470/470——兩個數字是同一件事在兩個時點，不是「9 筆非拉丁 authorized」）。
`addVenue` 則**不寫**，走 #227「建檔不機械偽造」。

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

要換掉機械值需要**替換**：X 成為對外形、同一個 `WritingSystem` 的舊指定 Y 移出。命名回到
`authorize`——叫 `add_*` 會說謊。不同 `WritingSystem`（han／latn／other）之間仍是 append。

## R1 verify：我替呼叫端多說了一句話

第一版把 Y **降成 variant**，理由是「跟 #553 合併端對稱」。R1 verify（5 席，Codex 429 缺席）
的 DA 席指出這句話的問題：呼叫端只說了「X 是對外形」，程式卻寫了兩句——X ∈ authorized、
**Y ∈ variant**。第二句是程式推論出來的分類判定，而 `venue-entity` spec 明寫「A name in
neither is unclassified … it makes no claim either way」——未標才是誠實狀態。這與 #554
立案時對 #553 的原始指控（「改變的是分類」）同型、反方向重演。

DA 還實測了一個零實例的形狀：沿革前身（`names` 帶 `start`／`end`）被 `--authorize` 後繼刊名
→ **整個呼叫被拒**（variant 不得帶時間欄位）且無出路。zero-instance 第 22 列保留沿革就是
為了讓它有位置可落，而第一版把「後繼名成為對外形」這一步堵死了。

**裁決（使用者 2026-09-12，D1）：Y 移出 authorized、留在 names、不標 variant。** 報告鍵從
`demotedToVariant` 改成 `authorizedRemoved`——說程式做了什麼，不說結果是什麼分類。

同一輪的 HIGH 是我自己的禁令再犯一次：對「同一字串既送 `add_variant` 又送 `authorize`」
我寫了「不能讓哪段先跑決定誰贏」並在入口拒絕，但**同一參數內**兩個同 `WritingSystem` 的
名字沒擋——迴圈第 N+1 輪把第 N 輪剛升上去的當舊指定移出，陣列順序決勝，報告
`authorized: [A, B]` 而 `authorizedTotal: 1`。四席各自在真 binary 重現。修法同型：
先 trim、再按 `WritingSystem.of` 分組，任一桶 >1 整批拒絕零寫入。

## 報告每個分類改變都說出來

`authorizedAdded`（升）／`authorizedRemoved`（移出，未標）／`liftedFromVariant`（從 variant
拉回——本面的主要用途，第一版沒報）／`alreadyAuthorized`（no-op，但與「空白被跳過」分得開）。
`lossless-intake` 執行細節 3：分類的改變要可見。

**不留 judgement**（D2）：與 person `authorize-names`（#81）、`add_variant`（#471）一致——
三個名字分類面要不要留、留什麼形狀一次裁（#564），本 change 不在這裡單獨定案。代價寫在
#553 合併端那格：它仍分不出「人確認過的 names[0]」與機械值，維持提醒不擋，觸發條件改綁 #564。

## 第二次端到端又紅——這次是我的 binary

改成替換語意後測試 7/7 綠、四個 mutation 負控乾淨，真 binary 卻說「authorized 含不在
names 內的名字」。隔離半天，最後是：**`swift test` 不重編 `akashic` executable target**，
`.build/debug/akashic` 是改 service 之前的版本。`swift build` 印 `Build complete! (0.17s)`
是快取；`swift build --product akashic` 花 3.31s 才是真的重編。

驗法：`grep -a -c '<這輪新加的字串>' .build/debug/akashic`——版號不會說謊但也不會說話，
新字串在不在才是證據。已記 memory（`swift-test-does-not-rebuild-executables`）。

## 落地

- `updateVenue` 加 `authorize: [String]?`；CLI `--authorize`、MCP `authorize`，兩面同批
- 12 條測試（R1 的 7 條改語意 ＋ R2 新增 5 條：同書寫系統兩名拒絕／沿革前身保留時間／
  確認既有值報 `alreadyAuthorized`／兩邊空白不是矛盾／呼叫端自己 `add_variant` 才進 variant）
- `mcp-cli-parity` 的 `akashic_update_venue` 列補記；`two-kinds-of-edits` 加一列、#553 那列
  理由改寫；`DivergenceResolve` 四處「venue 沒有 authorize 面」的文字改指向本面

## 不做（都有 issue）

- 470 筆的回填——那是 470 次「哪個名字對外」的判定，一輪 venue authorize campaign 的量級
- 撤回面（把名字從 authorized 移出而不放新的進去）——#559
- judgement 記錄——#564（三面一次裁）
- `bootstrap-venues` 是否停寫 `[names[0]]`——#563
- 入口 `String ==` vs 守衛 `NameIdentity.canonical`——#560（三個迴圈一起改）
- 合併端把併入名字一律標 variant、且丟時間欄位——#565（D1 的同一個論證在合併端）
