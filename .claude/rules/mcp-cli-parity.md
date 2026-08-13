# 新增 MCP 工具時，必須同時裁決 CLI 面

適用於**新增或修改 MCP 工具**的任何變更（`Sources/akashic-mcp/Server.swift` 的
`Tool(name:)` 註冊表）。修改既有工具（schema、語意）時，同一變更要**重新確認**
下表對應列仍成立，不成立就更新該列。

**本規則是單向的（MCP → CLI）**——反方向（新增 CLI subcommand 時要不要 MCP 面）
的裁決不在本規則範圍：12 個既有 CLI-only 能力（含 #206 鏡像的 `import-wos`）
零裁決的事實與雙向化的決定，追蹤 **#259**。這裡明寫，讓沉默是有記錄的沉默。

不適用於呈現細節（輸出格式、欄位排版）——那由 `entity-backlink-completeness` 的
「一個讀取面只有一條實作路徑」管。

## 規則

**在 `Server.swift` 新增一個工具的同一個變更裡，必須裁決它的 CLI 面**，二選一：

1. **同時補 CLI subcommand**（照 `PersonCommand.swift` 模式：同一個
   `AkashicService` 函式、`key:` 必帶；**讀取面**須 `--json` 原樣轉印 + 人可讀
   同源。**寫入面是封閉例外**：只回 service payload、不設 `--json` 旗標也無人可讀
   分支——`link`／`tag`／`set-status` 即此形；例外只有這一類，不得類推），**並在
   下表加一列**；或
2. **記錄一個有理由的缺席**——開 issue 載明為什麼這個能力可以只有 MCP 面
   （判準見下），並在下表加一列指向該 issue。

**「未決」不是第三個選項**：它只保留給本規則落地**之前**已存在的工具（下表的
#250 兩列即是，屬既往不咎的過渡態）。規則生效後新增的工具必須當場二選一。

**判準不是「MCP 有的 CLI 都要有」**——那是機械對稱，會製造沒人用的命令。判準是：

> 這個能力的可用性，該不該取決於使用者用的是 MCP 還是 CLI？

（#206 對匯入面的原話：「能不能無損匯入，不該取決於使用者會不會寫 script。」）

## 裁決史（封閉列舉——現有 20 工具，一格不多一格不少）

| MCP 工具 | CLI 對應 | 裁決 |
|---|---|---|
| `akashic_search` | `query`（filter flags）| ✅ 功能重疊 |
| `akashic_relations` | `query`（relation flags）| ✅ 功能重疊 |
| `akashic_graph` | `graph` | ✅ |
| `akashic_export` | `export-bib`／`export-tables` | ✅ 功能重疊 |
| `akashic_doctor` | `doctor` | ✅ |
| `akashic_files` | `file` | ✅ |
| `akashic_libraries` | `library` | ✅ |
| `akashic_import_zotero` | `import-zotero` | ✅ |
| `akashic_resolve_people` | `resolve-people` | ✅ |
| `akashic_record_divergence` | `record-divergence` | ✅ |
| `akashic_update_person` | `update-person` | ✅（#68）|
| `akashic_create_entry` | `create-entry` | ✅（#206）|
| `akashic_person` | `person` | ✅（#218）|
| `akashic_people` | `people` | ✅（#219）|
| `akashic_get_entry` | `get-entry` | ✅（#219）|
| `akashic_link` | `link` | ✅（#219）|
| `akashic_tag` | `tag` | ✅（#219；兩面呼叫契約小異：MCP 零參數 no-op、CLI 拒絕——見 #258）|
| `akashic_set_status` | `set-status` | ✅（#219；**兩面呼叫契約分岔**：MCP 省略 status＝靜默清除、CLI 拒絕——追蹤 #258）|
| `akashic_add_person` | ❌ 無 | **未決**——#250 |
| `akashic_divergences` | ❌ 無 | **未決**——#250 |

新增下一個工具 = 在這張表加一列。**不得依性質相似類推**「這個工具顯然不用 CLI」
——那個判斷要寫成表裡的一列（含理由或 issue 編號），不能只存在腦中。

### 怎麼機械檢查這張表真的封閉

不要相信作者窮舉過（`entity-backlink-completeness` 的表錯過兩次，教訓同形）：

```bash
# ① MCP 面的全部工具名（實測：恰 20，與表零差集）
grep -oE 'Tool\(name: "akashic_[a-z_]+"' Sources/akashic-mcp/Server.swift | sort -u
# ② CLI 面的全部註冊型別（取 subcommands 陣列整段，不靠型別命名慣例——
#    第一版寫 '[A-Za-z]+Cmd?\.self' 只命中 11/30：`Cmd?` 是「Cm+可選 d」，
#    #219 verify 三個 lens 獨立抓到。稽核程序自己也要被稽核）
sed -n '/subcommands: \[/,/\])/p' Sources/akashic/CLI.swift | grep -oE '[A-Za-z]+\.self'
# ③ 逐一比對上表：①有而表沒有 → 表壞了；表標 ✅ 而②對不到 → 表壞了。
#    注意 ② 吐的是**型別名**（FileCmd）而表用**命令名**（file）——對照時開該型別的
#    CommandConfiguration.commandName 核對，這一步是人工的（要全機械化需 manifest
#    或讀 configuration 的測試，見 #259 的討論）
```

## 為什麼：缺口是安靜累積的

兩張註冊表（`Server.swift` 工具表、`CLI.swift` subcommand 表）獨立生長，能力新增
落在 `AkashicService` + `Server.swift` 就能出貨——**沒有任何東西強制在那一刻想起
CLI 使用者**。失敗史：

- **#206**（2026-08-09）：無損匯入只有 MCP 有——家族第一例，當下以「繞過 CLI 用
  stdio 驅動 MCP」workaround，並留下上面那句判準
- **#218**（2026-08-10）：`person` 檢視只有 MCP 有——CLI 能**改寫** person 記錄
  （`update-person`）卻讀不出一筆
- **#219**（2026-08-10 開、08-12 修）：逐格盤點發現**一族六格**（含 #218 那格）
- **#250**（2026-08-12）：#219 開立後**兩天內**，同族又長出兩格（`add_person`／
  `divergences`）——本規則寫下前的最後證據：不修流程，格子必然繼續長

把失敗史留在檔內，是因為只留結論的話，日後維護者會覺得「這條寫得囉嗦、我幫它
精簡」而把裁決力刪掉（見全域 `common-spec-prose-enumeration.md` 執行細節 3）。

## 跟其他規則的關係

- `entity-backlink-completeness`（執行細節 2）：管「同一格的兩面必須落到同一條
  實作路徑」；本規則管「每一格必須被裁決要不要有兩面」。先有本規則的裁決，才輪
  到那條的單一路徑。
- 全域 `common-spec-prose-enumeration.md`：上表是封閉列舉 + 機械稽核程序，不寫
  總括判準——「工具該不該有 CLI 面」的判準存在（見上），但它的**輸出必須落回表
  裡**，不允許讀者拿判準自行類推出沒寫下的裁決。
