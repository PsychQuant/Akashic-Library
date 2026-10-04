import Foundation
import Darwin

/// `ensureLayout` 對 store 根目錄 `.gitignore` 的處置：沒有 sources 排除區塊（#66 task 4.3）就加上。
///
/// **讀不懂的內容不覆寫**（#700 b31 W5 MEDIUM 0、1）。先前讀不出來就當成空檔（非 UTF-8、UTF-16、讀取權限不足），整份以「只含區塊」的
/// 內容原子替換——使用者原有的規則（擋 raw 逐字稿的 `*.srt` 之類）全部消失、沒有任何訊息；`.gitignore` 是 symlink 時被換成一般檔。
/// `file add`、`doctor`、`import-zotero`、MCP 的兩個匯入都經 `ensureLayout` 走到這裡。現在：
/// - 標記以**位元組**比對（`# BEGIN akashic sources` 是 ASCII）——已在就什麼都不做，不論那個檔是什麼編碼。
/// - 要加區塊時以 `O_APPEND` 在尾端**附加位元組**，原有的位元組一個都不動；檔尾不是 `\n` 先補一個（同 `appendIndexEntry` 的守衛）。
///   寫到一半失敗就截回原長。檔案不存在時以 `O_EXCL` 新建。
/// - 讀不到、不是 UTF-8 文字（含 NUL 也算——UTF-16 存的檔）、是 symlink 而指向的內容沒有區塊、不是一般檔、沒有寫入權限：**不動它**。
///   寫入類命令在建立任何東西之前具名拒絕（`SourcesIgnorePolicy.refuse`）；`doctor` 照常建佈局、改報一則 warning（`.report`）。
/// - symlink 選拒絕、不寫到它指向的檔：那個檔可能在 store 之外、被別的 repo 共用，替人改 store 之外的檔不是建佈局該做的事。
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

    /// 看過 `.gitignore` 之後的狀態（`inspectSourcesIgnore`，不寫任何東西）。
    internal enum SourcesIgnoreState: Equatable {
        /// 標記已在（位元組比對），不用寫。
        case present
        /// 檔案不存在：以 `O_EXCL` 新建。
        case absent
        /// UTF-8 文字、一般檔、可寫、沒有標記：在尾端附加。`device`／`inode`／`size` 是看的時候那一份——附加之前再比一次，不同就不寫。
        case appendable(device: dev_t, inode: ino_t, size: off_t, needsNewline: Bool)
        /// 不動它的原因。
        case problem(SourcesIgnoreProblem)
    }

    private var sourcesIgnorePath: String { root.appendingPathComponent(".gitignore").path }

    /// 看 `.gitignore`：不寫任何東西、不改任何東西。
    internal func inspectSourcesIgnore() -> SourcesIgnoreState {
        let path = sourcesIgnorePath
        var linkStat = stat()
        if lstat(path, &linkStat) != 0 {
            let code = errno
            // root 還不存在（ENOENT）或路徑上有一段不是目錄（ENOTDIR，之後建 root 時具名失敗）：沒有 .gitignore 可看
            return code == ENOENT || code == ENOTDIR ? .absent : .problem(.unreadable(errno: code))
        }
        let isLink = linkStat.st_mode & S_IFMT == S_IFLNK
        // O_NONBLOCK：指向 FIFO 時 open 不會卡住（下面以 fstat 判它不是一般檔）
        let fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | (isLink ? 0 : O_NOFOLLOW))
        guard fd >= 0 else {
            let code = errno
            // 懸空的 symlink（ENOENT），或 lstat 之後被換成 symlink（ELOOP）
            return isLink || code == ELOOP ? .problem(.symlink) : .problem(.unreadable(errno: code))
        }
        defer { close(fd) }
        var fileStat = stat()
        guard fstat(fd, &fileStat) == 0 else { return .problem(.unreadable(errno: errno)) }
        guard fileStat.st_mode & S_IFMT == S_IFREG else { return .problem(isLink ? .symlink : .notRegularFile) }
        var bytes: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n < 0 {
                if errno == EINTR { continue }
                return .problem(.unreadable(errno: errno))
            }
            if n == 0 { break }
            bytes.append(contentsOf: buffer[0..<n])
        }
        if Data(bytes).range(of: Data(Self.sourcesIgnoreMarker.utf8)) != nil { return .present }
        if isLink { return .problem(.symlink) }
        // UTF-8 驗證：解碼再編碼回來要逐位元組相同（無效序列會被換成 U+FFFD）；NUL 不是文字——沒有 BOM 的 UTF-16 是合法的 UTF-8
        guard !bytes.contains(0), Array(String(decoding: bytes, as: UTF8.self).utf8) == bytes else {
            return .problem(.notUTF8Text)
        }
        if access(path, W_OK) != 0 { return .problem(.notWritable(errno: errno)) }
        return .appendable(device: fileStat.st_dev, inode: fileStat.st_ino, size: off_t(bytes.count),
                           needsNewline: bytes.last.map { $0 != UInt8(ascii: "\n") } ?? false)
    }

    /// 照 `inspectSourcesIgnore` 的結果寫：新建或附加。回 `nil` 表示區塊已在（本來就在或剛加上）；回原因表示 `.gitignore` 沒有改寫
    /// （新建到一半失敗時刪掉自己建的檔、附加到一半失敗時截回原長）。
    internal func applySourcesIgnore(_ state: SourcesIgnoreState) -> SourcesIgnoreProblem? {
        let path = sourcesIgnorePath
        let block = Array(Self.sourcesIgnoreBlock.utf8)
        switch state {
        case .present:
            return nil
        case .problem(let problem):
            return problem
        case .absent:
            // 0o666 再經 umask：與先前的原子寫入建出的模式相同
            let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o666)
            guard fd >= 0 else {
                let code = errno
                return code == EEXIST ? .changedWhileChecking : .writeFailed(errno: code)
            }
            defer { close(fd) }
            if let code = Self.writeAll(fd, block) {
                unlink(path)   // O_EXCL 建的：是這一步自己的檔
                return .writeFailed(errno: code)
            }
            return nil
        case let .appendable(device, inode, size, needsNewline):
            let fd = open(path, O_WRONLY | O_APPEND | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard fd >= 0 else {
                let code = errno
                if code == ELOOP { return .symlink }
                if code == ENOENT { return .changedWhileChecking }
                return .notWritable(errno: code)
            }
            defer { close(fd) }
            var now = stat()
            guard fstat(fd, &now) == 0, now.st_dev == device, now.st_ino == inode, now.st_size == size else {
                return .changedWhileChecking
            }
            if let code = Self.writeAll(fd, (needsNewline ? [UInt8(ascii: "\n")] : []) + block) {
                _ = ftruncate(fd, size)   // 截回原長：原有的位元組沒有動過，只拿掉這一次寫了一半的尾巴
                return .writeFailed(errno: code)
            }
            return nil
        }
    }

    /// 寫入類命令的拒絕（`ensureLayout` 的兩個擲出點共用這一個建構點）。
    internal static func sourcesIgnoreRefusal(_ problem: SourcesIgnoreProblem, layoutWritten: Bool) -> StoreIOError {
        StoreIOError.sourcesIgnoreNotWritten(problem, layoutWritten: layoutWritten)   // display-safe-exempt: problem 是封閉列舉 SourcesIgnoreProblem（描述端只讀它的固定句與 errno 說明）；layoutWritten 是 Bool
    }

    /// 寫完整段；回 errno 或 `nil`。`EINTR` 重試。
    private static func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Int32? {
        var offset = 0
        while offset < bytes.count {
            let n = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if n < 0 {
                if errno == EINTR { continue }
                return errno
            }
            offset += n
        }
        return nil
    }
}

/// `ensureLayout` 遇到 `.gitignore` 的問題時怎麼做（#700）。
public enum SourcesIgnorePolicy: Sendable {
    /// 寫入類命令（`file add`、`import-zotero`、MCP 的兩個匯入）：在建立任何東西之前擲出 `StoreIOError.sourcesIgnoreNotWritten`。
    case refuse
    /// 診斷面（`doctor`）：照常建佈局、`.gitignore` 不動，原因由 `ensureLayout` 的回傳值交給呼叫端報。
    case report
}

/// `.gitignore` 沒有加上 sources 排除區塊的原因（#700）。封閉列舉；每一格都表示 `.gitignore` 沒有改寫。
public enum SourcesIgnoreProblem: Equatable, Sendable {
    /// 讀不到（權限、I/O 錯誤）。
    case unreadable(errno: Int32)
    /// 不是 UTF-8 文字（含非 UTF-8 位元組或 NUL：Latin-1、UTF-16 存的檔）。
    case notUTF8Text
    /// 是 symlink，指向的內容沒有區塊（或指向的檔不存在、不是一般檔）。
    case symlink
    /// 不是一般檔（目錄、FIFO…）。
    case notRegularFile
    /// 沒有寫入權限。
    case notWritable(errno: Int32)
    /// 看過之後、寫入之前被換掉或改過。
    case changedWhileChecking
    /// 寫入失敗（已截回原長；新建的已刪掉）。
    case writeFailed(errno: Int32)

    /// 一句話的原因：固定字串、errno 數字與系統的固定英文說明，不含使用者資料。
    public var reason: String {
        switch self {
        case .unreadable(let code): return "讀不到（\(LibraryStore.errnoText(code))）"   // display-safe-exempt: LibraryStore.errnoText 只回 errno 數字與系統的固定英文說明（code 是 Int32）
        case .notUTF8Text: return "不是 UTF-8 文字（含非 UTF-8 位元組或 NUL，例如以 Latin-1 或 UTF-16 存的檔）——讀不懂的內容不覆寫也不附加"
        case .symlink: return "是 symlink，指向的內容沒有 sources 標記區塊——不經 symlink 寫入（指向的檔可能在 store 之外、被別處共用）"
        case .notRegularFile: return "不是一般檔"
        case .notWritable(let code): return "沒有寫入權限（\(LibraryStore.errnoText(code))）"   // display-safe-exempt: LibraryStore.errnoText 只回 errno 數字與系統的固定英文說明（code 是 Int32）
        case .changedWhileChecking: return "檢查之後、寫入之前被換掉或改過"
        case .writeFailed(let code): return "寫入失敗（\(LibraryStore.errnoText(code))；寫了一半的已截回原長）"   // display-safe-exempt: LibraryStore.errnoText 只回 errno 數字與系統的固定英文說明（code 是 Int32）
        }
    }

    /// 處置。
    public var remedy: String {
        switch self {
        case .unreadable: return "修好讀取權限後重跑，或自己在 .gitignore 加上下面這段"
        case .notUTF8Text: return "把它轉存成 UTF-8 後重跑，或自己在 .gitignore 加上下面這段"
        case .symlink: return "在它指向的檔加上下面這段（或把 symlink 換成一般檔）後重跑"
        case .notRegularFile: return "移走它、換成一般檔後重跑"
        case .notWritable: return "給它寫入權限後重跑，或自己在 .gitignore 加上下面這段"
        case .changedWhileChecking, .writeFailed: return "重跑；仍不行就自己在 .gitignore 加上下面這段"
        }
    }
}
