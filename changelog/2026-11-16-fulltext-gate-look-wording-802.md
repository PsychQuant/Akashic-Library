# #802：規格 `fulltext-gate-look`、#777 changelog 與 parity 文件的五處措辭

#777 verify 第 2、3 輪留下的 LOW／INFO（記在 #802）：五處散文與當時的事實沒對齊，程式與測試的行為沒有錯。這一輪只改描述：程式、測試、SKILL、plugin 殼都沒動，`fulltext-contract` 仍是 10。規格：Spectra change `idd-802-fulltext-gate-look-777-changelog-parity`（MODIFIED 三條 requirement，各改一句；既有 scenario 與 Example 原樣保留，對應的測試標記都在）。

## 規格 `fulltext-gate-look`

- **Atypon showLogin**：「導航之前判斷文章站上的 HTML 頁」的括號原本只列 DOI 落地頁落定之後、讀文字時分頁變成的頁兩處。`FulltextFetch` 的 `resume` 在 `.article` 階段（導航之前）也是同一條件下以 `(login page)` 整批暫停，補成三處列齊。
- **讀不到的同站分頁**：補一句既有的順序。服務標記的判斷（`BotSignals.serviceMarker`）先回整批暫停的標記，所以標題或網址同時命中這種標記時，以那個標記整批暫停（exit 6），訊息是那個標記、不含 `(login page)`（`judgeUnreadable` → `stop(for:)` → `botStop`）。先前的寫法讀起來像「只要命中等人驗證的兩個標記之一、路徑是登入長相，訊息就有 `(login page)`」。
- **契約版本**：理由句「Because two cells changed exit code」改成指這幾格。`contractVersion` 註解第 10 版那一段逐格列了四種情形（導航之後同站寫著 CAPTCHA 的頁 8 → 6、別的主機上落定的頁 7 → 6、落地頁與導航之前的同站頁改成 6、讀不到的同站分頁命中標記而路徑有登入長相 8 → 6），不止兩格。

## 文件

- `changelog/2026-11-11-fulltext-login-look-rulings-777.md`：契約版本那一行「兩格的結束碼變了」改成「這幾格」（理由同上）；〈併入 main〉最後一句原本寫「也沒有因為這次併入而改動」，但併入帶進了 #775 的檔，本意是沒有手動修改，改成「`Sources/`、`Tests/`、`openspec/` 沒有手動修改；main 帶進來的檔照原樣」。
- `docs/rulings/mcp-cli-parity.md` 的 `fulltext` 列：b49 那一段 (c) 的「是否保留待使用者裁決（#777 第 4 件，#779 加註）」已在同一列 #777 那一段 (d) 裁決維持，照該檔對已裁決句子的寫法劃掉並指向 (d)，原句全文保留。

## 沒做的

- 沒有為「整批暫停的標記優先」新增 Example 與測試：那是把既有行為寫成新的可執行紀錄，不在這張的範圍內；需要的話另開一張。
- `openspec/changes/archive/` 底下 #777 的封存檔沒動（封存是歷史）。
