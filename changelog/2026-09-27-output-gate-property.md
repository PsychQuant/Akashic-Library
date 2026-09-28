# 2026-09-27 輸出閘從列舉改成性質（#569）

`UnsafeToEmitScalar` 是 `displaySafe` 與 JSON 出口判斷「哪些字元不得原樣輸出」的唯一定義。它原本是一張列舉：C0／C1／DEL、LS／PS、bidi override 與 isolate、LRM／RLM／ALM、BOM。整個 Cf 類別的其餘 150 個碼位不在裡面，其中最要緊的是 U+E0020–E007F 的 TAG 字元，這是經典的隱形文字載體；ZWSP、SHY 也不在。結果是：

- 這些字元會原樣送進 LLM context；
- 同一個字元，名字輸入閘拒絕它，輸出閘卻放行它——兩份規格對同一個字元給出不同答案。

## 裁決（使用者 2026-09-27）

輸出閘改用性質，與 `escapingInvisibleScalars` 同一份定義：Default_Ignorable、Cc、Cf、Zl、Zp、非 U+0020 的空白、私用區（Co）、U+2800。

ZWJ／ZWNJ 分兩種輸出處理：
- 人可讀輸出保留原字元。它們是波斯文、阿拉伯文與印度系文字正字法的一部分，逃脫後會出現看得見的逃脫序列。
- JSON 出口逃脫成 `\u200C`／`\u200D`。這是 JSON 自己的逃脫語法，解回來逐字相同，無損。

## 改了什麼

- `UnsafeToEmitScalar.contains` 改成上述性質。新增 `escapesInDisplay`（扣掉 ZWJ／ZWNJ），`displaySafe` 用它。`escapingInvisibleScalars` 改成直接呼叫 `contains`，兩者從此是同一份。
- **預算**：`escapedScalarCount` 從常數 8 改成依碼位計算。BMP 內是 8；BMP 以外 `%04X` 會印五或六位，是 9 或 10。性質化之後集合含 TAG 字元與補充私用區，常數會讓每次逃脫少算一到兩格。
- **名字輸入閘**：拒絕的集合寫成「`UnsafeToEmitScalar.contains` 扣掉私用區」，語意不變——私用區本來就不擋，非 U+0020 的空白本來就由 canonical 檢查先擋。三支訊息的分類以 `isBidiControl` 等屬性重建，與舊列舉逐字等價。DOI 後綴閘同樣改寫成「扣掉私用區」。
- **JSON 出口**：`AkashicService.jsonString` 是 CLI `--json` 與 MCP 回應共用的序列化點，序列化之後套 `escapingUnsafeScalars`。`query --json` 與位元組預算的量測點 `jsonBytes` 也一併對齊。在此之前，只有 `bootstrap-people --json` 走這一道。
- `docs/store-format.md` §5.7 第 2 條、`mcp-cli-parity` 的 update_venue 列，以及程式裡七處「#569 另裁」「局部圍堵」的註解，改成現況。

## 影響

live store（唯讀量測）：沒有私用區字元；有 62 個非標準空白（U+2009、U+2002、NBSP）和 5 個軟連字號。這些字元在人可讀輸出會變成逃脫序列；JSON 無損。

另一個 session 負責的 `ReferencesExtractTests` T57 經使用者同意改了一行斷言。`references extract` 對 PDF 文字逐欄 `displaySafe`，所以 U+E000 現在輸出成 `\u{E000}`。那支測試要驗的是「私用區字元不被當成軟連字號」，這件事仍然成立。

## 測試

`SanitizationBoundaryTests` 新增四支：

- 逃脫長度逐碼位核對；
- 性質是舊列舉的超集；
- ZWJ／ZWNJ 在人可讀輸出保留、在 JSON 逃脫且無損（含 TAG 字元的 surrogate pair）；
- 名字閘的拒絕集合等於輸出閘扣掉私用區。

`VenueAuthorizedWriteTests` 新增一支 service JSON 出口的測試。

負控五組，都紅：

1. 逃脫長度改回常數 8；
2. `escapesInDisplay` 不扣接合字元；
3. 名字閘不扣私用區；
4. 性質拿掉 Zs 與 Co；
5. `jsonString` 不逃脫。

全套 2,907 條 0 失敗。

真 binary 驗證：
- `--authorize` 帶 TAG 字元時，錯誤訊息印出 `\u{E0041}`；
- 波斯文刊名在人可讀輸出保留 ZWNJ，`venue --json` 輸出 `\u200C`、解回來逐字相同；
- live store `validate` rc=0，沒有新的 error。
