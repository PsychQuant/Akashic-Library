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
    /// explicit / env 兩條路徑沒有 key（未註冊），legacy `library:` 亦然。
    public struct Resolved: Equatable {
        public let root: URL
        public let key: String?
        public init(root: URL, key: String?) { self.root = root; self.key = key }
    }

    /// 既有簽章保留——只要 root 的呼叫端不必改。
    public static func resolve(
        explicit: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configURL: URL = AkashicHome.configURL()
    ) throws -> URL {
        try resolveDetailed(explicit: explicit, environment: environment,
                            configURL: configURL).root
    }

    public static func resolveDetailed(
        explicit: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configURL: URL = AkashicHome.configURL()
    ) throws -> Resolved {
        if let explicit, !explicit.isEmpty {
            return Resolved(root: URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath),
                            key: nil)
        }
        if let env = environment["AKASHIC_LIBRARY"], !env.isEmpty {
            return Resolved(root: URL(fileURLWithPath: (env as NSString).expandingTildeInPath),
                            key: nil)
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
    /// 「這個 root 是可用的 Akashic library 嗎」——entries 必須存在**且是目錄**
    /// （普通檔案冒充 entries 會過 fileExists，R2 #3）。三面（CLI/MCP/App）共用。
    static func isLibraryRoot(_ root: URL) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: root.appendingPathComponent("entries").path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }
}
