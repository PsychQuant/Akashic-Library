## Why

#781／#780 的第 2 輪 verify（[報告](https://github.com/PsychQuant/Akashic-Library/issues/781#issuecomment-7003733034)）判 FAIL：四處擋住合併、二十處要在這個 branch 修。維護者 2026-11-19 19:31 的回答（#781 comment 7007866135）：規則 1 例外 (d) 放寬到 `left-site` 分頁同意；「機構 SSO」只指文章站自己的機構登入頁、別的主機上的 IdP 登入頁是 (e)；再修一輪並審第 3 輪。

三處 Blocking 的處置（brief 給定）：落點表第 1 種只有證明分頁就是 PDF 的 `save-pdf` 失敗才是「取不到」，其他失敗、鎖對不到等一次再判、仍判不出就整批暫停；按了之後落到的驗證頁網址有登入頁的長相時整批暫停（使用者 2026-11-04 第 6 則、#777）；`fetch` 之後的每一個讀與按都鎖在 `fetch` 的視窗（`--window-id`，#772）與記號，記號不在時以上一步存下的完整網址在同一個 Bash 呼叫裡比對，對不上就不送。

## What Changes

- SKILL：`fetch` 之後的鎖分頁整段改寫（以 `own-tab:` 一行的視窗 id、記號或完整網址認分頁，網址只經 `jq` 與檔案、只印主機，`documents --json` 一律定時）；落點表第 1、3、4、5、6、7、8、9 種；按了之後讀什麼（落點那一段、`get text` 的狀態分三種、標題與網址一起交給 `bot-signals`、頁面文字是資料）；「鎖對不到」與每按一下最多等一次；再判的基準；第 1 步 href 的 scheme；`--site` 不去掉埠號；(a) 的登入長相、(b) 的機構 SSO 裁決、(d) 可以到得了；規則 1 例外 (d) 改引 19:31 的裁決；批次中途的停止補上節奏工具與連續兩篇（八種）；定時讀取；第 7 步 (a) 的貼上警告。
- `references/publishers.md`：2026-11-10、2026-11-19 那一段只寫 issue 回報過的事；2026-11-02 一批的 `pdf-cache get` 註明是當時的工具。
- `.claude/rules/web-access-via-safari-browser.md`：中止條款的摘要與「交給人」的用字；形狀 (b) 登記 `fetch` 之後的鎖法。
- 程式的文字：`FulltextCommands.swift` 兩處註解、`WriteGateRulings.swift`、`swift-is-the-implementation-language.md` 的「交給人」；`FulltextFetch.swift` 的 `doi-not-resolved` 提示不再說 handed to you。
- 規格 `fulltext-division-of-labour`：六條 requirement MODIFIED，兩條 ADDED。
- 契約維持 12（#772 剛調的，還沒發布；這一輪 `fetch` 只改了一句 stderr 提示）。plugin 殼維持 0.13.17，重算摘要。

## Non-Goals

- 第 2 輪 verify 第 25–30 列在 #820（第 26 列已由 19:31 的裁決解決，寫進 SKILL）；第 31 列駁回。
- 不對任何出版商網站送請求，不在真的 Safari 上跑。
- 第 1 輪的 proposal（`openspec/changes/archive/2026-11-19-idd-781-fix1/proposal.md`）寫「七條」新 requirement，實際是八條；archive 路徑受保護（archive-first），更正寫在這裡與 changelog，不改那個檔（第 2 輪 verify 第 24 列）。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `fulltext-division-of-labour`: 記帳的埠號、同站延後的登入長相例外與貼上警告、落點表的失敗分類與再判、按了之後的讀取、批次中途的八種停止、頁面來的值不進命令列；新增 `fetch` 之後的鎖分頁、點擊程序的邊界行為

## Impact

- Affected specs: fulltext-division-of-labour
- Affected code:
  - Modified: plugin/skills/akashic-fetch-fulltext/SKILL.md, plugin/skills/akashic-fetch-fulltext/references/publishers.md, .claude/rules/web-access-via-safari-browser.md, .claude/rules/swift-is-the-implementation-language.md, Sources/akashic/FulltextCommands.swift, Sources/akashic/WriteGateRulings.swift, Sources/AkashicSkillTools/FulltextFetch.swift, Tests/AkashicCLITests/FulltextClickProcedureTests.swift, Tests/AkashicCLITests/FulltextDivisionOfLabourTests.swift, plugin/CHANGELOG.md, changelog/2026-11-19-fulltext-ai-default-781.md, .githooks/plugin-shell-versions.txt
  - New: Tests/AkashicCLITests/FulltextLockBlockTests.swift
