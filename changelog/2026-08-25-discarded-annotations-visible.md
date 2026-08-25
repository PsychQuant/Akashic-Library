# 剝掉可以，靜默不行——括號註記的可見性（#394 verify）

2026-08-25 中午。ensemble 的 codex 席報 CRITICAL：`migrate-identifiers` 把 ISSN／ISBN
值裡的括號註記整段丟掉，而那些不是雜訊。實測真實 store **8 筆**：

```
burnette2013mind     issn: 1939-1455(Electronic),0033-2909(Print)
burkner2022information  issn: 1860-0980 (Electronic) 0033-3123 (Linking)
vaart1998asymptotic  isbn: 0521496039 (hardcover)
…（完整清單見 #394 的 comment）
```

`Electronic`／`Print`／`Linking`／`hardcover`／`alk. paper` **是有書目語意的 qualifier**。
剝掉之後 venue 拿到兩個裸號，而「哪個是電子版」沒了。

## 為什麼剝括號本身是對的

不剝的話 `1860-0980 (Electronic) 0033-3123 (Linking)` 解析失敗、整筆略過——那是
`2026-08-24-migrate-identifiers.md` 已經權衡過的取捨。**本篇不推翻它**。

問題不在剝，在**剝了不說**。`lossless-intake` 執行細節 3：

> **丟棄必須可見。**……**靜默是最糟的形式**——它讓「沒有這個欄位」與「這個來源沒給」
> 變成同一個觀察，而那兩件事在事後完全無法區分。

先前這些註記在報告的**任何一處都不出現**：`Skipped` 只在 token **解析失敗**時產生，
而括號是在 `candidates()` 階段就被 regex 抹掉的——連 `skipped` 都輪不到它。

## 修法

`candidatesWithAnnotations(_:field:)` 一併回報被剝掉的內容，`Report.discardedAnnotations`
承接，CLI 印出原值與丟棄的 qualifier。**函式不決定要不要丟，只保證丟了看得見。**

`candidates()` 保留為薄包裝（既有呼叫端與測試不動）。

兩支測試：

- `testStrippedParentheticalAnnotationsAreReported` — `Electronic`／`Print` 要在報告裡，
  且**原值**也要在（否則使用者無從復原）
- `testDOIParenthesesAreNotTreatedAsAnnotations` — DOI 的後綴合法含括號
  （`10.1016/S0304-4076(98)00255-9`），**不得**被當註記剝掉也不該回報成丟棄。
  這是 8-24 那篇記過的坑，釘住它免得本次改動把它挖回來

## 那 8 筆怎麼辦——資訊沒消失，但模型還沒有它的家

`~/.akashic` 是 git repo，遷移前的 `9e22750` 仍在，8 筆全部可還原，完整對照表已發到
#394。但**還原到哪裡**是未決的：

`IdentifierYAML.listNode` 只寫 `normalized`——`Identifier` 的 `raw` 到不了磁碟。所以
qualifier 在現行模型裡確實沒有棲身處，而給 `Venue.issn` 加 medium 欄位是 schema 改動
（要 format bump，而 store 的 bump 本來就還欠著）。

**兩個選項的成本差一個量級，裁決留給使用者**：

| 選項 | 成本 | 代價 |
|---|---|---|
| 寫進 venue 的 `note` 散文 | 極低 | 不可機讀——而可機讀正是 #394 的全部目的 |
| `Venue.issn` 帶 medium qualifier | format 13 的 schema 改動 | 但 bump 本來就欠著，此刻做最便宜 |

8 筆裡有 2 筆是退化情形（`0033-2909 (Print) 0033-2909`、`0022-3514 (Print) 0022-3514
(Linking)`——同一個號的兩個角色），真正丟失資訊的是另外 6 筆。
