## Why

#781／#780 的第 1 輪 verify（issuecomment-7001377123）判 FAIL：改寫後的 `akashic-fetch-fulltext` SKILL 有三處擋住合併的缺陷，另有 27 處要在這個 branch 修。三處是：別的主機上的登入頁從「整批暫停」降成「跳過這一篇」，與〈整批暫停〉自己的登入長相那一條互相矛盾；按了之後的起疑檢查要讀頁面文字，而規則 5 只准 `snapshot -i`、`click`、`save-pdf`，讀不到；落點表第 2 種與第 9 種可能同時成立，同一個鈕就會被按第二次（違反使用者 2026-11-10 10:39「不按第二次」）。另外，SKILL 寫進了幾件沒有任何 requirement 記著的行為（同站延後、落點表、點擊程序的入口、批次中途的停止），之後改掉也不會有測試失敗。

## What Changes

- 規格 `fulltext-division-of-labour`：記帳那一條 requirement 補上 `--site` 的來源與結束碼 64，Example 改成只看點擊程序裡的記帳那一步；新增七條 requirement，各帶 Example 與帶標記的測試：同站延後（結束碼 8 與按了之後的人類驗證）、落點表的判斷順序與不按第二次、按了之後的讀取與起疑檢查、別的主機上的登入頁整批暫停、點擊程序的入口封閉清單、批次中途停下的封閉清單、頁面來的值經變數進 shell、延到最後的 (c) 一次交一篇。
- SKILL：照上面各條改寫；規則 3 拿掉 `dialog dismiss` 的條件；規則 1 例外 (d) 收 `left-site` 交接之後才顯示 PDF 的同一個分頁；`tab-unchanged` 寫明 `fetch` 的導航算第一下；「連續兩篇同樣的失敗就停」只算「取不到」；`browser-cache` 那一句補上 2026-11-19 的四篇；帳本讀不懂整批停下。
- `references/publishers.md`：EBSCO 閱讀器不走〈一層層按〉（它不是 `fetch` 的結果），列入最後交給使用者的清單；2026-11-10、2026-11-19 那一段只寫 issue 回報過的事。
- 鏡像與程式文字：`akashic-bootstrap` 的 `work-sources.md`、`.claude/rules/web-access-via-safari-browser.md`、`fulltext fetch` 的說明文字與 stderr 的各原因提示、`FulltextFetch.swift` 兩處註解。
- 契約版本維持 11：`fetch` 與 `take` 的結束碼、交接原因都沒有變，只改了 stderr 的提示文字，skill 不解析那些字（與 b37–b41 改 stderr 轉印的字時同一個理由；使用者 2026-11-04 裁決那幾行不升版）。plugin 殼維持 0.13.17（還沒推上 main），重算表裡那一列的摘要。

## Non-Goals

- 不處理 verify 第 31–36 列（follow-up）：`attempt --site` 不收埠號、點擊與記帳沒有機械的綁定、`left-site` 主機下載非 PDF 檔、測試的時鐘、`button` 一下記兩次、沒有對出版商網站實跑。
- 不改 `fetch` 的判斷（結束碼 6／8 分類、交接原因）；只改它印的提示文字。
- 不加 (a)–(e) 以外的交給人類別；清單外的情形照舊列入最後的清單，由使用者決定要不要加一類。
- 不對任何出版商網站送請求。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `fulltext-division-of-labour`: 記帳那一條補 `--site` 的來源與結束碼 64；新增同站延後、落點表的順序、按了之後的讀取、別的主機上的登入頁、點擊程序的入口、批次中途的停止、頁面來的值經變數、延到最後的 (c) 一次交一篇

## Impact

- Affected specs: fulltext-division-of-labour
- Affected code:
  - Modified: plugin/skills/akashic-fetch-fulltext/SKILL.md, plugin/skills/akashic-fetch-fulltext/references/publishers.md, plugin/skills/akashic-bootstrap/references/work-sources.md, .claude/rules/web-access-via-safari-browser.md, Sources/akashic/FulltextCommands.swift, Sources/AkashicSkillTools/FulltextFetch.swift, Tests/AkashicCLITests/FulltextDivisionOfLabourTests.swift, plugin/CHANGELOG.md, changelog/2026-11-19-fulltext-ai-default-781.md, .githooks/plugin-shell-versions.txt
  - New: Tests/AkashicCLITests/FulltextClickProcedureTests.swift
