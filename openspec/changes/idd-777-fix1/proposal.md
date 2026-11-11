## Why

#777 的第 1 輪 verify 指出：規格 `fulltext-gate-look` 只寫了「`/action/showLogin` 算登入頁長相」的兩格後果（導航之後同站寫著 CAPTCHA、別的主機），而同一個判斷在導航之前也改了結束碼（DOI 落地頁、讀頁面當中轉過去的同站頁），這兩格沒有 Example、沒有測試。另有兩處規格與程式對不上：正規化的敘述沒有提百分比解碼，讀不到的分頁那一條沒有寫明「路徑是驗證頁的長相時仍是等人驗證」。

## What Changes

- 第一條 requirement：正規化的敘述補上百分比解碼（程式本來就先解碼）；寫明導航之前判到這個長相的文章站頁面整批暫停；加三個 Example（百分比編碼的寫法、落地頁、讀頁面當中轉過去）。
- 第二條 requirement：寫明標記命中而路徑不是登入長相時照原本的訊號處理；加一個 Example（路徑是驗證頁的長相 `/captcha/x`，仍是等人驗證，結束碼 8）。
- 程式的行為不變；這個 change 只補規格、測試與文字。契約版本維持 10。

## Non-Goals

- 不改 `BotSignals` 與 `FulltextFetch` 的判斷。
- 不處理「導航之前要不要先判 PDF 連結的 href」：那是既有行為，改它需要使用者裁決，另開 issue。
- 不替第 3、4 件（維持現行行為）加 requirement；第 3 件補一支不帶標記的測試。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `fulltext-gate-look`: 補上導航之前的兩格、百分比解碼，以及讀不到的分頁在驗證頁長相的路徑上仍等人驗證

## Impact

- Affected specs: fulltext-gate-look
- Affected code:
  - Modified: Tests/AkashicKitTests/FulltextLoginLookRulingsTests.swift, Tests/AkashicKitTests/FulltextB37Tests.swift, Tests/AkashicKitTests/FulltextOffSiteTests.swift, Sources/AkashicSkillTools/FulltextFetch.swift, Sources/AkashicSkillTools/BotSignals.swift, plugin/skills/akashic-fetch-fulltext/SKILL.md, plugin/CHANGELOG.md, changelog/2026-11-11-fulltext-login-look-rulings-777.md, .githooks/plugin-shell-versions.txt
  - `Sources/` 底下只改註解
