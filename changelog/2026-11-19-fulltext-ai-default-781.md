# #781／#780：取全文預設由 Claude 做，交給人只有封閉清單（plugin 殼 0.13.16 → 0.13.17，契約版本 10 → 11）

使用者 2026-11-10：「skill是不是沒走說好哪些是可以ai做的，哪些必定要人做，我自己覺得預設AI做，除非需要人」（#781）、「如果頁面導覽之後才能下載的話你需要按」（#780）；2026-11-19 再確認：「妳可以預設你自己按嗎？因為剛開始我叫你下載就是授權你下載到最後了」。各題的裁決在兩張 issue 的 Decision comment。規格：Spectra change `idd-781-fetch-fulltext-ai-default`（新 capability `fulltext-attempt-accounting`、`fulltext-division-of-labour`；`fulltext-gate-look` 的契約版本那一條換成 11）。

## 程式

- **新子命令 `akashic fulltext attempt --site <主機> --landing <網址>`**（`Sources/AkashicSkillTools/FulltextAttempt.swift`、`Sources/akashic/FulltextCommands.swift`）：在與 `fetch` 共用的每日嘗試帳本上記一次，走同一個 `FulltextAttemptLedger.reserve`（跨行程的鎖之下查數並記錄）。
  - 記到：結束碼 0，stdout 一行 `attempt: <站> <n>/10 <日>`（與 `fetch` 記到時印的同一個形狀）。
  - 該站當天已滿：結束碼 9，stdout 一行 `cap: <站> <n>/10 <日>`，帳本不變。意思與 `fetch` 的 9 相同。
  - 帳本讀不懂或寫不了：結束碼 1，帳本不變。
  - `--site` 不是乾淨的 DNS 主機名稱（帶 scheme、路徑、帳密、埠號、百分比編碼、空白）或 `--landing` 不是絕對的 https 網址：結束碼 64，在碰帳本之前擋下，不建帳本。
  - 主機小寫化之後當鍵。**已知的差別**：`fetch` 的鍵是文章頁的「主機加埠號」，`attempt` 不收埠號；文章站開在非預設埠時兩邊的鍵會不同。沒有遇過這樣的出版商，沒有處理。
  - 不碰瀏覽器、不連網、不經 `openStore`。`WriteGateRulings` 記成 readOnly（帳本在 store 之外，與 `fetch` 同一個理由）；`docs/rulings/mcp-cli-parity.md` 的 `fulltext` 一列補上它與不開 MCP 面的理由。
- **契約版本 10 → 11**（`FulltextFetch.contractVersion`）：`fetch` 與 `take` 的結束碼、交接的原因、哪些頁面整批暫停都沒有變。調它是因為 SKILL 開始依賴 `attempt`：印 10 的 CLI 配上新的 SKILL，Claude 按的每一下都不會記帳。型別註解的〈契約版本〉補上「skill 開始依賴一個新的子命令時也調」。
- `fetch` 本身的行為沒有改。它印的字仍是 hand over；SKILL 把結束碼 7 稱為「交接」，接手的是 Claude。

## SKILL（`plugin/skills/akashic-fetch-fulltext/SKILL.md`）

- 新增〈人機分工〉：預設由 Claude 做；交給使用者的封閉清單 (a)–(d) 與 (e)；(a)–(d) 的那一篇先跳過、整批跑完一次交給使用者；兩種結局（交給人、取不到）分開。
- 規則 1 的例外 (d) 放寬到「Claude 從這篇自己的連結一路按到的分頁」；(a)(b)(c) 不變。
- 規則 3 改成預設可按這篇自己的連結；規則 4 不再等使用者處理完上一篇；規則 5 寫明 Claude 對頁面做的只有 safari-browser 自己的 `snapshot -i`、`click`、`save-pdf`。
- 〈中止條款〉的等人驗證：那一篇與同一批同站剩下的各篇延到最後（使用者 2026-11-10 10:49 選 A）。結束碼 6／8 怎麼分類、已知驗證主機的清單都沒有動（#819 另案）。
- 第 2 步：開放版本不在批次中途問，只在回報列出。
- 第 3 步：結束碼 3 與 `points off-site` 不再直接列入需要人；〈交給人之後〉改成〈結束碼 7 之後〉，七個原因逐列改寫；新增〈一層層按〉（四步、落點九種）；刪「不要代按任何按鈕」。
- 第 4 步檔案來源的第一種由 `pdf-cache get` 的輸出改成 `safari-browser save-pdf` 的輸出；第 5 步 `acquisition` 多一個值；第 7 步回報分兩張清單。
- 〈不做的事〉：「不代替使用者按登入、授權、「接受」、下載之類的按鈕」拿掉「下載」，加上付費；那一條原本寫是 safari-browser skill 的規定，查過該 skill 沒有這一條，改成本 skill 自己的規定。
- 〈每站每天 10 次嘗試〉：Claude 按的每一下也算。
- 第 0 步門檻 11，版本沿革加版本 11。

## `acquisition` 的新值：`browser-save-pdf`

使用者 2026-11-10 10:39 裁決：Claude 用 `save-pdf` 取得的檔，取得記錄記成與使用者自己存檔不同的值；名稱留到實作時定。定為 **`browser-save-pdf`**。`browser-download` 仍是瀏覽器自己下載的與使用者存的檔。程式不驗這個欄位（`store-source` 只擋空字串），所以只改了 SKILL。store 裡先前記成 `browser-cache` 的（`pdf-cache` 時期，以及 2026-11-19 那一批以 `save-pdf` 取得的四篇）沒有回頭改。

## 沒有做的、沒有量的

- **沒有對任何出版商網站跑過這一版**。〈一層層按〉的程序與落點表是照 2026-11-10、2026-11-19 兩批的紀錄寫的，那兩批都在這份 SKILL 之前。合併前要由維護者在場重跑：SAGE（兩下之後的儲存面板）、Ovid／LWW、AME、一篇 `pdf-shown`，並確認每一下都記進帳本。
- Annual Reviews 的表單按鈕（`button`）改成由 Claude 按，按下去之後的行為沒有實測過。
- 落點第 9 種（按了之後沒有變化）：Claude 分不出是儲存面板在等、權限提示在等、還是什麼都沒發生。SKILL 寫成不猜、請使用者看畫面，列在最後交給使用者的清單。它嚴格說不在五類封閉清單的任何一類裡（可能是 (c)，也可能不是）；這是照使用者 2026-11-10 10:39「等頁面落定一次，再交給人」寫的，沒有另立一類。
- `fetch` 結束碼 1 的幾種自動化失敗（別的 profile 的視窗開著、分頁清單不可信、分頁對不上）原本就寫「告訴使用者、等他處理」，這次沒有改：那些是使用者自己的 Safari 的狀態，不是某一篇取不取得到。
- `safari-browser documents --json` 的 `blocking_dialog` 讀不讀得到 Safari 的下載權限提示，沒有量過；儲存面板確定讀不到（PsychQuant/safari-browser#358）。
