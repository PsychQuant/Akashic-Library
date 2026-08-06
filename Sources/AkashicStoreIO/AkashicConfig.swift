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
        if let current { lines.append("current: \(Self.serializeScalar(current))") }
        lines.append(contentsOf: unknownLines)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // `defaultURL` 已移除（#110）：它寫死真實家目錄、不認 `AKASHIC_HOME`，與
    // env-aware 的 `AkashicHome.configURL(environment:)` 並存時，「registry 在哪」
    // 在同一支程式裡有兩個答案——`file add` 寫進真實 registry 而 doctor 讀 override
    // home 的。移除而非修正，理由與 #101 移除 `resolveRoot()` 同構：**少一個能繞過
    // env 解析的入口，比修 N 個呼叫點可靠**（編譯器保證零漏網）。
}
