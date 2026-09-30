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

    /// 把暫存檔放到位址上的系統呼叫（#703 R1 verify 第 5、9、12、33 則；R2 verify 第 1 則）。測試接縫：換掉其中一個，模擬
    /// 不支援 `RENAME_EXCL` 的檔案系統（2026-09-30 在磁碟映像上實測：exFAT 與 FAT32 的 `renamex_np(RENAME_EXCL)` 與 `link(2)`
    /// 都回 `ENOTSUP`），或在第三條路的建立／複製上注入失敗。
    internal struct BlobPlacement {
        /// 回 0 或 errno。
        var renameExclusive: @Sendable (_ from: String, _ to: String) -> Int32
        /// 回 0 或 errno。
        var hardLink: @Sendable (_ from: String, _ to: String) -> Int32
        /// 第三條路：以 `O_CREAT | O_EXCL` 建立目的檔，回 descriptor（≥ 0）或 `-errno`。位址上已有任何東西（含懸空 symlink）都是
        /// `EEXIST`——這一步本身不可能取代別人的檔。
        var createExclusive: @Sendable (_ path: String) -> Int32
        /// 第三條路複製時把一塊寫到目的檔：回 0 或 errno。
        var writeChunk: @Sendable (_ fd: Int32, _ chunk: Data) -> Int32
        /// 把一個已寫完的檔同步到裝置：回 0 或 errno（#703 R2 verify 第 21 則）。暫存檔在放上位址之前、第三條路的目的檔在驗證之前各呼叫一次；
        /// 預設是 `LibraryStore.syncFile`。測試接縫：驗「放上位址之前真的同步了」與「同步失敗就不放」。
        var sync: @Sendable (_ fd: Int32) -> Int32 = { LibraryStore.syncFile($0) }
        static let system = BlobPlacement(
            renameExclusive: { renamex_np($0, $1, UInt32(RENAME_EXCL)) == 0 ? 0 : errno },
            hardLink: { Darwin.link($0, $1) == 0 ? 0 : errno },
            createExclusive: { path in
                let fd = Darwin.open(path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
                return fd >= 0 ? fd : -errno
            },
            writeChunk: { fd, chunk in
                chunk.withUnsafeBytes { raw -> Int32 in
                    var offset = 0
                    while offset < raw.count {
                        let n = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                        if n < 0 {
                            if errno == EINTR { continue }
                            return errno
                        }
                        offset += n
                    }
                    return 0
                }
            })
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

    /// 把一個已寫完的檔的內容推到儲存裝置（#703 R2 verify 第 21 則）：先 `F_FULLFSYNC`（連裝置的寫入快取一起清——`fsync(2)` 在 macOS
    /// 不保證這一點，斷電時被撕裂的 blob 會以合法的位址留下），檔案系統不支援時退到 `fsync(2)`。回 0 或 errno；`fsync` 也回「不支援」
    /// 時當成盡力而為、回 0（那個檔案系統沒有可用的同步手段，不是 I/O 錯誤）。2026-10-01 本機實測（APFS、200 KB 的檔）：
    /// `F_FULLFSYNC` 平均 4.3 ms、`fsync` 0.1 ms——`copy-zotero-attachments` 一趟 2,817 個附件約多 12 秒。
    internal static func syncFile(_ fd: Int32) -> Int32 {
        if fcntl(fd, F_FULLFSYNC) == 0 { return 0 }
        if fsync(fd) == 0 { return 0 }
        let code = errno
        return code == ENOTSUP || code == EOPNOTSUPP || code == EINVAL ? 0 : code
    }

    /// 暫存檔放上位址（#703 R1；R2 verify 第 1 則）。三條路依序，每一條都**不覆寫**位址上已有的東西：
    ///
    /// 1. `renamex_np(RENAME_EXCL)`——原子、排他。`EEXIST`＝有人先放了。
    /// 2. 檔案系統不支援 → `link(2)`＋刪掉暫存名——同樣排他（目的地在就 `EEXIST`）。
    /// 3. 也不支援 → 以 `O_CREAT | O_EXCL` 建立目的檔（`EEXIST`＝有人先放了），從暫存檔逐塊複製、同步到裝置、從同一個 descriptor
    ///    讀回來重算 digest 與大小；任何一步失敗就刪掉**這一次建立的那個檔**（`O_EXCL` 成功才知道它是自己的；刪之前再以 `lstat` 比
    ///    裝置與 inode，名字被別人換掉了就不刪）。R1 的第三條是 `lstat` 確認不在、再一般 `rename(2)`——兩步之間別人放進來的檔會被
    ///    取代，違反「不覆寫」（R2 verify 第 1 則），已拿掉。
    ///
    /// **第三條的誠實邊界**：複製期間，未完成的檔在**最終的檔名**下看得到。同時另一個存檔讀到它，`writeBlob` 的佔用判斷看到大小
    /// 不符會具名拒絕、不信任它；`checkStoredBlob` 同樣判不符。行程在複製途中被殺掉（`SIGKILL`、斷電）時那個不完整的檔留在位址上——
    /// `SIGINT`／`SIGTERM` 由 `InFlightSourceFiles` 清掉，前兩種清不到：之後的 `store-source` 以大小不符具名拒絕，doctor 在 index
    /// 有它的大小時報大小不符、沒有條目時報成孤兒 blob。exFAT／FAT32 上只有這一條可用（實測）。
    ///
    /// 三條都走不通時具名擲出，說出三個 errno。
    internal func placeTemporaryBlob(_ tmp: String, at dest: String, digest: String, bytes: Int,
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
        let prefix = "這個檔案系統不支援排他改名與 hard link（\(Self.errnoText(excl))；\(Self.errnoText(ln))），"
        // 建立與登記在同一把鎖裡（`InFlightSourceFiles.create`）：Ctrl-C 在建立之後、登記之前送到也清得掉
        let (fd, flight) = InFlightSourceFiles.create(path: dest) { placement.createExclusive(dest) }
        defer { if let flight { InFlightSourceFiles.unregister(flight) } }
        if fd == -EEXIST { return .alreadyThere }
        guard fd >= 0 else { throw fail(prefix + "排他建立目的檔也失敗（\(Self.errnoText(-fd))）") }
        var st = stat()
        guard flight != nil, fstat(fd, &st) == 0 else {
            let code = errno
            close(fd)
            unlink(dest)   // 剛以 O_EXCL 建立、還沒寫任何東西；fstat 失敗時比不了 inode，只能照名字刪
            throw fail(prefix + "建立的目的檔 fstat 失敗（\(Self.errnoText(code))）")
        }
        let ours = (dev: st.st_dev, ino: st.st_ino)
        func removeOurs(_ why: String) -> StoreIOError {
            close(fd)
            Self.unlinkIfSameFile(dest, device: ours.dev, inode: ours.ino)
            return fail(prefix + why)
        }
        // 從暫存檔逐塊複製（經 `pump`：每塊讀完即釋放）
        let src = Darwin.open(tmp, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard src >= 0 else { throw removeOurs("讀不到暫存檔（\(Self.errnoText(errno))）") }
        let srcHandle = FileHandle(fileDescriptor: src, closeOnDealloc: true)
        defer { try? srcHandle.close() }
        var chunks = HandleChunks(handle: srcHandle)
        var writeError: Int32 = 0
        do {
            _ = try Self.pump(&chunks, limit: .max) { chunk in
                guard writeError == 0 else { return }
                writeError = placement.writeChunk(fd, chunk)
            }
        } catch {
            throw removeOurs("複製到目的檔時讀暫存檔失敗")
        }
        guard writeError == 0 else { throw removeOurs("複製到目的檔時寫入失敗（\(Self.errnoText(writeError))）") }
        let synced = placement.sync(fd)
        guard synced == 0 else { throw removeOurs("目的檔同步到裝置失敗（\(Self.errnoText(synced))）") }
        // 讀回來驗：從同一個 descriptor（不經路徑，名字被換掉也讀的是自己寫的那一份）
        let back = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        guard let streamed = try? Self.contentDigest(reading: back, limit: .max),
              case .digest(let actual, let n) = streamed else {
            throw removeOurs("讀回目的檔失敗")
        }
        guard actual == digest, n == bytes else {
            throw removeOurs("讀回目的檔的內容與暫存檔不同（\(n) bytes、\(actual)）——不留在位址上")   // display-safe-exempt: n 是 Int；actual 是本函式算的 SHA-256 十六進位
        }
        close(fd)
        // 名字還是不是自己建立的那個檔：複製期間被別人換掉了（它取代的是我們的檔，不是我們取代它），位址上是別人的東西——交給呼叫端判
        var now = stat()
        guard lstat(dest, &now) == 0, now.st_dev == ours.dev, now.st_ino == ours.ino else { return .alreadyThere }
        unlink(tmp)   // 放上了；暫存名刪掉（失敗的話 doctor 報成殘留）
        return .placed
    }

    /// 路徑上的檔還是 (device, inode) 那一個才刪（#703 R2）：刪的只能是這一次建立的檔，名字被別人換掉就留著。
    /// `lstat` 與 `unlink` 之間仍有一個系統呼叫那麼長的窗——POSIX 沒有「以 descriptor 刪名字」的呼叫。
    internal static func unlinkIfSameFile(_ path: String, device: dev_t, inode: ino_t) {
        var st = stat()
        guard lstat(path, &st) == 0, st.st_dev == device, st.st_ino == inode else { return }
        unlink(path)
    }
}

/// 存檔進行中、還沒放上位址（或第三條路正在複製）的檔（#703 R2 verify 第 27 則）：`SIGINT`／`SIGTERM`／`SIGHUP` 送來時刪掉它們再照原本的
/// 方式結束行程。R1 之前只有 `defer` 清理，而訊號結束行程時 `defer` 不跑——實測 Ctrl-C 留下 118 MB、SIGTERM 留下 243 MB 的暫存檔。
///
/// **只在有檔登記時接管訊號**：第一個登記時把這三個訊號中「原本是預設處置」的改成忽略、由 dispatch 的訊號來源接手；最後一個撤銷時還原。
/// 原本就被忽略的（`nohup` 的 SIGHUP）或有別的處理的不接管——那個訊號本來就不該由我們結束行程，也就不該刪檔。接手的處理：刪掉登記的檔
/// （`lstat` 比過裝置與 inode 才刪，名字被換掉就不動）、把處置改回預設、再對自己送一次同一個訊號——行程照樣被那個訊號結束，只是晚一點。
///
/// **接管在建立檔案之前**（`create`）：訊號在「檔案已建立、還沒登記」的那一瞬間送到時，先前的寫法以預設處置結束行程、留下檔案（第一版的
/// 測試實際撞到）。現在「接管 → 建立 → 登記」在同一把鎖裡，處理訊號的那一邊要等它做完才刪；刪完、送出訊號之前也一直拿著鎖，下一個檔建不起來。
/// 登記期間沒有 spawn 任何子行程（排除驗證的 `git` 在建立暫存檔之前），所以「忽略」不會被子行程繼承。
///
/// **清不到的**：`SIGKILL`、斷電、`abort()`——那些由 doctor 的 `strayTemporaryFiles` 報（只報不刪）。
internal enum InFlightSourceFiles {
    private struct Entry { let path: String; let device: dev_t; let inode: ino_t }
    private static let lock = NSLock()
    private static var entries: [Int: Entry] = [:]
    private static var nextID = 0
    /// 這一次接管的訊號（原本是預設處置的那幾個）——還原時只動它們。
    private static var taken: [Int32] = []
    /// 各訊號在最近一次接管時是不是預設處置。訊號來源只為接管過的訊號建立；它送來的事件只可能發生在我們忽略它的期間
    /// （預設處置時核心直接結束行程，事件來不及送到），所以即使事件送到時登記已經清空、處置已經還原，那一下 Ctrl-C 仍要結束行程
    /// ——不然它就被吞掉了。之後某次接管時發現處置已被別人改掉（不是預設），這一格變 false，之後的事件不理。
    private static var defaultAtLastTake: [Int32: Bool] = [:]
    private static var sources: [Int32: DispatchSourceSignal] = [:]
    static let signals: [Int32] = [SIGINT, SIGTERM, SIGHUP]

    /// 接管訊號、建立檔案（`make` 回 descriptor 或負值）、登記它的裝置與 inode——三步在同一把鎖裡。建立失敗時不登記、回原值；
    /// 登記的 id 由 `unregister` 撤銷。
    static func create(path: String, _ make: () -> Int32) -> (fd: Int32, id: Int?) {
        lock.lock(); defer { lock.unlock() }
        if entries.isEmpty { takeSignals() }
        let fd = make()
        var st = stat()
        guard fd >= 0, fstat(fd, &st) == 0 else {
            if entries.isEmpty { releaseSignals() }
            return (fd, nil)
        }
        nextID += 1
        entries[nextID] = Entry(path: path, device: st.st_dev, inode: st.st_ino)
        return (fd, nextID)
    }

    /// 登記一個已經存在的檔（測試用；存檔的路徑一律經 `create`）。
    static func register(path: String, device: dev_t, inode: ino_t) -> Int {
        lock.lock(); defer { lock.unlock() }
        if entries.isEmpty { takeSignals() }
        nextID += 1
        entries[nextID] = Entry(path: path, device: device, inode: inode)
        return nextID
    }

    static func unregister(_ id: Int) {
        lock.lock(); defer { lock.unlock() }
        guard entries.removeValue(forKey: id) != nil else { return }
        if entries.isEmpty { releaseSignals() }
    }

    /// 刪掉所有登記中的檔（仍是登記時那個 inode 的才刪），回刪了幾個。測試用；訊號處理在鎖裡做同一件事。
    @discardableResult
    static func removeRegistered() -> Int {
        lock.lock(); defer { lock.unlock() }
        return removeRegisteredLocked()
    }

    /// 目前登記了幾個（測試用）。
    static var count: Int { lock.lock(); defer { lock.unlock() }; return entries.count }

    /// 呼叫端持有 `lock`。
    private static func removeRegisteredLocked() -> Int {
        var removed = 0
        for e in entries.values {
            var st = stat()
            guard lstat(e.path, &st) == 0, st.st_dev == e.device, st.st_ino == e.inode else { continue }
            if unlink(e.path) == 0 { removed += 1 }
        }
        return removed
    }

    /// 呼叫端持有 `lock`。
    private static func takeSignals() {
        taken = []
        for sig in signals {
            // 先只讀（`sigaction` 不改任何東西）：原本不是預設處置（被忽略、或有別的處理——含 `SA_SIGINFO` 的）就不碰它
            var current = sigaction()
            guard sigaction(sig, nil, &current) == 0, unsafeBitCast(current.__sigaction_u, to: Int.self) == 0 else {
                defaultAtLastTake[sig] = false
                continue
            }
            signal(sig, SIG_IGN)
            taken.append(sig)
            defaultAtLastTake[sig] = true
            if sources[sig] == nil {
                let s = DispatchSource.makeSignalSource(signal: sig, queue: .global())
                s.setEventHandler { handle(sig) }
                s.resume()
                sources[sig] = s
            }
        }
    }

    /// 呼叫端持有 `lock`。
    private static func releaseSignals() {
        for sig in taken { signal(sig, SIG_DFL) }
        taken = []
    }

    /// 刪檔、還原預設處置、再送一次——整段拿著鎖：送出之前主執行緒建不了下一個檔（`create` 要同一把鎖）。
    private static func handle(_ sig: Int32) {
        lock.lock()
        guard defaultAtLastTake[sig] ?? false else {
            lock.unlock()
            return
        }
        _ = removeRegisteredLocked()
        signal(sig, SIG_DFL)
        raise(sig)
        lock.unlock()   // 走不到：預設處置下 raise 結束行程；留著讓鎖的配對在閱讀上完整
    }
}
