# 零實例裁決表的量測與歷輪補記

本文件是 [`.claude/rules/zero-instance-guards.md`](../.claude/rules/zero-instance-guards.md)（以下稱**規則檔**）的附錄，**不自動載入**。使用者 2026-10-05 裁決（#711）：規則檔每個 session 自動載入，所以它的裁決表每一列只留情形、裁決、理由的核心；各列的量測腳本、逐輪 verify 的補記與後來的 change／issue 補上的段落，**原樣**搬到這裡，依列號分節。

**讀法**：這裡的段落是從規則檔原樣搬來的，文中的「本檔」「本表」「表下方」「上方」指的是規則檔與它的裁決表（表格裡指向「表下方」的句子已改成指向本文件）。每一列的核心句仍在規則檔，這裡只放其餘的部分，所以一段補記可能接在規則檔那一列的某一句之後。

**守衛讀這份文件**：`zero-instance-rows-audit` 掃這裡與規則檔的量測指令（自證閘、合模板的條數與棘輪標記——棘輪標記住在這裡），`measured-numbers-audit` 掃這裡的「實測 N」。寫法見 [`measurement-commands-self-prove`](../.claude/rules/measurement-commands-self-prove.md)。

## 各列的歷輪補記

只列有補記被搬過來的列。

### 前言與規則段

**從規則檔前言與規則段搬出的括注**

- 「第 4 類同樣是顯式擴入的」之後：（#555 R2，2026-09-18——R1 verify 四席各抓一次：第 24 列在表裡宣稱「理由是第四種」，前言卻仍是封閉三類；理由的種類與**對象**的種類是兩件事，本段擴的是後者）
- 「撞牆」與「照猜出來的形狀實作了」兩項」之後：（R2 verify 第 14 列；R3 verify 第 4／7／15 列——R3 曾寫「新的只有撞牆」並斷言「前三類沒有任何一個有使用者面的後果」，對第 4／9／15／16 列為假：壞資料、誤導讀者、venue 消失都落在使用者身上）
- 「——在下表加一列：情形／裁決／理由。」之後：（這句曾寫「新增零實例守衛時」——第 2、3 類擴入時就與它分岔，第 4 類再拉寬一級（R2 verify 第 7 列）；R3 改成「新增……或對第 4 類做出動不動的裁決」，仍漏掉第 22 列那種對第 3 類的「保留」（R3 verify 第 6 列）——觸發條件要寫成與對象無關的形式。）

### 第 8 列（#416）

**理由欄的其餘部分**

只做前半的話，日後有人在 `validate()` 加一條非 key 的 error 級檢查，零實例悄悄變成一實例而沒有任何人知道排序守衛從裝飾品變成了承重結構。

第 25 列把可達的 error 類別再擴四個並在該列對帳

**從留下的句子裡搬出的括注**

- 理由欄「前提的失效日期」之後：（#554 R6 補記）

### 第 12 列（#365）

**情形欄的其餘部分**

**這一列的零是駁回出來的，不是量出來的**：2026-09-03 實測 865 筆 person 中 **11** 筆有 ≥2 個彼此不同的 confirmed literal（其中 1 筆跨書寫系統：`che-cheng` 的 `Che Cheng`／`鄭澈`），全部可駁回——腳本逐人列出的 literal 顯示 10 組只差縮寫形、標點或大小寫（APA7 的參考文獻本來就把 given name 正規化成首字母，差異活不到輸出），跨書寫系統那筆由 #81 的 `.latn` 裁決吸收；而「兩個彼此無共同 token 的拉丁名」（真筆名的形狀）**0** 筆。量測腳本與清單見量測文件

**理由欄的其餘部分**

這裡引的是 `entity-backlink-completeness` 的**立場**（《邏輯哲學論》3.325 的工程類比：讓那種分岔在記法裡**寫不出來**）而非它的封閉列舉——那張表管的是關係邊，名字是屬性，所以這是受稽核的類比，不是類推。

觸發時要的是 per-occurrence 的**選擇**（指向 `Person.names` 裡某一個名字的 selector），不是名字的第二份 copy，所以它不製造第二個家；#386 的 `judgeAuthorships` 是同一個位置的先例（per-work 的判定），但它選的是**人**（收 personKey）不是名字——selector 的形狀是觸發時才裁的事。

### 第 13 列（#464）

**情形欄的其餘部分**

三個結構缺口：#232 rename／person 側、#271 merge／person 側、#460 venue 側（#460 的 changelog 原話「家族第三個缺口」）；實際量到的 stale 累積只有 #460 那一次（來源是 #456 的攣生合併批次），而抓到它的三個機制全在那一次——205 條 stale 由 #456 pilot 人肉抓、殘留 1 條由 verify lens 全庫掃抓、清理完整性靠 set-difference 腳本**驗**（驗不是抓）。

**零有第二個來源**：#463 網格裡還沒補的格——`renameEntry` 沒有 organizations 迴圈——今天沒被走過（organizations 持有的 verdict 只有 9 條、其 holder 沒被 rename 過；verify DA 在副本上 rename 兩次即得 4 條死 verdict）。**該格已於 2026-09-03 由 #463（PR #493）補齊，第二個來源自此消失**——現在的零只剩「清理過之後的零」一個來源。重跑指令見量測文件

**理由欄的其餘部分**

**severity 是 warning，三個理由，且都是「現在」**：(1) 升 error 會把**第 8 列釘住的零翻掉**——那一列的依據是 per-record 的 error 級檢查全部是 key 合法性檢查、對載入後記錄不可達；死 verdict 若是 error 就是第一個既非 key 檢查又可達的 per-record error，`errorsFirst` 從裝飾品變承重結構，而第 8 列明寫那個轉變不得安靜發生——**本列因此繼承第 8 列的釘零義務**（測試釘住 malformed value 對已載入記錄不可達）。(2) #464 的 Expected 逐字寫「warning 級」。(3) 今天沒有處置命令，升 error 會讓一次合法的 rename 把 `validate` 打紅而修不掉。**不是**「rename 後常態為真」（假：只有 org 持有的那幾條）、也**不是**「rename 本來就全遷」（假：沒有 org 迴圈）——兩句 verify 都量過。#463 補完且有修復路徑後，error 要重開裁決，第 8 列與本列一起改（#463 已於 2026-09-03 補完；修復路徑仍缺，裁決未重開——#464 的 closing summary 記著）。**誠實邊界**：warning 級的 `validate` 對它 exit 仍為 0（DA 實測 5 條死 verdict 仍 exit=0）——它做到「掃得到」、做不到「叫醒」（`blocked-issues-must-be-scannable` 的同一條界線）；CLI 逐行可見、MCP 進 `recordIssues`，App 側欄「記錄」Section 渲染計數（#487，2026-09-04 落地；死 verdict 這一族沒有 per-record 上限——每筆 reference／配對／記錄各一則、與記錄持有的 verdict 數線性（`psychological-methods` 持 1,352 筆，holder 全退役就是 1,352 則），CLI `validate` 逐則完整；組合式的六族有上限，R24 D66／R25 D70／R26 D72）。

**#554 R21／R22 補記**：rename 遇到目的鍵上已有的死 verdict 一律具名拒絕、零寫入（D60／D63，含 quarantined 檔——位元組比對 `<kind>:<newKey>`，R22 的行級比對被 YAML 折行擊穿，R22 verify 四席同指）——「處置是人的重新消歧」在 rename 這一格自此有閘（R21 verify 第 18 列：D60 曾只記在第 27 列）

**從留下的句子裡搬出的括注**

- 理由欄「看，而下一條 holder 退役路徑」之後：（#463 網格裡還沒補的格）
- 理由欄「觸發條件可檢查」之後：（用含這條檢查的 binary，指令見量測文件）

### 第 14 列（#464）

**理由欄的其餘部分**

**本表第一個成本低而「不寫」的列**，理由與成本無關。本列**不取代** #486——「在等 #470」的可掃描位置是那張 issue 的 `### Blocking`，不是這張表（`blocked-issues-must-be-scannable` 的三個位置是封閉列舉）。

對照第 10、12 列——它們的觸發條件是「出現一個需要它的場景」，沒有任何機制會叫醒任何人。**change `resolution-verdict-states` 補記（2026-09-25，#619／#636）**：矛盾只比 confirmed×rejected——兩個判定層級（nominated／judged）都算、`resolution-undecided` 不參與（未決是查證歷史，與判定並存不是矛盾）；配對鍵的單一定義搬到 `ProvenanceReference.verdictPairingKey`，本掃描與合併閘（D31／D34）的兩份複本都改呼叫它

### 第 15 列（#453）

**情形欄的其餘部分**

2026-09-04 實測 live store：62 個 digest 引用、41 個 distinct `sha256:`，**本機缺 1 筆**——而那一筆不是缺席，是 divergence `B354B9E9…` 的 `judgement.restsOn` 裝了一個 URL、根本不是 digest（訊息分開說，見 `danglingSourceIssues`）；同一份 store 拿掉 `sources/` 的副本跑同一支 binary：**41 筆**（40 venue ＋ 1 divergence）。兩層盲區都實測為真：`missingSourceDigests` 不掃 venue（#406 起承重證據住在 venue 上）也不掃 `Entry.references`（第 15 條邊）；且它零 production 呼叫端——doctor 接的是 `auditSourceIndex()`，捏造的 digest 在 blob 與 index 兩邊都不在、兩邊一致、audit 說「全部一致」。重跑指令見量測文件

**理由欄的其餘部分**

第 3 列「未涵蓋不得冒充通過」正是 `auditSourceIndex` 的沉默形：沒被檢查與檢查過且乾淨在輸出上相同。

**用詞「本機缺」不寫「偽造」**：本機分不出「從未存在」與「沒同步」，訊息把這個邊界說出來。

**從留下的句子裡搬出的括注**

- 理由欄「觸發條件可檢查」之後：（指令見量測文件）
- 理由欄「「不是合法 digest 的引用數」」之後：（今天 1）

### 第 16 列（#499）

**情形欄的其餘部分**

第 13 條邊在 venue 側是 O(catalog)——`psychological-methods` 2026-09-04 實測 **1,352** 筆 resolution verdict、268 KB；硬預算 200,000 節點、每筆 verdict 量測 9 節點（2026-09-01：14,031／1,556），門檻＝預算一半÷9＝**11,111** 筆。

**理由欄的其餘部分**

~~門檻由量測換算（節點／筆）而不是憑空的數字，`VenueVerdictBudgetWarningTests` 釘住那個換算。~~（2026-09-26 失效：那個換算量的是對 store 檔不生效的節點軸，見本列末的更正；門檻現在是讀取上限的一半，測試釘的是這個推導。）**2026-09-26 更正（#645 R2 verify DA，真 binary 量過）：本列的「硬預算」量錯了東西**——`AliasEventBudget.estimate` 的節點軸只在檔案含 alias 時生效，store 寫出的檔不含 alias，讀取路徑上唯一會觸發的是 8 MiB 的檔案位元組上限（65,000 筆 verdict 的檔照常載入，8.7 MB 的檔才被 quarantine）。門檻因此改量**記錄檔本身的位元組**，取讀取上限的一半（`AliasEventBudget.recordFileWarningBytes`＝4 MiB；live 最大檔 268,627 bytes），`nodesPerVenueVerdict` 與 `venueVerdictWarningThreshold` 退場。**裁決不變**（候選 3：不改序列化位置、半預算處出聲、達門檻重開）——變的是預算的量綱；warning 出現時先查是否有呼叫端在重複記未決（venue 也收未決記錄，#619），再判斷是不是 O(catalog) 的歸戶在長

### 第 17 列（#450）

**情形欄的其餘部分**

2026-09-07 實測 live store：拆分記錄 **0** 筆——#443 已拆的 4 筆「某人與雷庚玲」（store `32916ba`）沒有記錄，因為那時值域還沒有這一格、且 #450 裁決不回填；產生實例的唯一路徑（`splitAuthors` 寫記錄）在本 change 才存在，所以兩種 warning 今天必為零。重跑指令見量測文件

**理由欄的其餘部分**

**釘零的方式**：`OrphanedSplitVerdictScanTests.testCleanStoreReportsNothing` 釘住乾淨為零、`testRejectedLiteralLaterSplitIsAnOrphan` 釘住形狀出現即報、`testSameLiteralOnDifferentWorkIsNotAnOrphan` 釘住鍵是 (citekey, literal) 不是 literal。

**從留下的句子裡搬出的括注**

- 理由欄「觸發條件可檢查」之後：（指令見量測文件）

### 第 18 列（#519）

**情形欄的其餘部分**

2026-09-08 實測 live store：1,517 筆 abstract，最長 **4,220 bytes**、p99 2,185、中位 1,137；全部 6,125 個 `fields` 值的最長也是同一筆。

**理由欄的其餘部分**

所以「還沒漲到」對它不成立，「還沒發生」也不精確：形狀發生過，只是發生在測試裡而不是 store 裡。

那一半動到了 `lossless-intake` 的封閉列舉，故該檔在同一輪顯式加了一節「有界拒絕」並寫明它**不是**那張表的第三類（成員資格是「可以丟掉這個欄位、繼續匯入」，而以大小為名的成員會被類推成「太長的欄位可以丟掉」）。**上限值不是挑的，是兩個量出來的錨點夾出來的**：下界是實測最長值的 15.5 倍，上界是 `AliasEventBudget.maxBytes`（**輸入檔**預算 8 MiB）的 1/128 未跳脫、**1/32 已跳脫**（實測 YAML 序列化放大：ASCII／CJK／換行 1.00×、`\t` 2.00×、控制字元 4.00×——單一欄位不會主導整筆記錄的預算）

### 第 19 列（#479）

**情形欄的其餘部分**

2026-09-09 實測 22 列全部有**自己的** bullet（判準是「以 `- 第 N 列的理由是` 開頭的行」，不是段落裡任何一次提到 N——那一段到處是跨列比較，鬆的判準讓拿掉某列的 bullet 也不會紅，實測過）；20 條 bullet 涵蓋 22 列，一條可涵蓋多列（「第 10、11、12 列的理由是三個**不同的**…」），所以判準是**每個列號至少被引用一次**而非「bullet 數等於列數」；未被引用的列 **0**。重跑指令見量測文件

**理由欄的其餘部分**

漂移真的發生過：第 12 列的裁決 2026-08-28 就下了，2026-09-02 才補進表，中間五天表與裁決不同步（只是當時漂的是列不是 bullet）。

**從留下的句子裡搬出的括注**

- 理由欄「觸發條件可檢查」之後：（指令見量測文件）

### 第 20 列（#526）

**情形欄的其餘部分**

2026-09-09 實測 live repo：2 個 workflow 檔、**5** 個腳本引用、不存在 **0**。重跑指令見量測文件

**理由欄的其餘部分**

前十九列的零各有來源——還沒發生（第 1 列）、走不到（第 8 列）、掃乾淨了（第 13 列）、在這台機器上（第 15 列）、還沒漲到（第 16 列）、寫入面剛長出來（第 17 列）、量的是出口（第 18 列）。

**它刻意不住在 `trigger-coverage` 裡**——併進去實測讓該支的 mutation harness **5 個既有 case 同時失敗**：那些 case 刻意在 workflow 注入指向不存在腳本的假命令（`plugin/tests/DELETED-numbers-audit.py`）來測 `invoked()` 的剖析，而本檢查會如實報那些引用。一支守衛的 harness 偽造某種內容，另一道檢查又對那種內容做存在性斷言，兩者永久互相干擾。

**從留下的句子裡搬出的括注**

- 理由欄「觸發條件可檢查」之後：（指令見量測文件）

### 第 21 列（#522）

**情形欄的其餘部分**

2026-09-09 實測三組：刪一整支守衛、刪一條 glob 規則檔、拿掉一條顯式 `DATA` 條目（重編 binary 後），**三組全部 rc=0 並印「無缺口」**。棘輪落地後三組皆 rc=1 具名；當下棘輪與清單相符、差異 **0**。重跑指令見量測文件

**理由欄的其餘部分**

前二十列的零都是關於「**還沒有**這個守衛」——沒發生、走不到、掃乾淨了、在這台機器上、還沒漲到、寫入面剛長出來、量的是出口、窮舉漏了一格。

**它刻意不住在 `trigger-coverage` 裡**，理由同第 20 列（那支的 mutation harness 會偽造它要檢查的內容）；清單則來自**同一個** `protectedInventory()`——一個自己算一遍的棘輪只會證明它自己與自己一致。**為什麼不是「把 glob 換成顯式清單」**（issue 列的另一個候選）：顯式條目 22/22 由 `missing` 逐條具名（2026-09-27；立案時 19/19——結構上恆為全部，`missing` 逐條檢查 `DATA`），但換掉之後**忘記加新規則檔是靜默的**，同一個失效換一步，而規則檔正是本 repo 承載裁決的地方。**為什麼它不是 #518 記過的「第 N 份副本」**：那次的缺陷是複製清單與 `DATA` 之間沒有東西在對帳，而棘輪整個存在理由就是被對帳——同形先例是 `hash-table-drift.sh`（生成表的漂移守衛；#629 隨 census 移植成 Swift 而退場——它守的「census 自己實作的 marker 解析與讀端不分岔」在只剩一份實作後不成立，先例的形狀仍在）。

**從留下的句子裡搬出的括注**

- 理由欄「觸發條件可檢查」之後：（指令見量測文件）

### 第 22 列（#474）

**理由欄的其餘部分**

前二十一列講的都是**程式**——守衛（第 1–8、13、15–18、20、21 列）與欄位（第 9–12、14、19 列）。

**從留下的句子裡搬出的括注**

- 理由欄「觸發條件可檢查」之後：（指令見量測文件）

### 第 23 列（#457）

**理由欄的其餘部分**

與第 8 列成鏡像：那一列的零由**別處的**程式（load 的 quarantine）造成、可能被改掉而沒人知道；這一列的零由**本 change 之前沒有這個面**造成，而面已經有了，所以零是暫時的。

**從留下的句子裡搬出的括注**

- 理由欄「觸發條件可檢查」之後：（指令見量測文件）

### 第 24 列（#555）

**情形欄的其餘部分**

另有 **3** 筆帶 `parents` 時間軸，那是 venue 合併沒有的問題（部分—整體關係怎麼併，`Organization.parents` 的 doc comment 明寫它與 person 的隸屬是不同的 predicate）。**誠實邊界（兩種形狀結構上看不到，R3 verify DA 第 11 列：R3 寫「一種」）**：(1) 一筆把三個機構黏在一格的 org（AERA＋APA＋NCME，R1 verify DA 第 42 列）——那是 #443「某人與雷庚玲」的形不是攣生；(2) **同一機構的單／複數誤植**（`Institute of Statistical Science`／`Sciences`，`identity-is-judged-not-matched` 記的那對）——`LooseTitleKey` 刻意不摺詞形（提名不是判定），所以若因此建出兩筆 org，它們是真的攣生而「重複群」永遠是 0。所以「重複群 0 組」承載的比它讀起來弱。重跑指令見量測文件

**理由欄的其餘部分**

**代價不是零**（R1 verify 第 4 列，R1 寫「代價是零」）：第一筆被記下的 org divergence 沒有面刪得掉（divergence 沒有移除面，#586）、只能手改 YAML——**2026-09-28 起有 `dismiss-divergence`／`akashic_dismiss_divergence`**（#586，只刪記錄、理由只進報告、要求已 commit），這項代價自此是「要人判定放棄」而不是「只能手改」；雙重零實例讓這項代價今天未兌現，且自 R2 起它一出現就由 `StoreHealth.unmergeableDivergences` 出聲。

**本列覆寫 #555 `## Expected` 的二選一（「要嘛有合併路徑、要嘛不進 `byShape`」）與 #553 changelog「venue 不重蹈」那句對 org 的延伸——覆寫者是使用者 2026-09-11 拍板；`## Expected` 依 idd-update 契約不改，覆寫記在這裡與 issue 的 Key Decisions（R1 verify 第 1／20 列）。** 零的來源要說真話（R1 寫「不取決於任何程式」，假的——R1 verify DA 第 8 列）：它由三件事按住——org 域剛重啟（#304）；#548 的 `pendingResolution` 扣留（`OrgBootstrap` 對與既有 org 寬鬆共鍵的名字不建檔，`OrgBootstrapResolveTests.testLooseKeyCollisionWithExistingOrgRoutesToPendingResolution` 釘住）；CJK 機構名產不出 key（`akashic bootstrap-organizations` 2026-09-18 實跑：無可自動建立的候選，另有 1 個產不出 key 的機構名待人工指定）。所以本列與第 8 列同型（零的來源在別處），並繼承它的釘零義務——上面那支測試就是。

**出聲的面要點名、邊界要說**（R2 寫「doctor／App 各一格」，R2 verify 第 6 列）：`akashic validate` 的逐則 warning＋家族計數行、MCP `akashic_doctor` payload 的 `unmergeableDivergences` 計數與 `recordIssues` 裡的逐則（同第 13 列的寫法，R3 verify 第 23 列）、App 側欄——CLI `akashic doctor` **不印** per-record 家族（既有慣例：`validate` 印計數行的家族本次從五個變六個，這是第六個），而 warning 級的 `validate` 對它 exit 仍為 0：與第 13 列同一條誠實邊界，它做到「掃得到」、做不到「叫醒」；前者仍是散文腳本，bootstrap 的扣留是它在寫入端的閘。這也是 `no-compat-fallback` 第 2 條要量的「還有誰在走這條路」（R1 verify DA 第 22 列），但「拿掉」不路由到那條規則——理由在前言。

**若實作，`DivergenceResolve.swift` 裡帶 `org-merge-slot` 標記的每一格要同批補**（數量以 `grep -c 'org-merge-slot' Sources/AkashicStoreIO/DivergenceResolve.swift` 量、不寫死——#558 R1 verify 第 9 列說「三格不是兩格」，R2 同一個 commit 又新增兩格而三處散文仍寫三，R2 verify 第 8／15 列；#555 R2 把手寫的 `mergeableShapes` 也標進去（R1 verify 第 10 列：它與 switch 分岔不會報錯，而訊息的誠實靠它），兩個會 throw `unsupportedShape` 的入口刻意不標——它們是 loud 的，實作時不可能不碰；#558 對 venue 漏掉的是 `doomedRelativePaths` 那格：只補部分會做出一個看起來完整、對 org holder 永遠回空的閘）

**從留下的句子裡搬出的括注**

- 情形欄「0 筆——沒有重複可合、也沒有人記過」之後：（2026-09-18 R2 重跑相同）
- 理由欄「掉；本列的對象是一條程式的半吊子管線」之後：（第 4 類，前言 2026-09-18 顯式擴入——R1 寫「前二十三列的裁決都是寫或不寫」，對第 22 列的「保留」為假，R1 verify 第 2／21 列）
- 理由欄「ape 的訊息從一份與分支對帳的清單」之後：（`mergeableShapes`——`testUnsupportedShapeMessageNamesTheRealDomain` 釘的是「venue 在清單裡」與「org 仍擲 `unsupportedShape`」，**不是**「org 不在清單裡」：把 org 加進清單而不動 switch 它五條斷言照綠；後者自 R2 起由 `UnmergeableDivergenceScanTests.testOrganizationCandidateIsReported` 釘住，R2 寫「parity 測試釘 venue-in／org-out」，R2 verify 第 13／16 列）
- 理由欄「會撞牆（本列）、合併面先開則沒有輸入」之後：（R1 寫成「關掉它等於斷言 org 永遠不會有歧異」，那是稻草人——R1 verify 第 14 列）

### 第 25 列（#554）

**情形欄的其餘部分**

2026-09-12 實測 live store：venue **485** 筆，四條不變式的違反字串 **0**、names 近重複對 **0**；而 R2–R5 四輪 verify 用真 binary 寫進了 `\r`／`\n`／LS／`—`／`×`／RLO／ZWSP／ALM／TAG 字元／尾隨空白／NFD 位元組／拉丁字母夾 ZWNJ／VS16／CGJ／Hangul filler——每一個都是實例，只是發生在 scratch store 而不是 live store。重跑腳本見量測文件

**理由欄的其餘部分**

R2→R4 三輪把閘裝在 `updateVenue` 的三個迴圈裡，每一輪都修在看見的那一圈，R4 verify 指出同一欄位還有 `addVenue`（連空字串都收）與 `VenueBootstrap`（只 trim）——`Venue.swift` 自己的 dated-variant 守衛 doc 早就寫著「守衛住在 validate → writeVenue 的交會處才擋得住所有路徑」。

**這與第 8／13 列的前提要對帳**（R5 verify 第 12 列）：那兩列說「per-record 的 error 級檢查全是 key 檢查、對載入後的記錄不可達」——**對 venue／organization 自 #227（authorized ⊆ names）／#422（帶時間 variant）／#473（孤兒 variant）起就已為假**：venue 的內容檢查全在寫入期、decode 不驗，所以載入後可達、`StoreHealth.perRecordIssues` 收得到；第 8 列的 pin test 只對 entry／person／divergence 改壞 key，證的是「key 錯會 quarantine」，不是那句前提。本列不翻第 8 列的裁決（`errorsFirst` 的排序仍是對的），只把那句前提的失效日期寫出來——它在本列之前就失效了，本列把可達的 error 類別從三個擴到七個。**誠實邊界**：不變式的 NFC 對 CJK 相容表意文字有損（U+FA10 塚 → U+585A）——位元組層有損、Swift 層無損（Swift `==` 早已視為相等）；ZWJ／ZWNJ 保留但只在 `NameIdentity.joinerIsLegal` 的兩個脈絡；DI 一律拒等於拒掉 IVS／蒙古文 FVS／希伯來 CGJ 等真實正字法用字——fail-closed、零實例、Claude 代裁 D9 的取捨，寫在 §5.7 誠實邊界（R6 verify 第 5／23 列）；私用區（Co）不擋，因為 doc 從未宣稱它；`canonical` 只丟 `White_Space` scalar、不刪任何其他 scalar（R6——R5 在 Character 上切，「空白＋combining mark」整個 cluster 被刪）。

**從留下的句子裡搬出的括注**

- 情形欄「norable_Code_Point」之後：（R6；R5 用 generalCategory 四類，VS16／CGJ 是 Mn、Hangul filler 是 Lo，全放行）
- 情形欄「一 Indic 文字的 virama」之後：（R6；R5 的「兩側是字母」對拉丁字母 fail-open；R7 再收區塊裡的標點與連續 joiner——R6 verify 第 1／19 列；R8 再收基底要是字母、兩側同文字、右側不收標記——R7 verify 第 1／26／33 列；R9 再收 virama 與標記要與基底同文字、放行詞尾 chillu 後的空白與 Bengali ya-phalaa 的 `<RA, ZWJ, VIRAMA, YA>`——R8 verify 第 6／10／11 列，D21／D22；R10 再收 virama 之前的 joiner 只在 Devanagari／Bengali 且 virama 之後要接同文字的字母——R9 對十個 Indic 文字一起放行且不看右脈絡，`क\u{200D}\u{094D}` 與 `क्` 渲染相同而各自進得了 names，R9 verify DA 第 10 列，D26）
- 情形欄「26），U+2800 顯式列入不可見」之後：（第 20 列）
- 理由欄「觸發條件可檢查」之後：（指令見量測文件）
- 理由欄「repair-venue-names」之後：（使用者 2026-09-28 裁決：乾跑逐筆列出「venue／清單[index]：before → after」、`--apply` 才寫、要求那些 venue 檔已 commit、任一筆過不了寫入閘整批零寫入；正規化後仍不合法、改完造出近重複或記錄還有其他 error、有 reference 指著舊拼法的，它只具名與理由、一筆都不動——那些仍是人改 YAML。它是名字的第六個寫入者，同樣經 `writeVenue`，本列的守衛因此不必另裝閘——「寫在 store 邊界」的裁決在這裡兌現一次）

### 第 26 列（#554）

**情形欄的其餘部分**

2026-09-14 實測 live store：2,411 筆 work、同 venue 兩條 key 邊 **0**。重跑腳本見量測文件

**理由欄的其餘部分**

與第 23 列（可達性是本 change 造出來的）成鏡像：那一列是新面讓不可達變可達、守衛與面同批；這一列是新閘讓可達變**不可達**（對工具面），守衛守的是關掉之前寫進去的與繞過工具寫進去的。R15 起有家族前綴（`Entry.duplicateVenueEdgePrefix`）、`StoreHealth.duplicateVenueEdges` 計數（doctor／App 各一格）、每筆 work 最多列 20 個 venue（第 27 列同一批，R14 verify regression 第 22 列、security 第 18 列）。

**從留下的句子裡搬出的括注**

- 理由欄「ary）——venue 合併不是入口」之後：（`resolveVenueDivergence` 對改指倖存者的 key 邊去重；R11 verify DA 第 14 列真 binary 造出的是另一個形：合併後一條 literal 邊指向 work 已 key 的 venue，它不造出重複的 key 邊，由 D33 的逐筆略過處理、提名照常；反方向倒是真的——它對 entry 的 key 邊去重時會把與被併鍵無關的既有重複 key 邊一併收成一條，是 #572 落地前唯一的移除面，R12 verify logic 第 38 列）
- 理由欄「自己所有的寫入，而處置面當時還不存在」之後：（#572；2026-09-28 起有 `resolve-venues --drop-venue`，severity 不因此重開——warning 的理由是「記錄合法可載入」，與處置面在不在無關）
- 理由欄「觸發條件可檢查」之後：（指令見量測文件）
- 理由欄「ues --drop-venue 刪」之後：（#572，2026-09-28 落地；之前只能手改 YAML）

### 第 27 列（#554）

**情形欄的其餘部分**

而真正造出第二半的路徑（work 合併把兩筆 work 的邊連同 verdict 併到一筆——R13 verify DA 第 3 列純工具面重現：`--apply` 兩個刊名變體 ＋ `resolve-divergence`）結構上**不會**點亮第一半的燈：被併 work 連同它的邊一起刪掉，倖存者只剩一條邊，validate 零診斷、`--demote` 撞 D23。2026-09-15 實測 live store：venue **485** 筆、對同一 work 持 ≥2 個正規化後不同 confirmed literal 的 **0** 筆。重跑腳本見量測文件

**理由欄的其餘部分**

**生產端自 R15 起三個面都 fail-closed**（D38；R14 verify Codex 第 1 列 HIGH：D34 只裝在合併路徑，apply／repoint 對「目的 venue 已對該 work 持有另一個 confirmed literal、沒有對應的邊」的形照寫）：`apply` 對它逐筆略過並具名（`skippedConflictingConfirmedLiteral`）、`repoint` 對預測後的 verdict 集合驗、整批拒絕零寫入。**R16（R15 verify 30 列，6 席齊）**：「位元組」要真的是位元組——R15 的去重寫 Swift `==`（canonical equivalence），NFC／NFD 的兩筆被收攏成一筆、兩類 warning 都不出而 D23 照拒（requirements 第 1 列 HIGH；D42 改 `Set<[UInt8]>`，與 `confirmedLiteral` 同一把、O(N)）；混合情形（三筆裡兩筆只差位元組）第一類訊息點名那一組（第 23 列）；概括句不進家族（DA 第 29 列：帶家族前綴時 `StoreHealth` 把它算成一則，25 筆 work 報 21——改用 `Entry.perRecordCapSummaryPrefix`）；生產端的閘也比位元組、同一 literal 的另一個拼法也略過／拒（D43，Codex 第 3 列 HIGH：放行同鍵異拼法之後 demote 還回舊拼法）、apply 的閘移到重複邊檢查之後（D44，regression 第 2 列 HIGH）。**R17（R16 verify：31 findings 合併成 24 列，6 席齊；列號＝報告的合併列號）**：合併是第三個會動到同一批 verdict 的面——收攏的勝者政策在拼法位元組不同時改由倖存配對自己的那筆勝、收攏列印兩個拼法（D47，第 1 列 HIGH；#468 的弱血統優先只在同拼法時適用）；近重複組上限只數真的出聲的組（D48，第 2 列 HIGH：21 組合法沿革曾被判 error、所有寫入面關門）；D43 訊息兩桶同時說（D50，第 7 列）；混合註記截在 5 組時揭露（第 10 列）；第 27 列量測段的 grep 註記改成它量的單位（第 9 列）。**R18（R17 verify：31 findings 合併成 20 列，6 席齊）**：收攏的勝者先看**活著的邊**（D51，第 1 列 HIGH：keeper 對某 work 的 confirmed 可能沒有邊，被併記錄的那筆才是那條邊記錄的字；三條收攏路徑同一個政策，rename 只收攏動到的鍵——D53，第 3 列）；近重複的概括句分「真違反」與「同名段過多」兩類、authorized／variant 也先分組、整筆記錄另有 100,000 對求值總量上限（D52，第 7／8 列）；家族計數是下限、`cappedRecords` 自成一族（D54，第 5 列）；第 25 列的量測 grep 補兩類求值上限句並排除概括句（第 11 列）。**R19（R18 verify：5 席 session limit、Codex 席 3 列，不完整）**：rename 的收攏以鍵整組算（D55，第 1 列 HIGH：R18 的單一槽位記帳讓三方碰撞由 YAML 順序決定）；`cappedRecords` 以記錄計（D56，第 2 列）、App 側欄渲染它且家族值標成下限（D57，第 3 列）。**R20（R19 verify：34 列，5 席齊、Codex 席 HTTP 429）**：早已指向新鍵的死 verdict 不論 field 一律丟（D58，第 1 列 HIGH：D55 的分組含 field，異 field 的死 rejected 逃過、rename 後與遷來的 confirmed 成 #486 矛盾對；merge 對同一形狀早已整批拒）；`total`／`errors` 也是下限（D59，第 7 列）；**本列的「應恆為 0」只涵蓋 venue×work**——其餘六格（person／organization 持 work、三種 holder 持 person）沒有掃描面，rename 也不替它們判定（第 4 列，寫進 §3.5）。**R21（R20 verify：26 列，5 席齊）**：D58 的丟棄退場——rename 對目的鍵上已有 verdict 的 holder 具名拒絕、零寫入（D60，第 1–5 列 HIGH：D58 只在 holder 另有被改寫 verdict 時生效，且生效時是無乾跑、無逆操作的判定刪除，與本表第 13 列「死 verdict 的處置是人的重新消歧」相牴觸）；rename 自此沒有任何會刪判定**內容**的路徑（R22 D62 之後才為真：R21 仍以拼法位元組折疊、會丟 judgement 不同的那筆——R21 verify DA 第 14 列；D61 把 quarantined 檔納入 D60 的母體——**R23 D63** 改成位元組比對，R22 的行級 needle 含空白、被 YAML 折行擊穿）。**R22（R21 verify：37 列，6 席齊）**：D62 留下的同鍵異 judgement 沒有掃描面（第 14 列）→ 第 28 列。

**從留下的句子裡搬出的括注**

- 理由欄「鍵不是一把是兩把，掃描兩類都掃」之後：（R15，Claude 代裁 D39；R14 verify Codex 第 3 列、requirements 第 5 列：R14 寫「鍵與 D23／`verdictEqualityKey`／#486 同一把（`matchingKey`）」——假的，D23 的拒絕（`confirmedLiteral`）比**位元組**，只差大小寫或 NFC 形的兩筆 confirmed 讓 demote／repoint 必拒而 R14 的掃描零診斷）
- 理由欄「ralAmbiguities 有計數」之後：（doctor／App 各一格——R14 verify regression 第 22 列：兩族 per-record warning 沒有家族，MCP 截 20 則、App 預覽 5 則時可能完全看不到）
- 理由欄「觸發條件可檢查」之後：（指令見量測文件）

### 第 28 列（#554）

**情形欄的其餘部分**

工具面的寫入以那把鍵去重、寫不出它（`appendIfAbsent`）；rename 自 R22 D62 起**刻意保留**它——只折整筆**位元組**相等的重複（R24 D65：R23 的鍵是合成 `Hashable`、canonical 相等，NFC／NFD 曾被折掉；訊息的「全部完全相同」自 R24 起也以 `byteExactKey` 判），R21 之前會當場折掉並回報；`contradictoryVerdicts` 只比 confirmed×rejected、第 27 列的第二類以位元組相異分組，都認不得它；而下一次 person／venue 合併會以 #468 的血統層收成一筆。第 27 列第二類已報的那一格（venue×work 的 confirmed、只差位元組）**不重報**——同一件事出兩則是雜訊；**只在每筆各有自己拼法、且 judgement／rests-on 全同時**（R25 D67／R26 D71；R24 verify 第 8／10／18 列：第 27 列以位元組去重、看不到「同一拼法出現兩次」，R24 的排除把 `Alpha`／`Alpha`／`ALPHA` 這種混合組整組吞掉；R25 verify 第 1／3／5／10／12／18 列 HIGH：R25 的排除不看 kind，`Alpha`／`ALPHA` 各帶相反 judgement 時三個面只說「只差位元組…留一筆」——一個真的證據衝突被一句銷毀判定的指令取代），家族計數不含被排除那一格（accessor doc、doctor 描述、App help 寫明）；訊息自 R25 分三向（拼法只差位元組／judgement 或 rests-on 不同／全同，R24 verify 第 3／11／16 列）；本族報的是它認不得的：位元組相同的重複、rejected 的重複、person 配對的重複、person／organization 持有的重複。每筆記錄至多 `Entry.perRecordWarningCap` 則、其餘一句概括（首版無上限，一個 20 筆 work × 6 對的 venue 出 120 則、把 doctor 的 `count` 從 20 推到 140，全套測試抓到）。**這個上限三個面共有**（R24 D66；R23 verify Codex 第 2 列）：它在產生訊息時就生效，CLI `validate` 只是不加面級的 20 則截斷——被截的記錄在 CLI 也只有概括句，`ValidatePerRecordCapCLITests` 釘住。**上限在渲染之前套**（R26；R25 verify Codex 第 4 列：R25 先把全部組渲染完再 `prefix(cap)`）。**有上限的是組合式的六族**（R26 D72；R25 verify DA 第 2 列 HIGH：R25 寫「五族」、漏掉 person 近重複——它當時無上限，200 個共用 matchingKey 的名字真 binary 吐 19,900 則、7.6 MB、`cappedRecords` 0；R25 還說其餘家族「每筆至多一則、撐不爆」，對六族全假——它們是每筆 reference／配對／記錄各一則、與資料項數線性）：venue 名字內容、venue 近重複、person 近重複（#576 在本輪落地：先以 matchingKey 分組、一組一則、每筆記錄 20 組、組內 5,000 對、**整筆 100,000 對**——R27 D76 的第五層，warning 級只計數；R28 起小組先評估、預算不鎖存，R27 verify DA 第 22 列：插入序讓巨型同鍵組把其後的真違反整批餓死）、重複 venue 邊、confirmed literal、重複判定記錄；venue 的求值上限命中自 R26 起也留 `perRecordCapSummaryPrefix` 概括句（第 23／31 列：曾漏計 `cappedRecords`）。

**理由欄的其餘部分**

訊息把三個來源（手改、舊 binary、rename 帶過來）與下游（合併收攏）都說出來——第 27 列第二類的訊息曾只怪手改與舊 binary，而 rename 就會帶過去（R22 verify 第 25 列，同輪補上）。

**change `resolution-verdict-states` 補記（2026-09-25，#619／#636）**：分組鍵從 `verdictEqualityKey` 換成**記錄鍵** `verdictRecordKey`——同一配對的 nominated 與 judged 是兩筆記錄不是重複（#636 並存），未決記錄只有整筆位元組相同才算重複（同一配對的多次查證是設計上要保留的）；訊息裡「工具面的寫入以…去重」同步改寫

**從留下的句子裡搬出的括注**

- 理由欄「觸發條件可檢查」之後：（指令見量測文件）

### 第 29 列（#554）

**情形欄的其餘部分**

2026-09-18 實測 Sources（HEAD `58bab46d`，R33 重量）：`displaySafeError(max:)` 57 站點、`displaySafeClipOnly(max:)` **39** 站點、sink 宣告的預設值 3 個（`displaySafeMultiline`／`displaySafeAssembled`／`displaySafeErrorMultiline` 的 400）、呼叫端字面的 `maxLineLength:` **0** 個，最大 4,096，**超過 ceiling 的 0**。**R32 寫的是 18／3，而它自己附的腳本第一次重跑就給出 39／5**（R32 verify 第 3／10／15 列，三席獨立重跑）：R32 的第三族（`maxLineLength` 與 `max` 兩個 `Int =` 預設值一起掃）把 `displaySafe`／`displaySafeInvisible` 的**生產者輸入預算** 200 也掃進來——它們不是 sink、與 ceiling 的前提無關，卻撐著那一族的地板（刪掉三個真的 sink 預設值裡的兩個仍綠）；clipOnly 的地板 15 是照量錯的 18 打的折，允許 62% 的站點靜默消失。R31 的第一版只掃 `displaySafeError(max:)` 與字面 `maxLineLength:`——後者全樹零命中、多行家族的上限是宣告的預設值 400、`displaySafeClipOnly` 完全沒掃，於是把預設值改成 8,192 守衛照綠（R31 verify 第 6／16／30 列）；R32 分三族各自有地板；R33 把生產者拿出族、分四族、地板照實測訂（50／35／3／0——第四族零實例、地板 0 明寫「可為空，不撐任何地板」）。重跑腳本見量測文件

**理由欄的其餘部分**

**而族要照它守的東西分，地板要照實測訂**（R33）：R32 分了族卻把兩個不是 sink 的生產者預設值混進第三族，又把一個量錯的數當地板——這一列自己在同一天就示範了「寫死的計數會與目錄分岔」，且分岔發生在它宣稱可重跑的腳本上。

**從留下的句子裡搬出的括注**

- 理由欄「觸發條件可檢查」之後：（腳本見量測文件）

### 第 30 列（#619）

**情形欄的其餘部分**

2026-09-25 實測 live store 8,747 筆 reference：最長的判定理由 687 位元組、rests-on 最多 3 個；`resolution-undecided` 0 筆——format 19 尚未部署。重跑腳本見量測文件

**理由欄的其餘部分**

**#645 落地、原本寫下的第二個觸發條件成立（2026-09-26）：重開後裁決不變**——三個上限仍只擋單次呼叫，累積改由第 31 列出聲（量記錄檔的位元組）；上限的量測錨點沒有變

**從留下的句子裡搬出的括注**

- 理由欄「age 的量級，這一格是推估不是量測」之後：（R2 verify DA 第 16 列）
- 理由欄「觸發條件可檢查」之後：（腳本見量測文件）

### 第 31 列（#645）

**情形欄的其餘部分**

2026-09-26 實測 live store：person 4,575 筆、最大檔 10,869 bytes（`chen-chien-hsiun`）；organization 13 筆、最大檔 717 bytes；門檻 4,194,304——0 實例。重跑腳本見量測文件

**理由欄的其餘部分**

**量的是檔案位元組**：初版照第 16 列用節點換算的筆數，R1 verify 指出未決記錄會先撞上位元組上限而加了「內容位元組」軸，R2 verify DA 再指出節點軸對 store 檔根本不生效——兩次修的都是估計，真正的預算是讀取路徑的 `maxBytes`，檔案大小已含 YAML 跳脫與 verdict 以外的內容，直接量它（第 16 列同日更正）。

**前綴分開**（`holderVerdictBudgetPrefix`）：兩族計數分開，而處置的第一步相同（先查重複記未決）。**誠實邊界**：warning 只在讀取面計算，~~寫入路徑有 2 倍寬限——一次夠大的寫入（judge／refute 的理由沒有長度上限）可以從門檻之下直接跳過讀取上限，warning 來不及出聲；那是寫入閘的缺口，記 #648。~~ → **#648（2026-09-28）更正並關閉**：前半的前提量錯了——encode 的語意 canary 一直以讀取上限（1 倍）擋著，超過 8 MiB 的寫入從未落盤，只是拒絕不具名、而多檔寫入面在它觸發之前已有檔落盤（撕裂）。現在寫入的位元組上限是讀取上限、具名拒絕，2 倍只給不增長的改寫，多檔面在任何檔落盤之前逐筆 preflight，judge／refute 的理由上限 4,096 位元組——見第 39 列。

**從留下的句子裡搬出的括注**

- 理由欄「觸發條件可檢查」之後：（指令見量測文件）

### 第 32 列（#589）

**情形欄的其餘部分**

#556 R4 verify security 席實測。2026-09-26 實測 live store 141 個 issn／orcid／isbn 值（issn 59、orcid 42、isbn 40；YAML 解析。先前寫過 1,739（行級 regex）與 282（本列腳本把每個值掃了兩次，R1 verify 四席同指）——兩個都不要用），另有 DOI 註冊者段同形（R1 verify：`isNumber` 認全形；live store 2,445 個 DOI），非 ASCII **0** 筆；新 binary `validate` rc=0、無新隔離。重跑腳本見量測文件

**理由欄的其餘部分**

判斷在 `uppercased()` 之前做（合字 `ﬀ` 轉大寫後是 ASCII 的 `FF`）。

PMID 以 `UInt64(s)` 解析、ROR 以 `Int(…)` 加 ASCII 字母表，都只收 ASCII，不在此列；DOI 的**註冊者段**同形（`isNumber`）、R1 起一併只收 ASCII，後綴本來就可以含 Unicode、不動。

**從留下的句子裡搬出的括注**

- 理由欄「觸發條件可檢查」之後：（腳本見量測文件）

### 第 33 列（#579）

**理由欄的其餘部分**

工具面不寫得出它（`attribute-org` 先驗 org 存在），實例只可能來自手寫、刪除或改名。

### 第 34 列（#660）

**情形欄的其餘部分**

#656 R1 verify DA 以 scratch store 實測 `akashic validate` rc=0、零 warning；#656 讓隸屬那一半在匯出表裡以 `affiliation_kind = 'organization' AND organization_id IS NULL` 分得出來，但要自己寫 SQL 才看得到；上級機構那一半在任何面都看不到——`organization.parent_id` 只看現任上級，懸空、字面、沒有上級三者都是 NULL（R1 verify DA）。2026-09-27 實測 live store：organization 13 筆、person 4,575 筆，懸空的隸屬 key **0**、懸空的上級機構 key **0**。重跑腳本見量測文件

**理由欄的其餘部分**

第 33 列照 work 的欄位窮舉，第 7、8 條住在別的形狀上而沒被看到（R1 verify 指出本列初稿寫「三條」，在自己講的那條軸上數錯）（`entity-backlink-completeness` 記過相鄰的形狀：補了形狀、沒窮舉它的欄位——這次是窮舉了一個形狀的欄位、沒窮舉指向同一個目標的其他形狀）。

上級機構的環已有檢查（#179），懸空的上級在那條檢查裡只是「不成環」、不出聲——本列補的是它沒問的那一半。實例只可能來自手寫、刪除 organization 檔、或手改 org key（`resolve-organizations` 升格前先驗 org 存在）。

### 第 35 列（#582）

**情形欄的其餘部分**

#554 R25／R26 把 `paginated` 冪等閘、`UpdatePerson` 的 append-only、`AddOnlyEnrichment.applied` 的去重換成位元組相等（D69／D73），於是只差位元組的變體寫得進來；而第 28 列那一族第一行就只看 verdict 欄位。2026-09-27 實測 live store：非判定 reference 90 筆、重複組 **0**；新 binary 的 `validate` 對 live store 這一族 0 則。重跑腳本見量測文件

**理由欄的其餘部分**

初稿寫「位元組完全相同的工具面寫不出」，R1 verify DA 以真 binary 否掉：`dropAuthors`／`splitAuthors` 對 work 的 references 直接 append，同一個移除做兩次就留下兩筆逐位元組相同的記錄。**計數的單位是組**，一筆記錄可以有好幾組。**誠實邊界**：只看 canonical 相等——只差 Cf 字元（ZWSP 之類）或只差 rests-on 順序的兩筆不報，它們在 D69／D73 之前也不被 `==` 去重，不是那次替換打開的格。

**#564 b34 補記（b33 X1 第 5／12 列）**：名字分類記錄（#564）另算——它們是有順序的歷史，「指定 R → 撤回 S → 指定 R」的兩筆「指定 R」是兩次轉移、寫入面只比最後一筆、store-format §3.5 定為合法；先前它們與一般 reference 一起以集合分組，這段合法歷史被報成「同一個動作做了兩次」、處置「留一筆」照做會讓最後一筆與分類矛盾（第 85 列要擋的狀態）。現在只報同一個名字同一個分割裡**相鄰**而彼此相等的（`classificationRuns`，處置：刪掉相鄰多餘的那一筆不改變最後一筆，手改 YAML）。2026-10-05 唯讀量測：名字分類記錄 0 筆，相鄰重複 0 組

### 第 36 列（#588）

**情形欄的其餘部分**

同輪補上移除面（`update-venue --remove-issn`／MCP `remove_issn`）：在此之前掛錯的號只能手改 YAML。2026-09-27 實測 live store：venue 485 筆、ISSN 值 59 個、distinct 59、掛在 ≥2 個 venue 的 **0**。重跑腳本見量測文件

**理由欄的其餘部分**

與第 32 列（前件寫寬會放行假號）不同：那一列的號本身不合法、改謂詞就擋得住；這一列的號合法，錯的是它掛在哪裡，只有跨記錄比對看得到。

移除的理由只進報告（使用者 2026-09-27 裁決；git 保存的是移除前的檔，理由要留在 git 得由操作者寫進 commit message），移除前要求那筆 venue 檔已 commit（`assertRecordsRecoverable`，#573 的閘一般化）。

**從留下的句子裡搬出的括注**

- 理由欄「觸發條件可檢查」之後：（腳本見量測文件）

### 第 37 列（#658）

**情形欄的其餘部分**

同一形狀先前的實例：#580 R1 的 `authorize-names`（宣告寫成 `: Bool` 而漏網，也一直沒有閘）、#650 的 `rename`（沒有閘）與 `rename-person`（呼叫閘卻不在手寫清單），以及本輪才發現的手寫清單裡的 `migrate-venue-variants`（列為過閘卻從未呼叫閘——它的 `--apply` 自 #554 R15 起一律拒絕）。2026-09-28 實測（與 #575 同批整合後；`repair-venue-names` 是第 57 格）：CLI 葉命令 57 個、裁決 57 格、兩個差集皆空（過閘 16、逐腿 3、不閘 18、不寫 20；同日 #586 R1 verify 把 `dismiss-divergence` 改為過閘後是 17／3／17／20）；三個逐腿命令的旗標 14／7／7 條、差集皆空。重跑指令見量測文件

**理由欄的其餘部分**

**過閘的集合改由表現算**：先前手寫的 `destructiveCommands` 與測試裡的第二份清單已經分岔（測試那份漏了 `migrate-identifiers`／`enrich`／`enrich-from-zotero`，「成員真的呼叫閘」對那三個從沒驗過），`--yes` 的說明也改由同一張表產生。**誠實邊界**：逐腿只做三個命令——`update-venue`、`update-person`、`library` 以命令為單位裁決，它們新長一個寫入旗標時看不到；裁決為不寫 store 的命令，測試只驗它不呼叫閘、不驗磁碟。

**從留下的句子裡搬出的括注**

- 情形欄「與逐 id 的寫入腿長出來時它不會紅」之後：（#653 R1 verify requirements 席）
- 理由欄「觸發條件可檢查」之後：（指令見量測文件）

### 第 38 列（#581）

**情形欄的其餘部分**

**跨 kind 同 key 不是零實例**：2026-09-28 實測 organization 與 venue 共用 2 個 key（`american-psychological-association`、`american-educational-research-association`），那是 kind 必填的理由、不是本列。**同 kind 的重複只有一部分有既有檢查**：`crossRecordIssues` 報 citekey 與 person key 的重複，venue 與 organization 的重複 key 沒有任何檢查會報（兩筆照常載入）。2026-09-28 實測 live store：person 4,575、work 2,563、venue 485、organization 13、divergence 1 筆，同 kind 重複 key **0**。重跑腳本見量測文件

**理由欄的其餘部分**

**訊息列出各筆的檔名 UUID**，因為重複的 key 本身指不到任何一個檔（`entities/` 以 UUID 命名）。**誠實邊界**：venue 與 organization 的重複 key 沒有跨記錄檢查，所以在這兩個 kind 上本列的拒絕是那個重複**唯一**會出聲的地方，而且只在有人剛好指名那個 key 時出聲；訊息照實說「目前沒有跨記錄檢查報」、不假稱 validate 會列出（#581 首版就這樣假稱過，同輪改掉）。補上那兩個 kind 的跨記錄檢查不在 #581 的範圍，記在 #669（2026-09-28 開立：讀取端還有七處以 `uniqueKeysWithValues` 建查找表，重複 key 會讓 `export-bib` 等直接崩潰）。成本是一個計數比較。

**從留下的句子裡搬出的括注**

- 理由欄「觸發條件可檢查」之後：（腳本見量測文件）

### 第 39 列（#648）

**情形欄的其餘部分**

**issue 的前提有一半不成立**（2026-09-28 讀碼並以測試確認）：「寫得進去、讀不回來」在 encode 層不會發生——語意 canary（`decode(out)`）一直以 1 倍擋著，只是拒絕不具名（`fileTooLarge`，訊息說「單一超大節點」），2 倍的外層檢查對位元組從未生效；成立的是另一半：多檔寫入面在那道拒絕觸發之前已有檔落盤（judge 先寫 entry、person 被拒——作者位歸戶而 verdict 沒寫）。2026-09-28 實測 live store：5 族 7,637 筆記錄，最大檔 268,627 bytes（venue `psychological-methods`）、超過 8,388,608 的 **0**；判定記錄最長理由 687 位元組。重跑腳本見量測文件

**理由欄的其餘部分**

**不另立控制字元規則**（使用者 2026-09-28）：4 倍跳脫是 YAML 的合法表示，由 1 倍寫入閘擋下。**寬限只作用於已經讀不回來的檔**：目的檔 ≤ 讀取上限時，不增長的改寫本來就在上限之內；目的檔超過時它在載入時已被 quarantine，entities 佈局的 #631 拒絕覆寫它，寬限只在 legacy 佈局落地——它從不把一個讀得回來的檔變成讀不回來。**誠實邊界**：(1) preflight 以每筆記錄 encode 兩次換零寫入；(2) 有逐筆收容語意的面（resolve-people 的 apply／reject、resolve-venues 的 reject）不 preflight——它們既有的契約是逐筆回報寫入失敗，拒絕現在具名，但仍可能部分落地；(3) 不經 encode 的文字層遷移（`IdentifierMigration` 的形狀升級）不受本閘管；(4) rename 與合併的 preflight dry-encode 不傳目的檔大小，比實際寫入嚴（fail-closed）——對 legacy 佈局裡已讀不回來的檔不給寬限。**C2b verify（2026-09-29）補上三個漏掉的多檔寫入者**：`import-wos`（先前逐列寫、無收容，第 N 列被拒時前 N−1 列已落盤、報告隨 throw 丟掉）、`authorize-names`（只擋了 #641 那一類）、`repair-venue-names`（手寫了前置的子集、少 #631 目的檔檢查）——三者都改成先對整個寫入集合 `preflightWrite`。先前這張表的誠實邊界沒有列它們，是漏看不是裁決。

**從留下的句子裡搬出的括注**

- 理由欄「觸發條件可檢查」之後：（腳本見量測文件）

### 第 40 列（#641）

**情形欄的其餘部分**

#631 R2 verify 以真 binary 重現 judge、refute、org apply、repoint／demote、migrate-identifiers 的撕裂，最後一處讓 ISSN 從 work 移除卻沒寫進 venue、重跑也救不回。2026-09-28 實測 live store：legacy 殘留 `entries/` **0** 個檔、`people/` **0** 個檔——load 不判斷任何記錄。重跑腳本見量測文件

**理由欄的其餘部分**

寫入當下的檢查留著當最後一道防線：load 到寫入之間檔案處境可以變（有人在中間 commit 或刪檔），那一段的撕裂本列擋不住。**person 側只收兩類**（key 重複、檔案處境）：作品側的「共用 id」不收——people 表以 key 為主鍵，entities 佈局下共用 id 必然有一筆是 legacy（它已經落在檔案處境那一類），收進來只會多擋住住在 `entities/` 那一筆寫得進去的記錄（`unlocatablePersonKeys` 的 doc 逐條寫著）。**兩筆都還是 legacy、共用同一個 id 時**（C2b verify，Codex HIGH）：目的檔此刻不存在，逐筆的 #631 檢查各自通過，第一筆搬進 `entities/<id>.yaml` 之後第二筆才撞上——load 另外跨記錄比 legacy 那一段的 id，把兩筆都標出來（仍是第 2 類「檔案處境」，不新增類別；作品側本來就有「共用 id」那一類）。

**成本**：只有 `entries/` 或 `people/` 裡真的有 YAML 時才判斷，git 對整批搬移候選只跑一次——live store 零成本。**誠實邊界**（沒接的寫入者，逐一點名）：`import-zotero` 與 `migrate-provenance` 是逐筆收容（每筆一個檔、寫入當下的拒絕逐筆回報，不撕裂），沒有接；`fmt`／`migrate-person-identity` 直接寫檔、不經 #631；`decodeCaptured` 的唯讀快照不標註（它的契約是不重讀磁碟，也沒有寫入者）。

**從留下的句子裡搬出的括注**

- 理由欄「觸發條件可檢查」之後：（腳本見量測文件）

### 第 41 列（#654）

**情形欄的其餘部分**

#546 在 `store-source` 擋下了 0 byte 的內容，但引用端照收這個 digest——`enrich` 的 `sourceDigest`、`update-person` 的 references、`update-venue --paginated` 與各 undecided 腿的 rests-on、`record-divergence` 的依據、`akashic.sources`——所以一筆指向「空存檔」的 reference 仍寫得進去，只是 blob 不再會被存下來。2026-09-28 實測 live store：記錄 7,637 筆、`sha256:` 值 95 個、指向空內容 digest 的 **0** 個；另有 `sources/index.jsonl` 1 列指向空 blob、那個 blob 在場（#546 之前兩次失敗抓取留下的，沒有記錄引用它）。重跑腳本見量測文件

**理由欄的其餘部分**

fingerprint 是作者清單的 domain-separated 雜湊、不是內容位址，空內容的 digest 不可能是它的值，那件事由比對時的「不符」說出來。

**誠實邊界**：那個空 blob 與它的 index 列仍在，清掉它需要一個移除存檔的面（#544 同族）；timeline 的舊 `source:` 若裝著它，`migrate-provenance` 略過並說 0 byte、原資料不動。**部署視窗**（#654 R1 verify DA）：收緊的是載入謂詞而沒有自己的 format bump。升級之前的舊 binary（plugin wrapper 下載的 MCP server、App）仍收空內容 digest，而 #546 的失敗抓取正是會產生它的情境；它寫進共用 store 的記錄會被新 binary 整檔隔離。format 21（#642）的 marker 升上去之後舊 binary 整個拒開 store，這個視窗隨之關閉——所以三個 binary 都升完再升 marker。

**從留下的句子裡搬出的括注**

- 理由欄「收緊會把一個能用的 store 關掉」之後：（負控實測：index 文法改回 `isValidDigest`，`store-source` 拒寫）
- 理由欄「觸發條件可檢查」之後：（腳本見量測文件）

### 第 42 列（#669）

**情形欄的其餘部分**

`crossRecordIssues` 只查 citekey 與 person key；以 `Dictionary(uniqueKeysWithValues:)` 建 store key 查找表的地方遇到重複直接 trap——`export-bib`、`apa7Report`、CSL、Projection、attribute-org 的 org 表、migrate-identifiers 的 venue 表，連重複的 person key 在匯出端也一樣；其餘以 `uniquingKeysWith` 建表的地方安靜地留第一筆。同一輪查到同形的第二個來源：MCP／CLI 的 payload 以**消毒後**的字串為鍵，截斷不是單射——`enrich` 的 `provenanceOmitted`（#668 起收 `fields.<鍵>`）遇到兩個共用 80 字元前綴的欄位名，真 binary `Fatal error: Duplicate values for key`、rc=133。

**理由欄的其餘部分**

**讀取端留第一筆**：選哪一筆是列舉順序、不是判定，validate 的 error 說明了它（同 `fields` 的既有處置：消毒後的鍵先依原始鍵排序再留第一個）。

**其餘寫入面由 #670 補上**：resolve-venues／resolve-organizations 的 verdict 寫入與 update-venue 原本不看跨記錄 error、安靜地留第一筆；現在比照 #627／#641 的無法唯一定位——顯式點名的腿整批拒絕，逐筆略過的腿（apply 的 D33、judge、undecided）具名略過，列表以 `unlocatableVenueKey`／`unlocatableOrganizationKey` 旗標標出（`unlocatableVenueKeys`／`unlocatableOrganizationKeys`）。index 重建對重複的 venue／person key 留第一筆（在此之前 PRIMARY KEY 擲錯，寫入面在檔案落地後才重建，一次不相干的合法寫入會回報失敗）。守衛是 `DuplicateVenueOrgKeyTests.testNoStoreKeyLookupTableTrapsOnDuplicates`：掃 `Sources/`，`uniqueKeysWithValues` 的來源以 `$0.key`／`$0.citekey`／`displaySafe…` 為鍵即紅（由生成器發的 ref 不在前件裡）。

**從留下的句子裡搬出的括注**

- 理由欄「resolve-divergence」之後：（#669 R1 verify：訊息原本把合併列成並列的出路，而合併正被同一個 error 擋住）

### 第 43 列（#565）

**情形欄的其餘部分**

2026-09-29 唯讀量測 live store：venue 485、名字段 537，帶時間 0、帶 source 0、帶 note 0；含 venue 候選的 divergence 0。重跑腳本見量測文件

**理由欄的其餘部分**

「能不能並存」與 `validate()` 的近重複檢查共用 `Venue.sameNameSegmentsCanCoexist` 一份。**R1 verify（2026-09-29，四席同指）**：分類不取決於被併者順序（倖存者原本沒有的名字，任一被併者列在 variant 就標）；「完全相同的段」比 source／note 的 UTF-8 位元組（`String ==` 會靜默丟掉只差 NFC／NFD 的一份）；名字併入改成以 canonical 鍵建索引的線性計算（首版是二次方，被併者與倖存者各 6,000 個相異名字約 78 秒）；不能並存的清單至多列 20 組並給總數。**出路（#675）**：拒絕的出路原本只有手改 YAML；自 #675 起有編輯面（`update-venue --edit-name-segment`／MCP `edit_name_segment`：改同名段的時間、`source`、`note`，或刪掉一段），拒絕訊息指向它並保留「也可以手改 YAML」——合併仍不替人判定哪一段對，判定由那個面承擔。

### 第 45 列（#587）

**情形欄的其餘部分**

2026-09-29 唯讀量測：venue 485、ISSN 值 59、認不出的角色 0；venue 的 references 只有 resolution-confirmed 2,200 筆與 paginated 36 筆，`field: issn` 0 筆；最長 judgement 287 位元組、rests-on 最多 3 個。重跑腳本見量測文件

**理由欄的其餘部分**

**R1 verify（2026-09-29）**：通用面的 `field` 收窄成 `issn` 與 `names`——venue 的 reference 沒有移除面，`authorized` 的 reference 會鎖住 `authorize` 換對外形（只能手改 YAML 解開），`note` 沒有寫入面；同時關掉兩個耦合：合併把被併者 `field: issn`／`names` 的 reference 逐位元組搬到倖存者，同一個 ISSN 兩邊角色不同（或被併者有而倖存者沒有）具名拒絕

### 第 46 列（#610）

**情形欄的其餘部分**

2026-09-29 唯讀量測（R1 verify 重量）：work 2,568、Zotero 來源 535 個（附加來源 3 個），多筆宣稱 0、沒記 `library_id` 的主來源 0。重跑指令見量測文件

**理由欄的其餘部分**

宣稱者的定義只有 `ZoteroSourceClaims` 一份，匯入、驗證、App 共用——**含**沒記 `library_id` 的舊檔宣稱同一個裸 key 的 `?:<key>` 桶（R1 verify 之前這一半是假的：匯入端在行內另有一份 `legacies.count == 1`，載入時 doctor 看不到，CLI 提示指向一則不存在的警告）；同一筆 entry 被讀到兩次（#631 兩份並存）以 entry id 去重、只算一次。

### 第 47 列（#642）

**情形欄的其餘部分**

2026-09-24 `akashic-work-references` 把 56 筆被引文獻掛進種子所屬的 library，其中 52 筆不是 Psychological Methods 的作品卻進了它的全量目錄；當時沒有任何守衛，是隔天的 verify 才發現，已在 store `2f18107a` 移除。2026-09-29 讀 live store：library 4 個、全部未標性質，規則型／文件型成員不符 **0**、讀不到的檔 0。重跑腳本見量測文件

**理由欄的其餘部分**

**「format 21 之前的舊 binary」不再是獨立來源**（R1 verify 更正——整合時寫成三個來源之一）：寫入閘 `assertLibraryWritable` 擋的是 format < 21 的 store 寫規則型與文件型，舊 binary 沒有這道閘、也不讀 `membership`；但 marker 不到 21 時新 binary 寫不出規則型與文件型，舊 binary 又不認得它們，所以舊 binary 只有在**marker 被手改到 21 之後**才寫得進 ≥21 的 store 的規則型 library——那是「手改」的一種，不是另一個來源。

**從留下的句子裡搬出的括注**

- 理由欄「觸發條件可檢查」之後：（指令見量測文件）

### 第 48 列（#587）

**情形欄的其餘部分**

2026-09-29 唯讀量測 live store：venue 485、ISSN 值 59、帶角色 9（print 4／electronic 4／linking 1）、含 venue 候選的 divergence 0、同一個號掛 2+ venue 0、`field: issn`／`names` 的 reference 0（venue 其餘非 verdict reference 只有 paginated 36）、讀不到的檔 0。重跑腳本見量測文件

**理由欄的其餘部分**

**誠實邊界**：搬過去的 reference 在倖存者上沒有移除面（#673）；名字存在與否以 `String ==` 判，倖存者以髒寫法持有同名時，搬過去的 value 位元組可以與名字不同。

**從留下的句子裡搬出的括注**

- 理由欄「觸發條件可檢查」之後：（腳本見量測文件）

### 第 49 列（#609）

**情形欄的其餘部分**

2026-09-29 唯讀量測 live store：work 2,568、Zotero 來源 535（附加 3）、整筆 orphan 0、附加來源已刪除 0、只有附加來源的 entry 0、讀不到的檔 0。重跑腳本見量測文件

**理由欄的其餘部分**

判準只有一份（health、index、App 共用），各寫一份會分岔。

**誠實邊界**：index 的 `orphaned` 欄語意改了而沒有 schema bump，目前沒有讀者；「與 Zotero 脫鉤」延伸到新形狀而仍不帶理由與 git 閘，待使用者裁決。

### 第 50 列（#614）

**情形欄的其餘部分**

2026-09-29 唯讀量測 live store：`sources/` 的 blob 99 個，非普通檔 0、`index.jsonl` 是普通檔。重跑腳本見量測文件

### 第 51 列（#629）

**理由欄的其餘部分**

**負控**：`audit-guards-mutations` 的 `coverage④` 刪光 `plugin/rules/*.md`、期望「沒有任何 .md 規則檔」（#629 R1 加入；R2 verify 第 5 則指出本列先前仍寫「還沒有」）。

### 第 52 列（#629）

**情形欄的其餘部分**

2026-09-29 唯讀量測 live store：`entities/`／`entries/`／`people/` 的 `.yaml` 7,643 個，不可讀或非一般檔 0。重跑腳本見量測文件

**理由欄的其餘部分**

釘住它的測試是 `LiteralCensusTests.testUnreadableRecordRefusesToCountRatherThanUndercount`。**#629 R1 補記（同一條理由，兩處同形）**：`entities/`、`entries/`、`people/` 任一個存在但**列不出來**也是具名 exit 3（`unlistableDirectory`，第一版把列目錄的錯誤轉成空清單，於是不可列的 `entities/` 印出全零的四域報告）；`akashic scan-yaml-profile` 的根不是資料夾、讀不到的檔或子資料夾、零個 `.yaml` 同樣具名失敗（先前印全零並 exit 0）。

### 第 53 列（#642）

**情形欄的其餘部分**

2026-09-29 唯讀量測 live store：library 4、規則型 0、排除清單指向不在庫 0、規則的 venue key 重複 0。重跑腳本見量測文件

**理由欄的其餘部分**

**誠實邊界**：規則依據不明確時，連被排除的成員也回「依據不明確」而不是「排除」（Claude 代裁，依據問題優先）。

### 第 54 列（#642）

**情形欄的其餘部分**

2026-09-29 唯讀量測 live store：規則型與文件型 library 都是 0，被規則指涉的 citekey 0

### 第 55 列（#642）

**理由欄的其餘部分**

修法是把閘抽成共用核心、多收一種檔，不是複製一份邏輯。

### 第 56 列（#679）

**情形欄的其餘部分**

2026-09-29 唯讀量測 live store：work 2,569、主來源 532（沒記 `library_id` 0）、附加來源 3（沒記 `library_id` 0）、被 ≥2 筆宣稱的來源 0、讀不到的檔 0。重跑腳本見量測文件

**理由欄的其餘部分**

警告說的後果由 `AdditionalSourceWithoutLibraryReimportTests` 釘住，警告與行為不會分岔。**誠實邊界**（b13f R1 verify）：這則 warning 走一般的 per-record 通道，MCP `akashic_doctor` 的 `recordIssues` 是 errors 優先且截 20 則，沒有像 `duplicateVenueEdges` 那樣的 `StoreHealth` 家族計數，所以「觸發條件可檢查」實際只有 CLI `validate` 的 grep 可用；live 零實例、且是線性家族（一筆 entry 一則），接受。訊息說的 twin 是有條件的（單筆 `validate` 看不到別的 entry）。

### 第 57 列（#629）

**情形欄的其餘部分**

2026-09-29 唯讀量測 live store：work 的 DOI 2,449 個，形狀檢查不過 0、讀不到的檔 0。重跑腳本見量測文件

**理由欄的其餘部分**

**#629 R1 補記**：查詢回應 200 而形狀不對（`message` 不是物件、`items` 不是陣列、任一缺席）同樣具名中止，不當成「沒有候選」——「查無此筆」與「回應壞了」在輸出裡不可區分正是這一列的形狀（`CrossrefMatchResponseShapeTests`）。

### 第 58 列（#629）

**理由欄的其餘部分**

**「十七萬餘案 0 不一致」這個說法過寬（R1 verify 第 17 則）**：驗證席找到五處可重現的分岔（補充資料標題跨行、Foundation 的 NFKC、`İ`／`ı`、ICU 的 `\b`、`JSONSerialization` 的重複鍵與字串內 U+FEFF），R1 全部修掉；語料是本機 PDF 與隨機字串，不涵蓋全部 Unicode。**#629 R1 補記**：一個檔案都沒量到回結束碼 4（先前 0，全零的 `0/0` 讀起來像「沒有別篇被收」）、資料夾不存在具名失敗、形狀不合格的 DOI 不組網址，缺記錄的清單帶完整網址；新舊工具在本機能湊到的語料（10 份有標籤、41 份引擎一致）上輸出逐字相同，見 `changelog/2026-09-29-b13p-verify-r1.md`。

### 第 59 列（#673）

**理由欄的其餘部分**

**屬前言四類的第 1 類（守衛）**（b13f R1 verify 第 28 列）：本列裁的對象是那道具名拒絕——「無法判定移哪一筆」時 `--remove-reference` 拒絕、不挑——要不要**放行成一條移除路徑**；不寫的是放行，不是那道守衛；不是新的一類（前言明寫沒有「零實例的移除腿」這一類）。

### 第 60 列（#673）

**理由欄的其餘部分**

首版把它寫成「單筆各字串上限之和約 1.4 KB、25 筆約 35 KB、落在 MCP 單一輸出 48 KiB 之內」，b13f R1 verify 抓到三處錯：(1) 1.4 KB 把各字串的**字元**上限相加、當成位元組——CJK 一個字元 3 位元組；`displaySafe` 在逃脫模式數輸入 scalar，一個控制字元逃成 `\u{XXXX}`（8 字元），JSON 序列化再把反斜線加倍，最壞單筆約 6 KB（retrieval：value 200＋url 300＋retrieved 與 media_type 各 60 個 scalar 全是控制字元）、25 筆約 150 KB（推估）；(2) 48 KiB 是 `tools/list` 與 `candidateByteBudget`（resolve 候選、doctor 的 per-record 清單）的預算，**`akashic_venue` 沒有單一輸出的位元組預算**；(3) 同一個 payload 的 `works` 編年清單本來就無界（live：`psychological-methods` 1,352 筆、每筆標題至多 500 字元），所以這個上限保護不了輸出大小。

### 第 61 列（#680）

**情形欄的其餘部分**

2026-09-29 唯讀量測 live store：work 2,572、有附加 Zotero 來源的 work 3（單筆最多 1）、單筆 work 最多 `akashic.sources` 0、venue 485、通用 reference 0、讀不到的檔 0。重跑腳本見量測文件

### 第 64 列（#629）

**情形欄的其餘部分**

2026-09-29 唯讀量測（量測文件腳本）：`~/.akashic/sources/` 裡整份可解析的 JSON 文件 88 份，重複鍵 0、尾隨逗號 0、字串值開頭是 U+FEFF 的 0；#629 R1 以另一個量法報 1,800 個文件，母體不同，兩數都不為 0 的只有文件數

### 第 65 列（#663）

**情形欄的其餘部分**

2026-09-29 唯讀量測 live store：person 4,575，無隸屬 4,413、現職 116、只有已結束 46、只被觀測到 0、混合 0；Core 以外直接用 `latestPastSegment` 的檔 0

### 第 66 列（#674）

**情形欄的其餘部分**

2026-09-29 唯讀量測：person、venue、organization 的 retrieval reference 0 筆（references 8,693 筆全是 judgement）；work 的 33 筆全是 https、無帳密、`YYYY-MM-DD`、status 200。重跑腳本見量測文件

### 第 69 列（#675）

**情形欄的其餘部分**

2026-09-29 唯讀量測 live store：venue 485、名字段 537，帶時間 0、帶 source 0、帶 note 0。重跑腳本見量測文件

### 第 70 列（#690）

**情形欄的其餘部分**

立案時兩條缺口——`network-confinement` 與 `zero-instance-rows-audit` 宣告讀 `Sources/*/*.swift`，115 個不受保護的檔改動時 CI 不跑它們；使用者 2026-09-30 裁決 A 讓 `census-parity.yml` 的 `paths` 涵蓋 `Sources/**`，兩條隨之消失、清單清空。

**理由欄的其餘部分**

R1 verify（requirements、logic、regression 三席）指出清單是編譯期常數時這三條分支沒有任何負控走得到——harness 改的是 copy 裡的檔、改不到 binary；清單因此搬進資料檔，`trigger-coverage-mutations` 三格各走一條，另兩格各釘宣告範圍檢查的兩個判斷（workflow 有跑這支守衛、`paths-ignore`，DA 席實測兩者改壞時負控全綠）。R2 verify 指出那三格只走到欄數：`#<issue>` 的格式與「樣式要相等」兩個條件拿掉時負控仍 44/44，`TODO` 當第三欄的一行會把缺口放過；補五格（第三欄不是 `#<issue>`、第一或第二欄空、樣式與宣告不同、CRLF 行尾、同一條列兩次），並把兩格 workflow 注入改成 Actions 收的設定（同一個事件不能同時有 `paths` 與 `paths-ignore`）。`#<issue>` 只驗格式，不驗 issue 存在或仍開著——那一半靠下面的觸發條件。

使用者委託的裁決（保守、可逆）：清單第四欄記被接受那一刻「CI 未覆蓋」的檔數，現在的數超過它 → 紅，訊息要求重新確認（改第四欄並回 issue 記一筆）；縮小照綠，只在 `⊘` 行建議改小，不擋。格式只收四欄（三欄舊格式是格式不對，不留兩種讀法）。**目前清單是空的，所以沒有條目要回填大小**；第一條出現時照檔頭寫的量法取數。

### 第 71 列（#689）

**情形欄的其餘部分**

兩個出口是 R1 verify 加的；R2 verify（Codex、logic、security、DA 四席）指出第二個與抽取共用同一條只認一個空格的 regex，雙空格、TAB、變數、引號的呼叫兩邊都看不到，改成獨立找 binary 路徑的每一處出現。2026-09-30 量測：兩個出口的訊息各 **0** 條。重跑指令見量測文件

**理由欄的其餘部分**

R1 的「抽取認不出」就是這樣——它拿抽取那條 regex 去找漏網的呼叫。「宣告是空的」不出聲的代價是一句宣告讓人以為那支守衛有負控；「抽取認不出」不出聲的代價是那支守衛整個不在名單裡、不被要求負控——兩者都是看起來綠、其實沒量到。方向是誤報（看得見），所以不逐一擴充語法；例外只有兩個具名的形狀（`[ ! -x … ]` 存在檢查、整行只有一個 `echo "…"`），各有一格負控證明它們沒有放寬。**誠實邊界**：受測對象是 source 文字裡的執行寫法，不是 harness 執行時實際跑的守衛——死函式裡的直接執行字面與改成 `exit(0)` 的分派仍然通過（`MigratedGuardControl.swift` 檔頭列著四個形狀的現況），執行期的證據另開 issue。

「宣告是空的」改由紀錄判定：宣告了、以 rc=0 跑完，卻沒有一次讓那支守衛如預期變紅；「抽取認不出」由執行期的 `start` 取代——任何寫法、任何路徑呼叫的守衛都會留下 start，文字只留一個檢查：runner 裡提到的 `akashic-guards <名>` 都要有 start（沒有的是沒跑，或跑的 binary 不寫紀錄）。上面誠實邊界裡還通過的兩個形狀（死函式裡的直接執行、分派改成 `exit(0)`），連同 #707 comment 的其餘形狀，在 `migrated-guard-control-mutations` 裡各一格真的建置、真的執行的負控，全部紅。新判準的零實例出口（紀錄讀不到或是空的、形狀不對、不是這一次的、harness 執行的不是這一支 binary、宣告自己或沒跑的守衛、沒有以 rc=0 跑完）同樣各一格，外加一格記錄端（寫紀錄的 `runGuardProcess` 不把沒跑起來的子行程記成如預期變紅）；「harness 以 rc=0 跑完、卻有執行沒照它自己的預期」**不是零實例**——第一次跑就報出 `oracle-precondition-control` 的「未毒化」那一次標成預期綠、實際 rc=1（它只讀通過數，標錯的是預期，改成 `.none`）。新的量測見量測文件第 71 列的 2026-10-01 補記

### 第 72 列（#703）

**情形欄的其餘部分**

同批兩件：SHA-256 與複製改成逐塊（每塊讀完即釋放——R1 verify 之前這裡寫「記憶體與檔案大小無關」，當時不成立，見理由欄），`copy-zotero-attachments` 對已在 `sources/` 的同一個 digest 逐塊比對內容。2026-09-30 唯讀量測：Zotero storage 2,817 個檔、合計 61,047,841 bytes（`du -sh` 66 MB）、最大 5,499,190 bytes；`sources/` 104 個檔（含 `index.jsonl`）、最大 3,912,063 bytes——超過上限 **0**。重跑腳本見量測文件

**理由欄的其餘部分**

不寫的代價與第 18 列同形：沒有上限時，群組 library 裡別人放的一個大附件會被整份讀進記憶體（乾跑也一樣），而那是一次呼叫一步跨過、沒有曲線可以預警。

**同批另兩件不是守衛**：逐塊**加上每塊讀完即釋放**是記憶體的界——~~`SourceIntakeStreamingTests.testDigestAndCopyNeverAskForMoreThanOneChunk` 釘住每次只要一塊~~（#703 R1 verify 第 2、8 則：那支只證每次只要一塊，量不到留住了幾塊；`FileHandle.read(upToCount:)` 回的 autoreleased 緩衝在 CLI 裡留到行程結束，改動前的 binary 存 128 MiB 的檔尖峰 RSS 284,557,312 bytes，比整份讀進來還多）→ 現在 `LibraryStore.pump` 每塊包一個 autorelease pool，由 `SourceIntakeMemoryCLITests` 以真 binary 的尖峰 RSS 釘住（#703 R1 實測：128 MiB 的檔比 1 MiB 的多 1,146,880 bytes，三個 48 MiB 的附件比一個 1 MiB 的多 3,964,928 bytes）；既有 blob 的比對是 #606 留下的缺口（被截短或換掉的 blob 以前看不出來；不符列在 `storedBlobMismatch`、不覆寫；R1 起新連結遇到位址上判不出來的存檔也不連）。

### 第 73 列（#703）

**情形欄的其餘部分**

R1 verify 實測（#703）：對 240 MB 的檔跑 `store-source`、複製到一半 `kill -9`，留下 118,489,088 bytes 的暫存檔，之後 doctor 一切如常。2026-09-30 唯讀量測 live store：分片目錄裡這個形狀的檔 **0** 個。重跑指令見量測文件

**理由欄的其餘部分**

**形狀只有一份**：建立（`writeBlob`）、預演（`preflightStoreSource`）與報告都讀 `LibraryStore.temporaryBlobName`／`isTemporaryBlobName`，FAT 卷上 macOS 自己寫的 `._` 檔不算。

**R2 補記（2026-10-01，#703 R2 verify 第 22、27、28 則）**：`SIGINT`／`SIGTERM`／`SIGHUP` 不在「清不到」之列——R1 只寫了 SIGKILL、斷電、逾時，而實測 Ctrl-C 與 SIGTERM 同樣留下暫存檔（118 MB、243 MB）；現在存檔進行中接管這三個訊號、先刪登記中的檔再照原訊號結束（`InFlightSourceFiles`），清不到的只剩 SIGKILL、斷電、`abort()`。每個殘留附最後修改時間（MCP 面 `ageSeconds`、`possiblyInProgress`），**一小時內還在動的不計入 `hasFindings`**——上面「它仍計入 `hasFindings`」自此只對一小時沒動的成立（進行中的存檔是正常的工作狀態，`divergenceCount` 不計入的同一條判準）；這是顯示的門檻，不是刪除的判準，doctor 仍然全部列出、只報不刪

### 第 74 列（#708）

**情形欄的其餘部分**

CLI 與 MCP 的範圍開在進入點與分派層，新的寫入命令不必記得接；App 沒有那一層，範圍開在各寫入點。本 change 之前 App 的寫入點全在範圍外（#705 的 App 例外）；2026-10-01 源碼量測：寫入點 6 個、在範圍外 0。重跑指令見量測文件

**理由欄的其餘部分**

它比執行期的範圍嚴——寫入搬進另一個函式、由範圍裡呼叫時守衛會紅，要在那個函式裡開範圍（accept 因此把範圍寫在原處、不抽函式）；反方向有一個它看不到的形：範圍裡再開一個逃逸的閉包（`async`、另一個執行緒）去寫，字面在裡面、執行時不在（範圍靠 task-local 傳遞）——那時照舊擲 `legacyCopyNotRemoved`，大聲而不是安靜：GCD 與 `Task.detached` 不繼承 task-local、本來就沒有範圍；`Task { }` 繼承它，所以範圍的帳本在範圍結束後拒收晚到的寫入（#708 R2 verify 第 39 列：先前收進一份已取走報告的帳本，沒有擲錯也沒有提示，這一句對 `Task { }` 為假；`LegacyCopyLedgerTests.testALateWriteThroughAnInheritedScopeIsRefusedNotSilentlyRecorded`），兩條轉交的路（`handToEnclosingScope`、`collecting` 的失敗轉交）自 R3 起同樣認得已結束的範圍：收不下就留在呼叫端的報告或回傳值裡（R3 verify 第 15／20／24 列：先前忽略回傳，那幾筆哪裡都不報；`testHandingToAClosedEnclosingScopeIsRefusedAndTheItemsStayWithTheCaller`）；App 今天沒有這種寫法。清單是四個方法名：`writeEntryExclusive`／`writeVenue`／`writeOrganization` 不經 #631 的搬移刪除，不在內。守衛 `AppLegacyCopyNoticeTests.testEveryAppStoreWriteIsInsideTheScope`，掃描器 `LegacyCopyScopeScanner` 另有九支測試（`testTheScannerFindsTheMatchingBraceAndSeparatesInsideFromOutside` 等）；負控：拿掉 mutate、accept、脫鉤任一處的範圍都讓它紅（changelog `2026-10-01-app-legacy-copy-notice.md`）。**R1 verify（第 13／20 列）補了掃描器的洞**：遞迴掃子目錄（先前只讀兩個目錄的第一層，日後開子目錄整批不在掃描內而下限擋不住）、先把註解與字串字面值的內容空白掉再數大括號與找寫入點（先前以第一個 `//` 砍行，字串裡的 URL 會吃掉同一行後面的 `}`、字串裡的裸大括號讓深度失衡、區塊註解還算程式碼）、認取函式值與跨行（先前只認 `.writeEntry(`）；仍看不到的寫在 `LegacyCopyScopeScanner` 的誠實邊界（方法名單封閉、範圍只認字面的 `recordingLegacyCopies {`、字串內插裡的程式碼整段當字串）

### 第 75 列（#613）

**情形欄的其餘部分**

**查數與記錄是一步**（2026-10-02 修正輪）：`FulltextAttemptLedger.reserve` 在跨行程的 `flock` 之下重讀帳本、數今天這個站的次數、沒到上限就記一筆，之後才導航——先前 `count` 與 `append` 之間沒有鎖，兩個行程都讀到 9 就各自記成第 10 次；記錄之前檢查檔尾，不是換行就先補一個（手改過的帳本不黏成一行）；站名讀回時一律小寫（少算正是上限要擋的方向）；以位元組切行（CRLF 的檔不會整檔被當成第 1 行）；`open` 帶 `O_NONBLOCK`（lstat 與 open 之間被換成 FIFO 時不卡住）。**R2 修正輪**：`reserve`、`append`、`count` 對傳入的站名做與讀回同一個正規化（`siteName`：去頭尾空白、小寫）——先前只在讀回時小寫，直接呼叫的 `reserve(site: "UP.example")` 比對原樣的字串、上限從未生效；`load` 開檔之後也以 `fstat` 確認是普通檔（註解先前就這樣寫）。2026-10-01 本機量測：`$HOME/Library/Application Support/akashic/` 不存在，帳本 **0** 行

**理由欄的其餘部分**

帳本不放 `~/.akashic`（那是 `main` store 的 root，`.gitignore` 不排除新目錄）。釘住 `FulltextFetchPathTests.testAnUnreadableLedgerStopsBeforeAnyBrowserCall`（四種壞行與 symlink）、`FulltextAttemptLedgerTests.testATimeWithoutAnOffsetIsRejected`、`testAppendRefusesASymlink`，以及修正輪的 `testAppendAfterAFinalRecordWithoutANewlineKeepsBothRecordsOnTheirOwnLines`、`testTwoReservationsRacingForTheLastSlotGrantExactlyOne`（兩條執行緒各自開檔，`flock` 對它們就是兩個行程）、`SkillToolsCLITests.testTwoProcessesRacingForTheLastSlotGrantExactlyOne`（測試握著鎖，真的 `akashic fulltext fetch` 必須卡在鎖上、放鎖後以結束碼 9 停下、帳本剛好 10 筆）、`testAMisCasedSiteInAHandEditedLedgerStillCounts`、`testACRLFLedgerIsRead`、R2 的 `testTheSiteGivenToTheLedgerIsNormalisedLikeTheSiteReadBack`。

### 第 76 列（#613）

**情形欄的其餘部分**

**`--title` 必填、不得是空的**（2026-10-02：先前沒給就整個跳過驗證、結束碼 0 照樣說存好了，而 SKILL 把 0 讀成「驗證過」）；驗證本身跑不起來是結束碼 1、什麼都不寫（不是 5）；不是 PDF 的檔案不印內容（只印位元組數、前 8 個位元組、是否像 HTML）。2026-10-01：`take` 還沒有對任何使用者存的檔跑過，實例 **0**

**理由欄的其餘部分**

釘住 `FulltextFetchHardeningTests.testTheSourceMustBeARegularFile`、`testASourceOverTheStoreLimitIsRefused`、`testTakeCopiesTheSourceWithoutTouchingIt`，以及修正輪的 `testAFIFOSourceIsRefusedWithoutHanging`（lstat 拒 FIFO）、`testAFileSwappedForAFIFOAfterTheLstatCheckDoesNotHang`（`O_NONBLOCK`；背景執行緒限時 10 秒）、`testAFileSwappedForASymlinkAfterTheLstatCheckIsNotFollowed`（`O_NOFOLLOW`）、`testAFileSwappedForADirectoryAfterTheLstatCheckIsRefusedByTheFstatRecheck`（`fstat` 再確認，訊息與讀取失敗分得開）、`testATitleIsRequiredAndAnEmptyOneIsRefusedBeforeAnythingIsRead`、`testAVerificationThatCouldNotRunIsNotReportedAsAnotherPaper`、`testANonPDFSourceDoesNotEchoItsContent`；每一條都有負控（拿掉該檢查即紅）。

### 第 77 列（#703）

**情形欄的其餘部分**

R1 把 `writeBlob` 的「已經在了」從 `fileExists`（跟隨 symlink）改成 lstat 語意之後，對任何佔用都回「沒寫、但成功」：`store-source` 寫一列 index、印「✓ 已建立 index 條目」，位址上仍是懸空 symlink——#703 之前的 binary 會以真檔取代它；被截短的 blob 被 `update-entry --add-source` 照連；`auditSourceIndex` 只比檔名，doctor 什麼都不說，而 `copy-zotero-attachments` 還叫人「用 akashic doctor 查」。

**理由欄的其餘部分**

守衛照的是閘擋不到的來源：手改、舊 binary（含 b26 F6 之前在 exFAT 上留下半截檔的第三條放置路——那條路已拿掉，見第 83 列）、別的同步工具——位址上的那一份在 index 有它的 `bytes` 時報大小不符，沒有條目時報成孤兒 blob（誠實邊界：看不出它是半截）。**我們自己的存檔不再在位址上留半截**：位址上的名字只經 `RENAME_EXCL` 或 `link(2)` 這兩個原子動作出現。與第 73 列成對：那一列報的是**我們自己**的失敗留下的暫存檔，這一列報的是**別人**（或我們被殺掉之後）留在位址上的東西；兩者都只報不刪，理由相同——那可能是一個人正在處理的東西。**只比大小不比內容**：大小相同而內容不同的普通檔 doctor 與 `store-source` 都看不出來（要整份讀；`copy-zotero-attachments` 的 `checkStoredBlob` 會讀）。

**從留下的句子裡搬出的括注**

- 理由欄「手改 index.jsonl 那一行」之後：（b26 F6：訊息兩邊都說）

### 第 78 列（#564）

**情形欄的其餘部分**

2026-10-01 唯讀量測 live store：venue 485 筆（470 筆有 authorized、41 筆有 variant）、person 4,575 筆（全有 authorized）、organization 13 筆，`field: authorized` 或 `field: variant` 的 reference **0** 筆，statement 以 `指定：`／`確認：`／`撤回：` 開頭的 reference **0** 筆；store marker 是 18，所以今天 format 22 的寫入閘必拒、合併拒絕必然不觸發。重跑腳本見量測文件

**理由欄的其餘部分**

不寫的代價與第 1 列同形：第一筆記錄出現後，合併會安靜地把人判定過的對外形降成未標，而那正是 #564 立案要解決的——記錄留了、合併端卻不讀，等於只做一半。**判準是「有任何記錄」而不是「最後一筆是指定或確認」**：最後一筆是撤回卻仍在 authorized 只可能是手改，保守地拒絕（#564 R1 verify 指出首版的去重比整份歷史，「指定 R → 撤回 → 再以 R 指定」由工具面就造得出這個形；修正輪改成只比同一個名字同一個分割的最後一筆，「只可能是手改」才回到真話）；合併時被併者的記錄接在倖存者之後，交錯的「最後一筆」不代表時間上的最後。**機械值仍是提醒**（沒有記錄的降級照舊合併並出 warning）——這一半由 `NameClassificationMergeTests.testMechanicalDemotionStillMergesWithAWarning` 釘住，免得日後有人把拒絕放寬成「一律拒」而讓合併對 470 筆機械值全部無用（這正是當初不把 authorized 降級直接升成拒絕的理由，`two-kinds-of-edits` 的 `resolve-divergence` 列）。

**誠實邊界**：拒絕只看被併者上的 `field: authorized` 記錄（`variant` 記錄不擋降級，因為合併不會把名字從 variant 降走；分類不一致的記錄走 `wouldLoseFields`）；~~person 合併維持原狀（本來就拒絕被併者有、倖存者沒有的 authorized）~~ → 修正輪（使用者 2026-10-02 裁決 #564 第 3 點）起 person 合併搬分類一致的記錄、不一致的拒絕（`personReferenceCarry`）；organization 合併尚未實作（第 24 列）。

**從留下的句子裡搬出的括注**

- 理由欄「d 升成拒絕條件、對機械值維持提醒」」之後：（2026-09-12 重開那一格時寫下的觸發條件）

### 第 79 列（#709）

**情形欄的其餘部分**

(a) 由 `candidateLegacyCopies` 在共用段補上；(b) 先前只剩 `commitResolution` 的 `entryWritePlan` 預檢，而 `--dry-run` 不經過它——#709 R3 verify 的兩席各自在真 binary 上重現：dry-run 印「參照將改寫」並以 0 結束，拿掉 `--dry-run` 才被 #631 拒絕。2026-10-02 唯讀量測 live store：legacy 殘留 `entries/` 0 個檔、`people/` 0 個檔，所以 (a)(b) 兩格今天都是零實例；重跑腳本見第 40 列的量測

**理由欄的其餘部分**

不寫的代價與第 1 列同形而更具體：dry-run 的存在理由是不可逆的合併之前讓人看到會發生什麼，預測成功、實跑被拒時使用者拿到的是一個假的安全感。

**誠實邊界**：預檢對每個被改指的 entry 跑一次 `entryWritePlan`——目的檔在 `entities/` 時（live store 的每一筆都是）它讀那個檔、重讀一次 `store.yaml`（`StoreVersion.read`）、decode 一次，再查一次 legacy 檔在不在；dry-run 從零變一遍，apply 從兩遍（`commitResolution` 的預檢、寫入時的 `plannedWrite`）變三遍。~~live store 沒有 legacy 殘留，每筆只是一次 `fileExists`~~（#709 R2 verify regression 席：假的，目的檔存在時就要讀與 decode，與有沒有 legacy 殘留無關）。2026-10-03 實測（debug binary，3,000 筆 work 引用被併 person，有預檢與沒有預檢的兩支 binary 交替各跑四次 dry-run，機器 load average 217–287）：有預檢 9.75–27.34 秒、沒有 6.37–11.40 秒，每一輪都是有預檢的慢，差 3.4–15.9 秒，即每筆約 1.1–5.3 ms；release 版沒有量。

### 第 80 列（#611）

**情形欄的其餘部分**

2026-10-02 唯讀量測 live store：work 2,599 筆、DOI 值 2,459 個，被 ≥2 筆 work 共用的 DOI 16 個、**全部恰好 2 筆**（最大 2）——超過門檻的 **0** 個。重跑腳本見量測文件

**理由欄的其餘部分**

**代價寫出來**：`groupTooLarge` 屬於「沒記下來」那一類，CLI 因此以 1 結束，MCP payload 帶 `doiNominationsUnrecorded`。已有 >10 筆共用 DOI 的 store 之後只要再新建一個該群組的成員，那一次匯入就以 1 結束（#611 R2 verify DA 實測：不是每次匯入——同一份來源再跑一次、沒有新建就是 0）；但 `groupTooLarge` 是**刻意的不提名**、不是寫入失敗，把它算進非零是第一輪的取捨，對 cron 或 CI 是否想要沒有確認過。為什麼不是「全記」或「全不記」：全記是上面的 C(k,2)；全不記違反「自動記」的裁決；門檻讓 live 資料（全部是 2 筆）完全不受影響。

### 第 81 列（#611）

**情形欄的其餘部分**

歧異記錄的 id 只雜湊候選 key（`DeterministicUUID.forDivergence`，不含形狀；`renameEntry`／`renamePerson` 就地改寫候選的 key 而不重算 id，`resolveDivergence` 的合併才重算並改名舊檔），所以有兩種撞法：同 key 的別種形狀；key 被 rename 改寫過的記錄占著舊 id。2026-10-02 唯讀量測 live store：歧異記錄 1 筆，它的 id 與它目前候選 key 算出的 id 相同——id 已過期的 **0** 筆。重跑腳本見量測文件

**理由欄的其餘部分**

拒絕住在 `recordCheckedDivergence`，`record-divergence`、`akashic_record_divergence` 與 Zotero 匯入的提名三個入口同一條，所以守衛只有一份。**第二輪（R2 verify 第 12／31／37 列）補的是訊息**：第一版借用 #631 的泛用拒絕（「先看那個檔：修好、移走、`akashic validate` 會列出被 quarantine 的檔」），把原因一律說成「形狀」（改名的情形兩邊形狀都是 work，說的是假話），出路還叫人「看那個檔」——那是給被 quarantine 的記錄的，這一筆是健康的記錄；而 `record-divergence` 本身撞同一個拒絕，指它手記是循環。**第三輪（R3 verify 第 1／2／5／8 列）補的是可見性**：R2 的訊息是約 550 字的單行、出路從第 390 字起，CLI 與 MCP 的錯誤出口逐行截 400，使用者讀到的版本正好截在出路之前，而單元測試斷言的是未截的描述；現在逐行、出路在第二行，CLI 與 MCP 各有一支走真 binary 的測試斷言 sink 之後看得到 `dismiss-divergence`。**誠實邊界**：(1) 這一組候選目前記不進去（同一個 id 不能同時是兩筆記錄）——出路是先處置現有那一筆；根治要把形狀或「記錄世代」納入 id，那是 format 級變更，沒有做；(2) 匯入端把它報成 `failed`（沒記下來，CLI 非零）；(3) 「無判斷的重錄不得抹掉判斷」（#133／#159）有各自的裁決，不在這一列。

### 第 82 列（#564）

**情形欄的其餘部分**

2026-10-02 唯讀量測 live store：每筆記錄的名字數最多 person 5、venue 4、organization 3，最長的名字 129 位元組，名字分類記錄 **0** 筆（store marker 18，寫入閘在 22 之前全拒）。R1 verify 用真 binary 造過三種形：一次 1,500 個名字的 `--add-variant` 寫出 6,167,788 位元組的 venue 檔、一個 9,000,000 字元的「名字」62 秒後才被 8 MiB 寫入閘擋、以 U+0301 開頭的理由寫成一筆可被移除的一般 reference。重跑腳本見量測文件

**理由欄的其餘部分**

person 的理由要求是裁決第 1 點：`fields.names` 先前能不附理由地改 authorized，與「名字分類一律留記錄」相反。**誠實邊界**：`authorize-names` 不設 200 的上限——它每個 person 至多三筆（每書寫系統一個對外形），上限防的是單筆記錄被灌爆，批次面不會；person 的 `fields.names` 的 authorized 200 遠大於實測的 5，量的是同一件事（單次呼叫）（b33 X1 第 15 列：R2 的 changelog 說這一列改成只數 authorized，推上去的樹仍寫「兩個分割合計」）。

### 第 83 列（#703）

**情形欄的其餘部分**

2026-10-02 在真的 exFAT 磁碟映像（macOS 27，FSKit 掛載）上量：`VOL_CAP_FMT_HARDLINKS` 與 `VOL_CAP_INT_RENAME_EXCL` 都是有效旗標、值為 0，兩個呼叫都回 `ENOTSUP`（errno 45）；新建檔案的 inode 在第一次寫入之後改變（建立時 18446744073709551612、寫入一個位元組後 9；APFS 前後相同）。

**理由欄的其餘部分**

**不寫替代路**：R2 在這個形狀上補過一條「`O_EXCL` 建立目的檔後逐塊複製」的路，四席各自在真的 exFAT 映像上量到它失效——靠建立當下的 inode 認「自己的檔」，而 exFAT 的 inode 在第一次寫入後改變，所以失敗清理與訊號清理全部失效（半截檔留在內容位址上、讀回驗證抓到的壞檔之後被記進 index），同時它讓未完成的檔在最終檔名下看得到。

拒絕在**建立任何檔案之前**由磁碟區的能力旗標擋下（`getattrlist`），所以訊號清理的 inode 問題也一併不存在——登記的暫存檔只可能在支援的磁碟區上，且改以名字認。~~磁碟區沒有回報能力旗標時，走到放置才發現（兩個呼叫都回「不支援」），暫存檔由 `defer` 以名字刪掉、同一句拒絕。~~（b29 V5 MEDIUM 0：位址上已有同一份內容時存檔不走放置，旗標讀不到又做不到的磁碟區上那一支回成功、缺條目時還補 index——「每一次」不成立。見 `changelog/2026-10-02-b29-h5-fixes-703-700.md`。）磁碟區沒有回報能力旗標時，寫入之前、任何分支之前在分片目錄裡**實際放一次**空的探測檔（同一條放置路；探測名是暫存檔的形狀、用完即刪），做不到就同一句拒絕、零寫入，含不補 index；拒絕在複製內容之前。**誠實邊界**：兩個旗標都有效而都為 0 才拒；旗標無效或查不到由那一次實際放置決定；預演（`preflightStoreSource`，乾跑也走它）不寫任何東西、所以不探測——旗標讀不到時批次的乾跑說可以，實跑逐筆探測、做不到才逐筆被拒（每筆在複製之前；探測做得到就照常存——b31 W5 LOW 2：先前寫「實跑逐筆被拒」，讀起來像旗標讀不到本身就是拒絕條件）；探測要在分片目錄建檔，所以旗標讀不到又不可寫的分片目錄上，連已在的內容重存也被拒（b31 W5 LOW 11、12，記錄、不改）；旗標回報不支援而其實可用時會誤拒；SMB／NFS 沒有測。

### 第 84 列（#613）

**情形欄的其餘部分**

這一輪的閘：(a) 別的主機上不是 PDF 的頁面要落定（readyState complete／interactive，約 60 秒——以時鐘計、也不超過 30 次輪詢，見 (j)——看的那一下換了頁就不算），沒落定是卡住；(b) 落定之後標題、網址、頁面文字與 HTTP 狀態一起判訊號（429 一律整批暫停，已知驗證服務上也是）；(c)「還在 doi.org」看主機，`doi-not-resolved` 要 doi.org 自己的查無證據（標題或頁面寫著 `DOI Not Found`、或 404），doi.org 上的訊號與登入頁長相一律整批暫停；(d) DOI 落地頁的網址是登入／驗證頁的長相 → 整批暫停（只看網址，落地頁的標題是文章標題）；(e) `followed` 接續只接文章站、已知驗證服務、或顯示 PDF 的分頁；(f) 已知驗證服務的主機要是乾淨的 DNS 名稱。R3（2026-10-04，b31 W4）再補：(g) 別的主機上的判斷用**同一份快照**——網址與標題同一次 `documents`、頁面文字與狀態碼同一次 JS，讀完再讀一次網址與標題，不同就回去等（先前舊中繼頁的網址與標題配上新登入頁的文字，交給人）；(h) DOI 落地頁（與導航之前的接續）的**登入頁長相先於頁面文字**判（先前登入頁的文字提到 CAPTCHA 就得 8）；(i) 讀不到的計數改成同一個網址上**連續**、換頁重算，讀到過一般網頁的網址不再走「讀不到」那一格（先前累積計數，沒載完的頁面夾著三次零星的失敗就交給人）；(j) 等落定以時鐘約 60 秒計；(k) SKILL 第 0 步改問 `akashic fulltext contract` 的版本（先前 `take` 的兩條探測分不出 R1、R2 的 CLI）；(l) SKILL〈中止條款〉的封閉清單與程式逐字對帳。b34（2026-10-05，b33 X3：R3 只修了別的主機那一條路）再補：(m) **文章站上同一套**——讀不到的分頁走同一個判斷（`judgeUnreadable`）、讀不到同一個網址連續計數且讀到過一般網頁的網址不算、HTML 頁的判斷與交給人時印的網址用同一份快照（先前同站 PDF 的文章標題得 8 或 6、讀的當中轉到 IdP 的頁面得 7 `html-page`、沒載完的頁面夾著三次失敗得 7）；(n) 讀不到的分頁停在**登入主機**上整批暫停（只看主機：最左邊的標籤是登入字詞、或任何標籤有 IdP 服務名；PDF 不從 IdP 主機出來，R3 讀不到的分頁一律交給人）；(o) 導航之前的接續先看主機的登入長相（不送 JS），PDF 先於路徑的登入長相，判的是分頁此刻的網址，驗證頁的網址而沒有訊號就等它轉走（只讀網址）；(p) 頁面連結的 origin 不帶帳密比、不帶帳密印；(q) 使用者 2026-10-05：網頁副檔名加八個、登入字詞拆複合段（只拆網頁名稱）——往停的方向；主機的登入字詞只認最左邊的標籤與四個 IdP 服務名——往放行的方向（`journals.auth.gr`）；同日本輪之後：讀的當中一直在變的頁面維持整批暫停、第二個標籤的登入字詞（`www.login.example`）不加。b37（2026-10-09，b36 Y2）再補：(r) 讀頁面的當中分頁在文章站上換了頁，換到的那一頁**先判網址的登入長相**、再判起疑訊號（落地頁、讀 PDF 連結之前、導航之前的接續；先前同站 `/login` 的文字寫著 CAPTCHA 就得 8、印出 `resume:`）——導航之後同站的 HTML 頁仍只看文字訊號、交給人 `html-page`；(s) 使用者 2026-10-09：複合路徑段只認明確的登入字（`BotSignals.compoundLoginWords` 七個、`compoundLoginJoins` 兩對）——往放行的方向（`hepatitis-c-as-…`、slug 裡的 `cas`、`auth`、`idp`、`sso` 不再停），歧義的四個字只在整段比。同一輪另一個方向：別的主機上顯示 PDF 先交給人，標題片語與路徑字詞改成整字、整段——那是把誤停收回，不是新的閘；R3 同一個方向：別的主機上讀不到的分頁（可能是 Safari 的 PDF 檢視器；b34 起文章站上同一套）不再因標題或網址的字樣整批暫停，交給人（`unverifiable`），只有網址在已知驗證服務上、或標題與網址帶著驗證服務自己的標記（`BotSignals.serviceMarkerLabels`，封閉的六個標籤）照訊號處理。2026-10-02：`fetch` 從沒對真的 Safari 跑過（任務約束），每日嘗試帳本 `$HOME/Library/Application Support/akashic/` 不存在，實例 **0**；每一種形狀都是審查者以假瀏覽器或 stub 造出來的

**理由欄的其餘部分**

**第四種是 R3 改正的封閉列舉**（b31 W4 第 5 則：R2 寫「三種」，而程式另有一條路——讀不到時累積計數，沒載完的頁面提早交給人）：裁決說 PDF 交給人，而讀不到的分頁可能就是 PDF 檢視器，所以讀不到的分頁照 PDF 的精神交給人、什麼都沒檢查過（b34 起文章站上同一套；停在登入主機上的整批暫停）；為了不讓沒載完的頁面借道，它限在同一個網址連三次讀不到、而那個網址從沒讀到過一般網頁的回答——**代價**是一個 JS 從頭到尾都讀不到的 HTML 頁與 PDF 檢視器分不出來，也走到這一格。**doi.org 那一格是在裁決之上的收窄**（b31 W4 第 23 則）：裁決原文把「DOI 解不開」列在交給人，R2 要 doi.org 自己的查無證據、停在 doi.org 而看不到證據的整批暫停——方向是停；使用者 2026-10-05 第 1 則照這個收窄裁定（以它為準），不再待確認。釘住 `FulltextOffSiteTests`、`FulltextR3Tests`（R3 的每一道閘至少一支：`testAPageChangeWhileReadingThePageTextIsNotMixedIntoOneJudgement`、`testALoginLookingLandingThatMentionsACaptchaStillPausesTheBatch`、`testAnUnreadableTabOnAnotherHostIsHandedOverWhateverItsTitleOrPathSays`、`testScatteredUnreadableAnswersOnALoadingPageAreAStallNotAHandover`、`testTheSkillsClosedListsAreTheCodesLists`）、`SkillToolsCLITests.testTheStepZeroProbeTellsAnR2CLIFromThisOne`（R2 每一道閘至少一支；`testAStillLoadingPageOnAnotherHostIsAStallNotAHandover`、`testAnHTTP429OnAKnownVerificationServiceAfterNavigationPausesTheBatch`、`testALoginPageCarryingTheDOIInItsQueryPausesTheBatch`、`testSafarisOfflinePageOnDoiOrgIsNotADOIProblem`、`testResumingAfterNavigationRefusesSomeoneElsesTab`、`testAnAnswerReadWhileTheTabWasChangingPagesIsNotUsed`）與 `BotSignalsResponseTests.testKnownVerificationServicesRejectNonCanonicalHosts`；b34 的每一道至少一支在 `FulltextB34Tests`（`testAnUnreadableTabOnTheArticleSiteIsHandedOverWhateverItsTitleSays`、`testAnUnreadableTabOnALoginHostPausesTheBatch`、`testAPageChangeWhileReadingAnArticleSitePageIsNotMixedIntoOneJudgement`、`testScatteredUnreadableAnswersOnTheArticleSiteAreAStall`、`testResumingBeforeNavigationOnASameSitePDFWithALoginWordInItsPathHandsItOver`、`testALinkCarryingTheSameCredentialsAsThePageIsFollowed`、`testHostLoginWordsCountOnlyInTheLeftmostLabelOrAsIdentityProviderNames`）；b37 的在 `FulltextB37Tests`（`testALandingThatTurnsIntoASameSiteLoginPageWhileBeingReadPauses`、`testCompoundSegmentsCountOnlyExplicitLoginWords`）；每一道都有負控（changelog `2026-10-02-fetch-fulltext-r2-fixes.md`、`2026-10-04-b32-f4-fixes-613.md`、`2026-10-05-b34-k2-fixes-613.md`、`2026-10-09-b37-n2-fixes-613.md`）。**誠實邊界**：doi.org 查無頁的標題寫著 `DOI Not Found` 是記憶、沒有對 doi.org 量過（頁面文字與 404 是另兩個證據）；`PerformanceNavigationTiming.responseStatus` 在 Safari 有沒有值沒量過，沒有時已知驗證服務上的 429 只能靠頁面文字；等落定最多多花約 60 秒。

### 第 85 列（#564）

**情形欄的其餘部分**

合併搬名字分類記錄自此按被併者的順序接、每一筆只與那個名字那個分割此刻的最後一筆比位元組（`appendCollecting`）；分類一致的被併者照它接過去，最後一筆必然與分類一致。

2026-10-03 唯讀量測 live store：名字分類記錄 **0** 筆（store marker 18，寫入閘在 22 之前全拒），最後一筆與分類矛盾的（分割, 名字）**0** 組。R2 verify 用真 binary 造過：被併者「指定 R → 撤回 S → 指定 R」併進已有「指定 R」的倖存者——先前以整份歷史去重只搬撤回，倖存者的名字仍是對外形、最後一筆卻是撤回。重跑腳本見量測文件

**理由欄的其餘部分**

**誠實邊界**：保險只看名字分類記錄的最後一筆，不看交錯的順序是不是時間上的順序（store-format §3.5 誠實邊界 (2)）；它是 delta，倖存者合併前就矛盾的那一格不擋——由 `testExistingContradictoryTailOnTheSurvivorDoesNotBlock` 釘住。

**#564 b34 補記（b33 X1 第 1／4／9／10／21 列）**：delta 的基準改成**原始倖存者**、全部接完之後算一次差集——先前每接一筆被併者就拿「此刻的倖存者」當基準並累加，一筆被併者暫時修好倖存者原有的矛盾、下一筆又帶回來時被當成新的，一筆造出的矛盾被下一筆修好也照擋，結論都隨順序翻轉；被併者依 key 排序再接，結果不受給定順序影響（`testThreeDoomedInAnyOrderGiveTheSameKeeper`）。搬法多一條：倖存者已有而此刻尾端一致的不重搬（`carryCollecting`）——兩筆攣生歷史相同時，先前的「只比最後一筆」把整段歷史再接一遍、validate 永久報重複；接續改成線性（先前名字互異時 O(N×R)，兩筆各 4,000 個名字的乾跑 89 秒）。拒絕的出口依實體、分割與方向各一句（variant 分割「不在 variant 卻以指定結尾」的出口先前給的是 authorized 的做法，照做之後同一則拒絕原樣回來）

**從留下的句子裡搬出的括注**

- 理由欄「或叫人去「撤回」一個不在分割裡的名字」之後：（R2 verify 第 6 列真 binary：出口是做不到的步驟）

### 第 86 列（#564）

**情形欄的其餘部分**

2026-10-03 唯讀量測 live store：person 4,575 筆，沒有任何名字的 **0** 筆。R2 verify 用真 binary 造過：只有一個 variant 名字、最後一筆是撤回的 person 一次刪成 `namesTotal: 0`，載入與 validate 都過，`doctor` 才報「no authorized name」。重跑腳本見量測文件

**從留下的句子裡搬出的括注**

- 理由欄「個；這一列的形~~只有一個入口造得出」之後：（`remove_names` 是唯一會讓 person 少一個名字的工具面——`fields.names` 的替換給什麼就是什麼，空的替換是呼叫端自己寫的）
- 理由欄「 fields.names 的空替換」之後：（b33 X1 第 19／40 列：R2 自己另開一條把對外形一起清掉的路，而空替換早就能清掉只有 variant 的 person；2026-10-05 起兩個入口都擋，原本就沒有名字的 person 不擋）

### 第 87 列（#700）

**情形欄的其餘部分**

`file add`、`doctor`、`import-zotero`、MCP 的兩個匯入都走到那裡。verify 用真 binary 在 scratch 重現了五種。2026-10-04 唯讀量測 live registry：註冊的 store 1 個，它的 `.gitignore` 是 UTF-8 一般檔、已有區塊——0 實例。重跑腳本見量測文件

**理由欄的其餘部分**

symlink 選拒絕而不是寫到它指向的檔：那個檔可能在 store 之外、被別的 repo 共用。**誠實邊界**：NUL 一律算「不是文字」（沒有 BOM 的 UTF-16 是合法的 UTF-8）；~~看與寫之間檔案被換掉時以 inode 與大小比對、不同就不寫；`access(W_OK)` 以實際 uid 判寫入權限~~（b33 verify 實測那個比對只縮小窗口：同時首跑會寫出兩份區塊、對已在的區塊假拒絕——第 94 列改成取鎖、鎖內重讀，寫入權限改以有效 uid 判）；`.gitignore` 先前若是唯讀（0444）而目錄可寫，舊版會整份替換它，現在以「沒有寫入權限」拒絕。

### 第 88 列（#711）

**情形欄的其餘部分**

R3 把辨識補寬，另加一個不靠辨識的地板：規則檔裡一行棘輪標記記「合模板的量測至少幾條、已退場區塊恰好幾個」。2026-10-04 量測：規則檔的量測 35 條、合模板 35 條、退場區塊 1 個（5 行不掃）；評審的探針在 R2 全部 rc=0、R3 全部紅（`audit-guards-mutations` 的九格）。**R4 補記（b33 X6，2026-10-05）**：R3 的辨識仍是列舉，評審在列舉之外又找到好幾種（管線跨空白行、以豎線開頭而不是表格列的續行、`${X-akashic}`、名字以 grep 結尾的命令、`--count-matches`、管線進 `awk`／`nl`／`sed`、大寫的 binary 名、兩段 inline code 之間只隔一個豎線），退場區塊在個數不變下照樣藏得住量測，同一道閘的複本撐得住地板；R3 新增的辨識分支 13 個原始碼突變體 12 個存活。2026-10-05 量測：量測 39 條、合模板 39 條、依閘去重 37 條；守衛原始碼的 35 個突變體逐一重編、重放 `audit-guards-mutations` 對應的格子，全數變紅。重跑指令見量測文件

**理由欄的其餘部分**

退場區塊釘成恰好，因為退場標記是一個全域的「不掃」開關，多一個就是多一處量測可以不帶閘。

辨識也從列舉「什麼算」改成反過來寫：binary 的輸出經管線送進任何命令都算計數，除了一張封閉的「已知不計數」清單——列舉會在下一輪漏，反過來寫的漏認方向只剩那張清單與誠實邊界。

### 第 89 列（#692）

**情形欄的其餘部分**

2026-10-04：這條讀取路徑從沒對真的 Safari 跑過（`akashic-verify-venue` SKILL 的「沒有實跑過」一段），實例 **0**；每一種形狀都是審查者以假瀏覽器、Node 或抽出的腳本造出來的

**理由欄的其餘部分**

(e) 不是值的守衛而是清理順序：失敗之後留下的上一輪檔案會被讀成這一輪的結果，「沒寫出」與「寫的是舊的」在讀的人眼裡一樣（第 3 列沉默的歧義的同形）。釘住 `WebAccessReadContractTests`（從文件抽出區塊、假 safari-browser 接真 `akashic`）與 `WebReadTests`；每一道都有對應的測試，(e) 與剔除集合另有負控（changelog `2026-10-04-b32-f2-fixes-692.md`）。**誠實邊界**：(a) 不模擬 WebKit，只在會分岔的地方拒絕——WebKit 回報的若是正規化之後的網址，這些形狀不會出現；(d) 只看主機，`www.google.com` 這類只在 `/recaptcha/` 才算驗證服務的主機也算進來（保守的一邊）；國際化網域名稱轉 punycode 走 Foundation 的 IDNA，Safari 實際回報哪一種沒量過。

**b33 verify 補三道**（同一條讀取路徑、同一個零）：(c) 加「`rawLength` 比交回的文字還短」與「剔除之後沒有看得見的字」也是 `READ-FAIL`，`truncated` 另由「原文長度超過上限」算；剔除加 noncharacter；(d) 寫明是比中止條款保守的一邊、只在主機**換到**驗證服務時觸發，待使用者裁決

### 第 90 列（#711）

**情形欄的其餘部分**

實測 bash 與 zsh：`${V:?…}` 寫在管線的一段裡只結束那一段的子 shell，錯誤訊息走 stderr、右邊的 `grep -c`／`wc -l` 照樣印 0——第 46、73、77 列的期望值就是 0，第 73 列的 `find …` 接 `wc -l` 與自證的 `doctor …` 接 `grep -c` 兩邊同為 0、還互相印證；STORE 打錯成一個不是 store 的目錄時 `validate` 報錯而計數一樣印 0，`doctor` 還在那裡建出一個 store、改它的 `.gitignore`。2026-10-05：五列改成前置條件 `: "${STORE:?…}" && test -f "$STORE/store.yaml" && …` 之後，fence 與 inline code 裡把 `${V:?…}` 寫在管線裡的單位 0 個、缺前置條件的量測 0 條；第 41、46、49、73、77 列的七條指令在 bash 與 zsh 下 STORE 沒設、設成非 store 目錄時都什麼都不印、那個目錄沒有多出任何檔，第 18 列沒設時同樣不印。重跑指令見量測文件

**理由欄的其餘部分**

沒有管線的簡單指令（第 49、77 列的 `python3 - "${STORE:?…}" <<'PY'`）裡的 `${V:?…}` 真的停得下來，不報。**誠實邊界**：前置條件只對同一行的 `&&` 串有效——多行片段的其他行（例如第 18 列的 `over=$(mktemp)`）各自負責；散文裡的 `${V:?…}` 不查。

### 第 91 列（#709）

**情形欄的其餘部分**

同一形狀在 `authorize-names`：改名一對而 legacy 那份已有 authorized 時只有 entities/ 那份在寫入集合裡，先前照寫、兩份各帶不同的 authorized 狀態。2026-10-05 唯讀量測 live store：legacy 殘留 `entries/` 0 個檔、`people/` 0 個檔（量法同第 40 列），兩格今天都是零實例

**理由欄的其餘部分**

**判準只有一份**：哪一筆是拷貝問 load 的標記（`markLegacyCopiesShadowedByEntities`），附註、`legacyCopiesInPlan` 與拒絕都由 `legacyCopiesInPlan` 算——第四次 verify 的另一半正是附註先前數了計畫沒讀到的種類（只有 person 拷貝時 venues 也說「計畫含 1 份」）。

### 第 92 列（#692）

**情形欄的其餘部分**

verify 以真 binary 在 scratch 實測 `landing --out <目錄>` 把目錄換成一般檔、`check --raw <目錄>` 在 READ-FAIL 之後照樣刪、`landing --out .` 刪掉目前目錄。web-access.md 的區塊給的路徑是 `<W>/…` 加十六進位碼或數字序號，頁面影響不到任何一條——實例只可能來自人或模型把目錄寫成這些引數，2026-10-05：0

**理由欄的其餘部分**

**誠實邊界**：路徑由呼叫端給、程式不限制它在哪個目錄（只保證不刪目錄）；`removeFile` 的 `lstat` 與 `unlink` 之間被換成目錄時 `unlink` 失敗、不遞迴；同類的 `fulltext take` 輸出（`OutputFile`）早已拒絕 symlink，這裡依指示放行 symlink、刪的是連結本身。

### 第 93 列（#692）

**情形欄的其餘部分**

正則的私有後綴少四個（`localdomain`、`home`、`box`、`private`）、不擋把四段數字塞進名稱的 `127.0.0.1.nip.io`——而開分頁就是帶著 profile 的 cookie 送出第一個請求，落地檢查只擋得住之後的讀取。兩份都不擋 RFC 6761／7686／9476 的特殊用途名稱（`.test`、`.example`、`.invalid`、`.onion`、`.alt`）。實例：開的網址只有兩種來源（端點範本、使用者給定或確認的），2026-10-05 沒有一次因為這條正則放行內網名稱的紀錄可查——0

**理由欄的其餘部分**

**誠實邊界**：仍是形狀檢查——解析到私有位址的公開名稱擋不了；舊 CLI 沒有 `url` 子命令時區塊以非零結束（不開），探測先擋下。

### 第 94 列（#700）

**情形欄的其餘部分**

verify 以真 binary 實測兩個以上的程序同時第一次對同一個 store 建佈局時：沒有 `.gitignore` 的那一種 `O_EXCL` 撞上 `EEXIST` 就報「被換掉或改過」（區塊其實已在：`doctor` 假警告、`file add`／`import-zotero` 假拒絕），有 UTF-8 `.gitignore` 的那一種兩個程序都通過比對、各自附加，寫出兩份區塊；舊版的整份原子替換兩種都不會。2026-10-05 以 3043aaf7 的 binary 重量：6 個程序 × 10 輪，前一種 9 輪有假警告、後一種 3 輪兩份；修後 0／0。

**理由欄的其餘部分**

四個新形狀各自是「不動它」的一格：硬連結與 symlink 同一個理由（那個檔可能在 store 之外）；git 不讀 ≥ 100 MiB 的 `.gitignore`（實測 git 2.55），附加會讓原本生效的檔越過那條線；只有標記沒有規則是寫到一半中斷的形狀，先前被當成已在而永遠不補。**誠實邊界**：檔案系統不支援 `flock` 時不鎖（鎖內重看仍擋得住「別人已寫好」，擋不住兩邊同時寫）；非 akashic 的寫入者不經這把鎖——回滾因此先看大小是不是「原長＋這一次寫的」，不是才截；同時跑的 `doctor` 重建 index 另有一個與 `.gitignore` 無關的競態（3043aaf7 同樣出現），不在這一列。

### 第 95 列（#564）

**情形欄的其餘部分**

R2 讓沒有記錄的對外形一步離開 names、不寫撤回：理由既不入庫也不在回應，format < 22 的寫入閘因為沒有記錄要寫而沒觸發——live store 是 format 18，那條路是 `fields.names` 對既有 authorized 唯一生效的改法（真 binary 造過）。2026-10-05 唯讀量測 live store：person 4,575 筆、有對外形的 4,575 筆，名字分類記錄 **0** 筆——每一個對外形都落在 R2 放行的那一邊。重跑腳本見量測文件

**理由欄的其餘部分**

**誠實邊界**：format < 22 時 person 的 authorized 改不了——每一種改法都要寫記錄，寫入閘擋；這是裁決第 1 點要的。

### 第 96 列（#564）

**情形欄的其餘部分**

現在只列帶內容的段、每個名字至多 20 段，總數在既有的 `segmentsRemoved`。2026-10-05 唯讀量測 live store：organization 13 筆，同一個名字最多 1 段。重跑腳本見量測文件

**b37 補記（b36 Y1 第 0／1／13 列）**：b34 的量測只數段數、沒數每段的 attested——還在長的那一軸沒有量到，而報告照樣整列它。b37 起每段的 attested 也截在 20 個（最後一項是「…另 N 個觀測點未列出（共 M 個）」），venue `edit_name_segment` 報告的 before／after 同一個上限；讀取面全列（`match` 要逐項相同）。真 binary 對 b36 重現的形（一段 20,000 個觀測點、`update-organization --remove-name`）：回應 460,506（b36 verify 席在 b089dc73 量的）→ 1,095 位元組（b37 自己量的，同一個形）。量測腳本改成兩軸都量（organization 與 venue 的名字段）。2026-10-09 唯讀量測 live store：organization 13 筆、venue 485 筆，同一個名字最多 1 段、一段最多 0 個觀測點。

### 第 98 列（#564）

**情形欄的其餘部分**

b36 Y1 第 12 列（devil's advocate 席，真 binary）：倖存者 `指定 R`；一筆被併者自己不一致（`撤回：手改` 卻仍在 authorized），另一筆 `確認：C`。不一致那一筆叫 d1 時乾跑通過（d2 的確認最後接上，矛盾被蓋住、validate 全綠），改叫 d9 時同一份內容被拒。b37 起兩種拼法都拒絕並說出那筆被併者（`NameClassificationMergeB37Tests`）。

## 各列的量測

**第 12 列的零是駁回出來的——量測腳本**（2026-09-03，`~/.akashic/entities`）。第一行印 person 總數與三個計數，對應第 12 列情形欄的 865／11／1／0（有 ≥2 個不同 confirmed literal 的 person、其中跨書寫系統的、其中有兩個彼此無共同 token 拉丁名的）；接著逐人列出那些 literal，**駁回理由要拿這份清單逐筆核對**（實跑：10 組只差縮寫形、標點或大小寫，1 組跨書寫系統）。「拉丁名」的判準寫在腳本裡（至少一個字母，且每個字母的 Unicode 名稱都以 `LATIN ` 或 `FULLWIDTH LATIN ` 開頭——後者是 #568 補的，與 Swift 的 `WritingSystem` 對齊；live store 沒有全形名字，計數不受影響——漢字、假名、諺文、西里爾都不算；不要求 ASCII、不靠 code-point 範圍）。這個判準改了兩次：第一版只排除 CJK，會把其他書寫系統當拉丁名、空 token 會誤算「無共同 token」（Codex R2 抓到）；第二版要求至少一個 ASCII 字母且只認部分拉丁區塊，`É` 單獨會被判非拉丁、`[À-ɏ]` 範圍含 `×`／`÷`（Codex R3 抓到）。三版在 live store 上都得同一組數——邊界案例目前沒有實例，但判準要與散文說的一致：

```bash
python3 - <<'EOF'
import glob, io, re, os, collections, unicodedata
root = os.path.expanduser('~/.akashic/entities')
people = 0
lits = collections.defaultdict(set)
for f in glob.glob(root + '/*.yaml'):
    t = io.open(f, encoding='utf8').read()
    if not t.startswith('person:'): continue
    people += 1
    key = re.search(r'^key: (.+)$', t, re.M).group(1).strip()
    for m in re.finditer(r'^\s*- field: resolution-confirmed\n\s*value: (.+)$', t, re.M):
        v = m.group(1).strip().strip('"\'')
        if ' :: ' in v: lits[key].add(v.split(' :: ', 1)[1])
multi = {k: sorted(v) for k, v in lits.items() if len(v) >= 2}
# 拉丁名 ＝ 至少一個字母，且每個字母的 Unicode 名稱都以 LATIN 開頭（漢字、假名、諺文、西里爾、阿拉伯……都不算；
# 不要求 ASCII、不靠 code-point 範圍——範圍會漏掉後面的拉丁區塊、也會把 × ÷ 當字母）
def is_latin_letter(c): return c.isalpha() and unicodedata.name(c, '').startswith(('LATIN ', 'FULLWIDTH LATIN '))   # #568：與 Swift 的 WritingSystem 同一條；全形的名稱是 FULLWIDTH LATIN …
def latin(s): return any(c.isalpha() for c in s) and all(is_latin_letter(c) for c in s if c.isalpha())
def toks(s):
    out, cur = set(), ''
    for c in s.lower():
        if is_latin_letter(c): cur += c
        elif cur: out.add(cur); cur = ''
    if cur: out.add(cur)
    return out
cross = sorted(k for k, v in multi.items() if len({latin(x) for x in v}) > 1)
disjoint = sorted(k for k, v in multi.items()
                  if any(latin(a) and latin(b) and toks(a) and toks(b) and not (toks(a) & toks(b))
                         for a in v for b in v if a < b))
print(f'person={people} multi={len(multi)} cross={len(cross)} disjoint={len(disjoint)}')   # 2026-09-03：865 11 1 0
for k in sorted(multi): print(' ', k, '|', ' / '.join(multi[k]))
print('cross:', cross); print('disjoint:', disjoint)
EOF
```

**第 13 列的量測（2026-09-03，可重跑，且自證）**：死 verdict 數 `LC_ALL=C grep -a -q '不在載入集合，且沒有任何檔宣稱它' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c '死 verdict'`（應印 0；**沒印任何東西＝你的 `akashic` 是沒有這條檢查的舊 binary**——verify 實測 PATH 上的 `~/bin/akashic` 就是這樣：對一份真有 5 條死 verdict 的副本它回 0、`.build/debug/akashic` 回 5。「沒被檢查」與「檢查過且乾淨」在輸出上不可區分，第 3 列的理由。**`LC_ALL=C` 不能省**（#710）：macOS 的 `/usr/bin/grep` 在 UTF-8 locale 下對 binary 比不到中文，2026-09-30 實測同一個 `.build/debug/akashic` 不加回 rc=1、加了回 rc=0——照抄的人會把新 binary 讀成舊的；`&&` 後面的 `grep -c` 讀 `validate` 的文字輸出，不受影響。**閘的片段取 `validate` 那則訊息自己的長字面段**（#711 R2 verify 第 19 列）：
`死 verdict` 是 11 位元組的獨立字面段（`StoreHealth.deadVerdictPrefix`），release 版的 binary 裡位元組不連續；R1 的閘靠 `rename` 拒絕訊息裡
的兩個長字面段成立——拿掉 `validate` 的掃描、留著 `rename` 的拒絕時，閘照樣綠）；verdict 總數 `grep -h 'field: resolution-' ~/.akashic/entities/*.yaml | wc -l`（2,700，含 confirmed 與 rejected）。第一版寫 2,698 並附 owner-kind 拆分——那是用單行正則掃出來的，漏掉兩筆被 YAML 折行的長 value；grep 的數才是可重跑的，拆分不承載裁決、不列。

**第 15 列的量測（2026-09-04，可重跑）**：本機缺承重存檔數 `LC_ALL=C grep -a -q '本機缺承重存檔' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c '本機缺承重存檔：'`（用含這條檢查的 binary——同第 13 列的自證：舊 binary 印不出東西，「沒被檢查」與「檢查過且乾淨」在輸出上不可區分；2026-09-04 實測 1，且那一筆是 URL 不是 digest）；distinct digest 引用數 `grep -ohE 'sha256:[0-9a-f]{64}' ~/.akashic/entities/*.yaml | sort -u | wc -l`（41）；「其他機器上會是多少」的下限＝把 `sources/` 排除後複製一份再跑同一支 binary（41，全部 venue 加那筆 divergence）。**#507 落地後**（2026-09-04）那筆 URL 已補存 landing page 並改成 digest，本機重跑為 0。

**第 16 列的量測（2026-09-04；2026-09-26 改量檔案位元組，可重跑）**：warning 數 `LC_ALL=C grep -a -q 'venue 的記錄檔逼近讀取上限' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c 'venue 的記錄檔逼近讀取上限'`（應為 0；2026-09-26 前綴改名，舊前綴是「venue 的 verdict 數逼近 decode 預算」——量的已不是筆數）；最大檔 `ls -l ~/.akashic/entities/*.yaml | sort -k5 -n | tail -1`（2026-09-26：268,627 bytes，即 `psychological-methods`，1,352 筆 verdict）；門檻 `AliasEventBudget.recordFileWarningBytes`（4,194,304＝8 MiB÷2）。舊門檻 11,111 筆（200,000÷2÷9）量的是對 store 檔不生效的節點軸，已退場。

**第 19 列的量測（2026-09-09，可重跑）**：未被 bullet 引用的列數應為 0——`LC_ALL=C grep -a -q '沒有任何 bullet 講它' .build/debug/akashic-guards && .build/debug/akashic-guards zero-instance-rows-audit 2>&1 | grep -c '沒有任何 bullet 講它'`（用含這條檢查的 binary；同第 13 列的自證，舊 binary 印不出東西。`akashic-guards` 不裝進 PATH，只在 `swift build` 之後的 `.build/debug/`——#711 R1 之前這裡寫 `"$(command -v akashic-guards)"`，在沒有它的 PATH 上閘必然失敗、什麼都不印，與舊 binary 分不開。第 70、71 列一直寫這個路徑；第 20、21、51 列 #711 R2 起也改成它——R1 在這裡寫「第 20、21 列早就寫這個路徑」，那是錯的：
它們與第 51 列寫的都是 PATH 上沒有的裸 `akashic-guards`，R2 verify 第 24 列）。量測指令的寫法（自證閘、前置條件、判讀原則、認不出來的寫法）見規則 [`measurement-commands-self-prove`](../.claude/rules/measurement-commands-self-prove.md)；#711 R1–R4 寫在這裡的原文移到本文件最後一節。合模板的量測由下面這一行**棘輪**兜底（依 binary 與閘的片段去重後至少幾條，少於下限守衛就紅；新增量測之後把下限調高）：

<!-- zero-instance-rows-audit 棘輪：合模板的量測（依 binary 與閘的片段去重）至少 38 條 -->

手算對照：

```bash
python3 - <<'EOF'
import io, re
t = io.open('.claude/rules/zero-instance-guards.md', encoding='utf8').read()
rows = [int(n) for n in re.findall(r'^\| (\d+) \|', t, re.M)]
i = t.index('## 各列共通的東西'); sec = t[i:]
cited = set()
for m in re.finditer(r'^- 第 ([0-9、]+) 列的理由是', sec, re.M):   # 與守衛同一條規則
    cited.update(int(x) for x in m.group(1).split('、') if x.isdigit())
print(f'表列數 {len(rows)}  未被引用 {sorted(set(rows) - cited)}')
EOF
# 2026-09-09：表列數 19  未被引用 []
```

**第 11 列的量測（2026-09-09 重量，可重跑）**——**三個來源曾給出三個數**（issue body 90/14、裁決 comment 46/27、2026-09-03 verify 99 行／28 檔），而三者都沒寫**量法**，所以無從收斂。這裡把量法釘死：

```bash
# 量法：型別名 `Author` 的出現。`enum → struct` 是型別形狀的改變，
# 每一個提到這個型別的地方都可能要動（宣告、pattern match、建構、簽章）。
grep -rhoE '\bAuthor\b' Sources/ --include='*.swift' | wc -l          # 54  行
grep -rlE  '\bAuthor\b' Sources/ --include='*.swift' | wc -l          # 26  檔
grep -rhoE '\bAuthor\b' Sources/ Tests/ --include='*.swift' | wc -l   # 153 行（含測試）
grep -rlE  '\bAuthor\b' Sources/ Tests/ --include='*.swift' | wc -l   # 64  檔（含測試）
```

**不能用 `case .key`／`case .literal`／`case .organization` 數**（那大概是先前某個數字的來源）：實測 **五個** enum 共用這些 case 名——`Author`、`VenueRef`、`Organization` 的 ref、`OrgResolver` 的、以及 `AkashicProposition` 的 `EntityRef`。那樣數會把另外四個一起算進來（實測 102 行／29 檔，高估近一倍）。

**編譯器的精確值拿不到（誠實邊界）**：給 `Author` 加一個 case 再 build 是最精確的量法，但 SwiftPM **在第一個失敗的 module 就停**——實測只看得到 `AkashicCore` 的 2 個 exhaustive-switch 錯誤，下游 module 根本沒編到。要真值得逐 module 迭代修補再重編，那是另一件事。上面的文字量法是可重跑、可否證的替代，**不宣稱它等於編譯器的答案**。

**第 18 列的量測（2026-09-08，可重跑）**：上限值 `AddOnlyEnrichment.maxValueBytes`（65,536）；庫內最長值——**必須用 YAML 解析器，不能用行為單位的 grep**（長 value 會被折行，本檔第 13 列的量測就踩過同一個坑）：

```bash
python3 - <<'EOF'
import glob, io, os, yaml, collections
root = os.path.expanduser('~/.akashic/entities')
absn, alln = [], []
for f in glob.glob(root + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: continue
    if not isinstance(d, dict): continue
    for k, v in (d.get('fields') or {}).items():
        if not isinstance(v, str): continue
        alln.append(len(v.encode('utf8')))
        if k.startswith('abstract'): absn.append(len(v.encode('utf8')))
absn.sort(); alln.sort()
p = lambda L, q: L[min(len(L)-1, int(len(L)*q))] if L else 0
print(f'abstract n={len(absn)} p50={p(absn,.5)} p99={p(absn,.99)} max={absn[-1]}')
print(f'全部 fields 值 n={len(alln)} max={alln[-1]} → 餘裕 {65536/alln[-1]:.1f} 倍')
EOF
# 2026-09-08：abstract n=1517 p50=1137 p99=2185 max=4220 ／ 全部 n=6125 max=4220 → 15.5 倍
```

守衛本身是否在跑（自證：前面的閘同第 13 列；這條的期望值是 **1** 不是 0，所以它另有第二層——舊 binary 印不出東西，閘被拿掉的話舊 binary 印 **0**，與期望值也分得開。#711 R2 之前這裡只靠第二層、不加閘，行尾寫 `# 正對照`；R2 起每一條量測各自要有閘，正對照不再是另一種寫法。`STORE` 設成某個 store 的路徑；沒設或不是 store 時整條不跑——檢查寫在最前面的 `: "${STORE:?…}" && test -f …`（#711 R3 verify 第 17 列：
`--library ""` 等同沒傳，在這台機器上那是活的 store。R3 把檢查寫在 `--library "${STORE:?…}"` 裡、說那樣讓 shell 停下，其實只結束管線左邊那一段——
R4 verify 第 1、3、5 列）；沒有 `--apply` 是乾跑，這一筆又整批拒絕、零寫入。輸入檔用 `mktemp`，不寫可預測的
`/tmp/over.json`——共用的 `/tmp` 裡別人可以先放一個同名的 symlink）：

```bash
over=$(mktemp); python3 -c "import json;print(json.dumps([{'citekey':'x','fields':{'abstract':'a'*65537}}]))" > "$over"
: "${STORE:?先設 STORE 為要量的 store 的路徑}" "${over:?mktemp 失敗}" && test -f "$STORE/store.yaml" && LC_ALL=C grep -a -q '截斷會讓一個不是來源給的值進 store' "$(command -v akashic)" && "$(command -v akashic)" enrich --library "$STORE" --from "$over" --json 2>&1 | grep -c '超過上限'   # 應為 1
rm -f "$over"
```

**第 17 列的量測（2026-09-07，可重跑）**：兩種 warning 數 `LC_ALL=C grep -a -q '拆分後的孤兒 verdict' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c '拆分後的孤兒 verdict'` 與 `LC_ALL=C grep -a -q '拆分記錄的各段都已不在作者位' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c '拆分記錄的各段都已不在作者位'`（應皆為 0；用含這條檢查的 binary——同第 13 列的自證，舊 binary 印不出東西）；拆分記錄數 `grep -c '^  *- field: authors$' ~/.akashic/entities/*.yaml | awk -F: '{s+=$2} END {print s}'`（0——#443 已拆的 4 筆沒有記錄，不回填）；那 4 筆的下落 `grep -l '雷庚玲' ~/.akashic/entities/*.yaml | wc -l`（4 個檔含該姓名，其中的拆分無記錄可機械辨認）。

**第 20 列的量測（2026-09-09，可重跑）**：`.build/debug/akashic-guards workflow-run-scripts`（rc=0 時印
「workflow `run:` 引用的 N 個腳本全部存在」——2026-09-09 為 **5**；非零時逐條印出是哪個
workflow 的第幾行跑了哪個不在的檔）。workflow 檔數 `ls .github/workflows/*.yml | wc -l`（2）。
**自證同第 13 列**：舊 binary 沒有這個子命令會印 usage 而不是 0，兩者分得開。

**第 21 列的量測（2026-09-09，可重跑）**：差異數 `.build/debug/akashic-guards protected-ratchet`
（相符時印「受保護清單與棘輪相符：N 條」、rc=0；不符時逐條印「少了／多了」、rc=1；
棘輪檔不存在 rc=2——三種分得開）。清單條數 `wc -l < .githooks/protected-ratchet.txt`
（2026-09-09：58；2026-09-14 重跑：59；2026-09-27：70；2026-09-29（#629 移植後）：61）。**顯式 vs glob 的拆分**——顯式＝路徑字面出現在 `ProtectedInventory.swift` 裡的那些（受保護清單的單一來源，#522 起從 `TriggerCoverage.swift` 搬過去；#571 之前腳本仍在舊檔找，所以量到 2）：

```bash
python3 - <<'EOF'
import io
lines = [l for l in io.open(".githooks/protected-ratchet.txt", encoding="utf8").read().split("\n") if l]
src = io.open("Sources/akashic-guards/ProtectedInventory.swift", encoding="utf8").read()
explicit = [l for l in lines if f'"{l}"' in src]
print(f"受保護 {len(lines)}｜顯式字面 {len(explicit)}｜glob／衍生 {len(lines)-len(explicit)}")
EOF
# 2026-09-09：受保護 58｜顯式字面 21｜glob／衍生 37
# 2026-09-14 重跑：59｜2｜57——「顯式字面」從 21 掉到 2 不是計數誤差，`TriggerCoverage.swift` 的路徑字面寫法變了，
# 這個拆分判準已失效；本列理由欄的 37/58 與 19/19 隨之過期（#554 R9 verify 第 17／20 列，#571 另案重定量法）
# 2026-09-27（#571）：原因不是寫法變了，是**清單換了家**——#522 把它搬進 `ProtectedInventory.swift`，腳本還在舊檔找。
# 腳本改指新檔後重量：受保護 70｜顯式字面 22｜glob／衍生 48
# 2026-09-29（#629：十一個 shell／Python 守衛與測試移植成 Swift 或退場、兩個 Swift 守衛新增）重量：受保護 61｜顯式字面 18｜glob／衍生 43
```

**三組刪除實測**要在副本上做（複製 `plugin`／`.github`／`Sources`／
`.githooks`／`.claude/rules`／`CLAUDE.md`／`mcpb/manifest.json` 到暫存目錄，在那裡以 cwd 執行）
——顯式條目那一組另需重編 binary，因為守衛跑的是已編譯的那一份而不是原始碼。

**第 22 列的量測（2026-09-09，可重跑）**：

```bash
python3 - <<'EOF'
import glob, io, os, re
n = dated = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    t = io.open(f, encoding='utf8').read()
    if not t.startswith('venue:'): continue
    n += 1
    m = re.search(r'^names:\n((?:- .*\n|  .*\n)+)', t, re.M)
    if m and re.search(r'^\s+(start|end|ended|attested):', m.group(1), re.M): dated += 1
print(f"venue {n} 筆｜names 帶時間欄位 {dated} 筆")   # 2026-09-09：406 / 0；2026-09-14 重跑：485 / 0；2026-09-29 鍵改成 ended 後重跑：485 / 0
EOF
```

**第 23 列的量測（2026-09-09，可重跑）**：矛盾數 `LC_ALL=C grep -a -q '移除記錄與作者位互相矛盾' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c '移除記錄與作者位互相矛盾'`
（應為 0；用含這條檢查的 binary——同第 13 列的自證，舊 binary 印不出東西）；移除記錄總數
`grep -c '^  judgement: 移除：' ~/.akashic/entities/*.yaml | awk -F: '{s+=$2} END {print s+0}'`
（2026-09-09：**0**——`--drop-author` 尚未對 live store 執行，等 store format bump 到 17）。

**第 24 列的量測（2026-09-11 首量；2026-09-18 R2 改寫並重跑，可重跑）**：觸發條件見理由欄（R2 寫「情形欄」，指錯欄——R2 verify 第 12 列）——腳本印的五個數裡**重複群**與**含 org 候選的 divergence** 兩個要為零才維持「暫不做」；organization 總數與帶 `parents` 筆數是脈絡，不是觸發（R1 寫「三個數字都要為零、任一非零即重開」，對自己的基線 13／3 就是假的——R1 verify 第 5／9 列）；第五個數**讀不到或不是記錄的檔**是母體的誠實邊界——一個壞檔曾讓整支腳本 traceback、四個數一個都不印（R1 第 28 列的處置「同第 16 列」只兌現了解析那一半，R2 verify 第 9 列），而照抄第 18 列腳本的 `except: continue`（R3 寫「第 12 列」，那支根本沒有 try——R3 verify 第 10 列；第 18 列那支至今仍是靜默跳過，已知缺口：它量的是長度分布，少算一筆不改變 15.5 倍的結論）會把「零輸出」換成「安靜少算」；現在跳過並計數。**這個數與 `akashic validate` 的 quarantine 是有向的包含、不是相等**（R3 寫「對得起來」，R3 verify 第 1／3／12 列三席同指）：它只涵蓋 YAML 解不開與頂層不是 mapping，quarantine 另含解析得了但 schema 不合法的記錄（非 UUID 檔名、形狀標籤帶值……），那些檔**會被腳本算進前四個數**——所以 quarantine ≥ 這個數是常態；非零時去對 quarantine 清單，別追一個不存在的差。腳本的母體是磁碟上的 `.yaml`，binary 的母體是載入成功的記錄，兩邊的 org divergence 數在有 quarantine 檔時可以不同（方向是腳本多報）。目錄讀不到（新 clone、HOME 打錯）印一句具名的話後退出，不 traceback（R3 verify 第 16／19 列）。「含 org 候選的 divergence」那個數（R3 寫「第二個數」，照位置讀是重複群——R3 verify 第 13 列）自 R2 起由 binary 出聲：`LC_ALL=C grep -a -q '沒有合併管線' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c '^⚠ divergence .*歧異記錄的 shape 沒有合併管線：'`（應印 0；**沒印任何東西＝PATH 上的 `akashic` 是沒有這條檢查的舊 binary**——R3 的指令沒有這道閘，2026-09-18 實測 `~/bin/akashic` 就是舊的、照抄印 0 冒充乾淨，R3 verify 第 5 列；第 13 列的構造逐字搬過來。**行首錨 `^⚠ divergence `** 讓 store 內容偽造不了它：一個名字含這句話的 venue 會讓無錨的 grep 多算（R3 verify 第 18 列，實測 2 個假 venue 名字得 2），錨在 binary 自己印的前綴上就不會；**帶全形冒號**——它數的是逐則 warning，家族計數行用 ASCII 冒號；不帶冒號會把計數行也數進去、一筆記錄得 2，R2 verify 第 10 列 Codex）；理由欄那句 bootstrap 的重跑：`akashic bootstrap-organizations`（2026-09-18：無可自動建立的候選，另有 1 個產不出 key 的機構名待人工指定）。R1 的腳本對檔首註解與 `.YAML` 靜默漏算、`shape: organization` 是含空白的無錨點子字串、值不 `str()` 就當掉（R1 verify 第 16／26／28／29 列）——R2 改以 yaml 解析後看頂層鍵與 `candidates[].shape`；`key()` 是 `LooseTitleKey.key` 的鏡射，改一邊要同批改另一邊；固定案例的出處逐條寫（R2 寫「取自那個檔頭」，四條裡兩條不是——R2 verify 第 17 列）：JRSS 的三種標點寫法與 BJMSP 的 `&`／and 取自 `LooseTitleKey` 檔頭；`The Guilford Press`＝`Guilford Press` 取自 live store 的 venue `the-guilford-press`（names 同時有兩種寫法）；`Science`≠`Sciences` 是**負控**、取自 `identity-is-judged-not-matched`（所方正式名稱與 ScienceDirect 的誤植）。

```bash
python3 - <<'EOF'
import io, os, unicodedata, yaml, collections
# 鏡射 LooseTitleKey.key（NFKC → 丟 Cf → 小寫 → `&`→and → 標點折成空白 → 剝前導冠詞）——改一邊要同批改另一邊。
# 樸素鏡射的誠實邊界：連字號家族與空白在 scalar 上處理，Swift 在 grapheme cluster 上（第 27 列量測段記過同一件事）；機構名裡零實例。
ART = {"the","a","an"}
def key(s):
    s = unicodedata.normalize('NFKC', str(s))
    s = ''.join(c for c in s if unicodedata.category(c) != 'Cf').lower().replace('&', ' and ')
    s = ''.join(c if (c.isalnum() or c.isspace()) else ' ' for c in s)
    t = s.split()
    while t and t[0] in ART: t.pop(0)
    return ' '.join(t)
# 固定案例（出處見上方散文：前兩條取自 LooseTitleKey 檔頭、第三條取自 live store 的 venue、第四條是負控；寬鬆鍵不摺詞形——那是提名不是判定）
assert key('Journal of the Royal Statistical Society Series B: Statistical Methodology') == key('Journal of the Royal Statistical Society Series B (Statistical Methodology)') == key('JOURNAL OF THE ROYAL STATISTICAL SOCIETY SERIES B-STATISTICAL METHODOLOGY')
assert key('British Journal of Mathematical & Statistical Psychology') == key('British Journal of Mathematical and Statistical Psychology')
assert key('The Guilford Press') == key('Guilford Press')
assert key('Institute of Statistical Science') != key('Institute of Statistical Sciences')
root = os.path.expanduser('~/.akashic/entities')
g = collections.defaultdict(set); n = with_parents = org_div = unreadable = 0
try: names = sorted(os.listdir(root))
except OSError as e: raise SystemExit(f'讀不到 {root}：{e}——五個數一個都沒量')   # 目錄層也不 traceback（R3 verify 第 16／19 列）
for name in names:
    if name.startswith('.') or not name.lower().endswith('.yaml'): continue   # 鏡射 LibraryStore 的過濾：`.YAML` 也算、dotfile 不算（R3 verify 第 17 列）
    try: d = yaml.safe_load(io.open(os.path.join(root, name), encoding='utf8'))
    except Exception: unreadable += 1; continue                 # 壞檔不當掉也不靜默——計數印出來（R2 verify 第 9 列）；quarantine ⊇ 這個數，見上方散文
    if not isinstance(d, dict): unreadable += 1; continue        # 不是 mapping 的 YAML 不是記錄，同上
    if 'organization' in d:                                   # 頂層鍵判 shape，不看檔首那一行（檔首註解會讓 startswith 漏掉）
        n += 1
        if d.get('parents'): with_parents += 1
        names = d.get('names') or []
        for x in (names if isinstance(names, list) else []):
            nm = x.get('value') if isinstance(x, dict) else x
            if nm is not None and key(nm): g[key(nm)].add(str(d.get('key')))
    elif 'divergence' in d:
        if any(isinstance(c, dict) and c.get('shape') == 'organization' for c in (d.get('candidates') or [])):
            org_div += 1
dupes = len([k for k, v in g.items() if len(v) >= 2])
print(f"organization {n} 筆｜重複群 {dupes} 組｜含 org 候選的 divergence {org_div} 筆｜帶 parents {with_parents} 筆｜讀不到或不是記錄的檔 {unreadable} 個")
EOF
# 2026-09-11：organization 13 筆｜重複群 0 組｜含 org 候選的 divergence 0 筆｜帶 parents 3 筆
# 2026-09-18 R2 重跑（改寫後的腳本）：同——13／0／0／3
# 2026-09-18 R3 重跑（加第五個數）：13／0／0／3／0；R4 重跑（目錄閘、dotfile 過濾）：同。對帳：organization 總數 `grep -l '^organization:' ~/.akashic/entities/*.yaml | wc -l`（13）、
#   `akashic divergences --json` 唯一一筆的 shape 是 person。R2 曾寫「`akashic doctor` 的 organization 計數 13」——**doctor 沒有 organization 總數**，
#   它印的 `no authorized name: … / 13 organization` 是沒有 authorized name 的機構數，今天相等只因 13 筆全無 authorized name（R2 verify 第 8 列 DA）
```

**第 25 列的量測（2026-09-12，可重跑）**：venue 側名字內容的 error 應恆為 0——
`LC_ALL=C grep -a -q '求值總量' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c '^[^ ]* venue [^ ]*: venue .*\(canonical 形\|近重複\|同名段過多\|求值總量\|不是名字\|沒有名字\|格式或控制字元\|控制或方向控制\|不可見字元\|接合字元\)'`
（十個子串對應 `NameIdentity.wellFormednessIssue` 的七句訊息加 `Venue.validate()` 的近重複句、組內求值上限句「同名段過多」與整筆記錄的求值總量句——R5 的 grep 漏了空名的「沒有名字」，Python 對照卻算它，兩套量測分歧；R6 補齊並加不可見／接合字元兩類；R18 加兩類求值上限句、並排除概括句（R17 verify 第 11 列：R17 的概括句含「venue」與「近重複」，會被數成一則名字內容 error，而求值上限那一類完全數不到）。**這個數量的是訊息行數**：近重複一組最多 3 對、概括句不算、每筆記錄至多 20 組——與下方 Python 對照的「對數」在配額到頂時必然分岔，兩邊都是 0 時才是同一件事）
（用含這條檢查的 binary——同第 13 列的自證；注意 person 側另有 #296 的近重複 **warning**，
`grep 'venue'` 才不會把那些算進來）。Python 對照（不依賴 binary）：

```bash
python3 - <<'EOF'
import glob, io, os, re, unicodedata, yaml
# 鏡射 Swift 的 NameIdentity.wellFormednessIssue 與 Venue.validate() 的近重複掃描（改一邊要同批改另一邊）：
#  - canonical：NFC、只丟 White_Space（顯式集合——Python isspace() 把 U+001C–001F 也當空白，Swift 不會）、
#    內部空白串收成一個 U+0020
#  - 危險／不可見：Cc／Cf／Zl／Zp、Default_Ignorable_Code_Point（unicodedata 沒有 DI 屬性，用
#    DerivedCoreProperties 的區段列舉——UAX #44 的表，版本差異只在未指派碼位）、`rendersBlank` 的五個碼位
#  - ZWJ／ZWNJ 例外：(a) 前一個 scalar 是 virama（ccc 9）、從 virama 往前跳過標記找到的基底是字母、virama 與
#    跳過的標記都是基底那個文字的（D22）、右鄰居若在要是同一文字的字母／數字——右鄰居是空白視同沒有（多字刊名的
#    詞尾 chillu）；(b) 左鄰居是 join-control 文字的字母／標記／數字、右鄰居是同一文字的字母／數字，或同一 Indic
#    Devanagari／Bengali 的 virama 且其後接同文字的字母（Bengali ya-phalaa <RA, ZWJ, VIRAMA, YA>，D21／D26——
#    每個引用實例都是 <C, J, H, C>，沒有後續輔音的 joiner 是純隱形位元組差）（標點不算；joiner 自己也不算，所以連續 joiner 必拒）
#  - 至少一個字母或數字（generalCategory 的 L／N 類——Python 的 isalnum() 正是這個，不含 Other_Alphabetic 的標記）
#  - names 近重複豁免：兩段都作時間宣稱（`DateRange.makesTemporalClaim`：start／end 非空、ended 為 true、
#    或 attested 非空）、一段的 end 與另一段的 start 都是 ISO 8601 前綴（鏡射 `ISO8601Prefix.isValid`：ASCII 數字、
#    月 01–12、日 01–31）、且 end 以較粗粒度截斷後嚴格小於 start
DI = [(0x00AD,0x00AD),(0x034F,0x034F),(0x061C,0x061C),(0x115F,0x1160),(0x17B4,0x17B5),(0x180B,0x180F),
      (0x200B,0x200F),(0x202A,0x202E),(0x2060,0x206F),(0x3164,0x3164),(0xFE00,0xFE0F),(0xFEFF,0xFEFF),
      (0xFFA0,0xFFA0),(0xFFF0,0xFFF8),(0x1BCA0,0x1BCA3),(0x1D173,0x1D17A),(0xE0000,0xE0FFF),(0x2800,0x2800),
      (0x13441,0x13442),(0x16FE4,0x16FE4),(0x1D159,0x1D159)]   # 後三組：`UnsafeToEmitScalar.rendersBlank`（#569 R1 verify）
JOIN = [(0x0600,0x06FF,1),(0x0750,0x077F,1),(0x0870,0x089F,1),(0x08A0,0x08FF,1),(0xFB50,0xFDFF,1),(0xFE70,0xFEFF,1),(0x10EC0,0x10EFF,1),
        (0x0700,0x074F,2),(0x0860,0x086F,2),(0x0840,0x085F,3),(0x07C0,0x07FF,4),(0x1000,0x109F,5),(0x1780,0x17FF,6),
        (0x1800,0x18AF,7),(0x2D30,0x2D7F,8),(0x10D00,0x10D3F,9),(0x10F30,0x10F6F,10),(0x10F70,0x10FAF,11),(0x10AC0,0x10AFF,12),(0x1E900,0x1E95F,13),
        (0xA8E0,0xA8FF,100),(0x11B00,0x11B5F,100),(0xAA60,0xAA7F,5),(0xA9E0,0xA9FF,5)]   # R9：Devanagari／Myanmar 的補充區塊
def script(ch):   # 鏡射 NameIdentity.joinScript：同一文字的多個區塊同一 id；Indic 每 0x80 一個
    o = ord(ch)
    if 0x0900 <= o <= 0x0DFF: return 100 + (o - 0x0900) // 0x80
    return next((sid for a, b, sid in JOIN if a <= o <= b), None)
WSSET = {0x09,0x0A,0x0B,0x0C,0x0D,0x20,0x85,0xA0,0x1680,0x2028,0x2029,0x202F,0x205F,0x3000} | set(range(0x2000,0x200B))
inr = lambda c, R: any(a <= ord(c) <= b for a, b in R)
WS = lambda ch: ord(ch) in WSSET
JOINER = lambda ch: ch in '\u200c\u200d'
MARK = lambda ch: unicodedata.category(ch) in ('Mn','Mc')
VIRAMA = lambda ch: unicodedata.combining(ch) == 9
BASE = lambda ch: ch.isalnum()   # L 類或 N 類（isalnum 不含 Other_Alphabetic 的標記）
member = lambda ch: script(ch) is not None and (BASE(ch) or MARK(ch))   # (b) 支的左鄰居
def canon(s):
    s = unicodedata.normalize('NFC', s); out = []; pend = False
    for ch in s:
        if WS(ch): pend = bool(out); continue
        if pend: out.append(' '); pend = False
        out.append(ch)
    return ''.join(out)
def joiner_ok(s, i):
    p = s[i-1] if i > 0 else None; n = s[i+1] if i + 1 < len(s) else None
    if p is not None and VIRAMA(p):
        j = i - 2
        while j >= 0 and MARK(s[j]): j -= 1
        if j < 0 or script(s[j]) is None or not s[j].isalpha(): return False
        sc = script(s[j])
        if any(script(ch) != sc for ch in s[j+1:i]): return False   # virama 與跳過的標記同文字（D22）
        if n is None or WS(n): return True                          # 詞尾——含「後面是空白」
        return script(n) == sc and BASE(n)
    if p is None or n is None or script(p) is None or script(n) != script(p): return False
    if member(p) and BASE(n): return True
    # D21／D26：virama 之前的 joiner——只在 Devanagari（100）／Bengali（101），且 virama 之後要接同文字的字母
    if not (member(p) and VIRAMA(n) and script(p) in (100, 101) and i + 2 < len(s)): return False
    c = s[i+2]; return script(c) == script(p) and c.isalpha()
def issue(s):
    c = canon(s)
    if not c: return '空白'
    if s != c: return 'canonical'
    for i, ch in enumerate(s):
        if JOINER(ch):
            if not joiner_ok(s, i): return '接合字元'
            continue
        if inr(ch, DI): return '不可見'
        if unicodedata.category(ch) in ('Cc','Cf','Zl','Zp'): return '控制'
    if not any(ch.isalnum() for ch in s): return '無字母數字'
    return None
ISO = re.compile(r'[0-9]{4}(-(0[1-9]|1[0-2])(-(0[1-9]|[12][0-9]|3[01]))?)?')   # 鏡射 ISO8601Prefix.isValid：ASCII、月 01–12、日 01–31，不驗日曆
def before(end, start):   # 鏡射 Venue.segmentsAreDisjoint 的 before；PyYAML 會把 1933 讀成 int、2003-01-15 讀成 date，先 str()
    if end is None or start is None: return False
    end, start = str(end), str(start)
    if not (ISO.fullmatch(end) and ISO.fullmatch(start)): return False
    n = min(len(end), len(start)); return end[:n] < start[:n]
def well_formed(x):   # 鏡射 Venue.segmentIsWellFormed（R12）：在場的端點都是 ISO 前綴、且 start 以較粗粒度截斷後 ≤ end——倒置區間不解鎖豁免
    s, e = x.get('start'), x.get('end')
    if any(p is not None and not ISO.fullmatch(str(p)) for p in (s, e)): return False
    if s is not None and e is not None:
        s, e = str(s), str(e); n = min(len(s), len(e))
        if s[:n] > e[:n]: return False
    return True
def disjoint(a, b): return well_formed(a) and well_formed(b) and (before(a.get('end'), b.get('start')) or before(b.get('end'), a.get('start')))
dated = lambda x: (x.get('start') is not None or x.get('end') is not None   # 鏡射 DateRange.makesTemporalClaim
                   or x.get('ended') is True or bool(x.get('attested')))
def near_dup(a, b):   # a、b 是 names 段（dict）
    if canon(str(a['value'])) != canon(str(b['value'])): return False
    return not (dated(a) and dated(b) and disjoint(a, b))
# 固定案例：Swift 測試（VenueNameInvariantTests）的同一組，兩邊答案要一致
fixed = {'Psychometrika':None, '1843':None, 'نشریه\u200cروان':None, '۱۴۰۰\u200cها':None, 'ന്\u200d':None, 'क्\u200dष':None,
         'ࡀ\u200dࡁ':None, '\U0001E900\u200c\U0001E901':None, 'क़्\u200dष':None, 'بَ\u200cب':None,
         'Journal \u0967\u094d\u200d':'接合字元', 'क्\u200cA':'接合字元', 'ک\u200cक':'接合字元',
         'ا\u200c\u064eب':'接合字元', '\u064e':'無字母數字', '\u0640':None,
         # R9：D22（virama／標記同文字、詞尾含空白）、D21（Indic virama 之前的 joiner）、補充區塊
         'ک\u094d\u200d':'接合字元', 'क\u09cd\u200dष':'接合字元', 'क\u09bc\u094d\u200dष':'接合字元', 'क\u093c\u094d\u200dष':None,
         'അവന്\u200d വന്നു':None, 'ত্\u200d ব':None, 'ب\u200c ب':'接合字元',
         'র\u200d\u09cdযাব':None, 'क\u200d\u094dष':None, 'ক\u200c\u09cdষ':None, '\u1000\u200d\u1039\u1000':'接合字元',
         'ក\u200d\u17d2ត':'接合字元', 'क\u200d\u09cdष':'接合字元', 'A\u200d\u094dष':'接合字元',
         'क्\u200d\ua8fb':None, '\uaa60\u200d\uaa61':None, '\ua9e0\u200c\ua9e1':None,
         # R10：D26——virama 之後要接同文字的字母、只收 Devanagari／Bengali
         'क\u200d\u094d':'接合字元', 'क\u200c\u094d':'接合字元', 'क\u200c\u094dJournal':'接合字元', 'Journal क\u200d\u094d':'接合字元',
         'র\u200d\u09cd':'接合字元', 'क\u200d\u094d\u0967':'接合字元', 'क\u200d\u094d\u093e':'接合字元', 'क\u200d\u094d ष':'接合字元',
         'ல\u200d\u0bcdல':'接合字元', 'ക\u200d\u0d4dക':'接合字元', 'Journal क\u200d\u094dष':None,
         'Psycho\u200cmetrika':'接合字元', 'Zwj\u200d':'接合字元', 'A\u200c،B':'接合字元', 'ک\u200cA':'接合字元',
         'ا\u200c\u200cب':'接合字元', 'Psychometrika्\u200d':'接合字元',
         '心\ufe0f理學報':'不可見', '\u3164':'不可見', 'Psychometrika\u2800':'不可見',
         'Psycho\u200bmetrika':'不可見', 'Psychometrika\u202e':'不可見', 'A\x1cB':'控制',
         'Psychometrika ':'canonical', '×':'無字母數字', '':'空白'}
mism = [(k, issue(k), v) for k, v in fixed.items() if issue(k) != v]
assert not mism, mism
S = lambda **kw: dict(value='Sankhyā', **kw)
dup_cases = [((S(start='1933',end='1960'), S(start='2002',end='2007')), False),
             ((S(start='1933',end='1960'), S(start='1950')), True),
             ((S(start='1933',end='1960'), S()), True),
             ((S(start='1933',end='1960'), S(start='1960-06')), True),
             ((S(start='1933',end='1960'), S(start='1960')), True),
             ((S(attested=['1950']), S(attested=['2005'])), True),
             ((S(start='1933',end='1960-12'), S(start='1961')), False),
             ((S(start='1933',end='2003-01'), S(start='2003-1')), True),
             ((S(start='1933',end='1960-10'), S(start='1960-9')), True),
             ((S(start=1933,end=1960), S(start=2002,end=2007)), False),
             # R9：ISO 鏡射 isValid（月 13、非 ASCII 數字都不是端點）、dated 鏡射 makesTemporalClaim
             ((S(start='1933',end='1960-13'), S(start='1961')), True),
             ((S(start='1933',end='١٩٦٠'), S(start='2002')), True),
             ((S(start='1933',end='1960'), S(ended=False)), True),
             ((S(start='1933',end='1960'), S(attested=[])), True),
             ((S(start='1933',end='1960'), S(start='1961', ended=True)), False),
             # R12：區間本身要有效（R11 verify Codex 第 3 列）——倒置、或未參與比較的端點不是 ISO，都不豁免
             ((S(start='2000',end='1900'), S(start='1950',end='1960')), True),
             ((S(start='民國49',end='1960'), S(start='1961',end='1970')), True),
             ((S(start='1960',end='1960-06'), S(start='1961')), False)]
bad_dup = [(a, b, got, want) for (a, b), want in dup_cases if (got := near_dup(a, b)) != want]
assert not bad_dup, bad_dup
n=bad=dup=0
for f in glob.glob(os.path.expanduser('~/.akashic/entities')+'/*.yaml'):
    t=io.open(f,encoding='utf8').read()
    if not t.startswith('venue:'): continue
    n+=1; d=yaml.safe_load(t)
    segs=[x if isinstance(x,dict) else {'value': x} for x in (d.get('names') or [])]
    names=[str(x['value']) for x in segs]
    for lst in (names, d.get('authorized') or [], d.get('variant') or []):
        for s in lst:
            if issue(str(s)) is not None: bad+=1
    for i in range(len(segs)):
        for j in range(i+1, len(segs)):
            if near_dup(segs[i], segs[j]): dup+=1
    for lst in (d.get('authorized') or [], d.get('variant') or []):
        ks=[canon(str(s)) for s in lst]
        if len(ks)!=len(set(ks)): dup+=1
print(f"venue {n}｜違反不變式的字串 {bad}｜近重複對 {dup}")   # 2026-09-14：485 / 0 / 0（R10 重跑仍是）
EOF
```

**第 26 列的量測（2026-09-14，可重跑）**：warning 數 `LC_ALL=C grep -a -q '條邊指向同一 venue' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c '條邊指向同一 venue'`（應為 0；用含這條
檢查的 binary——同第 13 列的自證，舊 binary 印不出東西；R15 起每筆 work 最多列 20 個 venue、其餘一句概括——概括句自 R16 起前綴
`則數已達上限`、不含這個子串也不進家族，所以這個數與 `StoreHealth.duplicateVenueEdges` 都是「受影響數，至多每筆 20」，R15 verify 第 18／29 列）。Python 對照（不依賴 binary；`work:` 檔的 `venues` 裡 `key:` 出現兩次以上）：

```bash
python3 - <<'EOF'
import glob, io, os, re, collections
n = dup = multi = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    t = io.open(f, encoding='utf8').read()
    if not t.startswith('work:'): continue
    n += 1
    m = re.search(r'^venues:\n((?:- .*\n|  .*\n)+)', t, re.M)
    if not m: continue
    keys = re.findall(r'^- key: (.+)$', m.group(1), re.M)
    edges = len(re.findall(r'^- ', m.group(1), re.M))
    if edges > 1: multi += 1
    if len(keys) != len(set(keys)): dup += 1
print(f"work {n} 筆｜>1 條 venue 邊 {multi} 筆｜同 venue 兩條 key 邊 {dup} 筆")   # 2026-09-14：2411 / 3 / 0
EOF
```

**第 27 列的量測（2026-09-15，可重跑；R15 分兩類、R16 對齊位元組）**：warning 數 `LC_ALL=C grep -a -q '個正規化後不同的 confirmed literal' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c '個正規化後不同的 confirmed literal'`
與 `LC_ALL=C grep -a -q '筆只差位元組的 confirmed literal' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c '筆只差位元組的 confirmed literal'`（應皆為 0；用含這條檢查的 binary——同第 13 列的自證，舊 binary 印不出東西；
家族總數 `LC_ALL=C grep -a -q '同一 work 多個 confirmed literal' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c '同一 work 多個 confirmed literal'`——R16 起**不含**概括句（它的前綴是 `則數已達上限`），所以家族總數＝
受影響的 work 數、至多每筆 venue 20；**兩類不是互斥分割**（R15 verify 第 23 列）：一筆 work 三個 literal、其中兩個只差位元組時只出第一類、訊息尾
附「另有 1 筆只差位元組的重複記錄」，第二類的 grep 不算它；`grep -c '只差位元組'` 數的是**含位元組重複的訊息行數**、不是組數——一則第一類
訊息最多點名 5 組（第 6 組起以「…共 N 組」揭露）、一則第二類訊息涵蓋一筆 work 的全部拼法；真要數「work 對」用下方鏡射的 `bytes_only`，
組數目前沒有 CLI 指令能數（R16 verify requirements 第 11 列、logic 第 14 列）。Python 對照（不依賴 binary；鏡射
`NameNormalization.matchingKey`——改一邊要同批改另一邊。**鏡射的兩處已知差異在 R15 對齊**（R14 verify logic 第 17 列、DA 第 23 列、
regression 第 30 列）：空白類用 Unicode 的 `White_Space` 集合（R15 當時 Swift 走 `Character.isWhitespace`；#574 起改在 scalar 上看 `properties.isWhitespace`，集合相同），不用 Python `str.split()`（它把 U+001C–001F 也當空白
——store 內不可達，但同檔第 25 列早就顯式列舉了）；連字號家族在 **grapheme cluster** 上比（Swift 的 `hyphenFamily.contains(Character)`）
——連字號後面跟著組合符號時整個 cluster 不在家族裡、**不**取代，DA 實測 `A-\u0301B` 與 `A\u2010\u0301B` 在 Swift 是兩個鍵而 R14 的鏡射判成一個。
**R16 再對齊兩處**（R15 verify logic 第 9／11 列、DA 第 24 列；Claude 代裁 D46，2026-09-16 用逐字複製的 `matchingKey` 探針量過）：(1) 空白也在
Character 上切——**機制是 grapheme 分群，不是 `isWhitespace` 讀幾個 scalar**（R17 更正，R16 verify DA 第 10 列：R16 寫成「只看第一個 scalar」，
鏡射照著無條件吞，60,033 例差分裡 2,967 例源於此）：U+0020 與其他 Zs 類空白（NFKC 後大多已折成 U+0020；U+1680 仍是 Zs）後面的組合符號依
GB9 併進同一個 cluster，`split(whereSeparator: \.isWhitespace)` 看到的是一個 `isWhitespace` 為 true 的 Character、**整個丟掉**、組合符號一起消失
（`A \u0301B` → `a b`；`canonical` 自 R6 起在 scalar 上切、不會這樣——`matchingKey` 這個資料損失另案 **#574**，鏡射照現況鏡射，修那條時要同批改這裡——**#574 已於 2026-09-27 修掉**：`matchingKey` 改在 scalar 上切，任何空白後面的組合符號都保留；下方鏡射與固定案例同批改。改之前量過 live store 202,139 個字串值，key 會變的 0 個）；
而 TAB／LF／VT／FF／CR／NEL／LS／PS 在 GCB 屬 **Control**，依 GB4 後面一定斷開，組合符號自成 cluster、**保留**（`A\t\u0301B` → `a \u0301b`）——
2026-09-16 探針對 `White_Space` 的 25 個碼位逐一量過，8 個是這一類（GCB Control）、17 個是 Zs（其中 U+2000–200A 的 11 個 NFKC 先折成 U+0020，落同一分支）——R17 曾寫「全部 14 個裡 8 個」，那是把 U+2000–200A 漏掉之後的數（R17 verify DA 第 10 列；同一份檔案第 25 列的 `WSSET` 自己就是 25 個），#574 的更正 comment 同批改；
(2) 連字號後接 ZWJ／ZWNJ 也是同一個 cluster（Grapheme_Extend）、不取代，之後 Cf 才被刪（`A\u2010\u200DB` → `a\u2010b`）。鏡射只認 M 類與
ZWJ／ZWNJ 當 extender——Swift 的 grapheme 規則另收 U+FF9E／FF9F（Lm）與 emoji modifier（Sk）等，刊名裡零實例，記為鏡射的誠實邊界（第 24 列）；
`lowercased()` 與 Python `lower()` 對特殊大小寫（İ、ß）的差異同屬邊界；**NFKC 那一步本身也有一處差異**（DA 第 10 列）：Foundation 的
`precomposedStringWithCompatibilityMapping` 對 `0301 FF9F 0BCD` 不做 canonical reordering（輸出 `0301 309A 0BCD`），ICU／Python 會——這個差分發生在任何
clustering 之前、修 clustering 收斂不了，同屬邊界）：

```bash
python3 - <<'EOF'
import glob, io, os, re, unicodedata, yaml
# 鏡射 NameNormalization.matchingKey：NFKC → 連字號家族（整個 grapheme cluster 恰為一個連字號才算：後接 M 類、ZWJ、ZWNJ 都不算）→ '-'
# → 刪 Cf → 小寫 → White_Space 收斂為單一空格（顯式集合，與第 25 列的 WSSET 同一份定義；在 **scalar** 上切，只丟空白、不刪其他 scalar
# ——#574 起。之前 Swift 在 Character 上切，Zs 類空白後面的組合符號隨 cluster 一起被丟，這裡曾照那個行為鏡射）
HY = set('\u2010\u2011\u2012\u2013\u2014\u2015\u2212')
WS = {0x09,0x0A,0x0B,0x0C,0x0D,0x20,0x85,0xA0,0x1680,0x2028,0x2029,0x202F,0x205F,0x3000} | set(range(0x2000,0x200B))
MARK = lambda c: unicodedata.category(c).startswith('M')
def mk(s):
    s = unicodedata.normalize('NFKC', s)
    out = []
    for i, c in enumerate(s):
        nxt = s[i+1] if i + 1 < len(s) else ''
        extended = bool(nxt) and (MARK(nxt) or nxt in '\u200c\u200d')   # 同一個 grapheme cluster（R16：ZWJ／ZWNJ 也是 extender）
        out.append('-' if (c in HY and not extended) else c)
    s = ''.join(c for c in out if unicodedata.category(c) != 'Cf').lower()
    toks, cur, i = [], '', 0
    while i < len(s):
        c = s[i]
        if ord(c) in WS:
            if cur: toks.append(cur); cur = ''
            i += 1
            continue
        cur += c; i += 1
    if cur: toks.append(cur)
    return ' '.join(toks)
# 固定案例（與 Swift 同一組期望；R15 起，R16 加三個——2026-09-16 用逐字複製的 matchingKey 探針逐一量過）：
assert mk('Chang, Y\u2010H.') == mk('Chang, Y-H.')            # 連字號家族
assert mk('A-\u0301B') != mk('A\u2010\u0301B')                # 連字號後接組合符號：cluster 不在家族裡，不取代（DA 第 23 列）
assert mk('Fann,  C.') == mk('Fann, C.') == mk('Fann,\tC.')    # 空白收斂
assert mk('Fann, C.\u200b') == mk('Fann, C.')                  # Cf 刪除
assert mk('A\u001fB') == 'a\u001fb'                            # U+001F 不是 White_Space（Python str.split 會切）
assert mk('A \u0301B') == 'a \u0301b'                          # #574 起空白後的組合符號保留（之前整個 cluster 被丟，R15 verify logic 第 9 列）
assert mk('A\u2010\u200dB') == 'a\u2010b'                      # 連字號＋ZWJ 是一個 cluster、不取代，ZWJ 隨後被當 Cf 刪掉（logic 第 11 列）
assert mk('A\u00a0\u0301B') == 'a \u0301b'                     # NBSP 經 NFKC 成空格，同上
assert mk('A\t\u0301B') == 'a \u0301b'                          # TAB：一直都保留；#574 起與 Zs 類空白一致
assert mk('A\u2028\u0301B') == 'a \u0301b'                      # LS 同上
n = flagged = pairs = bytes_only = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    t = io.open(f, encoding='utf8').read()
    if not t.startswith('venue:'): continue
    n += 1
    d = yaml.safe_load(t)
    by = {}
    for r in d.get('references') or []:
        if r.get('field') != 'resolution-confirmed': continue
        m = re.match(r'^work:(\S+) :: (.*)$', str(r.get('value', '')), re.S)
        if not m: continue
        by.setdefault(m.group(1), {}).setdefault(m.group(2), mk(m.group(2)))   # 位元組相異的 literal → 鍵
    bad = [w for w, lits in by.items() if len(set(lits.values())) > 1]
    dup = [w for w, lits in by.items() if len(lits) > 1 and len(set(lits.values())) == 1]
    if bad: flagged += 1; pairs += len(bad)
    bytes_only += len(dup)
print(f"venue {n} 筆｜對同一 work 持 ≥2 個正規化後不同 confirmed literal 的 venue {flagged} 筆（work 對 {pairs} 個）｜只差位元組的 work 對 {bytes_only} 個")   # 2026-09-15：485 / 0（0）/ 0
EOF
```

**第 28 列的量測（2026-09-16，可重跑）**：`LC_ALL=C grep -a -q '重複的判定記錄' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c '重複的判定記錄：'`（應為 0；用含這條檢查的 binary——同第 13 列的自證，
舊 binary 印不出東西；**帶冒號**——概括句的正文也含這六個字但接「；」，R24 verify 第 7 列，與第 27 列量測段修過的同一個錯；一則訊息＝一筆記錄的一個配對，
同一記錄兩個配對各有重複時是兩則，被截時是下限）。**D65 的量測（2026-09-17，R24）**：live store 8,671 筆 `value:` 行，以 NFC 正規化後計數的重複 **0** ＝
以原字串計數的重複 **0**——兩數相等即今天沒有只差 NFC／NFD 的配對，換鍵不改變任何既有記錄的意義（重跑：對每檔 `value:` 行各用 `unicodedata.normalize('NFC', v)`
與 `v` 各算一次 `Counter`，比較兩個重複數）。Python 對照要鏡射 `verdictEqualityKey`（field ＋ `kind:holder`
＋ `matchingKey(literal)`）——第 27 列的量測段已有 `mk()` 那份鏡射，以 (檔, field, `kind:holder`, `mk(literal)`) 分組、數 ≥2 的組即可，這裡不複製第二份。
同日順帶量的另一個數（D63 的立案理由）：live store 8,692 筆 verdict value 裡 **2 筆**被 emitter 折在 ` :: ` 之前——R22 的行級 needle 對它們永遠不命中。

**第 29 列的量測（2026-09-18，R33 重量，可重跑）**：`swift test --filter SanitizationBoundaryTests/testEverySinkBoundIsWithinTheInputCeiling`（四族各有地板，空掃描不是通過；第四族地板 0，它不撐任何東西）。Python 對照（不依賴 build；R32 的版本寫著 18／3 而腳本自己跑出 39／5——下面的期望值是 R33 實跑的）：

```bash
python3 - <<'EOF'
import re, glob, io
CEIL = 4096
fams = {'displaySafeError(max:)': r'displaySafeError\([^,)]+,\s*max:\s*([0-9_]+)\)',
        'displaySafeClipOnly(max:)': r'displaySafeClipOnly\((?:[^()]|\([^()]*\))*,\s*max:\s*([0-9_]+)\)',
        'sink 宣告的預設值': r'maxLineLength:\s*Int\s*=\s*([0-9_]+)',           # 生產者的 `max: Int = 200` 不在此族（R33）
        '呼叫端字面的 maxLineLength:': r'maxLineLength:\s*([0-9_]+)\b'}          # 零實例、地板 0
for name, pat in fams.items():
    ns = [int(m.replace('_','')) for f in glob.glob('Sources/**/*.swift', recursive=True)
          for m in re.findall(pat, re.sub(r'//.*', '', io.open(f, encoding='utf8').read()))]
    print(f"{name}: 站點 {len(ns)}｜最大 {max(ns) if ns else 0}｜超過 ceiling {sum(n > CEIL for n in ns)}")
EOF
# 2026-09-18（R33 實跑，HEAD 58bab46d）：displaySafeError(max:) 57｜4096｜0 ／ displaySafeClipOnly(max:) 39｜4096｜0 ／ sink 宣告的預設值 3｜400｜0 ／ 呼叫端字面 0｜0｜0
# R32 在這裡寫的是 18／3——腳本沒變、數字是抄錯的（R32 verify 第 3／10 列）；Swift 守衛的 `strippingLineComments` 比這裡的 `//.*` 保守，兩邊只會 ≥ 這些數
```

**第 30 列的量測（2026-09-25，可重跑）**：

```bash
python3 - <<'EOF'
import glob, io, os, yaml
mx = rmx = n = und = bad = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue          # 不靜默少算（第 24 列記過同形）
    if not isinstance(d, dict): bad += 1; continue
    for r in d.get('references') or []:
        if not isinstance(r, dict): continue
        n += 1
        if r.get('field') == 'resolution-undecided': und += 1
        j = r.get('judgement') or ''
        if isinstance(j, str): mx = max(mx, len(j.encode()))
        ro = r.get('rests-on') or []
        if isinstance(ro, list): rmx = max(rmx, len(ro))
print(f"reference {n}｜最長理由 {mx} 位元組（上限 4096；含 [rule: …] 尾註）｜rests-on 最多 {rmx}（上限 20）｜未決 {und}｜讀不到的檔 {bad}")
EOF
# 2026-09-25：reference 8747｜最長理由 687 位元組｜rests-on 最多 3｜未決 0
```

**第 31 列的量測（2026-09-26 改量檔案位元組，可重跑）**：warning 數 `LC_ALL=C grep -a -q 'person／organization 的記錄檔逼近讀取上限' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c 'person／organization 的記錄檔逼近讀取上限'`（應印 0；沒印任何東西＝舊 binary，同第 13 列的自證）。Python 對照量的就是工具比的那個數——記錄檔的位元組（讀不到的檔計數，同第 24 列）：

```bash
python3 - <<'EOF'
import glob, io, os, yaml
best = {'person': (0, ''), 'organization': (0, '')}; n = {'person': 0, 'organization': 0}; bad = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    for k in best:
        if k in d:
            n[k] += 1; size = os.path.getsize(f)
            if size > best[k][0]: best[k] = (size, str(d.get('key')))
print(n, '最大檔 bytes', best, '讀不到的檔', bad, '門檻 4194304')
EOF
# 2026-09-26：person 4575（最大 10869 bytes，chen-chien-hsiun）、organization 13（最大 717 bytes）｜讀不到 0
```

**第 32 列的量測（2026-09-26，可重跑）**：新 binary 對 live store 的 `akashic validate` rc 應為 0、沒有新的隔離（非 ASCII 號在載入時會被隔離）。
**這一句分不出新舊 binary**（#711 R4 verify 第 9 列）：#589 沒有加新訊息——全形號落進既有的「不是合法的 ISSN」——而 live store 沒有非 ASCII 號，
舊 binary 對它同樣 rc=0、零隔離。分得出來的是一份一次性的 fixture：在空的 store 上以全形號建 venue，新 binary 拒絕（印 1），#589 之前的 binary
收下它（印 0——推論自上面記的 `idCompact` 行為：全形數字過得了 mod-11，「不是合法的 ISSN」這則訊息 #589 之前就有，所以閘照樣成立；沒有拿舊 binary 實跑）。

```bash
fx=$(mktemp -d) && "$(command -v akashic)" doctor --library "$fx" > /dev/null   # 一次性的空 store，不是要量的那一份（`&&`：mktemp 失敗時 `--library ""` 會落到預設的 store）
: "${fx:?mktemp 失敗}" && test -f "$fx/store.yaml" && LC_ALL=C grep -a -q '不是合法的 ISSN' "$(command -v akashic)" && "$(command -v akashic)" add-venue zi-fullwidth --library "$fx" --names Fullwidth --type periodical --issn "００３３-３１２３" 2>&1 | grep -c '不是合法的 ISSN'   # 應為 1（2026-10-05：1）
rm -r "${fx:?}"
```

Python 對照（用 YAML 解析，不用行級 grep——長 value 會折行）：

```bash
python3 - <<'EOF'
import glob, io, os, yaml
n = bad = unreadable = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: unreadable += 1; continue
    if not isinstance(d, dict): unreadable += 1; continue
    for key in ('issn', 'orcid', 'isbn'):      # store 檔是扁平 mapping（形狀標籤與欄位同層），只掃一次（R1 verify：上一版掃兩次）
        v = d.get(key)
        vals = [x.get('value') if isinstance(x, dict) else x for x in v] if isinstance(v, list) else ([v] if v is not None else [])
        for x in vals:
            n += 1
            if any(ord(c) > 127 for c in str(x)): bad += 1
    dois = d.get('doi') or []                   # doi 是清單（一筆作品可以有多個 DOI）
    for x in (dois if isinstance(dois, list) else [dois]):
        if any(ord(c) > 127 for c in str(x).split('/', 1)[0]): bad += 1  # DOI 註冊者段（R1 起同形）
print(f"issn／orcid／isbn 值 {n}｜非 ASCII（含 DOI 註冊者）{bad}｜讀不到的檔 {unreadable}")
EOF
# 2026-09-26（R1 重量）：141｜0｜0（另數了 2,445 個 DOI）
```

**第 33 列的量測（2026-09-26，可重跑）**：`LC_ALL=C grep -a -q '團體作者 key「' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c '團體作者 key「'` 與 `LC_ALL=C grep -a -q '沒有對應的 venue 檔' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c 'venue key「.*」沒有對應的 venue 檔'`（#669 起 `venue key「…」重複` 也用這個前綴，所以錨在後半句；用含這條檢查的 binary——同第 13 列的自證，舊 binary 印不出東西；2026-09-26：2 與 0）。

**第 34 列的量測（2026-09-27，可重跑）**：`LC_ALL=C grep -a -q '位 person 引用' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c '隸屬 key「'` 與 `LC_ALL=C grep -a -q '上級機構 key「' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c '上級機構 key「'`（用含這條檢查的 binary——同第 13 列的自證，舊 binary 印不出東西；閘的片段取那則訊息裡 ≥16 位元組字面段的一段、不取被數的樣式——短的字面段在 release 版找不到，#711 R1，見第 19 列的量測段）。Python 對照（不依賴 binary；讀不到的檔計數，同第 24 列）：

```bash
python3 - <<'EOF'
import glob, io, os, yaml
root = os.path.expanduser('~/.akashic/entities')
orgs, affs, parents, bad = set(), [], [], 0
for f in glob.glob(root + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'organization' in d:
        orgs.add(str(d.get('key')))
        parents += d.get('parents') or []
    elif 'person' in d:
        affs += (d.get('profile') or {}).get('affiliations') or []
def keyed(s):   # `- value: {key: X}` 是 .key；`- value: 名稱` 是 .literal
    v = s.get('value') if isinstance(s, dict) else None
    return str(v['key']) if isinstance(v, dict) and 'key' in v else None
da = sorted({k for s in affs if (k := keyed(s)) and k not in orgs})
dp = sorted({k for s in parents if (k := keyed(s)) and k not in orgs})
print(f"organization {len(orgs)}｜懸空的隸屬 key {len(da)} {da}｜懸空的上級機構 key {len(dp)} {dp}｜讀不到的檔 {bad}")
EOF
# 2026-09-27：organization 13｜懸空的隸屬 key 0 []｜懸空的上級機構 key 0 []｜讀不到的檔 0
```

**第 35 列的量測（2026-09-27，可重跑）**：`LC_ALL=C grep -a -q '重複的 reference' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c '重複的 reference：'`（用含這條檢查的 binary——同第 13 列的自證；**帶全形冒號**，否則會把計數行也數進去）。Python 對照（不依賴 binary；逐欄 NFC 等於 Swift `String` 的 canonical equivalence）：

```bash
python3 - <<'EOF'
import glob, io, os, unicodedata, yaml
VERDICT = {'resolution-confirmed', 'resolution-rejected', 'resolution-undecided'}
def key(o, norm):
    if isinstance(o, dict): return tuple(sorted((k, key(v, norm)) for k, v in o.items()))
    if isinstance(o, list): return tuple(key(v, norm) for v in o)
    return None if o is None else (unicodedata.normalize('NFC', str(o)) if norm else str(o))
# 名字分類記錄（#564）是有順序的歷史：只數同一個名字同一個分割裡相鄰而相等的（鏡射 `classificationRuns`；名字的 canonical 以 NFC＋空白收斂近似）
def classification(r):
    j = r.get('judgement')
    return r.get('field') in ('authorized', 'variant') and r.get('value') is not None and isinstance(j, str) and j.startswith(('指定：', '確認：', '撤回：'))
refs = groups = variant = runs = bad = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    by, last = {}, {}
    for r in d.get('references') or []:
        if not isinstance(r, dict) or r.get('field') in VERDICT: continue
        if classification(r):
            g = (r['field'], ' '.join(unicodedata.normalize('NFC', str(r['value'])).split()))
            runs += last.get(g) == key(r, True)
            last[g] = key(r, True)
            continue
        refs += 1
        by.setdefault(key(r, True), []).append(key(r, False))
    for spellings in by.values():
        if len(spellings) > 1:
            groups += 1
            variant += len(set(spellings)) > 1
print(f"非判定 reference {refs}｜重複組 {groups}（其中只差位元組 {variant}）｜名字分類記錄相鄰相等 {runs}｜讀不到的檔 {bad}")
EOF
# 2026-09-27：非判定 reference 90｜重複組 0（其中只差位元組 0）｜讀不到的檔 0
# 2026-10-05（#564 b34：名字分類記錄改成只數相鄰相等，鏡射 `classificationRuns`）：非判定 reference 90｜重複組 0（其中只差位元組 0）｜名字分類記錄相鄰相等 0｜讀不到的檔 0
```

**第 36 列的量測（2026-09-27，可重跑）**：`LC_ALL=C grep -a -q '一個 ISSN 只屬於一本刊' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c '掛在 .* 個 venue 上'`（用含這條檢查的 binary——同第 13 列的自證，舊 binary 印不出東西；閘的片段取那則訊息裡 ≥16 位元組字面段的一段、不取被數的樣式——短的字面段在 release 版找不到，#711 R1，見第 19 列的量測段）。Python 對照（不依賴 binary；正規形＝去掉連字號、大寫；讀不到的檔計數，同第 24 列）：

```bash
python3 - <<'EOF'
import glob, io, os, yaml, collections
by = collections.defaultdict(set); n = bad = venues = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'venue' not in d: continue
    venues += 1
    for x in d.get('issn') or []:
        v = x.get('value') if isinstance(x, dict) else x
        n += 1; by[str(v).replace('-', '').upper()].add(str(d.get('key')))
print(f"venue {venues}｜ISSN 值 {n}｜distinct {len(by)}｜掛在 ≥2 個 venue {sum(len(k)>1 for k in by.values())}｜讀不到的檔 {bad}")
EOF
# 2026-09-27：venue 485｜ISSN 值 59｜distinct 59｜掛在 ≥2 個 venue 0｜讀不到的檔 0
```

**第 37 列的量測（2026-09-28，可重跑）**：`PATH=/usr/bin:$PATH swift test --filter WriteGateRulingsTests 2>&1 | grep 'WriteGateRulings：'`（四行：CLI 葉命令數、裁決表格數、兩個差集與四種裁決的格數，以及三個逐腿命令各自的旗標數、裁決數與差集；沒印任何東西＝這個 test target 沒有這條檢查，同第 13 列的自證）。**不能用 `akashic --experimental-dump-help` 重算**：CLI 頂層對輸出逐行截 400、總行數截 200（2026-09-28 實測 7,062 行截成 200），JSON 在第 200 行被截斷。

```
# 2026-09-28：
WriteGateRulings：CLI 葉命令 57｜裁決表 57｜只在 CLI []｜只在表 []｜不寫 20／不閘 18／逐腿 3／過閘 16
WriteGateRulings：resolve-organizations 旗標 7｜裁決 7｜差異 []
WriteGateRulings：resolve-people 旗標 14｜裁決 14｜差異 []
WriteGateRulings：resolve-venues 旗標 7｜裁決 7｜差異 []
# 2026-09-28 #586 R1 verify 之後（dismiss-divergence 改為過閘，其餘三行不變）：
WriteGateRulings：CLI 葉命令 57｜裁決表 57｜只在 CLI []｜只在表 []｜不寫 20／不閘 17／逐腿 3／過閘 17
# 2026-09-29 #567 之後（`migrate-venue-variants` 退場刪除——它是那一格「不寫」；其餘三行不變）：
WriteGateRulings：CLI 葉命令 56｜裁決表 56｜只在 CLI []｜只在表 []｜不寫 19／不閘 17／逐腿 3／過閘 17
# 2026-09-29 batch11 整合之後（#544／#614 的 `update-entry` 過閘、#642 的 `library set-kind`（不閘）與 `library check`（不寫）；
# 其餘三行不變。整合 commit 先寫的 57／19／17 只加了 update-entry——把沒有 #642 的分支上的計數當成整合後的計數，
# #642 R1 verify 以 `swift test --filter WriteGateRulingsTests` 實印更正）：
WriteGateRulings：CLI 葉命令 59｜裁決表 59｜只在 CLI []｜只在表 []｜不寫 20／不閘 18／逐腿 3／過閘 18
# 2026-10-05 #564 b34 之後（使用者裁決第 4 點：`update-person`／`update-organization`／`update-venue` 改成逐腿，會刪判定記錄的移除腿過閘；
# 葉命令 84 是這段期間其他 issue 新增的命令，不是本輪；逐腿命令多三行）：
WriteGateRulings：CLI 葉命令 84｜裁決表 84｜只在 CLI []｜只在表 []｜不寫 43／不閘 16／逐腿 6／過閘 19
WriteGateRulings：update-organization 旗標 4｜裁決 4｜差異 []
WriteGateRulings：update-person 旗標 6｜裁決 6｜差異 []
WriteGateRulings：update-venue 旗標 15｜裁決 15｜差異 []
```

**第 38 列的量測（2026-09-28，可重跑）**：拒絕本身由 `PerRecordFullListingTests.testNotFoundAndDuplicateKeysAreRefusedNotGuessed` 釘住（store 裡沒有重複時
binary 沒有東西可印，自證要靠測試）。Python 對照（不依賴 binary；讀不到的檔計數，同第 24 列；work 的 key 是 citekey、divergence 的 key 是檔名 UUID）：

```bash
python3 - <<'EOF'
import glob, io, os, yaml, collections, itertools
keys = collections.defaultdict(list); bad = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    for k in ('work', 'person', 'organization', 'venue', 'divergence'):
        if k in d:
            keys[k].append(os.path.basename(f)[:-5].upper() if k == 'divergence' else str(d.get('citekey' if k == 'work' else 'key')))
            break
dup = {k: sorted(x for x, n in collections.Counter(v).items() if n > 1) for k, v in keys.items()}
cross = {f'{a}×{b}': sorted(set(keys[a]) & set(keys[b])) for a, b in itertools.combinations(sorted(keys), 2) if set(keys[a]) & set(keys[b])}
print({k: len(v) for k, v in keys.items()}, '｜同 kind 重複 key', {k: len(v) for k, v in dup.items()}, '｜跨 kind 同 key', cross, '｜讀不到的檔', bad)
EOF
# 2026-09-28：person 4575、work 2563、venue 485、divergence 1、organization 13｜同 kind 重複 key 全 0｜跨 kind 同 key 只有 organization×venue 2 個｜讀不到的檔 0
```

**第 39 列的量測（2026-09-28，可重跑）**：唯讀，量的就是讀取路徑比的那個數——記錄檔的位元組（讀不到的檔計數，同第 24 列）；判定記錄的理由長度與 judge／refute 的上限對照（上限量的是呼叫端送來的理由，store 裡存的另含 `[rule: …]` 尾註，所以這個數偏大、方向安全）：

```bash
python3 - <<'EOF'
import glob, io, os, yaml
LIMIT = 8 * 1024 * 1024
best = {}; n = {}; bad = over = 0; jmax = (0, '')
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    size = os.path.getsize(f)
    if size > LIMIT: over += 1
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    kind = next((k for k in ('work', 'person', 'organization', 'venue', 'divergence') if k in d), None)
    if kind is None: bad += 1; continue
    n[kind] = n.get(kind, 0) + 1
    if size > best.get(kind, (0, ''))[0]: best[kind] = (size, str(d.get('key') or d.get('citekey') or d.get('id')))
    for r in d.get('references') or []:
        if isinstance(r, dict) and r.get('field') in ('resolution-confirmed', 'resolution-rejected'):
            j = r.get('judgement') or ''
            if isinstance(j, str) and len(j.encode()) > jmax[0]: jmax = (len(j.encode()), str(d.get('key')))
print('記錄數', n); print('各形狀最大檔 bytes', best)
print(f'超過讀取上限 {LIMIT} 的檔 {over}｜判定記錄最長理由 {jmax[0]} 位元組（{jmax[1]}；含 [rule: …] 尾註，上限 4096）｜讀不到的檔 {bad}')
EOF
# 2026-09-28：person 4575／work 2563／venue 485／organization 13／divergence 1；最大檔 venue 268627（psychological-methods）、
#   person 10869、work 5602、divergence 1004、organization 717；超過讀取上限 0｜最長理由 687 位元組｜讀不到 0
```

**第 40 列的量測（2026-09-28，可重跑）**：`LC_ALL=C grep -a -q '的檔案寫入時會被拒——' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c '^⚠ \[跨記錄\] \(work\|person\)「.*」的檔案寫入時會被拒——'`（用含這條檢查的 binary——同第 13 列的自證，舊 binary 印不出東西；行首錨在 binary 自己印的前綴上，同第 24 列）。Python 對照（不依賴 binary；legacy 殘留是本列的前提——沒有它，load 不判斷任何記錄）：

```bash
python3 - <<'EOF'
import glob, os
root = os.path.expanduser('~/.akashic')
for d in ('entries', 'people'):
    n = len([f for f in glob.glob(os.path.join(root, d, '*')) if f.lower().endswith('.yaml')])
    print(f"legacy 殘留 {d}/：{n} 個檔")
EOF
# 2026-09-28：entries/ 0 個檔、people/ 0 個檔
```

**第 41 列的量測（2026-09-28，可重跑，唯讀）**：新 binary 對 live store 的 `akashic validate` 不應多出隔離（指向空內容 digest 的記錄在載入時被隔離）——
`: "${STORE:?先設 STORE 為要量的 store 的路徑}" && test -f "$STORE/store.yaml" && LC_ALL=C grep -a -q '它對所有空輸入都相同' "$(command -v akashic)" && "$(command -v akashic)" validate --library "$STORE" 2>&1 | grep -c '是 0 byte 內容的 digest'`
（應為 0；#654 之前的 binary 沒有這則訊息、閘失敗而什麼都不印——先前這裡只寫「不應多出隔離」，舊 binary 對 live store 同樣零隔離，分不出來，#711 R4 verify 第 9 列）。Python 對照（不依賴 binary；YAML 解析後遞迴走過每個字串值，所以 `content`、`rests-on`、`akashic.sources`、divergence 的依據、timeline 的舊 `source:` 都涵蓋；讀不到的檔計數，同第 24 列）：

```bash
python3 - <<'EOF'
import io, json, os, yaml
E = 'sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'   # 0 byte 的 SHA-256
root = os.path.expanduser('~/.akashic'); ents = os.path.join(root, 'entities')
hits, digests, files, bad = [], 0, 0, 0
def walk(o, path):
    global digests
    if isinstance(o, dict):
        for k, v in o.items(): walk(v, path + [str(k)])
    elif isinstance(o, list):
        for v in o: walk(v, path + ['[]'])
    elif isinstance(o, str) and o.startswith('sha256:'):
        digests += 1
        if o == E: hits.append('.'.join(path))
try: names = sorted(os.listdir(ents))
except OSError as e: raise SystemExit(f'讀不到 {ents}：{e}')
for n in names:
    if n.startswith('.') or not n.lower().endswith('.yaml'): continue
    try: d = yaml.safe_load(io.open(os.path.join(ents, n), encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    files += 1; walk(d, [])
rows = empty_rows = 0
idx = os.path.join(root, 'sources', 'index.jsonl')
if os.path.exists(idx):
    for line in io.open(idx, encoding='utf8'):
        if not line.strip(): continue
        rows += 1
        try: empty_rows += json.loads(line).get('content') == E
        except Exception: pass
blob = os.path.join(root, 'sources', E[7:9], E[9:])
print(f"記錄 {files}｜sha256: 值 {digests}｜指向空內容 digest {len(hits)} {hits}｜index 列 {rows}（指向空 blob {empty_rows}）｜空 blob 在場 {os.path.exists(blob)}｜讀不到的檔 {bad}")
EOF
# 2026-09-28：記錄 7637｜sha256: 值 95｜指向空內容 digest 0 []｜index 列 95（指向空 blob 1）｜空 blob 在場 True｜讀不到的檔 0
```

**第 42 列的量測（2026-09-28，可重跑）**：`LC_ALL=C grep -a -q '分不出是哪一筆' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c 'key「.*」重複——以 key 定位'`（用含這條檢查的 binary——同第 13 列的自證，舊 binary 印不出東西；錨在本列訊息自己的後半句上，不會數到第 33 列的懸空 venue key）。Python 對照見第 38 列的腳本——它逐 kind 數同 kind 重複 key（2026-09-28：全 0）。源碼那一半：`PATH=/usr/bin:$PATH swift test --filter DuplicateVenueOrgKeyTests/testNoStoreKeyLookupTableTrapsOnDuplicates`（2026-09-28：0 處違規）。

**第 43 列的量測（2026-09-29，可重跑）**：唯讀，數帶時間、source 或 note 的名字段，以及含 venue 候選的 divergence（讀不到的檔計數，同第 24 列）：

```bash
python3 - <<'EOF'
import glob, io, os, yaml
segs = dated = sourced = noted = venue_div = bad = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'venue' in d:
        for x in d.get('names') or []:
            segs += 1
            if isinstance(x, dict):
                dated += any(x.get(k) is not None for k in ('start', 'end', 'ended', 'attested'))
                sourced += x.get('source') is not None
                noted += x.get('note') is not None
    elif 'divergence' in d:
        venue_div += any(isinstance(c, dict) and c.get('shape') == 'venue' for c in (d.get('candidates') or []))
print(f"名字段 {segs}｜帶時間 {dated}｜帶 source {sourced}｜帶 note {noted}｜含 venue 候選的 divergence {venue_div}｜讀不到的檔 {bad}")
EOF
# 2026-09-29：名字段 537｜帶時間 0｜帶 source 0｜帶 note 0｜含 venue 候選的 divergence 0｜讀不到的檔 0
# 2026-09-29 鍵改成 ended 後重跑（#675 R1 verify：先前查的 ended-unknown 不是 store 寫的鍵，只帶 ended: true 的段數不到）：同上
```

**第 44 列的量測（2026-09-29，可重跑）**：`grep '^format:' ~/.akashic/store.yaml`（2026-09-29：18）。**它量的是 live store 的 marker，不是情形欄說的「format-13 的 store 有幾筆帶 `variant` 的 venue」**（#642 R1 verify 第 40 則：兩者不是同一個命題）——後者只在 marker < 14 的 store 上有意義，而 live marker 是 18，所以這一列的零是「這台機器上沒有 store 落在閘管的範圍內」，不是「量到零筆違反」；閘本身由 `VenueStoreTests.testVariantWriteRefusedBelowFormat14` 釘住（那才是這一列的證據）。

**第 45 列的量測（2026-09-29，可重跑）**：唯讀（讀不到的檔計數，同第 24 列）：

```bash
python3 - <<'EOF'
import glob, io, os, yaml, collections
fields = collections.Counter(); issn = bad_q = jmax = rmax = bad = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict) or 'venue' not in d: continue
    for x in d.get('issn') or []:
        issn += 1
        q = x.get('qualifier') if isinstance(x, dict) else None
        bad_q += q is not None and q not in ('print', 'electronic', 'linking')
    for r in d.get('references') or []:
        if not isinstance(r, dict): continue
        fields[r.get('field')] += 1
        j = r.get('judgement') or ''
        if isinstance(j, str): jmax = max(jmax, len(j.encode()))
        ro = r.get('rests-on') or []
        if isinstance(ro, list): rmax = max(rmax, len(ro))
print(f"ISSN 值 {issn}｜認不出的角色 {bad_q}｜references 各 field {dict(fields)}｜最長 judgement {jmax}｜rests-on 最多 {rmax}｜讀不到的檔 {bad}")
EOF
# 2026-09-29：ISSN 值 59｜認不出的角色 0｜references：resolution-confirmed 2200、paginated 36｜最長 judgement 287｜rests-on 最多 3｜讀不到的檔 0
```

**第 46 列的量測（2026-09-29，可重跑，唯讀）**：`: "${STORE:?先設 STORE 為要量的 store 的路徑}" && test -f "$STORE/store.yaml" && LC_ALL=C grep -a -q '筆 entry 宣稱（' "$(command -v akashic)" && "$(command -v akashic)" validate --library "$STORE" 2>&1 | grep -c 'Zotero 來源.*被 [0-9]* 筆 entry 宣稱'`（同時涵蓋 `Zotero 來源「1:K」` 與 `Zotero 來源（裸 key「K」）` 兩種標籤；`STORE` 是要量的 store 的路徑，#711 R2 之前寫 `<store>`——不是 shell 能跑的寫法，R3 起寫成 `${STORE:?…}`，R4 起移到整條最前面——寫在管線裡只結束那一段、`grep -c` 照印 `0`（#711 R4 verify 第 1、3、5 列），`test -f` 擋打錯成不是 store 的目錄；用含這條檢查的 binary——同第 13 列的自證，舊 binary 印不出東西）。Python 對照（不依賴 binary；鏡射 `ZoteroSourceClaims`：主來源與附加來源都算、沒記 `library_id` 的**主來源**進 `?:` 桶、沒記 `library_id` 的**附加來源**不算、以 entry id 去重）：

```bash
python3 - <<'EOF'
import glob, io, os, yaml, collections
claims = collections.defaultdict(set)   # 來源鍵 → entry id（以 id 去重，同一筆讀到兩次只算一次）
works = bad = extra_no_lib = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'work' not in d: continue
    works += 1
    p = d.get('provenance')
    if isinstance(p, dict) and p.get('zotero_key') is not None:
        lid = p.get('library_id')
        claims[f"{'?' if lid is None else lid}:{p['zotero_key']}"].add(str(d.get('id')))
    for x in d.get('provenance_additional') or []:
        if not isinstance(x, dict) or x.get('zotero_key') is None: continue
        if x.get('library_id') is None: extra_no_lib += 1; continue   # 沒記 library_id 的附加來源不算
        claims[f"{x['library_id']}:{x['zotero_key']}"].add(str(d.get('id')))
multi = sorted(k for k, ids in claims.items() if len(ids) > 1)
legacy = sum(1 for k in claims if k.startswith('?:'))
print(f"work {works}｜來源鍵 {len(claims)}（其中沒記 library_id 的主來源 {legacy}）｜宣稱者 ≥2 的來源 {len(multi)} {multi[:5]}｜沒記 library_id 的附加來源（不算）{extra_no_lib}｜讀不到的檔 {bad}")
EOF
# 2026-09-29（R1 verify 重量）：work 2568｜來源鍵 535（其中沒記 library_id 的主來源 0）｜宣稱者 ≥2 的來源 0 []｜沒記 library_id 的附加來源（不算）0｜讀不到的檔 0
```

**第 47 列的量測（2026-09-29，可重跑，唯讀）**：`LC_ALL=C grep -a -q '筆成員不符規則（' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c '筆成員不符規則（'`（R1 verify：訊息把指路句移到前段，冒號後接的是點名，所以錨在全形括號） 與 `LC_ALL=C grep -a -q '沒有標成員性質（' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c '沒有標成員性質（'`（用含這條檢查的 binary——同第 13 列的自證，舊 binary 印不出東西；2026-09-29 預期 0 與 4）。Python 對照（不依賴 binary；只做規則型與文件型的比對，懸空規則由 binary 報）：

```bash
python3 - <<'PY'
import glob, io, os, yaml, collections
root = os.path.expanduser('~/.akashic')
libs, bad = {}, 0
for f in glob.glob(root + '/libraries/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if isinstance(d, dict): libs[str(d.get('key'))] = d.get('membership')
works = []   # 保留重複：以 citekey 為鍵的 dict 會吞掉重複，「文件 citekey 重複」就永遠判不出來（#642 R1 verify 第 40 則）
for f in glob.glob(root + '/entities/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if isinstance(d, dict) and 'work' in d: works.append(d)
kinds = collections.Counter((m or {}).get('kind', 'unmarked') if isinstance(m, dict) or m is None else 'malformed' for m in libs.values())
dup_ck = sum(n > 1 for n in collections.Counter(str(w.get('citekey')) for w in works).values())
viol = 0
for k, m in libs.items():
    if not isinstance(m, dict) or m.get('kind') not in ('rule', 'document'): continue
    for w in (w for w in works if k in ((w.get('akashic') or {}).get('libraries') or [])):
        if m['kind'] == 'rule':
            keys = [v.get('key') for v in (w.get('venues') or []) if isinstance(v, dict) and 'key' in v]
            ok = (w.get('citekey') not in (m.get('excluded') or [])) and m.get('venue') in keys \
                 and (not m.get('types') or w.get('type') in m['types'])
        else:
            doc = [x for x in works if x.get('citekey') == m.get('document')]
            ok = len(doc) == 1 and w.get('citekey') in (((doc[0].get('akashic') or {}).get('relations') or {}).get('cites') or [])   # len(doc) != 1：不在庫或 citekey 重複，一律不符
        viol += not ok
print(f"library {len(libs)}｜性質 {dict(kinds)}｜規則型／文件型成員不符 {viol}｜work 的重複 citekey {dup_ck} 組｜讀不到的檔 {bad}")
PY
# 2026-09-29：library 4｜性質 {'unmarked': 4}｜規則型／文件型成員不符 0｜讀不到的檔 0
# 2026-09-29（R1 verify 改寫：works 保留重複）：library 4｜性質 {'unmarked': 4}｜規則型／文件型成員不符 0｜work 的重複 citekey 0 組｜讀不到的檔 0
```

**第 48 列的量測（2026-09-29，可重跑，唯讀）**：角色的閘本身由 `VenueMergeReferencesAndISSNRolesTests` 釘住（live store 沒有含 venue 候選的 divergence，binary 沒有東西可印）。Python 對照（不依賴 binary；讀不到的檔計數，同第 24 列）：

```bash
python3 - <<'PY'
import io, os, yaml, collections
root = os.path.expanduser('~/.akashic/entities')
venues = issn_n = role_n = 0; roles = collections.Counter(); by = collections.defaultdict(set)
div_venue = refs_issn_names = paginated = bad = 0
try: names = sorted(os.listdir(root))
except OSError as e: raise SystemExit(f'讀不到 {root}：{e}')
for n in names:
    if n.startswith('.') or not n.lower().endswith('.yaml'): continue
    try: d = yaml.safe_load(io.open(os.path.join(root, n), encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'divergence' in d:
        if any(isinstance(c, dict) and c.get('shape') == 'venue' for c in (d.get('candidates') or [])): div_venue += 1
        continue
    if 'venue' not in d: continue
    venues += 1
    for x in d.get('issn') or []:
        v = x.get('value') if isinstance(x, dict) else x
        q = x.get('qualifier') if isinstance(x, dict) else None
        issn_n += 1; by[str(v).replace('-', '').upper()].add(str(d.get('key')))
        if q is not None: role_n += 1; roles[str(q)] += 1
    for r in d.get('references') or []:
        if not isinstance(r, dict): continue
        f = r.get('field')
        if f in ('issn', 'names'): refs_issn_names += 1
        elif f == 'paginated': paginated += 1
shared = sum(len(k) > 1 for k in by.values())
print(f"venue {venues}｜ISSN 值 {issn_n}｜帶角色 {role_n} {dict(roles)}｜含 venue 候選的 divergence {div_venue}｜同號掛 2+ venue {shared}｜field issn/names 的 reference {refs_issn_names}（paginated {paginated}）｜讀不到的檔 {bad}")
PY
# 2026-09-29：venue 485｜ISSN 值 59｜帶角色 9 {'linking': 1, 'electronic': 4, 'print': 4}｜含 venue 候選的 divergence 0｜同號掛 2+ venue 0｜field issn/names 的 reference 0（paginated 36）｜讀不到的檔 0
```

**第 49 列的量測（2026-09-29，可重跑；Python 對照唯讀，`doctor` 不是）**：`: "${STORE:?先設 STORE 為要量的 store 的路徑}" && test -f "$STORE/store.yaml" && "$(command -v akashic)" doctor --library "$STORE" 2>&1 | grep -E '^orphaned( additional sources)?:'`（STORE 沒設或不是 store 時整條不跑、什麼都不印、stderr 有一句——R3 寫在 `--library "${STORE:?…}"` 裡時一樣什麼都不印，與「舊 binary」的形狀分不開，#711 R4 verify 第 3 列；印的是那兩行本身、不是計數：#609 之後的 binary 印 `orphaned:` 與 `orphaned additional sources:` 兩行，舊 binary 只有第一行——第二行不在就是舊 binary。它的自證是輸出的形狀，不是第 13 列那種閘：這條不計數，舊 binary 不會印出一個冒充乾淨的 0。`doctor` 不改記錄，但佈局不存在時會建、並重建 index，不是唯讀——所以明寫 `--library`；不帶時它作用在預設解析到的 store，在這台機器上那是活的一份。#711 R3 verify 第 8、16、21 列：這裡先前寫「唯讀」與「同第 13 列的自證」，兩句都不對，也是 PATH 上的裸名）。Python 對照（不依賴 binary；讀同一個 `STORE`；鏡射 `Entry.zoteroLinkState`，讀不到的檔計數，同第 24 列）：

```bash
python3 - "${STORE:?先設 STORE 為要量的 store 的路徑}" <<'PY'
import glob, io, os, sys, yaml, collections
# 鏡射 `Entry.zoteroLinkState`（#609）：
#   完好／整筆 orphan（主來源已刪除；或沒有主來源、附加來源 ≥1 且全部已刪除）／附加來源已刪除（主連結仍在，且至少一個附加來源已刪除）
state = collections.Counter()
sources = additional = bad = works = 0
for f in glob.glob(os.path.join(sys.argv[1], 'entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'work' not in d: continue
    works += 1
    p = d.get('provenance') if isinstance(d.get('provenance'), dict) else None
    extra = [x for x in (d.get('provenance_additional') or []) if isinstance(x, dict)]
    sources += (1 if p else 0) + len(extra); additional += len(extra)
    gone_extra = [x for x in extra if x.get('orphaned_at')]
    if p:
        if p.get('orphaned_at'): s = 'orphaned'
        else: s = 'additionalSourceOrphaned' if gone_extra else 'intact'
    else:
        if not gone_extra: s = 'intact'
        else: s = 'orphaned' if len(gone_extra) == len(extra) else 'additionalSourceOrphaned'
    state[s] += 1
    if not p and extra: state['(只有附加來源)'] += 1
print(f"work {works}｜Zotero 來源 {sources}（附加 {additional}）｜整筆 orphan {state['orphaned']}｜附加來源已刪除 {state['additionalSourceOrphaned']}｜只有附加來源的 entry {state['(只有附加來源)']}｜讀不到的檔 {bad}")
PY
# 2026-09-29：work 2568｜Zotero 來源 535（附加 3）｜整筆 orphan 0｜附加來源已刪除 0｜只有附加來源的 entry 0｜讀不到的檔 0
```

**第 50 列的量測（2026-09-29，可重跑，唯讀）**：閘本身由 `EntrySourceLinkTests.testABlobPathThatIsNotARegularFileIsRefused` 釘住（live store 沒有非普通檔，binary 沒有東西可印）。Python 對照（以 lstat 判類型，不跟隨 symlink）：

```bash
python3 - <<'PY'
import os, stat
root = os.path.expanduser('~/.akashic/sources')
n = 0; other = []; idx_kind = None
try: shards = sorted(os.listdir(root))
except OSError as e: raise SystemExit(f'讀不到 {root}：{e}')
for shard in shards:
    p = os.path.join(root, shard)
    if len(shard) != 2 or not stat.S_ISDIR(os.lstat(p).st_mode): continue
    for f in sorted(os.listdir(p)):
        st = os.lstat(os.path.join(p, f)); n += 1
        if not stat.S_ISREG(st.st_mode): other.append((shard + f, stat.filemode(st.st_mode)))
ip = os.path.join(root, 'index.jsonl')
if os.path.lexists(ip): idx_kind = stat.filemode(os.lstat(ip).st_mode)
print(f"sources/ blob {n}｜非普通檔 {len(other)} {other}｜index.jsonl {idx_kind}")
PY
# 2026-09-29：sources/ blob 99｜非普通檔 0 []｜index.jsonl -rw-r--r--
```

**第 51 列的量測（2026-09-29，可重跑）**：每個 plugin 根的規則數（2026-09-29：`plugin`、`plugins/akashic-discovery` 各 2）。根的集合取自守衛自己的輸出，不寫死：

```bash
roots=$(.build/debug/akashic-guards plugin-roots)
printf '%s\n' "$roots" | while IFS= read -r r; do [ -n "$r" ] || continue; printf '%s ' "$r"; ls "$r"/rules/*.md | wc -l; done
```

#711 R2 之前是一行 for 迴圈（在 `$( … )` 裡跑 `akashic-guards plugin-roots`、迴圈裡 `ls … | wc -l`）：同一行執行 binary 又計數，不合量測的模板——數的是 `ls` 不是 binary 的輸出，但守衛分不出來；裸名 `akashic-guards` 也不在 PATH 上（R2 verify 第 24 列）。R2 把它拆成寫死兩個根的兩條 `ls … | wc -l`，對第三個根沉默（#711 R3 verify 第 18 列）。R3 先把根存進變數、下一行再數：binary 的輸出只供應根的名字，被數的是 `ls`，那是 `zero-instance-rows-audit` 不判讀的那一類（第 19 列量測段「認不出來的寫法」第 1 類），在這裡正好。舊 binary 沒有 `plugin-roots` 子命令時 `roots` 是空的，迴圈跳過空行、什麼都不印——不是 0。

**第 52 列的量測（2026-09-29，可重跑，唯讀）**：

```bash
python3 - <<'PY'
import os
root = os.path.expanduser('~/.akashic')
n = bad = 0; badlist = []
for sub in ('entities', 'entries', 'people'):
    d = os.path.join(root, sub)
    if not os.path.isdir(d): continue
    for f in os.listdir(d):
        if not f.endswith('.yaml'): continue
        p = os.path.join(d, f); n += 1
        if not os.path.isfile(p) or not os.access(p, os.R_OK): bad += 1; badlist.append(p)
print(f"記錄檔 {n}｜不可讀或非一般檔 {bad} {badlist[:5]}")
PY
# 2026-09-29：記錄檔 7643｜不可讀或非一般檔 0 []
```

**第 53–55 列的量測（2026-09-29，可重跑，唯讀）**：三列共用一支腳本；第 54、55 列看的是規則型、文件型 library 的筆數（都是 0，所以被規則指涉的 citekey 與標了性質可被替換的 library 都是 0）：

```bash
python3 - <<'PY'
import glob, io, os, yaml, collections
root = os.path.expanduser('~/.akashic')
libs, works, venues, bad = {}, [], [], 0
for f in glob.glob(root + '/libraries/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if isinstance(d, dict): libs[str(d.get('key'))] = d.get('membership')
for f in glob.glob(root + '/entities/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'work' in d: works.append(str(d.get('citekey')))
    elif 'venue' in d: venues.append(str(d.get('key')))
have = set(works); vcount = collections.Counter(venues)
rules = {k: m for k, m in libs.items() if isinstance(m, dict) and m.get('kind') == 'rule'}
dangling = sum(1 for m in rules.values() for ck in (m.get('excluded') or []) if str(ck) not in have)
ambiguous = sum(1 for m in rules.values() if vcount[str(m.get('venue'))] > 1)
docs = {k: m for k, m in libs.items() if isinstance(m, dict) and m.get('kind') == 'document'}
doc_bad = sum(1 for m in docs.values() if works.count(str(m.get('document'))) != 1)
print(f"library {len(libs)}｜規則型 {len(rules)}｜排除清單指向不在庫 {dangling}｜規則的 venue key 重複 {ambiguous}｜文件型 {len(docs)}（文件不在庫或重複 {doc_bad}）｜讀不到的檔 {bad}")
PY
# 2026-09-29：library 4｜規則型 0｜排除清單指向不在庫 0｜規則的 venue key 重複 0｜文件型 0（文件不在庫或重複 0）｜讀不到的檔 0
```

**第 56 列的量測（2026-09-29，可重跑，唯讀）**：`LC_ALL=C grep -a -q '附加 Zotero 來源沒記 library_id' "$(command -v akashic)" && "$(command -v akashic)" validate 2>&1 | grep -c '附加 Zotero 來源沒記 library_id'`（**前綴的 `LC_ALL=C grep -a -q … &&` 是自證閘**，同第 13 列：`grep -c` 沒命中時印 `0`，舊 binary、usage error、乾淨 store 三者輸出都是 `0`，分不開；沒印任何東西＝PATH 上的 `akashic` 是沒有這條檢查的舊 binary。b13f R1 verify 第 31 列補上；第 33–36 列的同型缺口是既有的，本輪不動）。Python 對照（讀不到的檔計數，同第 24 列）：

```bash
python3 - <<'PY'
import glob, io, os, yaml, collections
n_work = additional = additional_nolib = primary_nolib = primary = 0
claims = collections.defaultdict(set)
bad = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'work' not in d and 'citekey' not in d: continue   # 只看 work
    if 'citekey' not in d: continue
    n_work += 1
    eid = str(d.get('id') or f)
    p = d.get('provenance')
    if isinstance(p, dict):
        primary += 1
        lid = p.get('library_id')
        if lid is None: primary_nolib += 1
        claims[f"{lid if lid is not None else '?'}:{p.get('zotero_key')}"].add(eid)
    for x in (d.get('provenance_additional') or []):
        if not isinstance(x, dict): continue
        additional += 1
        lid = x.get('library_id')
        if lid is None: additional_nolib += 1
        else: claims[f"{lid}:{x.get('zotero_key')}"].add(eid)
multi = sum(1 for k, v in claims.items() if len(v) > 1)
print(f"work {n_work}｜主來源 {primary}（沒記 library_id {primary_nolib}）｜附加來源 {additional}（沒記 library_id {additional_nolib}）｜被 ≥2 筆宣稱的來源 {multi}｜讀不到的檔 {bad}")
PY
# 2026-09-29：work 2569｜主來源 532（沒記 library_id 0）｜附加來源 3（沒記 library_id 0）｜被 ≥2 筆宣稱的來源 0｜讀不到的檔 0
```

**第 57 列的量測（2026-09-29，可重跑，唯讀）**：

```bash
python3 - <<'PY'
import glob, io, os, re, yaml
pat = re.compile(r'^10\.[0-9]{4,9}/[^\s\'"\\$`#?%]+$')
n = bad = unreadable = 0; badlist = []
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: unreadable += 1; continue
    if not isinstance(d, dict): unreadable += 1; continue
    if 'work' not in d: continue
    dois = d.get('doi') or []
    for x in (dois if isinstance(dois, list) else [dois]):
        v = str(x.get('value') if isinstance(x, dict) else x); n += 1
        segs = v.split('/')[1:]
        if not pat.fullmatch(v) or any(s in ('.', '..') for s in segs): bad += 1; badlist.append(v)
print(f"work DOI {n}｜形狀檢查不過 {bad} {badlist[:5]}｜讀不到的檔 {unreadable}")
PY
# 2026-09-29：work DOI 2449｜形狀檢查不過 0 []｜讀不到的檔 0
```

**第 58 列的量測**：沒有可量的母體（校準從未在本機跑過）；閘由上面那支 CLI 測試釘住。

**第 59–60 列的量測（2026-09-29，可重跑，唯讀）**：兩列共用一支腳本（它另外數了帶 `akashic.sources` 的 work，是 #677 移除腿的母體）：

```bash
python3 - <<'PY'
import glob, io, os, yaml, collections
root = os.path.expanduser('~/.akashic/entities')
venues = with_generic = generic = dup_groups = works = works_with_sources = sources_total = bad = 0
maxn = 0
for f in glob.glob(root + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'venue' in d:
        venues += 1
        gen = [r for r in (d.get('references') or []) if isinstance(r, dict)
               and not str(r.get('field', '')).startswith('resolution-') and r.get('field') != 'paginated']
        if gen: with_generic += 1
        generic += len(gen); maxn = max(maxn, len(gen))
        c = collections.Counter(repr(sorted((k, str(v)) for k, v in r.items())) for r in gen)
        dup_groups += sum(1 for n in c.values() if n > 1)
    elif 'work' in d:
        works += 1
        s = (d.get('akashic') or {}).get('sources') or []
        if s: works_with_sources += 1; sources_total += len(s)
print(f"venue {venues}｜帶通用 reference 的 venue {with_generic}｜通用 reference {generic}（單筆 venue 最多 {maxn}）｜位元組相同的重複組 {dup_groups}"
      f"｜work {works}｜帶 akashic.sources 的 work {works_with_sources}（{sources_total} 條）｜讀不到的檔 {bad}")
PY
# 2026-09-29：venue 485｜帶通用 reference 的 venue 0｜通用 reference 0（單筆 venue 最多 0）｜位元組相同的重複組 0｜work 2569｜帶 akashic.sources 的 work 0（0 條）｜讀不到的檔 0
```

**第 61 列的量測（2026-09-29，可重跑，唯讀）**：

```bash
python3 - <<'PY'
import glob, io, os, yaml
root = os.path.expanduser('~/.akashic/entities')
works = with_add = maxadd = maxsrc = bad = venues = generic = 0
for f in glob.glob(root + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'work' in d or 'citekey' in d:
        works += 1
        add = d.get('provenance_additional') or []
        if add: with_add += 1; maxadd = max(maxadd, len(add))
        maxsrc = max(maxsrc, len((d.get('akashic') or {}).get('sources') or []))
    elif 'venue' in d:
        venues += 1
        generic += sum(1 for r in (d.get('references') or []) if isinstance(r, dict)
                       and not str(r.get('field', '')).startswith('resolution-') and r.get('field') != 'paginated')
print(f"work {works}｜有附加 Zotero 來源的 work {with_add}（單筆最多 {maxadd}）｜單筆 work 最多 akashic.sources {maxsrc}｜venue {venues}｜通用 reference {generic}｜讀不到的檔 {bad}")
PY
# 2026-09-29：work 2572｜有附加 Zotero 來源的 work 3（單筆最多 1）｜單筆 work 最多 akashic.sources 0｜venue 485｜通用 reference 0｜讀不到的檔 0
```

**第 62 列的量測（2026-09-29，可重跑，唯讀）**：`find ~/Downloads -maxdepth 2 \( -type d -o -type l \) -name '*.pdf' | wc -l`（2026-09-29：0）。

**第 63 列的量測（2026-09-29，可重跑，唯讀）**：

```bash
python3 -c "
import os
for d in (os.environ.get('TMPDIR','/tmp'), os.path.expanduser('~'), os.path.expanduser('~/Downloads'), '/tmp'):
    p = os.path.realpath(d); hit = None
    while True:
        if os.path.exists(os.path.join(p, '.git')): hit = p; break
        if p == '/': break
        p = os.path.dirname(p)
    print(d, hit)"
# 2026-09-29：四個都 None
```

**第 64 列的量測（2026-09-29，可重跑，唯讀）**：

```bash
python3 - <<'PY'
import glob, io, json, os
root = os.path.expanduser('~/.akashic/sources'); docs = dup = trail = bom = 0
def hook(pairs):
    global dup
    keys = [k for k, _ in pairs]
    if len(keys) != len(set(keys)): dup += 1
    return dict(pairs)
def walk(o):
    global bom
    if isinstance(o, str) and o.startswith('\ufeff'): bom += 1
    elif isinstance(o, dict): [walk(v) for v in o.values()]
    elif isinstance(o, list): [walk(v) for v in o]
for f in glob.glob(root + '/*/*'):
    try: b = io.open(f, encoding='utf-8').read()
    except Exception: continue
    for chunk in ([b] if b.lstrip()[:1] in '[{' else b.splitlines()):
        if not chunk.strip(): continue
        try: o = json.loads(chunk, object_pairs_hook=hook)
        except Exception:
            if ',}' in chunk.replace(' ', '') or ',]' in chunk.replace(' ', ''): trail += 1
            continue
        docs += 1; walk(o)
print(f"JSON 文件 {docs}｜重複鍵 {dup}｜尾隨逗號 {trail}｜字串開頭是 U+FEFF {bom}")
PY
# 2026-09-29：88｜0｜0｜0（母體是整份或逐行解得出的 JSON；#629 R1 報的 1,800 是另一個量法，不要拿兩個數相比）
```

**第 65 列的量測（2026-09-29，可重跑，唯讀）**：`grep -rl latestPastSegment Sources | grep -v -e AkashicCore/Temporal.swift -e AkashicCore/TimelineStanding.swift -e akashic-guards/BacklinkRatchetData.swift | wc -l`（應為 0）；live store 的分布由 `TimelineStandingTests` 的形狀清單對照，量法見 changelog `2026-09-29-attested-affiliation-wording.md`。

**第 66 列的量測（2026-09-29，可重跑，唯讀）**：

```bash
python3 - <<'PY'
import glob, io, os, re, yaml, collections
root = os.path.expanduser('~/.akashic/entities'); bad = 0
retr = collections.Counter(); judg = collections.Counter(); userinfo = []; scheme = collections.Counter(); status = collections.Counter()
for f in glob.glob(root + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    holder = next((k for k in ('person', 'organization', 'venue', 'work', 'divergence') if k in d), None)
    for r in d.get('references') or []:
        if not isinstance(r, dict): continue
        if 'url' in r:
            retr[holder] += 1; u = str(r['url'])
            m = re.match(r'^([A-Za-z][A-Za-z0-9+.-]*):', u); scheme[(holder, m.group(1).lower() if m else 'none')] += 1
            if re.match(r'^[a-z]+://[^/]*@', u): userinfo.append((holder, u))
            status[(holder, r.get('status'))] += 1
        elif 'judgement' in r: judg[holder] += 1
print('retrieval', dict(retr), '｜judgement', dict(judg), '｜scheme', dict(scheme), '｜status', dict(status), '｜帶帳密', len(userinfo), '｜讀不到的檔', bad)
PY
# 2026-09-29：retrieval 只有 work 33（https、status 200）｜person／venue／organization 0｜帶帳密 0
```

**第 67 列的量測（2026-09-29，可重跑，唯讀）**：`grep -rnE '(SELECT|WHERE|ORDER BY|GROUP BY|JOIN)[^"]*\borphaned\b|row\["orphaned"\]|\$0\["orphaned"\]' Sources --include='*.swift' | wc -l`（應為 0）；對照 `grep -rn 'orphaned INT' Sources --include='*.swift' | wc -l`（建表恰 1）。

**第 68 列的量測（2026-09-29，可重跑，唯讀）**：

```bash
cd ~/.akashic/entities && python3 - <<'PY'
import glob, io, collections, yaml
claims = collections.defaultdict(set); works = bad = 0
for f in glob.glob('*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict) or 'work' not in d: continue
    works += 1; cite = str(d.get('citekey'))
    provs = ([d['provenance']] if isinstance(d.get('provenance'), dict) else []) + [p for p in (d.get('provenance_additional') or []) if isinstance(p, dict)]
    for p in provs:
        if p.get('zotero_key'): claims[f"{p.get('library_id','?')}:{p['zotero_key']}"].add(cite)
print(f"work {works}｜來源 {len(claims)}｜被 ≥2 筆宣稱 {sum(len(v)>=2 for v in claims.values())}｜最大宣稱者數 {max((len(v) for v in claims.values()), default=0)}｜讀不到的檔 {bad}")
PY
# 2026-09-29：work 2572｜來源 535｜被 ≥2 筆宣稱 0｜最大宣稱者數 1｜讀不到的檔 0
```

**第 69 列的量測（2026-09-29，可重跑，唯讀）**：第 43 列的量測腳本已涵蓋（名字段數、帶時間、帶 source、帶 note）；另數 `attested` 的最多點數：

```bash
python3 - <<'PY'
import glob, io, os, yaml
mx = bad = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict) or 'venue' not in d: continue
    for x in d.get('names') or []:
        if isinstance(x, dict) and isinstance(x.get('attested'), list): mx = max(mx, len(x['attested']))
print(f"attested 最多 {mx} 點｜讀不到的檔 {bad}")
PY
# 2026-09-29：attested 最多 0 點｜讀不到的檔 0
```

**第 70 列的量測（2026-09-30，可重跑）**：宣告範圍每條宣告印一行，`✓` 是沒有缺口、`✗` 是未列管的缺口、`⊘` 是列管的缺口；清單條目數不含註解與空行。三條分支、格式閘的每個條件與兩個判斷的負控是 `.build/debug/akashic-guards trigger-coverage-mutations`（2026-09-30 R2：49/49；#710 補 issue 號形狀三格後 52/52；#711 補缺口大小七格後 59/59）。**`✗⊘` 的 0 要配 `✓` 那條一起讀**（R2 verify）：#690 之前的 binary 沒有範圍檢查，`grep -c` 都印 0，與「沒有缺口」分不出來——#711 R2 起兩條計數各自有閘（片段是範圍那一段的標題，#690 之前的 binary 沒有它，閘失敗、什麼都不印）；守衛中途以 rc=2 中止時兩條都印 0，所以仍先看 rc 與 `✓` 行數，`✓` 是 0 時下一行的 0 不算數。R2 之前這裡是 `out=$(…)` 一次、`printf '%s\n' "$out" | grep -c` 兩次，靠第一條的 `# 正對照` 讓第二條繼承；正對照不再讓別行繼承之後，改成每條各自跑一次守衛。

```bash
.build/debug/akashic-guards trigger-coverage > /dev/null 2>&1; echo "rc=$?"   # 2026-09-30：rc=0
LC_ALL=C grep -a -q '上面的逐對表只走受保護集合' .build/debug/akashic-guards && .build/debug/akashic-guards trigger-coverage 2>&1 | grep -c '^✓ .*宣告 `'     # 2026-09-30：3（0＝中途中止）
LC_ALL=C grep -a -q '上面的逐對表只走受保護集合' .build/debug/akashic-guards && .build/debug/akashic-guards trigger-coverage 2>&1 | grep -c '^[✗⊘] .*宣告 `'  # 2026-09-30：0
grep -cvE '^#|^$' .githooks/acknowledged-ci-gaps.txt                    # 2026-09-30：0
```

**第 71 列的量測（2026-09-30，可重跑）**：兩個出口的訊息數。先確認這個 binary 有這兩條檢查（找不到就是 #689 R1 之前的 binary，下面的 0 不算數；`LC_ALL=C` 不能省——macOS 的 `/usr/bin/grep` 在 UTF-8 locale 下對 binary 檔比不到中文字串，2026-09-30 實測同一個 binary 印 0 與 3），
再看正對照：對應表每支有負控的守衛一行（`·` 開頭），是 0 表示守衛中途中止。負控是 `.build/debug/akashic-guards audit-guards-mutations` 裡 `migrated：` 開頭的格子
（2026-09-30 R2：整支 75/75）。

**2026-10-02 起這個區塊標成 `text`（#711 R1 verify 第 6、11 列）**：兩個出口已退場（下面的補記），它是紀錄、不是可執行的量測。
第一行的閘對新 binary **該**失敗——#711 第一版的 `audit-guards-mutations` 把整行當錨字串編進
`akashic-guards`，曾讓它對沒有這兩條檢查的 binary 印「有這兩條檢查」；那幾格已改錨，守衛自 #711 R1 起擋「片段出現在 harness 的字串裡」。
#711 R1–R3 的 `zero-instance-rows-audit` 不掃這個區塊（R2 起靠它前一行的退場標記）；**R4 拿掉了那個標記**（R4 verify 第 6、11、13、21 列：它是一個全域的「不掃」開關，
區塊裡加一行、或把一行換成沒有閘的量測，守衛照樣綠）。這個區塊照掃，而在 R4 的辨識下它沒有一行是量測——第一行的閘之後只接 `echo`、
第二行沒有計數也沒有管線、後三行不提 binary。

```text
LC_ALL=C grep -a -q '抽取認不出' .build/debug/akashic-guards && LC_ALL=C grep -a -q '宣告是空的' .build/debug/akashic-guards && echo "有這兩條檢查"
out=$(.build/debug/akashic-guards migrated-guard-control); echo "rc=$?"   # 2026-09-30：rc=0
printf '%s\n' "$out" | grep -cE '^  · `'    # 正對照，2026-09-30：18
printf '%s\n' "$out" | grep -c '宣告是空的'   # 2026-09-30：0
printf '%s\n' "$out" | grep -c '抽取認不出'   # 2026-09-30：0
```

**第 71 列的量測，2026-10-01 補記（#707）**：上面量的兩個出口已退場——新 binary 沒有「抽取認不出」，上面第一行找不到它，照那一行自己寫的規則，
下面三個數對新 binary 不算數。`migrated-guard-control` 現在要 `--log`，只能跟著 runner 跑；讀的是它那一段輸出（`══ 執行紀錄` 起）。
負控是 `.build/debug/akashic-guards migrated-guard-control-mutations`（2026-10-01：27/27）。

```bash
out=$(mktemp)                                   # 不寫進 repo 樹；不用可預測的檔名（#711 R4 verify 第 8、22 列）
bash .githooks/run-guards.sh > "$out" 2>&1; echo "rc=$?"                              # 2026-10-01：rc=0
sed -n '/^══ 執行紀錄/,$p' "$out" | grep -cE '^  · `'           # 正對照（每支有負控的守衛一行），2026-10-01：18
sed -n '/^══ 執行紀錄/,$p' "$out" | grep -c '宣告是空的'         # 2026-10-01：0
sed -n '/^══ 執行紀錄/,$p' "$out" | grep -c '沒有它的 start'     # runner 列了卻沒跑，2026-10-01：0
rm -f "$out"
```

**第 72 列的量測（2026-09-30，可重跑，唯讀）**：量的是檔案大小（不是 `du` 的磁碟用量），不讀內容；symlink 不算。

```bash
python3 - <<'PY'
import os
CAP = 268_435_456   # LibraryStore.maxSourceBytes
for label, root in [('Zotero storage', '~/Zotero/storage'),
                     ('sources/', os.path.join(os.environ.get('AKASHIC_HOME', '~/.akashic'), 'sources'))]:
    root = os.path.expanduser(root)
    if not os.path.isdir(root): print(f'{label}：讀不到 {root}——沒有量'); continue
    n = tot = mx = over = 0
    for dp, _, fns in os.walk(root):
        for f in fns:
            p = os.path.join(dp, f)
            if os.path.islink(p) or not os.path.isfile(p): continue
            s = os.path.getsize(p); n += 1; tot += s; mx = max(mx, s); over += s > CAP
    print(f'{label}：檔 {n}｜合計 {tot} bytes｜最大 {mx} bytes｜超過上限 {over}')
PY
# 2026-09-30：Zotero storage：檔 2817｜合計 61047841 bytes｜最大 5499190 bytes｜超過上限 0
#             sources/：檔 104｜合計 19820273 bytes｜最大 3912063 bytes｜超過上限 0
```

**第 73 列的量測（2026-09-30，可重跑；`find` 唯讀，自證的 `doctor` 不是）**：`: "${STORE:?先設 STORE 為要量的 store 的路徑}" && test -f "$STORE/store.yaml" && find "$STORE/sources" -mindepth 2 -maxdepth 2 -name '.*.incoming-*' | wc -l`（2026-09-30：0）。自證：用含這條檢查的 binary，`: "${STORE:?先設 STORE 為要量的 store 的路徑}" && test -f "$STORE/store.yaml" && LC_ALL=C grep -a -q '殘留的暫存檔' "$(command -v akashic)" && "$(command -v akashic)" doctor --library "$STORE" 2>&1 | grep -c '殘留的暫存檔'` 對上面那個數（至多 20 行，其餘一句概括）；舊 binary 印不出任何一行——「沒被檢查」與「檢查過且乾淨」在輸出上分不開，第 13 列的同一條。R3 把 `${STORE:?…}` 寫在 `find` 與 `doctor` 的引數裡，
STORE 沒設時兩邊都印 `0`、還互相印證（#711 R4 verify 第 14 列）；R4 起檢查在整條最前面。`doctor` 不改記錄，但佈局不存在時會建、並重建 index，不是唯讀——所以明寫 `--library`；不帶時它作用在預設解析到的 store，在這台機器上那是活的一份（#711 R3 verify 第 16 列：這裡先前標「唯讀」、不帶 `--library`）。

**第 74 列的量測（2026-10-01，可重跑，唯讀）**：`PATH=/usr/bin:$PATH swift test --build-system native --filter AppLegacyCopyNoticeTests/testEveryAppStoreWriteIsInsideTheScope`（通過＝在範圍外 0；它另有地板：寫入點少於 6 個即紅，空掃描不是通過）；寫入點數 `grep -rhoE '\.(writeEntry|writePerson|renameEntry|renamePerson)\b' Sources/AkashicAppKit AkashicApp/Sources | wc -l`（2026-10-01：6；R1 verify 起遞迴、認取函式值，這一行是未去除註解與字串的粗量，守衛本身去除註解與字串）。

**第 77 列的量測（2026-10-01，可重跑；Python 唯讀，自證的 `doctor` 不是）**：lstat 每個 62 hex 的檔名，普通檔的大小與 index 那一列（每個 digest 的第一列）的整數 `bytes` 比；不讀內容。自證：用含這條檢查的 binary，`: "${STORE:?先設 STORE 為要量的 store 的路徑}" && test -f "$STORE/store.yaml" && LC_ALL=C grep -a -q '位址上不是普通檔' "$(command -v akashic)" && "$(command -v akashic)" doctor --library "$STORE" 2>&1 | grep -c '位址上不是普通檔'` 與 `: "${STORE:?先設 STORE 為要量的 store 的路徑}" && test -f "$STORE/store.yaml" && LC_ALL=C grep -a -q '存檔大小與 index 不符' "$(command -v akashic)" && "$(command -v akashic)" doctor --library "$STORE" 2>&1 | grep -c '存檔大小與 index 不符'` 各對上面一個數（兩種合計至多列 20 行，其餘一句概括）；舊 binary 印不出任何一行。#711 R2 之前是兩道閘串在一條計數前面——不合量測的模板（每一條只有一道閘），所以拆成兩條。`doctor` 不改記錄，但佈局不存在時會建、並重建 index，不是唯讀——所以明寫 `--library`；不帶時它作用在預設解析到的 store，在這台機器上那是活的一份（#711 R3 verify 第 16 列：這裡先前標「唯讀」、不帶 `--library`，Python 讀 `AKASHIC_HOME` 或預設路徑——兩邊不保證量的是同一份）。

```bash
python3 - "${STORE:?先設 STORE 為要量的 store 的路徑}" <<'EOF'
import os, json, stat, sys
root = os.path.join(sys.argv[1], 'sources')   # 與自證的 doctor 同一個 STORE（#711 R3 verify 第 16 列）
sizes, nonreg, unreadable = {}, 0, 0
for shard in sorted(os.listdir(root)):
    if len(shard) != 2 or not all(c in '0123456789abcdef' for c in shard): continue
    d = os.path.join(root, shard)
    try: names = os.listdir(d)
    except OSError: unreadable += 1; continue
    for n in names:
        if len(n) == 62 and all(c in '0123456789abcdef' for c in n):
            st = os.lstat(os.path.join(d, n))
            if stat.S_ISREG(st.st_mode): sizes['sha256:' + shard + n] = st.st_size
            else: nonreg += 1
indexed, rows = {}, 0
with open(os.path.join(root, 'index.jsonl'), encoding='utf8', errors='replace') as f:
    for line in f:
        if not line.strip(): continue
        rows += 1
        try: o = json.loads(line)
        except Exception: continue
        c, b = o.get('content'), o.get('bytes')
        if c and c not in indexed and isinstance(b, int) and not isinstance(b, bool): indexed[c] = b
mismatch = sum(1 for d, s in sizes.items() if d in indexed and indexed[d] != s)
print(f"普通檔 blob {len(sizes)}｜位址上不是普通檔 {nonreg}｜index 列 {rows}｜大小與 index 不符 {mismatch}｜讀不到的分片 {unreadable}")
EOF
# 2026-10-01：普通檔 blob 103｜位址上不是普通檔 0｜index 列 103｜大小與 index 不符 0｜讀不到的分片 0
```

**第 78 列的量測（2026-10-01，可重跑，唯讀）**：名字分類記錄數應為 0（非零＝拒絕與寫入閘已有實例）；store marker 是寫入閘的輸入（讀 `store.yaml` 的 `format:` 行）。讀不到的檔計數，同第 24 列：

```bash
python3 - <<'PY'
import glob, io, os, yaml, collections
root = os.path.expanduser('~/.akashic')
kinds = collections.Counter(); recs = stmts = bad = 0
for f in glob.glob(root + '/entities/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    kind = next((k for k in ('work', 'person', 'organization', 'venue', 'divergence') if k in d), None)
    if kind is None: bad += 1; continue
    kinds[kind] += 1
    for r in d.get('references') or []:
        if not isinstance(r, dict): continue
        if r.get('field') in ('authorized', 'variant'): recs += 1
        j = r.get('judgement')
        if isinstance(j, str) and j.startswith(('指定：', '確認：', '撤回：')): stmts += 1
fmt = [l for l in io.open(os.path.join(root, 'store.yaml'), encoding='utf8') if l.startswith('format:')]
print(dict(kinds), '｜field authorized／variant 的 reference', recs, '｜三個動作前綴的 statement', stmts, '｜', fmt[0].strip(), '｜讀不到的檔', bad)
PY
# 2026-10-01：{'person': 4575, 'work': 2575, 'venue': 485, 'divergence': 1, 'organization': 13}｜0｜0｜format: 18｜0
```


**第 80、81 列的量測（2026-10-02，可重跑，唯讀）**：第一個數是共用 DOI 的組大小分布與最大組（第 80 列的觸發條件 (1)：最大 ≥ 10）；第二個數是歧異記錄裡 id 與「它目前候選 key 算出的 id」不同的筆數（第 81 列的觸發條件：> 0）。id 的算法同 `DeterministicUUID.forDivergence`（UUIDv5、namespace `3f4c9a71-2d68-4e15-9b03-7a6c1e5d8b24`、名稱是排序後的候選 key 以換行相接）。讀不到的檔計數，同第 24 列：

```bash
python3 - <<'PY'
import glob, io, os, yaml, collections, uuid
root = os.path.expanduser('~/.akashic')
NS = uuid.UUID('3f4c9a71-2d68-4e15-9b03-7a6c1e5d8b24')
doi_map = collections.defaultdict(set); works = 0; divs = []; bad = 0
for f in glob.glob(root + '/entities/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'work' in d:
        works += 1
        for x in d.get('doi') or []:
            v = x.get('value') if isinstance(x, dict) else x
            doi_map[str(v).lower().strip()].add(str(d.get('citekey')))
    elif 'divergence' in d:
        divs.append((os.path.basename(f)[:-5], d))
sizes = collections.Counter(len(v) for v in doi_map.values() if len(v) >= 2)
print('work', works, '｜DOI 值', len(doi_map), '｜共用組大小分布', dict(sorted(sizes.items())), '｜最大', max([len(v) for v in doi_map.values()] or [0]), '｜讀不到', bad)
stale = 0
for fid, d in divs:
    keys = [str(c.get('key')) for c in d.get('candidates') or []]
    if str(uuid.uuid5(NS, '\n'.join(sorted(keys)))) != fid.lower(): stale += 1
print('divergence', len(divs), '｜id 與目前候選 key 算出的 id 不同', stale)
PY
# 2026-10-02：work 2599｜DOI 值 2459｜共用組大小分布 {2: 16}｜最大 2｜讀不到 0
#             divergence 1｜id 與目前候選 key 算出的 id 不同 0
```

**第 82 列的量測（2026-10-02，可重跑，唯讀）**：每筆記錄的名字數上限遠在 200 之下、最長的名字遠在 65,536 位元組之下；名字分類記錄數同第 78 列。讀不到的檔計數，同第 24 列：

```bash
python3 - <<'PY'
import glob, io, os, yaml
root = os.path.expanduser('~/.akashic/entities')
nmax = {'person': 0, 'venue': 0, 'organization': 0}; longest = 0; recs = bad = 0
for f in glob.glob(root + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    kind = next((k for k in ('person', 'venue', 'organization') if k in d), None)
    if kind is None: continue
    if kind == 'person':
        ns = d.get('names') or {}
        names = [str(x) for x in (ns.get('authorized') or []) + (ns.get('variant') or [])]
    else:
        names = [str(x.get('value') if isinstance(x, dict) else x) for x in (d.get('names') or [])]
    nmax[kind] = max(nmax[kind], len(names))
    longest = max([longest] + [len(n.encode()) for n in names])
    for r in d.get('references') or []:
        if isinstance(r, dict) and r.get('field') in ('authorized', 'variant') \
           and str(r.get('judgement') or '').startswith(('指定：', '確認：', '撤回：')): recs += 1
print('每筆記錄的名字數上限', nmax, '｜最長的名字（位元組）', longest, '｜名字分類記錄', recs, '｜讀不到的檔', bad)
PY
# 2026-10-02：{'person': 5, 'venue': 4, 'organization': 3}｜129｜0｜0
```

**第 83 列的量測（2026-10-02，可重跑，唯讀）**：live store 的 `sources/` 在哪種磁碟區上（應是 APFS；exFAT／FAT32 上 `store-source` 會具名拒絕）：

```bash
mount | grep "^$(df ~/.akashic/sources | awk 'NR==2{print $1}') "
# 2026-10-02：/dev/disk3s5 on /System/Volumes/Data (apfs, local, journaled, nobrowse, protect, root data)
```

拒絕本身由 `SourcePlacementTests` 釘住（`testAVolumeThatCannotPlaceExclusivelyRefusesWithZeroWrites`、`testWhenTheVolumeReportsNothingTheRefusalComesFromTheCallsAndLeavesNothing`、旗標讀不到而位址上已有同一份的 `testExistingContentIsAlsoRefusedWhenTheVolumeReportsNothingAndCannotPlace`（b29 V5）；
能力旗標的讀取由 `testTheVolumeCapabilityProbeReadsTheRealFlags` 對測試用的 APFS 暫存目錄釘住）。真的 exFAT 映像上的手動核對：
`hdiutil create -size 40m -fs ExFAT -volname T -o t.dmg && hdiutil attach t.dmg -mountpoint "$PWD/mnt" -nobrowse`，在 `mnt/` 下建 store 後 `akashic store-source <檔> … --library mnt/store`
——應以「sources/ 所在的檔案系統做不到不覆寫的原子放置…把 store 放在 APFS 或 HFS+ 的磁碟區上」拒絕，`mnt/store/sources/` 底下沒有任何檔（2026-10-02 實測）。

**第 84 列的量測（2026-10-02，可重跑，唯讀）**：每日嘗試帳本在不在、有幾筆（`fetch` 跑過才會有；跑過之後才可能有實例）：

```bash
ls -la "$HOME/Library/Application Support/akashic/" && wc -l "$HOME/Library/Application Support/akashic/fulltext-attempts.jsonl"
# 2026-10-02：No such file or directory（從沒對真的 Safari 跑過）
# 2026-10-04（R3）：No such file or directory。這只量得到前提（`fetch` 跑過沒有）；實例要使用者看過交給人的分頁才知道，帳本不記交給人的原因
```

**第 85 列的量測（2026-10-03，可重跑，唯讀）**：名字分類記錄的最後一筆與名字現在的分類矛盾的（分割, 名字）。成員資格看 canonical（NFC＋空白收斂，鏡射 `NameIdentity.canonical` 的近似：live store 的名字都已是 canonical 形，第 25 列）。讀不到的檔計數，同第 24 列：

```bash
python3 - <<'PY'
import glob, io, os, re, unicodedata, yaml
def canon(s): return re.sub(r'\s+', ' ', unicodedata.normalize('NFC', str(s))).strip()
recs = conflicts = bad = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    kind = next((k for k in ('person', 'venue', 'organization') if k in d), None)
    if kind is None: continue
    if kind == 'person':
        member = {'authorized': {canon(x) for x in (d.get('names') or {}).get('authorized') or []}}
    else:
        member = {'authorized': {canon(x) for x in d.get('authorized') or []}, 'variant': {canon(x) for x in d.get('variant') or []}}
    last = {}
    for r in d.get('references') or []:
        if not isinstance(r, dict) or r.get('field') not in ('authorized', 'variant'): continue
        st = str(r.get('judgement') or '')
        if not st.startswith(('指定：', '確認：', '撤回：')): continue
        recs += 1
        last[(r['field'], canon(r.get('value')))] = st[:2]
    for (field, name), action in last.items():
        if (action == '撤回') == (name in member.get(field, set())): conflicts += 1
print('名字分類記錄', recs, '｜最後一筆與分類矛盾的（分割, 名字）', conflicts, '｜讀不到的檔', bad)
PY
# 2026-10-03：0｜0｜0
```

拒絕本身由 `NameClassificationMergeTests` 的 R2 一節釘住（`testCarryThatWouldLeaveAContradictoryTailIsRefused`；搬法由 `testPersonCarryKeepsTheFinalDesignationThatRepeatsAnEarlierOne` 等四個）。

**第 86 列的量測（2026-10-03，可重跑，唯讀）**：沒有任何名字的 person 數。讀不到的檔計數，同第 24 列：

```bash
python3 - <<'PY'
import glob, io, os, yaml
people = empty = bad = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict) or 'person' not in d: continue
    people += 1
    ns = d.get('names') or {}
    if not ((ns.get('authorized') or []) + (ns.get('variant') or [])): empty += 1
print('person', people, '｜沒有名字的', empty, '｜讀不到的檔', bad)
PY
# 2026-10-03：4575｜0｜0
```

**第 87 列的量測（2026-10-04，可重跑，唯讀；2026-10-05 第 94 列改寫）**：每個註冊的 store 的 `.gitignore` 是什麼形狀、有沒有區塊。會被 `file add` 拒絕、`doctor` 與兩個匯入報 warning 的是（匯入自 2026-10-05 起報 warning，#700）：**不是 `block`**，而且是 `symlink`、`hardlink`、`NOT-utf8`、`marker-without-rule`、`read-only`、`not-regular`、`too-large`、`broken-symlink`、`unreadable` 之一（`block` 的什麼形狀都放行）：

```bash
python3 - <<'PY'
import os, io, stat, yaml
cfg = yaml.safe_load(io.open(os.path.expanduser('~/.akashic/config.yaml'), encoding='utf8')) or {}
for k, v in (cfg.get('files') or {}).items():
    p = os.path.join(os.path.expanduser(v), '.gitignore')
    if not os.path.lexists(p): print(k, 'absent'); continue
    link = os.path.islink(p)   # symlink 跟過去讀：指向的檔已有區塊時照樣放行（b33 verify X5 第 25 列）
    try: st = os.stat(p)
    except OSError as e: print(k, 'broken-symlink' if link else 'unreadable', e.errno); continue
    if not stat.S_ISREG(st.st_mode): print(k, 'not-regular'); continue
    if st.st_size >= 100 * 1024 * 1024: print(k, 'too-large'); continue
    try: b = open(p, 'rb').read()
    except OSError as e: print(k, 'unreadable', e.errno); continue
    i = b.find(b'# BEGIN akashic sources')
    rules = {b'sources/', b'/sources/', b'sources', b'/sources', b'sources/*', b'/sources/*', b'sources/**', b'/sources/**'}
    block = 'no-marker' if i < 0 else ('block' if any(l.strip(b' \t\r') in rules for l in b[i:].split(b'\n')[1:]) else 'marker-without-rule')
    try: b.decode('utf8'); text = b'\0' not in b
    except UnicodeDecodeError: text = False
    kind = 'symlink' if link else ('hardlink' if st.st_nlink > 1 else 'file')
    print(k, len(b), kind, 'utf8' if text else 'NOT-utf8', block, 'writable' if os.access(p, os.W_OK) else 'read-only')   # 寫入權限（第 19 列）
PY
# 2026-10-04：main 913 utf8 marker（舊腳本）；2026-10-05：main 913 file utf8 block writable
```

拒絕與 warning 由 `GitignorePreservationCLITests`（真 binary：Latin-1、UTF-16、mode 000、symlink、已有區塊而尾端有非 UTF-8 位元組，`file add` 與 `doctor` 各驗原有位元組不變）與
`ServiceTests.testImportWoSRefusesWithoutRewritingAnUndecodableGitignore` 釘住；負控見 `changelog/2026-10-04-b32-f6-fixes-700-703.md`。

**第 88 列的量測（2026-10-04；2026-10-05 R4 重量，可重跑）**：棘輪的訊息數應為 0；標題列印出量測條數、合模板的條數、依閘去重的條數與棘輪下限
（2026-10-04：35 條、合模板 35 條、下限 35、退場區塊 1 個、5 行不掃；2026-10-05 R4：39 條、合模板 39 條、依閘去重 37 條、下限 37——多的四條是
第 32、41、90 列補上的自證，去重少的兩條是同一道閘的複本；退場區塊拿掉）。負控是 `.build/debug/akashic-guards audit-guards-mutations` 裡 #711 的
`zi-rows：` 那幾格——R3 的九種寫法；R4 每一個辨識與邊界的分支各一個獨有記號，另有須綠的兩格（清單不在這裡複述，見 `AuditGuardsMutationsData.swift`）。
守衛原始碼的 35 個突變體（每個分支拿掉或退回 R3）逐一重編、重放對應的格子，全數變紅（2026-10-05）。

```bash
LC_ALL=C grep -a -q '合模板的量測依閘去重後只有' .build/debug/akashic-guards && .build/debug/akashic-guards zero-instance-rows-audit 2>&1 | grep -c '棘輪標記'   # 2026-10-05：0
.build/debug/akashic-guards zero-instance-rows-audit 2>&1 | head -1
```

**第 89 列的量測（2026-10-04，可重跑，唯讀）**：這條讀取路徑有沒有對真的 Safari 跑過，看 verify-venue SKILL 的那一段還在不在（在＝還沒跑過，實例只可能是零）：

```bash
grep -c '^- \*\*沒有實跑過\*\*' plugin/skills/akashic-verify-venue/SKILL.md
# 2026-10-04：1
```

**第 90 列的量測（2026-10-05，可重跑）**：兩種訊息數應為 0——管線裡的 `${V:?…}`，與用到變數卻沒有前置條件、或以 `--library "$V"` 指名 store
卻沒有 `test -f` 的量測。負控是 `audit-guards-mutations` 的「管線裡的 ${V:?…}」與「量測缺前置條件」兩格；手算對照：前置條件那一行在 STORE 沒設與設成非 store
目錄時都不該印任何東西（第 41、46、49、73、77 列各換成自己的指令，2026-10-05 bash 與 zsh 都是空的）。

```bash
LC_ALL=C grep -a -q '寫在管線裡：' .build/debug/akashic-guards && .build/debug/akashic-guards zero-instance-rows-audit 2>&1 | grep -c '寫在管線裡'   # 2026-10-05：0
LC_ALL=C grep -a -q '等同沒傳、落到預設解析到的' .build/debug/akashic-guards && .build/debug/akashic-guards zero-instance-rows-audit 2>&1 | grep -c '前面卻沒有'   # 2026-10-05：0
```

**第 95 列的量測（2026-10-05，可重跑，唯讀）**：person 數、有對外形的 person 數與名字分類記錄數。讀不到的檔計數，同第 24 列：

```bash
python3 - <<'PY'
import glob, io, os, yaml
people = auth = recs = bad = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict) or 'person' not in d: continue
    people += 1
    if ((d.get('names') or {}).get('authorized') or []): auth += 1
    for r in d.get('references') or []:
        if isinstance(r, dict) and r.get('field') == 'authorized' and str(r.get('judgement') or '').startswith(('指定：', '確認：', '撤回：')): recs += 1
print('person', people, '｜有對外形的', auth, '｜名字分類記錄', recs, '｜讀不到的檔', bad)
PY
# 2026-10-05：4575｜4575｜0｜0
```

拒絕本身由 `NameClassificationB34Tests`（format 18 與 22 各一）、`NameClassificationR2Tests.testCorrectingAnUnrecordedAuthorizedSpellingWritesAWithdrawal`、`NameClassificationCorrectionTests.testPersonReplacementWritesOnlyForNamesThatMove` 釘住。

**第 96 列的量測（2026-10-05；b37 2026-10-09 加 attested 一軸與 venue，可重跑，唯讀）**：organization 與 venue 的筆數、同一個名字（canonical）最多幾段、一段最多幾個觀測點（報告截的兩軸）。讀不到的檔計數，同第 24 列：

```bash
python3 - <<'PY'
import collections, glob, io, os, re, unicodedata, yaml
def canon(s): return re.sub(r'\s+', ' ', unicodedata.normalize('NFC', str(s))).strip()
n = {'organization': 0, 'venue': 0}; most = attested = bad = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): continue
    kind = next((k for k in n if k in d), None)
    if kind is None: continue
    n[kind] += 1
    segs = d.get('names') or []
    c = collections.Counter(canon(x.get('value') if isinstance(x, dict) else x) for x in segs)
    most = max([most] + list(c.values()))
    attested = max([attested] + [len(x.get('attested') or []) for x in segs if isinstance(x, dict)])
print('organization', n['organization'], '｜venue', n['venue'], '｜同一個名字最多幾段', most, '｜一段最多幾個觀測點', attested, '｜讀不到的檔', bad)
PY
# 2026-10-05（只量 organization 的段數）：13｜1｜0
# 2026-10-09：organization 13｜venue 485｜1｜0｜0
```

**第 97 列的量測（2026-10-05，可重跑）**：模板分岔的訊息數 `LC_ALL=C grep -a -q '規則與守衛分岔了' .build/debug/akashic-guards && .build/debug/akashic-guards zero-instance-rows-audit 2>&1 | grep -c '規則與守衛分岔了'`（應印 0；自證同第 13 列）。棘輪標記搬回規則檔、量測文件不在兩則各有負控（`audit-guards-mutations` 的「棘輪標記出現在規則檔」「量測文件不見」）；它們不是計數，所以這裡不另列指令。

**第 98 列的量測（2026-10-09，可重跑，唯讀）**：名字分類記錄數，與其中「記錄自己的最後一筆就與名字的分類矛盾」的（實體, 分割, 名字）數——合併時這種被併者一律被拒。讀不到的檔計數，同第 24 列：

```bash
python3 - <<'PY'
import glob, io, os, re, unicodedata, yaml
def canon(s): return re.sub(r'\s+', ' ', unicodedata.normalize('NFC', str(s))).strip()
recs = bad = selfc = 0
for f in glob.glob(os.path.expanduser('~/.akashic/entities') + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict) or not any(k in d for k in ('person', 'venue', 'organization')): continue
    names = d.get('names') or {}
    if isinstance(names, dict): authorized = names.get('authorized') or []; variant = []
    else: authorized = d.get('authorized') or []; variant = d.get('variant') or []
    member = {'authorized': {canon(x) for x in authorized}, 'variant': {canon(x) for x in variant}}
    last = {}
    for r in d.get('references') or []:
        if not isinstance(r, dict) or r.get('field') not in member: continue
        j = str(r.get('judgement') or '')
        if not j.startswith(('指定：', '確認：', '撤回：')): continue
        recs += 1; last[(r['field'], canon(r.get('value')))] = j[:2]
    selfc += sum((a == '撤回') == (nm in member[fld]) for (fld, nm), a in last.items())
print('名字分類記錄', recs, '｜最後一筆與分類矛盾', selfc, '｜讀不到的檔', bad)
PY
# 2026-10-09：0｜0｜0
```

拒絕本身由 `NameClassificationMergeB37Tests.testTheVerdictDoesNotDependOnHowTheInconsistentDoomedIsSpelled` 與改寫過的 `NameClassificationMergeOrderTests` 三支釘住。

## 附：#711 R1–R4 時寫在第 19 列量測段的量測寫法說明

這一節是歷史：現行的寫法以規則 [`measurement-commands-self-prove`](../.claude/rules/measurement-commands-self-prove.md)與守衛 `zero-instance-rows-audit` 為準，兩者與這裡不同時以它們為準。原文照錄（棘輪標記已移到上方第 19 列的量測段，這裡改寫成文字）。

**同一支守衛自 #711 起另查本檔的量測指令**（第 88 列。判讀的細節住在 `ZeroInstanceRowsAudit.swift` 的 `selfProofIssues`，片段的條件住在
`selfProofNeedleIssues`——這裡不複述：複述過的條件數已與那兩份分岔過，#711 R4 verify 第 18、34 列）。一個單位只要**提到** `akashic`／`akashic-guards`、
又**有計數**，就是一條量測，必須寫在 fence 裡的一行、或不跨行的一段 inline code，逐字是

`[: "${<V>:?<訊息>}" && [test -f "$<V>/store.yaml" && ]]LC_ALL=C grep -a -q '<片段>' <BIN> && <BIN> <參數> 2>&1 | grep -c '<樣式>'`

——`<BIN>` 兩處逐字相同，是路徑或 `"$(command -v akashic)"`（裸名不收：`grep` 會讀工作目錄裡同名的檔）；`<參數>` 不含 `|`、`&`、`;`、`#`、單引號、
反引號、反斜線、括號、`<`、`>`；`<參數>` 用到的變數都要列在最前面的 `: "${V:?…}"` 裡，`--library "$V"` 另要 `test -f "$V/store.yaml"`。不合模板
就是錯誤、具名那一行——沒有閘的寫法在沒有那條檢查的舊 binary 上印 `0`，與「檢查過且乾淨」分不開。**`${V:?…}` 寫在管線裡不會讓 shell 停下**：
它只結束那一段的子 shell，錯誤訊息走 stderr，管線右邊的 `grep -c` 照樣印 `0`；寫在 `&&` 串的最前面，整條不跑（#711 R4 verify 第 1、3、5 列：
R3 在第 18、46、49、73、77 列寫 `--library "${STORE:?…}"`、說那樣會讓 shell 停下——那句是錯的）。fence 與 inline code 裡的任何單位（不只量測）
把 `${V:?…}` 寫在管線裡都是錯誤。`test -f` 擋的是 V 打錯成一個不是 store 的目錄：`validate` 報錯而 `grep -c` 照印 `0`，`doctor` 還會在那裡建出
一個 store（R4 verify 第 15 列）。

**判讀的總原則（R4）：認不出來時偏向「是量測」，邊界認不出來時偏向「同一個單位」**——R1–R3 每一輪都列舉幾種寫法，下一輪 verify 都在列舉之外
找到新的（R4 verify 第 0、2、4、7、12、20 列），所以 R4 反過來寫：binary 的輸出經管線送進任何命令都算計數，除了一張封閉的「已知不計數」清單
（`selfProofDisplayFilters`）。其餘的單位邊界與辨識細節只寫在 `selfProofIssues`（fence、inline code 與散文三處同一把）。`text` fence 照掃：R4 拿掉了
第 71 列的退場標記——它是一個全域的「不掃」開關，區塊裡加一行或換一行沒有閘的量測，守衛照樣綠（R4 verify 第 6、11、13、21 列）。

**認不出來、所以不紅的寫法**（開放的，不是封閉列舉——R3 寫「封閉的三類」，R4 verify 第 4、7、12、20 列在三類之外找到好幾種）：binary 的輸出
先存進變數或檔案、在另一個單位計數；以別名、複本或名字不含 akashic 的變數執行 binary；散文裡 binary 名與計數不在同一個邏輯行；兩段 inline code
之間隔著文字。它們由下面這一行**棘輪**兜底：

（棘輪標記：見上方第 19 列的量測段）

它記合模板的量測**依閘去重後**至少幾條，少於下限守衛就紅（R3 起；R4 起去重——同一道閘貼兩份複本不再撐住地板，R4 verify 第 21 列）。它不是
新增量測的守衛：新增一條沒有閘的量測不改變合模板的條數，抓到它的只能是辨識。新增量測之後把下限調高（不調只是擋不住少量的流失）。
負控是 `audit-guards-mutations` 裡 `zi-rows：` 開頭、講量測、閘、fence、棘輪的幾格。
