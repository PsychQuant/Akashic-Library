import Foundation
import AkashicCore

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
        let yaml = try EntryYAML.encode(entry)
        let dest = entryURL(citekey: entry.citekey)
        try atomicWrite(yaml, to: dest)
        return dest
    }

    @discardableResult
    public func writePerson(_ person: Person) throws -> URL {
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
        return try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "yaml" && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func readUTF8(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// temp 檔寫在同一目錄 + rename 取代——中斷不留半寫檔。
    private func atomicWrite(_ content: String, to dest: URL) throws {
        let fm = FileManager.default
        let tmp = dest.deletingLastPathComponent()
            .appendingPathComponent(".\(dest.lastPathComponent).tmp-\(UUID().uuidString)")
        try content.write(to: tmp, atomically: false, encoding: .utf8)
        do {
            _ = try fm.replaceItemAt(dest, withItemAt: tmp)
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }
}
