## Context

`akashic` 有三個消費面，各自的 store 選擇粒度不同：

| 面 | 粒度 | 選擇方式 | 位置 |
|---|---|---|---|
| CLI | per-invocation | `--library <path>` | `LibraryOptions`（橫切 42 個 subcommand）|
| App | per-session，可中途切換 | `switchFile(key:)` | `AppState` |
| MCP | per-session，可中途切換 | `akashic_files(action:"use", key:)` | `AkashicService.files` |

`#310` 假設 MCP 面「沒有任何 per-invocation 的 library 選擇」並據此推論它缺能力。前半句
為真，後半句不成立——MCP 有的是 **session 級**選擇，與 App 同形：`use` 分支改寫
`AkashicService` 的 `root` 與 `storeKey`（`AkashicService` 是 `final class`，故 server
actor 持有的 `let service` 仍看得到變更；`store` 是 computed property，每次呼叫依當下
的 `root`/`storeKey` 現造 `LibraryStore`）。`testFilesUseSwitchesUniverseCompletely`
斷言切換後舊 universe 的內容不得洩入，該測試現為綠。

真正從未被裁決的是 `--library` 這一格本身。`.claude/rules/mcp-cli-parity.md` 的兩張表
以「MCP tool」與「CLI subcommand」為行，而 `--library` 兩者皆非——它是
`ParsableArguments`。規則的機械稽核程序枚舉的是 subcommands 陣列的註冊型別，因此
結構上永遠掃不到橫切選項。這不是漏填一列，是收錄機制本身有洞。

同一個洞另外藏著 `--config`（`FileConfigOptions`，`file` 家族使用），同樣從未被裁決。

## Goals / Non-Goals

**Goals:**

- 對 `--library` 與 `--config` 兩個橫切選項各給一則有記錄的裁決，連同理由寫進規則檔
- 讓規則的機械稽核程序涵蓋橫切選項，使同型缺口不能再安靜累積
- 把「MCP 的 store 是 session 狀態」這個事實寫成規則檔內可被引用的記錄，供 #298 的閘
  設計使用

**Non-Goals:**

- **不實作**任何 MCP 端的行為變更。本 change 只動 `.claude/rules/mcp-cli-parity.md`
- **不設計** #298 的確認閘。本 change 只提供它需要的裁決前提
- **不處理** #315 的命名衝突（`library` 在兩面意義不同）。只在裁決列裡交叉指向它
- **不新增** `openspec/specs/` 的 capability。裁決的正典位置是規則檔，複製一份進
  capability spec 會製造兩份會分岔的規格
- **不改** `akashic_files` 的既有行為，也不新增 store 狀態的 in-band 回音——後者是
  #298 的範圍

## Decisions

### MCP 不新增 per-invocation 的 store 參數

**選擇**：有理由的缺席。

**理由（三條，強度遞減）**：

1. **MCP 對齊的是 App，不是 CLI。** CLI 的 per-invocation 形式之所以自然，是因為每次
   呼叫都是獨立 process，沒有可承載選擇的 session。App 與 MCP 都是長 session，兩者都
   用「切換即整個 universe 換掉」的模型。MCP 已經有它，且與 App 逐字同形。
2. **per-call 選填參數對 LLM 消費端是淨負。** 省略即靜默落到預設 store——寫入類 tool
   因此可能在呼叫者毫無察覺下寫錯 store。CLI 的 `--library` 沒有這個風險，因為省略它
   的人正看著自己的 shell。
3. **命名衝突使它更糟。** `library` 在 MCP schema 已是 store **內**的 membership 分類
   （`akashic_search` / `akashic_person` 等）。新參數必須另取名字，於是同一個 tool 的
   schema 會並存兩個意義相近而所指不同的參數——那本身就是誤用來源（#315）。

**被否決的替代方案**：

- **給 28 個 tool 各加一個選填的 store 參數**（issue 的「補對等能力」字面讀法）。除了
  上述理由 2、3，它在介面深度上也不成立：該參數不隱藏任何行為，只把 `root`/`key`
  轉手給 `AkashicService` 的建構子；刪掉它不會有任何東西壞掉。
- **改成必填**可消除靜默寫錯，但那是 28 個 tool 的破壞性 schema 變更，代價與收益不成
  比例。

### --config 同為有理由的缺席

registry 檔的位置是**部署層**決定，不是呼叫層。MCP server 由操作者啟動，啟動環境
（`AKASHIC_HOME`）已決定它讀哪一份 registry；讓個別 tool 呼叫改指另一份 registry，等於
讓 LLM 消費者改寫部署決定。與第一則裁決同理由，但論據更短：這裡連 session 級的對等物都
不需要。

### 橫切選項需要自己的裁決表

現行兩張表的行是「MCP tool」與「CLI subcommand」。橫切選項兩者皆非，所以問題不是
「該填哪張表」而是「沒有表可填」。新增第三張表，行為「CLI 橫切選項」，欄位與現行表
同構（能力／裁決／理由）。

**被否決的替代方案**：把 `--library` 塞進 CLI-only 表。該表的機械檢查程序是
「subcommands 陣列的每個命令必須出現在兩表之一」，塞一個非 subcommand 的行進去會讓
那條檢查對不齊——修一個洞會弄壞另一個檢查。

### 稽核程序增加橫切型別的枚舉步驟

現行程序枚舉 MCP 的 `Tool(name:)` 與 CLI 的 subcommands 陣列。新增一步枚舉宣告為
`ParsableArguments` 的型別，其輸出必須逐一出現在新表中。

這一步在設計階段就已證明自己：寫下它的當下就撈出了 `--config` 這個從未被裁決的第二格。

### MCP 的 store 是 session 狀態

規則檔內記下一則可被引用的事實：MCP 面的 active store 是 session 狀態、可在 session
中途經 `akashic_files` 的 `use` 改變，且**呼叫端不會在每次呼叫時重新宣告它**。因此任何
以「本次呼叫有沒有顯式指定 store」為判準的閘，在 MCP 面恆為否，不可作為判準。

## Implementation Contract

**行為**：本 change 的產出是規則檔內容，無 runtime 行為變更。可觀察的結果是：跑該規則
的機械稽核程序時，橫切選項會被枚舉出來，且每一個都能在規則檔中找到對應的裁決列。

**介面／資料形狀**：

- `.claude/rules/mcp-cli-parity.md` 新增一節，含一張表，行為 CLI 橫切選項，欄位為
  「CLI 能力」「裁決」「理由」，與該檔既有兩張表同構
- 該表必須是**封閉列舉**並明寫封閉性（依全域 `common-spec-prose-enumeration` 的要求），
  初始恰有兩列：`--library`（`LibraryOptions`）與 `--config`（`FileConfigOptions`）
- 稽核程序一節新增一個枚舉步驟，其形式與既有步驟一致：一條可貼進終端機執行的命令，
  外加一句說明「輸出中每一項都必須出現在橫切選項表」

**失敗模式**：稽核程序輸出一個不在表中的型別 → 表壞了（未裁決的新橫切選項），與該檔
既有兩張表的失敗語意一致。此判定是人工執行的，不是 CI 閘——與該規則其餘部分同層級。

**驗收條件**：

1. 執行新增的枚舉步驟，輸出恰為 `LibraryOptions` 與 `FileConfigOptions` 兩項，兩者
   都能在新表中找到對應列
2. 新表的每一列都寫出裁決（不得留「未決」——該檔明文規定「未決」不是選項）與理由
3. 新表明寫封閉性且註明「不得依性質相似類推」
4. 規則檔內可以找到裁決五的那則事實，措辭足以讓 #298 的設計者引用而不必回頭讀原始碼
5. 該檔既有的兩張表與兩條機械檢查程序未被改動——本 change 是**新增**一張表與**新增**
   一個稽核步驟，不重寫既有內容

**範圍邊界**：

- 範圍內：`.claude/rules/mcp-cli-parity.md` 的新增內容
- 範圍外：任何 `Sources/` 下的檔案、任何測試、`openspec/specs/` 的任何 capability、
  #298 的閘設計、#315 的重新命名

## Risks / Trade-offs

- **裁決可能在未來被推翻**（有人真的需要在單一 session 內交錯操作兩個 store）→ 緩解：
  裁決列寫明它依賴的前提（「MCP 是長 session，且切換是模式變更」），前提若不成立即為
  重啟裁決的訊號。這與該檔既有「候補缺席」的用語一致
- **新表的機械檢查仍是人工執行**，與既有兩張表同樣不是 CI 閘 → 緩解：不在本 change
  解決。要全機械化需要 manifest 或讀 `CommandConfiguration` 的測試，該檔已在既有討論
  中記錄此限制（#259），本 change 不擴大它也不假裝修好它
- **`ParsableArguments` 的枚舉可能有假陰性**（若日後有人用其他方式宣告橫切選項）→
  緩解：這正是既有稽核程序踩過的坑（第一版寫 `[A-Za-z]+Cmd?\.self` 只命中 11/30），
  新步驟的說明中要註明它枚舉的是宣告式，不是所有可能的橫切機制

## Open Questions

無。五則裁決在 `/spectra-discuss` 中已逐條確認。
