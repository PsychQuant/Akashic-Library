import Foundation
import AkashicCore

/// `fulltext take` 的輸出檔落地（#629 R1 verify 第 1 則、第 50 則；#613 前是 `fulltext fetch` 的）。
///
/// 第一版把「已存在的目的地」處理成「先刪、再 `moveItem`」：`--out` 指著一個**非空目錄**時 `removeItem` 遞迴刪掉整個目錄再放 PDF
/// （舊 shell 的 `mv` 不會遞迴刪目錄），而目的地是普通檔時，搬移失敗之前原檔已經被刪。這裡改成：
///
/// 1. **在讀 `--from` 之前** `lstat` 每個輸出目的地（`--out`、`*.unverified.pdf`；#613 前還有 `fetch` 的 `*.response.txt`）：不存在或**普通檔**才放行；
///    目錄、symlink、FIFO、socket、裝置一律具名拒絕（零寫入）。拒 symlink 的理由同 `AbstractProposals.writeOut`：跟隨它會改到
///    另一條路徑上的檔，取代它則默默拆掉使用者刻意建的導向。
/// 2. 覆寫普通檔時在**目的地同目錄**開暫存檔、寫完 `rename(2)` 原子替換——`rename` 換的是名字、不跟隨 symlink、也不會遞迴刪任何
///    東西；目的地若在檢查之後變成目錄，`rename` 自己回 `EISDIR`，原檔（或目錄）原封不動。任何一步失敗，原本的檔案都還在。
///
/// **權限**：`replace` 的預設是 `open(2)` 的 `0666`、受 umask 約束，與 `fulltext take` 的舊實作落地的權限一致。`fulltext text`／
/// `compare` 寫第三方全文時傳 `0o600`（#742 verify 第一輪的裁決），`createExclusive` 也由呼叫端給權限。
enum OutputFile {
    enum State: Equatable {
        case absent
        case regular
        /// 已存在但不是普通檔；payload 是給人看的種類名。
        case other(String)
    }

    static func kindName(_ mode: mode_t) -> String {
        switch mode & S_IFMT {
        case S_IFLNK: return "symlink"
        case S_IFDIR: return "directory"
        case S_IFIFO: return "FIFO"
        case S_IFSOCK: return "socket"
        case S_IFCHR: return "character device"
        case S_IFBLK: return "block device"
        default: return "non-regular file"
        }
    }

    /// `lstat`：不存在 → `.absent`；普通檔 → `.regular`；其他 → `.other(種類)`。`lstat` 本身失敗（不是 ENOENT）丟具名錯誤。
    static func inspect(_ path: String) throws -> State {
        var st = stat()
        if lstat(path, &st) != 0 {
            if errno == ENOENT { return .absent }
            throw SkillToolError.failure("cannot inspect \(displaySafeInvisible(path, max: 400)): \(displaySafeInvisible(String(cString: strerror(errno)), max: 200))")
        }
        return (st.st_mode & S_IFMT) == S_IFREG ? .regular : .other(kindName(st.st_mode))
    }

    /// 原子替換用的暫存檔：`<目的地目錄>/.<token>.<目的地檔名>`。
    ///
    /// **尾巴是目的地的整個檔名**（R2 verify 第 2／33 則）：先前是 `.<檔名>.<UUID>.tmp`，而只以 `*.pdf`、`*.response.txt` 忽略輸出的
    /// 工作樹不忽略 `.tmp`——第三方全文在寫入期間（行程被殺時則永久）以一個沒被忽略的名字躺在工作樹裡。尾巴保留檔名，以副檔名忽略的規則
    /// 就同樣蓋得到它；`fulltext take` 的 git 閘另外拿**同一個 token** 算出的名字去問 `check-ignore`，只逐字忽略最終檔名的樹會被拒絕。
    static func tempPath(for path: String, token: String) -> String {
        let dir = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        return (dir.isEmpty ? "." : dir) + "/.\(token).\(name)"
    }

    /// 以 `data` **獨佔建立** `path`：目的地已存在（任何種類）就失敗、不覆寫（#742 verify 第二輪）。
    ///
    /// 先寫同目錄的暫存檔，再以 `link(2)` 把它掛到最終檔名——`link` 在目的地已存在時回 `EEXIST`、不跟隨 symlink，
    /// 所以「檢查之後、寫入之前出現的檔」也不會被蓋掉；`replace` 用的 `rename(2)` 會無聲取代它。最後刪掉暫存檔的名字，不留殘檔。
    static func createExclusive(path: String, with data: Data, mode: mode_t) throws {
        let shown = displaySafeInvisible(path, max: 400)
        let tmp = tempPath(for: path, token: UUID().uuidString)
        let fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode)
        guard fd >= 0 else {
            throw SkillToolError.failure("cannot write \(shown): \(displaySafeInvisible(String(cString: strerror(errno)), max: 200))")   // display-safe-exempt: shown 上面已 displaySafeInvisible
        }
        var failure: String?
        do {
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
            try handle.write(contentsOf: data)
            if fsync(fd) != 0 { failure = String(cString: strerror(errno)) }
        } catch {
            failure = displaySafeErrorText(error)
        }
        if close(fd) != 0, failure == nil { failure = String(cString: strerror(errno)) }
        if failure == nil, link(tmp, path) != 0 {
            switch errno {
            case EEXIST: failure = "it already exists — refusing to replace it"
            // 獨佔建立靠 hard link；不支援的磁碟區（部分網路或 FAT 類檔案系統）要說出原因，不只印 errno 的字串（#742 verify 第三輪）
            // 暫存檔與目的地在同一個目錄，EXDEV 不會發生；EPERM 也可能是別的原因，所以說「可能」
            case EPERM, ENOTSUP, EMLINK:
                failure = "the hard link used to create the file without replacing anything failed (\(String(cString: strerror(errno)))) — this volume may not support hard links; try an --out on another volume"
            default: failure = String(cString: strerror(errno))
            }
        }
        unlink(tmp)
        if let failure {
            throw SkillToolError.failure("cannot write \(shown): \(displaySafeInvisible(failure, max: 300))")   // display-safe-exempt: shown 上面已 displaySafeInvisible
        }
    }

    /// 原子替換（或建立）`path` 為 `data`。目的地是普通檔或不存在才動手；任何一步失敗都不留暫存檔、不動原本的東西。
    /// `mode` 是暫存檔建立時的權限（仍受 umask 限制）；第三方全文用 `0o600`（#742 verify）。
    static func replace(path: String, with data: Data, token: String = UUID().uuidString, mode: mode_t = 0o666) throws {
        let shown = displaySafeInvisible(path, max: 400)
        switch try inspect(path) {
        case .other(let kind):
            throw SkillToolError.failure("refusing to replace \(shown): it is a \(displaySafeInvisible(kind, max: 40)), not a regular file")   // display-safe-exempt: shown 上面已 displaySafeInvisible
        case .absent, .regular:
            break
        }
        let tmp = tempPath(for: path, token: token)
        let fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode)
        guard fd >= 0 else {
            throw SkillToolError.failure("cannot write \(shown): \(displaySafeInvisible(String(cString: strerror(errno)), max: 200))")   // display-safe-exempt: shown 上面已 displaySafeInvisible
        }
        var failure: String?
        do {
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
            try handle.write(contentsOf: data)
            if fsync(fd) != 0 { failure = String(cString: strerror(errno)) }
        } catch {
            failure = displaySafeErrorText(error)
        }
        if close(fd) != 0, failure == nil { failure = String(cString: strerror(errno)) }
        if failure == nil {
            // 開暫存檔到現在之間目的地可能變了：再看一眼，把窗縮到只剩 `rename` 前後（rename 自己也會在目錄上回 EISDIR）
            if case .other(let kind) = try? inspect(path) {
                failure = "the destination became a \(kind) while writing"
            } else if rename(tmp, path) != 0 {
                failure = String(cString: strerror(errno))
            }
        }
        if let failure {
            unlink(tmp)
            throw SkillToolError.failure("cannot write \(shown): \(displaySafeInvisible(failure, max: 300))")   // display-safe-exempt: shown 上面已 displaySafeInvisible
        }
    }
}
