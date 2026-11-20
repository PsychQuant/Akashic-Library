## Why

#781／#780／#772 的第 4 輪 verify 判 FAIL：四處擋住合併（第 1–4 列），二十五處要在這個 branch 修（第 5–29 列）；第 30–35 列在 #820，第 36 列駁回。第 2、3、4 輪的擋住合併都落在同一處：按了之後怎麼認分頁。三輪各有一條規則建立在沒有人量過的 Safari 行為上，三次都被找出錯。

維護者 2026-11-20 08:42 的回答（#781 comment 7026678467，「照你的建議作就好」，回答協調者提出的四件事）：先在真的 Safari 上量，再修；按了之後的分頁追蹤照「對得上連結才收、其餘停下」重做；兩種分不出來的情形寫成明文限制（使用者在同一刻把分頁開到同一個網址；同一個位置的分頁關掉再補上）；量到 Safari 下載提示的真實字樣之前，所有 `present` 都停下——最後這一點決定留言自己註明是協調者的讀法，不是維護者的原話。

量測在 2026-11-20 做完（#820 comment 7027590817，M0–M8）。它定下六件事：連結開的分頁、`window.open` 的分頁與 ⌘T 的分頁都落在視窗的最後面，位置說不出是誰開的；新分頁在按的命令回來之後的第一次讀取就顯示連結的目標，`get attr … href` 印的是屬性原文，轉址過的連結對不上；按一下可能開出新視窗；按一下可能只改掉被按的分頁的片段、同時開一個分頁；頁面的 `alert` 是 `present`、按的命令不回來，儲存面板是 `unknown`／`incomplete`、沒有文字；分頁自己關掉時一次讀取可能失敗。Safari 的下載權限提示沒有出現，仍然沒有量過。

## What Changes

- **新子命令 `akashic fulltext same-target`**（唯讀）：從三個檔讀被按的那一頁的網址、按之前讀到的 href 原文、新分頁的網址，把 href 對那一頁解析，印 `match`、`differ` 或 `unresolvable`。契約版本 12 → 13，SKILL 第 0 步一起調；`WriteGateRulings`、MCP／CLI parity 裁決列補記（同時補上 #772 契約 12 那一筆，第 23 列）。
- **SKILL 第 3 步重做按了之後的分頁追蹤**（第 1、2、8 列）：按、與按了之後的第一次讀取在同一個 Bash 呼叫裡；新分頁只在「恰好多一個、在最後面、其餘分頁沒變（被按的那一個只准片段不同）、沒有多出視窗、`same-target` 印 `match`」時才收；其餘讓 Safari 變多的情形立刻停下整批（第 (2) 種），不對多出來的分頁或視窗送任何命令，並印出位置與主機。拿掉右邊一格的規則、`same-host`／`verification`／`other`／`unattributed` 四種分類與對別的主機的探測。
- **對話框**（第 3 列）：`present` 一律是第 (3) 種停止，訊息不印也不比；`unknown` 當場停下請使用者看畫面，他確認是儲存面板或下載權限提示就當場處理、批次接著跑；按之前的狀態不是 `clear` 就不按；按的命令定時，沒有回來就接著讀落點。
- **批次結束的交接**（第 4、9、11 列）：每一篇到要交的前一刻才以記號或完整網址認分頁、取基準；做完之後只收文章站、已知驗證服務或交出去那一刻的主機，其餘不讀；同站延後的各篇等全部接完才跑；再接之後回到第 1 步，不走第 9 種；請使用者不動視窗的期間延到最後一篇接完。
- **鎖對不到**（第 6、7 列）：先跑落點那一段（它以位置認分頁、只要不是 `moved` 就改寫 `.url`），再取鎖；還沒按就自己換頁的頁面也照落點表判。
- 第 5、10、12–29 列：各段的結束碼表重寫（基準檔不在是自己的停止，不是 (e)）、探測在驗證服務與登入主機上不跑、profile 的名字從檔讀、位置不是 1 到 n 就拒絕、視窗 id 與 profile 隨每篇的狀態存、標題是空的不算失敗、第 1 步的第五類（同時表示接受條款的下載元件）、`fetch` 的 `tab-unchanged` 提示、publishers.md 的前言與 Ovid 一列、web-access.md 的例外、S:130 的說法。
- **量測放進 plugin**：`references/safari-measurements.md`（M0–M8、環境、沒有量過的）。SKILL、publishers.md 與規格裡每一句說 Safari 怎麼反應的話都指到它的某一列，或寫明沒有量過。
- 測試：`FulltextLockBlockTests` 的 fixture 改成量到的版面（各註明 M 編號），加按與落點同一個呼叫、兩篇交接、再接、鎖對不到的復原、位置重複、profile 檔；`same-target` 的 CLI 測試；文字測試跟著 Example 改。
- 規格：`fulltext-division-of-labour` 九條 MODIFIED、兩條 ADDED；`fulltext-gate-look` 契約 12 → 13；`fulltext-window-lock` 的門檻字樣。
- plugin 殼維持 0.13.17（還沒發布），重算殼摘要。

## Non-Goals

- 第 4 輪 verify 第 30–35 列在 #820；第 36 列駁回。
- 不對任何出版商網站送請求，不在真的 Safari 上跑。量測是協調者與維護者做的，這個 change 只引用它。
- Safari 下載權限提示的字樣沒有量到，所以不恢復「提示是 (c)、先跳過」的寫法；量到之後另案。
- 不替登入主機的長相另寫一個子命令或 `jq` 解析（第 30 列在 #820）：探測要不要跑，看落點那一段印的 `vsvc` 與主機，由模型照〈整批暫停〉的主機規則判。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `fulltext-division-of-labour`: 按了之後的新分頁與新視窗、對話框、批次結束的交接、鎖對不到的復原、各段的結束碼、`same-target` 子命令、量測的引用
- `fulltext-gate-look`: 契約版本 13
- `fulltext-window-lock`: SKILL 第 0 步的門檻字樣

## Impact

- Affected specs: fulltext-division-of-labour, fulltext-gate-look, fulltext-window-lock
- Affected code:
  - New: Sources/AkashicSkillTools/FulltextSameTarget.swift, Tests/AkashicCLITests/FulltextSameTargetCLITests.swift, plugin/skills/akashic-fetch-fulltext/references/safari-measurements.md
  - Modified: Sources/akashic/FulltextCommands.swift, Sources/akashic/WriteGateRulings.swift, Sources/AkashicSkillTools/FulltextFetch.swift, plugin/skills/akashic-fetch-fulltext/SKILL.md, plugin/skills/akashic-fetch-fulltext/references/publishers.md, plugin/skills/akashic-bootstrap/references/web-access.md, .claude/rules/web-access-via-safari-browser.md, docs/rulings/mcp-cli-parity.md, Tests/AkashicCLITests/FulltextLockBlockTests.swift, Tests/AkashicCLITests/FulltextClickProcedureTests.swift, Tests/AkashicKitTests/FulltextLandingVerificationHostTests.swift, Tests/AkashicKitTests/FulltextLoginLookRulingsTests.swift, Tests/AkashicKitTests/FulltextFetchPathTests.swift, plugin/CHANGELOG.md, changelog/2026-11-19-fulltext-ai-default-781.md, .githooks/plugin-shell-versions.txt
