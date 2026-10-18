# 2026-10-15 名字分類修正輪五：合併的「被併者自己不一致」收窄、organization 刪名字報告的總量、update-person 的乾跑跑 #631 前置（#564）

`changelog/2026-10-09-b37-n1-fixes-564.md`（修正輪四）之後的 verify（b38 Z1，六席：requirements、logic、security、regression、devil's advocate、Codex；Codex 席沒有提出 finding）找到 3 個 MEDIUM（其中兩則是同一件事）、12 個 LOW、5 個 INFO。依 findings 檔的 0 起算列號引用。量測於 2026-10-15（+08:00）。

**使用者 2026-10-15 的裁決**（#564 的 Decision comment）：合併時「被併者自己不一致就拒絕」收窄——只在被併者真的會把記錄搬進倖存者、而且原始倖存者沒有同一個矛盾時才拒絕；豁免條件綁原始倖存者的歷史，不綁處理順序。恢復被改掉的測試資料，補上攣生與「什麼都不搬」兩種情形的測試，拒絕訊息另寫被併者自己矛盾時的措辭。

## MEDIUM

### 被併者自己不一致的拒絕範圍比描述的寬（第 0、1 列；LOW 第 3、6、7 列同源）

b37 的 `doomedTailConflicts` 看的是候選佇列裡被併者自己的記錄尾端，沒有看這次是否真的搬了記錄，也沒有套用倖存者那邊的「合併前就有的矛盾不擋」。兩席以真 binary 重現：(1) 倖存者與被併者逐位元組持有同一個矛盾，合併什麼都不搬，被拒，訊息說矛盾是被併者「帶來的」；(2) 倖存者一致、被併者只是它歷史的前綴，合併什麼都不搬，被拒，訊息說「合併後它在 authorized 的最後一筆是「指定」」，而合併後的最後一筆是撤回；照出口做要替即將刪掉的被併者編兩筆理由，合併後倖存者的永久歷史多出四筆。b37 還把鎖住 (1) 的測試資料（`testAPreExistingContradictionIsNotBlamedOnTheMergeInEitherOrder` 的 b-doom）由「撤回」改成「確認」。

處置（照裁決）：

- `doomedTailConflicts` 只在兩個條件都成立時回報一個（分割, 名字）：
  1. 那筆被併者**單獨**併進原始倖存者時（`carryCollecting` 的同一條規則，在倖存者 references 的一份拷貝上模擬），真的會把那個（分割, 名字）的記錄接上至少一筆；
  2. 原始倖存者在同一個（分割, 名字）上沒有矛盾。
- 條件 1 以原始倖存者為準、不看其他被併者先接了什麼。devil's advocate 席的提醒成立：以實際合併時寫下的記錄來判，一筆只有「指定 x」、另一筆「指定 x → 撤回 w」，後者先接時前者的指定被「倖存者已有」略過——換一個 key 拼法就從拒絕變成放行，正是第 98 列要擋的形。
- 條件 2 與合併後的保險（`classificationTailDelta`）共用一份定義（`heldTailContradictions`）。「同一個矛盾」＝同一個（分割, 名字）、同一個方向（仍在分割卻以撤回結尾，或不在卻以指定／確認結尾）。倖存者的記錄錨定在它的 names 時（記錄錨定 names 是寫入期不變式），合併只加入倖存者沒有的名字、不增加 authorized，那些名字合併前後的分類相同、方向必然相同；方向不同只發生在倖存者的記錄錨不到 names（手改，載入不驗）而被併者把那個名字帶進來、分類變了——那時合併後的矛盾不是倖存者原本那一個。b33 起的保險只比（分割, 名字），那一格會放行；兩道檢查共用定義時一起收緊（零實例、只在手改的 store 上到得了，`testASurvivorContradictionInTheOtherDirectionDoesNotExempt`）。
- 「會不會搬」以（分割, 名字）計：被併者搬了別的名字的記錄、這個名字的一筆都不搬時，它在這個名字上的不一致不進倖存者，不擋。被併者會搬這個名字的某幾筆、而它自己的最後一筆（不一致的那一筆）因為倖存者已有而不搬時，仍拒絕——裁決的字面是「真的會把記錄搬進倖存者」，記錄來自一筆自己不一致的被併者，哪一筆對只有人能判斷。
- 拒絕訊息：被併者自己的矛盾另一句措辭——「被併的 venue「d」自己的記錄裡，「N」在 authorized 的最後一筆是「撤回」，而它仍在 authorized；它會把這個名字的記錄搬進倖存者，被併者自己不一致就擋，不論合併後的最後一筆是否一致」，不說「合併後」。開頭那句改成兩種矛盾都說，並寫明「倖存者合併前就有同一個矛盾的不擋」對兩種都成立。`ClassificationTailConflict` 多一個 `doomedOwn`。
- 測試資料恢復成 b34 的原樣（b-doom「撤回：U」），註解寫出為什麼。新增 `NameClassificationMergeB39Tests`：person 攣生持有同一個矛盾（什麼都不搬，乾跑與實跑都通過、倖存者記錄不變）、venue 攣生重複倖存者的矛盾（會搬，條件 2 豁免）、倖存者的矛盾方向不同時不豁免、被併者是倖存者歷史的前綴（條件 1 豁免）、「會不會搬」不隨 key 拼法翻轉、措辭。
- 文件：`docs/store-format.md` §3.5 搬記錄規則那一段、divergence-record spec delta（同一條 Requirement 的兩個 SHALL 不再在攣生與「什麼都不搬」上結論相反；補五個 Scenario）、Spectra design〈修正輪五〉、零實例第 98 列與量測文件、`two-kinds-of-edits` 的合併一格。

### organization `remove_names` 的報告總量仍無上限（第 2 列；LOW 第 11 列同源）

b37 封了每個名字的段數（20）與每段的 attested（20），名字數（一次至多 200）這一維沒有上限：devil's advocate 席 200 個已撤回的名字各 20 段（300 字元的 source、note）一次回 3,011,093 位元組，security 席 200 名 × 21 段 × 21 個觀測點回 4,699,784 位元組。venue `edit_name_segment` 有前 20 項的明細上限，organization 沒有對應物。

處置：照 venue 的形——**MCP 面的 `segments` 合計至多 20 段**（`removalDetailCap`，單位換成段）。依名字的順序，一個名字列出的段放得進剩下的額度才帶 `segments`；第一個放不下的名字與其後的只回 name／reason／segmentsRemoved／recordsRemoved，以 `detailsTruncated`／`detailsListed`（帶 `segments` 的名字數）揭露。CLI 傳 nil，每個名字都列（每個名字的段與每段的 attested 照舊封頂）。

為什麼選這個而不是位元組預算：venue 的移除面一族（`edit_name_segment`、`remove_reference`、`add_sources`）都用「前 N 項帶明細、其後只回識別與理由、兩個鍵揭露」，呼叫端已經認得這兩個鍵；位元組預算要另一套揭露。為什麼單位是段不是名字：一個名字最多 20 段，以名字計的 20 項是 400 段（約 0.7 MB，300 字元的 source、note 時），沒有解決問題；以段計，最壞是 20 段的明細（每段 start／end 各 40、attested 20 個、source、note 各 300 字元）加上 200 個名字的名字與理由，後者由呼叫端自己送的量決定。

`NameClassificationB39Tests`：三個名字各 15、10、1 段——MCP 只有第一個帶 `segments`、`detailsListed: 1`，CLI 三個都列；40 個名字各 20 段、每段 300 字元的 source 與 note——MCP 回應小於 48 KiB（`candidateByteBudget`）。

## LOW

| 列 | 處置 |
|---|---|
| 3、6、7 | 同第 0、1 列（措辭、測試資料、範圍）。 |
| 4、8 | `update-person --fields --dry-run` 跑寫入當下的 #631 前置（`personWritePlan`，不寫）：同一筆記錄的 legacy 拷貝（id 相同，b37 那一道「不同 id 共用 key」不擋）先前乾跑回 `wouldChange`、實跑被拒，現在兩者以同一句 #631 拒絕。實跑不另問（`writePerson` 會問，同一個操作稍早寫過時 #705 的訊息更準）。devil's advocate 席（第 19 列）指出這不是 b37 引入的、base 的 binary 同樣如此——照修，因為它是同一條乾跑的真實性，b37 的 changelog 與 help 寫「乾跑同樣拒」只對不同 id 成立。 |
| 5、13 | venue 合併拒絕的兩句出口補上兩種處境（`ClassificationTailConflict.inOtherPartition`）：variant 欄「不在 variant 卻以指定結尾」而名字是對外形時，`--add-variant` 收不了它，出口改成 `--unauthorize`、`--add-variant`、`--authorize`；authorized 欄「不在 authorized 卻以指定結尾」而名字在 variant 時，`--authorize` 把它抬出 variant，照先前那句做完它不在任何分割、合併改以「分類不同」拒絕，出口最後多一步 `--add-variant` 放回去。兩句都以真的寫入面（`updateVenue`）照做到合併通過（`NameClassificationB39Tests`）。第 13 列的第三點（出口要求寫判定記錄來解除守衛）是使用者 2026-10-15 裁決收窄之後剩下的那一格：被併者真的會搬自己不一致的記錄時才拒，那時補記錄是唯一不靠手改 YAML 的出口。 |
| 9 | **部分未改**。attested 最後一項是文字這件事沒有寫進 MCP 說明：它的形狀是「仍待使用者裁決」第 3 項（維持、另加回應鍵、或讀取面也截），裁決前寫進 MCP 說明會把一個待裁的形狀寫成契約；`tools/list` 也不能淨增。重複 key 的拒絕是錯誤路徑，訊息自己說出原因與出口，不寫進說明。 |
| 10、12 | MCP `judgement` 屬性說明改成「fields.names 的理由（進出 authorized 時必填，沒進出則拒收）」，`NameClassificationSchemaTextTests` 釘住第二句本身（先前只釘三個詞各出現一次，兩種讀法都滿足）。 |
| 14 | **未在這裡處理**：issue 本文的 `### Blocking` 由主 session 更新（2026-10-15 的 Current Status 已把待裁的四項各列一條）；修正 agent 不編輯 GitHub。 |

INFO：

| 列 | 處置 |
|---|---|
| 15 | `docs/store-format.md` 的 #675 段補上 before／after 每段的 attested 兩面都至多 20 個。MCP 說明不改，理由同第 9 列。 |
| 16 | (1) person 的 Expected 3 是待裁第 2 項，不動；(2) 紀錄的落差由主 session 處理；(3) 同第 17 列。 |
| 17 | `nameRemovalRefusal` 的「記錄讀不出動作」分支與 organization 呼叫端的 `unreadable` 判斷刪掉：`latestAction` 與 `allRecords` 都只收 `isRecord`（statement 讀得出動作）的記錄，沒有最後一筆就是沒有記錄，那一格到不了。organization 的拒絕一律接上寫入閘那一行（三條出口都經 `--authorize` 寫記錄）。 |
| 18 | 修正輪四的〈檢查過的同判斷路徑〉寫「CLI 人可讀的 `attestedPointsLabel`（本來就截在 4 個）」不完整：`akashic venue <key>` 的文字檢視（`VenueCommand` 的 `attested` 那一行）用另一個格式器、全列。它是讀取面，與「讀取面全列」同一個取捨（待裁第 3 項包含「讀取面也截」），這裡只更正紀錄、不改行為。 |
| 19 | 兩筆不同 person 共用 key 的拒絕多一句出口：「先手改 YAML 改掉其中一筆的 key（rename-person 在 key 重複時同樣拒絕）」。 |

## 檢查過的同判斷路徑

- **被併者自己不一致**：person 與 venue 兩個 keeper（`mergedPersonKeeper`／`mergedVenueKeeper`）都經 `doomedTailConflicts`；preview 與實跑共用同一個 keeper 計算（`validatePersonPreconditions`／`validateVenuePreconditions`）；合併只有 CLI `resolve-divergence` 一個面（MCP 與 App 都沒有，`mcp-cli-parity` 的既有裁決）。organization 合併仍是 `unsupportedShape`。
- **「倖存者合併前就有的矛盾不擋」**：合併後的保險與被併者自己的檢查兩處，現在共用 `heldTailContradictions`。
- **合併拒絕的出口**：person 的兩句不受影響（person 只有 authorized 欄的記錄，variant 是「其他名字」、沒有另一個分割可在）；venue 的四句裡，名字在另一個分割的那兩格是這次補的，「仍在某分割卻以撤回結尾」兩格不涉及另一個分割。
- **報告大小由 store 內容決定的移除面**：organization `remove_names`（這次補上名字數這一維）、venue `edit_name_segment`（已有前 20 項）、venue `remove_reference`（已有）、person `remove_names`（每個名字只回名字、理由與計數，大小由呼叫端送的量決定）。讀取面（`akashic_venue` 的 `names[].attested`、CLI `akashic venue` 的文字檢視）全列，屬待裁第 3 項，不動。
- **乾跑的真實性（單檔寫入者）**：`update-person --fields`（補上 #631 前置）、`update-person --remove-name`（本來就問 `unlocatablePersonKeys`）、`update-entry`（本來就在乾跑跑 `preflightWrite`）。

## 負控（反向編輯還原，不用 checkout）

| # | 突變 | 變紅的測試 |
|---|---|---|
| NC1 | `doomedTailConflicts` 不套用倖存者已有的豁免（條件 2） | `testAPreExistingContradictionIsNotBlamedOnTheMergeInEitherOrder`、`testAVenueTwinRepeatingTheSurvivorsContradictionIsNotRefused` |
| NC2 | 不看被併者會不會搬（條件 1） | `testADoomedThatCarriesNothingIsNotRefused`（與 NC1 一起時 `testIdenticalTwinsHoldingTheSameContradictionMerge` 也紅） |
| NC3 | 條件 1 改成看實際合併時寫下的記錄（依 key 順序累積） | `testWhetherADoomedCarriesIsJudgedAgainstTheOriginalSurvivorNotTheMergeOrder`（單獨套用、單獨跑） |
| NC4 | 被併者自己的矛盾改回「合併後它在…」那一句 | `testADoomedOwnConflictIsWordedAsTheDoomedsOwnTail` |
| NC5 | organization 報告不設合計上限 | `testOrganizationRemovalSegmentsShareOneBudgetOnTheMCPFace`、`testOrganizationRemovalReportStaysWithinTheMCPBudget` |
| NC6 | 乾跑不跑 #631 前置 | `testUpdatePersonDryRunRefusesALegacyCopyLikeTheRealRun` |
| NC7 | venue 出口不分名字在不在另一個分割 | `testTheVariantExitForAnAuthorizedNameWorks`、`testTheAuthorizedExitForAVariantNamePutsItBack` |
| NC8 | `judgement` 說明改回「否則拒收」；`remove_names` 說明不寫兩個回應鍵 | `NameClassificationSchemaTextTests` 的兩支（真 binary） |
| NC9 | 重複 key 的拒絕不說出口 | `testDuplicatedKeyRefusalNamesTheWayOut` |
| NC10 | 「同一個矛盾」不比方向（`heldKey` 只留（分割, 名字）） | `testASurvivorContradictionInTheOtherDirectionDoesNotExempt`（單獨套用、單獨跑） |

NC1、NC2、NC4–NC9 一起套上、一次建置一次跑：上表的測試全紅（13 支），同批其餘 21 支照綠；NC3 與 NC10 之後各自單獨做（NC2 拿掉了條件 1，NC3 在那時看不出來；NC10 的方向測試在寫完 NC1–NC9 之後才補，見條件 2 那一點）。都以反向編輯還原，`git diff --stat` 與突變前相同。

## 測試與守衛

全套測試（`swift test --build-system native`）：5,218 支、1 支略過（`MigrateProvenanceCLITests.testWriteFailureIsListedAndExitsNonZero`，chflags 在這個檔案系統不生效）、0 失敗。`--build-tests -Xswiftc -warnings-as-errors` 乾淨。`.githooks/run-guards.sh` rc=0。

## `tools/list` 位元組

真 binary（`akashic-mcp` stdio，`tools/list` 回應整行不含換行）：base（f2a321e4）**59,173**，這一輪 **59,171**，**−2 位元組**。`remove_names`（organization）多寫 `detailsTruncated`／`detailsListed` 與「不得是對外名稱」，`judgement` 多寫第二句；抵銷：organization 的拒絕類別收短（「沒有記錄、不是撤回、仍是對外名稱 → 整批拒絕」併進前一句的「否則整批拒絕」、`unauthorize` 那句去掉「給了即拒絕」、「沒給／空陣列／只有空白項」改成「沒給、空陣列或全空白」），person 工具描述的「寫指定／撤回記錄」改成「寫記錄」。

## 仍待使用者裁決（不在這一輪決定）

issue 的 `### Blocking` 裡四項，這一輪都沒有動它們問的行為：

1. 附了 `--judgement` 而沒有名字進出 authorized 時整批拒絕：維持，還是改成放行並回報「理由沒有寫進任何記錄」？（這一輪只把 MCP 屬性說明寫清楚，行為不動。）
2. issue Expected 3（確認既有的值留記錄）對 person 不再成立：另給 person 一個確認面，還是標成不適用？
3. 報告的 attested 截在 20 個、以最後一項文字說出省略數、讀取面全列：維持，還是另加回應鍵、或讀取面也截？（這一輪不把這個形狀寫進 MCP 說明，見第 9 列。）
4. `akashic-verify-person`、`akashic-promote-literals` 要不要補一行「保留 authorized」的提醒？
