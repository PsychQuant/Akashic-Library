# #822：量到的站別做法要寫回 plugin（plugin 殼 0.13.17 → 0.13.18，契約版本不變）

使用者 2026-11-20 17:26（+08:00），正在用 `akashic-fetch-fulltext` 抓一批全文時：「akashic 的plugin要有一個rule是每次更新pdf取用方式都要更新到plugin上」。之後以選單問了三題，回答都是選單上的選項文字（#822 的兩則 Decision comment）：

| 問題 | 回答 | 是不是選單上標成建議的那一個 |
|---|---|---|
| 「更新到 plugin 上」是寫回檔案，還是發布到安裝的版本 | 兩者都要 | 是 |
| 什麼時候寫回 | 整批結束、回報之前 | 是 |
| 範圍 | 所有碰網站的 skill | 不是（建議的是只管取全文）|

## 文件

- `plugin/rules/site-knowledge-goes-back-into-the-plugin.md`（新）：六條。第 1、3、4 條是封閉列舉（什麼算要寫回的更新、寫到哪個檔、誰來寫）；第 6 條是合併之後更新安裝的版本，只適用有原始碼 repo 的維護者，而且合併與更新各自仍要使用者確認。規則自己寫明三件做不到的事：它不自動載入（靠各 skill 引用，守衛只保證連結在）、一般安裝的使用者不送出就到不了 plugin、沒有檢查會發現「量到了卻沒寫」。
- `plugin/skills/akashic-fetch-fulltext/SKILL.md`：第 7 步加「回報之前，把這一批量到的寫回 plugin」；〈相關〉加這條規則；`html-page` 一列括號裡 Wiley epdf 的例子改成兩次量測各自的結果。
- `plugin/skills/akashic-bootstrap/references/web-access.md`：〈其他〉加一點，讓每一個照它取得的 skill 都讀得到這條義務。
- 其餘十個 skill 的 `SKILL.md`（akashic-mcp 九個、akashic-discovery 的 `akashic-work-references` 一個）：各加一行指向這條規則。規則覆蓋的守衛（`run-guards.sh` 的 rule coverage，兩個 plugin 根各跑一次）要求每一條 plugin 規則都被每一個 skill 以可解析的相對路徑引用；第一次跑守衛時這十個 skill 缺這個連結。（這一點原本寫「九個」，少算了 akashic-discovery 那一個，#822 verify 第 1 輪第 15 列。）`akashic-merge-twins`、`akashic-promote-literals`、`akashic-verify-work` 沒有自己的網頁取得步驟，那一行照實這樣寫。
- `plugin/skills/akashic-fetch-fulltext/references/publishers.md`：新增〈2026-11-20 的實測〉一節（九篇、六個站，每一列只有表裡寫的篇數）；規則表與先前各節裡被這一批推翻或補上的六處加註。
- `CLAUDE.md`：plugin 規則的說明由兩條改成三條。
- `plugins/akashic-discovery/.claude-plugin/plugin.json` 0.2.17 → 0.2.18 與 `.githooks/plugin-shell-versions.txt` 兩列：`akashic-discovery` 的 `rules/` 連到 `plugin/rules`，新規則讓它的殼內容變了；兩個殼都照 `akashic-guards plugin-shell-version` 印出的摘要接列。

## 這一批量到、但沒有因此改流程的事

- 視窗裡出現顯示 PDF 的分頁之後，`documents --json` 的 `blocking_dialog` 對整個視窗每一次都讀成 `unknown`／`incomplete`（PsychQuant/safari-browser#345，2026-11-20 的實測已補在那一張）。SKILL 第 3 步「按之前不是 `clear` 就不按、仍然 `unknown` 就停下整批」照這個觀察會在第一個 `pdf-shown` 之後擋下後面每一次按。那條規則沒有改：它是往停的方向定的，要不要放寬是使用者的裁決。（2026-11-21 更正：「擋下後面每一次按」是推論；#828 量到狀態跟著視窗的作用中分頁走，作用中分頁不顯示 PDF 時是 `clear`。量測記在 `safari-measurements.md` 的 P2。）
- Safari 的下載位置設成固定資料夾時，下載鈕按下去不跳儲存面板（2026-11-21 收窄：量到的是 SAGE 與 Wiley 各一篇沒有出現面板，加上使用者說當天下載位置是固定資料夾；面板出不出現是不是由這個設定決定，沒有同一天改設定前後的對照，#822 verify 第 1 輪第 6 列）。開始前提醒或檢查這個設定是 #823，使用者決定等 PsychQuant/safari-browser#388（讀出這個設定）落地再做，這一次沒有動。
- 存進 store 的 provenance note 寫錯時沒有更正的入口：#824。

## 驗證

改的是 Markdown、兩個 `plugin.json` 的版本號、兩個守衛資料檔（`.githooks/plugin-shell-versions.txt`、`.githooks/protected-ratchet.txt`），與一個 Swift 檔的一行（`Sources/akashic-guards/AuditGuardsMutationsData.swift`，負對照多刪一個規則檔）。（這一句原本寫「只改 Markdown 與 `plugin.json` 的版本號」，#822 verify 第 1 輪第 15 列。）釘住 SKILL 與 publishers.md 文字的測試與守衛的結果寫在 #822 的實作留言。
