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
        // 平面 YAML subset（documented）：頂層 key: value、files: 的一層縮排 mapping、
        // # 註解（保留於 unknownLines）。不支援 quoted 多行/anchor 等進階 YAML。
        func cleanValue(_ raw: String) -> String {
            var s = raw
            // quoted：整段引號內容為值（含 #）；unquoted：「 #」起為 inline comment（R2）
            if s.count >= 2, (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
                return String(s.dropFirst().dropLast())
            }
            if let range = s.range(of: " #") {
                s = String(s[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            return s
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
            inFiles = false
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            let key = parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            let value = parts.count == 2 ? cleanValue(parts[1].trimmingCharacters(in: .whitespaces)) : ""
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
