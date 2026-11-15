## 1. 測試先寫（看它們失敗）

- [x] 1.1 在 `Tests/AkashicKitTests/FulltextLoginLookRulingsTests.swift` 寫 `urlGateLook` 的三個 Example（帶標記 `spec-example: fulltext-gate-look / showLogin path is a login look`、`/ showlogin host label is not a login host`、`/ showlogin inside a longer slug does not count`），跑 `swift test --filter FulltextLoginLookRulingsTests` 看第一支失敗
- [x] 1.2 同一個檔寫兩個流程 Example（`A CAPTCHA on the showLogin page after navigation pauses the run`、`A showLogin page on another host pauses the run`），用 `FulltextFetchPathTests.Scenario` 與假瀏覽器，斷言結束碼 6 與 `(login page)`；看它們失敗（現行是 8 與 7）
- [x] 1.3 把 `FulltextB37Tests.testAnUnreadableSameSiteTabAtALoginPathWithAServiceMarkerStillWaits` 改名為 `…Pauses`、斷言 6、`STOP THE WHOLE RUN`、`(login page)`、沒有 `resume:`，帶標記 `Unreadable same-site login path with a Cloudflare marker pauses`；看它失敗
- [x] 1.4 負控兩支（`Unreadable same-site login path without a marker is handed over`、`Unreadable same-site PDF path with an auth segment is handed over`）：結束碼 7、`handover: unverifiable`；現行就應該綠，實作後仍綠
- [x] 1.5 契約 Example（`Skill and CLI agree on contract 10`）：斷言 `FulltextFetch.contractVersion == 10`，並確認既有的 `SkillToolsCLITests` 比對 SKILL 第 0 步的門檻

## 2. 實作

- [x] 2.1 （Requirement: An Atypon showLogin path segment SHALL have the look of a login page）`BotSignals`：新增只給路徑用的封閉清單 `pathOnlyLoginSegments = ["showlogin"]`，`urlGateLook` 的路徑迴圈以 `segment.bare` 比它；`loginTokens`、`compoundLoginWords`、`hostLoginLook` 不動；1.1、1.2 轉綠
- [x] 2.2 （Requirement: An unreadable same-site tab with a human-check marker at a login path SHALL pause the run）`FulltextFetch.judgeUnreadable` 第 3 步：命中 `cloudflare-challenge` 或 `perimeterx-press-and-hold`、同站、`urlGateLook` 是 `login` → `botStop(... (login page))`；1.3 轉綠、1.4 仍綠
- [x] 2.3 （Requirement: The fetch contract version SHALL be 10）`contractVersion` 9 → 10，版本沿革註解加一行；SKILL 第 0 步門檻改 10、版本沿革加版本 10；1.5 與 `SkillToolsCLITests` 綠

## 3. 文件與發布

- [x] [P] 3.1 `FulltextFetch.swift` 開頭、`onSiteStop`、`BotSignals` 註解、SKILL（結束碼 8 那一列、〈讀不到的分頁〉、登入長相那一條）、`FulltextB37Tests` 的註解：「待使用者裁決（#777）」改成已裁決（2026-11-11）
- [x] [P] 3.2 `changelog/2026-11-04-b49-fulltext-613.md` 的〈待使用者裁決（#777）〉加一段日期註記（不改寫歷史）；新增 `changelog/2026-11-11-fulltext-login-look-rulings-777.md`
- [x] [P] 3.3 `plugin/CHANGELOG.md` 加一則；plugin 殼版號 0.13.14 → 0.13.15（照 f887f1ee 改的檔）
- [x] 3.4 `swift build -Xswiftc -warnings-as-errors`、`swift test --filter Fulltext`、全套測試、`bash .githooks/run-guards.sh`
