# 2026-09-27 `matchingKey` 在 scalar 上收斂空白（#574）

`NameNormalization.matchingKey` 原本用 `split(whereSeparator: \.isWhitespace)` 在 grapheme cluster 上切空白。
- U+0020 與其他 Zs 類空白後面的組合符號，依 GB9 併進同一個 cluster，整個被當成空白丟掉：`"A \u{301}B"` → `"a b"`。
- TAB、LF 之類的 Control 類空白依 GB4 斷開，組合符號保留。

所以同一個組合符號保不保得住，取決於前面是哪一種空白。`NameIdentity.canonical` 自 #554 R6 起就在 scalar 上切，兩者都自稱「只收斂空白」，行為卻不同。

- 改成與 `canonical` 同一種切法：逐 scalar 走，只丟 White_Space scalar，其他 scalar 一個都不刪。前後空白一樣去掉，連續空白一樣收成一個。
- 連字號家族那一半（連字號後接組合符號或 ZWJ 時整個 cluster 不取代）不在本張範圍，照舊。
- **改之前量過**：live store 202,139 個字串值，會讓 key 改變的形狀（NFKC、刪 Cf 之後，Zs 類空白緊接組合符號）0 個。提名鍵、`verdictEqualityKey`、#486／D23 一族的去重鍵，在 live store 上都不變。
- `zero-instance-guards` 第 27 列的 Python 鏡射原本照 Swift 的舊行為鏡射，現在同批改掉；兩個固定案例改成新行為，另一個固定案例的註解一併更新。鏡射的 assert 全部通過。
- 測試：`NameNormalizationTests.testWhitespaceCollapseKeepsCombiningMarksAfterAnySpace`，涵蓋 U+0020、NBSP、TAB 三種空白後的組合符號，以及「孤立的組合符號是內容」。實作前 4 條紅（TAB 那條本來就對）。相關 632 支測試全綠。

## R1 verify 之後

- `LooseNameKey` 對 `matchingKey` 的輸出又在 grapheme cluster 上切一次。`" \u{301}"` 是同一個 cluster，上游剛修掉的損失在提名鍵裡重演（logic 席）。它的 `cleanTokens` 改成在 scalar 上切。測試：`LooseNameKeyTests.testReorderKeyKeepsACombiningMarkAfterASpace`，實作前紅。live store 同一個量測（0 個字串值有這個形狀），提名鍵不變。
- 第 27 列散文裡一句「Swift `Character.isWhitespace`」改成現況（scalar 上的 `properties.isWhitespace`，集合相同）。

## R2 verify 之後

- 同一種 Character 重切還在 `LooseTitleKey`（venue／org 的提名鍵）與 `PersonBootstrap` 的 `swappedOrder`／`suggestedKey`。`identity` 取兩個候選的 min，丟掉組合符號的那一支可能勝出（requirements 席）。
- 修法不是再修三處，是**抽成單一定義**：`NameNormalization.whitespaceTokens`（以 White_Space scalar 切、不回空 token）。`matchingKey` 自己、`LooseNameKey`、`LooseTitleKey`、`PersonBootstrap` 都呼叫它。四處各寫一份切法，正是 R1、R2 兩輪一再找到新一處的原因。
- 測試：`LooseNameKeyTests.testSiblingKeysKeepACombiningMarkAfterASpace`、`PersonBootstrapTests.testSwappedOrderKeepsACombiningMarkAfterASpace`，在修正前的程式上紅。
- 量測沿用本 changelog 開頭那一個：live store 沒有「空白後緊接組合符號」的字串，四個鍵在 live store 上都不變。
