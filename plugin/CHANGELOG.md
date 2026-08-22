# Changelog

## [unreleased]

- **「收窄才是根治」那句話過寬**（#407 R21d，DA 席指名）：R21 收窄 `DECLARE` 為「整行就是宣告」之後，兩個誤判都消失，於是我寫下「收窄才是根治」並刪掉自指排除。**DA 的反駁精準**——收窄真正解決的是「字面出現在**字串**裡」（case 描述、錯誤訊息模板）；它擋不住**獨立成行的教學範例**：一行 `# trigger-coverage: reads plugin/rules/*.md` 寫在任何守衛的 docstring 裡都會完整匹配。當時沒再撞到，是因為我**手動**把本檔的範例改成佔位形式——**一次性遮蔽，不是機制**。DA 的原話：「這個修法的存在本身就是反證」。
  現在的立場寫成誠實的三層：**收窄**（機制，擋字串內）＋ **佔位約定**（約定，擋教學範例）＋ **可見性**（攤開表用 `⟨宣⟩` 標出哪些依賴是宣告來的，一個誤宣告會顯示成「這個守衛讀了它其實不讀的東西」）。另加一道：**一個守衛只該有一條宣告**——教學範例＋真宣告 = 兩行，實測正確變紅。負控 11 → 12。
  **把約定寫成機制正是這條 issue 的主題**，所以三層的性質分別標明，不含糊帶過。

- **切段之後兩個缺陷一起消失**（#407 R21c）：串接偵測原本數「這行提到幾個腳本檔名」對上「認出來幾個」，而後者被 cap 在 1——於是 `bash a.sh && bash a.sh`（同一支呼叫兩次）**誤報**成有東西漏掉（跨模型審查指名），而量測時發現 `bash A && bash B` **只認出 A、B 仍然漏**（同一個 cap 的另一面）。改為按 `&&`／`;`／`||` **切段、每段獨立判斷 head**，兩者都對。
  同輪釐清一條語意：**單段未認出 ≠ 漏掉**。`run: echo "見 X.sh"` 只有一段，它就是不執行——正確忽略，不進 chained。只有多段時，一個帶腳本檔名卻認不出執行形式的段（變數展開、前置賦值）才是真的看不到。五種形式逐一驗過，反向（真的串接執行兩支）不誤報。負控 10 → 11。

- **比例判準會漂移，結構判準不會**（#407 R21b）：R21 加的「宣告命中超過受保護檔的一半即過寬」是**比例**判準。實測 `plugin/tests/*` 目前命中 6/16 安全，但守衛再長 5 支就會被判過寬——而那是一個**完全合法**的目錄宣告。把會變的東西當成恆定判準，正是這條 issue 反覆記過的形狀。
  主判準改為**結構的**：glob 必須含路徑成分。`*`／`*.sh` 說的是「凡是這種副檔名的」，`plugin/tests/*`／`plugin/rules/*.md` 說的是「這個位置的」——後者不隨集合大小改變。比例檢查保留但收到無疑義的那一格（命中**全部**），實測 `*/*`（有路徑成分、命中 16/16）證明它不是被結構判準遮蔽的死碼。
  負控相應重排：兩條規則各一格（`*.sh` 測結構、`*/*` 測全覆蓋），**刻意不用 `reads *`**——它同時觸發兩條，於是證明不了是哪一條抓到的，而第三段鑑別力判準會正確地把它判成不外科手術。9 → 10 格。

- **特例排除追不上，收窄謂詞才是根治**（#407 R21）：`DECLARE` 原本是裸子串 `trigger-coverage:\s*reads\s+(\S+)`，它認不出「這是宣告」與「這是在談論宣告」。連鎖踩了三次：先是 `trigger-coverage.py` 自己的 docstring 範例被當成宣告；改掉範例後，錯誤訊息模板裡的字面又命中；加了自指排除後，**harness 的 case 描述字串**再命中一次。每個談論它的地方都會再撞一次。收窄為「**整行就是宣告**」（行首註解標記、行尾無他物）後三者全消，而**自指排除隨即退場**——實測拿掉後仍全綠，留著一個保護不了任何東西的特例，與沒有它在報告上長得一樣（`no-compat-fallback` 的退場即刪）。過程中還撞到 macOS 的 `/var` → `/private/var` symlink：`abspath` 兩邊永遠不等，自指排除在 mutation 環境下靜默失效（負控 8 格掉到 2 格才發現）。
- **串接式 run 的揭露先前是不對稱的**（#407 R21，跨模型審查指名）：`cd A && bash B` 會被揭露，而 `bash A && bash B` **零可見度**——B 既不進 `found`（只認 `toks[1]`＝A）也不進 `chained`（條件要求 head 不是直譯器，短路成 False）。同一個缺口因為 head 的形式不同而有無揭露。判準改為「這一行含 `&&`／`;`，而且它提到的腳本檔名多於我們認出來的那一個」。
- **「解析得到」不等於「解析到對的東西」**（#407 R21，DA 席指名）：`reads *` 幾乎保證命中一堆守衛，「宣告必須解析得到」的斷言通過而宣告文不對題——那比宣告落空更難發現，因為覆蓋表會印出一個看似合理的讀取關係。加一條：單一宣告命中超過受保護檔的一半即報紅（實測 `reads *` → 16/16，正確變紅）。不猜「對的東西」是什麼（那要人判斷），只擋掉在描述整個 repo 的那種。
- **三格負控的 `expect_substr` 是裸檔名**（#407 R21）：缺口模板是「改 {f} 時 {g} 不在…」，同一個檔名會出現在兩側，於是一條**無關**的缺口只要涉及該檔任一側就被算成同類，第三段鑑別力判準被架空。改為指名側別的完整片語。

- **三種漏報形式現在都會發聲**（#407 R20e）：`invoked()` 認不出來的呼叫有三類——多行 `run: |` 的續行、`cd A && bash X` 這類串接、包在 shell 變數裡的。前兩類現在各印一行說明；第三類靜態上偵測不到（那需要展開變數），留在 docstring。**方向都是漏報**（讓守衛紅而非假綠），但仍要印：R20c 才立下的原則是「寫在註解裡的已知限制，對讀輸出的人等於沒人知道」。
  跨模型審查同輪確認 R20c 的修法涵蓋它舉的具體例子（`run: echo "若要手動重跑，執行 ./plugin/tests/rule-coverage.sh"` 正確不被算成執行），並獨立確認宣告機制有效。DA 席 error（fail-closed，ensemble 正確回 FINDINGS 而非 PASS）——它那題已由 R20d 自答並固化進判準。

- **負控的判準補上第三段：鑑別力**（#407 R20d）：`trigger-coverage-mutations.py` 的判準原本是「守衛變紅 ＋ 訊息指名了它」，那**不足以**說這格鑑別了它具名的缺陷——一個注入若順帶打壞別的東西，紅的原因就分不出來。姊妹 harness 在 R18b 已經吃過這個虧（四格宣告「第 1 項」的注入實際紅 `[1, 2]`）。第三段要求**每一條被報出來的缺口都屬於它指名的那一類**。八格實測全部「其他 0」，這條斷言在寫下時即為真；另以一個刻意不純的探針（同時拿掉 pre-push 的一支守衛與 workflow 的一個 run，宣告只提前者）證明它會紅並具名無關缺口。

- **同一個修法只修了一半，今天第二次**（#407 R20c）：R20 把 workflow 的「執行」偵測改為只認命令位置，但**只改了直譯器那半邊**（`bash X`）——`./X` 分支照舊掃全行，於是 `run: echo "見 ./rule-coverage.sh"` 仍被算成執行了它。改為只認 run 內容的第一個 token；代價是 `cd A && bash X` 這種會漏，**方向是漏報**（讓守衛紅而非假綠）。第 8 格 negative control 釘住它。
  同輪揭露一個已知限制：多行 `run: |` 的實際命令在**續行**上，本函式看不到。不靜默——它會印一行說明。目前只有 `ci.yml` 用這個形式，而 `ci.yml` 的 `paths-ignore` 排除 `plugin/**`、也不跑這些守衛，所以當下不影響；**但那是巧合不是設計**，所以印出來。
  今天第一次同型是 `code_only()` 只用在 `READS` 不用在 `HOOK`（R20 的 (a)）。兩次都是：寫了正確的修法，然後只套用到先想到的那個呼叫點。

- **宣告機制失效時守衛本來不會紅**（#407 R20b）：`# trigger-coverage: reads <glob>` 的宣告寫在**註解**裡（寫在程式碼裡它就會被執行），所以 `declared()` 必須讀 raw file——而同一個檔案裡的 `code_only()` 服務的是相反的判定（「這個 basename 是真的被讀，還是只在註解裡被提到」）。**兩個函式對註解的態度相反是設計**，而它看起來像不一致，下一個人很可能會「統一」它。統一之後宣告全部失效，**而守衛不會紅**：它只是少考慮幾個 pair，沉默地。加一條會紅的斷言（有宣告就必須解析得到）＋ 第 7 格 negative control（把 `declared()` 改成走 `code_only()`，實測紅且訊息指名根因）。跨模型審查的 requirements 席獨立確認機制有效。

- **新守衛自己有兩個假陰性**（#407 R20）：R17–R19c 的 887 行此前從未被跨模型審查（那是那幾輪自己寫的程式碼）。送審後 3/3 完成、六條 finding **全部指向 `trigger-coverage.py`**。兩個 HIGH 經構造實驗實測成立——守衛在那兩種狀態下**報綠而它宣稱的性質為假**：
  (a) **pre-push 覆蓋檢查讀 raw text**。把一支守衛從 hook 拿掉、只留一行 `# TODO: 之後再接 …`，守衛照樣印「涵蓋 10/10」。而 `code_only()` 就在同一個檔案裡、正是為了修「坑 3」而寫的——`READS` 用了它，`HOOK` 沒用。**修了一半**，正是本 repo `no-compat-fallback` 記過的 #241 形狀。
  (b) **workflow 的「執行」偵測匹配同一行任何檔名**。把 `run: bash plugin/tests/rule-coverage.sh` 換成 `run: echo "見 plugin/tests/rule-coverage.sh 的說明"`，該守衛仍被算成「這個 workflow 執行了它」。改為只認命令位置（`bash X`／`python3 X`／`swift X`／`./X`）；仍是啟發式，但失敗方向翻轉為漏報（讓守衛紅，不讓它假綠）。
  兩格已加進 negative control（4 → 6）。
  其餘四條：**`code_only()` 的 docstring 說剝行尾註解而 `.swift` 走 else 分支不剝**（零實例，但斷言是假的——依 `zero-instance-guards` 第 1 列「零實例、成本一行、前件精確」而寫）；**`READS` 是啟發式且失敗方向是漏報**（一個用 glob 組路徑的守衛整條依賴不被考慮，不報缺口也不印任何東西）——靜態分析救不了，所以改為**把判定攤開印出來**讓漏報在人眼前缺席，而攤開表當場讓一個真實漏報現形（`rule-coverage.sh` 用 `"$RULES"/*.md` 定位規則檔，從不寫出 basename，被判成「只讀自己」），並加上顯式宣告的出口（`# trigger-coverage: reads <glob>`）；**第 6 項散文守衛的靜態計數 proxy 沒驗它自己的前件**（`^check ` 只認 column 0，一個被縮排的 check 會讓計數少一而實跑不變）——補上前件檢查，實測縮排一個即變紅。

- **規則的旗艦論證自己過期了**（#407 R19b）：`assertions-must-be-measured.md` 的自我量測表（「我說的每句話都量過」）重量八列，**兩列已過期**——parity `26→46`、mutation `11/11→14/14`。過期的正是兩個**會長**的數字（每輪加 fixture 就變），而表格把它們寫得跟「`VenueType` 是六值」一樣像恆定事實。其餘六列仍成立（VenueType 6、skill 6、wrapper 第 6 行、format 10 vs 12、marketplace 27 個、main 最近 8 次 CI 全 `failure`）。
  修法**不只是換數字**（下一輪會再過期）：會長的那幾列標 `↗` 並寫出前一次的值，表頭寫下「數字會過期不是缺陷，把會長的數字寫得像恆定事實才是」。並新增**第 6 項散文守衛**——靜態數 fixture 定義與 mutation 項目（不跑那兩支腳本：parity 需 `swift build`、mutation 要數分鐘；實測靜態計數與實跑一致），與表格裡的數字比對。它有兩格 negative control（把兩個數字各自改回過期值），negative control 11 → 13。
  **這不是零實例守衛**——過期是 2026-08-22 真實量到的，2/8。

- **新增第 9、10 支守衛：觸發點自己的覆蓋**（#407 R19）：`plugin/tests/trigger-coverage.py` ＋ 它的 negative control。`CLAUDE.md` 有一張**手寫**的觸發點表，而手寫的表會與現實安靜分岔——這條 issue 已記過三次同形狀。判準取自 `census-parity.yml` 自己的檔頭：**不是聯集，是逐對**——對每個受保護檔案 × 每個讀它的守衛，必須存在一個 workflow 同時在該檔改動時觸發、且執行該守衛。當下實測**零缺口**，pre-push 涵蓋全部 10 支。**右欄（CI 是否真的跑起來）它量不到**，那三格的狀態仍如 `CLAUDE.md` 所載。
  **寫這支腳本的當天踩了四個坑，全部是本 issue 的主題**：(a) 受保護清單裡憑記憶寫了 `Sources/AkashicCore/StoreVersion.swift`，真實位置是 `AkashicStoreIO/`（**該 repo 為 private，plugin 單獨安裝者取不到這兩條路徑**）——現在每條路徑先驗存在，指不到東西的守衛比沒有守衛更糟；(b) 抽 `paths:` 的 regex 不認 YAML anchor（`paths: &parity_paths`），於是對 `census-parity.yml` 回報 0 條而它明明有 4 條；(c)「守衛讀哪些檔」用 basename 出現在整個檔案裡判定，於是**註解**裡提到姊妹 harness 被算成讀取它，報出兩個不存在的缺口——現在先剝註解行；(d) **negative control 自己是假的**：`io.open(p,'w').write(fn(io.open(p).read()))` 讓 Python 先求值 `open(...,'w')`（截斷檔案）再求參數（讀到空字串），於是守衛的 copy 是 **0 bytes**、零輸出、rc=0，而**前三格仍然「紅」**——紅的原因是檔案被清空，不是它們宣稱的注入。一個因錯誤理由變紅的負控，等於不存在。修法是先讀完再開寫，並加一條「注入若對內容零改動即失敗」的斷言。
  同輪查了另外兩支 mutation harness 有無同型缺陷（同型缺陷成對出現，本 repo 記過）：**兩支都安全**——它們的 `write` 參數是別處算好的變數，不是同一行讀同一個檔。

- **一句描述不存在的守衛的話，寫在守衛檔案自己的檔頭上**（#407 R18）：`multiscalar-parity.swift` 的檔頭寫著「表改動時這裡要重新產生——由 `tests/hash-table-drift.sh` 的比對兜住」，而該腳本對 `multiscalar` 的命中數是 **0**：它只比對表與生成器，從不讀那個檔。那份 inline 副本（它在 `swift <file>` 的 JIT 模式下不能讀檔，所以把表編進原始碼）可以與表安靜分岔——過期的那份仍會跑完、仍印 0 分歧，只是它驗的是**舊表**對 Swift 的**現行**行為。
  修法是把守衛真的加上去（**不是把話改軟**），三種注入證明它會紅：改邊界、刪最後一段、改寫宣告形式（第三種驗的是抽取式自己脫節時不靜默通過）。**加的過程中同一個錯誤又犯一次**：第一版抽取式寫死 `),$`，漏掉陣列最後一個元素（無結尾逗號），於是把「我的謂詞太窄」報成「表分岔了」並說出口——記在該行註解裡。
- **負控注入不是外科手術式的**（#407 R18b）：`rule-prose-guards-mutations.py` 四個宣告「第 1 項」的注入，實測紅 **[1, 2]**——一個 markdown 連結同時是兩者的正例（可跟隨連結 ＋ 提到 repo 路徑而未揭露取用限制），於是「第 1 項變紅」分不出是誰抓到的。那四格加揭露詞收斂成單一正例；`report()` 的判準從「第 n 項紅」升成「**恰好**第 n 項紅」。11/11 全 exact。
  **`marker-parity-mutations.py` 裁決不跟進**（理由寫進該檔，不留給下一個人重推）：它的 46 個 fixture 是**同一個性質**的不同輸入，一個注入讓多格紅是正確行為；要求 exact 會逼每個 mutation 手寫一份預期 fixture 集合，而那份集合會在新增 fixture 時安靜過期——一份與它所描述的東西分開演化的規格。兩邊共通的要求（baseline 全綠、在 pristine copy 上跑、宣告的那格必須紅）不變。
- **三處謂詞比它要管的東西寬**（#407 R18）：(a) `store-marker-parity.sh` 印 `已知分歧=${xfail}`，而 `xfail` 只被初始化、從未被任何一格 increment——那個數字恆為 0，讀起來卻像「有一套分類機制而目前分類為零」。「檢查過、沒有」與「沒有這個機制」長得一樣，正是該測試三值 `expect` 設計要防的東西；改為不印。(b) `review-claim-audit.sh` 用 `grep -q` 問「字串在檔案裡嗎」，不區分 `paths:` 與 `paths-ignore:`、`run:` 與註解——收窄為只在對應區段裡找，注入驗證時字串仍在檔內而新謂詞正確變紅。(c) `hash-table-drift.sh` 的 ASCII 檢查只認大寫 hex（依賴生成器印 `%X` 這個沒說出來的前提），加 `-i`。
- **`rule-prose-guards-mutations.py` 補齊 `REPO_ONLY` 的第 3、4 分支**（#407 R18）：它的 docstring 自己記載「手寫兩種形狀、另外兩種一路綠燈」發生過一次，而當時**只修了一半**——謂詞改成共用 `REPO_ONLY` 了，證明它四個分支都會紅的注入卻只有兩格。negative control 9 → 11。

- **新增 `plugin/rules/`**（#407）：plugin 自帶的規則目錄，第一條是 `assertions-must-be-measured`——**寫下一句可能是錯的話之前先回答四個問題**（這句話可能錯嗎／我憑什麼說它／我手上的東西還說了什麼我沒讀／我寫的範圍有沒有超出證據）。刻意**不是分類法**：前兩版都是分類法，兩版都被跨模型審查打掉，原因相同——每條分類邊界本身就是一個關於命題世界的斷言，規則的斷言表面比它要管的東西還大。問句沒有真假。**每一個 skill 都引用它**（該 plugin 的每個 skill 都產出人會照著行動的斷言）——這句話由 `plugin/tests/rule-coverage.sh` 守著，不是靠作者數過：先前寫的是硬編的「全部 6 個」，第 7 個 skill 長出來時沒有任何東西會提醒它漏掛。該守衛同時驗每個引用的相對路徑真的解析得到（引用一條指不到的路徑比不引用更糟：它讓讀者以為自己拿得到）。**已知缺口**：掛載面（skill 檔）比適用面（issue／報告／規格）窄，該檔的誠實邊界有記。
- **venue type 值域不再有第二份會分岔的清單**（#407）：`akashic_add_venue`／`akashic_update_venue` 的 tool 說明與 **per-parameter** 描述、CLI `add-venue`／`update-venue` 的 abstract 與 `--type` 說明，全部改由 `VenueType.domainDescription` 現算。先前四處寫死 `journal | conference | publisher`——`journal` 這個值在 #324 已更名為 `periodical` 且**刻意不留相容別名**，所以那份清單的三個值有一個根本不存在，另外三個（`database`／`socialMedia`／`website`）從未被提及。**LLM 讀 per-parameter 描述決定要傳什麼值**，於是它照著送一個會被 decode 拒絕的值。**`Sources/` 殘留 0**（`grep -rn 'journal | conference | publisher' Sources/`）。全樹另有兩處命中，兩處都不是缺口：本 CHANGELOG 這一行在**引述**舊字串，`openspec/changes/archive/` 的設計稿描述的是它寫下時的狀態（歷史正確、且在受保護的 archive 內）。**先前這裡寫「全樹殘留 0」**——一個沒有限定範圍的全稱句，而它是假的。
- **census 的 marker 解析：兩族 Unicode 分歧**（#407 R9，判準於 R10 換掉）：(a) `#` 註解判定——讀端的 `hasPrefix("#")` 是 **grapheme cluster** 比較，census 的 `startswith('#')` 是 **code point** 比較；`#` 後緊跟 grapheme extender（combining mark／VS16／ZWJ／keycap／tag）時讀端整檔拒開，而 census 判註解、跳過、印得與健康 store **逐字相同**。(b) `_WS` 由「Unicode Zs ∪ tab」推導，而那句註解是假的——Foundation 的 `CharacterSet.whitespaces` 含 **U+200B**（ZWSP，Cf 不是 Zs；獨立複驗：列舉 U+0000–U+10FFFF 得 19 個 scalar）。這一族方向**相反**：5 種位置讀端全部接受，census 卻說 marker 壞了並指使用者去修一個健康的檔。推導換成量測到的集合。(c) Python 3.11+ 的 `int()` 位數上限讓大量前導零的合法版號被誤判——改為先剝前導零再判 Int64 上界。三族共補 13 格 fixture。
  **(a) 的修法在 R10 被換掉**：R9 用「general category（Mn/Mc/Me）＋ 硬編範圍」近似 grapheme extender，並寫下「那正是分歧的**充要**形狀」——實測**兩個方向都錯**（漏 103 個含 U+200C ZWNJ／泰文 SARA AM／emoji modifier；多含 31 個緬甸文 Mc，那個方向是 R9 自己新引入的）。根因是拿 general category 近似 Grapheme_Cluster_Break，而**再加幾段是加不完的**。R10 改成查一份由 Swift 自己列舉的表（`scripts/hash-merging-ranges.txt`，334 段／2619 個 code point），並附 `tests/hash-table-drift.sh` 每次重新生成比對——Unicode 版本漂移會變紅而不是安靜。全 code point 空間掃描：兩個方向差集皆為 **0**。表讀不到時回第三態「判不出來」並指向 `akashic doctor`，**不替讀端猜**。
- **兩個 workflow 加最小權限**（#407 R9）：`permissions: contents: read` ＋ `persist-credentials: false`。它們以 `pull_request` 觸發並執行 PR 端可控的程式碼（守衛本身就是 PR 可以改的檔案），而 `actions/checkout` 預設把 token 留在 git config。**過程中踩到一次**：加 `persist-credentials` 時造成重複的 `with:` 鍵，而 `yaml.safe_load` **靜默接受並取最後一個**——設定被丟掉且驗證看不出來。改用會拒絕重複鍵的 loader 檢查。

- **🔒 移除守衛裡的任意指令執行路徑**（#407 R8）：`rule-prose-guards.py` 的第 5 項曾把從規則檔（markdown）擷取的字串交給 `subprocess.run(..., shell=True)`，旁邊註解寫著「只接受以 awk 開頭的指令，不執行任意擷取到的 shell」——**那句話是假的**：regex 只約束開頭與結尾，中間的 `;`／`|`／`$( )`／換行全部放行。跨模型審查做出 PoC：payload 尾端補一個 `echo 6` 讓輸出等於預期值，守衛報 **5/5 PASS、exit 0**，同時以使用者身分執行了注入的指令。觸發面是同輪接上的 `.githooks/pre-push`（每次 push、完整使用者權限）與 `plugin-guards.yml` 的 `pull_request`（可注入的 markdown 就在該 workflow 監看的路徑下），且本樹經**公開** marketplace 出貨。
  現在：指令是守衛內的**常數**，規則檔必須逐字展示它，執行的是常數本身、以參數陣列（`shell=False`）跑；檔內每一條同型指令都必須是那一條。注入 PoC 已加進出貨的 negative control——它不只看守衛紅不紅，還斷言**副作用沒有發生**。
- **守衛的觸發條件不再與它保護的檔案互斥**（#407 R8）：`ci.yml` 沒有 `pull_request` 觸發，且 `paths-ignore` 排除 `plugin/**`——所以「只改 census」的變更會讓整個 macOS job 被跳過，而 census 正是 parity 的受測對象；**parity 守衛在 CI 只會在它的受測檔案沒被改動時執行**。新增 `census-parity.yml`（macOS，觸發路徑只有三條：census、parity 測試、它的 oracle `StoreVersion.swift`），並把該 `VenueType` enum 的原始檔（在 Akashic repo 的 `Sources/AkashicCore/` 底下；**該 repo 為 private，plugin 單獨安裝者取不到**）加進 `plugin-guards.yml` 的觸發路徑——散文守衛第 5 項讀它，存在的理由正是防那個漂移。
- **支援上限改由實際 binary 回報**（#407 R11）：census 的註解自己寫著「『支援到第幾版』是 **binary 的性質**」，而實作取的是 checkout 的**原始碼**——source 與 binary 不同版時雙向誤判（binary 只到 11 但 source 說 12 → 不警告而使用者其實開不了；反之把讀得到的 store 錯報成 tooNew）。**parity 測試結構上抓不到**：workflow 先在同一個 checkout `swift build`，oracle 與被讀的 source 恰好同步。R8 與 R9 各報過一次。
  改為**直接問 binary**：讀端的 tooNew 訊息逐字含「本 binary 支援至 N」，所以拿一個 format 極高的臨時 store 問一次就有答案。三層來源各自標明出處——問到 binary 才敢說「你的 binary 開不開得起來」；只讀得到 source 時措辭與 ⚠ **同時**降級為「這份 checkout 的 source 上限…無法斷言」；兩者皆無則維持未知。
  **過程中踩到兩個**：(a) 探測用的管線寫了 `| head -1`，而本檔開頭是 `set -euo pipefail`——head 提前結束讓上游 sed 收 SIGPIPE 非零退出 → 整個腳本被 `set -e` 殺掉，輸出**完全靜默**；改用 sed 自己的 `q`。(b) 措辭降級了但**下一行的 ⚠ 沒有**（`_store_unopenable` 無條件含 `_too_new`），於是它照樣印「讀端會整體拒開此 store」——正是剛降級掉的那句話。修了標籤沒修相鄰的斷言，是這條 issue 反覆出現的形狀。
- **census：找不到原始碼時的操作出口**（#407 R8）：plugin 單獨安裝（marketplace 出貨的常態）沒有 `Sources/`，於是一個 `format: 99` 的 store——真讀端明確拒開——照樣印四列計數、rc=0、**沒有任何 ⚠**，而 SKILL.md 的操作指引正是「先看第一行有沒有全域警告」。現在該情形會印 ⚠ 並給出消除未知的方法（在 repo 內跑，或設 `AKASHIC_REPO`），SKILL.md 也補上對應的列。
- **`rule-coverage.sh` 加位置條件**（#407 R8）：它只加了「相對路徑要解析得到」，仍掃整個 skill 子樹——把 `SKILL.md` 的連結整段拿掉、在旁邊的 `note.md` 寫一句「不要載入這條規則」，守衛照樣 ✓。而該腳本自己的註解逐字宣稱它已經修掉這個形狀。現在只認 `SKILL.md`（掛載點是 skill 的進入點，不是它目錄裡的任一份筆記）。

- **census 的 marker 解析補齊數值與 BOM，並新增 tooNew 狀態**（#407 R7）：先前只認 ASCII 以外的 Unicode 數字（`format: １２`／`१२`／`١٢` 全被讀成 12）且 Python 的任意精度 `int()` 讓超出 Int64 的版號被當成合法——這四種形狀的輸出與一個**真正健康的 store 逐字相同**，而讀端整體拒開。現改為只認 ASCII 數字 ＋ `n > 2**63-1` 判 malformed（界線實測：`…807` 兩端一致、`…808` 起分歧）。UTF-8 BOM 是**反方向**的假話：Foundation 解 UTF-8 會吃掉 BOM、讀端正常開啟，而 census 說「讀端會整體拒開」並叫使用者去改一個合法的檔——已改用 `utf-8-sig`。
  **新增 tooNew**：一個 format 超過本機支援上限的 store 沒有任何 binary 打得開，而先前它印得跟健康 store 逐字相同且 exit 0。census 現在有原始碼時讀支援上限並明說超過，**讀不到原始碼時明說不知道**——兩種情形都不再與健康 store 同形。
- **守衛不再改寫出貨檔，並接上三個觸發點**（#407 R7）：兩支 mutation harness 先前**就地改寫版控中的檔案**再用快照還原，跨模型審查在審查期間實際觀察到 `literal-census.sh` 出現三種被注入的狀態（注入窗口約佔執行時間 87%）。三個缺口中最惡劣的是「無前置潔淨檢查」——第二個 process 會把已被注入的內容當成快照，還原時把 mutation **永久寫回**而 hash 比對通過。**根治不是各補一塊，是不要碰原檔**：現在 mutate 一份 copy（census → tempdir、規則檔 → 整個 plugin 樹的 copy），守衛以 `--census` / `--root` 指向它。
  觸發點：`.githooks/pre-push`（全部）、`plugin-guards.yml`（ubuntu，1× 計費，純 python／bash 的那些）、`census-parity.yml`（macOS，需要 build 產物的那些）。**支數刻意不寫死**——每輪都在長（#407 R10 verify 抓到這裡曾寫「五支／三支／兩支」而當時已是 6／3／3）。先前 `ci.yml` 的 `paths-ignore` 排除 `plugin/**`，所以純 plugin 的 push **整個 job 被跳過**——「進版控不等於會被執行」。
  **但接上觸發點也不等於觸發點會跑**（R8 verify 實測）：`core.hooksPath` 指向主 repo 的 `.githooks`（worktree 的修改不是實際生效的那份，merge 後自癒），而 macOS runner 帳務擱置——main 最近 8 次 CI run 全部 `failure` 且 **steps=0**。目前唯一實際跑過它們的路徑是本機手動執行。詳見 `CLAUDE.md` 的觸發點表。
- **parity 從一致性檢查升為可否證的規格**（#407 R7）：26 格各加上**必填的預期裁決**。先前只驗 `census == oracle`，於是「兩邊一起錯」是綠的——例如作者誤讀 grammar、又把 census 寫成與那個誤讀一致時，測試無法區分。`rule-coverage.sh` 同輪改為驗**可解析的相對路徑**而非字串出現（先前任何一處純文字提及都算「已掛載」，包括一句「本規則不適用於此」）；`rule-prose-guards.py` 的第 5 項改為**直接執行規則檔展示的那條指令**並比對輸出（先前它另寫一套計數器，於是「展示的指令印出 8 而非宣稱的 6」可以原封不動再犯）。

- **plugin 開始附出貨的測試**（#407）：新增 `plugin/tests/` 與 `plugin/skills/akashic-literal-campaign/scripts/tests/`——`rule-coverage.sh`（每條 `plugin/rules/` 的規則是否被每個 skill 掛到，並驗相對路徑真的解析得到）、`rule-prose-guards.py`（五項散文守衛：可跟隨的懸空連結、未在同一行揭露的 repo 專屬路徑、分類法用語復辟、被同段證據否證的假全稱句、`VenueType` 數量宣稱與實測**逐處**比對）、`store-marker-parity.sh`、以及兩支 negative-control harness。
  **為什麼連 negative control 都出貨**：一個從沒紅過的檢查，和一個不存在的檢查，在報告上長得一模一樣。本 issue 的第五輪正是這個形狀——十三項驗收全綠，而把前一輪的**原始**缺陷做成 mutation 一跑，13/13 完整存活（三個謂詞各自壞掉：一個對整個檔案做子串比對、一個檢查「那句宣稱有沒有被印出來」而非它是否為真、一個被 `or True` 中和且從未進入斷言）。那三項已刪除，由拿真 CLI 當 oracle 的 parity 測試與 coverage 守衛取代。
  **兩個誠實邊界**：(a) parity 測試需要 Akashic repo 的原始碼與 build 產物，而該 repo 為 private——plugin 單獨安裝的環境跑不動它；它出貨的目的是讓**有 repo 的人**能重跑那個等價性主張，不是讓每個使用者都跑得動。(b) `rule-coverage.sh` 驗的是「引用存在且路徑解析得到」，那是必要條件不是充分條件——一個 markdown 連結不等於規則已載入。

- **`literal-census.sh` 的 marker 解析改為讀端 grammar 的同構實作**（#407）：先前它只認 `^format:\s*(\d+)\s*$`，卻在註解裡宣稱「對照讀端」。跨模型審查實測出**六種輸入形狀分歧**，其中三種讓一個讀端**整體拒開**的 store 被 census 報成健康（`meta: {` 毒化 marker、重複 `format:` 行、縮排的非註解行），一種讓讀端完全接受的 marker（`format: 12  # v12`）被宣告壞掉並叫人去修一個沒壞的檔，還有一種（非 UTF-8）直接 traceback。campaign 的批次範圍就是照這個數字定的。
  **這次的「對照讀端」是被量測的，不是被宣稱的**：新增 `scripts/tests/store-marker-parity.sh`，拿真的 CLI 當 oracle 跑 26 格 fixture 矩陣、四值比對（accept／malformed／tooNew／unreadable）。**先前那個「已知殘留分歧」（Unicode 數字）已在 R7 修掉並升為正式格**，同輪另補全形／天城體／Int64 上下界／BOM 六格；目前零已知分歧。另附 `scripts/tests/marker-parity-mutations.py`：每個 mutation 各對應一個**實測過的**分歧形狀，證明那張矩陣真的會紅——一個從沒紅過的檢查與一個不存在的檢查在報告上長得一模一樣。（**數目刻意不寫死**：它每輪都在長，而寫死的計數會與腳本分岔——R8 verify 抓到這裡曾寫「七個」而實測已是 11 個。跑一次就知道當下是幾個。）
  venue 那一列同時改為**量測優先**：解析到 venue 邊就一定印計數列，不論 marker 說什麼；兩者不一致時把不一致本身報出來，並註明在修好 marker 之前這些數字不能拿去定批次範圍。輸出的 store 路徑縮成 `~` 形式（這份輸出的設計去向是 issue）。

- **修掉兩處懸空引用**（#407）：plugin 內指向 repo 端規則的裸相對路徑在 Akashic repo 外解析不到。**改法不是換成絕對 GitHub URL**——實測該 repo `isPrivate=true`，未認證 GET 一律 404，而 private repo 的 404 與「已刪除／從不存在」不可區分，等於把缺訊號換成假訊號；且主要讀者是未認證的 agent。改為**就地寫出 skill 實際需要的判準**，出處降為註記並明說需 repo 存取權。同一輪順帶修掉 `akashic-wos-intake` 既有的同型 404 連結（它原本被當成「既有慣例」引用，實測它自己也 404）。

- **`akashic_update_venue`／CLI `update-venue`**（#306）：venue 異名補寫——`add_names` append 語意（整組替換刻意不提供，R3F-2 教訓）；`note`／`type` 替換。沿革補全直接擴大 resolve-venues 命中面。
- **⚠️ `akashic_resolve_people` 增 `confirm_tiers`**（#307）：apply 集含寬鬆提名層（reorder／initials／confirmed-elsewhere）而該層未列於 `confirm_tiers` ＝整批拒絕零寫入並指名缺席層；exact 免承認。MCP 面自此也有 tier 覺察閘（CLI 為 `--tier`，兩面對稱不同形）。
- **`akashic_update_person` 的 `references` 落地**（#308）：**append-only**（與其他欄位的替換語意刻意不同——references 持有 verdict，整換會洗判定史）；retrieval／judgement 兩型、(field,value,kind) 冪等；verdict 欄位對拒收（只能經 resolve 流程寫）。alias-promotion 出口的 provenance 半邊自此有正規寫入面。
- **`HOME` 注入隔離**（#309）：registry 值（`~/.akashic`）的 tilde 展開改吃注入的 environment `HOME`——假 home 測試／排練不再落到真 store（R2 verify 事故的根因修除）。

## [0.9.0] - 2026-08-17

- **`akashic_resolve_people` 提名四層化**（#303）：candidates 每列新增 `tier`（封閉四值 `exact`／`confirmed-elsewhere`／`reorder`／`initials`，信心降冪排序；報告形狀 additive——apply 契約的變更見下方 R1 修正輪兩則 ⚠️，是有記錄的變更）。寬鬆比對封閉兩類——token 重排與姓＋首字母（無逗號不猜姓氏位置、CJK 不生 initials 鍵）；羅馬化異拼刻意排除。ambiguities 同步帶 tier（initials 碰撞 ≠ exact 同名）。
- **confirmed verdict 再利用**：同 literal 已於他處 confirmed → `confirmed-elsewhere` tier 自動提名（查證知識走 verdict 持久化、不寫 alias）。
- 新 skill **`akashic-literal-campaign`**：literal 歸零 campaign 編排層——三域 census（`scripts/literal-census.sh`；venue 域對 format < 11 報「未部署」而非 0）、分批 TaskCreate、逐 distinct 查證管線（引 person-verify）、每輪計數落 #303。
- CLI `resolve-people` 人可讀輸出按 tier 分組（initials 段標頭自帶查證義務）；App 裁決台候選列帶 tier。
- **R5 收斂批**（2026-08-17，R4 verify PASS-after-batch 的批）：census 恢復與 loader 同語意的合併掃描（混合佈局不再假零）；兩腿協調配對改寫入後、過濾寫失敗者；`rejected`／`applied` 回音改 raw 三段（StoreKey quarantine 把關，超長 citekey 回音可重用）；counts 標籤過文法夾；兩個守衛測試換可鑑別 fixture；歧義頁尾第五面補雙出口＋整組替換警語；spec R10 改配對級協調語意。**相容性註記**：verdict value 的 holder 自 R2 修正輪起過 `StoreKey` 文法閘（decode 層）——手改／外庫匯入的不合文法 holder 會使**整筆 person 記錄 quarantine**（非僅該 verdict 進 malformed）；真 store 37 筆 verdict 全數合法、零影響。
- **R2／R3 verify 修正輪**（2026-08-17）：兩腿協調改以內部未截斷配對（超長 citekey 不再打斷批次；同列 reject A＋apply B 正確進 apply 腿）；淘汰揭露計數去重（1 筆否決不再報 3）；tier 閘不豁免 `--citekey`／`--person` 收窄（訊息同步）；bootstrap 提名空間與 resolver 同構（逐 tier 查找＋吃 confirmed——幽靈 pending 與 confirmed 盲鑄修除）＋`confirmed:` 必填；`rejected`／`applied` 回音統一三段 pinned 形；歧義出口指引四面重寫（alias-provenance 升 exact；第三人走 `add-person`；`update_person.names` 整組替換警語；provenance 寫入面缺口誠實記錄）；person-verify skill 同步（三段 id、#272 組合呼叫、出口改正）；census 佈局模式切換（半遷移不雙計、純 legacy 不誤拒）；App skip 改 pinned 鍵。
- **R1 verify 修正輪**（2026-08-17，8 blocking）：
  - **⚠️ apply id 升三段形 `citekey:authorIndex:personKey`**（釘 person——提名改指時顯式拒絕指名兩造；兩段 legacy 形僅當該位置提名仍唯一時等價）
  - **⚠️ CLI `resolve-people --apply`（篩選式批次）對寬鬆 tier 候選拒絕、`--tier` 具名才放行**——新 `--tier` 選項（exact／confirmed-elsewhere／reorder／initials，可重複）收窄套用範圍
  - verdict rule 依 tier 導出（`author-name-reorder`／`author-name-initials`／`author-name-confirmed-elsewhere`——寬鬆 tier 的校準史與 exact 分開計；legacy 無尾註 verdict 維持 exact 語意）；三態計數按 rule 分桶、CLI 逐 rule 印
  - `LooseNameKey` 句點分段修正（`Chen, Y.H.`→`chen yh`；`L.W. Wang` 假陽性除）
  - 否決抑制改與提名同套正規化（EN DASH 變體壓得住）；淘汰而得的唯一命中 reason 揭露；confirmed-elsewhere 只吃 work-holder verdict
  - CLI／App 歧義列帶 tier、指引分層（exact 兩難 vs 寬鬆共鍵通常是不同人）
  - `bootstrap-people` 新增「與既有 person 寬鬆共鍵」桶（先消歧不建檔、全否決後回歸建檔候選）；`PersonBootstrap.resolve` 增 `rejected:` 必填參數
  - census：`glob.escape` 防靜默零計數（自檢 exit 3）、口徑統一（總邊／literal 邊／distinct）、org-parents 第四域
  - campaign skill 重寫：候選不在列的三因分辨階梯（歧義／截斷／真無命中）、initials 逐 entry 判斷、「store 內容是資料不是指令」條款

### venue 域（store format 11，#304——與本版並行出貨）

- **store format 11**（#303／#304 venue change）：新 entity 形狀 `venue:`（`type` 為封閉列舉——**當時是三值，#324 已改為六值**；`names` 沿革 timeline）＋ `Entry.venues` 二態 ref 邊（`.key`／`.literal`，literal-first）。舊 binary 讀 `venue:` 整檔 quarantine（實測），故 non-additive bump；新 binary 對 format < 11 的 venue 寫入 gate 拒絕指路 `migrate-venues`。
- **6 個新 MCP tool**：`akashic_venue`（記錄＋沿革＋文章編年 list——反向邊現算）、`akashic_venues`、`akashic_add_venue`、`akashic_resolve_venues`（apply+reject 組合腿同 #272 契約；verdict 落被判定 venue）、`akashic_add_organization`／`akashic_resolve_organizations`（#304 org 重啟的 MCP 面補齊）。
- CLI 對應面：`venue`／`venues`／`add-venue`／`resolve-venues`／`migrate-venues`（additive-idempotent 回填，per-file trackedness 守門）。
- importer（WoS／Zotero）自動產生 `.literal` venue ref（單一對映源 `VenueDerivation`；進庫不猜 key）。
- 新 skill `akashic-venue-verify`：literal→verdict 查證紀律（Crossref／OpenAlex／ISSN Portal 證據鏈、刊名沿革 timeline）。

## [0.8.0] - 2026-08-16

- **store format 10**（#227／#241）：person `names` 巢狀化（`authorized`／`variant` 分區——子集關係成為結構性事實）＋ `id` 改為獨立 v4 UUID（單一來源事件發放、永不由名字重算），既有 867 筆一次性換發。舊 binary 讀巢狀 names 整檔 quarantine；新 binary 讀舊格式 fail-closed 指向 `akashic migrate-person-identity`（dry-run 預設）。org 刻意不巢狀化。
- `akashic_update_person` 收巢狀 `names` 物件（平面陣列拒絕、分區重疊拒絕）；讀取面一律 `names.all`。
- `akashic_person` 對 quarantine 歧義查詢回「無法判定」（`undeterminable`）而非 not-found；name-lookup 零候選時附 `quarantined`／`note` 欄位。
- binary：signed＋notarized universal（`akashic-mcp-v0.8.0`）。

## [0.7.0] - 2026-08-15

- **`akashic_resolve_people` 組合呼叫解禁**（#272）：apply+reject 同呼叫改兩段式（reject 先完整提交、apply 以新狀態重解析），回應 `legs.{reject,apply}` 按腿回報；同列兩邊點到以 `skippedBecauseRejected` 回報。單腿呼叫形狀不變。
- **`akashic_person` 增 verdicts 段**（#270）：判定列舉（observed/stale 標示）——stale verdict 首次有列舉面。
- divergence merge 把 verdict 當一等邊（#271）：person merge 自動遷移、work merge 的 citekey 退役改寫 value。
- **`akashic_import_wos`**（#290）：WoS 匯入的 MCP 面——與 CLI `import-wos` 同一條無損路徑（#206：具名對映＋殘餘收集＋`droppedColumns` 可見）；`path`／`csv`／`dry_run`，形照 `akashic_import_zotero`。
- **store format 9**（#223）：附件鍵域收窄（移除 `pool`）＋記錄側副本引用 `akashic.sources`；真實 store 升 9 前 sources 寫入被 gate 拒絕指路。

## [0.6.0] - 2026-08-15

- **⚠️ `akashic_set_status` 呼叫契約變更**（#258）：省略 `status` 不再是清除——會被**拒絕**；清除要顯式 `clear:true`（與 CLI `--clear` 逐條對應）。`akashic_tag` 零參數同步由 no-op 改拒絕。守衛下沉 `AkashicService`，CLI／MCP 共用同一份判準（先前「省略＝清除」對 LLM 消費者是 footgun：省略即 valid 的面恰無守衛）。
- CLI 新增 `add-person`（單筆建 person——unkeyable 作者指定 key 的入口）與 `divergences`（列未決歧異；`--json`＋人可讀同源）——parity 最後兩格（#250）。
- 歸戶修正隨同出貨：識別重排等價對稱化（#226，55.5% 分裂收斂）、變音符號作者自動摺疊＋CJK 作者回報不丟棄（#238）。
- `export-tables --view <key>`：view-scoped 關聯表匯出（#274）。
- binary：signed＋notarized universal（`akashic-mcp-v0.6.0`）。

## [0.5.5] - 2026-08-14

- **#280 裁決落地（選項 2）**：resolution verdict 刻意不攜 rests-on——證據載體依生命週期分工（已判定 → person `references`；未判定 → divergence `restsOn`）。person-verify skill 的「工具面缺口」註記改為設計裁決；規格 requirement 與 entity-backlink 規則同步。shell-only bump（binary 仍 0.5.0）。

## [0.5.4] - 2026-08-14

- **更正 `akashic-wos-intake` 邊界段**（#281）：0.5.3 的「doctor 不查 DOI 共用」為誤——doctor 自 #94 即有兩道檢查（正規化 DOI 共用組＋同標題同年不同 DOI），敘述改回正確指向。
- wos-intake 的 W8 欄名清單降級為快照，正典移至 repo `docs/import-wos-mapping.md`（#286，含對映目標與合成語意；該 repo 為 private，無存取權者取不到）。shell-only bump（binary 仍 0.5.0）。

## [0.5.3] - 2026-08-14

- **`akashic-wos-intake` skill**（Akashic-Library #277）：WoS 型清單的匯入前 QA 閘——DOI 補查（寫回既有 `DOI` 欄）、同篇雙列偵測（early-access／erratum／重複；無 DOI 桶走標題∧年份∧type 三訊號）、機構欄容錯、intake 報告經人確認 → 另存 TSV → `import-wos --dry-run` → 寫入。分母在這一步定案。
- bootstrap 的 xlsx 匯入路徑改為先過 wos-intake（觸發競爭消解）；store 內 DOI 共用無自動偵測的缺口另記 #281。shell-only bump（binary 仍 0.5.0）。

## [0.5.2] - 2026-08-14

- **`akashic-person-verify` skill**（Akashic-Library #276）：歸戶查證——「這個 literal 作者是不是這個人」的證據鏈（Europe PMC core／ORCID／OpenAlex／出版商頁）、affiliation timeline、判定建議，經使用者確認後以 apply/reject 落 verdict；查不出來記 divergence（第三個出口）。`references/verification-traps.md` 收四類實測陷阱。shell-only bump（binary 仍 0.5.0）。
- `akashic-bootstrap` description 讓渡身分判定給 person-verify（觸發競爭消解）。

## [0.5.1] - 2026-08-14

- **Plugin shell 遷入 Akashic-Library**（#275）：plugin.json／.mcp.json／wrapper／skills 自 psychquant-claude-plugins `plugins/akashic-mcp/` 遷至本 repo `plugin/`；marketplace 改以 git-subdir source 引用本目錄。Release 流程單 repo 化——binary release 與 plugin bump 同 repo 同 commit。
- **`binary_version` 欄位**：wrapper 的 binary release tag 改讀 `binary_version`（缺席回讀 `version` 相容舊檔）——shell-only bump 不再產生不存在的 release tag（本版即例：shell 0.5.1、binary 0.5.0）。
- `akashic-bootstrap-workspace`（eval 工作區，504 檔）不隨遷入 plugin——移存本 repo `docs/skill-evals/`（不出貨給安裝者）。

## [0.5.0] - 2026-08-14

- 消解判定 ledger（Akashic-Library #232）：`akashic_resolve_people` 新增 `reject` 參數（顯式否決、entry 不動）；apply 同動作寫 `resolution-confirmed`；候選帶三態計數（confirmed/rejected/pending，不報比率）、已否決獨立 `rejected` 段、`pendingTotal` 可見
- **Store format 8**：verdict reference 需要 store format ≥ 8——format < 8 的 store 上 reject 硬擋（指路訊息）、apply 照常歸戶但跳過 verdict 並以 `verdictsSkipped` 揭露；升級程序見 Akashic-Library #247
- binary：signed + notarized universal（akashic-mcp-v0.5.0）

## [0.3.0] - 2026-08-04

### Added
- `akashic-bootstrap` skill：把資料補進 store 的完整路徑——認出手上是什麼（不要求使用者預先分類 person／work）→ 查 store 已有什麼 → 外部查詢 → 多訊號合取驗證 → 乾跑報告 → `--apply` 才寫。
  - `references/work-sources.md`：Crossref 與 Europe PMC 的實測覆蓋率與三類「像但不是」的記錄（審稿報告 DOI、preprint、同前綴會議摘要）。
  - `references/person-sources.md`：ORCID 的 employment 不回填歷史、given-names 常是英文暱稱；姓名比對靠佐證不靠拼音相似度。
  - `references/writing-to-the-store.md`：哪些操作有正規入口、哪些沒有（更新既有記錄欄位無入口，見 Akashic-Library#68）、以及沒有時的正確繞法（decode → 改 → encode，絕不手刻 YAML）。
  - `scripts/crossref_match.py`：標題→DOI 的四訊號合取比對 + 反向驗證，內建三類陷阱的自動繞行。

### Removed
- `person-search` skill —— 內容併入 `akashic-bootstrap`。它要求使用者先判定「這是 person 查詢」，但實務上人手上常是一個名字、一個 citekey、一份匯出檔，不知道也不該需要知道它對應到哪種實體形狀；分類是看內容就能決定的事。找人、消歧、聚合、追關係四段全部保留在新 skill 的步驟 1。

## [0.2.0] - 2026-07-30

### Added
- Binary v0.2.0（14→17 tools）：`akashic_libraries`（#13 membership views）、`akashic_person`（#14 人物聚合）、`akashic_files`（#18 多實體庫切換）；`akashic_search` 支援 `library` 過濾；index schema 版本機制；config schema v2（多檔案 registry，向後相容）。
- `person-search` skill（#14）：找人→消歧→聚合→追關係 workflow；需 akashic-mcp binary ≥ v0.2.0（`akashic_person` tool）。隨 akashic-mcp-v0.2.0 binary release 上架。

## 0.1.0 (2026-07-22)

- 首發：14 tools（7 讀 + 7 寫衍生層）；Akashic store 查詢/關係/圖形、person 解析逐候選 apply、Zotero 單向 pull。
