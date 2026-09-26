# 2026-09-27 `WritingSystem` 以 Unicode 名稱判定拉丁字母（#568）

`WritingSystem.isLatinLetter` 原本用 code-point 區間（A–Z、a–z、U+00C0–024F），兩個方向都錯：
- **區間內的符號**：×（U+00D7）與 ÷（U+00F7）被歸 `.latn`。#554 R3 verify 實測 `--authorize "×"` 會把既有的 PSYCHOMETRIKA 換下來。寫入面在 R4 擋住了，分類器本身沒改。
- **區間外的字母**：全形拉丁（U+FF21–FF5A）、越南文（U+1E00–1EFF）、Latin Extended-C／D／E 被歸 `.other`。結果同一個拉丁刊名能以兩個「書寫系統」並列為 authorized。

同一個陷阱本 repo 在 `zero-instance-guards` 第 12 列的量測腳本裡記過，那邊早就改用名稱判定。

- 判準：**是字母（L 類），且 Unicode 名稱以 `LATIN ` 或 `FULLWIDTH LATIN ` 開頭**。
  - issue 寫的是「名稱以 LATIN 開頭」，但全形字母的名稱是 `FULLWIDTH LATIN CAPITAL LETTER …`，只認 `LATIN` 會把 issue 自己點名要收的全形排除。所以認兩個前綴，第 12 列的腳本同輪改成一樣。
  - ASCII 走快路徑，因為名冊幾乎全是 ASCII，而 `properties.name` 要建字串。
- **改之前先量**（issue 的要求）：live store 全部 person／venue 的 authorized 共 5,189 個名字，新舊分類翻轉 0 個；改後「同書寫系統兩個以上」的記錄 0 筆（改前也是 0）。live store 沒有全形名字，加上全形前綴不改變這個結果。
- `NameNormalizationTests` 原本有一支測試記錄「NFKC 合成讓分類分家、兩條不變式同時靜默」的逃逸（`d` + U+0307 → U+1E0B）。U+1E0B 現在歸拉丁，逃逸關掉了。那支測試改成斷言不變式 2 抓得到，並改名。它原本的訊息要求屆時更新 `Person.authorized` 的 doc；那段 doc 沒有點名這個逃逸（只說「攔得下多數，但不是全部」），仍然成立。
- 測試：`AuthorizedNameTests.testLatinIsDecidedByLetterAndNameNotCodePointRange`，涵蓋 ×、÷、全形、越南文、Latin Extended-D、希臘文，以及 Latin-1 的真字母。實作前五條全紅。
  - 越南文那條第一版寫「Tạp chí」，但它夾著 ASCII 字母，舊區間也判得對，斷言驗不到東西；改成只含擴展區字母的「ỆỰ」。
- **沒改的**：`LooseNameKey` 有自己的一份 `isLatinLetter`（提名用的寬鬆鍵），不在本張範圍。它是否該共用同一個判準，要看提名的 recall 會不會因此改變，另案評估。
