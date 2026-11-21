## 0. 開工前

- [ ] 0.1 確認 proposal〈Open questions for the maintainer〉六題的答案；選了建議預設以外的，先改 `specs/source-export/spec.md` 對應的 requirement 與下面的 tasks，再寫測試
- [ ] 0.2 Q1 與 #824 的 Q2 一起定：既有 index 列要補 `version`，得靠 #824 的更正列能改這一欄；兩個 change 的實作順序寫進兩邊的 tasks

## 1. 測試先寫（在本 change 開工時的 main 上看它們失敗）

- [ ] 1.0 （Requirement: The original of a work's full-text PDF SHALL be the stored copy linked to the work）匯出記錄的 `digest` 一定是 `sources/` 裡、連在那篇作品上的那一份；沒有任何回應把匯出入口以外寫出的檔說成原版的副本（過期檢查只讀 `exports.jsonl` 記過的列）
- [ ] 1.1 （Requirement: An index row SHALL be able to record the version of a stored PDF）`store-source` 帶 `version` 寫進新列；四個值以外拒絕、零寫入；已記過的 digest 帶不同的 `version` 回到 `discardedProvenance`；沒有 `version` 的舊列照常載入
- [ ] 1.2 （Requirement: Which linked PDF is the original SHALL be decided by a closed table）表的六種情形各一個 fixture；只連著補充資料時拒絕、不把它寫成 `<citekey>.pdf`；補充資料不讓選擇變得不確定；讀不到種類的 digest 只讓選擇變得不確定、不會被選上；指名的 digest 沒連在這篇上就拒絕
- [ ] 1.3 （Requirement: The export entry point SHALL write verified stored bytes outside the library）大小相同、內容被改過的 blob 拒絕且目的地沒有檔；只給 digest：連在一篇上可以、連在兩篇上拒絕並列出兩個 citekey；`sources/` 裡除了 `exports.jsonl` 之外的位元組在匯出前後相同
- [ ] 1.4 （Requirement: The export file name SHALL follow a fixed rule unless overridden）預設檔名、非原版檔名、Markdown 檔名；覆寫含 `/`、空字串、`.`、`..`、NUL 都拒絕；非 ASCII 的覆寫照原樣寫出
- [ ] 1.5 （Requirement: The export destination SHALL pass the full-text output gate）被忽略的 git 工作樹可以寫、沒被忽略的拒絕、git 跑不起來拒絕；暫存檔名也問 git；目的地已有相同內容不重寫、不同內容不帶 `--replace` 拒絕、帶了以原子替換覆寫；symlink、目錄拒絕。git 閘與 `fulltext take` 共用同一個函式（測試斷言兩個呼叫端走同一條路徑，不是兩份實作）
- [ ] 1.6 （Requirement: Every export SHALL append a record in the store）每一個寫出、已在、取代的檔各一列，欄位齊全（含 `selection`）、`at` 帶 offset；被拒絕的匯出不留列；`exports.jsonl` 沒被 git 排除時在寫目的地之前拒絕
- [ ] 1.7 （Requirement: A read-only check SHALL report the state of every recorded copy）五種狀態各一個 fixture；指名匯出的非原版在仍連著時是 `current`、收回連結後是 `superseded`；讀不到的目錄報 `unreadable`；檢查前後目的地與記錄的位元組都不變
- [ ] 1.8 （Requirement: A Markdown converted from a stored PDF SHALL record its PDF and converter and be exported with it）`derived-from` 沒有 index 列或不是 PDF 時拒絕；給了 `derived-from` 沒給 `converter` 拒絕；Markdown 位元組與送入的檔相同；一份 PDF 有兩份 Markdown 時只寫 PDF 並列出兩個 digest；指名的 Markdown 不是這份 PDF 轉的就拒絕
- [ ] 1.9 （Requirement: The export entry point SHALL write verified stored bytes outside the library；Both interfaces）CLI 與 MCP 對同一個 fixture store 寫出相同的位元組、相同的檔名、欄位相同的記錄
- [ ] 1.10 （Requirement: The full-text skill SHALL place copies outside the library only by export）SKILL 的字串測試（與既有 SKILL 字串測試同一處，例如 `Tests/AkashicCLITests/FulltextClickProcedureTests.swift` 的寫法）：連回記錄之後的步驟點名匯出入口、沒有從暫存目錄 `cp` 的指示；`writing-to-the-store.md` 有原版的定義
- [ ] 1.11 驗證：上面帶 requirement 標記的新測試在開工時的 main 上都失敗；commit

## 2. 程式 [after: 1.11]

- [ ] 2.1 `SourceStore.swift`：index 列的 `version`、`derived-from`、`converter` 三個選填欄位（寫入順序接在 `note` 之後，既有欄位的位置不動）；`sourcePresence` 讀回這三欄
- [ ] 2.1b `Sources/AkashicStoreIO/SourcesIgnoreBlock.swift`：akashic 寫進 `sources/` 的路徑是一張封閉清單（`GlobText.indexPath`／`indexName` 與存檔子目錄），加上 `sources/exports.jsonl`，讓否定規則的判斷與 doctor 的訊息（「sources 這個目錄、index.jsonl、兩個十六進位字元的存檔子目錄」那幾句）都涵蓋它；`SourcesIgnoreBlock` 的既有測試照加一格
- [ ] 2.2 新檔 `SourceExport.swift`：原版的五格表、重算 digest、檔名規則、目的地閘（抽出 `FulltextTake` 的 git 閘成共用函式）、`exports.jsonl` 的追加與排除驗證、過期檢查
- [ ] 2.3 `AkashicService`：匯出與檢查的服務函式（兩面共用）；`storeSource` 收三個新欄位
- [ ] 2.4 CLI：`store-source` 的 `--version`、`--derived-from`、`--converter`；匯出與檢查兩個子命令（名稱實作時定，寫進 `docs/rulings/mcp-cli-parity.md`），加進 `Sources/akashic/CLI.swift` 的 subcommands
- [ ] 2.5 MCP：`akashic_store_source` 的三個新參數；匯出與檢查兩個工具。`tools/list` 的位元組預算由 `StdioE2ETests.testToolsListResponseStaysWithinByteBudget` 量（上限 65,000；超過要回 #578 重新裁決，不得自行調高）
- [ ] 2.6 `Sources/akashic/WriteGateRulings.swift`：兩個新命令各一格。建議：匯出 `.notGated`（只在 `sources/` 追加一份 git 排除的記錄、不改寫任何記錄檔，理由比照 `store-source` 那一格）、檢查 `.readOnly`；`WriteGateRulingsTests` 要綠
- [ ] 2.7 `ToolPayloadScenarios`、`ToolPayloadLegs`：新工具與新參數各有情境；新回應鍵寫進工具說明或在 `ToolPayloadKeyExemptions` 具名豁免（`ToolPayloadKeyGuardTests`、`ToolPayloadLegTests` 要綠）

## 3. 文件與裁決表 [after: 2.7]

- [ ] 3.1 `docs/store-format.md`：index 列的三個新欄位；`sources/exports.jsonl` 的格式、排除規則、只增不改
- [ ] 3.2 `docs/rulings/mcp-cli-parity.md`：兩個新工具、三個新參數的列（跑該規則〈怎麼機械檢查這張表真的封閉〉的稽核，兩面差集為零）
- [ ] 3.3 `docs/rulings/two-kinds-of-edits.md`：匯出歸「程式」（決定論、同一輸入同一輸出；逆操作是使用者刪掉副本，記錄留著）
- [ ] 3.4 `plugin/skills/akashic-fetch-fulltext/SKILL.md`：第 6 步之後加匯出那一步、第 5 步的 `store-source` 帶 `version`；回報表多一欄匯出的檔
- [ ] 3.5 `plugin/skills/akashic-bootstrap/references/writing-to-the-store.md`：原版的定義、副本從原版匯出、Markdown 的 `derived-from` 與 `converter`
- [ ] 3.6 `plugin/CHANGELOG.md`、`.githooks/plugin-shell-versions.txt`、`changelog/<日期>-source-export-825.md`

## 4. 驗證 [after: 3.6]

- [ ] 4.1 `swift build -Xswiftc -warnings-as-errors`、全套 `swift test`、`bash .githooks/run-guards.sh`、`spectra validate idd-825-source-original-export` 都通過
