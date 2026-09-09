# 作者位的移除、以及「缺頁碼」其實是三個族群（#457 #449）

兩張都是資料工作的 issue，而兩張的**立論在重量之後都不成立**——一張是我自己上一輪寫下的
建議被 Crossref 否掉，一張是它描述的族群被另一批資料淹沒。

## #457 —— 全庫掃過之後，非人只有一個，而它今天在出貨

issue 的第 3 步是「先扣非人」。逐一掃過 **3,885 個 distinct literal**（不只高頻榜——
高頻榜是抽樣，而佔位字串不保證高頻），命中疑似非人樣式的**恰一個**：

```
21  'No authorship indicated'
```

另外兩個被啟發式標出來的是偽陽性：`班固`（人，古典）與 `Μαριέττα Παπαδάτου-Παστού`
（人，希臘文）。

### 它的代價不是「還沒歸戶」

```bibtex
AUTHOR = {indicated, No authorship},
```

`export-bib` 把它當人名拆成 family／given，**造出一個不存在的人**；citekey 也照它生
（`indicated2002bpsychological` 一族）。APA7 §9.12 對無署名作品的處置是**以標題起首**，
那要求作者位是空的。

### 而沒有任何面到得了 0 個作者位

`Author` 的三態（#323）都假設那一格背後有一個作者：`apply` 升格、`attribute_org` 改歸屬、
`split_author` 增加數量、`un_split` 減到 1。**唯一的路是手改 YAML**——`mcp-cli-parity` 的
識別碼那一節記著那條路 2026-08-28 差點弄丟一筆 DOI。

所以本輪做的是那個面：`--drop-author` / `drop_author`，兩面同走 `dropAuthors`。

### 三個值域裁決

**① 它是 AI 編輯。**「這個字串不是作者」要知道 PsycInfo 用它當佔位符，字串謂詞單獨做不出來
（`identity-is-judged-not-matched`）。所以理由必填、記錄必留。

**② 記錄與拆分記錄住同一格，由 statement 前綴分辨。** `Entry.references` 的 `field: authors`
自 #450 起收拆分記錄（`拆為 ⟦a⟧ ⟦b⟧：理由`）；移除記錄是 `移除：理由`。兩者的 value 語意
**相同**——已退役的作者 literal——差別只在退役之後剩幾段（N ≥ 2 vs 0），所以它們是同一件事的
兩個結果，不是兩件事。

**為什麼不重用 `SplitRecordValue`**：它的 `init?` 要求段數 ≥ 2，而放寬到 0 會讓
`unsplitAuthors` 把一次移除讀成可還原的拆分並把字串塞回作者位——**正好是本面要消除的東西**。
兩種記錄要在文法上就分得開，不是靠呼叫端記得檢查（3.325 的立場）。

**③ 沒有具名逆操作，而那是裁決不是拖延。** `split_author` 的逆是 `un_split`（#513）。
還原一次移除需要知道**位置**，而記錄刻意不存索引——理由與拆分記錄不存索引的既有理由相同
（「索引在同一批的前一次操作之後會位移」）。移除之後作者位裡什麼都不剩，連「以值定位」都
無從施力。被移除的字串逐字留在 `value` 裡，所以資訊沒有丟；缺的是把它放回**原位**的能力。

### store format 17

format-16 binary 的 `authors` case **存在**，所以不是走到封閉 default，而是走到
`SplitRecordValue.parse(statement) != nil` 那道 guard——移除記錄的前綴不同，parse 回 nil，
**一樣整檔 quarantine 且 rc=0**。所以 16 那道閘擋不住它，要各自一道
（`assertEntryWritable` 對 format < 17 拒寫）。

### 同輪必須動 export 面，否則等於把捏造換成錯誤

移除之後 `apa7Report` 報 `[ERROR] Missing required field: AUTHOR`——21 個被捏造的 byline 會
變成 21 個 error。所以加了抑制，形狀取自 #406 的 `paginated`：

> **只在 store 明說過時抑制**——該 work 帶至少一筆移除記錄。**空的 `authors` 本身不足以抑制**，
> 那是「還沒記」，正是這個檢查要抓的東西（同 `paginated` 的 `nil` 照報）。

兩格成對釘住（`testRecordedUnattributedWorkIsNotAnAPA7Error` /
`testEmptyAuthorsWithoutARecordIsStillAnAPA7Error`）；少了後者，抑制條件會從「store 明說過」
悄悄退化成「作者位是空的」。

### 一個新的零實例守衛（`zero-instance-guards` 第 23 列）

移除之後 `authors` 是**空的**，而 `enrich --include-absent-authors` 的既有契約正好是
「只在完全為空時補作者」——**同一個字串補得回去**，那時 store 同時斷言「它已退役」與
「它是作者」。這條路徑不是假想的，而**讓它可達的那一步就是本 change**。

所以守衛與它同批落地：`StoreHealth.contradictedRemovalRecords`，warning，三個面都渲染。
它與 `staleSplitRecords` 的一致性條件**相反**——拆分要求「至少一段仍在」，移除要求
那個字串**不在**。

### 還沒對 live store 執行——而那是刻意的

21 筆的移除需要 store format 17，而 bump 會讓**每一個**還沒升級的 binary 整體拒絕開啟
（`~/bin/akashic` 與 `~/bin/akashic-mcp` 都是 2026-09-07 的）。`mcp-cli-parity` 的
CLI-only 表把 format bump 明列為**維運例外**：「部署鏈（release → migrate → validate →
手動 bump format）屬操作者角色」。

已在 store 副本上驗過整條路徑（21 筆全移除、`validate` rc=0、`.bib` 裡的捏造 byline 消失、
全庫 `No authorship indicated` 歸零）。部署順序見 #457 的收尾 comment。

## #449 —— 233 筆裡有 182 筆不是缺頁碼

issue 說「精確清單等 #406 的 floor 接線落地後現算」。算了：**233 筆**。而按刊拆開之後，
**185 筆是 `psychological-methods`**，不屬於 issue 描述的族群。

### 我上一輪的建議被 Crossref 否掉

上一輪的 comment 寫著「184/185 有 DOI，而 Psychological Methods 是有頁碼的刊——Crossref
查得到」，並建議「第二族另開 issue，走 `enrich` 批次補值」。

**那句話沒有量過。** 這一輪把 220 個 DOI 全查了（不是抽查）：

```
psychmeth 184 筆：有 page 0｜有 volume 1
rest       36 筆：有 page 8｜有 volume 30
```

Crossref 對那 184 筆**一筆頁碼都沒有**，而且 183 筆連 volume 都沒有。取兩筆看完整記錄，
簽章一致：只有 `published-online`、沒有 `published-print`、沒有卷期頁——那是**線上先行發表**
的樣子。年份分布佐證：1996–2023 每年缺 0–1 筆，2024/2025/2026 缺 64/78/40。

所以那 182 筆不是回補問題，是**出版狀態沒有地方表達**（#541）。`apa7-is-the-work-floor`
的封閉列舉早就預先裁決過它不進 `Entry.type`，落點是欄位。

### 而 #449 自己的族群，Crossref 今天有 18 筆補得動

issue 的表格寫 Crossref「**抽查**全部沒有頁碼」，而它上方的散文寫「四個外部書目來源已**全量**
查過」。兩句不一致，而今天的全量查證解決了它：36 筆有 DOI 的裡面，Crossref 有 **8 筆的頁碼**、
另外 10 筆有 volume／number。

已補值（`akashic enrich`，add-only，每個補進去的欄位帶一筆 `retrieval` reference 指向存進
`sources/` 的 Crossref 回應）。**233 → 225**，#449 自己的族群 48 → 40。

### 順帶修掉補值面的一句假話（#542）

`enrich` 的 CLI 對每一筆有 digest 的提案逐字印「只記在報告，不進 store」——#517 之前為真，
之後為假（實測：reference 確實寫進 YAML 了）。而 service payload **根本不帶**
`addedReferences`／`provenanceSkipped`，所以 MCP 面在結構上也看不出寫了沒。

兩面缺的是同一個欄位，所以補在 payload、兩面同源；CLI 那一行改成由 payload 現算，三種狀態
（寫了 N 筆／有 digest 但缺另兩欄／dry-run 尚未知）分得開。

## 另外三張 sister issue

- **#543**：196 筆 work 有多個 DOI，而 `.bib` 把清單用逗號串成一個 `DOI` 欄位——產出一個
  解析不到的連結。缺席是誠實的，錯的連結不是。
- **#544**：21 筆的 `abstract` 是 Crossref 的**錯誤頁**（與 #457 的 21 筆完全同一批，交集 21、
  對稱差 0——同一個成因）。而**沒有任何面刪得掉一個 `fields` 的值**。
- **#541**：上面那 182 筆。

## 一件量測方法本身的事

`~/bin/akashic` 是 **2026-09-07** 的，缺 #513／#517 之後的全部。第一次跑 `enrich` 時它以
「未知的鍵 sourceURL」整批拒絕——那是**它自己**告訴我它舊了。但 `validate` 不會：舊 binary
沒有的檢查會**印不出東西**，而「沒被檢查」與「檢查過且乾淨」在輸出上不可區分
（`zero-instance-guards` 第 13 列的自證形）。本輪所有量測改用 `.build/debug/akashic`。
