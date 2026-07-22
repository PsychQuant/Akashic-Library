import Foundation
import Observation
import AkashicCore
import AkashicStoreIO
import AkashicIndex

/// App 的中心狀態：載入/篩選/衍生層編輯/rename。
/// 寫入邊界與 MCP 相同（衍生層 + rename + orphan 裁決）；寫後 reload + reindex。
@Observable
public final class AppState {
    public let root: URL

    public private(set) var entries: [Entry] = []
    public private(set) var people: [Person] = []
    public private(set) var quarantined: [QuarantinedFile] = []

    public var searchText: String = ""
    public var filterType: String?
    public var filterTag: String?
    public var filterJournal: String?

    public init(root: URL) {
        self.root = root
    }

    var store: LibraryStore { LibraryStore(root: root) }

    // MARK: - 載入與統計

    public func load() throws {
        let loaded = try store.load()
        entries = loaded.entries
        people = loaded.people
        quarantined = loaded.quarantined
    }

    public var unresolvedLiteralCount: Int {
        entries.reduce(0) { count, entry in
            count + entry.authors.filter { if case .literal = $0 { return true } else { return false } }.count
        }
    }

    public var orphanedEntries: [Entry] {
        entries.filter { $0.provenance?.orphanedAt != nil }
    }

    public var filteredEntries: [Entry] {
        entries.filter { entry in
            if let type = filterType, entry.type != type { return false }
            if let tag = filterTag, !entry.akashic.tags.contains(tag) { return false }
            if let journal = filterJournal,
               entry.fields["journaltitle"]?.lowercased() != journal.lowercased() { return false }
            let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
            if !query.isEmpty {
                let haystack = ([entry.citekey, entry.title]
                    + entry.authors.map(\.displayName)).joined(separator: "\n").lowercased()
                if !haystack.contains(query) { return false }
            }
            return true
        }
    }

    // MARK: - 衍生層編輯（寫檔 + reload + reindex）

    public func setStatus(citekey: String, status: String?) throws {
        try mutate(citekey) { $0.akashic.status = status }
    }

    public func addTag(citekey: String, tag: String) throws {
        try mutate(citekey) {
            if !$0.akashic.tags.contains(tag) { $0.akashic.tags.append(tag) }
        }
    }

    public func removeTag(citekey: String, tag: String) throws {
        try mutate(citekey) { $0.akashic.tags.removeAll { $0 == tag } }
    }

    public func addRelation(citekey: String, kind: RelationKind, target: String) throws {
        try mutate(citekey) {
            switch kind {
            case .cites:
                if !$0.akashic.relations.cites.contains(target) { $0.akashic.relations.cites.append(target) }
            case .related:
                if !$0.akashic.relations.related.contains(target) { $0.akashic.relations.related.append(target) }
            }
        }
    }

    public func removeRelation(citekey: String, kind: RelationKind, target: String) throws {
        try mutate(citekey) {
            switch kind {
            case .cites: $0.akashic.relations.cites.removeAll { $0 == target }
            case .related: $0.akashic.relations.related.removeAll { $0 == target }
            }
        }
    }

    public func rename(from oldKey: String, to newKey: String) throws {
        _ = try store.renameEntry(from: oldKey, to: newKey)
        try reindexAndReload()
    }

    public enum RelationKind {
        case cites, related
    }

    // MARK: - Internals

    func mutate(_ citekey: String, _ change: (inout Entry) -> Void) throws {
        guard var entry = entries.first(where: { $0.citekey == citekey }) else {
            throw StoreIOError.invalidKey("citekey（不存在）", citekey)
        }
        change(&entry)
        try store.writeEntry(entry)
        try reindexAndReload()
    }

    func reindexAndReload() throws {
        _ = try LibraryIndex(store: store).rebuild()
        try load()
    }
}
