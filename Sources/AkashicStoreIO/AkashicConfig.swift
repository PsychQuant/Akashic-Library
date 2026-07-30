import Foundation
import AkashicCore

public enum ConfigError: Error, LocalizedError {
    case invalidFileKey(String)
    case invalidCurrent(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFileKey(let key):
            return "config.yaml 的 files key「\(key)」不合法（小寫英數起頭、僅 a-z0-9- ）"
        case .invalidCurrent(let key):
            return "config.yaml 的 current「\(key)」不在 files registry 中"
        }
    }
}

/// `~/.akashic/config.yaml` 的平面 model（#18 多檔案）。
/// 三欄皆 optional；本 schema 之外的頂層行在 write 時原樣保留。
public struct AkashicConfig: Equatable {
    public var library: String?
    public var files: [String: String]
    public var current: String?
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
    public static func read(from url: URL) throws -> AkashicConfig {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return AkashicConfig()
        }
        var config = AkashicConfig()
        var inFiles = false
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if line.first == " " || line.first == "\t" {
                // 縮排行：只在 files: 區塊內有意義
                guard inFiles else { config.unknownLines.append(line); continue }
                let parts = trimmed.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else { config.unknownLines.append(line); continue }
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let path = parts[1].trimmingCharacters(in: .whitespaces)
                guard StoreKey.isValid(key) else { throw ConfigError.invalidFileKey(key) }
                if !path.isEmpty { config.files[key] = path }
                continue
            }

            inFiles = false
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            let key = parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            let value = parts.count == 2 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
            switch key {
            case "library": if !value.isEmpty { config.library = value }
            case "current": if !value.isEmpty { config.current = value }
            case "files": inFiles = true
            default: config.unknownLines.append(line)
            }
        }
        return config
    }

    /// 整檔重寫：library → files（key 排序）→ current → 未知行（保序附尾）。
    public func write(to url: URL) throws {
        var lines: [String] = []
        if let library { lines.append("library: \(library)") }
        if !files.isEmpty {
            lines.append("files:")
            for key in files.keys.sorted() {
                lines.append("  \(key): \(files[key]!)")
            }
        }
        if let current { lines.append("current: \(current)") }
        lines.append(contentsOf: unknownLines)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// 預設 config 路徑（CLI/MCP/App 共用）。
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".akashic/config.yaml")
    }
}
