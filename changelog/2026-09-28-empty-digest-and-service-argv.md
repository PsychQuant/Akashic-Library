# 2026-09-28 空內容的 digest 不得被引用；服務層的 argv 檢查回到用法錯誤（#654）

#654 收 #546 與 #549 的 R1 verify 留下的三個餘項。本輪做了餘項 3 與餘項 2；餘項 1（`Sources/akashic/Reference*` 的站點歸類）屬 #617 的範圍，那三個檔由另一個 session 持有，本輪沒有動。

## 空內容的 digest 不得被引用（餘項 3）

#546 在 `store-source` 擋下了 0 byte 的內容，但引用端照收它的 digest（`sha256:e3b0c442…`，0 byte 的 SHA-256）：`enrich` 的 `sourceDigest`、`update-person` 的 references、`update-venue --paginated` 與各 undecided 腿的 rests-on、`record-divergence` 的依據、`akashic.sources` 都寫得進去。這個 digest 是常數，任何空輸入都得到它，不指認任何一份存檔；一筆指向它的 reference 說的是「這個值出自一份空的存檔」。

**裁決（使用者 2026-09-28）**：閘放在 `ProvenanceReference.isValidDigest` 本身，不放在 `enrich` 入口——寫入面不只一個，再加上載入，放在共用謂詞一處全部涵蓋。

- `isValidDigest` 對空內容的 digest 回 false。寫入面（寫入閘的 decode canary、`writeDivergence` 的顯式閘、`enrich` 的提案驗證）與載入同一個謂詞：手寫進 YAML 的會讓那筆記錄被隔離。
- 錯誤訊息說「0 byte」而不說「形狀必須是 …」：這個 digest 的形狀完全合法，說形狀錯是假話。理由句是一份常數（`ProvenanceReference.emptyContentDigestReason`），每個拒絕站點共用。
- **謂詞拆成兩個**。新增的 `isWellFormedDigest` 只看形狀，用在兩類地方（封閉列舉）：
  - 位址層：`sources/` 的路徑解析與 `sources/index.jsonl` 的文法。live store 的 index 有一列指向空 blob（#546 之前兩次失敗的抓取留下的），blob 也在。若 index 文法也排除它，那一列會被判成無法解析，而 index 有無法解析的行時 `store-source` 對所有新內容拒寫。
  - `AuthorListFingerprint` 的持久形：它是作者清單的 domain-separated 雜湊，不是內容位址；空內容的 digest 不可能是它的值，那件事由比對時的「不符」說出來。
- `migrate-provenance` 遇到 timeline 舊 `source:` 裝著空內容的 digest 時略過、理由說 0 byte，原資料不動（搬成 reference 會在寫入時被拒）。

**零實例**（2026-09-28 唯讀量測，腳本在 `zero-instance-guards` 本輪新增那一列的量測段）：live store 記錄 7,637 筆、`sha256:` 值 95 個，指向空內容 digest 的 0 個；index 95 列，其中 1 列指向空 blob，blob 在場、沒有記錄引用。所以收緊謂詞不隔離任何既有記錄，也不需要遷移。

## 服務層的 argv 檢查回到用法錯誤（餘項 2）

#549 的判準：只看解析後的 argv 就判得出來 → 用法錯誤（exit 64、印子命令 usage）；需要讀 argv 以外的任何東西 → 執行期失敗（exit 1）。CLI 呼叫 `AkashicService` 時，服務丟的錯誤一律變成 1，其中有些只看參數。

**做法**：服務把只看參數的檢查抽成**不碰 store 的 static 函式**，服務方法在讀 store 之前呼叫一次；CLI 的 `validate()` 經新的 `argvCheck`（`Sources/akashic/ArgvCheck.swift`）呼叫同一個函式、把它的錯誤轉成 `ValidationError`。同一件事只有一份描述（`no-compat-fallback`），CLI 不另寫一套判準；`validate()` 在 `run()` 之前，所以 store 缺佈局時用法錯誤不會被搶先。會交錯檢查的迴圈（judge、split……）把迴圈頭的解析原樣搬進 static 的 `parse…Specs`，迴圈改讀解析結果；訊息逐字不變。

### 搬到 `validate()` 的站點（2026-09-28 逐站盤點，不含 `Reference*`）

| 命令 | 參數 | 檢查 | 函式 |
|---|---|---|---|
| `set-status` | 狀態值／`--clear` | 省略、互斥 | `checkStatusArguments` |
| `tag` | `--add`／`--remove` | 至少一個 | `checkTagArguments` |
| `link` | `--kind` | 值域（先前在讀 entry 之後） | `checkLinkKind` |
| `link` | `--add`／`--remove` | 至少一個（CLI 自己的檢查，從 `run()` 搬來） | — |
| `person` | key／`--name` | 空白、互斥、至少其一（最後這條先前排在兩個分支之後） | `personLookupArguments` |
| `person` | `--in-library` 與 `--name` | CLI 自己的檢查，從 `run()` 搬來 | — |
| `venue` | key | 空白 | `venueLookupKey` |
| `store-source` | `--media-type` 等四個 | 不可空白 | `checkStoreSourceArguments` |
| `add-person` | key、`--orcid` | key 格式（先前只在寫入閘）、ORCID 形狀（先前在讀 store 之後） | `addPersonArguments` |
| `add-venue` | key、`--names`、`--type`、`--issn` | key 格式（先前只在寫入閘）、type 值域、名字、ISSN | `addVenueArguments` |
| `update-venue` | `--remove-issn`、`--add-name`、`--add-variant`、`--authorize`、`--type`、`--add-issn`、`--paginated`／`--clear-paginated`／`--judgement`／`--rests-on` | 形狀、理由、重複、兩句矛盾的話、值域、rests-on（先前全在讀 store、確認 venue 存在之後） | `updateVenueArguments` |
| `update-person` | `--fields` | 欄位名在白名單內、各欄位的形狀（套在一筆空白的暫存記錄上，與服務套在既有記錄上的是同一個函式） | `checkUpdatePersonFields`／`applyUpdateFields` |
| `record-divergence` | `--candidate`、`--judgement`、`--rests-on`、`--prefers` | `key:shape`（CLI 先前另有一份一模一樣的解析，排在開 store 之後）、候選數、候選鍵格式、不可作候選的形狀、判斷與依據成對、digest、prefers 兩條 | `parseDivergenceCandidates`、`LibraryStore.checkDivergenceArguments` |
| `resolve-people` | `--judge`／`--refute` | 缺 `=`、三段形、理由空白、重複、同一作者位判給兩人 | `parseJudgeSpecs` |
| `resolve-people` | `--undecided`／`--rests-on` | 一次的上限、digest、形狀、說明、重複（format 閘仍在讀 store 那一側） | `parseUndecidedSpecs` |
| `resolve-people` | `--split-author`、`--un-split`、`--drop-author`、`--attribute-org` | 各自的形狀、理由、同一批重複 | `parseSplitSpecs`、`parseUnsplitSpecs`、`parseDropAuthorSpecs`、`parseAttributeOrgSpecs` |
| `resolve-venues` | `--repoint`、`--demote`、`--drop-venue`、`--undecided` | 形狀、同一條邊兩次、理由、一次的上限、digest | `parseRepointSpecs`、`parseDemoteSpecs`、`parseDropVenueSpecs`、`parseUndecidedSpecs` |
| `resolve-organizations` | `--undecided`、`--judge` | 一次的上限、rests-on 的 digest、連一個 `@<orgKey>=` 位置都沒有的 id（這一種與列表無關；先前排在 format 閘與 load 之後） | `checkOrgUndecidedCallArguments`、`checkOrgJudgeCallArguments`（兩者共用 `checkOrgIDSpecShapes`，`parseOrgIDSpecs` 逐筆也呼叫它） |
| `bootstrap-people` | `--json` 與 `--apply` | 互斥（CLI 自己的檢查，從 `run()` 搬來；先前排在目標確認閘與開 store 之後） | — |
| `enrich-from-zotero` | `--citekeys` | 不得為空（CLI 自己的檢查；先前排在目標確認閘之後） | — |

`resolve-people` 的腿組合檢查本來就在 `run()` 裡、早於開 store，但 `--apply` 時目標確認閘排在它們前面，而閘要解析 registry、解析失敗是 1；本輪把閘移到組合檢查之後（`resolve-venues`、`resolve-organizations` 本來就是這個順序）。

**盤點的對照**：另一份獨立的逐站清單（子代理，92 個只看參數而不在 `validate()` 的檢查）晚於第一版 commit 送達；逐項對照後補上三件——`person` 的「至少其一」、`resolve-organizations` 沒有可切位置的 id、上面兩個排在閘之後的 CLI 檢查與 `resolve-people` 的閘序。其餘各項第一版已涵蓋。

### 仍是 1 的（寫在 `RuntimeFailure` 的 doc，封閉列舉）

- `resolve-people`／`resolve-venues` 的 `--apply`／`--reject` id：要比對這次的候選列表。
- `resolve-organizations` 每一筆 id 的解析：`@orgKey=` 要在這次列表的 id 上切（沒有可切位置的那一種除外，見上表）。
- store 狀態：format 閘、記錄是否存在、citekey 是否唯一、venue 有沒有要移除的 ISSN、作者位是否已歸戶。
- 合併到既有記錄後才判得出來的：`update-person` 的 `validate()` error 與寫入閘對合併後記錄的驗證（references 指名的欄位要存在、digest 的形狀——後者只看參數，但住在寫入閘的 canary 裡）。
- 輸入檔與 stdin 的內容：`create-entry`、`enrich` 的提案檔、`update-person` 從 stdin 讀的 JSON、`store-source` 讀不到或 0 byte 的檔。

`run()` 裡仍排在開 store 之後的只看 argv 的檢查另列在 doc 的第 4 點，只剩 `query` 的關係旗標組合（刻意留著——`CLIExitCodeTests` 靠它量 `run()` 期間 `ValidationError` 的子命令 usage）。

### MCP 面

兩面拒絕的集合不變，變的是先後：一次呼叫同時有參數錯與 store 狀態不符時，MCP 面也先報參數錯（先前依迴圈順序，可能先報 store 狀態或 format 閘）。`add_person`／`add_venue` 的 key 格式先前由寫入閘擋、訊息是 store 層的，現在服務先擋、訊息具名那個 key。`mcp-cli-parity` 在 MCP 表後加一段記這件事。

## 測試

- `EmptyContentDigestTests`（9 支）：常數就是 0 byte 的 SHA-256；兩個謂詞分開；建構器、寫入閘（person／work／divergence，零寫入）、載入隔離、`enrich`、`migrate-provenance` 都拒且說 0 byte；index 指向空 blob 的那一列不是無法解析的行、`store-source` 照常可寫；fingerprint 的持久形只看形狀。
- `ServiceArgvExitCodeTests`（8 支，真 binary）：上表每一族在**沒有佈局**的目錄上都回 64、印子命令 usage、訊息是服務的原句、不被缺佈局搶先；對照組：argv 合法時仍走到開 store、回 1、不印 usage。另一支把 config 弄壞讓目標確認閘必然失敗（對照組先確認閘確實回 1），`resolve-people --apply --reject`、`bootstrap-people --json --apply`、空 `--citekeys` 的 `enrich-from-zotero --apply` 仍先回 64。
- `ServiceArgvBeforeStoreTests`（2 支，MCP 面）：服務指向沒有 store 的目錄，參數錯先於 store 狀態被報出（含 org 兩條腿沒有可切位置的 id）。

負控（改掉、跑、確認紅、反向編輯還原、`cmp` 與備份逐位元組相同）：

- `isValidDigest` 拿掉空內容那一條 → `EmptyContentDigestTests` 6 支、16 個斷言紅。
- 位址層（index 文法與 `sourceURL`）改回 `isValidDigest` → index 那一支紅（`store-source` 拒寫）。
- fingerprint 改回 `isValidDigest` → fingerprint 那一支紅。
- `argvCheck` 不呼叫 body → `ServiceArgvExitCodeTests` 6 支、176 個斷言紅（對照組照綠）。
- `updateVenue` 與 `judgeAuthorships` 先讀 store 再驗參數 → `ServiceArgvBeforeStoreTests` 2 支、6 個斷言紅。
- 三處同時失效（`resolve-people` 的閘移回組合檢查之前、`checkOrgIDSpecShapes` 不擋、`personLookupArguments` 拿掉「至少其一」）→ CLI 3 支、MCP 1 支紅，逐一對到被改的那一處。
- `bootstrap-people` 的互斥與 `enrich-from-zotero` 的空清單在 `validate()` 不擋 → 閘序那一支的這兩格紅（回 1、被壞 config 搶先）。

## 規則與文件

- `zero-instance-guards` 加一列（整合進 main 時是第 41 列；分支上寫的是 37，#658／#581／#648／#641 先進來）與它的量測段、共通段的 bullet。
- `mcp-cli-parity`：`akashic_enrich` 列補 #654（空內容 digest 整批拒絕，其他收 digest 的面同時生效）；MCP 表後加一段記參數檢查的先後。
- `docs/store-format.md`：§3.5 規則 3、§2.4 的 `akashic.sources`、「存檔佈局」補位址層只看形狀。
- `RuntimeFailure` 的 doc：第 2 點改成逐站盤點後的封閉列舉，第 4 點列出仍在 `run()` 裡的站點。

## 誠實邊界

- 那個空 blob 與它的 index 列仍在，清掉它需要一個「移除一筆存檔」的面，目前不存在（與 #544 同族）。
- `openspec/specs/provenance-reference/spec.md` 沒有改——規範文字寫進 `docs/store-format.md`；spec 要改得走 Spectra change。
- `update-person` 從 stdin 讀的 JSON 仍是 1：同一份內容從 `--fields` 給是 64、從 stdin 給是 1，那是 #549 邊界 1 的既有裁決。
- 餘項 1（`Reference*` 的 argv 站點）沒有做，等 #617 那邊的檔案釋出。
