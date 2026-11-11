## 1. 測試（釘住既有行為；程式不改）

- [x] 1.1 （Requirement: An Atypon showLogin path segment SHALL have the look of a login page）`Tests/AkashicKitTests/FulltextLoginLookRulingsTests.swift`：`A percent-encoded showLogin segment is a login look`（帶標記 `spec-example: fulltext-gate-look / A percent-encoded showLogin segment is a login look`）
- [x] 1.2 （同一條 requirement）`Tests/AkashicKitTests/FulltextB37Tests.swift`：`A landing page at showLogin pauses the run`（帶標記；用 `assertLoginStop`：結束碼 6、`(login page)`、沒有導航、沒有記嘗試）
- [x] 1.3 （同一條 requirement）`Tests/AkashicKitTests/FulltextB37Tests.swift`：`A page that turns into showLogin before navigation pauses the run`（帶標記；用 `movesToALoginPageWhileReading`）
- [x] 1.4 （Requirement: An unreadable same-site tab with a human-check marker at a login path SHALL pause the run）`Tests/AkashicKitTests/FulltextLoginLookRulingsTests.swift`：`Unreadable same-site verification path with a Cloudflare marker still waits`（帶標記；結束碼 8、`--resume-stage followed`、沒有 `(login page)`）
- [x] 1.5 `Tests/AkashicKitTests/FulltextLoginLookRulingsTests.swift`：第 3 件的正向測試（不帶標記）：導航之後落在 `/auth/12345.pdf`、頁面寫著 CAPTCHA → 6、`(login page)`
- [x] 1.6 每支新測試各用一個 mutation 確認會變紅（在另一份 clone 上）

## 2. 文字

- [x] [P] 2.1 `plugin/skills/akashic-fetch-fulltext/SKILL.md` 第 47 行與 `Tests/AkashicKitTests/FulltextOffSiteTests.swift` 第 276 行：「讀不到的分頁不適用」改成與 `BotSignals.swift` 同一句
- [x] [P] 2.2 `changelog/2026-11-11-fulltext-login-look-rulings-777.md`、SKILL 版本 10 那段、`plugin/CHANGELOG.md`：直說 DOI 落地頁被轉到 `/action/showLogin` 的那一篇會停下整批；changelog 的正規化敘述補百分比解碼、加一節說明這一輪的修正
- [x] [P] 2.3 `Sources/AkashicSkillTools/FulltextFetch.swift`：版本 10 的註解逐格寫；版本 8 那段的「第 0 步要求 9」標明是當時的門檻（SKILL 同一句也改）；`BotSignals.pathOnlyLoginSegments` 的註解補百分比解碼
- [x] 2.4 `.githooks/plugin-shell-versions.txt`：0.13.15 那一列的摘要照改過的 SKILL 與 plugin CHANGELOG 重算

## 3. 驗證

- [x] 3.1 `swift build -Xswiftc -warnings-as-errors`、`swift test --filter Fulltext`、`bash .githooks/run-guards.sh`
