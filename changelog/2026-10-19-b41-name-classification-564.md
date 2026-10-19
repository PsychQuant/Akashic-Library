# 2026-10-19 名字分類修正輪六：帶時間的名字的合併出口、update-person 乾跑的整條前置、organization 刪名字報告的位元組預算（#564）

`changelog/2026-10-15-b39-name-classification-564.md`（修正輪五）之後的 verify（b40 Z1，六席：requirements、logic、security、regression、devil's advocate、Codex）找到 1 個 MEDIUM、11 個 LOW、12 個 INFO。依 findings 檔的 0 起算列號引用。量測於 2026-10-19（+08:00）。這一輪沒有新的使用者裁決；待裁的項目沒有動它們問的行為（見文末）。

## MEDIUM

### 名字段帶時間時，variant 出口照做到第二步才被拒、第一步已寫入（第 0 列，Codex）

Codex 席靜態讀出、沒有重現；這一輪先以真 binary 在 scratch store 重現：倖存者 `kv` 與被併者 `dv` 都有「Alpha J」（對外形，名字段 `start: '1990'`），`dv` 另有一筆手改的 `field: variant`「指定：手改」。`resolve-divergence --dry-run` 拒絕，出口是「在被併者上 --unauthorize 它、--add-variant 它、再 --authorize 它」。照做：`update-venue dv --unauthorize "Alpha J" --judgement …` 成功寫入（`dv` 的 authorized 變空、多一筆撤回），`--add-variant "Alpha J"` 被拒——「variant「Alpha J」帶時間欄位——異寫法沒有生效期間」。對外形已經撤掉了，而工具面沒有任何一步走得回原路。

同判斷的出口逐句看過：variant 欄「不在 variant 卻以指定或確認結尾」有兩句（名字是對外形、名字未標），兩句都要 `--add-variant` 它；未標那一句的第一步就是 `--add-variant`，在帶時間的名字上第一步就被拒（沒有寫入、但同樣走不通）。variant 的撤回只有 `--authorize` 把名字抬出 variant 時會寫——名字進不了 variant，就寫不出 variant 的撤回。所以這一格**沒有工具面的出口**。其餘四句不涉及：「仍在 variant 卻以撤回結尾」的名字在 variant 裡、不可能帶時間；authorized 欄的兩句只用 `--authorize`／`--unauthorize`，對外形可以帶時間；「不在 authorized 卻以指定結尾而它在 variant」的名字同樣在 variant 裡。person 的名字沒有時間欄位。

處置：`ClassificationTailConflict` 多一個 `dated`（venue：名字合併後有帶時間欄位的段，`DateRange.makesTemporalClaim`，看合併後的 `keeper.names`——倖存者的段與併入的段都在裡面）。variant 欄「不在 variant 卻以指定或確認結尾」而 `dated` 時，出口換成一句，在任何一步之前說：工具面沒有出口——variant 不得帶時間、`--add-variant` 收不了它，而 variant 的撤回只在 `--authorize` 把名字抬出 variant 時才寫；不要先 `--unauthorize` 它；只能手改帶來它的被併者的 YAML，在它的 references 末尾為這個名字補一筆 `field: variant`、`judgement: 撤回：理由` 的記錄，commit 之後再合併。照這個手改做（scratch store 與測試各一次），乾跑通過、搬兩筆（指定與補的撤回），合併後倖存者尾端一致、對外形與名字段的時間都在。

選「說只能手改」而不是另一條工具路徑：唯一想得到的工具路徑是先用 `--edit-name-segment` 拿掉時間欄位、照三步做、再補回時間——名字有兩段同名而不相交的沿革時，拿掉時間會讓兩段成為近重複、第一步就被拒；而且它改寫的是與這個矛盾無關的時間資料。

測試（`NameClassificationB41Tests`）：帶時間的對外形——出口說只能手改、不給 `--unauthorize 它、--add-variant 它`，照手改做到合併通過；舊出口的第一步寫入、第二步被拒（釘住為什麼）；帶時間的未標名字——同一句、不給「兩邊都 --add-variant」，`--add-variant` 確實被拒。

### 補回對外形那一步也要附理由（第 14 列，INFO）

三句出口寫「三次都附 --judgement——同書寫系統原本的對外形在 --authorize 那一步被換下，要再 --authorize 補回」，字面讀成只有前三次要附；`--authorize` 一律必附理由，第四步照字面做會被拒。補回也不是每次都要（同書寫系統原本沒有別的對外形時不必）。三句（authorized 欄而名字在 variant、variant 欄未標的「要它不是異寫」、authorized 欄未標）都改成「每一步（或兩次）都附 --judgement；同書寫系統原本有別的對外形時，它在那一步被換下（寫撤回），第四步（或第三步）再 --authorize 它補回（同樣附 --judgement）」。`testTheReplacementStepIsSaidToNeedAJudgementToo`。

## LOW

| 列 | 處置 |
|---|---|
| 1 | `docs/rulings/mcp-cli-parity.md` CLI-only 表的 `resolve-divergence` 列補 b39 的重新確認（「一律拒絕」收窄、措辭、`inOtherPartition` 的兩句出口）與這一輪的（帶時間名字的出口、補回附理由）。缺席的理由不變。 |
| 2、5 | 零實例第 96 列的裁決欄拆成三軸：每個名字的段數與每段的 attested 不新增回應鍵（b34、b37）；名字數那一軸以**新增的**回應鍵 `detailsTruncated`／`detailsListed` 揭露（b39；沿用 venue 移除面一族已有的鍵；它們在不在使用者 2026-10-05「不新增回應鍵」那個裁決的範圍內是 Claude 代裁、待使用者確認）；b41 再加位元組預算。理由欄的「CLI 與 MCP 同一份（不分面）」限定成前兩軸。「各列共通的東西」的第 98 列 bullet 改成收窄後的條件。第 85 列（合併後的保險）補 b39 的「同一個方向」與這一輪的更正，量測文件第 85 列同。 |
| 3 | 攣生豁免放行之後，合併照搬記錄的規則接——名字仍在 authorized、兩筆攣生都持有「指定 R → 撤回 W」時，倖存者的尾端本身矛盾，`carryCollecting` 的「倖存者已有、而且此刻尾端一致才略過」不成立，較早的「指定 R」被接在撤回之後，倖存者的記錄成為 [指定 R, 撤回 W, 指定 R]、最後一筆從撤回變成指定。**行為不改**（被豁免的攣生該不該停止重搬是待裁項，主 session 列進 Blocking）。說實話的部分：`docs/store-format.md` §3.5 補一段、spec delta 補 Scenario「Twins ending in a withdrawal on a still-authorized name」（它是搬記錄規則既有 SHALL 的直接後果：「此刻一致」不成立就照接）、`two-kinds-of-edits` 合併那一格補記、b39 changelog 的那一句加 b41 補記；`testAVenueTwinRepeatingTheSurvivorsContradictionIsNotRefused` 補三個斷言（搬了「指定 r」、合併後的記錄、最後一筆是指定），`NameClassificationMergeB41Tests.testTwinsEndingInAWithdrawalOnAStillAuthorizedNameRecarryTheEarlierDesignation` 以 store 的乾跑與實跑釘住同一件事（person）。`testIdenticalTwinsHoldingTheSameContradictionMerge` 的註解寫明「什麼都不搬」只對它那一種攣生成立。 |
| 4、7 | `update-person --fields --dry-run` 改跑 `writePerson` 的**整條**前置。b39 只補了 #631；兩席以真 binary 重現另兩類：9 MiB 的 `note`（從 stdin 給）乾跑回 `wouldChange`、實跑以「寫出後 9437279 位元組，超過這次寫入的上限 8388608」拒絕；format 9 的 store 改一筆有 names 的 person，乾跑回 `wouldChange`、實跑以「含巢狀 names，需要 store format ≥ 10」拒絕。`LibraryStore` 的 person 寫入前置拆成各段——`plannedWrite` 依序跑 store root、內容閘（`assertPersonWritable`：format gate 與 error 級驗證）、`plannedWriteAfterContentGates`（encode 含讀取上限、#631 目的檔）；新的 `preflightWrite(_:contentGate:)` 走同一串，內容閘的擲出交給回呼、之後不再問（實跑也停在第一道），其後的照擲。乾跑：有 error 級驗證錯誤時照舊以 `blockedByValidation` 說（實跑在 `writePerson` 之前就拒）；否則跑前置，內容閘的拒絕在既有兩個鍵（ended、名字分類）都沒有說時以 `blockedByFormatGate`（「real run 會被拒：」＋那一句）回報，encode 的回讀驗證、寫出上限與 #631 照拒、零寫入。全套測試抓到第三類假預覽：`RetrievalWriteShapeR3Tests`／`R4Tests` 的兩支 IPv6 測試對一筆沒有 `openalex` 的 person 乾跑加一筆 `field: openalex` 的 reference，先前乾跑通過，實跑會以 encode 回讀的「記錄沒有 openalex 欄位——reference 指名的欄位必須存在」拒絕；新的乾跑同樣拒絕。那兩支測的是網址形狀，fixture 的 person 補上 `openalex`（註解寫明為什麼），斷言不動。不新增回應鍵。CLI `--dry-run` 的 help 寫出這些；MCP `dry_run` 說明改成「true＝零寫入，實跑會拒的也拒（預設 false）」。`UpdatePersonDryRunPreflightCLITests`（真 binary；`CLITestHarness` 多一個帶 stdin 的 `run`，9 MiB 放不進 argv）。 |
| 6、11 | organization `remove_names` 的 MCP 報告：列出的 `segments` 另以 compact JSON 計（`jsonBytes`，resolve 候選與 doctor 的 per-record 清單同一把）合計至多 `candidateByteBudget`（48 KiB），放不下的名字照段數那一軸的形不帶 `segments`、同兩個鍵揭露；CLI 照舊全列。b39 只封段數：`displaySafe(max:)` 數輸入 scalar，控制字元逃脫成 `\u{XXXX}`、JSON 再把反斜線加倍——security 席 20 段（source、note 各 300 個 U+0001、attested 20 個各 40 個）一次回 318,939 位元組，devil's advocate 席 40 個名字同形 325,644 位元組；b39 changelog 的「MCP 回應小於 48 KiB」只對它的 fixture 成立（該 changelog 加了更正）。測試：兩個名字各 5 段控制字元——段數放得下、位元組放不下第二個；security 席的形——第一個名字就放不下、`detailsListed: 0`，回應小於 48 KiB（理由是「打錯」）。整份回應另含每個名字的名字、理由與計數，由呼叫端送的名字與理由決定，不在預算裡（第 15 列）。 |
| 8 | **不改**。devil's advocate 席（第 21 列）以 stdio 實際呼叫：帶 `unauthorize` 時 server 回 isError、訊息說 organization 沒有撤回腿（#557，待裁）並指路 `authorize`；說明裡的「沒有 unauthorize（待裁）」照樣告訴呼叫端它不存在，inputSchema 也沒有這個屬性。被刪的「給了即拒絕」不帶新資訊，加回來要 18 位元組。 |
| 9 | spec delta 的兩個 SHALL 補上「in the same direction」，與程式（`heldKey`）一致。不加「方向不同不豁免」的 Scenario：那個形狀在載得進來的 store 上到不了（第 10 列）。 |
| 10 | 「方向不同只發生在倖存者的記錄錨不到 names（手改，載入不驗）」為假——那種記錄在載入時整筆隔離（2026-10-19 真 binary 確認：venue 持一筆 `field: variant`、value 不在它的 names，`akashic validate` 整筆隔離，「名字分類的判定記錄錨定在 names」）。倖存者的記錄都錨定在 names，合併不改倖存者既有名字的分類（venue 只把倖存者沒有的名字標 variant，person 的 authorized 不變），方向就是成員資格、合併前後必然相同，方向那一項在任何載得進來的 store 上不改變結論；同理「倖存者自己的」那一格（`broughtBy == nil`）也到不了。**程式不改**（定義保留）。改說法的地方：`heldTailContradictions` 與 `ClassificationTailConflict` 的 doc comment、store-format §3.5、`two-kinds-of-edits` 合併那一格、零實例第 85 列與量測文件第 85／98 列、Spectra design（修正輪五那一句加更正、新增修正輪六）、b39 changelog 的那一句。測試：`testASurvivorContradictionInTheOtherDirectionDoesNotExempt` 的註解寫明它是記憶體裡的構造，新的 `testTheOtherDirectionShapeDoesNotLoad` 以手寫 YAML 釘住那個形狀載不進來（encode 自己的 canary 就擋下這筆，所以磁碟上只能是手改）。issue Blocking 的第 6 項（「同一個矛盾」讀成同方向對不對）兩種讀法在真實 store 上給出同一個答案——這一點寫進報告，項目本身留給使用者。 |

INFO：

| 列 | 處置 |
|---|---|
| 12 | 同第 3 列。 |
| 13 | `NameClassificationB37Tests` 那一句「記錄讀不出動作的那一格沒有出口，不加」改成說明那個分支 b39 當死碼刪了。 |
| 14 | 見上（MEDIUM 同節）。 |
| 15 | 不改程式：理由只進報告、不截是使用者對移除面一族的裁決。文件寫明整份回應不在位元組預算裡（第 6／11 列那一格、store-format、零實例第 96 列與量測文件）。 |
| 16、19、20、21、23 | 只讀；第 21 列是第 8 列的處置依據。 |
| 17 | 同第 4、7 列：乾跑對所有欄位都跑同一條前置，CLI help 與 MCP 說明現在說乾跑也會拒。 |
| 18 | 同第 6、11 列；`testOrganizationRemovalReportStaysWithinTheMCPBudget` 的註解加「只在這個 fixture 下」。 |
| 22 | 不改行為：豁免區內，合併後倖存者的最後一筆由被併者 key 的字典序決定（拒不拒絕與 key 無關）。是使用者 2026-10-15 收窄裁決與 spec「依 key 順序搬」的直接後果；寫進報告，請主 session 一併列進待裁。 |

## 檢查過的同判斷路徑

- **要 `--add-variant` 的出口**：venue `tailConflictExits` 的六句逐一看過（見 MEDIUM 那一節）；其他提到 `--add-variant` 的出口——合併的分類不同（`wouldLoseFields`，只說「讓兩邊分類一致」）、`bootstrap-venues` 的提示（新的寫法、沒有時間欄位）、`--remove-reference` 對 variant 的拒絕（一般說明）——都不叫人對特定的帶時間名字做 `--add-variant`。刪名字的拒絕（venue `nameSegmentRemovalBlocker`、organization／person `nameRemovalRefusal`）的出口只用 `--authorize`／`--unauthorize`，對外形可以帶時間。person 的名字沒有時間欄位。
- **乾跑等於實跑**（單檔寫入者）：`update-person --fields`（這次改跑整條前置）、`update-person --remove-name`（這次在乾跑也跑 `preflightWrite`；git 閘與目標 store 確認閘照舊只在實跑，help 寫明）、`update-entry`（本來就跑 `preflightWrite`）、`dismiss-divergence`（乾跑只回報要刪的那一筆，沒有寫入計畫）。`update-venue` 與 `update-organization` 沒有乾跑。
- **報告位元組由 store 內容決定的移除面**：organization `remove_names`（這次加位元組預算）；venue `edit_name_segment` 與 `remove_reference` 是前 20 項帶明細的項數上限，`VenueReferenceRemoval` 的 doc 明寫 `akashic_venue` 沒有單一輸出預算、25 項約 150 KB 是推估——沒有宣稱位元組上界，這一輪不改（同樣的逃脫放大在那裡也成立，是否也加位元組預算可另案）；person `remove_names` 每個名字只回名字、理由與計數。讀取面全列屬待裁第 3 項。
- **「方向」與「倖存者自己的」說法**：程式的兩處 doc comment、store-format、兩張規則表、量測文件、Spectra design、b39 changelog，見第 10 列。

## 負控（反向編輯還原，不用 checkout）

五個突變一起套上、一次建置一次跑（`NameClassificationB41Tests`、`NameClassificationMergeB41Tests`、`UpdatePersonDryRunPreflightCLITests`、`NameClassificationMergeB39Tests`、`NameClassificationB39Tests`、`NameClassificationMergeOrderTests`，34 支）：

| # | 突變 | 變紅的測試 |
|---|---|---|
| NC1 | 出口不看 `dated`（`c.dated && false`） | `testTheVariantExitForADatedAuthorizedNameSaysOnlyAHandEditWorks`、`testTheVariantExitForADatedUnmarkedNameSaysOnlyAHandEditWorks` |
| NC2 | authorized 欄未標那一句改回「要再 --authorize 補回」 | `testTheReplacementStepIsSaidToNeedAJudgementToo` |
| NC3 | update-person 乾跑不跑前置 | `UpdatePersonDryRunPreflightCLITests` 兩支（真 binary）、`testUpdatePersonDryRunRefusesALegacyCopyLikeTheRealRun`（b39 的 #631 那一支——新前置涵蓋它） |
| NC4 | organization 報告不設位元組預算 | `testOrganizationRemovalSegmentsAreBoundedInBytesOnTheMCPFace`、`testOrganizationRemovalReportWithEscapeHeavySegmentsStaysBounded` |
| NC5 | `--remove-name` 的乾跑不跑前置 | `testRemoveNamesDryRunRefusesWhatTheRealRunRefuses` |

9 支紅、其餘 25 支照綠（`testTheOldVariantExitWritesStepOneThenFailsStepTwoOnADatedName` 與兩支合併的現況測試釘的是 store 與合併本身，不隨突變變）。以反向編輯還原，`git diff --stat` 與突變前相同。

## 測試與守衛

全套測試（`swift test --build-system native`）：5,257 支、1 支略過（`MigrateProvenanceCLITests.testWriteFailureIsListedAndExitsNonZero`，chflags 在這個檔案系統不生效）、0 失敗（第一次全套抓到上面那兩支 IPv6 測試，修 fixture 之後重跑）。新增測試 11 支（`NameClassificationB41Tests` 7、`NameClassificationMergeB41Tests` 2、`UpdatePersonDryRunPreflightCLITests` 2）。`--build-tests -Xswiftc -warnings-as-errors` 乾淨。`.githooks/run-guards.sh` rc=0。

## `tools/list` 位元組

真 binary（`akashic-mcp` stdio，`tools/list` 回應整行不含換行）：base（04131a49）**59,171**，這一輪 **59,159**，**−12 位元組**。`akashic_update_person` 的 `dry_run` 說明「true＝只回報會改什麼並預演 format gate、零寫入（預設 false）」改成「true＝零寫入，實跑會拒的也拒（預設 false）」（−21）；`akashic_update_organization` 的 `remove_names` 說明「segments 合計至多 20 段」加「、48 KiB」（+9）。`blockedBy*` 的細節寫在 CLI `--dry-run` 的 help。

## 規則表改了哪些列（沒有新增列）

- `docs/rulings/mcp-cli-parity.md`：MCP 表 `akashic_update_person`、`akashic_update_organization` 兩列補 b41 重新確認；CLI-only 表 `resolve-divergence` 列補 b39 與 b41 重新確認。
- `docs/rulings/two-kinds-of-edits.md`：`resolve-divergence`／攣生合併那一列補 b41 補記。
- `docs/rulings/zero-instance-guards.md`：第 85、96 列；「各列共通的東西」的第 98 列 bullet。

## 仍待使用者裁決（不在這一輪決定）

issue 的 `### Blocking` 裡的項目，這一輪都沒有動它們問的行為：

1. 附了 `--judgement` 而沒有名字進出 authorized 時整批拒絕：維持，還是改成放行並回報「理由沒有寫進任何記錄」？
2. issue Expected 3（確認既有的值留記錄）對 person 不再成立：另給 person 一個確認面，還是標成不適用？
3. 報告的 attested 截在 20 個、以最後一項文字說出省略數、讀取面全列：維持，還是另加回應鍵、或讀取面也截？
4. `akashic-verify-person`、`akashic-promote-literals` 要不要補一行「保留 authorized」的提醒？
5. b39 的讀法（「同一個矛盾」＝同方向；「會不會搬」以（分割, 名字）計）對不對。這一輪的發現：方向那一項在載得進來的 store 上不改變任何結論（第 10 列），所以兩種讀法在真實 store 上給出同一個答案。
6. （主 session 新增）被豁免的攣生該不該停止重搬較早的記錄（第 3／12 列）。現況：會重搬、倖存者的最後一筆可能被翻成指定。
7. （主 session 新增）`detailsTruncated`／`detailsListed` 在不在使用者 2026-10-05「不新增回應鍵」的範圍內（第 5 列）。
8. （建議一併列入）豁免區內合併後倖存者的最後一筆由被併者 key 的字典序決定（INFO 第 22 列）。
