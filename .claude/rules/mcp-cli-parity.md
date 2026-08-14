# 新增任一面（MCP／CLI）的能力時，必須同時裁決另一面

適用於**新增或修改 MCP 工具**（`Sources/akashic-mcp/Server.swift` 的 `Tool(name:)`
註冊表）與**新增 CLI subcommand**（`Sources/akashic/CLI.swift` 的 subcommands
陣列）的任何變更。修改既有能力（schema、語意）時，同一變更要**重新確認**
對應列仍成立，不成立就更新該列。

**本規則自 #259（2026-08-15）起是雙向的**：新增 MCP 工具 → 裁決 CLI 面（MCP
表）；新增 CLI subcommand → 裁決 MCP 面（CLI-only 表）。#259 前累積的 12 個
CLI-only 能力已於同日一次性補裁（見 CLI-only 表）——此前的沉默至此有了記錄。

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

**「未決」不是第三個選項**：它曾保留給本規則落地**之前**已存在的工具（#250
兩列的過渡態，2026-08-15 已裁決補齊——第一次演練）。規則生效後新增的工具必須
當場二選一；表中現無未決格。

**判準不是「MCP 有的 CLI 都要有」**——那是機械對稱，會製造沒人用的命令。判準是：

> 這個能力的可用性，該不該取決於使用者用的是 MCP 還是 CLI？

（#206 對匯入面的原話：「能不能無損匯入，不該取決於使用者會不會寫 script。」）

## 裁決史（封閉列舉——現有 20 工具，一格不多一格不少）

| MCP 工具 | CLI 對應 | 裁決 |
|---|---|---|
| `akashic_search` | `query`（filter flags）| ✅ 功能重疊 |
| `akashic_relations` | `query`（relation flags）| ✅ 功能重疊 |
| `akashic_graph` | `graph` | ✅ |
| `akashic_export` | `export-bib`／`export-tables` | ✅ 功能重疊（tables 面與 #274 的 `--view` 為 **CLI-only**——正式裁決見 CLI-only 表的 `export-tables --view` 列，#259）|
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
| `akashic_tag` | `tag` | ✅（#219；契約已收斂——零參數兩面皆拒，守衛下沉 service 單一路徑，#258）|
| `akashic_set_status` | `set-status` | ✅（#219；契約已收斂——省略拒絕、清除須顯式（CLI `--clear`／MCP `clear:true`），守衛下沉 service，#258）|
| `akashic_add_person` | `add-person` | ✅（#250；寫入面封閉例外形。實證需求：#238 對 unkeyable 作者的處置就是單筆指定 key）|
| `akashic_divergences` | `divergences` | ✅（#250；讀取面 `--json`＋人可讀同源。#218 同形：能寫不能讀的格）|

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

## CLI-only 裁決表（封閉列舉——#259 一次性補裁；12 命令＋1 旗標，一格不多一格不少）

新增 CLI subcommand = 在這張表加一列（或補 MCP 面後在 MCP 表加一列）。兩個
裁決用語：**維運例外**＝要求操作者在檔案系統與版控旁（git 退路、人工
pre-flight）的操作，MCP 的 LLM 消費者不是該角色；**候補缺席**＝目前無 MCP 端
消費流程，需求出現即重啟裁決（不是永久判死——重啟訊號刻意不形式化，那是使用
情境判斷）。

| CLI 能力 | 裁決 | 理由 |
|---|---|---|
| `import-wos` | **需要 MCP 面**——實作追蹤 #290 | #206 鏡像判準直接命中：無損匯入不該取決於面（`akashic_import_zotero` 先例）|
| `view`（list／show） | 候補缺席 | 外延查詢對 agent 有潛在價值，但目前無 MCP 端消費流程 |
| `resolve-divergence` | 有理由缺席 | in-code 既有裁決（`AkashicService.recordDivergence` doc）：消歧含合併＋全庫改寫＋刪檔，tracked+clean 前提與人工確認屬 CLI／App 互動面 |
| `resolve-organizations` | 候補缺席 | 與 `resolve-people`（有 MCP 面）同判準，但 store 現僅 2 org、無 agent 流程 |
| `bootstrap-people` | 有理由缺席 | 批次建檔屬操作者規模；單筆由 `akashic_add_person` 覆蓋（#250）|
| `bootstrap-organizations` | 有理由缺席 | 同上；且 org 建模有未決問題（#63／#70 一族，「organization 先停」）|
| `fmt` | 有理由缺席 | 全庫改寫＝維運例外 |
| `migrate` | 有理由缺席 | 格式遷移＝維運例外 |
| `migrate-provenance` | 有理由缺席 | 同上 |
| `validate` | 有理由缺席 | 讀取檢查由 `akashic_doctor` 覆蓋（功能重疊）|
| `rename` | 有理由缺席 | 高風險身分操作（citekey 遷移含 verdict value 重寫，#232）＝維運例外 |
| `authorize-names` | 有理由缺席 | 批次策展＝操作者規模 |
| `export-tables --view`（#274） | 有理由缺席 | 匯出物是檔案樹，MCP 的回傳形狀未定——#274 註記的正式落位 |

**機械檢查（CLI→MCP 方向）**：上方稽核程序的 ② 枚舉 CLI 全部註冊型別後，
每個命令必須出現在 **MCP 表的「CLI 對應」欄**或**本表**其中之一——兩處都
查無即是新長出的零裁決格（正是 #259 修掉的形狀）。

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
- **#259**（2026-08-15 收口）：規則落地時只綁 MCP 方向，反方向 12 個 CLI-only
  能力零裁決（含 #206 鏡像的 `import-wos`）——雙向化＋一次性補裁即本表的由來

把失敗史留在檔內，是因為只留結論的話，日後維護者會覺得「這條寫得囉嗦、我幫它
精簡」而把裁決力刪掉（見全域 `common-spec-prose-enumeration.md` 執行細節 3）。

## 跟其他規則的關係

- `entity-backlink-completeness`（執行細節 2）：管「同一格的兩面必須落到同一條
  實作路徑」；本規則管「每一格必須被裁決要不要有兩面」。先有本規則的裁決，才輪
  到那條的單一路徑。
- 全域 `common-spec-prose-enumeration.md`：上表是封閉列舉 + 機械稽核程序，不寫
  總括判準——「工具該不該有 CLI 面」的判準存在（見上），但它的**輸出必須落回表
  裡**，不允許讀者拿判準自行類推出沒寫下的裁決。
