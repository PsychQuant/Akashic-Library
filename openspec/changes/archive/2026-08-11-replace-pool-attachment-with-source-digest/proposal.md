## Why

Akashic 目前有一件事無路可走：手上有一份論文 PDF，沒有辦法讓 store 認得它。

`attachments` 的 `pool` 種類是為此設計的，但它規格存在、資料 0 筆、沒有 root 解析、沒有 CLI 或 MCP 介面——一個沒人能用的層存在了兩個多月。它唯一的實質理由是「不想把外部檔案複製進 store」，而該理由已被推翻：位元組要複製一份進 store，且檔案要住在 Akashic 裡而非指向別人的儲存（見 `.claude/rules/replace-endnote-and-zotero.md`）。

同時，記錄側沒有任何欄位能指向 `sources/` 的已儲存內容。既有的 `references` 是**欄位層級**的 provenance（「這個欄位的值以那份內容為據」），而「這份 PDF 是這篇論文的副本」不是任何單一欄位的證據，是整筆記錄的呈現物。兩者關係不同，不能共用一個欄位。

## What Changes

- 新增記錄層級的 source 引用：work 記錄的 `akashic` namespace 下可攜帶一個 digest 清單，宣告「這些已儲存的內容是本筆記錄所描述之作品的副本」。反向（一個 digest 屬於哪些記錄）現算，不另存。
- 確立規範：**store 有能力 ingest 的內容，一律以 digest 引用，不以檔案系統路徑引用。** 路徑會因搬移或改名斷鏈、且無法偵測內容變更；digest 是既有 provenance 契約已採的 identity。
- **BREAKING** `attachments` 元素的鍵域移除 `pool`，收窄為只剩 `zotero`。鍵域是封閉集合且未知種類會觸發整檔 quarantine，故此變更為 non-additive。
- **BREAKING** store format 由 7 提升為 8。實際受影響資料為 0 筆（全庫無任何 `pool` 附件），但契約層仍是 breaking read change，不得當作死碼移除處理。

## Capabilities

### New Capabilities

- `entry-source-reference`: work 記錄以 digest 指向其副本的已儲存內容；並規範可 ingest 的內容一律以 digest 而非路徑引用。

### Modified Capabilities

(none)

## Impact

- Affected specs: `entry-source-reference`（新增）
- Affected code:
  - New:
    - openspec/specs/entry-source-reference/spec.md
  - Modified:
    - Sources/AkashicCore/Models.swift
    - Sources/AkashicCore/YAML.swift
    - Sources/AkashicStoreIO/StoreVersion.swift
    - Sources/AkashicStoreIO/DivergenceResolve.swift
    - Sources/AkashicZoteroImport/ZoteroMapping.swift
    - Sources/AkashicMCPKit/AkashicService.swift
    - Sources/akashic/Commands.swift
    - docs/store-format.md
    - Tests/AkashicKitTests/CoreTests.swift
    - Tests/AkashicKitTests/R8ForwardCompatTests.swift
    - Tests/AkashicKitTests/KnownLayerEvolutionTests.swift
    - Tests/AkashicKitTests/ZoteroImportTests.swift
  - Removed:
    - (none — 移除的是列舉成員與鍵域，不是檔案)
