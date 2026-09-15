# 兩種編輯方法：AI 編輯（判定型、依規則）與程式編輯（決定論式）——每個寫入面只能是其中一種

使用者 2026-09-03（+08:00）定調（#505）：本 repo 的編輯分兩種——**AI 編輯**（複雜、根據規則編輯）與
**程式編輯**（決定論式）。

適用於**任何把東西寫進 store 的面**——CLI subcommand、MCP tool、App 的寫入動作、skill 驅動的批次流程。
不適用於**讀取面**（doctor、query、export——它們不改 store）。

## 規則

**每個寫入面在設計時就要歸類為兩種之一，且兩種的義務不同。** 判準只有一句：

> **同一輸入是否必然得到同一輸出？** 若答案取決於**名字以外的證據**（共同作者、機構、作品領域、時間窗、
> 原文頁面），它就是 AI 編輯；若答案由輸入與規則完全決定，它就是程式編輯。

| | AI 編輯（判定型） | 程式編輯（決定論式） |
|---|---|---|
| 做的是什麼 | **判定**：這個 literal 是誰、這一格要不要拆、這本刊有沒有頁碼 | **轉換**：改名、遷移、匯入、批次建檔、只補不存在的鍵、收攏重複 |
| 誰執行 | AI agent（人可代）——`identity-is-judged-not-matched` 的「底線函數」 | 程式——`normalize` 以外沒有底線的那些函數 |
| 產出的義務 | **留 verdict／judgement**（`ResolutionLedger`、`ProvenanceReference`），必附理由，可回溯、可逆轉（`demote`／`repoint`／`resolve-divergence`） | **決定論**（同輸入同輸出）、**冪等或有具名逆操作**、可預期失敗**整批擋零寫入**、代價要**量測**不猜 |
| 不得做的事 | 不得由字串謂詞代做（`identity-is-judged-not-matched`）；不得把「未判定」折成預設值（`Venue.paginated` 的 nil） | 不得由 AI 逐筆手做（O(n²)、會出錯）；不得在 default 位置留兩條讀法（`no-compat-fallback`） |
| 失敗形 | 誤判——熔合兩個人、拆錯一格；發現時下游已建在錯的身分上 | 撕裂——部分寫入、index 過期；或安靜分岔（兩份政策各自演化） |

**混合的面要拆成三段，不要混在一個函式裡**：**提名（程式）→ 判定（AI）→ 落地（程式）**。`resolve-people`／
`resolve-venues`／`resolve-organizations` 就是這個形：`LooseNameKey` 的提名是 recall、由程式做；`apply`／`judge`
的判定由 AI 做且留 verdict；寫回 store 與收攏由程式做。

### 裁決史（封閉列舉——列數以下表為準；新的寫入面加一列，不得依性質相似類推）

| 寫入面 | 種類 | 一句話理由 |
|---|---|---|
| `resolve-people apply`／`reject`／`judge`（#272／#303／#386） | AI | `literal → key` 是身分判定；Jaccard 實測同一人 0.40、不同人 0.50，字串謂詞站在錯的一側 |
| `resolve-people split-author`（#443） | AI | 「這一格裝了兩個人」是判定；但落地是程式（切出的每一段必然是原文子字串）——持久化見 #450 |
| `resolve-people un-split`（#513） | 程式 | **split 的具名逆操作**——合回去的字串逐字取自 #450 寫下的記錄 value，不做任何判定。同輸入必得同輸出；整批擋零寫入；三種歧義（同 value 多筆記錄、各段出現多處、各段不連續）一律**拒絕不判定**（形狀取自 `enrich` 對 DOI 命中 ≥2 筆的既有處置）。段已升格為 `.key`／`.organization` 時拒絕並指向 `demote`——那一格才是判定的逆轉 |
| `resolve-people drop-author`（#457） | AI | **「這一格裝的不是作者」是判定**——要知道 `No authorship indicated` 是 PsycInfo 的無署名佔位字串，字串謂詞單獨做不出來。所以理由必填、記錄必留（`Entry.references` 的 `field: authors`、statement `移除：理由`，與作者位改寫同一次寫入，需要 store format ≥ 17）。**沒有具名逆操作**，而那不是「還沒做」：記錄留著被移除的字串逐字，但**刻意不留位置**（同拆分記錄不存索引的既有理由——索引在同一批的前一次操作之後會位移），所以還原無從定位。真出現要還原的需求時是一次顯式裁決。它把作者位的數量改成 N-1（可到 0），與 `split-author`／`un-split` 同族，各自單獨呼叫 |
| `resolve-people attribute-org`（#443） | AI | 團體作者的升格是判定，org key 由呼叫端顯式給 |
| `resolve-venues apply`／`reject`／`repoint`／`demote`（#304／#418） | AI | 同 people；`demote` 是判定的逆轉，原字串從 verdict 逐字取回、取不到寧可拒絕；≥2 個不同 literal 時同樣拒絕不判定（#554 R9，D23）。**翻轉判定時退役相反的那筆**（#554 R9，D20）：`repoint`／`demote` 寫 rejected 時把同 holder 上同一配對的 confirmed 移除（反向 repoint 對 rejected 亦然）——verdict 沒有時間戳，「後者為準」只有寫入面知道，留著就是 #486 的矛盾對；歷史留 git（同 un-split 的取捨）。**前提是配對只由一條邊實例化**（#554 R10，D25）：verdict 不帶 venue index，同一 work 兩條邊指同一 venue時退役會把另一條邊的證據一起刪——那種 work 具名拒絕零寫入；退役的每筆逐字回報（截 20 筆、總數揭露，R11）。**唯一性對寫入後的邊集合驗，生產端也擋**（#554 R11，D27／D28）：R10 的 D25 只看原始 entry 的 from——`repoint` 改指到本 work 已有邊的 venue、`apply` 對兩條同刊名的 literal 邊各 apply 一次，都造得出 D25 宣告不得存在的形；現在 `apply`／`repoint` 對寫入後會出現「同一 work 兩條 key 邊指同一 venue」的整批拒絕零寫入，同一批同一 work 的兩個 move 不得帶同一個 literal（逐 move 的退役會互相覆蓋）。既有的這種 work 由 `Entry.validate()` 報 warning；刪掉多餘邊的面另案 #572——落地前出路只有手改 YAML。**R12（D33）：`apply` 改逐筆略過並具名**（`skippedDuplicateVenueEdge`）——整批拒絕讓一筆毒候選殺掉同批無關的候選、既有的重複邊鎖死不相干的歸戶；store 狀態不符是「該筆略過並具名」（`judge` 的先例），語法錯才整批拒。D27 只看被動到的邊、同 literal 的 move 只在 venue 集合相交時拒；否決抑制改比 `matchingKey`（與其餘三處同粒度）|
| `resolve-organizations`（#304） | AI | 同上 |
| `resolve-divergence`（#71 一族）／攣生合併（#456／#459／#553） | AI | 兩筆記錄是否同一實體是判定；合併含全庫改寫＋刪檔，所以落地那一半是程式且要乾跑過目。**#553 起 venue 走同一個面**（不另開列——列是「寫入面」，而這是同一個面多收一個 shape）。venue 側有一格與 person 側**相反**且必須寫出來：被併者的 `authorized` 在 person 是**拒絕條件**（#81：「哪個名字對外」是判定），在 venue 只是**提醒**——實測 479/479 筆 venue 的 `authorized` 恰好等於 `[names[0]]`，唯一寫入者**當時**是 `VenueBootstrap` 的建檔慣例，所以它不承載判定。拿一個不做判定的操作的副產品當拒絕條件，會讓合併對它要解決的 7 組重複全部無用。**#554 起有面可寫（`update-venue --authorize`），這一格 2026-09-12 重開過一次、裁決不變**——理由換了：那個面不留 judgement（#564），所以「人確認過的 names[0]」與機械值在 store 裡仍然長得一樣，合併端拿不到可以承重的東西。#564 裁「留」且落地後升成拒絕條件（`DivergenceResolve.authorizedDemotedByMerging` 的 doc 記著觸發條件）。**#554 R12 兩條新拒絕（D31／D32，person 與 venue 同）**：倖存者與被併者對同一配對持相反判定時拒——合併不裁決哪一筆對，那是兩個判定的衝突（#486 的矛盾對，處置沒有工具面）；venue 合併把同一 work 的兩條 key 邊塌成一條而兩筆正規化後不同的 confirmed literal 都留下時拒（塌完之後 D23 讓那條邊永久不可 demote）。被併者的 verdict 遷移以 `verdictEqualityKey` 去重——R11 之前比位元組，「(field, value) 冪等」只在位元組層為真 |
| `update-venue --paginated`（#406） | AI | 「本刊是否使用頁碼」是判定，必附 judgement 與 rests-on |
| `update-venue --authorize`／`akashic_update_venue.authorize`（#554） | AI | 「這個名字是本刊的對外形」是判定——與 `authorize-names`（#81）同一句話換到 venue。語意是同 `WritingSystem` 原子替換（不是 append：「每書寫系統至多一個」對 470 筆機械值必擋 append）；被換下來的舊指定**移出 authorized、留在 names、不標 variant**——程式不替呼叫端多說「它是異寫」（R1 verify D1）。**不留 judgement**（與同列的 `authorize-names`、#471 `add_variant` 一致）——這是**有記錄的裁決不是遺漏**：三個名字分類面要不要留、留什麼形狀一次裁（#564）；在此之前這一格對「留 verdict」的義務是**未兌現的**，而它的代價住在上面 #553 那列（合併端分不出判定與機械值）。落地是程式（入口的輸入驗證整批拒絕零寫入；名字內容的不變式住在 `Venue.validate()`——四條的規範文字只在 `docs/store-format.md` §5.7（這裡不複述：R6 verify 第 10 列抓到本列是七份副本裡第一個分岔的）——所有寫入者存 canonical，D8；分割互斥同樣由 `Venue.validate()` 擋、不重造） |
| `record-divergence`（#77） | AI | 「當場記錄而非當場判斷」——記下判定尚未做出，本身也是判定型工作的一部分 |
| `rename`／`rename-person`（#35／#232／#395） | 程式 | 改名不改身分；參照集合由封閉列舉逐條窮舉、可機械檢查 |
| `migrate-*` 一族／`fmt`（#227／#304／#325／#394／#422） | 程式 | 格式遷移；不可逆但決定論，前置是 git 追蹤，乾跑逐筆過目 |
| `import-wos`／`import-zotero`（#206） | 程式 | 對映歸對映、收集歸收集；conflict 交人，不猜 |
| `create-entry`／`createEntries`（#206／#455） | 程式 | citekey 由規則生成；批次內碰撞由 `existing` 累積消解；可預期失敗整批擋 |
| `enrich-from-zotero`／generic enrich（#340／#458） | 程式 | 只補不存在的鍵；來源給什麼收什麼，不判定 |
| `bootstrap-people`／`-organizations`／`-venues`（#367；#547／#548 補註） | 程式 | 門檻建檔是提名不是判定——建出來的實體仍待 `resolve-*` 判定歸戶。**#547 起 `bootstrap-people` 多扣住一類**：彼此寬鬆共鍵而兩邊都還沒有記錄的群（`pendingMutual`），與既有的「與既有 person 共鍵」對稱。**種類不變，仍是程式編輯**——它用 `LooseNameKey` 做決定論式**提名**（同輸入必得同輸出），判定留給人／AI；`identity()` 一行不動，因為放寬它就會變成程式做身分判定（`identity-is-judged-not-matched`）。這一列**不另開新列**：新增的是既有寫入面的一個報告欄位與一道扣留，不是新的寫入面，而本表的列是「寫入面」。**#548 對 venue／org 做同一件事，種類同樣不變**——但判準是另一套（`LooseTitleKey`：標點／`&`／前導冠詞），不是把 `LooseNameKey` 平移過去。理由是人名與刊名的變異形狀不同：人名會被索引系統重排（`Hsu, Yung-Fong`）、刊名不會，而 token 集合相等對刊名是誤判來源。那是一次裁決，寫在 `LooseTitleKey` 的檔頭 |
| `library add`／`remove`、`tag`、`link`、`set-status`（#219／#258／#455） | 程式 | 集合語意，冪等 |
| order-insensitive collapse（#461）、verdict holder 遷移（#463） | 程式 | 對已判定結果的機械搬移；只收本次觸及、不碰未觸及 |
| `authorize-names`（#81） | AI | 「哪個名字對外」是人的判斷，建檔不得機械偽造（#227） |
| `enrich`／`akashic_enrich`（#458） | 程式 | generic add-only：只補不存在的鍵、來源給什麼收什麼、不判定——同輸入必得同輸出。DOI → citekey 由程式做是**識別碼例外**（`identity-is-judged-not-matched`），命中 ≥2 筆時**拒絕不判定**（`ambiguous`）——判定屬 #459 的攣生管線。`enrich-from-zotero` 自此是它的 adapter，種類不變。**#517 起它寫來源 reference，而 kind 必然是 `retrieval` 不是 `judgement`**——那不只是形狀偏好：judgement 是 AI 編輯欄的產出物（「留 verdict、必附理由」），一個決定論式的補值面**不該發出判定**。「這個值取自那份存檔」是一次取得的記錄，不是推理 |

新增下一個寫入面 = 在這張表加一列，並在 `mcp-cli-parity` 的表裡同時裁決它的兩面。

## 為什麼：兩個方向的失敗都發生過

| 方向 | 實例 | 代價 |
|---|---|---|
| 讓程式做判定 | #383：助手兩版字串判準都錯，第 2 版會把謝叔蓉重新拆成兩個人（#13 記載的合併代價已付過一次） | 誤判不可逆——發現時下游已建在錯的身分上 |
| 讓 AI 手做決定論工作 | #455 之前 `akashic-venue-works` 逐筆 `create-entry`：每筆 2 個 process × 全庫 load，1545 筆約 3 小時（O(n²)）；批次面落地後 50 筆 6 秒、1545 筆 9 秒（2026-09-03 量測） | 慢，而且**會出錯**：2026-08-28 手改 YAML 差點弄丟一筆 DOI（`mcp-cli-parity` 識別碼寫入面那一節記著） |
| 判定做了卻沒留記錄 | #443 的 split 只把理由印進報告、store 不留（#450 裁決持久化） | 不可逆且不可偵測——`literal-first-then-key` 的「誤可逆」論證在這一腿為假 |

三個方向的共同點：**種類沒被說出來**。`identity-is-judged-not-matched` 講了單向（程式不得做判定）；本規則補反向
（AI 不得手做決定論工作）與第三項（判定必須留記錄），並要求每個面在建時就歸類。

## 驗證責任落在 adapter 還是 core——**暫不立通則**（#528，2026-09-09）

#519 把「單一字串的長度上限」裁在 **core**（`AddOnlyEnrichment`），理由是缺口的形狀與
adapter 無關（「core 收下任意長的字串」），而已有兩個 adapter 共用同一條路徑。#528 問
這能不能一般化成「adapter 與 core 之間，合理性檢查該由誰負責」的通則。

**裁決：不立。理由是證據只有一個。** 2026-09-09 實測：全樹**只有一條**「core 政策 ＋
adapter」的鏈——`AddOnlyEnrichment` 與它的 `ZoteroEnrichment` adapter（重跑：
`grep -rln 'AddOnlyEnrichment\.' Sources/ --include='*.swift'`）。從一個案例寫出總括判準，
正是全域 `common-spec-prose-enumeration` 記過的失敗形狀：那句話的字面涵蓋範圍會大於
它唯一的案例，然後在邊界上自己長出沒人同意的答案。

**已知的那一個資料點記在這裡，供日後收斂**：

> 缺口的**形狀**與 adapter 無關時（「core 收下任意長的字串」是關於 core 的性質，不是關於
> 某個 adapter 的），檢查放 core；而那條鏈上已有 ≥2 個 adapter 共用同一條路徑，使「放
> adapter 端」必然要複製。

**觸發條件可檢查**：出現**第二條**「core 政策 ＋ adapter」的鏈時重開——那時才有兩個點
可以連線，也才看得出上面那句話是通則還是巧合。在此之前，每條鏈各自裁決並在本檔的
封閉列舉加一列。

## 跟其他規則的關係

- `identity-is-judged-not-matched`：本規則的「AI 編輯」欄就是那條的「底線函數」；那條說判定不得由字串謂詞代做，
  本規則補上對稱的另一半。
- `literal-first-then-key`：進庫（程式：以 literal 原樣收）→ 升格（AI：顯式消歧留 verdict）的生命週期，正是
  「提名（程式）→ 判定（AI）→ 落地（程式）」三段的實例。
- `no-compat-fallback`／`lossless-intake`：程式編輯欄的兩條義務（決定論、量測；丟棄必須可見）來自它們。
- `mcp-cli-parity`：新寫入面加列時兩張表要同時改——那張裁決兩面，這張裁決種類。
- 全域 `common-spec-prose-enumeration`：上表是封閉列舉，判準那一句只用來**判斷新面該加哪一列**，不允許讀者拿它
  對既有面重新歸類。
