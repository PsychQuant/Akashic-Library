# #822：量到的站別做法要寫回 plugin（plugin 殼 0.13.17 → 0.13.18，契約版本不變）

使用者 2026-11-20 17:26（+08:00），正在用 `akashic-fetch-fulltext` 抓一批全文時：「akashic 的plugin要有一個rule是每次更新pdf取用方式都要更新到plugin上」。之後以選單問了三題，回答都是選單上的選項文字（#822 的兩則 Decision comment）：

| 問題 | 回答 | 是不是選單上標成建議的那一個 |
|---|---|---|
| 「更新到 plugin 上」是寫回檔案，還是發布到安裝的版本 | 兩者都要 | 是 |
| 什麼時候寫回 | 整批結束、回報之前 | 是 |
| 範圍 | 所有碰網站的 skill | 不是（建議的是只管取全文）|

## 文件

- `plugin/rules/site-knowledge-goes-back-into-the-plugin.md`（新）：六條。第 1、3、4 條是封閉列舉（什麼算要寫回的更新、寫到哪個檔、誰來寫）；第 6 條是合併之後更新安裝的版本，只適用有原始碼 repo 的維護者，而且合併與更新各自仍要使用者確認。規則自己寫明三件做不到的事：它不自動載入、一般安裝的使用者不送出就到不了 plugin、沒有檢查會發現「量到了卻沒寫」。
- `plugin/skills/akashic-fetch-fulltext/SKILL.md`：第 7 步加「回報之前，把這一批量到的寫回 plugin」；〈相關〉加這條規則；`html-page` 一列括號裡 Wiley epdf 的例子改成兩次量測各自的結果。
- `plugin/skills/akashic-bootstrap/references/web-access.md`：〈其他〉加一點，讓每一個照它取得的 skill 都讀得到這條義務。
- `plugin/skills/akashic-fetch-fulltext/references/publishers.md`：新增〈2026-11-20 的實測〉一節（九篇、六個站，每一列只有表裡寫的篇數）；規則表與先前各節裡被這一批推翻或補上的六處加註。
- `CLAUDE.md`：plugin 規則的說明由兩條改成三條。
- `plugins/akashic-discovery/.claude-plugin/plugin.json` 0.2.17 → 0.2.18 與 `.githooks/plugin-shell-versions.txt` 兩列：`akashic-discovery` 的 `rules/` 連到 `plugin/rules`，新規則讓它的殼內容變了；兩個殼都照 `akashic-guards plugin-shell-version` 印出的摘要接列。

## 這一批量到、但沒有因此改流程的事

- 視窗裡出現顯示 PDF 的分頁之後，`documents --json` 的 `blocking_dialog` 對整個視窗每一次都讀成 `unknown`／`incomplete`（PsychQuant/safari-browser#345，2026-11-20 的實測已補在那一張）。SKILL 第 3 步「按之前不是 `clear` 就不按、仍然 `unknown` 就停下整批」照這個觀察會在第一個 `pdf-shown` 之後擋下後面每一次按。那條規則沒有改：它是往停的方向定的，要不要放寬是使用者的裁決。
- Safari 的下載位置設成固定資料夾時，下載鈕按下去不跳儲存面板。開始前提醒或檢查這個設定是 #823，使用者決定等 PsychQuant/safari-browser#388（讀出這個設定）落地再做，這一次沒有動。
- 存進 store 的 provenance note 寫錯時沒有更正的入口：#824。

## 驗證

只改 Markdown 與 `plugin.json` 的版本號。釘住 SKILL 與 publishers.md 文字的測試與守衛的結果寫在 #822 的實作留言。
