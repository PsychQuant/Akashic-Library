import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicSQLite

public struct IndexStats: Equatable {
    public var entries: Int
    public var people: Int
    public var relations: Int

    public init(entries: Int, people: Int, relations: Int) {
        self.entries = entries
        self.people = people
        self.relations = relations
    }
}

/// `.akashic/index.sqlite` 重建器。index 是可全刪重建的衍生物——
/// canonical 永遠是 entries/ 與 people/ 的 YAML。
public struct LibraryIndex {
    /// index schema 版本（#13 verify）：加表/改欄位時遞增。
    /// 舊 binary 建的 index 撞新查詢（如 entry_libraries）會 no such table——
    /// 讀端先 isCurrent 檢查、stale 就 rebuild，不靠 mtime。
    public static let schemaVersion: Int32 = 2

    let store: LibraryStore

    public init(store: LibraryStore) {
        self.store = store
    }

    /// index 是否為當前 schema 版本（檔案不存在＝false）。
    public static func isCurrent(indexPath: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: indexPath.path) else { return false }
        let db = try SQLiteDB(path: indexPath.path, readOnly: true)
        let rows = try db.query("PRAGMA user_version")
        let version = (rows.first?["user_version"] as? Int).map(Int32.init) ?? 0
        return version == schemaVersion
    }

    /// stale（版本不符）就 rebuild；current 則 no-op。回傳是否 rebuild 過。
    @discardableResult
    public func ensureCurrent() throws -> Bool {
        if try Self.isCurrent(indexPath: store.indexURL) { return false }
        _ = try rebuild()
        return true
    }

    @discardableResult
    public func rebuild() throws -> IndexStats {
        let load = try store.load()

        // 全刪重建：舊 index 直接移除，避免 schema 演化殘留
        try FileManager.default.createDirectory(at: store.akashicDir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: store.indexURL)
        let db = try SQLiteDB(path: store.indexURL.path, readOnly: false)

        for sql in [
            """
            CREATE TABLE entries(
                uuid TEXT PRIMARY KEY, citekey TEXT UNIQUE, type TEXT, title TEXT,
                year INT, journal TEXT, status TEXT, orphaned INT)
            """,
            "CREATE TABLE authors(entry_uuid TEXT, position INT, person_key TEXT, literal TEXT)",
            "CREATE TABLE tags(entry_uuid TEXT, tag TEXT)",
            "CREATE TABLE entry_libraries(entry_uuid TEXT, library_key TEXT)",
            "CREATE TABLE relations(from_uuid TEXT, kind TEXT, target TEXT)",
            "CREATE TABLE people(key TEXT PRIMARY KEY, names TEXT)",
            "CREATE INDEX idx_authors_entry ON authors(entry_uuid)",
            "CREATE INDEX idx_authors_key ON authors(person_key)",
            "CREATE INDEX idx_tags_entry ON tags(entry_uuid)",
            "CREATE INDEX idx_entry_libraries_key ON entry_libraries(library_key)",
            "CREATE INDEX idx_relations_from ON relations(from_uuid)",
            "CREATE INDEX idx_relations_target ON relations(target)",
            "PRAGMA user_version = 2",   // = schemaVersion；同步遞增
        ] {
            try db.execute(sql)
        }

        var relationCount = 0
        try db.execute("BEGIN")
        for entry in load.entries {
            try db.execute(
                "INSERT INTO entries VALUES (?,?,?,?,?,?,?,?)",
                bind: [
                    entry.id.uuidString, entry.citekey, entry.type, entry.title,
                    entry.date.flatMap(Self.extractYear),
                    entry.fields["journaltitle"],
                    entry.akashic.status,
                    entry.provenance?.orphanedAt == nil ? 0 : 1,
                ])
            for (i, author) in entry.authors.enumerated() {
                switch author {
                case .key(let k):
                    try db.execute("INSERT INTO authors VALUES (?,?,?,NULL)",
                                   bind: [entry.id.uuidString, i, k])
                case .literal(let s):
                    try db.execute("INSERT INTO authors VALUES (?,?,NULL,?)",
                                   bind: [entry.id.uuidString, i, s])
                }
            }
            for tag in entry.akashic.tags {
                try db.execute("INSERT INTO tags VALUES (?,?)", bind: [entry.id.uuidString, tag])
            }
            for libraryKey in Set(entry.akashic.libraries) {   // 防禦性去重（上游已保證，fragile invariant 加固）
                try db.execute("INSERT INTO entry_libraries VALUES (?,?)",
                               bind: [entry.id.uuidString, libraryKey])
            }
            for cite in entry.akashic.relations.cites {
                try db.execute("INSERT INTO relations VALUES (?,'cites',?)",
                               bind: [entry.id.uuidString, cite])
                relationCount += 1
            }
            for rel in entry.akashic.relations.related {
                try db.execute("INSERT INTO relations VALUES (?,'related',?)",
                               bind: [entry.id.uuidString, rel])
                relationCount += 1
            }
        }
        for person in load.people {
            try db.execute("INSERT INTO people VALUES (?,?)",
                           bind: [person.key, person.names.joined(separator: "\n")])
        }
        try db.execute("COMMIT")

        return IndexStats(entries: load.entries.count, people: load.people.count,
                          relations: relationCount)
    }

    static func extractYear(_ date: String) -> Int? {
        guard let range = date.range(of: "[0-9]{4}", options: .regularExpression) else { return nil }
        return Int(date[range])
    }
}
