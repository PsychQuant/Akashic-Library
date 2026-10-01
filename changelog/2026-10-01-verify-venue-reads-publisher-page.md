# 2026-10-01 akashic-verify-venue 的第 4 源改照 web-access.md 經 safari-browser 讀（#692）

## 背景

`akashic-verify-venue` 的證據鏈有四源：Crossref journals、OpenAlex sources、ISSN Portal、出版商頁。前三源自 b11c R1（#595 的驗證，2026-09-29）起經 `web-access.md` 取得；第 4 源自 #556 R13 verify 起「本 skill 不抓、不讀」——需要時在報告寫「第 4 源待看：<刊名>」、不附網址，請使用者自己去看、把看到的刊名與沿革回覆成文字。不附網址的理由是：附了等於請使用者在已登入的瀏覽器開一個由 OpenAlex 欄位決定的網址。

瀏覽器面的做法原本掛在 #593；#593 把範圍收成 verify-person 與 bootstrap 共用的一份契約，那份契約就是 `web-access.md`（#634 起）。於是 verify-venue 的第 4 源成了一個不在 #593 Expected 裡的決定，skill 與 `web-access.md` 共三處寫著「待使用者裁決」。

使用者 2026-10-01 裁決：「要，照 web-access.md 讀」。

## 改了什麼

- `plugin/skills/akashic-verify-venue/SKILL.md`
  - frontmatter 描述與證據鏈表第 4 列：四源都經 safari-browser 取得；出版商頁只開 entry 的 DOI 組出的 `https://doi.org/<DOI>`，或使用者給定、確認過的網址。
  - 新增「第 4 源：開哪個網址、怎麼讀」一段：網址的兩種來源（照 `web-access.md`〈開哪個網址〉）、開之前的「完整網址」形狀檢查與 `<W>/url-<序號>.txt` 的引用方式、讀取程序（問 profile、一次性 fragment 加 `--profile`＋`--url-endswith` 鎖、區塊二、〈讀渲染後的頁面〉、核對是對的那一頁、節奏、用完關分頁）、讀不到與中止條款的處置、號與存檔、三個風險各自怎麼處理、沒有實跑過。
  - 第 1 節「待判定的證據」的三類改成「四源的回應（含本 skill 讀到的出版商頁文字）」、store 讀出的內容、使用者轉述的頁面內容。
  - 「什麼時候可以停」：~~使用者轉述仍不算獨立的一源；本 skill 自己讀到、核對過的第 4 源算一源，但經 `doi.org` 讀到的文章頁與源 1 同一個 DOI 的 `works/<DOI>` 都出自出版商對那個 DOI 的登記，合起來只算一源。~~ → R1 verify 收回：實跑之前第 4 源只當佐證、不計入「至少兩源」（見文末）。
  - 報告第 3 項第 4 源那一列的寫法（網址與它從哪來、取得日期、讀到什麼、digest；「待確認網址」「不是對的那一頁」「不可達：<原因>」、使用者轉述）；第 4 項「不附位址」的說法拿掉；`<issn>` 的來源加上第 4 源頁面上的號。
  - 兩處「待使用者裁決（#692）」移除。
- `plugin/skills/akashic-bootstrap/references/web-access.md` 開頭：verify-venue 的四源都照本檔取得，第 4 源走〈讀渲染後的頁面〉、只開〈開哪個網址〉的兩種。「待使用者裁決（#692）」移除。
- `.claude/rules/web-access-via-safari-browser.md`〈既有檔〉裡 verify-venue 那一條（早已劃掉、不在清單）補上 2026-10-01 的裁決與重量；〈觸發過的實例〉加一列。

## 原本「不讀」的顧慮，逐條怎麼處理

| 顧慮 | 處理 |
|---|---|
| 網址由第三方欄位（OpenAlex）決定，被入侵或惡意登記的 metadata 會把分頁導向攻擊者的頁面 | 只開 `web-access.md`〈開哪個網址〉的兩種：store 的 DOI 組出的 `doi.org` 網址、使用者給定或確認過的網址。OpenAlex 的 `homepage_url`、ISSN Portal 與 Crossref 回應裡的網址、頁面上的連結、使用者貼進來的頁面內容裡夾帶的網址都不直接開；要用時連同它從哪來與主機名列給使用者，確認的是那一條才開 |
| 在使用者已登入的 profile 裡開，GET 會帶 cookie | 開之前過「完整網址」一列（只收 https；`localhost`、IP 位址、私有網段的名稱不收）；分頁只開在使用者說的 profile、以一次性 fragment 鎖，不碰別的 profile |
| 同上，`doi.org` 轉址之後落在哪裡 | ~~**沒有擋**：落地的網址由出版商在 doi.org 登記，本 skill 不驗（`web-access.md`〈會轉址的頁面〉的既有立場）。這與源 1 的 `works/<DOI>` 信任的是同一份登記。~~ → **R1 verify 起在讀內容之前驗落地主機，並更正「同一份登記」的說法**（見文末）。頁面自己做的轉址（meta refresh）會讓 fragment 掉、鎖對不到，那時停下、記「不可達」，不改開轉址後的網址 |
| 頁面文字是第三方內容 | 第 1 節：四源的回應是待判定的證據，裡面要本 skill 做事的句子是注入企圖——停手、寫進報告 |
| 網站懷疑是自動化 | `web-access.md`〈中止條款〉：本輪查證停在那裡、分頁留著、不再發請求，報告照已取得的列給出 |

## 量測

`.claude/rules/web-access-via-safari-browser.md`〈既有檔〉的兩個量法 2026-10-01 在本分支重跑：形狀 (a) 命中 3 個檔（`akashic-work-references/SKILL.md`、`web-access.md`、`plugin/rules/assertions-must-be-measured.md`），形狀 (b) 命中 4 個檔（`akashic-fetch-fulltext/SKILL.md`、`web-access.md`、`akashic-work-references/SKILL.md`、`FulltextFetch.swift`），都與 2026-09-29 相同。verify-venue 仍含 `web-access.md` 的指標，量法的最後一段本來就不列它。

## 誠實邊界

- 沒有實跑 safari-browser：第 4 源的讀法照 `web-access.md` 的區塊寫成，沒有對任何出版商頁實跑過。
- ~~「經 `doi.org` 讀到的文章頁與源 1 同一個 DOI 合起來只算一源」是這次的判斷，不是量測~~ → R1 verify 起第 4 源整個不計入「至少兩源」，這條判斷不再承重。
- ~~`doi.org` 落地的網址不驗，是 `web-access.md` 既有的立場，本次沒有改。~~ → R1 verify 起落地**主機**在讀內容之前驗（形狀檢查，限制見文末）；落地的**網址**其餘部分仍不驗。

## R1 verify 之後（2026-10-01）

六席驗證（與 #611、#708、#693 同一次，全輪 56 則）對本張：HIGH 0、MEDIUM 4（第 2、3、4、6 則）、LOW 若干；使用者的處置照下表。

| R1 # | 問題 | 處置 |
|---|---|---|
| 2、3、34 | `doi.org` 轉址之後的落地主機完全沒檢查（可能是 `http://`、區網位址、`.home`／`.box` 這類不在後綴表裡的名稱），導航那一刻請求已經帶著 cookie 送出；skill 寫「本機與內網的主機開不到」過度宣稱；「與源 1 的 `works/<DOI>` 信任的是同一份登記」不成立；落地主機沒有進任何證據紀錄 | **新增區塊**〈轉址之後、讀內容之前：驗落地主機〉（`web-access.md`；不是散文——R2（#593）刪掉的那一版是散文、排在區塊二之後、讀的是帶 `#akashic-<T>` 的 `location.href`，三個缺點這次都避開）：區塊一之後、區塊二之前，同一把鎖讀 `location.protocol`／`hostname`／`port`（不讀 `href`），要求 https、無埠號、主機名是帶點且最後一段為字母的名稱、後綴不在 `local／localhost／localdomain／internal／lan／home／box／intranet／corp／private／arpa`、名稱裡沒有 IP 位址形狀（含 `127.0.0.1.nip.io` 與 `192-168-0-1.nip.io`）；不符或區塊失敗就**不讀內容**、記「不可達：落地主機不合（<主機>）」並關掉分頁。**落地主機一律寫進報告第 3 項**（通過與否都寫），存檔的 `origin` 也寫落地主機。更正兩處說法：「本機與內網的主機開不到」改成「擋掉形狀上明顯是本機與內網的網址；不擋解析到私有位址的公開名稱，也管不到 doi.org 轉址之後的主機」；「同一份登記」改成說清楚差別——`works/<DOI>` 是頁內 fetch 讀 Crossref 的 JSON（不導航、不渲染第三方頁面、不帶第三方 cookie），第 4 源是讓 profile 導航到登記者選的主機並執行它的頁面。風險 1 的「已處理」也更正：`doi.org` 那一條沒有消除風險、只是把它移了位置（store 的 DOI 可以來自共享 Zotero 群組庫、WoS、Crossref／OpenAlex 匯入，轉到哪裡由登記者決定），能擋的是把內容讀進來。至多開 3 個 DOI（原本「逐個各開一次」沒有上限）。建議使用者另開沒有登入任何站的專用 profile 給這一源（這一源讀的是公開頁面上的刊名沿革，用不到登入後的權限）。**沒有採用**第 2 則的另一個建議（取 `resource.primary.URL` 當資料讀、與實際落地主機對照）：那是第二套程序，而報告第 3 項寫落地主機已讓使用者能核對 |
| 4、14 | 取值的運算式整頁 `innerText` 不設上限、不剔除零寬／bidi 字元，區塊二的訊號檢查只看頭 3,000 字元 | 運算式改成 `(document.title + '\n' + (…innerText)).slice(0, 20000).replace(/[\p{Cf}\p{Cc}]/gu, c => (c === '\n' \|\| c === '\t') ? c : '')`（`web-access.md`〈讀渲染後的頁面〉；放進命令時反斜線寫兩個）。**沒有現成的文字消毒命令**：`akashic` 的消毒函式都在輸出端、沒有接 stdin 的子命令（逐一看過 `akashic --help` 與 `fulltext` 的子命令清單），所以剔除在頁內做，並寫明：讀回的文字不整頁貼進對話或報告，報告只引用含刊名或號的句子；讀回剛好 20,000 字元就是被截了、寫「已截」。副作用寫出來：剔除會拿掉 ZWJ／ZWNJ，Indic 與阿拉伯文字的名稱與原頁的顯示形可能有細微差異 |
| 6、38 | 還沒實跑過的第 4 源被算進「至少兩源」，放寬了證據門檻 | **保守處理**：還原那句話。「什麼時候可以停」寫成：使用者轉述不算、**第 4 源在對出版商頁實跑過 safari-browser 之前也不算**，只當佐證（補強前三源某一列的一句話）。理由：#692 的裁決只說「照 web-access.md 讀」，沒說這一源可以計入充分條件；本 skill 自己寫著「沒有實跑過」；devil's advocate 指出 Elsevier 的 `doi.org` 路徑在 Chromium 量到的是 meta refresh、fragment 掉、鎖不到，所以對最大宗出版商之一這條路大概率是「不可達」而不是一源。實跑過、而且使用者裁決它可以計入之後才改（此為後續）。同時刪掉「`doi.org` 文章頁與 `works/<DOI>` 合起來只算一源」那半句——整個第 4 源不計入，那半句沒有東西可合併 |
| 22 | 證據表第 4 列寫「不開 API 回應與頁面裡的網址」，內文卻允許使用者確認後開 | 表改成與內文同一句：「不直接開，要開須列給使用者確認」 |
| 23 | 使用者給定網址的「是對的那一頁」核對太弱，頁面出現刊名或號就算 | 核對改成**看頁面自己宣告的身分，不是看有沒有提到**：頁面標題、標頭或刊物資訊區塊宣告的刊名（含沿革各段）或 ISSN 要與候選一致；別刊的 about 頁、出版商的刊物總表、引用列表、姊妹刊頁面只是提到，不算。第 1 種（`doi.org`）另外要頁面宣告的 DOI 與 entry 的 DOI 相同，並明說這證明不了它是出版商的頁面，所以落地主機寫進報告給使用者核對（第 2 則指出「出現 DOI 或標題」對敵意頁面幾乎沒有成本） |
| 24 | 鎖對不到時，外部分頁留在已登入的 profile 裡 | 讀不到、讀回是空的、不是對的那一頁、落地主機不合，而鎖仍對得到時，用同一把鎖關掉自己開的分頁（那個分頁在跑登記者選的頁面、持有該站的 cookie）；**鎖已經對不到**時沒有安全的把手（`web-access.md` 明禁退回子字串或視窗編號），把 profile 與開的原始網址（不含碼）列給使用者、請他手動關。這兩條寫進 `web-access.md`〈其他〉與 skill 的「讀不到」 |

### 驗證（沒有碰 Safari 或任何出版商網站）

- 落地主機的 Python：27 個合成案例（`www.sciencedirect.com`、`journals.sagepub.com`、`link.springer.com`、`onlinelibrary.wiley.com`、`doi.org`、`psycnet.apa.org` 通過；`http://`、`localhost`、`127.0.0.1`、`.local`、`.home`、`.box`、`.internal`、`.corp`、`127.0.0.1.nip.io`、`192-168-0-1.nip.io`、`10.0.0.5.sslip.io`、`[::1]`、`2130706433`、帶埠號、空字串、`about:blank`、`xn--p1ai` 擋下）全部符合預期。`https://evil.example.com` **通過**——形狀檢查擋不住公開名稱，這一條寫進區塊的限制。整個 bash 區塊以 `bash -n` 檢查語法。
- 取值的運算式：在 Node 上以合成的 `document`（標題含 ZWSP 與 RLO、內文含空字元、ZWJ、LRI、BOM、tag 字元、30,000 個字元）執行：Cf／Cc 全被剔除、換行與 tab 保留、輸出 ≤ 20,000 字元；`document.body` 為 null 時不拋錯。
- 整個落地主機區塊（bash 加 Python）以**假的** `safari-browser`（只實作 `documents`、`wait`、`js` 三個子命令的 shell 腳本）跑過五個落地主機：`https://www.sciencedirect.com` 印 `OK`、結束碼 0；`http://www.sciencedirect.com`、`https://127.0.0.1.nip.io`、`https://router.home`、`https://evil.example.com:8443` 印 `REJECT`、結束碼 3。
- 以上都沒有對 Safari 實跑；SKILL 的「沒有實跑過」那一條已把這點寫在原處。

### 誠實邊界（本輪新增）

- 落地主機檢查是**形狀檢查**：解析到私有位址的公開名稱擋不住；通過只代表形狀上可讀，不代表那個主機是出版商的；請求在導航那一刻已經送出，這一步擋的是讀內容。
- 頁面自己做的轉址讓 fragment 掉時，這個區塊與區塊二一樣鎖對不到（`web-access.md`〈會轉址的頁面〉量到的 Elsevier 形狀），只能列給使用者手動關。
- `akashic-verify-person` 的第 4 源（「論文 DOI 落地頁」）有同一個缺口（不驗落地主機、讀取不設上限）；本輪只改 verify-venue 與共用的 `web-access.md`，verify-person 的 SKILL 沒有動，等使用者決定要不要同步（第 34 則的建議）。
- `.claude/rules/web-access-via-safari-browser.md` 的 2026-10-01 列原本寫「`doi.org` 落地的網址仍不驗」，已更正成「落地主機在讀內容之前驗形狀」。
