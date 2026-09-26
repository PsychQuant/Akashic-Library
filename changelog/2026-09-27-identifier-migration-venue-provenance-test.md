# 2026-09-27 `rewritingProvenance` 的 venue 路徑有了行為測試（#590）

`IdentifierMigration.rewritingProvenance` 有兩個呼叫端：
- entry 那條結構上到不了，由 `testAResidueValuedReferenceCannotBeWrittenAtAll` 釘住；
- venue 那條可達、零實例，但沒有任何行為測試。`Tests/` 裡提到它的地方全是 doc 與斷言訊息。

`zero-instance-guards` 第 8 列的紀律是「釘住為什麼是零」，這一格的另一半（可達路徑的涵蓋）先前沒有釘。

- 新測試 `IdentifierMigrationRunTests.testVenueReferenceToAResidueTokenIsRewrittenToTheNormalizedForm`。
  - 造出三個前提：work 殘留裡有未正規化的 ISSN token `00333123`、venue 邊已歸戶、venue 持有 value 等於那個 token 的 reference。
  - 跑 `migrate-identifiers --apply`，斷言 reference 的 value 同一次改寫成 `0033-3123`、號落在 venue 上、work 殘留已移除、改寫進了報告。
- **裁決寫在測試名裡**：改寫成正規形（issue 要求兩者擇一）。這就是現行實作的行為；測試把它從「doc 說它會這樣」變成「測試證明它這樣」。不改寫的話，reference 會指向一個 store 裡已經不存在的字面，`validate` 照樣過（它比 normalized），但讀的人對不上。
- 負控：venue 那個呼叫改傳空的改寫清單，2 個斷言失敗。
- `testAResidueValuedReferenceCannotBeWrittenAtAll` 的 doc 裡「venue 那條零行為測試——記 #590」同步改寫。
