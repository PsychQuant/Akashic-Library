import Foundation
import AkashicCore

public enum StoreIOError: Error, LocalizedError, Equatable {
    case invalidKey(String, String)

    public var errorDescription: String? {
        switch self {
        case .invalidKey(let kind, let value):
            return "\(kind)「\(value)」不符合 \(StoreKey.pattern)，拒絕寫入"
        }
    }
}

public struct QuarantinedFile: Equatable {
    public var file: String
    public var reason: String

    public init(file: String, reason: String) {
        self.file = file
        self.reason = reason
    }
}

public struct LibraryLoad {
    public var entries: [Entry]
    public var people: [Person]
    public var quarantined: [QuarantinedFile]

    public init(entries: [Entry] = [], people: [Person] = [], quarantined: [QuarantinedFile] = []) {
        self.entries = entries
        self.people = people
        self.quarantined = quarantined
    }
}

/// 檔案為本的 library 存取層。canonical 是 entries/ 與 people/ 的 YAML；
/// .akashic/ 是可重建衍生物。所有寫入走 atomic（temp + rename）。
public final class LibraryStore {
    public let root: URL

    public var entriesDir: URL { root.appendingPathComponent("entries") }
    public var peopleDir: URL { root.appendingPathComponent("people") }
    public var notesDir: URL { root.appendingPathComponent("notes") }
    public var akashicDir: URL { root.appendingPathComponent(".akashic") }
    public var indexURL: URL { akashicDir.appendingPathComponent("index.sqlite") }

    public init(root: URL) {
        self.root = root
    }

    public func ensureLayout() throws {
        let fm = FileManager.default
        for dir in [root, entriesDir, peopleDir, notesDir, akashicDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    public func entryURL(citekey: String) -> URL {
        entriesDir.appendingPathComponent("\(citekey).yaml")
    }

    public func personURL(key: String) -> URL {
        peopleDir.appendingPathComponent("\(key).yaml")
    }

    @discardableResult
    public func writeEntry(_ entry: Entry) throws -> URL {
        // write-time key 驗證：不合格式的 citekey 絕不進檔名（path traversal 防護）
        guard StoreKey.isValid(entry.citekey) else {
            throw StoreIOError.invalidKey("citekey", entry.citekey)
        }
        let yaml = try EntryYAML.encode(entry)
        let dest = entryURL(citekey: entry.citekey)
        try atomicWrite(yaml, to: dest)
        return dest
    }

    @discardableResult
    public func writePerson(_ person: Person) throws -> URL {
        guard StoreKey.isValid(person.key) else {
            throw StoreIOError.invalidKey("person key", person.key)
        }
        let yaml = try PersonYAML.encode(person)
        let dest = personURL(key: person.key)
        try atomicWrite(yaml, to: dest)
        return dest
    }

    /// 掃描整個 library。schema 不合的檔案進 quarantined 報告，不靜默略過、
    /// 也不讓單一壞檔中斷整批載入。
    public func load() throws -> LibraryLoad {
        var result = LibraryLoad()
        for url in try yamlFiles(in: entriesDir) {
            do {
                result.entries.append(try EntryYAML.decode(try readUTF8(url)))
            } catch {
                result.quarantined.append(QuarantinedFile(
                    file: "entries/\(url.lastPathComponent)",
                    reason: String(describing: error)))
            }
        }
        for url in try yamlFiles(in: peopleDir) {
            do {
                result.people.append(try PersonYAML.decode(try readUTF8(url)))
            } catch {
                result.quarantined.append(QuarantinedFile(
                    file: "people/\(url.lastPathComponent)",
                    reason: String(describing: error)))
            }
        }
        result.entries.sort { $0.citekey < $1.citekey }
        result.people.sort { $0.key < $1.key }
        return result
    }

    // MARK: - Internals

    private func yamlFiles(in dir: URL) throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }
        // 副檔名比對大小寫不敏感：macOS 檔案系統多為 case-insensitive，
        // `.YAML` 檔是寫入目的檔的別名，必須被枚舉（否則連 quarantine 都進不了）
        return try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "yaml" && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func readUTF8(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// temp 檔寫在同一目錄 + rename 取代——中斷不留半寫檔。
    /// dest 不存在時 `replaceItemAt` 的行為在 Apple docs 未保證（實測可行），
    /// 防禦性改走 moveItem——兩條路徑都是同目錄 rename、同等原子性。
    private func atomicWrite(_ content: String, to dest: URL) throws {
        let fm = FileManager.default
        let tmp = dest.deletingLastPathComponent()
            .appendingPathComponent(".\(dest.lastPathComponent).tmp-\(UUID().uuidString)")
        try content.write(to: tmp, atomically: false, encoding: .utf8)
        do {
            if fm.fileExists(atPath: dest.path) {
                _ = try fm.replaceItemAt(dest, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: dest)
            }
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }
}

public struct RenameReport: Equatable {
    /// relations 有引用被改寫的 citekeys。
    public var relationsRewritten: [String]

    public init(relationsRewritten: [String] = []) {
        self.relationsRewritten = relationsRewritten
    }
}

extension LibraryStore {
    /// citekey rename（#4）：驗證 → 搬檔 → 全庫 relations 遷移 → 舊檔刪除。
    /// UUID 不變（雙 ID 的 rename 承諾至此真正成立）。呼叫端負責 reindex。
    @discardableResult
    public func renameEntry(from oldKey: String, to newKey: String) throws -> RenameReport {
        guard StoreKey.isValid(newKey) else {
            throw StoreIOError.invalidKey("citekey", newKey)
        }
        // 目的檔不可存在——含 quarantined 檔與 case-insensitive 別名
        guard !FileManager.default.fileExists(atPath: entryURL(citekey: newKey).path) else {
            throw StoreIOError.invalidKey("citekey（目的檔已存在）", newKey)
        }
        let load = try store_loadForRename()
        guard var entry = load.entries.first(where: { $0.citekey == oldKey }) else {
            throw StoreIOError.invalidKey("citekey（來源不存在）", oldKey)
        }

        // 1. 寫新檔（先寫後刪，中斷時頂多多一份檔案，不丟資料）
        entry.citekey = newKey
        try writeEntry(entry)
        // 2. 全庫 relations 遷移（cites/related 引用舊 citekey → 新；UUID 引用不動）
        var rewritten: [String] = []
        for var other in load.entries where other.citekey != oldKey {
            var changed = false
            if let i = other.akashic.relations.cites.firstIndex(of: oldKey) {
                other.akashic.relations.cites[i] = newKey
                changed = true
            }
            if let i = other.akashic.relations.related.firstIndex(of: oldKey) {
                other.akashic.relations.related[i] = newKey
                changed = true
            }
            if changed {
                try writeEntry(other)
                rewritten.append(other.citekey)
            }
        }
        // 3. 刪舊檔
        try FileManager.default.removeItem(at: entryURL(citekey: oldKey))
        return RenameReport(relationsRewritten: rewritten.sorted())
    }

    private func store_loadForRename() throws -> LibraryLoad {
        try load()
    }
}
