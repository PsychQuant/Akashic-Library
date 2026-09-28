# 2026-09-28 寫不進去的記錄在 load 時就標出來，多檔寫入者不再寫到一半才被拒（#641）

#631 讓 `writeEntry`／`writePerson` 在寫入當下檢查目的檔：同一個 id 的 legacy 拷貝與 `entities/` 檔兩份並存、目的檔被隔離或其實是另一種記錄時拒寫；只有 legacy 一份時改為搬移，但那一份的 key 對不上、不受 git 追蹤或有未 commit 的修改時也拒寫。

這些拒絕本身是對的，問題在**發生的時間**。多檔寫入者一次寫好幾個檔，拒絕若出現在中途，前面幾筆已經落盤、store 被撕成一半。#631 R2 verify 以真 binary 重現了五處：resolve-people 的 `--judge`（作者位已升格、verdict 沒寫）與 `--refute`（逐筆寫到一半）、resolve-organizations 的 apply、resolve-venues 的 `--repoint`／`--demote`，以及 `migrate-identifiers`——最後一處讓 ISSN 從 work 移除卻沒寫進 venue，重跑也救不回。

## 裁決

使用者 2026-09-28 採 issue 提的結構解：**在 load 時就把這類記錄標成「無法唯一定位」**，併進 `unlocatableCitekeys` 的定義。#627／#628 已經在各面接好的閘因此在第一次寫入之前拒絕或略過它們；寫入當下的 #631 檢查留著，當最後一道防線。

## 改了什麼

**load 時的判斷用的是 #631 的同一組前置，不另寫一份。** `entitiesWritePlan` 拆出 `legacyMoveCandidate`（legacy 那一半、不含 git），load 對每一筆讀進來的 work／person 跑 `assertEntitiesDestination` 與 `legacyMoveCandidate`，git 對整批搬移候選只呼叫一次 `filesNotSafelyRecoverable`。答案記在記錄旁的 `FileSituation.unwritableReason`：它不是記錄內容，所以不序列化、不參與相等（WoS 的「unchanged」判定、`changedSlots`、org apply 的「有沒有改到」都比內容）。只有 `entries/` 或 `people/` 裡真的有 YAML 時才判斷——live store 的 legacy 殘留是 0，所以零成本。`decodeCaptured` 的唯讀快照不判斷：它的契約是不重讀磁碟，也沒有寫入者。

**作品側**：`unlocatableCitekeys` 從兩類變成三類（citekey 重複、與另一筆共用 id、檔案寫入時會被拒）。resolve-people、resolve-venues、resolve-organizations 的作者位列、library、tag／link／set-status、enrich 一族、split／un-split／drop／attribute-org 一行不改就拿到第三類。

**person 側新增 `unlocatablePersonKeys`**，兩類：person key 重複、檔案寫入時會被拒。作品側的「共用 id」刻意不收——index 的 people 表以 key 為主鍵，共用 id 不會讓 rebuild 丟掉一筆；entities 佈局下兩筆 person 不可能都住在 `entities/`（檔名就是 id），所以共用 id 必然有一筆是 legacy，那一筆寫入時會被 #631 拒、已經落在第二類；另一筆寫的是它自己的檔，收進來只會多擋住一筆寫得進去的記錄。中途版本曾收了第三類，結果擋住了一份 legacy 佈局測試夾具裡兩個不同 key 共用 id 的 person（寫入以 key 定檔，其實安全），於是拿掉。

接上 person 集合的寫入者，各沿用自己對 `unlocatableCitekeys` 的既有處置：

- resolve-people：`--apply`／`--reject` 整批拒絕、零寫入；`--judge`／`--refute`／`--undecided` 該筆具名略過、其餘照寫；CLI 的篩選式 `--apply` 排除並另列；MCP 列表以 `unlocatablePersonKey` 標出。
- resolve-organizations：以 person 為 holder 的候選（隸屬）同上——apply／reject 整批拒絕、judge／undecided 該筆略過、列表標 `unlocatablePersonKey`，CLI 篩選式批次排除。`OrgResolver.apply` 自己也不改這些 person（最後一道防線，同 `PersonResolver.apply` 的形）。
- App 裁決台的 accept：`AdjudicationError.unlocatablePerson` 具名拒絕。
- authorize-names：`--apply` 的寫入集合裡有無法唯一定位的就在第一次寫入之前整批拒絕。順手把「要寫哪幾筆」算成一份清單再寫——先前 #641 的中途版本用一份複製出來的條件去猜要寫誰，那是同一件事的第二份描述。

**MCP 的 org apply 只寫真的改到的記錄，並先驗整個寫入集合。** 先前它重寫全庫每一筆 person 與 organization，所以與這次候選毫無關係、排在後面的一筆寫不進去時，前面已經寫了隸屬歸戶、verdict 卻沒寫。現在逐位置比對出改到的 person／organization／work，照 `judgeOrganizations` 的既有形在寫入前跑內容閘與 #631 的目的檔檢查。`peopleRewritten`／`organizationsRewritten` 改數真的改寫的筆數（先前前者是全庫筆數、後者漏算上級機構被改寫的 org）。CLI 的篩選式 apply 本來就只寫改到的、逐筆收容。

**migrate-identifiers**：無法唯一定位的 work 整筆列進 blockers、不寫，與既有的「落點 venue 寫不進去」「檔案未受追蹤」同一種處置。它的 ISSN 照樣進 venue 計畫，所以號不會消失，只是 work 上的殘留留著。

**import-wos**：回填（只多不少）要改寫既有記錄，寫之前先問它能不能唯一定位；不能的那一列具名進 `skippedRows`、零寫入、其餘照跑。先前寫入當下被拒時整趟匯入擲出、前面幾列已落盤而報告隨 throw 丟掉；共用 id 的那一格更糟，改寫的是兄弟的檔。

**validate 看得到**：`crossRecordIssues` 對每一筆寫入時會被拒的 work／person 報 warning，說出原因（#631 的那一句）與處置。兩份並存時 load 讀到兩筆、原因相同，同一則只出一次。warning 不是 error：記錄讀得到、內容完好，擋的是寫入；升 error 會讓 `assertNoCrossRecordErrors` 擋下不相干的改名與合併。

**「無法唯一定位」說成一句話**：`UnlocatableReason.work`／`.person` 是 AkashicCore 的兩個常數，二十幾處拒絕與略過訊息、MCP 工具描述、CLI help 都用它。先前每個面各寫一句「citekey 重複或與另一筆 work 共用 id」，第三類加進來之後那句話對它是假的，而二十幾份副本不會一起改。`SanitizationBoundaryTests` 的 programBuilt 表與 `DisplaySinkCoverageTests` 各認得這兩個完整的成員名（常數字面，不是 store 字串）。

## 測試

新檔 `LoadTimeUnlocatableTests` 16 支，每一支寫入者測試都造雙重損壞（legacy 殘留加上未受 git 追蹤、目的檔被隔離或兩份並存），斷言受損記錄的檔案一個位元都不動：

- 定義：三種損壞形都算、受 git 追蹤且乾淨的 legacy 單份不算（它照常被搬移）；person key 重複算、共用 id 單獨不算；entities 佈局下共用 id 只擋 legacy 那一筆；沒有 legacy 殘留時不標任何記錄；檔案處境不參與相等；validate 逐筆報 warning、兩份並存只報一次。
- 寫入者：judge、refute、apply／reject（與列表的 `unlocatablePersonKey`）、undecided、org 的 apply／reject／judge／undecided、org apply 不碰無關的受損 person 且歸戶與 verdict 一起落地、venue 的 repoint／demote／drop_venue／apply、migrate-identifiers（號進 venue、受損那筆不動、健康那筆照遷）、authorize-names、import-wos（受損那列略過、新的一篇照建、沒寫出第二份）。

另加：`AdjudicationTests.testAcceptRefusesAnUnwritablePersonBeforeAnyWrite`（App 面）、`ResolveVerdictCLITests.testFilteredApplyExcludesAnUnwritablePersonAndWritesTheRest`（CLI 面，真 binary、`AKASHIC_HOME` 指到暫存目錄）。

改寫兩支既有測試，理由都是夾具：`OrgJudgeLegTests` 那支本來用一筆未 commit 的 legacy work 驗「寫入前的整批驗證」，現在那筆在 load 時就被標出、該筆具名略過、其餘照寫（store 狀態不符＝逐筆略過，judge 的既有契約），測試改名並改斷言；`ServiceTests` 的逐筆收容測試原本把凍結記錄放在 legacy 目錄，現在移到 `entities/`——它要驗的是寫入當下的收容，記錄得走得到那一步。

負控四輪，各自以反向編輯還原並與備份逐位元組比對：

1. 關掉 load 時的判斷：14 支轉紅（兩面的定義與全部依賴第三類的寫入者測試；仍綠的是依賴第一、二類的 migrate-identifiers 與只寫改到的 org apply）。
2. 只拿掉作品側的第三類：4 支轉紅（定義、venue 各腿、WoS、改寫過的 `OrgJudgeLegTests`）。
3. 逐一拿掉各寫入者的 person 閘、migrate-identifiers 與 WoS 的閘、validate 的 warning、org apply 的「只寫改到的」、CLI 的排除：12 支轉紅，每支對應自己那一道。
4. 只拿掉 person 側的第二類：10 支轉紅。

## 誠實邊界

- **load 到寫入之間檔案處境會變**（有人在中間 commit 或刪檔）。那一段的撕裂本輪擋不住，寫入當下的檢查仍是最後一道防線。
- **沒接的寫入者，逐一點名**：`import-zotero` 與 `migrate-provenance` 是逐筆收容，每筆一個檔、寫入當下的拒絕逐筆回報，不撕裂，所以沒接；`fmt` 與 `migrate-person-identity` 直接寫檔、不經 #631；`update-person`／`add-person` 一次寫一個檔。
- **判斷的前提是 legacy 殘留**：organization 與 venue 沒有 legacy 佈局，不判斷；format 1 的 store 裡 legacy 目錄是正典位置不是殘留，也不判斷。
- **處置是人的**：validate 說哪一筆、為什麼；把 legacy 檔 commit（之後寫入會搬移它）、刪掉兩份裡的一份、或修好被隔離的目的檔，工具不替人選。

## 規則與文件

`zero-instance-guards` 加第 40 列（零實例：live store legacy 殘留 0，附可重跑的量測）與共通段的一條；`mcp-cli-parity` 的 `akashic_libraries`、`akashic_import_wos`、`akashic_resolve_people`、`akashic_tag`、`akashic_resolve_venues`、`akashic_resolve_organizations`、`akashic_enrich_from_zotero`、`akashic_enrich` 與 CLI-only 表的 `migrate-identifiers`、`authorize-names` 各補一句；`entity-shape-label` spec 的 #631 那條 Requirement 補 load 時的判斷與一個 Scenario。
