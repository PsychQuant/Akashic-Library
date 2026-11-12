# #777：取全文的四件待裁事項，使用者 2026-11-11 裁決（plugin 殼 0.13.15 → 0.13.16，契約版本 9 → 10）

使用者 2026-11-11 對 #777 的四件回答（#777 的 Decision comment）：第 1 件 `/action/showLogin` 算登入頁、第 2 件讀不到的同站分頁改整批暫停、第 3 件接受（多停）、第 4 件保留（多停）。前兩件改程式，後兩件只把文件裡的「待使用者裁決」改成已裁決。規格：Spectra change `idd-777-fulltext-login-look-rulings`（新 capability `fulltext-gate-look`）；第 1 輪 verify 之後的修正是 change `idd-777-fix1`（見最後一節）。

## 改了程式的兩件

- **第 1 件**：`BotSignals` 新增只給路徑用的封閉清單 `pathOnlyLoginSegments`，只有 `showlogin`。`urlGateLook` 的路徑迴圈以整段（`PathSegment.bare`：百分比解碼、小寫、去掉 `;` 之後的路徑參數與一個網頁副檔名）比它。**不放進 `loginTokens` 或 `compoundLoginWords`**：那兩份也給主機用，主機標籤 `showlogin.<網域>` 使用者沒有裁過，維持不算；較長 slug 裡的 `showlogin`（`how-to-showlogin-errors`）也不算。
  - `urlGateLook`／`gateLook` 在 `FulltextFetch` 的 8 個呼叫點都跟著算：導航之後同站寫著 CAPTCHA 的那一頁（`onSiteStop`，8 → 6，使用者問句描述的那一格）、DOI 落地頁與導航之前的同站頁（照一般網頁讀 → 6）、導航之後分頁跑到別的主機的 `/action/showLogin`（交給人 `left-site` → 6）、doi.org 落地的判讀。方向都是多停。
  - **落地頁那一格的實際效果**：站把讀者從 DOI 落地頁轉到 `/action/showLogin` 時（例如要求先登入），那一篇會停下整批，不是只跳過那一篇。先前那一頁照一般網頁讀：頁面文字有起疑訊號就照訊號，沒有的話多半等不到 PDF 連結、以結束碼 3 結束，批次繼續。這是第 1 件加上 2026-10-02 的裁決（登入頁維持整批暫停）的結果。
  - 同站、導航之後、**沒有**起疑訊號的 `/action/showLogin` 仍交給人 `html-page`（第 6 則只看有訊號的那一頁，與 `/login` 相同）。
- **第 2 件**：`FulltextFetch.judgeUnreadable` 第 3 步——驗證服務標記命中 `cloudflare-challenge` 或 `perimeterx-press-and-hold`（等人驗證的兩個）、分頁在文章站上、網址的路徑有登入長相時整批暫停，訊息帶 `(login page)`；先前是等人驗證（8）。沒有標記的讀不到分頁照舊不看路徑（使用者 2026-10-02，保護 PDF 檢視器的分頁），交給人 `unverifiable`。
- **契約版本 9 → 10**：兩格的結束碼變了。SKILL 第 0 步要求 10，版本沿革加版本 10。

## 改成已裁決的兩件

- **第 3 件**：PDF 連結路徑恰好有整段的 `auth`、`login`（`/auth/12345.pdf`），導航之後落在那裡的挑戰頁算登入長相、整批暫停（6）。維持。
- **第 4 件**：主機最左邊的標籤是 `signon`、`sign-on`、`single-sign-on`、`singlesignon` 也算登入主機。維持。

## 測試

- 新檔 `Tests/AkashicKitTests/FulltextLoginLookRulingsTests.swift`：`showLogin` 的三個 `urlGateLook` 案例（含查詢字串、主機標籤不算、較長 slug 不算）、兩個流程案例（導航之後同站 `/action/showLogin` 寫著 CAPTCHA → 6；別的主機上的 `/action/showLogin` → 6）、兩個負控（讀不到的同站 `/login`、`/auth/12345.pdf`，沒有標記 → 7 `unverifiable`）、契約版本 10 與 SKILL 第 0 步一致、SKILL 的路徑清單與程式一致。
- `FulltextB37Tests.testAnUnreadableSameSiteTabAtALoginPathWithAServiceMarkerStillWaits`（釘住 8）改名為 `…Pauses`，斷言 6、`STOP THE WHOLE RUN`、`(login page)`、不印 `resume:`。
- 每支對應 spec Example 的測試帶 `spec-example: fulltext-gate-look / …` 標記。
- verify 之前補的三支（同一個檔，不對應 spec Example）：讀不到的同站 `/login`、標題是按住驗證的用語 → 6、`(login page)`（裁決點名的第二個標記）；別的主機上讀不到的 `/login`、標題是 Cloudflare 挑戰 → 6，訊息說的是別的主機，不說成文章站；讀不到的同站 `/login`、標題是封鎖頁 → 6，訊息是封鎖的標籤、沒有 `(login page)`。後兩支釘的是訊息：拿掉 `judgeUnreadable` 新分支的 `sameSite` 或「等人驗證」條件，結束碼不變（別的主機與其他四個標記本來就是 6），先前沒有測試會變紅。

## 第 1 輪 verify 之後的修正（change `idd-777-fix1`）

程式的行為不變，契約版本維持 10。

- 規格 `fulltext-gate-look`：第一條的正規化敘述補上百分比解碼（跳脫序列解不開的那一段照原樣比），並寫明導航之前判到這個長相的文章站頁面整批暫停；加三個 Example（百分比編碼的寫法、DOI 落地頁、讀頁面當中轉過去的同站頁）。第二條寫明標記命中而路徑不是登入長相時照原本的方式判，並把最後一句收緊（沒有標記而交給人的那一格，不含登入主機與已知驗證服務上的分頁）；加一個 Example（路徑是驗證頁的長相 `/captcha/x`，仍是結束碼 8）。合併後的規格從 9 個 Example 變成 13 個（新增 4 個）。
- 測試：四個新 Example 各一支帶標記的測試（兩支在 `FulltextLoginLookRulingsTests`，兩支在 `FulltextB37Tests`）；第 3 件補一支不帶標記的正向測試（導航之後落在 `/auth/12345.pdf`、頁面寫著 CAPTCHA → 6、`(login page)`）。
- 文字：SKILL〈中止條款〉與 `FulltextOffSiteTests` 的註解裡「讀不到的分頁不適用」改成與 `BotSignals` 同一句；SKILL 版本 10 那段、本檔與 plugin CHANGELOG 直說落地頁那一格的實際效果；`contractVersion` 版本 10 的註解逐格寫出先前的結束碼；版本沿革裡「第 0 步要求 9」的兩句標明是當時的門檻。
- SKILL 與 plugin CHANGELOG 改了，`.githooks/plugin-shell-versions.txt` 裡這一張那一列的摘要重算（當時用的版號是 0.13.15，還沒有發布過；之後改成 0.13.16，見下一節）。

## 併入 main（#775 先合併）

#775（PR #783）在 2026-11-12 先合併進 main，用掉了 plugin 殼 0.13.15。這一張把 main 併進 branch，改成 0.13.15 → 0.13.16：

- `plugin/.claude-plugin/plugin.json` 的版號改成 0.13.16；`.githooks/plugin-shell-versions.txt` 保留 #775 的 0.13.15 那一列，另接 0.13.16 一列。
- `plugin/CHANGELOG.md`：這一張的條目在 #775 的條目上面，版號改成 0.13.15 → 0.13.16。
- SKILL 第 0 步有一處衝突：門檻用這一張的 10，建置指示用 #775 改寫過的（`scripts/stamp-version.sh` 與 `install -m 755`），訊息保留「印 9 的是 #777 之前的建置」。
- #775 的開場檢查（`plugin/hooks/check-cli.sh`）從 SKILL 第 0 步那一行讀契約門檻，所以門檻升到 10 之後，印 9 的 CLI 會在 session 開始時被指出來，並附重建指令。
- 程式（`Sources/`）與規格沒有衝突，也沒有因為這次併入而改動。
