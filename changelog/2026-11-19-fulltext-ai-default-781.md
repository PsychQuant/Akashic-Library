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
- `fetch` 本身的行為沒有改。它印的字仍是 hand over；SKILL 把結束碼 7 稱為「交接」，接手的是 Claude。第 1 輪 verify 之後，各原因的提示文字跟著改（見最後一節）。

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

## 第 1 輪 verify 之後（Spectra change `idd-781-fix1`）

第 1 輪 verify（#781 issuecomment-7001377123）判 FAIL：三處擋住合併、27 處要在這個 branch 修。這一輪照它們改，規格 `fulltext-division-of-labour` 多了八條 requirement、記帳那一條補上 `--site` 的來源與結束碼 64，每個 Example 一支帶標記的測試（`Tests/AkashicCLITests/FulltextClickProcedureTests.swift`），都先在 5aa42d02 的 SKILL 上看它們失敗。契約版本維持 11，plugin 殼維持 0.13.17（還沒推上 main，只重算表裡那一列的摘要）。

**三處擋住合併的**：

- **別的主機上的登入頁恢復整批暫停**。上一版把 `left-site` 與落點表第 6 種的登入頁一律當成 (b)，與〈整批暫停〉的登入長相那一條矛盾，也沒有使用者裁決。現在 (b) 只給文章站本身的登入頁；別的主機上要求登入、或有登入頁長相的頁面是 (e)，與基底版本相同（使用者 2026-11-10 10:34 說中止條款不變）。別的主機上要求登入而沒有命中登入長相的那一種，基底是由使用者看了判；這一版照「只有文章站是 (b)」寫成 (e)，這一格沒有使用者裁決。
- **按了之後讀得到頁面文字**。規則 5 的封閉清單加上 safari-browser 的唯讀命令 `get url`、`get title`、不帶選擇器的 `get text`、`get attr <ref> href`；落點表的起疑檢查以 `get text` 讀整頁文字交給 `akashic fulltext bot-signals --kind`。讀不到文字的落定網頁是 (e)，與〈整批暫停〉第五點同一條；鎖對不到分頁是「取不到」。
- **落點表有判斷順序**：5 → 3 → 4 → 1 → 8 → 6 → 7 → 9 → 2。第 2 種只在頁面換了（網址變了或新分頁）而且是另一個元件時成立，剛按的那一個不算；「沒有變化」排在它前面，所以同一個鈕不會被按第二次。

**其餘各列**：按了之後落到的人類驗證也是 (a)（主機條件與結束碼 8 相同），同站剩下的各篇一起延後，它沒有 `resume:` 一行，使用者驗證完之後不重新載入、用落點表重判同一個分頁；「同一個站」用 `fetch` 印過的主機，還沒跑到的用 DOI 前綴（經驗法則）；等一次之後第 1 到第 8 種都重判；對不上任何一種、以及〈人機分工〉清單外的情形，都列入最後交給使用者的清單；第 1 種的 `save-pdf` 說 `not a PDF` 時往下判，其他失敗才是「取不到」；鎖分頁的 `$lock` 在同一個 Bash 呼叫裡以 `jq -r` 從 `documents --json` 取進變數（網址的路徑可以帶 `$(…)`），`--site` 只在主機是乾淨的字元時放進單引號；按之前以 `get attr` 讀 href，指到別的主機不按；`--site` 沒有 `attempt:` 一行時用 `page:` 一行的主機，`attempt` 結束碼 64 是「取不到」；批次中途停下的封閉清單從四種變六種（加上帳本讀不懂、按了之後的定時讀取 Safari 沒有回答），中途詢問只有兩處，Finder 改檔名移到最後；第 5、9 種之後下一篇之前以 `perl` 的 `alarm` 做一次 20 秒的定時讀取（**沒有量過**：掛著儲存面板時下一篇會怎樣、20 秒夠不夠都沒有實測）；延到最後的那幾篇一次交一篇，(c) 的每一篇交之前 `touch` 一個 `.handover` 記號，只取比它新的檔；「連續兩篇同樣的失敗就停」只算「取不到」；規則 3 拿掉 `dialog dismiss` 的條件；規則 1 例外 (d) 收 `left-site` 交接之後才顯示 PDF 的同一個分頁；`tab-unchanged` 寫明 `fetch` 的導航算第一下（基底版本在這裡由使用者授權後再按一下，#781 起不再按）；點擊程序的入口寫明不經 `fetch` 到達的頁面不算，EBSCO 閱讀器因此列入最後交給使用者的清單（要加成入口需要使用者裁決）；`browser-cache` 那一句補上 2026-11-19 的四篇；`publishers.md` 2026-11-10、2026-11-19 那一段拿掉 issue 沒有回報的話（機構網路、2026-11-10 是誰按的）。

**鏡像與程式文字**：`akashic-bootstrap` 的 `work-sources.md` 取 PDF 那一句、`.claude/rules/web-access-via-safari-browser.md`〈不適用〉第 3 類的例子、`fulltext fetch` 的說明文字、`fetch` 在 stderr 印的 `pdf-shown`、`unverifiable`、`left-site` 三種提示（先前寫 save it yourself），以及 `FulltextFetch.swift` 的註解。提示文字的改動不升契約版本：skill 不解析那些字（與 b37–b41 改 stderr 轉印的字時同一個理由）。

**沒有做的**：verify 第 31–36 列留作 follow-up（`attempt --site` 不收埠號、點擊與記帳沒有機械的綁定、`left-site` 主機下載非 PDF 檔、測試的時鐘、`button` 一下記兩次、沒有對出版商網站實跑）。這一輪同樣沒有對任何出版商網站跑過。
