# venue 的 `authorized` 有了判定型寫入面——而它不是 append，這是端到端測出來的（#554）

## #471 只修了一半

`Venue` 有兩個對 `names` 的互斥標記：`authorized`（對外形）與 `variant`（異寫）。#471 補了
variant 的寫入面。`authorized` 那一半原封不動：唯一寫入者是 `VenueBootstrap` 取第一個名字的
慣例，立案時實測 479/479 筆恰是 `[names[0]]`（494 筆 venue，#553 合併前；合併併掉 9 組後
485 筆、470/470——兩個數字是同一件事在兩個時點，不是「9 筆非拉丁 authorized」）。
`addVenue` 則**不寫**，走 #227「建檔不機械偽造」。

#553 讓它變尖銳：攣生合併把被併記錄的 authorized 降成倖存者的 variant，工具逐筆提醒，
但沒有面能改回來。

## Plan 的前提在真 binary 上死掉

Plan 照 `add_variant` 寫成 append。四條測試綠、負控紅。然後對副本跑 JRSS-B：

```
Error: 在書寫系統 latn 有 2 個 authorized（…）——那是未決的問題，不是指定；請選一個
```

`AuthorizedNames.validate` 有「**每書寫系統至多一個**」的內容約束。470 筆 venue 已有一個
latin authorized——對它們，append 第二個 latin 名**必被擋**。而那 470 筆正是立案事實。
**測試綠是因為 fixture 的 authorized 是空的**：它涵蓋了「尚無 authorized」與「跨書寫系統」，
剛好漏掉唯一重要的那格。

要換掉機械值需要**替換**：X 成為對外形、同一個 `WritingSystem` 的舊指定 Y 移出。命名回到
`authorize`——叫 `add_*` 會說謊。不同 `WritingSystem`（han／latn／other）之間仍是 append。

## R1 verify：我替呼叫端多說了一句話

第一版把 Y **降成 variant**，理由是「跟 #553 合併端對稱」。R1 verify（5 席，Codex 429 缺席）
的 DA 席指出這句話的問題：呼叫端只說了「X 是對外形」，程式卻寫了兩句——X ∈ authorized、
**Y ∈ variant**。第二句是程式推論出來的分類判定，而 `venue-entity` spec 明寫「A name in
neither is unclassified … it makes no claim either way」——未標才是誠實狀態。這與 #554
立案時對 #553 的原始指控（「改變的是分類」）同型、反方向重演。

DA 還實測了一個零實例的形狀：沿革前身（`names` 帶 `start`／`end`）被 `--authorize` 後繼刊名
→ **整個呼叫被拒**（variant 不得帶時間欄位）且無出路。zero-instance 第 22 列保留沿革就是
為了讓它有位置可落，而第一版把「後繼名成為對外形」這一步堵死了。

**裁決（使用者 2026-09-12，D1）：Y 移出 authorized、留在 names、不標 variant。** 報告鍵從
`demotedToVariant` 改成 `authorizedRemoved`——說程式做了什麼，不說結果是什麼分類。

同一輪的 HIGH 是我自己的禁令再犯一次：對「同一字串既送 `add_variant` 又送 `authorize`」
我寫了「不能讓哪段先跑決定誰贏」並在入口拒絕，但**同一參數內**兩個同 `WritingSystem` 的
名字沒擋——迴圈第 N+1 輪把第 N 輪剛升上去的當舊指定移出，陣列順序決勝，報告
`authorized: [A, B]` 而 `authorizedTotal: 1`。四席各自在真 binary 重現。修法同型：
先濾掉空白項、再按 `WritingSystem.of` 分組，任一桶 >1 整批拒絕零寫入。

## 報告每個分類改變都說出來

`authorizedAdded`（升）／`authorizedRemoved`（移出，未標）／`liftedFromVariant`（從 variant
拉回——本面的主要用途，第一版沒報）／`alreadyAuthorized`（no-op，但與「空白被跳過」分得開）。
`lossless-intake` 執行細節 3：分類的改變要可見。

R1 第 11(b) 列「降級報告排除本次 add_variant 已列的」在 D1 下**重裁而非套用**：`add_variant Y`
＋ `authorize X` 同呼叫時，`variantAdded: [Y]` 是「呼叫端把它放進 variant」、`authorizedRemoved: [Y]`
是「它被移出 authorized」——兩個事實各印一次，不是同一件事印兩次（R1 的 `demotedToVariant`
才是後者）。

## R2 verify：我把 D1 之前的量測抄進了 D1 之後的規則

R1 report 第 8 列寫「近重複 fail-closed 零寫入」，量的是 R1 的行為（舊名進 variant，
`validateDisjointPartitions` 有交集可撞）。D1 把舊名留在未標——一個 `Venue.validate()` 完全
不看的分割——同一句話就變假了，而我把它原封不動抄進 parity 列與 #560。R2 五路獨立命中
（四席＋Codex 盲審）：`--authorize "Psychometrika "` 對既有 `[Psychometrika]` **寫入成功**，
帶空白版成為 displayName、`validate` 全綠。

修法：authorize 段的成員判定全部改走 `NameIdentity.canonical`（與守衛同一條）——x 若
canonical-命中既有 names 條目就用 store 拼法、不新增近重複條目；跨參數矛盾與同書寫系統
衝突也在 canonical 上算。順手收掉同輪的三格：`.whitespaces` 不含換行（`$'\n'` 曾成為
displayName）→ `.whitespacesAndNewlines`，純標點／純數字整批拒絕「不是名字」；衝突訊息
`Dictionary.first(where:)` 隨 hash 種子挑桶 → 依 rawValue 排序、全部桶一次印；`alreadyAuthorized`
短路跳過同書寫系統移出 → 確認既有值時也移出另一個（守衛說「請選一個」，選了就該修好）。

DA 席另抓兩個 D1 的後果：合併端的降級提醒對「已在倖存者 names、未標」的名字也說「成為
variant」（比的是 `keeper.authorized`、濾的是 `keeper.names`）——改成三種結果分開說，並拿掉
「用 `--authorize` 改回」那句祈使建議（照做會把人工指定移出）；`migrate-venue-variants` 的
補集規則會把 D1 的未標重新標成 variant——使用者裁決 D4：開退場 issue（#567）、本輪在 parity
列與命令 help 寫明不得再跑。

## R3 verify：相等沒有「局部正確」

R3 只把 `authorize` 一段改走 canonical。R3 verify 六路獨立命中（四席＋DA＋Codex）同一個殘餘：
**一個函式裡兩種相等**。`add-name "X "`（精確迴圈）種下髒條目、`authorize "X"` 把它升成
displayName；全新的輸入存原樣、之後以「用 store 拼法」黏住——乾淨拼法永遠進不了 authorized。
其中一條路對 R2 是 regression（精確比對版本在那條路反而是對的）。

#560 在 R1 就寫著「要改就三個迴圈一起改，不要只改 `authorize` 那段——只改一段會製造第三種
相等」。R3 把它當範圍外。**使用者裁決 D6：三個迴圈一起改**——同一組謂詞（空白／控制字元／
不是名字）、同一條相等（先精確、次乾淨拼法、再 canonical）、新條目一律存 canonical；`already`
時以 x 取代全部 canonical-相等的拼法；x 插回原位（remove＋append 會讓雙語 venue 的預設
displayName 換書寫系統）；variant 拉回移除全部 canonical-相等條目。#560 的程式缺口由本輪關掉。

同輪順手：`×`／`÷` 落在 `isLatinLetter` 的區間裡被歸 `.latn`、R3 的「`.other` 且無字母」放它過
——改成任何書寫系統都無字母即不是名字（分類器本身的問題另開 #568，它是 person 共用的）；
bidi override／零寬字元夾在字母間原樣進 authorized → 三個迴圈入口一起拒絕（ZWJ／ZWNJ 保留）；
`migrate-venue-variants` 自己那列與 README 補「不得再跑」；MCP `akashic_record_divergence` 的
candidates 描述補 venue（與上一輪順手修的 CLI help 對齊）；`DivergenceResolve` 裡一句 #553 從
person 路徑抄來的「前置已確認是子集」拿掉。

## R4 verify：閘的位置

R3 的 14 列全部在位。R4 verify 的 finding 集中在一個結構問題：我把名字內容的閘裝在
`updateVenue` 的三個迴圈裡，而同一個 `names` 欄位還有兩個寫入者沒經過它——`addVenue`
（`add-venue --names`／`akashic_add_venue`，原樣存入、連空字串都收）與 `VenueBootstrap`
（只 trim）。`akashic-verify-venue` skill 明文教 LLM 店裡沒有就走 `akashic_add_venue`，
所以 R3 第 1 列「髒種子黏住、乾淨拼法永遠進不了」換個入口就重現。`Venue.swift` 自己的
dated-variant 守衛 doc 早就寫著答案：「守衛住在 validate → writeVenue 的交會處才擋得住
所有路徑」。四輪、同一個形狀的四個變體：R2 在 authorize 精確相等 → R3 只 authorize 走
canonical → R4 三個迴圈一致 → R4 verify 指出第四、第五個寫入者。

另外三個 MEDIUM 都是 R4 自己引入的：`forbiddenScalar` 是 **19 個例子的列舉**、doc 寫的是性質
——170 個 Cf 漏 149（ALM、96 個 TAG 字元），且與 `AkashicCore.UnsafeToEmitScalar` 是分岔的
第二份副本（輸入放行、輸出逃脫）；Codex 盲審抓到去重先於驗證——`["New Journal", "New\tJournal"]`
靜默略過、反序整批拒絕，合法性隨陣列順序改變；DA 抓到「先精確」在 Swift 裡不存在——
`String ==` 是 canonical equivalence，NFD 輸入命中 NFC 條目後回傳**呼叫端的 NFD 位元組**寫進
authorized，Swift 讀者全綠、所有 Python 量測看到 `authorized ⊄ names`。還有一個真反例把
「沒有字母就不是名字」打掉：*1843*（The Economist 的雜誌）、*2600* 是純數字刊名。

**使用者裁決 D8：不變式搬到 store 邊界。** `Venue.validate()` 對 names／authorized／variant
逐條驗（error 級）：canonical 形、不含控制／格式字元（與 `UnsafeToEmitScalar` 同一份定義再加
整個 Cf／Cc／Zl／Zp 類別；ZWJ／ZWNJ 只在兩個字母或標記之間）、至少一個字母**或數字**、names
內無 canonical-相等對；謂詞一份在 `NameIdentity.wellFormednessIssue`。所有寫入者存 canonical：
`updateVenue`（`vetVenueNames`：canonical → 逐項驗 → 去重）、`addVenue`（同一個入口）、
`VenueBootstrap`。相等只有一條：canonical 查找、回傳 store 條目。手改出來的違反在下一次寫入
被 validate 具名擋下、零寫入——不猜、不靜默修；唯一的自我修復路是 authorized 裡同名不同
位元組（NFD）的舊指定被換成 canonical 並報在 `authorizedRemoved`。三席各自量過 live store
485 筆 venue：0 筆違反——提級不拒絕任何既有記錄；`zero-instance-guards` 第 25 列記著這一格
（實例全部是三輪 verify 在 scratch store 造出來的）。

**本輪自審抓到一條空洞的測試**：R4 verify 第 6 列要「拼法修正出聲」，我寫的測試斷言
`out.contains("\"authorizedRemoved\"")`——那個鍵永遠在，測試對任何輸出都綠。改成解析 JSON 斷言
內容，並發現 `y != x` 用的是 Swift `==`（NFD 看不出來）——改成位元組比較。

誠實邊界兩條：NFC 對 CJK 相容表意文字有損（U+FA10 塚 → U+585A；位元組層有損、Swift 層
無損）；輸出閘 `UnsafeToEmitScalar` 對 Cf 仍是列舉（TAG 字元在錯誤訊息裡原樣印出）——#569。

**不留 judgement**（D2）：與 person `authorize-names`（#81）、`add_variant`（#471）一致——
三個名字分類面要不要留、留什麼形狀一次裁（#564），本 change 不在這裡單獨定案。代價寫在
#553 合併端那格：它仍分不出「人確認過的 names[0]」與機械值，維持提醒不擋，觸發條件改綁 #564。

## R5 verify：性質要用 Unicode 自己的那個

R4 的 14 列全部在位。R5 verify 18 列、五路命中的兩條 Blocking 都在**謂詞自己身上**：

**「不可見」我又寫了一個列舉。** R4 verify 抓「19 個例子 → 性質」，R5 換成 generalCategory
四類（Cc／Cf／Zl／Zp）——那還是一個列舉，只是大一點。Unicode 對「不可見」有自己的性質
`Default_Ignorable_Code_Point`（UAX #44；UTS #39 confusable 用的那個），而它的成員橫跨
分類：VS16（U+FE0F，網頁貼上常見）與 CGJ（U+034F）是 **Mn**、Hangul filler（U+3164）是
**Lo**。DA 用真 binary 把 `心\u{FE0F}理學報`／`心\u{034F}理學報`／`心理學報` 存成三筆「不同」名字，
`add-venue --names $'\u{3164}'` 建出一筆 displayName 空白的 venue——而 Hangul filler 還滿足
「至少一個字母」。R6：`isDefaultIgnorableCodePoint` 一律不可見，四類 generalCategory 與
`UnsafeToEmitScalar` 留著（三份定義的聯集，每一份都是性質）。

**joiner 規則比它的 doc 寬、比真實文字窄。** R4 的 `joinable` 只查兩側是字母——拉丁字母就是
字母，`Psycho\u{200C}metrika` 通過；canonical 不刪它、不是近重複對、`--authorize` 走同書寫
系統替換把真名移出、joiner 版成為 displayName，報告印兩個視覺相同的字串。doc 逐字寫「拉丁
字母間的 joiner 重開通道」，而 R4 的測試 doc 也這樣寫、五個斷言裡沒有一個放「拉丁—joiner—
拉丁」——**測試 pin 不住它自己宣稱的性質**，本張第二次。反方向也錯：legacy Malayalam
chillu（consonant＋virama＋ZWJ **詞尾**）與波斯文 `۱۴۰۰\u{200C}ها`（**數字**＋ZWNJ）被拒。
**Claude 代裁 D9**（使用者離席）：合法脈絡封閉為兩支——前一個 scalar 是 virama、或兩側都有
非空白鄰居且任一側在使用 join control 的書寫系統區塊（Arabic 一族／Syriac／NKo／Indic／
Myanmar／Khmer／Mongolian）——它同時修正兩個方向；`NameIdentity.joinerIsLegal` 是那兩支，
row 25 的 Python 對照鏡射它並以固定案例對照（R5 的 Python 無條件拒 Cf，對合法波斯文與 Swift
分歧——「485/0/0」證不到兩套判準一致，Codex 抓到）。

**一個撕裂與一個刪除，都是 D8 新開的。** DA 逐一列舉 venue 寫入者，找到 `resolve-venues
--apply` 的順序是 entry 先落盤、`writeVenue`（verdict）之後才 throw——手改一筆尾隨空白的
venue 後 apply：entry 已升格成 `.key`、verdict 沒落、錯誤訊息像「什麼都沒寫」。這個撕裂
在 D8 之前是理論（venue 的拒絕條件只有三個罕見形狀），D8 把觸發集合擴到最常見的手改痕跡。
**D11**：apply／repoint／demote 改成 venue 先過 `assertVenueWritable` 再寫 entry（`rename`
那條早就是這個形狀）。刪除那半：`canonical` 在 **Character** 上切空白，`Character.isWhitespace`
只看 cluster 首 scalar，「空白＋combining mark」整個 cluster 被當空白刪掉——`add-venue
--names $'Jour ́nal'` 存成 `Jour nal`、零回報，違反該型別自己的「不做任何字元刪除」；D8 讓
每個寫入者都走它。R6 改逐 scalar、只丟 `White_Space`。

其餘 in-scope 的都修了：names 近重複對對**同名的不相交沿革段**豁免（`TimelineOf` 明寫同一
value 可在多段，Sankhyā 1933–1960 → 2002–2007 合回同名那筆在 R5 寫不進去、「人改 YAML」沒有
合法結果；authorized／variant 沒有時間軸，那兩張清單也掃、沒有例外）；`VenueBootstrap`
被謂詞拒的 literal 路由到 `dropped` 帶理由（R5 在分組前 `continue`，連 occurrences 都不累計，
同一個型別的 doc 寫著「不靜默丟」）；`fmt` 的 `.venue` 分支與 `.person` 同樣跑 validate
（R5 的裸 `encode(decode)` 讓 `fmt --check` 對 validate 報 error 的 store 印 ✓）；合併 dry-run
對預測的 keeper 過同一道寫入閘（keeper 計算抽成 `mergedVenueKeeper`，preview 與實跑共用
——#139 F1 第三次）；訊息改對操作者說改什麼（R5 寫「寫入者要先 NameIdentity.canonical」，
那是一句 Swift）；`add-venue --names`／`akashic_add_venue` 兩面描述補齊、parity 列重新確認；
`store-format.md` 加 §5.7 規範段（四條不變式、修法、**三 binary 全升才視為生效的部署視窗**
——沒有 format bump，refuse-if-newer 管不到、PyYAML 讀純數字刊名的註記）；row 25 計數改
「五個寫入者」、grep 補「沒有名字」與兩個新類、row 8 補記它的前提自 #227／#422／#473 起對
venue／organization 就已為假（DA 更正兩席：不是本 diff 第一個打破它）；#562 的 grep 又漏了
R5 自己加的 `vetVenueNames` join——第三次抄一個沒跑過的計算式，改成行內 `map { displaySafe }
.joined` 讓它看得到。**D10**：`migrate-venue-variants` 維持 D4 不加閘（DA 的更正成立：R5 再
立案是重審裁決）；logic 席「store 表達不了『已跑過 --authorize』這個前提」那句落到 #567
——那是「退場即刪」優於「加閘」的論證。

負控四條（joiner fail-open／拿掉 DI／canonical 回 Character 層／拿掉沿革豁免）各紅
12／11／8／1；撕裂、fmt、preview、bootstrap 四條在 RED 階段就是負控。真 binary 端到端：
五類拒絕各印一句、波斯數字與 chillu 收、combining mark 留著、髒 venue 上 apply 零寫入且
修 YAML 後成功、`fmt --check` 與 `validate` 都具名、bootstrap 印出 `×` 帶理由、Sankhyā 三段
收而重疊拒。live store 485 筆：Swift 與 Python 兩套量測都是 0／0。

## R6 verify：封閉列舉在邊界上長出的答案

R5 的 17 列全部在位；R6 verify 49 列、零 Blocking、4 MEDIUM。這一輪的 finding 幾乎都是 D9 兩條
封閉規則的**邊界**——正是 `common-spec-prose-enumeration` 說的那件事，只是這次是我自己寫的
列舉：

**區塊成員資格不是充分條件**（Codex）：Unicode 區塊含標點，`A\u{200C}،B` 因逗號落在 Arabic
區塊而通過——ZWNJ 沒有接合用途，只是通道。security 席補了一格：連續 joiner（`ا\u{200C}\u{200C}ب`）
在合法脈絡裡放行，字型忽略重複，同樣是「看起來一樣、canonical 不相等」的殘餘；virama 分支不要求
virama 掛在印度系字母上（`Psychometrika\u{094D}\u{200D}` 通過）。R7：兩側都要是 join-control 文字
的**字母／標記／數字**、鄰居不得是 joiner、virama 要掛在字母上。反方向兩席各自實測：清單漏了
Mandaic 與 Syriac Supplement——它們就夾在 Syriac 與 Arabic Extended-B 之間，是疏忽不是裁決——
以及 Adlam／Hanifi Rohingya／Tifinagh／Sogdian／Old Uyghur／Manichaean／Arabic Extended-C；補齊，
Python 對照同批。

**DI 一律拒的代價要寫出來**（requirements／regression／logic 三席）：CJK IVS、蒙古文 FVS／MVS、
希伯來文 CGJ、emoji ZWJ 序列、德文抑制連字的 ZWNJ 全部被拒。它們是 fail-closed（訊息具名、
零寫入），不是靜默損失；書目資料裡機率極低。**維持 D9**，但 §5.7 與 doc 把這一整組寫成誠實邊界
——R6 只記了 NFC 對 U+FA10 有損。DA 更正 logic 席的歸因：蒙古文的 joiner **確實**通過（清單對它
不是空的），被拒的是 FVS／MVS，走 DI 分支——所以要翻的話翻的是 DI 例外表，不是區塊表。另一個
三席都沒收的碼位：U+2800 BRAILLE PATTERN BLANK（So，渲染成一格空白）——顯式列進謂詞。

**沿革豁免把 `DateRange.overlaps` 用在放行方向**：那個函式做字串比較，`end: "1960"` 對
`start: "1960-06"` 判「在前」——它一直是給提醒用的（多報安全），本輪第一次拿它當放行條件就
fail-open；DA 補了反方向：端點相等（spec 自己的銜接年慣例）被判重疊、attested-only 段永遠進不了
豁免而訊息說「修時間欄位」。R7：豁免用自己的 `segmentsAreDisjoint`（一段有 end、另一段有 start、
較粗粒度截斷後嚴格早於；端點相等與 attested-only 都不豁免），訊息與 §5.7 把「不相交」定義寫清楚。
Codex 另抓到 Python 對照的近重複豁免根本沒看重疊——「485/0/0」在這一格證不到兩套判準一致；R7
的腳本鏡射同一個判準並加七組固定案例。security 席量到近重複掃描是 O(n²)（3,000 筆 5.75 s）——
`add_names` 無上限、無移除面，一個被灌滿的 venue 之後每次寫入與每次 doctor 都付這個代價；改成
先以 canonical 鍵分組。

**「D8 不進 spec」我說記了、其實沒記**（requirements 席，MEDIUM）：R6 的 scope note 寫「記在
parity 列」，diff 裡零命中；而 §5.7 自稱「cross-binary 契約」又說「不是 published contract」。
spec 已有兩條同形的 validate-time Requirement（互斥、variant 不帶時間），D8 的四條該是第三條——
那要走 spectra-propose，#554 不做。R7：§5.7 改成「store 契約，與 §3.4 同級；spec Requirement
是 #570」，parity 列真的把裁決寫下來。

**repoint 對懸空 from-key 是 crash 不是拒絕**（security MEDIUM；DA 更正：base 既有，D11 把它從
「entry 已落盤再 crash」變成「零寫入再 crash」，不是 D11 的 regression）。仍然修：MCP 面上那是
以合法參數殺死 server 的路徑。R7 與 `newKey` 同形的 `guard`，訊息指路 `--demote`。

其餘 in-scope：`mergedVenueKeeper` 原樣搬被併者的名字，被併者若違反不變式，R6 的訊息說
「venue 'keeper' 的 names…請在 YAML 裡改」——那個字串只在 doomed 的 YAML（DA）；R7 在前置檢查
逐筆驗被併者的名字，`doomedRecordInvalid` 指向被併者。`vetVenueNames` 的註解與 #562 comment 說
「原字串 120 ＋ 理由」而程式只對整項截 400，貼錯一整段摘要時被截掉的正是理由——補上 120 的
prefix（三席）。CLI 使用者看到 MCP 鍵名（`--add-name` 拒絕時印「add_names 的」）——參數名兩面
都印。bootstrap 的謂詞拒絕排在「已有 venue」之前，只差一個 soft hyphen 的既有刊名 literal 被印成
「修來源欄位」而它本來就能被 resolve-venues 歸戶——調換順序、理由補上 bootstrap 脈絡的出口。
`fmt --check` 對 validate 失敗的檔仍先印「✓ 全部已是 canonical form」——失敗的檔沒進比對集合，
「全部」是對沒被檢查的說的（第 3 列的形狀，`.person` 也有）。碼位補零到四位。changelog 寫「36 條」
而分項加總與檔案實數都是 38。`two-kinds` 那列複述四條而沒跟上——改成引用 §5.7。#567 comment
的兩句承重的話都要改：「自 #564 起不留 judgement」（#564 還開著，不留是 #554 自己的 D2）與
「閘寫不出來、能寫的只有刪」（DA：`format < 14` 就是一個可判定的閘；D4／D10 的「刪」維持，但
理由是 `no-compat-fallback` 第 3 條，不是結構上不可能）。#569 body 仍描述 R5 版輸入閘、且 R6 開了
三個印「已知含不可見字元」字串的 sink（bootstrap 的 dropped 行、`vetVenueNames`、`Venue.validate()`
的訊息）——留言補記。

不動的：合併端與 `resolve-venues` 的 entry 側撕裂（pre-existing，D11 只管 venue 側——regression
席自己標 INFO）；record-divergence help 的 #553 順手改（R3 起每輪都記）；訊息在寫入面說
「刪掉這一筆」的措辭代價（DA 第 46 列，接受並寫進 §5.7）。

## 第二次端到端又紅——這次是我的 binary

改成替換語意後測試 7/7 綠、四個 mutation 負控乾淨，真 binary 卻說「authorized 含不在
names 內的名字」。隔離半天，最後是：**`swift test` 不重編 `akashic` executable target**，
`.build/debug/akashic` 是改 service 之前的版本。`swift build` 印 `Build complete! (0.17s)`
是快取；`swift build --product akashic` 花 3.31s 才是真的重編。

驗法：`grep -a -c '<這輪新加的字串>' .build/debug/akashic`——版號不會說謊但也不會說話，
新字串在不在才是證據。已記 memory（`swift-test-does-not-rebuild-executables`）。

## 落地

- `updateVenue` 加 `authorize: [String]?`；CLI `--authorize`、MCP `authorize`，兩面同批
- 41 條寫入面測試（R1 的 7 條改語意 ＋ R2 新增 5 條：同書寫系統兩名拒絕／沿革前身保留時間／
  確認既有值報 `alreadyAuthorized`／兩邊空白不是矛盾／呼叫端自己 `add_variant` 才進 variant
  ＋ R3 新增 7 條：近重複不是替換／近重複用 store 拼法拉回／跨參數近重複仍是矛盾／控制字元
  與純標點不是名字／衝突桶排序全報／重複字串只報一次／確認既有值仍移出同書寫系統的另一個
  ＋ R4 新增 11 條：新名存 canonical／精確拼法優先且修正 authorized 拼法／`add_names` 近重複不加／
  `add_variant` 近重複不加第二筆／同呼叫髒 add-name＋乾淨 authorize／`×` 不是名字／bidi 與零寬拒絕
  但 ZWJ 保留／替換原位／兩筆近重複 variant 都拉回／手造兩個 canonical-相等 authorized 修好／
  三個迴圈同一個空白——後三條在 R5 重裁成「手改的違反被 validate 具名擋下」
  ＋ R5 新增 6 條：順序無關／NFD 存 NFC 位元組／ALM 與 TAG 拒絕／純數字刊名收／NFD 舊指定修正
  且報出／`addVenue` 存 canonical 且驗
  ＋ R6 新增 2 條：apply／demote 對不可寫的 venue 零寫入 ＋ R7 新增 3 條：repoint 懸空 from-key 具名拒絕／
  參數名兩面都印／長輸入理由不被截）；`VenueNameInvariantTests` 22 條
  （R5 的 8 條 ＋ R6：拉丁／CJK joiner 拒、join-control 文字的 joiner 收、DI 不可見、訊息對操作者、
  沿革同名豁免、三張清單近重複、bootstrap 拒的 literal 帶理由 ＋ R7：區塊標點與外文鄰居拒、連續 joiner
  與浮動 virama 拒、草書文字補進區塊表、U+2800、碼位補零、豁免對粒度與端點保守、bootstrap 先問已有 venue）；`NameIdentityTests` 加「不刪
  任何非空白 scalar」；合併端 14 條（三種結果各有測試 ＋ dry-run 對不可寫的 keeper 拒）；
  `CanonicalFormatValidationTests` 加 venue 語意驗證
- `record-divergence --candidate` 的 help 與 MCP `candidates` 描述補 venue（#553 遺留，兩面對齊）
- `mcp-cli-parity` 的 `akashic_update_venue` 列補記；`two-kinds-of-edits` 加一列、#553 那列
  理由改寫；`DivergenceResolve` 四處「venue 沒有 authorize 面」的文字改指向本面

## 不做（都有 issue）

- 撤回面（把名字從 authorized 移出而不放新的進去）——#559
- judgement 記錄——#564（三面一次裁）
- `bootstrap-venues` 是否停寫 `[names[0]]`——#563
- ~~`addNames`／`addVariant` 的 `String ==` vs 守衛 `NameIdentity.canonical`——#560~~ → R4 三個迴圈
  一起改，程式缺口由本輪關掉（issue 留給 idd-close）
- `WritingSystem.isLatinLetter` 的 code-point 區間（×÷ 當字母、全形／越南文拉丁歸 other）——#568
- 輸出閘 `UnsafeToEmitScalar` 對 Cf 仍是列舉——#569（輸入閘本輪已收整個類別）
- `migrate-venue-variants` 退場——#567（本輪只寫明「#554 之後不得再跑」）
- 470 筆的 authorize campaign 與 `akashic-verify-venue` 的 authorize 步驟——#566
- 合併端把併入名字一律標 variant、且丟時間欄位——#565（D1 的同一個論證在合併端）
