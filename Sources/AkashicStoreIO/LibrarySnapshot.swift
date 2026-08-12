import Foundation
import CryptoKit
import AkashicCore

/// 一個 store 的持久化化身身分。它回答「哪一個 store」，不回答內容版本。
public struct StoreIdentity: Equatable, Hashable, Sendable {
    public let uuid: UUID

    init(uuid: UUID) {
        self.uuid = uuid
    }
}

/// 從 canonical bytes 推導的內容版本。
public struct StoreRevision: Equatable, Hashable, Sendable {
    public let digest: String

    init(digest: String) {
        self.digest = digest
    }

    /// Versioned、domain-separated、結構化 framing。identity 不另行混進來；
    /// incarnation 若在 captured records 中，視同其他原始 canonical bytes 被雜湊。
    static func derive(from records: [CapturedCanonicalRecord]) -> StoreRevision {
        var hasher = SHA256()
        hasher.update(data: Data("Akashic-Library.StoreRevision\u{0}v1\u{0}".utf8))
        update(UInt64(records.count), in: &hasher)

        for record in records.sorted(by: { rawUTF8Less($0.path, $1.path) }) {
            let pathBytes = Data(record.path.utf8)
            update(UInt64(pathBytes.count), in: &hasher)
            hasher.update(data: pathBytes)
            update(UInt64(record.bytes.count), in: &hasher)
            hasher.update(data: record.bytes)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return StoreRevision(digest: "sha256:\(digest)")
    }

    private static func update(_ value: UInt64, in hasher: inout SHA256) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { buffer in
            hasher.update(data: Data(buffer))
        }
    }
}

/// 同時固定 store 化身與那個化身的一份內容。
public struct StoreSnapshotID: Equatable, Hashable, Sendable {
    public let store: StoreIdentity
    public let revision: StoreRevision

    init(store: StoreIdentity, revision: StoreRevision) {
        self.store = store
        self.revision = revision
    }
}

/// 一次可信載入的唯讀結果。production caller 只能由 `LibraryStore.loadSnapshot()` 取得。
public struct LibrarySnapshot {
    public let id: StoreSnapshotID
    public let load: LibraryLoad

    init(id: StoreSnapshotID, load: LibraryLoad) {
        self.id = id
        self.load = load
    }
}

/// Snapshot 邊界只公開有限、無 caller-controlled associated payload 的錯誤種類。
/// 這避免一般 `String(describing:)` 以 enum reflection 繞過 displaySafe。
public enum StoreSnapshotError: Error, LocalizedError, Equatable, CustomStringConvertible {
    case missingIncarnation
    case unreadableIncarnation
    case malformedIncarnation
    case unreadableCanonicalStore
    case changedDuringCapture

    public var errorDescription: String? {
        switch self {
        case .missingIncarnation:
            return "store 缺少必要的 incarnation，無法建立可信 snapshot；不會以路徑代替身分，也不會自動建立"
        case .unreadableIncarnation:
            return "store incarnation 存在但讀不到或不是 UTF-8，無法建立可信 snapshot"
        case .malformedIncarnation:
            return "store incarnation 必須只包含一個 canonical UUID，無法建立可信 snapshot"
        case .unreadableCanonicalStore:
            return "canonical store 的目錄或檔案在擷取時讀不到，無法建立可信 snapshot"
        case .changedDuringCapture:
            return "canonical store 在最多三次擷取 pass 內沒有出現相鄰相同內容，無法建立一致的 snapshot"
        }
    }

    public var description: String { errorDescription ?? "StoreSnapshotError" }
}

/// 一筆被 loader 實際消費的 relative path 與原始 bytes。
struct CapturedCanonicalRecord: Equatable {
    let path: String
    let bytes: Data

    static func == (lhs: CapturedCanonicalRecord, rhs: CapturedCanonicalRecord) -> Bool {
        Data(lhs.path.utf8) == Data(rhs.path.utf8) && lhs.bytes == rhs.bytes
    }
}

/// 單次 capture 的完整可比較值。marker／incarnation 保留 optional presence，
/// YAML 則保留完整 path inventory，讓增刪檔案也會使相鄰比較失敗。
struct CapturedCanonicalStore: Equatable {
    let markerBytes: Data?
    let incarnationBytes: Data?
    let yamlRecords: [CapturedCanonicalRecord]

    var digestRecords: [CapturedCanonicalRecord] {
        var records: [CapturedCanonicalRecord] = []
        if let markerBytes {
            records.append(CapturedCanonicalRecord(path: StoreVersion.fileName, bytes: markerBytes))
        }
        if let incarnationBytes {
            records.append(CapturedCanonicalRecord(
                path: StoreIncarnation.fileName, bytes: incarnationBytes))
        }
        records.append(contentsOf: yamlRecords)
        return records
    }
}

/// Canonical path identity is its raw UTF-8 bytes, not Swift String's Unicode-normalized equality.
func rawUTF8Less(_ lhs: String, _ rhs: String) -> Bool {
    lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
}

public extension LibraryStore {
    /// 取得兩份相鄰相同的 canonical capture 後，才建立可信 snapshot。
    func loadSnapshot() throws -> LibrarySnapshot {
        try loadSnapshot(capture: captureCanonicalStore)
    }
}

extension LibraryStore {
    /// Internal deterministic seam：public production API 與 tests 都跑同一個三-pass 演算法。
    /// 三次是**總 pass 數**：A→B→B 接受 B；A→B→C 立即 fail closed，不做第四次。
    func loadSnapshot(
        capture: () throws -> CapturedCanonicalStore
    ) throws -> LibrarySnapshot {
        var previous = try capture()
        for _ in 1..<3 {
            let current = try capture()
            if current == previous {
                return try snapshot(from: current)
            }
            previous = current
        }
        throw StoreSnapshotError.changedDuringCapture
    }

    /// 單次 filesystem capture；接受之後，decode 與 digest 都只使用回傳值。
    func captureCanonicalStore() throws -> CapturedCanonicalStore {
        let fm = FileManager.default

        func optionalBytes(at url: URL, incarnation: Bool = false) throws -> Data? {
            guard fm.fileExists(atPath: url.path) else { return nil }
            do {
                return try Data(contentsOf: url)
            } catch {
                throw incarnation
                    ? StoreSnapshotError.unreadableIncarnation
                    : StoreSnapshotError.unreadableCanonicalStore
            }
        }

        let marker = try optionalBytes(at: StoreVersion.url(in: root))
        let incarnation = try optionalBytes(
            at: StoreIncarnation.url(in: root), incarnation: true)
        var records: [CapturedCanonicalRecord] = []
        for directory in ["entities", "entries", "people", "libraries"] {
            let dir = root.appendingPathComponent(directory)
            guard fm.fileExists(atPath: dir.path) else { continue }
            let urls: [URL]
            do {
                urls = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            } catch {
                throw StoreSnapshotError.unreadableCanonicalStore
            }
            for url in urls where url.pathExtension.lowercased() == "yaml"
                && !url.lastPathComponent.hasPrefix(".") {
                let bytes: Data
                do {
                    bytes = try Data(contentsOf: url)
                } catch {
                    throw StoreSnapshotError.unreadableCanonicalStore
                }
                records.append(CapturedCanonicalRecord(
                    path: "\(directory)/\(url.lastPathComponent)", bytes: bytes))
            }
        }
        records.sort { rawUTF8Less($0.path, $1.path) }
        return CapturedCanonicalStore(
            markerBytes: marker,
            incarnationBytes: incarnation,
            yamlRecords: records)
    }

    private func snapshot(from capture: CapturedCanonicalStore) throws -> LibrarySnapshot {
        let rawIdentity: String
        do {
            guard let parsed = try StoreIncarnation.parse(
                data: capture.incarnationBytes,
                path: StoreIncarnation.url(in: root).path) else {
                throw StoreSnapshotError.missingIncarnation
            }
            rawIdentity = parsed
        } catch let snapshotError as StoreSnapshotError {
            throw snapshotError
        } catch let incarnationError as StoreIncarnationError {
            switch incarnationError {
            case .unreadable:
                throw StoreSnapshotError.unreadableIncarnation
            case .malformed:
                throw StoreSnapshotError.malformedIncarnation
            }
        }
        guard let uuid = UUID(uuidString: rawIdentity) else {
            throw StoreSnapshotError.malformedIncarnation
        }

        let revision = StoreRevision.derive(from: capture.digestRecords)
        let decoded = try decodeCaptured(capture)
        return LibrarySnapshot(
            id: StoreSnapshotID(store: StoreIdentity(uuid: uuid), revision: revision),
            load: decoded)
    }
}
