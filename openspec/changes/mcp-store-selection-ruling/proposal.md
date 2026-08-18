## Why

`.claude/rules/mcp-cli-parity.md` 要求「新增或修改任一面的能力時必須裁決另一面」，而
CLI 的 `--library` 從未被裁決過——它是橫切全部 subcommand 的 `ParsableArguments`，
不是具名 subcommand，所以該規則的逐命令機械稽核程序**結構上掃不到它**。兩張裁決表
因此對這一格沉默至今。

調查同時推翻了 #310 對現況的描述：**MCP 面已經有 store 選擇**——`akashic_files`
的 `use` action 會改寫 `AkashicService` 的 `root` 與 `storeKey`，其後所有 tool 都
作用在新 universe，且 `Tests/AkashicMCPTests/ServiceTests.swift` 的
`testFilesUseSwitchesUniverseCompletely` 已斷言「舊 universe 內容不得洩入」。所以
待裁決的問題不是「MCP 有沒有 store 選擇」，而是「已有 session 級選擇的前提下，要不要
再加 per-invocation 形式」。

**盲點藏了不只一格**：為了設計稽核修補而枚舉橫切型別時，`--config`
（`FileConfigOptions`，`file` 家族 4 個 subcommand 使用）當場一併現形，同樣從未被
裁決。同型缺陷成對出現，而只有先寫下量測方法才會看見第二個。

**現在做的理由**：#298（破壞性操作的確認閘）擋在這個裁決後面。它原本設想的閘判準是
「`--library` 有沒有被顯式給定」，而該判準在 MCP 面恆為否，會退化成「一律擋」或
「一律豁免」兩種都錯的結果。裁決一旦落地，#298 就能改用不依賴該判準的設計。

## What Changes

- **裁決 `--library`：不新增 per-invocation 的 store 參數到 MCP tool**，理由是 MCP
  已有與 App 同形的 session 級選擇，而 per-invocation 形式對 LLM 消費端是淨負。裁決
  連同理由寫進 `.claude/rules/mcp-cli-parity.md`
- **裁決 `--config`：同為有理由的缺席**，registry 檔位置是部署層決定，MCP 面由啟動
  環境決定而非呼叫層
- **新增第三張裁決表涵蓋橫切選項**——現行兩張表的行分別是「MCP tool」與「CLI
  subcommand」，跨全部 subcommand 的 `ParsableArguments` 兩處都不屬於，於是無處可寫
- **修補該規則的機械稽核程序**：現行步驟只枚舉 subcommands 陣列的註冊型別，新增一步
  枚舉 `ParsableArguments` 型別，使橫切選項無法再安靜地不被裁決
- **記錄 #298 的解耦事實**：MCP 面的 store 是 session 狀態且可在 session 中途改變，
  所以任何「以呼叫時有沒有顯式指定 store」為判準的閘在 MCP 面不成立
- **記錄 `library` 這個名字在兩面意義不同**（CLI＝store root 路徑；MCP＝store 內的
  membership 分類），交叉指向 #315

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

(none)

本裁決的正典位置是 mcp-cli-parity 規則檔（路徑見下方 Impact），不是 openspec 的
capability spec。這是刻意的：該規則檔已是雙面裁決的 source of truth，把同一條規範再寫
一份進 capability spec 會製造兩份會分岔的規格——正是 entity-backlink-completeness 規則
反覆記錄過的失敗形狀。

## Impact

- Affected specs: 無（見上方說明）
- Affected code:
  - Modified: `.claude/rules/mcp-cli-parity.md`
  - New: 無
  - Removed: 無
- 被本裁決解除阻擋、但**不在本次範圍**：#298 的確認閘設計、#315 的命名衝突
- 被引用為證據而不修改：`Sources/akashic-mcp/Server.swift`、
  `Sources/AkashicMCPKit/AkashicService.swift`、`Sources/akashic/CLI.swift`、
  `Sources/akashic/FileCommands.swift`、`Sources/AkashicAppKit/AppState.swift`、
  `Tests/AkashicMCPTests/ServiceTests.swift`
