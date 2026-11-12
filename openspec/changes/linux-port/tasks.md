各組共用的驗收指令（以下寫成「noble 驗收」「jammy 驗收」「macOS 驗收」）：

- noble／jammy 驗收：在 `swift:6.4.2-noble`／`swift:6.4.2-jammy`（digest 見 design）裡，以同一個非 root 使用者執行 `swift build --build-tests --force-resolved-versions -Xswiftc -warnings-as-errors`，再以 `swift test --force-resolved-versions --filter <該組的測試>` 跑該組列的測試。
- macOS 驗收：`swift build -Xswiftc -warnings-as-errors`，再以 `swift test --filter <該組的測試>` 跑該組列的測試。
- 第 0 組完成之前，第 1 到 11 組在本機驗證時把 submodule 切到 biblatex-apa-swift 未合併的分支，指標不 commit（design〈Migration Plan〉）。

跨組會碰同一個檔的地方（不要平行做，後做的那組先 rebase）：`Sources/AkashicSkillTools/AbstractProposals.swift`（2.1、4.8、6.2）、`Sources/AkashicStoreIO/SourceStore.swift`（2.1、6.2）、`Sources/akashic-guards/PluginShellVersion.swift`（5.3、10.1）、`Sources/AkashicStoreIO/SourcesIgnoreBlock.swift`（4.8、10.2）、`docs/rulings/zero-instance-guards.md` 與 `docs/zero-instance-measurements.md`（只在 10.5 改）、`.github/workflows/linux.yml`（只在第 12 組改）。

## 0. 前置（等使用者）

動到的檔：biblatex-apa-swift 那個 repo；本 repo 只有 submodule 指標。依賴：無。

- [ ] 0.1 biblatex-apa-swift 能在 Linux 建置：在那個 repo 開 issue 並實作——manifest 無條件宣告 swift-toolchain-sqlite、`SwiftToolchainCSQLite` product 以 `.when(platforms: [.linux])` 掛上、`ZoteroDiff.swift` 以 `#if os(Linux)` 改 import（design「biblatex-apa-swift 用同一個 SQLite 套件，先在那個 repo 合併」）。**那個 repo 的合併與 tag 要等使用者**，本 repo 的 submodule 只指向已合併的 commit。驗證：該 repo 在兩個映像以 `--force-resolved-versions` 建置並跑它自己的測試通過；macOS 照舊通過；本 repo 的 submodule 指標等於那個 repo 預設分支上已 tag 的 commit。

## 1. Manifest、相依套件與工具鏈下限

動到的檔：`Package.swift`、`Package.resolved`、`Tests/AkashicKitTests/PackageManifestTests.swift`、`Sources/AkashicStoreIO/LibraryStore.swift`、一個新的測試檔。依賴：無（Linux 驗收依第 0 組或本機的 submodule 分支）。

- [x] 1.1 Manifest 依 design「相依套件對每個平台宣告、product 只在 Linux 掛上，兩個平台共用一份鎖定檔」改寫：無條件宣告 swift-crypto（`from: "4.5.0"`）與 swift-toolchain-sqlite（`.upToNextMinor(from: "1.0.9")`），`Crypto` 掛到 import CryptoKit 的 target、`SwiftToolchainCSQLite` 掛到 `AkashicSQLite`，條件都是 `.when(platforms: [.linux])`；尾端 `#if os(Linux)` 移除 `AkashicAppKit`、`AkashicAppKitTests`、`UnicodeNormalizationGenerator` 與 `AkashicAppKit` product（design「Unicode 表產生器在 Linux 不宣告，信任鏈測試拆成兩支」）。在 macOS resolve 後 commit 新的 `Package.resolved`。驗證：macOS 驗收（`PackageManifestTests`）；在 macOS 單跑 `ExpressionConstructionTests/testUnicodeV1TrustChainAndOfficialConformanceArePinned` 通過（離線重建從全域快取取得新套件）。
  - ASSUMPTION: swift-toolchain-sqlite 在 `.upToNextMinor(from: "1.0.9")` 下 resolve 到 1.0.13（SQLite 3.53.4），不是 design 量測用的 1.0.9（3.53.0）。兩版的 `Package.swift` 逐位元組相同（`git diff 1.0.9 1.0.13 -- Package.swift` 空），差別只在 SQLite 的修正版與 shell；鎖定檔照 resolve 結果收 1.0.13。swift-crypto 4.5.2、swift-asn1 1.7.4。
  - ASSUMPTION: `Crypto` 也掛到 import CryptoKit 的五個 test target（`AkashicKitTests`、`AkashicCLITests`、`AkashicMCPTests`、`AkashicPropositionTests`、`TractatusDocsTests`），不靠傳遞依賴。`akashic-guards` 與產生器不掛（10.1 與「產生器在 Linux 不宣告」）。
  - 完成註記（2026-11-12）：`Package.resolved` 只多三個 pin，其餘逐位元組不變；submodule 在 v1.0.0 與 Linux 分支兩種狀態下 macOS resolve 出同一份（sha256 `9a12f664…`）。noble 與 jammy 以非 root 使用者 `swift package resolve --force-resolved-versions` 前後 sha256 相同；`dump-package` 在 Linux 列 27 個 target、macOS 列 30 個，差集恰是三個排除的 target，Linux 也沒有 `AkashicAppKit` product。macOS：`PackageManifestTests` 綠、`ExpressionConstructionTests/testUnicodeV1TrustChainAndOfficialConformanceArePinned` 綠（31 秒）、`bash .githooks/run-guards.sh` exit 0。
- [x] 1.2 寫測試：spec-example: linux-platform-support / macOS build contains no Linux-only product。測試在 macOS 讀 `swift build --show-bin-path` 所在的建置目錄，斷言沒有名字含 `CCryptoBoringSSL` 或 `SwiftToolchainCSQLite` 的物件檔（One lockfile serves both platforms）。驗證：macOS 驗收綠；把 `Crypto` 的條件拿掉後重建，測試紅（負對照，做完還原）。
  - ASSUMPTION: needle 除了 spec 列的兩個，另加 swift-crypto 自己的模組（`Crypto`、`_CryptoExtras`、`CryptoBoringWrapper`）。swift-crypto 的 manifest 只在 linux／android／windows／wasi／openbsd 掛 BoringSSL，Apple 平台本來就不編 `CCryptoBoringSSL`；只找 spec 的兩個字串時，下面的負對照不會紅。另有正對照：同一次掃描找不到 `AkashicSQLite` 的產物就紅（空掃描不算通過）。
  - 完成註記：負對照在另一個 `--scratch-path` 拿掉 `Crypto` 的條件後重建，測試紅並列出 `Crypto.o`、`Crypto.swiftmodule`、`swift-crypto.build/Debug/Crypto-t.build` 等，沒有 `CCryptoBoringSSL`；做完還原、刪掉那個 scratch。Linux 上這支目前以 `#if os(Linux)` 擲 `XCTSkip`，9.8 換成 `MacOSOnly.require`、9.9 要列進略過清單。
- [x] 1.3 [P] `PackageManifestTests` 新增一支：manifest 的字面宣告仍含 `AkashicAppKit`、`AkashicAppKitTests`、`UnicodeNormalizationGenerator`（spec-example: linux-platform-support / Targets declared on Linux and macOS 的 macOS 那一半；The package builds on the supported Linux platforms）。驗證：macOS 驗收綠；Linux 那一半在 12.2。
  - 完成註記：同一支另驗 manifest 尾端唯一的 `#if os(Linux)` 區塊移除的集合恰是那三個。負對照：把產生器從集合拿掉，測試紅；已還原。
- [x] 1.4 Linux builds refuse a Swift compiler older than 6.4：在 `AkashicStoreIO` 加 `#if os(Linux) && !compiler(>=6.4)` 的 `#error`，訊息含 `Swift 6.4` 與 `#794`（design「Linux 工具鏈釘 Swift 6.4.2 官方映像，最低版本在編譯期擋」、「不為 Swift 6.0.x 的 corelibs 錯誤寫分支」）。spec-example: linux-platform-support / Older Linux toolchains are refused——No executable check，手動驗兩列：`swift:6.0.3-noble` 在 resolve 就停、輸出含 `6.1`；一個官方 6.1、6.2 或 6.3 映像停在編譯 `AkashicStoreIO`、輸出含 `Swift 6.4` 與 `#794`。兩次的結束碼與錯誤行記進本 task 的完成註記。
  - 完成註記（第一列）：`swift:6.0.3-noble`（Swift 6.0.3）在 clone 的副本上 `swift build`，rc=1，停在 resolve：`error: Dependencies could not be resolved because 'swift-crypto' >= 4.4.0 contains incompatible tools version (6.1.0) and root depends on 'swift-crypto' 4.5.0..<5.0.0.`；副本的 `Package.resolved` 沒有變。
  - 完成註記（第二列，部分）：`swift:6.3-noble`（Swift 6.3.3，`sha256:1ba0416be43dc57ba6ff7d02114356cad1ab17364024b7669385e3fe41a224aa`）的完整建置**還沒跑**：第 6 組（JSON 判讀）之前 `AkashicCore` 在 Linux 編不過，建置會先停在那裡，量不到 `AkashicStoreIO`。改以探針驗 `#error` 本身：`swiftc -typecheck Sources/AkashicStoreIO/LibraryStore.swift` 在 6.3.3 rc=1、第 10 行報 `error: AkashicKit on Linux requires Swift 6.4 or newer (#794): …`；同一個指令在 6.4.2 只報 `no such module 'AkashicCore'`、沒有這一行。完整建置的那一列在第 11 組之後重量。
- [x] 1.5 [P] 寫測試：spec-example: linux-platform-support / Record overwrite on Linux。在 `AkashicKitTests` 建一筆 person 記錄再覆寫，斷言內容是新的、entities 目錄沒有 `.tmp-` 殘留（兩個平台都跑）。驗證：macOS 驗收與 jammy 驗收都綠。
  - 完成註記：macOS 綠；負對照（`atomicWrite` 在 `replaceItemAt` 之後刪掉目的檔，模擬 6.0.3）三個斷言都紅，已還原。**jammy 那一半還沒驗**：Linux 要到第 4 到 11 組做完才建得起來，在那之後補跑。

## 2. CryptoKit 換成條件 import

動到的檔：design〈Implementation Contract〉列的 10 個原始檔（`PluginShellVersion.swift` 除外）與 14 個測試檔。依賴：1.1。

- [x] 2.1 `import CryptoKit` 改成 `#if os(Linux) import Crypto #else import CryptoKit #endif`（design「條件編譯以 os(Linux) 對齊 manifest 的條件」）。API 不變（`SHA256`、`Insecure.SHA1`）。驗證：macOS 全套測試綠；noble 驗收的建置成功；`DeterministicUUID` 與 `LibrarySnapshot` 既有的 digest 測試在兩個平台給同一個值。
  - 完成註記：改的是 24 個檔（10 個原始檔、14 個測試檔），`akashic-guards/PluginShellVersion.swift`（10.1）與 `Tools/UnicodeNormalizationGenerator/main.swift`（digest 釘住）不動；改完產生器的 SHA-256 仍是 `c52fe7f7…`。macOS：`-warnings-as-errors` 建置 0 警告；全套 `swift test` 七個 bundle 5,643 支、0 失敗、1 略過（`MigrateProvenanceCLITests/testWriteFailureIsListedAndExitsNonZero`，chflags 在這個目錄不生效，既有的環境略過）。
  - **noble 驗收的建置還沒成功**：`AkashicCore` 停在 `JSONInteger.swift` 的 CF 呼叫（第 6 組）。以探針確認 `import Crypto` 本身沒有問題：在 clone 的副本把那三個 CF 呼叫暫改成 `objCType`（不 commit），noble 以非 root、`-warnings-as-errors` 建 `AkashicCore` 與 `TractatusDocs` 都成功；`AkashicStoreIO` 停在 `SourceOccupant.swift` 的 `import Darwin`（第 4 組）。`AkashicStoreIO`、`AkashicSkillTools`、`AkashicZoteroImport` 的 `import Crypto` 與 `DeterministicUUID`／`LibrarySnapshot` digest 測試在 Linux 的值，要等第 4、6 組之後驗。

## 3. SQLite

動到的檔：`Sources/AkashicSQLite/SQLiteDB.swift`。依賴：1.1。

- [x] 3.1 `SQLiteDB.swift` 依 design「Linux 上的 SQLite 用 swift-toolchain-sqlite」改成 `#if os(Linux) internal import SwiftToolchainCSQLite #else import SQLite3 #endif`。驗證：jammy 驗收（映像裡沒有 `sqlite3.h`）的建置成功，產出的 `akashic` 以 `ldd` 看不到 libsqlite3；macOS 的 `akashic` 以 `otool -L` 仍連系統的 libsqlite3；`AkashicIndex` 與 `AkashicQuery` 的測試在 macOS 與 jammy 驗收都綠。
  - 完成註記：`AkashicSQLite` 的公開介面不露出 C 型別（`OpaquePointer` 是 private），所以用 `internal import`。noble 與 jammy（兩者都沒有 `/usr/include/sqlite3.h`）以非 root、`--force-resolved-versions -Xswiftc -warnings-as-errors --target AkashicSQLite` 建置成功、0 警告，`Package.resolved` 前後不變。macOS：`otool -L .build/debug/akashic` 連 `/usr/lib/libsqlite3.dylib`；`AkashicIndex` 與 `AkashicQuery` 的測試在 macOS 全套裡綠。
  - **還沒驗**：`ldd akashic` 與 jammy 上 `AkashicIndex`／`AkashicQuery` 的測試——它們依賴 `AkashicStoreIO`（第 4 組）與 `AkashicCore`（第 6 組），Linux 的 `akashic` 要到那之後才建得出來。biblatex-apa-swift 的同一個改動在 submodule 的分支上（第 0 組），Linux 建 `AkashicExport` 時才會用到。

## 4. sources/ 的放置閘與平台 import

動到的檔：`Sources/AkashicStoreIO/SourcePlacement.swift`、`SourceOccupant.swift`、`SourcesIgnoreBlock.swift`、`SourceChunks.swift`、`Sources/AkashicSkillTools/AbstractProposals.swift`、`Sources/AkashicZoteroImport/ZoteroStorageFile.swift`、`Sources/AkashicCore`（`autoreleasepool`）、`Tests/AkashicKitTests/SourcePlacementTests.swift` 與 `SourceStore` 的測試。依賴：1.1。4.1 到 4.6 都動 `SourcePlacement` 與它的測試，依序做。

- [ ] 4.1 先寫測試（RED）：spec-example: source-storage-gates / Linux placement fallback table。以 `BlobPlacement` 的既有接縫注入表中七列的回傳值（含「符號缺席」），斷言結局與寫入的檔（Unsupported placement falls back to a hard link, then to a named refusal）。測試兩個平台都跑，Linux 專屬的兩列（`ENOSYS`、符號缺席）以同一個接縫注入。驗證：實作前紅、實作後在 macOS 與 noble 驗收都綠。
- [ ] 4.2 實作 Linux 的放置呼叫（design「sources/ 放置閘在 Linux 的做法」、「本 repo 不新增任何 C 程式碼」）：`BlobPlacement.system` 在 Linux 以 `dlopen(nil, RTLD_NOW)` 加 `dlsym("renameat2")` 取得函式（`RENAME_NOREPLACE` 是 1、`AT_FDCWD` 是 -100，寫成具名常數並註明出自 Linux uapi），找不到符號回 `ENOSYS`；hard link 用 Glibc 的 `link`；`placementUnsupported` 依平台分兩份封閉清單；`volumeSupportsExclusivePlacement` 在 Linux 回 nil；`Darwin` 的 import 依平台。驗證：4.1 綠；macOS 的 `SourcePlacementTests` 全綠；`git status` 顯示沒有新增 `.c`、`.h`、`module.modulemap`。
- [ ] 4.3 寫測試：spec-example: source-storage-gates / Exclusive rename onto an occupied address。真的呼叫 `BlobPlacement.system`（不經接縫）放到已有 `B` 的位址與空位址，斷言結果與內容（Placement never overwrites an existing address）。驗證：macOS 驗收綠；noble 驗收時把暫存目錄分別設在 `/tmp` 與 `/dev/shm` 各跑一次都綠。
- [ ] 4.4 寫測試：spec-example: source-storage-gates / Rename count on Linux。數改名呼叫：目標是內容位址的恰一次、探測名一次、探測名不殘留（An unknown volume capability is decided by a real placement on every write）。原本的 `testTheAddressOnlyAppearsInOneAtomicStepWithTheCompleteContent` 改成只數目標是內容位址的改名；`testTheVolumeCapabilityProbeReadsTheRealFlags` 標 macOS 專屬（9.8），另寫 Linux 版斷言回 nil。驗證：macOS 與 noble 驗收都綠。
- [ ] 4.5 同步：Linux 的 `syncFile` 用 `fsync(2)`，macOS 逐字不變（Content is synced before it is placed）。先寫測試：spec-example: source-storage-gates / Injected sync failure on Linux，以同步接縫回 `EIO`，斷言位址不存在、暫存檔不殘留、錯誤具名。驗證：macOS 與 jammy 驗收都綠。
- [ ] 4.6 拒絕訊息依平台：Linux 版寫 `renameat2` 與本機檔案系統，不寫 APFS；macOS 版逐字不變。先寫測試：spec-example: source-storage-gates / Linux refusal text。驗證：noble 驗收的測試斷言含 `renameat2`、不含 `APFS`、`sources/` 沒有新檔；macOS 既有的訊息測試不變而綠。
- [ ] 4.7 [P] `ZoteroStorageFile` 的 `kernelPath` 在 Linux 讀 `/proc/self/fd/<fd>`，結尾是 ` (deleted)` 或讀不到時回 nil（design「Linux 上以 /proc/self/fd 取得 descriptor 的真實路徑」）。先寫測試：開一個 storage 內的檔，斷言回傳路徑在 storage 之內；把檔刪掉後斷言 `openVerified` 回 `.unreadable`。驗證：macOS 與 jammy 驗收都綠。
- [ ] 4.8 [P] 其餘平台差異：`SourcesIgnoreBlock` 與 `SourceOccupant` 的 `Darwin` import 依平台；`sigaction` 欄位名依平台（`__sigaction_u`／`__sigaction_handler`）；`SourceChunks` 與 `AbstractProposals` 的 `autoreleasepool` 在 Linux 由 AkashicCore 提供一個直接呼叫閉包的同名函式。驗證：`SourceSignalCleanupCLITests` 兩支在 macOS 與 jammy 驗收都綠。

## 5. 共用切行函式

動到的檔：新檔 `Sources/AkashicCore/LineSplitting.swift`、`Sources/akashic-guards/GuardLineSplitting.swift`、一個新的測試檔，以及 design「共用切行函式，守衛自帶一份」列的 20 個檔。依賴：無。

- [ ] 5.1 先寫測試（RED）：spec-example: linux-platform-support / Line splitting table。`LineSplittingTests` 斷言表中七列（2026-11-12 在 macOS host 以 Foundation 量過這七列）；另在 macOS 以 1,000 組隨機字串（含 `\r`、`\n`、`\r\n`、U+2028、組合字元）把 `LineSplitting.lines(_:)` 與 Foundation 的 `components(separatedBy: "\n")` 逐位元組比對（design「共用切行函式，守衛自帶一份」）。驗證：實作前紅。
- [ ] 5.2 實作 `LineSplitting.lines(_:)`（以 UTF-8 的 0x0A 切、保留 0x0D、保留空欄位），把函式庫與 CLI 的 8 處換成它（Line splitting is identical on both platforms）。驗證：5.1 在 macOS 與 noble 驗收都綠；`PersonIdentityMigrationTests/testNonCanonicalKeyInUnparsableFileTriggersGlobalSuppression` 在 noble 驗收綠。
- [ ] 5.3 `GuardLineSplitting`（與 AkashicCore 那份同一個行為，不 import 任何 target），把守衛的 31 處換成它；`LineSplittingTests` 以同一張表與同一組隨機字串比對兩份。驗證：對帳測試綠；`bash .githooks/run-guards.sh` 在 macOS 全綠，輸出與換之前逐字相同（換之前先存一份輸出比對）。
- [ ] 5.4 寫測試：spec-example: linux-platform-support / No direct newline split remains。原始碼掃描測試數 `Sources/` 底下 `components(separatedBy: "\n")` 的出現次數，期望 0；把掃描根目錄改成空目錄時測試要紅（空掃描不算通過）。裁決表那一列在 10.5 寫。驗證：macOS 驗收綠；把一處呼叫改回原寫法時測試紅（負對照，做完還原）。

## 6. JSON 純量判讀

動到的檔：新檔 `Sources/AkashicCore/JSONScalar.swift`、`Sources/AkashicCore/JSONInteger.swift`、design〈Implementation Contract〉列的 CF 判讀 10 個檔、一個新的測試檔。依賴：無。

- [ ] 6.1 先寫測試（RED）：spec-example: linux-platform-support / JSON scalar table。對每一列以 `JSONSerialization` 解出值再分類（design「JSON 純量判讀集中到一個函式」）。驗證：實作前紅。
- [ ] 6.2 實作 `JSONScalar.classify(_:)`（macOS 分支逐字沿用 CF 呼叫，Linux 分支以 `objCType` 判並註明只對 `JSONSerialization` 的輸出成立），`JSONInteger.classify` 改建在它上面，10 個檔的 CF 呼叫改呼叫它（JSON scalar types are classified identically on both platforms）。`WebRead` 的 `is Bool` 不動。驗證：6.1 在 macOS 與 noble 驗收都綠；既有 `JSONInteger` 的測試不變而綠；`Sources/` 裡 `CFGetTypeID` 只出現在 `JSONScalar.swift`。

## 7. macOS 專屬能力的具名錯誤

動到的檔：新檔 `Sources/AkashicCore/PlatformCapability.swift`、`Sources/AkashicS2/S2KeyProvider.swift`、`S2Client.swift`、`S2Tool.swift`、`Sources/akashic/FulltextCommands.swift`、`docs/rulings/mcp-cli-parity.md`、S2 與 fulltext 的測試檔。依賴：無。

- [ ] 7.1 新增 `PlatformCapabilityError.macOSOnly(capability:)`，`capability` 封閉兩值 `keychain`、`safari`，訊息說明只在 macOS 有（design「macOS 專屬能力在 Linux 回具名錯誤」）。驗證：單元測試斷言兩個值的訊息含 `macOS`，且不含 `security add-generic-password`；macOS 驗收綠。
- [ ] 7.2 `S2KeyProvider`：`Security`、`LocalAuthentication` 只在 macOS import；Linux 的 `key()` 擲平台錯誤、`probe()` 回「此平台沒有 keychain」的新狀態；`s2 status` 印出那個狀態（macOS-only capabilities fail with a named platform error on Linux）。先寫測試：spec-example: linux-platform-support / S2 key read on Linux（CLI 不設 `AKASHIC_S2_BASE_URL`，斷言結束碼 3 與訊息；in-process 的 `S2Client` 以記錄請求的 session 斷言 0 個請求）與 spec-example: linux-platform-support / S2 status on Linux；`akashic_s2` 的 MCP 錯誤文字與 CLI 相同。斷言 macOS 措辭的 `S2KeyProviderTests/testMissingItemIsReportedAsMissing` 與 `S2ToolTests/testMissingKeyIsAnErrorWithTheSetupGuidanceAndNoRequest` 標 macOS 專屬（9.8）。驗證：Linux 測試在 jammy 與 noble 驗收都綠；macOS 的 S2 測試全綠。
- [ ] 7.3 [P] `akashic fulltext fetch` 在 Linux 於 `run()` 的第一步、解析帳本路徑與啟動任何行程之前擲平台錯誤，結束碼 1。先寫測試：spec-example: linux-platform-support / Fetch writes nothing on Linux。驗證：noble 驗收的測試斷言帳本路徑仍不存在；macOS 上同一組參數照舊走到既有的行為（既有測試不變而綠）。
- [ ] 7.4 [P] 兩面契約的紀錄：`docs/rulings/mcp-cli-parity.md` 的 `akashic_s2` 列與 `fulltext` 列各補一句「#794 重新確認，裁決不變、契約有改」，寫明 Linux 上的具名錯誤與結束碼。驗證：`akashic-guards parity-table-drift` 綠。

## 8. 可刪檢查與 plugin hook

動到的檔：`Sources/AkashicStoreIO/DivergenceResolve.swift`、`plugin/hooks/check-cli.sh`、plugin 殼版號所在的檔、`DivergenceResolveTests`、`DivergenceHardeningTests`、`VerdictHolderGridTests`、`EnrichServiceTests`、`ToolPayloadScenarios`。依賴：無。

- [ ] 8.1 先寫測試（RED）：spec-example: linux-platform-support / Linux flag table。旗標解碼寫成純函式，表中五列在兩個平台都跑（design「可刪檢查在 Linux 讀 FS_IOC_GETFLAGS」）。驗證：實作前紅。
- [ ] 8.2 實作 The deletability check reads the immutable and append-only flags on Linux：Linux 以 Glibc 的 `ioctl(fd, FS_IOC_GETFLAGS)` 讀旗標並交給 8.1 的函式；macOS 讀 `.immutable` 屬性逐字不變。驗證：8.1 在 macOS 與 noble 驗收都綠；noble 上一個普通檔判為可刪。
- [ ] 8.3 寫測試：spec-example: linux-platform-support / Read-only parent directory。以 0555 父目錄注入不可刪，斷言合併零刪除、錯誤具名。上列五個測試檔裡以 `.immutable` 注入刪除或寫入失敗的測試改用同一個做法；只驗 macOS `.immutable` 屬性本身的保留並標 macOS 專屬（9.8）。驗證：這五個檔的測試在 macOS 與 noble 驗收都綠。
- [ ] 8.4 [P] The plugin's CLI check hook works with GNU and BSD userlands：`check-cli.sh` 的兩處 `stat` 改成依 `stat --version` 選 GNU 或 BSD 寫法的函式（design「plugin hook 改成 GNU 與 BSD 都能用」）；plugin 殼版號照 `plugin-shell-version` 守衛升一號。寫測試：spec-example: linux-platform-support / Hook tests on both userlands，即既有的 `CheckCLIHookTests` 在三個環境跑。驗證：`CheckCLIHookTests` 在 macOS、jammy、noble 驗收全綠；`akashic-guards plugin-shell-version` 綠；合併前後各查一次 main 的殼版號沒有被別的 PR 用掉。

## 9. 測試的可攜性

動到的檔：新檔 `Sources/AkashicTestGuard/TestProducts.swift`、`Sources/AkashicTestGuard/LoopbackHTTPServer.swift`、`Tests/linux-skipped-tests.txt`，以及 design「測試改成可攜的做法」表中列的測試檔。依賴：1.1；9.8、9.9 依賴第 4、7、8 組標的 macOS 專屬測試。

- [ ] 9.1 量 corelibs `URLSession` 對真實 3xx 的行為（design「測試改成可攜的做法」最後一段的 ASSUMPTION）：在 noble 以 loopback server 回 302，task delegate 拒絕跟隨，記下結果。若 corelibs 不尊重拒絕，停下回報使用者，9.4 不得以略過收場。驗證：結果寫進本 task 的完成註記與 design 該段。
- [ ] 9.2 `TestProducts.directory` 在 macOS 照舊由 bundle 定位、在 Linux 由 `Bundle.main.executableURL` 定位；19 個測試檔的各自定位與 `CLIFixture.binary` 改用它。驗證：`ExportBoundaryTests` 的三支 CLI stdout 測試在 noble 驗收執行並綠（不再以「找不到 akashic binary」略過）；macOS 全套綠。
- [ ] 9.3 `testCanonicalBytesReplayInFreshSubprocesses` 的子行程在 Linux 以測試執行檔加測試名稱重跑，不經 `xcrun xctest`。驗證：這支在 macOS 與 noble 驗收都綠。
- [ ] 9.4 `LoopbackHTTPServer`（POSIX socket，只綁 127.0.0.1，檔頭寫明它是測試伺服器、不是 HTTP client）；`S2SessionHardeningTests` 的三支轉址測試與 `S2CommandTests` 的 `NWListener` 改用它。驗證：`S2CommandTests` 16 支與三支轉址測試在 noble 驗收執行並綠（不是略過）；macOS 綠；`akashic-guards network-confinement` 綠。
- [ ] 9.5 [P] 測試用的 BSD 工具：`SourceIntakeMemoryCLITests` 的峰值記憶體改以 `getrusage(RUSAGE_CHILDREN)` 讀（helper 處理 Linux KB 與 macOS bytes 的換算）；`MigrateProvenanceCLITests` 與 `ProvenanceMigrationTests` 以 BSD 檔案旗標注入的失敗改用目錄權限。驗證：這三個檔的測試在 macOS 與 noble 驗收都綠，`ProvenanceMigrationTests` 在 Linux 不再略過。
- [ ] 9.6 [P] 其餘測試寫法：`FoundationNetworking`、`FoundationXML` 的條件 import；`URLCache(directory:)` 改 `diskPath:` 的 helper；`RLIMIT_FSIZE` 在 glibc 的 enum；帶 `Darwin.` 前綴的 `write`／`link`／`rename` 改成不帶模組名；`SanitizationBoundaryTests` 的真實 Foundation 錯誤改成「兩個平台都不漏出暫存檔名、遮罩註記只在文字含檔名時出現」。驗證：jammy 驗收的建置成功；`SanitizationBoundaryTests` 在 macOS 與 noble 驗收都綠。
- [ ] 9.7 The exclusion judgement is never wider than git：`GitignorePreservationCLITests/testThePresentJudgementAgreesWithGitCheckIgnore` 改成兩條斷言（design「.gitignore 判讀維持不分大小寫」）。寫測試：spec-example: source-storage-gates / Judgement against git on Linux，三列以 `git -c core.ignorecase=…` 跑。驗證：macOS、jammy、noble 驗收都綠；`SourcesIgnoreBlock` 的判讀沒有改（這個 task 的 diff 只在測試檔）。
- [ ] 9.8 `MacOSOnly.require(_:)`（AkashicTestGuard，它已 import XCTest）與 macOS 專屬的測試逐支呼叫它：`FulltextHumanLikeTests` 用 `JavaScriptCore` 的三支（框架程式碼放進 `#if canImport(JavaScriptCore)`）、`IndexIdentityTests/testIsCurrentAcceptsOwnIndexIncludingPathAliases`、4.4、7.2、8.3 標的那幾支、Unicode 信任鏈測試拆出的離線重建那一支（design「macOS 專屬測試逐支略過，Linux 的略過集合等於審過的清單」、「Unicode 表產生器在 Linux 不宣告，信任鏈測試拆成兩支」）。驗證：noble 驗收的輸出逐支列出略過與理由；macOS 上這些測試照常執行。
- [ ] 9.9 寫 `Tests/linux-skipped-tests.txt`，列 9.8 的每一支（`macos-only`）與環境缺件（`AliasEventBudgetTests/testRealCorpusPasses`、`OrganizationParentLevelsTests` 兩支，`environment`），每行帶理由（Tests skipped on Linux equal an audited list）。驗證：noble 驗收跑全套，略過數等於清單行數；`akashic-guards linux-skip-audit` 對那份輸出 exit 0（依賴 10.4）。

- [ ] 9.10 The bot-signal word class agrees with Python 3.13 on both platforms：`BotSignalsPythonBoundaryTests/testTheWordClassAgreesWithPythonsWordOnEveryScalar` 只比對 age 不超過 15.1 的碼位，並斷言比對數過一個下限（design「BotSignals 字詞類別的測試只比對 Python 3.13 認得的碼位」）。產品的 `BotSignals.wordClass` 不改。spec-example: linux-platform-support / Word class against Python's \w。驗證：macOS、noble、jammy 驗收都綠；把篩選上限改成 17.0 時 noble 紅（負對照，做完還原）。

## 10. 守衛

動到的檔：新檔 `Sources/akashic-guards/PortableSHA256.swift`、`LinuxSkipAudit.swift`、`LinuxSkipAuditMutations.swift`，`Sources/akashic-guards/PluginShellVersion.swift`、`main.swift`、`ZeroInstanceRowsAudit.swift`、`Sources/AkashicStoreIO/SourcesIgnoreBlock.swift`、`.githooks/run-guards.sh`、`.githooks/protected-ratchet.txt`、`docs/rulings/zero-instance-guards.md`、`docs/zero-instance-measurements.md`，測試檔。依賴：5.3 之後做 10.1（同檔）；10.5 依賴 5.4、10.4、12.1。

- [ ] 10.1 akashic-guards stays dependency-free and platform-independent：`PortableSHA256` 取代 `PluginShellVersion.swift` 的 `CryptoKit`。先寫測試：spec-example: linux-platform-support / SHA-256 test vectors，加上 macOS 上 1,000 組隨機輸入與 CryptoKit 差分比對。先試 `AkashicKitTests` 以 `@testable import akashic_guards` 呼叫；任一平台 import 不起來就改加一個只供測試的隱藏子命令，結果記進 design「akashic-guards 維持零相依」。驗證：測試在 macOS 與 noble 驗收都綠；`Package.swift` 裡 `akashic-guards` 仍沒有任何依賴；`akashic-guards plugin-shell-version` 在 macOS 的輸出與換之前逐字相同。
- [ ] 10.2 [P] `memmem` 換成標準庫的 `firstRange(of:)`（`SourcesIgnoreBlock` 與 `ZeroInstanceRowsAudit` 兩處）。先在 macOS 寫差分測試（隨機 haystack 與 needle，比對 libc `memmem` 與新寫法的位置）。驗證：差分測試在 macOS 綠；jammy 驗收的建置成功。
- [ ] 10.3 先寫負對照（RED）：spec-example: linux-platform-support / Mutation control for the skip audit。`akashic-guards linux-skip-audit-mutations` 在暫存副本上注入四種變動（未列的略過、列了卻執行、缺分類、缺理由），每一種都要讓稽核紅，原樣副本要綠。驗證：實作稽核前它報失敗。
- [ ] 10.4 實作 `akashic-guards linux-skip-audit --log <path> --list <path>`（design「macOS 專屬測試逐支略過，Linux 的略過集合等於審過的清單」）。輸出格式先在 noble 量一次 `swift test` 對略過的實際印法再寫解析。寫測試：spec-example: linux-platform-support / A new unlisted skip fails the audit 與 spec-example: linux-platform-support / A listed test that ran fails the audit，以固定的輸出 fixture 跑。驗證：兩支測試與 10.3 的負對照綠；`.githooks/run-guards.sh` 跑負對照並綠。
- [ ] 10.5 守衛的登記（design「本 change 新增的零實例防線逐一裁決」）：五道防線各在 `docs/rulings/zero-instance-guards.md` 加一列與共通段的 bullet、`docs/zero-instance-measurements.md` 加量測並調棘輪下限、`.githooks/protected-ratchet.txt` 補新守衛的檔。驗證：`akashic-guards zero-instance-rows-audit`、`protected-ratchet`、`trigger-coverage`、`workflow-run-scripts` 全綠。

## 11. 警告

動到的檔：試作量到的 18 個警告位置所在的檔（`Sources/akashic-guards` 兩個檔、6 個測試檔、`CLIFixture.swift`、`FulltextFetchHardeningTests.swift`）。依賴：第 2 到 10 組（它們可能新增或移走警告）。

- [ ] 11.1 6.4.2 在 Linux 的警告全部修掉：`createFile` 的未用回傳值改成 `_ =`，並行閉包裡改寫捕捉的變數改成在閉包外收集結果。驗證：jammy 與 noble 從空的建置目錄建置（含測試、`-warnings-as-errors`）成功，`warning:` 行數為 0；macOS 的 `-warnings-as-errors` 建置照舊成功。

## 12. Linux CI

動到的檔：新檔 `.github/workflows/linux.yml`、一個新的測試檔。依賴：0.1、第 1 到 11 組。

- [ ] 12.1 新增 `linux.yml`（design「Linux CI 新增一個 workflow」）：矩陣兩個映像以 index digest 指定；容器內以 root 只做套件安裝、建立使用者、把工作目錄的擁有者改成他並加進他的 git `safe.directory`；建置、測試、守衛以那個使用者執行；建置與測試都帶 `--force-resolved-versions`，測試之後檢查 `Package.resolved` 沒有變動（步驟註解帶 spec-example: linux-platform-support / Lockfile unchanged after Linux resolve）；actions 釘 SHA、`persist-credentials: false`、`fetch-depth: 0`、取 submodule；觸發條件與 `ci.yml` 相同（ASSUMPTION，見 design Open Questions）。Linux CI builds and tests both Ubuntu versions as a non-root user。寫測試：spec-example: linux-platform-support / Static check of the Linux workflow，以原始碼掃描讀這個 workflow 斷言 spec 列的各項。驗證：靜態測試在 macOS 綠；`akashic-guards workflow-run-scripts` 與 `trigger-coverage` 綠；在本機 noble 照 workflow 的指令跑一次，改一個 pin 後鎖定檔那一步非零結束。
- [ ] 12.2 `linux.yml` 加一步 `swift package dump-package`，以 `jq` 斷言三個排除的 target 不在（spec-example: linux-platform-support / Targets declared on Linux and macOS 的 Linux 那一半，步驟註解帶這個標記）。驗證：在本機 noble 照指令跑，輸出符合 spec。
- [ ] 12.3 第一次 CI 執行（x86_64 的第一次量測）：spec-example: linux-platform-support / Clean build on both Ubuntu images 由 `linux.yml` 的建置步驟承擔，步驟註解帶這個標記。驗證：兩個 job 都綠；`warning:` 行數 0；略過稽核 exit 0。紅了照實回報，不放寬步驟。

## 13. 文件與紀錄

動到的檔：`README.md`、`.github/workflows/ci.yml`（只改註解）。依賴：第 12 組。

- [ ] 13.1 [P] `README.md` 加 Linux 一節：支援的 Ubuntu 與 Swift 版本、需要的套件（`git`、`poppler-utils`）、不需要 root 與 `sqlite3.h`、Linux 上回具名錯誤的兩個能力、`fsync` 與 macOS `F_FULLFSYNC` 的差別。驗證：rule-coverage 守衛綠；文件裡的命令在 noble 照抄能跑。
- [ ] 13.2 [P] `ci.yml` 檔頭「沒有 Linux 選項」那句改成指向 `linux.yml`。驗證：`workflow-run-scripts` 綠；diff 只在註解。

## 14. 整體驗收

依賴：全部。

- [ ] 14.1 macOS behaviour is unchanged：同一個 commit 在 macOS 跑 `-warnings-as-errors` 建置、全套 `swift test`、`bash .githooks/run-guards.sh`、`.githooks/pre-push`。寫測試：spec-example: linux-platform-support / Generator digest pin stays valid，即拆分後的信任鏈測試在 macOS 綠，且 `Tools/UnicodeNormalizationGenerator/main.swift` 的 SHA-256 仍是 `c52fe7f7f1c209d14973ab1461df4cb8195a640dc9a0dd4ae7be6baf60cd5c6f`。驗證：全部 exit 0；`DisplaySinkCoverageTests` 綠。
- [ ] 14.2 Linux 全套：jammy 與 noble 驗收跑全套（不帶 `--filter`）與略過稽核。驗證：失敗 0、崩潰 0、略過集合等於清單；`spectra validate linux-port` 通過。
- [ ] 14.3 Linux 的 `akashic` 不連系統 SQLite：jammy 與 noble 驗收建出的 `akashic` 以 `ldd` 看不到 `libsqlite3`（design「Linux 上的 SQLite 用 swift-toolchain-sqlite」，3.1 延後的那一半）。驗證：兩個映像的 `ldd` 輸出記進本 task 的完成註記。
- [ ] 14.4 spec-example: linux-platform-support / Older Linux toolchains are refused 的第二列以完整建置重量：在一個官方 6.1、6.2 或 6.3 映像（1.4 用的是 `swift:6.3-noble`）以非 root 使用者 `swift build`，建置停在編譯 `AkashicStoreIO`、輸出含 `Swift 6.4` 與 `#794`（1.4 延後的那一半；1.4 當時 `AkashicCore` 在 Linux 還編不過，只能以 `swiftc -typecheck` 驗 `#error` 本身）。驗證：結束碼與錯誤行記進本 task 的完成註記。
