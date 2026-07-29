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
    /// Library registry（#13 membership views）；成員關係在各 entry 的 akashic.libraries
    public var libraries: [Library]
    public var quarantined: [QuarantinedFile]

    public init(entries: [Entry] = [], people: [Person] = [],
                libraries: [Library] = [], quarantined: [QuarantinedFile] = []) {
        self.entries = entries
        self.people = people
        self.libraries = libraries
        self.quarantined = quarantined
    }
}

/// 檔案為本的 library 存取層。canonical 是 entries/ 與 people/ 的 YAML；
/// .akashic/ 是可重建衍生物。所有寫入走 atomic（temp + rename）。
public final class LibraryStore {
    public let root: URL

    public var entriesDir: URL { root.appendingPathComponent("entries") }
    public var peopleDir: URL { root.appendingPathComponent("people") }
    public var librariesDir: URL { root.appendingPathComponent("libraries") }
    public var notesDir: URL { root.appendingPathComponent("notes") }
    public var akashicDir: URL { root.appendingPathComponent(".akashic") }
    public var indexURL: URL { akashicDir.appendingPathComponent("index.sqlite") }

    public init(root: URL) {
        self.root = root
    }

    public func ensureLayout() throws {
        let fm = FileManager.default
        for dir in [root, entriesDir, peopleDir, librariesDir, notesDir, akashicDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    public func entryURL(citekey: String) -> URL {
        entriesDir.appendingPathComponent("\(citekey).yaml")
    }

    public func personURL(key: String) -> URL {
        peopleDir.appendingPathComponent("\(key).yaml")
    }

    public func libraryURL(key: String) -> URL {
        librariesDir.appendingPathComponent("\(key).yaml")
    }

    /// Library registry 寫入（#13）：metadata-only；key 走 StoreKey write-time 驗證。
    /// entry 的 membership（akashic.libraries）由 writeEntry 一併驗證。
    @discardableResult
    public func writeLibrary(_ library: Library) throws -> URL {
        guard StoreKey.isValid(library.key) else {
            throw StoreIOError.invalidKey("library key", library.key)
        }
        // pre-v1.2 store（無 libraries/）也能直接建 library——目錄缺就補
        try FileManager.default.createDirectory(at: librariesDir, withIntermediateDirectories: true)
        let yaml = try LibraryYAML.encode(library)
        let dest = libraryURL(key: library.key)
        try atomicWrite(yaml, to: dest)
        return dest
    }

    @discardableResult
    public func writeEntry(_ entry: Entry) throws -> URL {
        // write-time key 驗證：不合格式的 citekey 絕不進檔名（path traversal 防護）
        guard StoreKey.isValid(entry.citekey) else {
            throw StoreIOError.invalidKey("citekey", entry.citekey)
        }
        // membership keys（#13）同樣 write-time 驗證——不進路徑，但保 index/query 語意乾淨
        for key in entry.akashic.libraries where !StoreKey.isValid(key) {
            throw StoreIOError.invalidKey("akashic.libraries key", key)
        }
        let yaml = try EntryYAML.encode(entry)
        let dest = entryURL(citekey: entry.citekey)
        try atomicWrite(yaml, to: dest)
        return dest
    }

    /// exclusive-create 版 writeEntry：目的檔已存在（含檢查後才出現的並發寫入）
    /// 一律擲錯，絕不靜默覆蓋。rename 的目的檔寫入走這條，關掉 check-then-write
    /// 之間的 TOCTOU 覆寫視窗（moveItem 對既存目的檔是原子性拒絕）。
    @discardableResult
    public func writeEntryExclusive(_ entry: Entry) throws -> URL {
        guard StoreKey.isValid(entry.citekey) else {
            throw StoreIOError.invalidKey("citekey", entry.citekey)
        }
        let yaml = try EntryYAML.encode(entry)
        let dest = entryURL(citekey: entry.citekey)
        try atomicWrite(yaml, to: dest, mustCreate: true)
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
                let entry = try EntryYAML.decode(try readUTF8(url))
                // 語意驗證：decode 成功但 key 不合法／與檔名不符 → quarantine。
                // 畸形 citekey 一旦進入 library，之後任何 entryURL 組合（rename 刪除、
                // orphan trash）都是 path traversal 面；檔名不符則造成重複 entry 與錯位刪除。
                let stem = url.deletingPathExtension().lastPathComponent
                guard StoreKey.isValid(entry.citekey) else {
                    result.quarantined.append(QuarantinedFile(
                        file: "entries/\(url.lastPathComponent)",
                        reason: "citekey「\(entry.citekey)」不符合 \(StoreKey.pattern)"))
                    continue
                }
                guard stem == entry.citekey else {
                    result.quarantined.append(QuarantinedFile(
                        file: "entries/\(url.lastPathComponent)",
                        reason: "檔名 stem「\(stem)」與 citekey「\(entry.citekey)」不符"))
                    continue
                }
                result.entries.append(entry)
            } catch {
                result.quarantined.append(QuarantinedFile(
                    file: "entries/\(url.lastPathComponent)",
                    reason: String(describing: error)))
            }
        }
        for url in try yamlFiles(in: peopleDir) {
            do {
                let person = try PersonYAML.decode(try readUTF8(url))
                let stem = url.deletingPathExtension().lastPathComponent
                guard StoreKey.isValid(person.key) else {
                    result.quarantined.append(QuarantinedFile(
                        file: "people/\(url.lastPathComponent)",
                        reason: "person key「\(person.key)」不符合 \(StoreKey.pattern)"))
                    continue
                }
                guard stem == person.key else {
                    result.quarantined.append(QuarantinedFile(
                        file: "people/\(url.lastPathComponent)",
                        reason: "檔名 stem「\(stem)」與 person key「\(person.key)」不符"))
                    continue
                }
                result.people.append(person)
            } catch {
                result.quarantined.append(QuarantinedFile(
                    file: "people/\(url.lastPathComponent)",
                    reason: String(describing: error)))
            }
        }
        for url in try yamlFiles(in: librariesDir) {
            do {
                let library = try LibraryYAML.decode(try readUTF8(url))
                let stem = url.deletingPathExtension().lastPathComponent
                guard StoreKey.isValid(library.key) else {
                    result.quarantined.append(QuarantinedFile(
                        file: "libraries/\(url.lastPathComponent)",
                        reason: "library key「\(library.key)」不符合 \(StoreKey.pattern)"))
                    continue
                }
                guard stem == library.key else {
                    result.quarantined.append(QuarantinedFile(
                        file: "libraries/\(url.lastPathComponent)",
                        reason: "檔名 stem「\(stem)」與 library key「\(library.key)」不符"))
                    continue
                }
                result.libraries.append(library)
            } catch {
                result.quarantined.append(QuarantinedFile(
                    file: "libraries/\(url.lastPathComponent)",
                    reason: String(describing: error)))
            }
        }
        result.entries.sort { $0.citekey < $1.citekey }
        result.people.sort { $0.key < $1.key }
        result.libraries.sort { $0.key < $1.key }
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
    /// mustCreate = true 時強制走 moveItem——目的檔已存在會原子性擲錯，
    /// 不進 replaceItemAt 的覆蓋分支（exclusive-create 語意）。
    private func atomicWrite(_ content: String, to dest: URL, mustCreate: Bool = false) throws {
        let fm = FileManager.default
        let tmp = dest.deletingLastPathComponent()
            .appendingPathComponent(".\(dest.lastPathComponent).tmp-\(UUID().uuidString)")
        try content.write(to: tmp, atomically: false, encoding: .utf8)
        do {
            if !mustCreate && fm.fileExists(atPath: dest.path) {
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
        // oldKey 與 newKey 對稱驗證：oldKey 之後會進 entryURL 組刪除路徑，
        // 磁碟上若有畸形 citekey（load() 已 quarantine，此處縱深防禦）絕不可放行
        guard StoreKey.isValid(oldKey) else {
            throw StoreIOError.invalidKey("citekey", oldKey)
        }
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

        // 1. 寫新檔（先寫後刪，中斷時頂多多一份檔案，不丟資料）。
        //    exclusive-create：檢查後才出現的並發目的檔會在此擲錯，不被靜默覆蓋。
        //    自身 relations 的 self-reference 也在此一併遷移。
        entry.citekey = newKey
        entry.akashic.relations.cites =
            entry.akashic.relations.cites.map { $0 == oldKey ? newKey : $0 }
        entry.akashic.relations.related =
            entry.akashic.relations.related.map { $0 == oldKey ? newKey : $0 }
        try writeEntryExclusive(entry)
        // 2. 全庫 relations 遷移（cites/related 引用舊 citekey → 新，
        //    同一陣列的所有出現全部替換；UUID 引用不動）
        var rewritten: [String] = []
        for var other in load.entries where other.citekey != oldKey {
            let cites = other.akashic.relations.cites.map { $0 == oldKey ? newKey : $0 }
            let related = other.akashic.relations.related.map { $0 == oldKey ? newKey : $0 }
            if cites != other.akashic.relations.cites
                || related != other.akashic.relations.related {
                other.akashic.relations.cites = cites
                other.akashic.relations.related = related
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
