# 2026-09-29 venue 的 references 與 work 的副本宣告，都刪得掉、（venue 的）也讀得出了（#673、#677）

兩張 issue 是同一個形狀：**寫得進去、收不回來**。

- **#673**：venue 的 `references` 自 #587 起寫得進去（`issn`／`names`，合併也會把被併者這兩格逐位元組搬到倖存者），寫錯或已不成立的
  只能手改 YAML；而 venue 的讀取面（CLI `venue`、MCP `akashic_venue`）看不到它們——`verdicts` 與 `paginatedJudgements` 各有自己的鍵，其餘的沒有。
  只寫得進、讀不出，要定位一筆要移除的得先開 YAML。
- **#677**：#614 的 `update-entry --add-source` 只能加。宣告錯了（連到別篇的 PDF）沒有任何面收得回來，唯一的路是手改 YAML 或以 git 還原整個 work 檔。

兩者都是 `replace-endnote-and-zotero` 第 4 條要防的形狀（「這個功能我回去手改 YAML 做」一旦變成常態，就是取代失敗的樣子）。

2026-09-29 唯讀量測 live store：485 筆 venue 帶通用 reference 的 **0** 筆（位元組相同的重複組 0）、2,569 筆 work 帶 `akashic.sources` 的 **0** 筆——
兩個移除面今天都沒有實例要處理，它們是在第一個實例出現之前把出路補上。

## 改了什麼

**移除面一族的第五、第六個實例**（#588 `--remove-issn`、#572 `--drop-venue`、#586 `dismiss-divergence`、#544 `--remove-field`），
套用使用者 2026-09-27 的裁決：**理由必填、只進報告、不寫進 store、不改 store format**，移除前要求被改的檔已在 git 裡 commit、乾淨
（`assertRecordsRecoverable`——被移除的東西只剩 git 那份副本）。兩條都是判定（`two-kinds-of-edits` 的 AI 欄）。

### `update-entry --remove-source <digest>=理由`（#677）

MCP `akashic_update_entry` 的 `remove_sources`，同走 `AkashicService.updateEntry`（`Sources/AkashicMCPKit/EntryUpdate.swift`）。

- 以 digest 定位 `Entry.akashic.sources`；digest 要是合法形狀、**要在該 work 的清單上**（不在就具名拒絕，列出是哪些）。
- **只移除宣告**：`sources/` 裡的 blob 與 `index.jsonl` 的取得記錄原封不動——同一份內容可能被別筆 work 宣告、被欄位層級的 reference 引用，刪存檔另是
  #544 同族的事。`Entry.references`（欄位層級的 digest 證據）也不動（§2.4.1：兩種關係不得合併）。
- **不要求本機有位元組**：別台 clone 上 `sources/` 本來就可能不在，連錯的宣告在那裡照樣要收得回來（與 `--add-source` 的存在性閘相反——那個閘守的是「新連的內容要在」）。
  報告帶 index 的取得記錄（origin、mediaType、note…）只是讓乾跑的人認得出是哪份內容；本機沒有存檔或 index 讀不到時省略（`contentInfoUnreadable`）。
- **四條腿兩兩互斥**（`remove_fields`／`add_sources`／`remove_zotero_sources`〔#680〕／`remove_sources`，共 6 對，各自單獨呼叫，訊息「兩兩各自單獨呼叫」）；預設乾跑，`--apply`（MCP `dry_run:false`）才寫；CLI 的 `--apply` 過 `update-entry` 那一格的閘。
- 整批拒絕、零寫入：缺 `=`、digest 形狀不對、理由空白或超過 4,096 位元組、同一個 digest 兩次、一次超過 200 個、digest 不在清單上；work 無法唯一定位時拒絕。

### `update-venue --remove-reference '<JSON>'`（#673）

MCP `akashic_update_venue` 的 `remove_reference`，同走 `AkashicService.updateVenue`（新檔 `Sources/AkashicMCPKit/VenueReferenceRemoval.swift`）。

- **形狀是 JSON 物件陣列**（CLI 是一個 JSON 字串，同 `--references`）`{field, value?, reason, …縮小定位的鍵}`，不是 `<key>=理由` 的字串形：value 是任意名字，
  可含 `=`、`:`，字串切分沒有安全的分隔符。
- **定位＝`field` ＋ `value` 的位元組相等**（與寫入面去重的 `byteExactKey` 同一把：canonical 相等而位元組不同的是另一筆），可再以與 `--references` 同名的鍵
  （`kind`／`url`／`retrieved`／`status`／`media_type`／`content`／`statement`／`rests_on`）縮小。**定位不到、定位到多筆都具名拒絕**：多筆時列出各筆的區別讓呼叫端加鍵縮小；
  位元組完全相同的重複（#582 的重複掃描報它們）不判定移哪一筆；兩個定位指到同一筆同樣拒絕。
- **收四格**：`names`／`authorized`／`issn`／`note`。通用**寫入**面只收前兩格（#587 R1），但手改或舊資料可能有 `authorized`／`note` 的 reference，
  其中 `authorized` 的會讓 `--authorize` 換不了對外形——那則訊息叫人「刪掉它們」，在此之前沒有面刪得掉。
- **不在本面**：verdict 三欄（`resolve-venues --demote`／`--reject`）與 `paginated` 的判定（`--clear-paginated`：撤回本身是帶理由與證據的判定、翻轉要留史，
  #500——移除面會讓判定與記錄的 `paginated` 值分岔）都具名拒絕並指路。
- **單獨呼叫**（Claude 代裁）：不與 `update-venue` 的任何其他參數組合。其餘腿改記錄的值與名字分割，`--remove-issn` 還會連帶刪 reference，與「移除的是哪一筆」交錯。
- 只移除 reference，它指的號或名字仍在（移除號是 `--remove-issn`）。沒有乾跑（`update-venue` 整個命令沒有，同 `--remove-issn`、`--drop-venue`）：git 閘與整批拒絕零寫入是退路。

**讀取面（#673 的 comment）**：`venue`／`akashic_venue` 多一個 `references`——通用 references（不是 verdict、不是 `paginated` 判定的那些），鍵名同 `--references` 的輸入形，
所以讀取面看到的就是移除面收的形狀；有界（`venueReferencesCap`＝25 筆，推估非量測；`rests_on` 只列前 5 個），超過的以 `referencesTotal`／`referencesTruncated` 揭露；沒有就不輸出。CLI 人可讀面逐筆印，兩面同一條 `venue()` 路徑。

### 連帶修的舊說法

先前的訊息與文件多處寫「venue 的 reference 沒有移除面」，自此為假：通用寫入面對 `authorized`／`note` 的拒收訊息、`--references` 的 CLI help 與 MCP 描述、合併拒絕訊息（被併者的
`paginated`／`authorized`／`note` reference 沒有工具面能搬）、`docs/store-format.md`、`akashic-verify-venue` 與 `akashic-fetch-fulltext` 的 SKILL。
`VenueReferenceWriteTests` 的一條訊息 pin 跟著改。**通用寫入面對 `authorized`／`note` 的收窄沒有動**——#673 明寫落地後重新裁決，那是使用者的事（見下）。

## 測試與負控

- `EntrySourceRemovalTests` 12 支、`VenueReferenceRemovalTests` 22 支（服務層，真檔案系統與 git fixture）；CLI 真 binary：`UpdateEntryCLITests.testRemoveSourceRetractsTheDeclarationOnly`、
  `UpdateVenueReferencesCLITests.testRemoveReferenceThroughTheCLI` 與六格參數錯（exit 64）；`ServiceArgvExitCodeTests.testUpdateEntryArgvChecks` 多六格；
  `StdioE2ETests` 兩處（`remove_sources`、`remove_reference` 與讀取面）接到服務。
- 與 #680 的 `--remove-zotero-source` 整合後補測試：`ServiceArgvExitCodeTests.testUpdateEntryLegsAreMutuallyExclusive`（CLI，六對 exit 64）、`EntrySourceRemovalTests.testAllFourLegsAreMutuallyExclusive`（服務層，六對 × 乾跑／實跑）、`StdioE2ETests.testUpdateEntryDefaultsToDryRun`（MCP，六對）；負控三個（`remove_sources` 或 `remove_zotero_sources` 不算一條腿、只放行 zotero＋sources 一對）都轉紅。
- 先寫測試：新簽章編不過（`removeSources:`／`removeReference:` 不存在）才實作。
- #677 負控（反向編輯、`cmp` 確認還原）10 個：拿掉「不在清單上」的具名拒絕、拿掉 git 閘、乾跑也寫、不移除、全部移除、四條腿放行組合、理由截斷、MCP 不接 `remove_sources`、
  CLI `run()` 不送、CLI `validate()` 不檢查——每一個都讓對應的測試轉紅。
- #673 負控 23 個（同一套反向編輯；`cmp` 確認還原）：value 改比 canonical、不比 value、拿掉縮小鍵 `url`／`kind` 的比對、多筆時放行取第一筆、兩個定位指到同一筆放行、拿掉 git 閘、
  不移除、全部移除、移除時連 `paginated` 也刪、verdict 欄位與 `paginated` 不具名指路、放行組合、單獨呼叫不看 `note`、理由截斷、拿掉 venue key 重複的拒絕、讀取面不列 references、
  讀取面把 verdict 與 `paginated` 也列進去、讀取面不設筆數上限與 `rests_on` 上限、MCP 不接 `remove_reference`、CLI `run()` 不送、CLI `validate()` 不檢查——每一個都讓對應的測試轉紅。

## 誠實邊界

- **位元組完全相同的重複 reference 沒有移除路徑**：定位到它們時本面拒絕、不替呼叫端挑（issue 明寫定位到多筆具名拒絕）。#582 的重複掃描報它們，處置目前仍是手改 YAML。live store 為零。
- **定位靠呼叫端逐字給出 `value`**：讀取面的字串逐一消毒且有長度上限，超過上限的名字讀取面看到的是被截的形——那種 reference 要對照 YAML。
- **`--remove-source` 不刪 blob 也不告訴你別筆 work 是否也宣告了它**：只移除這一筆 work 的宣告；要知道一份內容還被誰引用，要掃全庫（沒有面）。
- **沒有乾跑的 `--remove-reference`**：`update-venue` 整個命令沒有乾跑，本腿沿用；退路是 git 閘（未 commit 拒絕）與整批拒絕零寫入。若使用者要乾跑，是給整個命令加，不是給一條腿。
- 報告裡被移除的 reference 逐字消毒且有長度上限（同讀取面）；理由不截。
- MCP `tools/list` 位元組：實測 45,251 bytes（預算 49,000）；本次新增約 1.2 KB——沒有另建 HEAD 的基線，是把三個工具（`akashic_update_entry`、`akashic_update_venue`、`akashic_venue`）的描述與 schema 還原成 HEAD 的文字後逐個編碼相減估出來的。

## 待使用者裁決

1. `authorized`／`note` 要不要回到通用**寫入**面（#673 Expected 4）：有了移除面之後，「寫進去出不來」的理由已不成立；但 `authorized` 的 reference 仍會鎖住 `--authorize` 換對外形，
   `note` 仍沒有寫入面。本次沒有動。
2. 位元組完全相同的重複 reference 要不要有移除路徑（例：加 ordinal，或「重複全收成一筆」的腿）。
3. `update-venue` 要不要有乾跑（整個命令）。

## 規則

`mcp-cli-parity` 的 `akashic_update_entry`、`akashic_update_venue`、`akashic_venue` 三列補契約變更；`two-kinds-of-edits` 加兩列（`--remove-source`、`--remove-reference`），並改
`--add-source` 與 `--references` 兩列裡「沒有移除面」的說法；`WriteGateRulings` 的 `update-entry` 註解與 `update-venue` 的理由補這兩條腿；`docs/store-format.md` §2.4.1 與 venue references 一節補移除端與讀取面。
零實例列（`zero-instance-guards`）沒有加——見整合者的提案。
