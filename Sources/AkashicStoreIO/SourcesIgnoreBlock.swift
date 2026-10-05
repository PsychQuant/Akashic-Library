import Foundation
import Darwin

/// `ensureLayout` 對 store 根目錄 `.gitignore` 的處置：沒有 sources 排除區塊（#66 task 4.3）就加上。
///
/// **讀不懂的內容不覆寫**（#700 b31 W5 MEDIUM 0、1）。先前讀不出來就當成空檔（非 UTF-8、UTF-16、讀取權限不足），整份以「只含區塊」的
/// 內容原子替換——使用者原有的規則（擋 raw 逐字稿的 `*.srt` 之類）全部消失、沒有任何訊息；`.gitignore` 是 symlink 時被換成一般檔。
/// `file add`、`doctor`、`import-zotero`、MCP 的兩個匯入都經 `ensureLayout` 走到這裡。現在：
/// - 標記以**位元組**比對（`# BEGIN akashic sources` 是 ASCII），而且標記之後要有一行排除規則（`sourcesRuleLines`，b33 verify X5 第 2 列：
///   寫到一半中斷的區塊只有標記、沒有規則，先前被當成「已在」而永遠不補）——兩者都在就什麼都不做，不論那個檔是什麼編碼。
/// - 要加區塊時以 `O_APPEND` 在尾端**附加位元組**，原有的位元組一個都不動；檔尾不是 `\n` 先補一個（同 `appendIndexEntry` 的守衛）。
///   檔案不存在時以 `O_EXCL` 新建。
/// - **看與寫之間**（b33 verify X5 第 0 列 MEDIUM）：先看（`inspectSourcesIgnore`，不寫）決定要不要在建立任何東西之前拒絕；真的要寫時
///   開檔、取 `flock(LOCK_EX)`、**在鎖內重讀一次內容**再決定——同時跑的兩個 akashic 程序因此一個寫、另一個看到區塊已在就什麼都不做。
///   先看也在讀內容之前取 `flock(LOCK_SH)`（b34 修正輪）：先看與鎖內重看是同一個判斷，不等鎖的先看會讀到寫了一半的區塊而假拒絕。
///   先前以 device／inode／大小比對代替鎖：只縮小窗口，實測兩個程序同時首跑時會寫出兩份區塊，`O_EXCL` 撞上 `EEXIST`、大小不符也直接
///   報「被換掉或改過」而不重看（假拒絕、假警告）。現在遇到這兩種情形重看一次（至多 `applyAttempts` 次），重看之後區塊在就算成功。
///   寫到一半失敗時只截掉這一次寫進去的位元組（大小還是「原長＋這一次寫的」才截；`ftruncate` 的結果要看），截不回來具名回報。
/// - 讀不到、不是 UTF-8 文字（含 NUL 也算——UTF-16 存的檔）、是 symlink 而指向的內容沒有區塊、symlink 打不開、不是一般檔、有其他硬連結、
///   大到 git 不讀、有標記沒有規則、沒有寫入權限：**不動它**。`file add` 在建立任何東西之前具名拒絕（`SourcesIgnorePolicy.refuse`）；
///   `doctor` 與兩個匯入照常建佈局、改報一則 warning（`.report`；匯入見下）。開檔、取鎖、寫入這一段才發現的原因（寫入失敗、重看之後仍在變），那時佈局已建好。
/// - **匯入是 warning，不是拒絕**（使用者 2026-10-05 裁決 #700 第 1 項）：`import-zotero` 與 MCP 的兩個匯入（含 `dry_run`）本身不寫
///   `sources/`，擋住第三方存檔進版控的防線在 `store-source`——它寫入前以 `git check-ignore` 驗排除，區塊沒加上就拒寫（`assertSourcesExcluded`）。
///   先前匯入也在建立任何東西之前拒絕，等於讓一個讀不懂的 `.gitignore` 擋住一件與它無關的事。警告的文字只有 `warningLines` 一份。
/// - symlink 與硬連結選拒絕、不寫到那個檔：它可能在 store 之外、被別的 repo 共用，替人改 store 之外的檔不是建佈局該做的事。
///   指向的內容已有區塊時照樣什麼都不做，symlink 不動。
extension LibraryStore {

    /// sources 排除區塊的開頭標記。以它判定區塊在不在（即使內文是手工版本、與程式版不同也不改寫——真實 store 的區塊是手工先寫的）。
    internal static let sourcesIgnoreMarker = "# BEGIN akashic sources"

    /// 附加的區塊（結尾一個換行）。拒絕與 doctor 的 warning 原樣印出它，給人自己加。
    public static let sourcesIgnoreBlock = """
    # BEGIN akashic sources — 存檔的來源內容（第三方逐字位元組）
    # 被指涉的內容本身不進 remote（Akashic-Library#66）；指涉紀錄（references:）照常追蹤。
    sources/
    # END akashic sources

    """

    /// 標記之後算數的排除規則（封閉列舉；一行去掉前後的空白、tab 與行尾的 CR 之後逐位元組比對）。程式寫的是 `sources/`；
    /// 手工區塊常見的寫法一併收（git 對這幾種都會排除根目錄的 `sources/` 底下的內容）。不在這裡的寫法（萬用字元的其他形狀、否定規則）
    /// 不算，那時區塊被判成「有標記沒有規則」、交給人看——`storeSource` 寫入前另以 `git check-ignore` 驗排除，未生效即拒寫。
    internal static let sourcesRuleLines: [[UInt8]] =
        ["sources/", "/sources/", "sources", "/sources", "sources/*", "/sources/*", "sources/**", "/sources/**"].map { Array($0.utf8) }

    /// git 不讀的 `.gitignore` 大小：≥ 100 MiB（實測 git 2.55，2026-10-05：104,857,600 bytes 的 `.gitignore` 印
    /// `ignoring excessively large pattern file`、裡面的規則全部不生效；少一個 byte 就照常讀）。區塊加進去也不生效，附加會讓原本生效的
    /// 檔越過這條線、使用者的規則一起失效——所以到這個大小就不讀、不寫（b33 verify X5 第 15 列：先前整檔讀進來沒有上限）。
    internal static let gitignoreSizeLimit = 100 * 1024 * 1024

    /// 看到「被換掉或改過」（`O_EXCL` 撞上別人剛建的檔、檔案在開檔與取鎖之間被換掉）時重看幾次。
    internal static let applyAttempts = 4

    /// 看過 `.gitignore` 之後的狀態（`inspectSourcesIgnore`，不寫任何東西）。
    internal enum SourcesIgnoreState: Equatable {
        /// 標記與規則都在（位元組比對），不用寫。
        case present
        /// 檔案不存在：以 `O_EXCL` 新建。
        case absent
        /// UTF-8 文字、一般檔、可寫、沒有標記：在尾端附加（附加之前在鎖內重看一次）。
        case appendable
        /// 不動它的原因。
        case problem(SourcesIgnoreProblem)
    }

    /// 內容的判讀：`inspectSourcesIgnore` 與附加前在鎖內的重看共用這一份。
    internal enum SourcesIgnoreContent: Equatable {
        case blockPresent
        case markerWithoutRule
        case notUTF8Text
        case needsBlock(needsNewline: Bool)
    }

    private var sourcesIgnorePath: String { root.appendingPathComponent(".gitignore").path }

    /// 看 `.gitignore`：不寫任何東西、不改任何東西。看的當下被換成 symlink（`ELOOP`）時重看。
    internal func inspectSourcesIgnore() -> SourcesIgnoreState {
        for _ in 0..<Self.applyAttempts {
            if let state = inspectSourcesIgnoreOnce() { return state }
        }
        return .problem(.changedWhileChecking)
    }

    /// 回 `nil`＝看的當下被換掉，要重看。
    private func inspectSourcesIgnoreOnce() -> SourcesIgnoreState? {
        let path = sourcesIgnorePath
        var linkStat = stat()
        if lstat(path, &linkStat) != 0 {
            let code = errno
            // root 還不存在（ENOENT）或路徑上有一段不是目錄（ENOTDIR，之後建 root 時具名失敗）：沒有 .gitignore 可看
            return code == ENOENT || code == ENOTDIR ? .absent : .problem(.unreadable(errno: code))
        }
        let isLink = linkStat.st_mode & S_IFMT == S_IFLNK
        // O_NONBLOCK：指向 FIFO 時 open 不會卡住（下面以 fstat 判它不是一般檔）
        let fd = Self.openRetrying(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | (isLink ? 0 : O_NOFOLLOW))
        guard fd >= 0 else {
            let code = errno
            // symlink 打不開：懸空（ENOENT）、迴圈（ELOOP）、指向的檔不可讀（EACCES）——沒有「內容」可言（b33 verify X5 第 22 列）
            if isLink { return .problem(.brokenSymlink(errno: code)) }
            return code == ELOOP ? nil : .problem(.unreadable(errno: code))   // lstat 之後被換成 symlink：重看
        }
        defer { close(fd) }
        var fileStat = stat()
        guard fstat(fd, &fileStat) == 0 else { return .problem(.unreadable(errno: errno)) }
        guard fileStat.st_mode & S_IFMT == S_IFREG else { return .problem(.notRegularFile) }
        if fileStat.st_size >= off_t(Self.gitignoreSizeLimit) { return .problem(.tooLarge) }   // 不讀：git 也不讀
        // 先看也等持鎖的寫入者寫完：這裡的判讀與鎖內重看是同一個判斷，先看讀到寫了一半的區塊（只有標記、或切在多位元組字元中間）
        // 會在建立任何東西之前假拒絕。共享鎖，看的程序之間不互等；fd 關掉即放鎖
        Self.lockShared(fd)
        let bytes: [UInt8]
        switch Self.readAll(fd) {
        case .bytes(let b): bytes = b
        case .tooLarge: return .problem(.tooLarge)
        case .failed(let code): return .problem(.unreadable(errno: code))
        }
        switch Self.judgeSourcesIgnore(bytes) {
        case .blockPresent: return .present
        case .markerWithoutRule: return .problem(.markerWithoutRule)
        case .notUTF8Text: return .problem(isLink ? .symlink : (fileStat.st_nlink > 1 ? .hardLinked : .notUTF8Text))
        case .needsBlock(let needsNewline):
            if isLink { return .problem(.symlink) }
            if fileStat.st_nlink > 1 { return .problem(.hardLinked) }
            if bytes.count + (needsNewline ? 1 : 0) + Self.sourcesIgnoreBlock.utf8.count >= Self.gitignoreSizeLimit { return .problem(.tooLarge) }
            // AT_EACCESS：以有效 uid 判（b33 verify X5 第 18 列：`access` 用實際 uid，setuid／sudo 下與之後的 open 不一致）
            if faccessat(AT_FDCWD, path, W_OK, AT_EACCESS) != 0 { return .problem(.notWritable(errno: errno)) }
            return .appendable
        }
    }

    /// 照 `inspectSourcesIgnore` 的結果寫：新建或附加。回 `nil` 表示區塊已在（本來就在、剛加上、或別的程序剛加上）；回原因表示沒有加上
    /// （`leavesGitignoreUntouched` 說 `.gitignore` 有沒有被這一次動到）。
    internal func applySourcesIgnore(_ state: SourcesIgnoreState) -> SourcesIgnoreProblem? {
        var state = state
        for _ in 0..<Self.applyAttempts {
            switch state {
            case .present:
                return nil
            case .problem(let problem):
                return problem
            case .absent, .appendable:
                switch appendSourcesIgnoreUnderLock(create: state == .absent) {
                case .done: return nil
                case .failed(let problem): return problem
                case .retry: state = inspectSourcesIgnore()
                }
            }
        }
        switch state {
        case .present: return nil
        case .problem(let problem): return problem
        case .absent, .appendable: return .changedWhileChecking
        }
    }

    private enum AppendOutcome { case done, retry, failed(SourcesIgnoreProblem) }

    /// 開檔（新建時 `O_EXCL`）、取 `flock(LOCK_EX)`、確認路徑仍指著這個檔、**在鎖內重讀內容**再決定寫不寫。
    private func appendSourcesIgnoreUnderLock(create: Bool) -> AppendOutcome {
        let path = sourcesIgnorePath
        // 0o666 再經 umask：與先前的原子寫入建出的模式相同。O_RDWR：鎖內要重讀內容（pread）
        let flags = O_RDWR | O_APPEND | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC | (create ? (O_CREAT | O_EXCL) : 0)
        let fd = Self.openRetrying(path, flags, mode: 0o666)
        guard fd >= 0 else {
            let code = errno
            if create && code == EEXIST { return .retry }                   // 別的程序剛建好
            if !create && (code == ENOENT || code == ELOOP) { return .retry }   // 看過之後被刪掉或換成 symlink
            if code == EACCES || code == EPERM || code == EROFS { return .failed(.notWritable(errno: code)) }
            return .failed(.openFailed(errno: code))   // EMFILE 之類：與權限無關，什麼都沒寫（b33 verify X5 第 9／18 列）
        }
        defer { close(fd) }
        Self.lockExclusively(fd)
        var held = stat(), named = stat()
        guard fstat(fd, &held) == 0 else { return .failed(.unreadable(errno: errno)) }
        // 取到鎖時路徑還指著這個檔？（前一個持鎖者新建失敗而刪掉了它、或有人換掉了它）——不然重看
        guard lstat(path, &named) == 0, named.st_dev == held.st_dev, named.st_ino == held.st_ino,
              held.st_mode & S_IFMT == S_IFREG else { return .retry }
        if held.st_size >= off_t(Self.gitignoreSizeLimit) { return .failed(.tooLarge) }
        let bytes: [UInt8]
        switch Self.readAll(fd) {
        case .bytes(let b): bytes = b
        case .tooLarge: return .failed(.tooLarge)
        case .failed(let code): return .failed(.unreadable(errno: code))
        }
        let needsNewline: Bool
        switch Self.judgeSourcesIgnore(bytes) {
        case .blockPresent: return .done   // 別的程序在我們取鎖之前加好了
        case .markerWithoutRule: return .failed(.markerWithoutRule)
        case .notUTF8Text: return .failed(held.st_nlink > 1 ? .hardLinked : .notUTF8Text)
        case .needsBlock(let n): needsNewline = n
        }
        if held.st_nlink > 1 { return .failed(.hardLinked) }
        let payload = (needsNewline ? [UInt8(ascii: "\n")] : []) + Array(Self.sourcesIgnoreBlock.utf8)
        if bytes.count + payload.count >= Self.gitignoreSizeLimit { return .failed(.tooLarge) }
        let base = off_t(bytes.count)
        let (written, writeErrno) = (SourcesIgnoreIO.write ?? Self.writeAll)(fd, payload)
        guard let writeErrno else { return .done }
        // 只收回這一次寫進去的位元組：大小還是「原長＋這一次寫的」才截（b33 verify X5 第 1 列：先前一律截回看的時候的長度，
        // 別的寫入者在這之間附加的位元組會一起被截掉；`ftruncate` 的結果也沒看）
        var now = stat()
        guard fstat(fd, &now) == 0, now.st_size == base + off_t(written) else {
            return .failed(.rollbackFailed(writeErrno: writeErrno, truncateErrno: nil))
        }
        if written > 0, let truncateErrno = (SourcesIgnoreIO.truncate ?? { ftruncate($0, $1) == 0 ? nil : errno })(fd, base) {
            return .failed(.rollbackFailed(writeErrno: writeErrno, truncateErrno: truncateErrno))
        }
        if create && base == 0 { unlink(path) }   // O_EXCL 建的、仍是空的：是這一步自己的檔
        return .failed(.writeFailed(errno: writeErrno))
    }

    /// 內容的判讀（不看檔案的種類與權限）：標記之後有一行排除規則＝區塊在；只有標記＝有標記沒有規則；沒有標記時看是不是 UTF-8 文字。
    internal static func judgeSourcesIgnore(_ bytes: [UInt8]) -> SourcesIgnoreContent {
        let marker = Array(sourcesIgnoreMarker.utf8)
        if let at = firstIndex(of: marker, in: bytes) {
            return hasRuleLine(bytes, from: at + marker.count) ? .blockPresent : .markerWithoutRule
        }
        // NUL 不是文字——沒有 BOM 的 UTF-16 是合法的 UTF-8
        guard !bytes.contains(0), isValidUTF8(bytes) else { return .notUTF8Text }
        return .needsBlock(needsNewline: bytes.last.map { $0 != UInt8(ascii: "\n") } ?? false)
    }

    /// 嚴格的 UTF-8 驗證（過長編碼、代理字元、超出 U+10FFFF 都不收），不複製整份內容。
    internal static func isValidUTF8(_ bytes: [UInt8]) -> Bool {
        var iterator = bytes.makeIterator()
        var parser = Unicode.UTF8.ForwardParser()
        while true {
            switch parser.parseScalar(from: &iterator) {
            case .valid: continue
            case .emptyInput: return true
            case .error: return false
            }
        }
    }

    private static func firstIndex(of needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        return haystack.withUnsafeBytes { h in
            needle.withUnsafeBytes { n -> Int? in
                guard let base = h.baseAddress, let hit = memmem(base, h.count, n.baseAddress, n.count) else { return nil }
                return base.distance(to: UnsafeRawPointer(hit))
            }
        }
    }

    /// `from` 之後（從下一行開始）有沒有一行是 `sourcesRuleLines` 之一。
    private static func hasRuleLine(_ bytes: [UInt8], from start: Int) -> Bool {
        let newline = UInt8(ascii: "\n")
        guard var i = bytes[start...].firstIndex(of: newline) else { return false }
        i += 1
        while i < bytes.count {
            let end = bytes[i...].firstIndex(of: newline) ?? bytes.count
            var lo = i, hi = end
            while lo < hi, bytes[lo] == 0x20 || bytes[lo] == 0x09 { lo += 1 }
            while hi > lo, bytes[hi - 1] == 0x20 || bytes[hi - 1] == 0x09 || bytes[hi - 1] == 0x0D { hi -= 1 }
            if hi - lo <= 12, sourcesRuleLines.contains(where: { $0.elementsEqual(bytes[lo..<hi]) }) { return true }
            i = end + 1
        }
        return false
    }

    private enum ReadOutcome { case bytes([UInt8]), tooLarge, failed(Int32) }

    /// 從頭讀到尾（`pread`，不動檔案位置）；到 `gitignoreSizeLimit` 就停、回 `.tooLarge`。`EINTR` 重試。
    private static func readAll(_ fd: Int32) -> ReadOutcome {
        var bytes: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var offset: off_t = 0
        while true {
            let n = buffer.withUnsafeMutableBytes { pread(fd, $0.baseAddress, $0.count, offset) }
            if n < 0 {
                if errno == EINTR { continue }
                return .failed(errno)
            }
            if n == 0 { return .bytes(bytes) }
            bytes.append(contentsOf: buffer[0..<n])
            offset += off_t(n)
            if bytes.count >= gitignoreSizeLimit { return .tooLarge }
        }
    }

    /// `open`，`EINTR` 重試（b33 verify X5 第 18 列）。
    private static func openRetrying(_ path: String, _ flags: Int32, mode: mode_t = 0) -> Int32 {
        while true {
            let fd = open(path, flags, mode)
            if fd >= 0 || errno != EINTR { return fd }
        }
    }

    /// `flock(LOCK_EX)`：同時跑的 akashic 程序在這裡排隊。檔案系統不支援（`ENOTSUP`／`EOPNOTSUPP`，部分網路掛載）時不鎖、照常往下——
    /// 那時鎖內重看仍會擋掉「別人已經寫好」的那一種，擋不住兩邊同時寫（誠實邊界）。`EINTR` 重試。
    private static func lockExclusively(_ fd: Int32) {
        while flock(fd, LOCK_EX) != 0 && errno == EINTR {}
    }

    /// `flock(LOCK_SH)`：先看（`inspectSourcesIgnoreOnce`）在讀內容之前取，等持 `LOCK_EX` 的寫入者寫完。不支援時同上、照常往下。
    private static func lockShared(_ fd: Int32) {
        while flock(fd, LOCK_SH) != 0 && errno == EINTR {}
    }

    /// `file add` 的拒絕（`.refuse`；`ensureLayout` 的兩個擲出點共用這一個建構點）。
    internal static func sourcesIgnoreRefusal(_ problem: SourcesIgnoreProblem, layoutWritten: Bool) -> StoreIOError {
        StoreIOError.sourcesIgnoreNotWritten(problem, layoutWritten: layoutWritten)   // display-safe-exempt: problem 是封閉列舉 SourcesIgnoreProblem（描述端只讀它的固定句與 errno 說明）；layoutWritten 是 Bool
    }

    /// 寫完整段；回寫進去的位元組數與 errno（成功時 `nil`）。`EINTR` 重試。
    private static func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> (written: Int, errno: Int32?) {
        var offset = 0
        while offset < bytes.count {
            let n = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if n < 0 {
                if errno == EINTR { continue }
                return (offset, errno)
            }
            offset += n
        }
        return (offset, nil)
    }
}

/// 測試用的注入點：附加的寫入與失敗後的截斷（`withValue` 的範圍內有效；`nil`＝真的 `write`／`ftruncate`）。
/// 寫入失敗與截斷失敗在真的檔案系統上造不出來（RLIMIT_FSIZE 在 macOS 對附加不生效，b33 verify X5 DA 實測）。
internal enum SourcesIgnoreIO {
    /// 回寫進去的位元組數與 errno（成功時 `nil`）。
    @TaskLocal static var write: (@Sendable (Int32, [UInt8]) -> (written: Int, errno: Int32?))?
    /// 回 errno（成功時 `nil`）。
    @TaskLocal static var truncate: (@Sendable (Int32, off_t) -> Int32?)?
}

/// `ensureLayout` 遇到 `.gitignore` 的問題時怎麼做（#700）。
///
/// 呼叫端是封閉列舉（2026-10-05 的 `ensureLayout` 呼叫者全部在此）：`.refuse`＝`file add`；`.report`＝`doctor`、CLI `import-zotero`、
/// MCP `akashic_import_zotero`、`akashic_import_wos`（含 `dry_run`）。CLI `import-wos` 開既有 store（`openStore`），不經 `ensureLayout`。
public enum SourcesIgnorePolicy: Sendable {
    /// `file add`：擲出 `StoreIOError.sourcesIgnoreNotWritten`。看得出的原因在建立任何東西之前擲；開檔、取鎖、寫入時才發現的原因在
    /// 佈局建好之後擲（訊息說是哪一種）。
    case refuse
    /// `doctor` 與兩個匯入：照常建佈局、`.gitignore` 不動，原因由 `ensureLayout` 的回傳值交給呼叫端報（`SourcesIgnoreProblem.warningLines`）。
    /// 匯入不寫 `sources/`，擋第三方存檔進版控的防線在 `store-source`（使用者 2026-10-05 裁決 #700 第 1 項）。
    case report
}

/// `.gitignore` 沒有加上 sources 排除區塊的原因（#700）。封閉列舉；除了 `rollbackFailed`，每一格都表示這一次沒有改寫 `.gitignore`。
public enum SourcesIgnoreProblem: Equatable, Sendable {
    /// 讀不到（權限、I/O 錯誤）。
    case unreadable(errno: Int32)
    /// 不是 UTF-8 文字（含非 UTF-8 位元組或 NUL：Latin-1、UTF-16 存的檔）。
    case notUTF8Text
    /// 是 symlink，指向的檔讀得到、沒有區塊。
    case symlink
    /// 是 symlink，指向的檔打不開（懸空、迴圈、不可讀）。
    case brokenSymlink(errno: Int32)
    /// 不是一般檔（目錄、FIFO…，或 symlink 指向它們）。
    case notRegularFile
    /// 一般檔，但有其他硬連結（`st_nlink > 1`）：附加會改到別處共用的同一個檔。
    case hardLinked
    /// 大到 git 不讀（≥ 100 MiB），或附加之後會越過那條線。
    case tooLarge
    /// 有 `# BEGIN akashic sources` 標記，但標記之後沒有一行排除規則（寫到一半中斷，或手改過）。
    case markerWithoutRule
    /// 沒有寫入權限。
    case notWritable(errno: Int32)
    /// 打不開來寫，原因與權限無關（`EMFILE` 之類）；什麼都沒寫。
    case openFailed(errno: Int32)
    /// 看與寫之間一直在變（重看 `LibraryStore.applyAttempts` 次之後）。
    case changedWhileChecking
    /// 寫入失敗；這一次寫進去的部分已截回原長（新建的、仍是空的已刪掉）。
    case writeFailed(errno: Int32)
    /// 寫入失敗，而且沒能截回原長（`ftruncate` 失敗，或寫入期間檔案被別的程序改過——截了會刪掉別人的位元組）。`.gitignore` 尾端可能留著半段區塊。
    case rollbackFailed(writeErrno: Int32, truncateErrno: Int32?)

    /// 這一次有沒有動到 `.gitignore`：只有 `rollbackFailed` 是 false。
    public var leavesGitignoreUntouched: Bool {
        if case .rollbackFailed = self { return false }
        return true
    }

    /// 一句話的原因：固定字串、errno 數字與系統的固定英文說明，不含使用者資料。
    public var reason: String {
        switch self {
        case .unreadable(let code): return "讀不到（\(LibraryStore.errnoText(code))）"   // display-safe-exempt: LibraryStore.errnoText 只回 errno 數字與系統的固定英文說明（code 是 Int32）
        case .notUTF8Text: return "不是 UTF-8 文字（含非 UTF-8 位元組或 NUL，例如以 Latin-1 或 UTF-16 存的檔）——讀不懂的內容不覆寫也不附加"
        case .symlink: return "是 symlink，指向的內容沒有 sources 標記區塊——不經 symlink 寫入（指向的檔可能在 store 之外、被別處共用）"
        case .brokenSymlink(let code): return "是 symlink，指向的檔打不開（\(LibraryStore.errnoText(code))：懸空、迴圈或不可讀）"   // display-safe-exempt: LibraryStore.errnoText 只回 errno 數字與系統的固定英文說明（code 是 Int32）
        case .notRegularFile: return "不是一般檔（目錄、FIFO 之類，或 symlink 指向它們）"
        case .hardLinked: return "有其他硬連結——附加會改到別處共用的同一個檔（與 symlink 同一個理由）"
        case .tooLarge: return "大到 git 不讀（git 不讀 100 MiB 以上的 .gitignore），或附加之後會越過那條線——加了也不生效"
        case .markerWithoutRule: return "有 sources 標記，但標記之後沒有排除 sources/ 的那一行（區塊寫到一半中斷，或被改過）——不改寫既有的區塊"
        case .notWritable(let code): return "沒有寫入權限（\(LibraryStore.errnoText(code))）"   // display-safe-exempt: LibraryStore.errnoText 只回 errno 數字與系統的固定英文說明（code 是 Int32）
        case .openFailed(let code): return "打不開來寫（\(LibraryStore.errnoText(code))），什麼都沒寫"   // display-safe-exempt: LibraryStore.errnoText 只回 errno 數字與系統的固定英文說明（code 是 Int32）
        case .changedWhileChecking: return "看與寫之間一直被換掉或改動（重看了 \(LibraryStore.applyAttempts) 次）"   // display-safe-exempt: LibraryStore.applyAttempts 是 Int 常數
        case .writeFailed(let code): return "寫入失敗（\(LibraryStore.errnoText(code))）；這一次寫進去的部分已截回原長"   // display-safe-exempt: LibraryStore.errnoText 只回 errno 數字與系統的固定英文說明（code 是 Int32）
        case let .rollbackFailed(w, t):
            return "寫入失敗（\(LibraryStore.errnoText(w))），而且沒能截回原長（"   // display-safe-exempt: LibraryStore.errnoText 只回 errno 數字與系統的固定英文說明（w、t 是 Int32）
                + (t.map { "ftruncate：" + LibraryStore.errnoText($0) } ?? "寫入期間檔案被別的程序改過，截了會刪掉別人的位元組")
                + "）——.gitignore 尾端可能留著半段區塊"
        }
    }

    /// 一則 warning（`.report` 的呼叫端報它）：一行說明加上要自己加的那段（每行縮排四格）。`doctor` 印到 stdout、`import-zotero` 印到
    /// stderr、MCP 的兩個匯入以換行接起來放進回應的 `gitignoreWarning`——三處同一份文字（#700 b35）。`actor` 是程式字面（命令名），
    /// `note` 是呼叫端的固定句，接在原因之後。只含固定句、errno 數字與系統的固定英文說明，不含使用者資料。
    public func warningLines(by actor: String, note: String = "") -> [String] {
        ["⚠ .gitignore 沒有 sources 排除區塊，\(actor) " + (leavesGitignoreUntouched ? "沒有改寫它" : "寫到一半、沒能收回")   // display-safe-exempt: actor 是呼叫端的程式字面（命令名）
            + "：\(reason)。\(note)\(remedy)："]   // display-safe-exempt: reason、remedy 是本型別的固定句與 errno 說明；note 是呼叫端的固定句
            + LibraryStore.sourcesIgnoreBlock.split(separator: "\n").map { "    \($0)" }   // display-safe-exempt: 取自常數 LibraryStore.sourcesIgnoreBlock
    }

    /// 匯入的 warning 接在原因之後的那一句（CLI `import-zotero` 與 MCP 的兩個匯入同一句）。
    public static let importContinuedNote =
        "匯入照常完成（匯入不寫 sources/）；store 在 git 工作樹裡時，sources/ 沒被排除之前 store-source 拒絕寫入。"

    /// 處置。
    public var remedy: String {
        switch self {
        case .unreadable: return "修好讀取權限後重跑，或自己在 .gitignore 加上下面這段"
        case .notUTF8Text: return "把它轉存成 UTF-8 後重跑，或自己在 .gitignore 加上下面這段"
        case .symlink: return "在它指向的檔加上下面這段（或把 symlink 換成一般檔）後重跑"
        case .brokenSymlink: return "把 symlink 換成一般檔（或修好它指向的檔）後重跑"
        case .notRegularFile: return "移走它、換成一般檔後重跑"
        case .hardLinked: return "確認別處共用的那個檔也該有這段之後自己加上下面這段，或把 .gitignore 換成獨立的一般檔後重跑"
        case .tooLarge: return "把 .gitignore 縮到 100 MiB 以下，並自己加上下面這段"
        case .markerWithoutRule: return "在標記區塊裡補上 sources/ 一行（或刪掉殘缺的區塊、換成下面這段）後重跑"
        case .notWritable: return "給它寫入權限後重跑，或自己在 .gitignore 加上下面這段"
        case .openFailed, .changedWhileChecking, .writeFailed: return "重跑；仍不行就自己在 .gitignore 加上下面這段"
        case .rollbackFailed: return "打開 .gitignore 看尾端，刪掉不完整的那段後重跑，或換成下面這段"
        }
    }
}
