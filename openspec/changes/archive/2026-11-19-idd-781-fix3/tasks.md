## 1. 測試先寫（在 24cda776 上看它們失敗）

- [x] 1.1 `FulltextLockBlockTests`：收下新分頁之後記號還在原分頁、文章分頁關掉而右邊的分頁滑進那個位置、⌘T 的分頁（別的位置、別的主機）、按過之後鎖對不到、起點先記號再位置、`--profile`、只印主機（帳密、沒有 `://`）、`tab-unchanged` 的基準
- [x] 1.2 `FulltextClickProcedureTests`：改過與新增的每個 Example 一支帶 `spec-example` 標記的測試，只搜 Example 指名的那一節
- [x] 1.3 `FulltextLandingVerificationHostTests`（新）：落點那一段的驗證服務判法與 `BotSignals.isKnownVerificationService` 一致
- [x] 1.4 驗證：新測試都失敗，commit

## 2. SKILL [after: 1.4]

- [x] 2.1 （Requirement: Reads and clicks after fetch SHALL stay on fetch's window and tab）起點、鎖分頁、落點、收下新分頁四段，交出去之後再接，`--profile`
- [x] 2.2 （Requirement: The landing table SHALL be judged in a fixed order…）落點表第 1、3、4、5 種，鎖對不到，`tab-unchanged`、`button`
- [x] 2.3 （Requirement: A login page on another host SHALL pause the whole run）(b) 與「Log in for access」
- [x] 2.4 （Requirement: The skill SHALL list the mid-run stops as a closed list）八種、(2)、(5)、S:39 與 S:158 的說法
- [x] 2.5 （Requirement: The skill SHALL state the edge behaviours of the click procedure）探測的代價到別的主機、規則 1 (d)、S:82、`get title`

## 3. 鏡像與程式文字 [after: 2.5]

- [x] 3.1 規則檔 R:34、R:64、R:101–102 與形狀 (b)；publishers.md:107
- [x] 3.2 `fetch` 的 `tab-unchanged` 提示、`FulltextCommands.swift` 與 `FulltextFetch.swift` 的註解
- [x] 3.3 changelog 兩份、殼摘要重算

## 4. 驗證 [after: 3.3]

- [x] 4.1 `swift build -Xswiftc -warnings-as-errors`、全套 `swift test`、`bash .githooks/run-guards.sh`、`spectra validate idd-781-fix3` 都通過
