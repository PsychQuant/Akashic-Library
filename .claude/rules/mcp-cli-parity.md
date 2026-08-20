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

## 裁決史（封閉列舉——現有 30 工具，一格不多一格不少）

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
| `akashic_import_wos` | `import-wos` | ✅（#290；#259 CLI-only 盤點唯一「需要」格的補齊——#206 鏡像判準）|
| `akashic_resolve_people` | `resolve-people` | ✅（#272 起兩面契約有記錄的差異：MCP 允許 apply+reject 組合（兩段式、按腿回報）；CLI 維持分兩次呼叫——互動面天然序列，組合是 LLM 批次 triage 的需求。#303 起兩面同步帶 `tier`（封閉四值 exact／confirmed-elsewhere／reorder／initials，信心降冪）：MCP 每列 `tier` 欄、CLI 按 tier 分組標頭與 `--tier` 篩選（裸 `--apply` 對寬鬆 tier 拒絕）、App 候選列標示；apply id 升三段形 `citekey:authorIndex:personKey`（釘 person，兩段 legacy 收）；否決抑制改與提名同一套正規化、淘汰而得的唯一命中在 reason 揭露——R1 verify 後 apply 語意有這些**有記錄的變更**，非純 additive。R3 裁決的**面不對稱**：tier 閘只在 CLI 篩選式批次（MCP per-id 顯式＋tier 可見，刻意不閘；tier-acknowledgment 參數列 follow-up）；rejected/applied 回音均三段 pinned 形）|

**#386 起多一個 per-id 判定面**（`judge` / `--judge`，兩面同走 `judgeAuthorships`）：
收 `citekey:authorIndex:personKey=理由`，**歧義列也適用**——歧義的意思是提名器分不出來，
不是人／AI 分不出來（`identity-is-judged-not-matched`）。**契約有記錄的差異**：CLI **不提供**
篩選式批次形式（judgement 必填形成摩擦，批次會讓它退化成罐頭）；MCP 面沿用該面既有的
per-id 顯式契約。兩面的失敗語意相同且刻意分兩類：輸入語法錯整批拒絕零寫入、store 狀態不符
該筆略過並具名。
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
| `akashic_venue` | `venue` | ✅（#304 venue change；讀取面 `--json`＋人可讀同源；編年 list 由反向邊現算）|
| `akashic_venues` | `venues` | ✅（#304 venue change；讀取面同源）|
| `akashic_add_venue` | `add-venue` | ✅（#304 venue change；寫入面封閉例外形，同 `add-person`）|
| `akashic_update_venue` | `update-venue` | ✅（#306；寫入面封閉例外形；append 語意——整組替換刻意不提供，R3F-2 教訓）|
| `akashic_resolve_venues` | `resolve-venues` | ✅（#304 venue change；兩面契約差異同 #272：MCP 允許 apply+reject 組合、CLI 分兩次呼叫）|
| `akashic_add_organization` | 無（單筆建檔 MCP-only；批次面 `bootstrap-organizations` 維持 CLI-only，見 CLI-only 表）| ✅ 有理由的單面（#304 移轉裁決：org 重啟後單筆建檔是 #303 campaign 的 LLM 消費流程；操作者規模的批次建檔另有 CLI 面）|
| `akashic_resolve_organizations` | `resolve-organizations` | ✅（#304 移轉；CLI-only 表「候補缺席（重啟訊號已觸發）」格的補齊——同 `import-wos`／#290 的移列形）|
| `akashic_store_source` | `store-source` | ✅（#264；**讀取面慣例**而非寫入面封閉例外——receipt 的 `discardedProvenance` 攜帶「你這份敘述沒被寫入」，人需要看得懂，故 `--json` 原樣轉印＋人可讀同源。收**檔案路徑**不收 base64／stdin：MCP 面無 stdin 會讓兩面分岔，base64 把二進位塞進 JSON 會膨脹並整份進 context（#165 的既有威脅模型）。`SourceStore.storeSource` 的寫入面防護 #224 已完成，本格只補呼叫端——先前全樹零 production 呼叫端，能力只有寫 Swift 的人做得到，#206 判準的同形）|
| `akashic_enrich_from_zotero` | `enrich-from-zotero` | ✅（#340；**#206／#290 判準的第三次套用**——那句原話是「能不能無損匯入，不該取決於使用者會不會寫 script」，在這裡是「能不能把一筆跌破下限的記錄補回下限，不該取決於面」。兩面同走 `ZoteroEnrichment.plan`。**契約有記錄的差異**：CLI 的 `--apply`走 #298 的破壞性閘、MCP 面用 `dry_run` 且**不設閘**——該閘擋的是「篩選式批次寫入未指名目標」，而本 tool 收的是逐筆顯式指名的 citekey 清單，與 `resolve-people` 的 tier 閘同型不對稱。**與 `akashic_import_zotero` 刻意不同語意**：那是 pull（整份替換 `fields`、重設 `type`、覆寫未歸戶作者），這是 add-only；同一個 store 上兩種語意並存是設計，不是重複）|

新增下一個工具 = 在這張表加一列。**不得依性質相似類推**「這個工具顯然不用 CLI」
——那個判斷要寫成表裡的一列（含理由或 issue 編號），不能只存在腦中。

### 怎麼機械檢查這張表真的封閉

不要相信作者窮舉過（`entity-backlink-completeness` 的表錯過兩次，教訓同形）：

```bash
# ① MCP 面的全部工具名（實測：恰 30，與表零差集）
grep -oE 'Tool\(name: "akashic_[a-z_]+"' Sources/akashic-mcp/Server.swift | sort -u
# ② CLI 面的全部註冊型別（取 subcommands 陣列整段，不靠型別命名慣例——
#    第一版寫 '[A-Za-z]+Cmd?\.self' 只命中 11/30：`Cmd?` 是「Cm+可選 d」，
#    #219 verify 三個 lens 獨立抓到。稽核程序自己也要被稽核）
sed -n '/subcommands: \[/,/\])/p' Sources/akashic/CLI.swift | grep -oE '[A-Za-z]+\.self'
# ③ 逐一比對上表：①有而表沒有 → 表壞了；表標 ✅ 而②對不到 → 表壞了。
#    ② 吐的是**型別名**（FileCmd）而表用**命令名**（file）。這一步過去是人工的
#    （#259 當時判斷「要全機械化需 manifest 或讀 configuration 的測試」）——實測
#    過於保守：從各型別的 CommandConfiguration 純文字抽 commandName 就夠，39/39
#    全解析（#318）。以下把型別名翻成命令名，再拿命令名去對表。
#    **失敗模式已驗**：抽不到 commandName 的型別印 `<未解析>` 而**不是靜默跳過**
#    ——只在 happy path 正確的稽核命令，會在真正需要它時安靜少報一列，那正是 ②
#    第一版 11/30 的形狀。
sed -n '/subcommands: \[/,/\])/p' Sources/akashic/CLI.swift \
  | grep -oE '[A-Za-z]+\.self' | sed 's/\.self$//' | sort -u \
  | while read -r t; do
      n=$(awk -v t="$t" '
            FNR==1 { f=0 }
            $0 ~ ("struct[[:space:]]+" t "[[:space:]]*:") { f=1 }
            f && /commandName:/ {
              sub(/.*commandName:[[:space:]]*"/, ""); sub(/".*/, ""); print; exit
            }' Sources/akashic/*.swift)
      printf '%-30s %s\n' "$t" "${n:-<未解析>}"
    done
#    誠實邊界：純文字抽取與「讀 configuration 的測試」不等價——前者對宣告寫法改變
#    脆弱（同 ② 的既有教訓）。本步只主張它足以取代**人工逐一開檔**，不主張它是終局
#    形狀。真正的不脆弱版本仍是那個測試，#259 的討論在這一點上沒有過期。
# ④ CLI 面的全部**橫切選項**（#310）：`ParsableArguments` 不是 subcommand，所以 ②
#    在結構上枚舉不到它——這是 ② 的盲點，不是它漏了一項。輸出的每一項都必須出現在
#    下方「CLI 橫切選項裁決表」；查無即是零裁決格。
#    **假陰性方向（寫出來而非假裝沒有）**：本式只認**宣告式**上的 conformance，
#    多重 conformance 的兩種順序都命中，但以 extension 追加 conformance 的寫法掃不到
#    ——與 ② 第一版 regex 只命中 11/30 同型。漏報比誤報安全，但漏報仍是漏報。
grep -rhoE 'struct [A-Za-z]+:[^{]*\bParsableArguments\b' Sources/akashic/ \
  | sed -E 's/^struct ([A-Za-z]+):.*/\1/' | sort -u
```

## CLI-only 裁決表（封閉列舉——#259 一次性補裁；12 命令＋1 旗標，`bootstrap-venues` 於 #367 新增時當場裁決，一格不多一格不少；`import-wos` 於 #290、`resolve-organizations` 於 #304 venue change 補 MCP 面後移列 MCP 表；`migrate-person-identity` 於 #227/#241、`migrate-venues` 於 #304 venue change 新增時當場裁決）

新增 CLI subcommand = 在這張表加一列（或補 MCP 面後在 MCP 表加一列）。兩個
裁決用語：**維運例外**＝要求操作者在檔案系統與版控旁（git 退路、人工
pre-flight）的操作，MCP 的 LLM 消費者不是該角色；**候補缺席**＝目前無 MCP 端
消費流程，需求出現即重啟裁決（不是永久判死——重啟訊號刻意不形式化，那是使用
情境判斷）。

| CLI 能力 | 裁決 | 理由 |
|---|---|---|
| `view`（list／show） | 候補缺席 | 外延查詢對 agent 有潛在價值，但目前無 MCP 端消費流程 |
| `resolve-divergence` | 有理由缺席 | in-code 既有裁決（`AkashicService.recordDivergence` doc）：消歧含合併＋全庫改寫＋刪檔，tracked+clean 前提與人工確認屬 CLI／App 互動面 |
| `bootstrap-people` | 有理由缺席 | 批次建檔屬操作者規模；單筆由 `akashic_add_person` 覆蓋（#250）|
| `bootstrap-organizations` | 有理由缺席 | 批次建檔屬操作者規模（同 `bootstrap-people`）。原第二理由「org 建模先停（#63／#70）」已由 #304（2026-08-16）廢止——org 重啟後**單筆**建檔的 MCP 面已於 venue change 補齊（`akashic_add_organization`，見 MCP 表）；批次面維持 CLI-only |
| `bootstrap-venues`（#367） | 有理由缺席 | 批次建檔屬操作者規模（同 `bootstrap-people`／`bootstrap-organizations` 的既有裁決）。**三個 bootstrap 命令的裁決一致不是巧合**：它們的共同形狀是「掃全庫的 literal、按門檻建實體、dry-run 供人審」，而那個規模與審閱動作屬操作者，不是 LLM 消費面。單筆建檔的 MCP 面已有 `akashic_add_venue`（見 MCP 表） |
| `fmt` | 有理由缺席 | 全庫改寫＝維運例外 |
| `migrate` | 有理由缺席 | 格式遷移＝維運例外 |
| `migrate-provenance` | 有理由缺席 | 同上 |
| `migrate-person-identity`（#227/#241） | 有理由缺席 | 格式遷移＝維運例外（同 `migrate`／`migrate-provenance`）；且不可逆、要求 store 工作樹乾淨的人工 pre-flight，MCP 的 LLM 消費者不是該角色 |
| `migrate-venues`（#304 venue change） | 有理由缺席 | 格式遷移＝維運例外（同 `migrate` 族）；per-file trackedness pre-flight＋部署鏈（release → migrate → validate → 手動 bump format 11）屬操作者角色 |
| ~~`migrate-work-types`~~（#325，**已退場**） | 有理由缺席 → 退場 | 格式遷移＝維運例外（同 `migrate` 族）；不可逆、要求檔案受 git 追蹤的人工 pre-flight，MCP 的 LLM 消費者不是該角色。**#325 階段二起命令不存在**——它讀不到舊值（舊值在階段二的 decode 就被拒），留著只會是一個永遠無事可做卻看似可用的命令（`no-compat-fallback` 的「退場即刪」）。列保留但劃掉：刪掉會丟失裁決史，而那正是本檔存在的理由 |
| `validate` | 有理由缺席 | 讀取檢查由 `akashic_doctor` 覆蓋（功能重疊）|
| `rename` | 有理由缺席 | 高風險身分操作（citekey 遷移含 verdict value 重寫，#232）＝維運例外 |
| `authorize-names` | 有理由缺席 | 批次策展＝操作者規模 |
| `export-tables --view`（#274） | 有理由缺席 | 匯出物是檔案樹，MCP 的回傳形狀未定——#274 註記的正式落位 |

**機械檢查（CLI→MCP 方向）**：上方稽核程序的 ② 枚舉 CLI 全部註冊型別後，
每個命令必須出現在 **MCP 表的「CLI 對應」欄**或**本表**其中之一——兩處都
查無即是新長出的零裁決格（正是 #259 修掉的形狀）。

**機械檢查（表→命令方向，#325 補）**：前兩個方向都問「命令有沒有裁決」，
都抓不到**命令退場後留下的孤兒列**——一列描述著一個已不存在的命令的裁決，
讀起來與有效裁決毫無區別。第三個方向反過來問：

```bash
# 本表與 MCP 表「CLI 對應」欄提到的每個命令名，是否仍在 ② 的枚舉裡？
# 不在 → 該列必須標記退場（劃掉 + 寫明退場理由與 issue），**不是刪除**：
#   刪掉會丟失裁決史，而保留失敗史正是本檔存在的理由
#   （見全域 `common-spec-prose-enumeration` 執行細節 3）。
```

觸發過的實例：#325 階段二刪除 `migrate-work-types`（退場即刪，
`no-compat-fallback`），本表的那一列因此在同一個變更裡改為劃掉標記。
**這個方向是 #325 才補的**——#259 雙向化時只想到「命令長出來」，沒想到
「命令退場」，因為當時還沒有任何命令退場過。

## CLI 橫切選項裁決表（封閉列舉——#310 一次性補裁 2 項、#298 增第 3 項；恰 3 項，一格不多一格不少。**不得依性質相似類推第四項**）

前兩張表的行分別是「MCP tool」與「CLI subcommand」。**橫切選項兩者皆非**——它是
`ParsableArguments`，被所有帶它的 subcommand 共享，不屬於其中任何一個。所以問題從來
不是「該填哪張表」，是**沒有表可填**：`--library` 因此從未被裁決過，而稽核程序的 ②
（枚舉 subcommands 陣列）在結構上也讀不出這件事。這是收錄機制的洞，不是漏填一列。

新增橫切 `ParsableArguments` = 在這張表加一列。**「未決」同樣不是選項**（與前兩張表
一致）。裁決用語沿用 CLI-only 表的定義。

| CLI 能力 | 裁決 | 理由 |
|---|---|---|
| `--library`（`LibraryOptions`，橫切 42 個 subcommand）| 有理由缺席（#310）| **MCP 已有對等能力，只是粒度不同**：`akashic_files` 的 `use` action 是 session 級切換（改寫 `AkashicService` 的 `root`／`storeKey`，其後所有 tool 作用在新 universe；`testFilesUseSwitchesUniverseCompletely` 已斷言「舊 universe 內容不得洩入」），與 App 的 `AppState.switchFile(key:)` 同形。per-invocation 形式適合 CLI，是因為每次呼叫都是獨立 process、沒有可承載選擇的 session；MCP 與 App 都是長 session，**MCP 對齊的是 App 不是 CLI**。不補 per-call 參數的三個理由：(a) 對等能力已存在（上述）；(b) 選填參數對 LLM 消費端是**淨負**——省略即靜默落到預設 store，寫入類 tool 可能在呼叫者毫無察覺下寫錯，而 CLI 省略 `--library` 的人正看著自己的 shell；(c) 命名衝突（見下方註）使新參數必須另取名字，於是同一個 tool 並存兩個意義相近而所指不同的參數 |
| `--config`（`FileConfigOptions`，`file` 家族 4 個 subcommand）| 有理由缺席（#310）| **部署層決定，非呼叫層**：registry 檔的位置由 MCP server 的啟動環境（`AKASHIC_HOME`）決定；讓個別 tool 呼叫改指另一份 registry，等於讓 LLM 消費者改寫部署決定。與 `--library` 不同的是**這裡連 session 級的對等物都不需要**——切 registry 不是切 universe，是換掉一整組 universe 的名冊 |
| `--yes`（`LibraryOptions`，只對 6 個破壞性 subcommand 生效）| 有理由缺席（#298）| **閘門本身不作用於 MCP，所以它的出路也不需要**。`--yes` 是「破壞性 `--apply` 未指名目標 store 時的知情同意」的出路（#298 D4），而該閘門刻意只擋 CLI：CLI 的 `--apply` 是**篩選式批次掃蕩**，MCP 的 apply 收**逐 id 顯式指名**的清單——與本表上方 `resolve-people` 列已記錄的 tier 閘同型不對稱。#310 的「顯式性在 MCP 面恆為否」因此不綁：閘門不在那一面。若日後 MCP 長出篩選式批次寫入，該閘門與本旗標的 MCP 面須一併重新裁決 |

> **命名衝突（#315）**：`library` 這個字在兩面**意義不同**——CLI 的 `--library` 指
> **store root 路徑**；MCP 的 `library` 參數（`akashic_search`／`akashic_person` 等）
> 指 **store 內的 membership 分類**（#13）。所以就算日後推翻上表第一列的裁決，新參數
> 也**不能**叫 `library`。

**機械檢查**：稽核程序的 ④ 枚舉全部橫切 `ParsableArguments` 後，輸出的每一項都必須
出現在本表——查無即是新長出的零裁決格。

### 由上表衍生的一則事實：MCP 的 active store 是 session 狀態

上表第一列的裁決把一件事固定下來，而下游設計會需要它，所以在此寫成可直接引用的形式
（引用者不必回頭讀原始碼）：

> **MCP 面的 active store 是 session 狀態。** 它由 server 啟動時解析一次，並可在
> session **中途**經 `akashic_files` 的 `use` action 改變（改變後所有後續 tool 呼叫
> 都作用在新 store）。**呼叫端不會在每次呼叫時重新宣告它** —— 依上表裁決，MCP tool
> 沒有、也不會有 per-invocation 的 store 參數。

**直接後果**：任何以「**本次呼叫有沒有顯式指定 store**」為判準的機制，在 MCP 面
**恆為否**，因此不可作為判準。若某個閘門以此為條件，它在 MCP 面只會退化成兩種都錯的
結果——一律擋（所有寫入類 tool 失效）或一律豁免（LLM 消費面完全不設防，而它的呼叫量
與誤呼叫機率都高於人工 CLI）。

**這則事實不裁決替代方案。** 它只說明「顯式性」為什麼不能用；該用什麼判準屬於提出該
閘門的變更（#298）的範圍，不在本規則內。

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
