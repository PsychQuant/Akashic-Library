# 2026-09-26 識別碼只收 ASCII 數字（#589）

ISSN、ISBN、ORCID 三者共用 `idCompact`。它用 `CharacterSet.alphanumerics` 過濾字元、用 `wholeNumberValue` 取值，兩者都接受 Unicode 數字。所以全形（U+FF10–FF19）或阿拉伯-印度數字（U+0660–0669）寫成的號能通過 mod-11 檢查，原樣成為 `normalized`。後果是：
- 去重是比字串，這兩種寫法會被當成兩筆；
- `akashic-verify-venue` 回讀時比不出差異；
- `Venue.validate()` 也看不到。

識別碼相等本身就足以做身分判定（`identity-is-judged-not-matched` 的封閉例外），所以這是一個看起來像決定性證據的假號。

- `idCompact` 把非 ASCII 的英數字元換成 `?`，而不是濾掉：
  - 長度照算，而 `?` 不是數字也不是 `X`，三個呼叫端不改一行就全部拒絕；
  - 若是濾掉，夾在 ASCII 號裡的非 ASCII 字元會被靜默吞掉，號照樣通過。
  - 判斷在 `uppercased()` 之前做，因為有些非 ASCII 字元轉大寫後會變成 ASCII（合字 `ﬀ` → `FF`）。
- 已入庫的非 ASCII 號，在載入時走既有的「不合法識別碼 → 整檔隔離」路徑，與其他不合法的號同級。live store 實測 282 個值，非 ASCII 0 筆；新 binary 跑 `validate` rc=0，沒有新的隔離。零實例，不需要遷移。
- PMID 以 `UInt64(s)` 解析，本來就只收 ASCII；DOI 的後綴本來就可以含 Unicode。兩者都不動。
- `zero-instance-guards` 加第 32 列。
- 測試：`testISSNRejectsNonASCIIDigits`（全形、阿拉伯-印度數字、混入一個、夾帶、全形 X）與 `testISBNAndORCIDRejectNonASCIIDigits`。負控：還原 `idCompact`，5 個斷言失敗。
