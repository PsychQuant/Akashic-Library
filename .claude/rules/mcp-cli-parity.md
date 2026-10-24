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
   `AkashicService` 函式、`key:` 必帶（**封閉例外，只有 `akashic_s2`／`s2` 這一列**：兩面同一個
   不經服務層的 library 函式（`AkashicS2`）、沒有 `key:`，理由見該列；**不得依「也不開 store」
   類推第二列**——新的工具要走這條，得在本檔顯式加一列、寫出它為什麼不能經服務層）；**讀取面**須 `--json` 原樣轉印 + 人可讀同源。**寫入面是封閉例外**：只回
   service payload、不設 `--json` 旗標也無人可讀分支——`link`／`tag`／`set-status` 即此形；例外只有這一類，不得類推），**並在
   下表加一列**；或
2. **記錄一個有理由的缺席**——開 issue 載明為什麼這個能力可以只有 MCP 面
   （判準見下），並在下表加一列指向該 issue。

**「未決」不是第三個選項**：它曾保留給本規則落地**之前**已存在的工具（#250
兩列的過渡態，2026-08-15 已裁決補齊——第一次演練）。規則生效後新增的工具必須
當場二選一；表中現無未決格。

**判準不是「MCP 有的 CLI 都要有」**——那是機械對稱，會製造沒人用的命令。判準是：

> 這個能力的可用性，該不該取決於使用者用的是 MCP 還是 CLI？

（#206 對匯入面的原話：「能不能無損匯入，不該取決於使用者會不會寫 script。」）

## 裁決史（MCP 工具表，已搬出）

本段已搬到 [`docs/rulings/mcp-cli-parity.md`](../../docs/rulings/mcp-cli-parity.md)（不自動載入）；需要查過往裁決或新增一列時讀那份檔。本檔其他段落說的「下表」「上表」「這張表」指那份檔裡的表。

新增下一個工具 = 在這張表加一列。**不得依性質相似類推**「這個工具顯然不用 CLI」
——那個判斷要寫成表裡的一列（含理由或 issue 編號），不能只存在腦中。

**工具描述有位元組預算（#578，2026-09-28）**：`tools/list` 回應整行不得超過 65,000 bytes（2026-09-28 訂為 49,000：精簡當下實測 39,164 × 1.25、進位到千。39,164 是補上 #670 兩個旗標的描述之前量的；`ee29fe47` 出貨時實測 39,285，照同一公式會得 50,000、超過單一 MCP 輸出的 48 KiB。當時預算維持 49,000、待使用者確認——#578 R1 verify DA。**2026-09-29 使用者裁決調高到 52,000**：#672 讓描述點名每一個回應鍵、#664 多一個工具，合併後實測 49,346；52,000 越過 2026-09-28 刻意守住的 48 KiB 線，那條線是本 repo 對單一工具回應的上限，不是 client 對 `tools/list` 的上限。**2026-10-01 使用者裁決再調高到 54,000**：整合 #695／#705／#703 的 R1 修正與 #700、#710 之後實測 51,997、只剩 3 bytes，而同日裁決的 #557（新工具）、#559（新參數）、#611（報告新鍵）估計共需約 1 KB；沒選的是「削既有描述騰空間」與「新面先只做 CLI」。**2026-10-01 晚使用者裁決再調高到 60,000**：整合 #564、#611 R1 修正後實測 54,235，修剪後 53,939、只剩 61 bytes，同日第三次撞上；修剪是把契約移到 CLI `--help`，只講 MCP 的 client 讀不到，結構性解法另開 #713（按需讀完整說明的 MCP 工具）；沒選 64,000 與維持 54,000）。**2026-10-21 使用者裁決再調高到 65,000、不拆分 MCP server**（#578；觸發點是 #742 的 `replace_authors`，當時 main 實測 59,159、只剩約 840 bytes；拆成讀寫兩個 server 不採——active store 是各 server 的 session 狀態，拆開會讀一個 store、寫另一個而不出聲；下次接近預算先瘦 input schema 再考慮提高；#742 接上後實測 59816），由 `StdioE2ETests.testToolsListResponseStaysWithinByteBudget` 走真 binary 量。#578 的 Expected 寫的是「源碼掃描守衛」，改用真 binary 量測是刻意的替代（R1 verify requirements 席指出這一點沒有寫出來）：呼叫端付的是 server 實際送出的那一行，源碼字串字面的加總量不到 input schema 的結構與 JSON 編碼，也會把不在那一行裡的字串算進去；這支測試在 pre-push 的 `swift test` 裡跑，超過即紅。描述只寫做什麼、輸入格式、拒絕類別、store format 與呼叫端要讀的回應鍵，完整契約指向 CLI `--help` 與 docs/store-format.md §3.5（只講 MCP 的 client 讀不到前者，#713 補按需說明）；裁決史與理由留在本檔與 changelog。要調高預算回 #578 重新裁決。

**每個回應鍵都要出現在該工具的說明裡（#672，2026-09-29）**：`ToolPayloadKeyGuardTests` 對每個工具走各條主要的腿（`ToolPayloadScenarios`，fixture store 上的真實呼叫），取回應的頂層鍵（陣列取元素鍵），要求每一個以**識別字邊界**（不是子字串）出現在該工具在真 binary `tools/list` 裡的說明文字——`description` 加各參數的 `description`，呼叫端讀得到的就是這兩處。刻意不寫的鍵在 `ToolPayloadKeyExemptions` 逐鍵具名、附理由（`echo`、`advisory`、`standard` 三種，封閉列舉；豁免本身也被守衛：鍵必須真的出現在 payload、且真的沒被說明提到，否則紅）。新增工具要同時加情境（工具清單與情境對不上即紅），既有工具長出新參數也要（#700，見下）；新增回應鍵要同時補說明（只寫鍵名加一句意思）或豁免。**它與上面的位元組預算是同一件事的兩個約束**：鍵名只能寫進說明、預算又不許長，所以新鍵的那句話要從別處省。**沒涵蓋的腿**（誠實邊界）寫在測試檔頭：只在特定 store 狀態才出現的鍵、`akashic_files` 的 `use`、錯誤回應，以及**封閉表以外的巢狀鍵**。**#700 起巢狀鍵只看一張封閉表**（`ToolPayloadNestedPaths`，使用者 2026-09-30 裁決 (a)）：`akashic_enrich` 的 `items[]`、`akashic_resolve_people` 的 `people[ref]`、`akashic_update_entry` 的 `sourcesAdded[]`、`akashic_update_venue` 的 `nameSegments[]` 與 `displayNameChanged`、`akashic_person` 的 `person`，各往下恰好一層、每一列寫明為什麼那一層的鍵要說明；表外的巢狀物件不遞迴（無差別遞迴要把幾百個鍵寫進說明，預算放不下），列入的路徑也不看第二層。巢狀鍵的比對與頂層同一條規則（鍵名在該工具說明的任何一處出現就算數，不要求寫成 `items[].<鍵>`）。**同輪另一半是 `ToolPayloadLegTests`：每條腿都要有情境**——MCP 工具的每個參數（真 binary 的 `inputSchema`）要有情境宣告它，或在 `ToolPayloadLegs.unexercised` 寫理由；CLI 裁決表（`WriteGateRulings`）的每一個寫入命令與三個逐腿命令的每條寫入腿，要對到一個有情境宣告的 MCP 參數，或寫明只有 CLI。#675 的 `edit_name_segment` 那一類（既有工具長出新腿而沒有情境）自此會紅；**擋住它的是參數那一半**——`update-venue` 在裁決表裡是命令層的一格，逐腿表只涵蓋三個 resolve 命令。第一次跑就抓到一條：`akashic_update_entry` 的 `remove_zotero_sources`（#680）沒有情境，它回應的 `zoteroSourcesRemaining`／`zoteroSourcesRemainingTotal` 也不在說明裡。

### 怎麼機械檢查這張表真的封閉

不要相信作者窮舉過（`entity-backlink-completeness` 的表錯過兩次，教訓同形）：

```bash
# ① MCP 面的全部工具名（2026-09-29 #664 量：恰 34；2026-10-01 #557 加 akashic_update_organization 後 35，與表零差集）。字元類要含 0-9：
#    `akashic_s2` 是第一個名字帶數字的工具，先前的 `[a-z_]+` 在 Server.swift 與表兩邊
#    一起漏掉它——兩邊的數字仍然相等（33 對 33），什麼都不會紅
grep -oE 'Tool\(name: "akashic_[a-z0-9_]+"' Sources/akashic-mcp/Server.swift | sort -u
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

## CLI-only 裁決表（封閉列舉——#259 一次性補裁；**列數以下表為準、表頭不寫死**（#422 verify R1 實測表頭的「12 命令＋1 旗標」與表已漂移多列——同 `entity-backlink-completeness` 對條數的既有作法：複述過的數字會與表分岔）；`bootstrap-venues` 於 #367 新增時當場裁決；`import-wos` 於 #290、`resolve-organizations` 於 #304 venue change 補 MCP 面後移列 MCP 表；`migrate-person-identity` 於 #227/#241、`migrate-venues` 於 #304 venue change 新增時當場裁決）

新增 CLI subcommand = 在這張表加一列（或補 MCP 面後在 MCP 表加一列）。兩個
裁決用語：**維運例外**＝要求操作者在檔案系統與版控旁（git 退路、人工
pre-flight）的操作，MCP 的 LLM 消費者不是該角色；**候補缺席**＝目前無 MCP 端
消費流程，需求出現即重啟裁決（不是永久判死——重啟訊號刻意不形式化，那是使用
情境判斷）。

本表的列（CLI 能力／裁決／理由）已搬到 [`docs/rulings/mcp-cli-parity.md`](../../docs/rulings/mcp-cli-parity.md)（不自動載入），接在 MCP 工具表後面；新增 CLI subcommand 時在那裡加一列。下面兩段說的「本表」指那份檔裡的這張表。

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

## 識別碼寫入面的裁決（已搬出）

本段（識別碼欄位的寫入面裁決與它的理由，#394）已搬到 [`docs/rulings/mcp-cli-parity.md`](../../docs/rulings/mcp-cli-parity.md)（不自動載入）；需要查過往裁決時讀那份檔。

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
| `--yes`（`LibraryOptions`，對 `DestructiveTargetGate.destructiveCommands` 列的 subcommand 生效——**#658 起那個集合由裁決表現算**：`WriteGateRulings.swift` 對 CLI 每一個葉命令記一格（過閘／不閘並寫出這一格自己的理由／不寫 store），逐腿命令另逐腿記一格（#564 b34 起六個：三個 resolve 族與 `update-person`／`update-organization`／`update-venue`）；`WriteGateRulingsTests` 以執行期的命令樹與旗標雙向比對，新命令或新腿沒有裁決即紅，本旗標的說明也由同一張表產生。個數不寫死（R21 verify 第 33 列寫死過「6 個」、之後又寫過「11 個」，兩次都過期）；**#580 裁決**：閘防的是**寫錯 store**，不是寫錯哪幾筆——從錯的 store 列出來的 id 在錯的 store 上全部對得上，所以逐 id 的寫入腿同樣要閘（比照 `enrich`／`enrich-from-zotero` 的既有裁決）。`resolve-venues` 的全部寫入腿與 `authorize-names --apply`（R1 verify：布林全庫掃蕩，因宣告寫成 `: Bool` 漏在稽核外）自 #580 起在表內，`resolve-organizations` 的篩選式 `--reject` 也閘。**#653 裁決（使用者 2026-09-27）：只閘不可逆的**——點名的是全庫改寫的合併、改名、格式遷移一族，自此在表內（預設就寫的在不帶乾跑旗標時閘，拒絕訊息指向那個乾跑旗標；沒有乾跑的改名，訊息說明它沒有預覽模式）。~~**表外不是每一個都可逆**：`resolve-people` 的移除作者位沒有具名逆操作、Zotero 匯入會覆寫欄位與作者——這兩個閘不閘、以及稽核怎麼抓到新的未閘寫入命令，記在 #658。~~ → **#658 裁決（使用者 2026-09-28）：`resolve-people --drop-author` 與 `import-zotero` 過閘**——前者沒有具名逆操作、被移除的作者位不留位置（#457）；後者整份替換 `fields`、覆寫未歸戶的 literal 作者，而且沒有乾跑（無條件閘，拒絕在建佈局之前）。稽核那一半見本格開頭的裁決表。其餘不閘的寫入面，理由寫在裁決表的那一格，**不宣稱可逆**：「可逆」的界線沒有一句可機械判定的判準（`resolve-people` 的逐篇判定就沒有把作者位退回 literal 的工具面），待裁。這裡刻意不逐一點名命令——本檔的稽核把反引號裡的命令名當成裁決列的引用（#580 R1 寫過「不閘的只有一類」，當場被找到六個反例）。**本列先前的兩句是錯的**：「`resolve-venues` 的 `--apply` 正是篩選式批次掃蕩」（它收 id 清單）、「`rename-person` 沒有這道閘」（它無條件呼叫）；`rename` 先前沒有閘而 `rename-person` 有——#650，隨 #653 補上，兩者都在表內）| 有理由缺席（#298）| **閘門本身不作用於 MCP，所以它的出路也不需要**。`--yes` 是「破壞性寫入未指名目標 store 時的知情同意」的出路（#298 D4；#580 起涵蓋 `resolve-organizations --reject` 與 `resolve-venues` 的各寫入腿，#658 起涵蓋 `resolve-people --drop-author` 與 `import-zotero`，#564 b34 起涵蓋 `update-person`／`update-organization` 的 `--remove-name` 與 `update-venue` 的 `--remove-issn`／`--remove-reference`／`--edit-name-segment` 帶 remove 的呼叫——使用者 2026-10-05 裁決：會刪判定記錄的面過閘），而該閘門刻意只擋 CLI：MCP 的 active store 是 session 狀態、「本次呼叫有沒有顯式指定」恆為否（#310），CLI 則每次呼叫獨立解析——閘防的寫錯 store 只在 CLI 那一面有「每次重新解析」這個形狀。（先前這裡的理由是「CLI 的 `--apply` 是篩選式掃蕩、MCP 收逐 id 清單」——#580 把逐 id 的 `resolve-venues`／`enrich` 也放進閘之後，那個理由不再成立。）若日後 MCP 長出篩選式批次寫入，該閘門與本旗標的 MCP 面須一併重新裁決 |

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
