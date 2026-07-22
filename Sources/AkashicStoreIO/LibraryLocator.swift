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

/// Library root 解析：explicit → $AKASHIC_LIBRARY → ~/.akashic/config.yaml。
/// CLI 與 akashic-mcp 共用（config 驅動、無寫死路徑）。
public enum LibraryLocator {
    public static func resolve(
        explicit: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".akashic/config.yaml")
    ) throws -> URL {
        if let explicit, !explicit.isEmpty {
            return URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath)
        }
        if let env = environment["AKASHIC_LIBRARY"], !env.isEmpty {
            return URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
        }
        if let content = try? String(contentsOf: configURL, encoding: .utf8) {
            for line in content.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "library" {
                    let path = parts[1].trimmingCharacters(in: .whitespaces)
                    if !path.isEmpty {
                        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                    }
                }
            }
        }
        throw LocatorError.notConfigured
    }
}
