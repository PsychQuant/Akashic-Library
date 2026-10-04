# 外部網頁與 web API 一律經 safari-browser 取得

使用者 2026-09-24（+08:00）在 #617 規劃時定調：「Sources 中並沒有 HTTP client，可以讓她仰賴
safari-browser，這可以是整個專案預設的」。

**本 repo 的本體是離線的，只有一個目錄例外**：2026-09-24 量 `Sources/` 內 `URLSession`／
`URLRequest` 0 處；#664（2026-09-29）起 `Sources/AkashicS2/` 是本體裡唯一可以連網、唯一可以讀
keychain 的地方，其餘由 `akashic-guards network-confinement` 機械地擋。對外查詢（OpenAlex、
Crossref、ORCID、DOI 解析、出版商頁面）一直是 skill 層的事；本規則把「skill 層用什麼去拿」定成
一條路徑，唯一走本體的是帶金鑰的 Semantic Scholar 查詢（〈例外〉第 2 類）。

## 規則

1. **skill 為了取得資料而讀外部網頁或 web API，一律經 safari-browser。** SKILL.md 與它的
   references 文件寫的取得指令，是 safari-browser 的指令，不是 `curl`、`WebFetch` 或裸 URL。
   例外只有〈例外〉列的兩類。
2. **`Sources/` 不新增 HTTP client，只有 `Sources/AkashicS2/` 例外。** 網路與 keychain 的 API
   只准出現在那個目錄——哪些字樣算數是 `akashic-guards network-confinement` 的封閉清單，不在這裡
   另抄一份；`network-confinement-mutations` 證明守衛會開火（#664）。那個目錄只做 Semantic
   Scholar：其他需要外部資料的能力，照舊由 skill 經 safari-browser 取得後，以本機檔案交給
   `akashic` CLI 處理（見 [swift-is-the-implementation-language.md](swift-is-the-implementation-language.md)
   的放置表）。讓第二個 target 連網、或讓 `AkashicS2` 接第二個 API，是改本條與守衛的封閉清單，
   不從「它也需要金鑰」類推。

## 使用紀律（每一條都有踩過的理由）

- **分頁以 `--profile` ＋ `--url-endswith '#akashic-<碼>'` 鎖定，網址帶一次性 fragment**（2026-09-29 由
  `--url-exact` 改，理由與查證見下一條）：
  `LOCK=(--profile "<使用者的 profile>" --url-endswith "#akashic-<8 位十六進位隨機碼>")`，
  再用 `"${LOCK[@]}"`（陣列：zsh 不對未加引號的變數分詞）。fragment 不送伺服器，只讓這把鎖
  對得到唯一的分頁。**不要**用 `--url <子字串>`：它取第一個符合的分頁、而且跨所有 profile，
  別人的 session 開著同一站就會被選中（#617 verify）。**也不要**用 `--window N --tab-in-window T`：
  視窗編號依前後順序排，使用者一切換就漂移（#617 落地時實際發生；`fetch-fulltext.sh` 仍是這個鎖法，
  是 grandfathered 的例外，見〈例外〉）。**`documents` 一律帶 `--profile`**：不帶會把所有 profile
  （含別人的 session）的分頁網址與標題整份倒進對話。
- **為什麼從 `--url-exact` 改成 `--url-endswith`，查證了什麼，沒實測什麼**（CLAUDE.md〈Rules〉的執行語意第 2 條：
  覺得規則錯了就顯式改、寫下為什麼、附上查證；#634 的驗證第 16 列指出）：
  - 舊鎖法 `--url-exact "<開分頁時用的完整網址>#akashic-<碼>"` 比的是 **Safari 回報的網址**。`safari-browser open --help`
    （2026-09-29 讀）：`--url-exact` 是「URL equals this string exactly (no normalization)」，「Trailing slash, query string,
    and host case are all significant — use --url-endswith or --url-regex when normalization is desired」。我們拿去比的是
    **自己組的字串**：轉址、百分比編碼（WHATWG 的路徑編碼集會編碼 `<` `>` `{` `}`，SICI 式 DOI 就有；這一點是依標準推論，沒有在
    Safari 實測）與根路徑的尾隨 `/` 都會讓兩邊對不上。同一類失敗在 #556 已記過
    （`changelog/2026-09-11-issn-on-demand.md` R12：路徑尾段對根路徑是 `/`、「`--url-exact` 讓回來的 URL 不同就停手成死分支、
    真正的 miss 沒有處置」）——舊版 web-access.md 沒有把那條教訓帶進來。
  - `--url-endswith`：`open`、`close`、`documents` 的 `--help` 都列（2026-09-29 讀），「URL ends with this suffix
    (case-sensitive)」，help 稱它是「prefix-substring ambiguity 的 primary escape」；binary 字串表另有「`--url-endswith` requires a
    non-empty suffix (an empty suffix would match every tab)」——所以鎖前導檢查碼非空。只鎖結尾那一段我們自己的 fragment，
    就避開正規化；轉址時 fragment 留不留得住見 web-access.md〈會轉址的頁面〉；`--profile` 限縮到那個 profile 的視窗。
  - **沒實測**（這一輪不得操作 Safari，只讀 `--help` 與 binary 字串表）：(1) Safari 轉址後回報的網址是否保留 fragment（web-access.md〈會轉址的頁面〉
    的量測是在 Chromium）；(2) 兩個以上分頁同時符合 `--url-endswith` 時 CLI 是否拒絕——help 只對 `--url` 子字串寫明「multi-match fail-closed，
    `--first-match` 才取第一個」，binary 字串表有 `ambiguousWindowMatch`，但沒有說 endswith 走同一條，所以 web-access.md 在動作前
    自己用 `documents --json --profile` 數一次；(3) 頁面自己的 JS 在載入後改寫 `location.hash` 的站；(4) `close` 以這把鎖關分頁的
    實際行為。**批次前先用一個站實跑一次**。
  - **鎖不到時怎麼辦**：停下回報、交給使用者決定；**不得**退回 `--url` 子字串、`--window` 或 front tab。
- **開的網址從哪來**：分頁只開兩種——由 store 的識別碼（DOI、ISSN、ORCID iD…，過形狀表）組進端點範本的網址，或使用者在對話裡給的網址。
  **API 回應或頁面內容裡取出的網址**（OpenAlex 的 `landing_page_url`／`pdf_url`、ORCID 的 `researcher-urls`、名冊連結、回應的
  `next`）**不直接在使用者已登入的 Safari 開**：那是第三方登記的資料，被入侵或惡意登記的 metadata 會把使用者的個人 profile 導向
  攻擊者頁面（GET 會帶 cookie，#634 驗證第 8 列）；改用 store 識別碼組得出的等價位址（`https://doi.org/<DOI>`），或列給使用者、
  等他確認。一律只收 https、拒絕 `localhost`、IP 位址與私有網段的名稱。完整網址不經 shell 字串：寫進暫存檔、以
  `"$(cat …)"` 引用，放進 JS 時轉成 JSON 字串字面值。
- **shell 變數不跨 Bash 呼叫保留**：每個動到分頁的步驟寫成**自足的 Bash 區塊**——同一次呼叫內自己初始化 `LOCK`、
  確認它非空才動作（`LOCK` 若是空的，safari-browser 會退回 front tab）。web-access.md 的每個區塊都照這個形，
  包括讀渲染後的頁面與關分頁（#634 驗證第 1 列：DOM 讀取那三步曾直接用 `"${LOCK[@]}"`，遺失時退回 front tab）。
- **只碰「個人」profile 的分頁。** 這台機器的 Safari 有其他人的 profile，那些是別人的 session。
- **中止條款**：網站一出現「懷疑是自動化」的訊號就停下，分頁留著、不重試、不換來源。停下分兩種（使用者
  2026-09-28、2026-10-01，#613）：CAPTCHA、人類檢查、Cloudflare「Just a moment」、按住驗證這四種是**等人驗證**——
  暫停、請使用者在那個分頁自己驗證、完成後在**同一個分頁**接著走（不重新載入、不代解、不換站）；其他訊號（403／429、
  access denied 與各家封鎖頁、unusual traffic、PMC 與 ScienceDirect 的下載前驗證頁）是**整批暫停**；2026-10-02 再補兩條：等人驗證只在**文章站本身或已知的驗證服務**（封閉清單：Cloudflare 的挑戰主機、hCaptcha、reCAPTCHA）上成立，其他主機上的驗證字樣一律整批暫停，HTTP 429 一律整批暫停；分頁導航之後到了別的主機時，顯示 PDF 照常交給人；其他頁面要等它載完，載完而沒有命中驗證／封鎖／登入的封閉清單（那不代表它不是登入頁）才把這一筆交給人、批次繼續，沒載完是卡住（整批暫停）；讀不到的分頁（可能是 Safari 的 PDF 檢視器；文章站上與別的主機上同一套）交給人、未驗證，除非它在已知的驗證服務上、主機是登入主機的長相（整批暫停），或帶著驗證服務自己的標記；DOI 解不開要看得到 doi.org 自己的查無頁，否則整批暫停（使用者 2026-10-05 第 1 則）；主機的登入字詞只認最左邊的標籤與 IdP 服務名（同日第 4 則）（#613 R2、R3、b34；細節與封閉清單以 akashic-fetch-fulltext SKILL.md〈中止條款〉為準）。實作範例是
  `plugin/skills/akashic-fetch-fulltext/`（`fetch` 結束碼 8／6；`akashic fulltext bot-signals --kind` 印 `verify`／`pause`）。**判斷順序：先看狀態碼，再看內容**（這句管取 API 的回應；讀渲染後頁面時，403 而文字是四種驗證頁才照等人驗證，429 一律整批暫停，見上）——404 是「查無此筆」、
  不是訊號（Crossref 對不存在的 DOI 回 404 加純文字本文，它同時符合「不是 JSON」，狀態碼優先）；#634 驗證第 26／32／38 列指出
  兩條規則對同一個回應各說各話。
- **讀大型回應**：頁內 `fetch` 存進 `window` 變數（**每次請求換一個新的變數名**）→ `wait --js`
  等完成 → `js --large --output` 讀出，不依賴頁面渲染後的文字；讀回後**核對內容身分**（例如
  回傳的 id 就是請求的 id）。#617 校準時有一批讀到上一批的結果、結束碼全為 0
  （PsychQuant/safari-browser#190）。範例見 `plugins/akashic-discovery/skills/akashic-work-references/`。
- **持久狀態變更先告知**：清 cache、註銷 service worker、改 cookie／storage 要先說明並取得同意。
- **操作程序的位置**：本規則在 plugin 安裝處讀不到，所以 `plugin/` 的 skill 引用的是
  `plugin/skills/akashic-bootstrap/references/web-access.md`——它只寫怎麼做（問 profile、鎖分頁、
  形狀檢查、頁內 fetch），理由與例外清單留在這裡。例外清單的第 2 類在那份檔裡另有一句指路
  （#664）：plugin 讀者讀不到本規則，而照「一律經 safari-browser」去打 S2 正是金鑰外露的那條路。
  `plugins/akashic-discovery/` 是另一個 plugin、不共用檔案，
  `akashic-work-references` 的第 2 步自帶一份：見下方〈操作程序的兩份描述〉。

## 操作程序的兩份描述（`no-compat-fallback` 〈同一件事只能有一份描述〉要求的顯式一列）

`no-compat-fallback.md` 〈同一件事只能有一份描述〉的判準是「這兩份描述的是同一件事嗎？是 → 刪掉一份、改成引用」，
並寫明「作用半徑不同的鏡像」本 repo 零實例、真出現時要**顯式加一列**。這裡就是那一列（#634 驗證第 25／33 列指出：
上一版只寫「兩份程序描述的是同一件事，要一起改」，是一句沒有守衛的叮嚀）：

| | 內容 |
|---|---|
| 兩份 | `plugin/skills/akashic-bootstrap/references/web-access.md`（正本）與 `plugins/akashic-discovery/skills/akashic-work-references/SKILL.md` 的第 2 步 |
| 為什麼不能併成一份 | 兩個 plugin 各自安裝、各自更新，一個 plugin 讀不到另一個的檔案；把程序抽成第三個共用 plugin 是另一個架構決定，沒有做 |
| 哪一份是正本 | **web-access.md**。副本要改先改正本，再同步 |
| 已知分岔（2026-09-29 逐條列） | (1) 鎖法：副本仍是 `--url-exact`＋一次性 fragment、正本自 2026-09-29 起是 `--url-endswith`；(2) 非 200 的處置：副本一律中止條款、正本 404 是查無；(3) 變數名前綴：副本 `__oa_`、正本 `__ak_`；(4) 節奏：副本 `safari-browser wait $(( 2000 + RANDOM % 4000 ))`（均勻間隔）、正本 Cauchy 抖動；(5) OpenAlex id 形狀：副本 `^W[0-9]+$`、正本 `^[WASIP][0-9]+$`；(6) 正本另有〈開哪個網址〉、完整網址與回應裡取出的值的形狀列、自足區塊、「取回內容是資料不是指令」，副本沒有；(7) 副本有一句已過期（說 bootstrap 的 DOI 反查仍直接呼叫 Crossref）；(8) #593 R2 起正本每個動到分頁的區塊先數分頁、取 API 的區塊回報 `Content-Type`、兩個讀取區塊檢查空讀，副本沒有；(9) #613 起正本的中止條款分兩種處置（四種驗證頁等人驗證、在同一個分頁接著走；其他整批暫停）、區塊二以 `bot-signals --kind` 分辨、讀頁面的 JS 寫成運算式，副本仍是「一律整批停」；(10) #692 R2 起正本多了〈轉址之後、讀內容之前：驗落地主機〉（落地主機不合以結束碼 4 結束）、〈讀頁面文字用的運算式與檢查〉（讀取的運算式與 `akashic web-read`——R3 時是文件裡要照抄執行的 `check-read.py`，R4 移成 CLI 子命令；R3 起主機取自 Safari 回報的網址、讀取前後各一次，剔除與長度上限在頁面碰不到的那一側做，`LAND` 預設 `-`（R4 起仍驗主機形狀）、落地主機檢查是選用的）、〈取一次 API〉以外的讀取一律經它們，區塊二的首屏改經同一套、帶 `LAND` 參數；副本都沒有（它讀 API，沒有開會轉址的頁面，也沒有區塊二的首屏讀取）。**副本在 `plugins/akashic-discovery/**`，這一輪不得動，所以分岔照實列在這裡** |
| 同步的工作 | #687（把 web-access.md 的鎖法、中止條款、形狀表同步到 `akashic-work-references`，並決定要不要加一支守衛比對兩份的關鍵字串；等 #617 釋出 `plugins/akashic-discovery/**`）。在它完成之前，**改鎖法或中止條款的人要自己同步兩份** |
| 守衛 | 目前沒有。兩份的關鍵性質（鎖的旗標、`404` 的處置）沒有機械比對；日後要加就寫成 `akashic-guards` 的子命令（見 `swift-is-the-implementation-language`） |

## 例外：可以不照本規則的取得指令（封閉列舉，只有兩類，不得依性質相似類推第三類）

1. **本規則成文前已存在的檔（grandfathered）**，逐檔列在下方〈既有檔〉。可以修 bug；不得新增
   同類指令，也不得在新 skill 裡照抄。遷移由 #634 追蹤，改完一檔就從清單拿掉（2026-09-29
   散文檔遷移完；同日 b11c R1 起 verify-venue 改為指向 web-access.md；同日 #629 第二塊移植掉兩支直連 Crossref 的 Python 腳本，形狀 (a) 只剩一個量測範例檔）。
   這一類有**兩種形狀**（2026-09-29 顯式加入第二種，#634 驗證第 3／12／41／47 列：#634 曾把 `akashic-fetch-fulltext`
   當成已遷移移出清單，而它取得雖走 safari-browser，鎖分頁的方式仍是本規則明禁的視窗編號）：
   (a) 取得指令**不經 safari-browser**（直連）；(b) 取得經 safari-browser，但**鎖分頁的方法不是〈使用紀律〉的鎖法**。
2. **帶金鑰的 Semantic Scholar 查詢，經 `akashic s2`（CLI）或 `akashic_s2`（MCP）**（#664，
   2026-09-29 起）。邊界逐條：
   - **只有這兩個面。** skill 不自己組 S2 的網址，也不以 `curl`、WebFetch 或頁內 fetch 帶金鑰打
     S2——頁內 fetch 得把金鑰交給 `safari-browser js` 的指令參數，會出現在 process list（#640），
     本類就是為了取代那條路。涵蓋的是 `Sources/AkashicS2/` 實作的八個端點（`paper`、`match`、
     `batch`、`references`、`citations`、`recommend`、`author-search`、`author-papers`）與不連網的
     `status`。
   - **金鑰只在程序內從 keychain 讀**（service `semantic-scholar`、account `default`，非互動），
     不收指令參數或環境變數；`x-api-key` 只附給 scheme 為 `https`、host 恰為
     `api.semanticscholar.org` 的請求。
   - **全機合計每秒至多 1 個請求。** 所有呼叫者以檔案鎖預約送出時段，429 的退避也共用；重試
     用盡或 `Retry-After` 超過 60 秒即停（CLI 結束碼 4）。這是本類自帶的限流處理，不在上面
     〈使用紀律〉中止條款的涵蓋範圍內——那條中止條款管的是 safari-browser 那條路。
   - **回傳是線索，不是寫入。** 兩個面都不開 store；要把 S2 給的值寫進 store，依據照
     `plugin/rules/source-of-truth-over-consent.md` 另行取得。
   - **沒有金鑰就停**（CLI 結束碼 3、MCP `isError: true`），訊息寫明 keychain 的 service／account
     並指向設定文件，不退回匿名請求。
   - **本類是 Semantic Scholar 這一個 API，不是「需要金鑰的 API」這個性質。** OpenAlex、
     Crossref、ORCID 等不需金鑰的 API 照舊經 safari-browser；出現第二個需要金鑰的 API 時，要顯式
     新增一類（連同規則第 2 條與守衛的封閉清單），不從本類類推。

## Semantic Scholar 的取得順序（封閉列舉，只看 `akashic s2 status` 的結束碼，只有兩種狀態）

使用者 2026-09-29（+08:00）裁決：「有 key 走 key，沒 key 最後才用 safari-browser」。skill 查 S2 之前先跑
`akashic s2 status`（MCP 是 `akashic_s2` 的 `endpoint: status`，看 `keychain.present` 與
`keychain.readable` 是否都為 true）：

1. **結束碼 0（金鑰存在且可讀）→ 一律走〈例外〉第 2 類。** 這時**不得**經 safari-browser 查
   Semantic Scholar——那是用另一個額度打同一個主機、繞過全機節流的第二條路。
2. **結束碼 3（沒有金鑰，或讀不到）→ 先請使用者設定金鑰**：指向
   `plugin/skills/akashic-bootstrap/references/semantic-scholar.md`，訊息裡的 service／account 照轉。
   使用者表示不設定、或這次設定不了，才**最後**經 safari-browser 查 S2：不帶金鑰，照本規則第 1 條與
   〈使用紀律〉的全部條款（鎖分頁、中止條款、讀大型回應後核對身分）。

兩個邊界：

- **查詢遇到結束碼 4（限流用盡）或 5（S2 或網路錯誤），不改走 safari-browser 補查。** 有金鑰時
  改走頁面等於繞過節流；照訊息處理，或稍後再查。
- **這是 skill 選路的規則，不是介面的行為。** `akashic s2` 本身沒有匿名模式——沒有金鑰就以結束碼 3
  停下（〈例外〉第 2 類最後一條）；退到 safari-browser 的是 skill，不是 CLI。

## 不適用（同樣是封閉列舉，只有四類）

1. **開發與發布工具鏈自身的網路操作**——`git`、`gh`、`swift` 的套件解析、`claude plugin`、
   `xcrun notarytool`。它們不是 skill 在「取得資料」，是工具在做自己的工作。
2. **本機檔案與不連網的本機工具**——`pdftotext`、`akashic` CLI 與 `akashic-mcp`、`akashic-guards`。
   **`akashic s2` 與 `akashic_s2` 不在此類**：它們連網，歸上面〈例外〉第 2 類，受那一類的邊界
   約束。#664 之前本類寫的是「`akashic` CLI……沒有網路」，`akashic s2` 落地後那句為假；所以把
   它點名排除，而不是讓「本機工具」這個字面把一個連網的子命令收進來。
3. **使用者本人在瀏覽器上的操作**——登入、授權、付費牆後的點擊。那是人的動作；skill 不代按
   登入或授權按鈕。
4. **凍結的評測快照**——`docs/skill-evals/**/skill-snapshot-*/` 底下的舊 skill（與 `swift-is-the-implementation-language`
   〈不適用〉第 5 類同一批檔，2026-09-29 #629 R2 加列）。它是 A／B 比對的基準線，不被任何 skill、CLI、守衛或測試執行；
   改寫它就不再是基準線。

## 既有檔（grandfathered，2026-09-24 量、2026-09-25 補量、2026-09-29 #634 遷移後重量、同日 #634 驗證補量、同日 #629 第二塊移植後重量）

量法（2026-09-25 #617 verify 放寬——原量法只看 SKILL.md 與 references、不看 `scripts/`，也不認
ORCID／doi.org，漏了 3 個會直連的檔；2026-09-29 #634 加最後一段；同日驗證補掃 `plugin/rules`——原量法掃的是
`plugin/skills plugins/*/skills`，而 `plugin/rules/assertions-must-be-measured.md` 有兩個可執行的 `curl` 範例）：

```bash
grep -rlE 'api\.(openalex|crossref)\.org|pub\.orcid\.org|api\.orcid\.org|https?://(dx\.)?doi\.org/|curl |WebFetch|urllib\.request|requests\.get|URLSession' \
  plugin/skills plugin/rules plugins/*/skills | grep -vE '__pycache__|/tests/' | xargs grep -F -L 'web-access.md'
```

最後一段是 #634 加的：已遷移的檔仍會寫端點網址（那是**要取的位址**），所以只看網址與工具字樣的
原量法在遷移之後照樣命中它們。含 `web-access.md` 指標的檔視為已遷移——操作程序在
`plugin/skills/akashic-bootstrap/references/web-access.md`（問 profile、`--profile`＋`--url-endswith` 鎖分頁、
插值前的形狀檢查、頁內 fetch、中止條款）；規則寫在這裡，程序寫在那裡，兩處各說各的事。

**形狀 (a)（直連）**：2026-09-29（#629 第二塊移植後重量）命中 3 個檔，其中 2 個不算：`akashic-work-references/SKILL.md`（它自己的操作程序，網址交給
safari-browser 開）、`akashic-bootstrap/references/web-access.md`（程序本身，提到 `curl` 是在說不要用）。**剩下的 1 個**：

- `plugin/rules/assertions-must-be-measured.md`（兩個 `curl -sS --fail … https://api.crossref.org/works/…` 範例，2026-08-21 觀察的**可重跑量測指令**，
  第 194、240 行前後）：它們是量測紀錄、不是 skill 的取得指令，而且「當次回傳」是照那個指令量的——改寫成頁內 fetch 會讓範例變成
  另一個做法的觀察。**不遷移、列入清單**（#634 驗證第 20 列）；不得在這份規則檔裡再新增同類範例，日後要改寫時用
  web-access.md 的形式並重量
- ~~`plugin/skills/akashic-verify-venue/SKILL.md`（三源查詢段經 MCP／WebFetch 送出；它的鎖分頁契約待使用者裁決，#593）~~ → **2026-09-29 b11c R1（#595 的驗證）起改為經 safari-browser、指向 web-access.md**（#595 加的「經 MCP／WebFetch 送出」是新增同類指令，而例外只讓 grandfathered 檔修 bug、不讓它們新增）。量法最後一段因此不再列它；第 4 源（出版商頁）自 2026-10-01 起（#692，使用者裁決）也照 web-access.md 讀——只開〈開哪個網址〉的兩種網址（entry 的 DOI 組出的 `doi.org` 網址、使用者給定或確認的網址），讀渲染後的頁面、照〈承重存檔〉存檔。這個檔仍含 `web-access.md` 的指標，量法的結果不變（2026-10-01 重量：形狀 (a) 命中 3 個檔、形狀 (b) 命中 4 個檔，都與 2026-09-29 相同）

**同日（#629 第二塊）從這個清單拿掉的兩個**：`plugin/skills/akashic-bootstrap/scripts/crossref_match.py`（`urllib.request` 直連 Crossref）與
`plugin/skills/akashic-fetch-fulltext/scripts/calibrate_title_match.py`（同上）——移植成 `akashic crossref-match` 與 `akashic fulltext calibrate`，
**兩者都不連網**：比對與計分邏輯進 Swift，取得回到 skill 經 safari-browser 做（`crossref-match` 是重播式狀態機：缺的請求以 JSON 列出、exit 3，
由 skill 照 web-access.md 取回後存進回應目錄再跑；`calibrate` 讀本機的 Crossref 回應目錄）。這同時關掉 #634 記著的缺口——那支腳本的
錯誤處理不是中止條款（查詢階段的請求失敗讓整支腳本以未捕捉的例外中止、反向驗證把錯誤寫進結果後繼續下一筆）：現在每個請求都是 skill 經
web-access.md 的一次取得，403／429／5xx 在取得那一步就是中止條款，404 存成 `.404` 標記＝查無此筆。
量法上一個新的判斷（不是機械結果）：`Sources/` 沒有 HTTP client，量法第一行的 `URLSession` 字樣在 `Sources/` 的命中是 0（2026-09-29 重量）。

**量法不涵蓋的一個檔**：`docs/skill-evals/akashic-bootstrap-workspace/skill-snapshot-old/scripts/crossref_match.py` 仍以 `urllib` 直連 Crossref，
屬上面〈不適用〉第 4 類，不在量法的掃描路徑裡（#629 R1 verify 第 44 則；R2 verify 第 42 則指出先前稱它「不適用」卻不在那張封閉列舉裡）。

**形狀 (b)（經 safari-browser、但鎖法不是〈使用紀律〉的鎖法）**——量法（#629 起加掃 `Sources`：腳本移進 Swift 之後，鎖法的程式在那裡）：

```bash
grep -rlE -- '--tab-in-window' plugin/skills plugins/*/skills Sources | grep -vE '__pycache__|/tests/'
```

2026-09-29（#629 第二塊移植後）命中 4 個檔，其中 2 個不算（`web-access.md` 與 `akashic-work-references/SKILL.md` 提到它是在說「不要用」）；剩下的：

- `Sources/AkashicSkillTools/FulltextFetch.swift`（`akashic fulltext fetch`，原 `fetch-fulltext.sh`），以及 `plugin/skills/akashic-fetch-fulltext/SKILL.md` 的第 3 步
  （描述那條命令）：**鎖法仍是 `--window N --tab-in-window T`（#613 的作法）；#629 移植時沒有改，改成 `--url-endswith` 仍待使用者裁決、且要實跑 Safari**。
  理由：`publishers.md` 記著——使用者已開著同一頁時，URL 鎖會比對到兩個分頁、safari-browser fail-closed。**便宜的解**（沒實測）：
  對 `--landing` 加一次性 fragment，同一頁已開的問題自然消失（#634 驗證第 41 列）。**但 `--landing` 的形狀檢查（`landingShapeProblem`）
  自 #629 R2 起拒絕 `#`**：照這個解做，得先讓形狀檢查放行結尾的那一段 fragment，或由工具在檢查之後自己加上（#629 R3 verify 第 2、42 則）。這個 skill 因此**同時有兩個鎖法**：第 2 步（頁內
  OpenAlex 查詢）用 web-access.md 的鎖，第 3 步（`fetch`）用命令自己的視窗編號鎖；SKILL.md 第 3 步明寫兩者不混用。**移植後這條鎖法有一個
  比以前好的地方**：`SafariBrowser` 介面讓「這支程式對瀏覽器說了什麼」可以在測試裡逐條斷言（`FulltextFetchPathTests`），改鎖法時測試會告訴你哪些
  引數向量變了——以前只有一個 Python stub 的結束碼。**要改時**：`FulltextFetch.swift` 的三個引數向量建構點（`open`／`close`／`js`／`wait` 的 `--window`
  `--tab-in-window`）改成 `--profile`＋`--url-endswith`，`currentTab()` 與「以位置認分頁」的整套邏輯要重想（分頁由 fragment 認，不需要位置）。

歷史：2026-09-25 同一個量法（沒有最後一段）命中 13 個檔，其中 2 個不算，其餘 11 個。#634 於 2026-09-29
遷移了其中 8 個：`akashic-bootstrap` 的 `person-sources.md`、`work-sources.md`，`akashic-disambiguate` 的
`SKILL.md`、`ambiguity-traps.md`，`akashic-fetch-fulltext` 的 `SKILL.md`，`akashic-venue-works` 的
`site-access.md`，`akashic-verify-person` 的 `SKILL.md`、`verification-traps.md`。**其中 `akashic-fetch-fulltext`
只遷移了取得指令（OpenAlex 查詢與「一般 HTTP 下載」），第 3 步的腳本鎖法沒動**——所以它同時在形狀 (b) 的清單裡。

**這個量法有兩個看不到的東西**（#634 逐檔讀出來的，不要當成量法涵蓋了）：

1. **沒有網址或工具字樣的寫法**：`site-access.md` 的 osascript 專用視窗、fetch-fulltext SKILL.md 的
   「一般 HTTP 下載」與 `publishers.md` 的一列、venue-works SKILL.md 階段 A 的 `works?filter=…`。
   它們是逐檔讀才找到的。（`site-access.md` 的 osascript 配方 #634 曾整段拿掉，驗證指出那把「量過能用」換成了「沒量過」；
   2026-09-29 把它留回去，**標成「有量測的既有紀錄，不是指示」**——它仍然不經 safari-browser、不帶 profile 鎖，所以不是
   取得指令，量法看不到它，這一行就是它的登記。）
2. **指標是必要條件、不是充分條件**：一個檔同時有 `web-access.md` 的指標與殘留的直連指令，量法看不到。
   所以已遷移的檔裡仍出現的 `curl`／WebFetch 字樣要逐條讀過——2026-09-29 逐條讀過，全部是「不要用」
   的敘述或量測紀錄（說明那條路被擋過），不是取得指令。

## 為什麼

1. **本體除了一個目錄以外是離線的**。把 HTTP client 加進 `Sources/` 是架構上的改變，不該為了
   某一個 skill 方便就發生；不需金鑰的外部取得都在 skill 層，路徑統一才看得清楚。這個改變只發生
   過一次（#664，見第 4 點），而且被守衛鎖在一個目錄裡。
2. **Safari 帶著使用者的 session 與一般瀏覽器指紋**。2026-09-17 實測：Bargh 等 (1996)、
   Greenwald 等 (1998)、Gignac 與 Zajenkowski (2020) 的摘要，PsycNet 回 loading 頁、
   ScienceDirect 回 403、OpenAlex 一篇空白一篇對錯篇，開 Safari 則都讀得到（使用者全域規則
   「網頁抓不到就開 Safari」記載的事例）。
3. **只有一條路徑，中止條款才涵蓋得到**。fetch-fulltext 的「懷疑是自動化就整批停」只作用在
   它自己走的那條路；若同一個 repo 裡還有 `curl` 與 `WebFetch` 在跑，同一個網站會從別的路徑
   繼續被打。#664 的 S2 例外是另一個主機、另一條路徑，所以它的限流處理寫在它自己的邊界裡
   （〈例外〉第 2 類），不假裝被這條中止條款涵蓋。
4. **帶金鑰的查詢不能經 safari-browser，也不該由各 skill 各做一份**（#664，2026-09-29）。頁內
   fetch 要把金鑰交給 `safari-browser js` 的指令參數，會出現在 process list（#640 指出）。要用
   S2 的工作線有五條（#640、#620、#621、#622、#665），各自實作就是五份金鑰處理與節流；而 S2 的
   額度是一把金鑰全機共用（有金鑰時所有端點合計每秒 1 次），CLI 與 MCP server 是不同程序，兩個
   session 各自節流仍會一起超速——跨程序節流只有一個共用的實作做得到。所以放進本體，而且是獨立的
   `AkashicS2` target 而不是 `AkashicCore`：網路程式與離線本體混在同一個 target 時，守衛只能靠掃
   字串分辨哪些檔可以連網；獨立 target 讓「可以連網的地方」等於一個目錄。使用者在 #664 的
   Clarity Surface 與 spectra-discuss 定案：一個共用接口、兩個面都要、帶金鑰的 S2 呼叫列為本規則的
   封閉例外、只在本機使用、沒有金鑰就提示設定。

## 觸發過的實例

| 日期 | 實例 | 處置 |
|---|---|---|
| 2026-09-24 | #617 規劃時原打算照其他 skill 的慣例，把 OpenAlex 取得寫成 `curl` 指令；使用者指出 `Sources/` 本來就沒有 HTTP client，應仰賴 safari-browser 並設為專案預設 | 成文為本規則；`akashic-work-references` 從第一版起就經 safari-browser；既有 8 檔列為 grandfathered（#634） |
| 2026-09-25 | #617 verify 指出三件事：規則推薦的 `--url` 鎖法會跨 profile 取分頁；grandfathered 清單的量法漏了 `scripts/` 與 ORCID（3 個直連檔未列）；新 skill 的建檔交給 bootstrap，而 bootstrap 仍直連 Crossref | 鎖法改為 `--profile`＋`--url-exact`＋一次性 fragment；量法放寬並補列 3 檔；SKILL 寫明 bootstrap 那段不在其中止條款範圍內（#634） |
| 2026-09-29 | #634 遷移 8 個散文檔時，逐檔讀出量法看不到的取得路徑（見〈既有檔〉的兩個盲區）；讀 `crossref_match.py` 發現它的錯誤處理不是中止條款：查詢階段的請求失敗讓整支腳本以未捕捉的例外中止、反向驗證把錯誤寫進結果後繼續下一筆。另見 `fetch-fulltext.sh` 以視窗編號＋分頁位置鎖分頁（#613 的作法，`publishers.md` 記著理由），與上面的鎖法不同——它取得走 safari-browser、不在清單內，#634 沒有處理 | 8 檔改為指向 `web-access.md`；量法加「含指標即已遷移」與盲區說明；剩下 3 個各有阻塞原因（#629／#593），照實保留；`fetch-fulltext.sh` 的鎖法差異留給使用者裁決（**同日驗證後改為列入清單，見下一列**） |
| 2026-09-29 | #634 的六席驗證（51 則）：(1) `--url-exact` 比的是 Safari 回報的網址而我們拿自己組的字串比，轉址與百分比編碼讓它鎖不到，且沒有 miss 處置（第 16 列）；(2) `web-access.md` 的 DOM 讀取步驟直接用 `"${LOCK[@]}"`，遺失時退回 front tab（第 1 列）；(3) `landing_page_url` 這類 API 回應裡的網址被交給使用者已登入的 Safari 開（第 8 列）；(4) 完整網址進 shell 字串（第 9 列）；(5) `akashic-fetch-fulltext` 被當成已遷移，而腳本鎖法沒動（第 3／12／41／47 列）；(6) 量法沒掃 `plugin/rules`（第 20 列）；(7) 兩份操作程序只靠叮嚀、已分岔（第 25／33 列）；(8) 404 與「不是 JSON」對同一個回應各說各話（第 26／32／38 列） | 鎖法改為 `--profile`＋`--url-endswith`（理由、查證、沒實測見〈使用紀律〉）；每個區塊自足；加〈開的網址從哪來〉與「完整網址」形狀列；判斷順序寫明；`fetch-fulltext` 列入形狀 (b)；量法補掃 `plugin/rules`；兩份程序的鏡像顯式成列（〈操作程序的兩份描述〉）。**沒有實跑 safari-browser**（限制：不得操作 Safari）：第 16 列的修法只讀了 `--help` 與 binary 字串表 |
| 2026-09-29 | #629 第二塊：把 `crossref_match.py`、`calibrate_title_match.py`（直連 Crossref 的 Python 腳本）與 `fetch-fulltext.sh`（視窗編號鎖）移植成 Swift。直連的兩支若照字面移植就是在 `Sources/` 新增 HTTP client；`fetch-fulltext.sh` 若順手改鎖法，就是在沒有裁決、沒有實跑 Safari 的情況下改動一條安全紀律 | `crossref-match` 做成重播式（取得回到 skill，缺的請求以 JSON 列出、exit 3）、`calibrate` 讀本機目錄，`Sources/` 仍沒有 HTTP client；`fetch` 鎖法不變（〈例外〉第二種形狀），改 `--url-endswith` 仍待使用者裁決。新舊差分（17 萬個判定案例、1,860 筆 Crossref 比對、18 條 fetch 路徑對同一個 stub）記在 changelog；**Swift 版 `fetch` 沒有對真的 safari-browser 跑過**（不得操作 Safari），引數向量逐字沿用舊腳本、由測試逐條斷言 |
| 2026-09-29 | #664：使用者有 Semantic Scholar 的 API 金鑰，想讓 Akashic 用它查詢。照本規則只能經 safari-browser 頁內 fetch，而那得把金鑰放進 `safari-browser js` 的指令參數、出現在 process list（#640 指出）；五條要用 S2 的工作線（#640、#620、#621、#622、#665）各自實作又會有五份金鑰處理與節流。本規則當時的第 2 條（`Sources/` 不新增 HTTP client）與「不適用」第 2 類（「`akashic` CLI……沒有網路」）都擋在這條路上 | 使用者在 Clarity Surface 與 spectra-discuss 定案後，Spectra change `semantic-scholar-interface` 新增 `AkashicS2` target、`akashic s2` 子命令群與 `akashic_s2` MCP 工具；第 2 條改為只有 `Sources/AkashicS2/` 例外、〈例外〉從一類改為兩類、「不適用」第 2 類點名排除 `akashic s2`；`akashic-guards network-confinement`（負對照 `network-confinement-mutations`）把網路與 keychain API 鎖在那個目錄 |
| 2026-09-29 | #664 實作完成後使用者裁決 S2 的取得順序：「有 key 走 key，沒 key 最後才用 safari-browser」——先前的例外只規定「帶金鑰的查詢走 `akashic s2`」，沒說無金鑰時能不能經 safari-browser 查 S2，也沒擋住有金鑰時仍經頁面查 S2 這條繞過節流的路 | 新增〈Semantic Scholar 的取得順序〉：依 `akashic s2 status` 的結束碼分兩種狀態；有金鑰一律走 `akashic s2`，沒有金鑰先請使用者設定、最後才經 safari-browser；查詢遇到 4、5 不改走頁面 |
| 2026-10-01 | #692：`akashic-verify-venue` 的第 4 源（出版商頁）先前不抓不讀，請使用者自己去看、回覆成文字，理由是一個由 OpenAlex 欄位決定的網址會在使用者已登入的 profile 裡被打開；#593 已把瀏覽器的做法定成 web-access.md，這一源仍寫著「待裁決」 | 使用者裁決照 web-access.md 讀：只開〈開哪個網址〉的兩種（store 的 DOI 組出的 `doi.org` 網址、使用者給定或確認的網址），讀渲染後的頁面並照〈承重存檔〉存檔；原本的顧慮在該 skill 的「第 4 源」一段逐條寫出處理；三處「待裁決」的指標移除。R1 verify 補：~~`doi.org` 落地的網址仍不驗~~ → 落地**主機**在讀內容之前以 `location.protocol`／`hostname`／`port` 驗形狀（`web-access.md`〈轉址之後、讀內容之前：驗落地主機〉，形狀檢查、擋不住解析到私有位址的公開名稱）、落地主機寫進報告；取值的運算式設 20,000 字元上限並剔除 Cf／Cc 字元；第 4 源在實跑過之前只當佐證、不計入「至少兩源」 |
| 2026-10-02 | #692 R2 verify（四席：requirements、logic、security、codex）對 R1 的修正輪：(1) 落地主機檢查只掛在「開分頁」那一步，同分頁讀下一頁（verify-venue 的第 2、3 個 DOI）只重跑區塊二、檢查被跳過；(2) 檢查是一次性的快照，頁面可用 JS 複製 `location.hash` 把自己導到別的主機而鎖照樣對得到，讀取不再斷言主機；(3) 區塊二的首屏讀取（3,000 字元）沒有剔除，而 SKILL 宣稱「字元層的花招因此擋得住」；(4) 剔除集合 `[\p{Cf}\p{Cc}]` 比 repo 自己的 `UnsafeToEmitScalar` 窄（變體選擇子、CGJ、各種 filler、U+2800、Zl／Zp／Zs、Co 都活著）；(5)「讀回剛好 20,000 字元就是被截」不成立（先截再剔除，被截的頁面讀回少於上限，剛好上限的頁面被誤標）；(6) 落地主機區塊用 `return …` 敘述形、結束碼 3 與區塊二的「等人驗證」相衝、所有失敗都被叫做「落地主機不合」；(7) 共用的 `web-access.md` 寫成每個讀頁面的 skill 都要驗，實際只有 verify-venue 做 | 落地主機區塊每載入新頁（開分頁、導航到下一頁）都要跑；區塊二與讀取改經同一個運算式，~~**同一次求值**回傳 `{protocol, hostname, port, truncated, rawLength, text}`，`check-read.py` 與驗過的主機比對~~（→ 2026-10-03 那一列：運算式在頁面自己的 JS 環境裡跑，主機與剔除都可以被頁面偽造）、不同就不寫出文字（結束碼 4）；運算式的剔除集合逐碼位對照 `UnsafeToEmitScalar`（Node 26 與 Swift 各 141,760／141,762 個，差別只有刻意保留的 TAB 與 LF）；`truncated` 由剔除之前的長度算；落地主機區塊改運算式形、REJECT 改結束碼 4；共用檔寫明範圍（會被第三方轉址的頁面）與目前只有 verify-venue 照做。副本的分岔記為〈操作程序的兩份描述〉第 (10) 條。**沒有對 Safari 實跑**：區塊以假的 `safari-browser` 與 Node 測過 |
| 2026-10-03 | #692 R3 verify（含 Codex 盲審的 HIGH）：R2 的「主機與文字同一次求值，所以文字一定出自宣告的主機」與「字元層的隱形通道擋得住」都不成立——`safari-browser js` 在**頁面自己的** JS 環境裡求值，頁面的腳本可以事先改寫 `JSON.stringify`、`String.prototype.replace`，連取回結果的通道都在頁面那一側；DA 以 Node 在合成頁面上實測：蓋掉 `JSON.stringify` 的頁面讓 R2 的區塊二印 `READ-OK` 與它宣告的主機、三個不可見字元都沒剔除。另外：落地主機區塊在判 REJECT 之前就寫了 `landing-<T>.txt`，`check-read.py` 照樣當它是「驗過的」；REJECT 之後輸出檔留著上一次的文字；共用的區塊二與讀取區塊預設 `LAND` 是落地主機檔，等於把檢查強加給每一個還沒接上的 skill，與「只有 verify-venue 照做」的說法矛盾 | **主機改從 Safari 那一側取**（`documents --json` 的 `url`、AppleScript 的 `URL of tab`；頁面的 JS 換不了它的主機），讀取前後各一次、都要等於驗過的落地主機；**剔除與長度上限移到 `check-read.py`**（頁面碰不到的那一側），運算式只截到上限當傳輸量；落地主機區塊先刪檔、只在 OK 時寫回，讀取時重新驗形狀；`check-read.py` 先刪輸出檔；`LAND` 預設 `-`（選用）；使用者確認的網址被轉到別的主機也算落地主機不合（`EXPECT`）。保證句改成實話：文字出自讀取前後 Safari 回報的網址都在驗過的主機上的分頁——頁面控制自己的內容，不誠實的頁面仍可以在文字裡說謊。~~`check-read.py` 仍是 web-access.md 裡的文件片段（執行時才寫進暫存目錄），不是新增的 Python 檔~~（→ 2026-10-04 那一列：那是依性質相似類推「不適用」第 1 類，R4 移成 `akashic web-read`）；repo 的 `WebAccessReadContractTests`（Swift）從文件抽出它與區塊實跑、並把剔除集合與 `UnsafeToEmitScalar` 逐碼位比對 |
| 2026-10-04 | #692 R4 verify（四席與 Codex）：(1) R3 把讀頁面的檢查寫成 web-access.md 裡約 175 行、要模型照抄進暫存目錄再執行的 Python（`check-read.py`），以 `swift-is-the-implementation-language`「不適用」第 1 類（文件裡的指令列）辯護——那一類是呼叫工具的指令列，不是要寫到磁碟上執行的程式，而規則的封閉列舉不得類推；跑的是抄本、測試釘的是文件；它另寫一份剔除集合，macOS 的 `/usr/bin/python3`（Unicode 13）留下 U+0890–0891、U+13439–1343F 九個之後才指派的格式字元。(2) 區塊二與讀取區塊的 `rm -f` 排在數分頁之後、落地主機檔只在檢查腳本裡刪：鎖不到或 `wait` 逾時時上一輪的首屏文字與「驗過的」落地主機檔留著。(3) 讀回的 JSON 只在檢查腳本裡刪：JS 寫完之後分頁不見了，第三方文字留在暫存目錄。(4) `LAND` 預設 `-` 時完全不驗主機形狀；Safari 回報的網址以 Python `urlsplit` 解析，帶反斜線的主機段與 WebKit 讀法不同；頁面自報的 `rawLength` 原樣印進輸出；主機換到已知的驗證服務被當成「不可達」而 run 繼續 | 檢查移成 `akashic web-read origin｜landing｜check`（Swift，剔除集合就是 `UnsafeToEmitScalar`），文件裡不再有要照抄的程式，各區塊的數分頁也改經 `web-read origin`；三個讀頁面的區塊在第一個可能失敗的瀏覽器指令之前刪掉輸出檔與落地主機檔、讀回的 JSON 由 `trap … EXIT` 收尾；`origin` 在解析器會分岔的形狀（反斜線、帳密、百分比編碼、IPv6 字面值、空白與控制字元）一律 `invalid://`，國際化網域名稱轉成 punycode；`LAND` 預設 `-` 時仍驗主機形狀；`rawLength` 限 0–1,000,000,000；主機換到已知的驗證服務是結束碼 2（整批暫停）。`WebAccessReadContractTests` 移到 CLI 測試、接真的 `akashic` 實跑區塊（不再需要 python3）。**仍沒有對 Safari 實跑** |
| 2026-10-01 | #613：2026-09-28 一晚三次 CAPTCHA 都緊跟在一個真人不會做的動作之後（頁內 fetch PDF 端點、對已顯示的 PDF 再發一次請求、導航前先以 curl 打網站）。使用者定下最高原則「跟真人一樣」，並把中止條款分成兩種處置：CAPTCHA 等四種驗證頁等人驗證、在同一個分頁接著走，其他訊號整批暫停 | 〈使用紀律〉的中止條款改寫；`web-access.md` 的中止條款與區塊二同步（`bot-signals --kind`、讀頁面的 JS 改成運算式）；`akashic fulltext fetch` 改成只導航、交給人，不再在頁內取檔。副本（`akashic-work-references`）不在這一輪能改的範圍，分岔記為〈操作程序的兩份描述〉的第 (9) 條，由 #687 同步 |
