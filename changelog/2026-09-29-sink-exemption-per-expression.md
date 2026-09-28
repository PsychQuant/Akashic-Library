# 2026-09-29 sink 守衛的豁免改成逐運算式，與擲出站點守衛共用一份規則（#584）

`DisplaySinkCoverageTests` 的豁免是整行毯式：`if l.contains("display-safe-exempt:") { continue }`。一句註記讓該行所有運算式免檢，不論註記具名的是哪一個。這是 #554 R30 verify 對擲出站點守衛判為缺陷的同一個形狀（74/540 站點在毯式豁免下）；R31／R32 把擲出站點守衛改成「只有註記具名的識別字免檢」，sink 守衛沒動（R32 verify regression 第 37 列）。結果是兩支守衛對同一個標記給出兩種粒度，而 sink 的掃描面比擲出站點大——CLI、MCP、App 三個面都在裡面。

一個真的未消毒的運算式與一個安全的運算式並排在同一行、註記只講後者時，前者靜默免檢。今天沒有已知的真實例；缺的是守衛，不是一個洩漏。

## 改了什麼

- **一份規則，兩支守衛共用**：`Tests/AkashicKitTests/DisplaySafeExemption.swift`（新）。規則是 R31／R32 的那一條：只看標記之後的文字；一個運算式被豁免，當且僅當它的**第一個識別字**以完整字詞出現在那段文字裡。三件事在取「第一個識別字」之前先取運算式的主詞（封閉列舉）：開頭的 `return`／`try`／`await` 不算；整條是 `displaySafeClipOnly(x, max: …)` 時主詞是載體 `x`（那個函式只截不逃，註記要擔保的是載體已消毒，不是函式名）；以字串字面開頭的運算式逐段對照（每個非字面運算元、字面裡的每個插值各自被具名）。
- `DisplaySinkCoverageTests.scanViolations`：整行跳過改成 `DisplaySafeExemption.names(expr, in: notes)`。帶註記的行先剝掉行尾註解再分類、再抽運算式——先前這一行從沒被看過，現在走完整條判準，註記裡的 `print(` 不得把非 sink 的行變成 sink。
- `SanitizationBoundaryTests.testEveryThrowSiteEscapesEachPayloadExactlyOnce`：自己那份 `notes` 與 `exempted` 換成同一個 helper。行為差異只有一處，且只放寬到「載體具名」：`displaySafeClipOnly(x, …)` 引數過去要具名函式名，現在具名 `x`（該守衛全綠，沒有站點靠舊寫法過關）。
- **註記要逐條具名**：守衛改嚴之後，2026-09-29 在 `def4ce7c` 上實測 **191 個運算式、162 行、44 個檔**沒被具名（issue 在 `58bab46d` 量到 161，其後新增的程式帶進更多）。每一條逐一判讀，沒有一條是真的未消毒 store 字串進 sink，所以全部是改註記，沒有改任何執行碼。粗分（依運算式的形狀分桶，桶界是機械規則不是逐條人工歸類）：
  - StoreKey 受 load 端驗過的 key、回程把手（`rowID`／`pinnedID` 必須逐字，消毒會讓 apply 對不上）、比對鍵：46
  - 生產端已消毒的訊息與 helper 回傳值、資料面（sink 端才消毒）、序列化面（JSON 的消毒層是序列化器）、內部比對鍵：54
  - Int、Bool、計數、dict 查找取到的 Int：41
  - 編譯期常量、封閉列舉的 `rawValue`、`StoreKey.pattern`、字面：25
  - `displaySafeClipOnly(x, …)` 的載體（已消毒、只截）：16
  - `UUID.uuidString`：9
  每一條註記在原文字前面加上被具名的運算式（`entry.citekey：…`、`idx 是 Int`、`$0.issue.message：…`）；原理由一字不刪，其他守衛要求的字樣（`已消毒`、`未消毒`）都還在。少數本來就不是「訊息」的行寫出了它們是什麼：`flipFamilyGiven` 回傳的是作者姓名本身（會存進 `Entry.authors`），`WriteGateRulings` 的 `.notGated("…")` 是編譯期字面。
- 文件：`DisplaySinkCoverageTests` 的檔頭、失敗訊息的修法指引、strip-all 那一段對「被豁免的站點看不見」的說法，與 README 的輸出消毒一節同批更新。

## 測試與負控

新增 `DisplaySafeExemptionTests`（6 支）釘 helper 本身：註記只取標記之後的文字、第一個識別字以完整字詞比對（`id` 不被 `identity` 具名、`$0` 是識別字元）、關鍵字不是主詞、`displaySafeClipOnly` 由載體具名、字串字面逐段對照，以及「兩支守衛都呼叫這一份」的結構釘。`DisplaySinkCoverageTests` 加 4 支：兩個 tainted 運算式並排、註記只具名其一；只有標記之後的文字算具名（含註記裡的 `print(` 不得讓非 sink 的行入列）；clipOnly 要具名載體；同一物件兩個成員共用豁免的已知邊界（釘成斷言）。

負控（反向編輯，還原後逐檔比對確認相同）：

| 反向編輯 | 轉紅的測試 |
|---|---|
| helper 的 `names` 一律回 true | `DisplaySafeExemptionTests` 4 支、`DisplaySinkCoverageTests` 3 支 |
| sink 守衛的豁免改回整行（有註記就 continue） | 新增的 3 支 sink 測試 |
| helper 的 `notes` 取整行而不是標記之後 | helper 的註記抽取測試、3 支 sink 測試 |
| sink 守衛不剝行尾註解 | 「註記裡的 `print(`」那支 |
| helper 不拆 `displaySafeClipOnly` | helper 與 sink 各一支，外加真實原始碼掃描（大量註記具名的是載體） |
| 拿掉一條真實註記裡的具名（`EntryViews.swift` 的 `entry.citekey：`） | `testNoUnsanitisedStoreStringReachesUserVisibleOutput`，恰報那一行 |
| 真實原始碼裡一個具名安全運算式（`idx 是 Int`）旁邊加一個裸 `\(citekey)` | sink 守衛（恰報 `citekey`）與擲出站點守衛（同一句）都紅；整行豁免會讓 sink 守衛放行 |

## 誠實邊界

- **粒度是第一個識別字，不是成員路徑。** 同一行的 `entry.citekey` 與 `entry.title` 共用 `entry`，註記具名其一就兩個都放行——而「同一個物件的另一個成員」恰好是最自然的夾帶形狀。這是 issue 指定的粒度（與擲出站點守衛同一條），本輪沒有收緊。用一個暫時的記錄器量過：兩支守衛的 461 次具名放行裡，440 次的註記寫出了運算式的完整成員鏈，其餘 21 次只寫到物件名或去掉尾端方法呼叫的鏈（`v.names.entries.map`、`stage.rawValue` 之類）；收緊到成員層級大約要改二十條擲出站點那一側的註記。`testKnownBoundaryMembersOfTheSameObjectShareAnExemption` 把今天的行為釘成斷言，收緊時它會紅、提醒回來改這一節與 `DisplaySafeExemption` 的型別 doc。
- 註記仍然要在**同一行**。多行語句的註記與運算式在不同行時，運算式要在自己那一行具名。
- **同族的另外幾個守衛仍是行級**：`SanitizationBoundaryTests` 裡 `testErrorToTextEntriesGoThroughTheSingleEntryPoint`（行上有標記就整行跳過）、`testSanitizedCarrierSinksOnlyClip`（標記加「未消毒」）、`InvisibleEscapeCoverageTests`（`displaySafeClipOnly(` 那一行要有標記加「已消毒」）。它們各自掃的不是「一行裡的多個運算式」（每行至多一個入口），本輪沒有動；若日後某一行長出第二個入口，要一起改成走 `DisplaySafeExemption`。
- 這 191 條的判讀依據是各條註記原本的理由與對應的生產端／sink 端程式（抽查：`verdictsCollapsed` 在 CLI 的 merge／rename 報告與 App 的 rename 報告都過 `displaySafeInvisible`、`LibraryMembershipViolation.message` 的每個 store 字串逐項消毒、venue 的文章清單逐欄 `displaySafe`）；沒有對 191 條逐條重跑資料流，那是這支行級守衛從來沒有的能力。守衛全綠仍不等於這一面安全（見 README 的盲區清單）。
