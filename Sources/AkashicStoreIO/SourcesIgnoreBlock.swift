import Foundation
import Darwin

/// `ensureLayout` 對 store 根目錄 `.gitignore` 的處置：沒有 sources 排除區塊（#66 task 4.3）就加上。
///
/// **讀不懂的內容不覆寫**（#700 b31 W5 MEDIUM 0、1）。先前讀不出來就當成空檔（非 UTF-8、UTF-16、讀取權限不足），整份以「只含區塊」的
/// 內容原子替換——使用者原有的規則（擋 raw 逐字稿的 `*.srt` 之類）全部消失、沒有任何訊息；`.gitignore` 是 symlink 時被換成一般檔。
/// `file add`、`doctor`、`import-zotero`、MCP 的兩個匯入都經 `ensureLayout` 走到這裡。現在：
/// - 標記以**位元組**比對（`# BEGIN akashic sources` 是 ASCII），而且標記之後要有一行排除規則（`sourcesRuleLines`，b33 verify X5 第 2 列：
///   寫到一半中斷的區塊只有標記、沒有規則，先前被當成「已在」而永遠不補），而且那一行沒有被更後面的否定規則放回來（`ruleState`，
///   #700 b38 verify）——都成立就什麼都不做，不論那個檔是什麼編碼。
/// - 要加區塊時以 `O_APPEND` 在尾端**附加位元組**，原有的位元組一個都不動；檔尾不是 `\n` 先補一個（同 `appendIndexEntry` 的守衛）。
///   檔案不存在時以 `O_EXCL` 新建。
/// - **看與寫之間**（b33 verify X5 第 0 列 MEDIUM）：先看（`inspectSourcesIgnore`，不寫）決定要不要在建立任何東西之前拒絕；真的要寫時
///   開檔、取 `flock(LOCK_EX)`、**在鎖內重讀一次內容**再決定——同時跑的兩個 akashic 程序因此一個寫、另一個看到區塊已在就什麼都不做。
///   先看也在讀內容之前取 `flock(LOCK_SH)`（b34 修正輪）：先看與鎖內重看是同一個判斷，不等鎖的先看會讀到寫了一半的區塊而假拒絕。
///   兩種鎖都只等 `lockWaitSeconds`（b36 verify）：持鎖的程序卡住時報 `lockTimedOut`、不讀不寫，不讓 `doctor` 與匯入無限期卡住。
///   先前以 device／inode／大小比對代替鎖：只縮小窗口，實測兩個程序同時首跑時會寫出兩份區塊，`O_EXCL` 撞上 `EEXIST`、大小不符也直接
///   報「被換掉或改過」而不重看（假拒絕、假警告）。現在遇到這兩種情形重看一次（至多 `applyAttempts` 次），重看之後區塊在就算成功。
///   寫到一半失敗時只截掉這一次寫進去的位元組（大小還是「原長＋這一次寫的」才截；`ftruncate` 的結果要看），截不回來具名回報。
/// - 讀不到、不是 UTF-8 文字（含 NUL 也算——UTF-16 存的檔）、是 symlink、symlink 打不開、不是一般檔、有其他硬連結、
///   大到 git 不讀、有標記沒有規則、規則被之後的否定規則放回來、沒有寫入權限、等鎖逾時：**不動它**。`file add` 在建立任何東西之前具名拒絕（`SourcesIgnorePolicy.refuse`）；
///   `doctor` 與兩個匯入照常建佈局、改報一則 warning（`.report`；匯入見下）。開檔、取鎖、寫入這一段才發現的原因（寫入失敗、重看之後仍在變），那時佈局已建好。
/// - **匯入是 warning，不是拒絕**（使用者 2026-10-05 裁決 #700 第 1 項）：`import-zotero` 與 MCP 的兩個匯入（含 `dry_run`）本身不寫
///   `sources/`，擋住第三方存檔進版控的防線在 `store-source`——它寫入前以 `git check-ignore` 驗排除，區塊沒加上就拒寫（`assertSourcesExcluded`）。
///   先前匯入也在建立任何東西之前拒絕，等於讓一個讀不懂的 `.gitignore` 擋住一件與它無關的事。警告的文字只有 `warningLines` 一份。
/// - symlink 與硬連結選拒絕、不寫到那個檔：它可能在 store 之外、被別的 repo 共用，替人改 store 之外的檔不是建佈局該做的事。
///   **symlink 不論指向的內容有沒有區塊都是問題**（#700 b36 verify）：git（2.32 起）不讀工作樹裡 symlink 的 `.gitignore`
///   （2026-10-09 以 git 2.55 實測：`warning: unable to access '.gitignore': Too many levels of symbolic links`、`sources/` 不被排除）。
///   先前指向的內容有區塊就判成「已在」、什麼都不說，而 git 根本不讀那個檔。symlink 一律不動。
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

    /// 標記之後算數的排除規則（封閉列舉；一行照 git 的切法去掉行尾之後逐位元組比對，見 `ruleState`）。程式寫的是 `sources/`；
    /// 手工區塊常見的寫法一併收（git 對這幾種都會排除根目錄的 `sources/` 底下的內容）。不在這裡的寫法（萬用字元的其他形狀、否定規則）
    /// 不算，那時區塊被判成「有標記沒有規則」、交給人看——`storeSource` 寫入前另以 `git check-ignore` 驗排除，未生效即拒寫。
    /// 前四種排除**目錄**本身（git 不進被排除的目錄，裡面的檔無法被之後的否定規則放回來）；後四種只排除目錄**裡的**內容，
    /// 目錄本身沒被排除（之後的否定規則放得回裡面的檔）。兩種在否定規則的判讀上不同，見 `ruleState`。
    internal static let sourcesDirectoryRuleLines: [[UInt8]] = ["sources/", "/sources/", "sources", "/sources"].map { Array($0.utf8) }
    internal static let sourcesContentRuleLines: [[UInt8]] = ["sources/*", "/sources/*", "sources/**", "/sources/**"].map { Array($0.utf8) }
    internal static let sourcesRuleLines: [[UInt8]] = sourcesDirectoryRuleLines + sourcesContentRuleLines

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
        /// 標記之後有排除規則，但更後面的否定規則（`!` 開頭）把 `sources/` 放了回來（#700 b38 verify）。
        case ruleNegatedLater
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
        // git 不讀 symlink 的 .gitignore：指向的內容有沒有區塊都不生效，不必讀（#700 b36 verify）
        if isLink { return .problem(.symlink) }
        if fileStat.st_size >= off_t(Self.gitignoreSizeLimit) { return .problem(.tooLarge) }   // 不讀：git 也不讀
        // 先看也等持鎖的寫入者寫完：這裡的判讀與鎖內重看是同一個判斷，先看讀到寫了一半的區塊（只有標記、或切在多位元組字元中間）
        // 會在建立任何東西之前假拒絕。共享鎖，看的程序之間不互等；fd 關掉即放鎖。等不到就報，不無限期卡住（b36 verify）
        guard Self.lock(fd, LOCK_SH) else { return .problem(.lockTimedOut) }
        let bytes: [UInt8]
        switch Self.readAll(fd) {
        case .bytes(let b): bytes = b
        case .tooLarge: return .problem(.tooLarge)
        case .failed(let code): return .problem(.unreadable(errno: code))
        }
        switch Self.judgeSourcesIgnore(bytes) {
        case .blockPresent: return .present
        case .markerWithoutRule: return .problem(.markerWithoutRule)
        case .ruleNegatedLater: return .problem(.ruleNegatedLater)
        case .notUTF8Text: return .problem(fileStat.st_nlink > 1 ? .hardLinked : .notUTF8Text)
        case .needsBlock(let needsNewline):
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
        guard Self.lock(fd, LOCK_EX) else {
            // 這一步以 O_EXCL 建的檔、仍是空的、路徑仍指著它：刪掉，訊息說的「沒有寫」才成立（b38 verify INFO：先前留下一個空檔）
            if create { Self.removeIfStillOurEmptyFile(fd, path) }
            return .failed(.lockTimedOut)
        }
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
        case .ruleNegatedLater: return .failed(.ruleNegatedLater)
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

    /// 內容的判讀（不看檔案的種類與權限）：標記之後有一行排除規則、而且沒有被更後面的否定規則放回來＝區塊在；只有標記＝有標記沒有規則；
    /// 規則被放回來＝`ruleNegatedLater`；沒有標記時看是不是 UTF-8 文字。
    internal static func judgeSourcesIgnore(_ bytes: [UInt8]) -> SourcesIgnoreContent {
        let marker = Array(sourcesIgnoreMarker.utf8)
        if let at = firstIndex(of: marker, in: bytes) {
            switch ruleState(bytes, from: at + marker.count) {
            case .noRule: return .markerWithoutRule
            case .effective: return .blockPresent
            case .negated: return .ruleNegatedLater
            }
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

    /// 標記之後的排除規則落在哪個狀態（`ruleState`）。
    internal enum RuleState: Equatable { case noRule, effective, negated }

    /// `from` 之後（從下一行開始）逐行照 git 的順序走：`sourcesRuleLines` 之一的那一行排除 `sources/`，`!` 開頭而會放回 `sources/` 的那一行
    /// 撤銷它——git 對同一個 `.gitignore` 以**最後一條**符合的規則為準（#700 b38 verify：先前只找規則行、不看它後面的否定，區塊之後接一行
    /// `!sources/`、`!sou*/`、`!*` 時判成「已在」、doctor 不出聲，而 git 不排除；2026-10-15 以 git 2.55 的 `check-ignore` 逐形實測）。
    ///
    /// **規則行的切法**（2026-10-09 以 git 2.55 逐形實測）：行尾**一個** CR（緊接換行或檔尾）先去掉，再去掉行尾的空格。**行首的空白與 tab、
    /// 行尾的 tab 都是規則的一部分**：`  sources/` 對 git 是「以兩個空白開頭的名字」，不排除根目錄的 `sources/`；`sources/\r ` 的 CR 不在行尾，
    /// 也不去（#700 b36 verify）。git 不去反斜線跳脫的行尾空格，規則行這裡一律去：`sourcesRuleLines` 沒有一個含反斜線，判讀相同。
    ///
    /// **否定規則**只看行首就是 `!` 的行（`  !sources/` 對 git 是一個以空白開頭的一般規則，`\!sources/` 是名字以 `!` 開頭的一般規則）；
    /// 行尾照 git 的 `trim_trailing_spaces` 去（反斜線跳脫的空格保留）。兩種排除各自記：
    /// - 目錄形（`sources/`、`sources` 等前四種）：git 不進被排除的目錄，只有**符合根目錄的 `sources` 這個目錄本身**的否定規則放得回來
    ///   （`!sources/`、`!/sources`、`!sou*/`、`!*`、`!*/`、`!**`、`!**/sources`；`!sources/x`、`!sources/*` 放不回來）——`negationReachesSources`。
    /// - 內容形（`sources/*`、`sources/**` 等後四種）：目錄本身沒被排除，否定規則放得回裡面的檔；這裡不知道裡面有哪些檔名，**任何一行**
    ///   非空的否定規則都當成會放回（保守：可能把 git 仍排除的形狀判成不生效，方向是多報、不是漏報）。
    /// 否定之後再出現一行規則行，那一行重新排除（最後一條為準）。只看標記之後：標記之前的規則行不算（先前就如此，方向同樣是多報）。
    internal static func ruleState(_ bytes: [UInt8], from start: Int) -> RuleState {
        let newline = UInt8(ascii: "\n")
        guard var i = bytes[start...].firstIndex(of: newline) else { return .noRule }
        i += 1
        var sawRule = false, directoryExcluded = false, contentExcluded = false
        while i < bytes.count {
            let end = bytes[i...].firstIndex(of: newline) ?? bytes.count
            var hi = end
            if hi > i, bytes[hi - 1] == 0x0D { hi -= 1 }
            let withoutCR = hi
            while hi > i, bytes[hi - 1] == 0x20 { hi -= 1 }
            let line = bytes[i..<hi]
            if hi - i <= 12, sourcesDirectoryRuleLines.contains(where: { $0.elementsEqual(line) }) {
                sawRule = true; directoryExcluded = true
            } else if hi - i <= 12, sourcesContentRuleLines.contains(where: { $0.elementsEqual(line) }) {
                sawRule = true; contentExcluded = true
            } else if i < withoutCR, bytes[i] == UInt8(ascii: "!") {
                let pattern = gitTrimmedTrailingSpaces(bytes[(i + 1)..<withoutCR])
                if !pattern.isEmpty {   // 只有一個 `!` 的行 git 不當規則（實測）
                    if negationReachesSources(Array(pattern)) { directoryExcluded = false }
                    contentExcluded = false
                }
            }
            i = end + 1
        }
        guard sawRule else { return .noRule }
        return directoryExcluded || contentExcluded ? .effective : .negated
    }

    /// git 的 `trim_trailing_spaces`（dir.c）：去掉行尾的空格，反斜線跳脫的那一個保留。
    private static func gitTrimmedTrailingSpaces(_ s: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        var lastSpace: Int?
        var p = s.startIndex
        while p < s.endIndex {
            switch s[p] {
            case 0x20:
                if lastSpace == nil { lastSpace = p }
            case 0x5C:
                p += 1
                if p >= s.endIndex { return s }
                lastSpace = nil
            default:
                lastSpace = nil
            }
            p += 1
        }
        return lastSpace.map { s[s.startIndex..<$0] } ?? s
    }

    /// 一行否定規則（去掉 `!` 之後）符不符合根目錄的 `sources` 這個目錄（照 git 的 `.gitignore` 語意：結尾的 `/` 只限目錄、`sources` 是目錄；
    /// 不含 `/` 的比最後一段名字、在任何深度；含 `/` 的對 `.gitignore` 所在目錄錨定，開頭的 `**/` 可以是零層）。名字的比對見 `globMatches`；
    /// 認不出的寫法（`[…]` 字元類）當成符合——保守，方向是多報。
    internal static func negationReachesSources(_ pattern: [UInt8]) -> Bool {
        var p = pattern[...]
        if p.last == UInt8(ascii: "/") { p = p.dropLast() }
        guard !p.isEmpty else { return false }
        let slash = UInt8(ascii: "/")
        if p.contains(slash) {
            if p.first == slash { p = p.dropFirst() }
            let doubleStar = Array("**/".utf8)
            while p.starts(with: doubleStar) { p = p.dropFirst(3) }
            if p.contains(slash) { return false }   // 還有一層以上：符合的是 sources 底下或別處的路徑，不是根目錄的 sources 本身
        }
        return globMatches(Array(p), Array("sources".utf8)) ?? true
    }

    /// 一段名字的 glob（git wildmatch 的子集：`*`、`?`、反斜線跳脫、其餘逐字），ASCII 不分大小寫——macOS 上 `git init` 的 repo
    /// 預設 `core.ignorecase=true`，`!SOURCES/` 放得回來；區分大小寫的 repo 照這裡判是多報。`[` 開頭的字元類不模擬，回 `nil`。
    internal static func globMatches(_ pattern: [UInt8], _ text: [UInt8]) -> Bool? {
        func lower(_ b: UInt8) -> UInt8 { (0x41...0x5A).contains(b) ? b + 0x20 : b }
        let star = UInt8(ascii: "*"), question = UInt8(ascii: "?"), backslash = UInt8(ascii: "\\"), open = UInt8(ascii: "[")
        if pattern.contains(open) { return nil }
        var p = 0, t = 0, starP = -1, starT = -1
        while t < text.count {
            if p < pattern.count {
                let c = pattern[p]
                if c == star {
                    while p < pattern.count, pattern[p] == star { p += 1 }
                    starP = p; starT = t
                    continue
                }
                if c == question { p += 1; t += 1; continue }
                if c == backslash {
                    guard p + 1 < pattern.count else { return false }   // 結尾的反斜線：符合不了任何名字
                    if lower(pattern[p + 1]) == lower(text[t]) { p += 2; t += 1; continue }
                } else if lower(c) == lower(text[t]) {
                    p += 1; t += 1; continue
                }
            }
            guard starP >= 0 else { return false }
            starT += 1; t = starT; p = starP
        }
        while p < pattern.count, pattern[p] == star { p += 1 }
        return p == pattern.count
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

    /// `fd` 是這一步剛以 `O_EXCL` 建的檔：仍是空的、路徑仍指著同一個 inode 時刪掉路徑。
    private static func removeIfStillOurEmptyFile(_ fd: Int32, _ path: String) {
        var held = stat(), named = stat()
        guard fstat(fd, &held) == 0, held.st_size == 0, lstat(path, &named) == 0,
              named.st_dev == held.st_dev, named.st_ino == held.st_ino else { return }
        unlink(path)
    }

    /// `open`，`EINTR` 重試（b33 verify X5 第 18 列）。
    private static func openRetrying(_ path: String, _ flags: Int32, mode: mode_t = 0) -> Int32 {
        while true {
            let fd = open(path, flags, mode)
            if fd >= 0 || errno != EINTR { return fd }
        }
    }

    /// 等鎖的上限（秒）。正常的持鎖者只持一次讀加一次附加（微秒級）；等這麼久還拿不到，是持鎖的程序卡住了（被 `SIGSTOP`、
    /// 卡在網路掛載）——`doctor` 與兩個匯入被裁決成不被 `.gitignore` 擋住，不能在這裡無限期等（#700 b36 verify：先前阻塞的 `flock`
    /// 沒有上限）。測試以 `SourcesIgnoreIO.lockWait` 換掉。
    internal static let lockWaitSeconds: Double = 10

    /// 取 `flock`：`LOCK_EX`（附加前，同時跑的 akashic 程序在這裡排隊）或 `LOCK_SH`（先看在讀內容之前取，等持 `LOCK_EX` 的寫入者
    /// 寫完）。以 `LOCK_NB` 每 20 ms 試一次，到 `lockWaitSeconds` 還拿不到回 `false`（呼叫端報 `lockTimedOut`、不讀不寫）。
    /// **期限用單調時鐘**（`ContinuousClock`；使用者 2026-10-15 裁決，b38 verify：先前用牆上時鐘 `Date()`，等待期間系統時間往回撥，
    /// 上限就跟著拉長）；`EINTR` 也看期限（先前直接重試、不看期限——`LOCK_NB` 實務上不會被中斷，但重試的每一條路都要過同一個期限）。
    /// `EWOULDBLOCK` 以外的錯誤一律不鎖、照常往下（回 `true`）：檔案系統不支援（`ENOTSUP`／`EOPNOTSUPP`，部分網路掛載）、網路掛載的
    /// 鎖服務停了（`ENOLCK`）之類都在這一類（b38 verify INFO：先前的說明只寫前兩個）——那時鎖內重看仍會擋掉「別人已經寫好」的那一種，
    /// 擋不住兩邊同時寫（誠實邊界）。測試以 `SourcesIgnoreIO.tryLock` 換掉 `flock` 本身。
    private static func lock(_ fd: Int32, _ operation: Int32) -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(SourcesIgnoreIO.lockWait ?? lockWaitSeconds))
        let attempt = SourcesIgnoreIO.tryLock ?? { flock($0, $1 | LOCK_NB) == 0 ? nil : errno }
        while true {
            guard let code = attempt(fd, operation) else { return true }
            guard code == EWOULDBLOCK || code == EINTR else { return true }   // 不支援或其他錯誤：照常往下（同先前的阻塞版）
            if clock.now >= deadline { return false }
            if code == EWOULDBLOCK { usleep(20_000) }
        }
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

/// 測試用的注入點：附加的寫入、失敗後的截斷、等鎖的上限與試鎖本身（`withValue` 的範圍內有效；`nil`＝真的 `write`／`ftruncate`／`flock`、預設上限）。
/// 寫入失敗與截斷失敗在真的檔案系統上造不出來（RLIMIT_FSIZE 在 macOS 對附加不生效，b33 verify X5 DA 實測）。
internal enum SourcesIgnoreIO {
    /// 回寫進去的位元組數與 errno（成功時 `nil`）。
    @TaskLocal static var write: (@Sendable (Int32, [UInt8]) -> (written: Int, errno: Int32?))?
    /// 回 errno（成功時 `nil`）。
    @TaskLocal static var truncate: (@Sendable (Int32, off_t) -> Int32?)?
    /// 等鎖的上限（秒；`nil`＝`LibraryStore.lockWaitSeconds`）。
    @TaskLocal static var lockWait: Double?
    /// 試一次 `flock(fd, operation | LOCK_NB)`：回 errno（拿到鎖時 `nil`）。`EINTR` 在 `LOCK_NB` 下造不出來，測試由這裡給。
    @TaskLocal static var tryLock: (@Sendable (Int32, Int32) -> Int32?)?
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
    /// 是 symlink，指向的檔讀得到（是一般檔）：git 不讀 symlink 的 `.gitignore`，指向的內容有沒有區塊都不生效。
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
    /// 標記之後有排除規則，但更後面有一行否定規則（`!` 開頭）把 `sources/` 放了回來（git 以最後一條符合的規則為準；#700 b38 verify）。
    case ruleNegatedLater
    /// 沒有寫入權限。
    case notWritable(errno: Int32)
    /// 打不開來寫，原因與權限無關（`EMFILE` 之類）；什麼都沒寫。
    case openFailed(errno: Int32)
    /// 看與寫之間一直在變（重看 `LibraryStore.applyAttempts` 次之後）。
    case changedWhileChecking
    /// 另一個程序持有 `.gitignore` 的鎖、等了 `LibraryStore.lockWaitSeconds` 還拿不到；沒有讀、也沒有寫。
    case lockTimedOut
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
        case .symlink: return "是 symlink——git（2.32 起）不讀工作樹裡 symlink 的 .gitignore，指向的檔有沒有 sources 區塊都不生效；也不經 symlink 寫入（指向的檔可能在 store 之外、被別處共用）"
        case .brokenSymlink(let code): return "是 symlink，指向的檔打不開（\(LibraryStore.errnoText(code))：懸空、迴圈或不可讀）"   // display-safe-exempt: LibraryStore.errnoText 只回 errno 數字與系統的固定英文說明（code 是 Int32）
        case .notRegularFile: return "不是一般檔（目錄、FIFO 之類，或 symlink 指向它們）"
        case .hardLinked: return "有其他硬連結——附加會改到別處共用的同一個檔（與 symlink 同一個理由）"
        case .tooLarge: return "大到 git 不讀（git 不讀 100 MiB 以上的 .gitignore），或附加之後會越過那條線——加了也不生效"
        case .markerWithoutRule: return "有 sources 標記，但標記之後沒有一行 git 會當成排除 sources/ 的規則（區塊寫到一半中斷或被改過；行首帶空白或 tab、行尾帶 tab 的 sources/ git 不認）——不改寫既有的區塊"
        case .ruleNegatedLater: return "標記之後有排除 sources/ 的規則，但更後面有一行否定規則（! 開頭，例如 !sources/、!*）把它放了回來——git 對同一個 .gitignore 以最後一條符合的規則為準（排除規則是 sources/* 這類只排除內容的寫法時，之後任何一行否定規則都算）；不改寫既有的規則"
        case .notWritable(let code): return "沒有寫入權限（\(LibraryStore.errnoText(code))）"   // display-safe-exempt: LibraryStore.errnoText 只回 errno 數字與系統的固定英文說明（code 是 Int32）
        case .openFailed(let code): return "打不開來寫（\(LibraryStore.errnoText(code))），什麼都沒寫"   // display-safe-exempt: LibraryStore.errnoText 只回 errno 數字與系統的固定英文說明（code 是 Int32）
        case .changedWhileChecking: return "看與寫之間一直被換掉或改動（重看了 \(LibraryStore.applyAttempts) 次）"   // display-safe-exempt: LibraryStore.applyAttempts 是 Int 常數
        case .lockTimedOut: return "另一個程序持有它的鎖，等了 \(Int(LibraryStore.lockWaitSeconds)) 秒還拿不到（持鎖的程序可能卡住了），沒有讀也沒有寫"   // display-safe-exempt: Int(LibraryStore.lockWaitSeconds)：LibraryStore.lockWaitSeconds 是 Double 常數，Int 只是型別轉換
        case .writeFailed(let code): return "寫入失敗（\(LibraryStore.errnoText(code))）；這一次寫進去的部分已截回原長"   // display-safe-exempt: LibraryStore.errnoText 只回 errno 數字與系統的固定英文說明（code 是 Int32）
        case let .rollbackFailed(w, t):
            return "寫入失敗（\(LibraryStore.errnoText(w))），而且沒能截回原長（"   // display-safe-exempt: LibraryStore.errnoText 只回 errno 數字與系統的固定英文說明（w、t 是 Int32）
                + (t.map { "ftruncate：" + LibraryStore.errnoText($0) } ?? "寫入期間檔案被別的程序改過，截了會刪掉別人的位元組")
                + "）——.gitignore 尾端可能留著半段區塊"
        }
    }

    /// 首句的主詞與狀態（warning 與 `file add` 的拒絕共用）。讀不到與等鎖逾時**沒有讀內容**，不知道裡面有沒有區塊：說「沒有讀」，
    /// 不斷言「沒有生效的區塊」（使用者 2026-10-15 裁決，b38 verify：先前一律說「沒有生效的」，處置又叫人自己加一段，持鎖的檔很可能已有區塊）。
    /// 其餘各格讀過內容，或 git 本來就不讀那個檔（symlink、不是一般檔、大到 git 不讀），「沒有生效的」成立。
    public var headline: String {
        switch self {
        case .unreadable, .lockTimedOut: return ".gitignore 沒有讀到，不知道裡面有沒有生效的 sources 排除區塊"
        default: return ".gitignore 沒有生效的 sources 排除區塊"
        }
    }

    /// 一則 warning（`.report` 的呼叫端報它）：一行說明加上要自己加的那段（每行縮排四格）。`doctor` 印到 stdout、`import-zotero` 印到
    /// stderr、MCP 的兩個匯入以換行接起來放進回應的 `gitignoreWarning`——三處同一份文字（#700 b35）。`actor` 是程式字面（命令名），
    /// `note` 是呼叫端的固定句，接在原因之後；`rerun` 是處置裡「之後怎麼再跑」那幾個字（`remedy(rerun:)`）。只含固定句、errno 數字與
    /// 系統的固定英文說明，不含使用者資料。
    ///
    /// 首句是 `headline`：「沒有**生效的**」排除區塊（#700 b36 verify）——symlink、大到 git 不讀的檔裡可能有區塊，只是 git 不讀；先前說
    /// 「沒有 sources 排除區塊」，處置又叫人「自己加上下面這段」，使用者在已經有區塊的檔裡再貼一份。沒有讀內容的兩格改說「沒有讀」（b38 verify）。
    public func warningLines(by actor: String, note: String = "", rerun: String = Self.defaultRerun) -> [String] {
        ["⚠ " + headline + "，\(actor) " + (leavesGitignoreUntouched ? "沒有改寫它" : "寫到一半、沒能收回")   // display-safe-exempt: headline 是本型別的固定句；actor 是呼叫端的程式字面（命令名）
            + "：\(reason)。\(note)\(remedy(rerun: rerun))："]   // display-safe-exempt: reason、remedy 是本型別的固定句與 errno 說明；note、rerun 是呼叫端的固定句
            + LibraryStore.sourcesIgnoreBlock.split(separator: "\n").map { "    \($0)" }   // display-safe-exempt: 取自常數 LibraryStore.sourcesIgnoreBlock
    }

    /// 匯入的 warning 接在原因之後的那一句（CLI `import-zotero` 與 MCP 的兩個匯入同一句）。不對還沒發生的事下斷言（#700 b36 verify：
    /// 先前寫「匯入照常完成」，CLI 在讀 zotero.sqlite 之前就印它，之後找不到 db 而以 1 結束時兩句互相矛盾）。
    public static let importContinuedNote =
        "匯入不因此中止（匯入不寫 sources/）；store 在 git 工作樹裡時，sources/ 沒被排除之前 store-source 拒絕寫入。"

    /// 匯入的處置裡「之後怎麼再跑」（#700 b36 verify：先前一律寫「重跑」，對匯入是叫人重做一次已經做完的匯入；CLI 的 `akashic doctor`
    /// 補區塊就夠。MCP 的 `akashic_doctor` 不建佈局、不補區塊，只用 MCP 的人重跑匯入也會補上——兩條都寫）。
    public static let importRerun = "跑 akashic doctor（或重跑匯入）"

    /// 處置裡「之後怎麼再跑」的預設（`file add`、`doctor` 自己）。
    public static let defaultRerun = "重跑"

    /// 處置（`file add`、`doctor` 用的那一份：之後「重跑」）。
    public var remedy: String { remedy(rerun: Self.defaultRerun) }

    /// 處置；`rerun` 是「之後怎麼再跑」那幾個字（匯入是 `importRerun`）。
    public func remedy(rerun: String) -> String {
        switch self {
        case .unreadable: return "修好讀取權限後\(rerun)；或自己打開它看，沒有區塊才加上下面這段（區塊已在就不用加）"   // display-safe-exempt: rerun 是呼叫端的固定句
        case .notUTF8Text: return "把它轉存成 UTF-8 後\(rerun)，或自己在 .gitignore 加上下面這段"   // display-safe-exempt: rerun 是呼叫端的固定句
        case .symlink: return "把 symlink 換成一般檔（內容照抄過去）後\(rerun)，區塊還沒有就會補上；或換好之後自己加上下面這段"   // display-safe-exempt: rerun 是呼叫端的固定句
        case .brokenSymlink: return "把 symlink 換成一般檔後\(rerun)"   // display-safe-exempt: rerun 是呼叫端的固定句
        case .notRegularFile: return "移走它、換成一般檔後\(rerun)"   // display-safe-exempt: rerun 是呼叫端的固定句
        case .hardLinked: return "確認別處共用的那個檔也該有這段之後自己加上下面這段，或把 .gitignore 換成獨立的一般檔後\(rerun)"   // display-safe-exempt: rerun 是呼叫端的固定句
        case .tooLarge: return "把 .gitignore 縮到 100 MiB 以下（git 才會讀它）後\(rerun)，區塊已在就不會再加一份、還沒有就會補上；或縮好之後自己加上下面這段"   // display-safe-exempt: rerun 是呼叫端的固定句
        case .markerWithoutRule: return "在標記區塊裡補上頂格的 sources/ 一行（行首不留空白、行尾不留 tab），或刪掉殘缺的區塊、換成下面這段後\(rerun)"   // display-safe-exempt: rerun 是呼叫端的固定句
        case .ruleNegatedLater: return "刪掉區塊之後放回 sources/ 的否定規則（或把它移到區塊之前）後\(rerun)；區塊已在，不要再貼一份——對照用的區塊"   // display-safe-exempt: rerun 是呼叫端的固定句
        case .notWritable: return "給它寫入權限後\(rerun)，或自己在 .gitignore 加上下面這段"   // display-safe-exempt: rerun 是呼叫端的固定句
        case .lockTimedOut: return "確認沒有卡住的 akashic 程序後\(rerun)；仍拿不到鎖就自己打開它看，沒有區塊才加上下面這段（區塊已在就不用加）"   // display-safe-exempt: rerun 是呼叫端的固定句
        case .openFailed, .changedWhileChecking, .writeFailed: return "\(rerun)；仍不行就自己在 .gitignore 加上下面這段"   // display-safe-exempt: rerun 是呼叫端的固定句
        case .rollbackFailed: return "打開 .gitignore 看尾端，刪掉不完整的那段後\(rerun)，或換成下面這段"   // display-safe-exempt: rerun 是呼叫端的固定句
        }
    }
}
