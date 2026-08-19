## Context

`SourceStore.storeSource(_:provenance:)` 的寫入面防護在 #224 已完成並經 verify（換行守衛、
O_APPEND、index 過閘、腐壞拒寫）。本變更**只接呼叫端**，不動那個函式。

實測依據（`grep -rn storeSource Sources/ Tests/`）：`Sources/` 全樹只命中宣告本身
（`SourceStore.swift:85`），`Tests/` 命中 23 次。零 production 呼叫端。

## Goals

- 「存一份 source」不再取決於使用者會不會寫 Swift
- receipt 的 `discardedProvenance` 與 `exclusionVerified` 在兩面都看得見

## Non-Goals

**In scope**：新增兩個入口 + 一條 spec requirement + parity 表一列。

**Out of scope**（各有理由，不是省略）：

- 改 `SourceStore.storeSource` 的行為 —— 已 verify 過的寫入面
- 取回（read）面 —— `akashic_files` 一族已覆蓋
- 批次存入 —— 要先回答「部分失敗怎麼回報」
- 自動抓取 URL —— 會讓 `retrieved` 的語意從「呼叫端何時取得」漂移成「工具何時抓的」

## Decisions

### D1：位元組從哪裡來——檔案路徑，不是 stdin、不是 base64

呼叫端交來的是**檔案路徑**，由入口讀成 `Data`。

- **不用 stdin**：CLI 可行但 MCP 面沒有 stdin；兩面會分岔成不同的輸入形狀，違反
  「同一條 service 路徑」。
- **不用 base64 字串**：MCP 可行但把二進位塞進 JSON 會讓一份 PDF 的 payload 膨脹 4/3 倍
  且整份進 LLM context——`export` 的既有威脅模型（#165）已記過同型風險。
- **檔案路徑兩面都成立**，且與 `akashic_files` 的既有形狀一致。

代價：MCP 面的呼叫端必須先把內容落到檔案系統。可接受——LLM 消費端本來就在跑工具的那台
機器上操作檔案。

### D2：`retrieved` 由呼叫端提供，不由入口生成

`SourceProvenance.retrieved` 是「呼叫端**何時取得**這份內容」，不是「何時存進來」。入口
自動填 `now()` 會讓兩者混淆，且對「三個月前抓的檔案今天才入庫」給出錯誤答案。

必填。缺就拒絕——不猜。

### D3：`exclusionVerified == false` 由既有實作拒寫，入口不重複判斷

`SourceStore` 已在寫入前用 git 自身的忽略判定確認，未生效即拒寫
（`replace-endnote-and-zotero` 明文：「不得為了任何便利放寬它」）。

入口**只回報** receipt 帶回的值，不自己再判一次——兩處判斷會分岔，而這道閘是承重的。

### D4：CLI 的人可讀面與 `--json` 同源

依 `mcp-cli-parity` 的讀取面慣例：`--json` 原樣轉印 service payload，人可讀分支從同一個
payload 渲染。**寫入面的封閉例外不適用**——那個例外是給「只回 service payload、無人可讀
分支」的 `link`／`tag`／`set-status`，而本命令的 receipt 有四個欄位、人需要看得懂
「你這份敘述沒被寫入」。

## Risks

- **`discardedProvenance` 被忽略**：它只在冪等早退時非 nil，是低頻路徑。緩解——CLI 人可讀
  面對該情況印明確的一行（而非只在 JSON 裡多一個鍵），測試釘住那行存在。
- **路徑注入**：檔案路徑來自呼叫端。既有 `displaySafe` 紀律涵蓋回顯；讀檔本身由
  `FileManager` 處理，不做 shell 展開。

## Implementation Contract

### `AkashicService.storeSource(path:mediaType:retrieved:origin:acquisition:note:) throws -> String`

- **行為**：讀 `path` 的位元組 → 組 `SourceProvenance` → 呼叫
  `SourceStore.storeSource` → 回傳 receipt 的 JSON 字串
- **回傳形狀**（四個鍵，`discardedProvenance` 僅在非 nil 時出現）：
  `digest` / `exclusionVerified` / `indexEntryCreated` / `discardedProvenance`
- **失敗模式**：
  - 路徑不存在或讀不到 → `ServiceError.invalid`，訊息含 `displaySafe` 過的路徑
  - `mediaType` / `retrieved` / `origin` / `acquisition` 任一為空 → `ServiceError.invalid`，
    具名哪個欄位
  - `SourceStore` 擲出的錯（index 腐壞、排除未驗證）→ 原樣往上傳，不吞
- **驗收**：`StoreSourceEntryPointTests` 的四條斷言（見 tasks）

### MCP tool `akashic_store_source`

- 參數與 service 同名同義；`note` 選填，其餘必填
- 回傳 service 的 JSON 字串原樣

### CLI `store-source`

- `akashic store-source <path> --media-type <t> --retrieved <d> --origin <o> --acquisition <a> [--note <n>] [--json]`
- `--json` 原樣轉印；無 `--json` 時人可讀，且 `discardedProvenance` 非 nil 時**必印一行**
  說明「這份敘述沒有被寫入」
