import Foundation

public enum LocatorError: Error, LocalizedError {
    case notConfigured

    public var errorDescription: String? {
        """
        找不到 library root。三選一：
          1) 明確傳入路徑（CLI --library / MCP 設定）
          2) export AKASHIC_LIBRARY=<path>
          3) ~/.akashic/config.yaml 寫入「library: <path>」
        """
    }
}

/// Library root 解析：explicit → $AKASHIC_LIBRARY → config current+files → config library（legacy）。
/// CLI 與 akashic-mcp 共用（config 驅動、無寫死路徑）。
public enum LibraryLocator {
    /// 解析結果——`key` 是 registry key（#37：index 位置需要它）。
    /// #105 之後 explicit / env 路徑會反查 registry（canonical 比對，含 symlink 解析）
    /// ——已註冊就帶 key；未註冊與 legacy `library:` 才是 nil。
    public struct Resolved: Equatable {
        public let root: URL
        public let key: String?
        public init(root: URL, key: String?) { self.root = root; self.key = key }
    }

    /// 既有簽章保留——只要 root 的呼叫端不必改。
    public static func resolve(
        explicit: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configURL: URL? = nil
    ) throws -> URL {
        try resolveDetailed(explicit: explicit, environment: environment,
                            configURL: configURL).root
    }

    public static func resolveDetailed(
        explicit: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configURL: URL? = nil
    ) throws -> Resolved {
        // **configURL 與 environment 必須同源**（#110 verify）：舊預設
        // `AkashicHome.configURL()` 讀 process env，不看本函式的 `environment:` 參數
        // ——測試注入 fake env 時 registry 仍解析到真實 home，正是 #110 要消滅的
        // 「兩個答案」的同構殘留。預設值改為由同一份 environment 推導。
        let configURL = configURL ?? AkashicHome.configURL(environment: environment)
        // **explicit / env 路徑反查 registry**（#105，使用者拍板）：`--library` 的語意是
        // 「指定一個 store」不是「繞過 registry」。路徑已註冊就把 key 帶回來——同一個
        // store 不因開法不同而有兩份會漂移的 index（#101 實測過的病）。未註冊或 config
        // 缺失 → 維持 keyless fallback。
        if let explicit, !explicit.isEmpty {
            return Resolved(root: URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath),
                            key: try AkashicConfig.key(forPath: explicit, configURL: configURL))
        }
        if let env = environment["AKASHIC_LIBRARY"], !env.isEmpty {
            return Resolved(root: URL(fileURLWithPath: (env as NSString).expandingTildeInPath),
                            key: try AkashicConfig.key(forPath: env, configURL: configURL))
        }
        let config = try AkashicConfig.read(from: configURL)
        // #18 多檔案：current + files registry 優先於 legacy library
        if let current = config.current {
            guard let path = config.files[current] else {
                throw ConfigError.invalidCurrent(current)
            }
            return Resolved(root: URL(fileURLWithPath: (path as NSString).expandingTildeInPath),
                            key: current)
        }
        if let path = config.library, !path.isEmpty {
            return Resolved(root: URL(fileURLWithPath: (path as NSString).expandingTildeInPath),
                            key: nil)
        }
        throw LocatorError.notConfigured
    }
}

public extension LibraryStore {
    /// 「這個 root 是可用的 Akashic library 嗎」——`entities/`（format 2）或
    /// `entries/`（legacy）任一存在**且是目錄**即可（普通檔案冒充會過 fileExists，R2 #3）。
    /// 三面（CLI / MCP / App）共用。
    ///
    /// **#35：必須認 `entities/`。** 只認 `entries/` 的話，遷移後的 store 在**新 clone**
    /// 上完全開不起來——`entries/` 是空目錄，git 不追蹤空目錄，所以 clone 出來根本沒有它。
    /// 這是 verify 抓到的 CRITICAL：已遷移的真實 store 換一台機器 clone 就用不了。
    static func isLibraryRoot(_ root: URL) -> Bool {
        func isDirectory(_ name: String) -> Bool {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: root.appendingPathComponent(name).path, isDirectory: &isDir)
            return exists && isDir.boolValue
        }
        return isDirectory("entities") || isDirectory("entries")
    }
}
