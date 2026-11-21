# #802：規格 `fulltext-gate-look`、#777 changelog 與 parity 文件的五處措辭

#777 verify 第 2、3 輪留下的 LOW／INFO（記在 #802）：五處散文與當時的事實沒對齊，程式與測試的行為沒有錯。這一輪只改描述：程式、測試、SKILL、plugin 殼都沒動，~~`fulltext-contract` 仍是 10~~ → 這一輪本身不動契約；併入 main 之後是 #821 的 13（見〈併入 main〉）。規格：Spectra change `idd-802-fulltext-gate-look-777-changelog-parity`（~~MODIFIED 三條 requirement，各改一句；既有 scenario 與 Example 原樣保留，對應的測試標記都在~~ → 併入 main 之後，主規格裡是這張改的兩條各一句（Atypon showLogin、讀不到的同站分頁），兩條的 Example 原樣保留、標記都在；第三條與它的 Example 由 #821 的改寫取代，見〈併入 main〉），以及修正輪的 `idd-802-fix1`（見〈verify 第 2 輪之後〉）。

## 規格 `fulltext-gate-look`

- **Atypon showLogin**：「導航之前判斷文章站上的 HTML 頁」的括號原本只列 DOI 落地頁落定之後、讀文字時分頁變成的頁兩處。`FulltextFetch` 的 `resume` 在 `.article` 階段（導航之前）也是同一條件下以 `(login page)` 整批暫停，補成三處列齊。
- **讀不到的同站分頁**：補一句既有的順序。服務標記的判斷（`BotSignals.serviceMarker`）先回整批暫停的標記，所以主機不是登入主機的長相、而標題或網址同時命中這種標記時，以那個標記整批暫停（exit 6），訊息是那個標記、不含 `(login page)`（`judgeUnreadable` → `stop(for:)` → `botStop`）。主機本身是登入主機的長相時，`judgeUnreadable` 先判 `hostLoginLook`，訊息仍帶 `(login page)`（spectra-verify 指出，正常流程碰不到：落地頁與 `.article` 的 resume 都先擋下）。先前的寫法讀起來像「只要命中等人驗證的兩個標記之一、路徑是登入長相，訊息就有 `(login page)`」。
- ~~**契約版本**：理由句「Because two cells changed exit code」改成指這幾格。`contractVersion` 註解第 10 版那一段逐格列了四種情形（導航之後同站寫著 CAPTCHA 的頁 8 → 6、別的主機上落定的頁 7 → 6、落地頁與導航之前的同站頁改成 6、讀不到的同站分頁命中標記而路徑有登入長相 8 → 6），不止兩格。~~ → 併入 main 時作廢：#821 把這條 requirement 改寫成 `SHALL be 13`、整句拿掉（見〈併入 main〉）。

## 文件

- `changelog/2026-11-11-fulltext-login-look-rulings-777.md`：契約版本那一行「兩格的結束碼變了」改成「這幾格」（理由同上）；〈併入 main〉最後一句原本寫「也沒有因為這次併入而改動」，但併入帶進了 #775 的檔，本意是沒有手動修改，改成「`Sources/`、`Tests/`、`openspec/` 沒有手動修改；main 帶進來的檔照原樣」。
- `docs/rulings/mcp-cli-parity.md` 的 `fulltext` 列：b49 那一段 (c) 的「是否保留待使用者裁決（#777 第 4 件，#779 加註）」已在同一列 #777 那一段 (d) 裁決維持，照該檔對已裁決句子的寫法劃掉並指向 (d)，原句全文保留。

## 沒做的

- 沒有為「整批暫停的標記優先」新增 Example 與測試：那是把既有行為寫成新的可執行紀錄，不在這張的範圍內；需要的話另開一張。
- `openspec/changes/archive/` 底下 #777 的封存檔沒動（封存是歷史）。

## 併入 main（2026-11-21）

這條 branch 在 main `82c63451` 之上合併（main 在 #802 之後多了 #821、#826 兩個 commit），兩個檔有衝突：

- `openspec/specs/fulltext-gate-look/spec.md`：#821 把「The fetch contract version SHALL be 10」改寫成「SHALL be 13」，「Because two cells changed exit code」那句整句拿掉，所以這張要改的規格第三條（契約版本的理由句）已經沒有句子可改，照 main 的版本。另外兩條 requirement（Atypon showLogin、讀不到的同站分頁）#821 沒有改，照這張的版本。這兩句描述的程式行為，對照 #821 之後的 `FulltextFetch.swift` 仍成立：導航之前的接續仍經 `botCheckPage(site, beforeNavigation: true)`，在登入長相上整批暫停；`judgeUnreadable` 的判斷順序沒變；`BotSignals`（`serviceMarker` 的先後順序）#821 沒有動。
- `docs/rulings/mcp-cli-parity.md` 的 `fulltext` 列：#821 改的是子命令清單並在列尾補了三段紀錄，這張改的是中間那句裁決，兩處不重疊，都保留。

`openspec/changes/archive/` 底下這張的 delta 照寫入當時的樣子保留，裡面仍記著契約那條 MODIFIED（封存是歷史，不回頭改）。同一個封存目錄的 proposal 與 tasks 寫的「`fulltext-contract` 仍是 10」也是併入之前的歷史；它們的摘要把「整批暫停的標記優先」寫得比 delta 寬，少了「主機不是登入主機的長相」這個前提（delta 有寫，上面〈規格〉那一條也有）。

## verify 第 2 輪之後（2026-11-21）

#802 verify 第 2 輪（審 `82c63451..1de0f7fe`，https://github.com/PsychQuant/Akashic-Library/issues/802#issuecomment-7065139102 ）判 PASS 但不乾淨：0 blocking，1 個 MEDIUM 與 4 個 LOW／INFO 的 In-scope fix。使用者決定再修一輪、驗第 3 輪。

- **規格**（第 1 列，MEDIUM）：這張插進「讀不到的同站分頁」那條的句子把「The marker found」定義成服務標記判斷回傳的那一個（可能是整批暫停的標記），下一句「When the marker is found and the path does not have the look of a login page …… exit 8」因此可以讀成也涵蓋整批暫停的標記，與前一句的 exit 6 衝突。經 Spectra change `idd-802-fix1` 改成「When the service-marker check returns `cloudflare-challenge` or `perimeterx-press-and-hold` and the path does not have the look of a login page」。程式本來就是這樣（`judgeUnreadable` 只在 `hit.response == .humanVerification` 時走等人驗證），四個 Example 不變。
- **這份 changelog**（第 2–5 列）：開頭的「三條……標記都在」改寫成併入之後的說法；契約那一條整段劃線、拿掉沒劃線的重複；原本以序號稱呼的規格第三條改成以內容稱呼（照 issue Problem 的編號，第 3 項是 Atypon 那一句；#802 的 merge note 一併更正）；〈併入 main〉補上封存 proposal 與 tasks 的說明。
