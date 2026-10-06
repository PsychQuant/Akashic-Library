## Why

使用者有 Semantic Scholar（S2）的 API 金鑰，想讓 Akashic 能用它查詢（#664）。S2 提供的引用關係、相似作品、作者著作清單，正是往回追的第三來源（#640）、往前追（#620）、相似作品（#621）、作者著作（#622）與書目補欄（#665）需要的。可是 Akashic 目前沒有任何安全帶金鑰的外部查詢路徑：本體不連網，skill 層一律經 safari-browser；而頁內 fetch 得把金鑰放進 `safari-browser js` 的指令參數，會外露（#640 指出）。如果讓各 skill 各自實作，金鑰處理與節流會出現多份不一致的做法。

## What Changes

- **新 library target `AkashicS2`**：Akashic 本體裡唯一可以連網、唯一可以讀 keychain 的地方。它負責下列幾件事：
  - 八個 S2 端點（`paper`、`search/match`、`batch`、`references`、`citations`、`recommendations/forpaper`、`author/search`、`author/{id}/papers`）與它們的分頁
  - 從 keychain 讀取金鑰
  - host 白名單，以及只對 `api.semanticscholar.org` 附上 `x-api-key` 的規則
  - 跨程序節流與共用的 429 退避
  - 外部字串清理
- **CLI 子命令群 `akashic s2`**：八個端點各一個具型別的子命令，外加 `status`。`status` 只回報金鑰存在、可讀，以及節流狀態，不印出金鑰。輸出預設人可讀，加 `--json` 則原樣輸出。
- **MCP 工具 `akashic_s2`**：與 CLI 共用同一個 `AkashicS2`，不經 `AkashicService`。輸出上限 48 KiB，只回完整的筆數，以 `total`／`returned`／`truncated` 揭露截斷，並附下一頁的 `offset`。
- **沒有金鑰時**：兩面都停下，以專用的結束碼或錯誤結果回報，訊息寫明 keychain 的 service／account，並指向設定文件；不退回匿名請求。
- **離線本體的守衛**：新增 `akashic-guards network-confinement` 與它的負對照 `network-confinement-mutations`。`URLSession`／`URLRequest`／Network framework 與 Security framework 只准出現在 `Sources/AkashicS2/`。
- **規則同步**：
  - `web-access-via-safari-browser.md`：第 2 條改為只有 `AkashicS2` 例外；例外清單從一類改為兩類；「不適用」第 2 類改寫，因為 `akashic s2` 會連網
  - `mcp-cli-parity.md`：MCP 表加一列，33 → 34
  - `CLAUDE.md`：規則索引同步
- **設定文件**：`plugin/skills/akashic-bootstrap/references/semantic-scholar.md`，給其他 Akashic 使用者：怎麼存金鑰、為什麼 ACL 要設成所有 app 可讀、怎麼用 `akashic s2 status` 確認。

## Non-Goals (optional)

見 design.md 的 Goals／Non-Goals。

## Capabilities

### New Capabilities

- `semantic-scholar-interface`：S2 共用接口的行為契約，涵蓋八個端點、兩個面、金鑰讀取與 host 規則、跨程序節流與 429 退避、MCP 輸出上限，以及沒有金鑰時的行為
- `offline-core-confinement`：本體除了 `AkashicS2` 以外不連網、不讀 keychain，由守衛機械地檢查，並附負對照證明守衛會開火

### Modified Capabilities

(none)

## Impact

- Affected specs: semantic-scholar-interface（新）、offline-core-confinement（新）
- Affected code:
  - New:
    - Sources/AkashicS2/S2Client.swift
    - Sources/AkashicS2/S2Endpoints.swift
    - Sources/AkashicS2/S2KeyProvider.swift
    - Sources/AkashicS2/S2Throttle.swift
    - Sources/AkashicS2/S2Output.swift
    - Sources/AkashicS2/S2Tool.swift
    - Sources/akashic/S2Commands.swift
    - Sources/akashic-guards/NetworkConfinement.swift
    - Sources/akashic-guards/NetworkConfinementMutations.swift
    - Tests/AkashicS2Tests/S2ClientTests.swift
    - Tests/AkashicS2Tests/S2ThrottleTests.swift
    - Tests/AkashicS2Tests/S2OutputTests.swift
    - Tests/AkashicS2Tests/S2SessionHardeningTests.swift（verify R1）
    - Tests/AkashicS2Tests/AAASandboxGuardActivation.swift
    - Tests/AkashicCLITests/S2CommandTests.swift
    - Tests/AkashicMCPTests/S2ToolTests.swift
    - plugin/skills/akashic-bootstrap/references/semantic-scholar.md
  - Modified:
    - Package.swift
    - Sources/akashic/CLI.swift
    - Sources/akashic-mcp/Server.swift
    - Sources/akashic-guards/main.swift
    - .githooks/run-guards.sh
    - .claude/rules/web-access-via-safari-browser.md
    - .claude/rules/mcp-cli-parity.md
    - CLAUDE.md
    - README.md
    - Sources/akashic-guards/ParityTableDrift.swift（名稱 regex 允許數字）、.githooks/protected-ratchet.txt（守衛接線）
    - Sources/akashic/WriteGateRulings.swift（九個 `s2` 葉命令登記為唯讀）
    - Tests/AkashicCLITests/CLITestHarness.swift（`s2` 呼叫的預設測試 service 與暫存狀態目錄）
    - Tests/AkashicMCPTests/StdioE2ETests.swift（工具數 33 → 34）
    - plugin/skills/akashic-bootstrap/SKILL.md、plugin/skills/akashic-bootstrap/references/web-access.md（把使用者 2026-09-29 的取得順序裁決帶給 plugin 讀者；不是接線，見 design〈verify R1 偏離〉）
