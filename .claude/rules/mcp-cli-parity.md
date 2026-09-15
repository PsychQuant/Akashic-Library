# 新增任一面（MCP／CLI）的能力時，必須同時裁決另一面

適用於**新增或修改 MCP 工具**（`Sources/akashic-mcp/Server.swift` 的 `Tool(name:)`
註冊表）與**新增 CLI subcommand**（`Sources/akashic/CLI.swift` 的 subcommands
陣列）的任何變更。修改既有能力（schema、語意）時，同一變更要**重新確認**
對應列仍成立，不成立就更新該列。

**本規則自 #259（2026-08-15）起是雙向的**：新增 MCP 工具 → 裁決 CLI 面（MCP
表）；新增 CLI subcommand → 裁決 MCP 面（CLI-only 表）。#259 前累積的 12 個
CLI-only 能力已於同日一次性補裁（見 CLI-only 表）——此前的沉默至此有了記錄。

不適用於呈現細節（輸出格式、欄位排版）——那由 `entity-backlink-completeness` 的
「一個讀取面只有一條實作路徑」管。

## 規則

**在 `Server.swift` 新增一個工具的同一個變更裡，必須裁決它的 CLI 面**，二選一：

1. **同時補 CLI subcommand**（照 `PersonCommand.swift` 模式：同一個
   `AkashicService` 函式、`key:` 必帶；**讀取面**須 `--json` 原樣轉印 + 人可讀
   同源。**寫入面是封閉例外**：只回 service payload、不設 `--json` 旗標也無人可讀
   分支——`link`／`tag`／`set-status` 即此形；例外只有這一類，不得類推），**並在
   下表加一列**；或
2. **記錄一個有理由的缺席**——開 issue 載明為什麼這個能力可以只有 MCP 面
   （判準見下），並在下表加一列指向該 issue。

**「未決」不是第三個選項**：它曾保留給本規則落地**之前**已存在的工具（#250
兩列的過渡態，2026-08-15 已裁決補齊——第一次演練）。規則生效後新增的工具必須
當場二選一；表中現無未決格。

**判準不是「MCP 有的 CLI 都要有」**——那是機械對稱，會製造沒人用的命令。判準是：

> 這個能力的可用性，該不該取決於使用者用的是 MCP 還是 CLI？

（#206 對匯入面的原話：「能不能無損匯入，不該取決於使用者會不會寫 script。」）

## 裁決史（封閉列舉——現有 31 工具，一格不多一格不少）

| MCP 工具 | CLI 對應 | 裁決 |
|---|---|---|
| `akashic_search` | `query`（filter flags）| ✅ 功能重疊 |
| `akashic_relations` | `query`（relation flags）| ✅ 功能重疊 |
| `akashic_graph` | `graph` | ✅ |
| `akashic_export` | `export-bib`／`export-tables` | ✅ 功能重疊（tables 面與 #274 的 `--view` 為 **CLI-only**——正式裁決見 CLI-only 表的 `export-tables --view` 列，#259）|
| `akashic_doctor` | `doctor` | ✅ |
| `akashic_files` | `file` | ✅ |
| `akashic_libraries` | `library` | ✅（#455 起 add／remove 兩面同走 `setMembership`：CLI 收多 citekey 是批次形、MCP 維持單 citekey——批次面的裁決見 CLI-only 表）|
| `akashic_import_zotero` | `import-zotero` | ✅ |
| `akashic_import_wos` | `import-wos` | ✅（#290；#259 CLI-only 盤點唯一「需要」格的補齊——#206 鏡像判準）|
| `akashic_resolve_people` | `resolve-people` | ✅（#272 起兩面契約有記錄的差異：MCP 允許 apply+reject 組合（兩段式、按腿回報）；CLI 維持分兩次呼叫——互動面天然序列，組合是 LLM 批次 triage 的需求。#303 起兩面同步帶 `tier`（封閉四值 exact／confirmed-elsewhere／reorder／initials，信心降冪）：MCP 每列 `tier` 欄、CLI 按 tier 分組標頭與 `--tier` 篩選（裸 `--apply` 對寬鬆 tier 拒絕）、App 候選列標示；apply id 升三段形 `citekey:authorIndex:personKey`（釘 person，兩段 legacy 收）；否決抑制改與提名同一套正規化、淘汰而得的唯一命中在 reason 揭露——R1 verify 後 apply 語意有這些**有記錄的變更**，非純 additive。R3 裁決的**面不對稱**：tier 閘只在 CLI 篩選式批次（MCP per-id 顯式＋tier 可見，刻意不閘；tier-acknowledgment 參數列 follow-up）；rejected/applied 回音均三段 pinned 形）|

**#457 起另有一個「把作者位移除」的面**（`--drop-author` / `drop_author`，兩面同走
`dropAuthors`）：`Author` 的三態（#323）都假設那一格背後有一個作者，而實測（2026-09-09，
全庫 3,885 個 distinct literal 逐一掃過）有一個不是——PsycInfo 的 `No authorship indicated`，
21 筆。在此之前**沒有任何面到得了 0 個作者位**：`apply` 升格、`attribute_org` 改歸屬、
`split_author` 增加數量、`un_split` 減到 1。唯一的路是手改 YAML。

它今天的代價不是「還沒歸戶」，是出貨的 `.bib` 裡有一個**被捏造**出來的人
（`AUTHOR = {indicated, No authorship}`），citekey 也照它生。APA7 §9.12 對無署名作品
以標題起首，那要求作者位是**空的**。

**以值定位不用索引**（同 `un_split`）：索引在同一批的前一次移除之後會位移，而「這個字串
不是人」本來就是關於字串的宣稱。同一筆 work 的作者位裡出現多次 → **拒絕不判定**。
**兩面同契約**：per-id 顯式、理由必填、整批驗證通過才寫、單獨呼叫不與其餘腿組合。

**同輪動到 export 面**：`apa7Report` 對帶移除記錄的 work 抑制 `AUTHOR` 的 required 檢查
——形狀取自 #406 的 `paginated`，且**空的 `authors` 本身不足以抑制**（那是「還沒記」，
正是該檢查要抓的東西；同 `paginated` 的 `nil` 照報）。少了這一半，21 個被捏造的 byline
會變成 21 個 error。

**#443 起另有一個「把作者位拆開」的面**（`--split-author` / `split_author`，兩面同走
`splitAuthors`）：一個 literal 裝了兩個人時，在此之前**沒有任何面拆得開**——`apply`
只能把它整個升格成一個 person，而那會建出一個不存在的人。實測 4 筆「某人與雷庚玲」。

**收分隔符而不是拆好的名字**：後者等於讓呼叫端**編造**，打錯一個字就寫進 store 而沒有
任何東西擋得住；收分隔符則拆出的每一段必然是原文的子字串。切出空段即拒絕（分隔符選錯）；
換行等空白段同拒；段數有上界（32，且在 materialization 之前生效——literal 是未信任
輸入，高頻分隔符不得先被切成無界陣列再拒）；分隔符**在語法上無法**含 `=`（第一個 `=`
之後一律是理由——誤解析由報告的 separator／judgement 欄揭露、有測試釘住，根治需
結構化參數：MCP 收 object 陣列、CLI 形式另議。**觸發條件（#451 (b)）：出現一個真實 literal
其正確分隔符含 `=` 時重開；在此之前不做**——實務上含 `=` 的人名分隔符零實例，先造介面等於
替一個還不存在的輸入設計形狀）。分隔符、**原始 literal 與理由**都被丟棄，而報告逐筆印出
「原文、用什麼切、切成什麼、為什麼」（`lossless-intake` 的丟棄必須可見；揭露的是
消毒顯示形——`displaySafe` 200／300 上限，#165 的既有取捨）——~~**store 不留原文與
理由是本面的誠實邊界**（R1 verify）：拆分沒有「被判定的另一方」可落 verdict，work 側 references
值域目前只收識別碼；un-split 所需資訊在 store 內不可回復（只在 store 的 git 歷史），持久化需要
值域的顯式裁決（follow-up）。~~ → **自 #450 起不成立**（Spectra change
`split-verdict-historical-reference`，2026-09-07）：拆分的判定持久化到 work 側 `references`
（`{field: authors, value: 原 literal 逐字, judgement: 拆為 ⟦a⟧ ⟦b⟧：理由, rests-on: []}`——第 15
條邊值域的顯式擴充、statement 走 `SplitRecordValue` 單一解析器、需要 store format 16），與作者位
改寫在**同一次**寫入，所以拆分永遠不會沒有記錄、也不會記兩次；段含文法保留字元 `⟦⟧` 拒絕。
報告的 `original`／`judgement` 仍是消毒顯示形，`recorded: true` 說記錄寫了。un-split 所需資訊
自此在 store 內；**un-split 操作面另開 issue**，兩面都還沒有。

**拆出來的仍是 `.literal`**——拆是**形狀**修正不是身分判定，每一段各自走既有消歧路徑。
**兩面同契約**：per-id 顯式、理由必填、**同一個作者位一次只能拆一次**（去重以解析後的
(citekey, index) 為鍵——字面去重會被同 slot 異拼法繞過，R1 verify HIGH）、**單獨呼叫
不與其餘腿組合且組合被顯式拒絕**（#418 樣式；R1 verify 前靠分支順序隱含達成、其餘腿被
靜默忽略——那不是「不可組合」而是隱藏優先序。空陣列與 JSON null 同拒）。它改的是
作者位的**數量**，混在一批裡會讓其他腿的 index 意義改變。同一筆 work 的多個位置一起拆時
**index 位移由實作處理**（由大到小），呼叫端給的是原始索引（報告的 `authorIndex` 也是
原始索引，非寫入後位置）。

**#513 起多一個把上面那個拆分合回去的面**（`--un-split` / `un_split`，兩面同走 `unsplitAuthors`）：#450 讓拆分的判定持久化到 work 側，於是 **un-split 所需的全部資訊自此在 store 內**——但沒有面把它合回去，還原只能手改 YAML（三個動作要一致，而那是 `replace-endnote-and-zotero` 第 4 條要防的安靜失敗）。

**以值定位**（`citekey:原literal`，`ProvenanceReference` 的既有立場 D2），**同 value 多筆記錄拒絕不判定**——那時兩筆記錄的 `parts` 可能不同，而「哪幾個作者位屬於哪一筆」store 裡沒有東西說得出來（形狀取自 `akashic_enrich` 對 DOI 命中 ≥2 筆的 `ambiguous`）。**還原後刪掉那筆記錄**：它的存在理由是「`authors` 已經沒有原 literal 了」，還原之後那句話為假——留著會讓 store 斷言一件假的事，並點亮 `staleSplitRecords`（一次合法的 un-split 製造一條永久 warning）。歷史留在 git，與 #443 那 4 筆的既有取捨相同。

**兩面同契約**：per-id 顯式、整批拒絕零寫入、**與 `split_author`／`attribute_org` 三者互斥且都不與其餘腿組合**（它同樣改作者位的數量，N → 1）。段已升格為 `.key`／`.organization` 時拒絕並**指向 `demote`**——把已歸戶的身分塞回黏著的 literal 是判定的逆轉，不屬本面。

**它不是新的一列，是既有 `akashic_resolve_people` 的一個參數**——加列會讓上表的封閉列舉與機械稽核（`grep -oE 'Tool\(name: "akashic_[a-z_]+"'`）對不上。#513 的 Expected 寫「兩張表各加一列」，那個寫法會壞掉本檔自己的稽核程序。

**#443 起多一個團體作者的升格面**（`--attribute-org` / `attribute_org`，兩面同走
`attributeToOrganizations`）：`.literal` → **`.organization`**。`Author` 的三態
（#323）在此之前只有兩態接得起來——`apply` 升格成 `.key`，而團體作者**只能在建檔時
指定**，既有記錄改不了（實測 #443：兩筆機構被記成 `.literal` 作者，唯一出路是手改
YAML）。**放在 `resolve-people` 是因為作用對象相同**（work 的一個作者位），不是因為
它是消歧——org key 由呼叫端顯式給，不經提名，所以沒有 tier 也沒有候選清單。
**兩面同契約**：per-id 顯式、judgement 必填、不提供批次形式、**不與 apply／reject 組合**
（升格目標是另一個值域，混在一批裡會讓「哪些寫了」難以判讀——同 #418 對 `repoint`／
`demote` 的既有裁決）。失敗語意：**整批驗證通過才寫**，任一筆前提不符即零寫入。

**#386 起多一個 per-id 判定面**（`judge` / `--judge`，兩面同走 `judgeAuthorships`）：
收 `citekey:authorIndex:personKey=理由`，**歧義列也適用**——歧義的意思是提名器分不出來，
不是人／AI 分不出來（`identity-is-judged-not-matched`）。**契約有記錄的差異**：CLI **不提供**
篩選式批次形式（judgement 必填形成摩擦，批次會讓它退化成罐頭）；MCP 面沿用該面既有的
per-id 顯式契約。兩面的失敗語意相同且刻意分兩類：輸入語法錯整批拒絕零寫入、store 狀態不符
該筆略過並具名。

**#388 起 CLI 多一個 `--rows`（歧義段列數上限的旋鈕），MCP 面刻意不加**——這是本列
第三個有記錄的差異。理由不是「還沒做」：

- **消費端不同，而上限保護的是消費端。** CLI 的輸出進人的終端機（可捲、可 pipe、
  可 `grep`）；MCP 的輸出進 LLM context（更貴、且呼叫端無法在收到後丟棄已付的代價）。
  兩面的位元組預算本來就不同值且刻意如此——CLI 128 KB、MCP 48 KB。給 MCP 一個放寬
  列數的旋鈕，等於讓呼叫端有辦法撐爆自己的 context。
- **MCP 已有對等的揭露**：`candidateTotal` 送分母讓程式判斷「我看到的是不是全部」，
  而 CLI 那面是印差額讓人一眼看到。缺的從來不是資訊，是**人**這一側取回全部的手段。
- **不對稱的方向與既有兩條一致**：本列的另外兩個差異（tier 閘、批次形式）也都是
  「CLI 給人多一個把手／多一道摩擦」。三者同向，不是各自為政。

日後若 MCP 面真的需要（例如出現一個要一次讀完全部歧義的 LLM 流程），要重新裁決的是
**該面的位元組預算**而不是列數——列數上限追不上內容，這是 #236 R4 已經量過的
（列數與 ref 上限都在時仍產出 3,844,596 bytes）。
| `akashic_record_divergence` | `record-divergence` | ✅ |
| `akashic_update_person` | `update-person` | ✅（#68）|
| `akashic_create_entry` | `create-entry` | ✅（#206；#455 起兩面同走 `createEntries`——MCP 單筆是薄包裝，CLI 的 JSON 陣列是批次形，批次面的裁決見 CLI-only 表）|
| `akashic_person` | `person` | ✅（#218）|
| `akashic_people` | `people` | ✅（#219）|
| `akashic_get_entry` | `get-entry` | ✅（#219）|
| `akashic_link` | `link` | ✅（#219）|
| `akashic_tag` | `tag` | ✅（#219；契約已收斂——零參數兩面皆拒，守衛下沉 service 單一路徑，#258）|
| `akashic_set_status` | `set-status` | ✅（#219；契約已收斂——省略拒絕、清除須顯式（CLI `--clear`／MCP `clear:true`），守衛下沉 service，#258）|
| `akashic_add_person` | `add-person` | ✅（#250；寫入面封閉例外形。實證需求：#238 對 unkeyable 作者的處置就是單筆指定 key）|
| `akashic_divergences` | `divergences` | ✅（#250；讀取面 `--json`＋人可讀同源。#218 同形：能寫不能讀的格）|
| `akashic_venue` | `venue` | ✅（#304 venue change；讀取面 `--json`＋人可讀同源；編年 list 由反向邊現算）|
| `akashic_venues` | `venues` | ✅（#304 venue change；讀取面同源）|
| `akashic_add_venue` | `add-venue` | ✅（#304 venue change；寫入面封閉例外形，同 `add-person`）。**#554 R5 重新確認，裁決不變、契約有改**：`names` 走與 `update_venue.add_names` 同一個入口（`vetVenueNames`——canonical 入庫、空白項略過、近重複留一筆、含不合法字元或無字母無數字整個呼叫拒絕、全空白拒絕），兩面描述於 R6 同步（R5 verify 第 14 列抓到只改了 update 面的描述）|
| `akashic_update_venue` | `update-venue` | ✅（#306；寫入面封閉例外形；append 語意——整組替換刻意不提供，R3F-2 教訓）。**#471 起兩面同時新增 variant 寫入**（MCP `add_variant`／CLI `--add-variant`，append 語意同 `add_names`）：在此之前 variant **兩面都沒有寫入面**，唯一的寫入者是 `migrate-venue-variants`——而它用的是「`authorized` 的補集」。**一個不做判定的操作成了唯一的判定寫入者**，正面撞上 `identity-is-judged-not-matched`：「這個名字是那個名字的異寫」是判定，不是「不在對外清單裡」的推論（`two-kinds-of-edits` 同向：判定型寫入要有自己的面，不能是決定論式遷移的副產品）。**不在 `names` 的一併 append 進 `names`**——兩個分割都是對 names 的標記，標一個 names 沒有的字串會造出孤兒，而孤兒 variant 自 #473 起是 error。分割互斥與孤兒由 `Venue.validate()` 擋，寫入面不重造。**#554 起兩面同時新增 authorized 的判定寫入**（MCP `authorize`／CLI `--authorize`）——**它不是 append，這是端到端測出來的**：`AuthorizedNames.validate` 對 authorized 有「每書寫系統至多一個」的內容約束，而 2026-09-11 實測 470 筆 venue 已有一個 latin authorized（`VenueBootstrap` 取第一個名字的機械值；`addVenue` 則**不寫**，走 #227 的「建檔不機械偽造」語意），append 第二個 latin 名必被擋——第一版就是照 `add_variant` 做 append，對那 470 筆全部無用。所以語意是**同書寫系統原子替換**：X 成為對外形、原本的 Y **移出 authorized、留在 names、不標 variant**（R1 verify D1，使用者 2026-09-12 裁決：呼叫端只說了「X 是對外形」，程式不替它多說「Y 是異寫」——`venue-entity` spec 的未標是「不作任何宣稱」的誠實狀態；而 Y 若是沿革前身（names 帶時間欄位），標成 variant 會撞 variant 的時間不變式、整個呼叫被拒，DA 席實測）、報告 `authorizedRemoved` 逐筆印出；X 若原本在 variant（被 #553 降過去的）從那個分割移出、報告 `liftedFromVariant`；已是 authorized 的報告 `alreadyAuthorized`（no-op 但不沉默）。**「書寫系統」是 `WritingSystem` 的三個值 han／latn／other**——不同值之間才是 append，`.other` 是一個桶（西里爾與假名互相替換，logic 席實測）。這是 #553 攣生合併「authorized → variant」降級**在該名字上**的逆操作——不是「精確」逆操作（#553 改一個名字的分類，`authorize A` 改兩個：A 升、同書寫系統的 S 移出），命名回到 `authorize` 而非 `add_*`，因為叫 add 會說謊。不在 `names` 的一併 append 進 `names`、分割互斥仍由 `Venue.validate()` 擋、不重造——與 variant 那段相同。**入口的輸入驗證**（都是**輸入**驗證，不是分割互斥的第二份副本——它們擋的是呼叫端的參數矛盾，不是 store 狀態；有幾道不寫數字，R3 verify 抓到「兩道」在同一個 diff 裡就過期）：同一次呼叫把同一個字串既送 `add_variant` 又送 `authorize` 是兩句矛盾的話；同一次呼叫**兩個同 `WritingSystem` 的名字**也是（R1 verify 第 1 列、四席各自重現：迴圈逐一處理時第 N+1 輪會把第 N 輪剛升的移出，陣列順序決勝）——兩者都整批拒絕零寫入。兩個檢查都在空白過濾**之後**算（空白是「沒說話」，不是矛盾）。**相等走 `NameIdentity.canonical`，與 store 守衛同一條**（R2 verify 第 1 列，五路獨立命中）：R2 之前入口是精確 `String ==`，而 R1 report 寫的「近重複 fail-closed」**只對撞到 variant 成立**——D1 讓被換下來的舊名留在未標，`Venue.validate()` 對 names 沒有 near-duplicate 檢查，於是 `--authorize "X "`（尾隨空白）對既有 authorized `[X]` **寫入成功**：帶空白的字串進 names、真名被移出、帶空白版成為 displayName。那句「fail-closed」是 D1 之前的量測被抄進 D1 之後的規則，沒有重量（`assertions-must-be-measured` §2 的形狀）。**R4（D6）→ R5（D8，使用者 2026-09-12）：名字內容的不變式住在 store 邊界，不在任何一個寫入面**。R2→R4 三輪把閘裝在 `updateVenue` 的三個迴圈裡（精確相等 → 只 authorize 走 canonical → 三個迴圈一致），每一輪都修在看見的那一圈，R4 verify 指出同一個 `names` 欄位還有 `addVenue`（原樣存入、連空字串都收）與 `VenueBootstrap`（只 trim）兩個寫入者——`add-venue --names "X "` 種下的髒條目讓乾淨拼法永遠進不了。`Venue.swift` 的 dated-variant 守衛 doc 早就寫著答案：「守衛住在 validate → writeVenue 的交會處才擋得住所有路徑」。現在：**`Venue.validate()` 對 names／authorized／variant 逐條驗（error 級）**——canonical 形（前後／連續空白、tab、NFD 都不是）、不含控制／格式字元（與輸出閘 `UnsafeToEmitScalar` **同一份**定義再加整個 Cf／Cc／Zl／Zp 類別——R4 曾是 19 個例子的列舉、170 個 Cf 漏 149：ALM、TAG 字元；**不可見**用 Unicode 的 `Default_Ignorable_Code_Point`（R6——R5 verify 第 2 列：VS16／CGJ 是 Mn、Hangul filler 是 Lo，四類 generalCategory 都放行，`心\u{FE0F}理學報` 存成第二筆「不同」名字、`add-venue --names $'\u{3164}'` 建出 displayName 空白的 venue）；ZWJ／ZWNJ 只在兩個脈絡合法——(a) 掛在同一文字字母上的 virama 之後（右鄰居若在，要是同一文字的字母／數字）、(b) 左鄰居是 join-control 文字的字母／標記／數字、右鄰居是同一文字的字母／數字（R6——R5 verify 第 1 列五路命中：「兩側是字母」對拉丁字母 fail-open、對 Malayalam chillu 與波斯數字 fail-closed；R7 再收：區塊裡的標點不算鄰居、連續 joiner 不算——R6 verify 第 1／19 列；R8 再收：virama 的基底要是**字母**、不是數字或標記（Codex，R7 verify 第 1 列）、兩側要同一文字、joiner 之後不能直接接標記或 virama（R7 verify 第 26／33 列）；`NameIdentity.joinerIsLegal` 是封閉的兩個脈絡，區塊表補進 Mandaic／Syriac Supplement／Adlam 等草書文字——第 14／22 列）；「至少一個字母或數字」的字母是 generalCategory 的 L 類，不是 `isAlphabetic`（R7 verify 第 15 列：一個孤立的 Arabic fatha 曾寫得進去）；U+2800 BRAILLE PATTERN BLANK 顯式列入不可見（第 20 列））、至少一個字母**或數字**（純數字刊名 *1843*／*2600* 是真的，R4 曾寫「至少一個字母」）、三張清單各無 canonical-相等對（names 的例外：兩段都帶不相交時間的沿革改回舊名——R6，R5 verify 第 4 列：Sankhyā 1933–1960 → 2002–2007 合回同名那筆記錄在 R5 寫不進去；R7 起「不相交」用 `Venue.segmentsAreDisjoint`——一段有 end、另一段有 start、**兩端都是 ISO 8601 前綴**（R8，R7 verify 第 2／3／7 列三席：手改的 `2003-1`／`民國49` 曾解鎖豁免，`ISO8601Prefix.isValid` 早就在）、較粗粒度截斷後嚴格早於；端點相等與 attested-only 都不豁免——R6 verify 第 9／35／47 列指出 `DateRange.overlaps` 對混合粒度 fail-open，而這裡是放行條件；掃描先以 canonical 鍵分組，O(n) 不是 O(n²)——第 21 列）；謂詞一份在 `NameIdentity.wellFormednessIssue`，訊息對操作者說改什麼（R6）。**D8 不進 `venue-entity` spec 是一個要記下來的裁決**（R6 verify 第 3 列：R6 說記了、實際沒記）：#554 的裁決是「既有 tool 的新參數，不走 Spectra」，D8 把它擴成 store 不變式時沒有重開；規範文字住 `docs/store-format.md` §5.7（store 契約，與 §3.4 同級），spec 的 Requirement 是 #570。`canonical` 只丟 `White_Space` scalar、不刪任何其他 scalar（R6——R5 在 Character 上切，「空白＋combining mark」整個 cluster 被刪，`add-venue --names $'Jour ́nal'` 存成 `Jour nal` 零回報）。**所有寫入者存 canonical**：`updateVenue`（`vetVenueNames`：canonical → 逐項驗 → 去重，順序不能反——R4 曾先去重再驗，`["New Journal", "New\tJournal"]` 兩種順序得到不同結果）、`addVenue`（同一個入口）、`VenueBootstrap`。相等只有一條：canonical 查找、回傳 **store 條目**——「先精確」在 Swift 裡不存在（`String ==` 是 canonical equivalence，R4 曾讓 NFD 輸入把 NFD 位元組寫進 authorized、非 Swift 讀者看到 `authorized ⊄ names`）。手改出來的違反（近重複對、非 canonical）在下一次寫入被 validate 具名擋下、零寫入——不猜、不靜默修（**含 `fmt`**：R6 起 `.venue` 分支與 `.person` 同樣跑 validate——R5 的裸 `encode(decode)` 讓 `fmt --check` 對一個 validate 報 error 的 store 印「✓ 全部已是 canonical form」；**含合併的 dry-run**：預測的 keeper 過同一道 `assertVenueWritable`；**`resolve-venues` apply／repoint／demote 改成 venue 先過閘再寫 entry**——R5 是 entry 先落盤、venue 才 throw，手改一筆尾隨空白的 venue 後 apply 會留下升格的 entry 與沒落的 verdict，Claude 代裁 D11；R7 補 `repoint` 對懸空 from-key 的具名拒絕——base 既有的 `venuesByKey[k]!` 在 D11 之前是「entry 已落盤再 crash」、之後是「零寫入再 crash」，對 MCP 面都是以合法參數殺死 server 的路徑，R6 verify 第 4／27 列（R8 把訊息的指路從 `--demote` 改成「救回檔案或手改 YAML」——`--demote` 對同一狀態也是 notFound，R7 verify 第 4 列）；**R8 起 `repoint` 的 verdict literal 從 from-venue 的 confirmed verdict 逐字取回**，取不到就拒絕——#418 用 work 的 `title` 當 literal，之後 `--demote` 會把 venue 邊改寫成論文標題（DA，R7 verify 第 6 列；既有缺陷，兩輪在同一函式上動刀而沒看到）；**work／person 合併對持有被併鍵 verdict 的 venue 在 commit 之前過寫入閘**（R8 當時的 `assertVenueHoldersWritable`——R9 起是涵蓋三種 holder 的 `assertHoldersWritable`，見後——preview 共用——post-commit 的 holder 遷移曾是第七個沒過閘的 venue 寫入者，dry-run 說 OK、apply 刪了檔、venue 留死 verdict，DA，R7 verify 第 5 列）；**合併的被併記錄自己違反不變式時，訊息指向被併者**（`doomedRecordInvalid`，第 28 列：那個字串只在 doomed 的 YAML）；拒絕訊息的參數名兩面各自正確（`add_names（--add-name）`，第 45 列）、原字串截 120 讓理由不被截掉（第 7／12 列））；唯一的自我修復路是 authorized 裡同名不同位元組（NFD）的舊指定在 `--authorize` 同名時被換成 canonical——R5 至 R9 報在 `authorizedRemoved`，R10 起報在自己的桶 `authorizedRewritten`（見下方 R10 段；R10 verify 第 11 列抓到這一句仍以現在式說 `authorizedRemoved`，同一列內兩份描述）。**誠實邊界**：NFC 對 CJK 相容表意文字有損（U+FA10 塚 → U+585A；位元組層有損、Swift 層無損）；`displaySafe`／`UnsafeToEmitScalar` 對 Cf 字元的**輸出**逃脫仍是列舉（TAG 字元在錯誤訊息裡原樣印出）——輸出閘另裁（#569）。**#560 的程式缺口由本輪關掉**（`zero-instance-guards` 第 25 列）。**R9（R8 verify 39 列，DA 席缺席）**：joiner 的 (a) 支要求 virama 與跳過的標記都是基底的文字、詞尾 chillu 後的空白視同沒有（D22）；(b) 支放行同一 Indic 文字的 virama（Bengali ya-phalaa `<RA, ZWJ, VIRAMA, YA>`，Microsoft Devanagari／Bengali 音節文法 `<ZWNJ|ZWJ>+H` 實取確認——R8 的「沒有正字法意義」對 Bengali 為假，D21）；區塊表補 Devanagari Extended／Extended-A、Myanmar Extended-A／B；`repoint`／`demote` 寫 verdict 時退役同 holder 上同一配對的相反判定（D20——R8 逐字帶原 literal 之後，每一次合法的 repoint 都在 from-venue 留下 #486 的矛盾對，處置「刪掉另一個」沒有工具面），報告 `verdictsRetired`；from-venue 上同一 work 有 ≥2 個正規化後不同的 confirmed literal 時具名拒絕、零寫入（D23，verdict 不帶 index；live store 2026-09-12 實測 0）；「找不到 confirmed verdict」的拒絕補出路（改回 `- literal:` 再 `--apply`）；work／person 合併的commit 前閘擴到三種 holder（`assertHoldersWritable`，D24——R8 的 doc 說 person／organization 沒有內容不變式，假的：兩者的寫入閘都跑 `validate()`）。R8 對 `zero-instance-guards.md` 的 splice 錨到 row-18 的 heredoc、把第 17／18／20／21／22 列的量測段整段蓋掉——R9 從 a03933d 逐字復原，第 25 列的Python 鏡射自此只有一份（ISO 鏡射 `ISO8601Prefix.isValid`、`dated` 鏡射 `makesTemporalClaim`）。**R10（R9 verify 29 列，6 席齊）**：D20 的退役只在**配對由一條邊實例化**時做——verdict 不帶 venue index，同一 work 兩條邊指同一 venue 時只有一筆 confirmed，退役它讓另一條邊在任何工具面上都救不回來且 #486 的 warning 一起消失（六路命中、DA 真 binary 重現），`repoint`／`demote` 對這種 work 具名拒絕零寫入（D25；live store 2026-09-14：2,411 筆 work、同 venue 兩條 key 邊 0、兩條 literal 邊同配對 0）；`verdictsRetired` 從整數改成逐筆具名（venue、欄位、value、statement——#553 合併會把被併 venue 的顯式 `--reject` 搬進 keeper，日後一次 repoint 退役它時被併檔已不在）；`confirmedLiteral` 的去重改位元組相等（`matchingKey` 去重會把另一條邊的字還回去——DA 第 9 列）；(b) 支收 virama 只限 Devanagari／Bengali 且 virama 之後要接同文字的字母（D26——R9 對十個 Indic 文字一起放行且不看右脈絡，`क\u{200D}\u{094D}` 與 `क्` 渲染相同）；`add_venue` 回報存入的名字與 `namesDropped`（R4 起走 `vetVenueNames` 但 payload 仍回原輸入）；`--authorize` 的 NFD 自我修復報在 `authorizedRewritten`（R9 讓同一字串同時落在 `alreadyAuthorized` 與 `authorizedRemoved`）；`Venue.validate()` 的近重複訊息每組最多列 3 對（O(k²) 則訊息由讀取路徑對未信任 store 觸發）；holder 閘移到 `fieldsLostByMerging` 之後。**R11（R10 verify 29 列，5 席——DA 席 errored）**：D25 只驗原始 entry 裡的 from 配對，`newKey` 不看——`repoint` 自己就能造出 `[key V, key V]`（logic 席真 binary 重現：alpha 上兩筆 confirmed、beta 的 confirmed 被退役、validate 全綠、之後兩條邊都動不了），而 `apply` 對兩條同刊名的 literal 邊各 apply 一次也造得出（requirements／regression 席：R10 自己的測試就是證據）。**D27**：配對的唯一性對改指**之後**的邊集合驗，同一批同一 work 的兩個 move 不得帶同一個 literal（verdict 以 (work, literal) 為鍵，逐 move 的退役會互相覆蓋、留下哪一側取決於輸入順序；literal 不同時交換是對的）；**D28**：`apply`／`repoint` 在會造出同一 work 兩條 key 邊指同一 venue 時具名拒絕零寫入（生產端 fail-closed），`Entry.validate()` 對既有的這種 work 報 warning（`zero-instance-guards` 第 26 列），移除面另案 #572（作者位有 `--drop-author`／`--un-split`，venue 邊沒有——`replace-endnote-and-zotero` 第 4 條）；D25 的 `.literal` 支只對 repoint 算（demote 沒有 to-venue，literal 邊在該 venue 上不可能持有 confirmed，R10 對 demote 也拒且出路等於叫人手做那次 demote）；**D30**：`verdictsRetired` 截 20 筆、`verdictsRetiredTotal`／`truncated` 揭露（`akashic_enrich` 的形——它是 payload 裡唯一由 store 內容決定體積的欄位；它迴送 verdict 的 value 與 statement，#569 的迴送點 4 → 6）；`Venue.validate()` 的近重複掃描求值也設上限（5,000 對 ≈ 100 筆同名段，超過即 error——R10 的上限只綁訊息，全豁免的沿革組仍 O(k²)，真 binary 4,500 段 20 秒全綠），「另至多 M 對」改說「未評估」（已評估而豁免的對同樣沒被列出）；`addVenue`／`update_venue.add_names` 的報告拆成 `namesRewritten`（canonical 形在 store、位元組不同）與 `namesDropped`（真的沒進——R10 用位元組相等，NFD 輸入同時落在 `names` 與 `namesDropped`）；**兩面描述補 D20（會刪掉一筆人的判定記錄）、D23、D25、D27、D28、`verdictsRetired`，MCP `authorize` 補 `authorizedRewritten`、`add_venue` 補兩個桶**（R10 verify 第 6／12 列：R6 抓過只改一面，這次兩面都沒改）；joiner 的 help 改寫成左右不對稱（右鄰不收標記）；venue 合併的 `doomedRecordInvalid` 移到 `fieldsLostByMerging` 之後（與 R9 對 person／work 的先後原則對齊）。**R12（R11 verify 32 列，6 席齊——DA 回來了）**：兩個 HIGH 都在合併路徑，四席都沒碰到、DA 真 binary 重現——`mergedVenueKeeper`（與 person 側逐字同型）的 verdict 遷移用位元組相等去重而 `supersede`／#486 用正規化鍵，一次合法合併就造出永久的矛盾對；合併把同一 work 的兩條 key 邊塌成一條而兩筆正規化後不同的 confirmed literal 都留下，D23 之後那條邊永久不可 demote／repoint 且 validate 零診斷。**D31**：遷移以 `verdictEqualityKey` 去重，倖存者與被併者對同一配對持相反判定時合併具名拒絕（person 同）；**D32**：塌邊會留兩筆不同 confirmed literal 時拒（出路：先 demote 一條）。**D33**：`apply` 的 D28 閘從整批拒絕改成**逐筆略過並具名**（`skippedDuplicateVenueEdge`）——一筆毒候選曾讓同批無關的候選零寫入、每次重列都再提（campaign 是照 listing 全量 apply），既有的重複邊（手改／舊 binary）曾把同一 work 上不相干的歸戶鎖死、訊息還把因果歸給這次 apply；store 狀態不符是「該筆略過並具名」那一類（`judge` 的先例）。D27 收窄：唯一性只看**被動到的邊**，同 literal 的兩個 move 只在 venue 集合相交時才拒（不相交的各在自己的檔裡退役、與順序無關——R11 的訊息在那一格為假、出路「分兩次呼叫」直接到達被拒的狀態）。`VenueResolver` 的否決抑制改比 `matchingKey`（與 `verdictEqualityKey`／#486／D25 一族同粒度，`PersonResolver` 早就這樣；R11 放寬 demote 的 literal 支後，apply → demote → apply 三步全工具面造出永久矛盾對）。沿革豁免要求兩段本身是有效區間（倒置日期曾解鎖放行）。`verdictsRetired` 以性質逃脫不可見 scalar（Cc／Cf／Zl／Zp／DI——#569 的局部圍堵）；no-op 早退也帶 D30 三鍵；訊息索引改「index N」（0-based）且列舉有上限；`namesRewritten` 拆成 `namesFolded`（這次折過才存）與 `namesAlreadyPresent`（本來就在，不論位元組——冪等但要說）；§5.7 補第 5 條（求值上限）、配對唯一性搬到 §3.5 成 normative 段；guards 第 26 列改寫「合併不是入口」。**R13（R12 verify 43 列，6 席齊）**：七個 HIGH 全在 R12 剛加的合併閘上——D31 只比 keeper↔doomed（三方合併的 doomed↔doomed 相反判定兩筆都進 keeper，五席同指）、且只裝在 person／venue 自己的 references 上（DA 真 binary 全工具面：work 合併的 holder 遷移把 `confirmed :: work:keep` 與 `rejected :: work:doom` 都改寫成 keep，#486 矛盾對）→ 累積比對＋閘裝在 `assertHoldersWritable`（三種 shape 共用）；D32 的 `hits.count > 1` 守的是「塌邊」這個症狀（DA：不塌邊也到得了同一終局；logic：keeper 既有的違反擋住無關的合併、出路被 D25 堵死）→ 改守不變式本身（這次新增的 confirmed literal 讓 keeper 對某 work ≥2 個正規化後不同的 confirmed 即拒，keeper 既有的不擋）；遷移去重丟掉的判定記錄零回報（四席）→ 逐筆進 `verdictsCollapsed`；repoint 同 literal 的相交檢查只比相鄰兩筆（Codex＋logic：三個 move 的第 1 與第 3 個相交逃過）→ 全配對；MCP 組合腿的 `skippedBecauseRejected` 只比 id 字面而抑制已比正規形（DA：reject 已提交、apply 回一句指錯路的 notFound）→ 以正規化配對算；性質式逃脫從 `verdictsRetired` 下沉到 Core 的 `displaySafeInvisible`，名字不變式的訊息、`doomedRecordInvalid`、`confirmedLiteral` 的 literal 列、合併拒絕訊息共用，補零到四位、加 U+2800／非 ASCII 的 Zs／Co（security 四列）；`skippedDuplicateVenueEdge` 的訊息分「既有的 key 邊」與「同一批稍早的候選」（先到先寫，順序由呼叫端決定——兩面描述寫明）；`add_variant`／`authorize` 的全空白項回報在 `variantDropped`／`authorizeDropped`；`fmt` 的 `.organization` 分支補語意驗證（三個同形 shape 只修了兩個）；apply 的重複邊預掃改 `Set`（O(entries×requested) → O(entries)）；`assertKeyEdgesAreUnique` 的 doc 不再說 apply 會拒；`assertPairingHasOneEdge` 的索引排序；§5.7 兩處「四條」→「五條」、§3.5 補 R13 三個收緊與「合併本身是一種移除面」；`supersede` 退役判定記錄卻沒有 trackedness 前置（security）另案 #573。**R14（R13 verify 33 列，6 席齊）**：三個 HIGH 中兩個是同一格——holder 遷移的閘只補了「相反判定」那一半，work 合併純工具面（`--apply` 兩個刊名變體 ＋ `resolve-divergence`）造得出 D23 從此拒的邊、validate 零診斷（Codex 第 1 列、DA 第 3 列）；第三個是 dry-run 對去重丟掉的判定沉默（regression 第 2 列）。收成一個 delta 謂詞（D34：合併後 vs 合併前，keeper 與 holder 兩路同一份、兩半都算；既有的違反不擋——R13 的 holder 側是絕對謂詞、keeper 側漏單一被併者內部）、訊息印出處與遷移前原值、preview 與實跑對 `verdictsCollapsed` 同源（D35）、`Venue.validate()` 對同一 work ≥2 個 confirmed literal 報 warning（D36，`zero-instance-guards` 第 27 列）、近重複與 bootstrap 的訊息以性質逃脫、三則入口拒絕訊息項數截 10、`skippedDuplicateVenueEdge` 列出既有重複邊的全部索引、repoint 相交訊息印兩個拼法、兩面描述補 `variantDropped`／`authorizeDropped`（R13 verify 第 26 列：第三次只做一半）、sink 守衛認得 `displaySafeInvisible(`。**R15（R14 verify 31 列，6 席齊）**：兩個 HIGH——D34 的差集在配對鍵層算而配對鍵含 holder，被併鍵上的既有違反被判成新（logic 第 2 列，四席同指；D37 改在索引層算、訊息分「帶進來的」與「既有的」）；生產端的 fail-closed 只在合併有，apply／repoint 對「目的 venue 已對該 work 持有另一個 confirmed literal」照寫（Codex 第 1 列；D38 兩面同契約：`apply` 逐筆略過並回報 `skippedConflictingConfirmedLiteral`、`repoint` 整批拒絕）；D36 只掃 `matchingKey` 不同的而 D23 比位元組（Codex 第 3／requirements 第 5 列；D39 兩類都掃、家族前綴、`StoreHealth` 計數、每筆 20 則上限）；收攏丟列印遷移後的 value（DA 第 10 列；D40 印原值、逐段截、rename 的 CLI／App sink 同一種逃脫）；`migrate-venue-variants --apply` 一律拒絕（regression 第 9 列；D41）；MCP／CLI 描述補 D38 與否決抑制的正規化鍵（regression 第 21 列）；guards 第 27 列的 Python 鏡射對齊 Swift 的空白集合與 grapheme 層連字號（logic 第 17／DA 第 23 列）；malformed 回退鍵加不可碰撞的前綴（security 第 28 列）。**R16（R15 verify 30 列，6 席齊）**：D42（第 1／4／8 列）、D43（第 3／5 列）、D44（第 2／6 列）、D45（第 12／13／20 列）、D46（第 9／11／24 列；#574）；第 14／15／16／17／18／19／23／29 列逐項修；第 22／25／27／28 列記錄不動——細節在 changelog「R15 verify」節與 §3.5，本列自 R16 起只記編號（第 28 列）。**R17（R16 verify 31 列，6 席齊）**：D47（第 1 列 HIGH——合併收攏的勝者政策在拼法位元組不同時改由倖存配對自己的那筆勝、收攏列印兩個拼法；#468 的弱血統優先只在同拼法時適用，使用者可翻）、D48（第 2／3／6／19 列——近重複組上限只數真的出聲的組）、D50（第 9 列——D43 訊息兩桶同時說）；第 4／5／7／8／10／11／12／13／14／15／16／17／18／20／22／24／25／26 列逐項修；第 21 列併入第 15 列；第 23／27／28／29／30／31 列記錄不動（第 31 列開 follow-up）。**`migrate-venue-variants` 在 #554 之後不得再跑**：它的補集規則會把 D1 留在未標的舊指定重新標成 variant（R2 verify 第 3 列，DA 席實測）；退場見 #567。**不留 judgement**：與 person `authorize-names`（#81）、`add_variant`（#471）同為不留，三個名字分類面一次裁（#564）——這一格因此是有記錄的裁決，不是遺漏；後果是 #553 合併端仍分不出「人確認過的 names[0]」與機械值，那格維持提醒不擋、觸發條件改綁 #564。撤回面（把名字從 authorized 移出而不放新的進去）本面沒有——#559。**#394 起兩面同時新增 ISSN 寫入**（MCP `add_issn`／CLI `--add-issn`，append 語意同 `add_names`——ISSN 本來就是清單，print 與 electronic 是兩個真的號）。**這是本檔「識別碼寫入面的裁決」那一節記為「最弱的一列」的第一格補齊**：在此之前識別碼只有遷移路徑（從 `fields` 殘留搬值），查到一個**新的** ISSN 時唯一的路是手改 YAML。相等看正規形（與 `IdentifierMigration.normalizedUnique` 同一條規則——兩面若用不同的相等，對「這本刊有幾個 ISSN」會給出不同答案）；任一個不合法即整批拒絕、零寫入，與同函式既有的 `type` 值域檢查同型）。**#406 起兩面同時新增 `paginated` 判定寫入**（MCP `paginated`+`judgement`+`rests_on`／CLI `--paginated --judgement --rests-on`，同走 `updateVenue`）：「本刊是否使用頁碼」是**判定**不是設定——必附理由與證據 digest（缺任一整個呼叫拒絕、零寫入；rests-on 的非空與形狀由 `ProvenanceReference` 平面 init 驗，單一驗證入口）；(field,value,kind) 冪等、翻轉判定留史；`nil` 是誠實的未判定狀態，floor 檢查（`apa7Report` 的 `PAGES` recommended）只對 **false** 抑制、nil 與 true 照報 |
| `akashic_resolve_venues` | `resolve-venues` | ✅（#304 venue change；兩面契約差異同 #272：MCP 允許 apply+reject 組合、CLI 分兩次呼叫）。**#418 起兩面同時新增 `repoint`**（三段式 id `citekey:venueIndex:newKey`，把**已歸戶**的邊改指到另一個 venue）——它是歸錯戶的退路：`apply` 只做 literal → key 的升格，此前一條已是 key 的邊改不回來，而 person 域有 `resolve-divergence`、venue 域沒有，且 `literal-first-then-key` 的整套論證建立在「誤可逆」上。**這一項兩面契約相同**（與上面那個差異不同）：`repoint` **不與** `apply`／`reject` 組合，兩面都拒——它們是不同階段（升格 vs 修正已升格的），混在一次呼叫裡會讓「哪一批寫了」難以判讀，而改指本來就是在修一個錯誤，最需要清楚的失敗語意。失敗語意分兩類（同 #386 的 `judge`）：語法錯或前提不符 → **整批拒絕零寫入**；成功則兩側都留 verdict（新的 confirmed、舊的 rejected——少了 rejected，下次提名會把同一配對再提出來）。**同輪另加 `demote`**（`citekey:venueIndex`）把**誤升**的邊退回 literal——`repoint` 只改得到既有 venue，而正確答案可能是「現有的都不對」，那時要能退回 `literal-first-then-key` 所說的**誠實狀態**。原字串**從該 venue 的 confirmed verdict 逐字取回**（第 13 條邊的 `<kind>:<key> :: <literal>` 文法），走 `ResolutionLedger.verdicts` 這個唯一解析器；**取不到就拒絕，不拿 venue 顯示名頂替**（顯示名不是那筆記錄原本寫的字——WoS 的 `PSYCHOMETRIKA` vs 正式刊名 `Psychometrika`，頂替會安靜改寫書目資料）。`repoint` 與 `demote` **各自單獨呼叫**，兩面同契約 |
| `akashic_add_organization` | 無（單筆建檔 MCP-only；批次面 `bootstrap-organizations` 維持 CLI-only，見 CLI-only 表）| ✅ 有理由的單面（#304 移轉裁決：org 重啟後單筆建檔是 #303 campaign 的 LLM 消費流程；操作者規模的批次建檔另有 CLI 面）|
| `akashic_resolve_organizations` | `resolve-organizations` | ✅（#304 移轉；CLI-only 表「候補缺席（重啟訊號已觸發）」格的補齊——同 `import-wos`／#290 的移列形）|
| `akashic_store_source` | `store-source` | ✅（#264；**讀取面慣例**而非寫入面封閉例外——receipt 的 `discardedProvenance` 攜帶「你這份敘述沒被寫入」，人需要看得懂，故 `--json` 原樣轉印＋人可讀同源。收**檔案路徑**不收 base64／stdin：MCP 面無 stdin 會讓兩面分岔，base64 把二進位塞進 JSON 會膨脹並整份進 context（#165 的既有威脅模型）。`SourceStore.storeSource` 的寫入面防護 #224 已完成，本格只補呼叫端——先前全樹零 production 呼叫端，能力只有寫 Swift 的人做得到，#206 判準的同形）|
| `akashic_enrich_from_zotero` | `enrich-from-zotero` | ✅（#340；**#206／#290 判準的第三次套用**——那句原話是「能不能無損匯入，不該取決於使用者會不會寫 script」，在這裡是「能不能把一筆跌破下限的記錄補回下限，不該取決於面」。兩面同走 `ZoteroEnrichment.plan`。**契約有記錄的差異**：CLI 的 `--apply`走 #298 的破壞性閘、MCP 面用 `dry_run` 且**不設閘**——該閘擋的是「篩選式批次寫入未指名目標」，而本 tool 收的是逐筆顯式指名的 citekey 清單，與 `resolve-people` 的 tier 閘同型不對稱。**與 `akashic_import_zotero` 刻意不同語意**：那是 pull（整份替換 `fields`、重設 `type`、覆寫未歸戶作者），這是 add-only；同一個 store 上兩種語意並存是設計，不是重複）|
| `akashic_enrich` | `enrich` | ✅（#458；generic add-only 補值——`akashic_enrich_from_zotero` 那列的**一般化**：政策抽成 `AddOnlyEnrichment`（AkashicCore）一份，Zotero 版降為它的 adapter，兩面同走 `AkashicService.enrich`。輸入以 citekey 或 DOI 定位（DOI 相等是 `identity-is-judged-not-matched` 的識別碼例外，對回 citekey 由程式做；命中 ≥2 筆＝`ambiguous`、具名全部 citekey、零寫入——不判定哪筆才對，那是 #459）。雙摘要分鍵（`abstract-<lang>`／`abstract-2` → `abstract_es`／`abstract_2`）；`sourceDigest` 只回顯不進 store（第 15 條邊的值域是 #450 的裁決）。**契約差異沿上一列**：CLI `--apply` 走 #298 閘、MCP `dry_run` 預設 true 且**不設閘**（逐筆顯式指名）。**第二個有記錄的差異**：MCP 面 items 截 20 筆（`counts`／`written`／`writeFailed` 永遠完整、`itemsTotal`／`truncated` 揭露）、CLI 不截——同 #388 `--rows` 那格的理由：上限保護的是消費端，MCP 的輸出進 LLM context。兩面**同一個 JSON 解析器**（`AddOnlyEnrichment.decodeProposals`：CLI 讀 `--from` 檔、MCP 把 `Value` 編回 JSON 再解），頂層未知鍵整批拒絕——把 `abstract` 寫在頂層而非 `fields` 是最容易犯的錯，靜默略過會讓那筆看起來「補了」）。**#517 起 `sourceDigest` 寫得進 store**：提案多收 `sourceURL`／`sourceRetrieved`／`sourceMediaType`／`sourceStatus`（蛇形同收），三欄齊備時每個補進去的欄位寫一筆 `retrieval` reference（`fields.<鍵>`／識別碼帶 value），與被補的值**同一次寫入**；**只給 digest 仍只回顯**，理由具名進 `provenanceSkipped`——一次取得的 url 與日期沒有別的地方記，digest 單獨湊不出一筆誠實的 retrieval。新鍵**不必逐面加**：兩面本來就同一個解析器（本列既有記載），這是那個設計的第一次兌現 |

新增下一個工具 = 在這張表加一列。**不得依性質相似類推**「這個工具顯然不用 CLI」
——那個判斷要寫成表裡的一列（含理由或 issue 編號），不能只存在腦中。

### 怎麼機械檢查這張表真的封閉

不要相信作者窮舉過（`entity-backlink-completeness` 的表錯過兩次，教訓同形）：

```bash
# ① MCP 面的全部工具名（實測：恰 30，與表零差集）
grep -oE 'Tool\(name: "akashic_[a-z_]+"' Sources/akashic-mcp/Server.swift | sort -u
# ② CLI 面的全部註冊型別（取 subcommands 陣列整段，不靠型別命名慣例——
#    第一版寫 '[A-Za-z]+Cmd?\.self' 只命中 11/30：`Cmd?` 是「Cm+可選 d」，
#    #219 verify 三個 lens 獨立抓到。稽核程序自己也要被稽核）
sed -n '/subcommands: \[/,/\])/p' Sources/akashic/CLI.swift | grep -oE '[A-Za-z]+\.self'
# ③ 逐一比對上表：①有而表沒有 → 表壞了；表標 ✅ 而②對不到 → 表壞了。
#    ② 吐的是**型別名**（FileCmd）而表用**命令名**（file）。這一步過去是人工的
#    （#259 當時判斷「要全機械化需 manifest 或讀 configuration 的測試」）——實測
#    過於保守：從各型別的 CommandConfiguration 純文字抽 commandName 就夠，39/39
#    全解析（#318）。以下把型別名翻成命令名，再拿命令名去對表。
#    **失敗模式已驗**：抽不到 commandName 的型別印 `<未解析>` 而**不是靜默跳過**
#    ——只在 happy path 正確的稽核命令，會在真正需要它時安靜少報一列，那正是 ②
#    第一版 11/30 的形狀。
sed -n '/subcommands: \[/,/\])/p' Sources/akashic/CLI.swift \
  | grep -oE '[A-Za-z]+\.self' | sed 's/\.self$//' | sort -u \
  | while read -r t; do
      n=$(awk -v t="$t" '
            FNR==1 { f=0 }
            $0 ~ ("struct[[:space:]]+" t "[[:space:]]*:") { f=1 }
            f && /commandName:/ {
              sub(/.*commandName:[[:space:]]*"/, ""); sub(/".*/, ""); print; exit
            }' Sources/akashic/*.swift)
      printf '%-30s %s\n' "$t" "${n:-<未解析>}"
    done
#    誠實邊界：純文字抽取與「讀 configuration 的測試」不等價——前者對宣告寫法改變
#    脆弱（同 ② 的既有教訓）。本步只主張它足以取代**人工逐一開檔**，不主張它是終局
#    形狀。真正的不脆弱版本仍是那個測試，#259 的討論在這一點上沒有過期。
# ④ CLI 面的全部**橫切選項**（#310）：`ParsableArguments` 不是 subcommand，所以 ②
#    在結構上枚舉不到它——這是 ② 的盲點，不是它漏了一項。輸出的每一項都必須出現在
#    下方「CLI 橫切選項裁決表」；查無即是零裁決格。
#    **假陰性方向（寫出來而非假裝沒有）**：本式只認**宣告式**上的 conformance，
#    多重 conformance 的兩種順序都命中，但以 extension 追加 conformance 的寫法掃不到
#    ——與 ② 第一版 regex 只命中 11/30 同型。漏報比誤報安全，但漏報仍是漏報。
grep -rhoE 'struct [A-Za-z]+:[^{]*\bParsableArguments\b' Sources/akashic/ \
  | sed -E 's/^struct ([A-Za-z]+):.*/\1/' | sort -u
```

## CLI-only 裁決表（封閉列舉——#259 一次性補裁；**列數以下表為準、表頭不寫死**（#422 verify R1 實測表頭的「12 命令＋1 旗標」與表已漂移多列——同 `entity-backlink-completeness` 對條數的既有作法：複述過的數字會與表分岔）；`bootstrap-venues` 於 #367 新增時當場裁決；`import-wos` 於 #290、`resolve-organizations` 於 #304 venue change 補 MCP 面後移列 MCP 表；`migrate-person-identity` 於 #227/#241、`migrate-venues` 於 #304 venue change 新增時當場裁決）

新增 CLI subcommand = 在這張表加一列（或補 MCP 面後在 MCP 表加一列）。兩個
裁決用語：**維運例外**＝要求操作者在檔案系統與版控旁（git 退路、人工
pre-flight）的操作，MCP 的 LLM 消費者不是該角色；**候補缺席**＝目前無 MCP 端
消費流程，需求出現即重啟裁決（不是永久判死——重啟訊號刻意不形式化，那是使用
情境判斷）。

| CLI 能力 | 裁決 | 理由 |
|---|---|---|
| `view`（list／show） | 候補缺席 | 外延查詢對 agent 有潛在價值，但目前無 MCP 端消費流程 |
| `resolve-divergence` | 有理由缺席 | in-code 既有裁決（`AkashicService.recordDivergence` doc）：消歧含合併＋全庫改寫＋刪檔，tracked+clean 前提與人工確認屬 CLI／App 互動面。**#553（2026-09-11）重新確認，裁決不變**：該輪讓本命令多收一個 shape（venue），而缺席的理由是**操作的性質**（不可逆、要乾跑逐筆過目、要 git 工作樹乾淨），與它收幾個 shape 無關——多一個 shape 不會讓那三件事對 LLM 消費面變得可承擔。`record-divergence` 那一面在 MCP 表已有對應（`akashic_record_divergence`），本輪的 `byShape` 擴充**兩面同時生效**，沒有新的不對稱 |
| `bootstrap-people` | 有理由缺席 | 批次建檔屬操作者規模；單筆由 `akashic_add_person` 覆蓋（#250）。**#547 重新確認，裁決不變**，但**理由要改寫**：該輪新增的是同一命令的報告欄位（`pendingMutual`）＋ 一個 `--json` 出口。上一版的理由是「**不是新能力**，所以不觸發本檔的義務」——那是**用重新分類迴避問題**。誠實的版本是：本檔的機械稽核 ② 枚舉 subcommand、④ 枚舉橫切 `ParsableArguments`，**兩者都枚舉不到 per-command 的 `@Flag`／`@Option`**（實測全 CLI 38 個 `@Flag`、91 個 `@Option`）。那是**收錄機制的缺口**，跟「這算不算新能力」無關——一個 per-command 旗標若真的長出 MCP 面該有的能力，今天沒有任何程序會發現。本格的裁決仍是缺席，理由與 #388 的 `--rows` 同型：`--json` 的消費端是把組別餵給 `add-person` 的人工消歧迴圈，而 MCP 面的輸出進 LLM context、呼叫端無法在收到後丟棄已付的代價；要一次讀完 3,000+ 筆的是操作者，不是 LLM。**缺口本身另案追蹤：#551。**|
| `bootstrap-organizations` | 有理由缺席 | 批次建檔屬操作者規模（同 `bootstrap-people`）。原第二理由「org 建模先停（#63／#70）」已由 #304（2026-08-16）廢止——org 重啟後**單筆**建檔的 MCP 面已於 venue change 補齊（`akashic_add_organization`，見 MCP 表）；批次面維持 CLI-only |
| `bootstrap-venues`（#367；#548 重新確認；#554 R6 重新確認） | 有理由缺席 | 批次建檔屬操作者規模（同 `bootstrap-people`／`bootstrap-organizations` 的既有裁決）。**三個 bootstrap 命令的裁決一致不是巧合**：它們的共同形狀是「掃全庫的 literal、按門檻建實體、dry-run 供人審」，而那個規模與審閱動作屬操作者，不是 LLM 消費面。單筆建檔的 MCP 面已有 `akashic_add_venue`（見 MCP 表）。**#548 重新確認裁決不變**：該輪新增的是同一命令的報告欄位（`pendingResolution`——與既有 venue 寬鬆共鍵的群）與一道扣留，不是新命令、也不是新能力面；`bootstrap-organizations` 同批同形。與 #547 對 `bootstrap-people` 的處置一致。**#554 R6／R7 重新確認裁決不變**：該輪讓報告多一個 `reason` 欄位（`Dropped.reason`——被謂詞拒的 literal 從「零字」變成印出並附理由，與產不出 key 的分得開）並把「已有 venue」的檢查移到謂詞之前（只差一個 Cf 的既有刊名 literal 走 resolve-venues 歸戶、不印成「修來源欄位」）；仍是同一命令的報告欄位與扣留順序，不是新能力面（R6 verify 第 11 列抓到沒記） |
| `fmt` | 有理由缺席 | 全庫改寫＝維運例外 |
| `migrate` | 有理由缺席 | 格式遷移＝維運例外 |
| `migrate-provenance` | 有理由缺席 | 同上 |
| `migrate-person-identity`（#227/#241） | 有理由缺席 | 格式遷移＝維運例外（同 `migrate`／`migrate-provenance`）；且不可逆、要求 store 工作樹乾淨的人工 pre-flight，MCP 的 LLM 消費者不是該角色 |
| `migrate-venues`（#304 venue change） | 有理由缺席 | 格式遷移＝維運例外（同 `migrate` 族）；per-file trackedness pre-flight＋部署鏈（release → migrate → validate → 手動 bump format 11）屬操作者角色 |
| ~~`migrate-work-types`~~（#325，**已退場**） | 有理由缺席 → 退場 | 格式遷移＝維運例外（同 `migrate` 族）；不可逆、要求檔案受 git 追蹤的人工 pre-flight，MCP 的 LLM 消費者不是該角色。**#325 階段二起命令不存在**——它讀不到舊值（舊值在階段二的 decode 就被拒），留著只會是一個永遠無事可做卻看似可用的命令（`no-compat-fallback` 的「退場即刪」）。列保留但劃掉：刪掉會丟失裁決史，而那正是本檔存在的理由 |
| `migrate-venue-variants`（#422；**#554 之後不得再跑，退場見 #567；R15 起 `--apply` 一律拒絕（D41）、乾跑仍可**） | 有理由缺席 → 待退場 | **2026-09-15（#554 R14 verify regression 第 9 列）**：只用散文禁止的命令仍可執行、會靜默推翻 D1 的未標——CLI 的 `--apply` 自 R15 起 throw（零成本閘，#567 落地前的中間項）。**2026-09-12（#554 R2 verify 第 3 列）**：它的補集規則「names − authorized → variant」在 #554 之後為假——`--authorize` 刻意把換下來的舊指定留在未標（D1），而那筆記錄恰好滿足它的四個條件；live store 的遷移工作已歸零。依 `no-compat-fallback` 退場即刪（同 `migrate-work-types` 列的形狀），本列在 #567 落地時劃掉。原裁決：格式遷移＝維運例外（同 `migrate` 族）；不可逆、per-file trackedness pre-flight、且**手動 bump format 是分開的一步**（13 → 14）。**這一列不是從 `migrate-venues` 類推來的**：它多一個該族沒有的性質——它做的是**重新分類**而非搬值（`names` 的名字不動，只是多一個 `variant` 標記），所以誤標的出口是**乾跑逐筆過目**而不是 rollback。實測 35 筆，人工可行 |
| `migrate-identifiers`（#394） | 有理由缺席 | 格式遷移＝維運例外（同 `migrate` 族與 `migrate-venues`）；不可逆、要求每個將被改寫的檔**自身**受 git 追蹤的人工 pre-flight，MCP 的 LLM 消費者不是該角色。**這一列不是從 `migrate-venues` 類推來的**：它多一個該族沒有的性質——它會**跨記錄搬動資料**（work 的 `issn` 移位到它的 venue），所以一次失敗的部分寫入會讓兩邊都不對，而不只是某些檔沒遷到。乾跑是預設、`--apply` 才寫，且乾跑刻意**不**受 #298 的破壞性閘管制——它不寫東西，且正是用來確認目標的手段 |
| `validate` | 有理由缺席（理由於 #416 換過）| **原理由「讀取檢查由 `akashic_doctor` 覆蓋（功能重疊）」被量測否掉**：`Entry.validate()` 在全樹只有一個呼叫點（CLI），`doctor()` 與 App 面各 0。**落差是 warning 一族**（#416 R1 更正：原本寫「有一條是 error 級」，實測那條到不了——load 的 quarantine 先擋下，而 quarantine 本來就在 `StoreHealth` 裡）。#416 把 per-record 驗證抽進 `StoreHealth.perRecordIssues`，兩個消費面因此都拿得到——**現在**才真的重疊。CLI 面維持獨立命令的理由改為：它是**逐行、無截斷**的完整報表，而 MCP 面截斷 20 則（輸出進 LLM context，呼叫端無法在收到後丟棄已付的代價，#236 的既有威脅模型）；要全部就用 CLI。這是**呈現粒度**的差異，不是能力缺席 |
| `rename` | 有理由缺席 | 高風險身分操作（citekey 遷移含 verdict value 重寫，#232）＝維運例外 |
| `rename-person`（#395） | 有理由缺席 | 同 `rename` 的理由，**而且遷移面更大**：除 verdict value（`person:` holder，掛在 person 與 organization 兩處）外，還含全庫 `authors[].key` 與 divergence 的 `candidates`／`judgement.prefers`。**這一列不是從上一列類推來的**——它的參照集合是照 `entity-backlink-completeness` 的封閉列舉逐條窮舉出來的（第 1、9、10、13 條），與 citekey 的那組**不重疊**。維運例外的理由因此更強而非更弱：漏一格的後果是安靜的（檔案照樣載入，只是某些邊指向不存在的 key） |
| `authorize-names` | 有理由缺席 | 批次策展＝操作者規模 |
| `export-tables --view`（#274） | 有理由缺席 | 匯出物是檔案樹，MCP 的回傳形狀未定——#274 註記的正式落位 |
| `create-entry` 的 JSON 陣列與 `library` add／remove 的多 citekey（批次語意，#455） | 有理由缺席 | **批次屬操作者規模**（同三個 `bootstrap-*` 的既有裁決）：一次 load、批次內消解 citekey 碰撞、可預期失敗整批擋零寫入、I/O 逐筆收容、一次 rebuild，是目錄匯入（1545 筆量到 O(n²)）的使用形；MCP 的 `akashic_create_entry`／`akashic_libraries` 維持單筆——LLM 消費面逐筆顯式指名，且兩面**同一條實作路徑**（單筆是 `createEntries([draft])`／`setMembership(citekeys: [ck])` 的薄包裝），所以缺的只是「一次送多筆」的參數形狀，不是能力。日後若出現 LLM 流程需要一次建千筆，重新裁決的是 MCP 面的**位元組預算**（#388 的同一個論證），不是加參數 |

**機械檢查（CLI→MCP 方向）**：上方稽核程序的 ② 枚舉 CLI 全部註冊型別後，
每個命令必須出現在 **MCP 表的「CLI 對應」欄**或**本表**其中之一——兩處都
查無即是新長出的零裁決格（正是 #259 修掉的形狀）。

**機械檢查（表→命令方向，#325 補）**：前兩個方向都問「命令有沒有裁決」，
都抓不到**命令退場後留下的孤兒列**——一列描述著一個已不存在的命令的裁決，
讀起來與有效裁決毫無區別。第三個方向反過來問：

```bash
# 本表與 MCP 表「CLI 對應」欄提到的每個命令名，是否仍在 ② 的枚舉裡？
# 不在 → 該列必須標記退場（劃掉 + 寫明退場理由與 issue），**不是刪除**：
#   刪掉會丟失裁決史，而保留失敗史正是本檔存在的理由
#   （見全域 `common-spec-prose-enumeration` 執行細節 3）。
```

觸發過的實例：#325 階段二刪除 `migrate-work-types`（退場即刪，
`no-compat-fallback`），本表的那一列因此在同一個變更裡改為劃掉標記。
**這個方向是 #325 才補的**——#259 雙向化時只想到「命令長出來」，沒想到
「命令退場」，因為當時還沒有任何命令退場過。

## 識別碼寫入面的裁決（#394，2026-08-24）

本 change 新增了五個識別碼欄位（`venue.issn`／`organization.ror`／work 的 `doi`・`pmid`・
`isbn`），而**兩面都沒有為它們新增參數**。這不是遺漏，是一個要寫下來的裁決——依本檔的
規則，新增能力時必須裁決兩面，而「兩面都不給」也是一種裁決。

| 面 | 現況 | 裁決 |
|---|---|---|
| MCP 寫入面（~~add_venue~~／~~update_venue~~／~~add_organization~~／~~create_entry~~）| ~~不收識別碼參數~~ → **四格全部補齊（#394，2026-08-28）**：`update_venue.add_issn`／`add_venue.issn`／`add_organization.ror`／`create_entry` 的 `doi`・`pmid`・`isbn` | ✅ **這一列已關閉** |
| CLI 寫入面（同名命令）| `update-venue --add-issn`／`add-venue --issn`／`create-entry` 的 JSON draft 收 `doi`・`pmid`・`isbn`；`add-organization` 是 **MCP-only**（本檔既有裁決，不是缺口）| ✅ |
| 既有的 person ORCID 欄位 | **兩面都收**（經 generic `fields` JSON object，#68 的既有形狀）| ✅ 既有，本 change 只改型別不改介面 |

> **這張表的第一欄刻意不用反引號包 token。** `parity-table-drift.py` 把表格第一欄的
> 反引號 token 一律當成「宣稱存在的 CLI subcommand」並去 `CLI.swift` 對照——第一版把
> `person.orcid`（一個**欄位**）放在第一欄，於是守衛報「表列了 `person.orcid` 而它已不在
> CLI.swift」。守衛沒錯，是我的表格形狀在對它說謊。

**缺席的理由**：識別碼的來源目前只有兩條——遷移（`migrate-identifiers`，一次性）與匯入
（`import-wos`／`import-zotero`，走 `fields` 殘留再由遷移升格）。**沒有第三條路徑產生
識別碼**，所以現在加寫入參數是替一個還不存在的流程造介面。

**但這一列必須標記為弱，理由要寫出來**：遷移之後，若使用者查到一筆 work 的 DOI，
**沒有任何面寫得進結構化欄位**——實測 `entry.doi` / `v.issn` / `org.ror` 在
`Sources/` 內的 production 寫入路徑**零命中**（`IdentifierMigration` 與 YAML 編解碼除外）。
唯一的路是手改 YAML。

這正是 `replace-endnote-and-zotero` 第 4 條要防的形狀：

> 使用者說「這個功能我回去用 Zotero 做」一旦變成常態，就是取代失敗的樣子——而且它是
> **安靜的**失敗，因為每次個別繞過都看起來很合理。

**venue 那一格已於 2026-08-28 補齊**（`update-venue --add-issn`／`akashic_update_venue` 的 `add_issn`）。動手的理由不是等到了實例，是相反的：`Venue.issn` 的欄位、型別與正規化都已存在，而**只差一個參數**——把它留著等一個實例，等於讓「查到 ISSN 卻只能手改 YAML」這件事在下次真的發生時才被修，而手改 YAML 的失敗方式是安靜的（2026-08-28 實測差點弄丟一筆 DOI）。

**`add_venue` 與 `add_organization` 同日補齊，理由與 venue 那格同**：欄位、型別、正規化都已存在，只差一個參數；而建檔時本來就知道刊物的 ISSN 與機構的 ROR，少了它得「先建再更新」——一次操作變兩次，中間有一個識別碼不在的狀態。

**形狀刻意不同**：ISSN 是**清單**（print 與 electronic 是兩個真的號），ROR 是**純量**（一個機構只有一個）。兩者都是「不合法即整個呼叫拒絕、零寫入」——建檔面的拒絕比更新面更強：若守衛只擋識別碼而讓記錄建了出來，結果是一筆「使用者以為帶識別碼、實際沒有」的記錄，比明確失敗更糟。

**`create_entry` 同日補齊，這一列因此關閉。** 理由與前三格相同（欄位、型別、正規化都已存在，只差一個參數）。

**`.bib` 匯入路徑刻意不帶結構化識別碼**：`.bib` 的 `DOI = {...}` 進 `fields`，走**殘留路徑**由 `migrate-identifiers` 升格。在匯入端順手升格會製造第二條升格路徑，而那條路徑對「解不了的 token」的處置與遷移端不同（遷移把它留在殘留並報出來），兩者會分岔——這正是同日 #424 修掉的那個 bug 的形狀（一個 `return` 綁兩個決定）。

**這一列關閉後，`replace-endnote-and-zotero` 第 4 條在識別碼這一格不再有「回去用 Zotero 做」的理由**——查到一個識別碼之後，四個寫入面都收得下。那時要裁的
不只是加參數，還有**它該長什麼形狀**——`person.orcid` 走 generic `fields` object，而
`venue`／`entry` 的寫入面目前沒有對應的 generic 通道（`update-venue` 只收 `key`）。
追蹤：#394 close 前不處理；本列即是那個「已知且具名」的缺口。

## CLI 橫切選項裁決表（封閉列舉——#310 一次性補裁 2 項、#298 增第 3 項；恰 3 項，一格不多一格不少。**不得依性質相似類推第四項**）

前兩張表的行分別是「MCP tool」與「CLI subcommand」。**橫切選項兩者皆非**——它是
`ParsableArguments`，被所有帶它的 subcommand 共享，不屬於其中任何一個。所以問題從來
不是「該填哪張表」，是**沒有表可填**：`--library` 因此從未被裁決過，而稽核程序的 ②
（枚舉 subcommands 陣列）在結構上也讀不出這件事。這是收錄機制的洞，不是漏填一列。

新增橫切 `ParsableArguments` = 在這張表加一列。**「未決」同樣不是選項**（與前兩張表
一致）。裁決用語沿用 CLI-only 表的定義。

| CLI 能力 | 裁決 | 理由 |
|---|---|---|
| `--library`（`LibraryOptions`，橫切 42 個 subcommand）| 有理由缺席（#310）| **MCP 已有對等能力，只是粒度不同**：`akashic_files` 的 `use` action 是 session 級切換（改寫 `AkashicService` 的 `root`／`storeKey`，其後所有 tool 作用在新 universe；`testFilesUseSwitchesUniverseCompletely` 已斷言「舊 universe 內容不得洩入」），與 App 的 `AppState.switchFile(key:)` 同形。per-invocation 形式適合 CLI，是因為每次呼叫都是獨立 process、沒有可承載選擇的 session；MCP 與 App 都是長 session，**MCP 對齊的是 App 不是 CLI**。不補 per-call 參數的三個理由：(a) 對等能力已存在（上述）；(b) 選填參數對 LLM 消費端是**淨負**——省略即靜默落到預設 store，寫入類 tool 可能在呼叫者毫無察覺下寫錯，而 CLI 省略 `--library` 的人正看著自己的 shell；(c) 命名衝突（見下方註）使新參數必須另取名字，於是同一個 tool 並存兩個意義相近而所指不同的參數 |
| `--config`（`FileConfigOptions`，`file` 家族 4 個 subcommand）| 有理由缺席（#310）| **部署層決定，非呼叫層**：registry 檔的位置由 MCP server 的啟動環境（`AKASHIC_HOME`）決定；讓個別 tool 呼叫改指另一份 registry，等於讓 LLM 消費者改寫部署決定。與 `--library` 不同的是**這裡連 session 級的對等物都不需要**——切 registry 不是切 universe，是換掉一整組 universe 的名冊 |
| `--yes`（`LibraryOptions`，只對 6 個破壞性 subcommand 生效）| 有理由缺席（#298）| **閘門本身不作用於 MCP，所以它的出路也不需要**。`--yes` 是「破壞性 `--apply` 未指名目標 store 時的知情同意」的出路（#298 D4），而該閘門刻意只擋 CLI：CLI 的 `--apply` 是**篩選式批次掃蕩**，MCP 的 apply 收**逐 id 顯式指名**的清單——與本表上方 `resolve-people` 列已記錄的 tier 閘同型不對稱。#310 的「顯式性在 MCP 面恆為否」因此不綁：閘門不在那一面。若日後 MCP 長出篩選式批次寫入，該閘門與本旗標的 MCP 面須一併重新裁決 |

> **命名衝突（#315）**：`library` 這個字在兩面**意義不同**——CLI 的 `--library` 指
> **store root 路徑**；MCP 的 `library` 參數（`akashic_search`／`akashic_person` 等）
> 指 **store 內的 membership 分類**（#13）。所以就算日後推翻上表第一列的裁決，新參數
> 也**不能**叫 `library`。

**機械檢查**：稽核程序的 ④ 枚舉全部橫切 `ParsableArguments` 後，輸出的每一項都必須
出現在本表——查無即是新長出的零裁決格。

### 由上表衍生的一則事實：MCP 的 active store 是 session 狀態

上表第一列的裁決把一件事固定下來，而下游設計會需要它，所以在此寫成可直接引用的形式
（引用者不必回頭讀原始碼）：

> **MCP 面的 active store 是 session 狀態。** 它由 server 啟動時解析一次，並可在
> session **中途**經 `akashic_files` 的 `use` action 改變（改變後所有後續 tool 呼叫
> 都作用在新 store）。**呼叫端不會在每次呼叫時重新宣告它** —— 依上表裁決，MCP tool
> 沒有、也不會有 per-invocation 的 store 參數。

**直接後果**：任何以「**本次呼叫有沒有顯式指定 store**」為判準的機制，在 MCP 面
**恆為否**，因此不可作為判準。若某個閘門以此為條件，它在 MCP 面只會退化成兩種都錯的
結果——一律擋（所有寫入類 tool 失效）或一律豁免（LLM 消費面完全不設防，而它的呼叫量
與誤呼叫機率都高於人工 CLI）。

**這則事實不裁決替代方案。** 它只說明「顯式性」為什麼不能用；該用什麼判準屬於提出該
閘門的變更（#298）的範圍，不在本規則內。

## 為什麼：缺口是安靜累積的

兩張註冊表（`Server.swift` 工具表、`CLI.swift` subcommand 表）獨立生長，能力新增
落在 `AkashicService` + `Server.swift` 就能出貨——**沒有任何東西強制在那一刻想起
CLI 使用者**。失敗史：

- **#206**（2026-08-09）：無損匯入只有 MCP 有——家族第一例，當下以「繞過 CLI 用
  stdio 驅動 MCP」workaround，並留下上面那句判準
- **#218**（2026-08-10）：`person` 檢視只有 MCP 有——CLI 能**改寫** person 記錄
  （`update-person`）卻讀不出一筆
- **#219**（2026-08-10 開、08-12 修）：逐格盤點發現**一族六格**（含 #218 那格）
- **#250**（2026-08-12）：#219 開立後**兩天內**，同族又長出兩格（`add_person`／
  `divergences`）——本規則寫下前的最後證據：不修流程，格子必然繼續長
- **#259**（2026-08-15 收口）：規則落地時只綁 MCP 方向，反方向 12 個 CLI-only
  能力零裁決（含 #206 鏡像的 `import-wos`）——雙向化＋一次性補裁即本表的由來

把失敗史留在檔內，是因為只留結論的話，日後維護者會覺得「這條寫得囉嗦、我幫它
精簡」而把裁決力刪掉（見全域 `common-spec-prose-enumeration.md` 執行細節 3）。

## 跟其他規則的關係

- `entity-backlink-completeness`（執行細節 2）：管「同一格的兩面必須落到同一條
  實作路徑」；本規則管「每一格必須被裁決要不要有兩面」。先有本規則的裁決，才輪
  到那條的單一路徑。
- 全域 `common-spec-prose-enumeration.md`：上表是封閉列舉 + 機械稽核程序，不寫
  總括判準——「工具該不該有 CLI 面」的判準存在（見上），但它的**輸出必須落回表
  裡**，不允許讀者拿判準自行類推出沒寫下的裁決。
