## Why

AkashicKit 目前只能在 macOS 建置。使用者要把建置與測試分到 Linux 機器（Ubuntu 22.04 與 24.04、x86_64，包括沒有 root 的機器）上跑，減輕本機負載；package 先要能在 Linux 建置、測試要能在那裡全數通過，這件事才用得上（#794）。

使用者 2026-11-11 已裁決四件事：兩個 Ubuntu 版本都要；只能在 macOS 跑的測試標明略過，其餘在 Linux 全部通過；macOS 專屬的能力（keychain、經 Safari 取全文）留著、在 Linux 執行時回具名錯誤；Linux 的建置與測試進 CI。2026-11-12 以 Swift 6.0.3 與 6.4.2 的官方映像做過一次拋棄式試作，量出要改的地方與三個會改變產品行為的差異（CRLF 切行、`sources/` 放置閘的系統呼叫、plugin hook 的 BSD `stat`）。

## What Changes

- **建置**：`Package.swift` 宣告兩個新的相依套件（swift-crypto、swift-toolchain-sqlite），兩者的 product 只在 Linux 掛上；兩個平台共用同一份 `Package.resolved`。App 的兩個 target 與 Unicode 表產生器在 Linux 不宣告。Linux 上支援的最低 Swift 是 6.4，低於它在編譯期具名失敗。
- **CryptoKit／SQLite**：雜湊在 Linux 改用 swift-crypto 的同名 API；SQLite 在 Linux 改連 swift-toolchain-sqlite（SQLite 原始碼隨套件編進來，不需要系統的開發套件或 root）。macOS 照舊用 CryptoKit 與系統的 SQLite。
- **`sources/` 的放置閘**：Linux 以 `renameat2(RENAME_NOREPLACE)` 做不覆寫的原子放置（純 Swift 經 `dlsym` 取得），不支援時退到 `link(2)`，再不行就具名拒絕；同步用 `fsync(2)`。閘在兩個平台都不比現在寬。本 repo 不新增任何 C 程式碼。
- **跨平台行為一致**：新增共用的切行函式，行為與 macOS 目前 `components(separatedBy: "\n")` 的結果逐位元組相同，取代 `Sources/` 的 39 個呼叫點；以 CoreFoundation 區分 JSON 布林與數字的判讀集中到一個函式，兩個平台給同一個答案。
- **macOS 專屬能力**：`akashic s2`／`akashic_s2` 在 Linux 讀金鑰時回具名錯誤，不叫人去跑 macOS 的 `security`；`akashic fulltext fetch` 在 Linux 於任何寫入之前具名失敗。命令與選項照樣存在。
- **可刪檢查**：歧異合併的「檔案可不可以刪」在 Linux 讀 `FS_IOC_GETFLAGS` 的 immutable／append-only 旗標。
- **plugin hook**：`plugin/hooks/check-cli.sh` 讀檔案時間與連結數的 `stat` 改成 GNU 與 BSD 都能用的寫法。
- **測試**：只能在 macOS 跑的測試逐支以具名理由略過；其餘以可攜的做法改寫（共用的 test products 定位、loopback HTTP server、以目錄權限注入刪除失敗、`getrusage` 量記憶體）。新增守衛：Linux 上被略過的測試集合必須等於一份審過的清單。
- **守衛**：`akashic-guards` 維持零相依，以自帶的 SHA-256 與切行函式取代 CryptoKit 與 Foundation 的切法。
- **警告**：6.4.2 在 Linux 的 18 個警告位置全部修掉，Linux 也以 `-warnings-as-errors` 建置。
- **CI**：新增 Linux workflow，以 digest 釘住 `swift:6.4.2-noble` 與 `swift:6.4.2-jammy`，以非 root 使用者建置與測試，並檢查鎖定檔沒有漂移。

## Capabilities

### New Capabilities

- `linux-platform-support`: Linux 上的建置契約（支援的 Ubuntu 與 Swift 版本、相依與鎖定檔、編譯期的版本下限）、跨平台必須一致的行為（切行、JSON 判讀、檔案錯誤訊息、可刪檢查、plugin hook）、macOS 專屬能力在 Linux 的具名錯誤、測試略過的稽核，以及 Linux CI。
- `source-storage-gates`: `sources/` 存檔的放置與排除兩道閘在每個支援平台上的契約：放置永不覆寫既有位址、不支援時的退路與具名拒絕、放上位址之前先同步、`.gitignore` 判讀不比 git 寬。

### Modified Capabilities

(none)

## Impact

- Affected specs: linux-platform-support（新）、source-storage-gates（新）
- Affected code:
  - New:
    - .github/workflows/linux.yml
    - Sources/AkashicCore/LineSplitting.swift
    - Sources/AkashicCore/JSONScalar.swift
    - Sources/AkashicCore/PlatformCapability.swift
    - Sources/akashic-guards/PortableSHA256.swift
    - Sources/akashic-guards/GuardLineSplitting.swift
    - Sources/akashic-guards/LinuxSkipAudit.swift
    - Sources/akashic-guards/LinuxSkipAuditMutations.swift
    - Tests/linux-skipped-tests.txt
    - Sources/AkashicTestGuard/TestProducts.swift
    - Sources/AkashicTestGuard/LoopbackHTTPServer.swift
  - Modified:
    - Package.swift
    - Package.resolved
    - Sources/AkashicSQLite/SQLiteDB.swift
    - Sources/AkashicStoreIO/SourcePlacement.swift
    - Sources/AkashicStoreIO/SourceOccupant.swift
    - Sources/AkashicStoreIO/SourcesIgnoreBlock.swift
    - Sources/AkashicStoreIO/LibraryStore.swift
    - Sources/AkashicStoreIO/DivergenceResolve.swift
    - Sources/AkashicStoreIO/SourceChunks.swift
    - Sources/AkashicZoteroImport/ZoteroStorageFile.swift
    - Sources/AkashicS2/S2KeyProvider.swift
    - Sources/AkashicS2/S2Client.swift
    - Sources/AkashicS2/S2Tool.swift
    - Sources/akashic/FulltextCommands.swift
    - Sources/AkashicSkillTools/FulltextFetch.swift
    - Sources/AkashicSkillTools/AbstractProposals.swift
    - Sources/AkashicCore/JSONInteger.swift
    - Sources/akashic-guards/PluginShellVersion.swift
    - Sources/akashic-guards/main.swift
    - plugin/hooks/check-cli.sh
    - .github/workflows/ci.yml
    - .githooks/run-guards.sh
    - .githooks/protected-ratchet.txt
    - README.md
    - docs/rulings/zero-instance-guards.md
    - docs/zero-instance-measurements.md
    - docs/rulings/mcp-cli-parity.md
    - 其餘 import CryptoKit、會切行、或判讀 JSON 型別的原始檔與測試檔（清單在 design 的 Implementation Contract）
  - 另一個 repo：repos/biblatex-apa-swift（submodule）的 manifest 與 ZoteroDiff 的 SQLite import，先在那個 repo 合併並 tag，這邊才更新 submodule
