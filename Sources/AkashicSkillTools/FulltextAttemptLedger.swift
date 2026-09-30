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
/// 每行一筆 JSON：`{"at": "<ISO 8601，帶 +08:00>", "site": "<主機>", "landing": "<--landing>"}`。
///
/// **讀不懂就拒絕（fail-closed）**：檔案存在但讀不了、不是普通檔（symlink、目錄）、有一行不是這個形狀、`at` 沒有明確的時區
/// ——一律丟具名錯誤，`fetch` 在碰瀏覽器之前停下。數不出今天的次數，就不能保證沒超過上限。
public struct FulltextAttemptLedger {
    public static let dailyCap = 10
    public static let timeZone = TimeZone(identifier: "Asia/Taipei")!

    public let path: String

    public init(path: String) { self.path = path }

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
        guard let data = FileManager.default.contents(atPath: path) else {
            throw SkillToolError.failure("cannot read the attempt ledger \(displaySafeInvisible(path, max: 400))")
        }
        var entries: [Entry] = []
        for (i, line) in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            guard let entry = Self.parse(text) else {
                throw SkillToolError.failure("the attempt ledger \(displaySafeInvisible(path, max: 400)) line \(i + 1) is not {\"at\": <ISO 8601 with an explicit offset>, \"site\": <host>} — fix or remove that line; today's count cannot be trusted until then")
            }
            entries.append(entry)
        }
        return entries
    }

    /// 同一個主機、與 `now` 同一個 Asia/Taipei 日曆日的嘗試次數。
    public func count(site: String, on now: Date) throws -> Int {
        let day = Self.taipeiDay(now)
        return try load().filter { $0.site == site && Self.taipeiDay($0.at) == day }.count
    }

    /// 記一次嘗試（`O_APPEND`，一次 `write`；目錄 0700、檔 0600）。帳本位置是 symlink 或不是普通檔時拒絕。
    public func append(site: String, landing: String, at now: Date) throws {
        let dir = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw SkillToolError.failure("cannot create the attempt ledger's folder \(displaySafeInvisible(dir, max: 400)): \(displaySafeErrorText(error))")
        }
        let object: [String: String] = ["at": Self.timestamp(now), "site": site, "landing": landing]
        let json = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        let line = json + Data("\n".utf8)
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else {
            throw SkillToolError.failure("cannot write the attempt ledger \(displaySafeInvisible(path, max: 400)): \(displaySafeInvisible(String(cString: strerror(errno)), max: 200))")
        }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else {
            throw SkillToolError.failure("the attempt ledger \(displaySafeInvisible(path, max: 400)) is not a regular file — refusing to write it")
        }
        let written = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == line.count else {
            throw SkillToolError.failure("cannot write the attempt ledger \(displaySafeInvisible(path, max: 400)): \(displaySafeInvisible(String(cString: strerror(errno)), max: 200))")
        }
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
              let at = obj["at"] as? String, let site = obj["site"] as? String, !site.isEmpty,
              hasExplicitOffset(at) else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        guard let date = f.date(from: at) else { return nil }
        return Entry(at: date, site: site)
    }

    static func hasExplicitOffset(_ at: String) -> Bool {
        at.range(of: #"(Z|[+-][0-9]{2}:[0-9]{2})$"#, options: .regularExpression) != nil
    }
}
