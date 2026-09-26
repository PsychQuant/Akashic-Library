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
- 已入庫的非 ASCII 號，在載入時走既有的「不合法識別碼 → 整檔隔離」路徑，與其他不合法的號同級。live store 實測 141 個值（issn 59、orcid 42、isbn 40），非 ASCII 0 筆。初版寫的 282 是量測腳本把每個值掃了兩次，R1 verify 抓到；新 binary 跑 `validate` rc=0，沒有新的隔離。零實例，不需要遷移。
- PMID 以 `UInt64(s)` 解析，ROR 以 `Int(…)` 解析，都只收 ASCII。**DOI 的註冊者段同形**：`isNumber` 認全形、阿拉伯-印度數字與上標，所以 `10.１０３７/x` 會成為 normalized。初版只用「後綴可以含 Unicode」帶過，前綴卻沒處理；R1 verify 四席同指後，註冊者段也只收 ASCII，後綴不動。live store 2,445 個 DOI，非 ASCII 註冊者 0 個。
- **與 issue Expected 的偏離**：issue 要的是「`Venue.validate()` 出聲」，實作是載入時整檔隔離，比出聲更強；零實例、沒有即時代價，這個偏離記在 issue。
- `zero-instance-guards` 加第 32 列。
- 測試：`testISSNRejectsNonASCIIDigits`（全形、阿拉伯-印度數字、混入一個、夾帶、全形 X）與 `testISBNAndORCIDRejectNonASCIIDigits`。負控：還原 `idCompact`，5 個斷言失敗。
