## 1. 收窄附件鍵域

> 對應需求：`The set of accepted attachment kinds SHALL contain exactly one kind`、`Content the store is able to ingest SHALL be referenced by digest rather than by file-system path`
> 對應設計決策：`移除 pool 而非改造成機器本地對照表`

- [x] 1.1 先寫測試：一份帶 `pool` 種類附件的記錄在載入時被拒絕，且錯誤訊息不把 `pool` 呈現為合法值。驗證：新測試加入 Tests/AkashicKitTests/CoreTests.swift 後執行 swift test，該測試為 red。
- [x] 1.2 實作需求 The set of accepted attachment kinds SHALL contain exactly one kind 與 Content the store is able to ingest SHALL be referenced by digest rather than by file-system path，讓合法附件種類只剩 `zotero`：從 Sources/AkashicCore/Models.swift 的 `AttachmentRef.Kind` 移除 `pool` 成員，並更新 Sources/AkashicCore/YAML.swift 的鍵域驗證與錯誤訊息文字。此舉同時落實「可 ingest 的內容以 digest 而非檔案系統路徑引用」——移除後僅存的路徑型引用是指向外部文獻管理器自有儲存的過渡形式。驗證：1.1 的測試轉 green，且全庫執行 swift test 無其他失敗。
- [x] 1.3 讓 Zotero 匯入在鍵域收窄後行為不變：移除 Sources/AkashicZoteroImport/ZoteroMapping.swift 中保留 `pool` 附件不被覆寫的分支，`zotero` 附件的匯入與保留語意維持原樣。驗證：Tests/AkashicKitTests/ZoteroImportTests.swift 全數通過。

## 2. 記錄側副本引用

> 對應需求：`A work record SHALL name stored content that is a copy of the work`、`The copy reference SHALL remain distinct from field-level provenance references`
> 對應設計決策：`記錄層級的 source 引用不重用欄位層級的 references`、`引用存在記錄側，反向現算`、`欄位放在 akashic namespace 下`

- [ ] 2.1 先寫測試，涵蓋三件事：帶一個 digest 的副本清單可完成序列化與反序列化的來回且字串逐字不變；空清單與缺席在行為上不可區分；不合文法的 digest 被拒絕且錯誤訊息包含該欄位名。驗證：測試加入 Tests/AkashicKitTests/CoreTests.swift 後執行 swift test，三個案例皆 red。
- [ ] 2.2 實作需求 A work record SHALL name stored content that is a copy of the work，讓 work 記錄能在 `akashic` 命名空間下攜帶副本 digest 清單（依設計決策「欄位放在 akashic namespace 下」，使匯入不會覆寫它；依「引用存在記錄側，反向現算」，不建立內容側的反向索引）：於 Sources/AkashicCore/Models.swift 定義該欄位，於 Sources/AkashicCore/YAML.swift 實作讀寫，digest 文法沿用既有的 provenance 引用驗證函式而不另立。驗證：2.1 的三個案例全數轉 green。
- [ ] 2.3 先寫測試：記錄所指的 digest 在本機沒有對應已儲存內容時，記錄仍載入成功，且該狀況被回報為與「記錄格式損壞」不同的條件。驗證：測試加入 Tests/AkashicKitTests/CoreTests.swift 後執行 swift test，為 red。
- [ ] 2.4 實作缺席內容的回報路徑，沿用 Sources/AkashicStoreIO/SourceStore.swift 既有的 digest 對應查找，不新增語意。驗證：2.3 轉 green。
- [ ] 2.5 實作需求 The copy reference SHALL remain distinct from field-level provenance references，讓副本引用與欄位層級 provenance 引用在同一筆記錄中並存而互不改寫（落實設計決策「記錄層級的 source 引用不重用欄位層級的 references」）：先寫測試，令一筆記錄同時帶有指向相同 digest 的 `references` 與副本清單，斷言兩者在來回後各自保留、任一方都未被改寫成另一方。驗證：測試加入 Tests/AkashicKitTests/CoreTests.swift 後由 red 轉 green；即使無需新增產品程式碼即通過，仍保留該測試作為回歸鎖。

## 3. format 提升與寫入閘

> 對應需求：`The copy reference SHALL be governed by a store format increment`
> 對應設計決策：`store format 提升到 8`

- [ ] 3.1 先寫測試，涵蓋兩件事：對 format 低於 8 的 store 寫入含副本清單的記錄被拒絕且錯誤訊息指出所需 format；僅支援 format 7 的載入路徑遇到 format 8 的 store 時整體拒絕開啟。驗證：測試加入 Tests/AkashicKitTests/KnownLayerEvolutionTests.swift 後執行 swift test，兩案例皆 red。
- [ ] 3.2 實作需求 The copy reference SHALL be governed by a store format increment，把 `StoreVersion.supported` 由 7 提升為 8 並在 Sources/AkashicStoreIO/StoreVersion.swift 的版本沿革補上第 8 項，明寫提升依據是附件元素鍵的嚴格驗證與未知種類導致整檔 quarantine，而非受影響資料筆數；同時實作副本清單的寫入閘。驗證：3.1 的兩個案例轉 green。

## 4. 服務層與命令列一致性

- [ ] 4.1 確認 MCP 服務與命令列對附件形狀無殘留於 `pool` 的假設：檢視 Sources/AkashicMCPKit/AkashicService.swift 與 Sources/akashic/Commands.swift 的附件處理路徑，移除或更新任何以兩種附件種類為前提的分支。驗證：對 Sources 與 Tests 執行 grep 搜尋 `pool` 僅剩本次變更的說明性註解，且 swift test 全綠。

## 5. 文件

- [ ] 5.1 [P] 讓格式規格書不再把 `pool` 呈現為合法附件種類：更新 docs/store-format.md 的附件章節、命名空間契約表、以及 format 版本沿革（新增第 8 項並寫入提升依據）。驗證：對該檔 grep 搜尋 `pool` 後，僅出現在描述其已被移除的段落。
- [ ] 5.2 [P] 讓 README 的儲存佈局說明反映移除後的現況：更新 README.md 中描述 attachment pool 的那一行，改為說明副本以 digest 引用、位元組存於內容定址區。驗證：閱讀該段落確認不再指示使用者建立 pool 目錄或 symlink。

## 6. 回歸保護

- [ ] 6.1 確認既有 51 筆帶 `zotero` 附件的記錄在本次變更後仍可正常載入：以真實 store 執行一次載入煙霧測試，並執行完整測試套件。驗證：載入回報的記錄數與變更前相同，且 swift test 全數通過。
