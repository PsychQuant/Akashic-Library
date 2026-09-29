# 2026-09-29 references 寫入面的契約對齊、App 的可回溯性 wrapper 搬進 StoreIO（#674、#683）

兩張 issue 都是「同一件事有兩份描述」：#674 是 person 與 venue 的 references 寫入面各自演化出兩份契約；#683 是 App 的移除面與 `AkashicService` 各自寫了一份可回溯閘的外層與理由上限。這次各自收成一份。

## #674：`update_person` 與 `update_venue` 的 references 寫入面是同一份契約

### 診斷

`update_person` 的 references（#308）與 `update_venue` 的 references（#587）解析同一種 JSON 物件，卻各寫一份：

| | person（#308） | venue（#587） |
|---|---|---|
| `status` | 預設 200 | 必填 |
| 未知鍵 | 靜默忽略 | 拒收 |
| `value`／`media_type`／`rests_on` 型別錯 | 靜默變成 nil／空／略過 | 拒收 |
| 上限 | 無 | 200 筆、statement 4,096 位元組、rests_on 20 個 |

#587 的 Expected 寫「與 person 側同契約」，實作刻意比 person 嚴，並在誠實邊界寫明，但沒有追蹤的 issue。根因不是哪一邊寫錯，是**同一個形狀的解析被抄了兩次**——之後任何一邊改，另一邊不會跟著變。

### 改了什麼

- 新檔 `Sources/AkashicMCPKit/ReferenceWriteParsing.swift`：`parseReferenceObjects(_:policy:)` 是兩個面**唯一**的解析函式。holder 自己的政策（收哪些 field、`value` 入庫前怎麼正規化）由 `ReferenceHolderPolicy` 注入——person 只拒 verdict 欄位對，venue 收 issn／names 並把 issn 的 value 正規化。
- `UpdatePerson.swift` 的 `appendReferences` 與 `VenueReferenceWrites.swift` 的 `parseVenueReferences` 改成呼叫它；兩份各自的解析（約 90 行重複）刪除。
- 兩面的入口不必統一：person 仍在 `fields.references`（CLI 是 `--fields` 的 JSON 內）、venue 仍是 `references`（CLI `--references`）。
- 解析與驗證在讀 store 之前（#654 的慣例）：person 經 `checkUpdatePersonFields`（CLI `validate()` 已呼叫）、venue 經 `checkUpdateVenueArguments`；CLI 違反是用法錯誤（64）。
- **不動 `ProvenanceReference` 的平面 init**：載入既有記錄的判準不能因為寫入面收緊而變。`url`／`retrieved`／`status` 範圍的檢查只在寫入面。

### #674 issue comment 那一項（url、retrieved、status 的形狀）——代裁

comment 要兩個 references 面對齊時「一併裁決要不要只收 http／https、拒絕 userinfo、驗 `retrieved` 與 `status`」。選了最窄、可逆、且不動既有資料的一版：

| 項目 | 裁決 | 理由 |
|---|---|---|
| `url` 只收 http／https、主機非空 | 收緊 | 離線來源本來就該走 judgement 型（#542 R2；status 的錯誤訊息早就這樣說）；`file:` 會把本機路徑寫進 git 追蹤的 YAML |
| `url` 含帳密（userinfo）拒收，**訊息不回顯原值** | 收緊 | 帳密落進 git 追蹤的 YAML；回顯進錯誤訊息等於再送進 log 與 MCP 對話紀錄一次 |
| `retrieved` 是 ISO 8601（`YYYY-MM-DD`，或再接 `THH:MM[:SS[.fff]]` 與 `Z`／`±HH:MM`），**裸日期照收** | 收緊 | store 既有的 33 筆擷取型 reference 全是裸日期，store-format 的範例也是；#262 的「帶 UTC offset」契約寫在 `sources/index.jsonl` 的 `retrieved`、尚未在任何寫入面強制，這裡不替它先行 |
| `status` 在 100–599 | 收緊 | HTTP 狀態碼的值域 |

query 裡的 token（`?token=…`）與路徑裡的機密看不出來，不猜（誠實邊界）。`enrich` 的 `sourceURL`／`sourceRetrieved`／`sourceStatus` 是另一個寫入面的契約，不在「兩個 references 面」的範圍，沒有動；追蹤於 #695（待使用者裁決）。

### 行為改變：先前寫得進去、現在整個呼叫拒絕的輸入類別

person 側（`update_person` 的 `references`／CLI `update-person`）：

1. retrieval 沒給 `status`（先前預設 200——離線掃描檔被記成 HTTP 200）。
2. `status` 不是整數（boolean 先前被當 1、字串 `"200"` 先前被當 200、小數先前被當預設）或不在 100–599。
3. 不認得的鍵（先前靜默忽略，例：`media_type` 打成 `mediatype`、YAML 鍵名 `rests-on`／`judgement`）。
4. `value`／`media_type` 不是字串（先前靜默變成 nil）、`rests_on` 有非字串的元素或整個不是陣列（先前靜默變成空）。
5. `statement` 超過 4,096 位元組、`rests_on` 超過 20 個、一次超過 200 筆（先前無上限）；其餘字串超過 65,536 位元組。
6. `url` 不是 http／https（`file:`、`ftp:`、無 scheme、`javascript:`）、主機為空、或含帳密。
7. `retrieved` 不是 ISO 8601 日期或日期時間。
8. `field` 只有空白（先前只擋空字串）。
9. references 陣列的元素不是物件的錯誤訊息改了（先前「references 必須是 object 陣列」，現在指到 `references[i] 必須是物件`）。

venue 側原本就是這個契約；新增的只有 `url`／`retrieved`／`status` 範圍三項（第 2 項的範圍、第 6、7 項）。

**有記錄的差異，不是遺漏**：空陣列（`"references": []`）在 person 仍是 no-op（`fields` 這個物件裡被提及的一格，先前就是），在 venue 是錯（獨立參數）。#674 只對齊 issue 點名的三個契約，沒有把 person 的 no-op 變成錯誤。兩面各自收哪些 field 是 holder 的政策。

### 對 live store 的影響（唯讀量測，2026-09-29，`~/.akashic/entities` 7,637 筆）

- person 的 references 6,448 筆、venue 2,236 筆、organization 9 筆：**全部是 judgement 型**（verdict 與 `paginated`，由 resolve 流程與 `--paginated` 寫，不經通用寫入面）。**person／venue／organization 的擷取型 reference 是 0 筆**，所以沒有任何既有記錄因為 `status`／`url`／`retrieved` 的收緊而受影響。
- work 的擷取型 reference 33 筆：全是 `https`、無帳密、`YYYY-MM-DD`、status 200（`enrich` 寫的，不經這兩個面）。
- 未知鍵 0 筆；最長的判定理由 687 位元組；rests-on 最多 3 個——上限離既有資料很遠。
- 讀取路徑不變（平面 init 沒動）：不會有既有記錄因此讀不進來。

### 文件與描述

MCP `akashic_update_person` 與 `akashic_update_venue` 的 `references` 描述、CLI `update-person --fields` 與 `update-venue --references` 的 help、`docs/store-format.md`（venue references 一節）、`mcp-cli-parity`（`akashic_update_person` 加一段、`akashic_update_venue` 把「與 update_person 有記錄的差異」劃掉並指向本次）、`akashic-promote-literals` 與 `akashic-verify-venue` 的 SKILL（前者原本寫 retrieval 型 `{field,url,retrieved,content}`，少了 `status`——照那句寫的呼叫現在會被拒）。MCP `tools/list` 46,151 bytes（預算 49,000；本次新增約 260 bytes）。

## #683：App 的可回溯性 wrapper 與理由上限搬進 StoreIO

### 診斷

#609 的 App 移除面（Orphans「拿掉已刪除的附加來源」）自己寫了一份可回溯閘的外層與 `4_096`，與 `AkashicService.assertRecordsRecoverable`／`maxStatementBytes` 是同一件事的正本。AkashicAppKit 與 AkashicMCPKit 互不能 import，所以只能各寫一次。根因同 #674：兩份各寫一次，改一邊另一邊不會跟著變（`no-compat-fallback` §同一件事只能有一份描述）。

### 兩份的差異（以 `AkashicService` 那份為正本）

| | `AkashicService`（正本） | App（先前） | 處置 |
|---|---|---|---|
| 拒絕的措辭 | `LibraryStore.recoverabilityRefusal` 的整句（動作句＋原因＋出路＋issue） | 自己組：「記錄檔不能確認 git 裡有副本：<why>——…先 commit 再做。已拒絕、零寫入」 | 採正本；App 的錯誤 `notRecoverable(refusal:)` 直接帶那一句 |
| 例外型別 | `ServiceError.invalid` | `AdjudicationError.notRecoverable(citekey:why:)` | 各留自己那一層的型別（`recoverabilityRefusal` 的設計本來就是「呼叫端把句子包成自己的錯誤型別」）；case 的形狀改成 `notRecoverable(refusal:)` |
| 路徑解析 | 只認 `entities/`（磁碟上的實際檔名） | entities 佈局同上；legacy 佈局（format < 2）認 `entries/<citekey>.yaml` | 共用函式多一個可選的 `legacyPaths`：只有給了才走、磁碟上要真的有那個檔；App 保留該能力、service 不給。**不是悄悄拿掉**——若要拿掉是另一個裁決 |
| 理由長度 | 常數 `maxStatementBytes`（4,096），各站點對**未 trim** 的原字串比 | `4_096` 字面量，對 **trim 之後**的字串比 | 常數收成一個；trim 與否**沒有動**（保留 App 的 trim 後比——UI 文字尾端的空白不該讓 4,096 剛好的理由被拒）。這是有記錄的差異 |
| 理由訊息中的上限 | `\(Self.maxStatementBytes)`（`4096`） | 硬寫 `4,096` | 改讀常數（顯示為 `4096`） |

### 改了什麼

- `Sources/AkashicStoreIO/RecoverabilityGate.swift`：新增 `LibraryStore.maxStatementBytes`（唯一的字面量定義）與 `LibraryStore.recordRecoverability(root:items:libraries:legacyPaths:action:issue:)`——解析半邊（路徑取自磁碟實際檔名、找不到檔就拒絕、registry 檔、回傳驗過的路徑）從 `AkashicService.assertRecordsRecoverable` 搬來，逐字保留行為。
- `AkashicService.assertRecordsRecoverable` 改成它的薄包裝（把整句包成 `ServiceError.invalid`）；`AkashicService.maxStatementBytes` 改成 `LibraryStore.maxStatementBytes` 的別名（四十幾個呼叫點不動）。
- `Sources/AkashicAppKit/Adjudication.swift`：`assertRecordFileRecoverable` 改呼叫共用函式；理由上限與訊息、報告裡回顯理由的 `max:` 都讀同一個常數。
- 沒有動的另一個 `4_096`：`displayReason`（`QuarantinedFile` 原因的 sink 預算）與 StoreIO 裡 `displaySafeError(error, max: 4_096)`——那是 `ErrorDisplay` 的輸出預算，與「一段人寫的理由」不是同一件事。

grep 確認：程式碼裡 `maxStatementBytes = <字面量>` 只有一處（StoreIO），由測試守（見下）。

## 測試與負控

- `Tests/AkashicMCPTests/ReferenceWriteContractTests.swift`（新，11 個）：每個拒絕格對 person 與 venue 兩面**同時**跑同一個輸入，都要丟出含同一句的參數錯誤、含 `references`、且零寫入（33 格 × 2 面）；帳密不回顯；一次 200 筆；接受格（url 大小寫、埠、IPv6，retrieved 五種寫法，404 也收）；person 不再預設 200（含 dry-run）；只看參數的檢查不需要 store；`retrieved` 與 `url` 的文法單元表（各 8／16 收、25／16 拒）；空陣列的有記錄差異；person 仍拒 verdict 欄位對。
- `Tests/AkashicMCPTests/RecordRecoverabilityTests.swift`（新，8 個；放在 MCPTests 是為了用 `StoreGitCommit`——`GitSpawnHygieneTests` 要求每個 spawn git 的測試檔登記，共用 helper 已登記）：共用函式本身（不在 git、未追蹤、dirty、找不到檔、小寫 UUID 檔名的路徑取自磁碟、legacy 路徑只在給了且存在時走）、service 是它的薄包裝且措辭逐字相同、常數只有一個定義且 service 名字是別名。
- `OrphanedAdditionalSourceTests`（+2）：App 的拒絕整句逐字等於共用函式的整句（不在 git、未 commit 兩種）；理由上限剛好收、多一位元組拒（以位元組計，CJK 也是）。
- 既有測試改動：`ServiceArgvBeforeStoreTests` 的 person retrieval fixture 補 `status: 200`（原本靠預設 200，意圖是測 digest）並加 4 格新契約；`StdioE2ETests` 的 status boolean 案例改用合法的 url／retrieved（讓 status 是唯一的錯）；`ServiceArgvExitCodeTests` +1（兩個面的違反都是 64）；`UpdateVenueReferencesCLITests` 的 status 案例改用合法的 url／retrieved 並加 url、retrieved 兩格。整支套件第一次跑（4,014 個）有 2 個紅，都是本次造成的：`GitSpawnHygieneTests`（新測試檔自己 spawn git 而未登記——改用已登記的 helper）、`UpdateVenueReferencesCLITests`（舊 fixture 的 `url: "u"`）；解析順序同時調整成「缺 status」先於 url／retrieved 的形狀。
- **#674 負控 10 個**（反向編輯，`cmp` 確認還原）：status 預設 200 回來、未知鍵放行、status 範圍不驗、url 不驗、retrieved 不驗、statement 上限拿掉、筆數上限拿掉、person 放行 verdict 欄位、帳密回顯進訊息、person 不經共用解析——每一個都讓對應的測試轉紅。
- **#683 負控 7 個**：找不到記錄檔改成略過、常數改值、App 的字面量回來、service 的別名變成第二個定義、App 自己組一句、legacy 路徑不認、service 自己改寫句子——每一個都讓對應的測試轉紅。
- 沒有先看到紅：#674 的實作與測試同一輪寫完後才跑；「新測試對舊實作會紅」是靠負控 1–3、10（把舊行為放回去）證明的，不是先跑了舊實作。

## 誠實邊界

- **`enrich` 的 `sourceURL`／`sourceRetrieved`／`sourceStatus` 沒有對齊**：三個 references 相關寫入面（`update_person`、`update_venue`、`enrich`）現在有兩份契約——前兩者同一份、`enrich` 沒有 url 形狀／retrieved 形狀／status 範圍的檢查。`enrich` 是判定不同的另一個面（add-only 補值），要不要對齊是另一個裁決（#695）。
- **url 的 query／路徑裡的機密看不出來**：只擋 userinfo；`?token=…` 這類收得進來。
- **#262 的「retrieved 帶 UTC offset」仍未在任何寫入面強制**：本次接受裸日期，理由見上。
- **空陣列的差異**（person no-op、venue 錯）是有記錄的，不是對齊完成。
- **`update-person` 在 `two-kinds-of-edits` 沒有自己的一列**（既有缺口，本次沒有補）：venue 的 references 那列說「同 update-person 的 references」，但 update-person 本身沒有被歸類。
- **App 在 legacy 佈局的能力被保留**而不是與 service 對齊；沒有測試從 App 那一側走 legacy 路徑（共用函式的 legacy 分支有單元測試）。
- **trim 與否的差異**（App 對 trim 後的理由比上限、service 各站點對原字串比）沒有動。
- 人可讀輸出的 `4096`（無千分位）取代 App 訊息原本的 `4,096`。

## 待使用者裁決

1. `enrich` 的來源欄位要不要也收 url／retrieved／status 的形狀檢查（#695）。
2. `update-person` 的 references 在 `two-kinds-of-edits` 的歸類（AI 判定型，與 venue 那列同形）。
3. 空陣列要不要對齊成錯（往 venue 收）。

## Verify R1 修正（#674）

以下的「第 N 列」是 batch14 verify R1（b14f）報告的列號。

**scheme 的回顯只在真的是 scheme 時（第 26 列）。** `vetRetrievalURL` 對非 http／https 的 url 回顯 `://` 之前的前 20 字——檔頭承諾「只在確定是 `scheme://` 形時回顯」，實作卻沒檢查那一段像不像 scheme。`alice:hunter2@example.org/?next=https://x` 的錯誤訊息因此帶出「scheme 是「alice:hunter2@exampl」」，帳密進了 log 與 MCP 的對話紀錄。現在 `://` 之前那一段要符合 `^[A-Za-z][A-Za-z0-9+.-]*$`（`looksLikeURLScheme`）才回顯，否則不說 scheme。

**「缺 status」先於 url／retrieved 的形狀，補回測試（第 28 列後半）。** 本輪把兩支既有測試改用合法的 url／retrieved，程式註解承諾的先後因此沒有測試釘住；補一支（status 缺、url 與 retrieved 都壞 → 先說缺 status）。

**follow-up 補上號碼（第 8、15 列）。** `enrich` 的 `sourceURL`／`sourceRetrieved`／`sourceStatus` 沒有跟著收緊——而 live store 僅有的 33 筆 retrieval url 正是經它寫入的（兩個被收緊的面在 live store 上零實例）。本檔、`mcp-cli-parity` 的 `akashic_update_person` 列、`zero-instance-guards` 第 66 列原本寫「列為 follow-up」沒有號碼，現在都指向 #695（待使用者裁決）。`enrich` 的行為這一輪不動。

**plugin CHANGELOG（第 28、30 列）。** plugin 的 wrapper 自動下載新 binary、skill 文字可能是舊的：`plugin/CHANGELOG.md` 補一段，列出 `akashic_update_person` 的 `references` 新拒收的輸入類別，以及 #663 的 `formerAffiliationAttested` 換成 `observedAffiliation`／`observedAffiliationAt`。plugin 版號沒有動。

**未改（第 37、42 列）**：收緊的範圍超出 issue 本文三項（url、retrieved、status 範圍來自 issue 的 comment）與 `retrieved` 不收 `+0800` 這類基本格式偏移——兩者都是有記錄的取捨，行為不動。

**負控**：`looksLikeURLScheme` 恆真 → 新測試紅；「缺 status」的檢查關掉 → 先後測試紅。兩者都以反向編輯還原、`cmp` 一致。
