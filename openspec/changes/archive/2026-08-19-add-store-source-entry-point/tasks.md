## 1. Service 層

實作 `AkashicService.storeSource(path:mediaType:retrieved:origin:acquisition:note:) throws -> String`
（Implementation Contract 的第一節）。

- [x] 1.1 依 **D1：位元組從哪裡來——檔案路徑，不是 stdin、不是 base64**，入口收檔案路徑並
  讀成 `Data`（兩面共用同一形狀；MCP 沒有 stdin，base64 會讓二進位膨脹並整份進 LLM
  context）。在 `Sources/AkashicMCPKit/AkashicService.swift` 加該函式，組
  `SourceProvenance`、呼叫 `SourceStore.storeSource`，回傳 receipt 的 JSON 字串
  （鍵：`digest` / `exclusionVerified` / `indexEntryCreated`，`discardedProvenance`
  僅在非 nil 時出現）。
  **驗收**：`swift build` 通過，且
  `Tests/AkashicMCPTests/StoreSourceEntryPointTests.swift` 的
  `testFirstStoreReportsDigestAndIndexEntryCreated` 通過。

- [x] 1.2 依 **D2：`retrieved` 由呼叫端提供，不由入口生成**，`retrieved` 必填、入口不填
  `now()`（那會把「呼叫端何時取得」混淆成「何時存進來」）。同時對
  `mediaType` / `retrieved` / `origin` / `acquisition` 任一為空白擲 `ServiceError.invalid`，
  訊息**具名哪個欄位**（不是「參數不足」）。
  **驗收**：`testEmptyRequiredFieldIsRefusedByName` 對四個欄位各斷言訊息含該欄位名。

- [x] 1.3 依 **D3：`exclusionVerified == false` 由既有實作拒寫，入口不重複判斷**，入口
  **只回報** receipt 帶回的值，不自己再判一次（兩處判斷會分岔，而這道閘是承重的）。
  `SourceStore` 擲出的錯（index 腐壞、排除未驗證）原樣往上傳、不吞。路徑讀不到時擲
  `ServiceError.invalid`，訊息含 `displaySafe` 過的路徑。
  **驗收**：`testUnreadablePathIsRefused` 斷言錯誤類型與訊息含路徑片段。

## 2. Stored content SHALL be reachable through a user-facing entry point — 冪等早退的可見性

- [x] 2.1 receipt 的 `discardedProvenance` 非 nil 時，JSON 必須含該鍵，且內容是**呼叫端
  這次交來**的五個欄位（不是既有條目的）——依 `lossless-intake` 的「丟棄必須可見」。
  **驗收**：`testResubmitSurfacesDiscardedProvenance` 存同一份位元組兩次、第二次帶不同
  `note`，斷言 `indexEntryCreated == false` 且 `discardedProvenance.note` 等於第二次的值。

## 3. MCP tool `akashic_store_source`

- [x] 3.1 在 `Sources/akashic-mcp/Server.swift` 註冊 `Tool(name: "akashic_store_source")`，
  參數與 service 同名同義（`note` 選填、其餘必填），回傳 service 的 JSON 原樣。
  **驗收**：`grep -oE 'Tool\(name: "akashic_[a-z_]+"' Sources/akashic-mcp/Server.swift | sort -u`
  的輸出含 `akashic_store_source`，且總數比實作前多 1。

## 4. CLI `store-source`

- [x] 4.1 新增 `Sources/akashic/StoreSourceCommand.swift`：
  `akashic store-source <path> --media-type <t> --retrieved <d> --origin <o> --acquisition <a> [--note <n>] [--json]`，
  並註冊進 `Sources/akashic/CLI.swift` 的 subcommands 陣列。
  **驗收**：`./.build/debug/akashic store-source --help` 列出全部旗標。

- [x] 4.2 依 **D4：CLI 的人可讀面與 `--json` 同源**，`--json` 原樣轉印 service payload、
  人可讀分支從同一個 payload 渲染（寫入面的封閉例外**不適用**——那是給只回 payload、
  無人可讀分支的命令）。`discardedProvenance` 非 nil 時**必印一行**說明該敘述沒有被寫入。
  **驗收**：`testCLIHumanReadableSurfacesDiscardedProvenance` 對第二次存入的輸出斷言
  含「沒有被寫入」字樣。

## 5. Parity 表（滿足 requirement 的「Both interfaces receive the same submission」scenario）

- [x] 5.1 在 `.claude/rules/mcp-cli-parity.md` 的 MCP 裁決表加一列
  `akashic_store_source` → `store-source`，裁決 ✅ 並註明 #264。
  **驗收**：跑該檔的稽核程序 ① 與 ②，兩者的輸出都能在表中找到對應列（新工具與新命令
  都不是零裁決格）。

## 6. 收尾

- [x] 6.1 全套 `swift test` 通過，且新測試檔的斷言全綠。
- [x] 6.2 `spectra validate add-store-source-entry-point` 通過。
