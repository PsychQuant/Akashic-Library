## Why

#825：一篇作品的全文 PDF 存進 `sources/`、連回條目之後，library 以外需要這份 PDF 的地方（例如某個研究專案的參考文獻資料夾）目前只能自己 `cp`。2026-11-20 的一批，五份副本是從 `akashic fulltext take` 的暫存檔複製的、檔名手取（其中一個先照錯的標題命名），事後比對 sha256 才知道與條目連著的 digest 相同——流程裡沒有任何一步會發現它不同。使用者的原話（2026-11-20 18:21 +08:00）：「每一個pdf在library要有一個原版，然後原版可以匯出到外面，向這編reference應該是要員版匯出，這樣才能保證版本不要錯誤吧」。

維護者 2026-11-21 17:05（+08:00）對 issue 上四個問題的答覆（#825 留言 7062309420），本 change 照它寫：

1. 一篇作品有不只一份 PDF 時，正式版（version of record）優先作為原版；其他版本留著，但預設不匯出。
2. 匯出的檔名由 Akashic 依固定規則產生（例如作者－年份－短標題），另有參數可以覆寫。
3. store 記下每一次匯出的目的地與 digest，之後找得到過期的副本。
4. marker 轉出的 Markdown 記下它轉自哪一份 PDF 的 digest（以及 marker 的版本），並與 PDF 一起匯出。

## Current behaviour

以下每一條都讀過程式或文件，不是只照 issue 的敘述（讀的是 `origin/main` 82c63451）：

- **全文的位元組只在 `sources/`**：內容定址、無副檔名、不進 git（`Sources/AkashicStoreIO/SourceStore.swift` 第 5–15 行、第 158–268 行）。每份內容在 `sources/index.jsonl` 有一列取得記錄，欄位固定是 `content`、`bytes`、`media-type`、`retrieved`、`origin`、`acquisition`、`note`（同檔第 284–303 行；`docs/store-format.md` 第 1478–1486 行）。index 只增不改，同一個 digest 以第一列為準（同檔第 338–339 行、第 362–378 行）。
- **index 列沒有「版本」欄位**：正式版、作者稿、預印本只寫在 `note` 的自由文字裡，由 skill 規定寫法（`plugin/skills/akashic-fetch-fulltext/SKILL.md`〈5. 存進 store〉：「版本：version of record / author manuscript / preprint」）；程式不讀 `note`。`akashic fulltext take` 的驗證只標得出補充資料（`flags` 的 `supplement`，`Sources/AkashicSkillTools/FulltextVerify.swift` 第 390 行），分不出正式版與作者稿。
- **條目連著的是一串 digest，沒有角色**：`akashic.sources` 只是 digest 清單（`openspec/specs/entry-source-reference/spec.md`；寫入面 `Sources/AkashicMCPKit/EntryUpdate.swift` 第 330–369 行）。
- **連著不只一份 PDF 時，現有唯一要挑一份的讀取面不猜**：`fulltext text` 的 `FulltextReconcile.chooseSource` 取 index 記為 `application/pdf` 的那一份，不只一份（或有判不出種類的）就拒絕並列出各 digest，要 `--source` 指定（`Sources/AkashicSkillTools/FulltextReconcile.swift` 第 28–77 行）。
- **沒有把存檔寫到外面的命令**：CLI 的子命令表（`Sources/akashic/CLI.swift` 第 91–126 行）與匯出有關的只有 `export-bib`、`export-tables`；MCP 的 `akashic_export` 匯出的是 .bib／CSL-JSON（`Sources/akashic-mcp/Server.swift` 第 112–117 行）。`grep -rniE 'export-source|exportSource|source-export|exports\.jsonl|export_source' Sources plugin docs openspec .claude` 零命中（2026-11-21）。
- **現有兩種寫輸出檔的閘，規則不同**：`fulltext take` 的 git 閘在輸出目錄有 git 祖先時要求那個 repo 忽略最終檔名與暫存檔名，忽略了就放行；寫入是同目錄暫存檔加原子替換（`Sources/AkashicSkillTools/FulltextTake.swift` 第 21–30 行、第 188–230 行）。`fulltext text` 的 `checkOutput` 對任何 git 工作樹一律拒絕、目標必須還不存在、獨佔建立、不跟隨 symlink（`FulltextReconcile.swift` 第 96–127 行）。下游專案的參考文獻資料夾通常在一個 git 工作樹裡、被該樹忽略——只有 `take` 的規則放得進去。
- **在場檢查只比大小**：`sourcePresence` 比位址上的檔與 index 記的 `bytes`，「大小相同而內容不同的看不出來」（`SourceStore.swift` 第 397–398 行、第 412–448 行）。
- **Akashic 沒有任何 Markdown 轉檔的程式**：`grep -rniE 'marker[^a-z]' Sources plugin docs .claude` 再篩 `markdown|\.md|pdf|轉`，命中的都是 store format marker 或 `.gitignore` 標記區塊，沒有 marker（PDF 轉 Markdown 的工具）的呼叫或記錄（2026-11-21）。
- **機器本機的帳已有先例住在 store 之外**：每日嘗試帳本在 `$HOME/Library/Application Support/akashic/`，理由是預設 store 的根同時是資料 git repo 的根（`Sources/AkashicSkillTools/FulltextAttemptLedger.swift` 第 12–18 行）。`sources/` 整個被 store 的 `.gitignore` 排除；`index.jsonl` 依 #262 裁決「SHOULD 被追蹤」，但 store 端的 `.gitignore` 改動不由本 repo 執行（`docs/store-format.md` 第 1534–1584 行）。
- **skill 的流程停在連回條目**：`SKILL.md` 第 5、6、7 步是存進 store、連回記錄、回報，沒有一步說 library 以外的副本怎麼來。

## What Changes

- 新 capability `source-export`：
  - 寫明一篇作品全文 PDF 的**原版**是 `sources/` 裡、連在它 `akashic.sources` 上的那一份；library 以外的副本一律由匯出入口從原版寫出。
  - 一篇作品連著幾份 PDF 時哪一份是原版：封閉表（補充資料不算候選；候選只有一份、或候選裡恰好一份是正式版時才自動選；其他情形拒絕並列出，要指名 digest）。
  - index 列可以記一個結構化的版本（`version`，封閉值域），由 `store-source` 寫入（開放問題 Q1 的建議預設）。
  - 匯出入口（CLI 與 MCP 兩面）：給 citekey（或只連在一篇作品上的 digest），把原版的位元組寫到指定的目錄；寫之前重算 digest，對不上就不寫。
  - 檔名規則：預設 `<citekey>.pdf`，非原版 `<citekey>.<digest 前 12 個十六進位>.pdf`；可用參數覆寫（Q2）。
  - 目的地閘沿用 `fulltext take` 的 git 閘；目的地已有檔時的處置（Q4）。
  - 每一次匯出在 `sources/exports.jsonl` 追加一列：時間、citekey、digest、是原版還是指名的、目的地、檔名、結果（Q3）。
  - 唯讀的過期檢查：逐列回報副本現在與記錄相同、內容不同、不在，或原版已換（Q5）。
  - marker 轉出的 Markdown 以 `store-source` 存進 `sources/`、index 列記 `derived-from` 與 `converter`；匯出 PDF 時一起寫出、記在同一列（Q6）。
  - `akashic-fetch-fulltext` 存好、連好之後，library 以外的副本一律走匯出；`writing-to-the-store.md` 寫明原版的定義。

## Non-Goals

- 不改取得全文的流程（`fetch`、`take`、`store-source` 的既有驗證都不動），只在它們之後加一步。
- 不刪除、不改寫 library 以外的任何檔：過期檢查只報告，不替使用者換掉或刪掉副本。
- 不回頭處理已經放在下游資料夾裡、不是由匯出寫出的副本（issue 的 Actual 提到的 16 份）：它們沒有匯出記錄，本 change 不提供「認領」既有副本的入口；要不要做另開 issue。
- 不讓 Akashic 自己執行 marker（Q6 的建議預設）；也不轉換、不改寫 Markdown 的位元組。
- 不匯出不是 PDF 也不是 PDF 衍生 Markdown 的存檔（API 回應、網頁）。

## Open questions for the maintainer

規格裡寫的是每一題的建議預設；維護者選了別的，對應的 requirement 與 tasks 跟著改。

| # | 問題 | 建議預設 | 依據 |
|---|---|---|---|
| Q1 | 條目沒說哪一份是哪個版本時，「正式版」從哪裡判 | index 列新增選填欄位 `version`，值只有 `version-of-record`、`accepted-manuscript`、`preprint`、`supplement` 四種；沒有這欄＝版本未知；不解析 `note` 的自由文字。之後由 `store-source` 寫；**既有列要補上，得靠 #824 的更正列能改這一欄**——#824 的建議預設只更正 `note`，兩題要一起定 | `note` 是自由文字、程式不讀（SKILL 第 5 步）；`chooseSource` 遇到多份就拒絕、不猜 |
| Q2 | 檔名規則、撞名、非 ASCII；只給 digest 時怎麼命名 | 原版 `<citekey>.pdf`；非原版 `<citekey>.<digest 前 12 hex>.pdf`；Markdown 用同一個主檔名配 `.md`。citekey 的文法是 `^[a-z0-9][a-z0-9-]*$`、在一個 store 裡唯一，所以預設檔名只有 ASCII、作品之間不撞名（撞到的只會是目的地已有的檔，見 Q4）。覆寫參數收一個檔名（不得含 `/`、不得是 `.` 或 `..`），非 ASCII 照原樣、不轉寫。只給 digest 時：那份 digest 恰好連在一篇作品上才收、用那篇的 citekey；沒連或連在多篇上就拒絕 | `Sources/AkashicCore/Models.swift` 第 1043 行的 citekey 文法；本 store 的 citekey 慣例是作者＋年份＋短標題，但文法本身不保證這個形狀 |
| Q3 | 匯出記錄放在哪裡、記哪些欄位 | `sources/exports.jsonl`：在 store 裡（照答覆 3 的「store 記下」），又跟著 `sources/` 被 git 排除——記錄含本機的絕對路徑，不該隨 store 推上 remote。寫之前照 index 的同一道 fail-closed 排除驗證。欄位：`at`（ISO 8601 帶 offset）、`citekey`、`digest`、`role`（`pdf`／`markdown`）、`selection`（`original`／`named`，過期檢查要靠它分辨指名匯出的非原版）、`destination`（目錄的實體絕對路徑）、`file`（檔名）、`outcome`（`written`／`already-present`／`replaced`）、取代時另加 `replaced`（被換掉那份的 digest） | 每日嘗試帳本住在 store 之外的理由（`FulltextAttemptLedger.swift` 第 12–18 行）；`sources/` 被排除（`docs/store-format.md` 第 1534–1584 行）。另一個選擇是照帳本放在 store 之外——但那就不是答覆 3 說的「store 記下」 |
| Q4 | 目的地已經有同名的檔 | 內容（digest）相同：不重寫，記 `already-present`；不同：拒絕並說出找到的 digest；帶 `--replace` 才以同目錄暫存檔加原子替換覆寫，記 `replaced` 與被換掉的 digest。symlink、目錄、其他非普通檔一律拒絕 | `take` 原子替換、`fulltext text` 不覆寫——兩個先例方向相反，這裡取「預設不覆寫、明說才換」 |
| Q5 | 過期檢查要不要在本 change 做；目的地的檔後來不見或被改了，記錄怎麼辦 | 做，唯讀：逐列回報 `current`（檔在、digest 與記錄相同，而且原版匯出的仍是那篇作品現在的原版、指名匯出的仍連在那篇上）、`differs`（檔在、digest 不同）、`missing`（檔不在）、`superseded`（檔與記錄相同，但上一條的條件不再成立）。記錄永不改寫、不刪除；狀態每次現算。只檢查本機路徑，讀不到的目錄報 `unreadable`，不當成 `missing` | 答覆 3「之後找得到過期的副本」；`auditSourceIndex`「讀不到 ≠ 缺席」的同一條（`SourceStore.swift` 第 450–456 行） |
| Q6 | marker 由誰執行；Markdown 的來源記在哪裡；一份 PDF 有幾份 Markdown 時匯出哪一份 | Akashic 不執行 marker；呼叫端轉好之後用 `store-source` 存，多帶兩個選填欄位 `derived-from`（PDF 的 digest，必須已在 index）與 `converter`（例如 `marker-pdf 1.2.3`）寫進 index 列；Markdown 的位元組照轉出來的樣子存、不加 front matter。匯出 PDF 時，`derived-from` 指向它的 Markdown 恰好一份就一起寫出；不只一份就不寫 Markdown、列出各 digest，要用 `--markdown <digest>` 指定 | 答覆 4；`swift-is-the-implementation-language`（Akashic 不新增非 Swift 的程式依賴） |

## Capabilities

### New Capabilities

- `source-export`：全文原版的定義、多份 PDF 時哪一份是原版、index 列的版本欄位、匯出入口與檔名、目的地閘、匯出記錄、過期檢查、衍生 Markdown、取全文 skill 改走匯出

### Modified Capabilities

（無。index 列多出的三個選填欄位寫在 `source-export` 的 requirement 裡；存放 index 列既有規格的那個 capability，字句不變。）

## Impact

- Affected specs: source-export（新）
- Affected code（實作時）：
  - Modified: Sources/AkashicStoreIO/SourceStore.swift, Sources/AkashicStoreIO/SourcesIgnoreBlock.swift, Sources/AkashicMCPKit/AkashicService.swift, Sources/akashic/StoreSourceCommand.swift, Sources/akashic/CLI.swift, Sources/akashic-mcp/Server.swift, Sources/akashic/WriteGateRulings.swift, docs/store-format.md, docs/rulings/mcp-cli-parity.md, docs/rulings/two-kinds-of-edits.md, plugin/skills/akashic-fetch-fulltext/SKILL.md, plugin/skills/akashic-bootstrap/references/writing-to-the-store.md, plugin/CHANGELOG.md, .githooks/plugin-shell-versions.txt
  - New: Sources/AkashicStoreIO/SourceExport.swift, Sources/akashic/SourceExportCommands.swift, Tests/AkashicKitTests/SourceExportTests.swift, Tests/AkashicCLITests/SourceExportCLITests.swift, changelog/<日期>-source-export-825.md
