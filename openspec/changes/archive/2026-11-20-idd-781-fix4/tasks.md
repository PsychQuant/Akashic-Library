## 1. 測試先寫（在 63a87a98 上看它們失敗）

- [x] 1.1 `FulltextLockBlockTests`：fixture 改成 2026-11-20 量到的版面（每一個註明 M 編號）；按與落點同一個呼叫、對得上連結才收、其餘 `grown`、隔一個呼叫才看到的不收、片段變了加新分頁、沒有網址的新分頁等一次、讀取失敗再讀一次、按的命令不回來、按之前不是 `clear` 不按、鎖對不到之後先跑落點、還沒按就換頁、兩篇交接、再接到別的主機、交之前認不到、位置重複、profile 檔、基準檔不在
- [x] 1.2 `FulltextSameTargetCLITests`（新）：`same-target` 的判定表與讀檔行為
- [x] 1.3 `FulltextClickProcedureTests`、`FulltextLandingVerificationHostTests`、`FulltextLoginLookRulingsTests`、`FulltextFetchPathTests`：改過與新增的每個 Example 一支帶 `spec-example` 標記的測試
- [x] 1.4 驗證：新測試都失敗，commit

## 2. CLI [after: 1.4]

- [x] 2.1 （Requirement: The CLI SHALL say whether a new tab shows the clicked link's target）`FulltextSameTarget` 與 `fulltext same-target` 子命令、`WriteGateRulings`
- [x] 2.2 （Requirement: The fetch contract version SHALL be 13）契約 13、`tab-unchanged` 的提示

## 3. SKILL [after: 2.2]

- [x] 3.1 （Requirement: Reads and clicks after fetch SHALL stay on fetch's window and tab）起點、鎖分頁、〈按〉、落點、收下新分頁、交出去之後再接各段；鎖對不到；結束碼表；仍然擋不住的
- [x] 3.2 （Requirement: The landing table SHALL be judged in a fixed order…）落點表第 1–5、9 種；`tab-unchanged`、`html-page`、`left-site` 三列
- [x] 3.3 （Requirement: The skill SHALL list the mid-run stops as a closed list）八種停止的 (1)、(2)、(3)、(5)；S:130
- [x] 3.4 （Requirement: Deferred hand-overs SHALL be done one at a time；The skill SHALL defer the rest of a site after a human check；The skill SHALL make the model the default actor…）第 7 步的順序與再說一次、同站延後的時機、(c) 當場處理的例外
- [x] 3.5 （Requirement: The skill SHALL read a page after a click…；The click procedure SHALL have a closed list of entries；The skill SHALL state the edge behaviours…）href 存檔、空標題、第五類、再接不是新的入口、探測的代價
- [x] 3.6 （Requirement: The skill SHALL require the window-id contract）第 0 步的門檻與版本說明
- [x] 3.7 （Requirement: Statements about Safari's behaviour SHALL cite the measurement or say unmeasured）`references/safari-measurements.md`；SKILL 與 publishers.md 逐句核對

## 4. 鏡像與紀錄 [after: 3.7]

- [x] 4.1 publishers.md 的前言與 Ovid 一列；web-access.md 的例外；規則檔跟著 SKILL 改
- [x] 4.2 `docs/rulings/mcp-cli-parity.md`：#772 契約 12 與這一輪契約 13 兩筆
- [x] 4.3 changelog 兩份、殼摘要重算

## 5. 驗證 [after: 4.3]

- [x] 5.1 `swift build -Xswiftc -warnings-as-errors`、全套 `swift test`、`bash .githooks/run-guards.sh`、`spectra validate idd-781-fix4` 都通過
