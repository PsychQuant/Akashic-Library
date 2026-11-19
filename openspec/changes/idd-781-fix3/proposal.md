## Why

#781／#780／#772 的第 3 輪 verify 判 FAIL：四處擋住合併（第 1–4 列：按了之後的分頁追蹤），十八處要在這個 branch 修（第 5–22 列）；第 23–28 列在 #820。維護者 2026-11-19 21:40 的回答（#781 comment 7010880375，「照你的建議作就好」）：`fetch` 印了 profile 時，鎖分頁與落點的每一段都帶 `--profile`；帶記號時的鎖算「鎖定固定視窗」（`ownTabNow` 拒絕固定視窗以外帶記號的分頁，記號每次執行都不同），SKILL 照實改寫；第 1–22 列這一輪全部修，第 1–4 列一起修。

第 1–4 列一起修的設計：記號存在每篇自己的檔（`.mark`），第 3 種收下新分頁時清掉，之後的鎖跟著收下的分頁；按了之後與交出去之後再接都用 `fetch` 的 `stillOurTab` 同一個判法（分頁數變了，那個位置的網址要沒變；顯示過網址的位置變空白不算）；新分頁只在它就在被按的分頁右邊一格、而且是這一下按出來的（其餘分頁都沒變）時才算，主機是被按的那一頁的主機或已知的驗證服務才收，否則只送 `save-pdf` 探測、是 PDF 才收，不是就整批暫停；鎖對不到時，這一篇還沒按過才是「取不到」，按過之後等一次、重取、再判，仍然對不到就是 (e)。

## What Changes

- SKILL：起點那一段（先記號、再 `handover:` 的位置，並存下按之前的基準）、鎖分頁那一段（記號從 `.mark` 讀、按過之後對不到是另一個結束碼、只印主機：去掉帳密，沒有 `://` 的網址只印 scheme、`--profile`）、落點那一段（`stillOurTab` 的判法、`url-changed` 比按的那一刻、新分頁的條件、對話框分兩種、基準檔不在是自己的結束碼）、收下新分頁那一段；落點表第 1、3、4、5 種；鎖對不到；交出去之後再接（(a)、(b)、(d) 都適用，交之前先更新基準）；`tab-unchanged` 與 `button`；讀頁面文字那一段也看 `get title` 的狀態；(b) 不含「Log in for access」；批次中途的停止（八種、(2) 與 (5) 的範圍）；規則 1 (d) 的條件改成 `fetch` 的固定視窗；S:158、S:39 照實描述記號鎖；S:82 讀不到的分頁是「取不到」；整批之前請使用者整批都不要動那個視窗。
- `.claude/rules/web-access-via-safari-browser.md`：R:34、R:64、R:101–102 加上這個 skill 的例外，形狀 (b) 的登記跟著改。
- `references/publishers.md:107`：當時的 `--url` 鎖註明是當時的作法。
- 程式的文字：`fetch` 的 `tab-unchanged` 提示不再說「needs a click」；`FulltextCommands.swift` 的 `--expect-profile` 註解與 `contract --help` 的「交給人」；`FulltextFetch.swift` 的契約版本註解與「交給人」註解。
- `plugin/CHANGELOG.md` 最上面一則的「仍是六種」補註；changelog 記這一輪。
- 規格 `fulltext-division-of-labour`：六條 requirement MODIFIED。
- 契約維持 12、plugin 殼維持 0.13.17（都還沒發布；`fetch` 只改一句 stderr 提示），重算殼摘要。

## Non-Goals

- 第 3 輪 verify 第 23–28 列在 #820。
- 不對任何出版商網站送請求，不在真的 Safari 上跑。
- 更正：fix2 的報告寫 `FulltextLockBlockTests` 有 12 支，實際是 11 支（第 3 輪第 22 列）。archive 路徑受保護，更正寫在這裡與 changelog。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `fulltext-division-of-labour`: 落點表的新分頁與下載、別的主機的登入頁與 (b) 的邊界、批次中途的停止、`fetch` 之後的鎖分頁、點擊程序的邊界行為

## Impact

- Affected specs: fulltext-division-of-labour
- Affected code:
  - Modified: plugin/skills/akashic-fetch-fulltext/SKILL.md, plugin/skills/akashic-fetch-fulltext/references/publishers.md, .claude/rules/web-access-via-safari-browser.md, Sources/AkashicSkillTools/FulltextFetch.swift, Sources/akashic/FulltextCommands.swift, Tests/AkashicCLITests/FulltextLockBlockTests.swift, Tests/AkashicCLITests/FulltextClickProcedureTests.swift, plugin/CHANGELOG.md, changelog/2026-11-19-fulltext-ai-default-781.md, .githooks/plugin-shell-versions.txt
  - New: Tests/AkashicKitTests/FulltextLandingVerificationHostTests.swift
