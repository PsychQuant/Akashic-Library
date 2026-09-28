# 2026-09-28 寫入不再寫出讀不回來的檔；judge／refute 的理由有上限（#648）

讀取路徑的位元組上限是 8 MiB（`AliasEventBudget.maxBytes`），超過的檔在載入時被 quarantine：那筆記錄從所有面消失，指向它的 key 全部懸空。#645 的預警（讀取上限的一半）只在讀取面計算，管得到漸進的增長，管不到一次寫入從門檻之下直接跳過上限。#648 問的是這一步：寫入路徑的 encode canary 以 `isWritePath: true` 放寬到 2 倍，而 judge／refute 的理由沒有長度上限。

使用者 2026-09-28 裁決兩件都做：(a) 寫出的結果超過讀取上限即拒絕、零寫入，2 倍只留給不增長的改寫；(b) judge／refute 的理由與未決腿同一個上限。

## 先量出來的事：issue 的前提有一半不成立

「寫得進去、讀不回來」在 encode 層不會發生。encode 在外層 canary 以 2 倍放行之後，緊接著做語意讀回（`decode(out)`），而那一步一直以 1 倍擋著——超過 8 MiB 的產物從未落盤，只是被一句不具名的 `fileTooLarge` 擋下，訊息說的是「單一超大節點會讓 parser 耗盡記憶體」，不說是哪筆記錄。

成立的是另一半：**多檔寫入面在那道拒絕觸發之前已經有檔落盤**。`judge` 先寫 entry（作者位歸戶）再寫 person（verdict），person 被拒時作者位已經歸戶而 verdict 沒寫。`resolve-venues` 的 apply／repoint／demote、`attribute-org`、未決腿的多個 holder 都是同一個形狀。

## 改了什麼

**寫入閘（encode 層，六個 encoder 共用）**：`AliasEventBudget.checkWriteSize` 在語意讀回之前比對寫出的 UTF-8 位元組與這次寫入的上限，超過即丟 `StoreYAMLError.writeExceedsReadLimit`，訊息具名記錄（`person「key」` 這種形）、寫出的位元組、這次的上限、目的檔目前的位元組。語意讀回改走寫入路徑的預算，只驗讀不讀得回同一個值。

**「不增長」的定義**：寫出的位元組 ≤ 寫入目的檔目前的位元組（`writeByteLimit(replacing:)`；目的地沒有檔＝新建，沒有寬限）。比的是位元組不是語意。上限因此是三段：目的檔讀得回來（≤ 8 MiB）時上限就是讀取上限；目的檔在 8 到 16 MiB 之間時上限是它自己的大小（只能原樣或縮小改寫）；超過 16 MiB 時上限是 16 MiB。寬限只作用在已經讀不回來的檔上，而 entities 佈局的 #631 目的檔檢查拒絕覆寫那種檔，所以它實際只在 legacy 佈局落地。它從不把一個讀得回來的檔變成讀不回來。

**寫入端量目的檔**：`writeEntry`／`writePerson`／`writeVenue`／`writeOrganization`／`writeDivergence` 在 encode 時傳入目的檔目前的位元組。其餘 encode 呼叫端（`writeEntryExclusive`、`writeLibrary`、遷移、`fmt`、rename 與合併的 preflight dry-encode）不傳，上限就是讀取上限——省略時任何寫入者都寫不出讀不回來的檔。

**多檔寫入面先 preflight**：新的 `LibraryStore.preflightWrite`（四種形狀）跑 writeX 在寫入當下的每一道——store root、內容閘、#631 目的檔、encode 含讀取上限——而不寫檔；writeX 本身也走同一個 `plannedWrite`，兩邊不會分岔。以下各面在任何檔落盤之前對整個寫入集合逐筆 preflight：`resolve-people` 的 judge／refute、undecided、split／un-split／drop、attribute-org；`resolve-venues` 的 apply、repoint、demote、undecided；`resolve-organizations` 的 apply、reject、undecided、judge。先前這些面的前置只驗內容閘（有的連 #631 都沒驗，attribute-org 與 org 的 apply／reject 什麼都沒驗；org 的 apply 先寫 person／org／entry，verdict 那一筆最後才寫）。

**judge／refute 的理由上限**：4,096 位元組，與未決腿的說明同一個常數（`AkashicService.maxStatementBytes`）。超過即整批拒絕、零寫入、不截斷，在任何 store 狀態分支之前擋——一筆過長的理由不得因為那一格恰好被略過而回報成功。拒絕訊息指名是哪一筆、兩個位元組數。CLI `--judge`／`--refute` 的 help 與 MCP `judge`／`refute` 的描述都寫明上限。

**控制字元不另立規則**（使用者裁決）：未決的說明含控制字元時，YAML 會把它跳脫成 4 倍（一次呼叫最多約 200 × 4,096 × 4 ≈ 3.3 MB）。那是 YAML 的合法表示，由 1 倍寫入閘擋下，`WriteReadLimitTests.testUndecidedBatchIsAllOrNothingAcrossHolders` 用 1,000 個 `\u{01}` 釘住這一條（跳脫後的產物 8,390,841 位元組，超過上限 2,233 位元組）。

## 誠實邊界

- preflight 以每筆記錄 encode 兩次換零寫入。
- 有逐筆收容語意的面沒有 preflight：`resolve-people` 的 apply／reject、`resolve-venues` 的 reject。它們既有的契約是逐筆回報寫入失敗（`writeFailed`／`confirmWriteFailed`），拒絕現在具名，但仍可能部分落地。drop-venue 只刪邊、檔案只會變小，沒有加 encode preflight。
- 不經 encode 的文字層遷移（`IdentifierMigration` 的識別碼形狀升級）不受寫入閘管。
- rename 與合併的 preflight dry-encode 不傳目的檔大小，比實際寫入嚴（fail-closed）：對 legacy 佈局裡已讀不回來的檔不給寬限。
- 一筆逼近上限的記錄會在某次編輯被擋下；那之前 #499／#645 的預警（讀取上限的一半）應已先響。

## 測試

- `WriteReadLimitTests` 15 支：三段上限與「不增長」定義的逐格對照（10 × 11 格）；六個 encoder 都具名拒絕；encode 的拒絕帶記錄與兩個數；寬限只給不增長的改寫；store 寫入長過上限時檔案不動；寬限只在 legacy 佈局、對已讀不回來的檔落地，entities 佈局由 #631 擋下；judge、refute、未決兩個 holder、venue apply、attribute-org、org apply、org reject 兩個 org 把記錄推過上限時零寫入。
- `JudgeReasonCapTests` 8 支：上限就是未決腿的常數；恰在上限放行；超過一位元組整批拒絕零寫入、訊息帶 id 與兩個數；算位元組不算字元（1,366 個「查」是 4,098 位元組）；refute 同；一筆過長拒絕整批；指向不存在的 work 的過長理由仍是輸入錯；兩面的文件都寫出上限。
- `JudgeReasonCapCLITests` 3 支走真 binary：`--judge`／`--refute` 過長理由非零結束、零寫入，恰在上限放行。
- 相關既有套件（resolve-people／resolve-venues／resolve-organizations 各腿、預警、寫入閘、`SanitizationBoundaryTests`、`PackageManifestTests` 等）以 47 個套件名過濾（`swift test --filter`）跑過，全綠：AkashicKitTests 491、AkashicMCPTests 227、AkashicCLITests 109、AkashicAppKitTests 17，共 844 支、0 失敗。

**負控**（改壞、跑、以反向編輯還原並 `cmp` 確認逐位元組相同）：拿掉 `checkWriteSize` 的判斷，10 支轉紅（寫入改走 2 倍讀回，16 MiB 以內的都落盤）；拿掉寬限，5 支轉紅；把寬限放寬成「有目的檔就 2 倍」，10 支轉紅；拿掉 judge 的 preflight、把 venue apply 的 preflight 退回只驗內容閘、拿掉 attribute-org、org apply、org reject、未決腿的 preflight，各自讓對應的那一支轉紅（作者位、隸屬或另一個 holder 先落盤）；拿掉理由上限，JudgeReasonCap 兩個套件 7 支轉紅；從 `--refute` 的 help 拿掉上限，文件那一支轉紅。

## 規則與文件

- `zero-instance-guards` 加第 39 列（實作時在分支上是第 37 列，合併時排在 #658、#581 之後），附量測腳本與共通段的 bullet；第 31 列的誠實邊界更正並指向新列。
- `mcp-cli-parity` 的 `akashic_resolve_people`、`akashic_resolve_venues`、`akashic_resolve_organizations` 三列補 #648 的契約變更，裁決不變。
- `docs/store-format.md` 的 alias 預算一節，「寫入路徑放寬 2×（遲滯）」之下補位元組軸的例外。
- `StoreHealth` 的預算 warning 訊息不再說「寫入路徑有 2 倍寬限擋不住」。
- `two-kinds-of-edits` 沒有改：沒有新的寫入面，也沒有寫入面換了種類。

2026-09-28 實測 live store（唯讀）：5 族 7,637 筆記錄，最大檔 268,627 位元組（venue `psychological-methods`），超過讀取上限的 0；判定記錄最長理由 687 位元組。零實例。
