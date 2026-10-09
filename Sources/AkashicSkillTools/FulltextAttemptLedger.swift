import Foundation
import AkashicCore

/// 每站每天取全文的嘗試次數（#613，使用者 2026-10-01 裁決）。
///
/// - **上限**：同一個網站、Asia/Taipei 的同一個日曆日，最多 `dailyCap`（10）次嘗試；到上限就停那個站，隔天再跑。
/// - **一次嘗試**：`fulltext fetch` 準備導航到 PDF（或把頁面的下載按鈕交給人）的那一刻。之後失敗、驗證不過、使用者沒存檔，
///   都已經算了——網站看到的是請求，不是結果。
/// - **網站**：doi.org 轉址之後，文章頁的主機（小寫）。不是 PDF 的主機：同一個出版商的 PDF 可能放在另一個主機
///   （ScienceDirect 的 `pdf.sciencedirectassets.com`），而上限管的是對那個出版商的造訪。
///
/// # 帳本住在 store 之外
///
/// 預設在 `$HOME/Library/Application Support/akashic/fulltext-attempts.jsonl`。**不放 `~/.akashic`**：那個目錄就是預設 store
/// （`main`）的 root、也是資料 git repo 的根，它的 `.gitignore` 只排除 `config.yaml`、`index/`、`sources/`，放進去的帳本會變成
/// 資料 repo 裡一個未追蹤的檔（`AkashicHome` 的型別註解記著同一個形狀）。**也不從 `sources/index.jsonl` 推算**：`fetch` 不碰
/// store；index 只記存進去的成功，失敗的嘗試（它們一樣打到了網站）不會出現；index 的 `origin` 是 PDF 的網址、主機不是文章頁的；
/// `retrieved` 是自由字串，沒有強制帶時區。
///
/// 每行一筆 JSON：`{"at": "<ISO 8601，帶 +08:00>", "site": "<主機>", "landing": "<--landing 去掉查詢、片段與路徑參數>"}`（`landing` 寫的是
/// `FulltextFetch.plainURL(--landing)`，#613 b34；它不參與計數，只是記錄——DOI 裡的 `?` 之後也會被切掉）。
///
/// **讀不懂就拒絕（fail-closed）**：檔案存在但讀不了、不是普通檔（symlink、目錄）、有一行不是這個形狀、`at` 沒有明確的時區
/// ——一律丟具名錯誤，`fetch` 在碰瀏覽器之前停下。數不出今天的次數，就不能保證沒超過上限。
///
/// # 查數與記錄是一步（#613 修正輪，使用者 2026-10-02）
///
/// `reserve` 在**跨行程的獨占鎖**（`flock(LOCK_EX)`，鎖在帳本檔本身）之下重讀帳本、數今天的次數、沒到上限就記一筆；之後才導航。
/// 兩個行程同時搶最後一格時只有一個拿到：先前的「`count` 之後 `append`」中間沒有鎖，兩個行程都讀到 9、各自記成第 10 次。
/// 記錄之前檢查檔尾：最後一個位元組不是換行（手改過帳本、編輯器沒補檔尾換行）就先補一個，免得新的一筆黏在舊的一筆後面、
/// 讓下一次 `load` 整個拒絕。
public struct FulltextAttemptLedger {
    public static let dailyCap = 10
    public static let timeZone = TimeZone(identifier: "Asia/Taipei")!

    public let path: String
    /// 測試接縫：`reserve` 讀完帳本、決定要不要記之前被叫一次（把「查數與記錄之間」的視窗拉寬，讓沒有鎖的實作必然出錯）。
    var afterRead: (() -> Void)?

    public init(path: String) { self.path = path }

    /// `reserve` 的結果。`used` 是**包含這一次**（granted）或目前已有（capReached）的次數。
    public enum Reservation: Equatable {
        case granted(used: Int)
        case capReached(used: Int)
    }

    /// 預設路徑。`HOME` 有設就用它（沙箱與測試把它指到暫存目錄），否則用系統的家目錄。
    public static func defaultPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let home = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? FileManager.default.homeDirectoryForCurrentUser.path
        return (home as NSString).appendingPathComponent("Library/Application Support/akashic/fulltext-attempts.jsonl")
    }

    public struct Entry: Equatable {
        public let at: Date
        public let site: String
    }

    /// 帳本的每一筆。檔案不存在＝空。
    public func load() throws -> [Entry] {
        var st = stat()
        if lstat(path, &st) != 0 {
            if errno == ENOENT { return [] }
            throw SkillToolError.failure("cannot read the attempt ledger \(displaySafeInvisible(path, max: 400)): \(displaySafeInvisible(String(cString: strerror(errno)), max: 200))")
        }
        guard (st.st_mode & S_IFMT) == S_IFREG else {
            throw SkillToolError.failure("the attempt ledger \(displaySafeInvisible(path, max: 400)) is a \(displaySafeInvisible(OutputFile.kindName(st.st_mode), max: 40)), not a regular file — refusing to follow or replace it")
        }
        // `O_NONBLOCK`：lstat 與 open 之間被換成 FIFO 時，阻塞的 open 會一直等下去；非阻塞開，再用 fstat 確認開到的是普通檔
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw SkillToolError.failure("cannot read the attempt ledger \(displaySafeInvisible(path, max: 400)): \(displaySafeInvisible(String(cString: strerror(errno)), max: 200))") }
        defer { close(fd) }
        var opened = stat()
        guard fstat(fd, &opened) == 0, (opened.st_mode & S_IFMT) == S_IFREG else {
            throw SkillToolError.failure("the attempt ledger \(displaySafeInvisible(path, max: 400)) is not a regular file — refusing to read it")
        }
        return try entries(in: try readAll(fd))
    }

    /// 同一個主機、與 `now` 同一個 Asia/Taipei 日曆日的嘗試次數。
    public func count(site: String, on now: Date) throws -> Int {
        let site = Self.siteName(site)
        let day = Self.taipeiDay(now)
        return try load().filter { $0.site == site && Self.taipeiDay($0.at) == day }.count
    }

    /// 查數與記錄是一步：在跨行程的獨占鎖之下重讀帳本、數今天這個站的次數，沒到 `cap` 就記一筆（`O_APPEND`，一次 `write`；
    /// 目錄 0700、檔 0600）。到上限時什麼都不寫。帳本位置是 symlink 或不是普通檔時拒絕；帳本讀不懂時拒絕。
    public func reserve(site: String, landing: String, at now: Date, cap: Int = FulltextAttemptLedger.dailyCap) throws -> Reservation {
        let site = Self.siteName(site)
        return try withLockedFile { fd, existing in
            let day = Self.taipeiDay(now)
            let used = try entries(in: existing).filter { $0.site == site && Self.taipeiDay($0.at) == day }.count
            afterRead?()
            if used >= cap { return .capReached(used: used) }
            try writeRecord(fd, existing: existing, site: site, landing: landing, at: now)
            return .granted(used: used + 1)
        }
    }

    /// 無條件記一次嘗試（同樣在鎖之下、同樣補檔尾換行）。帳本位置是 symlink 或不是普通檔時拒絕。
    public func append(site: String, landing: String, at now: Date) throws {
        let site = Self.siteName(site)
        try withLockedFile { fd, existing in
            try writeRecord(fd, existing: existing, site: site, landing: landing, at: now)
        }
    }

    // MARK: 鎖與讀寫

    /// 開帳本（建目錄 0700、檔 0600、不跟隨 symlink）、取獨占鎖、讀出現有內容、交給 `body`；`body` 結束後關檔（放鎖）。
    private func withLockedFile<T>(_ body: (_ fd: Int32, _ existing: Data) throws -> T) throws -> T {
        let dir = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw SkillToolError.failure("cannot create the attempt ledger's folder \(displaySafeInvisible(dir, max: 400)): \(displaySafeErrorText(error))")
        }
        let fd = open(path, O_RDWR | O_APPEND | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard fd >= 0 else {
            throw SkillToolError.failure("cannot write the attempt ledger \(displaySafeInvisible(path, max: 400)): \(displaySafeInvisible(String(cString: strerror(errno)), max: 200))")
        }
        defer { close(fd) }   // 關檔放鎖
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else {
            throw SkillToolError.failure("the attempt ledger \(displaySafeInvisible(path, max: 400)) is not a regular file — refusing to write it")
        }
        guard flock(fd, LOCK_EX) == 0 else {
            throw SkillToolError.failure("cannot lock the attempt ledger \(displaySafeInvisible(path, max: 400)): \(displaySafeInvisible(String(cString: strerror(errno)), max: 200))")
        }
        return try body(fd, try readAll(fd))
    }

    private func readAll(_ fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = pread(fd, &buffer, buffer.count, off_t(data.count))
            if n < 0 {
                if errno == EINTR { continue }
                throw SkillToolError.failure("cannot read the attempt ledger \(displaySafeInvisible(path, max: 400)): \(displaySafeInvisible(String(cString: strerror(errno)), max: 200))")
            }
            if n == 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }

    private func writeRecord(_ fd: Int32, existing: Data, site: String, landing: String, at now: Date) throws {
        let object: [String: String] = ["at": Self.timestamp(now), "site": site, "landing": landing]
        let json = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        // 檔尾不是換行（手改過、編輯器沒補）：先補一個，免得新的一筆黏在舊的一筆後面
        let needsNewline = existing.last.map { $0 != 0x0A } ?? false
        let line = (needsNewline ? Data("\n".utf8) : Data()) + json + Data("\n".utf8)
        let written = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == line.count else {
            throw SkillToolError.failure("cannot write the attempt ledger \(displaySafeInvisible(path, max: 400)): \(displaySafeInvisible(String(cString: strerror(errno)), max: 200))")
        }
    }

    /// 帳本內容 → 每一筆。以**位元組**切行（`\r\n` 在 Swift 的 `Character` 是一個字元，切 `"\n"` 對 CRLF 的檔完全不切）；每行去掉頭尾的
    /// 空白與換行；空行略過；有一行讀不懂就整個拒絕。
    func entries(in data: Data) throws -> [Entry] {
        var result: [Entry] = []
        for (i, raw) in data.split(separator: 0x0A, omittingEmptySubsequences: false).enumerated() {
            let text = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            guard let entry = Self.parse(text) else {
                throw SkillToolError.failure("the attempt ledger \(displaySafeInvisible(path, max: 400)) line \(i + 1) is not {\"at\": <ISO 8601 with an explicit offset>, \"site\": <host>} — fix that line (do not delete the ledger or its other lines: a missing line lowers today's count); today's count cannot be trusted until then")
            }
            result.append(entry)
        }
        return result
    }

    // MARK: 時間

    /// `2026-10-01T14:03:22+08:00`：Asia/Taipei、帶明確的偏移（全域 CLAUDE.md〈時區〉：寫進檔案的時間值一律帶 offset）。
    public static func timestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = timeZone
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// Asia/Taipei 的日曆日（`yyyy-MM-dd`）。
    public static func taipeiDay(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 一行帳本。`at` 必須帶明確的偏移（`Z` 或 `±hh:mm`）——沒有偏移的時間不知道是哪一天。
    static func parse(_ line: String) -> Entry? {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
              let at = obj["at"] as? String, let raw = obj["site"] as? String, case let site = siteName(raw), !site.isEmpty,
              hasExplicitOffset(at) else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        guard let date = f.date(from: at) else { return nil }
        return Entry(at: date, site: site)
    }

    /// 站名的比較形：去頭尾空白、小寫。寫入、查數、讀回都過它——先前只在讀回時小寫，`reserve(site: "UP.example")` 比對的是原樣的字串，
    /// 上限從未生效（#613 R2 verify 第 26 則）；讀回時也不去空白，手改的 `" pub.example "` 算成另一個站（第 30 則）。少算正是上限要擋的方向。
    static func siteName(_ site: String) -> String { site.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    static func hasExplicitOffset(_ at: String) -> Bool {
        at.range(of: #"(Z|[+-][0-9]{2}:[0-9]{2})$"#, options: .regularExpression) != nil
    }
}
