import Foundation
import AkashicCore

public enum ConfigError: Error, LocalizedError {
    case invalidFileKey(String)
    case invalidCurrent(String)
    case invalidViewKey(String)
    case invalidViewField(view: String, field: String, value: String)
    /// 同一正規路徑被 ≥ 2 個 key 註冊（#105/#121）——registry 損壞，反查不猜。
    case duplicateRegistration(path: String, keys: [String])

    public var errorDescription: String? {
        switch self {
        case .invalidFileKey(let key):
            return "config.yaml 的 files key「\(displaySafe(key, max: 200))」不合法（小寫英數起頭、僅 a-z0-9- ）"
        case let .duplicateRegistration(path, keys):
            return "路徑「\(displaySafe(path, max: 300))」被多個 key 註冊（\(keys.map { displaySafe($0, max: 200) }.joined(separator: ", "))）"
                 + "——同一實體庫不重複註冊；用 file remove 清掉多餘的再試"
        case .invalidViewKey(let key):
            return "view key「\(displaySafe(key, max: 200))」不符合 \(StoreKey.pattern)"   // display-safe-exempt: pattern 是編譯期常量（同 LibraryStore 的 invalidKey）
        case let .invalidViewField(view, field, value):
            return "view「\(displaySafe(view, max: 200))」的 \(displaySafe(field, max: 60))"
                + "「\(displaySafe(value, max: 200))」不合法"
        case .invalidCurrent(let key):
            return "config.yaml 的 current「\(displaySafe(key, max: 200))」不在 files registry 中"
        }
    }
}

/// `~/.akashic/config.yaml` 的平面 model（#18 多檔案）。
/// 三欄皆 optional；本 schema 之外的頂層行在 write 時原樣保留。
public struct AkashicConfig: Equatable {
    public var library: String?
    public var files: [String: String]
    public var current: String?
    /// view 的**判準**（#54／#65）。外延是衍生物、不在這裡。
    ///
    /// 住在 `config.yaml` 是 `docs/explainers/entity-vs-view.md` 拍板的位置：
    /// **它是設定，不是知識**——所以與 `library`／`files`／`current` 同層，而不是
    /// 進 `entities/`。**view 不是 entity**，這個欄位不改變那件事。
    public var views: [String: ViewDefinition] = [:]
    /// 不認得的頂層原始行（保序），write 時原樣寫回——不破壞使用者手寫內容。
    public var unknownLines: [String]

    public init(library: String? = nil, files: [String: String] = [:],
                current: String? = nil, unknownLines: [String] = []) {
        self.library = library
        self.files = files
        self.current = current
        self.unknownLines = unknownLines
    }

    /// 檔案不存在 → 空 config（首次 `file add` 的正常起點）。
    /// 檔案存在但讀不到（權限/編碼）→ 擲錯——絕不能把暫時性讀失敗當空 config，
    /// 否則後續 read-modify-write 會整檔覆寫、靜默清空既有 registry（verify R1）。
    public static func read(from url: URL) throws -> AkashicConfig {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            // 嚴格只認「檔案不存在」；權限/編碼/其他讀失敗全部重拋（R2 #2）
            return AkashicConfig()
        }
        var config = AkashicConfig()
        var inFiles = false
        // views: 的兩層縮排——`  <key>:` 開一個 view，`    <field>: <value>` 是它的欄位。
        // 與 `files:` 的一層平面 mapping 不同，所以要記住「現在在哪個 view 裡」。
        var inViews = false
        var currentView: String? = nil
        // 平面 YAML subset（documented）：頂層 key: value、files: 的一層縮排 mapping、
        // # 註解（保留於 unknownLines）。不支援 quoted 多行/anchor 等進階 YAML。
        func cleanValue(_ raw: String) -> String {
            // quoted：讀到配對收尾引號為止（引號內 # 為字面值；引號後可跟 inline comment）；
            // unquoted：「 #」起為 inline comment（R2/R3——與 writer 的按需加引號對稱）
            if let q = raw.first, q == "\"" || q == "'" {
                let body = raw.dropFirst()
                if let end = body.firstIndex(of: q) {
                    return String(body[..<end])
                }
            }
            if let range = raw.range(of: " #") {
                return String(raw[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            return raw
        }
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#") {
                // 註解保留（round-trip 不丟使用者手寫內容；位置歸尾端，內容不失）
                config.unknownLines.append(line)
                continue
            }

            if (line.first == " " || line.first == "\t") && inViews {
                let indent = line.prefix { $0 == " " || $0 == "\t" }.count
                // **`omittingEmptySubsequences` 預設是 true**：`"iss:"` 只切出
                // `["iss"]`，不是 `["iss", ""]`。view key 那一行**本來就沒有值**，
                // 用 `count == 2` 當 guard 會把它整行丟進 unknownLines——
                // 那正是第一版的症狀（views 區塊完全沒被 parse，而且無聲）。
                let parts = trimmed.split(separator: ":", maxSplits: 1,
                                          omittingEmptySubsequences: false)
                guard parts.count == 2 else { config.unknownLines.append(line); continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = cleanValue(parts[1].trimmingCharacters(in: .whitespaces))
                if indent <= 2 {
                    // 新的 view。key 走 StoreKey——view key 會出現在 CLI 旗標與檔名裡
                    guard StoreKey.isValid(key) else { throw ConfigError.invalidViewKey(key) }
                    currentView = key
                    config.views[key] = ViewDefinition(key: key)
                    continue
                }
                guard let vk = currentView, var v = config.views[vk] else {
                    config.unknownLines.append(line); continue
                }
                switch key {
                case "description": if !value.isEmpty { v.description = value }
                case "person-affiliation":
                    // **只收 organization key**——未歸戶的 literal 當判準會讓成員
                    // 資格隨拼寫漂移（見 ViewDefinition 的 doc）
                    guard value.isEmpty || StoreKey.isValid(value) else {
                        throw ConfigError.invalidViewField(view: vk, field: key, value: value)
                    }
                    if !value.isEmpty { v.personAffiliation = value }
                case "work-has-author-in-view":
                    guard ["true", "false"].contains(value) else {
                        throw ConfigError.invalidViewField(view: vk, field: key, value: value)
                    }
                    v.workHasAuthorInView = (value == "true")
                default: config.unknownLines.append(line); continue
                }
                config.views[vk] = v
                continue
            }
            if (line.first == " " || line.first == "\t") && inFiles {
                // files: 區塊內的一層縮排 mapping
                let parts = trimmed.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { config.unknownLines.append(line); continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let path = cleanValue(parts[1].trimmingCharacters(in: .whitespaces))
                guard StoreKey.isValid(key) else { throw ConfigError.invalidFileKey(key) }
                if !path.isEmpty { config.files[key] = path }
                continue
            }

            // 頂層（含縮排的頂層 key——舊版 locator 對 library: 做 trim 掃描，
            // 縮排寫法曾是合法的；維持向後相容，Codex R1 #6）
            inFiles = false; inViews = false; currentView = nil
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            let key = parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            let value = parts.count == 2 ? cleanValue(parts[1].trimmingCharacters(in: .whitespaces)) : ""
            switch key {
            case "library": if !value.isEmpty { config.library = value }
            case "current": if !value.isEmpty { config.current = value }
            case "files": inFiles = true
            case "views": inViews = true
            default: config.unknownLines.append(line)
            }
        }
        return config
    }

    /// 值含「 #」/首尾空白/引號起頭時按需加引號——與 parser 的 cleanValue 對稱，
    /// round-trip 不截斷（R3）。引號字元挑值裡沒有的那種；兩種都有屬病態路徑，
    /// 落 documented limitation（spec YAML subset 段）。
    static func serializeScalar(_ value: String) -> String {
        let needsQuoting = value.contains(" #") || value.hasPrefix("\"") || value.hasPrefix("'")
            || value != value.trimmingCharacters(in: .whitespaces)
        guard needsQuoting else { return value }
        if !value.contains("\"") { return "\"\(value)\"" }
        if !value.contains("'") { return "'\(value)'" }
        return "\"\(value)\""   // 病態（同時含兩種引號）：documented limitation
    }

    /// 整檔重寫：library → files（key 排序）→ current → 未知行（保序附尾）。
    public func write(to url: URL) throws {
        var lines: [String] = []
        if let library { lines.append("library: \(Self.serializeScalar(library))") }
        if !files.isEmpty {
            lines.append("files:")
            for key in files.keys.sorted() {
                lines.append("  \(key): \(Self.serializeScalar(files[key]!))")
            }
        }
        if !views.isEmpty {
            lines.append("views:")
            for key in views.keys.sorted() {
                let v = views[key]!
                lines.append("  \(key):")
                if let d = v.description { lines.append("    description: \(Self.serializeScalar(d))") }
                if let a = v.personAffiliation { lines.append("    person-affiliation: \(a)") }
                if v.workHasAuthorInView { lines.append("    work-has-author-in-view: true") }
            }
        }
        if let current { lines.append("current: \(Self.serializeScalar(current))") }
        lines.append(contentsOf: unknownLines)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// 路徑的正規形（#105 verify）：tilde 展開 + `standardizedFileURL` + **解析
    /// symlink**（`resolvingSymlinksInPath`——同時把 `/private` 前綴與 APFS 上的
    /// 大小寫正規化到磁碟實際形）。
    ///
    /// 為什麼要解析 symlink：`~/Dropbox` 在本機就是 symlink → `~/Library/
    /// CloudStorage/Dropbox`，而「store 在 Dropbox 裡」正是 index 外移的初衷場景
    /// ——只比 standardized path 會讓最需要反查的部署形態反查失敗，
    /// 在已註冊的 store 裡長出 `.akashic/`。路徑不存在時 `resolvingSymlinksInPath`
    /// 原樣保留該段，仍是決定性的。
    static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// registry 反查（#105，in-memory）：對**已載入**的 config 比對——`file add`
    /// 用這個，不做第二次讀檔（#121 verify Codex：TOCTOU + 二讀失敗被當成無重複）。
    ///
    /// **≥ 2 個 key 命中同一正規路徑 → 擲錯**（#121 verify H2：`Dictionary.first`
    /// 每個 process 的雜湊種子不同，同 store 反查結果會逐次交替、交替寫兩份 index
    /// ——正是 #105 的靶心以不可重現的形式回歸）。重複註冊是 registry 損壞，
    /// 修它，不猜它。
    public static func key(forPath path: String, in config: AkashicConfig) throws -> String? {
        let target = canonicalPath(path)
        let hits = config.files.filter { canonicalPath($0.value) == target }.keys.sorted()
        guard hits.count <= 1 else {
            throw ConfigError.duplicateRegistration(path: path, keys: hits)
        }
        return hits.first
    }

    /// registry 反查（#105，讀檔版）：resolveDetailed 用。
    ///
    /// **只有「config 檔不存在」降級成 nil**（explicit path 的解析不依賴 registry
    /// 存在）；malformed／權限／I/O 錯誤**往上拋**（#121 verify Codex：`try?` 會把
    /// 「registry 壞掉」當成「未註冊」，在已註冊的 store 裡靜默寫第二份 index，
    /// 且使用者拿不到任何 registry 損壞的診斷）。
    public static func key(forPath path: String, configURL: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: configURL.path) else { return nil }
        let config = try AkashicConfig.read(from: configURL)
        return try key(forPath: path, in: config)
    }

    // `defaultURL` 已移除（#110）：它寫死真實家目錄、不認 `AKASHIC_HOME`，與
    // env-aware 的 `AkashicHome.configURL(environment:)` 並存時，「registry 在哪」
    // 在同一支程式裡有兩個答案——`file add` 寫進真實 registry 而 doctor 讀 override
    // home 的。移除而非修正，理由與 #101 移除 `resolveRoot()` 同構：**少一個能繞過
    // env 解析的入口，比修 N 個呼叫點可靠**（編譯器保證零漏網）。
}
