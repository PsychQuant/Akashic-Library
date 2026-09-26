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
