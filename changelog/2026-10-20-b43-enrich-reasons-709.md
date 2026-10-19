# 2026-10-20 #709 b42 verify 之後：enrich 的拷貝那一句點名同 id 的每一份拷貝、判準與處置算在同一個集合上，validate 的重複 citekey 結論在前、名單有上限，citekey／person key 重複的 error 帶處置

#709 的 b42 verify（Z4，驗 `7f1962c8`；19 則 finding，0 起算：MEDIUM 1、LOW 10、INFO 8；六席：requirements、logic、security、regression、devil's advocate、Codex）。
本檔逐則寫處置，沒做的寫理由。量測於 2026-10-20（+08:00）。`### Blocking` 裡兩項「使用者裁決」（第 3 類無法唯一定位是否也擋、venue／organization 的重複 key
要不要納入）本輪不動。

## MEDIUM 0、LOW 4：判準在「刪掉全部拷貝」的集合上算，處置只叫人刪命中的那幾份

b41 讓拷貝那一句只替「刪掉拷貝之後就能唯一定位」的 citekey 說「再跑」，判準是 `unlocatableCitekeysAfterDeletingShadowedCopies`——它拿掉 load 裡的**全部**拷貝
再算。理由卻只叫人刪**命中裡**的拷貝，明細也只列它們。同一個 id 另有一份不帶這個 DOI 的拷貝時（E:x:A 帶 DOI、legacy x:A 帶、legacy y:A 不帶），判準說刪掉之後
能定位、理由以「，再跑」收尾；照做刪掉 `entries/x.yaml` 之後，y 仍與 x 共用 id A，重跑被「citekey 無法唯一定位……先修好」擋下（devil's advocate 以真 binary
重現；logic 席另以孿生改名的形狀 E:z:A、legacy x:A、legacy y:A 重現）。這是 b40 MEDIUM 0 的同一種失敗——訊息叫人做的事，做完仍被擋。

修法：叫人刪的拷貝與判準算在**同一個集合**上。

- 集合＝命中裡的拷貝，加上 store 裡與命中任一筆**同 id**、卻不帶這個 DOI 的拷貝（validate 的「UUID 被 N 筆 entry 共用」那一則同樣列出它們）。
- 判準改成 `Collection<Entry>.unlocatableCitekeys(afterDeletingCopiesAt:)`：只拿掉呼叫端傳進來的那幾份（以 legacy 檔路徑指認）再算，其餘照
  `unlocatableCitekeys`；被刪的拷貝與孿生同 id、同 citekey 時，孿生的第 3 類理由不算（理由同前）。舊的 `unlocatableCitekeysAfterDeletingShadowedCopies`
  刪除——它唯一的呼叫端就是這裡。
- 拷貝那一句說出另外幾份：「命中裡有 1 份是同一筆記錄的 legacy 拷貝、同 id 另有 1 份不帶這個 DOI：確認 entities/ 那份是新的之後刪掉 legacy 那份（共 2 份，akashic
  validate 列出），再跑」；明細逐份列出同一個集合，不帶 DOI 的那幾份標「這份不帶這個 DOI」。命中裡沒有拷貝、但命中的記錄另有同 id 的拷貝時（改名留下的），說
  「命中的記錄另有 N 份同 id 的 legacy 拷貝（不帶這個 DOI）」——先前只說「無法唯一定位，先修好」，要去 validate 才知道那是一份拷貝。
- 「再跑」只在拷貝是唯一一類時說，而那時前三類的判準保證刪掉這個集合之後命中的記錄恰好剩一筆、能唯一定位（`ambiguousDOIReason` 的 doc 第 4 點寫出推導）。

同 citekey 而 id 不同的拷貝（另一筆記錄改名留下、檔名正好是這個 citekey）不在集合裡：它不是命中那幾筆記錄的拷貝，它讓 citekey 重複，那一筆照第 1 類說先修好；
validate 的 citekey 重複那則本輪起會指出它是 legacy 拷貝（LOW 3）。這樣判準仍只算在集合上，說不出「再跑」。

測試（`EnrichReasonExplanationTests`）：
- `testTheCopyInstructionNamesEverySameIDCopySoTheRerunHolds`：finding 的兩種形狀（孿生沒改名、改名）。斷言理由點名兩份，然後**照著理由做**——讀出理由裡的
  「legacy 檔 …」、逐一刪掉、重跑——結果是 `added`。
- `testDeletingOnlyTheHitCopyLeavesTheTwinUnlocatable`：只刪命中那一份時判準說 x、y 仍無法唯一定位，重跑被擋（修正前的「再跑」的後果）。
- `testAnUnrelatedCopyElsewhereIsNotNamed`（對照組）：store 裡另有一對 id、citekey 都不同的拷貝，不點名、不算進「共 N 份」。
- `testASameIDCopyOfAHitRecordIsNamedEvenWhenNoHitIsACopy`、`testWhenEveryHitIsACopyTheReasonSaysTheDOIWillMatchNothing`（INFO 13，見下）。
- 真 binary：`EnrichCLITests.testTheCopyReasonNamesEverySameIDCopyThroughTheBinary`（同一個形狀走 `enrich --from … --json`，照著刪、重跑得 `added`）。

負控：同 id 的拷貝不收（集合只剩命中裡的）且判準改回全部拷貝——即修正前的行為——`EnrichReasonExplanationTests` 11 則失敗，其中
`testTheCopyInstructionNamesEverySameIDCopySoTheRerunHolds` 的「照著理由刪掉之後重跑」得 `ambiguous`、不是 `added`，正是 finding 重現的那一步。以反向編輯還原，
還原後 13 支全綠。

同判斷的其他路徑（逐一看過）：
- `AddOnlyEnrichment.plan` 只命中一筆的那一支：問完整的 `unlocatable`，本來就說先修好，不說「再跑」。
- `LibraryLoad.planBlockers`（三個 bootstrap）：乾跑逐份列出**全部**拷貝與全部無法唯一定位的記錄，「再跑」的前提是全部處理掉——判準與處置本來就是同一個集合。
- `ZoteroEnrichment`：以 citekey 定位、不經 DOI。CLI `enrich` 與 MCP `akashic_enrich` 印同一份 service payload（`AkashicService.enrich`）。
- `create-entry`／`akashic_create_entry` 的 `doiHits`：只回報、不叫人刪檔。

## LOW 10：拷貝明細以 citekey 指認 entities/ 那份

孿生在命中裡時，明細印「entities/ 那份是 x2020same」——而 citekey 重複的 store（這個函式要處理的情形之一，b40 的形狀 b）裡 entities/ 有兩筆 x2020same，指不出是哪一個檔。
改成一律以檔名指認：「entities/ 那份是 entities/<id>.yaml」；拷貝的 citekey 與 entities/ 那份不同（改名留下的）時另寫「、citekey <新的>」。測試：b40 形狀 b 的那一支
（`testACopyDoesNotExplainACitekeyThatStaysUnlocatableOnceTheCopyIsDeleted`）多斷言檔名，`ShadowedPairReadersTests` 三支改成檔名。

## INFO 13：命中全是拷貝時的「再跑」

E:x:A 不帶、legacy x:A 帶、E:y:B 不帶、legacy y:B 帶：先前以「，再跑」收尾，照做之後重跑得 notFound。現在說「entities/ 那份都不帶這個 DOI，刪掉之後它對不到任何記錄」、
不說「再跑」；doc 第 4 點的「保證」改寫成實際成立的那一句。測試：`testWhenEveryHitIsACopyTheReasonSaysTheDOIWillMatchNothing`（照做之後重跑得 `notFound`）。

## LOW 3：citekey 重複的 error 沒有處置

enrich、validate 的另外三則、rename 都說「先修好」，而 `citekey「…」重複` 這則 error 沒有處置——一圈指回來（requirements 席；devil's advocate 確認實際只能手改 YAML）。
同一個函式裡 venue key 那則早就寫了，照它寫：「——以 citekey 定位的讀取與寫入分不出是哪一筆；先在 YAML 改掉其中一筆的 citekey（legacy 檔的檔名要一起改；這個 error 在時
rename 與合併都會先停下），若兩筆其實是同一筆，改完之後再以 record-divergence／resolve-divergence 合併」。rename 的拒絕訊息帶這則 error 的前 300 個字元，處置因此
也到了那裡（先前那裡只剩「先跑 akashic doctor 看清楚並修好」）。

組裡有一份是 load 標出的 legacy 拷貝（另一筆記錄改名留下、檔名正好是這個 citekey）時，那一份要刪、不是改名：「其中 entries/x.yaml（entities/ 那份是 entities/<id>.yaml）
是 legacy 拷貝：確認 entities/ 那份是新的之後刪掉 legacy 那份」；拷貝以外只有一筆記錄時不叫人改名。`person key「…」重複` 是同一個缺口，同一個函式一起改
（`rename-person`）。`library key` 重複那則不動：它是 registry 檔的 key，不在這張 issue 的範圍。

測試：`CrossRecordDuplicateCitekeyCLITests.testTheCitekeyDuplicateErrorSaysHowToFixIt`（真 binary；rename 被擋、訊息帶處置）、`testTheCitekeyDuplicateErrorNamesALegacyCopyInTheGroup`；
`IndexPrefersEntitiesCopyTests` 的 person 那一支多斷言拷貝的處置（兩支原本以 `==` 比對整則訊息，改成前綴）。

## LOW 5、6、9、15（INFO 12 的前半）：「先修好那個重複」在不設上限的名單之後

三則跨記錄 warning（DOI 被 N 筆 work 共用、標題與年份相同而 DOI 不同、Zotero 來源被多筆 entry 宣稱）在組裡有重複的 citekey 時，b41 的「先修好那個重複」接在
不設上限的 citekey 名單之後；`repeatedCitekeysNote` 自己也逐項列出全部重複的 citekey。MCP `akashic_doctor` 對每則截 300 個 scalar：8 筆共用一個 DOI（logic 席，373 個
scalar、結論在第 315 個）、或 120 字元的標題（335 個 scalar）就截掉結論；Zotero 那則本來把名單截在 10 個，這一句繞過了它——security 席以 1,500 個重複的 citekey
量到一行 257,413 個字元。

修法（`LibraryStore.crossRecordIssues`）：
- 有重複的組**結論在前**：「DOI「…」被 N 筆 work 共用——先修好那個重複：其中 citekey「…」不只一筆記錄（validate 另以 error 報 citekey 重複；record-divergence 不收……）
  ；修好之後其餘的……（名單）」，標題那則把名單與標題放在最後，Zotero 那則把「再匯入分不出……」放在處置之後、名單放在最後。
- 重複的 citekey 至多列 5 個、其餘「…共 N 個」；組的名單至多 10 個、其餘「…共 N 筆」（Zotero 那則的既有上限，三則共用 `shownNames`）。名單上限對沒有重複的組也生效——
  live store 共用 DOI 的組全部是 2 筆、標題與年份相同的組最大 3 筆，看不到差別（量法見〈驗證〉）。
- 沒有重複的組，除了名單上限，訊息逐字不變。

測試（真 binary）：`testRepeatedCitekeyGroupsAreBoundedAndLeadWithTheConclusion`（7 個重複的長 citekey、14 筆 work 共用一個 DOI 與一個 Zotero 來源；斷言「…共 7 個」「…共 14 筆」、
第 6、7 個不列、一行不到 1,200 個 scalar、截到 300 個 scalar 之後結論仍在）；三則既有測試改成斷言結論在前、名單在尾。

## INFO 16、INFO 12 的後半：混合組指向不存在的那一則

標題與年份相同的組裡有重複的 citekey、又有別的 citekey 時，尾巴寫「修好之後其餘的留給編目判斷（同 DOI 共用那一則，可用 record-divergence 記下）」，而這一組的 DOI
彼此不同，那一則不一定存在。改成直接說處置：「修好之後其餘的要不要視為同一筆是編目判斷，可用 record-divergence 記下未決的同一性」。測試：標題那一支的混合組
（斷言輸出裡沒有「筆 work 共用」那一則）。沒有重複的組的「處置同上，留給編目判斷」也是同一種懸空指向（INFO 16 說舊文字就有），本輪不動：它不在重複 citekey 這一族，
改它會動到 live store 約 46 則 warning 的文字（量法見〈驗證〉），留給下一輪或另開。

## LOW 8：plugin/CHANGELOG.md 的「plugin 版號沒有動」

b41 那一段寫「plugin 版號沒有動（行為在 binary）」，旁邊兩段寫殼隨同一批升到 0.13.5，讀起來互相矛盾。finding 的前提有一半不成立：`plugin/CHANGELOG.md` **不在**殼的
內容摘要裡（`akashic-guards plugin-shell-version` 算摘要時排除根的 `CHANGELOG.md`），所以 b41 那一段改的只是版本史、沒有改出貨的內容。那句改成與 #700／#692 段同形，
並寫明這一點。

本輪要寫 `plugin/CHANGELOG.md`（MCP 面的訊息改了），照主 session 的規則把殼升到 0.13.6（`plugin/.claude-plugin/plugin.json`、`.githooks/plugin-shell-versions.txt`
接一列）。因為本檔不在摘要裡，0.13.6 那一列的摘要與 0.13.5 相同（守衛印出的就是這一列）；同一批若別的分支改了殼的內容，整合時重記。

## INFO 11：doc 與 changelog 把第 3 類寫成今天不擋

`ambiguousDOIReason` 的 doc 與 b41 changelog 寫「第 3 類該不該讓 bootstrap 的 `--apply` 也擋，是待使用者裁決的一項」，讀起來像今天不擋；實際上 `--apply` 今天就拒絕
（`testASingleUncommittedLegacyFileAlsoBlocks` 釘住）。doc 改成「今天照樣拒絕；維持這樣、還是只在計數真的加倍時才拒，是待使用者裁決的一項」；b41 changelog 那一行加劃線與更正。

## 不動的（理由）

- LOW 1（Codex）：兩類附註同時超過 20 筆的乾跑沒有測試。Codex 判定實作正確、只是測試深度；兩類各自超限的情形都有測試，結尾的組字是同一個函式（`dryRunApplyRefused`）
  的兩個分支，本輪不加。
- LOW 2：b36 第 26 則（`library add` 對依據不明確的既有成員附「用 library remove 移除」）仍沒有 issue 編號或 Blocking 項——那是 issue 上的寫入，留給主 session。
- LOW 7、INFO 14、18：回顯上限 300 → 100 的取捨。devil's advocate 以真 binary 量過，結論都在前、`partial` 的原字串在 CLI additions 行完整可見、`refused` 的值是識別碼；
  b41 刻意的產品取捨，記在這裡，不改。
- INFO 17：issue body 的 Commits 清單少整合 commit——issue 上的寫入，留給主 session。

## 仍待使用者裁決（本輪不動）

- 「無法唯一定位」的第 3 類：維持 bootstrap `--apply` 照樣拒絕，還是只在計數真的加倍時才拒（`### Blocking` 第 1 項）。
- venue／organization 的重複 key（#669）要不要納入 bootstrap 的拒絕條件（`### Blocking` 第 2 項）。

## 面

- MCP：`akashic_enrich` 的 `reason`（DOI 命中兩筆以上而有拷貝時）；`akashic_doctor` 的三則跨記錄 warning 與 citekey／person key 重複的 error。鍵、類別、`matches` 不變；
  `tools/list` 沒有改（Server.swift 未動）。
- CLI：`enrich`、`validate`／`doctor`（同一份 `crossRecordIssues`），`rename`／`rename-person`／`resolve-divergence` 的拒絕訊息（帶前 3 則 error 的前 300 個字元）。
- App：健康總覽讀同一份 `crossRecordIssues`，文字跟著改；沒有其他改動。

## 驗證

- live store 唯讀（2026-10-20，YAML 解析、讀不到的檔 0 個）：`entries/` 與 `people/` 各 0 個檔——拷貝那一格今天沒有實例。work 2,872 筆；被 ≥2 筆共用的 DOI 16 個、
  全部恰好 2 筆；標題與年份相同、未被 DOI 那則涵蓋的組 46 組、最大 3 筆（Python 鏡射 `titleKey`，與 Swift 的空白切法可能差幾組）——名單上限今天看不到差別。
- 理由前段的長度（以 scalar 計，四類全在、DOI 截到 100）：拷貝那一句帶同 id 的另外幾份時 465（筆數都到四位數時 489），不帶時 439／457；出口 512。
- 全套測試（`swift test --build-system native`，分離執行）：5,292 個測試、1 個 skip、0 個失敗。
- `swift build -Xswiftc -warnings-as-errors` 與 `--build-tests`：乾淨。
- 守衛 `.githooks/run-guards.sh`：rc=0（19 支需要負控的全部都有、無缺口；`plugin-shell-version`：plugin 0.13.6，main 0.13.5）。
- `tools/list`（真 binary）：59,159 → 59,159 bytes（±0；base `7ba4d695` 本輪重量）。
- 負控 1 個（MEDIUM 0，見上），以反向編輯還原，還原後全綠。
