# 2026-10-19 #709 b40 verify 之後：enrich 的拷貝那一句只說刪掉拷貝之後就能定位的、理由結論在前且回顯截短，validate 對同 citekey 的重複不指 record-divergence，bootstrap 乾跑結尾說出沒列出的筆數

#709 的 b40 verify（Z4，驗 `8f164bba`；21 則 finding，0 起算；六席：requirements、logic、security、regression、devil's advocate、Codex）。本檔逐則寫處置，沒做的寫理由。
量測於 2026-10-19（+08:00）。`### Blocking` 裡兩項「使用者裁決」（第 3 類無法唯一定位是否也擋、venue／organization 的重複 key 要不要納入）本輪不動。

## MEDIUM 0、LOW 4：拷貝那一句把「刪掉拷貝之後仍無法定位」的 citekey 也算成說明過了

`ambiguousDOIReason` 判斷哪些 citekey 已由拷貝那一句說明，只看命中的記錄（b38 的 `duplicatedInRecords`）。同一個 citekey 另有一筆**不帶這個 DOI**、id 不同的記錄時，
那個 citekey 在完整的 load 上無法唯一定位，命中裡卻看不出來，理由只說「確認 entities/ 那份是新的之後刪掉 legacy 那份（akashic validate 列出），再跑」。
logic 席以真 binary 重現兩種形狀：(a) entities/ 的 r1（不帶 DOI）＋它的 legacy 拷貝（帶）＋entities/ 另一筆 id 不同的 r2（帶）；(b) 拷貝那一對都帶 DOI＋
entities/ 另一筆 id 不同、不帶 DOI 的 r9。照做刪掉拷貝之後，validate 仍報 citekey 重複，重跑被「無法唯一定位……先修好」擋下。

修法：判準改成**刪掉 load 標出的拷貝之後**仍不能唯一定位的 citekey，在完整的 load 上算——`Collection<Entry>.unlocatableCitekeysAfterDeletingShadowedCopies`
（`DuplicateCitekeys.swift`，定義仍是 `unlocatableCitekeys`，算在拿掉拷貝之後的集合上）。多一步：拷貝的孿生（entities/ 那份）在完整的 load 上自己也帶第 3 類的理由，
因為 load 判第 3 類時讀的 `entries/<它的 citekey>.yaml` 正是那份拷貝；刪掉拷貝之後它就不在，所以同 id、同 citekey 的拷貝存在時不算它的理由。改名留下的拷貝
citekey 不同、不擋孿生自己的檔；同一個位置上被隔離的 legacy 檔不是拷貝，它造成的理由照算。拷貝或孿生的 citekey 在這個集合裡時，不算已由拷貝那一句說明：
理由說「命中裡有 N 個 citekey 無法唯一定位……先修好」，拷貝那一句照樣說、不接「，再跑」。命中裡的重複（b38）是這個判準的特例，那一步併掉了；共用 id 那一句的
「除非命中裡另有一筆 id 不同的記錄」保留。

`plan` 只在 DOI 命中兩筆以上時算這個集合（`lazy var`）；沒有拷貝時它就是 `unlocatableCitekeys`。

測試（`EnrichReasonExplanationTests`）：`testACopyDoesNotExplainACitekeyThatStaysUnlocatableOnceTheCopyIsDeleted`（兩種形狀；照做刪掉拷貝之後重跑仍被擋，那是舊的「再跑」的後果）、
`testAPlainCopyPairStillEndsWithRerun`（對照組：只有那一對，照舊以「再跑」收尾；刪掉拷貝之後寫得進去）。修正前前者紅、後者綠。負控兩個：拿掉
`.subtracting(unlocatableAfterDeletingCopies)`，前者與下一節的第一個形狀紅（9 則失敗）；拿掉孿生理由的清除，對照組紅（4 則失敗）。皆以反向編輯還原。

同判斷的其他路徑（逐一看過）：
- `LibraryLoad.planBlockers`（三個 bootstrap）：逐筆以 id 判，一對拷貝的兩份不重列、同 citekey 的第三筆照列（`for e in entries where … !pairIDs.contains`），兩種形狀都列得出
  r2／r9——不必改。它對「孿生的理由來自被隔離的同名 legacy 檔」那一格不另列，但拷貝在、`--apply` 照樣整批拒絕，刪掉拷貝之後下一次乾跑會列出來。
- `withoutShadowedLegacyCopies`：只決定要不要替孿生補一句理由（寫入面的封鎖），不產生「再跑」的指示。
- 只命中一筆的那一支：問的是完整的 `unlocatable`，本來就說先修好。
- `ZoteroEnrichment`：以 citekey 定位、不經 DOI。CLI `enrich` 與 MCP `akashic_enrich` 印同一份 service payload。

## LOW 3：先前沒有測試的分支

- 明細至多列 5 個、其餘「…另 N 個」：`testTheUnlocatableDetailListsFiveAndSummarisesTheRest`（6 個 citekey 各兩筆）。負控：上限改 6，紅（2 則失敗）。
- 拷貝那一對的 citekey 在拷貝以外的命中裡也重複，以及共用 id 的一組裡有一個 citekey 另有一筆 id 不同的記錄：`testACitekeyWithAnotherProblemBesidesItsCopyOrSharedIDIsStillListed`。
  負控：拿掉上一節的判準，第一個形狀紅；拿掉共用 id 那一句的「扣掉命中的重複」，第二個形狀紅（1 則失敗）。
- 第 3 類（只有一份、寫入時會被拒的 legacy 殘留）在多筆命中裡排在 #459 之前：`testACategoryThreeLeftoverAmongSeveralHitsIsFixedBeforeTheTwinPipeline`（前提斷言它在
  validate 只是 warning）。負控：把 #459 那一句挪到最前，這支與 b39 的 `testEnrichSendsASameCitekeyDuplicateToValidateNotTheTwinPipeline` 紅（4 則失敗）。

這三支在修正之前就綠——它們釘的是既有的行為，負控證明它們會紅。

## LOW 6、7、10、11（與 LOW 2 的前半同一件事）：結論在前、回顯截短

`notFound` 的「「rawDOI」不是合法的 DOI 形狀（…）」與「citekey「…」不在 store 裡」把呼叫端的原字串放在結論之前、不截，原字串約 510 個 scalar 以上時，出口
`displaySafe(max: 512)` 截掉的是結論（regression 與 devil's advocate 以 5,000 個字元與誤貼進 doi 的 1,620 字元摘要實測；security 席另指出這是一條約 490 scalar 的回顯通道）。
修法：回顯一律經 `AddOnlyEnrichment.echo`（以 Unicode scalar 截到 `reasonEchoScalarLimit`＝100、接「…」；常數由 `reasonDOIScalarLimit` 改名，歧義那一支的截短改用它），
句子改成結論在前：「citekey 不在 store 裡：「…」」「不是合法的 DOI 形狀（10.<註冊者>/<後綴>）：「…」」。

同一份計畫裡把未信任字串放在前面的其他句子一起改（逐一看過 `plan`、`policy`、`validate`）：
- 「沒有記錄帶 DOI「…」」：結論本來就在前，DOI 一樣截短。
- 只命中一筆而無法唯一定位：「citekey 無法唯一定位（…）——零寫入；先修好（#628／#641）：「…」」（store 的 citekey 長度沒有上限，手改的 YAML 寫得出 300 個字元的 key；`matches` 照舊是完整的 citekey）。
- `refused`：「issn：ISSN 識別的是期刊不是文章，work 不收；要補請補到它的 venue——「…」」、「pmid：解析不出 PMID 的形狀，不猜——「…」」；`partial`：「isbn：只解析出 N 個，……——「…」」
  （出口 `displaySafe(max: 300)`）。`ZoteroEnrichment` 共用這一份政策，CLI `enrich-from-zotero` 的拒絕明細同樣改了。
- 空值的附註：「值為空，略過：「欄位鍵」」。
- 兩個欄位名的整批拒絕：「欄位名無法表達成合法的 biblatex 欄位鍵：「…」」、「欄位名正規化後與另一個欄位相撞：「…」（正規化為 …）」；超長欄位值的拒絕訊息裡的欄位名截短。

`citekey`、`DOI` 與鍵的**內容**沒有改，只改句子的順序與回顯長度；消毒仍在出口端一次。

測試：`testNotFoundReasonsLeadWithTheConclusionAndClipTheEcho`（四種呼叫端字串，core 與 service 出口兩處）、`testTheSingleHitUnlocatableReasonLeadsWithTheConclusion`、
`testTheOtherSentencesOfThePlanLeadWithTheConclusion`。修正前三支都紅（例：不合法的 DOI 的理由長 5,039 個 scalar，出口之後只剩回顯）。負控：`echo` 改成不截，這三支與
b39 的組合符號 DOI 那一支紅（26 則失敗）。

## LOW 1、8：validate 的「DOI 被 N 筆 work 共用」對同 citekey 的重複仍指 record-divergence

b38 修掉 enrich 理由裡的「訊息叫人做的事，程式隨即拒絕」，而 enrich 的新理由指去的下一站 validate 對同一組又說「可用 record-divergence 記下未決的同一性」；照做，
`record-divergence --candidate j2020alpha:work --candidate j2020alpha:work` 被拒（「重複的候選不構成歧異」）。b39 的「同判斷的其他路徑」沒有列它。

修法（`LibraryStore.crossRecordIssues`）：組裡有重複的 citekey 時，說「其中 citekey「…」不只一筆記錄（validate 另以 error 報 citekey 重複）——record-divergence
不收同一個 citekey 的兩個候選、以 citekey 定位的寫入面也拒絕它，先修好那個重複」；組裡還有別的 citekey 時，接「修好之後其餘的……」。同一份輸出裡指向
record-divergence 的另兩則同形，一起改：「標題與年份相同但 DOI 不同」（它的「處置同上」就是 record-divergence）、「Zotero 來源被 N 筆 entry 宣稱」（另說
`update-entry --remove-zotero-source` 也以 citekey 定位）。三則共用 `repeatedCitekeysNote`。拷貝不在這三則的名單裡（前兩則跳過拷貝，Zotero 那則以 id 去重），
所以名單裡的重複都是兩筆不同的記錄；沒有重複的組，訊息逐字不變。

測試（真 binary，`CrossRecordDuplicateCitekeyCLITests`）：三則各一支（DOI 那一支先以真 binary 確認 record-divergence 拒收、validate 報 citekey 重複的 error，再加一筆不同 citekey
的記錄看先修好在前），加一支對照組（citekey 不同的三則照舊指向 record-divergence）。負控：`repeatedCitekeysNote` 恆回 nil（回到修正前），三支紅（8 則失敗）。

## LOW 9、INFO 18：乾跑結尾在附註列不完時

devil's advocate 更正 regression 席：附註被截時有「…另 N」，說「不誠實」言過其實；真正的缺口是使用者最後讀到的那一行沒提 validate，處理完列出的 20 筆之後
`--apply` 仍被拒。修法照較窄的讀法：附註任一類超過 20 筆時，結尾說「先處理開頭附註列的那幾筆，以及附註沒列出的另 N 份 legacy 拷貝、另 M 筆無法唯一定位的記錄
（akashic validate 逐筆列出），再加 --apply」；沒有被截時逐字不變。`BootstrapPlanBlockers.dryRunApplyRefused` 由常數改成依計畫算，上限與附註同一個
`noteListLimit`（20）。測試：`BootstrapPlanBlockersCLITests` 的兩支（22 份拷貝、22 筆無法唯一定位）斷言結尾；期望值以字面寫在測試裡。負控：恆走未截的那一句，兩支紅。

## LOW 5、INFO 12：排序理由對第 3 類不成立

`ambiguousDOIReason` 的 doc 以「前兩類都是 validate 的跨記錄 error，合併在修好之前也被 `assertNoCrossRecordErrors` 擋」說明先修好排在 #459 之前，而第 1 類含
第 3 類，它在 validate 是 warning。改寫成：citekey 重複與 UUID 重複是 error、由 `assertNoCrossRecordErrors` 擋；第 3 類是 warning、擋它的是寫入當下的 #631 前置
（load 用同一組判斷，那筆記錄的檔寫不進去）。順序不變；第 3 類要不要讓 bootstrap 的 `--apply` 也擋，是 `### Blocking` 裡待使用者裁決的一項，doc 也寫明。
上一節的第 3 類排序測試把順序釘住。

## INFO 13、16：tools/list 的量測數字

b39 的 changelog 與 `plugin/CHANGELOG.md` 的 #709 段寫 59,173 → 59,173；那是整合之前 P4 分支上的量測。base（`04131a49`）本輪以真 binary 重量為 59,171 bytes
（差的 2 bytes 是同一批 #564 修正輪五的 −2），兩處加劃線與更正。`plugin/CHANGELOG.md` 同一批的 #692／#700 與 #613 b39 兩段也寫 59,173，那不是 #709 的段落，本輪不動，留給整合。

## 留給主 session（本輪不開 issue）

- LOW 2、INFO 14：b36 第 26 則（`library add` 對依據不明確的既有成員附「用 library remove 移除」）仍沒有 issue 編號、也不在 `### Blocking`。LOW 2 的另一半（過長的不合法
  DOI 理由）本輪已修，不必另開。
- INFO 15、20：issue body 的 Current Status（Last updated 的日期、Commits 清單少了整合 commit）——那是 issue 上的寫入，不在這個分支。

## 仍待使用者裁決（本輪不動）

- 「無法唯一定位」的第 3 類是否也讓 bootstrap 的 `--apply` 拒絕（`### Blocking` 第 1 項）。
- venue／organization 的重複 key（#669）要不要納入 bootstrap 的拒絕條件（`### Blocking` 第 2 項）。

## INFO（不動）

- 17、19：`ambiguousDOIReason` 的 `unlocatable` 與 `hits` 的隱含契約——devil's advocate 窮舉後沒有可達的違反路徑；本輪多一個參數，唯一呼叫端仍是 `plan`，兩個集合都由
  同一份 `entries` 算。

## 面

- MCP：`akashic_enrich` 的 `reason`、`refused`、`partial` 文字與拒絕訊息；`akashic_doctor` 的三則跨記錄 warning。鍵、類別與 `matches` 不變；`tools/list` 沒有改（Server.swift 未動）。
- CLI：`enrich`、`enrich-from-zotero`（拒絕明細）、`validate`／`doctor`（同一份 `crossRecordIssues`）、三個 bootstrap 的乾跑結尾。
- App：健康總覽讀同一份 `crossRecordIssues`，那三則的文字跟著改；沒有其他改動。

## 驗證

- live store 唯讀：`entries/` 與 `people/` 各 0 個檔——本輪改的拷貝那一格今天沒有實例。
- 全套測試（`swift test --build-system native`，分離執行）：5,258 個測試、1 個 skip、0 個失敗。
- `swift build -Xswiftc -warnings-as-errors` 與 `--build-tests`：乾淨。
- 守衛 `.githooks/run-guards.sh`：rc=0（18 支需要負控的全部都有、無缺口）。
- `tools/list`（真 binary）：59,171 → 59,171 bytes（±0；base `04131a49` 本輪重量）。
- 負控 8 個（上面各節），每個都以反向編輯還原、還原後檔案的雜湊與還原前相同。
