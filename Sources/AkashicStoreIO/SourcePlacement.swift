import Foundation
import Darwin
import AkashicCore

/// `sources/` 存檔的暫存檔與「放上位址」那一步（#703；R1 verify 之後從 `SourceStore.swift` 拆出——那個檔加上這一輪會超過 800 行）。
///
/// 暫存檔的檔名只有一個形狀（`temporaryBlobName`），預演（`preflightStoreSource`）、建立（`writeBlob`）、殘留的報告
/// （`auditSourceIndex` 的 `strayTemporaryFiles`）都讀它。
extension LibraryStore {

    /// 存檔暫存檔的檔名（#703）：`.<62 hex>.incoming-<token>`，住在 blob 同一個分片目錄裡。`preflightStoreSource` 問排除的、
    /// `writeBlob` 建立的、`auditSourceIndex` 認得的都是這一個形狀（R1 verify 第 3、17、21 則：預演先前沒問暫存路徑，
    /// 乾跑說可以、實跑才在暫存路徑被拒，而多筆操作已經寫了前面幾筆）。token 要是 UUID——兩個入口以 `checkTemporaryToken` 先驗。
    internal static func temporaryBlobName(digest: String, token: String) -> String {
        ".\(digest.dropFirst("sha256:".count).dropFirst(2)).incoming-\(token)"
    }

    /// 分片目錄裡的一個檔名是不是 `temporaryBlobName` 的形狀（token 是 UUID）。
    internal static func isTemporaryBlobName(_ name: String) -> Bool {
        guard name.hasPrefix("."), let r = name.range(of: ".incoming-") else { return false }
        let rest = name[name.index(after: name.startIndex)..<r.lowerBound]
        return rest.count == 62 && rest.allSatisfy { "0123456789abcdef".contains($0) }
            && UUID(uuidString: String(name[r.upperBound...])) != nil
    }

    /// 暫存檔 token 的形狀（#703 R2 verify 第 20 則）：要是 UUID。`preflightStoreSource` 與 `storeSource(contentsOf:)` 都是公開的、
    /// token 直接接進檔名；不是 UUID 的 token 造出的暫存檔 `isTemporaryBlobName` 認不得，被殺掉之後 doctor 看不到它。兩個入口在任何
    /// 讀寫之前先驗，不合就具名擲出（fail-closed）。
    internal static func checkTemporaryToken(_ token: String) throws {
        guard UUID(uuidString: token) != nil else {
            throw StoreIOError.invalidInput(
                what: "sources/ 暫存檔 token",
                why: "要是 UUID（暫存檔名 .<hex>.incoming-<UUID> 只有這一個形狀，doctor 才認得殘留），實得「\(displaySafeInvisible(token, max: 80))」")
        }
    }

    /// 把暫存檔放到位址上的系統呼叫（#703 R1 verify 第 5、9、12、33 則；R2 verify 第 1 則；b26 F6 之後只剩兩條）。測試接縫：
    /// 換掉其中一個，模擬不支援 `RENAME_EXCL` 的檔案系統（2026-09-30 在磁碟映像上實測：exFAT 與 FAT32 的 `renamex_np(RENAME_EXCL)`
    /// 與 `link(2)` 都回 `ENOTSUP`），或讓磁碟區回報做不到不覆寫的原子放置。
    internal struct BlobPlacement {
        /// 回 0 或 errno。
        var renameExclusive: @Sendable (_ from: String, _ to: String) -> Int32
        /// 回 0 或 errno。
        var hardLink: @Sendable (_ from: String, _ to: String) -> Int32
        /// 把一個已寫完的檔同步到裝置：回 0 或 errno（#703 R2 verify 第 21 則）。暫存檔在放上位址之前呼叫一次；預設是
        /// `LibraryStore.syncFile`。測試接縫：驗「放上位址之前真的同步了」與「同步失敗就不放」。
        var sync: @Sendable (_ fd: Int32) -> Int32 = { LibraryStore.syncFile($0) }
        /// 這個路徑所在的磁碟區能不能做不覆寫的原子放置（`RENAME_EXCL` 或 hard link 至少一個）：`true`／`false`，判不出來是 `nil`
        /// （`nil` 不擋，由實際呼叫的結果決定）。預設讀磁碟區的能力旗標（`getattrlist`）。**在建立任何檔案之前**問——
        /// 做不到的磁碟區上一個位元組都不寫（b26 F6：#703 的使用者裁決）。
        var volumeSupportsExclusivePlacement: @Sendable (_ path: String) -> Bool? = {
            LibraryStore.volumeSupportsExclusivePlacement(at: $0)
        }
        static let system = BlobPlacement(
            renameExclusive: { renamex_np($0, $1, UInt32(RENAME_EXCL)) == 0 ? 0 : errno },
            hardLink: { Darwin.link($0, $1) == 0 ? 0 : errno })
    }

    /// 放上位址的結果：放了，或位址上已經有東西（不覆寫；那是什麼由呼叫端以 `sourceOccupant` 判）。
    internal enum Placed { case placed, alreadyThere }

    /// 檔案系統「不支援這個呼叫」的 errno（封閉列舉）：`ENOTSUP`／`EOPNOTSUPP`（實測 exFAT、FAT32）；`renamex_np` 另收 `EINVAL`
    /// （手冊：旗標值不被接受——SMB／NFS 掛載可能以它回應，沒有實測），`link` 另收 `EPERM`（Linux 與部分網路檔案系統以它表示不支援
    /// hard link；macOS 手冊的 `EPERM` 只指目錄，暫存檔不是目錄）。其餘 errno 不退，直接具名擲出。
    private static func placementUnsupported(_ code: Int32, orAlso extra: Int32) -> Bool {
        code == ENOTSUP || code == EOPNOTSUPP || code == extra
    }

    /// 系統給的錯誤說明（固定英文字串，不含使用者資料）。
    private static func errnoText(_ code: Int32) -> String { "errno \(code)，\(String(cString: strerror(code)))" }

    /// 磁碟區做不到不覆寫的原子放置時的拒絕（b26 F6，使用者 2026-10-02 裁決）：**每一次存檔**都具名拒絕、零寫入，說要把 store 放在
    /// APFS 或 HFS+。曾有第三條路（以 `O_EXCL` 建立目的檔後逐塊複製），拿掉的理由：exFAT／FAT32 上新建檔案的 inode 在第一次寫入後會變，
    /// 靠 inode 認「自己的檔」的失敗清理與訊號清理全部失效，半截檔留在內容位址上、讀回驗證抓到的壞檔之後還被記進 index。
    internal static func unsupportedVolumeError(_ detail: String) -> StoreIOError {
        StoreIOError.invalidInput(
            what: "sources/ 存檔",
            why: "sources/ 所在的檔案系統做不到不覆寫的原子放置（\(detail)；exFAT、FAT32 即此類）——沒有存任何東西。"   // display-safe-exempt: detail 是本檔的固定句與 errno 說明
                + "把 store 放在 APFS 或 HFS+ 的磁碟區上")
    }

    /// 磁碟區的能力旗標（`getattrlist`，`ATTR_VOL_CAPABILITIES`）：`RENAME_EXCL` 或 hard link 至少一個有 → `true`；兩個旗標都有效而都沒有 → `false`
    /// （實測 exFAT、FAT32：兩者都是有效旗標、值為 0；APFS：兩者皆 1）；其餘（查不到、旗標無效）→ `nil`，交給實際呼叫的結果。
    internal static func volumeSupportsExclusivePlacement(at path: String) -> Bool? {
        struct VolCaps { var length: UInt32 = 0; var caps = vol_capabilities_attr_t() }
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_CAPABILITIES)
        var buffer = VolCaps()
        guard getattrlist(path, &request, &buffer, MemoryLayout<VolCaps>.size, 0) == 0 else { return nil }
        let format = (cap: buffer.caps.capabilities.0, valid: buffer.caps.valid.0)
        let interfaces = (cap: buffer.caps.capabilities.1, valid: buffer.caps.valid.1)
        let hardLinks = (cap: format.cap & UInt32(VOL_CAP_FMT_HARDLINKS) != 0, valid: format.valid & UInt32(VOL_CAP_FMT_HARDLINKS) != 0)
        let renameExcl = (cap: interfaces.cap & UInt32(VOL_CAP_INT_RENAME_EXCL) != 0, valid: interfaces.valid & UInt32(VOL_CAP_INT_RENAME_EXCL) != 0)
        if (hardLinks.valid && hardLinks.cap) || (renameExcl.valid && renameExcl.cap) { return true }
        if hardLinks.valid && renameExcl.valid { return false }
        return nil
    }

    /// 存檔之前（`storeSource` 的第一步、`preflightStoreSource`）問磁碟區：做不到不覆寫的原子放置就具名拒絕，一個位元組都不寫。
    /// `sources/` 還不存在時問最近的既有上層（同一個磁碟區）。
    internal func assertSourcesVolumeCanPlace(_ placement: BlobPlacement) throws {
        var probe = sourcesDir
        while !FileManager.default.fileExists(atPath: probe.path), probe.path != "/" { probe = probe.deletingLastPathComponent() }
        if placement.volumeSupportsExclusivePlacement(probe.path) == false {
            throw Self.unsupportedVolumeError("磁碟區回報不支援 RENAME_EXCL 與 hard link")
        }
    }

    /// 把一個已寫完的檔的內容推到儲存裝置（#703 R2 verify 第 21 則；b26 F6）：先 `F_FULLFSYNC`（連裝置的寫入快取一起清——`fsync(2)` 在 macOS
    /// 不保證這一點，斷電時被撕裂的 blob 會以合法的位址留下）。**只有 `F_FULLFSYNC` 回「不支援」（`ENOTSUP`／`EOPNOTSUPP`／`EINVAL`）才退到
    /// `fsync(2)`**——真的 I/O 錯誤（`EIO`、`ENOSPC`）不能被後面的 `fsync` 成功蓋掉：`fsync` 成功不證明裝置快取清了。`fsync` 也回
    /// 「不支援」時當成盡力而為、回 0（那個檔案系統沒有可用的同步手段，不是 I/O 錯誤）。回 0 或 errno。
    /// **`EINTR`：重試**（每個呼叫至多 8 次；訊號被我們忽略或由 dispatch 接手，實際上不會發生，仍以有界迴圈寫明）；用完仍 `EINTR` 當成錯誤回傳。
    /// 2026-10-01 本機實測（APFS、200 KB 的檔）：`F_FULLFSYNC` 平均 4.3 ms、`fsync` 0.1 ms——`copy-zotero-attachments` 一趟 2,817 個附件約多 12 秒。
    /// 兩個系統呼叫是參數（預設是真的），測試以它們模擬「`F_FULLFSYNC` 回 `EIO`、`fsync` 成功」。
    internal static func syncFile(_ fd: Int32,
                                  fullFsync: (Int32) -> Int32 = { fcntl($0, F_FULLFSYNC) == 0 ? 0 : errno },
                                  plainFsync: (Int32) -> Int32 = { fsync($0) == 0 ? 0 : errno }) -> Int32 {
        func retryingInterrupts(_ call: () -> Int32) -> Int32 {
            var code = call()
            var retries = 0
            while code == EINTR, retries < 8 { code = call(); retries += 1 }
            return code
        }
        func unsupported(_ code: Int32) -> Bool { code == ENOTSUP || code == EOPNOTSUPP || code == EINVAL }
        let full = retryingInterrupts { fullFsync(fd) }
        if full == 0 { return 0 }
        guard unsupported(full) else { return full }
        let plain = retryingInterrupts { plainFsync(fd) }
        return plain == 0 || unsupported(plain) ? 0 : plain
    }

    /// 暫存檔放上位址（#703 R1；b26 F6 起只剩兩條）。兩條依序，每一條都**不覆寫**位址上已有的東西，而且**位址上出現的名字一律是寫完、
    /// 同步過的完整內容**——`renamex_np` 與 `link` 都是一個原子動作，名字出現的那一刻就是整份：
    ///
    /// 1. `renamex_np(RENAME_EXCL)`——原子、排他。`EEXIST`＝有人先放了。
    /// 2. 檔案系統不支援 → `link(2)`＋刪掉暫存名——同樣排他（目的地在就 `EEXIST`）。
    ///
    /// 兩條都不支援（exFAT、FAT32）→ 具名拒絕（`unsupportedVolumeError`）。曾有第三條（以 `O_EXCL` 建立目的檔後逐塊複製、讀回驗證），
    /// 使用者 2026-10-02 裁決拿掉：它讓未完成的檔在最終檔名下看得到（同時進來的存檔把大小相同的半截檔當成「已經在了」），而且在 exFAT 上
    /// 靠建立當下的 inode 認自己的檔、清理全部失效。正常情形下這個拒絕在建立暫存檔之前就由磁碟區的能力旗標擋下（`assertSourcesVolumeCanPlace`）；
    /// 走到這裡才發現不支援（磁碟區沒有回報能力旗標）時，暫存檔由呼叫端的 `defer` 以名字刪掉。
    ///
    /// **不覆寫的保證**：兩條都不會取代位址上已有的東西；`renamex_np` 與 `link` 失敗時位址上的東西不動。**我們從不刪位址上的檔**——
    /// 刪的只有暫存名。
    internal func placeTemporaryBlob(_ tmp: String, at dest: String, digest: String,
                                    placement: BlobPlacement) throws -> Placed {
        func fail(_ why: String) -> StoreIOError {
            StoreIOError.invalidInput(what: "sources/ 存檔", why: "\(why)——digest \(digest) 沒有存")   // display-safe-exempt: why 是本函式組的固定句與 errno 說明；digest 是本函式的呼叫端算的 SHA-256 十六進位
        }
        let excl = placement.renameExclusive(tmp, dest)
        if excl == 0 { return .placed }
        if excl == EEXIST { return .alreadyThere }
        guard Self.placementUnsupported(excl, orAlso: EINVAL) else {
            throw fail("暫存檔無法放到位址上（renamex_np RENAME_EXCL：\(Self.errnoText(excl))）")
        }
        let ln = placement.hardLink(tmp, dest)
        if ln == 0 {
            unlink(tmp)   // 失敗的話暫存名留著：doctor 會把它報成殘留的暫存檔，位址上的那一份不受影響
            return .placed
        }
        if ln == EEXIST { return .alreadyThere }
        guard Self.placementUnsupported(ln, orAlso: EPERM) else {
            throw fail("這個檔案系統不支援排他改名（RENAME_EXCL：\(Self.errnoText(excl))），hard link 也失敗（\(Self.errnoText(ln))）")
        }
        throw Self.unsupportedVolumeError("RENAME_EXCL：\(Self.errnoText(excl))；link：\(Self.errnoText(ln))")
    }
}

/// 存檔進行中、還沒放上位址的暫存檔（#703 R2 verify 第 27 則）：`SIGINT`／`SIGTERM`／`SIGHUP` 送來時刪掉它們再照原本的
/// 方式結束行程。R1 之前只有 `defer` 清理，而訊號結束行程時 `defer` 不跑——實測 Ctrl-C 留下 118 MB、SIGTERM 留下 243 MB 的暫存檔。
///
/// **登記的只有暫存檔，以名字認它**（b26 F6）：暫存檔的名字帶這一次呼叫自己產生的 UUID（`temporaryBlobName`），以 `O_CREAT | O_EXCL`
/// 建立——位址上的名字（會被別人搶先放上的那個）從不登記、從不被我們刪。R2 的第三條路曾登記目的檔、並以建立當下的 `(device, inode)` 認
/// 「自己的檔」；exFAT／FAT32 上新建檔案的 inode 在第一次寫入後會變，那個比對永遠不成立、清理全部失效。第三條路拿掉之後，名字本身就是
/// 身分（122 位元的隨機 token、`O_EXCL` 保證是這一次建立的），所以**不再比 inode**——在任何檔案系統上都一樣成立。登記的路徑刪之前仍要
/// `lstat` 是普通檔（名字上被換成目錄或 symlink 時不動它）。
///
/// **只在有檔登記時接管訊號**：第一個登記時把這三個訊號中「原本是預設處置」的改成忽略、由 dispatch 的訊號來源接手；最後一個撤銷時還原
/// （還原時處置若已被別人改掉就不動它）。原本就被忽略的（`nohup` 的 SIGHUP）或有別的處理的不接管——那個訊號本來就不該由我們結束行程，
/// 也就不該刪檔。接手的處理：刪掉登記的檔、把處置改回預設、再對自己送一次同一個訊號——行程照樣被那個訊號結束，只是晚一點。
///
/// **接管在建立檔案之前**（`create`）：訊號在「檔案已建立、還沒登記」的那一瞬間送到時，先前的寫法以預設處置結束行程、留下檔案（第一版的
/// 測試實際撞到）。現在「接管 → 建立 → 登記」在同一把鎖裡，處理訊號的那一邊要等它做完才刪；刪完、送出訊號之前也一直拿著鎖，下一個檔建不起來。
///
/// **訊號來源是長駐的，事件送到時重新讀處置**（b26 F6，三席同指）：來源建立一次、之後不取消（取消會吞掉「還原之後才送到的那一下 Ctrl-C」）。
/// kqueue 的 `EVFILT_SIGNAL` 在行程自己裝了 handler 時也會記錄訊號，所以長駐的來源會在主機之後自己裝 handler 的行程裡收到事件——
/// 先前以「最近一次接管時是預設處置」的旗標決定要不要結束行程，主機的 handler 會被 `SIG_DFL` ＋ `raise` 直接殺掉。現在事件送到時讀當下的
/// 處置（`shouldTerminate`）：只有「我們正在忽略它」或「處置是預設（我們還原之後才送到的事件）」才結束行程。
///
/// **清不到的**：`SIGKILL`、斷電、`abort()`——那些由 doctor 的 `strayTemporaryFiles` 報（只報不刪）。
/// **誠實邊界**：`SIG_IGN` 是整個行程的、`exec` 會繼承——存檔進行中（最長一個 256 MiB 的複製加同步）若另一個執行緒 spawn 子行程，
/// 子行程會繼承被忽略的 SIGINT／SIGTERM／SIGHUP。CLI 與序列化的 MCP actor 目前不會這樣（排除驗證的 `git` 在建立暫存檔之前結束）；
/// 內嵌 `AkashicStoreIO` 的主機要自己避開。
internal enum InFlightSourceFiles {
    private struct Entry { let path: String }
    private static let lock = NSLock()
    private static var entries: [Int: Entry] = [:]
    private static var nextID = 0
    /// 這一次接管的訊號（原本是預設處置的那幾個）——還原時只動它們；也是「我們現在正在忽略它」的事實。
    private static var taken: [Int32] = []
    private static var sources: [Int32: DispatchSourceSignal] = [:]
    static let signals: [Int32] = [SIGINT, SIGTERM, SIGHUP]

    /// 一個訊號當下的處置。
    enum Disposition: Equatable { case defaultAction, ignored, custom }

    /// 訊號來源的事件送到時，要不要刪檔並結束行程（純函式，`handle` 與測試共用）。
    /// `weAreIgnoring`：這個訊號是不是這一次接管、現在還在忽略的。
    /// - 我們在忽略它、處置也還是忽略 → 是（我們的接管；事件就是那一下 Ctrl-C）。
    /// - 處置是預設 → 是（我們還原之後才送到的事件；沒有它，Ctrl-C 被吞掉）。預設處置下核心直接結束行程，事件只可能是忽略期間留下的。
    /// - 處置是別人的 handler、或不是我們忽略的 `SIG_IGN`（主機自己的）→ 否：那個訊號不歸我們管。
    static func shouldTerminate(disposition: Disposition, weAreIgnoring: Bool) -> Bool {
        switch disposition {
        case .ignored: return weAreIgnoring
        case .defaultAction: return true
        case .custom: return false
        }
    }

    static func currentDisposition(_ sig: Int32) -> Disposition {
        var current = sigaction()
        guard sigaction(sig, nil, &current) == 0 else { return .custom }
        let handler = unsafeBitCast(current.__sigaction_u, to: Int.self)
        if handler == unsafeBitCast(SIG_DFL, to: Int.self) { return .defaultAction }
        if handler == unsafeBitCast(SIG_IGN, to: Int.self) { return .ignored }
        return .custom
    }

    /// 接管訊號、建立檔案（`make` 回 descriptor 或負值）、登記它的路徑——三步在同一把鎖裡。建立失敗時不登記、回原值；
    /// 登記的 id 由 `unregister` 撤銷。
    static func create(path: String, _ make: () -> Int32) -> (fd: Int32, id: Int?) {
        lock.lock(); defer { lock.unlock() }
        if entries.isEmpty { takeSignals() }
        let fd = make()
        guard fd >= 0 else {
            if entries.isEmpty { releaseSignals() }
            return (fd, nil)
        }
        nextID += 1
        entries[nextID] = Entry(path: path)
        return (fd, nextID)
    }

    /// 登記一個已經存在的檔（測試用；存檔的路徑一律經 `create`）。
    static func register(path: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        if entries.isEmpty { takeSignals() }
        nextID += 1
        entries[nextID] = Entry(path: path)
        return nextID
    }

    static func unregister(_ id: Int) {
        lock.lock(); defer { lock.unlock() }
        guard entries.removeValue(forKey: id) != nil else { return }
        if entries.isEmpty { releaseSignals() }
    }

    /// 刪掉所有登記中的檔（名字上還是普通檔的才刪），回刪了幾個。測試用；訊號處理在鎖裡做同一件事。
    @discardableResult
    static func removeRegistered() -> Int {
        lock.lock(); defer { lock.unlock() }
        return removeRegisteredLocked()
    }

    /// 目前登記了幾個（測試用）。
    static var count: Int { lock.lock(); defer { lock.unlock() }; return entries.count }

    /// 這一次接管、現在還在忽略的訊號（測試用）。
    static var takenSignals: [Int32] { lock.lock(); defer { lock.unlock() }; return taken }

    /// 已經建立了長駐訊號來源的訊號（測試用）。
    static var signalsWithSources: Set<Int32> { lock.lock(); defer { lock.unlock() }; return Set(sources.keys) }

    /// 呼叫端持有 `lock`。
    private static func removeRegisteredLocked() -> Int {
        var removed = 0
        for e in entries.values {
            var st = stat()
            guard lstat(e.path, &st) == 0, st.st_mode & S_IFMT == S_IFREG else { continue }
            if unlink(e.path) == 0 { removed += 1 }
        }
        return removed
    }

    /// 呼叫端持有 `lock`。
    private static func takeSignals() {
        taken = []
        for sig in signals {
            // 先只讀（`sigaction` 不改任何東西）：原本不是預設處置（被忽略、或有別的處理——含 `SA_SIGINFO` 的）就不碰它
            guard currentDisposition(sig) == .defaultAction else { continue }
            signal(sig, SIG_IGN)
            taken.append(sig)
            if sources[sig] == nil {
                let s = DispatchSource.makeSignalSource(signal: sig, queue: .global())
                s.setEventHandler { handle(sig) }
                s.resume()
                sources[sig] = s
            }
        }
    }

    /// 呼叫端持有 `lock`。只還原處置**仍是我們設的忽略**的訊號：登記期間別人改過它（主機裝了自己的 handler）就不動，
    /// 免得無條件的 `SIG_DFL` 蓋掉別人的 handler（b26 F6）。
    private static func releaseSignals() {
        for sig in taken where currentDisposition(sig) == .ignored { signal(sig, SIG_DFL) }
        taken = []
    }

    /// 刪檔、還原預設處置、再送一次——整段拿著鎖：送出之前主執行緒建不了下一個檔（`create` 要同一把鎖）。
    private static func handle(_ sig: Int32) {
        lock.lock()
        guard shouldTerminate(disposition: currentDisposition(sig), weAreIgnoring: taken.contains(sig)) else {
            lock.unlock()
            return
        }
        _ = removeRegisteredLocked()
        signal(sig, SIG_DFL)
        raise(sig)
        lock.unlock()   // 走不到：預設處置下 raise 結束行程；留著讓鎖的配對在閱讀上完整
    }
}
