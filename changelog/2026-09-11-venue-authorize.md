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
`UnsafeToEmitScalar` 留著（三份定義的聯集——前兩份是性質，`UnsafeToEmitScalar` 本身是與輸出閘共用的列舉，#569 管它；R6 verify 第 44 列抓到我在這裡寫成「每一份都是性質」）。

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

## R7 verify：把「字母」寫成程式

R6 的 19 列全部在位；R7 verify 35 列、零 Blocking、7 MEDIUM。三條都是 R7 自己寫的判準比散文寬：

**virama 分支驗的是 member 不是字母**（Codex）：`joiningScriptMember` 收數字與標記——那是給 (b) 支的
左鄰居用的——virama 分支重用它，`Journal \u{0967}\u{094D}\u{200D}`（Devanagari 數字＋virama＋ZWJ）
通過。DA 補了三格散文比程式窄的：virama 支不看右鄰居（`क्\u{200C}A` 通過）、(b) 支不要求同一文字
（`ک\u{200C}क` 通過）、joiner 夾在基底與它的 virama 或標記之間（`क\u{200D}\u{094D}ष`、
`ا\u{200C}\u{064E}ب`）通過。而合法的 conjunct 形（ka＋nukta＋virama＋ZWJ＋ssa、Khmer coeng、Bengali
khanda ta、Sinhala touching）DA 逐一實測都通過——R8 的收緊不能誤傷它們：從 virama 往前跳過標記找基底、
基底要是**字母**、右鄰居（若在）要是同一文字的字母／數字；(b) 支左收字母／標記／數字、右只收字母／數字、
兩側同一文字（`joinScript` 回文字 id，Indic 每 0x80 一個）。

**`segmentsAreDisjoint` 對非 ISO 端點 fail-open**（三席）：R7 的 `before` 對任意字串做字典序，`2003-1`
（手誤少一位）、`民國49`、`1960 `（尾隨空白）全判「不相交」而豁免；venue `names` 的日期 decode 不驗、
`dateFieldAnomalies` 不掃 venue，三處都沉默。DA 補了那句最痛的：`ISO8601Prefix.isValid` 早就在，
`ISO8601Prefix.compatible` 的 doc 明寫「非 ISO 一律當不相容」——R7 寫了第二套日期比較而沒 grep 既有的
（`grep-doctrine-before-authoring` 記過的形狀）。R8 在 `before` 對兩端各 guard 一次。

**repoint 把 work 的 title 當 verdict literal**（DA，#418 既有）：apply 寫刊名 literal、demote 從 verdict
逐字取回、repoint 卻用 `byCitekey[m.citekey]!.title`——repoint 之後 demote 會把 venue 邊改寫成論文標題，
比「顯示名頂替」更糟，rejected 那一側也帶著標題所以 `rejectedPairings` 對真正的刊名不會抑制。R6／R7 兩輪
在同一函式上動刀、理由都是「保護 verdict 的完整性」，沒有人看那筆 verdict 的 value 寫的是什麼。R8 從
from-venue 的 confirmed verdict 取回，取不到就拒絕改指（與 demote 同一立場）；既有測試的 fixture 因此改走
真的 apply 路徑，手造的裸 key 邊不再是合法的 repoint 起點。同一個函式的另一格（regression 席）：R7 的
懸空 from-key 訊息指路 `--demote`，而 `--demote` 對同一狀態也是 notFound——改成「救回檔案或手改 YAML」。

**D11 的寫入者列舉漏了一個**（DA）：work／person 合併在 `commitResolution` **之後**才對持有被併鍵 verdict
的 venue 跑 `migrateHolderVerdicts` → `writeVenue`，沒有 pre-commit 的閘、preview 也不看——e2e：venue 手改
一筆尾隨空白、dry-run 說 OK、apply 刪了被併 work、venue 留死 verdict（#139 F1 ＋ #460 的合成形，而 R5
第 3 列的 D11 就是為了關它）。R8：`assertVenueHoldersWritable` 在兩個 `validate*Preconditions` 裡先跑
（preview 共用）。

其餘：`doomedRecordInvalid` 只驗會搬進倖存者的名字（canonical 等於倖存者已有的被濾掉，不必為它修一筆
下一步就刪的檔——logic 席）；「至少一個字母」的字母是 L 類不是 `isAlphabetic`（security：一個孤立的
Arabic fatha 曾寫得進去，displayName 是懸空記號——R5 Hangul filler 的同形）；`vetVenueNames` 的 120 以
scalar 計（security：combining-mark 密集的 120 個 Character 是 596 個 scalar）；row 25 Python 的 `before`
對 PyYAML 型別化的 start／end 會 TypeError（logic）——加 `str()` 與 ISO regex；parity 列的 D15 句被 R7
接在四條不變式中間、把第 3／4 條孤立在句外（兩席）；changelog R5 節仍寫「每一份都是性質」（兩席）。
INFO 記錄：`fmt` 對 venue 的拒絕從此涵蓋所有 error 類別、不只 D8（regression 席）——與 `.person` 相同，
接受；Cn 在 DI 區段內的保留碼位會被擋（logic）；#553 順手改第五輪記錄。

## R8 verify：splice 錨錯了一格，沒有守衛會紅

R7 的 12 列全部在位；R8 verify 39 列、DA 席缺席（session limit）、4 HIGH 是同一件事：R8 對
`.claude/rules/zero-instance-guards.md` 的 splice 用 `"```bash\npython3 - <<'EOF'\nimport glob, io, os"` 當錨——
它命中的是 **row 18** 的 heredoc（`import glob, io, os, yaml, collections`），不是 row 25 的。結果：row 18 的
abstract 長度腳本被 venue 鏡射蓋掉、第 17／20／21／22 列的量測段（含 row 22 的觸發條件）整段消失（a03933d 第
152–224 行、13 個量測標題剩 9 個），而真正的「第 25 列的量測」下面還是 R7 舊腳本——R8 report 說「row-25 Python
的 `before` 做 `str()` 與 ISO regex」在讀者被指去看的位置**為假**。`zero-instance-rows-audit` 只數 bullet、
`measured-numbers-audit` 只讀表格，都不讀量測段，所以整件事是綠的。R9 從 a03933d 逐字復原那一段、把 R9 腳本放到
row 25 下（單一副本）、每個錨點斷言唯一——用的正是 R8 沒做的那一步。

**四個 MEDIUM 各是一格程式比散文寬或窄**：virama 分支不驗 virama 自己（與跳過的標記）的文字（Codex＋四席：
`ک\u{094D}\u{200D}` 通過，doc 寫「同一文字」）；(b) 支把 joiner 在 virama 之前一律當 confusable（logic：
Unicode ch. 12.2 的 Bengali ya-phalaa `<RA, ZWJ, VIRAMA, YA>`，`add-venue --names $'র‍্যাব'` 被拒——R8 那句
「沒有正字法意義」對 Bengali 為假，Microsoft 的 Devanagari／Bengali 音節文法 `<ZWNJ|ZWJ>+H` 實取確認，D21）；
(a) 支的「沒有右鄰居」只對字串末尾成立，多字刊名裡的詞尾 chillu 右邊是空白（logic，D22）；repoint 逐字帶原
literal 之後，from-venue 同時持有 confirmed 與 rejected `work:x :: Psychometrika`——每一次合法的 repoint 都在
`akashic validate` 留一條 #486 矛盾 verdict warning，唯一處置「刪掉另一個」沒有工具面（requirements＋logic；
demote 自 #418 起同形）。verdict 沒有時間戳，讀端判不出哪條是後來的，只有寫入面知道——D20：寫入時退役相反
判定；apply 面不動（提名層已抑制 rejected 配對，記為邊界）。Codex 另指出 `first(where:)` 對同一 work 在
from-venue 有兩個不同 literal 時任取第一筆（D23：≥2 拒絕；「不同」用 ledger 的相等——測試第一版用大小寫異寫，
`appendIfAbsent` 只留一筆，拒絕永遠不觸發）。D19 的 doc 說 person／organization holder 沒有內容不變式（三席）
——`assertPersonWritable`／`assertOrganizationWritable` 都跑 `validate()` error，一筆 `authorized ⊄ names` 的 org
持有 `person:<被併>` verdict 時 person 合併就是同一個形；D24 把閘擴到三種 holder，測試把缺陷實跑出來（被併
person 已刪、org 留死 verdict）。

LOW／INFO：Python 鏡射的 `\d{4}(-\d{2}(-\d{2})?)?` 比 `ISO8601Prefix.isValid` 鬆（`1960-13`、Arabic-Indic
數字都放行——四席）、`dated` 把 `ended-unknown: false` 當宣稱；區塊表漏 Devanagari Extended／Extended-A、Myanmar
Extended-A／B（Vedic Extensions 記為邊界）；changelog 標題的 41 條（括號裡的分項自己加起來是 44）；row 25 情形欄
仍是 R7 規則；§5.7 第 4 條的「同年」比程式鬆（`1960-06`／`1960-07` 是不相交）；「找不到 confirmed verdict」的拒絕
不說出路。D18 的量測（requirements＋regression 兩席各自做）：live store 2,203 條 key venue 邊、0 條在該 venue 上
沒有 confirmed verdict、0 個 work 對同一 venue 兩條 key 邊——`repoint` 的新拒絕今天擋不到任何合法操作；產生 key
邊的生產路徑（apply／repoint／venue 合併／rename／work 合併）每一條都留 verdict，literal 邊的來源（create-entry、
匯入、migrate-venues）造不出 key 邊。#561 已收 `authorize` 的 `argList` 靜默形。

## R9 verify：把矛盾變成掃不到的東西

R8 的 16 列全部在位；R9 verify 29 列、6 席齊（DA 席第五次嘗試才跑完——前四次被 harness 中斷）、0 HIGH、
7 MEDIUM。主線是 D20 的一個沒寫出來的前提：**`supersede` 用的鍵不帶 venue index**。同一 work 兩條邊指同一 venue 時
只有一筆 confirmed（`appendIfAbsent` 以 `verdictEqualityKey` 去重），demote 其中一條會退役那筆——另一條邊仍是 `key`
卻在任何工具面上都救不回來（demote／repoint 都撞「找不到 confirmed verdict」），而 R9 之前這個狀態會留一條 #486
warning、R9 之後 `validate` 全綠（Codex 靜態、DA 真 binary 端到端、logic／security／regression／requirements 各自命中——
六路）。R9 commit message 那句「apply→repoint→demote leaves 0 contradictory verdicts」為真，但它成立的方式是把矛盾變成
掃不到的東西。D23 的謂詞問的是 literal 的個數不是邊的個數，剛好漏掉這格。**D25**：配對由多條邊實例化（同 venue 兩條 key
邊、或另有 literal 邊同配對）時 repoint／demote 具名拒絕零寫入；`verdictsRetired` 從整數改成逐筆具名（security 席：
被刪的是人的判斷記錄，#553 合併會把被併 venue 的顯式 `--reject` 搬進 keeper，日後一次 repoint 退役它時被併檔已不在，
「從未判定」與「判過、被刪了」在輸出上不可區分）。DA 補了 D23 的一格：`confirmedLiteral` 用 `matchingKey` 去重並回第一筆
——`PSYCHOMETRIKA`／`Psychometrika` 兩條邊 apply 到同一 venue 後 `--demote` 邊 1 還回去的是邊 0 的字，正是同一則訊息
承諾不做的事；改位元組相等，同鍵異位元組落進 `default:` 拒絕。

**D21 開了一個洞**（DA）：R9 的 (b) 支收 virama 時不看 virama 之後有沒有東西，而每一個引用實例都是 `<C, J, H, C>`——
halant 後面的輔音才是 joiner 有作用的原因。`क\u{200D}\u{094D}`（詞尾）、`क\u{200C}\u{094D}Journal`、Tamil 全部通過、
validate 綠，與 `क्` 渲染完全相同，能各自進 names 再被 `--authorize` 升成 displayName；R8 是拒的。**D26**：virama
之後要接同文字的字母，且只收有引用的 Devanagari／Bengali（Unicode ch. 12.2 與 Microsoft 兩份音節文法都只涵蓋這兩個）。

其餘：`addVenue` 的 payload 仍回呼叫端原陣列——R4 讓它走 `vetVenueNames` 但沒把報告帶過來，宣稱 store 沒有（且不可能持有）
的字串（logic）；`--authorize` 的 NFD 自我修復同一字串落在兩個桶（logic）→ `authorizedRewritten`；近重複掃描在同鍵組內
O(k²) 則訊息、由讀取路徑對未信任 store 觸發（security）→ 每組最多列 3 對；`Venue.swift` 那句「與輸出閘共用危險 scalar 的
定義」為假——輸入閘是三份定義的聯集、輸出閘是其中一份（security；#569 補記迴送點 0 → 4）；D24 的閘擋在 `fieldsLostByMerging`
之前，merge 專屬的訊息被別人家 YAML 的錯蓋掉（regression）→ 移到之後，並補 person／org 的 incidence 量測（4,572／13 零
error）；`canonical` 不是 venue 專屬（regression）→ doc 補 person／org 呼叫端與量測；`usesJoinControl` 零呼叫端、註解說
「留給舊呼叫端」（regression）→ 刪；Vedic Extensions 的理由句描述的是 D22 之前的行為（logic）→ 改寫；CLI／MCP 的 joiner
摘要比程式窄（requirements）→ 對齊；parity 列的 R7 句仍以現在式指名已改名的 `assertVenueHoldersWritable`（requirements）
→ 改歷史語氣；a03933d 逐字復原把第 21／22 列兩組過期數字寫回來（requirements＋DA：第 22 列的 406 與同一份 diff 寫的 485
並存）→ 重跑、註記，第 21 列的拆分判準已失效另案 #571。security 席另記三處新增的無上限訊息（#562 第七個實例）、`authorize`
的 `argList` 靜默 no-op（#561）、`authorize` 不留 judgement（#564）——都是已知、已具名，不動。

## R10 verify：閘只擋消費端

R9 的 20 列全部在位；R10 verify 29 列、**5/6 席（DA 席 errored——第二次缺席，R11 verify 必須有它）**、2 HIGH、7 MEDIUM。
兩個 HIGH 是同一件事的兩面：D25 只驗**原始** entry 裡的 from 配對，`newKey` 完全不看——logic 席真 binary 重現 `[key alpha,
key beta]` 改指 1→alpha 走成 `[alpha, alpha]`，alpha 上兩筆 confirmed、beta 的 confirmed 被退役、`validate` 全綠、之後兩條邊都
動不了；**製造 D25 宣告不得存在的形的，是 D25 自己所在的函式**。Codex 盲審指出批次內的第二格：兩條帶同一 literal 的邊在同一批
裡互換，逐 move 的退役互相覆蓋，留下哪一側取決於輸入順序（literal 不同時逐 move 是對的——R11 測試釘住交換與其後的 demote）。
**D27**：配對的唯一性對改指**之後**的邊集合驗，同一批同一 work 的兩個 move 不得帶同一個 literal。requirements 與 regression 席
再往上游一格：`apply` 一行就造得出 `[key V, key V]`（R10 自己的測試就是證據），base 可以 demote、R10 之後兩條邊都動不了，
`StoreHealth` 沒有任何掃描，唯一出路是手改 YAML——`replace-endnote-and-zotero` 第 4 條要記成 issue 的缺口。**D28**：生產端
fail-closed（`apply`／`repoint` 在會造出同一 work 兩條 key 邊指同一 venue 時具名拒絕零寫入）＋ `Entry.validate()` 對既有的這種
work 報 warning（`zero-instance-guards` 第 26 列）＋ 移除面另案 #572（作者位有 `--drop-author`／`--un-split`，venue 邊沒有）。
logic 席另指 D25 的 `.literal` 支對 demote 是過度拒絕（demote 沒有 to-venue、literal 邊在該 venue 上不可能持有 confirmed），
而它給的出路「把多餘的 key 邊改回 `- literal:`」正是 demote 要做的事——那一支改成只對 repoint 算。

五席同指近重複的上限只綁住訊息不綁求值：`listed` 只在非豁免對上遞增，一組全部成對豁免的同名沿革段仍跑滿 k(k−1)/2 次
（logic 席真 binary：4,500 段 20 秒、全綠）→ 求值也設上限（5,000 對 ≈ 100 筆同名段，超過即 error、fail-closed），「另至多 M 對」
改說「未評估」（regression 席：已評估而豁免的對同樣沒被列出，R10 的 M 少算它們）。security 席：`verdictsRetired` 是兩個 payload
裡唯一由 store 內容決定體積的欄位、每項 ~520 字元、無上限——**D30**：截 20 筆，`verdictsRetiredTotal`／`truncated` 揭露
（`akashic_enrich` 的形）；它迴送 verdict 的 value 與 statement，輸出閘對 Cf 仍是列舉——#569 的迴送點 4 → 6。requirements 席：
MCP `akashic_resolve_venues` 的描述與 CLI help 沒提 D20（會**刪掉**一筆人的判定記錄）、D23、D25、`verdictsRetired`——R6 verify
抓過同型（只改了一面的描述），這次是兩面都沒改；`authorize` 的封閉列舉式描述漏 `authorizedRewritten`（唯一宣告「store 位元組
被改寫」的桶）；parity 列內部分岔（一句說 NFD 修復報在 `authorizedRemoved`、另一句說 `authorizedRewritten`）。logic 席：
`addVenue.namesDropped` 用位元組相等，NFD 輸入同時落在 `names` 與 `namesDropped`——正是 R9 剛在 `authorizedRewritten` 修掉的
歧義 → 拆成 `namesRewritten`（canonical 形在 store、位元組不同）與 `namesDropped`（真的沒進），`updateVenue.add_names` 同一組
欄位；joiner 的 help 把 (b) 支寫成對稱的「之間」而右鄰不收標記 → 改寫；venue 合併的 `doomedRecordInvalid` 排在 `wouldLoseFields`
之前、與 R9 剛替 person／work 立的先後原則相反 → 對齊。security 席另記 venue 名字輸入無長度／項數上限（#562）、`argList`
靜默 no-op 現在頂著一個判定型寫入面（#561）——已知、已具名，不動。

## R11 verify：四席都沒碰到合併端

R10 的十二列全部在位；R11 verify 32 列、**6 席齊（DA 回來了）**、2 HIGH、12 MEDIUM。兩個 HIGH 都是 DA 用真 binary 在
**合併路徑**上造出來的，而四個 lens 都沒碰到那條路：(1) `mergedVenueKeeper`（與 person 側逐字同型）的 verdict 遷移用位元組相等
去重，`supersede`／#486 用正規化鍵——keeper `confirmed :: Alpha Journal`、doomed `rejected :: ALPHA JOURNAL`，合併前 validate
全綠、合併後 #486 的矛盾對，而本 diff 引進 `supersede` 就是為了讓這個狀態寫不出來；(2) `resolveVenueDivergence` 對改指倖存者的
key 邊去重、`mergedVenueKeeper` 對 verdict 不做對應的收攏——邊塌成一條、證據留兩筆（`Alpha Journal`／`Alpha Review`），D23
之後那條邊永久不可 demote／repoint、validate 零診斷；base 沒有 `confirmedLiteral`，所以這是本 change 引入的退化。**D31**：
遷移以 `verdictEqualityKey` 去重、相反判定的衝突在前置拒（person 同，preview 與實跑共用）；**D32**：塌邊會留兩筆正規化後不同
的 confirmed literal 時拒，出路是先 demote 一條。

D27／D28 被四席從不同角度指出**過度拒絕**：`assertKeyEdgesAreUnique` 驗整筆 entry 而不是這次造出的重複，一筆帶既有重複邊的
work（正是第 26 列服務的那一族）上任何不相干的 literal 邊都再也 apply 不進去、repoint 同，訊息還把因果歸給這次操作；apply 是
整批中止，一筆毒候選讓同批無關的候選全部零寫入，而提名面不看 key 邊、每次重列都再提（campaign 是照 listing 全量 apply）；DA
再加一格：合併後一條 literal 邊指向 work 已 key 的 venue（合併只對 key 邊去重）——第 26 列「入口只剩兩個」少算了它。**D33**：
apply 改**逐筆略過並具名**（`skippedDuplicateVenueEdge`；store 狀態不符是「該筆略過並具名」那一類，`judge` 的先例）；D27 只看
被動到的邊，同 literal 的兩個 move 只在 venue 集合相交時才拒——不相交的各在自己的檔裡退役、與順序無關，R11 的訊息在那一格
為假、它給的出路「分兩次呼叫」直接到達被拒的狀態（requirements／logic 各自真 binary 重現）。logic 與 regression 席另抓：R11
放寬 demote 的 literal 支後，`apply → demote → apply` 三步全工具面造出永久矛盾對——根因是 `VenueResolver` 的否決抑制比
原始位元組而其餘三處比 `matchingKey`，`PersonResolver` 同一格早就修過且理由逐字寫在那裡 → 對齊。Codex 盲審抓到沿革豁免
不驗段本身：`{start: 2000, end: 1900}` 以 `"1900" < "1950"` 解鎖放行 → 兩段要是有效區間，Python 鏡射同批。

散文：§5.7 宣稱「四條，封閉」而求值上限是第五個會 error 的條件、只住在寫入者的括號裡（regression）→ 補第 5 條；D25 一族是
`work:` 記錄的約束卻住在「venue 的名字內容」那節（requirements）→ 搬到 §3.5 成 normative 段、§5.7 引用不複述；changelog 的
「合併端 15 條」與實測 16 分岔（requirements）→ 改用本輪重數。其餘：`verdictsRetired` 是這條路徑上第一個帶 store 字串的**成功**
payload（security）→ 以性質逃脫 Cc／Cf／Zl／Zp／DI（#569 的局部圍堵）；no-op 早退漏 D30 三鍵、訊息索引「第 0 條」、三處新
join 無上限（#562）、`namesRewritten` 把「本來就在」與「折過才存」報成一桶、求值上限的訊息仍以「近重複」開頭；security 另記
`vetVenueNames` 的自述第七個 #562 位置、無 prompt-injection；DA 記 repoint 批次對同一 venue 的 references 寫入順序隨輸入而異
（語意等價、位元組不等價——記錄，不動）。

## R12 verify：閘裝在看見的那一圈

R11 的十五列全部在位；R12 verify 43 列、**6 席齊**、7 HIGH、13 MEDIUM——七個 HIGH 全在 R12 剛加的合併閘上。五席同指 D31
只比 keeper↔doomed：三方合併時 S 沒有 verdict、D1 confirmed、D2 rejected，兩次前置都過，遷移時 field 進鍵、兩筆都進 keeper
——正是 D31 要讓它「寫不出來」的形。DA 再往外一圈：D31 只裝在 person／venue **自己的** references 上，work 合併的 holder
遷移（`migrateHolderVerdicts` 把第三方 holder 上的 `work:<被併鍵>` 改寫成倖存者）零守衛——真 binary 全工具面：venue 持
`confirmed :: work:keep :: Alpha` 與 `rejected :: work:doom :: ALPHA`，doom 併進 keep 後兩筆都留下，#486 矛盾對；三個
`validate*Preconditions` 各補一份正是 D8 那三輪「修在看見的那一圈」的形。**R13**：D31 累積比對（被併者依序併入累積中的
keeper），閘裝在 `assertHoldersWritable`——三種 shape 共用的遷移點。DA 的第二個 HIGH：D32 的 `hits.count > 1` 守的是「塌邊」
這個症狀不是不變式——keeper 與 doomed 各持同一 work 一筆正規化後不同的 confirmed 而該 work 只有一條邊時整個跳過，合併後
keeper 兩筆 confirmed、validate 零診斷、demote 撞 D23；logic 席報反方向——keeper 自己既有的 `[key S, key S]` 擋住一筆無關的合併，
出路「先 demote 一條」被 D25 堵死。R13 改守不變式本身：這次合併**新增**的 confirmed literal 會讓 keeper 對某 work 持有 ≥2 個
正規化後不同的 confirmed 即拒，keeper 既有的違反不是合併的事。四席另指遷移去重從位元組改正規化鍵之後，被丟掉的那筆（可能
帶人寫的 judgement 與 rests-on）零回報而被併檔隨即刪除——同一個 diff 對 `verdictsRetired` 立的紀律在合併路徑上的反例 → 逐筆
進既有的 `verdictsCollapsed`。

Codex 盲審與 logic 席各自抓到 repoint 的同 literal 相交檢查只比**相鄰**兩筆（`zip(group, group.dropFirst())`）：`[A, C, B]`
三個 move 的第 1 與第 3 個相交逃過，index 0 仍指向 B 卻失去 confirmed → 全配對。DA：R12 的正規化否決抑制對了，但 MCP
組合腿的 `skippedBecauseRejected` 只比 id 字面——同一 work 的兄弟拼法各給一腿時 reject 已提交、apply 走到一句指錯路的
notFound → 以正規化配對算。security 席四列指同一件事：R12 造的性質式逃脫只掛在 `verdictsRetired`，而名字不變式的訊息在
結構上保證迴送它剛拒掉的那個字元（`doomedRecordInvalid` 更尖——它只在該名字違反時才存在）、碼位不補零、漏 U+2800 與非
ASCII 的 Zs → 下沉到 Core 的 `displaySafeInvisible`，五個站點共用。其餘：`skippedDuplicateVenueEdge` 對同一批內互撞的訊息
把因果歸給 store、勝者由呼叫端順序決定卻無處記載（三席）→ 兩種來源分開措辭、兩面描述寫明先到先寫；`assertKeyEdgesAreUnique`
的 doc 仍說 apply 會拒；§5.7 一句「四條」沒改、two-kinds 也是；`add_variant`／`authorize` 的全空白項靜默 no-op；`fmt` 的
`.organization` 分支被留在裸 `encode(decode)`（三個同形 shape 只修兩個）；apply 的重複邊預掃 O(entries×requested)；
`assertPairingHasOneEdge` 的索引沒排序；CLI `--add-name` help 沒提三個桶；合併對 entry 的 key 邊去重會把與被併鍵無關的既有
重複一併收成一條（logic：它其實是一種移除面）→ §3.5 與第 26 列寫出來。security 另指 `supersede` 讓 repoint／demote 變成會
刪判定記錄的操作而沒有 trackedness 前置（merge 有、這裡沒有）→ #573；近重複求值上限只綁組內、組數不設上限（#562 家族）、
`vetVenueNames` 的自述第七個位置——記錄。DA 收窄 security 的「抑制鍵把自由欄位放中間」：兩側欄位是 `StoreKey`，`\0`
不可達——註記不改形狀（改了會與 `verdictEqualityKey` 分岔成兩套）。

## R13 verify：同一句不變式、三個謂詞

R12 的二十列全部在位；R13 verify 33 列、**6 席齊**、3 HIGH、14 MEDIUM。三個 HIGH 中兩個是同一格：R13 把 D31 裝到
`assertHoldersWritable` 時只裝了「相反判定」那一半，D32 那一半（同一 work ≥2 個正規化後不同的 confirmed literal）沒跟著擴
——DA 純工具面重現：`resolve-venues --apply wkeep:0 --apply wdoom:0`（兩個刊名變體各歸戶到同一 venue，`names` 多段的預期用法）、
`resolve-divergence --survivor wkeep`，alpha 上兩筆 confirmed 都改寫成 wkeep，validate rc=0、doctor 零診斷，`--demote wkeep:0`
撞 D23。而 twin work 合併正是 #456 進行中的 campaign。第三個 HIGH：R12 row 4 的修法只裝在實跑——preview 把 `mergedVenueKeeper`
回傳的 `verdictsCollapsed` 當場丟掉、person 側被 holder 遷移那一半整個覆蓋，dry-run 對「這次會丟掉哪幾筆判定記錄」沉默，而
同一個 `case .venue:` 往上三行的註解就寫著「dry-run 對它沉默就是 #139 F1 那個形狀第三次」。

MEDIUM 群集在同一件事的三個面向：**三處閘對同一句不變式用了三個謂詞**。keeper 路徑是 delta 謂詞但只拿被併者對累積 keeper 找
相反鍵——矛盾整組住在同一筆被併者裡（logic／regression）、單一被併者自帶兩個 literal 而 keeper 對該 work 無 verdict（Codex／
requirements／logic：D32 多了「keeper 已有 ≥1」的前提，判準寫的是「這次新增的」而程式比它窄）都放行，被併檔隨即刪除；holder
路徑是整份清單的絕對謂詞——既有且與被併鍵無關的 #486 矛盾對擋下不相干的合併、訊息把因果歸給這次合併（requirements／logic／
security／regression 四席），正是同一輪從 D32 拿掉的形狀；訊息印遷移**後**的 value（DA：`work:wkeep :: ALPHA JOURNAL` 不在
任何 YAML 裡，照訊息 grep 一無所獲——R6 verify 第 28 列修過的形狀重新引入）；keeper 側 `record: survivor, survivor: survivor`
三方合併時說不出哪兩筆在打架。**R14（D34）**：一個 delta 謂詞，兩路共用——after ＝ 合併後的記錄（keeper：自己的 ＋ 全部被併者的
references，person 側經 holder 改寫；holder：遷移後、去重前，與輸入索引對齊），before ＝ 合併前；只擋 after 有而 before 沒有的
兩類違反（相反判定三種 shape；≥2 個 confirmed literal 只對 venue 記錄——D23 是 venue 側的拒絕），每筆帶出處與遷移前的原值。
三方合併、單一被併者內部、倖存者既有（不擋）、holder 既有（不擋）四格由同一個差集決定。`wouldCollapseEdges` 改名
`wouldLeaveTwoConfirmedLiterals`（R13 之後它在完全沒有邊被塌時擲出，名字說謊——requirements 第 7 列），出路對調（第一條「demote
指向被併者的那條邊」在它主要命中的情形——該 work 只有一條邊且指向倖存者——不存在，logic 第 22 列、regression 第 27 列）。
**D35**：preview 與實跑對 `verdictsCollapsed` 同源——venue 用 `mergedVenueKeeper` 的整個 tuple、person 抽出 `mergedPersonKeeper`，
keeper 的 holder 遷移對合併後的 refs 預測。DA 另指 §3.5「既有的違反由 `Entry.validate()` 報 warning」對第二半為假：全庫沒有
任何掃描面掃 (venue, work) 的 confirmed literal 數，而造出第二半的路徑結構上不點亮第一半的燈 → **D36**：`Venue.validate()`
warning，`zero-instance-guards` 第 27 列（live store 485 筆、0 筆）。security 三列：性質式逃脫漏了同一 diff 新增的三則「結構上必然
帶著被拒字元」的訊息（近重複句——組員只差空白類或 NFC，`displaySafe` 不逃脫 NBSP、兩個字串印成逐像素相同而訊息叫人留一筆；
`bootstrap-venues` 的 dropped 行——venue 沒建出來、沒有 sibling 訊息可對照）→ 改 `displaySafeInvisible`；`verdictsCollapsed` 的
去重列未逃脫、整列 300 截斷會把它存在的理由（judgement）擠掉 → 逐段截、CLI 逐列 `displaySafeInvisible(max: 1_000)`；三則入口
拒絕訊息把呼叫端陣列無上限 join 進 MCP tool result → 截 10 項。regression：`variantDropped`／`authorizeDropped` 兩面描述都沒提
（第三次只做一半）→ 補；CLI 標題句「同 (field, value)」對去重那一半說錯話 → 改；changelog「R13 新增 3 條」列了四項 → 改。
logic：相交訊息只印 `b.literal` → 印兩個拼法；`keyed` 字典賦值後者覆蓋前者、既有兩條重複邊只印後一條的索引 → 全部索引；`fmt`
把「validate 報 error 被拒」說成「未檢查」→ 改措辭。security INFO：sink 守衛認不得 `displaySafeInvisible(`，四個真消毒站點掛著
exempt、拔掉消毒後守衛照樣全綠 → 守衛認得它、strip-all 突變一併拔、加測試釘住，exempt 只留給真的不消毒的部分。記錄不動：
`verdictsRetired`／`skippedDuplicateVenueEdge` 讓 store 作者寫的字串進 MCP tool result 而沒有框界（#569 的裁決是框界不只是逃脫）；
`record-divergence` 的 help 文案是 #553 的契約（差集明說）。

## R14 verify：差集算在錯的那一層

R13 的十九列全部在位；R14 verify 31 列、**6 席齊**、2 HIGH、9 MEDIUM。第一個 HIGH（logic 第 2 列，requirements／security／
regression 三席同指同一格）：D34 的差集在**配對鍵**層算，拿未改寫的 before 比改寫後的 after——而配對鍵含 holder。住在被併鍵上的
既有 #486 矛盾對（或雙 literal）改寫後鍵從 `work:doom…` 變成 `work:keep…`，差集判成新、合併被拒，訊息自己列出的兩筆 holder 都是
被併鍵、末句還說「合併前就存在的矛盾對不擋合併」。R14 自己的釘樁測試把既有矛盾對放在 `other2020a`（未被併的鍵）上，剛好避開這一格；
keeper 路徑對倖存者自己持有的 `person:<被併>` 矛盾對同型。**D37**：差集在**索引層**算——after 的違反是既有的，當且僅當構成它的索引裡
有一組在合併前（同一筆倖存記錄、同一個 before 配對鍵）就已經構成同一類違反；雙 literal 是「合併前同一個 work 鍵下就持有全部這些
literal」（把既有歧義變大仍擋——DA 第 11 列問的正是這格，答案是擋，但訊息要把帶進來的與倖存者既有的分開列，R14 把絕對集合印在
「這次合併帶進來的」下、末句又說既有的不擋，照最自然的讀法刪第一筆重跑仍被拒）。

第二個 HIGH 是 Codex 的盲審（第 1 列）：D34 只裝在合併路徑。目的 venue 已對該 work 持有另一個 confirmed literal（沒有對應的邊——
手改、舊 binary、R14 之前的 work 合併）時，apply／repoint 照寫第二個，那條邊立刻被 D23 鎖住，D36 事後才 warning。生產端的
fail-closed 只在合併有，是一個沒寫下來的不對稱。**D38**：`apply` 對它逐筆略過並具名（`skippedConflictingConfirmedLiteral`，store
狀態不符——D33 的同一類）；`repoint` 對**預測後**的 verdict 集合驗（同一批交換兩條 literal 不同的邊時，to 上原本那筆已被另一個 move
退役，逐 move 檢查會誤擋合法的中間態）、整批拒絕零寫入。

MEDIUM：D36 用 `matchingKey`、D23 比位元組（Codex 第 3 列、requirements 第 5 列）——R14 寫「鍵與 D23 同一把」是一句沒回頭量的斷言；
只差大小寫或 NFC 形的兩筆 confirmed 讓 demote／repoint 必拒而 validate 零診斷 → **D39**：掃描以位元組分兩類（正規化後不同＝不變式的
違反；只差位元組＝重複記錄，工具面寫不出），同一家族前綴、措辭分開。`verdictsCollapsed` 印遷移**後**的 value（DA 第 10 列、logic 第 14
列、security 第 7 列）——R14 commit message 自己指名要修的缺陷在姊妹函式上原封不動，且被丟掉的恆是被改寫的那一筆，所以每一列都指向
一個不存在的記錄；rename 的 CLI／App sink 仍是列舉式 `displaySafe`、措辭仍寫「同 (field, value)」 → **D40**：印原值、value 與
statement 各截 200、三個 sink 同一種性質式逃脫。`migrate-venue-variants` 只用散文禁止、命令仍可執行（regression 第 9 列）→
**D41**：`--apply` 一律拒絕。regression 第 22 列：兩族 per-record warning 沒有 StoreHealth 家族，doctor 截 20 則、App 預覽 5 則時可能
完全看不到 → 家族前綴住 Core（訊息在那裡組出）、StoreHealth 只引用、doctor 與 App 各一格；logic 第 16／security 第 18 列：兩族逐筆無
上限而鄰居剛為同一條理由加了上限 → 每筆 20 則。LOW：guards 第 27 列的 Python 鏡射與 Swift 的兩處差異（空白集合、grapheme 層連字號
——DA 實測 `A-\u0301B` 與 `A\u2010\u0301B` 在 Swift 是兩個鍵而鏡射判成一個）→ 對齊並加固定案例；`mergedVenueKeeper` 的 doc 引已刪的
`contradictingVerdicts`、五處 exempt 註解指名舊 sink → 改；否決抑制放寬到 `matchingKey` 的代價沒寫給使用者（regression 第 21 列）→
兩面描述補一句；`verdictEqualityKey` 的 malformed 回退鍵可與合法鍵碰撞（security 第 28 列；DA 說 store 內不可達）→ 加不可碰撞的前綴。
記錄不動：repoint 對無 verdict 的 key 邊自 D18 起只剩手改（regression 第 19 列——live store 2026-09-14 實測 2,203 條 key 邊、0 條無
verdict，R9 量過）；`fmt` 的 organization 分支是對稱性論證搭車（第 20 列；#557 的形狀）；`record-divergence` 的 help 補 venue 是
#553 的文件缺口（第 29 列）；`assertHolderAddsNoViolation` 重算一次 `rewrittenVerdicts`（第 25／26 列，DA 證實等價）。

## R15 verify：位元組要真的是位元組

R14 的全部修法在位；R15 verify 30 列、**6 席齊**、3 HIGH、6 MEDIUM。三個 HIGH 都是同一種形——一句寫進 commit message、§3.5、guards、
changelog 的斷言沒回頭量：

- **「以位元組分兩類」不是位元組**（requirements 第 1 列；MEDIUM 第 4／8 列同）。D39 的去重寫 `$0.literal == p.literal`，而 Swift 的
  `String ==` 是 canonical equivalence——NFC 與 NFD 的兩筆被收攏成一筆、`lits.count > 1` 放行、兩類 warning 都不出，而 D23 對同一筆記錄
  照拒。R14 第 3 列點名的兩個例子只修了大小寫那一個；測試的 fixture 也只有大小寫，對這一格是綠的假陽性；guards 的 Python 鏡射（code-point
  相等）反而會算成兩筆，與 binary 分岔。**D42**：去重鍵改 UTF-8 位元組（`Set<[UInt8]>`，與 `confirmedLiteral`／`otherConfirmedLiterals`
  同一把；順便把 O(N²) 的 `contains(where:)` 換成 O(N)，第 7 列）；混合情形（三筆裡兩筆只差位元組——第 23 列）第一類訊息點名那一組。
- **D38 的閘跑在重複邊檢查之前，reason 斷言「沒有對應的邊」而從未驗證**（regression 第 2 列、logic 第 6 列，真 binary 純工具面重現）。
  重複來源欄位（journaltitle／publisher 各帶同一本刊的一個寫法）是最常見的情境，第二條邊被分進 `skippedConflictingConfirmedLiteral`、
  出路叫人刪掉**有邊的** confirmed——照做之後那條 key 邊在 demote／repoint 上永遠救不回，正是 D25／D23 一族要防的終局。R15 之前它走
  `skippedDuplicateVenueEdge`、訊息與出路都對，是 R15 引入的迴歸。**D44**：移到 D28／D33 之後——走到那裡代表這筆 work 沒有任何 key 邊
  指向這個 venue，那句才為真。
- **D38 以 `matchingKey` 比、放行同鍵異拼法**（Codex 第 3 列 HIGH、第 5 列）。R15 的理由「`appendIfAbsent` 對它去重、不會多一筆」為真，
  但漏了下游：新拼法沒寫入，之後 `--demote` 從唯一的 confirmed 取回**舊拼法**，邊被改寫成不是這筆記錄原本寫的字——`confirmedLiteral`
  的拒絕訊息自己承諾不做的事。**D43**：閘比位元組、與 D23 同一把；`apply` 對「另一個拼法」也略過並具名、`repoint` 也拒，訊息分兩種。

MEDIUM／LOW 裡有一組是 D37 的判準：它問「有沒有**某一個**合併前分區已持有全部」——holder 對 doom 持 {A, B}、對 keep 持 {A} 時 doom 那一區
⊇ 全部就放行，而 (holder, keep) 合併前只有一個 literal、可以 demote，合併後被 D23 鎖住（logic 第 13 列）；整組住在被併記錄裡的擋、卻被列在
「這次合併帶進來的」下（第 12 列）；R15 自己新加的末句「含住在被併鍵上的不擋」被 DA 用真 binary 否掉（第 20 列：被搬到別的配對上、把它的歧義
變大的那幾筆正是住在被併鍵上）。**D45**：「既有」看**倖存配對**——它合併前就持有整組、或合併前一筆都沒有而整組原樣從單一被併鍵搬來，才不擋；
整組住在被併記錄裡的（R13 的裁決不變）、或讓倖存配對的既有歧義變大的，都擋；矛盾對同一條規則；訊息的末句改寫成這句、「帶進來的」明說含
合併前住在被併鍵上的。其餘：repoint 同一條邊在同一批被指定兩次落進「兩條邊帶同一個 literal」那句、出路錯（第 14 列）→ 以 (citekey, index)
去重、自成一句；doctor／App 的 `recordIssues` sink 對已消毒訊息再過一次 `displaySafe`——它逃脫反斜線自身、不冪等，`\u{200B}` 印成
`\u{005C}u{200B}`，且 300／160 把家族前綴之後的正文截掉（第 16 列）→ 只截不逃、doctor 1,000／App 300；名字內容 error 與近重複組無上限
（第 15 列）→ 各 20；概括句帶家族前綴、`StoreHealth` 把它算成一則（DA 第 29 列：25 筆 work 報 21）→ 自己的前綴 `則數已達上限`；apply 對每個
候選重剖一遍 ledger（第 17 列）→ 每個 venue 一次；guards 鏡射與 Swift 還差兩處（logic 第 9／11 列、DA 第 24 列：`Character.isWhitespace`
只看第一個 scalar，「空白＋組合符號」整個 cluster 被丟掉、組合符號消失；連字號＋ZWJ 是一個 cluster）→ **D46** 鏡射照 Swift 的行為鏡射並加
固定案例（2026-09-16 用逐字複製的 `matchingKey` 探針量過）——`matchingKey` 本身的資料損失另案 #574，這一輪不改它（動到全庫提名鍵與 verdict
去重鍵，要自己的量測）；`migrate-venue-variants` 的 `apply ?` 死分支（第 19 列）→ 刪。記錄不動：CLI `validate` 沒有家族計數行（第 22 列
INFO，逐行本來就全印）；`argList` 靜默 no-op（#561）；`StoreHealthSurfaceTests` 的反射守衛照不到計算屬性家族（第 27 列）；本輪 scope 累積
（第 28 列——DA 說得對，R16 起 `mcp-cli-parity` 那一列的 verify 摘要只記裁決編號與列號）。

## R16 verify：第三個面，與一個數錯的配額

R15 的十九列全部在位；R16 verify 31 findings 合併成 **24 列**、**6 席齊**、2 HIGH、6 MEDIUM（本節起列號是報告公布的**合併列號**；R1–R15 各節與 R16 之前的規則檔摘要句用的是合併前的 finding 編號——R17 verify 第 6 列抓到兩套編號互斥、規則檔用的那套對不上報告，parity 與 guards 的 R16／R17 句已改成合併列號；更早各節不回頭改，讀時對照各報告的「席」欄）。兩個 HIGH 都是 DA 席用真 binary 重現的：

- **合併是第三個會動到同一批 verdict 的面，而它沒跟上「位元組要真的是位元組」**（第 1 列）。收攏以 `verdictEqualityKey`（正規化）去重後由
  #468 的勝者政策挑一筆，而政策第 1 層「弱血統優先」排在第 2 層「未改寫者勝」之前——被併記錄弱血統的 `VEE JOURNAL` 贏過倖存者使用者確認的
  `Vee Journal`、連**位元組**一起取代，之後 `--demote` 把倖存邊寫成不是它原本記的字（`confirmedLiteral` 承諾不做、D43 逐字要防的事）；
  `verdictsCollapsed` 還用「正規化後相等」描述它。**D47**：碰撞的 literal 位元組不同時倖存配對自己的（未改寫）那筆勝，同拼法時 #468 三層照舊
  （留弱只多一句警告、不動任何字串）；被丟的那筆連同留下的拼法印在收攏列，holder 遷移、keeper 合併、rename 三條路同一個描述。這是對 #468
  使用者裁決的邊界收窄（使用者可翻）。刻意不加拒絕：只差位元組的兩筆判定不該擋合併，揭露即可。
- **R16 新加的近重複「組數上限」在判定該組有沒有違反之前就遞增**（第 2 列；Codex／logic／security 同指）。21 組合法的
  同名沿革段（每組兩段、時間不相交、零違反）讓 validate 憑空報一則 **error**，`assertVenueWritable` 從此對這筆 venue 所有寫入面關門，訊息
  說的是一件不存在的事；前 20 組合法時第 21 組的真近重複整條被吞進概括句。同一輪另外兩個上限都寫對了，只有這一格反了。**D48**：每一組照常
  求值，上限只管列出、只數真的出聲的組。

MEDIUM：D45 的矛盾對訊息把整組豁免寫得比謂詞寬（第 3 列——括號那句無條件、與同輪的測試互相矛盾）→ 刪掉括號、前件寫全；`testEveryFieldIsConsumedByDoctor`
的 6,000 字元窗口只剩 89 字元、R16 的處置是縮註解（第 4 列）→ 窗口改成掃到 `doctor()` 的閉合大括號；repoint 相交訊息的「兩個拼法」用列舉式
`displaySafe`（Cf 逃不出來）且以 Swift `==` 判同一拼法（第 5 列）→ 位元組比、性質式逃脫；doctor 的 `recordIssues.first` 沒有位元組預算而
單則上限 300 → 1,000（第 6 列）→ 受 `candidateByteBudget` 約束、截掉時 `firstCappedByBudget` 揭露；D43 的訊息兩桶同時非空時只印第一桶、用單數
「那筆」（第 7 列：照著刪掉一筆之後 validate 全綠、再跑才撞第二桶）→ **D50** 兩桶都說、出路分開列；D46 的鏡射把機制寫錯（第 8 列：
決定「空白＋組合符號」會不會整個丟掉的是 grapheme 分群不是 `isWhitespace` 讀幾個 scalar——TAB／LF 等 Control 類依 GB4 斷開、組合符號保留，
14 個空白裡 8 個對錯了；60,033 例差分裡 2,967 例源於此）→ 鏡射只在 Zs 類空白上吞、doc 改寫機制、NFKC 的 canonical reordering 差異記為邊界。
LOW：位元組重複註記靜默截在 5 組 → 「…共 N 組」；第 27 列的 `grep -c '只差位元組'` 數的是行不是組 → 改說它量的單位；parity 那一列自己宣告
「只記編號」卻寫了整段 → R16 那句縮成編號、R17 同形；`assertPairingHasOneEdge` 與重複邊 warning 迴送 store 字串只用列舉式逃脫 → `displaySafeInvisible`；
`displaySafe` 的「唯一 false 呼叫端」不變式註解已失效 → 「只截不逃」抽成具名的 `displaySafeClipOnly`；changelog 的 R16 splice 落在句中 → 修；
`wellFormednessIssue` 的 `name != canon` 析取項恆為死碼 → 刪；訊息兩個分支的排序基準 doc 補。記錄不動：否決抑制收窄 recall 而撤回面不存在
（第 16 列，補記在 #559）；`argList` 靜默強制轉型現在守著判定面（第 20 列，補記在 #561）；`VenueVariantMigration.run(apply: true)` 函式本身仍會寫
（第 21 列，#567）；`CanonicalFormat` 的 org 分支搭車（第 22 列，#557）；D8 的 error 級不變式沒有修復面（第 24 列）→ **#575**。#574 的 Problem
把機制寫錯了，補一則更正。

## R17 verify：倖存配對不是倖存邊

R16 的 24 列全部在位；R17 verify 31 findings 合併成 **20 列**、**6 席齊**、1 HIGH、9 MEDIUM（DA 把 security 的一列降成 LOW）。HIGH 是 Codex 盲審抓的，
其他五席全在同一格的旁邊打轉而沒碰到它：

- **keeper 路徑的收攏一律 keeper 勝，但 keeper 那筆 confirmed 可能沒有邊**（第 1 列；logic 第 6 列的三方合併、regression 第 8 列的組層級 `bytesDiffer`、
  DA 第 10 列的 rename 都是同一句話的四個面）。work 只有一條 `.key(doomed)` 邊、doomed 的 confirmed 是 `ALPHA JOURNAL`，keeper 卻對同一 work 持有
  `Alpha Journal`（手改、舊 binary，正是 D38 具名的那種輸入）；R17 的 D47 靠「keeper 的就是倖存配對自己的」這個代換，而**倖存配對 ≠ 倖存邊**——合併丟掉
  doomed 那筆、邊改指 keeper，之後 `--demote` 還回 `Alpha Journal`，不是該邊原文，D23 的掃描只看到一筆、零診斷。與 R16 第 1 列同型，入口從 holder 遷移換成
  keeper 收攏。**D51**：三條收攏路徑同一個勝者函式——拼法位元組不同時先留活著的邊（合併前 work 對該 venue／person、person 對該 organization 真的有邊，
  `VerdictEdgeSet`），再留與倖存配對自己位元組相同的（逐對，不是組層級旗標——三列碰撞裡與 keeper 同拼法的弱血統那筆現在留得住位元組與警告），再 #468
  三層，最後首見；R17 說 keeper 路徑的三方合併「由 #468 決定」是假的（陣列順序），現在是真的。**D53**：rename 只收攏它動到的鍵——被改寫的那筆對上早已指向
  新鍵的死 verdict 時留活的（R17 釘住的是相反的答案：陣列先見者勝），兩筆都沒動到的碰撞留著、validate 照報；R16 之前的全量 dedup 對不相干 work 的重複由
  YAML 順序決定留哪個。holder 路徑沒有活邊那一層：work 合併不搬 venues／authors 邊，被併配對在合併後必死。

MEDIUM：doctor 的描述與 service 註解寫「各族計數永遠完整」而 `StoreHealth` 的 doc 說家族計數 ＝ min(受影響數, 20)（Codex 第 5 列，同一個 diff 裡的兩份
描述）→ **D54** 家族計數是下限、被截的記錄數自成一族 `cappedRecords`（doctor／App 各一格）、描述改寫；R16／R17 摘要句引用的列號在被引用的報告裡不存在
——用的是合併前的 finding 編號，越界且對不上（第 6 列）→ parity／guards／changelog 改成合併列號，R17 句只記編號；D48 的概括句對只觸發組內求值上限的組說
「已評估且真的違反」、authorized／variant 數出現次數不數組（第 7 列）→ **D52** 兩類分開計數與措辭、authorized／variant 先分組；D48 把配額移到求值之後
拿掉了 20 組 × 5,000 對的常數上界（第 8 列）→ D52 整筆記錄 100,000 對求值總量上限，超過即 error 並說出幾組未評估；「全部 14 個 `White_Space` scalar」
是錯的量測——25 個，8 Control／17 Zs（DA 第 10 列）→ guards 與 #574 的更正 comment 改；`resolve_venues --apply` 的兩個 skipped 陣列無上限（security 第 9
列，DA 更正：每列體積早被既有上限夾住、筆數由呼叫端決定，與 `verdictsRetired` 不是同一個威脅模型）→ 記錄：缺的是請求面的筆數上限，管到 `applied` 也管到
skipped，另裁。LOW：第 25 列的量測 grep 數不到求值上限句、又把概括句數成一則（第 11 列）→ 改；`.message` 不在 sink 守衛的 tainted 清單，doctor／App
的 exempt 註記不承重（第 12 列）→ 入列、三個 CLI sink 掛 exempt；person 側的近重複掃描沒有任何上限（第 13 列）→ **#576**；apply 對「目的 venue 自己
不合法」仍整批零寫入、與 D33 的分類相反（第 14 列）→ 記錄不動，理由見「不做」；`jsonBytes` 量 compact 而輸出 pretty（第 15 列）→ doc 寫明偏差與餘裕。
INFO：`fmt` 訊息列了不可達的原因（第 17 列）→ 改；測試窗口的括號配對只有「太小」方向有守衛（第 18 列）→ 加結束錨；四個搭車項集中記（第 19 列）；
24/24 在位、無注入（第 16／20 列）。

## R18 verify：五席撞上 session limit

R18 verify 的六席裡**五席（requirements／logic／security／regression／DA）在起跑就撞上「You've hit your session limit · resets 7:10am」、零 finding 回來**，
只有 Codex 席完成——這不是一次有效的 ensemble（席次會大量掉是記過的事，`ensemble-lens-attrition`），R19 落地後**重跑一次完整的 verify**。Codex 席 3 列全收：

- **HIGH：D53 的 rename 收攏用單一槽位記帳，三方以上的碰撞由 YAML 順序決定**（第 1 列）。每個鍵只記「目前留下的那筆」是活是死；兩筆早已指向新鍵的死 verdict
  ＋ 一筆被改寫的活 verdict 時，第二筆死的對上「已被活的取代的槽位」走到「同狀態、拼法不同：都留」那一支——六種排列裡兩種留下一筆死的（活的排在中間或最後、
  另一筆死的在它之後）。**D55**：以被動到的鍵整組收攏——被改寫的全留（同拼法收成首見）、早已指向新鍵的全丟（目的鍵在 rename 之前不存在，否則 rename 拒絕，
  所以它們必然是死的）、兩筆被改寫而拼法不同的都留；整組放在鍵首次出現處。測試六種排列同一個答案、真 binary 同形。
- **MEDIUM：`cappedRecords` 數的是概括句的行數，不是記錄**（第 2 列）。一筆 venue 可以同時出名字近重複與 confirmed-literal 兩句概括，「被截的記錄數」就多報一筆，
  而 doctor 描述說的是「幾筆記錄」。**D56**：以 (kind, owner) 去重、每筆留首見那一句；MCP 描述補「以記錄計」。
- **MEDIUM：App 沒有任何 View 消費 `cappedRecords`**（第 3 列）。R18 把它放進 `RecordIssuesSummary` 就停了，側欄的家族計數仍是裸數字。**D57**：
  `RecordIssuesSection` 多一列「被截的記錄」，各家族的值經 `summary.lowerBound`——有記錄被截時前綴「≥」；源碼掃描釘住每個家族都經過它。

**搭車一項，與 #554 無關但擋住 push**：這台機器 2026-09-16 09:37 裝了 Xcode 27，`swift` 6.4 的預設建置系統改成 swiftbuild（`--build-system native`
標為 deprecated），而它只連結宣告過的依賴——`AkashicKitTests` 有四個檔 `@testable import AkashicMCPKit` 卻沒宣告、native 靠傳遞依賴連得起來，
swiftbuild 直接 `Undefined symbols … AkashicMCPKit.AkashicService`。`Package.swift` 補宣告一行。補完之後全套在預設系統下 2754 條**只剩 3 條紅**——`AkashicPropositionTests` 的三個外部探針以 `.xctest`
所在目錄反推 native 佈局的 `Modules/` 與 `checkouts/Yams`，swiftbuild 沒有那兩個位置；沒有環境變數可切回。另開 **#577**；在它落地前
`.githooks/pre-push` 顯式釘 `--build-system native` 並在 build 之後把 `.build/debug` 連結指回 native 產物（swiftbuild 會把它改指
`out/Products/Debug`、native 不會改回，而守衛從 `.build/debug` 找 binary），`PrePushHookTests` 的期望字串同步。native 全套 2754／0（1 skipped）。

## R19 verify：分組的鍵帶著 field，死的 rejected 逃了

R19 verify 5 席齊（Codex 席撞 HTTP 429 usage limit、2026-09-19 才重置，本輪與之後都是 5 席），34 列合併、1 HIGH：

- **HIGH：D55 的「早已指向新鍵的全丟」以 `verdictEqualityKey` 分組，而那把鍵含 field**（DA 第 1 列）。venue 對 new2020a 早已持一筆 **rejected**、對 W 持
  confirmed（同拼法）：rename W→new2020a 時 rejected 不在任何被動到的鍵裡、原樣通過，rename 後它從死變活、與剛遷來的 confirmed 構成 #486 的矛盾對——merge
  對同一形狀（D31／D34）是整批拒絕，rename 卻親手造出來。**D58**：凡 holder 同 kind、key 等於新鍵而沒被改寫的 verdict 一律丟（不論 field 與拼法）、逐筆回報，
  收攏列附 rests-on digest（security 第 22 列）；被改寫的同拼法重複走 `collapseWinner`（R19 留首見——R18／R19 三處寫「三條路徑同一個勝者函式」而 rename 沒跑它，
  requirements 第 1 列、logic 第 6 列）；留下的每一筆待在原位（regression 第 23 列）；O(N)（security 第 8 列）。真 binary 重現：rename 後 rejected 消失、
  `validate` 矛盾 verdict 0。
- **MEDIUM：`count`／`errors` 寫成「完整」，而被截掉的正是 error 級訊息**（logic 第 7 列、regression 第 3 列）。**D59**：訊息則數在 `cappedRecords > 0`
  時同為下限——doctor 描述、service 註解、App 的 `記錄層問題`／`其中 error` 都經 `lowerBound`；help 文案「未必每一族都受影響」（regression 第 6 列）。
- **MEDIUM：doctor 沒有 `deadVerdicts`／`contradictoryVerdicts`、App 沒有後者，而反射守衛從來沒生效**（DA 第 12 列）：`StoreHealthSurfaceTests` 用
  `Mirror` 只看 stored property，兩族都是 computed。守衛改掃源碼的家族存取子；名冊補齊；`RecordIssuesSummaryTests` 的硬寫清單改反射（第 13 列）。
- **MEDIUM：`VerdictEdgeSet` 對 `Entry.venues[].key` 不驗 StoreKey、分隔符 `|` 可碰撞**（security 第 19 列）→ 插入側與查詢側同一道 `StoreKey.isValid`、U+0000。
- **MEDIUM：`Package.swift` 的閉包不變式沒有守衛**（DA 第 14 列：另外三個 test target 有九個 import 沒直接宣告而在閉包內，R19 的註解把判準寫成「要直接宣告」）
  → `PackageManifestTests` 純文字檢查每個 `@testable import` 都在宣告依賴的閉包內；註解改寫。
- **MEDIUM：hook 的 `[ -d … ] && ln …` 重指失敗靜默略過、`ci.yml` 沒釘 native**（logic 第 30 列、regression 第 10／34 列）→ hook 三支分明：沒有 `.build`
  略過、有 native 目錄重指、否則出聲並 `exit 1`（`PrePushHookTests` 加一條）；`ci.yml` 同樣釘 native 並重指。
- 其餘：`Venue.validate()` 近重複概括句「每一組都已評估」對配額到頂的組為假（logic 第 18 列，改「部分組可能只評估到組內上限」）；`rename` 的收攏抬頭
  寫「留首見」（DA 第 26 列，改寫）；`DivergenceResolve` 兩處 doc（「三條收攏路徑同一個政策」「rename 全量 dedup」）過期（requirements 第 1／2 列）；
  `cappedRecords` 留下的那一句是任意的、消費端不得依它分流（logic 第 16 列，寫進 doc）；`variant` 不設閘的判準自 D41 起答案變成「沒有」
  （regression 第 24 列，§store-format 格式 14 列與 `LibraryStore` 註解補記，閘仍不加、#567 一併裁）；§3.5 寫明第 27 列第二半的掃描面只有 venue×work
  （requirements 第 4 列）。

## R20 verify：D58 修了一半，而另一半不該修

R20 verify 5 席齊（Codex 席仍 HTTP 429），26 列合併、5 HIGH——四席同指一格、DA 席指的是那一格修好之後的事：

- **HIGH ×4：D58 的「一律丟」寫在第一段後的早退之後**（requirements／logic／security／regression 各自真 binary 重現）。`migratedVerdicts`
  在改寫完就 `guard rewritten.contains(where: \.touched) else { return nil }`，四十行後的 `|| anyDead` 是死碼——holder **只**持有指向新鍵的死
  verdict、沒有任何被改寫的那筆時整筆記錄原樣通過，rename 後那筆從未對這筆 work 做過的否決生效、`validate` 全綠、報告零字。R20 的三支 D58
  測試每一支的 fixture 都同時放了一筆會被改寫的活 verdict，所以整組對這一格盲；R20 report 寫的「returns non-nil when rewritten OR dropped」對
  OR 的後半為假。
- **HIGH（DA）：D58 生效的那一半是不可逆的判定刪除**——無乾跑（`rename --help` 沒有 `--dry-run`）、無逆操作（`resolve-people` 一族每個破壞性面
  都有具名逆操作，這裡沒有）、無 git 追蹤閘（`rm -rf .git` 的 store 照刪）。真 binary：venue 持一筆舊 binary 沒遷走、人對另一筆仍存在的 work
  親自下的判定（帶 rests-on），rename 之後它從 store 消失、`validate` 看起來更健康；正確處置是 repoint 而不是刪。與本 repo 自己的規則衝突：
  `two-kinds-of-edits`（程式編輯不得銷毀判定編輯的產物）、`zero-instance-guards` 第 13 列（死 verdict 的處置是人的重新消歧）、merge 對同一形狀
  是整批拒絕（D31／D34）。**D60**：與 merge 對齊——改名之前掃三種 holder，任一筆 verdict 的配對已指向新鍵（同 holderKind、不論 field 與拼法）
  即 `assertNoVerdictAlreadyAt` 具名拒絕、零寫入，逐筆列 holder／欄位／value／judgement／rests-on，出路是先 repoint 或從 YAML 刪掉。
  rename 自此不做任何判定的刪除；第二段只剩被改寫的（同拼法折疊走 `collapseWinner`、拼法不同都留、原位）。R18／R19／R20 六支「丟死 verdict」
  的測試換成兩支拒絕測試（三種形：R19 DA 的死反向＋活同拼法、R20 的只有死的、拼法無關；person rename 對 organization holder）＋一支
  「被改寫的拼法全留、同拼法只留一筆」。
- **MEDIUM：pre-push 的重指在 build 之後，`PrePushHookTests` 以 repo root 為 cwd 跑前兩階段，跑一次 `swift test` 就改寫真工作樹**（regression
  第 6 列）；`ln -sfn` 對真目錄不取代、在裡面建巢狀連結回 0（security 第 13 列）→ 重指移進**守衛階段**（只有那一階段讀連結）、ln 之後驗
  `readlink` 等於目標，不等即中止；`[ ! -d .build ]` 那條只為 mock 而存在的略過分支拿掉；測試加「`.build/debug` 是真目錄 → 中止」。
- **MEDIUM：`ci.yml` 不在送審的 diff 裡、release 那一步沒釘 native**（第 7 列）→ 釘、重指、加進 verify 的檔案清單。
- **MEDIUM：MCP tool manifest 在本張長了 28%（24.2 → 30.9 KB），沒有預算或守衛**（第 8 列）→ **#578**。
- **MEDIUM：外部寫入把 D58 記成「一律丟／已落地」、E2E 只涵蓋已修的那一半**（DA 第 9 列）→ #554 body 與 R19 report 第 1 列同批 errata。
- **LOW：R19 report 宣稱的 #561 pointer 沒真的貼出**（第 10 列：`gh issue comment … -q .` 靜默失敗）→ 補貼，並記為「未量測就寫進報告」的實例。
- **LOW：`PackageManifestTests` 四個 fail-open**（第 12／16／17／19／22 列：非遞迴、目錄讀不到就跳過、只認 Tests 後綴、帶連字號的 target
  對映不到模組名）→ 遞迴走訪、讀不到即紅、母體取自 `.testTarget(` 宣告、`-`→`_` 映射、掃過的檔數與 `Tests/` 底下的 `.swift` 對帳。
- 其餘：doctor `first` 的註解不再說「count 完整」（第 11 列）；App 的 rename sink 上限 200 → 1,000 對齊 CLI（第 14 列：R20 疊在行尾的
  rests-on／留下的拼法在 App 面看不到）；App help 的 20 改讀 `Entry.perRecordWarningCap`（第 20 列）；`VerdictEdgeSet` 對非 StoreKey 的邊
  靜默當死邊（第 15 列）→ **#579**（根治在 load／validate 那一層，是一條新的零實例守衛）；DA 第 25 列更正四席的「silent」——confirmed＋rejected
  並存時 validate 改名前後都會報，只有一筆死 rejected 時才真的無聲；DA 第 26 列：R20 的 O(N) 註解只對第一段成立——那段已隨 D58 拿掉。

## R21 verify：D60 對 quarantined 檔是盲的，而「不刪判定」還差一半

R21 verify 5 席齊（Codex 席仍 429），38 列合併、0 HIGH、16 MEDIUM——三束：

- **D60 的母體沒有 quarantined 檔**（第 1／8／12／16／36 列；DA 真 binary 前後對照：一個 quarantined 的 venue 持 `work:new2020a` 的 confirmed，
  rename 照過、只印「其中若有 verdict 指向此鍵不會被遷移」——那句講的是舊鍵方向；修好那個檔之後 `validate` 全綠，一筆從未對這篇做過的判定成了
  活的斷言。**D61**：與同函式的 `quarantinedFileClaiming` 同一套紀律——對 quarantined 檔做行級文字比對、讀不到即 fail-closed、命中就拒絕並點名那個檔；
  CLI／App 的 quarantine 揭露改寫成兩個方向。
- **「rename 不做任何判定的刪除」是過度斷言**（第 2／14 列；DA 真 binary：兩筆同拼法、judgement 與 rests-on 不同的 confirmed，`validate` 不出聲，
  rename 後只剩一筆、另一筆的 digest 永久消失——正是撤掉 D58 的同一句話換個母體）。**D62**：折疊只折完全相同（含 judgement 與 rests-on）的重複，
  rename 不再呼叫 `collapseWinner`；那句量詞自此才是真話。
- **拒絕訊息在唯一的 CLI 出口上沒兌現**（第 7／9／11／15／17／24／28 列）：`displaySafeAssembled` 逐行截 400，R21 寫的 1,000 是到不了的死碼，
  而 rests-on 排在行尾——DA 真 binary 用一般長度的 judgement 就把 sha256 切成半個（比不印更糟：看起來像一個值、grep 不到）；行數也無上限。
  現在每筆命中拆成多行、每個 digest 自己一行（71 字）、至多 20 筆其餘揭露總數；測試把 description 送過與 CLI 相同的 sink 再驗。出路不再指
  `resolve-venues --repoint`——目的鍵此刻不存在，被拒的每一筆都沒有邊可改指（第 3／10／25 列）。
- 其餘：`renameEntry` 補 `oldKey != newKey`（第 4／20 列：自我改名撞 D60、訊息說目的鍵不存在）；`census-parity.yml`（CI 裡唯一真的跑守衛的
  workflow）與 `ci.yml` 的 `swift run` 沒釘 native（第 5／38 列）；hook 對真目錄在 ln 之前就拒、不留巢狀連結、不回顯 readlink（第 21／26／27 列）；
  `PackageManifestTests` 的 `guard let enumerator` 是死碼——`enumerator(at:)` 對不存在的目錄回非 nil（第 13／32 列）→ 改問目錄在不在；
  `moduleUniverse` 碰撞即紅（第 23／29 列）；§3.5 的 D55 段仍是現在式與 D60 段矛盾（第 6／30 列）→ 改成收攏史；`RenameReportSummary` 的
  註解仍寫 200（第 19 列）；parity 表「掛在兩處」→ 三處、`--yes` 的「6 個」→ 量測 11 個且 `rename` 不在那張表（第 33／35 列）；D60 補記進
  `two-kinds` 的 rename 列與 guards 第 13 列（第 18 列）。第 31 列（#577 搭車逐輪長大）與第 37 列（rename 契約從必成變成可能拒絕、App 按鈕硬失敗）記錄。

## R22 verify：needle 裡的那個空白

R22 verify **6 席齊**（Codex 席回來了），37 列合併、4 HIGH、15 MEDIUM——四個 HIGH 是同一件事：

- **D61 的行級比對被 YAML 折行擊穿**（第 1／2／3／4 列，四席同指；DA 真 binary 對 `rename` 與 `rename-person` 各重現一次）：needle `<kind>:<newKey> ::`
  含兩個空白，而 YAML 只在空白處折行——本 repo 的 emitter（Yams，libyaml 預設寬度 80）把長 value 折在 ` :: ` 之前，live store 當天實測 8,692 筆
  verdict value 裡 2 筆折在那裡。折行的 quarantined verdict 穿過 rename，三處通知還說「已擋過」——而 `quarantinedNotScanned` 的 doc 早就逐字寫著
  行級比對會漏掉折行、「掃過且沒有」不可誠實斷言（第 12／16 列）。DA 指出正解就在隔壁：merge 的隔離檔閘讀原始位元組、needle 是裸 key、不含空白，
  「可能偽陽性、不可能偽陰性」寫在它自己的檔頭。**D63**：位元組比對 `<kind>:<newKey>`（命中的下一個位元組不得是 StoreKey 字元，鄰居鍵不誤擋），
  訊息只說「位元組裡出現」、出路是修檔；quarantined 命中先列——R22 把它們排最後，25 筆 organization 就把那一筆擠出上限，而它是唯一沒有其他面
  看得到的一類（DA 第 18 列）。fail-closed 那一支在 entities 佈局下到不了（`quarantinedFileClaiming` 先擋，DA 第 19 列）——doc 寫明，不假裝它在跑。
- **「零資訊損失」只在 rename 那一步為真**（security 第 14 列）：D62 留下的同鍵異 judgement 沒有任何面看得見（`contradictoryVerdicts` 只比
  confirmed×rejected、D39 第二類以位元組相異分組），而下一次合併會以 #468 的血統層收成一筆。**D64**：`StoreHealth.duplicateVerdictRecords`
  （warning，guards 第 28 列），doctor／App 各一格；live store 0。merge 與 rename 的折疊規則自此明寫是兩條，不再說「同一條不變式」（第 8／11 列）。
- **唯一的使用者出口說的是 R21 的規則**（第 7／10／15／26 列，四席）：CLI 兩處抬頭仍印「同拼法只留一筆——#468 的血統層決定留哪筆」，兩句在 D62
  之後都為假；散文三處都改對了，只有人真的會讀的那兩行沒改。
- 其餘：keeper 合併路徑的 `describeDedupedVerdict` 仍不印 rests-on（Codex 第 6 列；R20 只補了另一個生產者）；D62 折疊的 `bytes == && ref ==` 是
  恆真的死條件、旁註的 O(N) 對閉包裡逐對重算為假（第 5／21／24／35 列）→ `ProvenanceReference` 加 `Hashable`、字典一次雜湊；`verdictsAlreadyAtTarget`
  的「每行本來就不超過 400」算的是輸入 scalar 數，DA 實測 406 字（第 9／23／37 列）→ 註解改成量測、截在 400 減標記長度只截一次；D39 第二類訊息
  只怪手改而 rename 就會帶過去（第 25 列）；hook 對普通檔案說「是真目錄」（第 34 列）；§3.5 R18 段的「自此」與 D62 段的「自此」對讀者是兩句現況
  （第 20 列）；`--yes` 列量了 11 個卻沒說 `resolve-venues` 不在表裡（DA 第 31 列，另案 #580）；`NameIdentity.canonical` 的量測只涵蓋 validate
  路徑（第 28 列）。第 17 列（22 輪把一個寫入面擴成三種實體的 verdict 生命週期重寫，沒有一輪把那個擴張當成 scope 決定交給使用者）、第 19 列(b)
  （`quarantinedFileClaiming` 對讀不到的檔說「佔用」——#61 既有）、第 27 列（#577 搭車）、第 30 列（`--build-system native` 已被 SwiftPM 標為
  deprecated，11 處 pin 會同一天壞——記進 #577）、第 36 列（D63 讓任何讀不到的 quarantined 檔擋住所有 rename——與 `quarantinedFileClaiming`
  同一條既有紀律）記錄。

## R23 verify：合成的 `Hashable` 是 canonical 的——ensemble 不完整，但那一列是真的

R23 verify **5 席在起跑就撞 session limit**（requirements／logic／security／regression／DA 全部
「You've hit your session limit · resets 2:10am」），只有 Codex 席回來——與 R18 同一種形，記為**不完整**、
R24 落地後重跑 6 席。Codex 純靜態讀 diff 回 3 列（1 HIGH／1 MEDIUM／1 INFO），沒碰 D63 邊界、D64 分組、
`refusalLineMax`、散文與外部寫入——那是未涵蓋，不是判為乾淨。

- **HIGH：D62 的「完全相同才折疊」用合成的 `Hashable`**——Swift `String` 的 `==`／`hashValue` 走 Unicode canonical
  equivalence，不是 UTF-8 位元組相等。同一個舊鍵上兩筆 confirmed、judgement 相同、literal 分別是 NFC `Sankhyā` 與 NFD
  `Sankhya\u{0304}`：rename 後 `firstSeen` 把兩筆當同一筆折成一筆，一種拼法永久消失——D62「拼法不同的都留、零資訊損失」
  在這一格為假，而 R23 的旁註「value 相等已蘊含拼法位元組相等」正是那句假話。**本 repo 在 R16（D42）為了同一個原因把
  第二半掃描的去重從 `==` 換成 `Set<[UInt8]>`**，R23 把同一個缺陷換到 rename 這條路上。紅測試釘住時，alpha 那筆的折疊列
  自己就印著「留『Sankhyā』（正規化後相等、**位元組不同**）」——描述函式看得出來，折疊卻照做。**D65**：`ProvenanceReference`
  **拿掉**合成的 `Hashable`（要拿它當鍵只有一把），新增 `byteExactKey: [[UInt8]]`（field、value、`Kind` 的每個欄位各占一格、
  nil 與 case 用 tag 元素分開、`restsOn` 逐段），D62 的折疊與 **D64 判「全部完全相同」的鍵**（同一個缺陷的第二處，Codex 沒點名、
  本輪順手抓到：judgement 只差 NFC／NFD 的兩筆曾被說成「全部完全相同」）一起換。
- **MEDIUM：per-record 上限在 `validate()`／`StoreHealth` 產生訊息時就丟掉明細，而 App help、doctor 描述與 parity 的 `validate`
  列仍把 CLI `validate` 指為「完整逐行」的出口**——R14–R23 陸續加的四個求值上限（近重複組、重複 venue 邊、confirmed literal、
  重複判定記錄，每筆記錄至多 20 則加一句概括）三個面共有，CLI 只是不再加一層面級的 20 則截斷；一個 venue 25 筆 work 各持兩種
  confirmed literal 時，照 help 去跑 CLI 仍拿不到被省略的 5 筆。**D66**：**不加**「完整列舉模式」——那是替 CLI 開一條繞過求值
  上限的路，而上限存在的理由正是讀取路徑不能被 store 內容撐爆（R14 verify security 第 18 列）；概括句說了「另有 N 個未列出」，
  沒有東西是沉默的；要全部只能讀 YAML。七處宣稱改成「不加面級截斷、per-record 上限三面共有」，parity 的 `validate` 列理由收窄
  （裁決不變），`ValidatePerRecordCapCLITests` 走真 binary 釘住實際契約。

## R24 verify：D65 只換了兩個鍵，而問「完全相同」的地方有四個

R24 verify **6 席齊**（自 R22 以來第二次），39 列、**0 HIGH**、20 MEDIUM、12 LOW、7 INFO。沒有一席否定 D65／D66 的方向；
MEDIUM 全是兩個裁決的**下游沒跟上**。

- **D64 的措辭在拼法只差位元組時說謊**（第 3／11／16 列三席同指）：R24 拿整筆 `byteExactKey` 判 sameness，而分組鍵正規化 literal——
  `beta`／`BETA`、judgement 相同的兩筆被說成「judgement 或 rests-on 彼此不同」，操作者去找一個不存在的證據衝突。**D67**：kind 那一半用
  `kindByteKey`、拼法用 literal 的 UTF-8，三向措辭；排除條件收窄成「每筆各有自己拼法」——第 8／10／18 列：第 27 列以位元組去重、看不到
  「同一拼法出現兩次」，R24 的 `spellings.count > 1` 把 `Alpha`／`Alpha`／`ALPHA` 整組吞掉、三個面都不出聲；DA 真 binary：25 個純拼法組時
  `duplicateVerdictRecords` 回 0 而 doctor 描述沒說那是排除後的 0——accessor doc 與 doctor 描述寫明 carve-out。同一函式的 CoW（Codex 第 1 列：
  取出再放回、每次 insert 複製兩個 Set）改原位修改。
- **`StoreHealth` 整層沒消毒**（security 第 13 列報 D64 一格，DA 第 20 列真 binary 量出七族全是 `displaySafe`、U+200B 原樣進終端）：
  **D68**：七族迴送 store 字串一律 `displaySafeInvisible`。
- **`byteExactKey` 的 doc 宣稱全 repo，換的只有兩處**（第 9／26／29 列、DA 第 39 列）：`fieldsLostByMerging`（person／work）以 canonical `==`
  判「倖存者已有」，被併記錄的 NFD 拼法隨檔案消失而報告說沒遺失；`paginated` 的冪等閘同型、寫入面靜默吞掉。**D69**：四處同一把鍵。
- **D66 換掉一句假話又寫了另一句**（第 12／14／37 列、DA 第 19 列）：「每筆記錄每族至多 20 則」對 11 族裡的 6 族為假——上限只在五族（則數是
  每筆記錄的組合），其餘線性、無上限。**D70**：七處措辭改成點名五族；`StoreHealth.swift:145` 那句「掃得到只對 CLI validate 成立」也是同一段
  doc 裡的矛盾。**被截的明細沒有出口這件事記成 #581**（第 5／17 列：`replace-endnote-and-zotero` §4）。
- 其餘：`verdictsRetired` 不印 rests-on（Codex 第 2 列，同一族的第三個生產者）；§3.5 第 921 行仍說 `Hashable` 字典（第 4／15／23 列）；
  guards 第 13 列的「完整逐行」與第 28 列量測的 grep 會數到概括句（第 6／7 列，後者是 R17 在第 27 列修過的同一個錯）；三處仍標 D61（第 21／36 列）；
  `verdictKeys`／`verdictsByKey` 是死碼——DA 更正：出自 R12／R17、死了十二輪 verify（第 24／31 列，刪）；`verdictEqualityKey` 的 malformed
  回退鍵分不出 nil 與 ""（第 25 列）；resolver 的否決抑制鍵用 U+0000／`|` 拼接（第 27 列，改 struct 鍵）；D63「不可能因折行偽陰性」對手改的
  雙引號 scalar 續行為假（第 28 列，收窄成本 repo emitter）；#577 的 Expected 沒點名 ci.yml／census-parity 的 6 處 pin（第 30／32 列，補 comment）；
  CLI cap 測試綁了走訪順序（第 34 列）；D65 的 live-store 量測沒進 repo（第 22 列）。

## R25 verify：每一輪修一格、下一輪抓到它的兄弟

R25 verify **6 席齊**，44 列、**2 HIGH**、16 MEDIUM、13 LOW、13 INFO。兩個 HIGH 都是 R25 自己剛寫的東西：

- **D67 的 carve-out 不看 kind**（logic 第 1 列 HIGH；Codex、requirements、security、regression、DA 五席同指）：`Alpha`／`ALPHA` 各帶相反
  judgement 時，`spellings.count == count` 成立、整組委派給第 27 列第二類——而那一面只看 literal、說不出 judgement／rests-on 差異，訊息還叫人
  「手改 YAML 留一筆」。一個真的證據衝突被一句銷毀判定的指令取代，正是 R21 D60／R22 D62 為 rename 關掉的那件事。**D71**：carve-out 多一個合取項
  `kinds.count == 1`；第 27 列的「留一筆」帶限定詞；accessor doc、doctor 描述、App help 三處寫明；上限改在渲染前套（Codex 第 4 列）。
- **D70 的「其餘家族線性、每筆至多一則、撐不爆」是漏成員的封閉列舉**（DA 第 2 列 HIGH；logic／security／regression 三席報成措辭問題）：
  被漏的正是唯一另一個組合式家族——`Person.validate()` 的近重複，兩兩比較、無上限，程式碼裡還寫著「名字數是個位數量級、O(n²) 不是問題」。
  DA 真 binary：200 個共用 matchingKey 的名字 → 19,900 則、7.6 MB、`cappedRecords` 0；live store `wen-chi-chung` 一筆就出 3 則。生長路徑是既有的
  程式編輯（`mergedPersonKeeper` 把被併者的 `names.all` 全 append 進 variant）。**D72**：person 近重複與 venue 同一套（先以 matchingKey 分組、
  一組一則、每筆記錄 20 組、組內 5,000 對；#576 在此落地）；venue 的求值上限命中也留概括句（第 23／31 列：`cappedRecords` 曾漏計）；「其餘家族」
  的措辭改成逐族點名——每筆 reference／配對各一則、與資料項數線性；死 verdict 掃描對 quarantined 檔的查找加快取（第 11 列：每一筆重讀全部檔）。
- **`byteExactKey` 的「四處」仍是過度斷言**（第 7／25／29 列）：`UpdatePerson` 與 `AddOnlyEnrichment` 的去重還在比 canonical；venue 的
  `fieldsLostByMerging` **根本不比 references**（DA 第 17 列、requirements 第 21 列），被併 venue 的 `paginated` judgement 隨檔案靜默消失。
  **D73**：七處封閉列舉（doc 自此寫「全樹 `references.contains(` 的每一個命中都在其內」）；venue 合併補遺失偵測；三份訊息說出「正規化後相等、
  位元組不同」（第 14 列）；`paginated` 冪等閘上方那句「以 `Equatable` 判」改掉（第 24／37 列）。
- **D68 只掃了 `StoreHealth`**（第 8／9／13／16／22 列；DA 真 binary：person 名字裡的 TAG 字元 U+E0001／U+E0041 與 ZWSP 原樣穿過 CLI **與 MCP
  doctor payload**，而 CLI 那一行的 exempt 註記說「訊息在 validate 裡已逐項消毒」）：五族 `validate()` 的名字、未知欄位鍵、`fields["editor"]`、
  `pages`、孤兒 variant、ISSN qualifier 全是列舉式 `displaySafe`。**D74**：全部換 `displaySafeInvisible`；`InvisibleEscapeCoverageTests` 對五個生產者
  檔做源碼掃描——每一個 `displaySafe(` 的第一個引數要在封閉的允許清單裡（StoreKey 驗過的 key／holder）——`DisplaySinkCoverageTests` 把兩個
  函式視為等價（第 36 列），沒有守衛認得出這個差別。
- 其餘：`RejectedPairKey` 改 public、`AkashicService` 的 `pairingKey` 同型 U+0000 拼接一起換（第 28 列）；`verdictEqualityKey` 的 malformed 回退鍵給
  field 加長度前綴（第 27 列）；CLI `--authorize` help 補三個桶（第 20 列）；`resolutionConfirmedField` 常量（第 34 列）；「統一拼法即可」拿掉
  （第 19 列）；`paginated` 位元組變體重複沒有掃描面——#582（第 26／30 列，non-verdict reference 的重複沒有任何家族看得到）；R25 送審的 diff 漏了
  `PersonResolver.swift`（第 40 列，files.txt 補上）；第 38 列（`authorize` 走 `argList`，#561）、第 42 列（`restsOnNote` public）記錄。

## R26 verify：守衛掃了五個檔，而生產者有八個

R26 verify **6 席齊**，54 列、**4 HIGH**、23 MEDIUM、17 LOW、10 INFO。四個 HIGH 裡兩個是同一件事、而且是我的流程：

- **送審的 diff 又漏檔——9 個**（Codex 第 1 列、requirements 第 2 列、logic 第 48 列、security 第 50 列）：`files.txt` 是從 R25 的複製再手工 append，
  R26 首次碰到的 `AuthorizedName.swift`／`UpdatePerson.swift`／`AddOnlyEnrichment.swift`／`Organization.swift`／`Divergence.swift` 與四個新測試檔全部
  不在 artifact 裡——D72／D73／D74 的主體沒有一席能從 diff 讀到（席次們回頭讀 HEAD 才確認）。R25 漏 1 檔、R26 漏 9 檔，漏檔機制沒被修。
  **R27 起 `files.txt` 每輪由 `git diff --name-only e7bd950..HEAD` 現算、只減去具名的 #556 排除**，並記進 memory；R26 verify 對那三條的
  「已落地」不算六席驗過——R27 verify 才是第一次完整 artifact。
- **同一列疊了兩個 `.help`**（regression 第 3 列 HIGH、security 第 36 列）：R26 為 D71 的揭露在「重複的判定記錄」那一列**新增**一個 `.help(` 而沒併進
  既有的——SwiftUI 只顯示一個，D71 的揭露與既有的處置指引二擇一消失，而源碼掃描守衛對兩段文字都在的檔案照樣綠。併成一個；
  `RecordIssuesSummaryTests` 新增「一列至多一個 `.help(`」的源碼守衛。
- **D74 漏掉第六個生產者**（DA 第 4 列 HIGH，真 binary：一份 rc=0、印「全部通過」的 store，doi 裡的 ZWSP 與 TAG 字元原樣進 CLI `validate` 與 MCP
  doctor payload——`IdentifierDiagnostics.issue` 用 `displaySafe` 迴送識別碼原字串，四族 `validate()` 都委派給它，而守衛的檔案清單沒有 `Identifier.swift`）、
  **第七個**（DA 第 26 列：`crossRecordIssues` 迴送 work 的 title——全庫最自由的欄位，TAG 原樣進 CLI）、`Models.swift` 三族 validate() 不在掃描清單
  （requirements 第 9 列、logic 第 15 列、security 第 20 列、regression 第 24 列）、key 拒絕訊息與 quarantine reason 零消毒（security 第 18 列：
  `add-venue $'alpha\U000E0001'` 一次普通 CLI 呼叫、不需要先污染 store）、quarantine reason 的二次消毒把 `StoreKey.pattern` 打壞成
  `\u{005C}A[a-z0-9]…`（DA 第 44 列：一句修法指示被改寫成不存在的正則）、允許清單以識別字拼法為鍵——三個 `key` 站點正好是 key **沒**通過
  StoreKey 才出的訊息、`h.slot`／`h.digest` 是死條目、`displaySafeClipOnly(` 完全繞得過（security 第 19／35 列、requirements 第 31 列、logic 第 33 列、
  regression 第 53 列）。**D75**：生產者對 store 字串一律 `displaySafeInvisible`——八個檔（加 `Models`／`Identifier`／`LibraryStore`）全部換掉，
  守衛**沒有允許清單**：生產者檔案裡 `displaySafe(` 一律違規（對 StoreKey 驗過的字串兩者輸出逐字相同，換掉沒有代價），`displaySafeClipOnly(` 只在
  同一行寫明「已消毒」的 exempt 註解時放行，三個 helper 的實作行是封閉列舉、死條目即紅；quarantine reason **在生產端消毒一次**（未信任的部分走
  `displaySafeInvisible`，pattern 與 uuid 原樣），CLI `quarantineLines` 與 MCP doctor 只截不逃；端到端三條：識別碼、跨記錄 title、quarantine reason
  （含「pattern 原樣、無 `\u{005C}`」）。
- **D72 只搬了 venue 五層裡的四層**（requirements 第 7 列、logic 第 13／14 列、security 第 21 列、regression 第 37／38 列、DA 第 27 列——DA release 實測
  198,000 個名字 15.97 秒、同大小單一分組 1.12 秒：組內 5,000 對的上限被「多組、每組剛好 100 個名字」一步繞開，總求值 ≈ 49.5 × n；超出 20 組名額的組
  照樣全部求值才被丟掉；capHit 而零違反的組印「其中 0 對是**近重複**（）」加一句叫人裁決 0 對；`capHitGroups` 在名額檢查前遞增、概括句把相交的集合當
  互斥報）。**D76**：整筆記錄 `pairsToEvaluatePerRecord = 100_000`（超過的組不評估、只計數）、四類分開記帳（未列出的真違反／未列出的觸頂／已列出但被截／
  整筆上限擋掉的）、零違反的觸頂組用自己的開頭詞「共用配對鍵過多」（不含「近重複」，`grep -c` 不算它）、一筆記錄一句概括且只列非零的類別。severity
  維持 warning——本族容許假陽性、不擋寫入，與 venue 的 error 刻意不同（venue 的同名段是沿革記錄、一百次改回同名不是真的沿革；person 的 variant 由合併
  無上限 append，數量大不是錯）。
- **venue 的 `capHit && listed == 0`**（Codex 第 5 列、logic 第 12 列：一組列出 1–2 對違反、其餘評到 5,000 對上限時 `listedCapHit` 不遞增、整筆零概括句、
  `cappedRecords` 漏計——R26 的測試用 110 段全不相交、與缺陷互補而非覆蓋；regression 第 42 列：同一筆記錄可以吐三句上限類訊息、兩句重複同一個數字、
  `listedCapHit > 0 && !budgetHit` 時說「有 0 組同名段未評估」）。**D77**：`evaluateGroup` 回傳 `capHit`（求值被截）與 `violating`（至少一對違反）兩個
  旗標；一筆記錄一句概括、只列非零的類別；有未列出的組才是 error，只有已列出但被截或整筆上限擋掉的是 warning（整筆上限自己另有一則 error，概括句是給
  `cappedRecords` 讀的記號、不重複 fail-closed——那一則 error 與概括句仍各說一次 `unevaluatedGroups`，記錄）。
- **`wouldContradictVerdicts` 在套上限之前渲染完全部配對、每配對的來源筆數無上限**（Codex 第 6 列；R25 第 4 列修的正是這個形狀而合併拒絕路徑原樣留著）。
  **D78**：生產端截到 5 個配對、每側至多 2 筆（至少留一筆 confirmed 與一筆 rejected，截斷後仍說得出為什麼矛盾）、其餘計數；enum 多帶 `totalPairs`，
  消費端那句「…共 N 個配對」照原數字說。
- **`fmt` 對 work／divergence 仍是裸 `encode(decode)`**（regression 第 39 列：R5／R12 說「三個同形的 shape」，那句指的是走 `AuthorizedNames` 的三個，而
  `Divergence.validate()` 有 error 級檢查——`fmt --check` 對一筆候選 key 不合法的 divergence 印「✓ 全部已是 canonical form」）。**D79**：五個 shape
  同一條紀律，判準是「validate() 有沒有 error 級檢查」；附帶記錄：`fmt` 對手改過記錄的 clone，`--check` 的 rc 自 R5／R12 起會從 0 變 1。
- **`byteExactKey` 的「七處」附了一條跑不出那個結果的稽核指令**（requirements 第 8 列、logic 第 16 列、regression 第 23 列、security 第 51 列：
  `grep 'references.contains('` 9 個命中、5 個不在七處、七處裡 2 處那條 grep 看不到、`paginated` 閘實際兩處）：doc 改成九處、稽核程序改成「引用
  `byteExactKey` 的檔案是封閉清單」（`ByteExactKeySiteInventoryTests` 釘住），`ResolutionLedger.appendIfAbsent`（刻意 `verdictEqualityKey`，#470）與
  `canonicalTwinNote`（刻意 `Equatable`）寫成具名例外。
- **D71 的限定詞只加在第二類**（logic 第 11 列；requirements 第 29／32 列、logic 第 34 列：carve-out 在 venue 家族 20 筆 work 的上限之後失去對象——第 21
  筆起兩族都不具名，缺口屬 #581）：第一類訊息在 `dupNote` 非空時也指路；App 的「同一 work 多個 confirmed literal」help 補「留之前先看」；accessor doc、
  doctor 描述、App help 三處寫明「在每筆 venue 20 筆 work 的上限之內」。
- **D73 改了 `akashic_update_person`／`akashic_enrich` 的可觀察語意而 parity 表沉默**（requirements 第 10 列、regression 第 54 列）：兩列各補「R26 D73
  重新確認，裁決不變、契約有改」，兩面描述補一句「冪等比位元組」。**venue 合併的遺失閘沒給 venue 這一格的出路**（regression 第 22 列；DA 第 43 列更正：
  出路的句子在，但對 venue 不可執行——`update-venue --paginated` 寫的是新的一筆，沒有工具面能逐位元組搬）：訊息對 references 那一項具名出路（逐字加進
  倖存者 YAML、或確認可丟棄後刪掉被併者那筆）並說出「只差位元組的雙胞胎也擋、零位元組損失是刻意的」；影響面（DA 量）：live store 485 筆 venue 裡
  **33 筆帶 paginated reference**（36 筆）、venue divergence **0** 筆——今天零回歸，#566 的 campaign 下次跑會撞到約 7%。
- 其餘：`#581` 標題「五族」→「六族」（第 28 列）；「其餘家族每筆 reference／配對各一則」四處補「／記錄」（第 46 列）；第 25 列（scope 擴張：#576 在本
  commit 落地、`UpdatePerson`／`AddOnlyEnrichment`、#577 的 CI pin——R22 第 17 列的觀察未經使用者裁決，**記錄，交使用者**）；第 40 列
  （`migrate-venue-variants --apply` 一律拒絕而命令與旗標留著——補記進 #567：未遷移的 format-13 store 自此只剩逐筆 `--add-variant`）；第 41 列
  （`.build/debug` 重指的同一段規則四份、措辭已開始漂移——補記進 #577）；第 45／47／49／52 列（無 injection）記錄。

## 第二次端到端又紅——這次是我的 binary

改成替換語意後測試 7/7 綠、四個 mutation 負控乾淨，真 binary 卻說「authorized 含不在
names 內的名字」。隔離半天，最後是：**`swift test` 不重編 `akashic` executable target**，
`.build/debug/akashic` 是改 service 之前的版本。`swift build` 印 `Build complete! (0.17s)`
是快取；`swift build --product akashic` 花 3.31s 才是真的重編。

驗法：`grep -a -c '<這輪新加的字串>' .build/debug/akashic`——版號不會說謊但也不會說話，
新字串在不在才是證據。已記 memory（`swift-test-does-not-rebuild-executables`）。

## 落地

- `updateVenue` 加 `authorize: [String]?`；CLI `--authorize`、MCP `authorize`，兩面同批
- 66 條寫入面測試（R1 的 7 條改語意 ＋ R2 新增 5 條：同書寫系統兩名拒絕／沿革前身保留時間／
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
  參數名兩面都印／長輸入理由不被截 ＋ R8 新增 3 條：repoint 的 literal 取自 verdict 不是 title／from-venue
  無 verdict 拒絕／combining-mark 密集輸入理由不被截 ＋ R9 新增 4 條：repoint 兩側退役相反判定且 undo 乾淨／demote
  退役 confirmed／同 work 兩個 literal 時 repoint 與 demote 都拒／無 verdict 的拒絕指出路 ＋ R10 新增 5 條：配對由多條邊
  實例化時 repoint 與 demote 都拒／同鍵異位元組的 confirmed 拒／退役的 verdict 具名／`addVenue` 回報存入值／NFD 修復報
  `authorizedRewritten` ＋ R11 新增 4 條：改指到本 work 已有邊的 venue 拒／同一批同 literal 交換拒而異 literal 交換對／`apply` 不得讓
  兩條邊指同一 venue／`verdictsRetired` 截 20 揭露總數；既有 3 條改 fixture 或改語意——D25 的形改手造、同配對 literal 邊 demote 收
  repoint 拒、`namesRewritten`／`namesDropped` 拆開 ＋ R12 新增 5 條：apply 逐筆略過並照寫其餘／repoint 只擋被動到的邊與相交的同
  literal move／否決抑制比正規形／`verdictsRetired` 逃脫不可見 scalar／no-op 帶 D30 三鍵；`namesFolded`／`namesAlreadyPresent`
  三桶、空陣列訊息 ＋ R13 新增 4 條（R13 verify 第 21 列：這裡曾寫「3 條」而列了四項）：三個 move 非相鄰相交拒／組合腿以正規化配對算
  skippedBecauseRejected／variant 與 authorize 的全空白項回報／入口拒絕訊息逃脫不可見字元 ＋ R14 新增 3 條：相交訊息印兩個拼法／
  既有重複邊的全部索引／入口拒絕訊息項數截 10 ＋ R15 新增 3 條：apply 對目的 venue 已持另一個 confirmed literal 的候選略過並具名／
  repoint 同形整批拒（同 literal 的另一拼法不擋——R16 翻成也擋）／doctor 對配對唯一性兩半各有計數 ＋ R16 新增 3 條、改 2 條：重複來源欄位
  的第二條邊報重複邊不報衝突（D44）／同一條邊在同一批被指定兩次自成一句／doctor 不對訊息二次逃脫；apply 與 repoint 的對照組（另一個拼法）
  從「照常」翻成「略過／拒」（D43）＋ R17 新增 5 條：D43 訊息兩桶同時說／repoint 相交訊息兩個拼法位元組比且逃脫不可見字元／
  `assertPairingHasOneEdge` 逃脫／doctor 的 `first` 受位元組預算約束／（既有）矛盾訊息前件寫全 ＋ R18 新增 1 條：doctor 的 `cappedRecords`）；`VenueNameInvariantTests` 39 條
  （R5 的 8 條 ＋ R6：拉丁／CJK joiner 拒、join-control 文字的 joiner 收、DI 不可見、訊息對操作者、
  沿革同名豁免、三張清單近重複、bootstrap 拒的 literal 帶理由 ＋ R7：區塊標點與外文鄰居拒、連續 joiner
  與浮動 virama 拒、草書文字補進區塊表、U+2800、碼位補零、豁免對粒度與端點保守、bootstrap 先問已有 venue
  ＋ R8：virama 基底要是同一文字的字母且 joiner 兩側同一文字、孤立標記不是名字、豁免端點要是 ISO
  ＋ R9：virama 與標記要與基底同文字、詞尾 chillu 後接空白、Indic virama 之前的 joiner、補充區塊入表
  ＋ R10：virama 之前的 joiner 要有後續字母且只限 Devanagari／Bengali、近重複訊息每組上限
  ＋ R11：近重複求值上限（全豁免組）、「另至多 M 對未評估」、同 venue 兩條 key 邊是 work 的 warning
  ＋ R12：倒置或非 ISO 端點的區間不豁免 ＋ R13：不變式訊息逃脫它剛拒掉的字元 ＋ R14：近重複訊息逃脫、同 work ≥2 個
  confirmed literal 是 warning ＋ R15：只差位元組的兩筆也是 warning（第二類、同家族前綴）、兩族 per-record warning 每筆 20 則上限
  ＋ R16：NFC／NFD 的兩筆真的是兩筆（D42）、混合情形點名位元組重複組、名字內容 error 與近重複組各 20 則上限、概括句不進家族
  ＋ R17：21 組合法沿革不消耗配額且真近重複具名（D48）、位元組重複註記截在 5 組時揭露、重複邊 warning 逃脫不可見 key
  ＋ R18：求值上限組與真違反組分開概括、整筆記錄的求值總量上限、authorized 四筆同鍵是一組（D52））；
  `VerdictHolderGridTests` 加「work 合併對持有被併鍵 verdict 的髒 venue 在 commit 前拒」與「person 合併對
  `authorized ⊄ names` 的 organization holder 在 commit 前拒」與「欄位遺失先於 holder 閘」；`NameIdentityTests` 加「不刪
  任何非空白 scalar」；`DivergenceResolveVenueTests` 25 條（三種結果各有測試 ＋ dry-run 對不可寫的 keeper 拒 ＋ 欄位遺失先於被併者的名字檢查 ＋ R12：遷移以正規化鍵去重／相反判定拒／塌邊留兩筆 confirmed literal 拒 ＋ R13：三方合併的 doomed↔doomed 相反判定拒／D32 守不變式本身且倖存者既有違反不擋、去重丟掉的回報 ＋ R14：dry-run 預告去重丟列／單一被併者自帶兩個 literal 拒／單一被併者內部的矛盾拒、三方合併的訊息指名兩筆記錄 ＋ R15：拒絕訊息把帶進來的與倖存者既有的分開列 ＋ R16：被併記錄內部整組的拒絕訊息說它擋（D45））；`VerdictHolderGridTests` 加 R16 兩條：
  把歧義搬到只持有其中一部分的倖存配對上拒、被併鍵上整組矛盾對搬到已有 confirmed 的倖存配對上拒 ＋ R17：holder 遷移不換掉倖存配對的拼法且收攏列印兩個拼法（D47）；
  `CollapseSurvivorPolicyTests` 加「拼法不同時倖存配對自己的勝」（同拼法 #468 照舊）＋ R18「三列碰撞留與 keeper 同拼法的弱血統那筆」「kept 解析不出時說出來」；`DivergenceResolveVenueTests` 加「keeper 路徑收攏列印兩個拼法」＋ R18「keeper 的死 verdict 讓位給活邊那筆」「三方合併走 #468 不走陣列順序」；`VerdictHolderGridTests` ＋ R18「person keeper 路徑活邊勝」「不相干 rename 不動另一 work 的重複」「rename 留被改寫的活 verdict」；`PairingUniquenessHealthTests`／`RecordIssuesSummaryTests` ＋ R18 `cappedRecords` ＋ R19「以記錄計」「App 渲染且家族值標下限」；`VerdictHolderGridTests` ＋ R19「三方碰撞六種排列同一答案」「被改寫的全留、死的全丟」＋ R20「早已指向新鍵的死 rejected 也丟」「不論拼法一律丟」「同拼法重複走 #468 不走順序」「不相干 reference 相對順序不變」「死列點名同拼法、否則第一筆活的」「`VerdictEdgeSet` 略過非 StoreKey 的邊」；`CollapseSurvivorPolicyTests` ＋ R20「收攏列印 rests-on digest」；`StoreHealthSurfaceTests` ＋ R20「每個家族存取子都被 doctor 與 App 消費」（源碼掃描，取代對 computed 家族無效的反射）；`PackageManifestTests`（新）守 test target 的 import 閉包；`PrePushHookTests` ＋ R20「native 產物目錄不在即中止」；`VenueAuthorizedWriteTests` 的 doctor 測試斷言 `deadVerdicts`／`contradictoryVerdicts`；
  `StoreHealthSurfaceTests` 的窗口改成掃到閉合大括號；`PairingUniquenessHealthTests` 加「家族計數
  不含概括句」；`RecordIssuesSummaryTests` 加「App 預覽不二次逃脫」；`VerdictHolderGridTests` 另加 person 合併的相反判定拒與遷移去重、work 合併的 holder 遷移矛盾拒 ＋ R14：holder 遷移留兩個 literal 拒、合併前就有的矛盾不擋、person dry-run 預告 #271 的去重 ＋ R15：住在被併鍵上的既有矛盾對不擋、被併鍵上既有的雙 literal 不擋、既有歧義變大仍擋且訊息分兩半、倖存者自己持有的 `person:<被併>` 矛盾對不擋而改寫後才相撞的擋、收攏列印原值並逐段截（merge 與 rename）（52 條）；`PairingUniquenessHealthTests`（新）與 `RecordIssuesSummaryTests` 加兩族家族計數；`VerdictEqualityTests` 加 malformed 回退鍵不碰撞；`OrderInsensitiveCollapseTests` 三處 pin 改成遷移前的原值；`AssembledDisplaySafetyTests` 加 organization 的 fmt 語意驗證；`DisplaySinkCoverageTests` 加「守衛認得 `displaySafeInvisible(`」；
  `CanonicalFormatValidationTests` 加 venue 語意驗證
- `record-divergence --candidate` 的 help 與 MCP `candidates` 描述補 venue（#553 遺留，兩面對齊）
- R22：`assertNoVerdictAlreadyAt` 改成 instance method、母體含 quarantined 檔的行級比對（D61）、命中多行化與 20 筆上限、出路改寫、`verdictsAlreadyAtTarget` 每行截 400（＝CLI sink）；`renameEntry` 補自我改名守衛；`migratedVerdicts` 只折完全相同的重複（D62）；hook 真目錄前置拒絕；`ci.yml`／`census-parity.yml` 三處釘 native 並驗 readlink；`PackageManifestTests` 問目錄在不在、模組名碰撞即紅；負控 7 支各紅一次、真 binary 重現 quarantined 形與 digest 截斷形
- R23：`assertNoVerdictAlreadyAt` 的 quarantined 掃描改位元組比對 `<kind>:<newKey>`（`bytesContainKeyToken`，StoreKey 邊界檢查）、quarantined 命中先列、上限走 `Entry.perRecordWarningCap`（D63）；`StoreHealth.duplicateVerdictRecords` 家族＋doctor／App（D64；第 27 列第二類已報的那一格不重報、每筆記錄套 `perRecordWarningCap`——首版無上限，全套測試的 doctor 位元組預算 fixture 把 `count` 從 20 推到 140 抓到）；`migratedVerdicts` 以 `Hashable` 字典折疊；`describeDedupedVerdict` 印 rests-on（`restsOnNote` 共用）；`verdictsAlreadyAtTarget` 截在 `refusalLineMax`；CLI 兩處抬頭與三處 quarantine 通知改寫；兩份 report doc、`migratedVerdicts`、`describeCollapsedVerdict`、`appendIfAbsent`、`NameIdentity.canonical` 的 doc 改成量測過的形；hook 訊息；負控 9 支各紅一次、真 binary 重現折行形（rename 與 rename-person）、偽陽性形、擠出上限形、D64 前後形
- R26：D64 carve-out 加 `kinds.count == 1`、上限渲染前套、第 27 列「留一筆」帶限定詞（D71）；person 近重複分組＋上限、venue 求值上限概括句、死 verdict quarantine 查找快取、「其餘家族」逐族點名（D72，#576 落地）；venue `fieldsLostByMerging` 比 references、`UpdatePerson`／`AddOnlyEnrichment` 去重比位元組、遺失訊息印「正規化後相等、位元組不同」（D73）；五族 validate() 的 store 字串全走 `displaySafeInvisible`＋源碼掃描守衛（D74）；`RejectedPairKey` public 給 `pairingKey`、回退鍵 field 長度前綴、`--authorize` help 補桶、`resolutionConfirmedField`；新測試 10 條、負控 7 支各紅一次
- R25：`kindByteKey`＋D64 三向措辭、排除收窄、原位修改（D67）；`StoreHealth` 七族 `displaySafeInvisible`（D68）；`fieldsLostByMerging` ×2 與 `paginated` 冪等閘比 `byteExactKey`（D69）；七處 cap 措辭點名五族、#581（D70）；`describeRetired` 印 rests-on；`verdictKeys`／`verdictsByKey` 刪；回退鍵 presence tag；`RejectedPairKey`；D61→D63 三處；折行宣稱收窄三處；新測試 7 條、負控 7 支各紅一次
- R24：`ProvenanceReference.byteExactKey`（D65；拿掉合成 `Hashable`）——`migratedVerdicts` 的 D62 折疊與 `duplicateVerdictRecordIssues` 的 sameness 同一把鍵；七處「完整逐行／要全部用 CLI validate」改成誠實措辭、parity `validate` 列理由收窄（D66）；新測試 3 條（NFC／NFD 兩筆都留且 `verdictsCollapsed` 空、D64 judgement 位元組、CLI 25 配對 → 20 則＋概括句）；負控 4 支各紅一次（鍵改 NFC、折疊忽略 kind、sameness 改 canonical、拿掉 cap）
- R21：`assertNoVerdictAlreadyAt`（D60）裝在 `renameEntry`／`renamePerson` 動任何記錄之前；`migratedVerdicts` 第二段只剩被改寫的；`describeCollapsedVerdict` 拿掉 R20 的 `why:`；hook 重指移進守衛階段＋readlink 驗證；`ci.yml` release 釘 native；`PackageManifestTests` 四個 fail-open 關掉；App rename sink 1,000；負控 8 支各紅一次（含拿掉 `Package.swift` 宣告）、真 binary 重現 R20 四席與 DA 的兩個形都被拒
- R20：`LibraryStore.migratedVerdicts` 重寫（D58，**R21 由 D60 取代**）、`describeCollapsedVerdict` 加 `why:` 與 rests-on、`VerdictEdgeSet` 驗鍵、doctor／App 名冊補齊、`lowerBound` 涵蓋 `total`／`errors`（D59）、`RecordIssuesSection` 加「矛盾 verdict」列、hook／`ci.yml` 釘 native 且重指失敗中止、`Package.swift` 註解改寫；負控 11 支各紅一次、真 binary 重現 DA 第 1 列並驗 doctor 名冊
- `mcp-cli-parity` 的 `akashic_update_venue` 列補記；`two-kinds-of-edits` 加一列、#553 那列
  理由改寫；`DivergenceResolve` 四處「venue 沒有 authorize 面」的文字改指向本面

## 不做（都有 issue）

- validate 被 per-record 上限截掉的明細沒有出口（組合式六族每筆 20 則、三面同；要全部只能讀 YAML）——#581（R24 D66 不加完整列舉模式；出口的形狀兩面一起裁）
- non-verdict reference 的位元組變體重複（`paginated` judgement 只差 NFC／NFD、identifier retrieval 同型）沒有任何掃描面——#582（R26 D73 讓冪等閘比位元組後才可達；三個掃描面都先過 `resolutionVerdictFields`）
- D71 的 carve-out 在 venue 家族 20 筆 work 的上限之後兩族都不具名（R26 verify 第 29／34 列）——#581 的同一個缺口（被截的明細沒有出口），三處揭露文字自 R27 起帶上限定詞
- `.build/debug` 重指的同一段規則在 pre-push／`ci.yml` ×2／`census-parity.yml` 各寫一份、措辭已漂移（R26 verify 第 41 列）——#577 落地時一併收成一支腳本
- `migrate-venue-variants --apply` 一律拒絕而命令、旗標與死碼留著（R26 verify 第 40 列）——#567；補記：未遷移的 format-13 store 自此只剩逐筆 `--add-variant`
- venue 合併的整筆記錄 fail-closed 與概括句各說一次 `unevaluatedGroups`（R27 D77 的取捨：概括句是 `cappedRecords` 的記號、error 是 fail-closed 的訊號，兩者消費端不同）——記錄不動
- 撤回面（把名字從 authorized 移出而不放新的進去）——#559
- venue 邊的移除面（同一 work 兩條邊指同一 venue 時唯一出路是手改 YAML）——#572（R11 把生產端關掉、既有的報 warning）
- `supersede` 退役判定記錄而 repoint／demote 沒有 trackedness 前置（merge 有）——#573
- ~~近重複求值上限只綁組內、組數不設上限~~（R16 起組數也有上限）；`vetVenueNames` 拒絕訊息項數無上限——#562 家族，記錄不動
- `matchingKey` 的空白切在 Character 上、「空白＋組合符號」整個 cluster 被丟掉（與 `NameIdentity.canonical` 不一致）——#574（R16 只把 guards 的鏡射對齊到這個行為）
- ~~`StoreHealthSurfaceTests.testEveryFieldIsConsumedByDoctor` 只掃 `doctor()` 開頭 6,000 字元——窗口是脆的，記錄不動~~ → R17 改成掃到閉合大括號（R16 verify 第 5／22 列：假紅會讓人學會忽略紅燈，且它懲罰在 doctor() 裡寫註解）
- venue 名字不變式的修復面（舊 binary 寫過的 store 只能手改 YAML，`fmt` 同輪從正規化改成拒絕）——#575（R16 verify 第 31 列）
- `VenueVariantMigration.run(apply: true)` 函式本身仍會寫，D41 的閘只在 CLI 層（R16 verify 第 28 列）——#567 刪命令時一併收
- `VenueResolver` 的否決抑制以 `matchingKey` 為鍵收窄了提名面的 recall，抑制是靜默的（R16 verify 第 23 列）——補記在 #559，撤回面落地時一併報計數
- judgement 記錄——#564（三面一次裁）
- `bootstrap-venues` 是否停寫 `[names[0]]`——#563
- ~~`addNames`／`addVariant` 的 `String ==` vs 守衛 `NameIdentity.canonical`——#560~~ → R4 三個迴圈
  一起改，程式缺口由本輪關掉（issue 留給 idd-close）
- `WritingSystem.isLatinLetter` 的 code-point 區間（×÷ 當字母、全形／越南文拉丁歸 other）——#568
- 輸出閘 `UnsafeToEmitScalar` 對 Cf 仍是列舉——#569（輸入閘本輪已收整個類別）
- `migrate-venue-variants` 退場——#567（本輪只寫明「#554 之後不得再跑」）
- 470 筆的 authorize campaign 與 `akashic-verify-venue` 的 authorize 步驟——#566
- 合併端把併入名字一律標 variant、且丟時間欄位——#565（D1 的同一個論證在合併端）
- repoint／demote 對「已是 key 但 venue 上沒有 confirmed verdict」的邊自 D18 起只剩手改 YAML（R14 verify regression 第 19 列）——live store
  2026-09-14 實測 2,203 條 key 邊、0 條無 verdict（R9 量過），不為零實例造介面；出現時屬 #559／#572 那一族的另一格
- `fmt` 的 organization 分支跑語意驗證（R14 verify regression 第 20 列）——對稱性論證搭車，本身是對的；org 的 `authorized` 面在 #557
- `record-divergence` 兩面 help 補 venue（R14 verify regression 第 29 列）——#553 遺留的兩行文字，歸屬記在這裡
- `assertHolderAddsNoViolation` 與 `migrateHolderVerdicts` 各算一次 `rewrittenVerdicts`（R14 verify 第 25／26 列）——DA 證實等價，代價一次 O(n)；
  收斂要改 `migrateHolderVerdicts` 的回傳形狀，記錄不動
- `resolve-venues --apply` 對「目的 venue 自己違反名字不變式」仍是整批零寫入（R17 verify 第 14 列：與 D33「store 狀態不符逐筆略過」的分類相反，而 D8 把
  觸發集合放大到最常見的手改痕跡）——**記錄不動、理由寫出來**：D33 的略過對象是「這一筆候選寫進去會造出的形」，略過它不影響其餘候選；這一格是「目的
  venue 這筆記錄本身寫不進去」，逐筆略過得把已改寫的 entry 邊撤回、把那個 venue 的全部候選一起撤，而 store 已經在對操作者說「先修這筆 venue」（#575 的
  修復面）。fail-closed 是對的，分類不同是因為擋的東西不同；#575 落地後重看
- `akashic_resolve_venues` 的請求面沒有筆數上限——`apply` 陣列由呼叫端決定，回報的 `applied`／兩個 skipped 陣列與它同階（R17 verify 第 9 列；DA 更正
  security 席：每列體積早被 `describe` 的 5 項 × 120、`IndexList` 的 10 項夾住，與 `verdictsRetired` 那個「體積由 store 內容決定」的威脅模型不同）——
  要加就加在請求面、一次管三個陣列，另裁
- person 側的近重複掃描（`AuthorizedNames.validateNearDuplicates`）沒有求值上限也沒有則數上限——venue 側 R10–R18 補的防線的孿生（R17 verify 第 13 列）——#576
- `jsonBytes` 量的是 compact 序列化而 `jsonString` 是 pretty（R17 verify 第 15 列）——實測每則多 85–113 bytes、20 則約 3.5%，三個消費端同一個偏差、
  預算留有餘裕；doc 寫明，不逐個呼叫端補係數

## R27 verify：消毒搬到了生產端，而沒有人說誰逃、誰截

R27 verify **6 席齊、第一次完整 artifact**（66 檔三方一致），37 列、**5 HIGH**、17 MEDIUM、9 LOW、6 INFO。五個 HIGH 加十列
MEDIUM／LOW 是**同一個缺陷的十五個位置**：D75 把消毒搬到生產端、把兩個 sink 改成只截，但沒有一句話寫下「哪些字串在哪一層逃脫」，
於是每一層各自決定——

- quarantine 的 decode-error 支把 `StoreYAMLError` 內部已逃脫的片段**再逃一次**（第 1／27 列，真 binary：`peri\u{005C}u{0007} odical`——訊息說
  store 裡有一個反斜線，那裡沒有）；
- `invalidInput` 對 `assertNoErrors` 已消毒的 what／why 再逃一次、`fmt` 疊到**第三層**（第 5／12／14 列：`Al\u{005C}\u{005C}u{200B}pha`——訊息叫人
  去 YAML 裡修一個 grep 不到的字串；R27 把這一格換成 `displaySafeInvisible`，與同一個 enum 另外兩格相反的方向）；
- MCP doctor 的 crossRecordIssues、App 的 `displayReason`、`update_person` 的兩個 sink 各自對已消毒訊息再逃（第 2／4／11／16／17 列）——CLI 與
  MCP 對同一個 `StoreHealth` 事實印出不同字串；
- quarantine 的 `file`、`unknownFieldFiles`、`fmt` 的檔名**完全沒逃**——ZWSP／TAG 原樣進 CLI 終端與 MCP payload（第 3 列，兩面實測）；
- 被改成只截的兩個 sink 會把 `\u{200B}` 從中間切開、輸出以裸反斜線結尾（DA 第 19 列：`refusalLineMax` 的註解早記過同一形狀）；
- 守衛掃八個手寫檔、不掃 sink——兩種缺陷都在視野外（第 15／24 列）。

其餘：D76 的預算鎖存＋插入序讓 20 組 × 101 個同鍵名字把其後 25 組真違反**全部餓死、rc 0**（DA 第 22 列，升級 regression 的 LOW）、觸頂訊息
20 行逐位元組相同、無從定位（DA 第 20 列）、概括句少 venue 同輪剛加的限定詞（第 31 列）；D77 的 `capHit` 漏掉「列滿 3 對就停」那個截點
（Codex 第 6 列、第 23 列）；D78 零測試、兄弟 case 仍渲染後才截、「各筆的出處如上」對被略去的筆為假（第 8／18／26 列）；`namesReport` 對同批
位元組相同的重複零回報（Codex 第 7 列）；`ByteExactKeySiteInventoryTests` 靠 `StoreHealth` 一行**註解**成立、對它要防的 `kindByteKey` 漂移是盲的
（DA 第 21 列，mutation 實證）；`store-format.md` 仍寫「七處」、§5.7「五條，封閉」漏了整筆總量上限與 D77 的 severity 分岔（第 9／10／13 列）；
guards 第 28 列與 parity 只列四層（第 25 列）；merge 遺失訊息的 field／value 原樣插值（第 28 列）；`StoreMigration` 對已消毒的 crossRecordIssues
再逃（第 29 列，今天不可達）。第 36 列的 scope 觀察（+9,317／−533，35 個檔與 authorize 無關）照 R26 第 25 列記錄不動、交使用者。

## R28 落地：一個邊界（D80）

**D80（Claude 代裁）：store 字串在最靠近它的地方逃脫一次，之後每一層只截。** 落到程式上是三件事，每一件都有掃全樹的守衛
（`SanitizationBoundaryTests`，不靠檔案清單）：

- **擲出端消毒**：`StoreYAMLError` 的每個 throw 站點逐項 `displaySafeInvisible`（YAML.swift 127 個站點、Provenance／AuthorshipCompleteness／
  PersonIdentityMigration；23 處列舉式 `displaySafe(` 換成性質式、26 處裸插值補上）——YAML.swift 檔頭那句「約 50 個站點未消毒，靠 sink 兜底」
  自此為假並改寫；`StoreIOError.invalidInput` 的 what／why 由擲出端消毒（DivergenceResolve 四處「傳原字串」反過來）、描述只截；程式構造值
  （context／field／count／rawValue／uuidString…）是一張封閉表、每列有理由。
- **錯誤描述的邊界**：`displaySafeError(_:max:)` 一個入口——自帶消毒的錯誤型別（`errorDescription` 內部已逐項逃脫：StoreYAMLError／StoreIOError／
  DivergenceResolveError／兩個 MigrationError／StoreIncarnationError／ConfigError，封閉列舉由原始碼現算釘住）只截、其餘（Yams、I/O）逃一次。
  quarantine 的四個 catch、`CanonicalFormat.describe`、MCP 的 14 處 `displaySafe(String(describing: error))`、`writeFailures`／`writeFailed` 的
  生產端、CLI `rebuildError` 全部改走它；那些型別描述裡的 `displaySafe(` 一律換成 `displaySafeInvisible(`。
- **sink 只截、原始載體逃一次**：MCP doctor 的 crossRecordIssues、App `displayReason`、`update_person` ×2、`StoreMigration`、`fmt` 的 reason、
  CLI `f.error` ×2、`wouldLoseFields` 的 losses（`fieldsLostByMerging` 三份改成回傳前逐條 `displaySafeInvisible`，內部片段原樣）改只截；
  quarantine 的 `file`、`unknownFieldFiles`、`fmt` 的檔名、App `displayFile`、resolver 的 reason、四個 migrate 報告的 reason 改
  `displaySafeInvisible` 並標「未消毒」。`displaySafeClipOnly` 的截點退到最後一個沒閉合的 `\u{` 之前。

其餘：D76——小組先評估（組依大小升冪）、預算不鎖存、觸頂訊息點名組員（`共用配對鍵過多（組：「X」）`）、概括句補「部分組可能只評估到組內上限」
與「未評估的是最大的幾組、其中可能含真違反」、doc 改寫第五層的結果與 venue 不同；D77——`truncated`（列滿 3 對**或**達 5,000 對）才是進
`cappedRecords` 的旗標，`capHit` 只管措辭；D78——`wouldLeaveTwoConfirmedLiterals` 同樣在擲出端截（`broughtTotal`／`existingTotal`）、出路改成
「標『另有 N 筆略』的配對要開持有記錄的 YAML 找其餘幾筆」、`MergeRefusalCapTests` 釘住四件事；`namesReport` 以 `seenInBatch` 分流同批重複；
`ByteExactKeySiteInventoryTests` 的 needle 改 `byteExactKey|kindByteKey`、只看程式行；`InvisibleEscapeCoverageTests.producerFiles` 由建構
`ValidationIssue(` 的檔案集合現算對帳；`DisplaySinkCoverageTests` 認得 `displaySafeError(`。散文：§5.7 六條並寫出概括句的 severity、
`store-format.md:919` 不再複述數字、guards 第 13／28 列、parity `validate` 與 `update_venue` 列。

**誠實邊界**：AppKit／Graph／Proposition／TractatusDocs 各自的錯誤型別描述仍是列舉式 `displaySafe(`，不在 `displaySafeError` 的封閉列舉裡——
它們的 sink 是 App 與 CLI 的字串面、不經 quarantine／MCP 的載體，本輪不動；`VenueMigration`／`VenueVariantMigration` 的 `MigrationError` 走
`CustomStringConvertible`（`description`，不是 `errorDescription`），守衛的掃描只認後者——四個 migrate 報告的 reason 因此標「未消毒」由 sink 逃。


## R28 verify：邊界寫在 StoreIO，而錯誤住在六個模組

六席齊、50 列（11 HIGH／15 MEDIUM／14 LOW／10 INFO）。HIGH 全部是同一件事的不同位置：D80 說「`displaySafeError` 是 Error → 文字的唯一入口」，
而樹上有三個入口沒走它——MCP 的 per-tool 錯誤出口（Server.swift，`displaySafeMultiline(message)` 對每一則已在擲出端消毒的訊息**再逃一次**，
真 binary 兩面實測：CLI 印 `\A[a-z0-9]…\z`、MCP 印 `\u{005C}A…`，一句修法指示被改寫成不存在的正則；第 1／7／17 列）、App 的 `errorMessage`
（`EntryViews`／`AdjudicationViews`／`GraphView` 六處取原始 `errorDescription`，`AppState:359`／`EntryViews:348` 再逃；第 15 列）、
`ServiceError` 本身（住在 AkashicMCPKit，StoreIO 的 `is` 鏈碰不到它；`displaySafeError` 對它再逃一次，而它的 doc 明寫「此處不再消毒」正是為了避免這件事；
第 5／13 列）。守衛的盲點也是同一形：只看 `\(…)` 插值、看不到 `what: relativePath` 這種裸引數（第 2 列，D80 拿掉 sink 兜底後檔名原樣送出）；
`^context$` 的允許清單放過 `YAML.swift:1777` 由未信任 mapping key 組出的 context（第 3／6／22 列）；自帶消毒集合只掃兩個目錄的 `errorDescription`
（第 14／19／32／37 列：`VenueMigration` 的 `MigrationError` 用 `description`、Index／Query／Graph／App 的錯誤全在鏈外）。R28 自己造出的：
截點退讓以 `!escapingBackslash` 當前件，砍到了 `displaySafeAssembled`（CLI 全域出口，一行 406 scalar 掉到 41；第 8／29／36 列）；
`enrich`／`enrich_from_zotero` 的 `writeFailed` 生產端改 `displaySafeError`、sink 仍逃（第 9 列）；`ZoteroImporter` 的第四個 writeFailed 載體
完全在邊界外（第 25 列）；`namesReport` 的同批去重排在空白檢查之前（第 12／30 列）；thesis 分支的片段層 `displaySafe` 被 return 再逃（第 4／20 列）；
`resolve-divergence` 的 `report.failures` 生產端已 `displaySafe(citekey)`、sink 再逃，warnings 完全裸印（第 18／21／33／34 列）；
#583 記的世界與 binary 相反（第 10 列：自帶消毒家族也雙重逃脫、「不再有原始 scalar」為假——真 binary 吐出原始 U+200B 與 U+E0001，第 11 列）。
其餘：§5.7「本節的五條」與「六條，封閉」同段矛盾（第 16 列）、`ci.yml` 沒有 `permissions:`（第 35 列）、D76「預算不鎖存」在升冪之下不可觀測而測試以它命名
（第 26／42 列）、venue 與 person 的餓死行為不同而 doc 只寫「結果不同」（第 43／45 列）、三處與程式牴觸的 exempt 註解（第 28／38 列）、
兄弟 case 的「出處如上」在截斷時無條件（第 27／31 列）、掃描器對無括號的命中會吞掉下一段（第 47 列）、Scope（第 24 列）。

## R29 落地：一個 protocol（D81）

**D81（Claude 代裁）：自帶消毒的錯誤型別由 protocol 宣告，Error → 文字只有一個入口，而那個入口住在 AkashicCore。** R28 把邊界寫成 StoreIO 裡的一條
`is` 鏈，於是相依方向反過來的 `ServiceError`、住在別的模組的 `IndexError`／`QueryError`／`GraphError`／App 的三個錯誤、`TractatusDocs` 的
`CorpusSchemaError`、`AkashicProposition` 的兩個錯誤全在鏈外，而守衛只掃兩個目錄。現在：

- **`SanitizedErrorDescription`**（AkashicCore）——19 個型別 conform（StoreYAMLError／StoreIOError／DivergenceResolveError／StoreMigration 與
  PersonIdentityMigration 的 MigrationError／StoreIncarnationError／ConfigError／VenueMigration 與 VenueVariantMigration 的 MigrationError（`description`）／
  ServiceError／IndexError／QueryError／GraphError／AppStateError／AdjudicationError／FileWatcherError／CorpusSchemaError／PropositionError／
  PropositionModelValidationError），描述裡的列舉式 `displaySafe(` 全部換成性質式；`ErrorDisplay` 搬進 AkashicCore、`isSelfSanitizing` 只問 protocol。
  守衛掃**全樹**（宣告可跨行、只看 Error 型別）：描述裡有逃脫的必須 conform，conform 而描述不逃脫的只有 `ServiceError`（封閉表：消毒在 140 個擲出站點）。
- **三個入口收攏**：MCP 的 per-tool 出口與 `Main.swift` 改 `displaySafeErrorMultiline`（自帶消毒 → `displaySafeAssembled` 只截、合法反斜線原樣；
  其餘 → 逐行逃一次並以性質逃脫不可見 scalar）；App 六個 `errorMessage`／`loadError`、`AppState.renameIndexRebuildFailed` 的 underlying；CLI 五個
  `ValidationError((error as? LocalizedError)?.errorDescription ?? …)` 包裝；`ZoteroImporter`／`EnrichFromZotero` 的 writeFailed、`PersonIdentityMigration` ×4、
  `ProvenanceMigration` ×2（Foundation `NSError` 取 `localizedDescription` 的分流搬進 `ErrorDisplay.describe`）、`StoreIncarnation`、YAML 的 encode 自檢、
  `resolve-divergence` 的六個 `report.failures` 生產端。守衛 `testErrorToTextEntriesGoThroughTheSingleEntryPoint` 掃全樹（`TractatusDocs`／`tractatus-doc`／
  `AkashicProposition` 的 corpus 管線不在範圍，寫在測試裡）。Server.swift 那段自 #162 起「約 90 個站點刻意不消毒、靠 sink 兜底」的註解改寫。
- **`ServiceError` 與 `ValidationError` 納入擲出站點守衛**：140 個 `displaySafe(` 換成 `displaySafeInvisible(`，`\(key)`／`\(title)`／`\(path)`／
  `\(existing)`／`\(known)`／`config.files[key]!`／`missing.joined` 包起來；守衛多一層**裸引數**檢查（頂層引數不是字面、不是消毒、不是程式構造值即紅——
  `LibraryStore` 的 `what: relativePath` ×2、`YAML.swift:1605` 的 `typeField: t` 由它抓出來），並從描述現算「描述端自己逃脫的 case」
  （`unknownShapeLabel`／`shapeLabelHasValue`／`ambiguousShapeLabels`／`shapeLabelContradiction`：擲出端傳原值，守衛反向要求不得再逃）；
  掃描前剝行註解、needle 後必須緊接 `(`（第 47 列）。`programBuilt` 多了 R29 的列，每列有理由。
- **截點退讓搬回 `displaySafeClipOnly`**，且只認**半截逃脫序列**（`\`、`\u`、`\u{`、`\u{` 後至多**六**個十六進位——`escapingInvisibleScalars` 的 `%04X` 對 BMP 以外的 scalar 印五位，`\u{E0001` 是合法殘端；R29 第一版寫四個，在寫 verify 的 DA 提示時自己抓到、`f85ea94e` 之後補一個 commit）——`\A`／`\z` 這種真反斜線常量不動；
  `displaySafeAssembled` 完全不受影響（測試釘住一行 406 scalar 留到上限）。
- **clip-only sink 的上限是輸出 scalar**（第 23 列）：人的終端與 App 的 sink 放大 8 倍（`invalidInput` 描述 960／3,200、CLI quarantine reason 4,096…）；
  **MCP 的 sink 刻意不放大**——它的上限保護的是 LLM context 的位元組預算（#236／#388），48 KB 裝不下 20 則 × 2,400 scalar。這是一個有記錄的不對稱。
- 其餘：thesis 分支傳原值（return 時整批逃）、`describe(d)`／`judgementWarnings`／authorized demotion 的片段改性質式、`DivergenceCommands` 的 failures sink
  只截；`namesReport` 先問「有沒有存進去」再問「同批已見」（全空白項報 dropped）；`wouldLeaveTwoConfirmedLiterals` 的出路句在截斷時說「標『…共 N 筆』時
  其餘幾筆要開 YAML 找」；`YAML.swift:1777` 的 contacts key 進 context 前消毒、:1865／1885 的 exempt 註解改寫；D76 的 doc 與測試改成只宣稱排序
  （升冪之下「不鎖存」不可觀測，第 26／42 列；「列出最小的 20 組」的代價寫進 doc，第 49 列；venue 側沿插入序＋鎖存的理由寫在 `Venue.validate()`，
  第 43／45 列）；§5.7「本節的各條」；`ci.yml` 補 `permissions: contents: read` 與 `persist-credentials: false`；`fieldsLostByMerging` 的 doc 改說
  return 時逃（第 44 列）。#583 的範圍在 issue 上更正：不只 `ServiceError`，是 MCP 出口對全部自帶消毒型別再逃一次；R29 關掉程式側，issue 留著記
  「輸出閘的列舉式逃脫」那一半（#569 的範圍）。

**誠實邊界**：`YAML.swift:1777` 那條路的守衛看不到——context 在 `decodeTimeline(…, context:)` 的引數裡組成、不在 throw 語句內，`^context$` 的
允許清單仍放行它，修的是站點本身、不是守衛；`TractatusDocs`／`AkashicProposition` 的 Error → 文字入口不在守衛範圍（範圍寫在測試裡，理由是它們不碰
store 字串）；`escapeAtThrow` 封閉表裡的 `ServiceError` 描述原樣回傳 what／why，「140 個站點全部消毒」由 `testServiceErrorAndValidationErrorThrowSitesSanitizeStoreStrings`
釘住，但那個守衛認得的「程式構造值」是一張正則表——第 39 列說它是性質式而非封閉列舉，這一輪沒改（每列仍有理由；改成逐站點列舉會讓表與 140 個站點分岔）。
