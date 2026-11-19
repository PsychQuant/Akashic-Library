## 1. 測試先寫（在 idd-772 archive 之後的 HEAD 上看它們失敗）

- [ ] 1.1 `FulltextClickProcedureTests`、`FulltextDivisionOfLabourTests`：改過與新增的每個 Example 一支帶 `spec-example` 標記的測試
- [ ] 1.2 `FulltextLockBlockTests`（新）：SKILL 第 3 步鎖分頁那一段原文照跑，對假的 safari-browser（記號、完整網址、移動過的分頁、對不到、兩個相同網址、頁面網址帶 `$(…)`、Safari 不回答）
- [ ] 1.3 驗證：帶標記的新測試都失敗，commit

## 2. SKILL 與出版商表 [after: 1.3]

- [ ] 2.1 （Requirement: Reads and clicks after fetch SHALL stay on fetch's window and tab；Values from a page SHALL reach the shell through a variable）第 3 步〈`fetch` 之後的鎖分頁〉、`save-pdf` 的命令、第 1、4 步的命令
- [ ] 2.2 （Requirement: The landing table SHALL be judged in a fixed order…）落點表第 1、3、4、5、9 種，「鎖對不到」與每按一下最多等一次，再判的基準
- [ ] 2.3 （Requirement: The skill SHALL read a page after a click…）落點那一段、`get text` 的三種狀態、標題與網址、頁面文字是資料、href 的 scheme
- [ ] 2.4 （Requirement: The skill SHALL defer the rest of a site after a human check）第 8 種與 (a) 的登入長相、第 7 步的貼上警告
- [ ] 2.5 （Requirement: The skill SHALL list the mid-run stops as a closed list）八種
- [ ] 2.6 （Requirement: The skill SHALL count each click it makes）埠號
- [ ] 2.7 （Requirement: The skill SHALL state the edge behaviours of the click procedure）第 6、7 種、(b)、(d)、`unverifiable`、例外 (d) 的裁決
- [ ] 2.8 `publishers.md` 第 17、23 列

## 3. 鏡像與程式文字 [after: 2.8]

- [ ] 3.1 規則檔的中止條款摘要、「交給人」、形狀 (b)
- [ ] 3.2 第 22 列的四處「交給人」與 `doi-not-resolved` 的提示
- [ ] 3.3 changelog 兩份、殼摘要重算

## 4. 驗證 [after: 3.3]

- [ ] 4.1 `swift build -Xswiftc -warnings-as-errors`、全套 `swift test`、`bash .githooks/run-guards.sh`、`spectra validate idd-781-fix2` 都通過
