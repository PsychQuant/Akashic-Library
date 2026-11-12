## Context

AkashicKit 只宣告 macOS（`platforms: [.macOS(.v14)]`），`Sources/` 沒有任何條件編譯。#794 要讓 `AkashicAppKit` 以外的 target 在 Linux 建置、測試在 Linux 通過，並進 CI。使用者 2026-11-11 的四件裁決（comment 6791275464）是本 design 的前提，不在這裡重新討論：

1. Ubuntu 22.04 與 24.04 都要。
2. 只能在 macOS 跑的測試標明略過，其餘在 Linux 全部通過。
3. macOS 專屬的能力（keychain、經 Safari 取全文）留著，在 Linux 執行時報錯。
4. Linux 的建置與測試進 CI。

2026-11-12 的拋棄式試作（以 `8fc7fc0b` 為基底，issue comment 6816525675、6817374709）在 `swift:6.0.3` 與 `swift:6.4.2` 的 noble、jammy 映像量過全套測試：6.4.2 兩個映像逐支結果相同，5,449 支裡 5,405 通過、29 失敗、4 崩潰、11 略過。本 design 依那份量測寫成，試作沒回答的幾件事在 2026-11-12 另以 6.4.2 映像與 macOS host 補量（見各 Decision 的「量測」）。

本 change 沒有另跑 discuss；討論的結論直接寫在 Decisions。標 `ASSUMPTION:` 的是使用者沒有裁決、由我取最保守做法的地方。

## Goals / Non-Goals

**Goals:**

- `AkashicAppKit`、`AkashicAppKitTests`、`UnicodeNormalizationGenerator` 以外的 target 在 `swift:6.4.2-jammy` 與 `swift:6.4.2-noble` 以 `-warnings-as-errors` 建置成功。
- Linux 上被略過的測試全部是 macOS 專屬或環境缺件，逐支具名，集合等於一份審過的清單；其餘全部通過。
- `sources/` 的放置閘與排除閘在 Linux 不比 macOS 寬。
- 店裡資料的讀寫在兩個平台給同一個結果（切行、JSON 型別判讀、記錄覆寫）。
- macOS 的建置、測試、守衛、pre-push 行為不變。
- Linux CI：兩個映像、以 digest 固定、非 root、鎖定檔唯讀。

**Non-Goals:**

- `AkashicAppKit` 與 App 的 XcodeGen 專案移植到 Linux。
- 在 Linux 提供金鑰來源（環境變數、檔案、libsecret）：裁決 3 是報錯，這張不新增。
- 把 `~/Library/...` 的預設路徑改成 XDG：只有 macOS 專屬能力用到它們，Linux 上那些能力在用到路徑之前就報錯。
- Windows、musl、Swift 6.4 以前的 Linux toolchain。
- 讓 `sources/` 的放置在兩個平台都 fsync 父目錄（現況兩邊都沒有，#805）。
- 量「送到 Linux 跑是否比較快」（#794 Residue 已寫明由另一張 issue 決定）。

## Decisions

### Linux 工具鏈釘 Swift 6.4.2 官方映像，最低版本在編譯期擋

ASSUMPTION: 依 lead 的設計傾向與試作 §11 的量測，Linux 支援的最低 Swift 是 6.4；CI 釘 `swift:6.4.2-noble`（index digest `sha256:23d9b28ad97fb1cf1999edc3a0cb265ee915ed42299a9344e7173d5a6d2b05f4`）與 `swift:6.4.2-jammy`（`sha256:18a1cdd3e55ee32b0b3e1a15f12a4e1320b67544e542ed96c907629e5e434144`）。

- 這兩個 digest 是多架構的 index（2026-11-12 以 docker buildx imagetools inspect 確認各含 `linux/amd64` 與 `linux/arm64/v8`），所以 GitHub 的 x86_64 runner 拉得到同一份。
- 6.0.3 的 `FileManager.replaceItemAt` 會刪掉目的檔（試作 §3.3），`atomicWrite` 用它覆寫每一筆記錄；6.4.2 已修好（§11.3）。依 `no-compat-fallback`，不為 6.0.x 寫 Linux 專用的 `rename(2)` 分支。
- 只寫成散文的版本下限擋不住有人用舊 toolchain 建置，所以在 `AkashicStoreIO` 放一段 `#if os(Linux) && !compiler(>=6.4)` 的 `#error`，訊息寫明最低版本與 #794。6.0.3 實際上走不到這一行：swift-crypto 4.5.2 宣告 `swift-tools-version:6.1`（2026-11-12 讀它的 manifest），6.0.3 在 resolve 就失敗。`#error` 擋的是 6.1 到 6.3；那三版的 `replaceItemAt` 有沒有修好沒有量，下限定在 6.4 是因為只有 6.4.2 量過是對的。
- 試作的所有量測都在 aarch64（Docker Desktop），CI 是 x86_64。第一次 CI 就是 x86_64 的第一次量測，寫進 Risks。

### 相依套件對每個平台宣告、product 只在 Linux 掛上，兩個平台共用一份鎖定檔

ASSUMPTION: 依 lead 的設計傾向與試作 §11.2。swift-crypto 與 swift-toolchain-sqlite 在 `dependencies` 無條件宣告；`Crypto` 與 `SwiftToolchainCSQLite` 兩個 product 以 `condition: .when(platforms: [.linux])` 掛到用得到的 target。

- 量測：§11.2 量到這種寫法下 macOS 與 6.4.2 Linux 解出的 `Package.resolved` 逐位元組相同；把相依套件本身寫成只在 Linux 宣告時，鎖定檔會隨最後在哪個平台 resolve 而翻轉。
- 量測（2026-11-12，探針套件）：macOS 上條件式的 SQLite product 沒有被編譯，執行檔連的是系統 SQLite 3.54.0。swift-crypto 在 macOS 是否完全不編譯沒有量，列為 task 1.1 的驗收。
- 量測：swift-toolchain-sqlite 的 manifest 在環境變數 `CI` 為 `true` 時會多加一個 dynamic product；以 `CI=true` 建置探針，兩個映像都成功，消費端不受影響。
- CI 以 `--force-resolved-versions` 建置，建置後檢查 `Package.resolved` 沒有變動，漂移就失敗而不是被改寫。
- App 的兩個 target、`AkashicAppKit` product 與 Unicode 產生器，用 manifest 尾端一段 `#if os(Linux)` 從 `package.targets`／`package.products` 移除（試作 stage 3 的形狀）。這三個名字的宣告文字在 macOS 不變，`PackageManifestTests` 讀的字面清單也不變。

### Linux 上的 SQLite 用 swift-toolchain-sqlite

lead 要求在「把 SQLite amalgamation 收成 Linux 專用的 C target」與「依賴 swiftlang/swift-toolchain-sqlite」之間選一個。選後者。

| | amalgamation 收進本 repo | swift-toolchain-sqlite 1.0.13 | 系統 libsqlite3（試作的做法） |
|---|---|---|---|
| 沒有 root、沒有 `sqlite3.h` 的 Linux 機器 | 可 | 可（2026-11-12 量：兩個映像都沒有 `/usr/include/sqlite3.h`，建置成功，`ldd` 看不到 libsqlite3） | 不可 |
| 本 repo 新增的 C 程式碼 | 約 9 MB 的 `sqlite3.c`，要在 `swift-is-the-implementation-language` 的放置表加一列 | 無；它與 Yams 一樣是相依套件 | modulemap 與一個 header |
| 授權 | SQLite 是 public domain | 包裝是 Apache-2.0，套件內的 `Sources/LICENSE.txt` 寫明 SQLite 原始碼已獻給 public domain | 系統套件 |
| 原始碼大小 | 收進 repo | 11 MB，只在 `.build/checkouts`，不進 repo | — |
| 版本怎麼釘 | 手動換檔 | `Package.resolved`（1.0.13 帶 SQLite 3.53.4） | 隨發行版（noble 3.45.1、jammy 3.37.2） |
| 維護者 | 本 repo | swiftlang（SwiftPM 自己在 Linux 用它） | 發行版 |
| macOS | 不受影響 | 不受影響（條件式 product，量過不編譯） | 不受影響 |

- 版本：manifest 寫 `.upToNextMinor(from: "1.0.9")`，2026-11-12 在 macOS resolve 到 1.0.13（SQLite 3.53.4），鎖定檔收的是 1.0.13。表中的量測是對 1.0.9 做的；兩版的 `Package.swift` 逐位元組相同（`git diff 1.0.9 1.0.13 -- Package.swift` 為空），差別只在 SQLite 的修正版（3.53.0 到 3.53.4）與 `sqlite` shell，所以沒有 `sqlite3.h`、不需要 root 這兩列對 1.0.13 一樣成立（第 3 組在兩個映像以 1.0.13 建 `AkashicSQLite` 成功）。
- import 寫法：`#if os(Linux)` 時 `internal import SwiftToolchainCSQLite`，否則照舊 `import SQLite3`。
- 量測（2026-11-12）：`internal import` 建置時沒有警告，但以 `swiftc` 單獨對該模組的 `.swiftmodule` 編譯 client 時，兩個映像都報 `missing required module 'SwiftToolchainCSQLite'`——`internal import` 不讓 client 免載入 C 模組。本 repo 以 `swiftc` 直接編譯 client 的測試只 import `AkashicProposition`，它的依賴閉包（AkashicCore、AkashicStoreIO、Yams）不經過 `AkashicSQLite`，所以不受影響；這也是下一個 Decision 不在 `AkashicStoreIO` 放任何 C 模組的理由之一。
- SQL 特性：試作 §3.2 掃過用 SQLite 的 target，jammy 3.37.2 以後才有的特性 0 處；3.53.4 比它新，沒有相容問題。

### 本 repo 不新增任何 C 程式碼

試作新增了兩個 C target（`CSQLite`、`CAkashicLinuxFS`），它們讓 macOS 的 `DisplaySinkCoverageTests` 變紅（掃 `Sources/*` 時遇到沒有 Swift 檔的目錄）。2026-11-12 的量測顯示兩者都可以不要：

- SQLite 由相依套件提供（上一個 Decision）。
- `renameat2`：Swift 的 Glibc 模組在 6.4.2 仍然不露出它（量：`cannot find 'renameat2' in scope`），但以 `dlopen(nil, RTLD_NOW)` 加 `dlsym("renameat2")` 取得、轉成 `@convention(c)` 函式型別後，非 root 使用者在 overlayfs 與 tmpfs 上覆寫既有檔回 `-1`／`EEXIST`、目的檔內容不變，放到新名字回 `0`。`RENAME_NOREPLACE` 是 Linux uapi 的固定值 1、`AT_FDCWD` 是 -100，寫成具名常數並附出處。
- `ioctl(FS_IOC_GETFLAGS)`：從 Swift 的 Glibc overlay 直接呼叫成功（overlayfs 讀到 `0x80000`，tmpfs 讀到 0）。

所以 `swift-is-the-implementation-language` 的放置表不用加列。另記一件不屬本 change 的事：既有的 C target `AkashicTestGuardLoader`（`loader.c`）在那條規則的例外與既有檔清單裡都沒有出現，規則的語言組成數字也沒算它，記在 #806。

### 條件編譯以 os(Linux) 對齊 manifest 的條件

macOS 與 Linux 的分支一律寫成 `#if os(Linux)`，不寫 `canImport`。product 的掛載條件是 `.when(platforms: [.linux])`，原始碼的條件要和它是同一個命題；`canImport(SQLite3)` 在一台另外提供了 `SQLite3` 模組的 Linux 機器上會為真，那時會同時連進系統與套件的 SQLite。例外只有平台框架本身（`JavaScriptCore`、`Network`）的測試，見「macOS 專屬測試逐支略過」。

### sources/ 放置閘在 Linux 的做法

ASSUMPTION: 依 lead 的設計傾向 5。

- 放置：先 `renameat2(RENAME_NOREPLACE)`，回「不支援」才 `link(2)`，兩個都不支援就具名拒絕、什麼都不寫。這是 `BlobPlacement` 既有的兩段結構，Linux 只換掉 `system` 的兩個呼叫。
- 「不支援」的 errno 是逐呼叫、逐平台的封閉列舉。Linux：rename 收 `ENOTSUP`、`EOPNOTSUPP`、`EINVAL`、`ENOSYS`，`dlsym` 找不到符號算 `ENOSYS`（kernel 3.15 以前、glibc 2.28 以前）；link 收 `ENOTSUP`、`EOPNOTSUPP`、`EPERM`。macOS 兩份不變。其餘 errno 不退，直接具名擲出。
- 磁碟區能力：Linux 一律回「判不出來」（`nil`），交給既有的 `assertDirectoryCanPlace` 在分片目錄裡實際放一次。不做檔案系統類型的允許清單：允許清單是另一份要維護、會與實際行為分岔的描述，而實際放一次本來就是 `nil` 時的既有路徑。代價是 Linux 上每次存檔多一次建檔、改名、刪檔。
- 同步：Linux 用 `fsync(2)`。macOS 的 `F_FULLFSYNC` 連裝置的寫入快取一起清，`fsync` 在 macOS 不保證這一點；Linux 的 `fsync` 依 man page 要求把資料送到裝置並清裝置快取，但只有在檔案系統下 barrier／flush 時成立（ext4、xfs 預設會）。這個等價在 VM 裡量不到，寫進 Risks。Linux 沒有「完整同步不支援就退一般同步」那一步，因為只有一個呼叫。
- 拒絕訊息：Linux 版寫 `renameat2`，並說要放在支援 hard link 或 RENAME_NOREPLACE 的本機檔案系統（ext4、xfs 這類），不叫人改用 APFS／HFS+。macOS 版逐字不變。
- 放置之後兩個平台都沒有 fsync 父目錄，新名字在斷電時不保證留下；這是既有缺口，記在 #805，本 change 不改 macOS 的行為。
- 閘不比現在寬的論證：Linux 的三個步驟對應 macOS 的三個步驟，不支援時的結局（具名拒絕、零寫入）相同；Linux 多收的 `ENOSYS` 只會把呼叫導向 `link(2)` 或拒絕，不會導向覆寫。

### Linux 上以 /proc/self/fd 取得 descriptor 的真實路徑

`ZoteroStorageFile` 的 `kernelPath` 在 Linux 讀 `/proc/self/fd/<fd>` 的 symlink；結果以 ` (deleted)` 結尾或讀不到（沒有掛 `/proc`）時回 nil。nil 在既有的呼叫端回 `.unreadable`，所以 `/proc` 不在時是拒絕，不是放行。

### 不為 Swift 6.0.x 的 corelibs 錯誤寫分支

`atomicWrite` 照舊用 `replaceItemAt`。試作在 Linux 加的 `rename(2)` 分支不帶進來：它只為 6.0.3 存在，而 6.0.3 已被編譯期的版本下限排除。Linux 上「覆寫記錄之後記錄還在」由一支測試在兩個映像上釘住（spec 的 Record overwrite on Linux），toolchain 日後若變動，那支測試會紅。

### 共用切行函式，守衛自帶一份

`components(separatedBy: "\n")` 在 Linux 不切 CRLF（6.4.2 仍是，量到 `["a\r\nb\r\n"]`），在 macOS 切在每個 LF、保留 CR。`Sources/` 有 39 處：函式庫與 CLI 8 處（`IdentifierMigration`、`PersonIdentityMigration` 5 處、`TractatusDocs` 的 `Rendering`、`ReferenceListExtractor`），`akashic-guards` 31 處（16 個檔）。

- 新增 AkashicCore 的 `LineSplitting.lines(_:)`：以 UTF-8 的 0x0A 切、保留 0x0D、保留空欄位，結果與 macOS 現在的 `components(separatedBy: "\n")` 逐位元組相同。Swift 的 `split(separator: "\n")` 不能用：`"\r\n"` 在 Swift 是一個 `Character`（量：兩個平台都不切）。
- 先在 macOS 寫差分測試，把 Foundation 的結果與新函式比對（spec 的 Line splitting table 加上隨機輸入），通過之後才換呼叫點。
- `akashic-guards` 依 #433 不得依賴任何 target，所以帶一份自己的 `GuardLineSplitting`。兩份不算 `no-compat-fallback`〈同一件事只能有一份描述〉禁止的第二份：那一節的處置是「改成引用」，而引用在建置圖上做不到（守衛要能在一個建不起來的樹上仍然跑得動）。兩份由同一張表的測試對帳，任一份變了測試就紅。SHA-256 與 `memmem` 的替代同理（見「akashic-guards 維持零相依」）。
- 換完之後加一支原始碼掃描測試：`Sources/` 底下 `components(separatedBy: "\n")` 出現 0 次。它是一個零實例守衛，依 `zero-instance-guards` 在裁決表加一列。

### JSON 純量判讀集中到一個函式

`JSONSerialization` 的 `0`、`1` 在 Linux 也是 `is Bool`（6.0.3 與 6.4.2 量的都是 `true, true, true, true`），macOS 靠 `CFGetTypeID`、`CFBooleanGetTypeID`、`CFNumberIsFloatType` 區分，而 Linux 沒有公開的 CoreFoundation。

- 新增 AkashicCore 的 `JSONScalar.classify(_:)`，回 `boolean`、`integer(Int)`、`integerOutOfRange`、`nonInteger`、`other`。macOS 分支逐字沿用現在的 CF 呼叫；Linux 分支以 `NSNumber.objCType` 判（試作量到 `JSONSerialization` 的 `true`／`false` 是 `c`、整數是 `i`／`q`／`Q`、小數是 `d`、超過 `UInt64` 的是 `NSDecimalNumber`）。這個判讀只對 `JSONSerialization` 的輸出成立，函式文件寫明這個前提。
- `JSONInteger.classify` 改成建在它上面，回傳值不變。
- 10 個檔裡的 CF 呼叫改呼叫它。spec 的表在兩個平台跑同一組斷言；表中每一列的原始值（型別、`objCType`、`is Bool`）2026-11-12 在 macOS host 與 noble 各量過一次。
- `WebRead` 的兩處 `is Bool`（第 397–398 行）不改，也不另開 issue：它們判讀的不是 `JSONSerialization` 的輸出，而是 `PyJSONParser` 的輸出。`PyJSONParser` 回原生的 Swift 值，2026-11-12 在 macOS 與 `swift:6.4.2-noble` 各量一次，`0`、`1`、`1.0`、`-3` 的 `is Bool` 都是 false，只有 `true`／`false` 是 true，兩個平台相同，所以那兩處在兩個平台都正確。`is Bool` 對 `0`、`1`、`1.0` 為 true 只發生在 `JSONSerialization` 產生的 `NSNumber` 上——本節的 `JSONScalar` 處理的正是那一種。

### macOS 專屬能力在 Linux 回具名錯誤

- 新增 AkashicCore 的 `PlatformCapabilityError.macOSOnly(capability:)`，訊息寫「這個能力只在 macOS 有」與它是哪一個能力。型別在 macOS 也編譯，但只在 Linux 被擲出。
- `S2KeyProvider`：`Security`、`LocalAuthentication` 只在 macOS import。`S2Client` 只在目標是 Semantic Scholar 主機時讀 keychain（`readsKeychain`），loopback 的測試覆寫不讀，所以 `S2CommandTests` 這類對 loopback 送請求的測試在 Linux 照常執行，平台錯誤只在真主機的路徑出現。Linux 上 `key()` 擲 `macOSOnly(capability: .keychain)`；`probe()` 回一個新的狀態「這個平台沒有 keychain」，不是「不存在」（試作的 stub 回「不存在」，`s2 status` 因此說錯話）。訊息不提 `security add-generic-password`。
- ASSUMPTION: `akashic s2` 在 Linux 讀不到金鑰時結束碼用既有的 3（缺金鑰），`s2 status` 也結束於 3。另立結束碼要改 CLI 的結束碼表與兩面的契約，使用者沒有要求。
- `akashic fulltext fetch` 在 Linux 於解析帳本路徑與啟動任何行程之前擲 `macOSOnly(capability: .safari)`，結束碼沿用既有的 1。`fulltext take`、`verify` 這些不碰 Safari 的子命令在 Linux 照常運作（只需 `pdftotext`）。
- `~/Library/Caches/akashic/s2-throttle` 與 `~/Library/Application Support/akashic/fulltext-attempts.jsonl` 不改：Linux 上用到它們的能力在用到之前就報錯。
- `mcp-cli-parity`：`akashic_s2` 與 `s2` 兩面在 Linux 給同一句錯誤，契約的新增部分記進 `docs/rulings/mcp-cli-parity.md` 該列的「重新確認」；`fulltext` 是 CLI-only，該列同樣補一句。

### 可刪檢查在 Linux 讀 FS_IOC_GETFLAGS

`DivergenceResolve` 的可刪檢查在 macOS 讀 `.immutable` 屬性；corelibs 對它設定回 `Code=3328`、讀回 nil（6.4.2 量），原樣移植會讓 Linux 永遠說「可刪」。Linux 改以 `ioctl(fd, FS_IOC_GETFLAGS)` 讀旗標，`FS_IMMUTABLE_FL`（0x10）或 `FS_APPEND_FL`（0x20）任一個在就不可刪；讀不到（例如 `ENOTTY`）視為沒有旗標，與 macOS 讀不到屬性時相同。父目錄權限的檢查兩個平台不變。設這兩個旗標要 `CAP_LINUX_IMMUTABLE`，非 root 的 CI 設不了，所以旗標解碼寫成純函式、以表測試；整條路徑的測試在兩個平台改用 0555 的父目錄。

### .gitignore 判讀維持不分大小寫

ASSUMPTION: 這是承重閘，取「產品判讀不變寬」的做法；改成依 `core.ignorecase` 判讀要使用者決定。

- `SourcesIgnoreBlock` 的否定規則判讀刻意不分大小寫（`ruleNegatedLater` 的說明文字寫明「判讀是保守的」）。2026-11-12 在 noble 量：`sources/*` 之後 `!Index.JSONL`，`core.ignorecase` 未設定時 git 仍排除 `sources/index.jsonl`，設成 true 時才放回。akashic 兩種情況都判「被否定」而拒絕，所以 Linux 上只會多拒絕，不會放寬。
- 試作的失敗（第 8 類）是測試要求「與 git 完全一致」。測試改成兩條：akashic 判「在」的每一種排列，`git check-ignore` 都排除受測路徑（不變寬）；`core.ignorecase=true` 時兩者完全一致（macOS 上原本的斷言）。
- 另一個做法是讓判讀依 `core.ignorecase` 走，Linux 上與 git 完全一致、少拒絕一些排列；它讓閘在 Linux 比本做法寬，所以留給使用者。

### macOS 專屬測試逐支略過，Linux 的略過集合等於審過的清單

ASSUMPTION: 依 lead 的設計傾向 7。

- 只能在 macOS 跑的測試，在測試本體第一行呼叫共用的 `MacOSOnly.require(_:)`，Linux 上擲 `XCTSkip`。測試名稱在兩個平台相同，Linux 的輸出逐支列出略過與理由。需要平台框架（`JavaScriptCore`）的程式碼放進 `#if canImport(...)`，測試方法本身兩個平台都編譯。
- 清單 `Tests/linux-skipped-tests.txt` 一行一支：`<Target>.<Class>/<test>`、分類（`macos-only` 或 `environment`）、理由，以 tab 分隔。`environment` 是 macOS 也會因同一個缺件略過的（例如沒有 `duckdb`、沒有真實 corpus）。
- 新守衛 `akashic-guards linux-skip-audit --log <xctest 輸出> --list <清單>`：解析 Linux 測試輸出的略過紀錄，與清單比對，兩個方向的差異都具名、非零結束；清單的行缺分類或理由也紅。負對照 `linux-skip-audit-mutations` 在暫存副本上證明四種注入都會紅。
- 這是新守衛。它只在 Linux CI 跑真正的稽核（需要 Linux 的測試輸出），`trigger-coverage` 與 `workflow-run-scripts` 的期望要涵蓋新的 workflow，`.githooks/protected-ratchet.txt` 補它的兩個檔。

### 本 change 新增的零實例防線逐一裁決

`zero-instance-guards` 要求每一道「現在沒有資料會被它擋下」的防線在 `docs/rulings/zero-instance-guards.md` 的裁決表加一列（含「各列共通的東西」的 bullet），量測寫進 `docs/zero-instance-measurements.md`（寫法照 `measurement-commands-self-prove`）。本 change 有五道，各加一列：

| 防線 | 裁決 | 理由的主幹 |
|---|---|---|
| `Sources/` 不得直接呼叫 `components(separatedBy: "\n")` 的原始碼掃描測試 | 寫 | 換完之後零實例，而新的呼叫點在 macOS 上看不出錯，只會在 Linux 讀 CRLF 時安靜地切錯 |
| `linux-skip-audit` | 寫 | 略過的測試在輸出上與通過的一樣安靜；不對帳，「其餘全部通過」就可以靠多略過幾支達成 |
| Linux 上 Swift 低於 6.4 的 `#error` | 寫 | 零實例的原因是 CI 釘了版本；後果是覆寫記錄時刪掉它，而那一刻沒有任何跡象 |
| CI 在測試後檢查 `Package.resolved` 沒變 | 寫 | 鎖定檔被改寫時建置照樣成功，兩個平台會各自解出不同的圖而沒有人知道 |
| linux workflow 的靜態檢查測試 | 寫 | workflow 被改成以 root 跑或拿掉 digest 時，CI 照樣綠，只是量的不再是 spec 說的那件事 |

新功能的單元測試（切行表、JSON 表、SHA-256 向量、旗標表）不在此列：它們驗的是新寫的程式本身，不是為一個還沒出現的形狀設防。

### 測試改成可攜的做法

| 試作的失敗類別 | 處置 |
|---|---|
| 1 user-immutable 旗標（11 支） | 產品改讀 `FS_IOC_GETFLAGS`（上面）；測試的刪除失敗改由 0555 父目錄注入（非 root 兩個平台都有效）。只驗 macOS `.immutable` 屬性的那幾支保留並標 `macos-only` |
| 2 plugin hook 的 BSD `stat`（5 支） | 產品修（見「plugin hook 改成 GNU 與 BSD 都能用」） |
| 3 測試用的 BSD 工具（3 支加 1 支略過） | `/usr/bin/time -l` 改為以 `getrusage(RUSAGE_CHILDREN)` 讀子行程峰值記憶體（單位：Linux 是 KB、macOS 是 bytes，換算寫在 helper）；以 BSD 檔案旗標注入的寫入失敗改為目錄權限 |
| 4 URLProtocol 回報轉址時 corelibs 崩潰（3 支） | 改成真的 loopback HTTP server（POSIX socket，只綁 127.0.0.1）。`S2CommandTests` 的 `NWListener` 換成同一個 server，16 支在 Linux 照跑 |
| 5 測試假設 macOS 的 XCTest 佈局（1 支崩潰加 3 支安靜略過） | 19 個檔（`8fc7fc0b` 上以 git grep -lE 對 `allBundles` 或 `Bundle(for:` 在 `Tests/` 量）各自用 `Bundle.allBundles`／`Bundle(for:)` 找 products 目錄，收成一個 `TestProducts.directory`，Linux 以 `Bundle.main.executableURL` 定位；`testCanonicalBytesReplayInFreshSubprocesses` 的子行程在 Linux 以測試執行檔加測試名稱重跑，不用 `xcrun xctest` |
| 6 keychain 措辭（2 支） | 斷言 macOS 措辭的兩支標 `macos-only`；另寫 Linux 版，斷言具名的平台錯誤 |
| 7 Foundation 行為差異（6.4.2 剩 2 支） | `PersonIdentityMigrationTests` 的 CRLF 由共用切行函式修；`SanitizationBoundaryTests` 的真實 Foundation 錯誤斷言依賴 macOS 的本地化文字會引用暫存檔名（測試註解自己寫了「本地化依賴」），改成兩條：兩個平台都不得漏出暫存檔名，遮罩註記只在 Foundation 的文字含檔名時出現 |
| 8 大小寫敏感的檔案系統（1 支） | 測試改成「不變寬」加「ignorecase=true 時一致」（見上） |
| 9 沒有能力旗標的放置（2 支） | `testTheVolumeCapabilityProbeReadsTheRealFlags` 標 `macos-only`（`getattrlist` 只有 macOS 有），另寫 Linux 版斷言回 nil；`testTheAddressOnlyAppearsInOneAtomicStepWithTheCompleteContent` 改成只數目標是內容位址的改名，探測用的改名另外斷言 |
| 10 試作自己造成的（3 支） | 不新增 C 目錄，`DisplaySinkCoverageTests` 不受影響；產生器原始碼不動，digest 釘住不變；`ClassicalSemanticsTests` 的 Code 513 是建置與測試用了不同使用者，CI 用同一個非 root 使用者 |

兩個共用 helper 放在 `Sources/AkashicTestGuard/`（它本來就是只被 test target 依賴的 target）：`TestProducts.swift` 與 `LoopbackHTTPServer.swift`。loopback server 是測試用的伺服器，不是 HTTP client，不違反 `web-access-via-safari-browser` 第 2 條，也不在 `network-confinement` 的模式清單裡；放在 `Sources/` 底下這件事要在該檔的檔頭寫明。

其他沒有失敗、但要移植的測試寫法：`FoundationNetworking`、`FoundationXML` 的條件 import；`URLCache(directory:)` 在 corelibs 沒有，helper 改用 `diskPath:`；`RLIMIT_FSIZE` 在 glibc 是 enum；測試檔裡帶 `Darwin.` 前綴的 `write`／`link`／`rename` 改成不帶模組名稱的呼叫；`sigaction` 的欄位名稱（macOS `__sigaction_u`、glibc `__sigaction_handler`）。

`IndexIdentityTests/testIsCurrentAcceptsOwnIndexIncludingPathAliases`（`/private` 別名只有 macOS 有）與 `FulltextHumanLikeTests` 裡用 `JavaScriptCore` 的三支是 `macos-only`。

ASSUMPTION: corelibs 的 `URLSession` 對真實的 3xx 回應是否尊重 task delegate 的拒絕沒有量。S2 連線不跟隨轉址是金鑰外洩的防線，而 Linux 上沒有金鑰；這一組的第一個 task 是量它，若 corelibs 不尊重，三支轉址測試不得以略過收場，改成回報為產品發現、由使用者決定。

### Unicode 表產生器在 Linux 不宣告，信任鏈測試拆成兩支

ASSUMPTION: 依 lead 的設計傾向 9。產生器 import `CryptoKit`，改它會讓 `UnicodeNormalizationV1TrustAnchor.json` 釘住的 digest 失效（試作的第 10 類）。產生器是離線工具，production 不依賴它，所以在 Linux 不宣告，原始碼一個位元組都不動。

`testUnicodeV1TrustChainAndOfficialConformanceArePinned` 現在把「digest 釘住」與「以 `swift run --disable-automatic-resolution` 離線重建產生器」放在同一支。拆成兩支：釘住的檢查兩個平台都跑；離線重建在 Linux 標 `macos-only`（產生器不在 Linux 的套件圖裡）。macOS 上離線重建要從 SwiftPM 全域快取取得所有相依套件，新增的兩個套件也要在快取裡；`ci.yml` 的快取 key 綁 `Package.resolved`，第一次會 miss 再補。task 1.1 的驗收包含在 macOS 單跑這支測試。

### BotSignals 字詞類別的測試只比對 Python 3.13 認得的碼位

`BotSignalsPythonBoundaryTests/testTheWordClassAgreesWithPythonsWordOnEveryScalar` 在 macOS 通過、在兩個 Linux 映像失敗。它不是 macOS 專屬的測試（試作 §11.4 推測 macOS 可能也紅；2026-11-12 在 macOS 跑過，6 支全部通過），依裁決 2 要在 Linux 通過，所以屬於本 change。

- 產品怎麼判斷：`BotSignals.wordClass` 是 ICU 正則的字元類 `(?-i:[\p{L}\p{N}_])`，用的是 Foundation 帶的 ICU 的 Unicode 資料。測試拿它與 `PyText.isWord`（以標準函式庫的 `generalCategory`／`numericType` 重寫 Python 3.13 的 `\w`）在每個已指派、非私用區的 scalar 上比對。
- 量測（2026-11-12，同一支探針分別在 macOS 與 `swift:6.4.2-noble` 跑）：兩個平台的標準函式庫都是 Unicode 17；macOS 的 ICU 與它一致（0 個不一致），Linux 的 ICU 比它舊——4,657 個不一致全部是 age 17.0 的碼位（例如 U+088F、U+A7CE、U+10940），全部是 ICU 判「不是字詞字元」、標準函式庫判「是」。age 16.0 以前的碼位兩邊一致。
- 這 4,657 個碼位 Python 3.13（`unicodedata.unidata_version` 為 15.1.0）根本不認得，Python 的 `\w` 對它們是 false；在 macOS 上 ICU 與標準函式庫都說 true，測試通過只表示兩者彼此一致，不表示與 Python 一致。`PyText` 的檔頭已把「新指派的碼位可能不同」列為已知差異。
- 做法：測試只比對 age 不超過 15.1 的碼位，也就是 Python 3.13 的 Unicode 資料涵蓋的範圍；比對的碼位數要過一個下限，空掃描不算通過。產品不改。
- 不選「讓字詞類別不隨 Unicode 版本變動」：那要把產品的 ICU 字元類換成固定版本的表（repo 有信任鏈釘住的 `Vendor/Unicode/15.1.0/UnicodeData.txt`，可以產生這張表），會改變 macOS 的行為——Unicode 16、17 的新字母旁邊的訊號從「不命中」變「命中」，違反「macOS 行為不變」；也多一張要維護的 Unicode 表，而測試的命題（與 Python 3.13 一致）不需要它。

### plugin hook 改成 GNU 與 BSD 都能用

`plugin/hooks/check-cli.sh` 讀連結數（`stat -L -f %l`）與修改時間（`stat -L -f %m`）的兩處是 BSD 寫法；GNU 的 `stat -L -f %m` 印的是檔案系統資訊並以 1 結束（試作在 jammy 量）。改成一個函式：`stat --version` 成功（GNU）時用 `stat -L -c %h`／`%Y`，否則用 BSD 寫法。`date -r FILE` 兩邊都能用，不改。這支 hook 是 `swift-is-the-implementation-language` 例外 1 的具名成員（#775），改的是它既有的判斷，不新增 shell 檔。這支 hook 是裝到使用者機器上的 plugin 殼，所以 plugin 殼的版號要升（`plugin-shell-version` 守衛會要求），合併前後各查一次 main 上的版號有沒有被別的 PR 先用掉。

### akashic-guards 維持零相依

依 lead 的設計傾向 9。`PluginShellVersion.swift` 的 `CryptoKit` 換成自帶的 `PortableSHA256`（約 60 行），兩個平台用同一份、不分支。正確性由 spec 的四組公開測試向量釘住，另在 macOS 以隨機輸入與 CryptoKit 差分比對。測試以 `@testable import akashic_guards` 從 `AkashicKitTests` 呼叫，這要把 `akashic-guards` 加進該 test target 的依賴；若 executable target 在兩個平台的 test target 裡 import 不起來，改為加一個只供測試的隱藏子命令（task 10.1 決定並記錄在 design 的這一節）。`memmem` 改用標準庫的 `firstRange(of:)`（`SourcesIgnoreBlock` 與 `ZeroInstanceRowsAudit` 兩處）：jammy 的 glibc 2.35 不在預設標頭露出 `memmem`。

### 6.4.2 在 Linux 的警告全部修掉

試作在 6.4.2 量到 18 個警告位置：13 個是 `createFile(atPath:contents:attributes:)` 在 corelibs 沒有 `@discardableResult`（改成 `_ =`），3 個是並行閉包裡改寫捕捉的變數（改成在閉包外收集結果），2 個是試作自己的 `@_implementationOnly`（本做法不用它）。Linux 也以 `-warnings-as-errors` 建置，macOS 的警告數照舊是 0。

### biblatex-apa-swift 用同一個 SQLite 套件，先在那個 repo 合併

ASSUMPTION: submodule 的 `ZoteroDiff.swift` 也 import `SQLite3`。在那個 repo 用同一個 swift-toolchain-sqlite 與同一種條件寫法。試作在那邊用的是另一個 system library target（名字要與本 repo 的避開）；改成套件之後兩邊引用同一個模組，名字衝突不存在，也不要求 Linux 機器有 `sqlite3.h`。那個 repo 的合併與 tag 由使用者決定；本 repo 的 submodule 只能指向已合併的 commit，所以這一組是所有 Linux 建置的前置，要等使用者。

### Linux CI 新增一個 workflow

- `.github/workflows/linux.yml`：矩陣兩個映像，`runs-on: ubuntu-24.04`，`container:` 以 digest 指定。容器內先以 root 安裝 `git`、`poppler-utils`，建一個非 root 使用者，之後建置、測試、守衛全部以那個使用者執行（試作 §5.1：root 會讓 77 支權限相關測試略過，建置與測試用不同使用者會造成 Code 513）。
- 步驟：checkout（釘 SHA、`persist-credentials: false`、`fetch-depth: 0`、連同 submodule 一起取）→ 把工作目錄的擁有者改成那個非 root 使用者，並為他把工作目錄加進 git 的 `safe.directory`（checkout 在容器裡以 root 執行，不改的話他寫不了 `.build`，測試裡呼叫的 git 也會報 dubious ownership）→ 以 `--force-resolved-versions` 與 `-warnings-as-errors` 建置含測試 → `swift test --force-resolved-versions`，輸出存檔 → 檢查 `Package.resolved` 沒有變動（放在測試之後，測試的 resolve 也算在內）→ `akashic-guards linux-skip-audit`。
- ASSUMPTION: 觸發條件與 `ci.yml` 相同（只在 push to main，沿用它的 `paths-ignore`）。Linux runner 是 1× 計費，也可以在 PR 跑，但 repo 有計費事故的紀錄（CLAUDE.md），要不要在 PR 跑由使用者決定。
- `ci.yml` 檔頭「沒有 Linux 選項」那句改掉。CLAUDE.md 記的 #435（ubuntu 沒有 toolchain，所以守衛只能在 macOS 跑）的前提從此不成立，是否把守衛移到 Linux runner 記在 #807。

## Implementation Contract

**行為（完成時觀察得到的）：**

- 在 `swift:6.4.2-noble` 與 `swift:6.4.2-jammy`，以非 root 使用者建置（`--build-tests --force-resolved-versions -Xswiftc -warnings-as-errors`）成功、零警告；`swift test` 沒有失敗；略過的測試集合等於 `Tests/linux-skipped-tests.txt`。
- 同一個 commit 在 macOS 的 `-warnings-as-errors` 建置、`swift test`、`.githooks/run-guards.sh`、pre-push 全部通過。
- `Package.resolved` 在兩個平台 resolve 後逐位元組不變。
- Linux 上 `akashic s2 paper DOI:10.1037/a0038889` 結束碼 3、訊息含 macOS 與 keychain、不含 `security add-generic-password`、沒有送出請求；`akashic s2 status` 說 keychain 在此平台不可用；`akashic fulltext fetch` 結束碼 1、帳本檔沒有被建立。
- Linux 上 `store-source`：位址已被占用時不覆寫；放置不支援時具名拒絕、零寫入；每次存檔前在分片目錄實際放一次。

**介面：**

- `LineSplitting.lines(_ text: String) -> [String]`（AkashicCore，public）；`akashic-guards` 內部的 `GuardLineSplitting` 同一份行為。
- `JSONScalar.classify(_ value: Any) -> JSONScalar.Kind`（AkashicCore，public），`Kind` 五個 case 如上。
- `PlatformCapabilityError.macOSOnly(capability:)`（AkashicCore），`capability` 是封閉列舉：`keychain`、`safari`。
- `akashic-guards linux-skip-audit --log <path> --list <path>` 與 `linux-skip-audit-mutations`；`.githooks/run-guards.sh` 只跑負對照（真正的稽核需要 Linux 的測試輸出，只在 Linux CI 跑）。
- `Tests/linux-skipped-tests.txt`：UTF-8，每行 `<Target>.<Class>/<test>`、`macos-only` 或 `environment`、理由，以 tab 分隔，`#` 開頭為註解。
- `MacOSOnly.require(_ reason: String) throws`、`TestProducts.directory`、`LoopbackHTTPServer`（AkashicTestGuard）。

**會動到的原始檔（依 `8fc7fc0b` 量）：**

- import `CryptoKit` 的 11 個原始檔：`Sources/AkashicCore/AuthorshipCompleteness.swift`、`Sources/AkashicCore/DeterministicUUID.swift`、`Sources/AkashicSkillTools/AbstractProposals.swift`、`Sources/AkashicSkillTools/CrossrefMatch.swift`、`Sources/AkashicStoreIO/LibrarySnapshot.swift`、`Sources/AkashicStoreIO/SourceChunks.swift`、`Sources/AkashicStoreIO/SourceStore.swift`、`Sources/AkashicZoteroImport/ZoteroMapping.swift`、`Sources/TractatusDocs/SourceManifest.swift`、`Sources/TractatusDocs/Validation.swift`、`Sources/akashic-guards/PluginShellVersion.swift`（最後一個改用自帶 SHA-256）；另有 14 個測試檔。
- import `Darwin`：`Sources/AkashicStoreIO/SourceOccupant.swift`、`Sources/AkashicStoreIO/SourcePlacement.swift`、`Sources/AkashicStoreIO/SourcesIgnoreBlock.swift`；測試 `Tests/AkashicCLITests/SourceSignalCleanupCLITests.swift`、`Tests/AkashicKitTests/SourcePlacementTests.swift`。
- CF 判讀：`Sources/AkashicCore/JSONInteger.swift`、`Sources/AkashicMCPKit/ReferenceWriteParsing.swift`、`Sources/AkashicMCPKit/UpdatePerson.swift`、`Sources/AkashicMCPKit/VenueNameSegmentEdit.swift`、`Sources/AkashicMCPKit/VenueReferenceRemoval.swift`、`Sources/AkashicSkillTools/AbstractProposals.swift`、`Sources/AkashicSkillTools/CrossrefMatch.swift`、`Sources/AkashicSkillTools/FulltextFetch.swift`、`Sources/AkashicStoreIO/SourceStore.swift`、`Sources/akashic/CreateEntryCommand.swift`。
- 切行：「共用切行函式」列的 20 個檔。
- 其餘：`Sources/AkashicSQLite/SQLiteDB.swift`、`Sources/AkashicS2/S2KeyProvider.swift`、`Sources/AkashicS2/S2Client.swift`、`Sources/AkashicS2/S2Tool.swift`、`Sources/akashic/FulltextCommands.swift`、`Sources/AkashicStoreIO/DivergenceResolve.swift`、`Sources/AkashicStoreIO/LibraryStore.swift`（版本下限）、`Sources/AkashicZoteroImport/ZoteroStorageFile.swift`、`plugin/hooks/check-cli.sh`。

**失敗模式：**

- 版本下限：Linux 上 Swift 低於 6.4 是編譯錯誤，不是執行期檢查。
- 放置：清單外的 errno 具名擲出、不退；`dlsym` 找不到符號走 `link(2)`。
- 平台錯誤：在任何網路請求、檔案寫入、子行程之前擲出。
- 略過稽核：兩個方向的差異都非零結束並具名。

**範圍：** 在內的是上面列的建置、產品修正、測試改寫、守衛、CI 與文件（README 的 Linux 建置一節）。不在內的見 Non-Goals。

## Risks / Trade-offs

- [所有量測都在 aarch64，CI 是 x86_64] → 第一次 CI 就是量測；CI 那一組的驗收是兩個 x86_64 job 都綠，紅了照實回報。
- [Linux 的 ICU 與標準函式庫的 Unicode 版本不同（量到 ICU 停在 16、標準函式庫是 17）] → 字詞類別的測試只比對 Python 3.13 認得的碼位（見「BotSignals 字詞類別的測試只比對 Python 3.13 認得的碼位」）；其他以 ICU 與標準函式庫交叉比對的測試若在 Linux 紅，同樣先量差異是否全落在 Unicode 16 以後的碼位。
- [corelibs 的 URLSession 對真實轉址的行為沒量] → 測試可攜性那一組的第一個 task 量；不符時當產品發現回報，不以略過收場。
- [`renameat2` 的 `EINVAL`、`ENOSYS` 與符號缺席三條退路只在測試接縫上驗過，沒有真的檔案系統（NFS、FUSE、vfat）可量] → 接縫測試把三條都走一次；真實檔案系統留給使用者遇到時回報。
- [Linux 的 `fsync` 是否清裝置快取取決於檔案系統的 barrier] → 寫進 design 與 README，不宣稱等價。
- [Linux 每次存檔多一次探測放置] → 接受，換到的是不維護允許清單。
- [設不了 immutable 旗標，Linux 讀旗標的整條路徑不在 CI 測到] → 旗標解碼以純函式測，ioctl 呼叫本身以讀到 0 的情況在 CI 測。
- [swift-crypto 在 macOS 是否完全不編譯沒量] → task 1.1 驗收。
- [SQLite 版本兩個平台不同（macOS 系統 3.54.0、Linux 3.53.4，swift-toolchain-sqlite 1.0.13）] → 試作的特性掃描 0 處；日後若用到新特性，兩個平台的測試都要過。
- [Unicode 信任鏈的離線重建依賴 SwiftPM 全域快取裡有新套件] → task 1.1 在 macOS 單跑；CI 快取 key 綁鎖定檔。
- [CI 計費] → 觸發條件與 `ci.yml` 相同，是否加 PR 由使用者決定。
- [`.gitignore` 判讀在 Linux 會多拒絕一些大小寫變體的排列] → 接受；改依 `core.ignorecase` 由使用者決定。

## Migration Plan

1. 前置：biblatex-apa-swift 那個 repo 的修改合併並 tag（等使用者），這邊更新 submodule。
2. manifest 與相依、CryptoKit、SQLite、平台 import：Linux 建置成功、macOS 照舊。
3. 產品行為：放置閘、切行、JSON 判讀、可刪檢查、平台錯誤、hook。
4. 測試可攜性與略過清單、守衛、警告。
5. CI 最後開。

第 1 步要等使用者，第 2 到 4 步在那之前就能做：在工作 clone 裡把 submodule 切到 biblatex-apa-swift 未合併的分支、在本機的兩個映像建置與測試，但 submodule 的指標不 commit；第 1 步完成後再把指標改成已 tag 的 commit 並重跑一次。

每一步 macOS 的全套測試都要綠。回復：revert 整個 change；macOS 不依賴任何 Linux 專用的東西，鎖定檔多出的套件隨 revert 拿掉。

## Open Questions

需要使用者決定、本 design 以保守做法暫定的：

1. Linux CI 只在 push to main 跑（暫定），還是也在 PR 跑。
2. `.gitignore` 判讀維持不分大小寫（暫定），還是依 `core.ignorecase`。
3. biblatex-apa-swift 用 swift-toolchain-sqlite 的做法，以及那個 repo 的合併與 tag。
4. `akashic s2` 在 Linux 沿用結束碼 3（暫定）還是另立。
5. 存檔途中收到 SIGINT、SIGTERM、SIGHUP 時，Linux 要不要刪掉寫到一半的暫存檔。macOS 以 dispatch 的 signal source 接管這三個訊號、刪掉暫存檔再照預設結束。2026-11-12 在 noble 與 jammy 量到同一段寫法在 Linux 不成立：source `resume` 之後訊號的處置變成 libdispatch 自己的 handler；處置是 `SIG_IGN` 時 source 收不到訊號；事件處理裡還原預設再 `raise` 不會結束行程。暫定：Linux 不接管，訊號照 kernel 的預設結束行程，留下的暫存檔由 doctor 的殘留暫存檔檢查報出、不自動刪。代價是 Linux 上存檔被中斷會留下暫存檔（單檔上限 256 MiB），而 `SourcePlacementTests` 有兩支、`SourceSignalCleanupCLITests` 有兩支在 Linux 是紅的，沒有標略過。另一個做法是不經 libdispatch、自己以 `sigaction` 或專門等訊號的 thread 實作，還沒有試作。task 4.8 在這一項決定之前不勾。
6. Linux 的 `fsync(2)` 回「不支援」的 errno（`ENOTSUP`、`EINVAL`、`ENOSYS` 這一類）時，暫定算成功、繼續放置（與 macOS 上 `F_FULLFSYNC` 與 `fsync` 都不支援時的結局相同），還是改成拒絕存檔。`EIO` 這類真的錯誤兩個平台都拒絕。
