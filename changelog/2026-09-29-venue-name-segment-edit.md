# 2026-09-29 venue 名字段的編輯面：時間欄位、source、note 與刪段（#675）

## 問題

venue `names` 的每一段（`TemporalValue`）可以帶時間欄位（`start`／`end`／`ended`／`attested`）、`source`、`note`，但沒有任何工具面能改它們：`update-venue --add-name` 只加新名字，`--authorize` 與 `--add-variant` 只改分類。#565 起，venue 合併遇到「同名、時間／source／note 不同、又不是可並存的沿革」的兩段會具名拒絕，出路只有手改 YAML——沒有型別檢查、沒有 round-trip、沒有原子性，是 `replace-endnote-and-zotero` 第 4 條要記成缺口的那一種。

另一個附帶的缺口：`venue`／`akashic_venue` 的 `names[]` 只帶時間欄位，**看不到 `source` 與 `note`**。同名的兩段只差 `source` 或 `note` 時（#565 拒絕的正是這種），呼叫端連要改哪一段都認不出（能寫不能讀，#218／#219 的形狀）。

live store 今天沒有實例（2026-09-29 唯讀量測：485 筆 venue、537 段名字，帶時間欄位 0、帶 source 0、帶 note 0），所以這是設計上的缺口，不是已發生的資料損失。

## 改了什麼

### 新的一條腿：`update-venue --edit-name-segment`／MCP `edit_name_segment`

收一個 JSON 物件陣列，每項 `{name, match?, set 或 remove, reason}`（一次至多 200 項）。檔頭契約在 `Sources/AkashicMCPKit/VenueNameSegmentEdit.swift`。

- `name`：以 canonical 相等定位（與 `add_names`／`add_variant`／`authorize` 同一把）。
- `match`（選填）：同名不只一段時縮小到一段。鍵與 `set` 相同（`start`／`end`／`ended`／`attested`／`source`／`note`，鍵名同讀取面的 `names[]`）；給了的鍵都要相符，字串與陣列比 UTF-8 位元組；**`null` 是「要求缺席」**。
- `set`：逐鍵覆寫、沒給的鍵不動；字串給 `null`、`ended` 給 `false`、`attested` 給 `[]` 或 `null` 是清除。
- `remove: true`：刪掉那一段，與 `set` 擇一。
- `reason`：必填、至多 4,096 位元組。

**它是判定**（「這一段的時間是錯的」），走移除面一族的裁決（使用者 2026-09-27）：理由只進報告（`nameSegments[].reason`，全文不截）、不寫進 store、不改 store format；改寫前要求該 venue 檔已在 git 裡 commit、乾淨（`assertRecordsRecoverable`，issue `#675`）。每一項改完都與現在逐位元組相同時不寫檔、不過 git 閘（報告 `written: false`）。沒有乾跑，同 `--remove-reference`。

拒絕（都是整批、零寫入、具名）：

- 輸入錯（鍵封閉、`set` 與 `remove` 恰一個、時間要寫成字串、`ended` 要布林、`source`／`note` 不得空白……）。
- 定位不到（列出現有的名字或同名各段）、定位到多段（列出各段的區別，並說怎麼用 `match` 縮小，含 `start: null` 的用法）、兩項指到同一段、逐位元組完全相同的重複段。定位都在**呼叫前的記錄**上，不依陣列順序。
- 改完的時間欄位不成立：`end` 與 `ended: true` 並存、`attested` 與起訖並存、非 ISO 8601 前綴、`start` 晚於 `end`。訊息說出怎麼在同一個 `set` 裡給 `null` 清掉矛盾的那一格。
- **這次造出的** `Venue.validate()` error：在寫之前具名拒絕並歸因到這次編輯（例：時間欄位落在 `variant` 的名字上——異寫法沒有生效期間；把兩段沿革改成重疊）。記錄原本就有的違反不歸咎，寫入閘照舊會擋。同一次呼叫的各項先全部套用再驗，所以兩段沿革可以在同一次呼叫裡一起改成不相交。
- 移除一個名字的最後一段時，名字還在 `authorized`／`variant`／`field: names` 的 reference 裡，或移除後 venue 沒有任何名字：具名拒絕並指路（`--authorize`／`--remove-reference`；`variant` 沒有移除面，老實說只能手改 YAML）。程式不替人動那些判定。

**單獨呼叫**（代裁，同 `--remove-reference`）：不與 `update-venue` 的任何其他參數組合，也不與 `remove_reference` 組合。

### 讀取面

`venue`／`akashic_venue` 的 `names[]` 多帶 `source`／`note`（各截 300 字元，沒有就不輸出）；CLI 人可讀面在該段後印 `source 「…」`／`note 「…」`。報告與讀取面共用同一個 `nameSegmentFieldsDict`，讀取面看到的鍵就是 `match`／`set` 收的鍵。

### 共用判準

- `DateRange.contradictionDescription`（`Temporal.swift`）：矛盾組合的一句說明。`PersonYAML.rejectContradictoryRange`（YAML 的 encode／decode）改成呼叫它，訊息逐字不變；寫入面的輸入檢查也呼叫它——工具面說「可以」而 store 邊界說「不行」的組合不存在。
- `Venue.endpointIssue`／`Venue.nameSegmentRangeIssue`（`Venue.swift`）：區間有效性（端點是 ISO 8601 前綴、`start` 不晚於 `end`）。`segmentIsWellFormed`（沿革豁免的放行條件）改成 `endpointIssue(r) == nil`，成功路徑不配置任何東西（那個函式在同名組的求值迴圈裡最多跑 100,000 次）。寫入面放行的區間，沿革豁免也認得。
- 這是寫入面的輸入檢查，**不是** store 的不變式：載入端對 venue `names` 的日期不驗（#85），手改的非 ISO 值照樣載入。要不要升成 `validate()` 的 error 是另一個裁決（會讓既有的手改值從「載入得了」變成「所有寫入被拒」）。

### #565 的合併拒絕訊息

`describeNameSegmentConflict` 的兩種出路（與倖存者衝突、兩個被併者互相衝突）都改指向 `update-venue --edit-name-segment`（remove 或 set），並保留「也可以手改 YAML」。

### 其他

- `RemovalReportSupport.noteIndexRebuildFailure` 多一個 `written:` 參數（預設是原本的移除句），名字段編輯的 `indexNote` 說「改寫已經寫入磁碟」。
- MCP manifest：描述只寫做什麼、`reason` 只進報告、git 閘與指向 CLI help。`tools/list` 實測 46,249 位元組（預算 49,000；這一條腿約 +350）。
- 文件同步：`docs/store-format.md` §5.7 多一段；`.claude/rules/mcp-cli-parity.md` 的 `akashic_update_venue`（新增，含組合規則與兩面差異）與 `akashic_venue`（重新確認）兩列；`.claude/rules/two-kinds-of-edits.md` 加一列；`.claude/rules/zero-instance-guards.md` 第 43 列補出路；`WriteGateRulings` 的 `update-venue` 命令層一格寫明新腿（裁決仍是不閘，理由同兩條移除腿）；`update-venue` 的 help 與 MCP 描述。

## 測試與負控

新增。**測試是實作之後補的，沒有嚴格照先紅後綠走**（先寫了服務，再寫測試，再以下面的突變補回「測試真的在守」）：

| 檔 | 支數 | 內容 |
|---|---|---|
| `VenueNameSegmentEditTests` | 31 | 改（只動被定位到的一段、`null` 清除、match 的 `null`、canonical 名字與位元組 match、`attested`／`ended`、矛盾與非 ISO、只改 source／note 不重驗手改日期）；這次造出的違反歸因與原本就有的不歸咎；移除（保留同名另一段、最後一段的孤兒與空 venue）；定位（多段、找不到、同段兩項、位元組相同的重複）；沒有變動不寫不過閘；git 閘；理由全文且不進 store；輸入錯 28 種；單獨呼叫（10 條腿＋反方向）；key 重複與 venue 不存在；MCP 報告只有前 20 項帶前後內容；讀取面帶 source／note；與 #565 接起來（合併拒絕指向這個面、用它刪掉被併者那一段後合併成立，或把兩段改成不相交沿革後合併保留兩段） |
| `VenueNameSegmentRangeTests` | 5 | 矛盾判準、YAML 邊界說同一句、`nameSegmentRangeIssue` 接受與拒絕的表、端點判準對沿革豁免與寫入面一致 |
| `UpdateVenueEditNameSegmentCLITests` | 2 | 真 binary：未 commit 拒絕、commit 後成功、報告與讀取面（人可讀與 `--json`）看得到 source／note、刪段；用法錯誤 exit 64 且不被缺佈局搶先 |
| `StdioE2ETests.testEditNameSegmentReachesTheService` | 1 | 真 binary：JSON `true` 是布林、`null` 是清除、整數不是字串、鍵名接到服務 |
| `RemovalIndexRebuildFailureTests` | +1 | 名字段編輯在 index 重建失敗時報告不消失 |

負控（反向編輯後跑測試、再還原並 `cmp` 確認逐位元組相同）：

| # | 改壞什麼 | 結果 |
|---|---|---|
| 1 | `match` 恆真 | 11 支紅 |
| 2 | 不驗改完的時間區間 | 13 支紅 |
| 3 | 不過 git 閘 | 4 支紅 |
| 4 | 不歸因這次造出的不變式違反 | 3 支紅 |
| 5 | 移除時不查孤兒 | 5 支紅 |
| 6 | 理由在報告裡截成 200 | 1 支紅 |
| 7 | match 的 `null` 當沒給 | 1 支紅 |
| 8 | 單獨呼叫的檢查整段略過（第一版只拿掉反方向的一行，是等價突變：另一個區塊照樣拒絕，改成整段略過） | 11 支紅 |
| 9 | 沒有變動也寫 | 1 支紅 |
| 10 | match 字串改成 canonical 相等 | 2 支紅 |
| 11 | 合併訊息不指向編輯面 | 1 支紅 |
| 12 | 讀取面不帶 source／note | 5 支紅 |
| 13 | 矛盾判準少一支（`ended` 與 `attested`） | 1 支紅 |
| 14 | 端點檢查放行倒置 | 7 支紅 |
| 15 | 兩項指到同一段不拒 | 2 支紅 |

負控的記帳有一個教訓：driver 的正則 `with (\d+) failures` 對「恰好 1 個失敗」的輸出（`with 1 failure`）不匹配，第 6、7、9、11 號因此被記成「編譯錯誤」，實際都是各紅 1 支；第 13 號第一次跑得 0 支紅（Range 測試沒被選進那次的執行），重跑得 1 支紅。都重跑確認、輸出存檔。

## 誠實邊界

- **時間欄位的 ISO 檢查只在這個入口**，載入端仍不驗（#85）。手改的非 ISO 值照樣載入、`segmentsAreDisjoint` 不認它。
- **`variant` 沒有移除面**：移除一個名字的最後一段而它在 `variant` 裡，出路只有手改 YAML。撤回面（#559 記的是 authorized）另案。
- **`source`／`note` 的讀取面截在 300 字元**，超過的段要對照 YAML；`match` 收逐字的值。
- **位元組完全相同的重複段沒有編輯路徑**：`match` 分不出它們，本面不替呼叫端挑。
- **沒有乾跑**：`update-venue` 整個命令沒有；git 閘與整批拒絕零寫入是退路。要不要有乾跑（連帶要不要過 #298 的目標 store 確認閘）待使用者裁決，這裡沒有動。
- `openspec/specs/venue-entity` 沒有動：這條腿是「既有 tool 的新參數」（#554 的同一個裁決），規格語言的 Requirement 要走 spectra-propose。
- 零實例：新的輸入上限（一次 200 項、理由 4,096 位元組、`source`／`note` 65,536 位元組、`attested` 200 點）與 ISO 入口檢查守的都是零實例形狀；`zero-instance-guards` 的新列由整合者加（提案在報告裡）。

## Verify R1 修正（#675）

以下的「第 N 列」是 batch14 verify R1（b14f）報告的列號。

**合併拒絕訊息只推薦編輯面真的會收的那一條（第 12 列）。** #565 的拒絕訊息推薦「對被併者刪掉它那一段（remove）」，而兩筆重複的 venue 通常以同一個名字當對外形——衝突的正是被併者的 authorized，或它唯一的名字——編輯面對這種 remove 必拒（「沒有任何名字」或「在 authorized 裡成孤兒」）。原本的測試讓衝突發生在第二個名字上，恰好避開了最常見的形狀。現在「能不能刪」只有一份判準 `Venue.nameSegmentRemovalBlocker`（AkashicCore）：編輯面的 remove 以它拒絕（訊息不變，只是從各寫一份改成共用），合併訊息以它決定要不要推薦 remove；刪不掉時推薦 `set`——把被併者那一段改成與另一段逐字相同（對方沒有的欄位給 null），合併就把它當同一段、不搬、不衝突——並說出 remove 為什麼不行。兩個被併者互相衝突時同一個處理：只對刪得掉的那一筆推薦 remove，兩筆都刪不掉就只推薦 set。

**寫入前重讀（第 27 列）。** 閘之後、`writeVenue` 之前讀可回溯閘回傳的那個檔（`LibraryStore.rereadVenue`），與這次讀到的不同就整批拒絕、零寫入——不以閘之前的內容覆寫別的寫入者剛 commit 的修改（#606 同一條；App #609 的 `changedDuringCheck` 是先例）。

**`source`／`note` 不收控制、格式、方向與不可見字元（第 34 列）。** `set` 給的 `source`／`note` 含 `UnsafeToEmitScalar` 人可讀輸出要逃脫的字元（扣掉私用區）就拒絕，訊息指名欄位與碼位（NUL、RLO、ZWSP、TAB、LS、TAG 字元……）；散文用得到的 ZWJ／ZWNJ 與私用區照收。危險 scalar 的定義沿用那一份，沒有新寫清單。`match` 照收——修一個手改進來的髒值要逐字比到它。這是寫入面的輸入檢查，不是 store 的不變式：`source`／`note` 經匯入或手改仍可帶這些字元（§5.7 寫明）。

**顯示名變了要說出來（第 35 列）。** 沒有 `authorized` 的 venue，`displayName` 在時間軸帶時間宣稱時改走現行的那一段——只編一個時間欄位就可能換掉對外顯示的刊名。報告在那時多 `displayNameChanged: {before, after}`；沒變就不出這個鍵。

**`attested` 每個點也有上限（第 43 列）。** 先前只有個數上限（200 點），超長的點要到 ISO 檢查或定位時才失敗；現在每個點與其他字串一樣至多 65,536 位元組，在解析時拒絕（`set` 與 `match` 都是）。

**MCP 描述與 payload 守衛（第 5、13、16 列）。** `edit_name_segment` 的參數說明補上 `match`／`set` 的六個鍵名與 `null` 的兩種意思（`match`＝要求缺席、`set`＝清除），回應鍵補上 `written`、`writeNote`、`displayNameChanged`、`detailsTruncated`／`detailsListed`；`ToolPayloadScenarios` 加三個情境（有變動且顯示名跟著換、沒有變動、超過 20 項）。加情境之後守衛先紅（五個鍵不在說明裡），補說明後綠。

**未改（第 9、41、47、50 列）**：`update-venue` 的三條判定腿沒有乾跑、CLI 不過目標 store 確認閘——待使用者裁決（`WriteGateRulings` 的 `update-venue` 一格與上面的誠實邊界都寫著），這一輪沒有動。

**測試**：`VenueNameSegmentEditTests` +7（被併者的對外形衝突時訊息推薦 set 而不是 remove、照做之後合併成立；兩個被併者都刪不掉時只推薦 set；閘之後被改過並 commit 時拒絕且修改保留；`source`／`note` 的六種危險字元逐一拒絕、ZWNJ 與私用區照收、`match` 修得掉手改進來的 RLO；顯示名換了才出 `displayNameChanged`；`attested` 超長的點在解析時拒絕）＋ 輸入錯的表多兩列。

**負控**（反向編輯、`cmp` 確認還原）：合併訊息的「刪得掉」恆真 → 2 支紅；拿掉重讀比對 → 1 支紅；拿掉 `source`／`note` 的字元檢查 → 1 支紅；拿掉 `displayNameChanged` → 1 支紅；拿掉 `attested` 單點上限 → 1 支紅。
