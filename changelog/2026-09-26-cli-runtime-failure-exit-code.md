# 2026-09-26 CLI 分開「命令列打錯了」與「命令列對、環境不對」（#549）

store 缺佈局是執行期的前置條件失敗，CLI 卻回 `exit 64`（`EX_USAGE`）並印 top-level 的 `Usage: akashic <subcommand>`。issue 回報時，這讓人以為是旗標打錯，多跑了兩次 `--help`；以 exit code 分支的腳本也分不出這兩件事。

## 做了什麼

- 新增 `RuntimeFailure`（`Sources/akashic/RuntimeFailure.swift`）：走頂層的一般錯誤路徑，印 `Error: <訊息>`、exit 1、不印 usage。
  - 它自帶消毒（`SanitizedErrorDescription`），payload 在擲出端逃一次，與 `ValidationError` 同一條紀律。
  - 做成 enum，讓 `SanitizationBoundaryTests` 的「擲出站點逐 payload 比對」自動涵蓋每個站點。負控：拿掉一處的 `displaySafeInvisible`，守衛點名那一行。
- `run()` 裡拋出的 `ValidationError` 仍回 64，但改印**該子命令**的 usage 與 `See 'akashic <子命令> --help'`。之前 ArgumentParser 用根命令渲染它；parse 階段的錯誤本來就是子命令 usage，這裡補成同一個形狀，巢狀命令也印完整路徑（`akashic library create`）。

## 判準與逐站歸類

判準是一個可獨立驗證的性質，寫在 `RuntimeFailure` 的 doc：**只看解析後的 argv 就判得出來 → `ValidationError`；需要讀 argv 以外的任何東西（檔案系統、檔案註冊表與 config、store 內容、服務層回應、輸入檔內容）→ `RuntimeFailure`。**

2026-09-26 對 `Sources/akashic/` 的 `ValidationError` 站點逐一歸類。全樹 78 個，其中 10 個在 #617 範圍的 `Reference*` 三個檔、本輪不動，所以在範圍內的是 68 個：改成 `RuntimeFailure` 的 41 個，留下 27 個。（初版寫「留下 37 個都是只看 argv 的」，把那 10 個也算進去了，而其中幾個會讀檔——R1 verify 更正。）改成 `RuntimeFailure` 的 41 個：

| 類 | 站點 |
|---|---|
| store 佈局與 library 解析 | `CLI.swift` 的 `openStore` 缺佈局、`resolved()` 的 registry 解析失敗 |
| 檔案註冊表與 config 的狀態 | `FileCommands.swift` 的 key 已存在／路徑已註冊／key 未註冊（兩處）／註冊路徑不是 library；`LibraryCommands.swift` 的 library 已存在；`Commands.swift` 與 `ViewCommands.swift` 的「config.yaml 沒有 view」 |
| 外部檔案不在 | 找不到 zotero.sqlite（`Commands.swift`、`EnrichFromZoteroCommand.swift`）、找不到提案檔（`EnrichCommand.swift`） |
| 輸入檔內容 | `CreateEntryCommand.swift` 的 12 處（非 UTF-8、零筆、JSON 形狀、大括號未閉合……）、`EnrichCommand.swift` 的提案檔解析錯誤 |
| store 內容決定的結果 | `Commands.swift`：citekeys 不存在、`--holder`／`--org` 或 `--citekey`／`--person`／`--tier` 沒有命中任何候選（三處）、套用集含寬鬆提名層、套用集沒有可套用的候選 |
| 包裝的執行期錯誤 | `Commands.swift` 的 migrate、`LibraryCommands.swift`（寫入失敗與兩處包裝）、`EnrichCommand.swift` 的服務錯誤 |
| 服務層回應形狀不符（內部錯誤） | `PersonDivergenceCommands.swift`、`GetEntryCommand.swift`、`PersonCommand.swift`、`PeopleCommand.swift` |

留在 `ValidationError` 的 27 個都是只看 argv 就判得出來的：旗標組合、值的格式（UUID、StoreKey、`--tier`、`--rows`、候選 `key:shape`）、必填旗標、目標確認閘（只看有沒有 `--library`／`--yes`）、`migrate-venue-variants --apply` 的拒絕。

兩處邊界值得寫出來：
- ~~`update-person --fields` 留在用法錯誤：JSON 就是旗標值本身，stdin 只是同一個值的另一種送法。~~ R1 verify 指出這與判準矛盾（stdin 是 argv 以外），而且讓 `update-person` 與 `create-entry` 對同一個 stdin 壞 JSON 回不同的 code。R1 起拆成兩條：`--fields` 格式不對 → 64，stdin 內容不對 → 1。
- 「套用集含寬鬆提名層」歸執行期：它要看 store 裡的候選才判得出來，雖然修法是加一個旗標。判準看的是**判斷需要什麼**，不是修法在哪裡。

**沒有動的**：`Sources/akashic/Reference*` 三個檔（`ReferencesCommands.swift`、`ReferenceNominator.swift`、`ReferenceListExtractor.swift`）屬另一個 session 的 #617 範圍。其中讀檔失敗與 contract 版本不符那幾處依判準也該歸執行期，留給那邊處理。

## 測試

- `CLIExitCodeTests`（真 binary）：
  - issue 的四個命令在缺佈局時回 1、不印 usage；
  - `query` 的旗標組合錯誤回 64、印 `Usage: akashic query`；
  - 巢狀子命令印完整路徑；
  - parse 錯誤維持原樣。
- 負控：`openStore` 改回 `ValidationError`，同時拿掉子命令 usage 那段，3 支測試、12 個斷言失敗；對照組照綠。
- `AkashicCLITests` 全部 330 支通過。沒有既有測試斷言 exit 64。
- `SanitizationBoundaryTests` 釘住的四個包裝站點 needle 改成新型別。

## R1 verify 之後（6 席，0 HIGH、10 MEDIUM）

- **只看 argv 的檢查搬進 `validate()`**：
  - `library create`、`library add`、`library remove` 的 key 格式；
  - `resolve-people --tier` 的值域；
  - `update-person --fields` 的格式。

  `validate()` 在 `run()` 之前執行，所以早於開 store。先前 `library create` 的 key 檢查排在開 store 之後，store 缺佈局時先報執行期失敗；而 `library add`／`remove` 把 key 檢查交給服務層，被包成 1。DA 實測：同一個 `"Bad Key"` 在 create 回 64、在 add 回 1。
- **`update-person` 的 stdin 例外拿掉**：`--fields` 格式不對 → 64；stdin 內容不對 → 1，與 `create-entry` 同一類。
- **`RuntimeFailure` 的 doc 寫明四個邊界**：stdin 算 argv 以外；服務層做的輸入驗證會被包成 1；exit 1 與「跑了、發現問題」共用；只看 argv 的檢查要放在 `validate()`。
  - 服務層那一格沒有逐站盤點，記在 #654。
  - exit 1 共用是一個選擇：#549 要求的是不回 64，本輪不再細分成 sysexits 的 66／78。以 exit code 分支的腳本分得開「用法」與「其他」，分不開「沒跑起來」與「跑了有問題」；後者要讀訊息。
- **Reference* 三個檔的站點**交給 #654 追蹤，不只寫在這份 changelog 的散文裡。依判準應歸執行期的有：讀不到 `--text`、`--refs` 的 contract 版本不符、`--openalex` 讀不到。
- **判準取代封閉表**：issue 的 Expected 第三項寫的是「一張封閉表的形狀，不是總括判準」。本輪兩者都給：
  - 判準是一個可獨立驗證的性質（全域 `common-spec-prose-enumeration` 允許的那一種）；
  - 上面那張逐站表是它在 2026-09-26 的封閉展開。
  - 這個選擇在 #549 的 comment 裡記為裁決。
- 過期註解：`CLI.swift` 與 `TerminalOutputSafetyTests` 提到「五個 `ValidationError` 包裝」的兩處，改成現在的型別。
- 測試（`CLIExitCodeTests`）：
  - `testArgvOnlyChecksRunBeforeTheStoreIsOpened`：五個情形在 store 缺佈局時仍回 64、印子命令 usage。負控：四處 `validate()` 改成空的，12 個斷言失敗。
  - `testUpdatePersonStdinContentIsARuntimeFailure`。
- 這支測試檔的沙箱補上 `AKASHIC_HOME`。akashic 找 registry 只認它，`HOME` 被忽略；同一天 verify 的 DA 席照「用假的 HOME」跑，真實 registry 被寫進一行並被切走 `current`，已還原。
